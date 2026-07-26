# Cost-Effective GPU Compute for a Solo Developer — July 2026 Landscape

> Research snapshot (2026-07-26) for the personal-sandbox migration
> ([spec](../superpowers/specs/2026-07-25-personal-sandbox-migration-design.md)).
> Scope: bursty personal use (open-weight LLM fine-tuning/inference,
> image/video gen, occasional CUDA dev) from Mumbai, latency-insensitive,
> price-first. Prices USD/GPU-hour unless noted. Marketplace prices float
> hourly — treat as ±20%. **[unverified]** = single secondary source.

---

## 1. Per-hour pricing comparison — marketplaces & neoclouds

| Provider | RTX 4090 (24GB) | RTX 5090 (32GB) | L40S (48GB) | A100 80GB | H100 80GB | B200 (192GB) | Notes |
|---|---|---|---|---|---|---|---|
| **Vast.ai** (marketplace) | $0.29–0.50 OD, ~$0.29 interruptible | ~$0.40–0.60 OD; spot lower | from ~$0.40 | ~$0.67–1.10 (SXM) | $0.90 unverified hosts, $1.50–2.01 verified DC | varies | Cheapest overall; quality varies by host |
| **RunPod Community** | $0.34 | $0.69 | $0.79 | $1.19 (PCIe) / $1.39 (SXM) | $1.99 (PCIe) / $2.69 (SXM) | $5.89 | Third-party hosts, can be interrupted |
| **RunPod Secure** | $0.69 | $0.99 | $0.99 | $1.39–1.49 | $2.89 (PCIe) / $2.99 (SXM) | $5.89 | RunPod-owned DCs, stable |
| **TensorDock** | $0.37 OD (~$0.25 seen) | — | varies | ~$1.30 | ~$2.50 OD / ~$1.60 spot [unverified] | — | Marketplace, per-second billing |
| **Lambda Labs** | n/a | n/a | listed | ~$1.29–1.99 | $2.99–4.29 (SXM) | $4.99–6.99 | Reliable; often out of stock at 1-GPU scale |
| **Hyperbolic** | marketplace | — | — | listed | ~$2.69 | — | Old "$0.99 H100" promo gone [unverified floor] |
| **Prime Intellect** | low-cost tiers from ~$0.14 | — | — | listed | $1.50–4.00 (aggregated) | — | Aggregator; most reliably in-stock H100 |
| **Salad** | $0.16–0.20 (batch) | $0.25–0.29 (batch) | ~$0.32–0.68 | n/a | n/a | n/a | Idle gaming PCs; interruptible, container-only |
| **io.net** | listed | — | — | $1.50–3.50 | listed | — | DePIN; weakest trust profile |
| **Novita AI** | $0.35 OD / $0.18 spot | $0.35 OD / $0.25 spot | — | — | $1.70–1.99 via bare-metal | — | Jun 2026 price cuts; self-serve RTX-only |
| **Verda** (ex-DataCrunch) | n/a | n/a | listed | ~$1.10–1.50 hist. | ~$2.26 (SXM5 via Shadeform) | $8.62 OD / **$3.02 spot** | Finland/Iceland DCs, clean spot pricing |
| **Shadeform** (aggregator) | passthrough | passthrough | passthrough | passthrough | e.g. $2.26 via Verda | passthrough | One console across 20+ clouds; no spot |

Cross-market reference (Jul 2026): H100 spans $2.01 (Vast) → $11.06 (GCP).
Thunder Compute index: Vast $2.01, Thunder $2.19, Vultr $2.30, Hyperbolic
$2.69, RunPod $2.89, Nebius $3.85, Modal $3.95, Lambda $3.99, CoreWeave
$6.16, AWS $6.88, Azure $8.30, OCI $10.00, GCP $11.06. **H100 market
median ~$3.15/hr**, down from $7+ in early 2024. L40S floor ~$0.40
(Vast). B200 cheapest spot ~$2.12–3.02 (Spheron [unverified], Verda).

### New/notable in 2026

- **RTX 5090 (32GB)** dominates marketplaces for image/video gen: Vast
  ~$0.40–0.60, Novita spot $0.25, Salad $0.25–0.29, RunPod Community $0.69.
- **RTX PRO 6000 Blackwell (96GB)** — new prosumer workhorse; Fal $2.99
  list / $1.10 discounted. Great VRAM/$ for big-model inference.
- **B200** at solo-dev prices only as spot (~$2–3/hr).
- **Thunder Compute** — virtualized A100 $1.09/hr, H100 $2.19; cheap but
  network-attached GPU, some workloads incompatible.

### Reliability caveats (marketplaces)

- **Vast.ai**: hosts vanish mid-run; bandwidth billed separately on some
  hosts (~$2.50/100GB — check listing); storage bills until you *destroy*
  (not stop). Mitigate: verified-DC hosts + high reliability score,
  checkpoint aggressively. Verified-DC H100 $1.50–1.87 vs $0.90
  unverified is the price of sleep.
- **RunPod Community**: interruption possible; fewer horror stories.
  Secure Cloud is the "just works" tier.
- **Salad**: idle gaming PCs — interruptions, slow model pulls, no
  persistent disk guarantees. Stateless batch only.
- **io.net**: cheapest claims, weakest trust (crypto-incentivized supply).
  Checkpointed, secret-free batch only.

## 2. Serverless / per-second GPU

| Platform | Pricing model | Key rates | Free credits | Cold starts |
|---|---|---|---|---|
| **Modal** | Per-ms execution; Python-decorator DX | A100 80GB ~$2.50/hr, H100 $3.95/hr | **$30/month recurring (Starter), confirmed 2026** | Best-in-class: container snapshots ≈ near-zero warm starts; genuine cold pulls of big models still 30s+ unless weights baked into image/volume |
| **RunPod Serverless** | Per-second; Flex (scale-to-zero) vs Active (−20%) | 4090 Flex $1.12, A100 $2.72, H100 $4.18/$3.35 | Small one-time signup credit [unverified] | FlashBoot: <200ms ~48%, <2s p95 once pool warm |
| **Replicate** | Per-second (public models); private pay idle too | T4 $0.81, L40S $3.51, A100 $5.04, H100 $5.49 | No standing free tier | Fast for popular public models; cold custom models minutes |
| **Fal.ai** | **Per-output** hosted models; per-second custom | Flux Kontext $0.04/img, Wan 2.5 $0.05/s video; H100 $3.99/$1.89 disc., B200 $3.49 disc., RTX PRO 6000 $1.10 disc. | Small signup credits [unverified] | Effectively none on flagship hosted models |
| **Baseten** | Per-second inference (Truss) | A100 ~$4.56/hr, H100 ~$6.50 effective | ~$30 trial [unverified] | Good autoscaling; priced for startups not hobbyists |
| **Beam** | Per-second; no charge for spin-up | 4090 ~$0.69/hr, A100 80GB $1.30, H100 **$1.74** | **$30/mo (free Developer plan)** + 10h trial | Sub-second claimed (custom runc); smaller ecosystem |

Modal's $30/mo ≈ 7–12 free H100-hours or ~40 T4-class hours monthly.
Beam is the budget Modal clone. Fal is cheapest for mainstream
image/video models (pay per output, never idle-burn).

## 3. Free GPU access in 2026

| Service | GPU | Limits | Status Jul 2026 |
|---|---|---|---|
| Google Colab free | T4 (not guaranteed) | ~12h sessions, throttled at peak | Alive; default free scratchpad |
| Colab Pro / PAYG | T4/L4, occasional A100 | Pro ~$9.99–11.99/mo (conflicting — verify), 100 CU; PAYG $9.99/100 CU ≈ 57 T4-hr or ~7 A100-hr | Alive; compute-unit model |
| **Kaggle Notebooks** | 2×T4 or P100 (+TPU) | **~30 GPU-hr/week**, 9–12h sessions, background exec | Most generous free allowance anywhere |
| Lightning AI free | T4/L4/A10G/L40S | 15 credits/mo ≈ ~22 T4-hr; 1 Studio | Alive |
| SageMaker Studio Lab | T4 | free, no card | **Closed to new signups Jun 30, 2026** |
| Paperspace free | M4000/P5000-class pool | 6h sessions, public notebooks | Degraded since DO acquisition; unreliable |
| Oracle free tier | **No GPU** (4 OCPU/24GB ARM only) | — | GPU needs paid account + quota |

## 4. Big-cloud credits for GPU

- **GCP $300/90d**: real; must upgrade to billing-enabled account for GPU
  quota (credits survive). ≈100+ T4-hrs or ~30–40 A100-hrs, but A100/H100
  quota usually denied on fresh accounts — plan for T4/L4. Worth doing once.
- **Azure $200/30d**: N-series quota effectively unreachable for new
  personal accounts within the window. Low expected value.
- **AWS**: no blanket GPU credit; Activate needs a startup entity.
- **GitHub Student Pack**: DO $200 credit dead (GPU-excluded Jun 8, 2026,
  retired Aug 1); remaining Azure $100 has no realistic GPU quota. Not a
  GPU route in 2026.
- **Applications that still work**: Google TPU Research Cloud (individual
  researchers, TPU+JAX) [current status unverified]; Lambda/Together/
  Nebius/Prime Intellect ad-hoc research credits (low hit rate for
  unaffiliated hobbyists).

## 5. Practitioner consensus (r/LocalLLaMA, HN, r/StableDiffusion)

- **Cheap fine-tune default**: interruptible 4090/5090 on Vast
  (~$0.29–0.40/hr) or RunPod Community for QLoRA; Community A100 80GB or
  Vast verified H100 (~$1.50–2.00) when it doesn't fit. Checkpoint every
  N steps. "Vast when you want lowest price and can do a little ops;
  RunPod when you want to be running in an hour."
- **Serverless-first cohort**: lives inside Modal's $30/mo credits for
  everything bursty; Beam as the cheaper clone once outgrown.
- **Image/video**: ComfyUI-on-RunPod (one-click 5090 templates) and
  ComfyUI-on-Vast dominate; Salad for cheap stateless batch; Fal per
  output for no-babysitting.
- **Buy vs rent**: used RTX 3090 (~$750, 24GB) is the forum answer for
  heavy *daily* local use (payback ~9–10 months); **rent, don't buy** for
  bursty use — break-even needs ~12h/day utilization.
- GPU rental is a buyer's market in 2026; prices still drifting down.

## 6. India-specific providers

None beat global marketplaces on price for residency-free personal use,
with one partial exception:

| Provider | Observed | Verdict |
|---|---|---|
| **Jarvislabs.ai** (Coimbatore) | A100 80GB $1.49/hr, H100 SXM ≈$2.69 (₹217.89/hr), per-minute billing, entry GPUs from ₹41/hr | Only Indian option in the global ballpark; INR billing avoids forex markup; pause/resume UX. Backup/convenience, not primary |
| E2E Networks (TIR) | A100 80GB from ₹189/hr (~$2.2), H100 from ₹362/hr (~$4.2) | 1.5–2× marketplace; skip |
| NeevCloud | pricing page blocked scraping [unverified] | reportedly not competitive |
| Yotta Shakti | enterprise quotes only | not addressable solo |
| AceCloud | 8×H100 ~₹16L/mo (~$2.4/GPU-hr) | cluster-shaped; skip |

Vast/RunPod have Asia-region hosts, so the latency argument for Indian
clouds mostly evaporates. Checkpoint to Cloudflare R2 (no egress fees).

## Bottom line — ranked

**(a) Interactive tinkering:** 1. Kaggle (free, 30 hr/wk) → 2. Colab
free/PAYG + Lightning free pool → 3. Vast interruptible 4090/5090
(~$0.30/hr) or RunPod Community one-click when it must just work.

**(b) Fine-tuning bursts:** 1. Vast (4090/5090 QLoRA ~$0.30/hr;
verified-DC H100 $1.50–2.00; A100 80 ~$0.67–1.10) with checkpoint
discipline → 2. RunPod Community (+20–40%, fewer surprises, persistent
network volumes) → 3. Verda spot B200 $3.02 / Shadeform-sniping for
weekend big-iron. Skip Lambda at 1-GPU scale; hyperscaler credits only
as one-time GCP T4/L4 top-up.

**(c) Always-available cheap inference:** 1. Modal serverless inside the
$30/mo credit (snapshots ≈ instant warm) → 2. Fal per-output for
image/video → 3. RunPod Serverless Flex or Beam ($30/mo free, H100
$1.74) for custom containers. True 24/7 sustained load: Salad batch 4090
(~$120–150/mo) or a used local 3090.

Cross-cutting: keep datasets/checkpoints in R2/S3-compatible storage;
bake weights into images/volumes to kill cold starts; re-check an
aggregator (getdeploying.com, gpuperhour.com, cloudgputracker.com)
before any multi-day run.

---

### Sources

[Vast 4090](https://vast.ai/pricing/gpu/RTX-4090) · [Vast 5090](https://vast.ai/pricing/gpu/RTX-5090) · [RunPod pricing](https://www.runpod.io/pricing) · [TensorDock 4090](https://www.tensordock.com/gpu-4090.html) · [Thunder Compute H100 index Jul 2026](https://www.thundercompute.com/blog/nvidia-h100-pricing) · [Spheron GPU pricing 2026](https://www.spheron.network/blog/gpu-cloud-pricing-comparison-2026/) · [SynpixCloud Vast vs RunPod](https://www.synpixcloud.com/blog/vast-ai-vs-runpod-rtx-4090-pricing) · [GPUnex Vast review](https://www.gpunex.com/blog/vast-ai-review-2026/) · [Novita 5090 spot](https://blogs.novita.ai/rtx-5090-spot-instance/) · [Verda products](https://verda.com/products) · [Shadeform](https://shadeform.com/) · [aimultiple GPU marketplaces](https://aimultiple.com/gpu-marketplace) · [io.net review](https://ownyourmind.ai/projects/io-net/) · [getdeploying L40S](https://getdeploying.com/gpus/nvidia-l40s) · [Trustpilot Vast](https://www.trustpilot.com/review/vast.ai) · [CloudRift](https://www.cloudrift.ai/pricing) · [Modal pricing](https://costbench.com/software/ai-gpu-cloud/modal/) · [Spheron on Modal](https://www.spheron.network/blog/modal-gpu-pricing-2026-per-second-billing/) · [Beam's Modal teardown](https://www.beam.cloud/blog/modal-pricing-explained) · [Replicate pricing](https://replicate.com/pricing) · [Fal pricing](https://fal.ai/pricing) · [RunPod serverless rates](https://hackceleration.com/labs/runpod-pricing) · [serverless GPU comparison 2026](https://www.buildmvpfast.com/blog/serverless-gpu-ai-inference-platform-comparison-2026) · [Beam free tier](https://cloudgpuprices.com/vendors/beam) · [Colab guide](https://www.hivenet.com/post/google-colaboratory-gpu-complete-guide-to-free-cloud-gpu-access-and-limitations) · [Colab alternatives Jul 2026](https://www.thundercompute.com/blog/colab-alternatives-for-cheap-deep-learning-in-2025) · [Kaggle GPU docs](https://www.kaggle.com/docs/efficient-gpu-usage) · [Lightning free plan](https://aicreditmart.com/ai-credits-providers/lightning-ai-free-plan-22-gpu-hours-month-guide-2026/) · [Studio Lab closure](https://docs.aws.amazon.com/sagemaker/latest/dg/studio-lab.html) · [Oracle always-free](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) · [aimultiple free GPU](https://aimultiple.com/free-cloud-gpu) · [GCP credits guide](https://dev.to/behruamm/the-2026-developers-guide-to-free-google-cloud-credits-for-ai-side-projects-1ac5) · [Azure GPU quota Q&A](https://learn.microsoft.com/en-us/answers/questions/1616602/free-credits-do-not-allow-launching-gpu-accelerate) · [GitHub Student Pack](https://education.github.com/pack) · [DO student credit wind-down](https://codeharbor.tech/blog/digitalocean-github-student-pack-credits-expire-july-2026-migration-checklist) · [Spheron credit programs](https://www.spheron.network/blog/free-gpu-cloud-credits-2026/) · [localllms rental guide](https://localllms.dev/guide/cheapest-gpu-for-llm-inference/) · [cloud GPU rental guide](https://www.promptquorum.com/power-local-llm/cloud-gpu-rental-guide-2026) · [Vast vs RunPod 2026](https://medium.com/@velinxs/vast-ai-vs-runpod-pricing-in-2026-which-gpu-cloud-is-cheaper-bd4104aa591b) · [used 3090 in 2026](https://willitlocal.com/articles/used-3090-still-worth-it/) · [buy vs cloud](https://www.synpixcloud.com/blog/buy-gpu-or-use-cloud) · [ComfyUI RunPod 5090](https://dev.to/furkangozukara/ultimate-comfyui-swarmui-on-runpod-tutorial-with-addition-rtx-5000-series-gpus-1-click-to-setup-3loj) · [SemiAnalysis H100 index](https://newsletter.semianalysis.com/p/the-great-gpu-shortage-rental-capacity) · [Jarvislabs pricing](https://jarvislabs.ai/pricing) · [Jarvislabs H100 India](https://docs.jarvislabs.ai/blog/h100-price-india) · [E2E A100](https://www.e2enetworks.com/gpus/nvidia-a100-80gb) · [E2E H100](https://www.e2enetworks.com/gpus/nvidia-h100) · [Spheron India 2026](https://www.spheron.network/blog/gpu-cloud-india-2026/) · [NeevCloud](https://www.neevcloud.com/pricing.php) · [AceCloud](https://acecloud.ai/blog/cloud-gpu-pricing-comparison/)
