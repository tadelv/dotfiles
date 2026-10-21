# Overseer

One pi session watching — and steering — every other pi session and subagent run
on the machine, in any project folder.

## Two planes

**Observe (no dependencies).** Reads the evidence every pi process already writes:

- `~/.pi/agent/sessions/--<munged-cwd>--/<iso>_<uuid>.jsonl` — every session transcript
- `<tmp>/pi-subagents-<scope>/async-subagent-runs/<runId>/status.json` — every subagent run

Runs are joined to their parent session via `status.json.sessionId`. A session is
"live" when its transcript was written in the last 2 minutes; a run is live when its
state is running/queued/starting and its pid is alive.

**Control.** `steer` / `stop` / `interrupt` a run by id:

- If this session **owns** the run → executes the pi-subagents RPC locally.
- Otherwise → broadcasts an `overseer/v1` command over pi-intercom's extension bus.
  The owning session receives it and executes the RPC in **its** process.

Ownership matters because pi-subagents' RPC is ownership-scoped: only the session
whose branch spawned a run may control it. The target key is exactly pi-subagents'
own identity (`getSessionFile() ?? getSessionId()`), so keys always match.

pi-intercom is optional. Without it the overseer still observes everything and
controls its own runs; cross-window control goes quiet.

## Surfaces

- **`/overseer`** — live panel: control status, findings, live runs, sessions.
- **`overseer` tool** — actions `summary | runs | sessions | findings | steer | stop | interrupt`.
- **Status line** — `N live · X finding(s) · steer ready`.

## Rules

Deterministic thresholds in `config.json`:

| rule | fires when |
|---|---|
| `run-stale` | live run, no activity for `staleMs` |
| `run-long` | live run older than `maxRuntimeMs` |
| `run-budget-usd` | run cost ≥ `maxCostUsd` |
| `run-budget-tokens` | run tokens ≥ `maxTokens` |
| `session-failure-streak` | ≥ `failureStreak` **consecutive** non-complete runs at the end of one session (a later success clears it; a user interrupt doesn't count) |

`rules.action` decides delivery:

- `"notify"` (default) — a message, nothing is touched.
- `"steer"` — sends `autoSteerMessage` to the stalled run.
- `"stop"` — stops the run.

Findings notify once and re-arm only after they clear.

## Configuration

`~/.pi/agent/extensions/overseer/config.json`:

```json
{
  "maxAgeHours": 24,
  "autoSteerMessage": "Overseer: this run looks stalled...",
  "rules": { "action": "notify", "staleMs": 300000, "maxCostUsd": 5 }
}
```

Subagent child sessions load this extension too, so their runs are addressable.
They register for control but skip the scan, notifications, and auto-actions.

## Layout

| file | role |
|---|---|
| `discovery.ts` | scans sessions + run artifacts (plain `node:fs`, testable) |
| `rules.ts` | thresholds → findings |
| `control.ts` | pi-subagents RPC client (steer/stop/interrupt) |
| `channel.ts` | pi-intercom `overseer/v1` extension channel |
| `panel.ts` | `/overseer` view |
| `format.ts` | display helpers |
| `index.ts` | tool, command, lifecycle, rule execution |
