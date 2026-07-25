/**
 * Redactor Extension
 *
 * Scrubs credential-shaped strings from tool output before it enters
 * the agent's context. Port of the Claude Code PostToolUse hook
 * (agents/claude-code/hooks/redactor.sh); pattern list is shared via
 * shared/patterns/redactor.json.
 *
 * Place in ~/.pi/agent/extensions/ for global protection.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
import { join } from "node:path";

interface RedactorPatterns {
	replacement: string;
	patterns: string[];
}

function loadPatterns(): RedactorPatterns {
	const candidates = [
		"/home/agent/.pi/agent/patterns/redactor.json",
		join(__dirname, "..", "patterns", "redactor.json"),
		// Repo checkout (local dev / tests): extensions/ → repo root → shared/
		join(__dirname, "..", "..", "..", "shared", "patterns", "redactor.json"),
	];
	for (const path of candidates) {
		try {
			return JSON.parse(readFileSync(path, "utf-8"));
		} catch {
			continue;
		}
	}
	throw new Error(`redactor.json not found in any of: ${candidates.join(", ")}`);
}

const config = loadPatterns();
const PATTERNS = config.patterns.map((p) => new RegExp(p, "g"));
const REPLACEMENT = config.replacement ?? "[REDACTED]";

export function scrubText(
	text: string,
	patterns: RegExp[] = PATTERNS,
	replacement: string = REPLACEMENT,
): string {
	let out = text;
	for (const p of patterns) {
		out = out.replace(p, replacement);
	}
	return out;
}

export default function (pi: ExtensionAPI) {
	// tool_result fires after every tool execution; returning { content }
	// replaces the result content that gets appended to the session.
	pi.on("tool_result", async (event) => {
		let changed = false;
		const content = event.content.map((item) => {
			if (item.type === "text") {
				const scrubbed = scrubText(item.text);
				if (scrubbed !== item.text) {
					changed = true;
					return { ...item, text: scrubbed };
				}
			}
			return item;
		});
		return changed ? { content } : undefined;
	});

	pi.on("session_start", async (_event, ctx) => {
		if (ctx.hasUI) {
			ctx.ui.setStatus("redactor", ctx.ui.theme.fg("accent", "redactor active"));
		}
	});
}
