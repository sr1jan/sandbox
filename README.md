# Sandbox — Cred-Isolated Coding Agent Environments

Sandboxed development environments for running coding agents (Pi, Claude
Code) with strong credential isolation. Runs on Mac (Docker), GCP VMs,
and AWS EC2 — any combination of agent × host, parameterized by
per-workspace config.

See [design spec](docs/superpowers/specs/2026-04-24-yolo-sandbox-design.md)
and [ADRs](docs/adr/) for the full architecture.

## Security model

Three OS-enforced layers + two Claude-Code/Pi-enforced layers prevent
the agent from seeing credentials:

1. **File permissions** — `/etc/devbox/locked/secrets` and per-project
   locked `.env` files are `root:root 600`. Agent user cannot read them.
2. **Sudoers** — agent can only `sudo /usr/local/bin/run <cmd>`.
3. **cred-guard hook / extension** — blocks Bash commands and file
   reads that match credential-exposure patterns.
4. **Output redactor hook / extension** — scrubs credential-shaped
   strings from tool output before they reach the agent's context.
5. **Egress allowlist** — iptables + security groups restrict the VM's
   outbound traffic to HTTPS, DNS, and specific known ports.

The agent invokes privileged commands via `sudo run <cmd>`, which
sources locked secrets as root and drops privileges back to the agent
user via `gosu` before exec.

## Repo layout

```
sandbox/
├── shared/                   # agent + host + workspace agnostic
│   ├── scripts/              # run, lock-env, unlock-env
│   ├── sudoers.d/            # agent sudoers entry
│   ├── tmuxinator/           # dev.yml tmux layout
│   └── patterns/             # cred-guard.json, redactor.json (single source of truth)
│
├── agents/                   # what agent and how to install
│   ├── pi/                   # Pi extensions + skills + install.sh
│   └── claude-code/          # hooks + settings template + install.sh
│
├── hosts/                    # where it runs and how to reach it
│   ├── docker-mac/           # Mac Docker mode
│   ├── gcp-vm/               # GCP VM bootstrap
│   └── aws-ec2/              # AWS EC2 with Terraform + Tailscale
│
├── workspaces/               # per-instance config (tfvars + secrets)
│   └── deepreel-srijan-claude.tfvars
│
└── docs/
    ├── superpowers/specs/    # design spec
    └── adr/                  # architecture decision records
```

## Quick Start

### Mac Docker (Pi)

```bash
cd hosts/docker-mac
cp secrets.example secrets
vi secrets              # add GH_TOKEN, AWS keys, etc.
./attach.sh             # builds on first run, attaches tmux
```

### GCP VM (Pi or Claude Code)

```bash
scp -r . dev-vm:~/sandbox
ssh dev-vm 'cd ~/sandbox && bash hosts/gcp-vm/bootstrap.sh --agent pi'
# or: bash hosts/gcp-vm/bootstrap.sh --agent claude-code
./hosts/gcp-vm/connect.sh
```

### AWS EC2 (Claude Code)

See [hosts/aws-ec2/README.md](hosts/aws-ec2/README.md) for the full flow.
Summary:

```bash
cd hosts/aws-ec2/terraform
terraform init
terraform workspace new deepreel-srijan-claude
set -a; source ../../../workspaces/deepreel-srijan-claude.secrets.env; set +a
terraform apply -var-file=../../../workspaces/deepreel-srijan-claude.tfvars
# Wait ~3-5 min for bootstrap, then:
../connect.sh
```

## What the agent can and cannot do

| Action | Allowed? | How |
|--------|----------|-----|
| Read/write project code | Yes | Direct file access |
| Run project with credentials | Yes | `sudo run <cmd>` |
| Use gh/aws/gcloud CLI | Yes | `sudo run gh ...` |
| Read .env files | No | OS file perms + hook blocks |
| Run env/printenv | No | cred-guard hook blocks |
| Read /etc/devbox/locked/secrets | No | root:root 600 |
| sudo cat/bash (as agent) | No | cred-guard + sudoers restrict |
| sudo bash (as admin) | Yes | For credential management |

## Supported agents

- **Pi** ([pi-mono](https://github.com/badlogic/pi-mono)) — TypeScript
  extensions for cred-guard and tmux-tools
- **Claude Code** ([claude-code](https://github.com/anthropics/claude-code))
  — PreToolUse + PostToolUse shell hooks; YOLO mode
  (`--dangerously-skip-permissions`) safe by construction

## Adding a new agent or host

- **New agent**: drop `agents/<name>/` in place with an `install.sh`,
  hooks/extensions, and any settings templates. Both existing hosts
  and future hosts can use it via the `--agent` flag.
- **New host**: drop `hosts/<name>/` in place with its own
  `bootstrap.sh --agent <name>` entry point (and IaC if provisioning
  cloud infra). `shared/` is unchanged.
- **New workspace**: drop `workspaces/<name>.tfvars` in place. See
  [workspaces/README.md](workspaces/README.md).

## Tools versions

Matched to Mac for consistent experience (Docker mode):
- tmux 3.5a (built from source)
- Neovim 0.11.1
- Node.js 22, Python 3, uv, ripgrep, fd, fzf, git
