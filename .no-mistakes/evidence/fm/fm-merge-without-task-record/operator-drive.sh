#!/usr/bin/env bash
# Operator-level drive of bin/fm-pr-merge.sh in a throwaway sandbox.
# Stands up a fake GitHub CLI (the forge is the only external service) and runs
# the script exactly the way a secondmate runs it from a shell.
set -u
ROOT=${FM_REPO:?set FM_REPO to the checkout under test}
SANDBOX=$(mktemp -d /tmp/fm-pr-merge-drive.XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT

new_case() {  # <name> <head-branch> [--red] [--no-record]
  local name=$1 branch=$2; shift 2
  local d="$SANDBOX/$name" red=false record=true a
  for a in "$@"; do
    case $a in --red) red=true ;; --no-record) record=false ;; esac
  done
  mkdir -p "$d/state" "$d/home/data" "$d/home/config" "$d/fakebin" "$d/wt"
  cp "$ROOT/.tasks.toml" "$d/home/.tasks.toml"
  printf '%s\n' '## In flight' '' '## Queued' '' '## Done' > "$d/home/data/backlog.md"
  if [ "$record" = true ]; then
    printf '%s\n' "window=fm-task-x1" "worktree=$d/wt" "project=$d/project" \
      "kind=ship" "mode=no-mistakes" > "$d/state/task-x1.meta"
  fi
  printf '%s\n' 'state=MERGED' 'merged=true' 'queued=false' 'base=main' > "$d/github-outcome"
  : > "$d/github-rules"; : > "$d/gh.log"; : > "$d/gh-axi.log"
  local head=1111111111111111111111111111111111111111
  printf '%s\n' "$head" > "$d/github-head"
  local check='{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}'
  [ "$red" = false ] || check='{"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"FAILURE"}'
  printf '%s\n' "{\"state\":\"OPEN\",\"isDraft\":false,\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"headRefOid\":\"$head\",\"headRefName\":\"$branch\",\"baseRefName\":\"main\",\"statusCheckRollup\":[$check]}" > "$d/github-view.json"
  cat > "$d/fakebin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GH_LOG"
case "${1:-} ${2:-}" in
  "pr view")
    case " $* " in
      *statusCheckRollup*) cat "$FM_TEST_GH_VIEW_JSON"; exit 0 ;;
      *headRefOid*) cat "$FM_TEST_GH_HEAD"; exit 0 ;;
    esac ;;
  "pr merge") printf 'merged:\n  number: %s\n  status: ok\n' "${3:-}"; exit 0 ;;
  "api graphql") cat "$FM_TEST_GH_OUTCOME"; exit 0 ;;
  api\ *) cat "$FM_TEST_GH_RULES"; exit 0 ;;
esac
exit 0
SH
  cat > "$d/fakebin/gh-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GH_AXI_LOG"
case "${1:-} ${2:-}" in
  "pr view") printf 'pull_request:\n  number: %s\n  state: merged\n' "$3" ;;
esac
exit 0
SH
  chmod +x "$d/fakebin/gh" "$d/fakebin/gh-axi"
  printf '%s' "$d"
}

go_away() {  # <case-dir> [--grant <id>]
  local d=$1; shift
  FM_HOME="$d/home" FM_STATE_OVERRIDE="$d/state" "$ROOT/bin/fm-afk-contract.sh" propose "$@" >/dev/null
  FM_HOME="$d/home" FM_STATE_OVERRIDE="$d/state" "$ROOT/bin/fm-afk-contract.sh" confirm >/dev/null
}

merge() {  # <case-dir> <task-id> <url>
  local d=$1; shift
  FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$d/home" FM_STATE_OVERRIDE="$d/state" \
  FM_TEST_GH_LOG="$d/gh.log" FM_TEST_GH_AXI_LOG="$d/gh-axi.log" \
  FM_TEST_GH_OUTCOME="$d/github-outcome" FM_TEST_GH_RULES="$d/github-rules" \
  FM_TEST_GH_VIEW_JSON="$d/github-view.json" FM_TEST_GH_HEAD="$d/github-head" \
  HOME="$d/user-home" PATH="$d/fakebin:$PATH" \
    "$ROOT/bin/fm-pr-merge.sh" "$@"
}

section() { printf '\n=== %s ===\n' "$1"; }
report() {  # <case-dir> <rc>
  printf -- '--- exit code: %s\n' "$2"
  printf -- '--- gh pr merge calls: %s\n' "$(grep -c 'pr merge' "$1/gh.log" || true)"
  grep 'pr merge' "$1/gh.log" | sed 's/^/    gh /' || true
  if [ -f "$1/state/task-x1.meta" ]; then
    printf -- '--- task record after run: present\n'
  else
    printf -- '--- task record after run: absent (not recreated)\n'
  fi
}

printf 'fm-pr-merge.sh operator drive\nrepo: %s\ncommit: %s\n' \
  "$ROOT" "$(git -C "$ROOT" rev-parse --short HEAD)"

section "S1 torn-down task, green PR, operator present (the reported trap)"
d=$(new_case s1 fm/task-x1 --no-record)
merge "$d" task-x1 https://github.com/example/repo/pull/1936; rc=$?
report "$d" "$rc"

section "S2 torn-down task, red check"
d=$(new_case s2 fm/task-x1 --no-record --red)
merge "$d" task-x1 https://github.com/example/repo/pull/1937; rc=$?
report "$d" "$rc"

section "S3 torn-down task, captain away, no grant"
d=$(new_case s3 fm/task-x1 --no-record)
go_away "$d"
merge "$d" task-x1 https://github.com/example/repo/pull/1938; rc=$?
report "$d" "$rc"

section "S4 torn-down task, away grant, PR head branch belongs to another task"
d=$(new_case s4 fm/task-other --no-record)
go_away "$d" --grant task-x1
merge "$d" task-x1 https://github.com/example/repo/pull/1939; rc=$?
report "$d" "$rc"

section "S5 torn-down task, away grant, PR head branch is fm/task-x1"
d=$(new_case s5 fm/task-x1 --no-record)
go_away "$d" --grant task-x1
merge "$d" task-x1 https://github.com/example/repo/pull/1940; rc=$?
report "$d" "$rc"

section "S6 live task with its record intact, green PR (unchanged path)"
d=$(new_case s6 fm/task-x1)
merge "$d" task-x1 https://github.com/example/repo/pull/1941; rc=$?
report "$d" "$rc"
printf -- '--- recorded identity in the task record:\n'
grep -E '^(pr|pr_head)=' "$d/state/task-x1.meta" | sed 's/^/    /'

section "S7 task record present but unsafe (symlink)"
d=$(new_case s7 fm/task-x1 --no-record)
: > "$d/state/.elsewhere.meta"
ln -s "$d/state/.elsewhere.meta" "$d/state/task-x1.meta"
merge "$d" task-x1 https://github.com/example/repo/pull/1942; rc=$?
printf -- '--- exit code: %s\n' "$rc"
printf -- '--- gh pr merge calls: %s\n' "$(grep -c 'pr merge' "$d/gh.log" || true)"
