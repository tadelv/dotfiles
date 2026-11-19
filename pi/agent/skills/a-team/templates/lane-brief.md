# Lane brief — #{{ISSUE}} {{TITLE}}

## Lane

| | |
| --- | --- |
| repo | `{{REPO}}` (default branch `{{DEFAULT_BRANCH}}`) |
| worktree | `{{WORKTREE}}` |
| branch | `{{BRANCH}}` |
| base | `{{BASE_REF}}` @ `{{BASE_SHA}}` |
| publish | `{{PUBLISH}}` |

Gitignored build inputs (bundled plugin assets, bundled skins, the Android debug keystore) are already
materialised by the preflight. They are untracked on purpose: never add them to a commit, and never
copy tracked directories over the worktree.

## Authority

{{PUBLISH_LINE}}

- You own this worktree only. Never touch another worktree.
- Commit locally on `{{BRANCH}}` using the repo's conventional-commit style.
- Apply the A-Team skill's **Role boundaries**. The repo `AGENTS.md` and this brief specialize
  scope and checks within those boundaries; state any departure from generic phase defaults.

## Sources of truth — read these, do not rely on memory

- **Acceptance criteria, maintainer decisions, non-goals:** `.lane/issue.md` (the full issue body)
  and `.lane/issue.json`. They are authoritative. Do not transcribe them from this brief.
- **Gate commands:** start from `.lane/gate.md`, then confirm against the repo `AGENTS.md` and CI.
  Run final gates yourself using the candidate helper and retain its receipt/raw output.
- **Review identity:** follow the A-Team `references/review-candidate.md` procedure. Use this
  brief's pinned base SHA, include uncommitted/new files, and bind gates and review to one ID.
  A changed candidate needs new gates and review; map the final commit with `--committed`.
- **Refinement plan:** write it to `doc/plans/{{ISSUE}}-<slug>.md` per repo conventions, and archive
  or delete it before your commit if repo `AGENTS.md` asks.

## Refinement first

Do the refinement pass — read the issue, read the machinery you will touch, write the plan — **before**
writing product code.

- A genuine blocking decision (it changes the public contract, could contradict the issue, or needs a
  product call): escalate with `contact_supervisor`, reason `need_decision`, giving your recommendation
  and the alternatives, and **wait** for the reply. Batch into one message.
- A non-blocking choice: take the smallest change consistent with the issue and existing patterns, and
  record the choice in the plan.
- If nothing is blocking, proceed in this same run.

## Lane-specific constraints

{{CONSTRAINTS}}
