#!/usr/bin/env bash
# Wait until workers add reports to the inbox, print the new ones, and exit.
# The orchestrator runs this in the background and starts it again after each
# wake. Only one watcher runs per repo; a second one exits right away.
# Usage: watch-inbox.sh
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib.sh"

dir="$(inbox_dir)"
mkdir -p "$dir"
inbox="$dir/inbox"
seen="$dir/seen"
touch "$inbox"

exec 8>"$dir/watch.lock"
flock -n 8 || { echo "watch-inbox: a watcher is already running"; exit 0; }

while :; do
    offset="$(cat "$seen" 2>/dev/null || echo 0)"
    if [ "$(stat -c %s "$inbox")" -gt "$offset" ]; then
        sleep 1 # let reports sent at the same moment arrive together
        size="$(stat -c %s "$inbox")"
        tail -c +"$((offset + 1))" "$inbox" | head -c "$((size - offset))" |
            jq -r '"[worker \(.slug)] \(.message)"'
        echo "$size" >"$seen"
        exit 0
    fi
    inotifywait -qq -t 60 -e modify "$inbox" 2>/dev/null || sleep 2
done
