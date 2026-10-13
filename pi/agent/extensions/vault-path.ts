/**
 * Vault Path extension - resolves the Obsidian vault root at session start.
 *
 * Resolution order:
 *   1. `obsidian eval code="app.vault.adapter.basePath"` when Obsidian is running
 *   2. `obsidianVault` from ~/.pi/agent/private.json (gitignored, per machine)
 *   3. `OBSIDIAN_VAULT` from the environment
 *
 * When none resolve, nothing is injected and the operator is told what to set.
 * The vault path is never hardcoded here, so this file is safe to version.
 *
 * Injects the vault path as a constant block so the agent can reference it
 * directly in read/edit/write calls without spending tool calls to discover it.
 */

import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PRIVATE_FILE = join(homedir(), ".pi/agent/private.json");

function readPrivate(key: string): string | undefined {
  try {
    const value = JSON.parse(readFileSync(PRIVATE_FILE, "utf-8"))[key];
    return typeof value === "string" && value.trim() ? value.trim() : undefined;
  } catch {
    return undefined;
  }
}

function expandHome(path: string): string {
  return path.startsWith("~/") ? join(homedir(), path.slice(2)) : path;
}

function detectVaultRoot(): string {
  try {
    const result = execSync(
      `obsidian eval code="app.vault.adapter.basePath"`,
      { encoding: "utf-8", stdio: "pipe", timeout: 2000 },
    ).trim();
    if (result) return result;
  } catch {
    // Obsidian not running or not installed
  }
  const configured = readPrivate("obsidianVault") ?? process.env.OBSIDIAN_VAULT;
  if (!configured) return "";
  const expanded = expandHome(configured);
  return isAbsolute(expanded) ? expanded : "";
}

export default function (pi: ExtensionAPI) {
  let vaultRoot = "";

  pi.on("session_start", async (_event, ctx) => {
    vaultRoot = detectVaultRoot();
    ctx.ui.notify(
      vaultRoot
        ? `Vault root: ${vaultRoot}`
        : "Vault root unresolved - set obsidianVault in ~/.pi/agent/private.json",
      "info",
    );
  });

  pi.on("before_agent_start", async (event) => {
    if (!vaultRoot) vaultRoot = detectVaultRoot();
    if (!vaultRoot) return;
    return {
      systemPrompt: `${event.systemPrompt}\n\n## Obsidian notes vault\nVault root: \`${vaultRoot}\`\nCommon paths (relative to vault root):\n- Sprint tasks: \`Professional/Decent/TODO.md\`\n- Roadmap: \`Professional/Decent/Timeline.md\`\n- DA items: \`Professional/Decent/ReaPrime/TODO.md\`\n- HDS tasks: \`Professional/Decent/HDS/TODO.md\`\n- Bengle tasks: \`Professional/Decent/Bengle/TODO.md\`\n- DE1 tasks: \`Professional/Decent/DE1/TODO.md\`\n- Playbook: \`Professional/Decent/Playbook.md\`\n\nUse \`read\`/\`edit\`/\`write\` on the full path directly (e.g. \`${vaultRoot}/Professional/Decent/TODO.md\`). No obsidian-cli needed for file access.`,
    };
  });
}
