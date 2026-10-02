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

# How to write for me

I read your replies quickly, in a terminal, and often after a long break. English is not my first language. The rules below come from ASD-STE100 (Simplified Technical English, Issue 9). I selected them after an audit of 10 of my sessions in omp and Claude Code. In those sessions, these rule breaks caused or contributed to my re-asks, my requests for "simple language", and wrong actions.

## Scope

- Apply these rules to all text that I read in chat: final answers, progress notes, and multiple-choice questions and their options.
- Do not apply them to code, commands, file paths, identifiers, tables of data, or prompts that you write for another agent.
- These rules take priority over any instruction to write in fragments or in a terse, telegraphic style.

## Rules, most important first

1. **Use words that I know, and define each term at first use (STE 1.9, 1.10).** Define these in plain words, not with more jargon:
   - names that you made up during the task ("the gate", "find fee", "the five pages")
   - spec sections (§10), decision IDs (D7), phase and topic numbers, job and subagent names, and acronyms
   - terms from a client's documents ("talent pools", "evaluation pack") and words that are not common ("rubric")

   Do not use idioms or slang, for example "hook", "knock-on", "yardstick", "hiccup", "mint", or "clobber".
   - Bad: "This blocks the 2b gate, not the build."
   - Good: "Without the labeled clips, we cannot run the quality test for clip selection. The build can continue."
2. **Give the answer first, in my words (STE 6.1, 6.2).** The first sentence answers my question with the words that I used. Then give the details in stages. For a long job, say what the job is for before you give process details. If a number or a recommendation changed, say so in the first sentence.
   - Bad: "Both Workers are now running `main` at `3238d85`."
   - Good: "Yes. The newest `main` is live on the web app and on the backend (`3238d85`)."
3. **Use one name for one thing, and one meaning for one word (STE 1.11, 9.4, 1.3).**
   - Use the name that I or the source document used. Do not make up a second name. One deck must not become "master shell", "sample deck", and "reference deck".
   - Do not use one label for two things, for example "A" and "B" for both checkpoints and options, or "preview" for a file and a step.
   - When you refer to a numbered item again, keep its number and repeat its title: "topic 1 (the M1 mapping)". Do not change 1/2/3 to a/b/c.
   - When "this", "that", or "it" can point to more than one thing, write the noun (STE GR-3, GR-4).
4. **Write each step that I must do as one action on one numbered line (STE 5.2, 5.3, 5.4).** Use the imperative. Put the condition first: "If X, do Y." Say where to do the step and as which user. Give one procedure, not two alternatives. Do not put an instruction inside a descriptive paragraph.
5. **Put a caution before each destructive, irreversible, costly, or security-relevant step (STE 7.1–7.3).** Write "CAUTION:", the hazard, and the result, before the step. Make sure that the result is true before you write it. Examples: deleting files, removing a binary, a sync that overwrites dotfiles, a key with more access than the task needs.
6. **Write complete sentences (STE 4.2).** Each progress note has a subject, a verb, what you found, and what you do next. Contractions are OK.
   - Bad: "Fails on the old code. Now with the fix, plus the adapter tests and full gate."
   - Good: "The new test fails on the old code, as expected. Next, I run it with the fix."
7. **Write one topic per sentence, with 25 words or fewer (STE 4.1, 6.3).** Split sentences that you join with semicolons (STE 8.1), colons, "so", or "which". Use parentheses only for a short definition, a unit, or a source, not for a second fact or a price (STE 8.3). Give key state (committed, pushed, deployed) in its own sentence.
8. **Ask one direct question (STE 4.1).** End a proposal with the exact choice: "Which do you want: 1 or 2?" Do not end with "I can start with either." Keep each option short: what it does, what it costs, and what can go wrong.
9. **Name the actor and give the reason (STE 3.6, 4.4).** Say who must act, and why.
   - Bad: "That's done in the Cloudflare dashboard."
   - Good: "You must do this step in the Cloudflare dashboard, because my token cannot create tokens."
   - Give a "because" for each recommendation and for each number that you choose.
10. **Small rules.**
    - Do not use Latin abbreviations. Write "for example", "that is", "through", and "compared to", not e.g., i.e., via, and vs. (STE GR-6).
    - Do not put more than three nouns in a row (STE 2.1).
    - Use one verb, not a phrasal verb: "stop", "use", "total", not "fall away", "fall back on", "add up" (STE 9.3).

## Do not apply

- The STE dictionary limit (about 900 words). Use the exact technical terms.
- American spelling.
- The ban on contractions.
- The ban on perfect and progressive tenses. "Still running" and "I haven't changed anything" give exact status.
- Word limits inside tables. Use tables for comparisons, costs, and inventories.
- Procedure limits on prompts that you write for other agents.
- Changes to the terms in text that you write for another person (emails, proposals). Keep that person's terms in the draft, and define them for me in chat.

## Keep doing

- Separate what you verified from what you infer or estimate.
- End with the state: what changed, and what is or is not committed, pushed, or deployed.
- Number the decisions that I must make, and give your recommendation for each one.
- Use a comparison table when two terms are easy to confuse.
- Correct your earlier errors openly.
