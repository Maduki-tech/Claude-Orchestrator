# Project settings

Each repo can tune the orchestrator in `.claude/orchestrator.md` at its root.
The scripts read it on every run; the orchestrator itself only needs this file
when a repo has no settings yet, or when the user wants to change them.

## Format

Optional front matter, then optional free text. Every key is optional.

```markdown
---
base: develop          # branch tasks start from and merge into
hotfix_base: main      # branch hotfixes start from and merge into
hotfix_merge_back: true
setup: bun install     # workers run it before anything else
env_files: .env.local  # space-separated
prefix_feature: features
model: sonnet          # worker model for every type
model_bugfix: opus     # worker model for one type
---
Free text: extra rules added to every worker's first prompt, such as shared
services, ports, or steps that need the orchestrator's sign-off.
```

| Key                 | Default                                                    |
| ------------------- | ---------------------------------------------------------- |
| `base`              | the remote's default branch, else `main`                   |
| `hotfix_base`       | same as `base`                                             |
| `hotfix_merge_back` | `true`: a merged hotfix also merges into `base` when the two differ |
| `setup`             | none                                                       |
| `env_files`         | every git-ignored `.env*` file at the repo root            |
| `prefix_<type>`     | `feature`, `fix` (bugfix), else the type name              |
| `model`, `model_<type>` | none: the orchestrator's pick per task, else Claude's default. `model_<type>` wins over `model`, and both win over the pick |

## Checking a new repo

Before the first spawn in a repo without the file, find out whether the
defaults fit. Each answer comes from the repo or from the user:

- **Base branch**: which branch does work merge into? `git branch -a` and
  recent merge commits show it. Gitflow repos use `develop` for `base` and
  `main` for `hotfix_base`.
- **Setup**: what does a fresh checkout need before it runs? The lockfile
  names the install command.
- **Env files**: which ignored files does the app need to start? Check that
  the default glob catches them.
- **Shared services**: what runs once for the whole machine (a database
  container, a fixed port)? Each one becomes a worker rule in the free text,
  stating what workers may and may not do with it.

When any default doesn't fit, offer to write the file, and ask the user
whether to commit it.
