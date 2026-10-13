# Global Pi Instructions

Loaded in every session, so it stays short. Task-specific depth lives in skills, which Pi surfaces
by description and loads only when you actually read them.

## Session start

Run `/context` — one `codemode` call that gathers git status, open PRs, the lane board and CodeGraph
state.

## Working with me

- Non-trivial changes (new feature, refactor, multi-file fix) start with a short plan in chat. Write
  it to a file only when it spans sessions.
- **Load skills by task, not on session start.** Read a skill when its work actually appears:
  `decent-sb-dev` for ReaPrime/Decaid, `decent-playbook` for Decent domain context, and
  `obsidian-todo-sync` only when syncing TODOs — not to answer "what is in flight".
- Obsidian vault: the root is injected by the `vault-path` extension along with its common paths.
  Read those files directly; looking something up does not need a skill. `obsidian help` covers vault
  CLI work.

## Output discipline

Compress when compression helps; stop when it costs more than it saves.

- Small, bounded output is fine to read directly — `gh issue list`, a single file, a short diff. Do
  not archive or re-fetch something you could simply read.
- `raw: true` only when byte-exact stdout matters and the output is under ~8 KiB. When you must quote
  something exactly — an issue body, a commit message — read the file, not a compressed rendering.
- Never dump unbounded output into the transcript: builds, test runs, logs, recursive searches, full
  diffs. Save it to a file, summarise, then inspect only the relevant ranges.
- Prefer `rtk err` / `rtk test` / `rtk log` for noisy commands when they keep the evidence you need.
- One `codemode` script beats a chain of shell calls for independent probes, and beats an archive
  round-trip for filtering a long run down to its failures.
