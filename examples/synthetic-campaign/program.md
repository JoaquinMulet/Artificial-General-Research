# AGR campaign instructions (one experiment per agent invocation).

## Your ONE task per invocation

1. Read `agr_logs/state.json` FIRST: it holds the SAME-WINDOW reference
   (`ref_*`). Compare ONLY against `ref_*` - never against historical rows
   from other windows.
2. Pick ONE optimization from the campaign backlog (see STRATEGY.md).
3. Implement it, run the benchmark, and verify correctness.
4. Append your result row to `results.tsv` (same columns as the header).
5. Update `STRATEGY.md` with what worked / what did not.
6. Reply with a one-line summary of what you tried and the outcome.

## Hard rules

- ONE experiment per invocation. Never modify benchmark.py, program.md,
  results.tsv headers, or any orchestration file.
- The benchmark command and the metric contract are owned by the stack:
  stdout must keep printing `key: float` lines.
- Do not compare across measurement windows.
