#!/bin/bash
# One-time VM bootstrap. Run as your user (with sudo access).
# Host-level setup + delegation to agents/<agent>/install.sh.
#
# Usage:
#   ./hosts/gcp-vm/bootstrap.sh                 # defaults to --agent pi
#   ./hosts/gcp-vm/bootstrap.sh --agent pi
#   ./hosts/gcp-vm/bootstrap.sh --agent claude-code

set -euo pipefail

AGENT="pi"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2;;
    --help|-h)
      echo "Usage: $0 [--agent pi|claude-code]"
      exit 0;;
    *) echo "Unknown flag: $1"; exit 1;;
  esac
done

echo "=== Devbox VM Bootstrap (agent: $AGENT) ==="

# --- System packages ---
echo "[1/6] Installing packages..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  git curl wget tmux neovim ripgrep fd-find fzf \
  sudo gosu less jq unzip \
  python3 python3-venv build-essential \
  openssh-client ca-certificates \
  ruby

# Node.js 22
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

# uv
if ! command -v uv &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  sudo mv ~/.local/bin/uv /usr/local/bin/uv
  sudo mv ~/.local/bin/uvx /usr/local/bin/uvx
fi

# tmuxinator
if ! command -v tmuxinator &>/dev/null; then
  sudo gem install tmuxinator
fi

# --- Agent user ---
echo "[2/6] Creating agent user..."
if ! id agent &>/dev/null; then
  sudo useradd -m -s /bin/bash agent
fi

# --- Shared scripts ---
echo "[3/6] Installing scripts..."
SANDBOX_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

sudo cp "$SANDBOX_DIR/shared/scripts/run" /usr/local/bin/run
sudo cp "$SANDBOX_DIR/shared/scripts/lock-env" /usr/local/bin/lock-env
sudo cp "$SANDBOX_DIR/shared/scripts/unlock-env" /usr/local/bin/unlock-env
sudo chmod 755 /usr/local/bin/run /usr/local/bin/lock-env /usr/local/bin/unlock-env

sudo cp "$SANDBOX_DIR/shared/sudoers.d/agent" /etc/sudoers.d/agent
sudo chmod 440 /etc/sudoers.d/agent

# --- Secrets directory ---
echo "[4/6] Setting up secrets..."
sudo mkdir -p /etc/devbox
sudo chown root:root /etc/devbox
sudo chmod 700 /etc/devbox

if [ ! -f /etc/devbox/secrets ]; then
  sudo cp "$SANDBOX_DIR/hosts/docker-mac/secrets.example" /etc/devbox/secrets
  sudo chmod 600 /etc/devbox/secrets
  echo "  → Edit /etc/devbox/secrets with your CLI credentials"
fi

# --- Editor and tmux configs for agent (shared across agents) ---
echo "[5/6] Setting up editor and tmux configs for agent..."

# Neovim config — copy from your user to agent
if [ -d "$HOME/.config/nvim" ]; then
  sudo -u agent mkdir -p /home/agent/.config
  sudo cp -r "$HOME/.config/nvim" /home/agent/.config/nvim
  sudo chown -R agent:agent /home/agent/.config/nvim
  echo "  → Copied nvim config"
fi

# Tmux config — gpakosz/.tmux
if [ ! -d /home/agent/.tmux ]; then
  sudo -u agent git clone https://github.com/gpakosz/.tmux.git /home/agent/.tmux
  sudo -u agent ln -sf /home/agent/.tmux/.tmux.conf /home/agent/.tmux.conf
fi
if [ -f "$HOME/.tmux.conf.local" ]; then
  sudo cp "$HOME/.tmux.conf.local" /home/agent/.tmux.conf.local
  sudo chown agent:agent /home/agent/.tmux.conf.local
  echo "  → Copied .tmux.conf.local"
fi

# tmuxinator config
sudo -u agent mkdir -p /home/agent/.config/tmuxinator
sudo cp "$SANDBOX_DIR/shared/tmuxinator/dev.yml" /home/agent/.config/tmuxinator/dev.yml
sudo chown agent:agent /home/agent/.config/tmuxinator/dev.yml

# --- Agent install (delegated) ---
echo "[6/6] Installing agent: $AGENT"
if [ ! -x "$SANDBOX_DIR/agents/$AGENT/install.sh" ]; then
  echo "Error: agents/$AGENT/install.sh not found or not executable"
  exit 1
fi

# Prompt for ANTHROPIC_API_KEY once (Pi consumes it via env at install time;
# other agents may use /login instead). Skip if already set or if agent
# doesn't want it.
if [ "$AGENT" = "pi" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo -n "ANTHROPIC_API_KEY (for Pi; press Enter to skip): "
  read -rs API_KEY
  echo ""
  export ANTHROPIC_API_KEY="$API_KEY"
fi

SANDBOX_DIR="$SANDBOX_DIR" AGENT_HOME="/home/agent" AGENT_USER="agent" \
  ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  bash "$SANDBOX_DIR/agents/$AGENT/install.sh"

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Connect from your Mac:"
echo "  ./hosts/gcp-vm/connect.sh            # attach to agent tmux session"
echo "  ./hosts/gcp-vm/connect.sh admin      # your shell for credential management"
echo ""
echo "Inside the VM:"
echo "  sudo vi /etc/devbox/secrets     # edit CLI credentials"
echo "  cd ~/projects/<proj> && sudo lock-env  # lock .env files"
