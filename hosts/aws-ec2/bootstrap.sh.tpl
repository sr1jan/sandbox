#!/bin/bash
# Sandbox EC2 bootstrap — runs as root on first boot via user-data.
#
# Interpolated by Terraform with:
#   ${tailscale_auth_key}   pre-authorized single-use key
#   ${tailnet_hostname}     base tailnet hostname (no FQDN suffix)
#   ${deepreel_repo_urls}   JSON array of git URLs to clone into /workspace/core/
#   ${skills_source_path}   absolute path on the VM (empty string = no symlinks)
#   ${workspace_name}       Terraform workspace name (e.g., deepreel-srijan-claude)

set -euo pipefail
exec > >(tee -a /var/log/sandbox-bootstrap.log) 2>&1

echo "=== Sandbox bootstrap start: $(date -u +%Y-%m-%dT%H:%M:%SZ) (workspace: ${workspace_name}) ==="

# --- System packages ---
echo "[bootstrap] Installing packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  git curl wget tmux neovim ripgrep fd-find fzf \
  sudo gosu less jq unzip jo \
  python3 python3-venv build-essential \
  openssh-client ca-certificates iptables iptables-persistent \
  ruby-full

# Node.js 22
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

# Docker (for dp-pg / dp-redis and general container workloads)
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

# uv
if ! command -v uv &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  mv /root/.local/bin/uv /usr/local/bin/uv
  mv /root/.local/bin/uvx /usr/local/bin/uvx
fi

# tmuxinator
if ! command -v tmuxinator &>/dev/null; then
  gem install tmuxinator --no-document
fi

# --- Users ---
echo "[bootstrap] Creating users..."
if ! id agent &>/dev/null; then
  useradd -m -s /bin/bash agent
fi
usermod -aG docker agent

# admin user: whichever user you SSH in as via Tailscale. Ubuntu default
# is ubuntu — leave it alone and just ensure it's in docker + sudo groups.
usermod -aG docker ubuntu || true

# --- Tailscale ---
echo "[bootstrap] Installing and joining Tailscale..."
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
tailscale up \
  --authkey='${tailscale_auth_key}' \
  --hostname='${tailnet_hostname}' \
  --ssh

# --- Disable sshd (tailscale ssh only) ---
echo "[bootstrap] Disabling standard sshd (access via tailscale ssh only)..."
systemctl disable --now ssh || true
systemctl mask ssh || true

# --- Sandbox repo (pulled fresh; not a git clone of the user's local work) ---
SANDBOX_DIR=/opt/sandbox
if [ ! -d "$SANDBOX_DIR" ]; then
  git clone https://github.com/sr1jan/sandbox.git "$SANDBOX_DIR"
fi

# --- Shared scripts + sudoers + patterns ---
echo "[bootstrap] Installing shared scripts and sudoers..."
install -m 755 "$SANDBOX_DIR/shared/scripts/run"        /usr/local/bin/run
install -m 755 "$SANDBOX_DIR/shared/scripts/lock-env"   /usr/local/bin/lock-env
install -m 755 "$SANDBOX_DIR/shared/scripts/unlock-env" /usr/local/bin/unlock-env
install -m 440 "$SANDBOX_DIR/shared/sudoers.d/agent"    /etc/sudoers.d/agent

mkdir -p /etc/devbox/locked
chmod 700 /etc/devbox
touch /etc/devbox/secrets
chmod 600 /etc/devbox/secrets

# --- Egress allowlist at the host level (iptables) ---
echo "[bootstrap] Applying host-level iptables egress rules..."
iptables -F OUTPUT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT   # Ubuntu APT mirrors
iptables -A OUTPUT -p tcp --dport 5432 -j ACCEPT
iptables -A OUTPUT -p udp --dport 41641 -j ACCEPT
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -P OUTPUT DROP
netfilter-persistent save

# --- Agent install (Claude Code) ---
echo "[bootstrap] Installing Claude Code agent..."
SANDBOX_DIR="$SANDBOX_DIR" AGENT_HOME="/home/agent" AGENT_USER="agent" \
  SKILLS_SOURCE_PATH='${skills_source_path}' \
  bash "$SANDBOX_DIR/agents/claude-code/install.sh"

# --- tmuxinator config for agent ---
sudo -u agent mkdir -p /home/agent/.config/tmuxinator
install -m 644 -o agent -g agent \
  "$SANDBOX_DIR/shared/tmuxinator/dev.yml" \
  /home/agent/.config/tmuxinator/dev.yml

# --- Clone deepreel repos into /workspace/core/ ---
echo "[bootstrap] Cloning deepreel repos into /workspace/core/..."
mkdir -p /workspace/core
chown agent:agent /workspace/core
echo '${deepreel_repo_urls}' | jq -r '.[]' | while read -r repo; do
  [ -z "$repo" ] && continue
  repo_name="$(basename "$repo" .git)"
  if [ ! -d "/workspace/core/$repo_name" ]; then
    sudo -u agent git clone "$repo" "/workspace/core/$repo_name" || \
      echo "Warning: failed to clone $repo — likely needs GH_TOKEN in /etc/devbox/secrets first"
  fi
done

echo "=== Sandbox bootstrap complete: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "Connect: tailscale ssh admin@${tailnet_hostname}"
