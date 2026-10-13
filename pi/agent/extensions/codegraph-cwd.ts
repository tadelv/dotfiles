/**
 * CodeGraph CWD guidance - when the session runs inside a configured repository
 * root, tell the agent to use the structural code graph and to create the index
 * if it is missing.
 *
 * Roots come from `codegraphRoots` in ~/.pi/agent/private.json. With no roots
 * configured, or a cwd outside them, nothing is injected.
 *
 * Configured roots are auto-indexed: `codegraph-auto-index` is enabled, so
 * `@estebanforge/pi-codegraph-enhanced` creates and maintains the index. This
 * extension only adds guidance; index maintenance stays with that package.
 */

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve, sep } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PRIVATE_FILE = join(homedir(), ".pi/agent/private.json");

function codegraphRoots(): string[] {
  try {
    const roots = JSON.parse(readFileSync(PRIVATE_FILE, "utf-8")).codegraphRoots;
    if (!Array.isArray(roots)) return [];
    return roots
      .filter((root: unknown): root is string => typeof root === "string" && root.trim().length > 0)
      .map((root: string) => resolve(root.startsWith("~/") ? join(homedir(), root.slice(2)) : root));
  } catch {
    return [];
  }
}

function isInside(target: string, roots: string[]): boolean {
  const here = resolve(target);
  return roots.some((root) => here === root || here.startsWith(root + sep));
}

function findIndexDir(start: string): string | undefined {
  let dir = resolve(start);
  for (;;) {
    if (existsSync(join(dir, ".codegraph"))) return dir;
    const parent = resolve(dir, "..");
    if (parent === dir) return undefined;
    dir = parent;
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", async (event, ctx) => {
    const roots = codegraphRoots();
    if (roots.length === 0 || !isInside(ctx.cwd, roots)) return;

    const indexDir = findIndexDir(ctx.cwd);
    const section = indexDir
      ? [
          "## CodeGraph",
          `This work is inside an indexed repository (${indexDir}/.codegraph).`,
          "For architecture, call-site, impact, or \"where is X defined or used\" questions, prefer",
          "the `codegraph_*` tools over grep/read. If results look stale after a large change, run",
          "`codegraph sync` (or `codegraph status` to inspect) before searching.",
        ]
      : [
          "## CodeGraph",
          "This work is inside a configured repository root, which is auto-indexed, but no",
          ".codegraph index exists here yet.",
          "Create it rather than asking: `codegraph init -i` builds the graph in one step, and",
          "`/codegraph init` does the same on demand. Once `.codegraph/` exists, prefer the",
          "`codegraph_*` tools for architecture, call-site, impact, and \"where is X defined or",
          "used\" questions.",
        ];

    return { systemPrompt: `${event.systemPrompt}\n\n${section.join("\n")}` };
  });
}
