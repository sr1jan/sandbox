# Devbox — Sandboxed AI Coding Agent Environment

A sandboxed development environment for running [Pi coding agent](https://github.com/badlogic/pi-mono) with credential isolation. Works on Mac (Docker) and GCP VM.

## Architecture

```
Ghostty tab → attach.sh → Docker container (or VM)
                           │
                           tmux (single layer, agent user)
                           ├── admin window (sudo bash → root)
                           │   └── lock-env, unlock-env, edit secrets
                           ├── project window (pi + shell panes)
                           │   └── Pi with cred-guard + tmux-tools extensions
                           └── (dynamic panes created by Pi's tmux-tools)
```

## Security Model

Three layers prevent the AI agent from seeing credentials:

1. **File permissions** — `.env` files and `/etc/devbox/secrets` are copied to `/etc/devbox/locked/` (root:root 600). Originals are hidden via bind mount shadow.
2. **cred-guard extension** — Blocks Pi from running `env`, `printenv`, `cat .env`, `/proc/*/environ`, and other credential-exposing commands.
3. **tmux-tools extension** — Output captured from tmux panes is filtered to redact credential-like strings.

The agent runs commands needing credentials via `sudo run <cmd>`, which reads locked secrets as root, then drops privileges back to the agent user.

## Quick Start (Mac Docker)

```bash
# 1. Add credentials
cd ~/fun/sandbox/docker
cp secrets.example secrets
vi secrets                    # add GH_TOKEN, AWS keys, etc.

# 2. Attach (builds on first run)
./attach.sh
```

Inside the tmux session:
- **Window 1 (admin):** Root shell for `lock-env` / `unlock-env` / editing secrets
- **Window 2 (project):** Pi agent + shell pane

## Quick Start (GCP VM)

```bash
# 1. Bootstrap the VM (one-time)
scp -r ~/fun/sandbox dev-vm:~/sandbox
ssh dev-vm 'cd ~/sandbox && bash vm/bootstrap.sh'

# 2. Connect
./vm/connect.sh
```

## Project Credentials

```bash
# In the admin tmux window:
cd /workspace/my-project
vi .env                       # add project credentials
lock-env                      # locks .env to root:root 600

# In the Pi window, the agent uses:
sudo run python -m src.main   # loads locked .env, runs as agent
sudo run gh pr create ...     # loads global CLI creds
```

## File Structure

```
sandbox/
├── shared/                   # Identical in Docker and VM
│   ├── scripts/
│   │   ├── run               # Credential wrapper: loads secrets, drops privs
│   │   ├── lock-env          # Locks .env files (root:root 600)
│   │   └── unlock-env        # Unlocks for editing
│   ├── extensions/
│   │   ├── cred-guard.ts     # Blocks credential reads from Pi
│   │   └── tmux-tools.ts     # Gives Pi tmux pane control
│   ├── skills/
│   │   └── dev-environment/
│   │       └── SKILL.md      # Teaches Pi the sandbox workflow
│   ├── sudoers.d/
│   │   └── agent             # agent can only: sudo run, sudo bash
│   └── tmuxinator/
│       └── dev.yml           # tmux session layout
├── docker/                   # Mac Docker mode
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── entrypoint.sh         # Locks files, shadows .env, builds Pi
│   ├── attach.sh             # Entry point: start container + attach tmux
│   ├── start.sh              # Alternative: start without attaching
│   ├── secrets.example       # Template for CLI credentials
│   └── secrets               # Real CLI credentials (gitignored)
├── vm/                       # GCP VM mode
│   ├── bootstrap.sh          # One-time VM setup
│   └── connect.sh            # SSH + attach tmux
└── README.md
```

## What the Agent Can and Cannot Do

| Action | Allowed? | How |
|--------|----------|-----|
| Read/write project code | Yes | Direct file access |
| Run project with credentials | Yes | `sudo run <cmd>` |
| Use gh/aws/gcloud CLI | Yes | `sudo run gh ...` |
| Create tmux panes | Yes | tmux-tools extension |
| Read .env files | No | Bind mount shadow + cred-guard |
| Run env/printenv | No | cred-guard blocks |
| Read /etc/devbox/secrets | No | Bind mount shadow |
| Read /etc/devbox/locked/* | No | root:root 600 |
| sudo cat/bash (via Pi) | No | cred-guard blocks |
| sudo bash (manual, admin window) | Yes | For credential management |

## OAuth Login

Pi's `/login` works in Docker via socat port forwarding:

```
Mac browser → localhost:53692 → Docker port forward → socat → Pi's 127.0.0.1:53692
```

Supported providers: Anthropic, OpenAI Codex, Google Gemini CLI, Google Antigravity.

## Tools Versions

Matched to Mac for consistent experience:
- tmux 3.5a (built from source)
- Neovim 0.11.1 (official release)
- Pi coding agent (from source at `/workspace/pi-mono`)
- Node.js 22, Python 3, uv, ripgrep, fd, fzf, git
