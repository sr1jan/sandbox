#!/usr/bin/env bash
# Fetch a URL via Jina Reader API — returns clean LLM-ready markdown
set -euo pipefail

URL="${1:?Usage: fetch.sh <url>}"

curl -sS \
  -H "Accept: text/markdown" \
  --max-time 30 \
  "https://r.jina.ai/${URL}"
