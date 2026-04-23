# 0001 — Threat model

**Status**: Accepted
**Date**: 2026-04-24

## Context

The sandbox exists so coding agents (Claude Code initially) can run in `--dangerously-skip-permissions` / YOLO mode without constant permission prompts. The security design has to be principled about what it protects against, or every later decision degenerates into "make it more secure" or "make it easier" without a way to judge the tradeoff. This ADR anchors every other security decision.

## Decision

We defend against the threats in the **in-scope** list below. Threats in the **out-of-scope** list are accepted as residual risk; their severity has been reasoned about and judged tolerable for v1 given the benefit (low-friction YOLO mode) and the mitigations already in place.

### In-scope threats (must be defended)

1. **Accidental credential leak into the agent's context window.** Claude reads a `.env` file, runs `printenv`, or otherwise pulls secrets into its conversation context where they might be logged, displayed, or sent back to the model provider. This is the headline threat — everything else is in service of preventing it.
2. **Exfiltration via non-HTTPS protocols.** A compromised or buggy agent tries to dial out over SMTP, SSH, raw TCP, IRC, DNS tunneling (partial), etc. to send data out of band.
3. **Lateral movement from sandbox to deepreel production resources.** The sandbox VM sits in the same AWS account as prod; network or IAM misconfiguration could let a compromised agent reach prod databases, S3 buckets, or running services.
4. **IAM privilege misuse.** Credentials provisioned for read-only purposes (CloudWatch reads, prod replica reads) get used for writes because the policy was too broad (e.g., using AWS-managed `ReadOnlyAccess` which grants more than the name implies).
5. **Unintended public exposure of the VM.** SSH port open to the internet, inadvertent public S3 bucket containing logs, VM's IP showing up in public Shodan scans.
6. **Disk exfiltration if the AWS account itself is compromised.** An attacker with AWS credentials snapshots the EBS volume and reads secrets from it.

### Out-of-scope threats (accepted residual risk, with mitigation notes)

1. **Credential exfiltration over HTTPS.** If both cred-guard and redactor fail to catch a secret entering Claude's context, Claude could in principle POST it to any HTTPS endpoint. Mitigated in depth by (a) OS-level cred isolation making most exposures impossible rather than guarded; (b) PostToolUse redactor scrubbing output before it reaches context; (c) first-party trust in the skills that Claude invokes. Tightening this would require a strict domain allowlist, which is operationally unsustainable for deepreel's integration surface — see ADR 0004.
2. **DNS tunneling exfiltration.** A very determined exfil path (encode data into DNS queries). Blocking it would require a DNS filter that blocks unknown TLDs. Accepted as low-probability; same mitigations as (1).
3. **Novel secret formats not in redactor patterns.** Brand-new vendor API key shape introduced after we last updated `redactor.json`. Mitigation: quarterly review of the pattern file.
4. **Obfuscated commands that evade cred-guard regex.** `bash -c "$(echo Y2F0IC5lbnY= | base64 -d)"` decodes to `cat .env` — a regex on the invocation won't catch it. Mitigation: regex patterns cover common forms; OS-level file perms (layer 1) still block the read even if the hook doesn't.
5. **Targeted supply-chain attack on first-party skills or Pi extensions.** A malicious commit to the skills repo could define a `with_creds` that exfiltrates. Accepted because the skills repo is first-party and all commits require your review. Not a realistic attacker for v1.
6. **Malicious insider with deepreel AWS admin access.** Anyone with AWS admin can snapshot EBS, add an instance profile, grant themselves access. Out of scope for this design; trust boundary is "the AWS account is honestly administered."
7. **Compromised Tailscale SSO.** If `srijan@deepreel.com`'s SSO is compromised, attacker can add nodes to the tailnet and reach the sandbox. Mitigation: enforce 2FA on the SSO (ADR 0003 references this).
8. **Physical access to the Mac or phone.** Out of scope — device-level compromise defeats any remote-access scheme.

### Threat actor assumptions

- **Primary concern**: the *agent itself* behaving unexpectedly (bugs, prompt injection, tool-use mishaps). Not a capable external attacker.
- **Secondary concern**: casual opportunistic internet scanning (unsolicited port probes, credential-stuffing attempts).
- **Explicitly not in scope**: nation-state adversary, APT, insider threat with AWS admin credentials. The sandbox is not designed to resist these.

## Alternatives considered

**Stricter threat model** — include HTTPS exfiltration as in-scope. Rejected because the operational cost of the strict egress allowlist needed to block it is unsustainable for deepreel's surface area (20+ third-party API integrations, growing); see ADR 0004. Can be tightened later if the threat posture changes.

**Looser threat model** — accept credential leak into context as acceptable. Rejected because the whole point of the sandbox is to make YOLO mode safe, and context-leak is the most likely bad outcome from an agent bug.

## Consequences

- Every other ADR references this one. A decision is evaluated against whether it protects an in-scope threat or costs more than it gains for an out-of-scope threat.
- The "done carefully" constraints in ADR 0002 derive directly from threats 3, 4, and 5 above.
- The egress design in ADR 0004 derives from the accepted residual risk in out-of-scope (1).
- The credential flow design (spec §5) derives from threat 1.
- When a new threat is identified, we update this ADR (edit in place if the category is new; supersede if the categorization changes fundamentally) before responding to it.
