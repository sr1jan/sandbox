#!/bin/bash
# Sandbox EC2 bootstrap — runs as root on first boot via user-data.
#
# Interpolated by Terraform with:
#   ${tailscale_auth_key}        pre-authorized single-use key
#   ${tailnet_hostname}          base tailnet hostname (no FQDN suffix)
#   ${sandbox_repo_url}          HTTPS URL for sandbox repo to clone
#   ${sandbox_repo_ref}          git ref to clone (branch/tag/sha)
#   ${deepreel_repo_urls}        JSON array of work repos → /workspace/core/
#   ${fun_repo_urls}             JSON array of personal repos → /workspace/fun/
#   ${skills_source_path}        absolute path on the VM (empty string = no symlinks)
#   ${workspace_name}            Terraform workspace name
#
# Secrets (also templated; written to /etc/devbox/locked/secrets via
# sync-secrets, NEVER echoed to the bootstrap log):
#   ${aws_access_key_id} ${aws_secret_access_key} ${aws_default_region}
#   ${gh_token_deepreel} ${gh_token_sandbox}
#   ${anthropic_api_key}
#   ${database_replica_host} ${database_replica_name}
#   ${database_replica_user} ${database_replica_password}

set -euo pipefail
exec > >(tee -a /var/log/sandbox-bootstrap.log) 2>&1

echo "=== Sandbox bootstrap start: $(date -u +%Y-%m-%dT%H:%M:%SZ) (workspace: ${workspace_name}) ==="

# --- System packages ---
echo "[bootstrap] Installing packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  git curl wget tmux neovim ripgrep fd-find fzf \
  sudo gosu less jq unzip jo netcat-openbsd \
  python3 python3-venv build-essential \
  openssh-client ca-certificates iptables iptables-persistent \
  postgresql-client \
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

# AWS CLI v2 (apt's awscli is v1, in maintenance mode). Used by the agent
# via `sudo run aws ...` for IAM-scoped reads (CloudWatch logs etc.).
if ! command -v aws &>/dev/null; then
  ARCH=$(uname -m)   # aarch64 on t4g, x86_64 on t3
  cd /tmp
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$ARCH.zip" -o awscliv2.zip
  unzip -q awscliv2.zip
  ./aws/install
  rm -rf /tmp/aws /tmp/awscliv2.zip
  cd -
fi

# GitHub CLI (gh) — used by bootstrap to clone private deepreel repos and
# at runtime by the agent (`sudo run gh repo clone deepreel/foo`).
if ! command -v gh &>/dev/null; then
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
  chmod 644 /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update
  apt-get install -y --no-install-recommends gh
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

# --- Sandbox repo (clone the configured branch — defaults to main) ---
SANDBOX_DIR=/opt/sandbox
if [ ! -d "$SANDBOX_DIR" ]; then
  git clone --branch '${sandbox_repo_ref}' --depth 1 \
    '${sandbox_repo_url}' "$SANDBOX_DIR"
fi
# /opt/sandbox is root-owned; mark it safe so any user can run git ops on
# it without "fatal: detected dubious ownership" (e.g. agent inspecting
# the source of an installed script).
git config --system --add safe.directory "$SANDBOX_DIR"

# --- Shared scripts + sudoers + patterns ---
echo "[bootstrap] Installing shared scripts and sudoers..."
install -m 755 "$SANDBOX_DIR/shared/scripts/run"          /usr/local/bin/run
install -m 755 "$SANDBOX_DIR/shared/scripts/lock-env"     /usr/local/bin/lock-env
install -m 755 "$SANDBOX_DIR/shared/scripts/unlock-env"   /usr/local/bin/unlock-env
install -m 755 "$SANDBOX_DIR/shared/scripts/sync-secrets" /usr/local/bin/sync-secrets
install -m 755 "$SANDBOX_DIR/shared/scripts/tx"           /usr/local/bin/tx
install -m 440 "$SANDBOX_DIR/shared/sudoers.d/agent"      /etc/sudoers.d/agent

# Canonical paths: shared/scripts/run reads /etc/devbox/locked/secrets and
# /etc/devbox/locked/projects/<proj>/.env*. Both dirs are root:700 so the
# agent user cannot enumerate or read anything inside.
mkdir -p /etc/devbox/locked
chmod 700 /etc/devbox /etc/devbox/locked
touch /etc/devbox/locked/secrets
chmod 600 /etc/devbox/locked/secrets

# --- Inject operator-supplied secrets via sync-secrets ---
# Heredoc body is single-quote-delimited so bash never expands $ or `…` in
# the values; sync-secrets reads each KEY=value line, single-quotes the
# value, atomically writes to /etc/devbox/locked/secrets. Empty values are
# skipped, so optional secrets (gh_token_sandbox, anthropic_api_key, etc.)
# don't pollute the file when unset. Output goes nowhere — no values touch
# /var/log/sandbox-bootstrap.log.
echo "[bootstrap] Writing secrets to /etc/devbox/locked/secrets..."
/usr/local/bin/sync-secrets >/dev/null 2>&1 <<'__SANDBOX_SECRETS_EOF__'
AWS_ACCESS_KEY_ID=${aws_access_key_id}
AWS_SECRET_ACCESS_KEY=${aws_secret_access_key}
AWS_DEFAULT_REGION=${aws_default_region}
GH_TOKEN_DEEPREEL=${gh_token_deepreel}
GH_TOKEN_SANDBOX=${gh_token_sandbox}
ANTHROPIC_API_KEY=${anthropic_api_key}
DATABASE_REPLICA_HOST=${database_replica_host}
DATABASE_REPLICA_NAME=${database_replica_name}
DATABASE_REPLICA_USER=${database_replica_user}
DATABASE_REPLICA_PASSWORD=${database_replica_password}
__SANDBOX_SECRETS_EOF__

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

# --- tmuxinator configs for agent ---
sudo -u agent mkdir -p /home/agent/.config/tmuxinator
for cfg in "$SANDBOX_DIR/shared/tmuxinator/"*.yml; do
  install -m 644 -o agent -g agent "$cfg" \
    "/home/agent/.config/tmuxinator/$(basename "$cfg")"
done

# --- Set up gh CLI auth for the agent (one-time, persists in ~/.config/gh) ---
# Reads token from the secrets file we just wrote. Subsequent `sudo run gh ...`
# calls work without env vars because gh stored creds in agent's home.
if grep -q '^export GH_TOKEN_DEEPREEL=' /etc/devbox/locked/secrets 2>/dev/null; then
  echo "[bootstrap] Configuring gh CLI auth for agent..."
  # Source secrets in a subshell so the value never lands in our env or log.
  ( set -a; . /etc/devbox/locked/secrets; set +a
    if [ -n "$${GH_TOKEN_DEEPREEL:-}" ]; then
      echo "$${GH_TOKEN_DEEPREEL}" \
        | sudo -u agent gh auth login --with-token --hostname github.com --git-protocol https >/dev/null 2>&1
    fi
  )
fi

# --- Clone work repos (deepreel) into /workspace/core/ ---
# --- Clone personal repos (fun) into /workspace/fun/ ---
# Both lists accept either "owner/name" (preferred) or full https URL.
clone_repos_into() {
  local target_root="$1"
  local repo_json="$2"
  mkdir -p "$target_root"
  chown agent:agent "$target_root"
  echo "$repo_json" | jq -r '.[]' | while read -r repo; do
    [ -z "$repo" ] && continue
    case "$repo" in
      https://github.com/*)
        ownername="$(echo "$repo" | sed -E 's|^https://github.com/||;s|\.git$||')" ;;
      *)
        ownername="$repo" ;;  # already owner/name
    esac
    repo_name="$(basename "$ownername")"
    if [ ! -d "$target_root/$repo_name" ]; then
      sudo -u agent gh repo clone "$ownername" "$target_root/$repo_name" \
        || echo "Warning: failed to clone $ownername into $target_root (token may lack access or repo doesn't exist)"
    fi
  done
}

echo "[bootstrap] Cloning work repos into /workspace/core/..."
clone_repos_into /workspace/core '${deepreel_repo_urls}'

echo "[bootstrap] Cloning personal repos into /workspace/fun/..."
clone_repos_into /workspace/fun '${fun_repo_urls}'

echo "=== Sandbox bootstrap complete: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "Connect: tailscale ssh ubuntu@${tailnet_hostname}"
