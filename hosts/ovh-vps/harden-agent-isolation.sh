#!/bin/bash
# One-shot: install hardened agent sudoers + sandbox-only tmuxinator layout.
# Run on the box as root, e.g.:
#   sudo bash /opt/sandbox/hosts/ovh-vps/harden-agent-isolation.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_SUDOERS="$ROOT/shared/sudoers.d/agent"
SRC_TMUX="$ROOT/hosts/ovh-vps/tmuxinator/dev.yml"

visudo -cf "$SRC_SUDOERS"
cp "$SRC_SUDOERS" /tmp/agent.sudoers.new
chown root:root /tmp/agent.sudoers.new
chmod 440 /tmp/agent.sudoers.new
visudo -cf /tmp/agent.sudoers.new
install -m 440 -o root -g root /tmp/agent.sudoers.new /etc/sudoers.d/agent
rm -f /tmp/agent.sudoers.new

if [ -d /opt/sandbox/shared/sudoers.d ]; then
  install -m 644 -o root -g root "$SRC_SUDOERS" /opt/sandbox/shared/sudoers.d/agent
fi
if [ -d /opt/sandbox/hosts/ovh-vps/tmuxinator ]; then
  install -m 644 -o root -g root "$SRC_TMUX" /opt/sandbox/hosts/ovh-vps/tmuxinator/dev.yml
fi

install -d -o agent -g agent -m 755 /home/agent/.config/tmuxinator
install -m 644 -o agent -g agent "$SRC_TMUX" /home/agent/.config/tmuxinator/dev.yml

echo HARDEN_OK
