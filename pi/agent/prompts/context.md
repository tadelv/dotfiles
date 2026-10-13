---
description: Start-of-session context digest in one codemode call
---
Gather this session's context in a **single** `codemode` call, then summarise it. Do not run these as
separate shell calls.

In the script, fire the independent probes together with `Promise.allSettled` and return one compact
object. Use the shell tool this setup exposes (`tools.ctx_shell`), and drop any probe that fails:

- `git log -5 --oneline`
- `git status --short`
- `gh pr list --limit 5 --json number,title,state` (skip when `gh` is absent or unauthenticated)
- `agent-wt status --json` (skip outside a git repo)
- `codegraph status` (only when `.codegraph/` exists)

Return only: current branch, HEAD subject, uncommitted files, open PRs, lanes that are `dirty` or
`baseBehind > 0`, and whether a CodeGraph index exists and is fresh.

Then tell me in a few lines: what is in flight, anything blocked or dirty, and what you would pick up
next.
