# claude-orchestrator

A Claude Code setup that hands each change to its own worker in a
Herdr git worktree, so your main session stays free.

- `skills/orchestrator`: the dispatcher skill plus the scripts it calls (spawn, list, report, finish)
- `skills/orchestrator-worker`: the skill each worker follows
- `mods/orchestrator-worktrees`: a Claude Code mod that shows every task and its state in a band and a pane

## Requirements

`git`, `jq`, `herdr`, and Claude Code.

## Install

```sh
git clone https://github.com/Maduki-tech/claude-orchestrator
cd claude-orchestrator && ./install.sh
```

This symlinks the skills into `~/.agents/skills` and `~/.claude/skills`, the mod
into `~/.claude/mods`, and adds the mod to `CLAUDE_CODE_PLUGIN_DIRS` in
`~/.claude/settings.json`. Pulling the repo updates everything in place.

Per-repo settings: see [skills/orchestrator/SETTINGS.md](skills/orchestrator/SETTINGS.md).
