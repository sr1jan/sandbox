/**
 * Credential Guard Extension
 *
 * Blocks the agent from reading credential files or running commands
 * that would expose secrets to the conversation context.
 *
 * Pattern lists are loaded from shared/patterns/cred-guard.json, which
 * is shared with the Claude Code PreToolUse hook.
 *
 * Two layers of defense:
 *   1. File permissions (OS-enforced, .env files are root:root 600)
 *   2. This extension (soft guard, catches env/printenv/proc reads)
 *
 * Place in ~/.pi/agent/extensions/ for global protection across all projects.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { isToolCallEventType } from "@mariozechner/pi-coding-agent";
import { readFileSync } from "node:fs";
import { join } from "node:path";

interface CredGuardPatterns {
	file_patterns: string[];
	bash_patterns: string[];
}

function loadPatterns(): CredGuardPatterns {
	// Resolve shared/patterns/cred-guard.json. The Dockerfile and GCP
	// bootstrap copy this file to /home/agent/.pi/agent/patterns/
	// alongside extensions/. Search there first, then fall back to a
	// path relative to this file (for local dev).
	const candidates = [
		"/home/agent/.pi/agent/patterns/cred-guard.json",
		join(__dirname, "..", "patterns", "cred-guard.json"),
	];
	for (const path of candidates) {
		try {
			return JSON.parse(readFileSync(path, "utf-8"));
		} catch {
			continue;
		}
	}
	throw new Error(
		`cred-guard.json not found in any of: ${candidates.join(", ")}`,
	);
}

const patterns = loadPatterns();
const SENSITIVE_FILE_PATTERNS = patterns.file_patterns.map((p) => new RegExp(p, "i"));
const SENSITIVE_BASH_PATTERNS = patterns.bash_patterns.map((p) => new RegExp(p));

function isSensitiveFile(path: string): boolean {
	return SENSITIVE_FILE_PATTERNS.some((p) => p.test(path));
}

function isSensitiveBash(command: string): boolean {
	return SENSITIVE_BASH_PATTERNS.some((p) => p.test(command));
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		// Block read/edit/write of sensitive files
		if (
			isToolCallEventType("read", event) ||
			isToolCallEventType("write", event) ||
			isToolCallEventType("edit", event)
		) {
			const path = event.input.path as string;
			if (isSensitiveFile(path)) {
				if (ctx.hasUI) {
					ctx.ui.notify(`Blocked: sensitive file ${path}`, "warning");
				}
				return { block: true, reason: `Sensitive file: ${path}` };
			}
		}

		// Block bash commands that expose credentials
		if (isToolCallEventType("bash", event)) {
			const cmd = event.input.command as string;
			if (isSensitiveBash(cmd)) {
				if (ctx.hasUI) {
					ctx.ui.notify(`Blocked: credential-exposing command`, "warning");
				}
				return { block: true, reason: "Command may expose credentials" };
			}
		}

		return undefined;
	});

	pi.on("session_start", async (_event, ctx) => {
		if (ctx.hasUI) {
			ctx.ui.setStatus("cred-guard", ctx.ui.theme.fg("accent", "cred-guard active"));
		}
	});
}
