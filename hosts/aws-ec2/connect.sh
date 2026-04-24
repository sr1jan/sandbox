#!/bin/bash
# Convenience wrapper: tailscale ssh into the sandbox VM.
#
# Usage:
#   ./connect.sh                      # SSH as admin (ubuntu) to the default workspace's VM
#   ./connect.sh --user agent         # SSH as agent
#   ./connect.sh --workspace <name>   # SSH to a specific workspace's VM
#
# Prereqs: Tailscale is running on your Mac and authenticated to the same
# tailnet as the sandbox VM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

USER="ubuntu"
WORKSPACE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER="$2"; shift 2;;
    --workspace) WORKSPACE="$2"; shift 2;;
    --help|-h)
      echo "Usage: $0 [--user ubuntu|agent] [--workspace <name>]"
      exit 0;;
    *) echo "Unknown flag: $1"; exit 1;;
  esac
done

# Select workspace if one was given, else use the currently-selected one.
if [ -n "$WORKSPACE" ]; then
  ( cd "$TF_DIR" && terraform workspace select "$WORKSPACE" >/dev/null )
fi

HOSTNAME="$(cd "$TF_DIR" && terraform output -raw tailnet_hostname 2>/dev/null || true)"
if [ -z "$HOSTNAME" ]; then
  echo "Error: could not resolve tailnet_hostname from terraform output." >&2
  echo "Make sure you've run 'terraform apply' in $TF_DIR for the selected workspace." >&2
  exit 1
fi

exec tailscale ssh "${USER}@${HOSTNAME}"
