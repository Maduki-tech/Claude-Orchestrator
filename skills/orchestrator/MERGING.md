# Merging and cleaning up by hand

Workers normally merge their own pull requests after the user's "Ship", and
you run `finish-task.sh <branch>` on their Done report. This file covers
everything else. `finish-task.sh` first fetches and fast-forwards each base
branch where it's checked out, then removes the task's worktree, its Herdr
workspace, and its branch once the work has landed.

- **A repo with no forge remote:** the worker reports Done with an unmerged
  branch. Run `finish-task.sh <branch> --merge`. It merges with `--no-ff`
  into each merge target (a hotfix goes into its base and back into the
  regular base), where the target is checked out or in a temporary worktree.
  Nothing is pushed, so ask the user whether to push afterwards.
- **The user asks you to merge a pull request** a worker left open: check its
  CI (`gh pr checks <branch>`), merge with `gh pr merge <branch> --merge`,
  then run `finish-task.sh <branch>`.
- **The work already landed**, through a pull request or by hand:
  `finish-task.sh <branch>`. It removes everything only after it confirms
  the merge, in git or as a merged GitHub pull request.
- **Leftovers:** `finish-task.sh --all-merged` removes every worktree whose
  branch is merged, skipping any with a live agent. Offer it when
  `list-tasks.sh` shows finished tasks.

The script refuses when a worktree or a merge target has uncommitted changes,
when the branch isn't merged, or when the branch has no commits yet. Pass the
reason on to the user and leave the state as it is: each check protects work
that hasn't landed yet. When a merge stops on a conflict, the script names the
worktree it stopped in; tell the user and leave it there.
