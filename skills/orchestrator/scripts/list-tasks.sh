#!/usr/bin/env bash
# List every task worktree of this repo: branch, path, whether an agent is
# live in it, the goal line of its brief, and the files it has changed so far
# (committed since its base, plus uncommitted), and the worker's last report.
# Usage: list-tasks.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

root="$(repo_root)"
agents="$(herdr agent list 2>/dev/null |
    jq -r '.result.agents[] | "\(.cwd)\t\(.name // .pane_id)"' || true)"

inbox="$(inbox_dir)/inbox"

found=0
while IFS=$'\t' read -r path branch; do
    [ "$path" != "$root" ] || continue
    found=1
    base="$(base_for_branch "$branch")"
    ref="$(base_ref "$base" || echo "$base")"
    agent="$(awk -F'\t' -v p="$path" '$1 == p { print $2; exit }' <<<"$agents")"
    brief="$(brief_file "$path")"
    goal="(no brief)"
    [ -f "$brief" ] && goal="$(grep -m1 . "$brief" | sed 's/^#* *//')"
    changed="$({
        git -C "$path" diff --name-only "$ref...HEAD" 2>/dev/null
        git -C "$path" status --porcelain | cut -c4-
    } | sort -u | paste -sd ' ')"
    last="$(jq -r --arg s "${branch#*/}" 'select(.slug == $s) | "\(.time) \(.message)"' \
        "$inbox" 2>/dev/null | tail -n1 | head -c 200 || true)"

    echo "$branch"
    echo "  worktree: $path"
    echo "  agent:    ${agent:-none running}"
    echo "  goal:     $goal"
    echo "  changed:  ${changed:-nothing yet}"
    echo "  last:     ${last:-no report yet}"
done < <(git -C "$root" worktree list --porcelain | awk '
    /^worktree / { path = substr($0, 10) }
    /^branch refs\/heads\// { print path "\t" substr($0, 19) }')

[ "$found" = 1 ] || echo "list-tasks: no task worktrees"
