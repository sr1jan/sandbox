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

  description = "Sandbox VM provisioning key — workspace ${terraform.workspace}"

  # Tag must be pre-created in the tailnet ACL (tailnet admin console).
  tags = [var.tailscale_tag]
}
