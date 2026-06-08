# 0004 — Always-attached SSM-only profile for break-glass

**Status**: Accepted
**Date**: 2026-06-08
**Supersedes**: the break-glass mechanism of [ADR 0003](0003-tailscale-over-ssm.md) (attach-on-demand). The rest of ADR 0003 (Tailscale as primary access) stands.

## Context

ADR 0003 chose Tailscale as primary remote access with SSM Session Manager as
break-glass, and—citing ADR 0002 constraint 2 (no standing IAM instance
profile)—made the SSM profile **attach-on-demand**: attach the profile only
when Tailscale is broken, then detach.

On 2026-06-08 a real Tailscale outage exercised this path and it failed:

- The SSM agent starts at boot. With no instance profile present, it falls back
  to **Default Host Management**, which is not configured for account
  `941377130901` (`AccessDeniedException: Systems Manager's instance management
  role is not configured`).
- Attaching the instance profile **after** boot does **not** make the agent
  re-register within any useful window — it does not pick up the new IMDS
  credentials on its own.
- SSM only came online after `aws ec2 reboot-instances` (agent restarts *with*
  the profile present) — or, equivalently, after restarting the agent over a
  working connection, which defeats the purpose of break-glass.

So attach-on-demand is not a viable break-glass path: recovering it requires a
reboot (disruptive to in-flight agent tmux work) or access you don't have when
Tailscale is down. ADR 0003 itself anticipated this: *"if [attach-on-demand]
proves too painful, switch to always-attached via a new ADR superseding this
one."*

## Decision

Attach the SSM-only IAM instance profile **permanently** at instance create
time. Implemented by defaulting `enable_ssm_break_glass = true`
(`variables.tf`); `main.tf` already wires the profile when the flag is set.

- The agent boots with credentials, registers immediately, and
  `aws ssm start-session --target <id>` works at any time with no reboot.
- The profile carries **only** `AmazonSSMManagedInstanceCore` (see `iam.tf`),
  scoped to SSM messaging — no S3, no prod, nothing useful for exfiltration.

## Consequences

- **Relaxes ADR 0002 constraint 2** (a standing instance profile now exists).
  Accepted: ADR 0003 already judged this risk "minor" — an attacker who steals
  the IMDS role credentials gets SSM-messaging permissions only, which grant no
  data access and no lateral/prod reach. The break-glass reliability win
  outweighs it.
- The break-glass runbook (`connection_instructions` output) no longer needs
  the reboot workaround; `start-session` is immediate.
- Set `enable_ssm_break_glass = false` to return to the strict no-profile
  posture if the threat model changes.
- Existing instances provisioned before this change need the profile attached
  once (`aws ec2 associate-iam-instance-profile`) and the agent restarted; new
  instances get it from boot. Done for the live `deepreel-srijan-claude` box on
  2026-06-08.

## Alternatives considered

**Account-level Default Host Management (DHMC)** — configure a default SSM role
for the account so agents register with no instance profile at all, preserving
ADR 0002 constraint 2 exactly. Rejected for now: it's an account-wide change
affecting every EC2 instance in `941377130901`, a broader blast radius than this
single-sandbox need warrants. Revisit if the no-standing-profile posture becomes
a hard requirement.
