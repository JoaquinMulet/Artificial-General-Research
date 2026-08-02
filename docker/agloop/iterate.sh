#!/usr/bin/env bash
# iterate.sh - ONE AGR iteration (port of iterate.ps1 to bash).
#
# 1. Acquire optional cross-campaign mutex (agr-shared volume).
# 2. Measure SAME-WINDOW reference (HEAD + clock + fresh benchmark) into
#    agr_logs/state.json - the agent compares ONLY against ref_*, never
#    against historical windows (the campaign's biggest bias).
# 3. Launch a FRESH opencode agent (one experiment, then dies).
#
# No `set -e` on purpose: like the PS1 ErrorActionPreference=Continue fix, a
# failing native command must NOT silently abort the reference measurement.
# We validate state.json explicitly, retry once, and never launch a blind
# agent without a valid reference.
set -uo pipefail

cd /work || exit 2
WORK=/work
mkdir -p agr_logs

PY="${AGR_PYTHON:-python3}"
MODEL="${AGR_MODEL:-your-model-provider/model}"
VARIANT="${AGR_VARIANT:-}"
BENCH_CMD="${AGR_BENCH_CMD:-python3 benchmark.py}"
PROMPT_FILE="${AGR_PROMPT_FILE:-program.md}"
AGENT_NAME="${AGR_AGENT:-agr-optimizer}"
RESULTS_FILE="${AGR_RESULTS_FILE:-results.tsv}"
LOCK_WAIT_S="${AGR_LOCK_WAIT_S:-600}"

# ---- optional cross-campaign mutex (file lock on shared volume) ----------
if [ -n "${AGR_LOCK_FILE:-}" ]; then
    exec 9>"$AGR_LOCK_FILE"
    if ! flock -w "$LOCK_WAIT_S" 9; then
        echo "LOCK TIMEOUT: could not acquire $AGR_LOCK_FILE within ${LOCK_WAIT_S}s" >&2
        exit 3
    fi
    trap 'flock -u 9' EXIT
fi

# ---- same-window reference measurement --------------------------------
clock_mhz=""
max_clock_mhz=""
regime="unknown"
if [ -r /proc/cpuinfo ]; then
    clock_mhz="$(awk -F: '/^cpu MHz/ {print $2; exit}' /proc/cpuinfo | tr -d ' ')"
fi
# allow the host to pin the max clock via env when /proc is not informative
max_clock_mhz="${AGR_MAX_CLOCK_MHZ:-$clock_mhz}"
if [ -n "$clock_mhz" ] && [ -n "$max_clock_mhz" ] && [ "$max_clock_mhz" -gt 0 ] 2>/dev/null; then
    if awk "BEGIN{exit !($clock_mhz >= $max_clock_mhz * 0.9)}" 2>/dev/null; then
        regime="full"
    elif awk "BEGIN{exit !($clock_mhz >= $max_clock_mhz * 0.5)}" 2>/dev/null; then
        regime="throttled"
    else
        regime="collapse"
    fi
fi

head_short="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
ref_out="agr_logs/ref_out.log"
ref_err="agr_logs/ref_stderr.log"

measure() {
    ( eval "$BENCH_CMD" ) >"$ref_out" 2>"$ref_err"
}

measure
# retry only if the run produced NO parseable metric at all (any "key: value"
# line), regardless of which key the campaign uses - this avoids a phantom
# double run for benchmarks that do not print total_time_s.
if ! grep -qE '^[A-Za-z_][A-Za-z0-9_]*:\s+[0-9.]+' "$ref_out" 2>/dev/null; then
    echo "REF MEASUREMENT FAILED (1st attempt) - retrying in 5s" >&2
    sleep 5
    measure
fi

# ---- parse benchmark output into state.json --------------------------
# Generic: ANY "key: float" line becomes ref_<key>. The campaign's primary
# metric is AGR_METRIC_KEY (default total_time_s); ref_valid = at least one
# metric was parsed (so benchmarks that report e.g. metric_throughput_bps
# instead of total_time_s still produce a valid reference).
python3 - "$head_short" "$clock_mhz" "$max_clock_mhz" "$regime" "${AGR_METRIC_KEY:-total_time_s}" <<'PYEOF'
import json, os, re, sys

head, clock, maxclock, regime, metric_key = sys.argv[1:6]
vals = {"head": head, "clock_mhz": (float(clock) if clock else 0),
        "max_clock_mhz": (float(maxclock) if maxclock else 0), "regime": regime}
path = os.path.join("/work", "agr_logs", "ref_out.log")
try:
    with open(path) as f:
        for line in f:
            m = re.match(r"^(\w[\w]*):\s+([\d.]+)\s*$", line)
            if m and m.group(1) != "correctness":
                vals["ref_" + m.group(1)] = float(m.group(2))
except FileNotFoundError:
    pass
# primary metric: AGR_METRIC_KEY or the first parsed metric
if "ref_" + metric_key in vals:
    vals["ref_total"] = vals["ref_" + metric_key]
else:
    first = next((k for k in vals if k.startswith("ref_") and k not in
                  ("ref_head", "ref_clock_mhz", "ref_max_clock_mhz",
                   "ref_regime")), None)
    if first:
        vals["ref_total"] = vals[first]
vals["ref_valid"] = "ref_total" in vals
with open(os.path.join("/work", "agr_logs", "state.json"), "w") as f:
    json.dump(vals, f, separators=(",", ":"))
PYEOF

ref_valid="$(python3 -c 'import json;print(json.load(open("/work/agr_logs/state.json"))["ref_valid"])' 2>/dev/null)"
if [ "$ref_valid" != "True" ]; then
    echo "REF MEASUREMENT FAILED - not launching a blind agent (see agr_logs/ref_stderr.log)" >&2
    exit 2
fi

# ---- launch the agent -------------------------------------------------
MSG="Read the file ${PROMPT_FILE} in this directory COMPLETELY (paginate if truncated) and execute ALL the instructions it contains for this ONE experiment iteration. Read agr_logs/state.json FIRST - it contains your SAME-WINDOW reference measurement (HEAD, clock, regime, ref_* times) - you must compare your measurements against ref_*, never against historical records. Work autonomously until done. Reply with a one-line summary of what you tried and the outcome."

# dry-run mode: validate the pipeline without an LLM (Phase A).
# Appends a synthetic row that matches the campaign's OWN results header
# (same column count) so it never corrupts a campaign-specific format. If the
# repo has no results file, the dry-run is still logged to stderr only.
if [ "${AGR_DRY_RUN:-0}" = "1" ]; then
    echo "DRY-RUN: agent launch skipped (AGR_DRY_RUN=1)"
    if [ -f "/work/$RESULTS_FILE" ]; then
        # header = first non-comment line (results files may start with '#')
        header_line=$(grep -v '^#' "/work/$RESULTS_FILE" | head -1)
        ncols=$(printf '%s' "$header_line" | awk -F'\t' '{print NF}')
        ncols=${ncols:-1}
        row="dryrun"
        i=1
        while [ "$i" -lt "$ncols" ]; do
            row="${row}$( [ "$i" -eq 1 ] && printf '\t%s' '0.001' || printf '\t%s' 'dry-run' )"
            i=$((i + 1))
        done
        printf '%s\n' "$row" >> "/work/$RESULTS_FILE"
    fi
    exit 0
fi

if [ -n "${VARIANT}" ]; then
    opencode run "$MSG" --agent "$AGENT_NAME" --model "$MODEL" --variant "$VARIANT" --auto 2>&1
else
    opencode run "$MSG" --agent "$AGENT_NAME" --model "$MODEL" --auto 2>&1
fi
exit $?
