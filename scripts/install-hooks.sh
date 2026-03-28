#!/usr/bin/env bash

set -euo pipefail

quiet=0

if [ "${1:-}" = "--quiet" ]; then
    quiet=1
    shift
fi

repo_root="$(git rev-parse --show-toplevel)"
git_dir="$(git rev-parse --git-dir)"
active_hooks_dir="$(git rev-parse --git-path hooks)"

case "$git_dir" in
    /*) ;;
    *) git_dir="$repo_root/$git_dir" ;;
esac

case "$active_hooks_dir" in
    /*) ;;
    *) active_hooks_dir="$repo_root/$active_hooks_dir" ;;
esac

target_hook_dirs=("$active_hooks_dir")

if [ "$git_dir/hooks" != "$active_hooks_dir" ]; then
    target_hook_dirs+=("$git_dir/hooks")
fi

install_hook() {
    local hooks_dir="$1"
    local name="$2"
    local source_path="$repo_root/.githooks/$name"
    local target_path="$hooks_dir/$name"

    if [ ! -f "$source_path" ]; then
        echo "missing managed hook template: $source_path" >&2
        return 1
    fi

    mkdir -p "$hooks_dir"
    ln -sfn "$source_path" "$target_path"
    chmod +x "$source_path" "$target_path"

    if [ "$quiet" != "1" ]; then
        echo "installed $name -> $target_path"
    fi
}

for hooks_dir in "${target_hook_dirs[@]}"; do
    install_hook "$hooks_dir" pre-commit
    install_hook "$hooks_dir" commit-msg
done
