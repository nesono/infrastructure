#!/usr/bin/env bash
# Run on the production host. All services except Borg are offline during backup.
set -uo pipefail

compose=(docker compose -f /svc/volumes/docker-compose/docker-compose.yaml)

restart_services() {
    echo 'Restarting previously running services...'
    "${compose[@]}" start --wait --wait-timeout 180 "${services[@]}"
}

cleanup() {
    result=$?
    trap - EXIT INT TERM
    if [[ -n "$pull_pid" ]]; then
        kill "$pull_pid" 2>/dev/null || true
        wait "$pull_pid" || true
    fi
    if $restart_needed; then
        if ! restart_services; then
            echo 'Restart failed; check docker compose ps and restore services manually.' >&2
            result=1
        fi
    fi
    exit "$result"
}

run_maintenance() {
    services=()
    applications=()
    databases=()
    restart_needed=false
    pull_pid=

    exec 9>/run/lock/compose-backup.lock
    echo 'Waiting for running service jobs or another maintenance run to finish...'
    flock -x 9

    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    # Verify Borg's existing passphrase file before interrupting services.
    "${compose[@]}" exec -T borg-backup sh -ec 'test -r "$BORG_PASSPHRASE_FILE"'
    running=$("${compose[@]}" ps --status running --services)
    while IFS= read -r service; do
        [[ -n "$service" && "$service" != borg-backup ]] || continue
        services+=("$service")
        # Keep this classification in sync when adding a database service.
        case "$service" in
            mysql_*|mariadb_*|pgsql_*|redis_*) databases+=("$service") ;;
            *) applications+=("$service") ;;
        esac
    done <<< "$running"
    [[ ${#services[@]} -gt 0 ]] || { echo 'No running services to back up.' >&2; exit 1; }

    restart_needed=true
    echo 'Stopping applications, then databases...'
    if [[ ${#applications[@]} -gt 0 ]]; then
        "${compose[@]}" stop --timeout 120 "${applications[@]}"
    fi
    if [[ ${#databases[@]} -gt 0 ]]; then
        "${compose[@]}" stop --timeout 120 "${databases[@]}"
    fi

    # Do not archive a database that was killed after its shutdown timeout.
    containers=$("${compose[@]}" ps --all --quiet "${services[@]}")
    [[ -n "$containers" ]] || { echo 'Stopped containers not found.' >&2; exit 1; }
    while IFS= read -r container; do
        state=$(docker inspect --format '{{.State.Running}} {{.State.ExitCode}} {{.State.OOMKilled}} {{index .Config.Labels "com.docker.compose.service"}}' "$container")
        read -r active status oom service <<< "$state"
        if [[ "$active" != false || "$status" == 137 || "$oom" != false ]]; then
            echo "Container $container did not stop safely ($state); aborting backup." >&2
            exit 1
        fi
        case "$service" in
            mysql_*|mariadb_*|pgsql_*|redis_*)
                [[ "$status" == 0 ]] || { echo "$service exited with $status; aborting backup." >&2; exit 1; } ;;
        esac
    done <<< "$containers"

    echo 'Pulling Compose images in parallel with the Borg backup...'
    "${compose[@]}" pull --policy always &
    pull_pid=$!

    echo 'Creating Borg archive...'
    "${compose[@]}" exec -T borg-backup sh -ec '
        BORG_PASSPHRASE=$(cat "$BORG_PASSPHRASE_FILE")
        export BORG_PASSPHRASE
        exec borgmatic create --verbosity 1 --stats
    '
    echo 'Borg archive created; waiting for image pulls to finish...'
    if wait "$pull_pid"; then
        pull_pid=
    else
        pull_pid=
        echo 'Image pull failed; starting existing containers without applying image updates.' >&2
        exit 1
    fi

    echo 'Starting previously running services with their updated images...'
    "${compose[@]}" up --detach --wait --wait-timeout 180 --no-deps --pull never "${services[@]}" borg-backup
    restart_needed=false
    echo 'Nightly maintenance completed; services are running.'
}

report=$(mktemp) || exit 1
trap 'rm -f -- "$report"' EXIT

# Keep errexit in the maintenance subprocess and collect both pipeline statuses.
(
    trap - EXIT
    set -e
    run_maintenance
) 2>&1 | tee "$report"
read -r maintenance_status report_status <<< "${PIPESTATUS[*]}"

subject='Nightly maintenance: SUCCESS'
if (( maintenance_status != 0 || report_status != 0 )); then
    subject='Nightly maintenance: FAILED'
fi

if ! "${compose[@]}" exec -T borg-backup sh -ec '
    {
        printf "From: %s\nTo: %s\nSubject: %s\n\n" "$MAIL_FROM" "$MAIL_TO" "$1"
        cat
    } | sendmail -t
' sh "$subject" < "$report"; then
    echo 'Could not send nightly maintenance report.' >&2
    report_status=1
fi

if (( maintenance_status != 0 )); then
    exit "$maintenance_status"
fi
exit "$report_status"
