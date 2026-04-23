# 0006 — Three-axis repo structure

**Status**: Accepted
**Date**: 2026-04-24

## Context

The existing Pi sandbox repo has two top-level directories for deployment modes: `docker/` (Pi on Mac Docker) and `vm/` (Pi on GCP VM). This works for two combinations but does not scale. Future plans include:

- A new agent (Claude Code), making it two agents × two hosts = four combinations
- A new host (AWS EC2 for this project; Hetzner or others possibly later)
- Multiple workspaces (deepreel-work, personal-work, future per-dev stamps when going to A+C)

The existing layout couples agent choice with host choice (one directory per combo), which means adding either axis duplicates the other. Adding a third axis (workspaces) makes the combinatorics untenable.

## Decision

Restructure into three independent axes, each its own top-level directory:

- `agents/<agent-name>/` — what agent, how it's installed, and agent-specific configuration
- `hosts/<host-name>/` — where it runs, provisioning (IaC or Dockerfile), and how to reach it
- `workspaces/<workspace-name>.tfvars` — instance-specific variables (AWS account, region, tailnet, cred paths, etc.)
- `shared/` — primitives that are agnostic of all three axes (the `run` wrapper, locking scripts, sudoers template, cred-guard pattern definitions)

Combinations are invoked by parameterized host bootstrap:

```bash
./hosts/aws-ec2/bootstrap.sh --agent claude-code --workspace deepreel-srijan-claude
./hosts/gcp-vm/bootstrap.sh --agent pi --workspace personal-srijan-pi
```

The host's bootstrap knows how to set up the OS and user accounts; it then delegates agent-specific installation to `agents/<agent>/install.sh`. Workspace variables come from the tfvars file and are consumed by both the host's Terraform code and the agent's install script.

Key invariant: **nothing workspace-specific or deepreel-specific lives in `shared/` or `agents/`.** Prod endpoints, deepreel AWS account IDs, egress domain lists — all workspace-scoped.

## Alternatives considered

**Keep the mode-based layout (status quo + add new dirs per combination):**
- `docker/` = Pi + Docker; `vm/` = Pi + GCP; new `aws/` = Claude Code + AWS.
- Rejected because adding a second agent-host combination doubles the directories and forces duplication (Claude-Code-on-Docker and Pi-on-Docker would both need Dockerfile tweaks, stored separately).

**One repo per combination:**
- `sandbox-pi-docker`, `sandbox-claude-aws`, etc.
- Rejected because the `run` wrapper, sudoers config, and cred-guard patterns are genuinely shared. Duplicating them means bugs get fixed in one repo and rot in the others.

**Shared primitives in a separate repo, consumed via git submodule:**
- `sandbox-shared` submodule pulled into `sandbox-pi-docker`, `sandbox-claude-aws`, etc.
- Rejected because submodules add operational overhead (init, update, version pinning) without a commensurate benefit at this scale.

**Monorepo with explicit packages (npm workspaces, uv workspaces, etc.):**
- Rejected as overengineered for a codebase of shell scripts, Terraform, and a handful of TypeScript extensions.

## Consequences

- Adding a new agent is additive: drop `agents/<name>/` in place with `install.sh` and any agent-specific hooks or extensions. No changes to existing agents or hosts.
- Adding a new host is additive: drop `hosts/<name>/` in place with IaC or Dockerfile and a `bootstrap.sh --agent <name>` entry point. No changes to existing hosts or agents.
- Adding a new workspace is additive: drop `workspaces/<name>.tfvars` in place. No changes to existing workspaces, agents, or hosts.
- The cred-guard patterns and redactor patterns become `shared/patterns/*.json` — a single source of truth both Pi (TS extension) and Claude Code (shell hook) read from. Updates propagate to all agents without duplication.
- The existing `docker/` and `vm/` directories are renamed to `hosts/docker-mac/` and `hosts/gcp-vm/` respectively; the existing Pi extensions move from `shared/extensions/` to `agents/pi/extensions/`. Behavior is unchanged; only paths move.
- Future readers looking at a new agent-host combination do not have to grep the repo to find what applies — the layout tells them.
- When someone later adds a Codex agent or a Hetzner host, the precedent is clear and the addition does not require coordination with other combinations.
