#!/usr/bin/env bash
# Create a git worktree for one task, copy local env files into it, and start
# a Claude worker there in its own Herdr space, pointed at the brief and the
# worker rules.
# Usage:
#   spawn-task.sh <type> <slug> <brief-file> [--model <m>] [--effort <e>]
#   spawn-task.sh --check    only check that the orchestrator can run here
#   type: feature | bugfix | hotfix | chore | refactor | docs
#   slug: kebab-case, lowercase, e.g. blog-empty-state
# Branch names, base branches, setup, models, and extra worker rules come from
# the repo's .claude/orchestrator.md (see ../SETTINGS.md).
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKER_SKILL="$script_dir/../../orchestrator-worker/SKILL.md"
source "$script_dir/lib.sh"

[ "${ORCHESTRATOR_WORKER:-}" != 1 ] || die "this session is a worker; workers don't spawn tasks"
command -v jq >/dev/null || die "jq is required"
command -v hc >/dev/null || die "hc (the Herdr core) is required"
hc ls --json >/dev/null 2>&1 || die "the Herdr core isn't running; start Herdr"
[ -f "$WORKER_SKILL" ] || die "missing worker rules: $WORKER_SKILL"
root="$(repo_root)"
git -C "$root" rev-parse --verify --quiet HEAD >/dev/null ||
    die "the repo has no commits yet; worktrees need at least one"
# Workers push and merge through gh whenever the repo has a remote.
! git -C "$root" remote get-url origin >/dev/null 2>&1 || command -v gh >/dev/null ||
    die "gh is required to open and merge pull requests"

if [ "${1:-}" = --check ]; then
    echo ok
    exit 0
fi

usage="usage: spawn-task.sh <${TYPES// /|}> <slug> <brief-file> [--model <m>] [--effort <e>]"
type="${1:?$usage}"
slug="${2:?$usage}"
brief_src="${3:?$usage}"
shift 3
pick_model="" effort=""
while [ $# -gt 0 ]; do
    case "$1" in
        --model) pick_model="${2:?$usage}"; shift 2 ;;
        --effort) effort="${2:?$usage}"; shift 2 ;;
        *) die "unknown option '$1'. $usage" ;;
    esac
done

[ -s "$brief_src" ] || die "brief file is missing or empty: $brief_src"
[[ " $TYPES " == *" $type "* ]] || die "unknown type '$type'. $usage"
[[ "$slug" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] || die "slug must be kebab-case: $slug"

if [ "$type" = hotfix ]; then base="$(hotfix_base)"; else base="$(base_branch)"; fi
base_ref="$(base_ref "$base")" ||
    die "base branch '$base' not found; set 'base' in $(config_file)"

branch="$(prefix_for "$type")/$slug"
git -C "$root" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null &&
    die "branch $branch already exists"

# Terminal names: 1-32 of a-z 0-9 - _, unique among live terminals.
agent_name="${slug:0:32}"
agent_name="${agent_name%-}"
hc ls --json | jq -e --arg n "$agent_name" 'any(.terminals[]; .name == $n)' >/dev/null &&
    die "a live terminal is already named $agent_name"

worktree_path="$(worktree_dir "$slug")"
[ ! -e "$worktree_path" ] || die "$worktree_path already exists"
mkdir -p "$(dirname "$worktree_path")"
git -C "$root" worktree add --quiet -b "$branch" "$worktree_path" "$base_ref"

# Keep the brief with the worktree: the worker reads it from there, and
# list-tasks.sh shows each task's goal after the orchestrator's context is gone.
cp "$brief_src" "$(brief_file "$worktree_path")"

env_report="$("$script_dir/copy-env.sh" "$worktree_path")"
echo "$env_report" >&2
env_files="$(sed -n 's/^copy-env: copied //p' <<<"$env_report" | paste -sd ' ')"

# Workers run without permission prompts (the user's choice). This flag
# leaves the user's approval gate to the "Ship" rule in the worker skill.
# ORCHESTRATOR_WORKER tells the orchestrator skill, which every session can
# see, that this session is a worker and must not spawn tasks of its own.
# A model in the repo's settings wins over the orchestrator's pick.
model="$(model_for "$type")"
model="${model:-$pick_model}"
claude_args=(--dangerously-skip-permissions
    --settings '{"env":{"ORCHESTRATOR_WORKER":"1"}}')
[ -z "$model" ] || claude_args+=(--model "$model")
[ -z "$effort" ] || claude_args+=(--effort "$effort")

setup="$(conf setup '')"
rules="$(config_rules)"
report="$script_dir/report.sh $slug"

# Optional lines of the workspace facts, empty when they don't apply.
env_line=""
[ -z "$env_files" ] ||
    env_line="- Copied from the main checkout: $env_files. Never print or commit them."$'\n'
setup_line=""
[ -z "$setup" ] ||
    setup_line="- Dependencies aren't shared between worktrees. Run '$setup' first."$'\n'
rules_block=""
[ -z "$rules" ] || rules_block=$'\n'"Project rules for workers:"$'\n'"$rules"$'\n'

targets="$(merge_targets "$branch" | paste -sd ' ')"
# The brief and the worker rules go in as file paths, keeping the prompt short.
brief="$(brief_file "$worktree_path")"
worker_rules="$(realpath "$WORKER_SKILL")"

prompt="You are an orchestrator worker. Before anything else, read both files in full:
- Your brief: $brief
- Your rules: $worker_rules

Workspace facts (added by the orchestrator):
- Branch $branch in the worktree $worktree_path, based on $base.
- Merge targets: $targets.
- Report command: $report \"<message>\"
${env_line}${setup_line}- Other worktrees may be running at the same time. Pick a free port for any
  server you start, and leave shared services running.
${rules_block}"

# A terminal labelled with a space and tab id Herdr doesn't know yet shows up
# as a new space in the sidebar. --no-parent keeps the worker alive when this
# session ends. The prompt goes in as claude's first message.
new_id() { echo "$1$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"; }
space_id="$(new_id sp)"
started="$(hc run --bg --json --no-parent --keep --name "$agent_name" \
    --cwd "$worktree_path" --label "herdr.space=$space_id" \
    --label "herdr.tab=$(new_id tb)" --label "orchestrator.branch=$branch" \
    -- claude "${claude_args[@]}" "$prompt")"
terminal="$(jq -r '.address' <<<"$started")"
# A new worktree is a folder Claude hasn't seen, so it asks whether to trust
# it. This script made it from the repo the user already works in: say yes.
# ponytail: matches the dialog's text; update it if Claude rewords the prompt
for _ in $(seq 30); do
    if hc read "$terminal" 2>/dev/null | grep -q 'Yes, I trust this folder'; then
        hc keys "$terminal" down enter >/dev/null
        break
    fi
    # Claude reports a status once it's past any dialog.
    [ "$(hc get "$terminal" 2>/dev/null | jq -r '.status.state // empty')" = "" ] || break
    sleep 1
done
# Name the space after the task. Needs the window open; harmless if it isn't.
herdr-app do space.rename --id "$space_id" --name "$slug" >/dev/null 2>&1 || true

jq -n --arg type "$type" --arg branch "$branch" --arg base "$base_ref" \
    --arg path "$worktree_path" --arg space "$space_id" \
    --arg terminal "$terminal" --arg agent "$agent_name" \
    --arg model "${model:-default}" --arg effort "${effort:-default}" \
    '{type: $type, branch: $branch, base: $base, worktree: $path,
      space: $space, terminal: $terminal, agent: $agent, model: $model,
      effort: $effort}'
