/**
 * Credential Guard Extension
 *
 * Blocks the agent from reading credential files or running commands
 * that would expose secrets to the conversation context.
 *
 * Two layers of defense:
 *   1. File permissions (OS-enforced, .env files are root:root 600)
 *   2. This extension (soft guard, catches env/printenv/proc reads)
 *
 * Place in ~/.pi/agent/extensions/ for global protection across all projects.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { isToolCallEventType } from "@mariozechner/pi-coding-agent";

// Files the agent should never read/write/edit directly
const SENSITIVE_FILE_PATTERNS = [
	/\.env($|\.)/,
	/\.env\.local$/,
	/\.env\.secrets$/,
	/\.env\.development$/,
	/\.env\.production$/,
	/credentials/i,
	/secrets?\./i,
	/\.pem$/,
	/\.key$/,
	/\.p12$/,
	/\.pfx$/,
	/service.account.*\.json/i,
	/\/etc\/devbox\/secrets/,
	/\.aws\/credentials/,
	/\.config\/gh\/hosts\.yml/,
	/\.config\/gcloud/,
	/\.docker\/config\.json/,
	/\.npmrc$/,
	/\.pypirc$/,
	/\.netrc$/,
];

// Bash commands that would expose credentials
const SENSITIVE_BASH_PATTERNS = [
	// Direct .env reads
	/\bcat\b.*\.env/,
	/\bless\b.*\.env/,
	/\bhead\b.*\.env/,
	/\btail\b.*\.env/,
	/\bmore\b.*\.env/,
	/\bsource\b.*\.env/,
	/\bgrep\b.*\.env/,
	/\bawk\b.*\.env/,
	/\bsed\b.*\.env/,

	// Environment variable dumping
	/\benv\s*($|\|)/,
	/\bprintenv\b/,
	/\bset\s*($|\|)/,
	/\bexport\s+-p/,
	/\bdeclare\s+-x/,

	// Process environment reads
	/\/proc\/.*\/environ/,
	/\bxargs\b.*\/proc/,

	// Secrets file reads
	/\/etc\/devbox\/secrets/,
	/\.aws\/credentials/,
	/\.config\/gh\/hosts/,

	// Sudo abuse (only sudo run is allowed)
	/\bsudo\s+cat\b/,
	/\bsudo\s+less\b/,
	/\bsudo\s+head\b/,
	/\bsudo\s+tail\b/,
	/\bsudo\s+more\b/,
	/\bsudo\s+vi\b/,
	/\bsudo\s+vim\b/,
	/\bsudo\s+nvim\b/,
	/\bsudo\s+nano\b/,
	/\bsudo\s+bash\b/,
	/\bsudo\s+sh\b/,
	/\bsudo\s+su\b/,
	/\bsudo\s+-i\b/,
	/\bsudo\s+-s\b/,

	// Python/Node one-liners to read env
	/python.*os\.environ/,
	/python.*subprocess.*env/,
	/node.*process\.env/,
];

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
