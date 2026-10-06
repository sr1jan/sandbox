---
name: youtube-modal-fetch
description: Use when you need a YouTube video's transcript, captions, audio, video file, or metadata — especially when yt-dlp on this machine fails with YouTube's bot check (HTTP 403 or 429, "Sign in to confirm you're not a bot", LOGIN_REQUIRED). Runs yt-dlp on Modal containers on Google Cloud and brings the files back to local disk. Single videos only; needs Modal credentials.
---

# YouTube through Modal

YouTube's bot check refuses this host's IP and most datacenter IPs. It judges the IP, so PO tokens, retries from the same host, and newer yt-dlp releases do not help. `scripts/fetch.py` runs yt-dlp on fresh Modal containers on Google Cloud in Europe and South America, where about 3 containers in 4 pass, and copies the results to local disk. No local yt-dlp is needed.

Use it for single YouTube videos: metadata, captions, a plain-text transcript, audio, or video. Where yt-dlp works locally (other sites, or a host YouTube does not refuse), plain yt-dlp is cheaper and faster.

## Run

The skill directory is the directory of this SKILL.md:

| Harness | Skill directory |
|---|---|
| Claude Code | `~/.claude/skills/youtube-modal-fetch/` |
| omp | `~/.omp/agent/skills/youtube-modal-fetch/` |
| pi | `~/.pi/agent/skills/youtube-modal-fetch/` |

On the deepreel sandbox VM, Modal credentials come from `with_creds`, and `uv` must be the command right after it (the credential guard blocks an interpreter such as python, node, or bash in that place). Replace `<skill-dir>` with the directory above:

```bash
with_creds uv run --script <skill-dir>/scripts/fetch.py --transcript https://youtu.be/VIDEO_ID
```

Elsewhere, drop `with_creds` and have a Modal token: run `modal token new` once, or set `MODAL_TOKEN_ID` and `MODAL_TOKEN_SECRET`.

| Goal | Options |
|---|---|
| Metadata only | none |
| Read what is said | `--transcript` |
| Human-made captions (WebVTT) | `--subs` |
| YouTube's automatic captions (WebVTT) | `--auto-subs` |
| Another caption language | `--langs 'de,de-.*'` — comma-separated regexes, full match, default `en,en-.*` |
| Audio, mono AAC 64 kbps | `--audio` |
| Video, MP4, ≤1080p, video ≤1500 kbps | `--video` |
| Output root | `--out DIR` (default `./youtube`) |
| Other Modal regions, still on Google Cloud | `--region sa` or `--region eu,sa` (default `eu,sa`) |
| Workspace that cannot pin a cloud | `--any-cloud` (see Failures) |

URLs: watch, youtu.be, shorts, live, embed, or a bare 11-character video id. Pass several URLs in one call: they run 4 at a time in one Modal app. A call usually takes 15–35 s for a short video and about 100 s for one hour of audio, but it can wait 1–2 minutes for a container in the pinned regions. The first run in a Modal workspace also builds the container image (under 1 minute on 2026-10-06; it can take a few minutes).

## Outputs

Files go to `<out>/<video-id>/`:

| File | When |
|---|---|
| `info.json` | Always. yt-dlp's metadata (`title`, `channel`, `duration`, `upload_date`, `chapters`, `description`, `heatmap`, …) without the format lists, plus `caption_langs`: `{"human": [...], "auto": [...]}` |
| `subs.<lang>.vtt` | `--subs` |
| `auto.<lang>.vtt` | `--auto-subs` |
| `transcript.txt` | `--transcript`. One `[hh:mm:ss] text` line per paragraph (20–40 s), from human captions when any match `--langs`, else from automatic captions with their rolling repeats removed |
| `audio.m4a` | `--audio` |
| `video.mp4` | `--video`. Usually AV1 video with Opus audio; re-encode with ffmpeg if a player needs H.264 |

stdout has one JSON line per URL, in input order:

```json
{"url": "...", "id": "jNQXAC9IVRw", "ok": true, "transcript_source": "human captions, en",
 "title": "Me at the zoo", "channel": "jawed", "duration": 19, "upload_date": "20050424",
 "dir": "/abs/youtube/jNQXAC9IVRw", "files": {"info": "...", "subs": {"en": "..."}, "transcript": "..."},
 "from_cache": false, "fetched": ["info", "subs"], "tries": 1, "refused": 0,
 "modal_sec": 7.7, "est_cents": 0.016, "bytes_returned": 0, "placements": ["gcp eu-west: done"]}
```

`ok: false` comes with `error`. `missing` lists requested parts the video does not have, for example no captions in `--langs`, or a machine-translated caption track that YouTube refused. `placements` gives the cloud, region, and outcome of each try. Progress and errors go to stderr. The exit code is 1 when any URL failed, 2 for bad arguments.

Everything fetched is cached in `~/.cache/youtube-modal-fetch/<video-id>/`. A repeat call for cached parts does not start Modal (`from_cache: true`, under 1 s). Delete that directory to fetch again, for example after captions were added. Output files are hard links to the cached files when both are on one file system, so deleting only one of them frees no disk.

## How it works

- An ephemeral Modal app (`app.run()`, never deployed) runs on containers pinned with `cloud="gcp"` and `region=["eu", "sa"]`. The image holds Python 3.12, ffmpeg, `yt-dlp[default,deno]`, and bgutil's PO-token server for the `mweb` client.
- The regions leave out Google Cloud `us-east` and `us-west`. On 2026-10-06 YouTube refused 7 of 7 tries in us-east and 4 of 5 in us-west, but passed 23 of 32 in eu-west and 5 of 5 in sa. `DEFAULT_REGIONS` in `scripts/fetch.py` has the counts.
- One yt-dlp session per video does extraction, captions, and media download on one IP, because media URLs are bound to the IP that extracted them.
- A failure that a new IP can fix (HTTP 403/410/429, "not a bot", "try again later", a dropped connection) marks the container refused. That container takes no more inputs, and the script retries on a new container, up to 6 tries per URL. stderr and `placements` show the cloud and region of each try. Other failures are final at once.
- A machine-translated caption track (for example English captions for a Korean video) that fails is skipped and listed in `missing`, not retried: YouTube answered HTTP 429 to such a track on 4 of 4 containers whose extraction had passed.
- Audio and video come back as 16 MiB chunks from a generator function, so long videos work.

## Cost

Modal bills about 0.0018 cents per container-second (1 core, 2 GiB) before the region multiplier. A pinned region costs more: 1.15× when the list holds a broad region (`us`, `eu`, `ap`), else 1.75×. The default `eu,sa` is billed at 1.15×, that is about 0.12 cents per minute; `--region sa` alone is 1.75×. `est_cents` uses the container's own timing and that multiplier. It leaves out container start and the 10 s idle time before a container stops (about 10–20 s per container). Measured 2026-10-06 (the first three rows at 1.15×; the last two before region pinning, at 1×):

| Call | Modal seconds | est. cents |
|---|---|---|
| Metadata or captions + `--transcript`, short video | 8–16 | 0.016–0.032 |
| One refused try | 5–9 | ~0.01–0.02 |
| 6 refused tries (the call fails) | 36–61 | 0.07–0.12 |
| `--audio --video`, 1-minute video | 6–12 | ~0.02 |
| `--audio --auto-subs --transcript`, 60-minute talk | 67 (+8 refused) | 0.13 |

Bytes sent back count as Modal egress: 1 TiB per month is included on the Starter plan, then $0.04/GiB.

## Failures

| stderr or `error` says | Meaning | Do |
|---|---|---|
| `YouTube refused 6 containers in a row` | YouTube blocks the IPs in the pinned regions for now | Look at `placements`. Retry once later, or once now with another region, for example `--region sa`. Do not loop: each try costs money |
| `cannot pin cloud='gcp'` or `Pinning cloud gcp not supported` | The Modal workspace's plan cannot pin a cloud | Re-run with `--any-cloud`. It keeps the regions but lets containers land on AWS or Azure, where YouTube refused 9 of 10 tries on 2026-10-06, so expect several refusals |
| `Regions ... are not supported` | Modal does not know a `--region` name | Use names from Modal's region guide, for example `eu`, `eu-west`, `sa`, `us-central` (not `us-central1`) |
| `missing: ... machine-translated track` | YouTube refused an automatic translation of the captions (HTTP 429) | Use the video's own language, which the `missing` entry or `caption_langs` names (for example `--langs ko`) |
| `Modal has no credentials` or `Token missing` | No Modal token in the process | Deepreel VM: prefix with `with_creds`. Elsewhere: `modal token new` |
| `This video is unavailable`, `Private video`, `Sign in to confirm your age`, members-only | Final from every IP | Tell the user. This skill passes no cookies |
| `live stream`, `hasn't started`, `still processing` | Not a finished video | Fetch it after the stream ends and YouTube processes it |
| `missing: ... no captions match --langs` | No captions in those languages | Pick a language from `caption_langs` in `info.json`, or use `--audio` and a speech-to-text tool |
| The image build fails, or every try fails the same new way | YouTube changed and the pinned yt-dlp broke | Bump `YTDLP_VERSION` and `BGUTIL_VERSION` in `scripts/fetch.py` together |

`--verbose` shows Modal's own output (image build, container logs) on stderr.

On the deepreel VM, `with_creds` runs through `sudo`, which drops environment variables. Use the flags `--region` and `--any-cloud` there, not `YT_MODAL_REGION` or `YT_MODAL_ANY_CLOUD`.

## Out of scope

- A paid residential proxy fallback: no proxy account exists. When YouTube refuses Google Cloud, the skill fails.
- Playlists, channels, and search: pass single-video URLs.
- Speech-to-text for videos without captions: use `--audio`, then any local transcriber.
- Live streams, and content that needs a login (age-restricted, members-only, private).
