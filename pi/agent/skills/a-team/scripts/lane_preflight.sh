#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# lane_preflight.sh — one-command setup for an A-Team lane.
#
# Turns "user names a GitHub issue" into "ateam-lead is running" with a single
# shell call, by doing the mechanical setup the orchestrator kept repeating:
#
#   * allocate (or reuse) the agent-wt worktree for the issue;
#   * materialise gitignored build inputs the fresh worktree lacks;
#   * write the issue body to .lane/issue.{json,md}  (never through compression);
#   * detect candidate gate commands into .lane/gate.md;
#   * materialise the lane brief from templates/lane-brief.md into .lane/brief.md;
#   * exclude .lane/ and .codegraph/ so they never show as lane dirt;
#   * print the lane board and the exact launch snippet.
#
# Usage:
#   lane_preflight.sh <issue-number> [--publish none|push|pr|pr-pause] [-c "constraint"]
#
# Run it from anywhere inside the target repository (a worktree is fine).
# The lane lead is then launched with a two-line task:
#
#   subagent({ agent: 'ateam-lead', cwd: '<worktree>', async: true,
#              task: 'Read .lane/brief.md in your worktree and execute it as your lane brief.' })
#
###############################################################################

die() { echo "error: $*" >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$script_dir/../templates/lane-brief.md"
[[ -f "$template" ]] || die "missing template: $template"

usage() {
  cat <<'EOF'
lane_preflight.sh — one-command setup for an A-Team lane.

Usage:
  lane_preflight.sh <issue-number> [--publish none|push|pr|pr-pause] [-c "constraint"]

Allocates (or reuses) the agent-wt worktree for the issue and writes
.lane/{issue.json,issue.md,gate.md,brief.md} inside it, then prints the lane
board and the exact ateam-lead launch snippet. Run from anywhere inside the
target repository. --publish defaults to none: commit locally, publish nothing.
EOF
  exit "${1:-0}"
}

issue=""
publish="none"
constraint=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--publish)   publish="${2:?--publish needs a value}"; shift 2 ;;
    -c|--constraint) constraint="${2:?--constraint needs a value}"; shift 2 ;;
    -h|--help)      usage 0 ;;
    -*)             die "unknown flag: $1 (try --help)" ;;
    *)              [[ -z "$issue" ]] || die "unexpected argument: $1"; issue="$1"; shift ;;
  esac
done

[[ "$issue" =~ ^#?[0-9]+$ ]] || usage 1
issue="${issue#\#}"
case "$publish" in
  none|push|pr|pr-pause) ;;
  *) die "invalid --publish '$publish' (none|push|pr|pr-pause)" ;;
esac

for cmd in git gh agent-wt python3; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done

common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || die "not inside a Git repository (cd into the target repo first)"
repo_root="$(dirname "$common")"
cd "$repo_root"

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || basename "$repo_root")"
default_branch="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)"
[[ -n "$default_branch" ]] || default_branch=main
base_ref="origin/$default_branch"

# --- worktree: reuse if the lane already exists, else allocate --------------
lane_path() {
  agent-wt status --json | python3 -c '
import json, sys
want = int(sys.argv[1])
for entry in json.load(sys.stdin):
    if entry.get("kind") == "issue" and entry.get("number") == want:
        print(entry["path"])
        break
' "$issue"
}

wt="$(lane_path)"
if [[ -z "$wt" ]]; then
  echo "allocating worktree for issue #$issue ..." >&2
  agent-wt issue "$issue" >&2
  wt="$(lane_path)"
fi
[[ -n "$wt" && -d "$wt" ]] || die "could not resolve a worktree for issue #$issue"

git -C "$wt" fetch origin "$default_branch" -q 2>/dev/null || true
branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD)"
base_sha="$(git -C "$wt" rev-parse "$base_ref")"

# --- disk headroom ----------------------------------------------------------
# A full volume stalls heavy test runs with no output, no failing test and no
# worker process, which reads as a flaky suite and burns a gate cycle before
# anyone checks. Advisory only: warn, never block the lane.
avail_kb="$(df -Pk "$wt" 2>/dev/null | awk 'NR==2 {print $4}')"
if [[ -n "$avail_kb" && "$avail_kb" -lt 2097152 ]]; then
  printf 'warning: %s MiB free on this volume; heavy Flutter runs can stall silently (0%% CPU, no tester child).\n' "$((avail_kb / 1024))" >&2
fi

# --- materialise gitignored inputs ------------------------------------------
# A fresh worktree checks out tracked files only, so build inputs that the repo
# gitignores (bundled plugin assets, bundled skins, the Android debug keystore)
# are missing and the lane starts on a red baseline it did not cause.
# Copy them from the primary checkout, but only paths Git reports as ignored:
# a tracked path is never overwritten. Extra paths come from LANE_ASSETS.
asset_candidates=(
  "assets/plugins/*.reaplugin"
  "assets/bundled_skins"
  "android/app/debug.keystore"
)
if [[ -n "${LANE_ASSETS:-}" ]]; then
  # shellcheck disable=SC2206
  asset_candidates+=(${LANE_ASSETS})
fi

copied_assets=()
skipped_assets=()
for candidate in "${asset_candidates[@]}"; do
  for src in $(compgen -G "$repo_root/$candidate" || true); do
    rel="${src#$repo_root/}"
    git -C "$wt" check-ignore -q -- "$rel" || continue
    if [[ -e "$wt/$rel" ]]; then
      skipped_assets+=("$rel")
      continue
    fi
    mkdir -p "$wt/$(dirname "$rel")"
    cp -R "$src" "$wt/$rel"
    copied_assets+=("$rel")
  done
done

# --- artifacts -------------------------------------------------------------
lane_dir="$wt/.lane"
mkdir -p "$lane_dir"

gh issue view "$issue" \
  --json number,title,state,labels,milestone,url,body > "$lane_dir/issue.json"

python3 - "$lane_dir/issue.json" "$lane_dir/issue.md" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
labels = ", ".join(l["name"] for l in d.get("labels", [])) or "-"
milestone = (d.get("milestone") or {}).get("title") or "-"
body = (d.get("body") or "").strip()
open(sys.argv[2], "w").write("\n".join([
    f"# #{d['number']} — {d['title']}", "",
    f"state: {d['state']}  ·  labels: {labels}  ·  milestone: {milestone}",
    f"url: {d['url']}", "", "---", "", body, "",
]))
PY

detect_gate() {
  if [[ -f pubspec.yaml ]] && grep -qE '^[[:space:]]*flutter:' pubspec.yaml; then
    echo "dart format --output=none --set-exit-if-changed lib test"
    echo "flutter analyze"
    echo "flutter test"
  elif [[ -f pubspec.yaml ]]; then
    echo "dart format --output=none --set-exit-if-changed ."
    echo "dart analyze"
    echo "dart test"
  elif [[ -f Cargo.toml ]]; then
    echo "cargo fmt --check"; echo "cargo clippy --all-targets -- -D warnings"; echo "cargo test"
  elif [[ -f go.mod ]]; then
    echo "gofmt -l ."; echo "go vet ./..."; echo "go test ./..."
  elif [[ -f pyproject.toml || -f setup.cfg ]]; then
    echo "python -m pytest"
  elif [[ -f package.json ]]; then
    echo "npm test"
  fi
}

agents_md=""
for candidate in AGENTS.md CLAUDE.md; do
  [[ -f "$candidate" ]] && { agents_md="$candidate"; break; }
done

{
  echo "# Gate candidates — confirm against the repo AGENTS.md and CI before relying on them."
  echo
  echo "## Detected by project type"
  detected="$(detect_gate)"
  if [[ -n "$detected" ]]; then echo "$detected" | sed 's/^/- /'; else echo "- none detected; derive from CI"; fi
  if [[ -n "$agents_md" ]]; then
    echo
    echo "## From $agents_md (verification / testing / pre-commit headings)"
    awk '
      /^#{1,6} / { p = 0 }
      /^#{1,6} / && tolower($0) ~ /(verification|testing|pre-commit|pre-pr)/ { p = 1; print; next }
      p { print }
    ' "$agents_md" | head -60
  fi
} > "$lane_dir/gate.md"

publish_line() {
  case "$publish" in
    none)     echo "Publication: **none**. The orchestrator publishes only on explicit request. Do NOT push and do NOT open or update a PR — commit locally and stop." ;;
    push)     echo "Publication: the orchestrator will **push** this branch after validating. You still do NOT push or open a PR." ;;
    pr)       echo "Publication: the orchestrator will **open a PR** after validating. You still do NOT push or open a PR." ;;
    pr-pause) echo "Publication: the orchestrator will **open a PR** after validating, then pause for human review. You still do NOT push or open a PR." ;;
  esac
}

[[ -n "$constraint" ]] || constraint="- None beyond the issue body, the repo \`AGENTS.md\`, and your own protocol."

python3 - \
  "$template" \
  "$lane_dir/brief.md" "$issue" "$repo" "$default_branch" "$wt" "$branch" \
  "$base_ref" "$base_sha" "$publish" "$(publish_line)" "$constraint" <<'PY'
import json, os, sys
tpl_path, out_path = sys.argv[1], sys.argv[2]
(issue, repo, default_branch, wt, branch, base_ref, base_sha, publish, publish_line, constraint) = sys.argv[3:]
with open(os.path.join(wt, ".lane", "issue.json")) as fh:
    title = json.load(fh)["title"]
text = open(tpl_path).read()
for key, value in {
    "{{ISSUE}}": issue, "{{TITLE}}": title, "{{REPO}}": repo,
    "{{DEFAULT_BRANCH}}": default_branch, "{{WORKTREE}}": wt, "{{BRANCH}}": branch,
    "{{BASE_REF}}": base_ref, "{{BASE_SHA}}": base_sha, "{{PUBLISH}}": publish,
    "{{PUBLISH_LINE}}": publish_line, "{{CONSTRAINTS}}": constraint,
}.items():
    text = text.replace(key, value)
open(out_path, "w").write(text)
PY

# --- keep tooling artifacts out of lane dirt -------------------------------
exclude="$(git -C "$wt" rev-parse --git-path info/exclude)"
mkdir -p "$(dirname "$exclude")"
for pattern in '.lane/' '.codegraph/'; do
  grep -qxF "$pattern" "$exclude" 2>/dev/null || echo "$pattern" >> "$exclude"
done

# --- report ----------------------------------------------------------------
board="$(agent-wt status --json | python3 -c '
import json, sys
for e in json.load(sys.stdin):
    if e.get("dirty"):
        print("    %-12s dirty=true  %s" % (e.get("name", ""), e.get("branch", "")))
')"

echo
echo "lane #$issue  $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["title"])' "$lane_dir/issue.json")"
echo "  repo      : $repo  (default branch: $default_branch)"
echo "  worktree  : $wt"
echo "  branch    : $branch   base: $base_ref @ ${base_sha:0:8}"
echo "  publish   : $publish"
echo "  artifacts : $lane_dir/{issue.json,issue.md,gate.md,brief.md}"
if [[ ${#copied_assets[@]} -gt 0 ]]; then
  echo "  assets    : materialised ${#copied_assets[@]} gitignored path(s) from $repo_root"
  [[ ${#skipped_assets[@]} -gt 0 ]] && echo "              (${#skipped_assets[@]} already present)"
  echo "              they stay untracked: do not commit them"
elif [[ ${#skipped_assets[@]} -gt 0 ]]; then
  echo "  assets    : gitignored inputs already present"
fi
if [[ -n "$board" ]]; then
  echo "  lane board (dirty):"
  echo "$board"
fi
echo
echo "launch:"
echo "  subagent({ agent: 'ateam-lead', cwd: '$wt', async: true,"
echo "             task: 'Read .lane/brief.md in your worktree and execute it within your A-Team role boundaries.' })"
