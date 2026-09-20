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

printf 'fm-pr-merge.sh adversarial drive\nrepo: %s\ncommit: %s\n' \
  "$ROOT" "$(git -C "$ROOT" rev-parse --short HEAD)"

section "A1 torn-down + away grant, forge cannot report a head branch"
d=$(new_case a1 fm/task-x1 --no-record)
# headRefName is empty in the live view: the binding cannot be established.
sed -i 's/"headRefName":"fm\/task-x1"/"headRefName":""/' "$d/github-view.json"
go_away "$d" --grant task-x1
merge "$d" task-x1 https://github.com/example/repo/pull/2001; rc=$?
report "$d" "$rc"

section "A2 torn-down + away, grant names a different task"
d=$(new_case a2 fm/task-x1 --no-record)
go_away "$d" --grant task-other
merge "$d" task-x1 https://github.com/example/repo/pull/2002; rc=$?
report "$d" "$rc"

section "A3 torn-down merge races a respawn: a task record appears while the merge waits for the control lock"
d=$(new_case a3 fm/task-x1 --no-record)
lock="$d/state/.control-task-x1.lock"
sleep 30 & holder=$!          # a live process stands in for the spawn holding the lock
mkdir -p "$lock"; printf '%s\n' "$holder" > "$lock/pid"
merge "$d" task-x1 https://github.com/example/repo/pull/2003 > "$d/out" 2>&1 &
mpid=$!
sleep 2
printf '%s\n' "window=fm-task-x1" "worktree=$d/wt" "kind=ship" > "$d/state/task-x1.meta"
rm -rf "$lock"; kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
wait "$mpid"; rc=$?
cat "$d/out"
printf -- '--- exit code: %s\n' "$rc"
printf -- '--- gh pr merge calls: %s\n' "$(grep -c 'pr merge' "$d/gh.log" || true)"

section "A4 torn-down, PR already closed on the forge"
d=$(new_case a4 fm/task-x1 --no-record)
sed -i 's/"state":"OPEN"/"state":"CLOSED"/' "$d/github-view.json"
merge "$d" task-x1 https://github.com/example/repo/pull/2004; rc=$?
report "$d" "$rc"
