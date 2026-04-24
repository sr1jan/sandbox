#!/bin/bash
# Connect to VM sandbox from Ghostty (NOT from inside tmux).
# Attaches to remote tmux session, or starts one.
# tmux runs as root on the VM — admin + agent windows coexist.
#
# Usage: ./connect.sh [vm-name]

set -euo pipefail

VM="${1:-dev-vm}"

ssh "${VM}" -t \
  'sudo tmux attach -t dev 2>/dev/null || sudo tmuxinator start dev'
