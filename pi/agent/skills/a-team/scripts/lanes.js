// lanes.js — fan out one ateam-lead per worktree lane and return a compact board.
//
// The caller owns preflight and the lane data, because workflow scripts have no
// filesystem or shell access:
//
//   subagent({
//     workflow: '/Users/vid/.pi/agent/skills/a-team/scripts/lanes.js',
//     args: { lanes: [{ issue: 973, worktree: '/repo-worktrees/issue-973', extra: 'gate: pnpm test' }] },
//     async: true
//   })
//
// args.lanes[*] = { issue: positive integer, worktree: absolute path, extra?: constraint text }
// The brief itself stays on disk (.lane/brief.md); this script only names it.
// Invalid lanes are rejected before any child launches — a duplicate issue would
// otherwise reuse the first child while overstating the count, and a missing
// worktree becomes an undefined cwd the child schema rejects.
// async:true returns launch receipts in seconds; async:false blocks for the finished board.

const lanes = (args && args.lanes) || [];
if (!Array.isArray(lanes) || lanes.length === 0) {
  return { launched: 0, board: [], note: 'args.lanes was empty' };
}

const DEFAULT_TASK = 'Read .lane/brief.md in your worktree and execute it as your lane brief; it and the repo AGENTS.md win over your defaults.';
// args.agent / args.task exist for smoke tests and for cheap single-role lanes.
const AGENT = (args && args.agent) || 'ateam-lead';
const BASE_TASK = (args && args.task) || DEFAULT_TASK;

const seen = {};
const problems = [];
const clean = [];

lanes.forEach(function (lane, i) {
  const issue = lane && lane.issue;
  const worktree = lane && lane.worktree;
  if (typeof issue !== 'number' || !Number.isFinite(issue) || issue <= 0 || issue % 1 !== 0) {
    problems.push('lanes[' + i + '].issue must be a positive integer');
    return;
  }
  if (seen[issue] === true) {
    problems.push('lanes[' + i + '].issue ' + issue + ' is a duplicate');
    return;
  }
  if (typeof worktree !== 'string' || worktree.length < 2 || worktree.charAt(0) !== '/') {
    problems.push('lanes[' + i + '].worktree must be an absolute path');
    return;
  }
  seen[issue] = true;
  clean.push(lane);
});

if (problems.length > 0) {
  problems.forEach(function (p) { emit('lanes.js rejected: ' + p); });
  return { launched: 0, board: [], note: 'args.lanes rejected', problems: problems };
}

if (clean.length > 64) {
  return { launched: 0, board: [], note: 'args.lanes has ' + clean.length + ' lanes; the fan-out budget is 64 per run' };
}

const launches = clean.map(function (lane) {
  const task = lane.extra ? BASE_TASK + ' Lane constraints: ' + lane.extra : BASE_TASK;
  return { key: 'lane-' + lane.issue, agent: AGENT, cwd: lane.worktree, task: task };
});

const results = await runs.all(launches);

const board = results.map(function (r, i) {
  const lane = clean[i] || {};
  const text = String((r && r.output) || '').replace(/[ \t]+/g, ' ').replace(/\n+/g, ' | ');
  return {
    issue: lane.issue !== undefined ? lane.issue : null,
    ok: !!(r && r.ok === true),
    state: (r && r.state) || null,
    runId: (r && r.runId) || null,
    summary: text.slice(0, 200)
  };
});

const ok = board.filter(function (b) { return b.ok; }).length;
emit('lanes.js: ' + ok + '/' + board.length + ' lanes ok');
return { launched: board.length, ok: ok, board: board };
