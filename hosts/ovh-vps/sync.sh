#!/bin/bash
# sync.sh — reconcile a running OVH sandbox with the repo. Idempotent.
#   - git pull /opt/sandbox
#   - reinstall shared scripts, sudoers, patterns, dotfiles, tmuxinator
#   - reinstall Pi extensions/skills/patterns (agents/pi/install.sh)
#   - install any shipped keys onto agent (ssh + gpg + gh token)
#   - clone any FUN_REPO_URLS missing from /workspace/fun/
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/host.conf"

echo "[sync] Pulling latest /opt/sandbox..."
tailscale ssh "ubuntu@$TAILNET_HOSTNAME" 'cd /opt/sandbox && sudo git pull --ff-only 2>&1 | tail -3'

echo "[sync] Re-installing scripts, patterns, dotfiles, agents..."
tailscale ssh "ubuntu@$TAILNET_HOSTNAME" '
  set -e
  for s in run lock-env unlock-env sync-secrets with_creds tx hx gh; do
    sudo install -m 755 /opt/sandbox/shared/scripts/$s /usr/local/bin/$s
  done
  sudo install -m 440 -o root -g root /opt/sandbox/shared/sudoers.d/agent /etc/sudoers.d/agent
  SANDBOX_DIR=/opt/sandbox AGENT_HOME=/home/agent AGENT_USER=agent \
    bash /opt/sandbox/agents/pi/install.sh
  # Refresh the herdr↔pi state integration if herdr is installed (its
  # extension lives alongside ours in ~agent/.pi/agent/extensions/).
  if command -v herdr >/dev/null 2>&1; then
    sudo -u agent herdr integration install pi >/dev/null 2>&1 || true
  fi
  sudo -u agent mkdir -p /home/agent/.config/tmuxinator
  for cfg in /opt/sandbox/hosts/ovh-vps/tmuxinator/*.yml; do
    sudo install -m 644 -o agent -g agent "$cfg" "/home/agent/.config/tmuxinator/$(basename "$cfg")"
  done
  sudo rm -f /home/agent/.config/tmuxinator/fun.yml
  for f in .tmux.conf .tmux.conf.local; do
    sudo install -m 644 -o agent -g agent "/opt/sandbox/shared/dotfiles/tmux/$f" "/home/agent/$f"
  done
  sudo -u agent mkdir -p /home/agent/.config/nvim
  sudo -u agent cp -rT /opt/sandbox/shared/dotfiles/nvim /home/agent/.config/nvim
  sudo chown -R agent:agent /home/agent/.config/nvim
  sudo install -d -o agent -g agent -m 700 /home/agent/.ssh
  sudo install -m 600 -o agent -g agent /opt/sandbox/shared/dotfiles/ssh/config /home/agent/.ssh/config
  sudo install -m 644 -o agent -g agent /opt/sandbox/shared/dotfiles/git/gitconfig          /home/agent/.gitconfig
  sudo install -m 644 -o agent -g agent /opt/sandbox/shared/dotfiles/git/gitconfig.personal /home/agent/.gitconfig.personal
  if sudo test -f /etc/devbox/locked/keys/id_ed25519_personal; then
    sudo install -m 600 -o agent -g agent /etc/devbox/locked/keys/id_ed25519_personal     /home/agent/.ssh/id_ed25519_personal
    sudo install -m 644 -o agent -g agent /etc/devbox/locked/keys/id_ed25519_personal.pub /home/agent/.ssh/id_ed25519_personal.pub
    sudo -u agent ssh-keyscan -p 443 -t ed25519,rsa ssh.github.com 2>/dev/null \
      | sudo -u agent tee -a /home/agent/.ssh/known_hosts >/dev/null || true
  fi
  if sudo test -f /etc/devbox/locked/keys/gpg_personal.asc; then
    sudo install -d -o agent -g agent -m 700 /home/agent/.gnupg
    sudo cat /etc/devbox/locked/keys/gpg_personal.asc \
      | sudo -u agent gpg --batch --import 2>&1 \
      | grep -vE "secret key imported|already in secret keyring" || true
  fi
  sudo install -d -o agent -g agent -m 700 /home/agent/.config/gh/tokens
  if sudo test -f /etc/devbox/locked/secrets; then
    val="$(sudo grep -oP "^export GH_TOKEN_PERSONAL=\x27\K[^\x27]+" /etc/devbox/locked/secrets 2>/dev/null || true)"
    if [ -n "$val" ]; then
      printf "%s" "$val" | sudo tee /home/agent/.config/gh/tokens/personal > /dev/null
      sudo chown agent:agent /home/agent/.config/gh/tokens/personal
      sudo chmod 600 /home/agent/.config/gh/tokens/personal
    fi
  fi
'

echo "[sync] Cloning any missing personal repos..."
printf 'FUN %s\n' $FUN_REPO_URLS | tailscale ssh "ubuntu@$TAILNET_HOSTNAME" '
  while read -r _ repo; do
    [ -z "$repo" ] && continue
    repo_name="$(basename "$repo")"
    if [ ! -d "/workspace/fun/$repo_name" ]; then
      echo "  cloning $repo → /workspace/fun/$repo_name"
      sudo mkdir -p /workspace/fun && sudo chown agent:agent /workspace/fun
      sudo -u agent git clone "git@github.com-personal:$repo.git" "/workspace/fun/$repo_name" \
        || echo "  warning: failed to clone $repo"
    else
      echo "  skip $repo (already cloned)"
    fi
  done
'
echo "[sync] Sync complete."
