# 0004 — Egress: broad HTTPS allowlist

**Status**: Accepted
**Date**: 2026-04-24

## Context

The sandbox VM's outbound traffic is a choice point with meaningful security and operational consequences. A strict allowlist (only specific domains reachable) is the textbook "secure" answer; broad outbound is the "permissive" one. The right answer depends on what deepreel's actual integration surface looks like and what threat the egress filter is defending against.

Deepreel's services talk to 20+ distinct third-party APIs today (AI/LLM providers, TTS, video rendering, Google APIs, PostHog, Stripe, email, Figma, Canva, and so on) and the list grows. Each integration adds a domain the sandbox might legitimately need to reach while Claude is debugging or developing against it.

The egress filter is a *second* line of defense against credential exfiltration. The *first* line is preventing credentials from entering Claude's context (OS-level cred isolation, cred-guard hook, output redactor). See ADR 0001.

## Decision

Allow outbound HTTPS broadly; deny all other outbound protocols.

Concretely, the egress allowlist is:

- `tcp/443` to `0.0.0.0/0` (HTTPS, any destination) — **allowed**
- `udp/53` and `tcp/53` to `0.0.0.0/0` (DNS) — **allowed**
- `tcp/5432` to the prod replica endpoint only — **allowed**
- `udp/41641` to the Tailscale coordination server — **allowed**
- Everything else — **denied**

Enforced at both the EC2 security-group level (outbound rules) and at the host level (iptables) as belt-and-suspenders.

## Alternatives considered

**Option A — strict per-domain allowlist** (allow only enumerated endpoints: `api.anthropic.com`, `api.openai.com`, `api.posthog.com`, etc.):
- Pros: tightest exfil protection against an attacker using a known C2 server.
- Cons: requires continuous maintenance; every new integration adds friction; will erode as devs work around it; does not block DNS tunneling exfiltration anyway. For deepreel's integration surface (20+ domains, growing), operationally unsustainable.
- Rejected because the maintenance cost exceeds the marginal security gain given the primary defense (cred-guard + redactor) catches the common case.

**Option C — DNS-based filter** (e.g., Cloudflare Zero Trust, NextDNS, dnsmasq with allowlist):
- Pros: human-readable domain policy; easier to maintain than IP allowlists.
- Cons: adds an external dependency; can be bypassed by direct-IP requests (skipping DNS); some friction.
- Not rejected — marked as a future-state option (see spec §10) for when the domain list stabilizes and multi-dev use makes central policy worthwhile.

**Option D — no egress filtering at all**:
- Pros: zero maintenance.
- Cons: non-HTTPS exfil vectors (SMTP, SSH-out, IRC, raw TCP) are open. The cost of adding two iptables rules (deny non-HTTPS) to close those is trivial.
- Rejected because the small effort of deny-non-HTTPS buys meaningful protection.

## Consequences

- **Accepted residual risk**: if both cred-guard and redactor fail to prevent a credential from entering Claude's context, Claude can exfiltrate it over HTTPS. This is explicitly listed in ADR 0001's out-of-scope threats.
- Maintenance burden is near-zero. New integrations added by deepreel Just Work in the sandbox — no SG rule updates needed.
- Non-HTTPS protocols (SSH-out, SMTP, IRC, plain HTTP, raw TCP) are blocked at both SG and iptables levels. A compromised agent cannot use these as exfiltration paths.
- DNS tunneling remains an exotic but possible exfil path. Out of scope per ADR 0001.
- If the threat model changes (e.g., we start running less-trusted third-party skills), this decision should be revisited. Natural next step: move to Option C (DNS allowlist) once the domain list is stable.
- When reconsidered, a new ADR supersedes this one; this one's status updates to `Superseded by <NNNN>`.
