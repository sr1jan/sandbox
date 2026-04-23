# 0005 — OS-level isolation over devcontainer

**Status**: Accepted
**Date**: 2026-04-24

## Context

The sandbox needs to isolate credentials from the coding agent — that is, the agent process (Claude Code) must not be able to read credential files or see environment variables that contain secrets. Three architecturally distinct approaches were considered:

1. **DevContainer-based isolation.** Claude Code runs inside a Docker devcontainer on the VM. Anthropic ships a reference devcontainer for Claude Code with its own firewall rules and credential-mount pattern. Isolation is container-level (namespaces, filesystems, network).

2. **OS-level isolation with a privileged helper** (the Pi sandbox pattern already in this repo). One VM, two Linux users (`admin` and `agent`), locked-down sudoers configuration that only allows one thing: `sudo /usr/local/bin/run <cmd>`. The `run` wrapper loads secrets as root, then drops privileges via `gosu agent` before exec'ing the command. Isolation is filesystem-permission-level (secrets are `root:600`) plus Linux user separation.

3. **Ephemeral VM per task.** Every Claude session provisions a fresh EC2 from a pre-baked AMI via Packer, runs to completion, and is destroyed. No state carries across tasks.

## Decision

Use option 2 — OS-level isolation with the `sudo run` wrapper — as the primary isolation mechanism. Build on the Pi sandbox pattern already in this repo.

## Alternatives considered

**Option 1 — DevContainer:**
- Pros: Anthropic's reference ships with a baked-in firewall; container-level isolation is well-understood; destroy-the-container model is clean.
- Cons: nested containerization (Docker-in-Docker needed if dp-pg/dp-redis also run on the host); introduces a different mental model from the existing Pi sandbox, eliminating code reuse; harder to reason about "where does this secret live right now" when there are two levels of indirection.
- Rejected because the primary value prop (existing pattern + code reuse) outweighs the marginal benefits of container-level isolation. The `sudo run` pattern, combined with ADR 0002's constraints, achieves the threat-model goals in ADR 0001.

**Option 3 — Ephemeral per-task VM:**
- Pros: strongest isolation achievable (no state carryover, no session-to-session contamination); audit trail is clean (one instance per task).
- Cons: Packer + AMI versioning overhead; 2-3 minute spin-up per task kills interactive workflow; overkill for solo use on trusted first-party code.
- Rejected as overkill for v1. Mitigated in option 2 by using ephemeral git worktrees per task (stateful VM, ephemeral workspaces) to recover most of the cleanliness benefit.

## Consequences

- The existing Pi sandbox primitives (`shared/scripts/run`, `lock-env`, `unlock-env`, sudoers config) are reused as-is. No code to rewrite; only paths to reorganize (per ADR 0006).
- Docker continues to run on the host for dp-pg/dp-redis; no nested containerization.
- The `creds/` multi-file directory handling (spec §5.4) requires extending `run` to copy files to a per-invocation tmpdir, because filesystem permissions alone can't give a subprocess access to a directory the `agent` user can't read.
- Mess accumulates on the VM across sessions (installed packages, test artifacts, etc.). Mitigated by:
  - Per-task git worktrees created fresh and torn down after use
  - Admin-initiated weekly hygiene (`docker system prune`, apt update)
- Cred-guard hook (Claude-enforced) and output redactor (Claude-enforced) become the secondary layers that catch cases where OS-level perms aren't sufficient — e.g., `env`, `printenv`, `cat /proc/$$/environ`. These are belt-and-suspenders; if a hook has a bug, filesystem perms still protect.
- Future migration to option 3 (ephemeral VMs) is possible later if threat posture changes — it would mean adding a Packer pipeline and wrapping `terraform apply` around Claude sessions. Not planned.
