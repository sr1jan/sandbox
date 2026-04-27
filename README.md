# Sandbox — Cred-Isolated Coding Agent Environments

Run coding agents (Claude Code, Pi) on a private VM where they can write
code and call `gh` / `aws` / `psql` — but **can't** read `.env` files,
see credentials in `env`, or reach the internet outside an allowlist.

```
   YOU                                AWS EC2 sandbox
   ───                                ────────────────

   workspaces/                        ┌─ ubuntu (admin)
   ├ <ws>.secrets.env  ──┐            │   sudo for ops & secret mgmt
   └ <ws>.tfvars        ─┤            │
                         ▼            ├─ agent (YOLO claude)
                    terraform apply ──┤   $ claude
                     (one-shot)       │   • cred-guard hook (blocks .env)
                                      │   • redactor hook (scrubs keys)
   power.sh sync ────────────────────►│
   (idempotent reconcile)             ├─ /etc/devbox/locked/  (root:600)
                                      │   secrets, project .envs
   tailscale ssh ────────────────────►│
   (the only ingress —                ├─ /workspace/
    no public SSH; ACL-scoped)        │   ├ core/  (work repos)
                                      │   └ fun/   (personal repos)
                                      │
                                      └─ outbound: 443/80/53/5432/41641
                                          (SG + iptables allowlist)
```

## Five layers of credential isolation

1. **OS file perms** — `/etc/devbox/locked/secrets` and per-project locked
   `.env` files are `root:root 600`. Agent can't read them directly.
2. **Sudoers** — agent's only sudo entry is `/usr/local/bin/run <cmd>`,
   which sources secrets as root and drops priv back to agent (via `gosu`)
   before exec.
3. **cred-guard hook** — blocks Bash commands matching credential-exposure
   patterns (`cat .env`, `printenv`, `sudo bash`, `cat /etc/devbox/...`).
4. **Redactor hook** — scrubs secret-shaped strings (`sk-ant-*`, `ghp_*`,
   `AKIA*`, `Bearer …`) from tool output before it reaches the agent.
5. **Egress allowlist** — SG + iptables restrict outbound to
   `443/80/53/5432/41641` only. No path to prod admin APIs.

## Quick start (AWS EC2)

**Prereqs**

- AWS CLI configured (`aws sts get-caller-identity` works)
- Tailscale account, OAuth client with `auth_keys:write` + `devices:read+write`,
  ACL tag `tag:claude-sandbox` defined with you as owner
- GitHub fine-grained PAT scoped to the private repos you want cloned

**Provision**

```bash
# 1. Per-workspace config (gitignored)
cd workspaces
cp deepreel-srijan-claude.secrets.env.example my-ws.secrets.env
vi my-ws.secrets.env       # Tailscale OAuth + GH_TOKEN + DB creds
cp deepreel-srijan-claude.tfvars my-ws.tfvars
vi my-ws.tfvars            # which repos to clone

# 2. Provision (one-shot, ~5 min)
cd ../hosts/aws-ec2/terraform
terraform init
terraform workspace new my-ws
set -a; source ../../../workspaces/my-ws.secrets.env; set +a
terraform apply -var-file=../../../workspaces/my-ws.tfvars

# 3. Connect
cd ..
./connect.sh                            # SSH as ubuntu (sudo-capable)
./connect.sh --user agent               # SSH as agent
```

The bootstrap installs Claude Code + hooks, joins Tailscale, populates
secrets at `/etc/devbox/locked/secrets`, and `gh repo clone`s every entry
in `deepreel_repo_urls` (→ `/workspace/core/`) and `fun_repo_urls` (→
`/workspace/fun/`).

## Day-to-day commands

**On the box** (after `tailscale ssh`):

| | |
|---|---|
| `tx` | `tmuxinator start dev` **as agent** — admin + backend windows |
| `tx fun` | Personal projects layout |
| `sudo sync-secrets` | Idempotent upsert into `/etc/devbox/locked/secrets` |
| `sudo run <cmd>` | Invoke `<cmd>` with secrets sourced, as agent |

**From your Mac**:

| | |
|---|---|
| `./hosts/aws-ec2/connect.sh` | SSH (defaults to ubuntu) |
| `./hosts/aws-ec2/power.sh status` | Running / stopped |
| `./hosts/aws-ec2/power.sh stop` | Stop EC2 (compute = $0/hr; EBS still bills) |
| `./hosts/aws-ec2/power.sh start` | Start EC2 (Tailscale auto-reconnects) |
| `./hosts/aws-ec2/power.sh sync` | Reconcile box without replacing it (clone new repos in tfvars, refresh scripts) |
| `./hosts/aws-ec2/sync-aws-keys.sh` | Re-inject AWS_* if rotated, no apply |

## What the agent can / can't do

| Action | Allowed | How / why blocked |
|---|---|---|
| Read/write project code | ✅ | Direct file access |
| Run with credentials | ✅ | `sudo run gh \| aws \| psql ...` |
| Read `.env` / `/etc/devbox/locked/*` | ❌ | OS file perms |
| `cat .env`, `env`, `printenv`, etc. | ❌ | cred-guard hook (exit 2) |
| `sudo bash`, `sudo cat ...` | ❌ | sudoers + cred-guard |
| Outbound to arbitrary host:port | ❌ | SG + iptables allowlist |
| Reach prod write APIs | ❌ | Sandbox IAM user is read-only; no instance profile |

## Repo layout

```
sandbox/
├── shared/
│   ├── scripts/        # run, sync-secrets, with_creds, tx, lock-env, unlock-env
│   ├── sudoers.d/      # agent's sudo rules
│   ├── tmuxinator/     # dev.yml (work), fun.yml (personal)
│   ├── patterns/       # cred-guard.json, redactor.json (single source)
│   └── secrets.example
│
├── agents/
│   ├── claude-code/    # PreToolUse + PostToolUse shell hooks + install.sh
│   └── pi/             # TS extensions for Pi
│
├── hosts/
│   ├── aws-ec2/        # terraform/, bootstrap.sh.tpl, power.sh, connect.sh, sync-aws-keys.sh
│   ├── docker-mac/     # Mac Docker mode
│   └── gcp-vm/         # GCP VM bootstrap
│
├── workspaces/         # per-workspace .tfvars + .secrets.env (gitignored)
└── docs/
    ├── superpowers/specs/2026-04-24-yolo-sandbox-design.md
    └── adr/            # architecture decisions
```

## Supported

- **Agents**: Claude Code (primary, YOLO mode safe by construction), Pi
- **Hosts**: `aws-ec2` (production sandbox), `gcp-vm`, `docker-mac`

## Mobile access

1. Install the Tailscale app, sign in with the same Google account
2. Install an SSH client (Blink Shell on iOS, Termius on Android)
3. `ssh ubuntu@dp-sandbox-<workspace>` — Tailscale handles auth via your
   tailnet identity (no SSH keys / passwords)

## Adding things

- **New host** → `hosts/<name>/bootstrap.sh --agent <name>`. `shared/` unchanged.
- **New agent** → `agents/<name>/install.sh` + hooks/templates. Existing hosts pick it up via `--agent`.
- **New workspace** → `workspaces/<name>.{tfvars,secrets.env}`. See [workspaces/README.md](workspaces/README.md).

See [design spec](docs/superpowers/specs/2026-04-24-yolo-sandbox-design.md)
and [ADRs](docs/adr/) for the full architecture.
