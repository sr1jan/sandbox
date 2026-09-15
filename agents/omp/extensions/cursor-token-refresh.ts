/**
 * Refresh omp's Cursor JWT before provider calls.
 *
 * Dashboard API keys (CURSOR_API_KEY) must be exchanged into a 1-hour
 * session JWT. This extension re-runs refresh-cursor-token when the JWT
 * is missing or near expiry, then overrides Authorization so a long
 * session can pick up a new token without restarting omp.
 *
 * Place in ~/.omp/agent/extensions/.
 */

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";

const REFRESH_BIN = "/usr/local/bin/refresh-cursor-token";
const OMP_ENV = `${process.env.HOME || "/home/agent"}/.omp/.env`;
const SKEW_SECS = 300;
const MIN_REFRESH_GAP_MS = 30_000;

let lastRefreshAt = 0;

function readEnvValue(path: string, key: string): string | undefined {
	let text: string;
	try {
		text = readFileSync(path, "utf-8");
	} catch {
		return undefined;
	}
	for (const raw of text.split("\n")) {
		const line = raw.trim().replace(/^export\s+/, "");
		if (!line.startsWith(`${key}=`)) continue;
		let val = line.slice(key.length + 1).trim();
		if (
			val.length >= 2 &&
			((val.startsWith("'") && val.endsWith("'")) ||
				(val.startsWith('"') && val.endsWith('"')))
		) {
			val = val.slice(1, -1);
		}
		return val || undefined;
	}
	return undefined;
}

function secondsLeft(token: string): number | undefined {
	const parts = token.split(".");
	if (parts.length < 2) return undefined;
	try {
		const padded = parts[1] + "=".repeat((4 - (parts[1].length % 4)) % 4);
		const payload = JSON.parse(Buffer.from(padded, "base64url").toString("utf-8"));
		if (typeof payload?.exp !== "number") return undefined;
		return payload.exp - Math.floor(Date.now() / 1000);
	} catch {
		return undefined;
	}
}

function currentToken(): string | undefined {
	return (
		process.env.CURSOR_ACCESS_TOKEN ||
		readEnvValue(OMP_ENV, "CURSOR_ACCESS_TOKEN")
	);
}

function needsRefresh(token: string | undefined): boolean {
	if (!token) return true;
	const left = secondsLeft(token);
	return left === undefined || left <= SKEW_SECS;
}

function refresh(): string | undefined {
	const now = Date.now();
	if (now - lastRefreshAt < MIN_REFRESH_GAP_MS && !needsRefresh(currentToken())) {
		return currentToken();
	}
	lastRefreshAt = now;
	const result = spawnSync("sudo", ["/usr/local/bin/run", REFRESH_BIN], {
		encoding: "utf-8",
		timeout: 20_000,
	});
	if (result.status !== 0) {
		return currentToken();
	}
	const token = currentToken();
	if (token) {
		process.env.CURSOR_ACCESS_TOKEN = token;
	}
	return token;
}

export default function (pi: ExtensionAPI) {
	const on = (name: string, handler: (...args: any[]) => unknown) => {
		try {
			(pi.on as (event: string, fn: (...args: any[]) => unknown) => void)(name, handler);
		} catch {
			// Older omp builds may not expose every lifecycle event.
		}
	};

	on("session_start", async () => {
		refresh();
	});

	on("before_agent_start", async () => {
		if (needsRefresh(currentToken())) {
			refresh();
		}
	});

	on("before_provider_headers", (event: { headers: Record<string, string | null> }) => {
		const token = needsRefresh(currentToken()) ? refresh() : currentToken();
		if (token) {
			event.headers.Authorization = `Bearer ${token}`;
		}
	});
}
