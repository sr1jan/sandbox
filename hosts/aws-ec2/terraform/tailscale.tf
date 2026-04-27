resource "tailscale_tailnet_key" "sandbox" {
  # Single-use provisioning key consumed by the EC2 user-data on first boot.
  reusable = false

  # Node persists across reboots (NOT ephemeral — we want the VM to stay
  # in the tailnet after it reboots, even though the key was single-use).
  ephemeral = false

  # Authorized automatically on creation; no admin approval needed to join.
  preauthorized = true

  # Key itself expires after 1h. After that the VM is already in the tailnet
  # and doesn't need it. If the bootstrap fails to consume it in time, we
  # terraform apply to get a fresh key.
  expiry = 3600

  # Tailscale API caps description at 50 chars.
  description = "Sandbox provisioning ${terraform.workspace}"

  # Tag must be pre-created in the tailnet ACL (tailnet admin console).
  tags = [var.tailscale_tag]
}

# ---- Tailscale device cleanup on EC2 destroy ----
#
# When the EC2 is replaced (terraform apply with user_data change), the old
# node's record persists in the tailnet — Tailscale doesn't auto-delete on
# disconnect for non-ephemeral nodes. The replacement EC2 then registers
# under the same hostname → Tailscale appends "-1" / "-2" / ... to
# disambiguate, which breaks `tailscale ssh ubuntu@<host>` for the
# original hostname.
#
# This null_resource ties its lifecycle to aws_instance.sandbox.id. When
# the EC2 is replaced, terraform destroys this null_resource first (before
# destroying the EC2), firing the destroy provisioner. The provisioner
# mints an OAuth-scoped Tailscale API token and deletes any device whose
# hostname starts with the workspace's tailnet_hostname — clearing both
# the current node and any orphaned previous nodes (-1/-2 suffixed).
#
# REQUIREMENT: the Tailscale OAuth client must have the `devices` (write)
# scope. Add it in Admin Console → Settings → OAuth clients → Edit. If the
# scope is missing, the provisioner exits 0 (doesn't block destroy) and
# logs a warning so you can manually clean the device from admin → Machines.
resource "null_resource" "tailscale_device_cleanup" {
  triggers = {
    instance_id      = aws_instance.sandbox.id
    tailnet_hostname = local.tailnet_hostname
    oauth_client_id  = var.tailscale_oauth_client_id
    oauth_secret     = var.tailscale_oauth_client_secret
  }

  provisioner "local-exec" {
    when = destroy
    environment = {
      TS_OAUTH_CLIENT_ID     = self.triggers.oauth_client_id
      TS_OAUTH_CLIENT_SECRET = self.triggers.oauth_secret
      TS_HOSTNAME_BASE       = self.triggers.tailnet_hostname
    }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -uo pipefail
      TOKEN_RESP=$(curl -fsS -u "$TS_OAUTH_CLIENT_ID:$TS_OAUTH_CLIENT_SECRET" \
        -X POST "https://api.tailscale.com/api/v2/oauth/token" \
        -d "grant_type=client_credentials" 2>/dev/null) || {
        echo "[tailscale-cleanup] Failed to mint OAuth token. Manual cleanup needed in admin console." >&2
        exit 0
      }
      TOKEN=$(echo "$TOKEN_RESP" | jq -r .access_token)
      if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo "[tailscale-cleanup] OAuth token empty (does the client have devices:write scope?). Manual cleanup needed." >&2
        exit 0
      fi
      DEVICES=$(curl -fsS -H "Authorization: Bearer $TOKEN" \
        "https://api.tailscale.com/api/v2/tailnet/-/devices" 2>/dev/null) || {
        echo "[tailscale-cleanup] Failed to list devices. Manual cleanup needed." >&2
        exit 0
      }
      MATCHED=$(echo "$DEVICES" | jq -r --arg base "$TS_HOSTNAME_BASE" \
        '.devices[] | select(.hostname | startswith($base)) | .id')
      if [ -z "$MATCHED" ]; then
        echo "[tailscale-cleanup] No devices matching '$TS_HOSTNAME_BASE*' to clean up."
        exit 0
      fi
      echo "$MATCHED" | while read -r DEVICE_ID; do
        [ -z "$DEVICE_ID" ] && continue
        echo "[tailscale-cleanup] Deleting device $DEVICE_ID (hostname starts with '$TS_HOSTNAME_BASE')"
        curl -fsS -X DELETE -H "Authorization: Bearer $TOKEN" \
          "https://api.tailscale.com/api/v2/device/$DEVICE_ID" 2>/dev/null \
          || echo "[tailscale-cleanup] Warning: failed to delete $DEVICE_ID (already removed or 403)" >&2
      done
    EOT
  }
}
