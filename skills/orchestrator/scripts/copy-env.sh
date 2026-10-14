#!/usr/bin/env bash
# Copy the main checkout's local env files into a worktree.
# Usage: copy-env.sh <worktree-path> [--force]
# Copies the files named by `env_files` in .claude/orchestrator.md, or else
# every git-ignored .env* file at the repo root (.env, .env.local, ...).
# Tracked files such as .env.example are already in the worktree.
# Never prints file contents. Keeps existing files unless --force.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

target="${1:?usage: copy-env.sh <worktree-path> [--force]}"
force="${2:-}"
[ -d "$target" ] || die "no such directory: $target"

source_root="$(cd "$target" && repo_root)"
if [ "$(realpath "$source_root")" = "$(realpath "$target")" ]; then
    echo "copy-env: target is the main checkout, nothing to do"
    exit 0
fi

names="$(cd "$source_root" && conf env_files '')"
if [ -z "$names" ]; then
    shopt -s nullglob dotglob
    for f in "$source_root"/.env*; do
        name="${f##*/}"
        [ -f "$f" ] && git -C "$source_root" check-ignore -q -- "$name" &&
            names+="$name "
    done
fi

copied=0
for name in $names; do
    src="$source_root/$name"
    [ -f "$src" ] || { echo "copy-env: $name not found in the main checkout"; continue; }
    dest="$target/$name"
    if [ -e "$dest" ] && [ "$force" != "--force" ]; then
        echo "copy-env: kept existing $name"
        continue
    fi
    install -m 600 "$src" "$dest"
    echo "copy-env: copied $name"
    copied=1
done
[ "$copied" = 1 ] || echo "copy-env: no env files copied"
