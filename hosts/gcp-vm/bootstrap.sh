#!/bin/bash
# One-time VM bootstrap. Run as your user (with sudo access).
# Sets up: agent user, dev tools, pi from source, extensions, tmuxinator.
#
# Usage: ssh dev-vm 'bash -s' < bootstrap.sh

set -euo pipefail

echo "=== Devbox VM Bootstrap ==="

# --- System packages ---
echo "[1/7] Installing packages..."
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
echo "[2/7] Creating agent user..."
if ! id agent &>/dev/null; then
  sudo useradd -m -s /bin/bash agent
fi

# --- Shared scripts ---
echo "[3/7] Installing scripts..."
SANDBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"

sudo cp "$SANDBOX_DIR/shared/scripts/run" /usr/local/bin/run
sudo cp "$SANDBOX_DIR/shared/scripts/lock-env" /usr/local/bin/lock-env
sudo cp "$SANDBOX_DIR/shared/scripts/unlock-env" /usr/local/bin/unlock-env
sudo chmod 755 /usr/local/bin/run /usr/local/bin/lock-env /usr/local/bin/unlock-env

sudo cp "$SANDBOX_DIR/shared/sudoers.d/agent" /etc/sudoers.d/agent
sudo chmod 440 /etc/sudoers.d/agent

# --- Secrets directory ---
echo "[4/7] Setting up secrets..."
sudo mkdir -p /etc/devbox
sudo chown root:root /etc/devbox
sudo chmod 700 /etc/devbox

if [ ! -f /etc/devbox/secrets ]; then
  sudo cp "$SANDBOX_DIR/hosts/docker-mac/secrets.example" /etc/devbox/secrets
  sudo chmod 600 /etc/devbox/secrets
  echo "  → Edit /etc/devbox/secrets with your CLI credentials"
fi

# --- Pi extensions and skills ---
echo "[5/7] Installing Pi extensions and skills..."
sudo -u agent mkdir -p /home/agent/.pi/agent/extensions /home/agent/.pi/agent/skills
sudo cp "$SANDBOX_DIR/shared/extensions/"*.ts /home/agent/.pi/agent/extensions/
sudo cp -r "$SANDBOX_DIR/shared/skills/"* /home/agent/.pi/agent/skills/
sudo chown -R agent:agent /home/agent/.pi

# --- Editor and tmux configs for agent ---
echo "[6/9] Setting up nvim and tmux configs for agent..."

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

# --- Pi from source ---
echo "[7/9] Setting up Pi from source..."
PROJECTS_DIR="$HOME/projects"
mkdir -p "$PROJECTS_DIR"

if [ ! -d "$PROJECTS_DIR/pi-mono" ]; then
  git clone https://github.com/badlogic/pi-mono.git "$PROJECTS_DIR/pi-mono"
fi

cd "$PROJECTS_DIR/pi-mono"
npm install
npm run build

# Pi alias for agent user
PI_BIN="$PROJECTS_DIR/pi-mono/packages/coding-agent/dist/cli/index.js"
sudo -u agent bash -c "echo 'alias pi=\"node $PI_BIN\"' >> /home/agent/.bashrc"
sudo -u agent bash -c "echo 'export PATH=\"/home/agent/.local/bin:\$PATH\"' >> /home/agent/.bashrc"

# --- tmuxinator config (for agent user) ---
echo "[8/9] Installing tmuxinator config..."
sudo -u agent mkdir -p /home/agent/.config/tmuxinator
sudo cp "$SANDBOX_DIR/shared/tmuxinator/dev.yml" /home/agent/.config/tmuxinator/dev.yml
sudo chown agent:agent /home/agent/.config/tmuxinator/dev.yml
echo "  → Installed dev.yml tmuxinator config for agent"

# --- ANTHROPIC_API_KEY for agent ---
echo "[9/9] Configuring agent environment..."
if ! sudo -u agent grep -q ANTHROPIC_API_KEY /home/agent/.bashrc 2>/dev/null; then
  echo ""
  echo -n "ANTHROPIC_API_KEY (will be stored in agent's .bashrc): "
  read -rs API_KEY
  echo ""
  sudo -u agent bash -c "echo 'export ANTHROPIC_API_KEY=\"$API_KEY\"' >> /home/agent/.bashrc"
fi

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Connect from your Mac:"
echo "  ./vm/connect.sh            # attach to agent tmux session"
echo "  ./vm/connect.sh admin      # your shell for credential management"
echo ""
echo "Inside the VM:"
echo "  sudo vi /etc/devbox/secrets     # edit CLI credentials"
echo "  cd ~/projects/<proj> && sudo lock-env  # lock .env files"
