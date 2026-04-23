# YOLO Coding-Agent Sandbox — Design Spec

**Date**: 2026-04-24
**Status**: Approved (brainstorm output; ready for implementation planning)
**Author**: srijan@deepreel.com (with Claude)

## 1. Summary

A dedicated AWS EC2 sandbox VM for running coding agents (initially Claude Code) in `--dangerously-skip-permissions` / YOLO mode, with credential isolation strong enough that the low-friction operating mode is safe. The VM is reachable only via Tailscale (Mac + phone), has no public SSH, and lives in a dedicated VPC inside the existing deepreel AWS account with carefully-scoped read-only access to prod resources (replica DB, CloudWatch logs) and no path to prod writes.

The existing Pi-coding-agent sandbox at this repo provides the foundational pattern (`sudo run` privilege-drop wrapper, locked `.env` files, cred-guard hook). This project refactors the repo to cleanly support multiple agents × multiple hosts × multiple workspaces, then adds a new host (AWS EC2) and a new agent (Claude Code) as the v1 target.

## 2. Goals and non-goals

### Goals

- YOLO-mode Claude Code usable without permission prompts for routine development work
- Credential isolation strong enough that accidental exposure to Claude's context window is prevented by OS-level enforcement for sensitive data, with hook-level enforcement as a second layer
- Remote access from Mac and phone, no public SSH
- Read-only access to prod replica DB and CloudWatch logs; **zero path to prod writes**
- Repo structure supports future extension to other agents (Pi, Codex), other hosts (Hetzner, GCP, Docker-local), and other workspaces (personal use, per-dev stamps) without a rewrite
- ADRs capture load-bearing decisions so future readers understand why each constraint exists

### Non-goals (v1)

- Multi-user / shared sandbox (v1 is solo; future A+C plan documented in §9)
- Strict per-domain egress allowlist (accepted as impractical for deepreel's breadth; see ADR 0004)
- Ephemeral per-task VMs (accepted as overkill; mitigated by ephemeral worktrees on a stateful VM)
- DevContainer-based isolation (rejected in favor of OS-level pattern; see ADR 0005)
- Automated cred loading from AWS Secrets Manager or 1Password CLI (deferred to post-v1)
- Port of deepreel Claude Code skills (skills work is a parallel track after the base VM works; see §7)

## 3. Architecture

### 3.1 Physical layout

```
┌──────────────┐        ┌──────────────┐
│  Mac         │        │  Phone       │
│  - Tailscale │        │  - Tailscale │
│  - SSH       │        │  - Blink/    │
│    client    │        │    Termius   │
└──────┬───────┘        └──────┬───────┘
       │                       │
       └───── tailnet ─────────┘
                  │
                  │ (tailscale ssh, peer-to-peer)
                  ▼
       ┌──────────────────────────────────────┐
       │  EC2 in ap-south-1                   │
       │  (deepreel account, dedicated VPC)   │
       │  - public IP, inbound deny-all       │
       │  - IMDSv2 enforced, no instance role │
       │  - egress allowlisted (broad HTTPS)  │
       │                                      │
       │  Users on the box:                   │
       │  - admin  (you, sudo, cred mgmt)     │
       │  - agent  (Claude runs here)         │
       │                                      │
       │  Services:                           │
       │  - sshd disabled (tailscale ssh only)│
       │  - tailscaled (joins tailnet)        │
       │  - Docker (for dp-pg, dp-redis)      │
       │  - Claude Code (runs as agent user)  │
       └──────────────────────────────────────┘
                  │
                  ▼
     ┌─────────────────────────────────────┐
     │ External targets                    │
     │ - github.com (git, PAT)             │
     │ - api.anthropic.com (Claude auth)   │
     │ - registry.npmjs.org, pypi.org      │
     │ - prod-replica.*.rds.amazonaws.com  │
     │ - logs.ap-south-1.amazonaws.com     │
     │ - login.tailscale.com               │
     │ - arbitrary 443/tcp (broad HTTPS)   │
     └─────────────────────────────────────┘
```

### 3.2 Key invariants

- VM is unreachable from the public internet (no inbound SG rules, no SSH port exposed, sshd disabled in favor of tailscale ssh).
- VM cannot reach prod resources *except* the already-public replica — no VPC peering, no transit gateway to prod.
- `agent` user cannot read credential files by direct file access (OS-enforced, `root:600`).
- Non-HTTPS outbound is denied (egress SG + host iptables). HTTPS is broadly allowed per ADR 0004.
- Network egress for `agent` cannot bypass the broad-HTTPS rule via tunneling over allowed protocols — nothing we can enforce beyond hook + redactor vigilance, hence ADR 0001's explicit residual risk.

### 3.3 Future-state compatibility

Directory layout (§4) separates agent-specific, host-specific, and workspace-specific concerns. Adding other agents/hosts/workspaces is additive — no cross-cutting changes. Migration path to A+C (multiple devs with shared credential store) is documented in §9.

## 4. Repo structure

```
sandbox/
├── README.md                            # top-level overview
│
├── shared/                              # 100% agent+host+workspace agnostic
│   ├── scripts/
│   │   ├── run                          # [unchanged] sudo-invoked cred loader
│   │   ├── lock-env                     # [unchanged]
│   │   └── unlock-env                   # [unchanged]
│   ├── sudoers.d/agent                  # [unchanged]
│   ├── tmuxinator/dev.yml               # [unchanged]
│   ├── editor/                          # [NEW] portable nvim/tmux configs
│   └── patterns/                        # [NEW] single source of truth
│       ├── cred-guard.json              # file + bash regex patterns
│       └── redactor.json                # output redaction patterns
│
├── agents/                              # "what agent, and how it's configured"
│   ├── pi/
│   │   ├── extensions/                  # [moved] cred-guard.ts, tmux-tools.ts
│   │   │                                # rewired to read shared/patterns/cred-guard.json
│   │   ├── skills/                      # [moved from shared/skills/]
│   │   └── install.sh                   # [NEW] Pi install on any host
│   │
│   └── claude-code/                     # [NEW] v1 agent
│       ├── hooks/
│       │   ├── cred-guard.sh            # PreToolUse — reads shared/patterns/cred-guard.json
│       │   └── redactor.sh              # PostToolUse — reads shared/patterns/redactor.json
│       ├── settings.json.template       # hook wiring
│       └── install.sh                   # installs Claude Code, writes settings.json,
│                                        # adds `with_creds` export to agent's .bashrc
│
├── hosts/                               # "where it runs + how to reach it"
│   ├── docker-mac/                      # [renamed from docker/]
│   ├── gcp-vm/                          # [renamed from vm/]
│   └── aws-ec2/                         # [NEW] v1 target
│       ├── terraform/
│       │   ├── main.tf                  # VPC, subnet, IGW, EC2, SG, EIP
│       │   ├── tailscale.tf             # ephemeral tailnet key
│       │   ├── iam.tf                   # readonly IAM user for CloudWatch
│       │   ├── variables.tf             # workspace-scoped vars
│       │   ├── outputs.tf
│       │   └── versions.tf
│       ├── bootstrap.sh                 # runs on EC2 post-provision
│       │                                # takes --agent <name> --workspace <name>
│       ├── connect.sh                   # `tailscale ssh` wrapper
│       └── README.md                    # setup, prerequisites, teardown
│
├── workspaces/                          # [NEW] instance-specific config
│   ├── deepreel-srijan-claude.tfvars    # v1 workspace
│   ├── deepreel-srijan-claude.secrets.env  # gitignored
│   ├── README.md                        # how to add a new workspace
│   └── .gitignore
│
└── docs/
    ├── superpowers/specs/               # design docs (this file)
    └── adr/                             # architecture decision records
```

### 4.1 Invariants

- **Nothing deepreel-specific in `shared/` or `agents/`.** Prod replica endpoints, deepreel AWS account IDs, deepreel egress domains — all workspace-scoped.
- **`shared/patterns/*.json` is the single source of truth** for cred-guard and redactor patterns. Both Pi (TypeScript extension) and Claude Code (shell hook) read from it.
- **Host bootstraps are agent-agnostic.** `hosts/aws-ec2/bootstrap.sh --agent claude-code` delegates agent-install to `agents/claude-code/install.sh`.

### 4.2 Migration checklist (Pi sandbox stays functional)

**Moves (no behavior change):**
- `docker/` → `hosts/docker-mac/`
- `vm/` → `hosts/gcp-vm/`
- `shared/extensions/*.ts` → `agents/pi/extensions/`
- `shared/skills/` → `agents/pi/skills/`

**Edits:**
- `agents/pi/extensions/cred-guard.ts`: read from JSON at `shared/patterns/cred-guard.json`
- `hosts/docker-mac/Dockerfile`: update paths post-move
- `hosts/gcp-vm/bootstrap.sh`: update paths; accept `--agent` parameter

**New (v1 build):**
- `shared/patterns/{cred-guard,redactor}.json`
- `agents/pi/install.sh`
- `agents/claude-code/` (entire tree)
- `hosts/aws-ec2/` (entire tree)
- `workspaces/` (entire tree)
- `docs/` (this spec + ADRs)

## 5. Credential flow

Three concurrent flows. Each invariant is load-bearing.

### 5.1 Flow A: Provisioning

```
admin on Mac → scp/copy-paste → EC2 admin tmux window
  $ sudo vi /etc/devbox/secrets            # global CLI creds
  $ cd /workspace/core/backend
  $ sudo vi .env                           # project creds
  $ sudo lock-env                          # root:600 in /etc/devbox/locked/
```

**Invariant after A**: every secret is `root:600` in `/etc/devbox/` or `/etc/devbox/locked/`. `agent` cannot read any directly.

### 5.2 Flow B: Claude invokes a privileged command

```
Claude (as agent) → bash tool: `sudo run psql "$PROD_REPLICA_URL" -c "..."`
   │
   ▼ PreToolUse cred-guard hook
       - reads shared/patterns/cred-guard.json
       - bash_patterns match → exit 2 blocks
       - no match (sudo run allowed) → exit 0
   │
   ▼ /usr/local/bin/run (runs as root via sudoers)
       1. source /etc/devbox/locked/secrets
       2. source $(pwd)'s locked .env if present
       3. copy locked creds/ to tmpdir, chown agent, export GOOGLE_APPLICATION_CREDENTIALS etc.
       4. gosu agent "$@"    ← privs dropped before exec
       5. on subprocess exit: rm -rf tmpdir
   │
   ▼ subprocess stdout
   │
   ▼ PostToolUse redactor hook
       - reads shared/patterns/redactor.json
       - replaces matches with [REDACTED]
   │
   ▼ Claude's context (redacted)
```

**Invariants after B**: secrets exist only in the transient process environment of the `run`-spawned subprocess. `agent`'s shell never has them. Even if subprocess prints a secret, redactor scrubs before Claude sees it.

### 5.3 Flow C: Defense layers when Claude tries to break out

| Layer | Mechanism | Failure mode | Catches |
|-------|-----------|--------------|---------|
| 1 | File perms (`root:600`) | OS-enforced, cannot be bypassed by hook bugs | Direct `cat .env`, `cat /etc/devbox/secrets` |
| 2 | Sudoers (only `sudo run *`) | OS-enforced | `sudo bash`, `sudo cat`, `sudo vi .env` |
| 3 | PreToolUse cred-guard hook | Claude-enforced; regex-based | `printenv`, `env`, Python `os.environ`, `/proc/*/environ` |
| 4 | PostToolUse redactor hook | Claude-enforced; regex-based | Accidental secret echoes in tool output |
| 5 | Egress deny non-HTTPS | Network-enforced | Exfil via SMTP, IRC, raw TCP, SSH-out |

Layers 1-2 are OS/infra-level and cannot be bypassed by a buggy hook. Layers 3-4 are Claude-enforced; if one has a gap, the others still protect. Layer 5 is network-level; HTTPS exfil is the accepted residual risk per ADR 0004.

### 5.4 `creds/` directory (multi-file, non-env-var secrets)

Service-account JSONs, PEM certs, and similar multi-file credentials live in `core/creds/` on the Mac and are needed by backend subprocesses at runtime. On the VM, they follow the same OS-level isolation as `.env` files:

- Locked at `/etc/devbox/locked/projects/core/creds/` as `root:600`
- `run` wrapper copies them to a per-invocation tmpdir, `chown` to agent, sets `GOOGLE_APPLICATION_CREDENTIALS` etc., cleans up on exit
- `agent` user cannot read them directly; subprocess reads from tmpdir transparently

### 5.5 Break-glass

Tailscale daemon can fail. SSM Session Manager is the break-glass access path: IAM-authenticated, no open ports. Because SSM requires an IAM path on the instance, and ADR 0002 constraint 2 says no instance profile is attached in normal operation, break-glass is a three-step process:

1. `aws ec2 associate-iam-instance-profile` — attach the `AmazonSSMManagedInstanceCore`-only profile
2. `aws ssm start-session --target <instance-id>` — shell session
3. `aws ec2 disassociate-iam-instance-profile` — detach when done

If this turns out to be too painful in practice, a new ADR can supersede ADR 0003 to allow a permanently-attached SSM-only profile (threat reduction is minor; see ADR 0003's decision section).

## 6. Day-to-day workflow

### 6.1 VM filesystem

```
/workspace/
└── core/                          # mirrors ~/work/deepreel/core/ locally
    ├── creds/                     # shadowed to /etc/devbox/locked/projects/core/creds/
    ├── backend/
    │   ├── .git/
    │   ├── <main checkout>
    │   └── .worktrees/
    │       ├── feature-seo/
    │       └── task-signup-bug/
    ├── seo-content-agent/
    │   └── .worktrees/
    ├── frontend/
    └── ...

/etc/devbox/
├── secrets                        # root:600 — global CLI creds
└── locked/projects/
    └── core/
        ├── creds/                 # multi-file secrets (SA JSONs)
        ├── backend/
        │   ├── .env
        │   └── .worktrees/<name>/.env  # per-task, independent from repo-level
        └── ...
```

Bootstrap clones each deepreel service repo individually into `/workspace/core/<repo>`; the list of repos comes from the workspace tfvars file.

### 6.2 Session start

```bash
# From Mac or phone:
$ tailscale ssh admin@dp-sandbox
admin@dp-sandbox:~$ tmuxinator start dev

# Inside tmux, admin window:
$ cd /workspace/core/backend
$ git fetch && git checkout main && git pull
$ git worktree add .worktrees/task-seo-fix -b task/seo-fix

# Seed task .env (independent copy — not a symlink):
$ sudo unlock-env .worktrees/task-seo-fix
$ sudo cp /etc/devbox/locked/projects/core/backend/.env \
          /workspace/core/backend/.worktrees/task-seo-fix/.env
$ sudo vi /workspace/core/backend/.worktrees/task-seo-fix/.env  # edit as needed
$ cd .worktrees/task-seo-fix && sudo lock-env

# Switch to claude window (agent user):
agent@dp-sandbox:~$ cd /workspace/core/backend/.worktrees/task-seo-fix
agent@dp-sandbox:~$ claude --dangerously-skip-permissions
```

### 6.3 During the session

- DB reads: `sudo run psql "$PROD_REPLICA_URL" -c "..."` — `run` loads the locked URL
- CloudWatch: `sudo run aws logs tail /ecs/deepreel-backend --since 1h`
- Git push: `sudo run git push origin task/seo-fix`
- UI review: dev server on VM binds `0.0.0.0`, Mac browser hits `http://dp-sandbox:<port>` (Tailscale MagicDNS)

### 6.4 End of task

```bash
# admin window:
$ cd /workspace/core/backend
$ git worktree remove .worktrees/task-seo-fix
$ sudo rm /etc/devbox/locked/projects/core/backend/.worktrees/task-seo-fix/.env
```

### 6.5 Teardown

```bash
# On Mac:
$ cd ~/fun/sandbox/hosts/aws-ec2/terraform
$ terraform workspace select deepreel-srijan-claude
$ terraform destroy -var-file=../../../workspaces/deepreel-srijan-claude.tfvars
```

Destroys EC2, EIP, SGs, VPC, IAM user, Tailscale node. Leaves tailnet itself intact.

## 7. deepreel Claude Code skills

### 7.1 Where skills live

On the VM, at `/workspace/core/skills/`. The skills repo is one of the per-service deepreel repos the bootstrap clones into the `core/` meta-directory (alongside `backend/`, `seo-content-agent/`, etc.). Symlinked into `/home/agent/.claude/skills/` by `agents/claude-code/install.sh`.

### 7.2 Portability via `with_creds` convention

Skills are shared between Mac and VM (same files run in both environments — a sandbox-compatibility helper cannot be VM-specific, or local use breaks). To avoid coupling skills to sandbox internals, skills use an environment-defined function `with_creds`:

**In each skill's `run.sh` (or sourced once via `core/skills/_common/creds.sh`):**
```bash
type -t with_creds >/dev/null || with_creds() { "$@"; }   # default no-op
with_creds psql "$PROD_REPLICA_URL" -c "$query"
```

**On the VM, `agents/claude-code/install.sh` writes to `/home/agent/.bashrc`:**
```bash
with_creds() { sudo /usr/local/bin/run "$@"; }
export -f with_creds
```

- On the VM: `with_creds` inherited from shell env, wraps via `sudo run`
- On Mac: `with_creds` not set by environment, skill's default no-op runs command directly (creds come from user's shell env as today)

Skills know the protocol (function name `with_creds`); they do not know the implementation (`/usr/local/bin/run`, sandbox paths). Mac requires no installation.

### 7.3 Porting effort

~5-10 min per skill: add the `type -t` check (or source `_common/creds.sh`), wrap each privileged command call with `with_creds`. Estimate ~30-45 min across all deepreel skills. Not a v1 blocker — port after the base VM works; first real task is to port `/deepreel-db` and validate end-to-end.

## 8. Verification and monitoring

### 8.1 Go-live checklist (all must pass before v1 declared usable)

**Network:**
- [ ] `nmap dp-sandbox.tail....ts.net` from untrusted net → 0 open ports
- [ ] `curl http://<vm-public-ip>:22` from external → timeout/refused
- [ ] VPC has no peering connections to default VPC
- [ ] From VM: `ssh -v github.com` (port 22 out) → blocked

**Credential isolation:**
- [ ] As `agent`: `cat /etc/devbox/secrets` → permission denied
- [ ] As `agent`: `env | grep AWS` → empty
- [ ] Claude bash: `cat .env` → blocked with block reason
- [ ] Claude bash: `printenv` → blocked
- [ ] Claude bash: `python -c "import os; print(os.environ)"` → blocked
- [ ] Claude Read: `/home/agent/.aws/credentials` → blocked

**Cred loading:**
- [ ] `sudo run env | grep PROD_REPLICA_URL` → value visible (subprocess only)
- [ ] `sudo run python -c "print(os.environ['PROD_REPLICA_URL'])"` → value
- [ ] `sudo run python -c "from google.cloud import storage; storage.Client()"` → succeeds
- [ ] After `sudo run` exits: `ls /tmp/run-*` → no orphans

**Redactor:**
- [ ] Plant `TEST_FAKE_sk-ant-PLANT-xyz` in secrets; `sudo run echo $TEST` → output shows `[REDACTED]`

**IAM scoping:**
- [ ] `sudo run aws logs tail /ecs/deepreel-backend` → succeeds
- [ ] `sudo run aws logs delete-log-group` → AccessDenied
- [ ] `sudo run aws s3 ls` → AccessDenied
- [ ] `sudo run aws ec2 describe-instances` → AccessDenied

**Prod replica readonly:**
- [ ] `sudo run psql "$PROD_REPLICA_URL" -c "SELECT 1"` → succeeds
- [ ] `sudo run psql "$PROD_REPLICA_URL" -c "INSERT..."` → permission denied

**Access:**
- [ ] `tailscale ssh admin@dp-sandbox` from Mac → shell
- [ ] Blink Shell on phone → shell
- [ ] `http://dp-sandbox:<port>` in Mac browser → loads dev server
- [ ] `aws ssm start-session --target <id>` → shell (break-glass)

**Teardown:**
- [ ] `terraform destroy` → zero orphans; verify in AWS console

**Skills (post-port):**
- [ ] `/home/agent/.claude/skills/` has symlinks to `/workspace/core/skills/*`
- [ ] `/deepreel-db` in a Claude session → returns real data

### 8.2 Ongoing monitoring

- **First-week CloudTrail review**: filter by the readonly IAM user, confirm only `logs:*` reads, no write APIs
- **Monthly**: `terraform plan` drift check, AWS Cost Explorer by `Environment=sandbox` tag, `tailscale status` review
- **Quarterly**: review `shared/patterns/*.json` against current vendor secret shapes; add patterns as needed
- **Alerts**: AWS Budgets at $50/mo and $100/mo

### 8.3 Cost (monthly, ap-south-1)

| Resource | Spec | Monthly |
|----------|------|---------|
| EC2 t3.large | 2 vCPU / 8 GB | ~$65 |
| EBS gp3 | 40 GB | ~$3 |
| EIP (attached) | — | $0 |
| Data transfer out | ~10 GB/mo est | ~$1 |
| **Total** | | **~$70/mo** |

Levers: t3.medium (~$35/mo); stop when not in use (compute $0, storage $3/mo); spot (~30% off, kills session on interrupt).

## 9. Residual risks (accepted)

1. **Broad HTTPS egress** — cred exfiltration possible if both cred-guard and redactor fail. ADR 0004.
2. **Cred-guard is regex-based** — novel obfuscation (base64-encoded commands) could evade. Mitigated by redactor.
3. **Redactor is pattern-based** — new vendor key shapes won't scrub until we add the pattern. Mitigated by quarterly review.
4. **Single-tenant v1** — no per-user audit attribution. Resolved by A+C migration.
5. **Stateful VM** — long-term state accumulation. Mitigated by worktrees + weekly admin hygiene.
6. **Tailnet SSO single point of trust** — enforce 2FA on `srijan@deepreel.com` SSO.
7. **EBS encryption** — use customer-managed KMS key with logged usage.
8. **Skills require sandbox-compatibility maintenance** — fail-loud on VM when `with_creds` isn't wrapped.

## 10. Future evolution

Migration paths documented so nothing is accidentally locked in:

- **Personal-use variant**: new workspace tfvars, `terraform workspace new`, apply. ~20 min.
- **Add a teammate (A+C)**: teammate creates their own workspace tfvars, runs `terraform apply` against their own creds. ADR 0002 constraints still apply.
- **Migrate to dedicated sandbox AWS account (A)**: new account, reconfigure provider, re-apply. Tailscale nodes migrate as auth keys re-issued.
- **Add a new agent (Codex, Cursor CLI)**: new `agents/<name>/` dir, port cred-guard to the agent's hook mechanism, export `with_creds` in its install.
- **Add a new host (Hetzner, GCP for personal)**: new `hosts/<name>/` with its own IaC. `shared/` unchanged.
- **Egress tightening (future)**: move from ADR 0004's broad HTTPS to a DNS-based filter (Cloudflare Zero Trust, NextDNS) once domain list stabilizes.

## 11. Open gaps (to resolve in implementation plan)

1. **How canonical locked files get onto the VM initially** — manual paste vs 1Password CLI vs Secrets Manager pulled-at-provision
2. **Admin-clone auto-update** — cron vs manual-only (leaning manual for v1)
3. **Disk size default** — 40 GB proposed; resize path if insufficient
4. **Cred-guard and redactor JSON schema** — define in plan before writing pattern files

## 12. ADR index

- [ADR 0001 — Threat model](../adr/0001-threat-model.md)
- [ADR 0002 — AWS account C with "carefully" constraints](../adr/0002-aws-account-c-with-carefully-constraints.md)
- [ADR 0003 — Tailscale over SSM](../adr/0003-tailscale-over-ssm.md)
- [ADR 0004 — Egress: broad HTTPS allowlist](../adr/0004-egress-broad-https-allowlist.md)
- [ADR 0005 — OS-level isolation over devcontainer](../adr/0005-os-level-isolation-over-devcontainer.md)
- [ADR 0006 — Three-axis repo structure](../adr/0006-three-axis-repo-structure.md)
