#!/usr/bin/env bash
set -u
. "$(dirname "$0")/live-lab-driver.sh" "$1" "$2"
echo "# live lab: FM_HOME=\$LAB (marked lab home), private tmux socket fm-lab, real treehouse/git/tasks-axi"
echo; echo "## S1 GAP 1: spawned ship record with spawn_gen but no worktree= line"
mk lab-nowt ship no-mistakes ""
run s1-plain lab-nowt
run s1-legacy lab-nowt --legacy-record
run s1-empty lab-nowt --empty-outcome

echo; echo "## S2 GAP 2: scout with a real leased worktree that never wrote report.md"
WT2=$(lease); echo "leased: ${WT2/#$LAB/\$LAB}"
mk lab-scout scout no-mistakes "$WT2"
run s2-plain lab-scout
run s2-empty lab-scout --empty-outcome
echo "  treehouse status after:"; (cd "$P" && HOME="$LAB/home" treehouse status 2>&1) | sed "s#$LAB#\$LAB#g;s/^/    /"

echo; echo "## S3 adversarial: scout that DID write report.md"
mk lab-report scout no-mistakes ""
mkdir -p "$LAB/data/lab-report"; echo "# Findings" > "$LAB/data/lab-report/report.md"
run s3-empty lab-report --empty-outcome

echo; echo "## S4 adversarial: ship task that recorded a PR"
mk lab-pr ship no-mistakes "" "pr=https://github.com/example/repo/pull/7"
run s4-empty lab-pr --empty-outcome

echo; echo "## S5 adversarial: scout with an open captain decision"
mk lab-decide scout no-mistakes ""
echo "needs-decision [key=api-shape]: pick REST or RPC" > "$LAB/state/lab-decide.status"
run s5-empty lab-decide --empty-outcome

echo; echo "## S6 adversarial: identifiable worktree holding an unlanded commit"
WT6=$(lease)
git -C "$WT6" -c user.email=a@a -c user.name=a commit -q --allow-empty -m "real unlanded work"
mk lab-unlanded ship no-mistakes "$WT6"
run s6-empty lab-unlanded --empty-outcome

echo; echo "## S7 adversarial: identifiable worktree with uncommitted changes"
WT7=$(lease); echo scratch > "$WT7/scratch.txt"
mk lab-dirty scout no-mistakes "$WT7"
run s7-empty lab-dirty --empty-outcome

echo; echo "## S8 adversarial: two worktree= lines (ambiguous identity)"
mk lab-ambig ship no-mistakes "" "worktree=$LAB/a" "worktree=$LAB/b"
run s8-empty lab-ambig --empty-outcome

echo; echo "## S9 adversarial: secondmate record"
mk lab-mate secondmate secondmate ""
run s9-empty lab-mate --empty-outcome

echo; echo "## S10 local-only project whose local main is ahead of origin; task committed nothing"
git -C "$P" -c user.email=a@a -c user.name=a commit -q --allow-empty -m "earlier local-only task merged into local main"
WT10=$(lease); git -C "$WT10" checkout -q --detach main
echo "  origin/main..main: $(git -C "$P" rev-list --count origin/main..main) commit(s) ahead; task HEAD == main: $([ "$(git -C "$WT10" rev-parse HEAD)" = "$(git -C "$P" rev-parse main)" ] && echo yes)"
mk lab-localonly ship local-only "$WT10"
run s10-empty lab-localonly --empty-outcome

echo; echo "## Final Done section of \$LAB/data/backlog.md"
sed -n '/^## Done/,$p' "$LAB/data/backlog.md" | sed "s#$LAB#\$LAB#g"

tmux -L fm-lab kill-server 2>/dev/null
(cd "$P" && HOME="$LAB/home" treehouse status >/dev/null 2>&1)
rm -rf "$LAB"; echo; echo "# lab removed: $([ -e "$LAB" ] && echo NO || echo yes)"
