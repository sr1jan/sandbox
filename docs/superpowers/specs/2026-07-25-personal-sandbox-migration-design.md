# Personal Sandbox Migration — Design

**Date:** 2026-07-25
**Status:** Approved (pending spec review)
**Context:** Company financing for the current setup (AWS EC2 sandbox +
Claude Code on Claude Max $200/mo) is ending: the Claude Max sub
auto-cancels by 2026-08-14, and the AWS box is to be destroyed no
earlier than 2026-08-14. Migrate to a personally-financed,
cost-optimized setup with the new box proven out before that date.

## Goal

Replace the company-financed sandbox (~$260+/mo: Claude Max $200 + AWS
EC2/EBS/EIP) with a personally-financed equivalent at ~$16–70/mo,
without giving up the credential-isolation architecture or day-to-day
capability. Scope shrinks to **personal projects only** — all DeepReel
work repos, DB access, and AWS deploy credentials are dropped.

## Decisions

| Axis | Decision | Rationale |
|---|---|---|
| Compute | **OVHcloud Mumbai VPS-2** (4 vCPU / 8 GB / 75 GB NVMe), ₹810/mo ex-GST ≈ $11/mo, always-on | User is in Mumbai: 2–8 ms latency vs 130 ms (Hetzner EU) / 60 ms (Singapore). Hetzner-class price at local latency. Always-on ≤ what stop-when-idle AWS costs, and long unattended agent runs need no start/stop machinery. Start small; OVH supports in-place upgrade to VPS-3 (6c/12 GB/100 GB, ₹1,160) if cramped |
| Agent | **Pi** (earendil-works/pi, MIT, pi.dev) | Already scaffolded in `agents/pi/`; 30+ providers + any OpenAI/Anthropic-compatible endpoint; per-session cost tracking; TS extensions replicate the cred-guard/redactor hooks |
| Models | **Multi-model, decision deferred.** Day one: DeepSeek V4 PAYG key. Trial subscriptions (GLM Coding Pro $50.40 promo / Kimi Allegretto $39 / Kimi Allegro $99) after real usage data accumulates in Pi's cost tracking | Different models for different task types is the intended end state. DeepSeek's ~99% cache-hit discount makes the uncommitted default nearly free. Claude-sub-in-third-party-agents is banned (Feb 2026), so no path retains the Max sub usefully for Pi |
| IaC | **No Terraform for the new host.** Plain `bootstrap.sh` over SSH, modeled on `hosts/gcp-vm/` | OVH VPS is portal/API-ordered; one pet box doesn't justify IaC. The AWS host keeps its Terraform until destroyed |

## Research summary (July 2026)

Full details in the conversation research; key facts the design rests on:

- **Latency (from Mumbai):** India DC 2–8 ms, Singapore 55–75 ms, EU
  120–145 ms. Practitioner consensus: 120 ms+ is fatiguing for
  vim/tmux; <30 ms imperceptible. Singapore is strictly dominated —
  India-or-higher prices at 10x India latency. The "India surcharge"
  no longer exists at Vultr/Linode/DO; OVH Mumbai is the price leader.
- **OVH Mumbai caveats:** 1 TB/mo APAC traffic quota then throttled to
  10 Mbps (harmless for terminal + agent API traffic); 75 GB disk.
- **Models:** GLM-5.2, DeepSeek V4-Pro, Kimi K3, MiniMax M3 all beat
  frontier budget tiers (Haiku 4.5, GPT-5 mini) on agentic coding.
  Prompt caching dominates agent economics (~90% of input tokens are
  re-reads): DeepSeek direct ~99% cache discount, Moonshot/z.ai
  ~80–90%. Direct lab APIs beat OpenRouter (5.5% credit fee,
  quantization roulette, cache-breaking provider hops); OpenRouter
  BYOK (free <1M req/mo) kept as fallback only.
- **Quota reality vs Claude Max:** user's real consumption ≈ Max-5x
  tier. GLM Pro (~400 prompts/5h, ~2,000/wk, prompt = one user turn)
  field-tested at ~65% weekly utilization by ex-Max users. GLM wart
  for India: 3x quota burn 14:00–18:00 UTC+8 = 11:30–15:30 IST (peak
  working hours); GLM-4.7 always 1x. Kimi: stronger model (K3, 1M
  ctx), no peak multiplier, but opaque quotas shared with the chat
  app and reports of silent hangs on rate limit — a risk for
  unattended runs. MiniMax token plans ruled out (documented ~5h
  burn-through of the $20 tier under agent load).
- **Pi:** moved to earendil-works/pi (Apr 2026); npm packages renamed
  `@earendil-works/pi-*`. `agents/pi/install.sh` still clones the dead
  `badlogic/pi-mono` repo and must be updated. Config:
  `~/.pi/agent/settings.json`, custom endpoints via `models.json`,
  keys via env vars or `~/.pi/agent/auth.json` (we use env via
  `sudo run`).

## Architecture

Unchanged in principle — the five isolation layers port as-is:

1. **OS file perms** — `/etc/devbox/locked/` root:600. Same.
2. **Sudoers** — agent's only sudo is `/usr/local/bin/run`. Same.
3. **cred-guard** — Pi TS extension (`agents/pi/extensions/cred-guard.ts`),
   loading the same `shared/patterns/cred-guard.json`. Already built.
4. **Redactor** — extend `shared/patterns/redactor.json` with new key
   shapes (DeepSeek `sk-*`, z.ai, Moonshot `sk-*`, OpenRouter
   `sk-or-*`) and port the redactor as a Pi extension (does not exist
   yet — only cred-guard.ts and tmux-tools.ts do).
5. **Egress allowlist** — iptables rules in bootstrap (no cloud SG on
   OVH VPS; iptables/nftables is the only enforcement layer, plus
   OVH's optional edge firewall for ingress). Tailscale remains the
   only ingress; UFW/iptables drop all other inbound.

### New/changed components

- **`hosts/ovh-vps/`** — new host:
  - `bootstrap.sh` — idempotent, run as root over SSH on the fresh
    VPS: create `agent` user, install Node 22 + toolchain + Docker,
    lay down `/etc/devbox/locked/`, install `shared/scripts/`,
    sudoers, dotfiles, patterns, iptables egress allowlist +
    persistence, join Tailscale (auth key passed via env), install
    agents (`--agent pi`, optionally claude-code), clone
    `fun` repos via SSH aliases.
  - `sync.sh` — the `power.sh sync` equivalent: git-pull `/opt/sandbox`,
    reinstall scripts/patterns/dotfiles/keys, retry clones. No
    start/stop/status subcommands (box is always-on, no hourly billing).
  - `connect.sh` — thin `tailscale ssh` wrapper (ubuntu + agent users).
  - Reuse `sync-ssh-keys.sh` / `sync-project-env.sh` patterns from
    aws-ec2, generalized to take a target host (small refactor: move
    shared logic or parameterize `VM_TARGET`).
- **`agents/pi/install.sh`** — update to earendil-works/pi npm install
  (`npm install -g @earendil-works/pi-coding-agent` or pinned
  version), fix extension imports to renamed packages, install
  `models.json` template with DeepSeek / z.ai coding / Kimi coding /
  OpenRouter endpoints, keep the `sudo run` wrapper.
- **`agents/pi/extensions/redactor.ts`** — new, PostToolUse-equivalent
  scrubbing using `shared/patterns/redactor.json`.
- **Secrets** — `shared/secrets.example` gains
  `DEEPSEEK_API_KEY` / `ZAI_API_KEY` / `MOONSHOT_API_KEY` /
  `OPENROUTER_API_KEY` placeholders; `AWS_*`, `DATABASE_*`,
  DeepReel-specific keys dropped.

### Explicitly dropped

- DeepReel repos, project envs, DB URLs, deploy IAM — out of scope.
- `seed-from-dump.sh`, ECS/CloudWatch IAM policies — die with the AWS host.
- Claude Max subscription — cancel effective end of July.
- Claude Code — remains installed but unauthenticated; optional PAYG
  Anthropic key later for frontier escalation.

## Migration sequence

1. Order OVH VPS-2 Mumbai (Ubuntu 24.04), note IPv4.
2. Write + run `hosts/ovh-vps/bootstrap.sh`; verify Tailscale up,
   public SSH closed, egress allowlist active.
3. Ship personal SSH/GPG keys; clone personal (`fun`) repos.
4. Create DeepSeek account + API key; `sudo sync-secrets` it in.
5. End-to-end Pi test: cred-guard blocks `cat .env`, redactor scrubs a
   planted dummy key, agent completes a real task on a personal repo,
   cost shows in Pi footer.
6. Parallel-run both boxes (until ~Aug 14); migrate any personal state
   (dotfile drift, in-flight worktrees) from the AWS box.
7. On/after 2026-08-14 (not before): `terraform destroy` the AWS
   workspace (instance, EBS, EIP, IAM user, Tailscale device cleanup).
   Claude Max auto-cancels by 2026-08-14 — verify no renewal charge,
   no manual cancellation needed.
8. Aug–Sep: trial GLM Pro and/or Kimi Allegretto against Pi's cost
   data; commit to whichever earns it (z.ai 30% promo + 1x off-peak
   both run through ~end of September — decide before then).

## Testing

- **Bootstrap idempotency:** run `bootstrap.sh` twice; second run is a
  no-op.
- **Isolation parity:** the same manual checks the aws-ec2 host uses —
  `cat /etc/devbox/locked/secrets` fails (perms), `pi` session refuses
  `cat .env` (cred-guard), planted `sk-test…` string comes back
  redacted (redactor), `curl` to a non-allowlisted host:port fails
  (egress), `ssh` from a non-tailnet source fails (ingress).
- **Cost telemetry:** Pi session footer shows tokens + cache hits +
  cost against DeepSeek; sanity-check against DeepSeek's usage
  dashboard after a day.

## Cost outcome

| | Today (company) | After |
|---|---|---|
| Compute | AWS EC2 + EBS + EIP (~$60+) | OVH VPS-2 ~$11 |
| Model | Claude Max $200 | $0 fixed + DeepSeek PAYG (est. $5–15) → optionally +$39–50 sub after trial |
| **Total** | **~$260+** | **~$16–26 now; ~$55–65 if a sub is added** |

## Open questions (deliberately deferred)

- Which subscription (if any) after the trial period — GLM Pro vs
  Kimi Allegretto/Allegro. Decision input: Pi cost data, IST
  peak-multiplier pain in practice, unattended-run reliability.
- Whether to add a PAYG Anthropic key for occasional Claude Code
  escalation.
- VPS-2 → VPS-3 upgrade — only if RAM/disk pressure shows up.
