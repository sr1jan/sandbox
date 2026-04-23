# Architecture Decision Records

This directory holds ADRs — short documents capturing load-bearing architectural decisions for the sandbox project.

Format follows Michael Nygard's template: context, decision, status, consequences, alternatives considered.

## Index

| # | Title | Status | Date |
|---|-------|--------|------|
| [0001](0001-threat-model.md) | Threat model | Accepted | 2026-04-24 |
| [0002](0002-aws-account-c-with-carefully-constraints.md) | AWS account C with "carefully" constraints | Accepted | 2026-04-24 |
| [0003](0003-tailscale-over-ssm.md) | Tailscale over SSM for remote access | Accepted | 2026-04-24 |
| [0004](0004-egress-broad-https-allowlist.md) | Egress: broad HTTPS allowlist | Accepted | 2026-04-24 |
| [0005](0005-os-level-isolation-over-devcontainer.md) | OS-level isolation over devcontainer | Accepted | 2026-04-24 |
| [0006](0006-three-axis-repo-structure.md) | Three-axis repo structure | Accepted | 2026-04-24 |

## Conventions

### When to write a new ADR

Write an ADR when a decision:
- Has visible downstream consequences (other code has to adapt to it)
- Has credible alternatives that were considered and rejected
- Will be re-questioned later ("why did we do X and not Y?")

Do not write ADRs for:
- Implementation details that can be changed without consequences (e.g., specific binary versions)
- Decisions fully captured in the spec doc or in code comments

ADRs can be written any time — at brainstorm, during implementation, or post-hoc when a reader asks "why?" Mid-implementation ADRs are normal and encouraged.

### When to edit vs supersede

**Edit in place** when:
- The decision is unchanged but context/consequences need clarification
- Typo, broken link, or formatting fix
- Adding cross-references to later ADRs that build on this one

**Supersede** when:
- The decision is reversed or fundamentally changed
- Create a new ADR with the revised decision
- Update the old ADR's status to `Superseded by NNNN` but leave its content otherwise intact — readers want to know the history

### Template

```markdown
# NNNN — <Title>

**Status**: Accepted | Proposed | Deprecated | Superseded by MMMM
**Date**: YYYY-MM-DD

## Context

What problem are we solving? What constraints and forces are in play?

## Decision

What did we decide?

## Alternatives considered

Short list of what else was on the table and why each was rejected.

## Consequences

What becomes easier / harder because of this decision? What new risks or
follow-on decisions does it introduce?
```

### Numbering

Sequential, zero-padded to four digits. Never reuse numbers, even for superseded ADRs.
