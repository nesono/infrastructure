#!/usr/bin/env bash
# Run on the production host. All services except Borg are offline during backup.
set -euo pipefail

compose=(docker compose -f /svc/volumes/docker-compose/docker-compose.yaml)
services=()
applications=()
databases=()
restart_needed=false

exec 9>/run/lock/compose-backup.lock
flock -n 9 || { echo 'Another cold backup is running.' >&2; exit 1; }

restart_services() {
    echo 'Restarting previously running services...'
    "${compose[@]}" start --wait --wait-timeout 180 "${services[@]}"
}

cleanup() {
    result=$?
    trap - EXIT INT TERM
    if $restart_needed; then
        if ! restart_services; then
            echo 'Restart failed; check docker compose ps and restore services manually.' >&2
            result=1
        fi
    fi
    exit "$result"
}
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

echo 'Creating Borg archive...'
"${compose[@]}" exec -T borg-backup sh -ec '
    BORG_PASSPHRASE=$(cat "$BORG_PASSPHRASE_FILE")
    export BORG_PASSPHRASE
    exec borgmatic create --verbosity 1 --stats
'
restart_services
restart_needed=false
echo 'Backup completed; services restarted.'
