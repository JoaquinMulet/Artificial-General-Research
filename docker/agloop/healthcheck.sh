#!/usr/bin/env bash
# healthcheck.sh - container health = fresh heartbeat.
# Exit 0 if the loop touched agr_logs/heartbeat within StallMinutes.
set -uo pipefail

HB=/work/agr_logs/heartbeat
STALL_MIN="${AGR_STALL_MINUTES:-25}"

if [ ! -f "$HB" ]; then exit 1; fi
age=$(( $(date +%s) - $(stat -c %Y "$HB") ))
if [ "$age" -gt $((STALL_MIN * 60)) ]; then
    echo "heartbeat stale: ${age}s > ${STALL_MIN}min" >&2
    exit 1
fi
exit 0
