/**
 * Tmux Tools Extension
 *
 * Gives the MAIN agent tmux panes for the two jobs the shell tool can't do:
 * credentialed `sudo run` commands its credential guard refuses, and
 * services the user wants to watch live. Tests, builds and one-shot commands
 * belong in the shell tool (exit codes, full output).
 *
 * Panes open in a dedicated `agent-work` window of the agent's own tmux
 * session — never split into the window the user is looking at.
 *
 * Security:
 *   - Commands sent to panes go through the same credential guard patterns
 *   - Captured output is filtered to redact any credential-like strings
 *   - Max pane limit prevents runaway pane creation
 *
 * Place in ~/.pi/agent/extensions/ for global availability.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const MAX_PANES = 8;

// Credential patterns to redact from captured output.
// Loaded from shared/patterns/redactor.json — the same source the
// Claude Code PostToolUse redactor hook consumes.
interface RedactorPatterns {
	replacement: string;
	patterns: string[];
}

function loadRedactorPatterns(): RegExp[] {
	const candidates = [
		"/home/agent/.pi/agent/patterns/redactor.json",
		join(__dirname, "..", "patterns", "redactor.json"),
	];
	for (const path of candidates) {
		try {
			const parsed: RedactorPatterns = JSON.parse(readFileSync(path, "utf-8"));
			// Detect which patterns need the case-insensitive flag (those that
			// match identifier words like token/password/secret). In the
			// original hardcoded list these used /gi; all others used /g.
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

// Same bash patterns as cred-guard — block credential-exposing commands in panes
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

/**
 * Agent panes live in their own window. A bare `split-window` targets the
 * attached client's CURRENT window — whatever the user is looking at — so
 * every pane is placed explicitly. tmux removes the window when its last
 * pane closes.
 */
const WORK_WINDOW = "agent-work";

const shellQuote = (s: string): string => `'${s.replace(/'/g, `'\\''`)}'`;

/** The tmux session this agent runs in, not whichever one a client has focused. */
function agentSessionId(): string {
	const self = process.env.TMUX_PANE;
	return tmux(`display-message -p ${self ? `-t ${shellQuote(self)} ` : ""}"#{session_id}"`);
}

/**
 * Opens a pane in the agent-work window (creating the window on first use),
 * starting in the agent's cwd: `sudo run` loads credentials for the project
 * that contains the current directory.
 */
function openWorkPane(direction: "horizontal" | "vertical"): string {
	const session = agentSessionId();
	const window = shellQuote(`${session}:${WORK_WINDOW}`);
	const cwd = shellQuote(process.cwd());
	const windows = tmux(`list-windows -t ${shellQuote(session)} -F "#{window_name}"`).split("\n");
	if (!windows.includes(WORK_WINDOW)) {
		return tmux(
			`new-window -d -t ${shellQuote(`${session}:`)} -n ${WORK_WINDOW} -c ${cwd} -P -F "#{pane_id}"`,
		);
	}
	const flag = direction === "horizontal" ? "-h" : "-v";
	const paneId = tmux(`split-window -d ${flag} -t ${window} -c ${cwd} -P -F "#{pane_id}"`);
	tmux(`select-layout -t ${window} tiled`);
	return paneId;
}

/**
 * The module — and this map — can be shared by several sessions in one
 * process (subagents). So each pane records the session that created it,
 * and only that session's shutdown closes it.
 */
const managedPanes = new Map<string, { tmuxId: string; name: string; owner: string | undefined }>();

function sessionIdOf(ctx: unknown): string | undefined {
	return (ctx as { sessionManager?: { getSessionId?: () => string } } | undefined)?.sessionManager?.getSessionId?.();
}

/** Subagents share the user's tmux session but not their rules: tmux is main-agent only. */
function subagentRefusal(ctx: unknown) {
	if ((ctx as { agent?: { kind?: string } } | undefined)?.agent?.kind !== "sub") return undefined;
	return {
		content: [
			{
				type: "text" as const,
				text: "Error: tmux tools are for the main agent only. Run commands with the shell tool.",
			},
		],
		details: {},
	};
}

export default function (pi: ExtensionAPI) {
	// --- tmux_pane_create ---
	pi.registerTool({
		name: "tmux_pane_create",
		label: "Create tmux pane",
		description:
			"Open a pane in the dedicated `agent-work` tmux window (never the user's window), starting in your working directory. Only for a `sudo run` command the shell tool's credential guard refuses, or a service the user wants to watch live. Tests, builds and one-shot commands go through the shell tool. Main agent only. Returns a pane name for the other tmux tools.",
		parameters: Type.Object({
			direction: Type.Optional(
				Type.Union([Type.Literal("horizontal"), Type.Literal("vertical")], {
					description: "Split direction inside the agent-work window. Default: vertical",
				}),
			),
			name: Type.String({
				description: "A short name for this pane (e.g., 'server', 'probe')",
			}),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx?: unknown) {
			const refusal = subagentRefusal(ctx);
			if (refusal) return refusal;

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

			const tmuxId = openWorkPane(params.direction ?? "vertical");
			managedPanes.set(params.name, { tmuxId, name: params.name, owner: sessionIdOf(ctx) });

			return {
				content: [
					{ type: "text", text: `Created pane '${params.name}' in tmux window '${WORK_WINDOW}'` },
				],
				details: {},
			};
		},
	});

	// --- tmux_pane_send ---
	pi.registerTool({
		name: "tmux_pane_send",
		label: "Send to tmux pane",
		description:
			"Send a command or keystrokes to a named tmux pane. Credentialed commands: `sudo run <cmd>` from the project root (it loads that project's credentials). Anything that runs longer than a few seconds: `(sudo run setsid nohup <cmd> > /tmp/<job>.log 2>&1 &)`, then read the log with the shell tool, so the job survives the pane.",
		parameters: Type.Object({
			pane: Type.String({ description: "Pane name (from tmux_pane_create)" }),
			keys: Type.String({ description: "Command or keystrokes to send" }),
			enter: Type.Optional(
				Type.Boolean({
					description: "Press Enter after sending keys. Default: true",
				}),
			),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx?: unknown) {
			const refusal = subagentRefusal(ctx);
			if (refusal) return refusal;

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

			// Single-quoted: `$VAR`, `$(…)` and backticks must reach the pane
			// verbatim, not be expanded by this process's shell first.
			const enter = params.enter !== false ? "Enter" : "";
			tmux(`send-keys -t ${pane.tmuxId} ${shellQuote(params.keys)} ${enter}`);

			return {
				content: [{ type: "text", text: `Sent to '${params.pane}': ${params.keys}` }],
				details: {},
			};
		},
	});

	// --- tmux_pane_capture ---
	pi.registerTool({
		name: "tmux_pane_capture",
		label: "Capture tmux pane output",
		description:
			"Capture recent terminal output from a named tmux pane, with credential-like strings redacted. Screen scrape only: for output you need in full or after the pane is gone, redirect the command to a log file and read it with the shell tool.",
		parameters: Type.Object({
			pane: Type.String({ description: "Pane name (from tmux_pane_create)" }),
			lines: Type.Optional(
				Type.Number({
					description: "Number of lines to capture from the bottom. Default: 50",
				}),
			),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx?: unknown) {
			const refusal = subagentRefusal(ctx);
			if (refusal) return refusal;

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
					content: [{ type: "text", text: `Error: could not capture pane '${params.pane}' (may be closed)` }],
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

	// --- tmux_pane_close ---
	pi.registerTool({
		name: "tmux_pane_close",
		label: "Close tmux pane",
		description: "Close a named tmux pane. Kills the process running in it.",
		parameters: Type.Object({
			pane: Type.String({ description: "Pane name to close" }),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx?: unknown) {
			const refusal = subagentRefusal(ctx);
			if (refusal) return refusal;

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

	// --- tmux_pane_list ---
	pi.registerTool({
		name: "tmux_pane_list",
		label: "List tmux panes",
		description: "List all managed tmux panes with their names and status.",
		parameters: Type.Object({}),
		async execute(_id, _params, _signal, _onUpdate, ctx?: unknown) {
			const refusal = subagentRefusal(ctx);
			if (refusal) return refusal;

			if (managedPanes.size === 0) {
				return {
					content: [{ type: "text", text: "No managed panes. Use tmux_pane_create to create one." }],
					details: {},
				};
			}

			const lines: string[] = [];
			for (const [name, pane] of managedPanes) {
				let status = "unknown";
				try {
					const running = tmux(`display-message -t ${pane.tmuxId} -p "#{pane_current_command}"`);
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

	// --- Session lifecycle ---
	pi.on("session_start", async (_event, ctx) => {
		if (!isInsideTmux() && ctx.hasUI) {
			ctx.ui.notify("tmux-tools: not in tmux session, pane tools disabled", "warning");
		}
	});

	// Only the panes this session created: a subagent's shutdown must not
	// kill its parent's panes.
	pi.on("session_shutdown", async (_event, ctx) => {
		const session = sessionIdOf(ctx);
		for (const [name, pane] of managedPanes) {
			if (pane.owner !== session) continue;
			try {
				tmux(`kill-pane -t ${pane.tmuxId}`);
			} catch {
				// Pane may already be closed
			}
			managedPanes.delete(name);
		}
	});
}
