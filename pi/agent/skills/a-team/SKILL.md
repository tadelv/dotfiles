---
name: a-team
description: Run a configurable worker-plus-reviewer pipeline for implementation work, and orchestrate several such pipelines as parallel lanes in separate git worktrees. Use when the user says "use the a-team", "a-team this", "run the a-team", "start a worktree lane", "pick up #N in a new worktree", "worker and reviewer", or wants a task implemented by a cheap/free worker and independently verified by a strong reviewer without naming models — including multi-issue work split across worktrees with the agent-wt CLI, and when the operator wants a lane running as its own tmux pi session instead of a subagent.
---

# A-Team

A worker implements, a strong reviewer independently verifies, the parent orchestrates and owns validation, commits, and scope.

The protocol runs at two scales. **Phases 0–4 are one lane** — one worktree, one change. The **orchestrator role** drives several lanes at once, one worktree each, using the `agent-wt` CLI. Read that section too whenever a request spans more than one issue; it carries the lane board, the `agent-wt` push trap, the nested-tool ceiling, and integration/publication rules.

## Role boundaries

Agent profiles define each role's tool, delegation, and git ceilings; runtime filtering may narrow
those ceilings. Repo instructions and lane briefs specialize scope, acceptance criteria, and checks,
and may narrow phase defaults. They cannot widen capabilities, transfer publication to a lane lead
or worker, or waive independent review. Phase 1 below owns the exceptions for direct lead authoring.
Escalate a conflict rather than treating task prose as a permission grant.

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

**2. Launch** — one lane at a time for a single issue. For two or more, hand the preflighted
worktrees to the lane script, which fans out one `ateam-lead` per worktree in a single workflow:

```ts
await extensions.subagent({
  workflow: '/Users/vid/.pi/agent/skills/a-team/scripts/lanes.js',
  async: true,
  args: { lanes: [{ issue: 973, worktree: '<worktree>' }, { issue: 974, worktree: '<worktree>', extra: 'gate: pnpm test' }] }
});
```

`args` is the only channel: workflow scripts get no shell and no filesystem, so gather the board
first (agent-wt / git / gh checks in a `fabric_exec` program), then pass the lanes in.
`async: false` blocks and returns the finished board; `async: true` returns dispatch receipts.
`args.agent` / `args.task` override the default lead role for smoke tests. Validate any edit with
`extensions.subagent({ action: 'validate', workflow: '<path>' })`.

For a single lane the task is two lines, because the brief carries the rest:

```
subagent({ agent: 'ateam-lead', cwd: '<worktree-from-preflight>', async: true,
           task: 'Read .lane/brief.md in your worktree and execute it within your A-Team role boundaries.' })
```

Then:

1. **Yield.** Do not poll; native completion wakes you.
2. **Answer escalations.** A lead's `contact_supervisor` (`need_decision`) blocks it and wakes you.
   Reply with `subagent_supervisor({ action: 'reply', replyTo: '<id>', message: '<answer>' })`. See
   "Escalation channel" for depth and timeout.
3. **Validate yourself.** Check the exact candidate, rerun the repo gate with a candidate-bound
   receipt, and read its frozen diff/context. A lead's transcript is a claim, not evidence.
4. **Publish** — only at the level `--publish` asked for. Push with an explicit refspec, verify both
   refs, then `gh pr create --base <default> --body-file <pr-body>`.

## Lane dispatch — the shape a lane request becomes

The operator describes a lane in plain words. Pick the shape before doing anything else: the shapes
differ in who leads and in whether this session outlives the work.

| Branch — what the operator says | Shape | Lead |
| --- | --- | --- |
| "start a worktree lane for #N", "pick up #N in a new worktree", "a-team this" | `ateam-lead` **subagent** launched from this session | the child; this session orchestrates |
| the same words plus "in its own session", "as a separate pi", "in a tmux window", or a wish to watch/steer it | **detached pi instance** in a new tmux window, cwd = lane worktree | that instance; this session answers its questions and validates |
| two or more issues in one request | `lanes.js` fan-out, one `ateam-lead` per worktree | each child |

Default to the subagent shape. A detached instance costs an operator-visible window and a whole
second session, so take it only when the operator asks for a separate instance or needs to steer the
lane directly.

Every shape starts the same way:

1. `agent-wt issue <n>` — allocates the worktree and branch. Done when `agent-wt status` lists it clean.
2. `scripts/lane_preflight.sh <n> --publish <none|push|pr|pr-pause>` — materialises `.lane/brief.md`.
   Pass `-c "..."` for constraints the issue body does not carry. Done when the brief exists in the
   worktree and the printed board matches the intended lane.
3. Launch per the table above. Done when the lane reports for work, not when the process starts.

The detached shape:

```sh
agent-wt issue <n>
~/.pi/agent/skills/a-team/scripts/lane_preflight.sh <n> --publish pr
tmux new-window -d -c <worktree> -n issue-<n> 'pi "$(cat .lane/brief.md)"'
```

A detached instance is a peer pi session, not a child: it raises questions over pi-intercom
(`intercom list-cwd` with the lane path) and is steered with `intercom send`. There is no
`subagent_supervisor` channel to it, and native completion never wakes this session for it, so report
its state only when the operator asks.

Two rules hold in every shape: one writer per worktree (never a subagent lead and a detached instance
on the same lane), and no lane pushes — publication belongs to the orchestrating session, at the
`--publish` level it was given.

---

Routing is **native to pi-subagents** — this skill is the protocol, not a router. Each launch resolves one model; there is no in-launch fallback chain. By default, the team comes from configuration; an explicit operator model request overrides it for the named role.

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
| `daily` **(default)** | `deepseek/deepseek-flash:high` | `sol:high` | `luna:medium` | `deepseek-flash:low` |
| `free` | `nex-n2.5-pro:free` | `sol:high` | `nex-n2.5-pro:free` | `nex-n2.5-mini:free` |

Pi-subagents no longer switches models during a launch. If a model fails, fix the profile or make a later, explicit retry; do not hand-roll a fallback loop or silently change execution mode.

### Provider limit fallback — an explicit retry ladder, not an in-launch fallback

There is no automatic model fallback inside a launch, and there must not be one: a child that
switches provider mid-run hides which model produced the work. When a provider returns a usage
limit, **you** retry, naming the next model explicitly, and you record the switch.

Configured ladder on this machine (probed 2026-10-21, one child each; ids resolved from the loaded profile):

| Step | Lead (`ateam-lead`) | Worker / researcher | Reviewer / oracle |
| --- | --- | --- | --- |
| 1 | `openai-codex/gpt-6.1-sol` | `openai-codex/gpt-5.6-luna` | `openai-codex/gpt-6.1-sol` |
| 2 | `opencode-go/muse-spark-1.3-contributor` | same | same |
| 3 | `deepseek/deepseek-flash` | `deepseek/deepseek-flash:low` | `deepseek/deepseek-flash` |

Probe result: sol, luna, muse-spark and deepseek-flash all answered. `opencode-go/longcat-2.5-preview-free` — the old worker rung — returned `402 server_error: Upstream request failed: Endpoint is unavailable.`, so that free endpoint has been withdrawn and must not be routed to. Free tiers are what die first: re-probe this table before trusting it after a gap of weeks.

Rules that keep the ladder honest:

- A limit is a **provider** failure: same task, same worktree, different model. Do not rewrite the
  task to fit the cheaper model, and never let a retry arrive as a different execution mode
  (`interactive_shell`, `pi -ne`, another CLI).
- Retry **once per step**. A step that fails on anything other than a limit is a task failure: fix
  the task rather than climbing past it.
- Say which step you are on, in the lane report and in your own final report. A run that quietly
  moved to step 3 carries different evidence quality, and the operator is entitled to know.
- After a switch, re-check the child's tool list (`subagent({action:"status", id})`): a cheaper model
  is likelier to mis-declare a capability, and the shell/tool gaps documented below are exactly
  what that check catches. Keep verification on the strongest reviewer available — that is the one
  place a cheap model is a false economy.

### What a dead provider looks like — and the cheap pre-flight

`pi auth check --model <id>` returning `{"status":"ready"}` proves **only** that a credential
exists. It reported `ready` for every one of the shapes below, so treat it as a key-presence check,
not a capacity check:

| Shape | What you see on the first turn | Retry? |
| --- | --- | --- |
| Spend cap on the key | `403 permission_error`, `"Key limit exceeded (total limit)… $0.00 of $0.00 used; does not reset"` (OpenRouter) | not on this key — climb |
| Empty account | `403` / quota error before any token | not on this provider — climb |
| Free tier kept for its own client | `403 FreeTierError: OpenCode's free tier can only be used from within OpenCode` | never from pi — skip that step |
| Id not in the active registry | `Unknown subagent model 'x' in the active Pi model registry` | fix the id, don't climb |
| Endpoint withdrawn | `402 server_error: Upstream request failed: Endpoint is unavailable.` | not on this model — climb |

All four fail **on turn one**, at 0 tokens and $0. That is the cheap case, but a 3-wide fan-out turns
one dead model into three dead runs and still trips the overseer's `session-failure-streak` — which
reports credentials, not code. So probe with **one** throwaway child (`scout`, "say hi") before any
fan-out, and rotate only once it answers.

An id rejected by the registry spawns **no run at all**, so an empty `subagent({action:"runs"})`
after a launch is a launch failure, not a suspiciously fast success.

A child that answers is only half the check: the other half is whether it can hold an agent loop.
`scripts/probe_models.py` covers that class — tool calls emitted as text (stalls after turn one) and
tool results rejected outright (200 on turn one, 400 on the turn two) — one line per model, non-zero
exit if any fail. Run it after editing a profile, or when a lane stalls with no error to show.

### Reading a "repeated mutating tool failures" signal

A lead that trips this signal is usually **not** blocked — it is composing bad commands, or chasing a
gate that cannot run here. Triage in three steps before spending a steer:

1. **Status, not alarm.** `subagent({action:"status", id})` — still running? which step?
2. **Check the tree.** `git -C <worktree> status --short`. A malformed redirection can *create* a file
   (a stray `&1`, `null`), and a mid-write tree is normal — but real product work in a clean tree
   means the lane is fine and only its command pattern is broken.
3. **Then steer with the diagnosis**, not with encouragement. Two classes recur, both model-side and
   neither a capability problem:
   - **Output pasted back as input** — a diffstat line (`bash: path | 288 +++---`), a numbered context
     line, a hunk header. The shell was handed evidence and asked to execute it.
   - **Redirection fragments run as commands** — `bash(&1;)`, `bash(/dev/null;)`, `bash(>)`: pieces of
     `2>&1` or `> /dev/null` split off into calls of their own.

The steer that works names the rule: *one plain command per call; no `;`, `>`, `2>&1` or pipes; never
paste tool output back as a command; let the tool compress long output instead of piping to
`head`/`tail`.* Then **make it structural**: put the same discipline in the lane brief, because the
next lane on that model hits it too. A failure class that recurs across lanes is a brief defect, not
a run defect.

### Recovery: preserve before discarding

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

## Phase 1 — the worker authors, the lead orchestrates

**Default: dispatch an `ateam-worker` for the implementation and let the lead validate and review
it.** The worker runs a real shell (`ctx_shell`) and proves its own red→green; see "A worker child
has no `bash` — give it `ctx_shell`" for the mechanism and the trap that used to make this
impossible. Keep the lead's hands off the product diff: a lead that writes the change has nothing
left to validate independently, and the worker's separate context is half the value of the team.

Dispatch the worker async with fresh context; you are woken on completion, then validate.
(`context: 'fresh'` is that agent's default — pass it explicitly only if you changed it.)

```
subagent({ agent: 'ateam-worker', cwd: '<worktree>', async: true, task: '<task>' })
```

The lead may author directly only when the change is genuinely shell-free (pure text), when the
worker has already failed twice on the same task, or when the task is under ~10 lines — and it must
say so in its report and still obtain independent review. Missing tools or a failed launch are
configuration blockers, not worker implementation failures; fix or escalate them instead.

**Do not pass `model:` by default.** The configured profile supplies the model for this launch. If it is unusable, fix the profile or make a later explicit retry with an approved exact model; do not hand-roll fallback or silently switch execution modes.

The task string must state: repo and branch, no commit/push; the exact files the worker may touch, and that anything else must be reverted; the wanted behaviour and acceptance criteria; the red→green evidence required for behavioural change; and the focused check to run while iterating (not the full suite).

Keep scope small — one file plus one focused test. Split work that is larger, or run it on a paid profile.

## Phase 2 — validate as the parent

Before final gates, read `references/review-candidate.md` and freeze the exact candidate with its
helper. It includes uncommitted and new files without touching the real index. Run the repository's
real gates yourself through the helper, the same commands CI runs. Clean up after the toolchain:

- revert any tracked file a gate mutated that the task did not ask to change;
- revert repo-wide formatter churn when the tree was committed under an older SDK (keep the diff scoped);
- prove any failure is pre-existing by stashing your changes and re-running the same test at `HEAD`;
- if a gate produces a long transcript, filter it with `codemode` (failures and counts, not the whole
  log) instead of archiving and expanding it later.

## Phase 3 — dispatch the reviewer

The reviewer is read-only with no shell. Use the packet from Phase 2, following
`references/review-candidate.md`: check it before dispatch and after review. Supply `candidate.json`,
`diff.patch`, frozen `source/` paths, and candidate-bound gate receipts/logs, not a live HEAD-only diff.

Launch it async with fresh context:

```
subagent({ agent: 'ateam-reviewer', cwd: '<worktree>', async: true, task: '<review packet>' })
```

Include the exact candidate ID, packet paths, numbered acceptance criteria, scope constraints,
non-goals, and environment caveats. Require the verdict to echo that ID, per-requirement confirmations
relative to the frozen `source/`, and a false-positive assessment of each new test. An absent or
mismatched ID is not SHIP. Any fix or candidate change requires new gates and a fresh review.

For a public contract, a security-shaped change, or a diff you cannot cheaply re-verify, escalate to **Phase 3b — panel review** below.

### Phase 3b — panel review (two models, one cross-exam)

Escalation of Phase 3 for changes where a single verdict is not enough. Two reviewers on **different
models** report independently, then answer each other's disputed claims. The model diversity *is* the
mechanism: two passes of the same model share its blind spots, and a second opinion from a different
model found a live bug today that the primary reviewer pass missed.

The pass mechanics come from `council-mode` (read its `references/pass-contracts.md`); this is the
review-shaped application of them. Reviewers are read-only with no shell, so both get the *same*
packet and you supply all executed evidence.

1. **Roster.** Two reviewers, two different models — the profile's reviewer plus one second opinion,
   passed as a per-run `model:` on the `subagent` call. Never two builds of the same model, and never
   three or more: the marginal reviewer buys little and costs a full pass.
2. **Pass 1 — independent.** One `runs.all` with keys `review-a` / `review-b`, both given the same
   frozen packet and candidate ID (diff, source, numbered criteria, non-goals, matching gate
   receipts/logs). Neither sees the other before it reports.
3. **Claim matrix — you, in the parent.** Sort the findings into agreements, disputes, claims only one
   reviewer could support, and claims neither can. Relay at most five material claims per reviewer;
   never forward a whole transcript.
4. **Pass 2 — one cross-exam.** Resume each reviewer with the *other's* disputed claims, labelled as a
   peer's claim and not as fact. Read-only reviewers cannot run anything, so they settle disputes by
   reading source, not by testing. One pass, no loop for polish.
5. **Close the dispute.** Any claim still contradicted by its author — including a rebuttal that
   arrived after you sent the packets — must be settled before it reaches the report: relay it back to
   the author for one reply, or resolve it yourself from primary source. Never hand over an unresolved
   "A says X, B says not-X". In the run that produced this section, one reviewer's only *blocking*
   finding looked decisive until the CLI's own docs showed the assumption behind it was wrong; the peer
   who downgraded it was right, and neither reviewer could have settled it alone.
6. **Synthesis — you write the verdict.** An agreement is not proof: two models can share a training
   blind spot, and both can be wrong the same way. Verify every disputed or single-source claim
   against the source yourself before it enters the review or changes the code.

Stop at convergence or after one cross-exam. A panel is for *finding*; the parent still owns the
verdict. Nested reviewers' `contact_supervisor` requests reach **you** — resolve them (rule 12).

## Phase 4 — close out

Apply blocking fixes, then capture a new candidate, rerun gates, and obtain a fresh ID-bound review.
Before closeout, check the packet as described in `references/review-candidate.md`. Commit/push or
update the PR **only if asked**; after an authorized local commit, use the helper's `--committed`
check to map it to the reviewed tree. Report candidate ID/packet, exact final commit or `none`,
matching gate receipts, reviewer verdict, and residual risk. Retain the packet with the evidence.

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

### Lane status and retirement

When the operator asks "status of the lanes", the answer starts with plain `agent-wt status`, not
with git archaeology:

```
WORKTREE           BRANCH                           STATUS     COMMITS         GITHUB
issue-1077         agent/issue-1077                 clean      0               #1077
issue-1087         agent/issue-1087                 clean      +2              #1087
```

Join the board with upstream state in one `fabric_exec` program — the board lists a number, never an
issue's or PR's state, so on its own it cannot tell you a lane is finished:

```ts
const [wt, prs, open] = await Promise.all([
  pi.bash({ cmd: 'agent-wt status --json', cwd: R, settle: true }),
  pi.bash({ cmd: 'gh pr list --json number,headRefName,state,mergedAt --limit 30', cwd: R, settle: true }),
  pi.bash({ cmd: 'gh issue list --state open --json number,title --limit 60', cwd: R, settle: true })
]);
```

Three verdicts, and only one means "leave it alone":

| Verdict | Evidence | Action |
| --- | --- | --- |
| **parked** | upstream still open, clean tree, handover records an external block | keep — it is waiting on evidence, not on you |
| **working** | `dirty: true`, or a live `ateam-*` run against that worktree | leave it |
| **redundant** | upstream CLOSED/MERGED **and** its patches are in the base | retire the lane |

Retirement is per lane, and `agent-wt rm` deliberately leaves the branch behind:

```sh
agent-wt rm issue-963            # one name per call — it takes no list
git branch -D agent/issue-963    # -D because a squash-merge leaves the commits unmatched
```

Merged-ness is a content question, not a commit-count one:

- `COMMITS +2` does **not** mean unmerged: a squash-merge (or a patch re-landed from another branch)
  leaves the lane's own commits outside the base with identical subjects inside it. Recover them with
  `git log origin/main --oneline --grep="<lane subject>"`.
- `git diff HEAD origin/main` is **not** the test either — a lane that is `baseBehind > 0` diffs the
  base's newer commits, not its own divergence.
- `git cherry -v <base> <branch>` is: every `-` means that patch is already upstream.

A lane at `COMMITS 0` is not automatically stale — that is what a research lane parked on a
measurement looks like. When an open issue is blocked on the reporter, relabel it
(`needs-triage` → `needs-info`) and keep its lane; `gh issue edit <n> --remove-label needs-triage
--add-label needs-info`.

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
tools: read, grep, find, ls, bash, ctx_shell, edit, write, subagent, contact_supervisor
extensions:
subagentOnlyExtensions: /Users/vid/.pi/agent/npm/node_modules/pi-lean-ctx/extensions/index.ts
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
`subagent`. (Fabric's full code mode is also safe now that the `ateam-*` agents declare
a blank `extensions:` key — see "Working inside a fabric session" below.) Three places it pays for itself:

- **Lane board.** One call instead of N shells: run `agent-wt status --json`, `git -C <wt> status
  --short` and `gh pr checks` across every lane, and return only `{name, dirty, baseBehind, checks}`.
- **Gate output.** Filter a long build/test run down to the failing lines and counts instead of
  archiving the transcript and expanding it later.
- **Review packets.** Assemble diff stat, changed files and criteria in one script rather than
  several reads.

Keep the sandbox in mind: it has no filesystem or network of its own, so it can only orchestrate the
tools it is given.

### Working inside a fabric session

pi-fabric ships with `fullCodeMode: true`: it removes Pi's core tools from the parent model and serves
them only through `fabric_exec`. Two consequences for this protocol, both verified:

1. **The parent writes the protocol in fabric syntax.** `subagent(...)`, `subagent_supervisor(...)`
   and `bg_wait(...)` are reachable inside a fabric program as `extensions.subagent(...)`,
   `extensions.subagent_supervisor(...)`, `extensions.bg_wait(...)`. Nothing else changes, and children
   are unaffected.
2. **`workflow:` launches used to break every child; single and `args` launches were always fine.**
   pi-subagents inherits the parent's *ambient* extensions only in the workflow host
   (`input.host === "runner" && !disableAmbientExtensions`), so a scripted/parallel workflow child
   loaded pi-fabric, fabric took session ownership, and the child was left with a phantom
   `fabric_exec` ("Tool fabric_exec not found") and **no core tools at all** — the child's
   system-prompt `<tools>` section came back empty. Observed for `delegate`, `ateam-worker` and
   `ateam-lead`: no shell, no read, no write.

The fix is a blank `extensions:` key in the frontmatter of `ateam-lead`, `ateam-worker` and
`ateam-reviewer`. It must be **blank, not `[]`**: these frontmatter lists are comma-split strings, not
YAML, so `extensions: []` parses as the single selector `"[]"` and registers a junk extension path
(observed: `configured: ["sha256:4f53…"]` vs `configured: []` for the blank form). The blank key still
sets `disableAmbientExtensions`, which is what does the work.
Any explicit `extensions` value sets `disableAmbientExtensions`, so the child never inherits fabric;
`subagentOnlyExtensions` is a separate field and still loads, so the worker keeps `ctx_shell`. Verified
with a control agent in the same workflow call: the blank-`extensions` child resolved
`read, bash, contact_supervisor` and ran `echo`; the worker beside it stayed tool-less. Under a
non-fabric parent nothing is lost, because these agents already declare full allowlists.

Consequence for lane launches: scripted `subagent({workflow: ...})` fan-out from a fabric session is
safe again. Keep the blank `extensions:` key on any new `ateam-*` variant, or it inherits fabric and
goes blind.

The key protects only agents that declare it. A workflow child running `delegate`, `scout`, `worker` or
any other agent without it still inherits pi-fabric and gets a phantom `fabric_exec` plus an empty tool
set, so a scripted lane must launch `ateam-*` agents (which is what `scripts/lanes.js` does).

### A worker child has no `bash` — give it `ctx_shell`

`bash` is absent from a child whose shell is routed through lean-ctx. This is **not** a pi-subagents
child-safety default and not a depth rule: the `pi-lean-ctx` extension, in its default additive mode
with `routeShell: true` (`~/.pi/agent/extensions/pi-lean-ctx/config.json`), registers a
`session_start` handler that filters `bash` out of the active tool set and replaces it with
`ctx_shell`.

That collides with how pi-subagents launches children. A child's tool list is exactly its agent
frontmatter `tools:` allowlist, and that allowlist also filters **extension** tools: lean-ctx's
`ctx_*` tools are registered but dropped from the session because the allowlist does not name them.
So a worker declaring `read, grep, find, ls, bash, edit, write` resolves to
`read, grep, find, ls, edit, write, contact_supervisor` — `bash` suppressed by lean-ctx, `ctx_shell`
filtered out by the allowlist, and no shell at all. `edit`/`write` stay, which is what makes the
failure quiet: the worker looks fully equipped and only fails at the first gate.

Earlier runs exposed a registration-order race: lean-ctx's `session_start` filter removed `bash`,
then a coordinator's later tool registration reactivated it. Leads sometimes kept a shell while
workers lost it at the same depth. That was not a role or depth restriction; declare the shell
replacement explicitly instead of relying on that race.

**Declare both the replacement tool and its provider.** Both `ateam-worker.md` and
`ateam-lead.md` declare `ctx_shell` plus `subagentOnlyExtensions`; the lead additionally keeps its
bounded delegation tools. The worker's shell-related fields are:

```yaml
tools: read, grep, find, ls, bash, ctx_shell, edit, write
subagentOnlyExtensions: /Users/vid/.pi/agent/npm/node_modules/pi-lean-ctx/extensions/index.ts
```

`tools:` names the replacement so the allowlist stops filtering it. `subagentOnlyExtensions:` is
required for the *foreground* case: a blocking child never loads the parent's ambient extensions, so
lean-ctx is absent, `ctx_shell` is never registered, and a strict allowlist naming it fails the whole
launch ("these child tools were unavailable: ctx_shell"). The explicit path loads lean-ctx into the
child either way. Earlier worker checks recorded:

| Launch | Resolved tools | Shell |
| --- | --- | --- |
| `async: true` | `read, grep, find, ls, edit, write, ctx_shell, contact_supervisor` | `ctx_shell` exit 0 |
| `async: false` | `read, grep, find, ls, edit, write, ctx_shell, contact_supervisor` | `ctx_shell` exit 0 |

The provider path is machine-specific. On another host with lean-ctx, update it in both profiles.
On a host without lean-ctx, remove both `ctx_shell` and `subagentOnlyExtensions` and keep `bash`;
a strict allowlist naming an unavailable extension tool fails the launch.

So a lane **can** be built around a worker child. Two things still hold:

- Confirm the shell before spending the run: `subagent({ action: 'status', id })`, or read the
  child's `toolsAdded` in its events log. A worker that reports no shell tool is telling you the
  truth — stop and fix its allowlist rather than waiting for it to park in `contact_supervisor`.
- Any agent that needs a shell must name `ctx_shell`; that includes future worker variants and any
  `researcher`/`scout` variant you give a shell.

The lead uses the same explicit shell/provider pair instead of relying on the registration-order
race described above. A shell-capability fix does not change author ownership — see Phase 1.

The clean upstream fix is for lean-ctx to never suppress a builtin whose replacement is absent from
the session — its own comment says it must "never suppress a tool without a local replacement", and
this is that same failure class arriving through the allowlist. Until then, the allowlist entry is
the reliable lever.

### Research and audit children lose the shell too — and `write` goes with it

The same lean-ctx allowlist collision described above hits read-only research, where it does more
damage, because searching *is* the method. A `researcher` declaring `read, write, web_search, bash`
and an `evidence-auditor` declaring `read, web_search, bash` both reported **no shell and no write
tool** on a real run. (The missing `write` is the separate pi-subagents withholding, not lean-ctx.)
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
- **A missing worker is the clearest signal.** If the driver sits at 0.0% CPU and the tool's worker
  process (`flutter_tester` for `flutter test`, the equivalent for other toolchains) does not exist at
  all, it never started. Waiting cannot fix that; find out what blocked it.
- **Check disk before blaming code.** A full volume stalls Flutter builds with no output, no failing
  test and no worker process: `df -h` the volume holding the worktree first. Free space, clear
  generated caches (`build/test_cache`, `.dart_tool/flutter_build`), rerun. The same stall appears in
  every worktree at once, which is the tell that it is the host, not the lane.
- **Never put a 20-minute suite inside a tool timeout.** Launch it detached with an exit-status file:
  `( cmd > log 2>&1; echo $? > log.exit ) &`, then poll the exit file. A tool timeout is not a test
  failure and must never be reported as one; likewise, log staleness alone is not evidence of a hang.

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
8. **Task-specific constraints specialize phases within role boundaries.** A brief may narrow scope or name environment-appropriate gates; it cannot grant missing tools, widen git/delegation authority, or remove independent review. Record why a generic phase default does not apply. A missing worker shell is a configuration blocker, not a reason to make the lead the default author.
9. **Skipping a check is not the same as omitting it.** When a check cannot run in the current environment, record it as *declining a check that cannot produce a signal here*: prove it fails identically on unmodified HEAD, and say where CI does run it. "Not run because it always fails on macOS" is evidence; "not run" is an unexplained gap. **Name the unrunnable gates in the brief** when you allocate the lane — the command, and why it cannot produce a signal here — so the lead records them instead of rediscovering them at the cost of a dozen turns (a lane worktree has no provisioned toolchain, so a bare firmware-toolchain build cannot run; a wrapper that fetches a foreign-architecture binary cannot either).

10. **Inherited project context advertises tools the agent does not have.** A subagent session loads
    the ancestor `AGENTS.md` files — including `/Users/vid/development/AGENTS.md`, the lean-ctx
    setup — while its effective tools are exactly its frontmatter `tools:` list. Observed: a lane
    lead spent an entire run calling `ctx_read` and a fabricated `fabric_exec`, never reached
    `bash`, and returned "blocked" having done nothing. The `ateam-*` prompts now state the boundary
    explicitly; keep that section when you add an agent, or give the agent the tools the inherited
    guidance names. `inheritProjectContext: false` is **not** the fix — it also drops the target
    repo's `AGENTS.md`, which lanes need — and `inheritGlobalContext: false` does not suppress
    `~/.pi/agent/AGENTS.md`, which still arrives as project context.

11. **A child's tool list is exactly its frontmatter `tools:` — minus whatever extensions subtract.** Never assume a parent's mode, flags,
    or installed extensions give a child a tool, and never assume a declared tool survives: `pi-lean-ctx`
    with `routeShell: true` removes `bash` from every session it loads into, so a child can be narrower
    than its own declaration (see "A worker child has no `bash` — give it `ctx_shell`"). Conversely the
    allowlist *filters* extension tools, so an agent that needs `ctx_shell` must name it. Confirm a capability
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

14. **A dependency is proven by mechanism, not proximity — and an architecture swap is not a
    dependency.** When a lane reports that porting a feature needs something else from the source
    line, require the mechanism: *what breaks or misreports without it?* "It came along in the same
    range" and "the source has it" are not dependencies. The test that settles it: does the target
    feature fail without it, or does the other change merely improve something adjacent? If the
    "dependency" **replaces** the target's existing design — a different control architecture, a
    different clock, a different wire layout — it is a separate change wearing a dependency's
    clothes, and that decision belongs to the operator, not to the lane. Observed: a learning
    feature whose learned model is consumed only by a control mode the target repo has never had
    (absent at core-math, bridge *and* wire layer). Porting it under the feature's banner would have
    silently swapped how two boards share control; escalating it produced a clean choice.

    Corollary: when a lane asserts something "already exists here", verify it yourself. In that same
    escalation the lane's premise was backwards — the core math it planned against was absent from
    the whole tree — and a port built on it would have compiled against nothing.

## Ecosystem, if per-task selection is ever wanted

Native routing is per **role**. Per **task** selection is the only gap, and these exist:

| Package | Approach |
| --- | --- |
| `@guygrigsby/pi-subagent-routing` | Injects a routing policy per turn; price terciles; `cost`/`performance` mode; spawns a reviewer and escalates a tier on failed review. Same idea as this skill; low adoption — read before installing. |
| `pi-subagents-team` | Dashboard for per-role model + reasoning effort, writes markdown agent profiles, injects them into every `subagent` call. |
| `pi-subagents-extension` (cgarrot) | A separate subagents implementation with `cheap`/`balanced`/`capable` class routing and an explicit `A→B→parent` fallback chain. Replaces pi-subagents. |
| `pi-subagents-router` | Routes the *agent type* by `useWhen`/`avoidWhen` keywords, not the model. |

Note what today's failures actually were: endpoint availability and tool-protocol quirks, not selection intelligence. Explicit profile selection covers the first; the probe covers the second. Before adding a router, confirm the gap is really selection.
