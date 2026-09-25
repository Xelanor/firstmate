#!/usr/bin/env bash
set -u
. "$(dirname "$0")/live-lab-driver.sh" "$1" "$2"
echo "# S6 re-run: the first run used an empty commit, which teardown's content check correctly treats as landed."
echo "## S6 adversarial: identifiable worktree on branch fm/lab-unlanded holding a commit with real unlanded content"
WT6=$(lease)
git -C "$WT6" checkout -q -b fm/lab-unlanded
echo "real work" > "$WT6/feature.txt"; git -C "$WT6" add feature.txt
git -C "$WT6" -c user.email=a@a -c user.name=a commit -q -m "real unlanded work"
mk lab-unlanded ship no-mistakes "$WT6"
run s6-empty lab-unlanded --empty-outcome
echo "  commit still in worktree: $(git -C "$WT6" log --oneline -1 2>/dev/null)"
echo "## S6b same record via local-only mode (not merged into main, not on any remote)"
WT6b=$(lease)
git -C "$WT6b" checkout -q -b fm/lab-lo-unlanded
echo "real work" > "$WT6b/feature2.txt"; git -C "$WT6b" add feature2.txt
git -C "$WT6b" -c user.email=a@a -c user.name=a commit -q -m "real local-only work"
mk lab-lo-unlanded ship local-only "$WT6b"
run s6b-empty lab-lo-unlanded --empty-outcome
tmux -L fm-lab kill-server 2>/dev/null
rm -rf "$LAB"; echo; echo "# lab removed: $([ -e "$LAB" ] && echo NO || echo yes)"
