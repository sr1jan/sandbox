# OVH VPS host (Mumbai)

Personal-scope sandbox on an always-on OVH VPS-2 (4 vCPU / 8 GB / 75 GB
NVMe, ₹810/mo ex-GST). No Terraform — the box is ordered in the OVH
portal and reconciled with `sync.sh`. Design:
`docs/superpowers/specs/2026-07-25-personal-sandbox-migration-design.md`.

## Provision (one-time)

1. Order **VPS-2, Mumbai, Ubuntu 24.04** at ovhcloud.com/en-in/vps/
   (in-place upgrade to VPS-3 available later if cramped).
2. Mint a Tailscale auth key (reusable=no, ephemeral=no, tag as usual).
3. First SSH in with the OVH-provided key, then:

       sudo git clone https://github.com/sr1jan/sandbox.git /opt/sandbox
       TS_AUTHKEY=tskey-auth-... bash /opt/sandbox/hosts/ovh-vps/bootstrap.sh

4. From your Mac: `./ship-keys.sh && ./sync.sh` (keys → clones).
5. Switch /opt/sandbox origin to SSH once keys are live:
   `sudo git -C /opt/sandbox remote set-url origin git@github.com-personal:sr1jan/sandbox.git`
6. Populate provider keys (from your Mac):
   `printf 'DEEPSEEK_API_KEY=%s\n' "$KEY" | tailscale ssh ubuntu@sandbox-personal 'sudo sync-secrets'`

## Verify isolation (after bootstrap and after any sync)

Run as agent (`./connect.sh agent`):

| Check | Expect |
|---|---|
| `cat /etc/devbox/locked/secrets` | Permission denied |
| `sudo bash` | sudoers denial (only `run` allowed) |
| inside `pi`: read a `.env` path | cred-guard block |
| inside `pi`: `echo sk-ant-test1234567890abcdefghij` output | `[REDACTED]` in context |
| `curl --max-time 5 http://example.com:8080` | timeout (egress allowlist) |
| `nc -zv <public-ip> 22` from a non-tailnet machine | no route/filtered |
| `bash /opt/sandbox/hosts/ovh-vps/bootstrap.sh` re-run | completes, changes nothing |

## Day-to-day

| | |
|---|---|
| `./connect.sh [agent\|ubuntu]` | Tailscale SSH |
| `./sync.sh` | Reconcile box with repo (scripts, patterns, Pi, dotfiles, keys, clones) |
| `./ship-keys.sh` | Re-ship SSH/GPG keys after rotation |
| `./ship-project-env.sh <dir> <target>` | Ship a project's locked dotfile secrets |
| on box: `pi` | Pi with provider keys injected per-invocation |
| on box: `tx fun` | tmuxinator personal layout |

## Model providers

Keys live in `/etc/devbox/locked/secrets` (names in
`shared/secrets.example`); Pi's **built-in catalog** covers all target
providers — no models.json needed:

| Pi provider | Key | Endpoint |
|---|---|---|
| `deepseek` | `DEEPSEEK_API_KEY` | api.deepseek.com (PAYG default) |
| `zai` | `ZAI_API_KEY` | api.z.ai/api/coding/paas/v4 (GLM Coding Plan) |
| `kimi-coding` | `KIMI_API_KEY` | api.kimi.com/coding (Kimi membership) |
| `moonshotai` | `MOONSHOT_API_KEY` | api.moonshot.ai/v1 (PAYG) |
| `openrouter` | `OPENROUTER_API_KEY` | openrouter.ai (BYOK fallback) |

Day-one: DeepSeek PAYG. Subscription trial (GLM Pro vs Kimi) decided
per the design doc, ~Sept 2026.

## AWS decommission checklist (on/after 2026-08-14 — NOT before)

- [ ] Migrate any personal state off the AWS box (non-git dirs in
      /workspace/fun — cockpit, profile, resume —, dotfile drift,
      in-flight worktrees, `~/.claude` history worth keeping)
- [ ] `cd hosts/aws-ec2/terraform && terraform workspace select <ws>`
      then source workspace secrets and `terraform destroy -var-file=...`
- [ ] Confirm in AWS console: instance, EBS volume, EIP, IAM sandbox user gone
- [ ] Remove the old device from the Tailscale admin console
- [ ] Claude Max auto-cancels by 2026-08-14 — verify no renewal charge
- [ ] Downgrade/rotate any DeepReel-scoped tokens still in ~/.sandbox-keys
