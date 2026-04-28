#!/bin/bash
# rebuild.sh — full instance replacement in one command.
#
# Wraps the multi-step flow so a planned VM rebuild doesn't require
# remembering the order:
#   1. terraform apply    (interactive — terraform prompts before destroy)
#   2. wait for bootstrap to finish on the new instance
#   3. sync-ssh-keys.sh   (re-ship the SSH+GPG keypairs to the new disk)
#   4. power.sh sync      (install keys onto agent + retry any failed clones)
#   5. smoke-test         (verify SSH auth to both GitHub identities)
#
# What this does NOT do (run manually if needed):
#   - sync-project-env.sh — per-project .env files. These vary per
#     workspace, no manifest yet to drive auto-shipping.
#
# Usage:
#   ./rebuild.sh                       # uses currently-selected tf workspace
#   ./rebuild.sh --workspace my-ws     # selects workspace before applying

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

WS_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WS_OVERRIDE="$2"; shift 2;;
    --help|-h)
      sed -nE 's/^# ?//; 1,/^$/p' "$0" | head -n 25
      exit 0;;
    *) echo "Unknown flag: $1" >&2; exit 1;;
  esac
done

if [ -n "$WS_OVERRIDE" ]; then
  ( cd "$TF_DIR" && terraform workspace select "$WS_OVERRIDE" >/dev/null )
fi

WS="$(cd "$TF_DIR" && terraform workspace show)"
TFVARS="../../../workspaces/$WS.tfvars"

if ! [ -f "$TF_DIR/$TFVARS" ]; then
  echo "[rebuild] Expected $TF_DIR/$TFVARS but it doesn't exist." >&2
  echo "[rebuild] Either pass --workspace or create the tfvars file." >&2
  exit 1
fi

echo "[rebuild] Workspace: $WS"
echo "[rebuild] Tfvars: $TFVARS"

# 1. terraform apply — interactive; user confirms the destroy/replace.
echo
echo "[rebuild] === Step 1/4: terraform apply ==="
( cd "$TF_DIR" && terraform apply -var-file="$TFVARS" )

HOSTNAME="$(cd "$TF_DIR" && terraform output -raw tailnet_hostname)"
echo "[rebuild] New instance hostname: $HOSTNAME"

# 2. Wait for bootstrap to finish (looks for the marker echoed at the end
#    of bootstrap.sh.tpl). tailscale ssh fails until the new instance has
#    joined the tailnet, so the loop also retries connectivity.
echo
echo "[rebuild] === Step 2/4: waiting for bootstrap to complete (~3-5 min) ==="
deadline=$(($(date +%s) + 900))   # 15-minute cap
while true; do
  if tailscale ssh "ubuntu@$HOSTNAME" \
       'sudo grep -q "Sandbox bootstrap complete" /var/log/sandbox-bootstrap.log 2>/dev/null' \
       2>/dev/null; then
    echo
    echo "[rebuild] Bootstrap complete."
    break
  fi
  if [ "$(date +%s)" -gt "$deadline" ]; then
    echo
    echo "[rebuild] Timeout. Inspect logs:" >&2
    echo "  tailscale ssh ubuntu@$HOSTNAME 'sudo tail -50 /var/log/sandbox-bootstrap.log'" >&2
    exit 1
  fi
  printf '.'
  sleep 10
done

# 3. Ship SSH/GPG keys to the new /etc/devbox/locked/keys/.
echo
echo "[rebuild] === Step 3/4: sync-ssh-keys.sh ==="
"$SCRIPT_DIR/sync-ssh-keys.sh"

# 4. Reconcile — installs keys onto agent, drops dotfiles, and clones
#    any repos that bootstrap couldn't (because keys hadn't arrived yet).
echo
echo "[rebuild] === Step 4/4: power.sh sync ==="
"$SCRIPT_DIR/power.sh" sync

# Smoke-test both identities.
echo
echo "[rebuild] === Smoke test ==="
tailscale ssh "ubuntu@$HOSTNAME" '
  set -e
  for alias in github.com-personal github.com-deepreel; do
    if sudo -u agent ssh -T "git@$alias" 2>&1 | grep -qF "successfully authenticated"; then
      echo "  [OK]  $alias"
    else
      echo "  [FAIL] $alias" >&2
      exit 1
    fi
  done
'

echo
echo "[rebuild] Done. Manual follow-ups (if applicable):"
echo "  - ./sync-project-env.sh <local-dir> <vm-target>   # per-project .env files"
echo "  - sudo sync-secrets on the box for non-tfvars secrets"
