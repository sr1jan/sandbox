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

`sudo run` loads a project's credentials by mapping the current directory to
`/etc/devbox/locked/projects/<path under /workspace>`. Run it from the project
ROOT (e.g. `cd /workspace/fun/agent-studio && sudo run …`). From a
subdirectory or `/tmp`, the project's keys are silently missing.

## Updating omp

Do **not** run `omp update`. On this host:

- `/usr/local/bin/omp` is a wrapper → `sudo run` → `omp-with-cursor`
- `/opt/omp/omp` is the real binary

`omp update` would overwrite the PATH wrapper. Ask the operator (ubuntu)
to run sync / `agents/omp/install.sh`, which upgrades only `/opt/omp/omp`.

## Running commands: bash first, tmux only when needed

**Default: the bash tool.** Use it for tests, builds, typechecks, linters and
one-shot scripts, with `async` for anything long. It returns exit codes, full
output, and a notice when the run finishes. A tmux pane gives you none of
that: output is scraped from the screen, a `clear` wipes it, and the job dies
if the pane does.

**Long-running services (dev servers, workers):** use the bash tool's named
service mode, which gives a ready check and logs via `proc://`. Use tmux only
when the user wants to watch the process live.

**tmux is for credentialed commands the bash tool refuses.** The bash tool's
credential guard may block `sudo run <cmd>`; `tmux_pane_send` is the
sanctioned path. When you use it:

1. `tmux_pane_create` opens the pane in a dedicated `agent-work` window of
   this tmux session, in your working directory. It never splits the user's
   window. Don't create or move panes by hand with raw `tmux` commands.
2. **Detach anything that outlives a few seconds**, and read results from a
   file, not the screen:
   `(sudo run setsid nohup <cmd> > /tmp/<job>.log 2>&1 &)`
   The job then survives the pane closing. Read `/tmp/<job>.log` with the
   bash tool.
3. **Clean up:** `tmux_pane_close` every pane you created. They are also
   closed when your session ends.

**Subagents can't use tmux:** the tools refuse them. When delegating, say
"bash only". Read-only scouts don't execute commands at all: the parent runs
and times things.

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
