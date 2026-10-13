/**
 * CodeGraph CWD guidance - when the session runs inside a configured repository
 * root, tell the agent to use the structural code graph and when to index.
 *
 * Roots come from `codegraphRoots` in ~/.pi/agent/private.json. With no roots
 * configured, or a cwd outside them, nothing is injected.
 *
 * Configured roots are indexed on demand, not automatically: `codegraph-auto-index`
 * is disabled so `@estebanforge/pi-codegraph-enhanced` never creates an index on
 * its own (it still keeps existing ones fresh). This extension is the trigger -
 * inside a configured root it tells the agent to create the index when it is
 * missing. The upward search for `.codegraph` stops at the matched root, and a `.codegraph`
 * directory only counts as an index when it also holds `codegraph.db`, so neither a parent
 * project's index nor the CLI's global `~/.codegraph` state directory is mistaken for this
 * repo's.
 */

import { existsSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve, sep } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PRIVATE_FILE = join(homedir(), ".pi/agent/private.json");

function expandRoot(raw: string): string {
  const root = raw.trim();
  if (root === "~") return homedir();
  return resolve(root.startsWith("~/") ? join(homedir(), root.slice(2)) : root);
}

function loadRoots(): { roots: string[]; invalid: boolean } {
  try {
    const configured = JSON.parse(readFileSync(PRIVATE_FILE, "utf-8")).codegraphRoots;
    if (!Array.isArray(configured)) return { roots: [], invalid: configured !== undefined };
    const roots = configured
      .filter((root: unknown): root is string => typeof root === "string" && root.trim().length > 0)
      .map(expandRoot);
    return { roots, invalid: roots.length !== configured.length };
  } catch {
    return { roots: [], invalid: false };
  }
}

function matchingRoot(target: string, roots: string[]): string | undefined {
  const here = resolve(target);
  return roots
    .filter((root) => here === root || here.startsWith(root + sep))
    .sort((a, b) => b.length - a.length)[0];
}

function hasIndex(dir: string): boolean {
  const codegraph = join(dir, ".codegraph");
  try {
    if (!statSync(codegraph).isDirectory()) return false;
  } catch {
    return false;
  }
  return existsSync(join(codegraph, "codegraph.db"));
}

function findIndexDir(start: string, root: string): string | undefined {
  let dir = resolve(start);
  for (;;) {
    if (hasIndex(dir)) return dir;
    if (dir === root) return undefined;
    const parent = resolve(dir, "..");
    if (parent === dir) return undefined;
    if (!(parent === root || parent.startsWith(root + sep))) return undefined;
    dir = parent;
  }
}

export default function (pi: ExtensionAPI) {
  let reportedInvalid = false;

  pi.on("before_agent_start", async (event, ctx) => {
    if (!ctx.cwd) return;
    const { roots, invalid } = loadRoots();
    if (invalid && !reportedInvalid) {
      reportedInvalid = true;
      ctx.ui.notify(
        "codegraphRoots in ~/.pi/agent/private.json is not an array of paths - no CodeGraph guidance is injected",
        "info",
      );
    }
    const root = matchingRoot(ctx.cwd, roots);
    if (!root) return;

    const indexDir = findIndexDir(ctx.cwd, root);
    const section = indexDir
      ? [
          "## CodeGraph",
          `This work is inside an indexed repository (${indexDir}/.codegraph).`,
          "For architecture, call-site, impact, or \"where is X defined or used\" questions, prefer",
          "the `codegraph_*` tools over grep/read. The index is kept fresh automatically; if results",
          "still look stale, `codegraph status` inspects it.",
        ]
      : [
          "## CodeGraph",
          "This work is inside a configured repository root and should be indexed, but no",
          ".codegraph index exists here yet.",
          "Index it before structural work: `codegraph init` builds the graph in one step, and",
          "`/codegraph init` does the same on demand. Do not ask first - these roots are meant to be",
          "indexed. Then prefer the `codegraph_*` tools for architecture, call-site, impact, and",
          "\"where is X defined or used\" questions.",
        ];

    return { systemPrompt: `${event.systemPrompt}\n\n${section.join("\n")}` };
  });
}
