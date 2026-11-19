# Exact-candidate review

Use this procedure before final gates, review, and closeout. Run the helper from the target worktree.
A candidate is a pinned base and HEAD plus the raw contents, modes, and symlink targets of Git-listed
files. It includes committed lane changes, staged and unstaged edits, deletions, and non-ignored new
files. The helper uses a temporary Git index; it never stages or commits in the real index.

## 1. Freeze the candidate

Finish the worker run and stop writers. Inspect `git status --short`: every captured change must be
intentional and in scope. Resolve unrelated/private files before capture; the helper does not filter
secrets. Use the lane's pinned **base SHA**, not a moving ref or a diff of HEAD alone.

```sh
python3 ~/.pi/agent/skills/a-team/scripts/review_candidate.py capture <base-sha>
```

Record the returned `packet` path and `candidate` ID. The private packet is outside the checkout:

- `candidate.json`: ID, pinned base/HEAD, Git tree, content fingerprint, and diff digest.
- `diff.patch`: complete base-to-candidate Git diff, including new files and binary changes.
- `source/` and `files.json`: frozen context and its raw-content/mode manifest. Symlinks are rendered
  as their target text, not followed; their original kind is in the manifest and diff.

The snapshot is for reading, not running tests. Git's diff may normalize content through attributes;
`source/` and the raw fingerprint preserve the actual bytes the gates run against.

## 2. Bind final gate evidence

Run each final gate through the helper, on the same packet:

```sh
python3 ~/.pi/agent/skills/a-team/scripts/review_candidate.py run <packet> -- <command> <args>
```

It prints a receipt/log path immediately, records raw combined output, command argv, exit code, log
digest, and candidate ID. A receipt is usable only with `status: finished`, `valid: true`, and the
expected candidate ID. A zero exit code is insufficient if the checkout changed during the gate.
Interrupted/running receipts are not passes. Keep red/baseline demonstrations separately labelled;
they are not final-candidate passing receipts. A pre-capture or worker transcript cannot replace a
final gate receipt.

If a formatter, test, or cleanup changes captured files, finish that work and capture again. Rerun
final gates and obtain a fresh review for the new ID; do not transfer an old SHIP verdict.

## 3. Review the frozen packet

```sh
python3 ~/.pi/agent/skills/a-team/scripts/review_candidate.py check <packet>
```

Check immediately before dispatch, after the verdict, and before committing or handing back. It
checks checkout identity, frozen source/diff integrity, and the IDs/digests of passing gate logs. Give the reviewer `candidate.json`,
`diff.patch`, `source/` context paths, matching receipts and logs, acceptance criteria, non-goals,
and environment caveats. Reviewers cite paths relative to `source/`, echo the exact candidate ID in
the verdict, and read frozen context rather than the moving worktree. Panel reviewers get the same
packet and criteria. A missing or mismatched ID is not an approval.

Any code edit, rebase, changed requirements, or material environment change invalidates acceptance.
The helper detects code/HEAD changes, not changes to requirements or the environment; the parent
owns those checks. Evidence without a matching valid receipt is unverified, even when prose says
that tests passed.

## 4. Map an authorized final commit

Only the role already authorized to commit may do so. After committing the reviewed candidate:

```sh
python3 ~/.pi/agent/skills/a-team/scripts/review_candidate.py check <packet> --committed
```

This requires the final commit to have the captured HEAD as its sole parent, its tree to equal the
reviewed tree, and the checkout's raw file fingerprint to remain unchanged. Record its returned HEAD
alongside the candidate ID and reviewer verdict. A partial commit, hook edit, or different parent
fails closed. Without commit authority, leave the candidate uncommitted and report its ID and packet.

## Limits

Ignored untracked build inputs, SDKs, dependencies, credentials, and environment variables are outside
this identity: record relevant versions/caveats and rerun gates if they change. Submodules are rejected
rather than silently claiming their working contents were reviewed. Do not run another writer while
capturing, gating, or reviewing; before/after checks are not a filesystem lock or a sandbox. Packets
and Git objects contain local source, potentially including sensitive non-ignored files; do not upload
them without authorization. Keep the packet until acceptance evidence no longer needs it.
