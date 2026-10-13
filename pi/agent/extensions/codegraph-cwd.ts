/**
 * CodeGraph CWD guidance - when the session runs inside a configured repository
 * root, tell the agent whether a CodeGraph index applies here and what to do
 * when it does not.
 *
 * Roots come from `codegraphRoots` in ~/.pi/agent/private.json. With no roots
 * configured, or a cwd outside them, nothing is injected.
 *
 * Indexes are created on demand, not automatically: `codegraph-auto-index` is
 * disabled so `@estebanforge/pi-codegraph-enhanced` never creates one. It
 * refreshes only an index in the session's own directory, while the codegraph
 * CLI daemon keeps the nearest ancestor index fresh once the tools are used.
 * This extension is the trigger - inside a configured root it tells the agent
 * to index the directory when no index covers it. The upward search
 * stops at the matched root, and a `.codegraph` directory counts as an index
 * only when it also holds `codegraph.db` as a file, so neither the CLI's global
 * `~/.codegraph` state directory nor an unrelated ancestor is mistaken for one.
 */

import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join, resolve, sep } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PRIVATE_FILE = join(homedir(), ".pi/agent/private.json");

type RootProblem = "not-array" | "entries" | "unreadable";

const PROBLEM_MESSAGES: Record<RootProblem, string> = {
  "not-array":
    "codegraphRoots in ~/.pi/agent/private.json must be an array of paths - no CodeGraph guidance is injected",
  entries:
    "some codegraphRoots entries in ~/.pi/agent/private.json were ignored (use ~/... or absolute paths)",
  unreadable:
    "~/.pi/agent/private.json could not be read or parsed - no CodeGraph guidance is injected until it is fixed",
};

function supportedRoot(raw: string): boolean {
  const root = raw.trim();
  return root === "~" || root.startsWith("~/") || isAbsolute(root);
}

function expandRoot(raw: string): string {
  const root = raw.trim();
  if (root === "~") return homedir();
  return resolve(root.startsWith("~/") ? join(homedir(), root.slice(2)) : root);
}

function loadRoots(): { roots: string[]; problem?: RootProblem } {
  let configured: unknown;
  try {
    configured = JSON.parse(readFileSync(PRIVATE_FILE, "utf-8")).codegraphRoots;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException)?.code;
    return { roots: [], problem: code === "ENOENT" ? undefined : "unreadable" };
  }
  if (configured === undefined) return { roots: [] };
  if (!Array.isArray(configured)) return { roots: [], problem: "not-array" };
  const entries = configured.filter(
    (root): root is string => typeof root === "string" && root.trim().length > 0,
  );
  const usable = entries.filter(supportedRoot).map(expandRoot);
  return {
    roots: usable,
    problem: usable.length === configured.length ? undefined : "entries",
  };
}

function within(target: string, root: string): boolean {
  const here = resolve(target);
  return here === root || here.startsWith(root === sep ? sep : root + sep);
}

function matchingRoot(target: string, roots: string[]): string | undefined {
  return roots.filter((root) => within(target, root)).sort((a, b) => b.length - a.length)[0];
}

function hasIndex(dir: string): boolean {
  const codegraph = join(dir, ".codegraph");
  try {
    if (!statSync(codegraph).isDirectory()) return false;
    return statSync(join(codegraph, "codegraph.db")).isFile();
  } catch {
    return false;
  }
}

function indexFor(start: string, root: string): string | undefined {
  let dir = resolve(start);
  for (;;) {
    if (hasIndex(dir)) return dir;
    if (dir === root) return undefined;
    const parent = resolve(dir, "..");
    if (parent === dir || !within(parent, root)) return undefined;
    dir = parent;
  }
}

export default function (pi: ExtensionAPI) {
  let reported: RootProblem | undefined;

  pi.on("before_agent_start", async (event, ctx) => {
    if (!ctx.cwd) return;
    const { roots, problem } = loadRoots();
    if (problem !== reported) {
      reported = problem;
      if (problem) ctx.ui.notify(PROBLEM_MESSAGES[problem], "info");
    }
    const root = matchingRoot(ctx.cwd, roots);
    if (!root) return;

    const indexDir = indexFor(ctx.cwd, root);
    const section = indexDir
      ? [
          "## CodeGraph",
          `An index applies to this directory: ${indexDir}/.codegraph (the CLI resolves upward like git,`,
          "so a parent index also covers subdirectories). If results look stale after a large change,",
          "run `codegraph sync` in that directory before trusting them.",
        ]
      : [
          "## CodeGraph",
          "No CodeGraph index covers this directory yet, so the codegraph_* tools return nothing until",
          "one exists. Index it rather than asking: run `codegraph init` in this repository's own",
          "directory, not in a parent container of repositories. Then prefer the codegraph_* tools for",
          "architecture, call-site, impact, and \"where is X defined or used\" questions.",
        ];

    return { systemPrompt: `${event.systemPrompt ?? ""}\n\n${section.join("\n")}` };
  });
}
