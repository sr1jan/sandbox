---
name: youtube-toolkit
description: Use when downloading YouTube videos, extracting audio clips, or working with playlists - provides yt-dlp commands for audio extraction, partial clips, format selection, subtitles, and metadata
---

# YouTube Toolkit (yt-dlp)

## Overview

`yt-dlp` is the modern YouTube downloader (fork of youtube-dl). This skill covers common operations.

## Installation Check

```bash
yt-dlp --version
ffmpeg -version | head -1
```

Both are pre-installed on this VM. If missing, install via:
```bash
sudo apt-get install -y ffmpeg
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod 755 /usr/local/bin/yt-dlp
```

## Quick Reference

| Task | Command |
|------|---------|
| Audio as MP3 | `yt-dlp -x --audio-format mp3 URL` |
| **Partial clip** | `yt-dlp -x --audio-format mp3 --download-sections "*START-END" URL` |
| Video 1080p | `yt-dlp -f "bestvideo[height<=1080]+bestaudio" URL` |
| Playlist items | `yt-dlp --playlist-items 5-10 URL` |
| Subtitles embedded | `yt-dlp --write-auto-subs --embed-subs URL` |
| Metadata only | `yt-dlp -j URL` (JSON) or `yt-dlp --print title,duration URL` |
| Audio best quality (no convert) | `yt-dlp -f bestaudio URL` |

## Partial Clip Extraction (Key Pattern)

**This is the most commonly needed but least known feature.**

```bash
# Extract 16:00-16:10 as MP3
yt-dlp -x --audio-format mp3 --download-sections "*16:00-16:10" -o "clip.%(ext)s" URL

# Time formats supported:
# "*1:30-2:45"      minutes:seconds
# "*01:30:00-01:35:00"  hours:minutes:seconds
# "*90-120"         seconds only
```

The `*` prefix means "apply to all matching sections" (required).

## Format Selection

```bash
# List available formats
yt-dlp -F URL

# Best video up to 1080p + best audio
yt-dlp -f "bestvideo[height<=1080]+bestaudio" URL

# Specific format by ID
yt-dlp -f 137+140 URL

# Best single file (no merge needed)
yt-dlp -f best URL
```

## Playlists

```bash
# Download entire playlist
yt-dlp --yes-playlist URL

# Specific items (1-indexed)
yt-dlp --playlist-items 1,3,5-10 URL

# Skip playlist, download single video
yt-dlp --no-playlist URL
```

## Subtitles

```bash
# Download with auto-generated subs embedded
yt-dlp --write-auto-subs --embed-subs URL

# Download manual subs if available
yt-dlp --write-subs --sub-lang en --embed-subs URL

# List available subtitle languages
yt-dlp --list-subs URL
```

## Output Templates

```bash
# Custom filename
yt-dlp -o "%(title)s.%(ext)s" URL

# Organized by channel
yt-dlp -o "%(channel)s/%(title)s.%(ext)s" URL

# With upload date
yt-dlp -o "%(upload_date)s-%(title)s.%(ext)s" URL
```

## Common Mistakes

| Mistake | Correct |
|---------|---------|
| `--postprocessor-args "-ss 90"` for clips | Use `--download-sections "*1:30-2:00"` |
| `-x -f bestaudio` (converts anyway) | Just `-f bestaudio` (keeps original) |
| Forgetting `*` in download-sections | Must be `"*START-END"` not `"START-END"` |
| Using youtube-dl | Use yt-dlp (actively maintained) |
