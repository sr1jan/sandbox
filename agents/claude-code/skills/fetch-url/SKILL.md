---
name: fetch-url
description: Use when you need full raw web page content — all text, links, and structure — especially for multi-page research, JS-rendered SPAs, or when you need to scan links to decide what to fetch next. Prefer over WebFetch when you need complete unfiltered content rather than LLM-extracted summaries.
---

# Fetch URL

Convert any web page to clean LLM-ready markdown via Jina Reader API. Zero auth, handles JS-rendered SPAs (Puppeteer-based).

## Usage

```bash
~/.claude/skills/fetch-url/fetch.sh <url>
```

Returns raw markdown with headings, text, links, and images. Content goes straight into conversation context — no storage needed.

## When to Use (instead of WebFetch)
- You need **full raw content** — all links, all text, all structure
- You want to **scan links** in the output to decide which internal pages to fetch next
- **Multi-page research** — homepage → find internal links → fetch product/about/features pages
- **JS-rendered SPAs** — guaranteed to work (Puppeteer), WebFetch may not render JS content
- You want to **reason over the complete page** yourself rather than get a summary

## When to Use WebFetch Instead
- You need a **specific fact extracted** from a page ("what's the pricing?")
- **Token budget is tight** — WebFetch filters via LLM before hitting context
- Single-page quick lookup, not multi-page research

## When NOT to Use Either
- Authenticated pages (will return login page)
- Downloading files/binaries (use curl directly)

## Multiple Pages

Fetch pages sequentially. Start with homepage, scan links in the output, then fetch relevant internal pages. This is the key advantage over WebFetch — you see all the links to make informed decisions about what to fetch next.

## Gotchas
- Free tier: 100 RPM, 2 concurrent — sufficient for any research task
- Large pages (>100KB markdown) may need summarization after fetch
- Some sites block Jina — if empty output, fall back to WebFetch
- Pass the full URL including protocol: `fetch.sh https://example.com`
