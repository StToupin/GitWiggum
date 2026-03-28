#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
postgres_state_dir="$repo_root/.devenv/state/postgres"
process_compose_socket="$repo_root/.devenv/run/pc.sock"

devenv_pattern='devenv-tasks run --task-file|process-compose|direnv exec \. devenv up|(^|[ /])devenv up($| )'
service_pattern='devenv-processes-|MailHog|/bin/minio server|RunDevServer|ngrok http|stripe listen'

log() {
    printf '%s\n' "$*"
}

collect_matching_pids() {
    {
        pgrep -f "$devenv_pattern" 2>/dev/null || true
        pgrep -f "$service_pattern" 2>/dev/null || true
        pgrep -x postgres 2>/dev/null || true
    } | awk 'NF { print }' | sort -u
}

kill_matching_pids() {
    local signal="$1"
    local pids

    pids="$(collect_matching_pids)"

    if [[ -z "$pids" ]]; then
        return 1
    fi

    log "Sending SIG${signal} to matching devenv, postgres, and child services:"
    printf '  %s\n' $pids

    # Intentionally split on whitespace so `kill` receives one PID per argument.
    # shellcheck disable=SC2086
    kill -"${signal}" $pids 2>/dev/null || true
    return 0
}

cleanup_current_worktree() {
    rm -f "$postgres_state_dir/postmaster.pid"
    rm -f "$process_compose_socket"
}

main() {
    if ! kill_matching_pids TERM; then
        log "No matching devenv, postgres, or gitWiggum child-service processes found."
    fi

    sleep 3

    if kill_matching_pids KILL; then
        sleep 2
    fi

    local remaining_pids
    remaining_pids="$(collect_matching_pids)"

    cleanup_current_worktree

    if [[ -n "$remaining_pids" ]]; then
        log "Processes still running after SIGKILL:"
        printf '  %s\n' $remaining_pids
        exit 1
    fi

    log "Stopped all matching devenv and postgres processes."
    log "Cleaned current worktree runtime markers in $repo_root/.devenv."
}

main "$@"
