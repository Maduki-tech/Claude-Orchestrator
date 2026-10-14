#!/usr/bin/env bash
# Append a worker's status report to the orchestrator inbox and show a Herdr
# notification. The orchestrator's background watch-inbox.sh picks it up, so
# nothing is typed into the orchestrator pane while the user may be typing.
# Usage: report.sh <slug> <message>
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib.sh"

slug="${1:?usage: report.sh <slug> <message>}"
message="${2:?missing message}"

dir="$(inbox_dir)"
mkdir -p "$dir"
line="$(jq -nc --arg time "$(date -Iseconds)" --arg slug "$slug" \
    --arg message "$message" '{time: $time, slug: $slug, message: $message}')"
{
    flock 9
    printf '%s\n' "$line" >>"$dir/inbox"
} 9>"$dir/inbox.lock"

herdr notification show "worker $slug" --body "$message" --sound request \
    >/dev/null 2>&1 || true
echo "report: queued for the orchestrator"
