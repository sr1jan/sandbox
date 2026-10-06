#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["modal>=1.5,<2"]
# ///
"""Fetch a YouTube video's metadata, captions, transcript, audio or video
through yt-dlp on Modal, for hosts whose IP YouTube refuses.

    uv run --script fetch.py [--subs] [--auto-subs] [--transcript] [--audio]
                             [--video] [--langs en,en-.*] [--out DIR] URL...

YouTube's bot check ("Sign in to confirm you're not a bot", LOGIN_REQUIRED,
HTTP 403/429) depends on the IP's reputation, not on PO tokens. Measured
2026-09-29 on fresh Modal containers: AWS 0/6, Oracle Cloud 0/4, Google Cloud
21/28. An IP works for every video or for almost none, so a retry must run on
a new container. This script runs yt-dlp in an ephemeral Modal app
(`app.run()`, never deployed) on containers pinned to Google Cloud, outside
Modal's `us-east` region (`DEFAULT_REGIONS`). A container that YouTube
refused stops taking inputs, and the next try lands on a new one. Media
comes back in chunks from a generator function, so a large video never
travels as one message.

Only `modal` runs locally; yt-dlp, ffmpeg, Deno and bgutil's PO-token server
run in the container image. Everything fetched is cached per video id and part
under ~/.cache/youtube-modal-fetch/, so a repeat call for cached parts does not
start Modal.

stdout: one JSON summary per URL. stderr: progress and errors. Exit 1 when a
URL failed, 2 on bad arguments.

Ported from agent-studio `apps/clip-jobs` (`eval/ytfetch.py`,
`clip_jobs/youtube.py`, `modal_app.py`), without the paid proxy fallback.
"""

from __future__ import annotations

import argparse
import contextlib
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

import modal

APP_NAME = "youtube-modal-fetch"
# Bump yt-dlp and bgutil together: yt-dlp pins its JS-challenge solver
# (yt-dlp-ejs) per release, the bgutil plugin and its server must share a
# version, and YouTube breaks old yt-dlp releases about once a month.
YTDLP_VERSION = "2026.8.19"
BGUTIL_VERSION = "2.0.0"

# Container resources, and Modal's list prices for them (2026-09).
CPU = 1.0
MEMORY_MIB = 2048
CPU_CENTS_PER_CORE_SEC = 0.00131
MEMORY_CENTS_PER_GIB_SEC = 0.000222
# Modal's price multipliers for a container region (docs, region selection,
# 2026-10-06): 1.15x for a broad region (`us`, `eu`, `ap`), 1.75x for a narrow
# one; a list that spans both is billed at the smaller.
BROAD_REGIONS = frozenset({"us", "eu", "ap"})

# Where containers run by default: Google Cloud in Europe and South America.
# Bot-check results per GCP region on 2026-10-06 (this skill's tests and two
# omp runs; a try passes when YouTube served the player response):
#   us-east 0/7, us-west 1/5, eu-west 23/32, eu-south 2/5, sa 5/5.
# (Before us-west was dropped: eu-west 14/20, sa 4/4. With this list: 10 of
# 13 tries passed, 10 of 10 URLs fetched.)
# us-east holds Columbus, which agent-studio's research (2026-09-29 §A5)
# found weak: 2 of 8 GCP containers clean there, 19 of 20 elsewhere. us-west
# is left out too (1/5). eu-south looks weak as well, but excluding it means
# naming eu-west and eu-north instead of the broad `eu`: a smaller pool, billed
# at 1.75x instead of 1.15x (a list with a broad region gets the broad price).
# Off Google Cloud, YouTube refused 9 of 10 tries the same day (AWS 0/3, Azure
# 1/7).
DEFAULT_REGIONS = ("eu", "sa")

# Tries per URL, each on a fresh container. About 3 Google Cloud containers
# in 4 pass the bot check (21/28 on 2026-09-29; 5/8 on 2026-10-05), and IPs
# fail independently, so 6 tries pass ~99.7% of the time even at 5/8. A
# refused try costs ~10-20 s of one core (~0.03 cents), so the cap keeps a bad
# hour (YouTube refusing all of Google Cloud) cheap.
MAX_TRIES = 6
# URLs fetched at once in one app run (and the container cap).
PARALLEL = 4
# Bytes per generator item: above Modal's 2 MiB inline limit each item goes
# through Modal's blob store, so 16 MiB keeps a 0.5 GB video to ~32 items.
CHUNK_BYTES = 16 << 20
TIMEOUT_SEC = 60 * 60
SCALEDOWN_SEC = 10

# Mono AAC 64 kbps: enough for speech-to-text and listening, ~29 MB/hour.
AUDIO_ARGS = ["-vn", "-ac", "1", "-c:a", "aac", "-b:a", "64k"]
DEFAULT_LANGS = "en,en-.*"

# At most 1500 kbps of video at <=1080p; when every 1080p rendition is over
# the cap, 720p, then 480p uncapped, then anything (`w`).
MAX_VIDEO_KBPS = 1500
FORMAT = (
    f"bv*[height<=1080][tbr<={MAX_VIDEO_KBPS}]+ba/bv*[height<=720][tbr<={MAX_VIDEO_KBPS}]+ba"
    "/bv*[height<=480]+ba/b[height<=480]/w"
)
# Resolution first, then https before HLS (the ~5.9 Mbps "Premium" HLS 616
# otherwise wins), then yt-dlp's codec order (AV1 > VP9 > AVC).
FORMAT_SORT = ["res:1080", "fps", "proto", "vcodec"]
AUDIO_FORMAT = "bestaudio/best"

POT_BASE_URL = "http://127.0.0.1:4416"
POT_START_SEC = 60.0

# Failures a new IP can fix: YouTube refusing the IP (403/410/429, the bot
# check, the "try again later" rate limit), a dropped connection. Anything
# else (private, removed, age-restricted, members-only, live) fails the same
# way from every IP.
_RETRYABLE = re.compile(
    r"HTTP Error (403|407|410|429)|proxy|tunnel connection failed|not a bot|timed out|"
    r"connection (reset|refused|aborted)|remote end closed|incomplete ?read|"
    r"content isn.t available, try again later",
    re.IGNORECASE,
)
# yt-dlp's message prefix: `ERROR: [youtube] <video id>: `.
_YTDLP_PREFIX = re.compile(r"^(?:ERROR:\s*)?(?:\[[^\]]+\]\s*(?:[\w-]+:\s*)?)?")
# yt-dlp's `live_status` values that are not a finished video.
_LIVE_REFUSALS = {
    "is_live": "this is a live stream; only finished videos can be fetched",
    "is_upcoming": "this stream hasn't started yet; only finished videos can be fetched",
    "post_live": "this stream just ended and YouTube is still processing it; try again later",
}
# Large or expiring parts of yt-dlp's info dict (format lists, IP-bound URLs).
_DROP = ("formats", "requested_formats", "requested_downloads", "thumbnails", "automatic_captions",
         "subtitles", "requested_subtitles", "http_headers", "_format_sort_fields", "url",
         "manifest_url", "fragments", "fragment_base_url", "downloader_options")


def _placement_options() -> tuple[list[str] | None, bool]:
    """`--region`/`YT_MODAL_REGION` (comma-separated Modal regions that
    replace `DEFAULT_REGIONS`, still on Google Cloud) and
    `--any-cloud`/`YT_MODAL_ANY_CLOUD=1` (drop the `cloud="gcp"` pin, for a
    workspace whose plan cannot pin a cloud: "Pinning cloud gcp not
    supported"). Two flags, because off Google Cloud YouTube refused 9 of 10
    tries on 2026-10-06 (AWS, Azure): a region override that silently left
    Google Cloud would waste its tries. Read before argparse because the
    function decorator needs them at import; `sudo` (and so `with_creds`)
    drops the env vars, hence the flags."""
    argv = sys.argv[1:] if __name__ == "__main__" else []
    value = os.environ.get("YT_MODAL_REGION") or ""
    any_cloud = os.environ.get("YT_MODAL_ANY_CLOUD", "").lower() in ("1", "true", "yes")
    for i, arg in enumerate(argv):
        if arg == "--region" and i + 1 < len(argv):
            value = argv[i + 1]
        elif arg.startswith("--region="):
            value = arg.split("=", 1)[1]
        elif arg == "--any-cloud":
            any_cloud = True
    return [r.strip() for r in value.split(",") if r.strip()] or None, any_cloud


OVERRIDE_REGIONS, ANY_CLOUD = _placement_options()
REGIONS = OVERRIDE_REGIONS or list(DEFAULT_REGIONS)
PLACEMENT: dict[str, Any] = {"region": REGIONS} if ANY_CLOUD else {"cloud": "gcp", "region": REGIONS}


def region_multiplier(regions: list[str]) -> float:
    return 1.15 if any(r in BROAD_REGIONS for r in regions) else 1.75


def placement_text() -> str:
    where = f"{'any cloud' if ANY_CLOUD else 'Google Cloud'} in {', '.join(REGIONS)}"
    if OVERRIDE_REGIONS:
        return f"{where} (--region)"
    return f"{where} (not us-east, where YouTube refused every try)"

image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install("ffmpeg", "git", "ca-certificates")
    .pip_install(f"yt-dlp[default,deno]=={YTDLP_VERSION}", f"bgutil-ytdlp-pot-provider=={BGUTIL_VERSION}")
    .run_commands(
        f"git clone --single-branch --branch {BGUTIL_VERSION} --depth 1 "
        "https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git /opt/bgutil",
        "cd /opt/bgutil/server && deno install --allow-scripts=npm:canvas --frozen",
    )
    .env({"BGUTIL_SERVER_HOME": "/opt/bgutil/server"})
)
app = modal.App(APP_NAME, image=image)


# ------------------------------------------------------------ container side


class _Retry(Exception):
    """A failure a new IP can fix: this container is refused."""


class _Final(Exception):
    """A failure that is the same from every IP."""


def _reason(message: str) -> str:
    """yt-dlp's error without its `ERROR: [youtube] <id>: ` prefix and its
    cookie advice (this script passes no cookies)."""
    why = _YTDLP_PREFIX.sub("", message.strip(), count=1) or message.strip()
    return re.sub(r"\s*Use --cookies-from-browser or --cookies\b.*", "", why, flags=re.DOTALL)


def _classify(message: str) -> Exception:
    why = _reason(message)
    return _Retry(why) if _RETRYABLE.search(why) else _Final(why)


def _live_refusal(info: dict[str, Any]) -> str | None:
    status = info.get("live_status")
    if status in _LIVE_REFUSALS:
        return _LIVE_REFUSALS[status]
    return _LIVE_REFUSALS["is_live"] if info.get("is_live") else None


# Per container process. `refused` stays set: an IP that fails fails for
# every video (agent-studio research 2026-09-29 §A5).
_container: dict[str, Any] = {"refused": False, "pot_server": None}


def _pot_up() -> bool:
    import urllib.request

    try:
        with urllib.request.urlopen(f"{POT_BASE_URL}/ping", timeout=2) as response:
            return response.status == 200
    except OSError:
        return False


def _pot_provider() -> str:
    """bgutil's PO-token server URL, started once per container (the README's
    Deno command for bgutil 2.0.0, run from node_modules)."""
    if _pot_up():
        return POT_BASE_URL
    server = _container["pot_server"]
    if server is None or server.poll() is not None:
        server = _container["pot_server"] = subprocess.Popen(
            ["deno", "run", "--allow-env", "--allow-net", "--allow-ffi=.", "--allow-read=.", "../src/main.ts"],
            cwd=Path(os.environ["BGUTIL_SERVER_HOME"]) / "node_modules",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    deadline = time.monotonic() + POT_START_SEC
    while time.monotonic() < deadline:
        if _pot_up():
            return POT_BASE_URL
        if server.poll() is not None:
            break
        time.sleep(0.5)
    # A container fault, so a new container can fix it.
    raise _Retry("the PO-token server did not start in this container")


def _ytdlp_options(workdir: Path, *, video: bool, audio: bool, pot_url: str) -> dict[str, Any]:
    options: dict[str, Any] = {
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "noplaylist": True,
        "socket_timeout": 30,
        "format": FORMAT if video or not audio else AUDIO_FORMAT,
        "format_sort": FORMAT_SORT,
        "merge_output_format": "mp4",
        "outtmpl": str(workdir / "media.%(ext)s"),
        "js_runtimes": {"deno": {}},
        "retries": 5,
        "fragment_retries": 10,
        "continuedl": True,
        # `mweb` needs a PO token (from bgutil); the default clients do not.
        "extractor_args": {
            "youtube": {"player_client": ["default", "mweb"]},
            "youtubepot-bgutilhttp": {"base_url": [pot_url]},
        },
    }
    if video:
        # The single-file fallbacks (`b`, `w`) are not always MP4.
        options["postprocessors"] = [{"key": "FFmpegVideoRemuxer", "preferedformat": "mp4"}]
    return options


def _matching(tracks: dict[str, Any] | None, langs: list[str], *, auto: bool) -> dict[str, dict[str, Any]]:
    """lang -> the track's WebVTT format, for languages that fully match one
    of `langs`. yt-dlp lists the original-language automatic track twice
    (`en` and `en-orig`, same captions): keep `en`."""
    found: dict[str, dict[str, Any]] = {}
    for lang, formats in (tracks or {}).items():
        if lang == "live_chat" or not any(re.fullmatch(p, lang) for p in langs):
            continue
        vtt = next((f for f in formats or [] if f.get("ext") == "vtt" and f.get("url")), None)
        if vtt:
            found[lang] = vtt
    if auto:
        for lang in [k for k in found if k.endswith("-orig")]:
            if lang.removesuffix("-orig") in found:
                del found[lang]
    return found


def _trim(info: dict[str, Any]) -> dict[str, Any]:
    trimmed = {k: v for k, v in info.items() if k not in _DROP and k != "entries"}
    trimmed["caption_langs"] = {
        # `live_chat` is a premiere's chat replay, not captions.
        "human": sorted(k for k in (info.get("subtitles") or {}) if k != "live_chat"),
        "auto": sorted(info.get("automatic_captions") or {}),
    }
    return json.loads(json.dumps(trimmed, default=str))


def _stream(part: str, path: Path) -> Iterator[dict[str, Any]]:
    size = path.stat().st_size
    with path.open("rb") as f:
        while chunk := f.read(CHUNK_BYTES):
            yield {"type": "chunk", "part": part, "data": chunk}
    yield {"type": "end", "part": part, "size": size}


def _fetch_in_container(url: str, want: dict[str, Any], workdir: Path) -> Iterator[dict[str, Any]]:
    """One yt-dlp session, so extraction, captions and media share one IP:
    info, then captions, then audio and video in chunks."""
    from yt_dlp import YoutubeDL
    from yt_dlp.utils import DownloadError

    pot_url = _pot_provider()
    options = _ytdlp_options(workdir, video=want["video"], audio=want["audio"], pot_url=pot_url)
    with YoutubeDL(options) as ydl:
        try:
            info = ydl.extract_info(url, download=False)
        except DownloadError as e:
            raise _classify(str(e)) from e
        if not isinstance(info, dict):
            raise _Final("yt-dlp returned no video")
        if refusal := _live_refusal(info):
            raise _Final(refusal)
        yield {"type": "info", "info": _trim(info)}

        human = _matching(info.get("subtitles"), want["langs"], auto=False)
        kinds: list[tuple[str, dict[str, dict[str, Any]]]] = []
        if want["subs"]:
            kinds.append(("subs", human))
        if want["auto"] or (want["auto_if_no_subs"] and not (want["subs"] and human)):
            kinds.append(("auto", _matching(info.get("automatic_captions"), want["langs"], auto=True)))
        for kind, tracks in kinds:
            texts: dict[str, str] = {}
            skipped: dict[str, str] = {}
            for lang, track in tracks.items():
                path = workdir / f"{kind}.{lang}.vtt"
                # yt-dlp's own subtitle download (headers, impersonation).
                try:
                    ydl.dl(str(path), {**track, "http_headers": track.get("http_headers") or info.get("http_headers")},
                           subtitle=True)
                except Exception as e:  # noqa: BLE001 — DownloadError or a network error, classified alike
                    # A machine-translated track (`tlang` in its URL) that
                    # fails is skipped, not retried: on 2026-10-06 YouTube
                    # answered HTTP 429 for the English translation of a
                    # Korean video on 3 of 3 containers whose extraction had
                    # passed, so a new IP did not help.
                    if "tlang" in parse_qs(urlparse(track["url"]).query):
                        skipped[lang] = _reason(str(e))
                        continue
                    raise _classify(str(e)) from e
                if not path.is_file():
                    raise _Final(f"yt-dlp could not download {kind} captions {lang!r}")
                text = path.read_text(encoding="utf-8", errors="replace")
                if not text.lstrip("﻿").startswith("WEBVTT"):
                    raise _Final(f"YouTube returned no WebVTT for {kind} captions {lang!r}")
                texts[lang] = text
            yield {"type": "captions", "kind": kind, "files": texts, "skipped": skipped}

        if not (want["audio"] or want["video"]):
            return
        try:
            done = ydl.process_ie_result(info, download=True)
        except DownloadError as e:
            raise _classify(str(e)) from e
    downloads = (done or {}).get("requested_downloads") or []
    media = Path(downloads[0]["filepath"]) if downloads and downloads[0].get("filepath") else None
    if media is None or not media.is_file():
        raise _Final("yt-dlp wrote no media file")
    if want["audio"]:
        # From the merged MP4 when there is one: it holds the best audio.
        audio = workdir / "audio.m4a"
        result = subprocess.run(["ffmpeg", "-hide_banner", "-nostdin", "-y", "-v", "error", "-i", str(media),
                                 *AUDIO_ARGS, str(audio)], capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"ffmpeg could not transcode the audio: {result.stderr.strip()[-500:]}")
        yield from _stream("audio", audio)
    if want["video"]:
        if media.suffix != ".mp4":
            raise _Final(f"yt-dlp produced {media.suffix}, not .mp4")
        yield from _stream("video", media)


def _where() -> str:
    cloud = os.environ.get("MODAL_CLOUD_PROVIDER", "?").removeprefix("CLOUD_PROVIDER_").lower()
    return f"{cloud} {os.environ.get('MODAL_REGION', '?')}"


@app.function(cpu=CPU, memory=MEMORY_MIB, timeout=TIMEOUT_SEC, max_containers=PARALLEL,
              scaledown_window=SCALEDOWN_SEC, **PLACEMENT)
def remote_fetch(url: str, want: dict[str, Any]) -> Iterator[dict[str, Any]]:
    """One fetch on this container, as a stream of messages; the last one is
    `done`, `refused` (try a new container), `final` or `error`."""
    if _container["refused"]:
        # Modal applies `stop_fetching_inputs` late at times: an input that
        # still reaches a refused container ends it. The caller sees a failed
        # call and tries again on another container.
        os._exit(1)
    started = time.monotonic()
    where = _where()
    try:
        with tempfile.TemporaryDirectory() as tmp:
            try:
                yield from _fetch_in_container(url, want, Path(tmp))
            except _Retry as e:
                _container["refused"] = True
                yield {"type": "refused", "reason": str(e), "sec": time.monotonic() - started, "where": where}
                return
            except _Final as e:
                yield {"type": "final", "reason": str(e), "sec": time.monotonic() - started, "where": where}
                return
            except Exception as e:  # noqa: BLE001 — a bug or a broken file: final, never retried
                yield {"type": "error", "reason": f"{type(e).__name__}: {e}", "sec": time.monotonic() - started,
                       "where": where}
                return
            yield {"type": "done", "sec": time.monotonic() - started, "where": where}
    finally:
        if _container["refused"]:
            # After this input: the retry must land on another container.
            modal.experimental.stop_fetching_inputs()


# ------------------------------------------------------------ transcript

_CUE_TIME = re.compile(r"^\s*((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})\s+-->")
_TAG = re.compile(r"<[^>]*>")
_SENTENCE_END = re.compile(r"[.?!…][\"')\]]*$")
# A paragraph ends at a sentence end after SOFT_SEC, or anywhere after
# HARD_SEC: one timestamp per 20-40 s locates a quote and keeps the file short.
SOFT_SEC = 20.0
HARD_SEC = 40.0


def _seconds(stamp: str) -> float:
    parts = stamp.replace(",", ".").split(":")
    return (int(parts[-3]) * 3600 if len(parts) == 3 else 0) + int(parts[-2]) * 60 + float(parts[-1])


def _clean(line: str) -> str:
    """Caption text without inline timing/style tags or HTML entities."""
    return " ".join(html.unescape(_TAG.sub("", line)).split())


def parse_vtt(text: str) -> list[tuple[float, list[str]]]:
    """(start seconds, cleaned non-empty lines) per cue."""
    cues: list[tuple[float, list[str]]] = []
    current: list[str] | None = None
    for line in re.split(r"\r\n|\r|\n", text):
        if m := _CUE_TIME.match(line):
            current = []
            cues.append((_seconds(m.group(1)), current))
        elif line == "":
            current = None
        elif current is not None and (cleaned := _clean(line)):
            current.append(cleaned)
    return cues


def transcript_lines(cues: list[tuple[float, list[str]]]) -> list[tuple[float, str]]:
    """Each caption line once. YouTube's automatic captions roll: a cue
    repeats the previous cue's last line(s) above its new line, so the longest
    prefix of a cue that equals a suffix of the previous cue is dropped."""
    out: list[tuple[float, str]] = []
    previous: list[str] = []
    for start, lines in cues:
        if not lines:
            continue
        overlap = next((k for k in range(min(len(previous), len(lines)), 0, -1)
                        if previous[-k:] == lines[:k]), 0)
        out.extend((start, line) for line in lines[overlap:])
        previous = lines
    return out


def _hms(sec: float) -> str:
    s = int(sec)
    return f"{s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}"


def build_transcript(vtt: str) -> str:
    """`[hh:mm:ss] text` per paragraph; a `>>` (speaker change) starts one."""
    paragraphs: list[tuple[float, list[str]]] = []
    for start, line in transcript_lines(parse_vtt(vtt)):
        if paragraphs:
            begun, words = paragraphs[-1]
            span = start - begun
            if not (line.startswith(">>") or span >= HARD_SEC
                    or (span >= SOFT_SEC and _SENTENCE_END.search(words[-1]))):
                words.append(line)
                continue
        paragraphs.append((start, [line]))
    return "".join(f"[{_hms(start)}] {' '.join(words)}\n" for start, words in paragraphs)


# ------------------------------------------------------------ local side

_VIDEO_ID = re.compile(r"[A-Za-z0-9_-]{11}")
_log_lock = threading.Lock()


def log(message: str) -> None:
    with _log_lock:
        print(f"[youtube-modal-fetch] {message}", file=sys.stderr, flush=True)


def video_id(arg: str) -> str:
    """The id of a single-video URL (watch, youtu.be, shorts, live, embed) or
    of a bare 11-character id."""
    if _VIDEO_ID.fullmatch(arg):
        return arg
    parsed = urlparse(arg if "://" in arg else f"https://{arg}")
    host = (parsed.hostname or "").lower()
    for prefix in ("www.", "m.", "music."):
        host = host.removeprefix(prefix)
    candidate = ""
    if host == "youtu.be":
        candidate = parsed.path.strip("/").split("/")[0]
    elif host in ("youtube.com", "youtube-nocookie.com"):
        if parsed.path == "/watch":
            candidate = parse_qs(parsed.query).get("v", [""])[0]
        elif m := re.match(r"/(?:shorts|live|embed|v|e)/([^/?#]+)", parsed.path):
            candidate = m.group(1)
    else:
        raise ValueError("not a YouTube URL")
    if not _VIDEO_ID.fullmatch(candidate):
        raise ValueError("not a single-video URL (watch, youtu.be, shorts, live, embed); "
                         "playlists and channels are out of scope")
    return candidate


def cache_root() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "youtube-modal-fetch"


@dataclass
class Cache:
    """One video's cached parts: info.json, captions.json (langs spec ->
    languages fetched, per kind; [] means none matched), <kind>.<lang>.vtt,
    audio.m4a, video.mp4."""

    dir: Path

    @property
    def info(self) -> Path:
        return self.dir / "info.json"

    @property
    def audio(self) -> Path:
        return self.dir / "audio.m4a"

    @property
    def video(self) -> Path:
        return self.dir / "video.mp4"

    def captions(self) -> dict[str, dict[str, list[str]]]:
        try:
            manifest = json.loads((self.dir / "captions.json").read_text())
        except (OSError, ValueError):
            manifest = {}
        return {"subs": manifest.get("subs", {}), "auto": manifest.get("auto", {})}

    def caption(self, kind: str, lang: str) -> Path:
        return self.dir / f"{kind}.{lang}.vtt"

    def store_captions(self, kind: str, spec: str, texts: dict[str, str]) -> None:
        self.dir.mkdir(parents=True, exist_ok=True)
        for lang, text in texts.items():
            _atomic_write(self.caption(kind, lang), text.encode())
        manifest = self.captions()
        manifest[kind][spec] = sorted(texts)
        _atomic_write(self.dir / "captions.json", json.dumps(manifest, indent=2).encode())


def _atomic_write(path: Path, data: bytes) -> None:
    tmp = path.with_name(path.name + ".part")
    tmp.write_bytes(data)
    tmp.replace(path)


@dataclass
class Job:
    url: str
    vid: str | None = None
    error: str | None = None
    want: dict[str, Any] | None = None
    tries: int = 0
    refused: int = 0
    modal_sec: float = 0.0
    bytes_returned: int = 0
    fetched: list[str] = field(default_factory=list)
    placements: list[str] = field(default_factory=list)
    # "<files key> <lang>" -> why YouTube refused that machine-translated track.
    skipped: dict[str, str] = field(default_factory=dict)
    done: bool = False


def needed(cache: Cache, args: argparse.Namespace, spec: str, langs: list[str]) -> dict[str, Any] | None:
    """What Modal must fetch for this video, or None when the cache has it."""
    manifest = cache.captions()
    subs_known, auto_known = spec in manifest["subs"], spec in manifest["auto"]
    want = {"langs": langs, "subs": False, "auto": False, "auto_if_no_subs": False, "audio": False,
            "video": False}
    want["subs"] = (args.subs or args.transcript) and not subs_known
    want["auto"] = args.auto_subs and not auto_known
    # The transcript reads human captions first, automatic ones only without.
    want["auto_if_no_subs"] = (args.transcript and not auto_known
                               and not (subs_known and manifest["subs"][spec]))
    want["audio"] = args.audio and not cache.audio.is_file()
    want["video"] = args.video and not cache.video.is_file()
    if any(want[k] for k in ("subs", "auto", "auto_if_no_subs", "audio", "video")) or not cache.info.is_file():
        return want
    return None


def _is_pinning_error(e: BaseException) -> bool:
    return bool(re.search(r"pinning cloud|cloud\b.*not supported", str(e), re.IGNORECASE))


def _hint(e: BaseException) -> str:
    text = f"{type(e).__name__}: {e}"
    if _is_pinning_error(e):
        return (f"{text} -- this Modal workspace cannot pin cloud='gcp'. Re-run with --any-cloud (or set "
                "YT_MODAL_ANY_CLOUD=1): it keeps the regions and drops the cloud pin, so containers also land "
                "on AWS or Azure, which YouTube refuses more often; stderr shows each container's cloud.")
    if isinstance(e, modal.exception.AuthError) or "Token missing" in str(e):
        return (f"{text} -- Modal has no credentials. On the deepreel sandbox VM, prefix the command with "
                "with_creds. Elsewhere run `modal token new`, or set MODAL_TOKEN_ID and MODAL_TOKEN_SECRET.")
    return text


def fetch_job(job: Job, cache: Cache, spec: str) -> None:
    try:
        _try_containers(job, cache, spec)
    finally:
        if job.error:
            with contextlib.suppress(OSError):
                cache.dir.rmdir()  # only when nothing was cached


def _try_containers(job: Job, cache: Cache, spec: str) -> None:
    """Tries on fresh containers until one fetches the parts, the failure is
    final, or MAX_TRIES is spent."""
    assert job.vid is not None and job.want is not None
    url = f"https://www.youtube.com/watch?v={job.vid}"
    cache.dir.mkdir(parents=True, exist_ok=True)
    for attempt in range(1, MAX_TRIES + 1):
        job.tries = attempt
        log(f"{job.vid}: try {attempt}/{MAX_TRIES}")
        started = time.monotonic()
        partial: dict[str, Any] = {}
        sec: float | None = None
        outcome, reason, where = "refused", "", "?"
        try:
            for msg in remote_fetch.remote_gen(url, job.want):
                kind = msg["type"]
                if kind == "info":
                    _atomic_write(cache.info, json.dumps(msg["info"], indent=2, ensure_ascii=False).encode())
                    job.fetched.append("info")
                elif kind == "captions":
                    cache.store_captions(msg["kind"], spec, msg["files"])
                    job.fetched.append(msg["kind"])
                    key = "subs" if msg["kind"] == "subs" else "auto_subs"
                    job.skipped |= {f"{key} {lang}": why for lang, why in msg.get("skipped", {}).items()}
                elif kind == "chunk":
                    part = msg["part"]
                    if part not in partial:
                        partial[part] = getattr(cache, part).with_suffix(".part").open("wb")
                    partial[part].write(msg["data"])
                    job.bytes_returned += len(msg["data"])
                elif kind == "end":
                    part, f = msg["part"], partial.pop(msg["part"])
                    f.close()
                    tmp, dest = Path(f.name), getattr(cache, part)
                    if (size := tmp.stat().st_size) != msg["size"]:
                        tmp.unlink()
                        raise RuntimeError(f"{part}: got {size} of {msg['size']} bytes")
                    tmp.replace(dest)
                    job.fetched.append(part)
                    log(f"{job.vid}: {part} received ({msg['size'] / 1e6:.1f} MB)")
                else:
                    outcome, reason, sec, where = kind, msg.get("reason", ""), msg["sec"], msg["where"]
        except Exception as e:  # noqa: BLE001 — a container that ended mid-call or Modal failing it
            if _is_pinning_error(e):
                job.error = _hint(e)
                return
            outcome, reason = "refused", f"the Modal call failed: {_hint(e)}"
        finally:
            for f in partial.values():
                f.close()
                Path(f.name).unlink(missing_ok=True)
        # The container's own timing; the local wall time when it never said.
        job.modal_sec += sec if sec is not None else time.monotonic() - started
        job.placements.append(f"{where}: {outcome if sec is not None else 'call failed'}")
        if outcome == "done":
            job.done = True
            log(f"{job.vid}: done on {where} in {sec:.0f} s")
            return
        if outcome in ("final", "error"):
            job.error = reason
            log(f"{job.vid}: failed on {where}, not retried: {reason}")
            return
        job.refused += 1
        log(f"{job.vid}: refused on {where} ({reason}); next try on a new container")
    job.error = f"YouTube refused {MAX_TRIES} containers in a row; the last reason: {reason}"


def _place(src: Path, dest: Path) -> None:
    """dest as a hard link to the cached file (no second copy of a video),
    or a copy across file systems."""
    dest.unlink(missing_ok=True)
    try:
        os.link(src, dest)
    except OSError:
        shutil.copy2(src, dest)


def summarize(job: Job, args: argparse.Namespace, spec: str, langs: list[str]) -> dict[str, Any]:
    cents = job.modal_sec * (CPU * CPU_CENTS_PER_CORE_SEC + MEMORY_MIB / 1024 * MEMORY_CENTS_PER_GIB_SEC)
    summary: dict[str, Any] = {"url": job.url, "id": job.vid, "ok": job.error is None}
    if job.error:
        summary["error"] = job.error
    cache = Cache(cache_root() / job.vid) if job.vid else None
    if cache and cache.info.is_file():
        info = json.loads(cache.info.read_text())
        outdir = Path(args.out).expanduser().resolve() / job.vid
        outdir.mkdir(parents=True, exist_ok=True)
        files: dict[str, Any] = {"info": str(outdir / "info.json")}
        _place(cache.info, outdir / "info.json")
        missing: list[str] = []
        manifest = cache.captions()
        for flag, kind, key in ((args.subs, "subs", "subs"), (args.auto_subs, "auto", "auto_subs")):
            if not flag or spec not in manifest[kind]:
                continue
            files[key] = {}
            for lang in manifest[kind][spec]:
                _place(cache.caption(kind, lang), outdir / f"{kind}.{lang}.vtt")
                files[key][lang] = str(outdir / f"{kind}.{lang}.vtt")
            if not files[key]:
                missing.append(f"{key}: no {'human' if kind == 'subs' else 'automatic'} captions match --langs {spec}")
        if args.transcript:
            source = _transcript_source(manifest, spec, langs)
            if source:
                kind, lang = source
                (outdir / "transcript.txt").write_text(build_transcript(cache.caption(kind, lang).read_text()))
                files["transcript"] = str(outdir / "transcript.txt")
                summary["transcript_source"] = f"{'human' if kind == 'subs' else 'automatic'} captions, {lang}"
            elif spec in manifest["subs"] and spec in manifest["auto"]:
                own = [k.removesuffix("-orig") for k in info.get("caption_langs", {}).get("auto", [])
                       if k.endswith("-orig")]
                hint = f"; the video's own automatic captions are in {own[0]}: try --langs {own[0]}" if own else ""
                missing.append(f"transcript: no captions match --langs {spec}{hint}; "
                               "for speech-to-text use --audio")
        for flag, part, path in ((args.audio, "audio", cache.audio), (args.video, "video", cache.video)):
            if flag and path.is_file():
                _place(path, outdir / path.name)
                files[part] = str(outdir / path.name)
        summary |= {"title": info.get("title"), "channel": info.get("channel") or info.get("uploader"),
                    "duration": info.get("duration"), "upload_date": info.get("upload_date"),
                    "dir": str(outdir), "files": files}
        missing += [f"{track}: YouTube refused this machine-translated track ({why}); not retried"
                    for track, why in job.skipped.items()]
        if missing:
            summary["missing"] = missing
    summary |= {"from_cache": job.tries == 0 and job.error is None, "fetched": list(dict.fromkeys(job.fetched)),
                "tries": job.tries,
                "refused": job.refused, "modal_sec": round(job.modal_sec, 1),
                "est_cents": round(cents * region_multiplier(REGIONS), 3),
                "bytes_returned": job.bytes_returned, "placements": job.placements}
    return summary


def _transcript_source(manifest: dict[str, dict[str, list[str]]], spec: str,
                       langs: list[str]) -> tuple[str, str] | None:
    """Human captions first, then automatic; within a kind, `--langs` order."""
    for kind in ("subs", "auto"):
        available = manifest[kind].get(spec) or []
        for pattern in langs:
            for lang in sorted(available):
                if re.fullmatch(pattern, lang):
                    return kind, lang
    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="fetch.py",
        description="Fetch YouTube metadata, captions, a transcript, audio or video through yt-dlp on Modal "
                    "(Google Cloud containers), for hosts whose IP YouTube's bot check refuses.",
        epilog="stdout: one JSON summary per URL. Cache: ~/.cache/youtube-modal-fetch/<id>/.")
    parser.add_argument("urls", nargs="+", metavar="URL",
                        help="a single-video YouTube URL (watch, youtu.be, shorts, live, embed) or an 11-character id")
    parser.add_argument("--subs", action="store_true", help="human-made captions as WebVTT")
    parser.add_argument("--auto-subs", action="store_true", help="YouTube's automatic captions as WebVTT")
    parser.add_argument("--langs", default=DEFAULT_LANGS,
                        help=f"caption languages: comma-separated regexes, full match (default: {DEFAULT_LANGS})")
    parser.add_argument("--transcript", action="store_true",
                        help="transcript.txt from the best captions (human, else automatic), [hh:mm:ss] per paragraph")
    parser.add_argument("--audio", action="store_true", help="audio.m4a: best audio, mono AAC 64 kbps")
    parser.add_argument("--video", action="store_true", help="video.mp4: <=1080p, video <=1500 kbps")
    parser.add_argument("--out", default="youtube", metavar="DIR",
                        help="output root; files go to DIR/<video id>/ (default: ./youtube)")
    parser.add_argument("--region", metavar="REGIONS",
                        help=f"comma-separated Modal regions, still on Google Cloud; replaces the default "
                             f"({','.join(DEFAULT_REGIONS)}) (also YT_MODAL_REGION)")
    parser.add_argument("--any-cloud", action="store_true",
                        help="drop the cloud=gcp pin, for Modal workspaces that cannot pin a cloud "
                             "(also YT_MODAL_ANY_CLOUD=1); YouTube refuses AWS and Azure containers more often")
    parser.add_argument("--verbose", action="store_true", help="show Modal's output (image build, container logs)")
    args = parser.parse_args()

    langs = [p.strip() for p in args.langs.split(",") if p.strip()]
    for pattern in langs:
        try:
            re.compile(pattern)
        except re.error as e:
            parser.error(f"--langs: bad regex {pattern!r}: {e}")
    spec = ",".join(langs)

    jobs = [Job(url=u) for u in args.urls]
    todo: dict[str, Job] = {}
    for job in jobs:
        try:
            job.vid = video_id(job.url)
        except ValueError as e:
            job.error = f"{job.url}: {e}"
            continue
        if job.vid in todo:
            continue
        job.want = needed(Cache(cache_root() / job.vid), args, spec, langs)
        if job.want is not None:
            todo[job.vid] = job
        else:
            log(f"{job.vid}: everything requested is cached; Modal not started")

    if todo:
        log(f"starting an ephemeral Modal app for {len(todo)} video(s) on {placement_text()}; "
            "the first run in a workspace builds the image "
            "(it can take a few minutes)")
        try:
            with contextlib.ExitStack() as stack:
                if args.verbose:
                    stack.enter_context(contextlib.redirect_stdout(sys.stderr))
                    stack.enter_context(modal.enable_output())
                stack.enter_context(app.run())
                with ThreadPoolExecutor(PARALLEL) as pool:
                    list(pool.map(lambda j: fetch_job(j, Cache(cache_root() / j.vid), spec), todo.values()))
        except Exception as e:  # noqa: BLE001 — the app did not start (credentials, placement, image)
            message = _hint(e)
            log(f"Modal failed: {message}")
            for job in todo.values():
                if job.error is None and not job.done:
                    job.error = message

    # A repeated URL shares its first occurrence's fetch.
    by_vid = {job.vid: job for job in todo.values()}
    failed = False
    for job in jobs:
        result = summarize(by_vid.get(job.vid, job) if job.error is None else job, args, spec, langs)
        result["url"] = job.url
        failed |= not result["ok"]
        print(json.dumps(result, ensure_ascii=False), flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
