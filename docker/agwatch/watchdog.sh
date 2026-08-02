#!/usr/bin/env bash
# watchdog.sh - periodic check + atomic restart + AUTO-CLEANUP of the
# campaign when it completes. It talks to the host docker daemon through the
# mounted socket - no process scraping ever (the root cause of every
# duplicate-loop bug in the Windows era).
#
# Two failure modes, one action (docker restart = atomic, unique by name):
#   1. loop container unhealthy (heartbeat stale inside the container)
#   2. loop container gone/down (restart policy failed)
#
# Completion: when the loop exits 0 ("AGR LOOP COMPLETE"), and if
# AGR_AUTO_CLEANUP=1, this watchdog removes the whole stack (containers,
# campaign volumes, images, network) - the system is left as clean as (or
# cleaner than) it was found.
#
# Env:
#   AGR_LOOP_NAME          (default agloop)
#   AGR_CAMPAIGN           campaign name (default main)
#   AGR_PROJECT            docker compose project name (default agr-<campaign>)
#   AGR_STALL_MINUTES      heartbeat staleness threshold (default 25)
#   AGR_CHECK_INTERVAL_S   check cadence (default 300)
#   AGR_AUTO_CLEANUP       1 = remove the whole stack on completion (default 0)
#   AGR_PRUNE_IMAGES       1 = also remove built images on cleanup (default 1)
#   AGR_PRUNE_SYSTEM       1 = also docker system prune -f (default 0)
set -uo pipefail

LOOP="${AGR_LOOP_NAME:-agloop}"
CAMP="${AGR_CAMPAIGN:-main}"
PROJECT="${AGR_PROJECT:-agr-${CAMP}}"
STALL_MIN="${AGR_STALL_MINUTES:-25}"
INTERVAL_S="${AGR_CHECK_INTERVAL_S:-300}"
AUTO_CLEANUP="${AGR_AUTO_CLEANUP:-0}"
PRUNE_IMAGES="${AGR_PRUNE_IMAGES:-1}"
PRUNE_SYSTEM="${AGR_PRUNE_SYSTEM:-0}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

cleanup_stack() {
    log "campaign '$CAMP' completed - launching cleaner"
    # The cleaner is a SHORT-LIVED independent container: it survives this
    # watchdog (which must remove itself and its own image, impossible to do
    # in-process). It sleeps 2s (let this container exit), then removes
    # containers, volumes, network and images - including ours. --rm removes
    # the cleaner itself at the end. Nothing is left behind.
    docker run -d --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -e AGR_LOOP_NAME="$LOOP" \
        -e AGR_PROJECT="$PROJECT" \
        -e AGR_CAMPAIGN="$CAMP" \
        -e AGR_PRUNE_IMAGES="$PRUNE_IMAGES" \
        -e AGR_PRUNE_SYSTEM="$PRUNE_SYSTEM" \
        --name "agclean-${CAMP}" \
        docker:28-cli sh -c '
            sleep 2
            docker rm -f agloop-$AGR_CAMPAIGN agdash-$AGR_CAMPAIGN agwatch-$AGR_CAMPAIGN >/dev/null 2>&1
            docker volume rm ${AGR_PROJECT}_agldata ${AGR_PROJECT}_agrshared ${AGR_PROJECT}_seed-empty >/dev/null 2>&1
            docker network rm ${AGR_PROJECT}_default >/dev/null 2>&1
            if [ "$AGR_PRUNE_IMAGES" = "1" ]; then
                docker image rm agr-agloop agr-agwatch agr-agdash >/dev/null 2>&1
            fi
            if [ "$AGR_PRUNE_SYSTEM" = "1" ]; then
                docker system prune -f >/dev/null 2>&1
            fi
        ' >/dev/null 2>&1 || true
    exit 0
}

loop_exited_zero() {
    # exited with code 0 == "AGR LOOP COMPLETE" (restart policy on-failure
    # does NOT relaunch it, so exited(0) is terminal and unambiguous)
    local status code
    status="$(docker inspect -f '{{.State.Status}}' "$LOOP" 2>/dev/null || echo gone)"
    [ "$status" = "exited" ] || return 1
    code="$(docker inspect -f '{{.State.ExitCode}}' "$LOOP" 2>/dev/null || echo 1)"
    [ "$code" = "0" ]
}

while :; do
    sleep "$INTERVAL_S"

    # 0) completion -> auto-cleanup
    if loop_exited_zero; then
        if [ "$AUTO_CLEANUP" = "1" ]; then
            cleanup_stack
            # we removed ourselves; nothing else to do
            exit 0
        fi
        log "loop completed (exited 0) - auto-cleanup disabled, leaving stack up"
        # nothing to keep checking; stand down unless user restarts us
        exit 0
    fi

    # 1) is the container registered at all?
    if ! docker inspect "$LOOP" >/dev/null 2>&1; then
        log "container '$LOOP' does not exist - nothing to do (compose down?)"
        continue
    fi

    # 2) health status (docker native healthcheck)
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$LOOP" 2>/dev/null)"
    if [ "$health" = "unhealthy" ]; then
        log "health=unhealthy - restarting $LOOP"
        docker restart "$LOOP"
        continue
    fi

    # 3) heartbeat staleness (covers loops that are alive but dead inside)
    ts="$(docker exec "$LOOP" stat -c %Y /work/agr_logs/heartbeat 2>/dev/null || echo 0)"
    if [ "$ts" = "0" ]; then
        log "no heartbeat file readable - restarting $LOOP"
        docker restart "$LOOP"
        continue
    fi
    age=$(( $(date +%s) - ts ))
    if [ "$age" -gt $((STALL_MIN * 60)) ]; then
        log "heartbeat stale ${age}s (>{STALL_MIN}min) - restarting $LOOP"
        docker restart "$LOOP"
    fi
done
