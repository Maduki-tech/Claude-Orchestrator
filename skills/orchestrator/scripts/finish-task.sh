#!/usr/bin/env bash
# Finish a task: optionally merge its branch, then remove its worktree,
# its Herdr workspace, and the local branch.
# Usage:
#   finish-task.sh <branch> [--merge]   one task
#   finish-task.sh --all-merged         every worktree whose work is merged
#
# --merge merges the branch with --no-ff into each of its targets (see
# merge_targets in lib.sh): in the worktree where the target is checked out,
# or else in a temporary worktree. Nothing is pushed.
# Every mode first fetches and fast-forwards the base branches where they are
# checked out. A branch with no commits yet is never treated as merged.
# Without --merge, the branch must already be merged: locally, on the remote,
# or as a merged GitHub pull request (which also covers squash merges).
# A worktree with uncommitted changes is never removed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

repo_root="$(repo_root)"
git_main() { git -C "$repo_root" "$@"; }

# Fetch, then fast-forward each base branch where it is checked out, so work
# a worker merged and pushed is pulled before anything is checked or removed.
sync_bases() {
    local b path before
    git_main fetch --quiet origin 2>/dev/null ||
        { echo "finish-task: fetch failed, using local refs" >&2; return 0; }
    for b in $(printf '%s\n' "$(base_branch)" "$(hotfix_base)" | sort -u); do
        path="$(worktree_path_for "$b")"
        [ -n "$path" ] || continue
        git_main rev-parse --quiet --verify "origin/$b" >/dev/null || continue
        before="$(git -C "$path" rev-parse HEAD)"
        if git -C "$path" merge --ff-only --quiet "origin/$b" 2>/dev/null; then
            [ "$before" = "$(git -C "$path" rev-parse HEAD)" ] ||
                echo "finish-task: pulled $b to $(git -C "$path" rev-parse --short HEAD)"
        else
            echo "finish-task: $b in $path can't fast-forward to origin/$b; pull it by hand" >&2
        fi
    done
}

# Prints how the branch was merged, or nothing if it was not.
merged_how() {
    local branch="$1" base
    base="$(base_for_branch "$branch")"
    if git_main merge-base --is-ancestor "$branch" "$base" 2>/dev/null; then
        echo "merged into $base"
    elif git_main merge-base --is-ancestor "$branch" "origin/$base" 2>/dev/null; then
        echo "merged into origin/$base"
    elif command -v gh >/dev/null &&
        [ -n "$(cd "$repo_root" && gh pr list --head "$branch" --state merged \
            --json number --jq '.[0].number // empty' 2>/dev/null)" ]; then
        echo "pull request merged on GitHub"
    fi
}

# merge_into <target> <branch>: merge where the target is checked out, or in
# a temporary worktree when it isn't checked out anywhere. A conflict leaves
# that worktree as it is for the user to resolve.
merge_into() {
    local target="$1" branch="$2" path tmp
    path="$(worktree_path_for "$target")"
    if [ -n "$path" ]; then
        [ -z "$(git -C "$path" status --porcelain --untracked-files=no)" ] ||
            die "$path (on $target) has uncommitted changes"
        git -C "$path" merge --no-ff --no-edit "$branch" ||
            die "merging $branch into $target stopped on a conflict in $path"
    else
        tmp="$(mktemp -d)"
        git_main worktree add --quiet "$tmp" "$target"
        git -C "$tmp" merge --no-ff --no-edit "$branch" ||
            die "merging $branch into $target stopped on a conflict in the temporary worktree $tmp"
        git_main worktree remove "$tmp"
        rmdir "$tmp" 2>/dev/null || true
    fi
    echo "finish-task: merged $branch into $target"
}

finish() {
    local branch="$1" do_merge="$2" path how workspace target
    git_main rev-parse --verify --quiet "refs/heads/$branch" >/dev/null ||
        die "no local branch $branch"
    path="$(worktree_path_for "$branch")"
    [ "$path" != "$repo_root" ] || die "$branch is checked out in the main checkout"

    # A branch whose reflog holds only its creation never got a commit, yet
    # counts as merged because its tip is an ancestor of the base.
    [ "$(git_main reflog show --format=%H "refs/heads/$branch" 2>/dev/null | wc -l)" != 1 ] ||
        die "$branch has no commits yet; its task hasn't started or is still running"

    if [ -n "$path" ] && [ -n "$(git -C "$path" status --porcelain)" ]; then
        die "$path has uncommitted changes; commit or discard them first"
    fi

    if [ "$do_merge" = 1 ]; then
        while read -r target; do
            merge_into "$target" "$branch"
        done < <(merge_targets "$branch")
    fi

    how="$(merged_how "$branch")"
    [ -n "$how" ] || die "$branch is not merged; use --merge or merge the PR first"

    if [ -n "$path" ]; then
        workspace="$(herdr worktree list --cwd "$repo_root" 2>/dev/null | jq -r \
            --arg p "$path" '.result.worktrees[] | select(.path == $p)
            | .open_workspace_id // empty')"
        if [ -n "$workspace" ]; then
            herdr worktree remove --workspace "$workspace" >/dev/null
        else
            git_main worktree remove "$path"
        fi
    fi

    # -D is safe here: merged_how proved the work landed. Squash-merged PRs
    # are not ancestors of the base, so -d would refuse them.
    git_main branch -D "$branch" >/dev/null
    echo "finish-task: $branch $how; removed ${path:-no worktree} and the branch"
}

case "${1:-}" in
    --all-merged)
        sync_bases
        # A new branch with no commits counts as merged, so skip any worktree
        # that still has a live agent in it.
        busy="$(herdr agent list 2>/dev/null | jq -r '.result.agents[].cwd')"
        found=0
        while read -r branch; do
            [ -n "$(merged_how "$branch")" ] || continue
            path="$(worktree_path_for "$branch")"
            if [ -n "$path" ] && grep -q -F -x -e "$path" <<<"$busy" ; then
                echo "finish-task: skipped $branch, an agent is still running in it"
                continue
            fi
            found=1
            # A subshell, so one refusal (die exits) doesn't end the sweep.
            ( finish "$branch" 0 ) || true
        done < <(git_main worktree list --porcelain |
            awk '/^branch refs\/heads\// { print substr($0, 19) }' |
            grep -v -x -e "$(base_branch)" -e "$(hotfix_base)" -e main -e master -e develop)
        [ "$found" = 1 ] || echo "finish-task: no merged worktrees"
        ;;
    "" | -*) die "usage: finish-task.sh <branch> [--merge] | --all-merged" ;;
    *)
        merge=0
        [ "${2:-}" = --merge ] && merge=1
        sync_bases
        finish "$1" "$merge"
        ;;
esac
