#!/bin/bash
# connect.sh — SSH to the OVH sandbox over Tailscale.
# Usage: ./connect.sh [ubuntu|agent]   (default: ubuntu)
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/host.conf"
SSH_USER="${1:-ubuntu}"
exec tailscale ssh "$SSH_USER@$TAILNET_HOSTNAME"
