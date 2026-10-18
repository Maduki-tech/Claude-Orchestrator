# claude-orchestrator

A Claude Code setup that hands each change to its own worker in a
Herdr git worktree, so your main session stays free.

- `skills/orchestrator`: the dispatcher skill plus the scripts it calls (spawn, list, report, finish)
- `skills/orchestrator-worker`: the skill each worker follows
- `mods/orchestrator-worktrees`: a Claude Code mod that shows every task and its state in a band and a pane

## Requirements

`git`, `jq`, `herdr`, `gh` (for repos with a remote), `inotifywait` (from
inotify-tools; optional, the inbox watcher polls without it), and Claude Code.

## Install

```sh
git clone https://github.com/Maduki-tech/claude-orchestrator
cd claude-orchestrator && ./install.sh
```

This symlinks the skills into `~/.agents/skills` and `~/.claude/skills`, the mod
into `~/.claude/mods`, and adds the mod to `CLAUDE_CODE_PLUGIN_DIRS` in
`~/.claude/settings.json`. Pulling the repo updates everything in place.

Per-repo settings: see [skills/orchestrator/SETTINGS.md](skills/orchestrator/SETTINGS.md).

## Usage

Questions, explanations, reviews, and diagnosis are answered in your session
with reads only. Any change to files, even one line, is spawned as a task: its
own worktree and worker. Say "do it here" and the session edits directly instead.

Workers report back to the session, and each report starts with one of:

- **Question:** a decision the brief doesn't settle; your answer goes back to the worker.
- **Ready for review:** the changed files, the checks run, and any preview URLs. Reply "Ship" to approve the commit and merge; anything else is review feedback.
- **Done:** the worker merged, and the worktree and branch are cleaned up.

`/worktrees` opens the task pane.
