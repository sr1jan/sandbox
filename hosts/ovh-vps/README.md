# OVH VPS host (Mumbai)

Personal-scope sandbox on an always-on OVH VPS-2 (4 vCPU / 8 GB / 75 GB
NVMe, ₹810/mo ex-GST). No Terraform — the box is ordered in the OVH
portal and reconciled with `sync.sh`. Design:
`docs/superpowers/specs/2026-07-25-personal-sandbox-migration-design.md`.

## Provision (one-time)

1. Order **VPS-2, Mumbai, Ubuntu 24.04** at ovhcloud.com/en-in/vps/
   (in-place upgrade to VPS-3 available later if cramped).
2. Mint a Tailscale auth key (reusable=no, ephemeral=no, tagged
   `tag:sandbox`) — from the **personal** tailnet (personal-email
   account), NOT the deepreel-email tailnet, which dies with the AWS
   box. The personal tailnet's ACL defines `tag:sandbox` + an ssh rule
   allowing members → tag as `ubuntu`/`agent`.
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
| on box: `tx` | tmux/tmuxinator layout (default multiplexer) |
| on box: `hx` | herdr — alternative, agent-aware multiplexer |

## Multiplexers

Both are installed; pick per session. Each wrapper forces the **agent**
user so panes can write to `/workspace/fun` and pick up agent's dotfiles.

**`tx` — tmux + tmuxinator (default).** Layout lives at
`hosts/ovh-vps/tmuxinator/dev.yml`: an `admin` window (`sudo -i` for
`sync-secrets`), a `sandbox` window running `pi`, and plain shells for
`fintrack` and `wingman`. Plain `tx` starts it (the project is named
`dev`, which is `tx`'s default).

**`hx` — [herdr](https://herdr.dev) (alternative).** A Rust multiplexer
built for coding agents: tmux's pane/tab/session model plus a sidebar
showing each agent's state (working / idle / blocked), and sessions that
survive disconnects. Bootstrap installs the binary to `/usr/local/bin`
and runs `herdr integration install pi`, which drops
`herdr-agent-state.ts` into `~agent/.pi/agent/extensions/` next to our
cred-guard and redactor — so Pi reports state via lifecycle hooks rather
than screen-scraping. Useful when several agent sessions run at once and
you want to see which one is blocked on input.

Its keybindings are remapped to match the tmux setup — prefix `C-a`,
`-` / `_` for splits, bare `C-h/j/k/l` for pane movement, `prefix d` to
detach — via `shared/dotfiles/herdr/config.toml`. Validate edits with
`herdr config check` (it catches both bad key syntax and unknown action
names) and reload a running server with `prefix shift+r`. Three tmux
habits have no herdr equivalent and stay at defaults: repeatable
directional resize (herdr uses a modal `prefix r`), `prefix Tab` for
last-window (herdr has no last_tab action; it cycles panes), and
`prefix b`, which is herdr's agent sidebar.

Security notes: herdr is client/server over a **Unix socket**, so it adds
no listening port and doesn't widen the Tailscale-only ingress. Its
remote mode (`herdr --remote ssh://…`) tunnels over SSH, which works
through Tailscale SSH without opening anything. Config (optional) lives
at `~/.config/herdr/config.toml`; `herdr --default-config` prints the
documented defaults, `herdr agent list` shows what it currently detects.

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
- [ ] Remove the old device from the Tailscale admin console; revoke the
      "terraform-sandbox" OAuth client (Trust credentials) there; abandon
      the deepreel-email tailnet entirely (personal devices switched to
      the personal tailnet)
- [ ] Claude Max auto-cancels by 2026-08-14 — verify no renewal charge
- [ ] Downgrade/rotate any DeepReel-scoped tokens still in ~/.sandbox-keys
