# Shared helpers for the orchestrator scripts. Source it; don't run it.
#
# Per-project settings live in <repo>/.claude/orchestrator.md. The keys and
# their defaults are documented in ../SETTINGS.md. The file is parsed, never
# sourced, so a repo can't run code through it.

die() { echo "${0##*/}: $*" >&2; exit 1; }

TYPES="feature bugfix hotfix chore refactor docs"

git rev-parse --git-common-dir >/dev/null 2>&1 ||
    die "not inside a git repository"

# The main checkout: the parent of the shared .git directory, so this works
# from the main checkout and from any of its worktrees.
repo_root() {
    dirname "$(git rev-parse --path-format=absolute --git-common-dir)"
}

config_file() { echo "$(repo_root)/.claude/orchestrator.md"; }

# conf <key> <default>: a front-matter value, or the default.
conf() {
    local file value
    file="$(config_file)"
    if [ -f "$file" ]; then
        value="$(awk -v k="$1" '
            NR == 1 && $0 != "---" { exit }
            NR > 1 && $0 == "---" { exit }
            NR > 1 {
                key = $0; sub(/:.*/, "", key); gsub(/[ \t]/, "", key)
                if (key == k) {
                    v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v)
                    sub(/[ \t]+$/, "", v); print v; exit
                }
            }' "$file")"
    fi
    echo "${value:-$2}"
}

# The settings file without its front matter: extra worker rules.
config_rules() {
    local file
    file="$(config_file)"
    [ -f "$file" ] || return 0
    awk 'NR == 1 && $0 == "---" { fm = 1; next }
         fm && $0 == "---" { fm = 0; next }
         !fm' "$file" | sed '/./,$!d'
}

default_branch() {
    local head
    head="$(git -C "$(repo_root)" symbolic-ref --quiet --short \
        refs/remotes/origin/HEAD 2>/dev/null)"
    echo "${head#origin/}" | grep . || echo main
}

base_branch() { conf base "$(default_branch)"; }
hotfix_base() { conf hotfix_base "$(base_branch)"; }

default_prefix() {
    case "$1" in
        feature) echo feature ;;
        bugfix) echo fix ;;
        *) echo "$1" ;;
    esac
}

prefix_for() { conf "prefix_$1" "$(default_prefix "$1")"; }

# model_for <type>: the worker model for a task type, or empty for the
# agent's own default.
model_for() { conf "model_$1" "$(conf model '')"; }

# base_for_branch <branch>: the base a task branch was cut from.
base_for_branch() {
    case "$1" in
        "$(prefix_for hotfix)"/*) hotfix_base ;;
        *) base_branch ;;
    esac
}

# merge_targets <branch>: every branch a finished task merges into, in order.
# A hotfix also merges back into the base branch, so the fix isn't lost
# there, unless hotfix_merge_back is false.
merge_targets() {
    local base
    base="$(base_for_branch "$1")"
    echo "$base"
    if [ "$base" != "$(base_branch)" ] &&
        [ "$(conf hotfix_merge_back true)" != false ]; then
        base_branch
    fi
}

# base_ref <branch>: the local branch if it exists, else origin/<branch>.
base_ref() {
    local root
    root="$(repo_root)"
    if git -C "$root" rev-parse --verify --quiet "refs/heads/$1" >/dev/null; then
        echo "$1"
    elif git -C "$root" rev-parse --verify --quiet "refs/remotes/origin/$1" >/dev/null; then
        echo "origin/$1"
    else
        return 1
    fi
}

# worktree_path_for <branch>: where the branch is checked out, if anywhere.
worktree_path_for() {
    git -C "$(repo_root)" worktree list --porcelain | awk -v b="refs/heads/$1" '
        /^worktree / { path = substr($0, 10) }
        $0 == "branch " b { print path }'
}

# brief_file <worktree>: where spawn-task.sh keeps the task's brief. It sits
# in the worktree's private git directory, so it is never committed and is
# removed together with the worktree.
brief_file() {
    echo "$(git -C "$1" rev-parse --absolute-git-dir)/orchestrator-brief.md"
}

# Worker reports go to an inbox in the shared git directory, so every worktree
# writes to the same place. Nothing types into the orchestrator's input box.
inbox_dir() {
    echo "$(git rev-parse --path-format=absolute --git-common-dir)/orchestrator"
}
