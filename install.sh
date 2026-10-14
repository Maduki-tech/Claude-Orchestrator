#!/usr/bin/env bash
# Symlinks the skills and the mod into place and registers the mod with Claude Code.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
settings="$HOME/.claude/settings.json"
mod="$HOME/.claude/mods/orchestrator-worktrees"

mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.claude/mods"
for s in orchestrator orchestrator-worker; do
  ln -sfn "$repo/skills/$s" "$HOME/.agents/skills/$s"
  ln -sfn "$HOME/.agents/skills/$s" "$HOME/.claude/skills/$s"
done
ln -sfn "$repo/mods/orchestrator-worktrees" "$mod"

[ -f "$settings" ] || echo '{}' > "$settings"
tmp="$(mktemp)"
jq --arg m "$mod" '.env.CLAUDE_CODE_PLUGIN_DIRS |=
  (if . == null or . == "" then $m elif (split(":") | index($m)) then . else . + ":" + $m end)' \
  "$settings" > "$tmp" && mv "$tmp" "$settings"
echo "Installed. Restart Claude Code."
