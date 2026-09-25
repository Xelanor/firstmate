#!/usr/bin/env bash
# Live lab driver for fm-teardown.sh --empty-outcome. Runs every teardown inside a
# window of a private tmux server (socket fm-lab) against a marked lab FM_HOME.
set -u
WTREE=$1; E=$2
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$LAB"
"$WTREE/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux" "$LAB/home"
export TMUX_TMPDIR="$LAB/tmux"
TM() { tmux -L fm-lab "$@"; }
TM new-session -d -s firstmate -n shell -c "$WTREE"
# Real project repo with origin; main pushed.
P="$LAB/projects/proj"; git init -q -b main "$P"; git init -q --bare "$LAB/origin.git"
git -C "$P" -c user.email=a@a -c user.name=a commit -q --allow-empty -m init
git -C "$P" remote add origin "$LAB/origin.git"; git -C "$P" push -q origin main
printf '%s\n' '# Backlog' '' '## In flight' '' '## Queued' '' '## Done' > "$LAB/data/backlog.md"
lease() { (cd "$P" && HOME="$LAB/home" treehouse get --lease 2>/dev/null); }
mk() {  # id kind mode worktree-or-empty [extra lines...]
  local id=$1 kind=$2 mode=$3 wt=$4; shift 4
  tasks-axi add "$id" "lab $id" --kind "$( [ "$kind" = scout ] && echo scout || echo ship )" --file "$LAB/data/backlog.md" >/dev/null
  tasks-axi start "$id" --file "$LAB/data/backlog.md" >/dev/null
  TM new-window -d -t firstmate -n "fm-$id" "sleep 3600"
  { echo "window=firstmate:fm-$id"; echo "endpoint_task_id=$id"
    [ -n "$wt" ] && echo "worktree=$wt"
    echo "project=$P"; echo "kind=$kind"; echo "mode=$mode"; echo "spawn_gen=lab-$id"
    for l in "$@"; do echo "$l"; done; } > "$LAB/state/$id.meta"
}
run() {  # label id [flags]
  local label=$1 id=$2; shift 2
  local out="$LAB/run-$label"
  TM new-window -d -t firstmate -n "run-$label" \
    "env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME=$LAB HOME=$LAB/home PATH=$PATH $WTREE/bin/fm-teardown.sh $id $* >$out.out 2>$out.err; echo \$? >$out.rc"
  for _ in $(seq 1 120); do [ -f "$out.rc" ] && break; sleep 0.5; done
  {
    echo "===== [$label] \$ FM_HOME=\$LAB bin/fm-teardown.sh $id $*   (exit $(cat "$out.rc" 2>/dev/null || echo TIMEOUT))"
    sed 's/^/  stdout| /' "$out.out"; sed 's/^/  stderr| /' "$out.err"
    echo "  meta present: $( [ -e "$LAB/state/$id.meta" ] && echo yes || echo no )"
    echo "  tmux window fm-$id alive: $(TM list-windows -t firstmate -F '#W' | grep -qx "fm-$id" && echo yes || echo no)"
    echo "  report.md present: $( [ -e "$LAB/data/$id/report.md" ] && echo yes || echo no )"
    echo "  backlog: $(tasks-axi show "$id" --file "$LAB/data/backlog.md" 2>/dev/null | sed -n 's/^  \(state\|closed\|body\|note\|links\): */\1=/p' | tr '\n' ' ')"
    grep -n "$id" "$LAB/data/backlog.md" | sed 's/^/  backlog.md| /'
  } | sed "s#$LAB#\$LAB#g"
}
