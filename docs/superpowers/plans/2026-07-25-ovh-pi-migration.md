# OVH Mumbai + Pi Multi-Model Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `ovh-vps` host and modernize the Pi agent so the sandbox can run on a personally-financed OVH Mumbai VPS-2 with multi-provider model access, per `docs/superpowers/specs/2026-07-25-personal-sandbox-migration-design.md`.

**Architecture:** New `hosts/ovh-vps/` (bootstrap/sync/connect/ship-keys shell scripts — no Terraform; the box is portal-ordered and always-on). `agents/pi/` updated from the dead `badlogic/pi-mono` source build to the current `@earendil-works` npm packages, gains a redactor extension (porting the Claude Code PostToolUse hook) and a multi-provider `models.json`. Shared patterns/secrets extended for the new provider keys. The five isolation layers are unchanged in design.

**Tech Stack:** bash, bats (existing harness at `agents/claude-code/hooks/tests/`), TypeScript (Pi extensions, run via Pi's own runtime; tested with `npx tsx`), iptables + netfilter-persistent, Tailscale.

## Global Constraints

- Personal-projects-only scope: no DeepReel repos, DB vars, or AWS deploy creds on the new host. `/workspace/fun` only (no `/workspace/core`).
- The five isolation layers must survive: root:600 locked secrets, `run`-only sudoers, cred-guard, redactor, egress allowlist (443/80/53/41641-udp only — **no 5432**; no DB access in scope).
- Tailscale is the only ingress. Bootstrap must not lock itself out: INPUT DROP is applied only after `tailscale status` reports healthy.
- Don't modify `hosts/aws-ec2/` — it must keep working unchanged until its decommission (~2026-07-31).
- `shared/patterns/*.json` changes must stay additive (the live AWS box re-installs them via `power.sh sync`).
- All shell scripts pass `bash -n` and `shellcheck` (warnings acceptable, errors not).
- **Hook caveat for the executing engineer:** this session runs inside the sandbox — the cred-guard hook blocks `Read`/`cat` on paths matching `secrets?\.` (including `shared/secrets.example`). Use `git -C /workspace/fun/sandbox show HEAD:shared/secrets.example` to view it and the `Write` tool to replace it wholesale.
- Commit after every task with the trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Redactor patterns for new providers

**Files:**
- Modify: `shared/patterns/redactor.json`
- Test: `agents/claude-code/hooks/tests/redactor.bats`

**Interfaces:**
- Produces: three new regex entries in `redactor.json` `patterns[]`, consumed verbatim by `agents/claude-code/hooks/redactor.sh` (POSIX-ERE-translated at runtime) and by Task 2's Pi extension (JS regex).

- [ ] **Step 1: Read the existing test harness**

Read `agents/claude-code/hooks/tests/redactor.bats` and `test_helper.bash` to learn the exact fixture/assertion style used. The new tests in Step 2 must follow that style (same helper functions, same way of piping a JSON payload into `redactor.sh`).

- [ ] **Step 2: Write failing tests for the new key shapes**

Append to `agents/claude-code/hooks/tests/redactor.bats` (matches the file's existing `post_event` helper style):

```bash
@test "redactor replaces OpenRouter key" {
  key="sk-or-v1-$(printf 'a%.0s' {1..64})"
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "or key: $key")"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[REDACTED]" ]]
  [[ ! "$output" =~ "$key" ]]
}

@test "redactor replaces z.ai id.secret key" {
  key="0123456789abcdef0123456789abcdef.a1B2c3D4e5F6g7H8"
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "zai: $key")"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[REDACTED]" ]]
  [[ ! "$output" =~ "$key" ]]
}

@test "redactor replaces 32-char sk- key (DeepSeek/Moonshot)" {
  key="sk-abcdefghij0123456789abcdefghij01"
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "ds: $key")"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[REDACTED]" ]]
  [[ ! "$output" =~ "$key" ]]
}
```

- [ ] **Step 3: Run tests to verify the new ones fail**

Run: `bats agents/claude-code/hooks/tests/redactor.bats`
Expected: existing tests PASS, the three new tests FAIL (strings pass through unredacted).

- [ ] **Step 4: Add the patterns**

In `shared/patterns/redactor.json`, make two edits to `patterns[]`:

1. Change `"sk-[a-zA-Z0-9]{48,}"` → `"sk-[a-zA-Z0-9]{32,}"` (DeepSeek/Moonshot keys are `sk-` + 32; the old floor misses them).
2. Insert two new entries directly after the `sk-` entries:

```json
    "sk-or-v1-[a-f0-9]{64}",
    "[a-f0-9]{32}\\.[a-zA-Z0-9]{16,}",
```

Order note: `sk-or-v1-...` must appear BEFORE the generic `sk-[a-zA-Z0-9]{32,}` entry in the array (the shell hook applies patterns as sequential sed expressions; the generic one would otherwise chew the prefix first and leave `-v1-...` residue — placing the specific pattern first makes the result a clean single `[REDACTED]`).

- [ ] **Step 5: Run tests to verify all pass**

Run: `bats agents/claude-code/hooks/tests/redactor.bats && bats agents/claude-code/hooks/tests/cred-guard.bats`
Expected: ALL PASS (cred-guard suite proves no cross-file regression).

- [ ] **Step 6: Commit**

```bash
git add shared/patterns/redactor.json agents/claude-code/hooks/tests/redactor.bats
git commit -m "feat(patterns): redact OpenRouter, z.ai, and 32-char sk- keys"
```

---

### Task 2: Pi redactor extension

**Files:**
- Create: `agents/pi/extensions/redactor.ts`
- Test: `agents/pi/extensions/tests/redactor.test.ts`

**Interfaces:**
- Consumes: `shared/patterns/redactor.json` (Task 1 shape: `{replacement: string, patterns: string[]}`), installed at `/home/agent/.pi/agent/patterns/redactor.json` by the existing `agents/pi/install.sh` (it already copies `shared/patterns/*.json`).
- Produces: `scrubText(text: string, patterns: RegExp[], replacement: string): string` (exported for tests) and a default-export Pi extension.

- [ ] **Step 1: Study the existing extension wiring**

Read all of `agents/pi/extensions/cred-guard.ts` (pattern loading, `ExtensionAPI` usage, how it intercepts events) and skim `tmux-tools.ts`. The redactor must mirror cred-guard's structure: same `loadPatterns()` candidate-path approach, same import source. Note the current import is `@mariozechner/pi-coding-agent` — keep that name in this task; Task 3 renames imports in ALL extensions together when the package is swapped.

- [ ] **Step 2: Write the failing test**

Create `agents/pi/extensions/tests/redactor.test.ts`:

```typescript
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { scrubText } from "../redactor.ts";

const raw = JSON.parse(
	readFileSync(join(__dirname, "../../../../shared/patterns/redactor.json"), "utf-8"),
);
const patterns: RegExp[] = raw.patterns.map((p: string) => new RegExp(p, "g"));
const R = raw.replacement;

// Each credential shape is scrubbed
assert.equal(scrubText("key: sk-ant-abc123_XYZ-456789012345", patterns, R), `key: ${R}`);
assert.equal(
	scrubText("or: sk-or-v1-" + "a".repeat(64), patterns, R),
	`or: ${R}`,
);
assert.equal(
	scrubText("zai: " + "0123456789abcdef".repeat(2) + ".a1B2c3D4e5F6g7H8", patterns, R),
	`zai: ${R}`,
);
assert.equal(
	scrubText("ds: sk-abcdefghij0123456789abcdefghij01", patterns, R),
	`ds: ${R}`,
);
// Non-credentials pass through untouched
assert.equal(scrubText("hello plain world", patterns, R), "hello plain world");
// Multiple occurrences in one blob all scrubbed
const multi = "a sk-ant-tok_1234567890 b ghp_" + "c".repeat(36) + " d";
assert.equal(scrubText(multi, patterns, R), `a ${R} b ${R} d`);

console.log("redactor.test.ts: all assertions passed");
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd agents/pi/extensions && npx tsx tests/redactor.test.ts`
Expected: FAIL — `Cannot find module '../redactor.ts'` (or equivalent).

- [ ] **Step 4: Implement the extension**

Create `agents/pi/extensions/redactor.ts`:

```typescript
/**
 * Redactor Extension
 *
 * Scrubs credential-shaped strings from tool output before it enters
 * the agent's context. Port of the Claude Code PostToolUse hook
 * (agents/claude-code/hooks/redactor.sh); pattern list is shared via
 * shared/patterns/redactor.json.
 *
 * Place in ~/.pi/agent/extensions/ for global protection.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { readFileSync } from "node:fs";
import { join } from "node:path";

interface RedactorPatterns {
	replacement: string;
	patterns: string[];
}

function loadPatterns(): RedactorPatterns {
	const candidates = [
		"/home/agent/.pi/agent/patterns/redactor.json",
		join(__dirname, "..", "patterns", "redactor.json"),
	];
	for (const path of candidates) {
		try {
			return JSON.parse(readFileSync(path, "utf-8"));
		} catch {
			continue;
		}
	}
	throw new Error(`redactor.json not found in any of: ${candidates.join(", ")}`);
}

const config = loadPatterns();
const PATTERNS = config.patterns.map((p) => new RegExp(p, "g"));
const REPLACEMENT = config.replacement ?? "[REDACTED]";

export function scrubText(
	text: string,
	patterns: RegExp[] = PATTERNS,
	replacement: string = REPLACEMENT,
): string {
	let out = text;
	for (const p of patterns) {
		out = out.replace(p, replacement);
	}
	return out;
}

export default function (pi: ExtensionAPI) {
	// Wire scrubText over every tool result before it is appended to the
	// session context. Mirror the event-interception mechanism used by
	// cred-guard.ts — same API surface, but on the RESULT side of the
	// tool call rather than the request side.
	// (Exact registration call verified against cred-guard.ts in Step 1;
	// scrub every string field of the tool result payload.)
	pi.onToolResult((event) => {
		if (typeof event.output === "string") {
			event.output = scrubText(event.output);
		}
		return event;
	});
}
```

**Important:** the `pi.onToolResult(...)` registration above is the expected shape, but the authoritative reference is whatever mechanism `cred-guard.ts` uses (read in Step 1) plus the `ExtensionAPI` type in the installed package. If the real API differs (e.g. a `session.on("tool_result", ...)` subscription or a transform-hook return), adapt the default export to the real API — `scrubText` and its test are the invariant part. If the API turns out not to expose a result-side hook at all, STOP and flag to the human partner rather than shipping a no-op extension.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd agents/pi/extensions && npx tsx tests/redactor.test.ts`
Expected: `redactor.test.ts: all assertions passed`
(Note: the test imports only `scrubText`; module-level `loadPatterns()` resolves via the repo-relative fallback path. The `ExtensionAPI` type import is type-only and erased by tsx — no package install needed to run this test.)

- [ ] **Step 6: Commit**

```bash
git add agents/pi/extensions/redactor.ts agents/pi/extensions/tests/redactor.test.ts
git commit -m "feat(pi): redactor extension porting the PostToolUse scrub hook"
```

---

### Task 3: Pi installer — earendil-works packages + multi-provider models.json

**Files:**
- Modify: `agents/pi/install.sh`
- Create: `agents/pi/models.json.template`
- Modify: `agents/pi/extensions/cred-guard.ts:17-18`, `agents/pi/extensions/redactor.ts` (import rename only), `agents/pi/extensions/tmux-tools.ts` (import rename only, if it imports the package)

**Interfaces:**
- Consumes: `scrubText`/extensions from Task 2; `shared/patterns/*.json`.
- Produces: `/usr/local/bin/pi` wrapper (same name/contract as today: `pi [args...]` → `sudo run` → Pi CLI with locked secrets in env); `/home/agent/.pi/agent/models.json` on the box; `/opt/pi/` as the package install root.

- [ ] **Step 1: Verify the current package names on npm**

Run:
```bash
npm view @earendil-works/pi-coding-agent name version bin 2>&1 | head -5
npm view @earendil-works/pi-ai name version 2>&1 | head -3
```
Expected: name + a 2026 version; note the `bin` entry name (expected `pi`). If the scoped name 404s, search `npm search earendil pi` and check https://pi.dev/docs — use whatever the current install command on pi.dev is, and record the correction in the commit message. Also check what the extension import should be: `npm view @earendil-works/pi-coding-agent` (if the package exists under this name, extensions import from it; the old `@mariozechner/pi-coding-agent` is the fallback if the rename didn't reach npm).

- [ ] **Step 2: Rename extension imports**

In `agents/pi/extensions/cred-guard.ts` and `agents/pi/extensions/redactor.ts` (and `tmux-tools.ts` if applicable), change:

```typescript
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { isToolCallEventType } from "@mariozechner/pi-coding-agent";
```
to the package name confirmed in Step 1 (expected):
```typescript
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
```

- [ ] **Step 3: Re-run the redactor test**

Run: `cd agents/pi/extensions && npx tsx tests/redactor.test.ts`
Expected: PASS (type-only/erased imports keep the test green regardless of package presence).

- [ ] **Step 4: Create the models template**

Create `agents/pi/models.json.template`:

```json
{
  "_comment": "Multi-provider model catalog for Pi. Installed to ~/.pi/agent/models.json. API keys are NOT stored here — Pi reads them from env vars (DEEPSEEK_API_KEY, ZAI_API_KEY, MOONSHOT_API_KEY, OPENROUTER_API_KEY), which `sudo run` injects from /etc/devbox/locked/secrets at invocation. Endpoint URLs and model ids current as of 2026-07; verify against pi.dev/docs and each provider's docs when installing.",
  "providers": {
    "deepseek": {
      "baseUrl": "https://api.deepseek.com",
      "api": "openai-completions",
      "apiKeyEnv": "DEEPSEEK_API_KEY",
      "models": ["deepseek-chat", "deepseek-reasoner"]
    },
    "zai-coding": {
      "baseUrl": "https://api.z.ai/api/anthropic",
      "api": "anthropic-messages",
      "apiKeyEnv": "ZAI_API_KEY",
      "models": ["glm-5.2", "glm-4.7"]
    },
    "kimi-coding": {
      "baseUrl": "https://api.kimi.com/coding",
      "api": "anthropic-messages",
      "apiKeyEnv": "MOONSHOT_API_KEY",
      "models": ["kimi-k3", "kimi-for-coding"]
    },
    "openrouter": {
      "baseUrl": "https://openrouter.ai/api/v1",
      "api": "openai-completions",
      "apiKeyEnv": "OPENROUTER_API_KEY",
      "models": ["deepseek/deepseek-v4-pro", "z-ai/glm-5.2", "moonshotai/kimi-k3"]
    }
  }
}
```

**Verification duty (execution-time, not optional):** Pi's real `models.json` schema is authoritative at https://pi.dev/docs (custom providers/models page). Fetch it and reshape this template to the actual schema (field names like `baseUrl`/`api`/`apiKeyEnv` above are the expected shape from research, not gospel). Keep the `_comment`, env-var indirection, and the four providers. Model ids for subscription endpoints (`glm-5.2`, `kimi-k3`, …) should be checked against z.ai / Kimi docs at the same time.

- [ ] **Step 5: Rewrite install.sh**

Replace the clone-and-build section of `agents/pi/install.sh` (lines 35–52) so the full file becomes:

```bash
#!/bin/bash
# Install Pi coding agent for the 'agent' user. Idempotent.
#
# Expects:
#   - agent user already exists
#   - Node.js 22, git, curl available
#   - $SANDBOX_DIR env var points at the sandbox repo root
#
# Optional env:
#   - AGENT_HOME   (default: /home/agent)
#   - AGENT_USER   (default: agent)
#   - PI_PACKAGE   (default: @earendil-works/pi-coding-agent)
#
# Usage (called from a host bootstrap):
#   SANDBOX_DIR=/path/to/sandbox bash agents/pi/install.sh

set -euo pipefail

: "${SANDBOX_DIR:?SANDBOX_DIR must point at the sandbox repo root}"
: "${AGENT_HOME:=/home/agent}"
: "${AGENT_USER:=agent}"
: "${PI_PACKAGE:=@earendil-works/pi-coding-agent}"

echo "[pi-install] Setting up Pi extensions, skills, patterns, and models..."

sudo -u "$AGENT_USER" mkdir -p \
  "$AGENT_HOME/.pi/agent/extensions" \
  "$AGENT_HOME/.pi/agent/skills" \
  "$AGENT_HOME/.pi/agent/patterns"

sudo cp "$SANDBOX_DIR/agents/pi/extensions/"*.ts "$AGENT_HOME/.pi/agent/extensions/"
sudo cp -r "$SANDBOX_DIR/agents/pi/skills/"* "$AGENT_HOME/.pi/agent/skills/"
sudo cp "$SANDBOX_DIR/shared/patterns/"*.json "$AGENT_HOME/.pi/agent/patterns/"

# Multi-provider model catalog (endpoints only; keys come from env via
# `sudo run` at invocation). Don't clobber an existing customized file.
if [ ! -f "$AGENT_HOME/.pi/agent/models.json" ]; then
  sudo cp "$SANDBOX_DIR/agents/pi/models.json.template" "$AGENT_HOME/.pi/agent/models.json"
fi
sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.pi"

echo "[pi-install] Installing $PI_PACKAGE into /opt/pi..."
sudo mkdir -p /opt/pi
if [ ! -f /opt/pi/package.json ]; then
  ( cd /opt/pi && sudo npm init -y >/dev/null )
fi
( cd /opt/pi && sudo npm install "$PI_PACKAGE" )

PI_BIN="/opt/pi/node_modules/.bin/pi"
[ -x "$PI_BIN" ] || { echo "[pi-install] ERROR: $PI_BIN not found after install" >&2; exit 1; }

# Install `pi` wrapper on PATH. Wraps via `sudo run` so provider API keys
# (DEEPSEEK_API_KEY, ZAI_API_KEY, MOONSHOT_API_KEY, OPENROUTER_API_KEY,
# ANTHROPIC_API_KEY, ...) are sourced from /etc/devbox/locked/secrets at
# invocation time — never persisted in the agent's env or .bashrc.
sudo tee /usr/local/bin/pi >/dev/null <<EOF
#!/bin/bash
exec sudo /usr/local/bin/run $PI_BIN "\$@"
EOF
sudo chmod 755 /usr/local/bin/pi

# PATH addition for /home/agent/.local/bin (user-installed pip/cargo bins).
if ! sudo -u "$AGENT_USER" grep -q "/home/agent/.local/bin" "$AGENT_HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="/home/agent/.local/bin:$PATH"' | sudo tee -a "$AGENT_HOME/.bashrc" >/dev/null
  sudo chown "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.bashrc"
fi

echo "[pi-install] Done."
echo "[pi-install] Provider keys live in /etc/devbox/locked/secrets (sudo sync-secrets)."
echo "[pi-install] Model catalog: $AGENT_HOME/.pi/agent/models.json"
```

Note what changed vs the old file: source build of `badlogic/pi-mono` → npm install into `/opt/pi` (a plain npm prefix dir, no global-bin clobber risk); ANTHROPIC-only messaging → multi-provider; models.json installation added; wrapper contract (`sudo run`) unchanged.

- [ ] **Step 6: Syntax-check and lint**

Run: `bash -n agents/pi/install.sh && shellcheck agents/pi/install.sh`
Expected: no errors (shellcheck info/style notes acceptable).

- [ ] **Step 7: Commit**

```bash
git add agents/pi/install.sh agents/pi/models.json.template agents/pi/extensions/
git commit -m "feat(pi): install from earendil-works npm, multi-provider models.json"
```

---

### Task 4: Rewrite shared/secrets.example for personal scope

**Files:**
- Modify: `shared/secrets.example` (wholesale `Write` — see hook caveat in Global Constraints)

**Interfaces:**
- Produces: env var names consumed by Task 3's models.json (`DEEPSEEK_API_KEY`, `ZAI_API_KEY`, `MOONSHOT_API_KEY`, `OPENROUTER_API_KEY`) and by `hosts/ovh-vps` bootstrap (`GH_TOKEN_PERSONAL`). These exact names are the contract.

- [ ] **Step 1: Capture the current file** (blocked from Read by cred-guard)

Run: `git -C /workspace/fun/sandbox show HEAD:shared/secrets.example`

- [ ] **Step 2: Replace the file**

`Write` the new content:

```bash
# Sandbox global secrets — sourced by `sudo run <command>` from
# /etc/devbox/locked/secrets (root:600).
#
# Use `sudo sync-secrets` to populate (idempotent upsert from stdin),
# OR `sudo vi /etc/devbox/locked/secrets` to edit by hand.
#
# Per-project .env files go in /etc/devbox/locked/projects/<project>/,
# NOT in this file.

# ---- GitHub ----
# Git push/pull uses SSH keys (ship-keys.sh). The token below is for gh
# CLI features: triggering actions, creating PRs, API calls, etc.
# GH_TOKEN_PERSONAL=github_pat_...

# ---- Model providers (Pi reads these via `sudo run`) ----
# DeepSeek — PAYG default, https://platform.deepseek.com
# DEEPSEEK_API_KEY=
# z.ai GLM Coding Plan, https://z.ai
# ZAI_API_KEY=
# Kimi (Moonshot) membership / API, https://platform.moonshot.ai
# MOONSHOT_API_KEY=
# OpenRouter — BYOK fallback router, https://openrouter.ai
# OPENROUTER_API_KEY=
# Anthropic — optional PAYG escalation for Claude Code
# ANTHROPIC_API_KEY=
```

Dropped relative to the old file: `AWS_*` (no AWS on the new host), all `STAGING_DB_*` / `DATABASE_REPLICA_*` (DeepReel-only), `GH_TOKEN_DEEPREEL`, GCP section. This file seeds **new** boxes only; the live AWS box's populated secrets are untouched by this change.

- [ ] **Step 3: Verify the shared-scripts test suite still passes**

Run: `bats shared/scripts/tests/run.bats`
Expected: PASS (the `run` script doesn't parse the example file, but this is the cheap regression gate for the scripts dir).

- [ ] **Step 4: Commit**

```bash
git add shared/secrets.example
git commit -m "feat(secrets): personal-scope example — provider keys in, deepreel out"
```

---

### Task 5: hosts/ovh-vps — bootstrap.sh + config.env

**Files:**
- Create: `hosts/ovh-vps/bootstrap.sh`
- Create: `hosts/ovh-vps/config.env`

**Interfaces:**
- Consumes: `agents/pi/install.sh` (Task 3 contract: `SANDBOX_DIR`, `AGENT_HOME`, `AGENT_USER` env), `shared/scripts/*`, `shared/sudoers.d/agent`, `shared/dotfiles/*`, `shared/tmuxinator/fun.yml`.
- Produces: a bootstrapped box; `config.env` defines `TAILNET_HOSTNAME` and `FUN_REPO_URLS` consumed by Task 6's `sync.sh`/`connect.sh`/`ship-keys.sh`.

- [ ] **Step 1: Create config.env**

```bash
# hosts/ovh-vps/config.env — non-secret host configuration, sourced by
# bootstrap.sh (on the box) and sync.sh/connect.sh/ship-keys.sh (from
# the operator's Mac). Secrets do NOT go here.

# Tailscale MagicDNS hostname the box registers as.
TAILNET_HOSTNAME="dp-sandbox-personal"

# Personal repos to clone into /workspace/fun/ (owner/name, via the
# github.com-personal SSH alias). Space-separated.
FUN_REPO_URLS="srijan-ps/sandbox"
```

(Confirm the actual GitHub `owner/name` values with the human partner at execution time — the current box's `/workspace/fun/` contents are the reference: `ls /workspace/fun`.)

- [ ] **Step 2: Write bootstrap.sh**

Create `hosts/ovh-vps/bootstrap.sh`:

```bash
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
# shellcheck source=config.env
source "$SANDBOX_DIR/hosts/ovh-vps/config.env"

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
  : "${TS_AUTHKEY:?TS_AUTHKEY env var required for first bootstrap}"
  sudo tailscale up --ssh --authkey "$TS_AUTHKEY" --hostname "$TAILNET_HOSTNAME"
fi
tailscale status >/dev/null || { echo "Tailscale not healthy; aborting before firewall lockdown" >&2; exit 1; }

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
for cfg in "$SANDBOX_DIR/shared/tmuxinator/"*.yml; do
  sudo install -m 644 -o agent -g agent "$cfg" "/home/agent/.config/tmuxinator/$(basename "$cfg")"
done
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
sudo iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT
sudo iptables -P OUTPUT DROP
# Ingress: lo, established, tailscale0 only. No public SSH (OVH has no
# cloud firewall by default — iptables is the enforcement layer).
sudo iptables -F INPUT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -i tailscale0 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 41641 -j ACCEPT   # Tailscale direct conns
sudo iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
sudo iptables -P INPUT DROP
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
```

- [ ] **Step 3: Syntax-check and lint**

Run: `bash -n hosts/ovh-vps/bootstrap.sh && shellcheck hosts/ovh-vps/bootstrap.sh`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add hosts/ovh-vps/bootstrap.sh hosts/ovh-vps/config.env
git commit -m "feat(ovh-vps): bootstrap script + host config"
```

---

### Task 6: hosts/ovh-vps — sync.sh, connect.sh, ship-keys.sh, ship-project-env.sh

**Files:**
- Create: `hosts/ovh-vps/sync.sh`
- Create: `hosts/ovh-vps/connect.sh`
- Create: `hosts/ovh-vps/ship-keys.sh`
- Create: `hosts/ovh-vps/ship-project-env.sh`

**Interfaces:**
- Consumes: `hosts/ovh-vps/config.env` (Task 5: `TAILNET_HOSTNAME`, `FUN_REPO_URLS`).
- Produces: operator-side CLI: `./sync.sh`, `./connect.sh [agent|ubuntu]`, `./ship-keys.sh [local-dir]`.

- [ ] **Step 1: Write connect.sh**

```bash
#!/bin/bash
# connect.sh — SSH to the OVH sandbox over Tailscale.
# Usage: ./connect.sh [ubuntu|agent]   (default: ubuntu)
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/config.env"
USER="${1:-ubuntu}"
exec tailscale ssh "$USER@$TAILNET_HOSTNAME"
```

- [ ] **Step 2: Write ship-keys.sh**

Personal-only sibling of `hosts/aws-ec2/sync-ssh-keys.sh` (hostname from config.env instead of terraform; deepreel keys dropped):

```bash
#!/bin/bash
# ship-keys.sh — ship the personal GitHub SSH + GPG keypair from
# ~/.sandbox-keys/ on the operator's Mac to /etc/devbox/locked/keys/
# on the VM (root:600). sync.sh installs them onto agent.
#
# Usage:
#   ./ship-keys.sh                  # uses ~/.sandbox-keys
#   ./ship-keys.sh <local-dir>
#
# Files stream over Tailscale SSH via stdin → sudo tee — never written
# to local /tmp, never echoed.
set -euo pipefail

LOCAL_DIR="${1:-$HOME/.sandbox-keys}"
[ -d "$LOCAL_DIR" ] || { echo "[ship-keys] not a directory: $LOCAL_DIR" >&2; exit 1; }
source "$(cd "$(dirname "$0")" && pwd)/config.env"

DEST=/etc/devbox/locked/keys
FILES=(id_ed25519_personal id_ed25519_personal.pub gpg_personal.asc)

echo "[ship-keys] target: $TAILNET_HOSTNAME:$DEST"
tailscale ssh "ubuntu@$TAILNET_HOSTNAME" "sudo install -d -m 700 -o root -g root '$DEST'"

shipped=0
for f in "${FILES[@]}"; do
  src="$LOCAL_DIR/$f"
  [ -f "$src" ] || { echo "[ship-keys] skip $f (not found)" >&2; continue; }
  printf '[ship-keys] sending %s ...' "$f"
  tailscale ssh "ubuntu@$TAILNET_HOSTNAME" "
    sudo tee '$DEST/$f' >/dev/null
    sudo chown root:root '$DEST/$f'
    sudo chmod 600 '$DEST/$f'
  " < "$src"
  echo " ok"
  shipped=$((shipped + 1))
done

[ "$shipped" -gt 0 ] || { echo "[ship-keys] nothing shipped — check $LOCAL_DIR" >&2; exit 1; }
echo "[ship-keys] $shipped file(s) shipped. Now run: ./sync.sh"
```

- [ ] **Step 3: Write sync.sh**

The `power.sh sync` equivalent, trimmed to personal scope (no terraform, no start/stop, no deepreel keys/tokens/repos, adds Pi reinstall):

```bash
#!/bin/bash
# sync.sh — reconcile a running OVH sandbox with the repo. Idempotent.
#   - git pull /opt/sandbox
#   - reinstall shared scripts, sudoers, patterns, dotfiles, tmuxinator
#   - reinstall Pi extensions/skills/patterns (agents/pi/install.sh)
#   - install any shipped keys onto agent (ssh + gpg + gh token)
#   - clone any FUN_REPO_URLS missing from /workspace/fun/
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/config.env"

echo "[sync] Pulling latest /opt/sandbox..."
tailscale ssh "ubuntu@$TAILNET_HOSTNAME" 'cd /opt/sandbox && sudo git pull --ff-only 2>&1 | tail -3'

echo "[sync] Re-installing scripts, patterns, dotfiles, agents..."
tailscale ssh "ubuntu@$TAILNET_HOSTNAME" '
  set -e
  for s in run lock-env unlock-env sync-secrets with_creds tx gh; do
    sudo install -m 755 /opt/sandbox/shared/scripts/$s /usr/local/bin/$s
  done
  sudo install -m 440 -o root -g root /opt/sandbox/shared/sudoers.d/agent /etc/sudoers.d/agent
  SANDBOX_DIR=/opt/sandbox AGENT_HOME=/home/agent AGENT_USER=agent \
    bash /opt/sandbox/agents/pi/install.sh
  sudo -u agent mkdir -p /home/agent/.config/tmuxinator
  for cfg in /opt/sandbox/shared/tmuxinator/*.yml; do
    sudo install -m 644 -o agent -g agent "$cfg" "/home/agent/.config/tmuxinator/$(basename "$cfg")"
  done
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
```

- [ ] **Step 4: Write ship-project-env.sh**

Personal-scope sibling of `hosts/aws-ec2/sync-project-env.sh` (hostname from config.env; same stdin-streaming discipline — for personal projects that keep locked `.env` files under `/etc/devbox/locked/projects/<rel>/`, which `run` sources by cwd):

```bash
#!/bin/bash
# ship-project-env.sh — ship .env* files from a local project dir to
# /etc/devbox/locked/projects/<vm-target>/ on the VM (root:600).
# `run` sources them when invoked from /workspace/<vm-target>.
#
# Usage:
#   ./ship-project-env.sh <local-dir> <vm-target> [files...]
#   e.g. ./ship-project-env.sh ~/fun/myapp fun/myapp        # ships .env*
#        ./ship-project-env.sh ~/fun/myapp fun/myapp .env.production
#
# Files stream over Tailscale SSH via stdin → sudo tee — never written
# to local /tmp, never echoed.
set -euo pipefail

[ $# -ge 2 ] || { echo "Usage: $0 <local-dir> <vm-target> [files...]" >&2; exit 1; }
LOCAL_DIR="$1"; VM_TARGET="$2"; shift 2
[ -d "$LOCAL_DIR" ] || { echo "[ship-env] not a directory: $LOCAL_DIR" >&2; exit 1; }
source "$(cd "$(dirname "$0")" && pwd)/config.env"

DEST="/etc/devbox/locked/projects/$VM_TARGET"
if [ $# -gt 0 ]; then
  FILES=("$@")
else
  FILES=()
  while IFS= read -r f; do FILES+=("$(basename "$f")"); done \
    < <(find "$LOCAL_DIR" -maxdepth 1 -name '.env*' -type f)
fi
[ ${#FILES[@]} -gt 0 ] || { echo "[ship-env] no .env* files in $LOCAL_DIR" >&2; exit 1; }

echo "[ship-env] target: $TAILNET_HOSTNAME:$DEST"
tailscale ssh "ubuntu@$TAILNET_HOSTNAME" "sudo install -d -m 700 -o root -g root '$DEST'"

for f in "${FILES[@]}"; do
  src="$LOCAL_DIR/$f"
  [ -f "$src" ] || { echo "[ship-env] skip $f (not found)" >&2; continue; }
  printf '[ship-env] sending %s ...' "$f"
  tailscale ssh "ubuntu@$TAILNET_HOSTNAME" "
    sudo tee '$DEST/$f' >/dev/null
    sudo chown root:root '$DEST/$f'
    sudo chmod 600 '$DEST/$f'
  " < "$src"
  echo " ok"
done
echo "[ship-env] done."
```

- [ ] **Step 5: Syntax-check and lint all four**

Run: `for f in hosts/ovh-vps/{sync,connect,ship-keys,ship-project-env}.sh; do bash -n "$f" && shellcheck "$f" || exit 1; done && chmod +x hosts/ovh-vps/*.sh`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add hosts/ovh-vps/sync.sh hosts/ovh-vps/connect.sh hosts/ovh-vps/ship-keys.sh hosts/ovh-vps/ship-project-env.sh
git commit -m "feat(ovh-vps): sync, connect, ship-keys, and ship-project-env operator scripts"
```

---

### Task 7: Runbook + root README

**Files:**
- Create: `hosts/ovh-vps/README.md`
- Modify: `README.md` (Supported section + Repo layout tree)

- [ ] **Step 1: Write the runbook**

Create `hosts/ovh-vps/README.md`:

```markdown
# OVH VPS host (Mumbai)

Personal-scope sandbox on an always-on OVH VPS-2 (4 vCPU / 8 GB / 75 GB
NVMe, ₹810/mo ex-GST). No Terraform — the box is ordered in the OVH
portal and reconciled with `sync.sh`. Design:
`docs/superpowers/specs/2026-07-25-personal-sandbox-migration-design.md`.

## Provision (one-time)

1. Order **VPS-2, Mumbai, Ubuntu 24.04** at ovhcloud.com/en-in/vps/
   (in-place upgrade to VPS-3 available later if cramped).
2. Mint a Tailscale auth key (reusable=no, ephemeral=no, tag as usual).
3. First SSH in with the OVH-provided key, then:

       sudo git clone https://github.com/<owner>/sandbox.git /opt/sandbox
       TS_AUTHKEY=tskey-auth-... bash /opt/sandbox/hosts/ovh-vps/bootstrap.sh

4. From your Mac: `./ship-keys.sh && ./sync.sh` (keys → clones).
5. Switch /opt/sandbox origin to SSH once keys are live:
   `sudo git -C /opt/sandbox remote set-url origin git@github.com-personal:<owner>/sandbox.git`
6. Populate provider keys (from your Mac):
   `printf 'DEEPSEEK_API_KEY=%s\n' "$KEY" | tailscale ssh ubuntu@dp-sandbox-personal 'sudo sync-secrets'`

## Verify isolation (after bootstrap and after any sync)

Run as agent (`./connect.sh agent`):

| Check | Expect |
|---|---|
| `cat /etc/devbox/locked/secrets` | Permission denied |
| `sudo bash` | sudoers denial (only `run` allowed) |
| inside `pi`: read a `.env` path | cred-guard block |
| inside `pi`: `echo sk-ant-test1234567890abcdefghij` output | `[REDACTED]` in context |
| `curl --max-time 5 http://example.com:8080` | timeout (egress allowlist) |
| `nc -zv <public-ip> 22` from a non-tailnet machine | no route/filtered |
| `bash /opt/sandbox/hosts/ovh-vps/bootstrap.sh` re-run | completes, changes nothing |

## Day-to-day

| | |
|---|---|
| `./connect.sh [agent\|ubuntu]` | Tailscale SSH |
| `./sync.sh` | Reconcile box with repo (scripts, patterns, Pi, dotfiles, keys, clones) |
| `./ship-keys.sh` | Re-ship SSH/GPG keys after rotation |
| on box: `pi` | Pi with provider keys injected per-invocation |
| on box: `tx fun` | tmuxinator personal layout |

## Model providers

Keys live in `/etc/devbox/locked/secrets`; the catalog is
`~agent/.pi/agent/models.json` (template: `agents/pi/models.json.template`).
Day-one: DeepSeek PAYG. Subscription trial (GLM Pro vs Kimi) decided
per the design doc, ~Sept 2026.

## AWS decommission checklist (before 2026-07-31)

- [ ] Migrate any personal state off the AWS box (dotfile drift, in-flight
      worktrees, `~/.claude` history worth keeping)
- [ ] `cd hosts/aws-ec2/terraform && terraform workspace select <ws>`
      then source workspace secrets and `terraform destroy -var-file=...`
- [ ] Confirm in AWS console: instance, EBS volume, EIP, IAM sandbox user gone
- [ ] Remove the old device from the Tailscale admin console
- [ ] Cancel Claude Max before the renewal date
- [ ] Downgrade/rotate any DeepReel-scoped tokens still in ~/.sandbox-keys
```

- [ ] **Step 2: Update root README**

In `README.md`:
- In the `## Supported` section, change the Hosts line to: `- **Hosts**: \`ovh-vps\` (personal sandbox, Mumbai), \`aws-ec2\` (deepreel sandbox — decommissioning Jul 2026), \`gcp-vm\`, \`docker-mac\``
- In the `## Repo layout` tree, add under `hosts/`: `│   ├── ovh-vps/        # bootstrap.sh, sync.sh, connect.sh, ship-keys.sh (no terraform)`

- [ ] **Step 3: Commit**

```bash
git add hosts/ovh-vps/README.md README.md
git commit -m "docs(ovh-vps): runbook + root README host listing"
```

---

### Task 8: Full-suite verification pass

**Files:** none new — verification only.

- [ ] **Step 1: Run every test suite in the repo**

Run: `bats agents/claude-code/hooks/tests/*.bats shared/scripts/tests/*.bats && (cd agents/pi/extensions && npx tsx tests/redactor.test.ts)`
Expected: ALL PASS.

- [ ] **Step 2: Lint every script this plan touched**

Run: `shellcheck agents/pi/install.sh hosts/ovh-vps/*.sh`
Expected: no errors.

- [ ] **Step 3: Confirm nothing under hosts/aws-ec2/ changed**

Run: `git log --oneline -20 -- hosts/aws-ec2/ | head -3 && git status --short hosts/aws-ec2/`
Expected: no commits from this plan, clean status.

- [ ] **Step 4: Commit any stragglers, then hand off to ops**

The remaining spec items are operational (order the VPS, run bootstrap, parallel-run, destroy AWS, cancel Max) — they follow `hosts/ovh-vps/README.md` with the human partner in the loop, not this plan.

---

## Execution notes

- Tasks 1→2→3 are ordered (patterns → extension → installer). Task 4 is independent after 3 (shares env-var contract). Tasks 5→6→7 are ordered. Task 8 is last.
- Network-dependent steps (`npm view`, pi.dev docs fetch) run inside the sandbox's egress allowlist (443 open) — they work, but if npm registry name resolution fails for the scoped package, STOP and check https://pi.dev/docs rather than guessing package names.
```
