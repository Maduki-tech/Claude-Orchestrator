#!/usr/bin/env bash
# Create a Herdr worktree for one task, copy local env files into it, start a
# Claude worker there, and point it at the brief and the worker rules.
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
[ "${HERDR_ENV:-}" = 1 ] || die "not running inside a Herdr pane"
command -v jq >/dev/null || die "jq is required"
command -v herdr >/dev/null || die "herdr is required"
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

# Herdr agent names: [a-z][a-z0-9_-]{0,31}, unique among live agents.
agent_name="${slug:0:32}"
agent_name="${agent_name%-}"
herdr agent get "$agent_name" >/dev/null 2>&1 &&
    die "a live agent is already named $agent_name"

created="$(herdr worktree create --cwd "$root" --branch "$branch" \
    --base "$base_ref" --label "$slug" --no-focus)"
worktree_path="$(jq -r '.result.worktree.path' <<<"$created")"
worker_pane="$(jq -r '.result.root_pane.pane_id' <<<"$created")"
workspace_id="$(jq -r '.result.workspace.workspace_id' <<<"$created")"

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
herdr agent start "$agent_name" --kind claude --pane "$worker_pane" \
    --timeout 60000 -- "${claude_args[@]}" >/dev/null

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
# The brief and the worker rules go in as file paths, not pasted text:
# `herdr agent prompt` types into the pane, and a short prompt types reliably.
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

herdr agent prompt "$agent_name" "$prompt" >/dev/null

jq -n --arg type "$type" --arg branch "$branch" --arg base "$base_ref" \
    --arg path "$worktree_path" --arg workspace "$workspace_id" \
    --arg pane "$worker_pane" --arg agent "$agent_name" \
    --arg model "${model:-default}" --arg effort "${effort:-default}" \
    '{type: $type, branch: $branch, base: $base, worktree: $path,
      workspace: $workspace, pane: $pane, agent: $agent, model: $model,
      effort: $effort}'
