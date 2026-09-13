/**
 * Tmux Tools Extension (omp)
 *
 * Gives the agent control over tmux panes for running servers, tests,
 * log tailers, and other background processes. The agent can create panes,
 * send commands, capture output, and close panes.
 *
 * Security:
 *   - Commands sent to panes go through the same credential guard patterns
 *   - Captured output is filtered to redact any credential-like strings
 *   - Max pane limit prevents runaway pane creation
 *
 * Place in ~/.omp/agent/extensions/ for global availability.
 */

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const MAX_PANES = 8;

interface RedactorPatterns {
	replacement: string;
	patterns: string[];
}

function loadRedactorPatterns(): RegExp[] {
	const candidates = [
		"/home/agent/.omp/agent/patterns/redactor.json",
		join(__dirname, "..", "patterns", "redactor.json"),
		join(__dirname, "..", "..", "..", "shared", "patterns", "redactor.json"),
	];
	for (const path of candidates) {
		try {
			const parsed: RedactorPatterns = JSON.parse(readFileSync(path, "utf-8"));
			return parsed.patterns.map((p) => {
				const needsCaseInsensitive = /token|password|secret/i.test(p);
				return new RegExp(p, needsCaseInsensitive ? "gi" : "g");
			});
		} catch {
			continue;
		}
	}
	throw new Error("redactor.json not found");
}

const CREDENTIAL_PATTERNS = loadRedactorPatterns();

const BLOCKED_COMMANDS = [
	/\bcat\b.*\.env/,
	/\bless\b.*\.env/,
	/\bhead\b.*\.env/,
	/\btail\b.*\.env/,
	/\bsource\b.*\.env/,
	/\benv\s*($|\|)/,
	/\bprintenv\b/,
	/\/proc\/.*\/environ/,
	/\/etc\/devbox\/secrets/,
	/\bsudo\s+cat\b/,
	/\bsudo\s+bash\b/,
	/\bsudo\s+sh\b/,
	/\bsudo\s+-[is]\b/,
];

function redactCredentials(text: string): string {
	let result = text;
	for (const pattern of CREDENTIAL_PATTERNS) {
		result = result.replace(pattern, "[REDACTED]");
	}
	return result;
}

function isBlockedCommand(command: string): boolean {
	return BLOCKED_COMMANDS.some((p) => p.test(command));
}

function tmux(cmd: string): string {
	try {
		return execSync(`tmux ${cmd}`, { encoding: "utf-8", timeout: 5000 }).trim();
	} catch (err: any) {
		throw new Error(`tmux command failed: ${err.message}`);
	}
}

function isInsideTmux(): boolean {
	return !!process.env.TMUX;
}

const managedPanes = new Map<string, { tmuxId: string; name: string }>();

export default function (pi: ExtensionAPI) {
	const z = pi.zod;

	pi.registerTool({
		name: "tmux_pane_create",
		label: "Create tmux pane",
		description:
			"Create a new tmux pane in the current window. Use for running servers, tests, log tailers, or any background process. Returns a pane name you can reference in other tmux tools.",
		parameters: z.object({
			direction: z
				.union([z.literal("horizontal"), z.literal("vertical")])
				.describe("Split direction: horizontal (side-by-side) or vertical (top-bottom)"),
			name: z.string().describe("A short name for this pane (e.g., 'server', 'tests', 'logs')"),
			size: z
				.number()
				.optional()
				.describe("Pane size as percentage (10-80). Default: 50"),
		}),
		async execute(_id, params) {
			if (!isInsideTmux()) {
				return {
					content: [{ type: "text", text: "Error: not running inside a tmux session" }],
					details: {},
				};
			}

			if (managedPanes.size >= MAX_PANES) {
				return {
					content: [
						{
							type: "text",
							text: `Error: max pane limit (${MAX_PANES}) reached. Close unused panes first.`,
						},
					],
					details: {},
				};
			}

			if (managedPanes.has(params.name)) {
				return {
					content: [{ type: "text", text: `Error: pane '${params.name}' already exists` }],
					details: {},
				};
			}

			const flag = params.direction === "horizontal" ? "-h" : "-v";
			const size = params.size ? `-p ${Math.min(80, Math.max(10, params.size))}` : "";

			const tmuxId = tmux(`split-window ${flag} ${size} -P -F "#{pane_id}"`);
			managedPanes.set(params.name, { tmuxId, name: params.name });

			tmux("last-pane");

			return {
				content: [{ type: "text", text: `Created pane '${params.name}' (${params.direction})` }],
				details: {},
			};
		},
	});

	pi.registerTool({
		name: "tmux_pane_send",
		label: "Send to tmux pane",
		description:
			"Send a command or keystrokes to a named tmux pane. Use 'sudo run <cmd>' for commands that need project/CLI credentials.",
		parameters: z.object({
			pane: z.string().describe("Pane name (from tmux_pane_create)"),
			keys: z.string().describe("Command or keystrokes to send"),
			enter: z
				.boolean()
				.optional()
				.describe("Press Enter after sending keys. Default: true"),
		}),
		async execute(_id, params) {
			const pane = managedPanes.get(params.pane);
			if (!pane) {
				const available = Array.from(managedPanes.keys()).join(", ") || "(none)";
				return {
					content: [
						{
							type: "text",
							text: `Error: pane '${params.pane}' not found. Available: ${available}`,
						},
					],
					details: {},
				};
			}

			if (isBlockedCommand(params.keys)) {
				return {
					content: [{ type: "text", text: "Blocked: command may expose credentials" }],
					details: {},
				};
			}

			const enter = params.enter !== false ? "Enter" : "";
			const escaped = params.keys.replace(/"/g, '\\"');
			tmux(`send-keys -t ${pane.tmuxId} "${escaped}" ${enter}`);

			return {
				content: [{ type: "text", text: `Sent to '${params.pane}': ${params.keys}` }],
				details: {},
			};
		},
	});

	pi.registerTool({
		name: "tmux_pane_capture",
		label: "Capture tmux pane output",
		description:
			"Capture recent terminal output from a named tmux pane. Output is filtered to redact any credential-like strings. Use to check server logs, test results, or command output.",
		parameters: z.object({
			pane: z.string().describe("Pane name (from tmux_pane_create)"),
			lines: z
				.number()
				.optional()
				.describe("Number of lines to capture from the bottom. Default: 50"),
		}),
		async execute(_id, params) {
			const pane = managedPanes.get(params.pane);
			if (!pane) {
				const available = Array.from(managedPanes.keys()).join(", ") || "(none)";
				return {
					content: [
						{
							type: "text",
							text: `Error: pane '${params.pane}' not found. Available: ${available}`,
						},
					],
					details: {},
				};
			}

			const lines = params.lines ?? 50;
			const start = -lines;

			let output: string;
			try {
				output = tmux(`capture-pane -t ${pane.tmuxId} -p -S ${start}`);
			} catch {
				return {
					content: [
						{
							type: "text",
							text: `Error: could not capture pane '${params.pane}' (may be closed)`,
						},
					],
					details: {},
				};
			}

			const redacted = redactCredentials(output);

			return {
				content: [{ type: "text", text: redacted || "(empty)" }],
				details: {},
			};
		},
	});

	pi.registerTool({
		name: "tmux_pane_close",
		label: "Close tmux pane",
		description: "Close a named tmux pane. Kills the process running in it.",
		parameters: z.object({
			pane: z.string().describe("Pane name to close"),
		}),
		async execute(_id, params) {
			const pane = managedPanes.get(params.pane);
			if (!pane) {
				return {
					content: [{ type: "text", text: `Error: pane '${params.pane}' not found` }],
					details: {},
				};
			}

			try {
				tmux(`kill-pane -t ${pane.tmuxId}`);
			} catch {
				// Pane may already be closed
			}
			managedPanes.delete(params.pane);

			return {
				content: [{ type: "text", text: `Closed pane '${params.pane}'` }],
				details: {},
			};
		},
	});

	pi.registerTool({
		name: "tmux_pane_list",
		label: "List tmux panes",
		description: "List all managed tmux panes with their names and status.",
		parameters: z.object({}),
		async execute() {
			if (managedPanes.size === 0) {
				return {
					content: [
						{
							type: "text",
							text: "No managed panes. Use tmux_pane_create to create one.",
						},
					],
					details: {},
				};
			}

			const lines: string[] = [];
			for (const [name, pane] of managedPanes) {
				let status = "unknown";
				try {
					const running = tmux(
						`display-message -t ${pane.tmuxId} -p "#{pane_current_command}"`,
					);
					status = running || "idle";
				} catch {
					status = "closed";
					managedPanes.delete(name);
				}
				lines.push(`${name}: ${status}`);
			}

			return {
				content: [{ type: "text", text: lines.join("\n") }],
				details: {},
			};
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		if (!isInsideTmux() && ctx.hasUI) {
			ctx.ui.notify("tmux-tools: not in tmux session, pane tools disabled", "warning");
		}
	});

	pi.on("session_shutdown", async () => {
		for (const [, pane] of managedPanes) {
			try {
				tmux(`kill-pane -t ${pane.tmuxId}`);
			} catch {
				// Ignore
			}
		}
		managedPanes.clear();
	});
}
