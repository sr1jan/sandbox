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

- `/usr/local/bin/omp` is a wrapper → `sudo run` → `omp-launch`
- `/opt/omp/omp` is the real binary

`omp update` would overwrite the PATH wrapper. Ask the operator (ubuntu)
to run sync / `agents/omp/install.sh`, which upgrades only `/opt/omp/omp`.

## Running commands: always the bash tool

Use the bash tool for tests, builds, typechecks, linters, one-shot scripts and
credentialed `sudo run` / `with_creds` commands, with `async` for anything
long. It returns exit codes, full output, and a notice when the run finishes.

**Long-running services (dev servers, workers):** use the bash tool's named
service mode, which gives a ready check and logs via `proc://`.

**If the credential guard blocks a command** (for example `sudo run python …`
or `sudo run node …`), do not look for a way around it. Give the user the
exact command and the directory to run it from, and ask them to run it.

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
