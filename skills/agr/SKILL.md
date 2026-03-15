---
name: agr
description: "AGR: Artificial General Research — autonomous iterative optimization framework for Claude Code. Generalizes Karpathy's autoresearch to any measurable problem with variance-aware acceptance, correctness verification, and fresh-context-per-iteration (Ralph Loop). Use when setting up autoresearch, creating optimization loops, or autonomous research. Triggers on: autoresearch, AGR, auto research, optimization loop, auto optimize, artificial general research."
argument-hint: [metric-to-optimize]
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# AGR: Artificial General Research

> Autonomous iterative optimization for any measurable problem.
> Powered by **Claude Code**. Inspired by [Karpathy's autoresearch](https://github.com/karpathy/autoresearch).
>
> Thank you Andrej Karpathy for everything you do for open source and the AI community.
> Your autoresearch showed that AI agents can run experiments overnight and wake up to
> a better system. AGR generalizes that vision beyond ML to any domain.
>
> Also inspired by [uditgoenka/autoresearch](https://github.com/uditgoenka/autoresearch)
> for the Guard/Metric separation and rework-on-failure patterns.
>
> **Requires**: [Claude Code](https://claude.com/claude-code) v2.1.72+ (`claude` CLI in PATH)

## What Is AGR?

AGR uses Claude Code's headless mode (`claude -p`) to run an autonomous optimization loop.
Each iteration is a **fresh Claude Code instance** (no context degradation) that:

1. Reads state from files (what's been tried, what worked, what's next)
2. Picks ONE experiment to try
3. Implements the change
4. Measures **Metric** (the number to optimize) + checks **Guard** (must not break)
5. Keeps if improved, reworks if guard failed, discards if no improvement
6. Logs everything, updates strategy document
7. Dies — next iteration starts with fresh context

**Works for any problem where you can**: measure a number + verify correctness + modify code.

## Quick Start

```bash
/agr speed                    # set up speed optimization
/agr accuracy                 # set up accuracy optimization
/agr "bundle size"            # set up bundle size optimization
```

## What Makes AGR Different

### vs Karpathy's autoresearch
| Feature | Karpathy | AGR |
|---|---|---|
| Domain | ML training only | **Any measurable problem** |
| Context | One long session (degrades) | **Fresh per iteration** (Ralph Loop) |
| Correctness | Not verified | **Checksums + guard command** |
| Variance handling | Not addressed | **Per-benchmark variance analysis** |
| Failed ideas | Not tracked | **Exhausted Approaches registry** |

### vs uditgoenka/autoresearch
| Feature | Udit | AGR |
|---|---|---|
| Variance analysis | Not explicit | **Per-benchmark with artifact detection** |
| Context management | Long session | **Fresh per iteration** (Ralph Loop) |
| Progress visualization | Not included | **progress.png with breakdown chart** |
| Supervisor pattern | Not included | **Audit discards, adjust strategy between batches** |
| Templates | Pure instructions | **Generates benchmark.py, analysis.py, etc.** |

### Unique to AGR
- **Variance-aware acceptance**: measurement noise in dominant benchmarks can mask real improvements. AGR checks each sub-benchmark independently and accepts if ANY improves >5% without others regressing.
- **Artifact detection**: if ALL experiments show the same "improvement", it's system noise, not optimization.
- **Supervisor pattern**: a parent agent or human monitors results.tsv, audits discards for hidden improvements, and adjusts strategy between batches.
- **Multi-benchmark visualization**: progress.png shows total metric + per-component breakdown.

## Setup Wizard

When invoked, follow these steps:

### Step 1: Understand the Project
Ask the user:
1. **What to optimize?** (speed, accuracy, size, cost, latency, score...)
2. **How to measure it?** (Metric — must output a parseable number)
3. **How to verify correctness?** (Guard — tests, checksums, golden outputs)
4. **What can the agent modify?** (files, directories)
5. **What MUST NOT change?** (benchmark, tests, data)
6. **Build step needed?** (compile, bundle, deploy)
7. **Runtime path?** (especially on Windows with multiple Pythons)

### Step 2: Generate Files
See [references/templates.md](references/templates.md) for complete templates.
```
{project}/
├── benchmark.py              ← Metric + Guard verification
├── baseline_checksums.json   ← Guard ground truth
├── program.md                ← Agent instructions (one iteration)
├── STRATEGY.md               ← Persistent brain
├── results.tsv               ← Experiment log (append-only)
├── analysis.py               ← Generates progress.png
├── run_agr.sh                ← Loop launcher (bash)
└── run_agr.ps1               ← Loop launcher (PowerShell)
```

### Step 3: Baseline
1. Run `benchmark.py --save` to establish baseline + save checksums
2. Record baseline in `results.tsv`
3. **Mandatory dry-run validation**: confirm benchmark produces parseable number
4. Generate initial `progress.png`

### Step 4: Launch
```bash
bash run_agr.sh --max 3   # start with 3 to validate
```

## Core Principles

### From Karpathy
- **Single metric** — one number, lower (or higher) is better
- **Fixed benchmark** — NEVER modified by the agent
- **Git keep/discard** — commit before running, reset if no improvement
- **Log everything** — failures prevent re-trying bad ideas
- **Never stop** — runs until human interrupts
- **Simplicity criterion** — complexity needs proportional improvement

### From AGR
- **Fresh context per iteration** (Ralph Loop) — no quality degradation
- **Metric + Guard separation** — optimize speed without breaking tests
- **Rework before discard** — if guard fails but metric improved, fix implementation (2 attempts)
- **Variance-aware acceptance** — per-benchmark analysis beats total-only
- **Stuck detection** (>5 discards) — re-read everything, try opposites, combine successes
- **Persistent strategy** — STRATEGY.md with exhausted approaches registry
- **Supervisor audit** — review discards for hidden improvements

## Decision Logic

```
1. GUARD FAILED + Metric improved?   → REWORK (max 2 attempts)
2. GUARD FAILED + Metric didn't?     → DISCARD
3. GUARD PASSED + Metric improved?   → KEEP
4. GUARD PASSED + benchmark >5% up?  → KEEP (noise-masked improvement)
5. GUARD PASSED + code simpler?      → KEEP (simplification win)
6. None of above?                    → DISCARD
7. Build crashed?                    → Fix (3 attempts) or CRASH
8. Benchmark timeout?                → CRASH
```

## Claude Code Flags

```bash
claude -p "$(cat program.md)" \
    --dangerously-skip-permissions \
    --max-turns 100 \
    --effort high
```

| Flag | Purpose | Recommendation |
|---|---|---|
| `-p` | Headless mode (fresh context) | Always use |
| `--dangerously-skip-permissions` | Full autonomy | Required |
| `--max-turns 100` | Safety limit | 50 simple / 100 compiled |
| `--effort high` | Deep reasoning | Use for optimization |
| `--max-budget-usd N` | Cost cap | Optional |
| `-w` / `--worktree` | Parallel experiments | Advanced |

See [references/guide.md](references/guide.md) for complete documentation.

## Compatibility

Designed for **Claude Code** (Anthropic CLI). Expanding to other AI coding agents
(OpenCode, Cursor CLI, Aider) is pending — the core architecture is agent-agnostic,
only loop scripts and CLI flags need adaptation.

## Credits

- [Andrej Karpathy](https://github.com/karpathy/autoresearch) — original autoresearch vision
- [Udit Goenka](https://github.com/uditgoenka/autoresearch) — Guard/Metric separation, rework patterns
- [Frank Bria](https://github.com/frankbria/ralph-claude-code) — Ralph Loop pattern (fresh context per iteration)
- Built with [Claude Code](https://claude.com/claude-code) by Anthropic
