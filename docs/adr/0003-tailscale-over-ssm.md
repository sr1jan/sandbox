# 0003 — Tailscale over SSM for remote access

**Status**: Accepted
**Date**: 2026-04-24

## Context

The sandbox VM needs remote access from the author's Mac and phone, and must not be exposed publicly (per ADR 0001, in-scope threat 5). Two serious options were evaluated: Tailscale (mesh VPN built on WireGuard) and AWS Systems Manager Session Manager (SSM).

Key requirements:

- No inbound ports open on the VM
- Shell access from Mac
- Shell access from phone (iOS/Android)
- Port forwarding for UI review (dev servers on the VM viewable in Mac browser)
- Resilient to "I can't reach the VM" failures (i.e., a break-glass path exists)

## Decision

Use Tailscale for primary access, with SSM Session Manager available as a break-glass path.

- VM joins a dedicated deepreel Tailscale tailnet (new, owned by `srijan@deepreel.com`, free tier sufficient)
- Provisioning uses an ephemeral pre-authorized auth key, consumed on first use
- Mac uses `tailscale ssh admin@dp-sandbox` for shell access
- Phone uses the Tailscale mobile app plus any SSH client (Blink Shell on iOS, Termius cross-platform)
- Port forwarding is native: VM services bound to `0.0.0.0:<port>` are reachable from the Mac at `http://dp-sandbox:<port>` via Tailscale MagicDNS
- One ACL rule prevents `tag:claude-sandbox` from initiating connections toward the Mac or phone (belt-and-suspenders against lateral movement)
- **Break-glass path (SSM)**: SSM agent is installed on the VM (comes preinstalled on recent Ubuntu AMIs). Because SSM requires the instance to authenticate to the SSM service, a *minimal* SSM-only IAM instance profile is the honest way to support it. Two options for when that profile is attached:
  - **Default (preferred)**: no instance profile attached in normal operation. When Tailscale access is broken, attach the `AmazonSSMManagedInstanceCore` profile via `aws ec2 associate-iam-instance-profile` from your Mac, run `aws ssm start-session --target <id>`, detach when done. Preserves ADR 0002 constraint 2 strictly.
  - **Always-attached SSM-only**: leave an SSM-only profile attached permanently. Slightly relaxes ADR 0002 constraint 2, but the threat reduction is minor (an attacker stealing creds via IMDS only gets SSM permissions, which are not useful for exfiltration or prod access). Simpler operationally.
  - v1 uses the default (attach-on-demand) path; if it proves too painful, switch to always-attached via a new ADR superseding this one.

## Alternatives considered

**SSM Session Manager only** — gives shell access with no ports open, IAM-authenticated. Rejected as the primary path because:

- No practical mobile story. AWS Console mobile doesn't expose a usable SSM terminal; running `aws ssm start-session` from an iOS or Android device is painful (iSH, Termux workarounds).
- Port forwarding exists (`AWS-StartPortForwardingSession`) but is clunky — each forwarded port requires a separate session command.
- Still retained as break-glass because it's IAM-authenticated and works when Tailscale is broken.

**Public SSH with IP allowlist** — rejected outright. Home IPs change, port 22 is constantly scanned, and key management is another moving part.

**Bastion host** — rejected. Adds another machine to run, maintain, and secure. Tailscale accomplishes the same goal without the extra infrastructure.

**Existing deepreel tailnet (if one existed)** — would have been preferred but deepreel has none today, so we create a new dedicated one. Zero-cost on the free tier, covers up to 3 users / 100 devices.

## Consequences

- Installing and authorizing Tailscale is part of both the EC2 bootstrap and the Mac/phone setup. Users onboarding to the sandbox later will need Tailscale running on their devices.
- The Tailscale tailnet is a dependency; if Tailscale's control plane is down, access is broken until either Tailscale recovers or we break-glass via SSM.
- The tailnet's SSO identity (`srijan@deepreel.com`) becomes a single point of trust for access. 2FA must be enforced on that SSO; this is a recurring operational responsibility.
- Terraform provisions a `tailscale_tailnet_key` via the Tailscale Terraform provider; that provider requires an OAuth client ID/secret, stored in the workspace secrets env file (not in state).
- Future A+C migration: additional devs get invited to the same tailnet, their VMs are tagged similarly, ACLs gain entries per-user. No structural change.
