# 0002 — AWS account C with "carefully" constraints

**Status**: Accepted
**Date**: 2026-04-24

## Context

The sandbox VM runs on AWS EC2. Three candidate accounts were considered:

- **A**: a new dedicated deepreel-sandbox AWS account. Strongest blast-radius isolation (sandbox cannot touch prod resources because prod is in a different account, full stop).
- **B**: the author's personal AWS account. Clean, but billing is personal.
- **C**: the existing deepreel production AWS account (same account prod runs in). Fastest to start because IAM, billing, and access are already configured. Largest blast-radius risk because sandbox and prod share an account boundary.

Deepreel does not currently use AWS Organizations (confirmed during brainstorm — `aws organizations describe-organization` would return `AWSOrganizationsNotInUseException`). Prod infrastructure runs inside the default VPC, meaning anything sharing that VPC shares a trust boundary with prod.

## Decision

Use the existing deepreel production AWS account (option C) for v1. Mitigate the increased blast-radius risk with a set of **eight non-negotiable constraints** (the "done carefully" contract):

1. **Dedicated VPC**, new CIDR range (e.g., `10.100.0.0/16`), no peering, no transit gateway to prod. The sandbox EC2 is never placed in the same VPC as prod, so SG misconfiguration cannot be the only thing between sandbox and prod.
2. **No IAM instance profile on the EC2.** The VM has zero AWS role attached; it cannot make any AWS API call without credentials we explicitly hand it.
3. **Custom IAM policies only** for any credentials provisioned into the VM. No AWS-managed `ReadOnlyAccess` (grants broader access than the name implies — e.g., `s3:GetObject` on all buckets).
4. **IMDSv2 enforced** on the EC2. Redundant given constraint 2, but defense-in-depth: if an instance profile is ever attached by mistake, IMDSv2 resists SSRF-based cred exfil.
5. **Egress allowlist** (broad HTTPS + DNS + prod replica; deny everything else at protocol level). Details in ADR 0004.
6. **Resource tagging**: every sandbox resource tagged `Environment=sandbox, Owner=srijan`. Supports cost tracking and one-command teardown.
7. **CloudTrail review after first week of use.** Read the sandbox IAM user's events; confirm zero write API calls and zero unexpected resource access. If the audit finds anything unexpected, treat it as a go-live blocker.
8. **Teardown story documented upfront.** `terraform destroy` cleanly deletes every sandbox resource; no orphans. If we can't commit to this, we haven't earned C.

These constraints are treated as load-bearing — if any is relaxed, the decision to use account C must be revisited.

## Alternatives considered

**Option A (new dedicated account):** Strongest isolation by construction. Accidental access to prod is impossible because prod is not in the account. Rejected for v1 only because the ~15 min friction to create and configure a new account wasn't justified for solo use. Will be the target for the A+C future-state migration (spec §9).

**Option B (personal AWS account):** Fastest start. Rejected because billing falls on the author's personal card and the later migration to A+C would have to move resources out of the personal account anyway.

**Deferring the sandbox project:** spin up A properly before starting. Rejected because C-with-constraints is a workable starting point and the learnings from v1 inform what A should look like.

## Consequences

- A dedicated VPC becomes a mandatory part of the v1 build (not optional) because prod is in the default VPC.
- IAM policies for CloudWatch read, replica DB read, etc., must be hand-written and line-reviewed before deploy. No using managed policies as shortcuts.
- First-week CloudTrail review is a go-live checkpoint, not a nice-to-have.
- Every new AWS-integrated feature requires asking "does this grant the sandbox anything near prod?" — a question A would make moot.
- Migration to A (future) is non-trivial: create account, reconfigure Terraform provider, re-apply, migrate Tailscale nodes. Done at the "second dev needs their own sandbox" trigger.
- When that migration happens, this ADR stays in place with status updated to `Superseded by <NNNN>` and a forward-link to the new ADR.
