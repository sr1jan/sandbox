# YOLO Sandbox v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude-Code sandbox VM on AWS EC2 with credential isolation, Tailscale-only access, and a refactored repo structure that supports future agents, hosts, and workspaces.

**Architecture:** Three-axis repo structure (`agents/` × `hosts/` × `workspaces/`). Refactor first (no behavior change; existing Pi sandbox keeps working), then add `agents/claude-code/`, `hosts/aws-ec2/`, and the `deepreel-srijan-claude` workspace. Credential isolation via existing `sudo run` wrapper (extended to handle multi-file creds), cred-guard PreToolUse hook, and redactor PostToolUse hook reading from `shared/patterns/*.json`.

**Tech Stack:** Bash, TypeScript (Pi extensions), Terraform with AWS + Tailscale providers, Docker (for dp-pg/dp-redis on the host), tmux, bats (hook tests).

**Spec:** [docs/superpowers/specs/2026-04-24-yolo-sandbox-design.md](../specs/2026-04-24-yolo-sandbox-design.md)

**ADRs:** [0001-threat-model](../../adr/0001-threat-model.md) · [0002-aws-account](../../adr/0002-aws-account-c-with-carefully-constraints.md) · [0003-tailscale-over-ssm](../../adr/0003-tailscale-over-ssm.md) · [0004-egress-broad-https](../../adr/0004-egress-broad-https-allowlist.md) · [0005-os-level-isolation](../../adr/0005-os-level-isolation-over-devcontainer.md) · [0006-three-axis-repo-structure](../../adr/0006-three-axis-repo-structure.md)

---

## File Structure Map

**Refactored (moves + edits to existing files):**

| File | Disposition |
|------|-------------|
| `docker/` → `hosts/docker-mac/` | Directory rename; update internal paths |
| `vm/` → `hosts/gcp-vm/` | Directory rename; update internal paths; accept `--agent` param |
| `shared/extensions/` → `agents/pi/extensions/` | Move; rewire to read JSON patterns |
| `shared/skills/` → `agents/pi/skills/` | Move; path update only |
| `shared/scripts/run` | Edit: add multi-file creds tmpdir handling |
| `README.md` | Rewrite for new layout |

**Created (new v1 files):**

| File | Responsibility |
|------|----------------|
| `shared/patterns/cred-guard.json` | File + bash regex patterns (single source of truth) |
| `shared/patterns/redactor.json` | Output-redaction regex patterns |
| `shared/editor/tmux.conf.local` | Portable tmux config template |
| `agents/pi/install.sh` | Install Pi on any host (extracted from existing bootstrap) |
| `agents/claude-code/hooks/cred-guard.sh` | PreToolUse hook reading cred-guard.json |
| `agents/claude-code/hooks/redactor.sh` | PostToolUse hook reading redactor.json |
| `agents/claude-code/hooks/tests/cred-guard.bats` | Bats tests for the hook |
| `agents/claude-code/hooks/tests/redactor.bats` | Bats tests for the hook |
| `agents/claude-code/settings.json.template` | Claude Code settings wiring the hooks + agent .bashrc |
| `agents/claude-code/install.sh` | Installs Claude Code, writes settings.json, adds `with_creds` to .bashrc |
| `hosts/aws-ec2/terraform/versions.tf` | Provider version pins |
| `hosts/aws-ec2/terraform/variables.tf` | Workspace-scoped input variables |
| `hosts/aws-ec2/terraform/main.tf` | VPC + subnet + IGW + route table + SG + EC2 + EIP |
| `hosts/aws-ec2/terraform/iam.tf` | Custom-policy IAM user for CloudWatch readonly |
| `hosts/aws-ec2/terraform/tailscale.tf` | Ephemeral tailnet key (consumed at first boot) |
| `hosts/aws-ec2/terraform/outputs.tf` | Instance ID, EIP, tailnet name |
| `hosts/aws-ec2/bootstrap.sh` | Runs on EC2 post-provision; delegates agent install |
| `hosts/aws-ec2/connect.sh` | Convenience wrapper for `tailscale ssh` |
| `hosts/aws-ec2/README.md` | Setup prerequisites and teardown |
| `workspaces/deepreel-srijan-claude.tfvars` | v1 workspace variables |
| `workspaces/deepreel-srijan-claude.secrets.env.example` | Template (real `.secrets.env` gitignored) |
| `workspaces/README.md` | How to add a new workspace |
| `workspaces/.gitignore` | Excludes real secrets + tfstate |

---

## Phase 1: Refactor (no behavior change)

Goal: reorganize the repo into the three-axis layout without breaking the existing Pi-on-Docker setup. Each task lands as one atomic commit. If anything breaks Pi, stop and investigate.

### Task 1.1: Pre-flight — verify Pi+Docker currently works

**Files:** none (read-only verification)

- [ ] **Step 1: Confirm existing layout before touching anything**

Run:
```bash
cd /Users/neodurden/fun/sandbox
ls -d docker vm shared
```

Expected output: `docker  shared  vm` (three dirs).

- [ ] **Step 2: Build and attach once to verify Pi works pre-refactor**

Run:
```bash
cd /Users/neodurden/fun/sandbox/docker
./attach.sh
```

Expected: container builds (or is already built), tmux session attaches, two windows visible (admin + AISpotlight). Exit with `Ctrl-b d`. This is the baseline we must preserve.

- [ ] **Step 3: Record baseline**

Note the container ID and image tag:
```bash
docker ps --filter name=devbox --format "{{.ID}} {{.Image}}"
```

No commit in this task.

### Task 1.2: Move `docker/` to `hosts/docker-mac/`

**Files:**
- Move: `docker/` → `hosts/docker-mac/`
- Modify: `hosts/docker-mac/Dockerfile` (two `COPY` lines)
- Modify: `hosts/docker-mac/docker-compose.yml` (one `dockerfile:` line)

- [ ] **Step 1: Create the hosts directory and move the tree**

Run:
```bash
cd /Users/neodurden/fun/sandbox
mkdir -p hosts
git mv docker hosts/docker-mac
```

- [ ] **Step 2: Update the Dockerfile COPY path for entrypoint**

Edit `hosts/docker-mac/Dockerfile`, find the line:
```dockerfile
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
```

Replace with:
```dockerfile
COPY hosts/docker-mac/entrypoint.sh /usr/local/bin/entrypoint.sh
```

- [ ] **Step 3: Update the docker-compose dockerfile path**

Edit `hosts/docker-mac/docker-compose.yml`, find:
```yaml
    build:
      context: ..
      dockerfile: docker/Dockerfile
```

Replace with:
```yaml
    build:
      context: ../..
      dockerfile: hosts/docker-mac/Dockerfile
```

The `context: ../..` points to the repo root (so `COPY shared/*` paths still resolve).

- [ ] **Step 4: Rebuild and verify Pi still works**

Run:
```bash
cd /Users/neodurden/fun/sandbox/hosts/docker-mac
docker compose build --no-cache
./attach.sh
```

Expected: build completes, tmux attaches with the two expected windows. Detach with `Ctrl-b d`.

- [ ] **Step 5: Commit**

```bash
cd /Users/neodurden/fun/sandbox
git add -A
git status    # verify: renames + Dockerfile/compose edits only
git commit -m "Move docker/ to hosts/docker-mac/

Part of the refactor to the three-axis repo structure. No behavior
change: Dockerfile entrypoint path and compose build context updated
to point at the new location.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.3: Move `vm/` to `hosts/gcp-vm/`

**Files:**
- Move: `vm/` → `hosts/gcp-vm/`
- Modify: `hosts/gcp-vm/bootstrap.sh` — update references to `$SANDBOX_DIR/docker/secrets.example` (now `hosts/docker-mac/secrets.example`)

- [ ] **Step 1: Move the directory**

Run:
```bash
cd /Users/neodurden/fun/sandbox
git mv vm hosts/gcp-vm
```

- [ ] **Step 2: Fix the secrets.example path in bootstrap.sh**

Edit `hosts/gcp-vm/bootstrap.sh`, find:
```bash
  sudo cp "$SANDBOX_DIR/docker/secrets.example" /etc/devbox/secrets
```

Replace with:
```bash
  sudo cp "$SANDBOX_DIR/hosts/docker-mac/secrets.example" /etc/devbox/secrets
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Move vm/ to hosts/gcp-vm/

Part of the refactor to the three-axis repo structure. Updated one
path in bootstrap.sh pointing at the secrets.example template.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.4: Move Pi extensions and skills to `agents/pi/`

**Files:**
- Move: `shared/extensions/` → `agents/pi/extensions/`
- Move: `shared/skills/` → `agents/pi/skills/`
- Modify: `hosts/docker-mac/Dockerfile` — `COPY shared/extensions/` → `COPY agents/pi/extensions/`; `COPY shared/skills/` → `COPY agents/pi/skills/`
- Modify: `hosts/gcp-vm/bootstrap.sh` — `"$SANDBOX_DIR/shared/extensions/"` → `"$SANDBOX_DIR/agents/pi/extensions/"`; same for skills

- [ ] **Step 1: Move the directories**

Run:
```bash
cd /Users/neodurden/fun/sandbox
mkdir -p agents/pi
git mv shared/extensions agents/pi/extensions
git mv shared/skills agents/pi/skills
```

- [ ] **Step 2: Update the Dockerfile COPY paths**

Edit `hosts/docker-mac/Dockerfile`, find:
```dockerfile
COPY shared/extensions/ /home/agent/.pi/agent/extensions/
COPY shared/skills/ /home/agent/.pi/agent/skills/
```

Replace with:
```dockerfile
COPY agents/pi/extensions/ /home/agent/.pi/agent/extensions/
COPY agents/pi/skills/ /home/agent/.pi/agent/skills/
```

- [ ] **Step 3: Update bootstrap.sh paths**

Edit `hosts/gcp-vm/bootstrap.sh`, find:
```bash
sudo cp "$SANDBOX_DIR/shared/extensions/"*.ts /home/agent/.pi/agent/extensions/
sudo cp -r "$SANDBOX_DIR/shared/skills/"* /home/agent/.pi/agent/skills/
```

Replace with:
```bash
sudo cp "$SANDBOX_DIR/agents/pi/extensions/"*.ts /home/agent/.pi/agent/extensions/
sudo cp -r "$SANDBOX_DIR/agents/pi/skills/"* /home/agent/.pi/agent/skills/
```

- [ ] **Step 4: Rebuild and verify**

Run:
```bash
cd /Users/neodurden/fun/sandbox/hosts/docker-mac
docker compose build --no-cache
./attach.sh
```

Inside the container, as agent: `ls /home/agent/.pi/agent/extensions/ && ls /home/agent/.pi/agent/skills/` — expect the same files as before the move.

- [ ] **Step 5: Commit**

```bash
cd /Users/neodurden/fun/sandbox
git add -A
git commit -m "Move Pi extensions and skills under agents/pi/

Part of the three-axis refactor. Extensions and skills are
Pi-specific; they belong under agents/pi/, not in shared/.
Dockerfile and GCP bootstrap paths updated.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 2: Extract patterns to `shared/patterns/`

Goal: pull the regex lists out of Pi's TypeScript extensions into JSON, so Claude Code hooks can consume the same source of truth.

### Task 2.1: Create `shared/patterns/cred-guard.json`

**Files:**
- Create: `shared/patterns/cred-guard.json`

- [ ] **Step 1: Write the JSON file**

Create `shared/patterns/cred-guard.json` with the pattern lists from `agents/pi/extensions/cred-guard.ts`:

```json
{
  "$schema": "./cred-guard.schema.json",
  "description": "File-path and bash-command patterns that indicate credential exposure. Regexes are JavaScript-flavored but intentionally written to work in POSIX ERE (grep -E / awk) as well — so both the Pi TS extension and the Claude Code shell hook can consume this file.",
  "file_patterns": [
    "\\.env($|\\.)",
    "\\.env\\.local$",
    "\\.env\\.secrets$",
    "\\.env\\.development$",
    "\\.env\\.production$",
    "credentials",
    "secrets?\\.",
    "\\.pem$",
    "\\.key$",
    "\\.p12$",
    "\\.pfx$",
    "service.account.*\\.json",
    "/etc/devbox/secrets",
    "\\.aws/credentials",
    "\\.config/gh/hosts\\.yml",
    "\\.config/gcloud",
    "\\.docker/config\\.json",
    "\\.npmrc$",
    "\\.pypirc$",
    "\\.netrc$"
  ],
  "bash_patterns": [
    "\\bcat\\b.*\\.env",
    "\\bless\\b.*\\.env",
    "\\bhead\\b.*\\.env",
    "\\btail\\b.*\\.env",
    "\\bmore\\b.*\\.env",
    "\\bsource\\b.*\\.env",
    "\\bgrep\\b.*\\.env",
    "\\bawk\\b.*\\.env",
    "\\bsed\\b.*\\.env",
    "\\benv\\s*($|\\|)",
    "\\bprintenv\\b",
    "\\bset\\s*($|\\|)",
    "\\bexport\\s+-p",
    "\\bdeclare\\s+-x",
    "/proc/.*/environ",
    "\\bxargs\\b.*/proc",
    "/etc/devbox/secrets",
    "\\.aws/credentials",
    "\\.config/gh/hosts",
    "\\bsudo\\s+cat\\b",
    "\\bsudo\\s+less\\b",
    "\\bsudo\\s+head\\b",
    "\\bsudo\\s+tail\\b",
    "\\bsudo\\s+more\\b",
    "\\bsudo\\s+vi\\b",
    "\\bsudo\\s+vim\\b",
    "\\bsudo\\s+nvim\\b",
    "\\bsudo\\s+nano\\b",
    "\\bsudo\\s+bash\\b",
    "\\bsudo\\s+sh\\b",
    "\\bsudo\\s+su\\b",
    "\\bsudo\\s+-i\\b",
    "\\bsudo\\s+-s\\b",
    "python.*os\\.environ",
    "python.*subprocess.*env",
    "node.*process\\.env"
  ]
}
```

- [ ] **Step 2: Commit**

```bash
git add shared/patterns/cred-guard.json
git commit -m "Extract cred-guard patterns to shared/patterns/cred-guard.json

Single source of truth for file and bash patterns that trigger
credential-exposure blocks. Both Pi's TypeScript extension and the
forthcoming Claude Code shell hook will read from this JSON.
No behavior change yet; Pi's .ts still has the hardcoded lists.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 2.2: Create `shared/patterns/redactor.json`

**Files:**
- Create: `shared/patterns/redactor.json`

- [ ] **Step 1: Write the JSON file**

Create `shared/patterns/redactor.json` with the `CREDENTIAL_PATTERNS` list from `agents/pi/extensions/tmux-tools.ts` (lines 23-40):

```json
{
  "description": "Regex patterns matching credential-looking strings in tool output. Matches are replaced with [REDACTED] before the output is returned to the agent's context. Patterns are JavaScript-flavored; the Claude Code shell hook translates to POSIX ERE at runtime.",
  "replacement": "[REDACTED]",
  "patterns": [
    "sk-ant-[a-zA-Z0-9_-]+",
    "sk-proj-[a-zA-Z0-9_-]+",
    "sk-[a-zA-Z0-9]{48,}",
    "ghp_[a-zA-Z0-9]{36,}",
    "gho_[a-zA-Z0-9]{36,}",
    "ghs_[a-zA-Z0-9]{36,}",
    "github_pat_[a-zA-Z0-9_]+",
    "AKIA[A-Z0-9]{16}",
    "glpat-[a-zA-Z0-9_-]+",
    "xoxb-[a-zA-Z0-9-]+",
    "xoxp-[a-zA-Z0-9-]+",
    "AIza[a-zA-Z0-9_-]{35}",
    "Bearer\\s+[a-zA-Z0-9_.-]{20,}",
    "token[\"\\s:=]+[a-zA-Z0-9_.-]{20,}",
    "password[\"\\s:=]+\\S+",
    "secret[\"\\s:=]+\\S+"
  ]
}
```

- [ ] **Step 2: Commit**

```bash
git add shared/patterns/redactor.json
git commit -m "Extract redactor patterns to shared/patterns/redactor.json

Single source of truth for output-scrubbing regexes. Pi's
tmux-tools extension and the forthcoming Claude Code PostToolUse
hook will consume this JSON. No behavior change yet.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 2.3: Rewire Pi's `cred-guard.ts` to read the JSON

**Files:**
- Modify: `agents/pi/extensions/cred-guard.ts`

- [ ] **Step 1: Replace the inline regex arrays with JSON loading**

Edit `agents/pi/extensions/cred-guard.ts`. Replace the `SENSITIVE_FILE_PATTERNS` and `SENSITIVE_BASH_PATTERNS` arrays (lines 17-90) with a single JSON load at module init. The full revised file:

```typescript
/**
 * Credential Guard Extension
 *
 * Blocks the agent from reading credential files or running commands
 * that would expose secrets to the conversation context.
 *
 * Pattern lists are loaded from shared/patterns/cred-guard.json, which
 * is shared with the Claude Code PreToolUse hook.
 *
 * Two layers of defense:
 *   1. File permissions (OS-enforced, .env files are root:root 600)
 *   2. This extension (soft guard, catches env/printenv/proc reads)
 *
 * Place in ~/.pi/agent/extensions/ for global protection across all projects.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { isToolCallEventType } from "@mariozechner/pi-coding-agent";
import { readFileSync } from "node:fs";
import { join } from "node:path";

interface CredGuardPatterns {
	file_patterns: string[];
	bash_patterns: string[];
}

function loadPatterns(): CredGuardPatterns {
	// Resolve shared/patterns/cred-guard.json relative to this file.
	// Dockerfile copies extensions to /home/agent/.pi/agent/extensions/
	// and we copy patterns to /home/agent/.pi/agent/patterns/ alongside.
	const candidates = [
		join(__dirname, "..", "patterns", "cred-guard.json"),
		"/home/agent/.pi/agent/patterns/cred-guard.json",
	];
	for (const path of candidates) {
		try {
			return JSON.parse(readFileSync(path, "utf-8"));
		} catch {
			continue;
		}
	}
	throw new Error(
		`cred-guard.json not found in any of: ${candidates.join(", ")}`,
	);
}

const patterns = loadPatterns();
const SENSITIVE_FILE_PATTERNS = patterns.file_patterns.map((p) => new RegExp(p, "i"));
const SENSITIVE_BASH_PATTERNS = patterns.bash_patterns.map((p) => new RegExp(p));

function isSensitiveFile(path: string): boolean {
	return SENSITIVE_FILE_PATTERNS.some((p) => p.test(path));
}

function isSensitiveBash(command: string): boolean {
	return SENSITIVE_BASH_PATTERNS.some((p) => p.test(command));
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (
			isToolCallEventType("read", event) ||
			isToolCallEventType("write", event) ||
			isToolCallEventType("edit", event)
		) {
			const path = event.input.path as string;
			if (isSensitiveFile(path)) {
				if (ctx.hasUI) {
					ctx.ui.notify(`Blocked: sensitive file ${path}`, "warning");
				}
				return { block: true, reason: `Sensitive file: ${path}` };
			}
		}

		if (isToolCallEventType("bash", event)) {
			const cmd = event.input.command as string;
			if (isSensitiveBash(cmd)) {
				if (ctx.hasUI) {
					ctx.ui.notify(`Blocked: credential-exposing command`, "warning");
				}
				return { block: true, reason: "Command may expose credentials" };
			}
		}

		return undefined;
	});

	pi.on("session_start", async (_event, ctx) => {
		if (ctx.hasUI) {
			ctx.ui.setStatus("cred-guard", ctx.ui.theme.fg("accent", "cred-guard active"));
		}
	});
}
```

- [ ] **Step 2: Update Dockerfile to copy patterns dir into the container**

Edit `hosts/docker-mac/Dockerfile`, find:
```dockerfile
# Pi extensions and skills (global, for agent user)
RUN mkdir -p /home/agent/.pi/agent/extensions /home/agent/.pi/agent/skills
COPY agents/pi/extensions/ /home/agent/.pi/agent/extensions/
COPY agents/pi/skills/ /home/agent/.pi/agent/skills/
```

Add a line for patterns:
```dockerfile
RUN mkdir -p /home/agent/.pi/agent/extensions /home/agent/.pi/agent/skills /home/agent/.pi/agent/patterns
COPY agents/pi/extensions/ /home/agent/.pi/agent/extensions/
COPY agents/pi/skills/ /home/agent/.pi/agent/skills/
COPY shared/patterns/ /home/agent/.pi/agent/patterns/
```

- [ ] **Step 3: Update gcp-vm bootstrap.sh**

Edit `hosts/gcp-vm/bootstrap.sh`, find:
```bash
sudo cp "$SANDBOX_DIR/agents/pi/extensions/"*.ts /home/agent/.pi/agent/extensions/
sudo cp -r "$SANDBOX_DIR/agents/pi/skills/"* /home/agent/.pi/agent/skills/
```

Add one line:
```bash
sudo cp "$SANDBOX_DIR/agents/pi/extensions/"*.ts /home/agent/.pi/agent/extensions/
sudo cp -r "$SANDBOX_DIR/agents/pi/skills/"* /home/agent/.pi/agent/skills/
sudo mkdir -p /home/agent/.pi/agent/patterns
sudo cp "$SANDBOX_DIR/shared/patterns/"*.json /home/agent/.pi/agent/patterns/
```

- [ ] **Step 4: Rebuild and verify cred-guard still blocks correctly**

```bash
cd /Users/neodurden/fun/sandbox/hosts/docker-mac
docker compose build --no-cache
./attach.sh
```

Inside container, switch to agent window (Ctrl-b 2), launch pi, and ask it: "Please run `cat /etc/devbox/secrets`". Expected: cred-guard blocks with "Sensitive file" notification. Detach.

- [ ] **Step 5: Commit**

```bash
cd /Users/neodurden/fun/sandbox
git add -A
git commit -m "Rewire Pi cred-guard.ts to read shared/patterns/cred-guard.json

Pattern lists now come from the shared JSON file. Dockerfile and
gcp-vm bootstrap updated to place patterns under
/home/agent/.pi/agent/patterns/. Behavior unchanged; verified by
attempting a blocked file read.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 2.4: Rewire Pi's `tmux-tools.ts` redactor to read redactor.json

**Files:**
- Modify: `agents/pi/extensions/tmux-tools.ts`

- [ ] **Step 1: Replace the inline `CREDENTIAL_PATTERNS` array with JSON load**

Edit `agents/pi/extensions/tmux-tools.ts`. Find the `CREDENTIAL_PATTERNS` array (around lines 23-40) and replace it with a JSON load similar to cred-guard.ts:

At the top of the file, add imports:
```typescript
import { readFileSync } from "node:fs";
import { join } from "node:path";
```

Replace the `CREDENTIAL_PATTERNS` constant with:
```typescript
interface RedactorPatterns {
	replacement: string;
	patterns: string[];
}

function loadRedactorPatterns(): RegExp[] {
	const candidates = [
		join(__dirname, "..", "patterns", "redactor.json"),
		"/home/agent/.pi/agent/patterns/redactor.json",
	];
	for (const path of candidates) {
		try {
			const parsed: RedactorPatterns = JSON.parse(readFileSync(path, "utf-8"));
			return parsed.patterns.map((p) => new RegExp(p, "g"));
		} catch {
			continue;
		}
	}
	throw new Error("redactor.json not found");
}

const CREDENTIAL_PATTERNS = loadRedactorPatterns();
```

Leave `BLOCKED_COMMANDS` and the rest of the file untouched (those are Pi-pane-specific).

- [ ] **Step 2: Verify build and redaction still works**

```bash
cd /Users/neodurden/fun/sandbox/hosts/docker-mac
docker compose build --no-cache
./attach.sh
```

Inside container: open Pi, create a tmux pane that echoes a fake key: `echo "sk-ant-FAKE-PLANT-xyz123456"`, then use Pi's `tmux_capture_pane` tool to read it. Expected: the captured output shows `[REDACTED]` instead of the fake key.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Rewire Pi tmux-tools redactor to read shared/patterns/redactor.json

Redactor pattern list now loaded from the shared JSON. BLOCKED_COMMANDS
stays inline since it's Pi-pane-specific (not shared with Claude Code).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 3: Extract `agents/pi/install.sh`

Goal: pull the Pi-specific installation logic out of the GCP bootstrap into a reusable install script. This is what `hosts/*/bootstrap.sh` will delegate to via `--agent pi`.

### Task 3.1: Write `agents/pi/install.sh`

**Files:**
- Create: `agents/pi/install.sh`
- Modify: `hosts/gcp-vm/bootstrap.sh` (call agents/pi/install.sh instead of inlining)

- [ ] **Step 1: Create install.sh**

Create `agents/pi/install.sh`:

```bash
#!/bin/bash
# Install Pi coding agent for the 'agent' user. Idempotent.
#
# Expects:
# - agent user already exists
# - $SANDBOX_DIR env var points at the sandbox repo root
# - Node.js 22, git, curl available
#
# Usage (called from a host bootstrap):
#   SANDBOX_DIR=/path/to/sandbox AGENT_HOME=/home/agent \
#     bash agents/pi/install.sh

set -euo pipefail

: "${SANDBOX_DIR:?SANDBOX_DIR must point at the sandbox repo root}"
: "${AGENT_HOME:=/home/agent}"
: "${AGENT_USER:=agent}"
: "${PI_PROJECTS_DIR:=$HOME/projects}"

echo "[pi-install] Setting up Pi extensions, skills, and patterns..."

# Extensions + skills + patterns (shared with cred-guard/redactor hooks)
sudo -u "$AGENT_USER" mkdir -p \
  "$AGENT_HOME/.pi/agent/extensions" \
  "$AGENT_HOME/.pi/agent/skills" \
  "$AGENT_HOME/.pi/agent/patterns"

sudo cp "$SANDBOX_DIR/agents/pi/extensions/"*.ts "$AGENT_HOME/.pi/agent/extensions/"
sudo cp -r "$SANDBOX_DIR/agents/pi/skills/"* "$AGENT_HOME/.pi/agent/skills/"
sudo cp "$SANDBOX_DIR/shared/patterns/"*.json "$AGENT_HOME/.pi/agent/patterns/"
sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.pi"

# Pi from source
echo "[pi-install] Cloning and building pi-mono..."
mkdir -p "$PI_PROJECTS_DIR"
if [ ! -d "$PI_PROJECTS_DIR/pi-mono" ]; then
  git clone https://github.com/badlogic/pi-mono.git "$PI_PROJECTS_DIR/pi-mono"
fi
( cd "$PI_PROJECTS_DIR/pi-mono" && npm install && npm run build )

PI_BIN="$PI_PROJECTS_DIR/pi-mono/packages/coding-agent/dist/cli/index.js"

# Agent alias
if ! sudo -u "$AGENT_USER" grep -q "alias pi=" "$AGENT_HOME/.bashrc" 2>/dev/null; then
  echo "alias pi=\"node $PI_BIN\"" | sudo tee -a "$AGENT_HOME/.bashrc" >/dev/null
  sudo chown "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.bashrc"
fi

echo "[pi-install] Done."
```

Make it executable: `chmod +x agents/pi/install.sh`.

- [ ] **Step 2: Refactor `hosts/gcp-vm/bootstrap.sh` to delegate to install.sh**

Edit `hosts/gcp-vm/bootstrap.sh`. Remove the "[5/9]" and "[7/9]" sections (Pi extensions/skills copy and Pi source build) and replace them with a delegation block. The full updated bootstrap should:

1. Accept a new `--agent` flag (default `pi` for backward compatibility)
2. After OS/user setup, call `agents/<agent>/install.sh`

Add argument parsing at the top of the script:
```bash
AGENT="pi"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2;;
    *) echo "Unknown flag: $1"; exit 1;;
  esac
done
```

Replace the block starting `# --- Pi extensions and skills ---` through the end of the `# --- Pi from source ---` block with:
```bash
# --- Agent install (delegated) ---
echo "[...] Installing agent: $AGENT"
if [ ! -x "$SANDBOX_DIR/agents/$AGENT/install.sh" ]; then
  echo "Error: agents/$AGENT/install.sh not found or not executable"
  exit 1
fi
SANDBOX_DIR="$SANDBOX_DIR" AGENT_HOME="/home/agent" AGENT_USER="agent" \
  bash "$SANDBOX_DIR/agents/$AGENT/install.sh"
```

Renumber the step messages (previously 5/9...9/9) to reflect the new structure.

- [ ] **Step 3: Test on a throwaway VM (or skip if no GCP VM available — Docker path covers regression)**

If you have a GCP VM: rsync + re-run bootstrap, verify Pi still works. Otherwise skip; the Docker path exercises the extensions/patterns copy via Dockerfile.

- [ ] **Step 4: Verify Docker path still works (regression check)**

```bash
cd /Users/neodurden/fun/sandbox/hosts/docker-mac
docker compose build --no-cache
./attach.sh
```

Expected: Pi still launches and cred-guard still blocks sensitive reads.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Extract Pi install logic to agents/pi/install.sh

GCP VM bootstrap now delegates to agents/<agent>/install.sh via
the --agent flag (default: pi). This makes the host bootstrap
agent-agnostic, preparing for Claude Code as a second agent.
Docker path unchanged (Dockerfile already uses direct COPY).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 4: Claude Code hooks (TDD with bats)

Goal: write the PreToolUse cred-guard hook and PostToolUse redactor hook that read from `shared/patterns/*.json`. Use TDD — tests first, implementation second.

### Task 4.1: Set up bats testing infrastructure

**Files:**
- Create: `agents/claude-code/hooks/tests/test_helper.bash`
- Create: `agents/claude-code/hooks/tests/fixtures/cred-guard.json` (minimal test fixture)

- [ ] **Step 1: Ensure bats is available**

Run:
```bash
which bats || brew install bats-core
```

Expected: bats binary is available. If on Linux: `sudo apt-get install -y bats`.

- [ ] **Step 2: Create test helper**

Create `agents/claude-code/hooks/tests/test_helper.bash`:

```bash
#!/bin/bash
# Shared test helper for hook tests.
# Provides paths, temp dirs, and a mock PATTERNS_DIR pointing at fixtures.

setup() {
  TEST_DIR="$BATS_TEST_DIRNAME"
  HOOKS_DIR="$(cd "$TEST_DIR/.." && pwd)"
  FIXTURES_DIR="$TEST_DIR/fixtures"

  # Claude Code passes hook input via stdin as JSON. Tests simulate this
  # by piping a crafted JSON payload into the hook.
  export CLAUDE_HOOKS_PATTERNS_DIR="$FIXTURES_DIR"
}

teardown() { :; }

# Helper: emit a PreToolUse event payload for the Bash tool
bash_event() {
  local cmd="$1"
  printf '{"tool":"Bash","input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)"
}

# Helper: emit a PreToolUse event payload for Read
read_event() {
  local path="$1"
  printf '{"tool":"Read","input":{"file_path":%s}}' "$(printf '%s' "$path" | jq -Rs .)"
}
```

- [ ] **Step 3: Create a minimal cred-guard fixture**

Create `agents/claude-code/hooks/tests/fixtures/cred-guard.json`:

```json
{
  "file_patterns": [
    "\\.env($|\\.)",
    "/etc/devbox/secrets"
  ],
  "bash_patterns": [
    "\\bcat\\b.*\\.env",
    "\\bprintenv\\b",
    "\\bsudo\\s+cat\\b"
  ]
}
```

- [ ] **Step 4: Commit fixtures and helper**

```bash
git add agents/claude-code/hooks/tests/
git commit -m "Add bats test harness skeleton for Claude Code hooks

Fixture cred-guard.json + test helper. No hook code yet; ready
for TDD in the next task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 4.2: Write failing tests for `cred-guard.sh`

**Files:**
- Create: `agents/claude-code/hooks/tests/cred-guard.bats`

- [ ] **Step 1: Write the bats test file**

Create `agents/claude-code/hooks/tests/cred-guard.bats`:

```bash
#!/usr/bin/env bats

load test_helper

@test "cred-guard blocks Bash: cat .env" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'cat .env')"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "blocked" ]] || [[ "$output" =~ "credential" ]]
}

@test "cred-guard blocks Bash: printenv" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'printenv')"
  [ "$status" -eq 2 ]
}

@test "cred-guard blocks Bash: sudo cat /etc/devbox/secrets" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'sudo cat /etc/devbox/secrets')"
  [ "$status" -eq 2 ]
}

@test "cred-guard allows Bash: sudo run psql" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'sudo run psql $DB_URL -c \"SELECT 1\"')"
  [ "$status" -eq 0 ]
}

@test "cred-guard allows Bash: ls" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'ls -la')"
  [ "$status" -eq 0 ]
}

@test "cred-guard blocks Read: .env file" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(read_event '/workspace/core/backend/.env')"
  [ "$status" -eq 2 ]
}

@test "cred-guard blocks Read: /etc/devbox/secrets" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(read_event '/etc/devbox/secrets')"
  [ "$status" -eq 2 ]
}

@test "cred-guard allows Read: regular source file" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(read_event '/workspace/core/backend/src/models.py')"
  [ "$status" -eq 0 ]
}

@test "cred-guard returns clear reason in stderr when blocking" {
  run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'cat .env')"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "pattern:" ]]
}

@test "cred-guard fails loud if CLAUDE_HOOKS_PATTERNS_DIR/cred-guard.json is missing" {
  CLAUDE_HOOKS_PATTERNS_DIR=/nonexistent run bash "$HOOKS_DIR/cred-guard.sh" <<< "$(bash_event 'ls')"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "cred-guard.json" ]]
}
```

- [ ] **Step 2: Run tests to verify they all fail with "hook not found"**

Run:
```bash
cd /Users/neodurden/fun/sandbox
bats agents/claude-code/hooks/tests/cred-guard.bats
```

Expected: all 10 tests FAIL because `agents/claude-code/hooks/cred-guard.sh` does not exist. This is the TDD baseline.

- [ ] **Step 3: Commit failing tests**

```bash
git add agents/claude-code/hooks/tests/cred-guard.bats
git commit -m "Add failing bats tests for Claude Code cred-guard hook

TDD baseline. 10 tests cover: block cat/printenv/sudo-cat; allow
sudo-run and regular commands; Read-path file checks; missing-JSON
error. All fail until cred-guard.sh is written.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 4.3: Implement `cred-guard.sh` to make tests pass

**Files:**
- Create: `agents/claude-code/hooks/cred-guard.sh`

- [ ] **Step 1: Write the hook**

Create `agents/claude-code/hooks/cred-guard.sh`:

```bash
#!/bin/bash
# Claude Code PreToolUse hook: blocks tool calls that would expose credentials.
#
# Input: JSON payload on stdin, shape:
#   {"tool":"Bash","input":{"command":"<string>"}}
#   {"tool":"Read","input":{"file_path":"<string>"}}
#   {"tool":"Edit","input":{"file_path":"<string>","old_string":"...","new_string":"..."}}
#   {"tool":"Write","input":{"file_path":"<string>","content":"..."}}
#
# Exit codes:
#   0 = allow (tool call proceeds)
#   2 = block (Claude sees the block reason in its tool result)
#   other = hard error (Claude Code surfaces this to the user)
#
# Patterns are loaded from $CLAUDE_HOOKS_PATTERNS_DIR/cred-guard.json
# (default: $HOME/.claude/hooks/patterns/).

set -euo pipefail

PATTERNS_DIR="${CLAUDE_HOOKS_PATTERNS_DIR:-$HOME/.claude/hooks/patterns}"
PATTERNS_FILE="$PATTERNS_DIR/cred-guard.json"

if [ ! -f "$PATTERNS_FILE" ]; then
  echo "cred-guard.json not found at $PATTERNS_FILE" >&2
  exit 3
fi

# Read the event payload
event_json="$(cat)"
tool="$(jq -r '.tool' <<< "$event_json")"

case "$tool" in
  Bash)
    command="$(jq -r '.input.command // empty' <<< "$event_json")"
    if [ -z "$command" ]; then
      exit 0  # nothing to check
    fi
    mapfile -t bash_patterns < <(jq -r '.bash_patterns[]' "$PATTERNS_FILE")
    for p in "${bash_patterns[@]}"; do
      if grep -qE "$p" <<< "$command"; then
        echo "blocked: bash command matches credential-exposure pattern: $p" >&2
        exit 2
      fi
    done
    exit 0
    ;;
  Read|Edit|Write)
    path="$(jq -r '.input.file_path // empty' <<< "$event_json")"
    if [ -z "$path" ]; then
      exit 0
    fi
    mapfile -t file_patterns < <(jq -r '.file_patterns[]' "$PATTERNS_FILE")
    for p in "${file_patterns[@]}"; do
      if grep -qiE "$p" <<< "$path"; then
        echo "blocked: file path matches credential pattern: $p" >&2
        exit 2
      fi
    done
    exit 0
    ;;
  *)
    # Unknown tool — allow through
    exit 0
    ;;
esac
```

Make it executable: `chmod +x agents/claude-code/hooks/cred-guard.sh`.

- [ ] **Step 2: Run tests to verify they all pass**

Run:
```bash
cd /Users/neodurden/fun/sandbox
bats agents/claude-code/hooks/tests/cred-guard.bats
```

Expected: 10 passed, 0 failed. If any fail, fix the hook until all pass (no loosening of tests).

- [ ] **Step 3: Commit**

```bash
git add agents/claude-code/hooks/cred-guard.sh
git commit -m "Implement Claude Code cred-guard.sh PreToolUse hook

Reads shared/patterns/cred-guard.json and blocks Bash commands or
Read/Edit/Write paths matching credential-exposure patterns.
Exit 2 = block (with reason on stderr), exit 0 = allow.
All 10 bats tests pass.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 4.4: Write failing tests for `redactor.sh`

**Files:**
- Create: `agents/claude-code/hooks/tests/fixtures/redactor.json`
- Create: `agents/claude-code/hooks/tests/redactor.bats`

- [ ] **Step 1: Create redactor fixture**

Create `agents/claude-code/hooks/tests/fixtures/redactor.json`:

```json
{
  "replacement": "[REDACTED]",
  "patterns": [
    "sk-ant-[a-zA-Z0-9_-]+",
    "AKIA[A-Z0-9]{16}",
    "ghp_[a-zA-Z0-9]{36,}"
  ]
}
```

- [ ] **Step 2: Write the bats tests**

Create `agents/claude-code/hooks/tests/redactor.bats`:

```bash
#!/usr/bin/env bats

load test_helper

# Helper: feed a PostToolUse event with tool output
post_event() {
  local output="$1"
  printf '{"tool":"Bash","tool_result":{"stdout":%s,"stderr":""}}' \
    "$(printf '%s' "$output" | jq -Rs .)"
}

@test "redactor replaces Anthropic API key" {
  output_with_key="Response: sk-ant-api03-ABCxyz123-fake"
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "$output_with_key")"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[REDACTED]" ]]
  [[ ! "$output" =~ "sk-ant-api03-ABCxyz123-fake" ]]
}

@test "redactor replaces AWS access key" {
  output_with_key="AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "$output_with_key")"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[REDACTED]" ]]
  [[ ! "$output" =~ "AKIAIOSFODNN7EXAMPLE" ]]
}

@test "redactor replaces GitHub PAT" {
  output_with_pat="Token: ghp_abcdefghijklmnopqrstuvwxyz0123456789"
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "$output_with_pat")"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "[REDACTED]" ]]
}

@test "redactor passes non-matching output through unchanged" {
  plain="Hello, world. Nothing sensitive here."
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "$plain")"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Hello, world. Nothing sensitive here." ]]
}

@test "redactor replaces multiple matches in one output" {
  multi="Keys: sk-ant-ONE-xyz and AKIAIOSFODNN7EXAMPLE in one string"
  run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event "$multi")"
  [ "$status" -eq 0 ]
  match_count="$(grep -oc '\[REDACTED\]' <<< "$output" || true)"
  [ "$match_count" -ge 2 ]
}

@test "redactor fails loud if redactor.json is missing" {
  CLAUDE_HOOKS_PATTERNS_DIR=/nonexistent run bash "$HOOKS_DIR/redactor.sh" <<< "$(post_event 'foo')"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "redactor.json" ]]
}
```

- [ ] **Step 3: Run tests to verify they all fail**

```bash
bats agents/claude-code/hooks/tests/redactor.bats
```

Expected: all 6 fail because `redactor.sh` doesn't exist.

- [ ] **Step 4: Commit**

```bash
git add agents/claude-code/hooks/tests/fixtures/redactor.json agents/claude-code/hooks/tests/redactor.bats
git commit -m "Add failing bats tests for Claude Code redactor hook

TDD baseline. 6 tests cover: redact Anthropic/AWS/GitHub keys;
pass clean output through; multi-match; missing-JSON error.
All fail until redactor.sh is written.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 4.5: Implement `redactor.sh` to make tests pass

**Files:**
- Create: `agents/claude-code/hooks/redactor.sh`

- [ ] **Step 1: Write the hook**

Create `agents/claude-code/hooks/redactor.sh`:

```bash
#!/bin/bash
# Claude Code PostToolUse hook: scrubs credential-shaped strings from tool output
# before it reaches Claude's context.
#
# Input: JSON payload on stdin with the tool result, e.g.:
#   {"tool":"Bash","tool_result":{"stdout":"...","stderr":"..."}}
#
# Output: same JSON with stdout/stderr scrubbed. Claude Code replaces the tool
# result with this.
#
# Exit 0 = success (scrubbed JSON emitted on stdout)
# Non-zero = error (Claude Code surfaces to user)

set -euo pipefail

PATTERNS_DIR="${CLAUDE_HOOKS_PATTERNS_DIR:-$HOME/.claude/hooks/patterns}"
PATTERNS_FILE="$PATTERNS_DIR/redactor.json"

if [ ! -f "$PATTERNS_FILE" ]; then
  echo "redactor.json not found at $PATTERNS_FILE" >&2
  exit 3
fi

event_json="$(cat)"
replacement="$(jq -r '.replacement // "[REDACTED]"' "$PATTERNS_FILE")"

# Build a single sed expression from the pattern list
sed_script=""
while IFS= read -r pattern; do
  # Escape sed delimiter / and the replacement's special chars
  esc_pattern="$(printf '%s' "$pattern" | sed 's#/#\\/#g')"
  esc_repl="$(printf '%s' "$replacement" | sed 's#/#\\/#g')"
  sed_script="${sed_script}s/${esc_pattern}/${esc_repl}/g;"
done < <(jq -r '.patterns[]' "$PATTERNS_FILE")

# Scrub stdout and stderr fields
scrubbed="$(jq -c --arg sed "$sed_script" '
  def scrub(s): if s == null then s else (s | @text) end;
  .tool_result.stdout = (.tool_result.stdout // "" | @text)
    | .tool_result.stderr = (.tool_result.stderr // "" | @text)
' <<< "$event_json")"

# Apply the sed patterns to stdout + stderr fields via a shell pipeline,
# since jq does not natively support regex replacement of arbitrary patterns.
stdout_scrubbed="$(jq -r '.tool_result.stdout' <<< "$scrubbed" | sed -E "$sed_script")"
stderr_scrubbed="$(jq -r '.tool_result.stderr' <<< "$scrubbed" | sed -E "$sed_script")"

jq -c \
  --arg stdout "$stdout_scrubbed" \
  --arg stderr "$stderr_scrubbed" \
  '.tool_result.stdout = $stdout | .tool_result.stderr = $stderr' \
  <<< "$scrubbed"
```

Make executable: `chmod +x agents/claude-code/hooks/redactor.sh`.

- [ ] **Step 2: Run tests to verify they pass**

```bash
bats agents/claude-code/hooks/tests/redactor.bats
```

Expected: 6 passed, 0 failed. If any fail, fix the hook (not the tests).

- [ ] **Step 3: Commit**

```bash
git add agents/claude-code/hooks/redactor.sh
git commit -m "Implement Claude Code redactor.sh PostToolUse hook

Reads shared/patterns/redactor.json and replaces matching strings in
tool output stdout/stderr with [REDACTED] before Claude sees it.
All 6 bats tests pass.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 5: Claude Code install script and settings template

Goal: write the install.sh that sets up Claude Code on a fresh VM (installs the CLI, copies hooks, writes settings.json, adds `with_creds` to the agent's bashrc).

### Task 5.1: Write `agents/claude-code/settings.json.template`

**Files:**
- Create: `agents/claude-code/settings.json.template`

- [ ] **Step 1: Create the settings template**

Create `agents/claude-code/settings.json.template`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Read|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cred-guard.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/redactor.sh"
          }
        ]
      }
    ]
  },
  "env": {
    "CLAUDE_HOOKS_PATTERNS_DIR": "$HOME/.claude/hooks/patterns"
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add agents/claude-code/settings.json.template
git commit -m "Add Claude Code settings.json template wiring cred-guard and redactor hooks

PreToolUse runs cred-guard on Bash/Read/Edit/Write; PostToolUse
runs redactor on Bash output. Patterns dir is $HOME/.claude/hooks/patterns.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 5.2: Write `agents/claude-code/install.sh`

**Files:**
- Create: `agents/claude-code/install.sh`

- [ ] **Step 1: Create install.sh**

Create `agents/claude-code/install.sh`:

```bash
#!/bin/bash
# Install Claude Code for the 'agent' user. Idempotent.
#
# Expects:
#   - $SANDBOX_DIR env var points at the sandbox repo root
#   - agent user exists
#   - Node.js 22 available
#
# Usage (called from a host bootstrap):
#   SANDBOX_DIR=/path/to/sandbox AGENT_HOME=/home/agent \
#     bash agents/claude-code/install.sh

set -euo pipefail

: "${SANDBOX_DIR:?SANDBOX_DIR must point at the sandbox repo root}"
: "${AGENT_HOME:=/home/agent}"
: "${AGENT_USER:=agent}"

echo "[cc-install] Installing Claude Code CLI..."
sudo -u "$AGENT_USER" npm install -g @anthropic-ai/claude-code

echo "[cc-install] Setting up hooks, patterns, settings..."
sudo -u "$AGENT_USER" mkdir -p \
  "$AGENT_HOME/.claude/hooks" \
  "$AGENT_HOME/.claude/hooks/patterns" \
  "$AGENT_HOME/.claude/skills"

# Hooks
sudo cp "$SANDBOX_DIR/agents/claude-code/hooks/cred-guard.sh" \
        "$AGENT_HOME/.claude/hooks/cred-guard.sh"
sudo cp "$SANDBOX_DIR/agents/claude-code/hooks/redactor.sh" \
        "$AGENT_HOME/.claude/hooks/redactor.sh"
sudo chmod +x "$AGENT_HOME/.claude/hooks/"*.sh

# Patterns
sudo cp "$SANDBOX_DIR/shared/patterns/"*.json \
        "$AGENT_HOME/.claude/hooks/patterns/"

# Settings
sudo cp "$SANDBOX_DIR/agents/claude-code/settings.json.template" \
        "$AGENT_HOME/.claude/settings.json"

# Expand $HOME references in settings.json
sudo sed -i "s|\$HOME|$AGENT_HOME|g" "$AGENT_HOME/.claude/settings.json"

sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.claude"

# with_creds helper in agent's .bashrc (Option 2 from spec §7.2)
echo "[cc-install] Adding with_creds to agent's .bashrc..."
BASHRC="$AGENT_HOME/.bashrc"
if ! sudo grep -q "^with_creds" "$BASHRC" 2>/dev/null; then
  sudo tee -a "$BASHRC" >/dev/null <<'EOF'

# Sandbox credential wrapper (see sandbox/docs/superpowers/specs)
# Delegates credential-needing commands to sudo /usr/local/bin/run,
# which loads secrets and drops privs back to this user before exec.
with_creds() {
  if [ -x /usr/local/bin/run ]; then
    sudo /usr/local/bin/run "$@"
  else
    "$@"
  fi
}
export -f with_creds
EOF
  sudo chown "$AGENT_USER:$AGENT_USER" "$BASHRC"
fi

# Optional: symlink deepreel skills if configured by the workspace
if [ -n "${SKILLS_SOURCE_PATH:-}" ] && [ -d "$SKILLS_SOURCE_PATH" ]; then
  echo "[cc-install] Symlinking skills from $SKILLS_SOURCE_PATH..."
  for skill_dir in "$SKILLS_SOURCE_PATH"/*/; do
    skill_name="$(basename "$skill_dir")"
    if [ "$skill_name" = "_common" ]; then continue; fi  # skip helpers
    sudo -u "$AGENT_USER" ln -sf "$skill_dir" \
      "$AGENT_HOME/.claude/skills/$skill_name"
  done
fi

echo "[cc-install] Done."
```

Make executable: `chmod +x agents/claude-code/install.sh`.

- [ ] **Step 2: Smoke-test the script locally (dry-run style)**

Syntax check:
```bash
bash -n agents/claude-code/install.sh
```

Expected: no output (no syntax errors).

- [ ] **Step 3: Commit**

```bash
git add agents/claude-code/install.sh
git commit -m "Add agents/claude-code/install.sh

Installs Claude Code CLI, copies hooks + patterns + settings, and
adds with_creds to agent's bashrc per spec §7.2. Also handles
optional skill symlinking when SKILLS_SOURCE_PATH is set by the
workspace tfvars.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 6: Extend `shared/scripts/run` for multi-file creds

Goal: add the `creds/` tmpdir handling per spec §5.4 and ADR 0005. `run` should detect a locked `creds/` directory for the current project, copy it into a per-invocation tmpdir owned by `agent`, export `GOOGLE_APPLICATION_CREDENTIALS` if a known filename is present, and clean up on exit.

### Task 6.1: Extend `run` wrapper

**Files:**
- Modify: `shared/scripts/run`

- [ ] **Step 1: Add tmpdir handling logic**

Edit `shared/scripts/run`. After the existing env-loading block (before the final `exec gosu agent "$@"`), add:

```bash
# Multi-file creds (service-account JSONs, PEM certs, etc.)
# If a locked creds/ directory exists for this project, copy it to a
# per-invocation tmpdir owned by agent, export common env vars that
# point at well-known filenames inside it, and schedule cleanup.
LOCKED_CREDS_DIR="$LOCKED_DIR/creds"
if [ -d "$LOCKED_CREDS_DIR" ]; then
  TMPDIR_CREDS="$(mktemp -d -t run-creds-XXXXXX)"
  cp -r "$LOCKED_CREDS_DIR"/. "$TMPDIR_CREDS/"
  chown -R agent:agent "$TMPDIR_CREDS"
  chmod -R go-rwx "$TMPDIR_CREDS"

  # Export GOOGLE_APPLICATION_CREDENTIALS if a service-account file exists
  for candidate in "$TMPDIR_CREDS/service-account.json" \
                   "$TMPDIR_CREDS/google-sa.json" \
                   "$TMPDIR_CREDS"/*-sa.json; do
    if [ -f "$candidate" ]; then
      export GOOGLE_APPLICATION_CREDENTIALS="$candidate"
      break
    fi
  done

  # Cleanup trap
  cleanup_creds() { rm -rf "$TMPDIR_CREDS"; }
  trap cleanup_creds EXIT
fi
```

Also update the block that walks the `/workspace/` path: after the `REL=${CWD#/workspace/}` and loop, the script currently sets `LOCKED_DIR` once. Verify `LOCKED_DIR` is defined for the new block above (if not, compute it the same way — `LOCKED_DIR="/etc/devbox/locked/projects/$REL"`).

- [ ] **Step 2: Test the wrapper manually**

On a system with the sandbox layout (inside the Docker container works), create a test creds dir:
```bash
sudo mkdir -p /etc/devbox/locked/projects/test-app/creds
sudo sh -c 'echo "fake-google-sa-contents" > /etc/devbox/locked/projects/test-app/creds/service-account.json'
sudo chmod 600 /etc/devbox/locked/projects/test-app/creds/service-account.json

mkdir -p /workspace/test-app
cd /workspace/test-app
sudo run sh -c 'echo "GOOGLE_APPLICATION_CREDENTIALS=$GOOGLE_APPLICATION_CREDENTIALS"; ls -la $(dirname $GOOGLE_APPLICATION_CREDENTIALS)'
```

Expected: `GOOGLE_APPLICATION_CREDENTIALS` is set to a `/tmp/run-creds-XXX/service-account.json` path; listing shows agent-owned files.

After exit: `ls /tmp/run-creds-*` should return nothing (tmpdir cleaned up).

- [ ] **Step 3: Commit**

```bash
git add shared/scripts/run
git commit -m "Extend shared/scripts/run with multi-file creds tmpdir handling

If a locked creds/ directory exists for the current project, copy
to a per-invocation tmpdir owned by agent and set
GOOGLE_APPLICATION_CREDENTIALS to a service-account.json if present.
Cleanup on exit via trap. Closes spec §5.4 / ADR 0005.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 7: AWS EC2 Terraform

Goal: Terraform code that provisions a dedicated-VPC EC2 in the deepreel AWS account with all of ADR 0002's constraints baked in.

### Task 7.1: Create Terraform scaffolding

**Files:**
- Create: `hosts/aws-ec2/terraform/versions.tf`
- Create: `hosts/aws-ec2/terraform/variables.tf`
- Create: `hosts/aws-ec2/terraform/outputs.tf`

- [ ] **Step 1: versions.tf**

Create `hosts/aws-ec2/terraform/versions.tf`:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.17"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "sandbox"
      Owner       = var.owner
      ManagedBy   = "terraform"
      Workspace   = terraform.workspace
    }
  }
}

provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = var.tailscale_tailnet
}
```

- [ ] **Step 2: variables.tf**

Create `hosts/aws-ec2/terraform/variables.tf`:

```hcl
variable "owner" {
  description = "Owner tag value, e.g. 'srijan'"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR for the dedicated sandbox VPC (must not overlap prod)"
  type        = string
  default     = "10.100.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR for the sandbox public subnet"
  type        = string
  default     = "10.100.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"
}

variable "ebs_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 40
}

variable "ebs_kms_key_alias" {
  description = "KMS key alias (e.g., 'alias/sandbox-ebs') for EBS encryption. If null, uses AWS-managed aws/ebs."
  type        = string
  default     = null
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID for provisioning ephemeral keys"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret"
  type        = string
  sensitive   = true
}

variable "tailscale_tailnet" {
  description = "Tailscale tailnet name, e.g. 'deepreel.com'"
  type        = string
}

variable "tailscale_tag" {
  description = "Tailscale tag for the sandbox VM"
  type        = string
  default     = "tag:claude-sandbox"
}

variable "allowed_egress_cidrs" {
  description = "CIDRs for egress security-group rules. Broad HTTPS egress is defined in main.tf."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "prod_replica_endpoint" {
  description = "Prod read-replica endpoint (FQDN) the sandbox VM is allowed to reach on 5432. Set to null to disable."
  type        = string
  default     = null
}

variable "cloudwatch_log_group_arns" {
  description = "CloudWatch log group ARNs the sandbox IAM user is allowed to read (scope for the custom policy)"
  type        = list(string)
  default     = []
}

variable "enable_ssm_break_glass" {
  description = "When true, attach a minimal SSM-only IAM instance profile at create time (see ADR 0003)"
  type        = bool
  default     = false
}

variable "deepreel_repo_urls" {
  description = "List of git URLs to clone into /workspace/core/ during bootstrap"
  type        = list(string)
  default     = []
}

variable "skills_source_path" {
  description = "Absolute path on the VM to the skills dir to symlink into agent's ~/.claude/skills/"
  type        = string
  default     = ""
}
```

- [ ] **Step 3: outputs.tf**

Create `hosts/aws-ec2/terraform/outputs.tf`:

```hcl
output "instance_id" {
  value       = aws_instance.sandbox.id
  description = "EC2 instance ID"
}

output "public_ip" {
  value       = aws_eip.sandbox.public_ip
  description = "Elastic IP (used for prod replica allowlisting)"
}

output "tailnet_hostname" {
  value       = local.tailnet_hostname
  description = "Hostname in the tailnet, e.g., 'dp-sandbox' → dp-sandbox.<tailnet>.ts.net"
}

output "vpc_id" {
  value       = aws_vpc.sandbox.id
  description = "Sandbox VPC ID"
}

output "iam_user_access_key_id" {
  value       = aws_iam_access_key.cloudwatch_reader.id
  description = "Access key ID to place in the workspace's .secrets.env as AWS_ACCESS_KEY_ID"
  sensitive   = true
}

output "iam_user_secret_access_key" {
  value       = aws_iam_access_key.cloudwatch_reader.secret
  description = "Secret to place in the workspace's .secrets.env as AWS_SECRET_ACCESS_KEY"
  sensitive   = true
}

output "connection_instructions" {
  value = <<-EOT
    # After terraform apply, connect via Tailscale:
    tailscale ssh admin@${local.tailnet_hostname}

    # Break-glass via SSM (requires step 1 below to attach IAM profile):
    aws ec2 associate-iam-instance-profile \\
      --instance-id ${aws_instance.sandbox.id} \\
      --iam-instance-profile Name=sandbox-ssm-break-glass-${terraform.workspace}
    aws ssm start-session --target ${aws_instance.sandbox.id}
  EOT
}
```

- [ ] **Step 4: Commit**

```bash
git add hosts/aws-ec2/terraform/versions.tf \
        hosts/aws-ec2/terraform/variables.tf \
        hosts/aws-ec2/terraform/outputs.tf
git commit -m "Add Terraform scaffolding: versions, variables, outputs

AWS + Tailscale providers pinned. Variables cover workspace-scoped
inputs (region, CIDRs, instance type, tailnet config, prod replica
endpoint, CloudWatch ARN scope, SSM break-glass toggle, deepreel
repo URLs, skills path). Outputs expose the instance, EIP, tailnet
hostname, and IAM access key pair for the workspace secrets.env.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 7.2: Write `main.tf` — VPC, networking, EC2, security groups

**Files:**
- Create: `hosts/aws-ec2/terraform/main.tf`

- [ ] **Step 1: Write main.tf**

Create `hosts/aws-ec2/terraform/main.tf`:

```hcl
locals {
  tailnet_hostname = "dp-sandbox-${terraform.workspace}"
}

# ---- Ubuntu AMI lookup ----
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---- VPC ----
resource "aws_vpc" "sandbox" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "sandbox-vpc-${terraform.workspace}" }
}

resource "aws_subnet" "sandbox_public" {
  vpc_id                  = aws_vpc.sandbox.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = { Name = "sandbox-public-${terraform.workspace}" }
}

resource "aws_internet_gateway" "sandbox" {
  vpc_id = aws_vpc.sandbox.id

  tags = { Name = "sandbox-igw-${terraform.workspace}" }
}

resource "aws_route_table" "sandbox_public" {
  vpc_id = aws_vpc.sandbox.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sandbox.id
  }

  tags = { Name = "sandbox-public-rt-${terraform.workspace}" }
}

resource "aws_route_table_association" "sandbox_public" {
  subnet_id      = aws_subnet.sandbox_public.id
  route_table_id = aws_route_table.sandbox_public.id
}

# ---- Security group: inbound deny-all, outbound allowlisted ----
resource "aws_security_group" "sandbox" {
  name        = "sandbox-sg-${terraform.workspace}"
  description = "Sandbox VM: no inbound, HTTPS/DNS/specific outbound only"
  vpc_id      = aws_vpc.sandbox.id

  # Inbound: none (default deny)

  egress {
    description = "HTTPS out (broad, per ADR 0004)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_egress_cidrs
  }

  egress {
    description = "DNS out (udp)"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = var.allowed_egress_cidrs
  }

  egress {
    description = "DNS out (tcp)"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = var.allowed_egress_cidrs
  }

  egress {
    description = "Tailscale WireGuard"
    from_port   = 41641
    to_port     = 41641
    protocol    = "udp"
    cidr_blocks = var.allowed_egress_cidrs
  }

  # Prod replica (only if configured)
  dynamic "egress" {
    for_each = var.prod_replica_endpoint != null ? [1] : []
    content {
      description = "Prod Postgres replica"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  # replica is public; SG restriction uses no source since we can't resolve endpoint to IP here
    }
  }

  tags = { Name = "sandbox-sg-${terraform.workspace}" }
}

# ---- EBS KMS key (optional) ----
data "aws_kms_alias" "ebs" {
  count = var.ebs_kms_key_alias != null ? 1 : 0
  name  = var.ebs_kms_key_alias
}

# ---- EC2 instance ----
resource "aws_instance" "sandbox" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.sandbox_public.id
  vpc_security_group_ids      = [aws_security_group.sandbox.id]
  associate_public_ip_address = true
  iam_instance_profile        = null  # ADR 0002 constraint 2 — no profile by default

  metadata_options {
    http_tokens                 = "required"   # IMDSv2 only
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  root_block_device {
    volume_size = var.ebs_size_gb
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = var.ebs_kms_key_alias != null ? data.aws_kms_alias.ebs[0].target_key_arn : null
  }

  user_data = templatefile("${path.module}/../bootstrap.sh.tpl", {
    tailscale_auth_key  = tailscale_tailnet_key.sandbox.key
    tailnet_hostname    = local.tailnet_hostname
    deepreel_repo_urls  = jsonencode(var.deepreel_repo_urls)
    skills_source_path  = var.skills_source_path
    workspace_name      = terraform.workspace
  })

  tags = { Name = "sandbox-${terraform.workspace}" }
}

resource "aws_eip" "sandbox" {
  instance = aws_instance.sandbox.id
  domain   = "vpc"

  tags = { Name = "sandbox-eip-${terraform.workspace}" }
}
```

- [ ] **Step 2: Commit**

```bash
git add hosts/aws-ec2/terraform/main.tf
git commit -m "Add main.tf: VPC, subnet, IGW, SG, EC2, EIP

Dedicated VPC (no peering) per ADR 0002 constraint 1. Security
group allows broad HTTPS + DNS + Tailscale + optional prod replica
outbound; inbound empty. EC2 uses IMDSv2-required, no instance
profile by default, EBS encrypted with optional CMK. EIP for
prod-replica allowlisting. User-data is templated from
bootstrap.sh.tpl (next task).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 7.3: Write `iam.tf` — CloudWatch readonly IAM user + SSM break-glass profile

**Files:**
- Create: `hosts/aws-ec2/terraform/iam.tf`

- [ ] **Step 1: Write iam.tf**

Create `hosts/aws-ec2/terraform/iam.tf`:

```hcl
# ---- CloudWatch readonly IAM user (NOT an instance profile; creds go in /etc/devbox/secrets) ----

resource "aws_iam_user" "cloudwatch_reader" {
  name = "sandbox-cloudwatch-reader-${terraform.workspace}"
  path = "/sandbox/"

  tags = { Purpose = "CloudWatch read-only access from sandbox VM" }
}

data "aws_iam_policy_document" "cloudwatch_reader" {
  statement {
    sid     = "ReadLogs"
    effect  = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:DescribeQueries",
    ]
    # Scope to specific log groups if provided; else all (for now).
    resources = length(var.cloudwatch_log_group_arns) > 0 ? var.cloudwatch_log_group_arns : ["*"]
  }

  statement {
    sid     = "DenyAllWrites"
    effect  = "Deny"
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DeleteLogGroup",
      "logs:DeleteLogStream",
      "logs:PutRetentionPolicy",
      "logs:PutMetricFilter",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "cloudwatch_reader" {
  name   = "cloudwatch-readonly"
  user   = aws_iam_user.cloudwatch_reader.name
  policy = data.aws_iam_policy_document.cloudwatch_reader.json
}

resource "aws_iam_access_key" "cloudwatch_reader" {
  user = aws_iam_user.cloudwatch_reader.name
}

# ---- SSM break-glass instance profile (created but not attached by default) ----

resource "aws_iam_role" "ssm_break_glass" {
  name               = "sandbox-ssm-break-glass-${terraform.workspace}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Purpose = "SSM break-glass, attach on demand per ADR 0003" }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_break_glass.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_break_glass" {
  name = "sandbox-ssm-break-glass-${terraform.workspace}"
  role = aws_iam_role.ssm_break_glass.name
}
```

- [ ] **Step 2: Commit**

```bash
git add hosts/aws-ec2/terraform/iam.tf
git commit -m "Add iam.tf: CloudWatch readonly IAM user + SSM break-glass profile

CloudWatch user has a hand-written policy (no managed ReadOnlyAccess
per ADR 0002 constraint 3) with explicit deny on writes. Scoped to
specific log group ARNs if provided in the workspace vars, else '*'.
SSM break-glass profile is created but NOT attached (ADR 0003);
admin attaches on demand and detaches after use.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 7.4: Write `tailscale.tf` — ephemeral auth key

**Files:**
- Create: `hosts/aws-ec2/terraform/tailscale.tf`

- [ ] **Step 1: Write tailscale.tf**

Create `hosts/aws-ec2/terraform/tailscale.tf`:

```hcl
resource "tailscale_tailnet_key" "sandbox" {
  reusable      = false
  ephemeral     = false
  preauthorized = true
  expiry        = 3600  # auth key valid for 1h — consumed on first boot
  description   = "Sandbox VM ${terraform.workspace} provisioning key"
  tags          = [var.tailscale_tag]
}
```

- [ ] **Step 2: Commit**

```bash
git add hosts/aws-ec2/terraform/tailscale.tf
git commit -m "Add tailscale.tf: ephemeral provisioning auth key

Non-reusable, non-ephemeral (we want the node to persist across
reboots), preauthorized, 1h expiry. Tagged 'tag:claude-sandbox'
by default. Consumed on first boot by the user-data script.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 8: EC2 bootstrap and connect scripts

Goal: the user-data script that runs on first EC2 boot, and a convenience connect wrapper.

### Task 8.1: Write `hosts/aws-ec2/bootstrap.sh.tpl` (user-data template)

**Files:**
- Create: `hosts/aws-ec2/bootstrap.sh.tpl`

- [ ] **Step 1: Write the template**

Create `hosts/aws-ec2/bootstrap.sh.tpl`. This runs as root on first boot via EC2 user-data. It's a Terraform template; `$${...}` is a literal `${...}` in the output script; `${...}` is a Terraform interpolation.

```bash
#!/bin/bash
# Sandbox EC2 bootstrap — runs as root on first boot via user-data.
# Interpolated by Terraform with tailscale_auth_key, tailnet_hostname,
# deepreel_repo_urls, skills_source_path, workspace_name.

set -euo pipefail
exec > >(tee -a /var/log/sandbox-bootstrap.log) 2>&1

echo "=== Sandbox bootstrap start: $(date) ==="

# --- System packages ---
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  git curl wget tmux neovim ripgrep fd-find fzf \
  sudo gosu less jq unzip jo \
  python3 python3-venv build-essential \
  openssh-client ca-certificates iptables \
  ruby-full

# Node.js 22
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

# Docker (for dp-pg / dp-redis)
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

# uv
if ! command -v uv &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  mv /root/.local/bin/uv /usr/local/bin/uv
  mv /root/.local/bin/uvx /usr/local/bin/uvx
fi

# jq must be present for hooks (already installed above, but verify)
command -v jq >/dev/null

# --- Users ---
if ! id agent &>/dev/null; then
  useradd -m -s /bin/bash agent
fi
usermod -aG docker agent

# --- Tailscale ---
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
tailscale up --authkey="${tailscale_auth_key}" --hostname="${tailnet_hostname}" --ssh

# --- Disable sshd (tailscale ssh only) ---
systemctl disable --now ssh || true
systemctl mask ssh || true

# --- Pull the sandbox repo for agent installs ---
SANDBOX_DIR=/opt/sandbox
if [ ! -d "$SANDBOX_DIR" ]; then
  git clone https://github.com/sr1jan/sandbox.git "$SANDBOX_DIR"
fi

# --- Install shared scripts + sudoers + patterns ---
install -m 755 "$SANDBOX_DIR/shared/scripts/run"         /usr/local/bin/run
install -m 755 "$SANDBOX_DIR/shared/scripts/lock-env"    /usr/local/bin/lock-env
install -m 755 "$SANDBOX_DIR/shared/scripts/unlock-env"  /usr/local/bin/unlock-env
install -m 440 "$SANDBOX_DIR/shared/sudoers.d/agent"     /etc/sudoers.d/agent
mkdir -p /etc/devbox/locked
chmod 700 /etc/devbox
touch /etc/devbox/secrets
chmod 600 /etc/devbox/secrets

# --- Egress allowlist at host level (iptables) ---
iptables -F OUTPUT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 5432 -j ACCEPT
iptables -A OUTPUT -p udp --dport 41641 -j ACCEPT
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -P OUTPUT DROP
# Persist iptables rules
apt-get install -y iptables-persistent
netfilter-persistent save

# --- Install Claude Code agent ---
SANDBOX_DIR="$SANDBOX_DIR" AGENT_HOME="/home/agent" AGENT_USER="agent" \
  SKILLS_SOURCE_PATH="${skills_source_path}" \
  bash "$SANDBOX_DIR/agents/claude-code/install.sh"

# --- Clone deepreel repos into /workspace/core/ ---
mkdir -p /workspace/core
chown agent:agent /workspace/core
for repo in $(echo '${deepreel_repo_urls}' | jq -r '.[]'); do
  repo_name="$(basename "$repo" .git)"
  if [ ! -d "/workspace/core/$repo_name" ]; then
    sudo -u agent git clone "$repo" "/workspace/core/$repo_name" || \
      echo "Warning: failed to clone $repo (likely needs GH_TOKEN in /etc/devbox/secrets first)"
  fi
done

# --- tmuxinator config for agent ---
gem install tmuxinator --no-document
sudo -u agent mkdir -p /home/agent/.config/tmuxinator
install -m 644 -o agent -g agent \
  "$SANDBOX_DIR/shared/tmuxinator/dev.yml" \
  "/home/agent/.config/tmuxinator/dev.yml"

echo "=== Sandbox bootstrap complete: $(date) ==="
echo "Connect: tailscale ssh admin@${tailnet_hostname}"
```

- [ ] **Step 2: Verify Terraform interpolation is valid**

Run:
```bash
cd hosts/aws-ec2/terraform
terraform init
terraform validate
```

Expected: `Success! The configuration is valid.` If it fails on the template, fix the syntax (Terraform's `templatefile` has strict escaping).

- [ ] **Step 3: Commit**

```bash
git add hosts/aws-ec2/bootstrap.sh.tpl hosts/aws-ec2/terraform/.terraform.lock.hcl
git commit -m "Add EC2 user-data bootstrap template

Installs OS packages + Node + Docker + Tailscale; creates admin +
agent users; disables sshd in favor of tailscale ssh; applies
iptables egress allowlist per ADR 0004; delegates Claude Code
install to agents/claude-code/install.sh; clones deepreel repos
into /workspace/core/ from the workspace tfvars URL list.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 8.2: Write `hosts/aws-ec2/connect.sh`

**Files:**
- Create: `hosts/aws-ec2/connect.sh`

- [ ] **Step 1: Write connect.sh**

Create `hosts/aws-ec2/connect.sh`:

```bash
#!/bin/bash
# Convenience wrapper: tailscale ssh into the sandbox VM.
#
# Usage:
#   ./connect.sh                  # SSH as admin to the default workspace's instance
#   ./connect.sh --user agent     # SSH as agent
#   ./connect.sh --workspace <w>  # SSH to a specific workspace's instance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

USER="admin"
WORKSPACE="$(cd "$TF_DIR" && terraform workspace show 2>/dev/null || echo default)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER="$2"; shift 2;;
    --workspace) WORKSPACE="$2"; shift 2;;
    --help|-h)
      echo "Usage: $0 [--user admin|agent] [--workspace <name>]"
      exit 0;;
    *) echo "Unknown flag: $1"; exit 1;;
  esac
done

HOSTNAME="$(cd "$TF_DIR" && terraform workspace select "$WORKSPACE" && terraform output -raw tailnet_hostname)"

exec tailscale ssh "${USER}@${HOSTNAME}"
```

Make executable: `chmod +x hosts/aws-ec2/connect.sh`.

- [ ] **Step 2: Commit**

```bash
git add hosts/aws-ec2/connect.sh
git commit -m "Add hosts/aws-ec2/connect.sh convenience wrapper

Resolves tailnet hostname from terraform output for the given
workspace, then execs 'tailscale ssh <user>@<hostname>'.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 8.3: Write `hosts/aws-ec2/README.md`

**Files:**
- Create: `hosts/aws-ec2/README.md`

- [ ] **Step 1: Write README**

Create `hosts/aws-ec2/README.md`:

```markdown
# AWS EC2 host

Provisions an EC2 sandbox VM in the deepreel AWS account following
ADR 0002's "carefully" constraints. Access is Tailscale-only.

## Prerequisites

- AWS CLI configured with credentials for the deepreel account, with
  permissions to manage VPC, EC2, IAM, and SSM resources.
- Terraform >= 1.6.
- A Tailscale tailnet with an OAuth client configured (Tailscale Admin
  Console → Settings → OAuth Clients → New). Scopes: `auth_keys`,
  `devices`.
- A workspace tfvars file under `../../workspaces/<workspace>.tfvars`
  and a matching `<workspace>.secrets.env` with the Tailscale OAuth
  secret (not committed).

## First-time setup

```bash
cd hosts/aws-ec2/terraform
terraform init
terraform workspace new <workspace-name>    # e.g. deepreel-srijan-claude
```

Load workspace secrets (Tailscale OAuth) into env:

```bash
set -a; source ../../../workspaces/<workspace>.secrets.env; set +a
```

Apply:

```bash
terraform apply -var-file=../../../workspaces/<workspace>.tfvars
```

Wait ~3-5 minutes for the VM to bootstrap (pulls repos, installs
Claude Code, joins tailnet). Check progress via CloudWatch or SSM
break-glass (see below).

## Connecting

After bootstrap:

```bash
../connect.sh               # SSH as admin
../connect.sh --user agent  # SSH as agent
```

## Break-glass via SSM

If Tailscale is unreachable:

```bash
aws ec2 associate-iam-instance-profile \
  --instance-id $(terraform output -raw instance_id) \
  --iam-instance-profile Name=sandbox-ssm-break-glass-<workspace>
aws ssm start-session --target $(terraform output -raw instance_id)
# ...fix whatever's broken...
# after your session ends:
aws ec2 disassociate-iam-instance-profile \
  --association-id $(aws ec2 describe-iam-instance-profile-associations \
    --filters Name=instance-id,Values=$(terraform output -raw instance_id) \
    --query 'IamInstanceProfileAssociations[0].AssociationId' --output text)
```

## Teardown

```bash
terraform destroy -var-file=../../../workspaces/<workspace>.tfvars
```

Verify in AWS console: no sandbox-* resources remain. If any orphans,
they're the spec's acceptance criterion — file a follow-up to clean
them up.
```

- [ ] **Step 2: Commit**

```bash
git add hosts/aws-ec2/README.md
git commit -m "Add hosts/aws-ec2/README.md — setup, connect, break-glass, teardown

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 9: Workspace configuration

Goal: the v1 workspace tfvars for `deepreel-srijan-claude`.

### Task 9.1: Write workspace files

**Files:**
- Create: `workspaces/deepreel-srijan-claude.tfvars`
- Create: `workspaces/deepreel-srijan-claude.secrets.env.example`
- Create: `workspaces/README.md`
- Create: `workspaces/.gitignore`

- [ ] **Step 1: workspace tfvars**

Create `workspaces/deepreel-srijan-claude.tfvars`:

```hcl
owner      = "srijan"
aws_region = "ap-south-1"

# Dedicated VPC (no peering to default VPC where prod lives)
vpc_cidr    = "10.100.0.0/16"
subnet_cidr = "10.100.1.0/24"

instance_type = "t3.large"
ebs_size_gb   = 40

# Tailscale
tailscale_tailnet = "deepreel.com"           # adjust to your tailnet name
tailscale_tag     = "tag:claude-sandbox"

# tailscale_oauth_client_id and _secret come from the .secrets.env file

# Prod replica (already publicly accessible; listed here so SG rule opens 5432)
prod_replica_endpoint = "<prod-replica-fqdn>.rds.amazonaws.com"

# CloudWatch log group ARNs the sandbox IAM user is allowed to read.
# Fill in before first apply.
cloudwatch_log_group_arns = [
  # "arn:aws:logs:ap-south-1:<account-id>:log-group:/ecs/deepreel-backend:*",
]

# Deepreel repos to clone into /workspace/core/ during bootstrap
deepreel_repo_urls = [
  # "git@github.com:deepreel/backend.git",
  # "git@github.com:deepreel/seo-content-agent.git",
  # "git@github.com:deepreel/frontend.git",
  # "git@github.com:deepreel/skills.git",
]

# Skills: path on the VM (bootstrap clones skills repo into /workspace/core/)
skills_source_path = "/workspace/core/skills"

enable_ssm_break_glass = false  # attach on demand per ADR 0003
```

- [ ] **Step 2: secrets.env template**

Create `workspaces/deepreel-srijan-claude.secrets.env.example`:

```bash
# Copy to workspaces/deepreel-srijan-claude.secrets.env (gitignored) and fill in.
#
# Load into env before `terraform apply`:
#   set -a; source workspaces/deepreel-srijan-claude.secrets.env; set +a

export TF_VAR_tailscale_oauth_client_id="<from Tailscale Admin Console → OAuth Clients>"
export TF_VAR_tailscale_oauth_client_secret="<from Tailscale Admin Console>"
```

- [ ] **Step 3: workspaces/README.md**

Create `workspaces/README.md`:

```markdown
# Workspaces

Each `*.tfvars` file here defines a distinct sandbox instance. The
filename becomes the Terraform workspace name.

## Adding a new workspace

1. Copy an existing tfvars as template:
   ```bash
   cp deepreel-srijan-claude.tfvars my-new-workspace.tfvars
   cp deepreel-srijan-claude.secrets.env.example my-new-workspace.secrets.env
   ```

2. Edit both files with workspace-specific values.

3. Create the Terraform workspace and apply:
   ```bash
   cd ../hosts/aws-ec2/terraform
   terraform workspace new my-new-workspace
   set -a; source ../../../workspaces/my-new-workspace.secrets.env; set +a
   terraform apply -var-file=../../../workspaces/my-new-workspace.tfvars
   ```

## Conventions

- Name format: `<org>-<owner>-<agent>` (e.g., `deepreel-srijan-claude`,
  `personal-srijan-pi`).
- `.tfvars` files are committed; `.secrets.env` files are NOT
  (covered by this directory's .gitignore).
- Local Terraform state (`terraform.tfstate*` under `hosts/*/terraform/`)
  is also gitignored; back up via 1Password if it matters.
```

- [ ] **Step 4: workspaces/.gitignore**

Create `workspaces/.gitignore`:

```
# Real secrets files (per workspace)
*.secrets.env
!*.secrets.env.example

# Terraform state artifacts (if accidentally placed here)
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl

# Other
.DS_Store
```

- [ ] **Step 5: Commit all workspace files**

```bash
git add workspaces/
git commit -m "Add workspaces/ with v1 deepreel-srijan-claude tfvars

Includes .tfvars template, .secrets.env.example (real .secrets.env
gitignored), README explaining the workflow, and .gitignore.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 10: End-to-end provisioning and verification

Goal: run the full provisioning end-to-end for the v1 workspace and execute the go-live checklist from spec §8.1.

### Task 10.1: Pre-flight checks

**Files:** none (read-only)

- [ ] **Step 1: Verify AWS CLI access**

```bash
aws sts get-caller-identity
```

Expected: returns the deepreel AWS account ID and your IAM user ARN.

- [ ] **Step 2: Verify Tailscale OAuth client exists**

Check the Tailscale admin console: Settings → OAuth Clients. Confirm you have a client with scopes `auth_keys` and `devices`. If not, create one.

- [ ] **Step 3: Populate workspace secrets**

```bash
cp workspaces/deepreel-srijan-claude.secrets.env.example \
   workspaces/deepreel-srijan-claude.secrets.env
vi workspaces/deepreel-srijan-claude.secrets.env
```

Fill in the Tailscale OAuth values.

- [ ] **Step 4: Fill in workspace tfvars variables**

Edit `workspaces/deepreel-srijan-claude.tfvars`:
- Replace `<prod-replica-fqdn>` with the actual hostname
- Add CloudWatch log group ARNs the sandbox should be able to read
- Add deepreel repo URLs (at least `backend`, `skills`)

### Task 10.2: Terraform apply

**Files:** none (provisioning only)

- [ ] **Step 1: Initialize Terraform**

```bash
cd hosts/aws-ec2/terraform
terraform init
```

Expected: providers downloaded, no errors.

- [ ] **Step 2: Create workspace**

```bash
terraform workspace new deepreel-srijan-claude
```

- [ ] **Step 3: Load secrets into env and plan**

```bash
set -a; source ../../../workspaces/deepreel-srijan-claude.secrets.env; set +a
terraform plan -var-file=../../../workspaces/deepreel-srijan-claude.tfvars
```

Expected: plan shows 10-15 resources to create. Review carefully — no surprises.

- [ ] **Step 4: Apply**

```bash
terraform apply -var-file=../../../workspaces/deepreel-srijan-claude.tfvars
```

Expected: apply completes in ~2-3 min. Outputs show `public_ip`, `tailnet_hostname`, `instance_id`.

- [ ] **Step 5: Wait for bootstrap to complete**

The EC2 user-data runs on first boot. It clones repos, installs packages, joins Tailscale. Watch Tailscale admin console: the new node should appear within ~2-5 minutes.

If it doesn't appear within 10 minutes, break-glass via SSM and check `/var/log/sandbox-bootstrap.log`.

### Task 10.3: Execute go-live checklist

This mirrors spec §8.1. Run each command and record the result. Blockers get fixed before declaring v1 done.

- [ ] **Step 1: Network isolation**

```bash
# From your Mac (public internet, Tailscale turned off):
curl -m 5 http://$(cd hosts/aws-ec2/terraform && terraform output -raw public_ip):22
# Expected: timeout or connection refused

# From your Mac (Tailscale on):
tailscale ping $(cd hosts/aws-ec2/terraform && terraform output -raw tailnet_hostname)
# Expected: peer-to-peer ping succeeds
```

- [ ] **Step 2: Cred isolation — OS-level**

```bash
# From Tailscale, as admin:
../connect.sh
admin@dp-sandbox-...$ sudo su - agent
agent@dp-sandbox-...$ cat /etc/devbox/secrets
# Expected: Permission denied

agent@dp-sandbox-...$ env | grep -iE "aws|secret|key"
# Expected: no matches (or only non-sensitive like PATH)

agent@dp-sandbox-...$ ls -la /etc/devbox/locked/
# Expected: Permission denied (directory is 700)
```

- [ ] **Step 3: Cred-guard hook — blocked paths**

```bash
# As agent:
agent@dp-sandbox-...$ echo '{"tool":"Bash","input":{"command":"cat .env"}}' | /home/agent/.claude/hooks/cred-guard.sh
# Expected: exit 2, "blocked: ..." on stderr
echo $?  # Expected: 2

agent@dp-sandbox-...$ echo '{"tool":"Bash","input":{"command":"printenv"}}' | /home/agent/.claude/hooks/cred-guard.sh
# Expected: exit 2

agent@dp-sandbox-...$ echo '{"tool":"Bash","input":{"command":"sudo run psql"}}' | /home/agent/.claude/hooks/cred-guard.sh
# Expected: exit 0 (allowed)
```

- [ ] **Step 4: Redactor hook — redacts known key shapes**

```bash
agent@dp-sandbox-...$ echo '{"tool":"Bash","tool_result":{"stdout":"key: sk-ant-fake-PLANT-xyz","stderr":""}}' \
  | /home/agent/.claude/hooks/redactor.sh
# Expected output: contains "[REDACTED]" and does NOT contain "sk-ant-fake-PLANT-xyz"
```

- [ ] **Step 5: `with_creds` function exported in bashrc**

```bash
agent@dp-sandbox-...$ source ~/.bashrc
agent@dp-sandbox-...$ type with_creds
# Expected: "with_creds is a function"
```

- [ ] **Step 6: IAM scoping — confirm writes are denied**

Requires a global CLI secret set. In the admin window (back to admin user):
```bash
sudo bash
echo 'export AWS_ACCESS_KEY_ID=...' >> /etc/devbox/secrets         # from terraform output
echo 'export AWS_SECRET_ACCESS_KEY=...' >> /etc/devbox/secrets     # from terraform output
echo 'export AWS_DEFAULT_REGION=ap-south-1' >> /etc/devbox/secrets
chmod 600 /etc/devbox/secrets
```

Then as agent:
```bash
sudo run aws logs describe-log-groups --limit 5
# Expected: returns list

sudo run aws logs delete-log-group --log-group-name /tmp/test
# Expected: AccessDenied

sudo run aws s3 ls
# Expected: AccessDenied (no s3 permissions)
```

- [ ] **Step 7: Prod replica readonly**

Requires PROD_REPLICA_URL in /etc/devbox/secrets (as admin, append to secrets file).

```bash
sudo run psql "$PROD_REPLICA_URL" -c "SELECT 1"
# Expected: "?column?\n---\n 1"

sudo run psql "$PROD_REPLICA_URL" -c "CREATE TABLE test (id int)"
# Expected: permission denied for schema public (role is readonly)
```

- [ ] **Step 8: Tailscale phone access**

Open Tailscale app on phone, verify VPN is on. In Blink Shell (iOS) or Termius (Android):
```
ssh admin@dp-sandbox-deepreel-srijan-claude
```

Expected: shell. Exit.

- [ ] **Step 9: Port forwarding / UI review**

On the VM as agent:
```bash
agent@dp-sandbox-...$ python3 -m http.server 5173
```

On your Mac (with Tailscale on): open `http://dp-sandbox-deepreel-srijan-claude:5173` in Chrome.
Expected: directory listing.

- [ ] **Step 10: Break-glass SSM path**

From Mac:
```bash
aws ec2 associate-iam-instance-profile \
  --instance-id $(cd hosts/aws-ec2/terraform && terraform output -raw instance_id) \
  --iam-instance-profile Name=sandbox-ssm-break-glass-deepreel-srijan-claude
aws ssm start-session \
  --target $(cd hosts/aws-ec2/terraform && terraform output -raw instance_id)
# Expected: shell prompt as ssm-user

# Exit:
exit

aws ec2 disassociate-iam-instance-profile \
  --association-id $(aws ec2 describe-iam-instance-profile-associations \
    --filters Name=instance-id,Values=$(cd hosts/aws-ec2/terraform && terraform output -raw instance_id) \
    --query 'IamInstanceProfileAssociations[0].AssociationId' --output text)
```

- [ ] **Step 11: Teardown test**

```bash
cd hosts/aws-ec2/terraform
terraform destroy -var-file=../../../workspaces/deepreel-srijan-claude.tfvars
```

Expected: all resources destroyed. Then in AWS Console, search for `sandbox` tag. No results expected.

Re-apply to restore:
```bash
terraform apply -var-file=../../../workspaces/deepreel-srijan-claude.tfvars
```

### Task 10.4: Document any deviations

**Files:**
- Modify: `docs/adr/NNNN-<topic>.md` (new ADRs for any load-bearing decisions made during implementation)
- Modify: `docs/superpowers/specs/2026-04-24-yolo-sandbox-design.md` (edit in place for clarifications)

- [ ] **Step 1: Post-implementation ADR pass**

Did any load-bearing decision come up during implementation that's not covered by the existing 6 ADRs? Common candidates:

- Specific AWS AMI / instance type details (no — covered by variable defaults)
- Tailscale provider version conflicts (no — pinned)
- Any change to the "carefully" constraints from ADR 0002? (likely no)
- New pattern additions to cred-guard.json or redactor.json? (spec notes quarterly review, no ADR needed)

If yes to anything, write an ADR. If no, skip this step.

- [ ] **Step 2: Mark the plan done**

```bash
git add docs/
git commit -m "Post-implementation doc updates

Any ADRs or spec edits that came up during end-to-end provisioning
and verification.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-review (before handing off for execution)

**Spec coverage check**: every section of the spec has at least one task:

- §1 Summary — covered by all
- §2 Goals / Non-goals — covered (non-goals explicitly excluded)
- §3 Architecture — Phase 7 (Terraform) + Phase 8 (bootstrap)
- §4 Repo structure — Phases 1-3
- §5 Credential flow — Phase 4 (hooks) + Phase 6 (run wrapper)
- §6 Workflow — Phase 8 (bootstrap sets up tmux, worktrees, etc.) + Phase 10 (verification exercises the workflow)
- §7 Skills — only the symlinking infrastructure in `install.sh`; actual skill porting is non-goal
- §8 Verification — Phase 10 (Task 10.3 maps 1:1 to spec §8.1)
- §9 Residual risks — noted in spec; not implementable
- §10 Future evolution — pointer; implementation is per-workspace stamp
- §11 Open gaps — Phase 10 Task 10.4 for post-impl ADRs

**Placeholder scan**: searched for "TBD", "TODO", "implement later" — none found. Some workspace tfvars values are explicitly marked for the engineer to fill in (prod-replica-fqdn, log group ARNs, repo URLs); these are deployment inputs, not plan placeholders.

**Type consistency**: `with_creds` function name is consistent across spec §7.2, ADR 0006, and `install.sh`. `LOCKED_DIR`, `TMPDIR_CREDS`, and `GOOGLE_APPLICATION_CREDENTIALS` are used consistently across Phase 6. Hook file names (`cred-guard.sh`, `redactor.sh`) are consistent across Phase 4, Phase 5 (`settings.json.template`), and Phase 10 verification.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-24-yolo-sandbox-v1.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. Good fit because each task is well-scoped and verification is explicit.

**2. Inline Execution** — execute tasks in this session using `executing-plans`, batch execution with checkpoints for review. Better if you want to watch every step land in real time.

**Which approach?**
