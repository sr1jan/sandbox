#!/bin/bash
# One-time bootstrap for the OVH VPS host. Run ON the box as a
# sudo-capable user (OVH's default 'ubuntu'), from a clone of this
# repo at /opt/sandbox:
#
#   sudo git clone <repo-url> /opt/sandbox   # via https, first boot only
#   TS_AUTHKEY=tskey-auth-... bash /opt/sandbox/hosts/ovh-vps/bootstrap.sh
#
# Idempotent: safe to re-run. Applies the five isolation layers:
#   1. /etc/devbox/locked root:700/600   (OS perms)
#   2. sudoers: agent may only `sudo run` (shared/sudoers.d/agent)
#   3. cred-guard patterns (Pi extension / Claude Code hook)
#   4. redactor patterns  (Pi extension / Claude Code hook)
#   5. iptables egress allowlist + Tailscale-only ingress
#
# Flags:
#   --agent pi|claude-code   (repeatable; default: pi)

set -euo pipefail

AGENTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENTS+=("$2"); shift 2;;
    --help|-h) echo "Usage: TS_AUTHKEY=... $0 [--agent pi|claude-code]..."; exit 0;;
    *) echo "Unknown flag: $1" >&2; exit 1;;
  esac
done
[ ${#AGENTS[@]} -gt 0 ] || AGENTS=(pi)

SANDBOX_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=host.conf
source "$SANDBOX_DIR/hosts/ovh-vps/host.conf"

echo "=== OVH VPS Bootstrap (agents: ${AGENTS[*]}) ==="

# --- [1/8] System packages ---
echo "[1/8] Installing packages..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  git curl wget tmux neovim ripgrep fd-find fzf \
  sudo gosu less jq unzip \
  python3 python3-venv build-essential \
  openssh-client ca-certificates \
  iptables iptables-persistent \
  ruby bats shellcheck

if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
fi
if ! command -v uv &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  sudo mv "$HOME/.local/bin/uv" /usr/local/bin/uv
  sudo mv "$HOME/.local/bin/uvx" /usr/local/bin/uvx
fi
if ! command -v tmuxinator &>/dev/null; then
  sudo gem install tmuxinator
fi

# --- [2/8] Tailscale (the only ingress) ---
echo "[2/8] Joining Tailscale..."
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if ! tailscale status &>/dev/null; then
  : "${TS_AUTHKEY:?TS_AUTHKEY required for first bootstrap}"
  sudo tailscale up --ssh --authkey "$TS_AUTHKEY" --hostname "$TAILNET_HOSTNAME"
fi
tailscale status >/dev/null || { echo "Tailscale not healthy; aborting before firewall lockdown" >&2; exit 1; }

# --- Swap (4G) — protects small-RAM tiers from OOM during builds ---
if [ ! -f /swapfile ]; then
  echo "[swap] Creating 4G swapfile..."
  sudo fallocate -l 4G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

# --- [3/8] Agent user + workspace ---
echo "[3/8] Creating agent user and /workspace/fun..."
if ! id agent &>/dev/null; then
  sudo useradd -m -s /bin/bash agent
fi
sudo usermod -aG docker agent
sudo mkdir -p /workspace/fun
sudo chown agent:agent /workspace/fun

# --- [4/8] Shared scripts + sudoers ---
echo "[4/8] Installing scripts + sudoers..."
for s in run lock-env unlock-env sync-secrets with_creds tx gh; do
  sudo install -m 755 "$SANDBOX_DIR/shared/scripts/$s" "/usr/local/bin/$s"
done
sudo install -m 440 -o root -g root "$SANDBOX_DIR/shared/sudoers.d/agent" /etc/sudoers.d/agent

# --- [5/8] Locked secrets dir ---
echo "[5/8] Setting up /etc/devbox/locked..."
sudo mkdir -p /etc/devbox/locked/projects /etc/devbox/locked/keys
sudo chown -R root:root /etc/devbox
sudo chmod 700 /etc/devbox /etc/devbox/locked /etc/devbox/locked/projects /etc/devbox/locked/keys
if ! sudo test -f /etc/devbox/locked/secrets; then
  sudo cp "$SANDBOX_DIR/shared/secrets.example" /etc/devbox/locked/secrets
  sudo chmod 600 /etc/devbox/locked/secrets
  echo "  → Populate with: sudo sync-secrets  (or ship from Mac)"
fi

# --- [6/8] Dotfiles for agent ---
echo "[6/8] Installing dotfiles..."
for f in .tmux.conf .tmux.conf.local; do
  sudo install -m 644 -o agent -g agent "$SANDBOX_DIR/shared/dotfiles/tmux/$f" "/home/agent/$f"
done
sudo -u agent mkdir -p /home/agent/.config/tmuxinator /home/agent/.config/nvim
# Host-specific layouts only — shared/tmuxinator/ holds the deepreel
# `dev` (rooted at /workspace/core) and `fun` layouts, neither of which
# applies here. Remove them if an earlier bootstrap installed them.
for cfg in "$SANDBOX_DIR/hosts/ovh-vps/tmuxinator/"*.yml; do
  sudo install -m 644 -o agent -g agent "$cfg" "/home/agent/.config/tmuxinator/$(basename "$cfg")"
done
sudo rm -f /home/agent/.config/tmuxinator/fun.yml
sudo -u agent cp -rT "$SANDBOX_DIR/shared/dotfiles/nvim" /home/agent/.config/nvim
sudo chown -R agent:agent /home/agent/.config/nvim
sudo install -d -o agent -g agent -m 700 /home/agent/.ssh
sudo install -m 600 -o agent -g agent "$SANDBOX_DIR/shared/dotfiles/ssh/config" /home/agent/.ssh/config
sudo install -m 644 -o agent -g agent "$SANDBOX_DIR/shared/dotfiles/git/gitconfig"          /home/agent/.gitconfig
sudo install -m 644 -o agent -g agent "$SANDBOX_DIR/shared/dotfiles/git/gitconfig.personal" /home/agent/.gitconfig.personal

# --- [7/8] Firewall: egress allowlist + Tailscale-only ingress ---
echo "[7/8] Applying iptables rules..."
# Egress: same allowlist as aws-ec2 minus 5432 (no DB in personal scope).
sudo iptables -F OUTPUT
sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT   # APT mirrors
sudo iptables -A OUTPUT -p udp --dport 41641 -j ACCEPT  # Tailscale
sudo iptables -A OUTPUT -p udp --dport 3478 -j ACCEPT   # STUN (Tailscale NAT traversal)
sudo iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT
sudo iptables -P OUTPUT DROP
# Ingress: lo, established, tailscale0 only. No public SSH (OVH has no
# cloud firewall by default — iptables is the enforcement layer).
#
# This closes the public SSH door you are most likely connected through.
# Your current session survives (ESTABLISHED), but new public SSH is gone
# — if Tailscale SSH doesn't work, OVH's KVM console is the only way
# back. So confirm it works first. Set SKIP_INGRESS_CONFIRM=1 to bypass
# the prompt, or SKIP_INGRESS=1 to leave public SSH open for now.
SKIP_INGRESS="${SKIP_INGRESS:-0}"
if [ -t 0 ] && [ "$SKIP_INGRESS" != "1" ] && [ "${SKIP_INGRESS_CONFIRM:-0}" != "1" ]; then
  echo ""
  echo "  ⚠  About to close public SSH (ingress becomes Tailscale-only)."
  echo "     From another terminal, verify this works RIGHT NOW:"
  echo "         tailscale ssh ubuntu@$TAILNET_HOSTNAME"
  echo "     Answer 'n' if it fails — you can re-run bootstrap after fixing the ACL."
  read -r -p "  Tailscale SSH verified working? [y/N] " reply
  case "$reply" in
    [yY]*) ;;
    *) SKIP_INGRESS=1 ;;
  esac
fi

if [ "$SKIP_INGRESS" != "1" ]; then
  sudo iptables -F INPUT
  sudo iptables -A INPUT -i lo -j ACCEPT
  sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  sudo iptables -A INPUT -i tailscale0 -j ACCEPT
  sudo iptables -A INPUT -p udp --dport 41641 -j ACCEPT   # Tailscale direct conns
  sudo iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
  sudo iptables -P INPUT DROP
else
  echo "  → ingress lockdown SKIPPED — public SSH is still open."
  echo "    Re-run bootstrap once Tailscale SSH works to close it."
fi
sudo netfilter-persistent save

# --- [8/8] Agents + repos ---
for agent_name in "${AGENTS[@]}"; do
  echo "[8/8] Installing agent: $agent_name"
  SANDBOX_DIR="$SANDBOX_DIR" AGENT_HOME="/home/agent" AGENT_USER="agent" \
    bash "$SANDBOX_DIR/agents/$agent_name/install.sh"
done

echo "[8/8] Cloning personal repos..."
for repo in $FUN_REPO_URLS; do
  repo_name="$(basename "$repo")"
  if [ ! -d "/workspace/fun/$repo_name" ]; then
    sudo -u agent git clone "git@github.com-personal:$repo.git" "/workspace/fun/$repo_name" \
      || echo "  warning: clone failed for $repo (keys shipped yet? run ship-keys.sh + sync.sh)"
  fi
done

echo ""
echo "=== Bootstrap complete ==="
echo "Next, from your Mac:"
echo "  ./hosts/ovh-vps/ship-keys.sh     # ship SSH+GPG keys"
echo "  ./hosts/ovh-vps/sync.sh          # install keys onto agent + retry clones"
echo "  ./hosts/ovh-vps/connect.sh       # tailscale ssh in"
