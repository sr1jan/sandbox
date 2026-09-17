#!/bin/bash
# Install Oh My Pi (omp) for the 'agent' user. Idempotent.
#
# Installs only sandbox harness pieces:
#   - cred-guard / redactor / tmux-tools extensions
#   - dev-environment skill
#   - shared pattern JSONs
#
# Binary layout (do NOT run `omp update` on this host):
#   /usr/local/bin/omp            → sudo run → omp-with-cursor
#   /usr/local/bin/omp-with-cursor → refresh Cursor JWT → /opt/omp/omp
#   /opt/omp/omp                  → real binary
# `omp update` resolves the PATH launcher and would overwrite the wrapper.
# This script updates only /opt/omp/omp when the installed version is older
# than the latest GitHub release.
#
# Expects:
#   - agent user already exists
#   - curl, bash, python3 available
#   - $SANDBOX_DIR env var points at the sandbox repo root
#
# Optional env:
#   - AGENT_HOME      (default: /home/agent)
#   - AGENT_USER      (default: agent)
#   - OMP_REPO        (default: can1357/oh-my-pi)
#   - OMP_FORCE_UPDATE (default: 0; set to 1 to re-download even if current)
#   - GITHUB_TOKEN / GH_TOKEN — optional, avoids GitHub API rate limits
#
# Usage (called from a host bootstrap / sync):
#   SANDBOX_DIR=/path/to/sandbox bash agents/omp/install.sh

set -euo pipefail

: "${SANDBOX_DIR:?SANDBOX_DIR must point at the sandbox repo root}"
: "${AGENT_HOME:=/home/agent}"
: "${AGENT_USER:=agent}"
: "${OMP_REPO:=can1357/oh-my-pi}"
: "${OMP_FORCE_UPDATE:=0}"

OMP_BIN="/opt/omp/omp"

echo "[omp-install] Setting up omp extensions, skills, and patterns..."

sudo -u "$AGENT_USER" mkdir -p \
  "$AGENT_HOME/.omp/agent/extensions" \
  "$AGENT_HOME/.omp/agent/skills" \
  "$AGENT_HOME/.omp/agent/patterns"

sudo cp "$SANDBOX_DIR/agents/omp/extensions/"*.ts "$AGENT_HOME/.omp/agent/extensions/"
sudo cp -r "$SANDBOX_DIR/agents/omp/skills/"* "$AGENT_HOME/.omp/agent/skills/"
sudo cp "$SANDBOX_DIR/shared/patterns/"*.json "$AGENT_HOME/.omp/agent/patterns/"
sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.omp"

# --- binary install / update (targets /opt/omp/omp only) -----------------

omp_host_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      echo "[omp-install] ERROR: unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

# True when $1 is strictly older than $2 (semver-ish; sort -V).
omp_version_lt() {
  local a="$1" b="$2"
  [ "$a" != "$b" ] && [ "$(printf '%s\n' "$a" "$b" | sort -V | head -n1)" = "$a" ]
}

omp_current_version() {
  if [ -x "$OMP_BIN" ]; then
    # `omp --version` prints e.g. "omp/18.2.0"
    "$OMP_BIN" --version 2>/dev/null | sed -n 's/^omp\///p' | head -n1
  fi
}

omp_latest_release() {
  # Prints: <tag> <version>   e.g. "v18.2.4 18.2.4"
  local auth=()
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if [ -n "$token" ]; then
    auth=(-H "Authorization: Bearer ${token}")
  fi
  curl -fsSL "${auth[@]}" \
    "https://api.github.com/repos/${OMP_REPO}/releases/latest" \
    | python3 -c 'import sys, json
d = json.load(sys.stdin)
tag = d["tag_name"]
print(tag, tag.lstrip("v"))'
}

omp_download_binary() {
  local tag="$1"
  local version="$2"
  local arch asset url tmp
  arch="$(omp_host_arch)"
  asset="omp-linux-${arch}"
  url="https://github.com/${OMP_REPO}/releases/download/${tag}/${asset}"
  tmp="${OMP_BIN}.new.$$"

  echo "[omp-install] Downloading ${asset} (${version}) → ${OMP_BIN}"
  sudo mkdir -p /opt/omp
  # shellcheck disable=SC2064
  trap "sudo rm -f '$tmp'" EXIT
  sudo curl -fsSL -o "$tmp" "$url"
  sudo chmod 755 "$tmp"
  if ! "$tmp" --version >/dev/null 2>&1; then
    echo "[omp-install] ERROR: downloaded binary failed --version" >&2
    exit 1
  fi
  sudo mv "$tmp" "$OMP_BIN"
  trap - EXIT
  sudo chmod 755 "$OMP_BIN"
}

echo "[omp-install] Checking omp binary at ${OMP_BIN}..."
sudo mkdir -p /opt/omp

# Old install.sh could `mv $(command -v omp)` onto /opt/omp/omp, which
# replaces the real binary with the PATH wrapper and creates a launch loop.
# Detect that before calling --version (a contaminated path can recurse).
omp_is_elf() {
  [ -x "$1" ] && file -b "$1" 2>/dev/null | grep -q 'ELF'
}

read -r latest_tag latest_version < <(omp_latest_release)
[ -n "${latest_tag:-}" ] && [ -n "${latest_version:-}" ] || {
  echo "[omp-install] ERROR: could not resolve latest release for ${OMP_REPO}" >&2
  exit 1
}

current=""
if omp_is_elf "$OMP_BIN"; then
  current="$(omp_current_version || true)"
fi

if [ ! -x "$OMP_BIN" ]; then
  echo "[omp-install] No binary at ${OMP_BIN}; installing ${latest_version}"
  omp_download_binary "$latest_tag" "$latest_version"
elif ! omp_is_elf "$OMP_BIN"; then
  echo "[omp-install] ${OMP_BIN} is not an ELF binary (wrapper contamination); reinstalling ${latest_version}"
  omp_download_binary "$latest_tag" "$latest_version"
elif [ "$OMP_FORCE_UPDATE" = "1" ]; then
  echo "[omp-install] OMP_FORCE_UPDATE=1; reinstalling ${latest_version} (was ${current:-unknown})"
  omp_download_binary "$latest_tag" "$latest_version"
elif [ -z "$current" ]; then
  echo "[omp-install] Could not read current version; reinstalling ${latest_version}"
  omp_download_binary "$latest_tag" "$latest_version"
elif omp_version_lt "$current" "$latest_version"; then
  echo "[omp-install] Updating ${current} → ${latest_version}"
  omp_download_binary "$latest_tag" "$latest_version"
else
  echo "[omp-install] Already current (${current}); leaving ${OMP_BIN} in place"
fi

[ -x "$OMP_BIN" ] || {
  echo "[omp-install] ERROR: ${OMP_BIN} missing after install/update" >&2
  exit 1
}

# Drop any leftover agent-local shadow so `omp` resolves to the wrapper.
# Never leave a real binary on the agent's PATH — `omp update` / installers
# would otherwise race the /usr/local/bin/omp sudo-run wrapper.
sudo rm -f "$AGENT_HOME/.local/bin/omp"

# Install `omp` wrapper on PATH. Wraps via `sudo run` so provider API keys
# are sourced from /etc/devbox/locked/secrets at invocation time — never
# persisted in the agent's env or .bashrc. shared/sudoers.d/agent env_keep
# must preserve HERDR_* across that sudo so herdr-agent-state can report
# the pane (Agents sidebar).
#
# Built-in cursor provider: CURSOR_ACCESS_TOKEN (session JWT).
# Dashboard User API Key (crsr_…) needs exchange into ACCESS_TOKEN first;
# CURSOR_API_KEY alone is not enough for omp's built-in cursor client.
# refresh-cursor-token re-mints the 1h JWT from CURSOR_API_KEY on each
# omp start; cursor-token-refresh.ts re-exchanges during a long session.
sudo install -m 755 "$SANDBOX_DIR/shared/scripts/refresh-cursor-token" /usr/local/bin/refresh-cursor-token
sudo install -m 755 "$SANDBOX_DIR/shared/scripts/omp-with-cursor" /usr/local/bin/omp-with-cursor
sudo tee /usr/local/bin/omp >/dev/null <<'EOF'
#!/bin/bash
exec sudo /usr/local/bin/run /usr/local/bin/omp-with-cursor "$@"
EOF
sudo chmod 755 /usr/local/bin/omp
sudo rm -f /etc/cron.d/refresh-cursor-token

# PATH addition for /home/agent/.local/bin (user-installed bins).
if ! sudo -u "$AGENT_USER" grep -q "/home/agent/.local/bin" "$AGENT_HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="/home/agent/.local/bin:$PATH"' | sudo tee -a "$AGENT_HOME/.bashrc" >/dev/null
  sudo chown "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.bashrc"
fi

echo "[omp-install] Done. Binary: $("$OMP_BIN" --version 2>/dev/null || echo unknown)"
echo "[omp-install] Provider keys live in /etc/devbox/locked/secrets (sudo sync-secrets)."
echo "[omp-install] Sandbox extensions: cred-guard, redactor, tmux-tools."
echo "[omp-install] For Cursor models: put CURSOR_API_KEY in locked secrets;"
echo "[omp-install] refresh-cursor-token mints CURSOR_ACCESS_TOKEN (1h JWT) on omp start and mid-session."
echo "[omp-install] Do not run \`omp update\` here — it would replace /usr/local/bin/omp (the wrapper)."
