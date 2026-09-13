---
description: Rules for running in the sandboxed devbox environment with credential isolation
---

# Sandboxed Development Environment

You are running in a sandboxed environment. You CANNOT read credential files directly. Follow these rules strictly.

## Running commands that need credentials

ALWAYS use `sudo run <command>` for anything that needs API keys, tokens, or database credentials:

```bash
sudo run python -m src.main           # start project
sudo run gh pr create --title "..."    # github CLI
sudo run aws s3 ls                     # aws CLI
sudo run gcloud compute instances list # gcp CLI
sudo run npm publish                   # npm with token
sudo run pytest tests/                 # tests needing API access
```

NEVER try to read .env files, /etc/devbox/secrets, or run env/printenv. These are blocked.

## Managing background processes with tmux panes

Use tmux tools to run servers, tests, and log tailers in separate panes:

1. **Start a server:**
   - `tmux_pane_create(direction: "vertical", name: "server")`
   - `tmux_pane_send(pane: "server", keys: "sudo run python -m src.main")`

2. **Watch logs:**
   - `tmux_pane_create(direction: "horizontal", name: "logs")`
   - `tmux_pane_send(pane: "logs", keys: "tail -f logs/app.log")`

3. **Run tests:**
   - `tmux_pane_create(direction: "vertical", name: "tests")`
   - `tmux_pane_send(pane: "tests", keys: "sudo run pytest tests/ -v")`

4. **Check output:**
   - `tmux_pane_capture(pane: "server", lines: 30)`
   - `tmux_pane_capture(pane: "tests", lines: 50)`

5. **Stop and restart:**
   - `tmux_pane_send(pane: "server", keys: "C-c", enter: false)` to Ctrl+C
   - `tmux_pane_send(pane: "server", keys: "sudo run python -m src.main")` to restart

6. **Clean up:**
   - `tmux_pane_close(pane: "server")`
   - `tmux_pane_close(pane: "tests")`

## Creating .env templates for new projects

When a new project needs credentials, create a `.env.example` with empty values:

```bash
cat > .env.example << 'EOF'
OPENAI_API_KEY=
DATABASE_URL=
EOF
```

Then tell the user: "Please create .env with your credentials and run lock-env."

## What you cannot do

- Read .env, .env.local, .env.secrets, or any credential file
- Run env, printenv, export -p, or read /proc/*/environ
- Run sudo with anything other than `run`
- Access /etc/devbox/secrets directly
