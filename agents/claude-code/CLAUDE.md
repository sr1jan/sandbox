# Sandbox VM — credential conventions

This is the deepreel sandbox VM. Secrets are root-owned at
`/etc/devbox/locked/`; the agent shell has **no credentials in env**.

## Use `with_creds` for any credentialed CLI

`/usr/local/bin/with_creds` sources locked secrets and runs your
command as agent with the secrets in its process env. Use it for any
binary that authenticates via `AWS_*`, `DATABASE_*`, `ANTHROPIC_API_KEY`,
`MINIMAX_API_KEY`, etc.

```
with_creds aws sts get-caller-identity
with_creds psql "$DATABASE_REPLICA_URL" -c "SELECT 1"
with_creds curl -H "Authorization: Bearer $MINIMAX_API_KEY" https://...
```

`sudo run <cmd>` is the lower-level equivalent — `with_creds` is a
thin wrapper that calls it. Either form works.

## Project-scoped envs (cwd matters)

`run` also sources `/etc/devbox/locked/projects/<rel>/.env*` based on
cwd, where `<rel>` is cwd with `/workspace/` stripped. Backend-only
secrets (e.g. `MINIMAX_API_KEY`, project DB URLs) attach only when
`with_creds` is invoked from somewhere under that project's tree —
typically `/workspace/core/backend/` for the deepreel backend.

If a `with_creds <cmd>` reports a missing env var that you know is set
on this VM, your first check is: which directory was the wrapper
called from?

## GitHub is separate

Git auth uses SSH keys (`~/.ssh/`) for push/pull and GPG (`~/.gnupg/`)
for commit signing. `gh` CLI uses its own creds at `~/.config/gh/`
(`gh auth login` once if not authed). **None of these need
`with_creds`.**

## Don't try

- `aws login` — not a real subcommand. If `aws ...` returns
  `NoCredentials`, you forgot the `with_creds` prefix.
- `cat .env`, `printenv`, `env | …`, `sudo bash`, `sudo run env`,
  `with_creds env` — all blocked by the cred-guard PreToolUse hook
  with a clear error message naming the matched pattern.
- Reading `/etc/devbox/locked/*` directly — `700 root:root`, agent
  can't traverse.

## See also

The deepreel skills (`deepreel-db`, `deepreel-cloudwatch`,
`deepreel-gsc`, `deepreel-ga4`, `deepreel-posthog`) already use this
pattern for their task-specific commands. Their SKILL.md files are
worth a glance when working in those areas.
