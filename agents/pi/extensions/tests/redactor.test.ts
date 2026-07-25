import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { scrubText } from "../redactor.ts";

const raw = JSON.parse(
	readFileSync(join(__dirname, "../../../../shared/patterns/redactor.json"), "utf-8"),
);
const patterns: RegExp[] = raw.patterns.map((p: string) => new RegExp(p, "g"));
const R = raw.replacement;

// Each credential shape is scrubbed
assert.equal(scrubText("key: sk-ant-abc123_XYZ-456789012345", patterns, R), `key: ${R}`);
assert.equal(
	scrubText("or: sk-or-v1-" + "a".repeat(64), patterns, R),
	`or: ${R}`,
);
assert.equal(
	scrubText("zai: " + "0123456789abcdef".repeat(2) + ".a1B2c3D4e5F6g7H8", patterns, R),
	`zai: ${R}`,
);
assert.equal(
	scrubText("ds: sk-abcdefghij0123456789abcdefghij01", patterns, R),
	`ds: ${R}`,
);
// Non-credentials pass through untouched
assert.equal(scrubText("hello plain world", patterns, R), "hello plain world");
// Multiple occurrences in one blob all scrubbed
const multi = "a sk-ant-tok_1234567890 b ghp_" + "c".repeat(36) + " d";
assert.equal(scrubText(multi, patterns, R), `a ${R} b ${R} d`);

console.log("redactor.test.ts: all assertions passed");
