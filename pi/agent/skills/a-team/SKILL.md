---
name: a-team
description: Run a configurable worker-plus-reviewer pipeline for implementation work, and orchestrate several such pipelines as parallel lanes in separate git worktrees. Use when the user says "use the a-team", "a-team this", "run the a-team", "worker and reviewer", or wants a task implemented by a cheap/free worker and independently verified by a strong reviewer without naming models — including multi-issue work split across worktrees with the agent-wt CLI.
---

# A-Team

A worker implements, a strong reviewer independently verifies, the parent orchestrates and owns validation, commits, and scope.

The protocol runs at two scales. **Phases 0–4 are one lane** — one worktree, one change. The **orchestrator role** drives several lanes at once, one worktree each, using the `agent-wt` CLI. Read that section too whenever a request spans more than one issue; it carries the lane board, the `agent-wt` push trap, the nested-tool ceiling, and integration/publication rules.

## Orchestrator quickstart

From "the user names an issue" to a running lane lead in two calls.

**1. Preflight** — allocates (or reuses) the `agent-wt` worktree and materialises the lane brief:

```sh
~/.pi/agent/skills/a-team/scripts/lane_preflight.sh 973 --publish pr
```

It writes `.lane/{issue.json,issue.md,gate.md,brief.md}` inside the worktree (the issue body never
passes through output compression), excludes `.lane/` and `.codegraph/` from lane dirt, and prints
the lane board plus the launch snippet. `--publish` is `none` (default) `| push | pr | pr-pause`: it
tells *you* what to do at the end — the lane lead never pushes at any level.

Pass lane-specific constraints with `-c "..."`; they land in the brief's constraints section.

**2. Launch** — the task is two lines because the brief carries the rest:

```
subagent({ agent: 'ateam-lead', cwd: '<worktree-from-preflight>', async: true,
           task: 'Read .lane/brief.md in your worktree and execute it as your lane brief; it and the repo AGENTS.md win over your defaults.' })
```

Then:

1. **Yield.** Do not poll; native completion wakes you.
2. **Answer escalations.** A lead's `contact_supervisor` (`need_decision`) blocks it and wakes you.
   Reply with `subagent_supervisor({ action: 'reply', replyTo: '<id>', message: '<answer>' })`. See
   "Escalation channel" for depth and timeout.
3. **Validate yourself.** Run the repo gate at the lane HEAD and read the product diff. A lead's
   transcript is a claim, not evidence.
4. **Publish** — only at the level `--publish` asked for. Push with an explicit refspec, verify both
   refs, then `gh pr create --base <default> --body-file <pr-body>`.

---

Routing is **native to pi-subagents** — this skill is the protocol, not a router. Each launch resolves one model; there is no in-launch fallback chain. The user never names a model; they say "use the a-team" and the team comes from configuration.

| Concern | Where it lives |
| --- | --- |
| Worker/reviewer **models and thinking** | `subagents.agentOverrides` in `settings.json`, or a saved profile |
| Worker/reviewer **prompt, tools, context, timeout** | `~/.pi/agent/agents/ateam-{worker,reviewer}.md` |
| **The process** (phases, evidence, review) | this skill |
| **Protocol-level model check** | `~/.pi/agent/skills/a-team/scripts/probe_models.py` |

## Routing (native — do not reimplement)

- `subagents.agentOverrides.<name>.model` / `.thinking` in `~/.pi/agent/settings.json` (user) or `.pi/settings.json` (project, wins).
- Precedence, strongest first: **per-run override → provider-scoped role override → `agentOverrides` → agent frontmatter → `subagents.defaultModel` → parent session model**.
- Saved profiles live in `~/.pi/agent/profiles/pi-subagents/*.json` and are applied with `/subagents-load-profile <name>`. The shipped ones:

| Profile | Worker | Reviewer / oracle | Researcher | Scout / delegate |
| --- | --- | --- | --- | --- |
| `daily` **(default)** | `luna:high` | `sol:high` | `luna:medium` | `deepseek-flash:low` |
| `free` | `nex-n2.5-pro:free` | `sol:high` | `nex-n2.5-pro:free` | `nex-n2.5-mini:free` |

Pi-subagents no longer switches models during a launch. If a model fails, fix the profile or make a later, explicit retry; do not hand-roll a fallback loop or silently change execution mode.

Thinking level does not set the price — the model tier does, and a worker is output-token-heavy (reasoning plus generated code). Measured $/M in→out: `sol` 5→30, `astra` 10→50, `luna` 0.2→1.2, `deepseek-flash` 0.3→1.2. So `sol:low` is a *more expensive* worker than `luna:high` despite the lower effort: low thinking trims output tokens, it does not change a 25x output price.

Each profile covers the whole team — `ateam-worker`, `ateam-reviewer` and the builtin `worker`, `reviewer`, `oracle`/`advisor`, `researcher`, `evidence-auditor`, `scout`, `delegate` — because **loading a profile replaces the entire `agentOverrides` map** (unrelated keys like `disableBuiltins`, `modelScope`, `watchdog` survive). External CLI agents (`claude-code-*`, `codex-exec-*`, `cursor-agent-*`) are deliberately not listed: their model comes from their own runner, not from a pi model id.

Load with `/subagents-load-profile daily` or `/subagents-load-profile free`. The `free` profile keeps the reviewer on `sol:high` — verification is the one place a free model is a false economy. Change that line if you want it fully free.

So "use the a-team on the free profile" means: `/subagents-load-profile free`, then run the phases. Loading a profile writes `agentOverrides`, and it stays until another profile (or an edit) replaces it.

Agent frontmatter keeps a sane `model` so the agent still works standalone if no override is loaded. Overrides win — that is the intended default-vs-override split, not duplication.

## Phase 0 — know the team

Nothing to resolve. If the user named a profile, load it first. If the last profile is unknown or a run has been flaky, verify once:

```sh
python3 ~/.pi/agent/skills/a-team/scripts/probe_models.py              # default profile
python3 ~/.pi/agent/skills/a-team/scripts/probe_models.py --profile free
python3 ~/.pi/agent/skills/a-team/scripts/probe_models.py --settings   # effective settings.json
python3 ~/.pi/agent/skills/a-team/scripts/probe_models.py --show-free  # live free model ids
```

It probes each OpenRouter model for two protocol failures — tool calls emitted as text instead of structured `tool_calls`, and tool results rejected on turn two — then prints a verdict and exits non-zero if a model is unusable. Non-OpenRouter models are reported as not probed (they need their own provider API). Run it after editing a profile, and when a run fails in a way that looks like the model rather than the task.

## Phase 1 — the lane lead authors

**Default: the lane lead writes the change.** A nested `ateam-worker` is a depth-2 child and pi
withholds `bash` from it (see "A worker child loses `bash` at any depth"), so it cannot run the gate or prove
red→green. Dispatch it only for shell-free text edits that the lead will validate. The rest of
this phase describes that optional worker path; skip it when in doubt.

If you do use a worker: launch it async with fresh context; you are woken on completion, then
validate. (`context: 'fresh'` is that agent's default — pass it explicitly only if you changed it.)

```
subagent({ agent: 'ateam-worker', cwd: '<worktree>', async: true, task: '<task>' })
```

**Do not pass `model:` by default.** The configured profile supplies the model for this launch. If it is unusable, fix the profile or make a later explicit retry with an approved exact model; do not hand-roll fallback or silently switch execution modes.

The task string must state: repo and branch, no commit/push; the exact files the worker may touch, and that anything else must be reverted; the wanted behaviour and acceptance criteria; the red→green evidence required for behavioural change; and the focused check to run while iterating (not the full suite).

Keep scope small — one file plus one focused test. Split work that is larger, or run it on a paid profile.

## Phase 2 — validate as the parent

Run the repository's real gates yourself, the same commands CI runs. Then clean up after the toolchain:

- revert any tracked file a gate mutated that the task did not ask to change;
- revert repo-wide formatter churn when the tree was committed under an older SDK (keep the diff scoped);
- prove any failure is pre-existing by stashing your changes and re-running the same test at `HEAD`;
- if a gate produces a long transcript, filter it with `codemode` (failures and counts, not the whole
  log) instead of archiving and expanding it later.

## Phase 3 — dispatch the reviewer

The reviewer is read-only with no shell, so hand it the diff and the evidence:

```sh
git diff HEAD > .review-diff.patch    # delete before committing
```

Launch it async with fresh context:

```
subagent({ agent: 'ateam-reviewer', cwd: '<worktree>', async: true, task: '<review packet>' })
```

Include in its task: the diff path, files to read for context, the numbered acceptance criteria, the scope constraints, your validation transcripts, and any environment caveats that are **not** part of the change. Ask for the verdict, per-requirement confirmations with `file:line`, and a false-positive assessment of each new test.

## Phase 4 — close out

Apply blocking fixes (verify them against the code; a strong reviewer is usually right, but check). Then: confirm `git status --short` shows only intended files, delete the temporary diff, commit/push or update the PR **only if asked**, and report what changed, the red/green evidence, validation results, the verdict, and residual risk.

## Orchestrator role — many lanes, many worktrees

Phases 0–4 describe **one lane**. When a request spans several independent issues, the orchestrator
runs N lanes in parallel — one worktree each — and owns everything a lane lead must not touch.

| Role | Owns | Must not |
| --- | --- | --- |
| **Orchestrator** | worktrees, lane dispatch, integration, push/PR | implement lane code; hand-resolve lane-local conflicts |
| **Lane lead** (`ateam-lead`) | one worktree, Phases 1–4, its local commit | touch another worktree, push, open/update a PR |

### Escalation channel — who receives `contact_supervisor`

Depth decides the recipient, and it matters when you brief a lead:

- **Depth 1 — lane lead → you (the orchestrator).** `contact_supervisor` with `reason: 'need_decision'`
  writes a request, blocks the lead, and **wakes your session**. Re-read it with
  `subagent_supervisor({ action: 'pending' })`; unblock with
  `{ action: 'reply', replyTo: '<id>', message: '...' }`. This is the refinement checkpoint working.
- **Depth 2 — a nested reviewer or researcher → its lane lead,** not you. The root can neither see nor
  answer it; the lead resolves it (hard-won rule 12).

The child waits **10 minutes** by default (`PI_INTERCOM_ASK_TIMEOUT_MS`, in milliseconds). For an
interactive lane where the human may step away, export a longer value before launching, or brief the
lead to report the question instead of guessing if the wait times out.

### Allocate worktrees with `agent-wt`

```sh
agent-wt issue 29          # -> <repo>-worktrees/issue-29, branch agent/issue-29, from origin/main
agent-wt pr 905            # PR checkout worktree
agent-wt status --json     # the lane board; drive decisions from this, not from prose
agent-wt rm issue-29       # refuses if the worktree holds uncommitted work
```

`scripts/lane_preflight.sh <issue>` wraps allocation plus brief materialisation — prefer it (see
Orchestrator quickstart).

`agent-wt` finds the primary repo and worktree root itself (`<repo>-worktrees/` beside it, or
`AGENT_WORKTREE_ROOT`), and refuses to open an issue that is not `OPEN`. `status --json` is an
array with one object per managed worktree:

| field | meaning |
| --- | --- |
| `name` / `path` | `issue-<n>` / `pr-<n>` and its absolute path |
| `kind` / `number` | `issue`, `pr`, or `other`; the number for `issue`/`pr` |
| `branch` / `detached` / `head` | current branch, detached-ness, HEAD sha |
| `dirty` | uncommitted work — a lane reporting success with `dirty: true` is lying or mid-write |
| `upstream`, `upstreamAhead`, `upstreamBehind` | divergence from the branch it started from |
| `base`, `baseAhead`, `baseBehind` | divergence from the default branch |

Poll it between phases: `dirty` catches a lane that died mid-edit, and `baseBehind > 0` tells you a
lane needs a rebase. Three catches:

- `dirty` counts *untracked* files, so tooling dirs such as `.codegraph/` report `dirty: true` with
  no real change — confirm with `git status --short` before acting (`lane_preflight.sh` excludes those).
- `agent-wt issue <n>` errors if the worktree already exists; reuse through the preflight rather than
  re-invoking it raw.
- After a **rebase or rebase-merge** GitHub rewrites the SHAs, so `baseAhead` stays `> 0` for a branch
  whose work is already fully on the base — the lane board cannot see a merge. Confirm with
  `git cherry -v <base> <branch>`: every `-` means that patch is already upstream, so the lane is
  stale and safe to remove (`agent-wt rm <name>`, then `git branch -D <branch>`).

### The `agent-wt` push trap — read before publishing

`agent-wt` creates the worktree branch with its **upstream set to `origin/main`**. On a machine with
`push.default=tracking`, a bare push therefore targets the *upstream* branch:

```sh
git push -u origin agent/issue-29      # WRONG: fast-forwards MAIN and creates no branch
```

The tell is the output line — `agent/issue-29 -> main`. Sibling lanes then fail as
non-fast-forward, which is usually how it surfaces. Never push from a lane without an explicit
destination:

```sh
git -C <worktree> -c push.default=current push origin agent/issue-29
git -C <worktree> branch --set-upstream-to=origin/agent/issue-29 agent/issue-29
```

Verify every push, both refs:

```sh
git -C <worktree> ls-remote origin refs/heads/agent/issue-29   # must equal local HEAD
git -C <worktree> ls-remote origin refs/heads/main             # must be UNCHANGED
```

Undoing it needs a deliberate force-push back (`git push --force-with-lease=refs/heads/main:<sha>
origin refs/heads/main:refs/heads/main`), safe only on an unprotected branch when you know the
exact prior sha. Cheaper to verify than to unwind.

### Give the lane lead a `subagent` tool, and bound it

No builtin agent can spawn subagents, so a lane lead needs an agent definition whose `tools`
include `subagent`. That is the entire reason a lane-lead agent exists:

```markdown
---
name: ateam-lead
tools: read, grep, find, ls, bash, edit, write, subagent, contact_supervisor
allowedAgents: ateam-worker, ateam-reviewer
allowNestedSubagents: true
defaultContext: fresh
systemPromptMode: replace
---
```

`allowedAgents` keeps a lane from fanning out arbitrarily. Depth matters too: with the default
`maxSubagentDepth: 2`, the whole budget is orchestrator (0) → lane lead (1) → reviewer (2).

### Dispatch every lane in ONE async workflow

`runs.all` accepts a per-child `cwd`, which is what lets one workflow cover many worktrees:

```js
const lanes = [
  { key: 'issue29', cwd: '<root>/issue-29', label: 'Fix #29 rejection path', task: T29 },
  { key: 'issue30', cwd: '<root>/issue-30', label: 'Fix #30 ownership', task: T30 },
];
const results = await runs.all(lanes.map((l) => ({
  key: l.key, label: l.label, agent: 'ateam-lead', cwd: l.cwd, task: l.task
})));
return results.map((r) => ({ key: r.key, state: r.state, ok: r.ok, runId: r.runId, output: r.output }));
```

Build lane tasks in a script file and validate it before spending child budget
(`subagent({ action: 'validate', workflow: './lanes.js' })`). It catches a template literal that
closed early — the usual cause is an unescaped backtick inside a task string.

### Use `codemode` for fan-out and filtering, not as a mode

`codemode` is a model-facing tool: a JavaScript sandbox that calls other tools and returns only what
you keep. It does **not** change how children dispatch their tools, so it is safe to use alongside
`subagent` — unlike a fabric-style full code mode, which takes over tool execution and leaves every
child shown an executor it does not have. Three places it pays for itself:

- **Lane board.** One call instead of N shells: run `agent-wt status --json`, `git -C <wt> status
  --short` and `gh pr checks` across every lane, and return only `{name, dirty, baseBehind, checks}`.
- **Gate output.** Filter a long build/test run down to the failing lines and counts instead of
  archiving the transcript and expanding it later.
- **Review packets.** Assemble diff stat, changed files and criteria in one script rather than
  several reads.

Keep the sandbox in mind: it has no filesystem or network of its own, so it can only orchestrate the
tools it is given.

### A worker child loses `bash` at any depth — the lane lead authors

`bash` is withheld from an `ateam-worker` child **regardless of who launches it or how deep it sits**
— a child-safety default, not a setting you can toggle. Verified twice: an `ateam-worker` declaring
`read, grep, find, ls, bash, edit, write` resolved to
`read, grep, find, ls, edit, write, contact_supervisor` — `bash` silently dropped, `edit`/`write`
kept — once as a depth-2 child of a lane lead, and once as a **depth-1 child of the orchestrator
itself**. An `ateam-lead` at the same depth *keeps* `bash`; the only declared difference is the
orchestrator role (`subagent` in `tools:` plus `allowNestedSubagents: true`), so that is the likely
discriminator — not depth.

Without `bash` a worker cannot run a gate, so it cannot produce red→green evidence, and it will
correctly refuse to pretend otherwise. Do not build a lane that needs a shell around one.

So do not build a lane around a worker child. **The lane lead keeps `bash`: it authors
the change and runs the gate itself**, exactly as Phase 2 describes. `ateam-worker` is not part of
the default lane; use it only for work that needs no shell (pure text edits the lead validates),
and check its tools first with `subagent({ action: 'status', id })` — if `bash` is absent, collapse
immediately instead of waiting for it to park in `contact_supervisor`. Independent verification is
unaffected: the read-only `ateam-reviewer` needs no shell. State the deviation in the report.

### Research and audit children lose `bash` *and* `write` — worse than the worker case

The same withholding hits read-only research, where it does more damage, because searching *is* the
method. Verified on a real run: a `researcher` declaring `read, write, web_search, bash` and an
`evidence-auditor` declaring `read, web_search, bash` both reported **no shell and no write tool**.
Three consequences, all of which degrade the product silently:

- **No shell means no negative results.** The child cannot run `grep`/`find`, so "X does not exist",
  "nothing consumes Y", "Z is absent from the file" are *prose, not findings*. In that run the
  capability report asserted `RCTA_01` was missing from the DBC — a parent `grep` found `BO_ 695
  RCTA_01` immediately — and claimed a whole-tree absence it had no way to check.
- **No write means deliverables land somewhere else.** Reports never reached the absolute paths they
  were given; the harness captured them as workflow artifacts under
  `…/subagent-artifacts/outputs/<workflow-id>/<key>.md`. A child that answers "I could not write the
  file, content follows" is behaving *correctly* — treat that as the expected shape, not a failure.
- **Line numbers drift.** The auditor's own citations were wrong (it placed `RCTA_01` at line 1379;
  the real line is 1411). A child that cannot run `nl -ba` or `grep -n` is guessing at locations.

So for any research or audit lane:

1. **Re-derive every load-bearing claim yourself.** Run the grep, confirm the line with `grep -n`,
   read the file. A child's citation is a hint about where to look, not evidence.
2. **Put it in the task.** Tell the child to report its tool set immediately, to mark existence
   claims *unproven* rather than asserting them, and to return the full deliverable inline.
3. **Persist the output yourself** from the artifact path to wherever it belongs, and expect to
   correct it before it is publishable.
4. **Prefer exact paths over searching.** A child with no shell can still `read` an absolute path, so
   hand it the files it needs; do not ask it to go find them.
5. **Read the narrative, not the acceptance report.** A child's self-reported JSON can list
   `commandsRun: []` while its prose implies verification happened.

### Integration before publication

Lanes touching the same file will not all merge cleanly. Probe without allocating anything:

```sh
git merge-tree --write-tree --name-only agent/issue-30 agent/issue-31   # exit != 0 => conflict
```

When a composition must be proven together, spend one more lane on it: a worktree at the merge
base, merging every branch in order, resolving conflicts against an explicitly enumerated required
end state, then re-running the full gate. That lane's reviewer verifies *the resolution* — "did
either side's semantics get lost?" — not the individual changes.

A **series** of dependent PRs avoids the problem rather than solving it: rebase each PR onto the new
default branch as its predecessor lands. Conflicts then disappear by construction instead of
accumulating into a merge-time resolution.

### Publication, rebases, and review loops

The orchestrator publishes; lane leads commit locally and stop. After a rebase the branch needs a
forced update — `git push --force-with-lease` (plain form: it compares against the remote-tracking
ref, so `git fetch origin <branch>` first) — then re-run both `ls-remote` checks above.

When a reviewer requests changes on a PR, hand the lane back the same shape: have the lead read the
review from the PR itself (`gh api .../pulls/<n>/reviews`) rather than paraphrasing it, implement,
re-derive red→green, review, commit. Two things belong to the PR:

- **Keep the body true.** A body still describing a superseded mechanism is itself a review
  finding; refresh it in the same pass that changes the code.
- **Do not widen the series.** If a fix can reuse an existing contract instead of adding a parallel
  one, reuse it — a second API on the same function is how sibling PRs start conflicting.

### Every toolchain mutates tracked files

Gates are not read-only. Package managers rewrite lockfiles, formatters/linters rewrite config or
source, and codegen rewrites generated files — all tracked, all churn that could be committed as
unrelated change. Wrap the gate in a script that runs the toolchain and then restores what it
mutates, and require `git status --short` to show only intended files before commit.

### Hung is not the same as slow

Measure before killing or waiting:

- `ps %cpu` is a **lifetime average**, not instantaneous — 0.0% proves nothing.
- `cmd | tail -N` buffers, so "no output for minutes" is often normal.
- Delta-sample instead: `ps -o pid=,time= -p <pids>` twice, ~6s apart. Unchanged CPU time means
  blocked, not busy.
- A quiet *parent* log while it awaits a child is expected. Check whether the **child** is
  progressing (its event log still growing) before intervening.
- Contention is a real cause: two lanes running the same SDK tool can deadlock on a shared cache
  lock. Serialise the heavy gate, or run it in one lane at a time.

### Recovery: preserve before discarding

Two writers in one worktree is the failure mode to design against, and `git stash` as a baseline
makes it worse — stash/checkout/rebase will silently entangle both writers. Capture first:

```sh
git -C <wt> diff > /tmp/<lane>-pre-recovery-$(date +%H%M%S).patch
git -C <wt> status --short && git -C <wt> stash list
```

Then revert toolchain churn, discard the untrusted files, and restore the lead's known-good state
with `stash pop` (**not** `apply` — pop consumes the entry so it cannot be replayed twice). A stash
label is a claim, not evidence: re-run the gate before trusting the restored tree.

## Hard-won rules

1. **Fresh context.** A forked worker inherits the parent conversation, including sentences like "worker does X, reviewer does Y", and a weak model concludes it is the orchestrator. `context: 'fresh'` prevents it.
2. **Workers never commit, push, or stage.** The parent owns git.
3. **Check the tree after every worker.** Timed-out workers leave partial edits and can touch files they were told to leave alone.
4. **Evidence or it did not happen.** Require exact transcripts, and red→green for anything behavioural.
5. **Do not trust a free worker's summary of its own state.** In practice a timed-out free worker left a correct one-line fix, a test that could not pass, a doc comment with a duplicated word, and two unrelated files modified. Salvaging took minutes; trusting the report would have shipped all four problems.
6. **Keep the reviewer read-only — but give it a mouth.** It verifies by reading; the parent supplies executed evidence. Read-only means no mutation tools, not no escalation channel: a reviewer with no way to ask a question can burn its entire timeout and return no verdict at all (observed in practice). Keep `contact_supervisor` in its tool list.
7. **Prefer native mechanisms.** If you are writing routing logic, fallback handling, or a model picker, check `docs/models.md` first — it is probably already there.
8. **Task-specific constraints override the generic phases — and say so explicitly.** A lane brief will sometimes forbid something a phase mandates. Observed twice in one session: a lead asked whether to dispatch the worker after being told not to (nested workers get no shell), and whether to skip the repo-wide test suite that Phase 2 names. Both times the brief was right and the phase default was wrong for that environment. When you write a lane brief, state that the brief wins where it conflicts, and why — otherwise every lead burns a turn re-litigating it.
9. **Skipping a check is not the same as omitting it.** When a check cannot run in the current environment, record it as *declining a check that cannot produce a signal here*: prove it fails identically on unmodified HEAD, and say where CI does run it. "Not run because it always fails on macOS" is evidence; "not run" is an unexplained gap.

10. **Inherited project context advertises tools the agent does not have.** A subagent session loads
    the ancestor `AGENTS.md` files — including `/Users/vid/development/AGENTS.md`, the lean-ctx
    setup — while its effective tools are exactly its frontmatter `tools:` list. Observed: a lane
    lead spent an entire run calling `ctx_read` and a fabricated `fabric_exec`, never reached
    `bash`, and returned "blocked" having done nothing. The `ateam-*` prompts now state the boundary
    explicitly; keep that section when you add an agent, or give the agent the tools the inherited
    guidance names. `inheritProjectContext: false` is **not** the fix — it also drops the target
    repo's `AGENTS.md`, which lanes need — and `inheritGlobalContext: false` does not suppress
    `~/.pi/agent/AGENTS.md`, which still arrives as project context.

11. **A child's tool list is exactly its frontmatter `tools:`.** Never assume a parent's mode, flags,
    or installed extensions give a child a tool. Pi also *drops* some tools from children (see "A
    worker child loses `bash` at any depth"), so a child can be narrower than its own declaration.
    Confirm a capability
    with `subagent({ action: 'status', id })` before relying on it, and treat a child that reports a
    missing tool as having told you the truth rather than failed.

12. **A nested child's `contact_supervisor` reaches its parent, not the orchestrator.** A depth-2
    reviewer that calls `contact_supervisor` with `reason: "need_decision"` sends its request to the
    lane lead. The root session can neither see nor answer it: the child is absent from
    `subagent({action:"status"})` ("async run not found"), and `subagent_supervisor({action:"pending"})`
    at the root lists only the lead's own requests. Observed: a reviewer raised a genuine
    acceptance-criterion ambiguity, the lead answered with a **steer**, and the reviewer stayed
    blocked until relaunched — a steer delivers guidance but does not clear a decision wait.
    - The lead resolves it: `subagent_supervisor({action:"pending"})` for the request id, then
      `subagent_supervisor({action:"reply", replyTo:"<id>", message:"..."})`.
    - Time-box it. If no id is reachable, interrupt and relaunch, folding any partial findings into
      the new packet.
    - This is the mechanism working, not failing: the reviewer found a real ambiguity. The
      orchestrator's job is to supply the *substance* of the decision — it is a question about the
      requirements, not a tool problem.

13. **A delegated child's tool list is a claim, not a fact — and the gap is widest for research.**
    `researcher` and `evidence-auditor` were both declared with `bash` and reported having no shell;
    `researcher` was declared with `write` and could not write. The failure is *silent and
    confidence-shaped*: the child still returns a well-formatted, sourced-looking report, and only
    the parent's own `grep` reveals which parts were never checkable. Treat every delegated negative
    ("absent", "does not exist", "nothing uses it") as unproven until you run the command yourself,
    and re-derive line numbers with `grep -n` before publishing. In one run, two of three research
    reports needed correction on exactly these points — and the "audit" child inherited the same
    blind spot, so an audit is not a substitute for the parent checking. A read-only reviewer is
    unaffected because it needs no shell; a researcher is not, because searching is the job.

## Ecosystem, if per-task selection is ever wanted

Native routing is per **role**. Per **task** selection is the only gap, and these exist:

| Package | Approach |
| --- | --- |
| `@guygrigsby/pi-subagent-routing` | Injects a routing policy per turn; price terciles; `cost`/`performance` mode; spawns a reviewer and escalates a tier on failed review. Same idea as this skill; low adoption — read before installing. |
| `pi-subagents-team` | Dashboard for per-role model + reasoning effort, writes markdown agent profiles, injects them into every `subagent` call. |
| `pi-subagents-extension` (cgarrot) | A separate subagents implementation with `cheap`/`balanced`/`capable` class routing and an explicit `A→B→parent` fallback chain. Replaces pi-subagents. |
| `pi-subagents-router` | Routes the *agent type* by `useWhen`/`avoidWhen` keywords, not the model. |

Note what today's failures actually were: endpoint availability and tool-protocol quirks, not selection intelligence. Explicit profile selection covers the first; the probe covers the second. Before adding a router, confirm the gap is really selection.
