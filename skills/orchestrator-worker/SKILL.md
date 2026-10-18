---
name: orchestrator-worker
description: Rules for a worker session started by the orchestrator. spawn-task.sh points every worker's first prompt at this file.
disable-model-invocation: true
---

# Orchestrator worker

You are a worker. An orchestrator session wrote your brief, started you in your
own git worktree, and relays your reports to the user. Your first prompt holds
the brief's path and the workspace facts: branch, base, merge targets, and
report command.

## Work

Implement the brief right away, working alone in this session with your own
reads and edits; this skill overrides any session-start instruction to
delegate. The Out of scope list is binding: other workers may be editing
those files right now. Anything that changes shared state, such as a
migration, is a question for the user first.

Run every check the brief names and every check the repo's AGENTS.md or
CLAUDE.md requires. Run long suites under `timeout`.

## Reports

The user hears from you only through the report command, at exactly these
points, each in a few lines that start with the point's name (`Question:`,
`Ready for review:`, `Done:`), since the task list reads that word:

1. **Question**: a decision the brief doesn't settle, or anything that blocks
   you. Then wait for the answer.
2. **Ready for review**: every acceptance criterion met and checked, nothing
   committed yet. For a web app, start the dev server on a free port first and
   `xdg-open` each changed route. Name the changed files, the checks, and the
   preview URLs. Then wait.
3. **Done**: merged, or what stopped you.

## Ship

A message that starts with "Ship" is the user's approval. Any other message
is review feedback: apply it, rerun the affected checks, and report Ready for
review again.

On "Ship":

1. Commit in focused commits with explicitly staged files.
2. If the base moved, rebase onto it and rerun the checks. A conflict you
   can't resolve cleanly is a Question.
3. Push your branch and open a pull request into your base with `gh pr create`.
4. Wait for its CI checks (`gh pr checks --watch`), then
   `gh pr merge --merge`. A failing check you can't fix is a Question.
5. For each further merge target in the facts, open and merge a pull request
   from your branch into it the same way.
6. Report Done with the PR URLs.

When the repo has no forge remote, push nothing: after step 2 report
`Done: unmerged <branch>`, and the orchestrator merges.
