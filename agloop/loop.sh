#!/usr/bin/env bash
# loop.sh - AGR campaign loop (port of run_agr_opencode.ps1 to bash).
#
# One container = one campaign = one loop. Iterations are launched as
# subprocesses with a hard timeout (killed on expiry, recorded in
# agr_logs/completed.txt so resume skips them). All state lives in the
# bind-mounted repo (/work): results.tsv, STRATEGY.md, agr_logs/.
#
# Env (all optional unless noted):
#   AGR_MAX_ITERATIONS      (default 200)
#   AGR_ITER_TIMEOUT_MIN    (default 40)
#   AGR_QUIET_WINDOW        "HH:MM-HH:MM" - only run measurements inside window
#   AGR_DASH_CMD            optional command to regenerate dashboard per iteration
set -uo pipefail

WORK=/work
cd "$WORK"

MAX_ITER="${AGR_MAX_ITERATIONS:-200}"
TIMEOUT_MIN="${AGR_ITER_TIMEOUT_MIN:-40}"
QUIET="${AGR_QUIET_WINDOW:-}"

mkdir -p agr_logs
STATE_FILE="agr_logs/completed.txt"
touch "$STATE_FILE"

echo "========================================"
echo " AGR LOOP (containerized)"
echo " Max iterations : $MAX_ITER"
echo " Iter timeout   : ${TIMEOUT_MIN} min"
echo " Quiet window   : ${QUIET:-off}"
echo " Working dir    : $WORK"
echo "========================================"

# Heartbeat: refreshed every iteration AND periodically so a slow agent
# doesn't look dead. The watchdog only restarts on TRUE staleness.
touch agr_logs/heartbeat

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

quiet_wait() {
    [ -n "$QUIET" ] || return 0
    local start end now
    start="${QUIET%%-*}"; end="${QUIET##*-}"
    while :; do
        now="$(date +%H:%M)"
        if [[ "$now" > "$start" ]] && [[ "$now" < "$end" ]]; then return 0; fi
        log "outside quiet window ($QUIET) - sleeping 60s"
        sleep 60
    done
}

for ((i = 1; i <= MAX_ITER; i++)); do
    grep -qx "$i" "$STATE_FILE" 2>/dev/null && continue

    log "=== Iteration $i / $MAX_ITER ==="
    quiet_wait

    OUT="agr_logs/iter_$(printf '%03d' "$i").log"
    ERR="agr_logs/iter_$(printf '%03d' "$i").err.log"

    # hard timeout, same semantics as the PS1 WaitForExit(ms) + taskkill
    timeout -k 60 $((TIMEOUT_MIN * 60)) /opt/agr/iterate.sh >"$OUT" 2>"$ERR"
    code=$?

    if [ "$code" -eq 124 ]; then
        log "  TIMEOUT after ${TIMEOUT_MIN} min - killing process tree"
        echo "$i" >> "$STATE_FILE"
    fi

    log "--- Iteration $i finished (exit=$code) ---"
    touch agr_logs/heartbeat

    # optional per-repo dashboard/analysis regeneration
    if [ -n "${AGR_DASH_CMD:-}" ]; then
        ( eval "$AGR_DASH_CMD" ) >/dev/null 2>&1 || true
    elif [ -f dashboard.py ]; then
        ( python3 dashboard.py ) >/dev/null 2>&1 || true
    fi

    if [ -f "results.tsv" ]; then
        log "Latest results.tsv rows:"
        tail -3 results.tsv | sed 's/^/  /'
    fi
    echo ""
    sleep 2
done

echo "========================================"
echo " AGR LOOP COMPLETE ($MAX_ITER iterations)"
echo "========================================"
