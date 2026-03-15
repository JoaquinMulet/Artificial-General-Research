# AGR: Artificial General Research

> Autonomous iterative optimization for any measurable problem.
> Powered by [Claude Code](https://claude.com/claude-code).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-v2.1.72+-blue)](https://claude.com/claude-code)

**AGR** is a Claude Code skill that turns any measurable optimization problem into an autonomous research loop. Define a metric, a correctness check, and what code to modify — AGR handles the rest: experiment, measure, keep or discard, repeat forever.

You go to sleep. You wake up to a faster, smaller, better system.

## Inspired By

- **[Andrej Karpathy's autoresearch](https://github.com/karpathy/autoresearch)** — the original vision of autonomous AI research. 630 lines of Python, 100 experiments per night, compounding gains. Thank you Andrej for everything you do for open source and the AI community.
- **[Udit Goenka's autoresearch](https://github.com/uditgoenka/autoresearch)** — generalized autoresearch beyond ML, introduced Metric/Guard separation and rework patterns.

## What AGR Adds

AGR solves three problems the original implementations don't address:

### 1. Context Degradation → Fresh Context Per Iteration

Other implementations run in one long conversation. By experiment 50+, the context is compressed and the agent makes worse decisions.

AGR uses the **Ralph Loop pattern**: each iteration is a fresh Claude Code instance. The agent reads state from files, does ONE experiment, logs everything, and exits. Iteration 100 has the same reasoning quality as iteration 1.

### 2. Measurement Noise → Variance-Aware Acceptance

We discovered this the hard way: a dominant benchmark had ±1s variance, masking real 120ms improvements in smaller benchmarks. 4 experiments with real improvements were incorrectly discarded.

AGR implements **per-benchmark variance analysis**:
- Evaluates each sub-benchmark independently (not just total)
- Accepts if ANY benchmark improves >5% without others regressing
- Detects measurement artifacts (if ALL experiments show the same "improvement", it's noise)
- Outlier detection for anomalous baselines

### 3. Speed Without Correctness → Metric + Guard Separation

AGR separates **Metric** (what you optimize) from **Guard** (what must not break):
- If metric improves but guard fails → **rework** (fix implementation, 2 attempts)
- If metric improves and guard passes → **keep**
- Prevents discarding good optimization ideas that just have implementation bugs

## Real Results

Tested on a C++/Python spatial analysis library ([spatialize](https://github.com/alges/spatialize)):

```
Baseline:    53.54s
After AGR:   28.73s  (-46.3%)

14 experiments, 7 kept, 7 discarded, 0 crashes
```

![AGR Optimization Timeline](progress.png)

*Top: total benchmark time per experiment (green = kept, gray = discarded). Bottom: per-benchmark breakdown showing where improvements came from.*

Optimizations found autonomously:
| Optimization | Improvement | Type |
|---|---|---|
| `std::pow(x,2)` → `x*x` in distance() | -16.4% | Micro |
| Pre-computed coordinate diffs | -12.7% | Memory |
| Vectorized KDE, bypassed sklearn | -14.4% | Algorithmic |
| Parallelized estimate() tree loop | -9.8% | Parallelism |

The agent progressed from easy micro-optimizations to algorithmic changes. When micro-opts plateaued (5 consecutive discards), the strategy document guided it toward architectural improvements.

## Installation

```bash
# Clone into your Claude Code skills directory
git clone https://github.com/JoaquinMulet/Artificial-General-Research.git
cp -r Artificial-General-Research/skills/agr ~/.claude/skills/

# Or for project-specific installation
cp -r Artificial-General-Research/skills/agr .claude/skills/
```

## Usage

### Setup
```bash
# In Claude Code, run the setup wizard
/agr speed              # optimize for speed
/agr accuracy           # optimize for accuracy
/agr "bundle size"      # optimize bundle size
```

The wizard asks what to optimize, how to measure it, how to verify correctness, and what code to modify. Then generates all necessary files.

### Run
```bash
# Start 10 optimization iterations
bash run_agr.sh --max 10

# Or run one iteration manually
claude -p "$(cat program.md)" \
    --dangerously-skip-permissions \
    --max-turns 100 \
    --effort high
```

### Monitor
```bash
cat results.tsv          # experiment history
cat STRATEGY.md          # current plan + insights
open progress.png        # visual timeline
```

## How It Works

```
┌─────────────────────────────────────────────────────┐
│  AGR LOOP (each iteration = fresh Claude instance)  │
│                                                      │
│  1. Read state (results.tsv + STRATEGY.md)          │
│  2. Pick ONE optimization idea                       │
│  3. Implement change                                 │
│  4. Git commit (before running — clean rollback)     │
│  5. Run benchmark (Metric + Guard)                   │
│  6. Decide:                                          │
│     ├─ Guard FAIL + Metric up → REWORK (2 attempts) │
│     ├─ Guard PASS + Metric up → KEEP                │
│     ├─ Guard PASS + bench >5% → KEEP (noise-masked) │
│     ├─ Code simpler?         → KEEP (simplification)│
│     └─ None of above         → DISCARD + git reset  │
│  7. Log to results.tsv                               │
│  8. Update STRATEGY.md                               │
│  9. Exit → loop restarts fresh                       │
└─────────────────────────────────────────────────────┘
```

## Generated Files

| File | Purpose | Agent modifies? |
|---|---|---|
| `benchmark.py` | Metric measurement + Guard verification | **Never** |
| `baseline_checksums.json` | Guard ground truth | **Never** |
| `program.md` | Agent instructions per iteration | **Never** |
| `STRATEGY.md` | Persistent brain (ideas, history, insights) | **Yes** |
| `results.tsv` | Experiment log (append-only) | **Yes** |
| `analysis.py` | Generates progress.png | **Never** |
| `run_agr.sh` | Loop launcher | **Never** |
| `progress.png` | Optimization timeline chart | Auto-generated |

## Works For Any Measurable Problem

| Use Case | Metric | Guard |
|---|---|---|
| **Library speed** | Wall-clock time | Checksums match |
| **Bundle size** | KB after build | Tests pass |
| **ML accuracy** | F1 score | Min threshold met |
| **API latency** | p95 response time | Integration tests pass |
| **Lighthouse score** | Performance score | No visual regression |
| **Query optimization** | Execution time | Same result set |
| **Prompt engineering** | Eval score | Golden set matches |
| **Cloud costs** | $/month | Functionality tests pass |

## Claude Code Flags Reference

| Flag | Purpose |
|---|---|
| `-p` | Headless mode (fresh context each iteration) |
| `--dangerously-skip-permissions` | Full autonomy, no permission prompts |
| `--max-turns 100` | Safety limit (50 for simple, 100 for compiled) |
| `--effort high` | Deep reasoning for optimization decisions |
| `--max-budget-usd N` | Optional cost cap per iteration |
| `-w` / `--worktree` | Git worktree isolation for parallel experiments |

## Key Design Decisions

- **STRATEGY.md as persistent brain** — survives between sessions. Contains bottleneck analysis, prioritized ideas, exhausted approaches, and key insights.
- **Exhausted Approaches registry** — after N failures in a category (e.g., "compiler flags"), the category is marked as exhausted so future iterations don't retry.
- **Stuck detection** — after >5 consecutive discards: re-read all code, review patterns, try opposites, combine previous successes.
- **Simplicity criterion** (from Karpathy) — small improvement + complexity = discard. Simpler code + same results = keep.
- **Supervisor pattern** — parent agent or human audits discards for hidden per-benchmark improvements.

## Compatibility

Currently designed for **Claude Code** (Anthropic's CLI). The core architecture (externalized state, benchmark + verify, keep/discard logic) is agent-agnostic. Adapting to other AI coding agents (OpenCode, Cursor CLI, Aider) requires only changing the loop script and CLI flags.

## Contributing

PRs welcome! Areas of interest:
- Adapters for other AI coding agents
- Additional benchmark templates for new domains
- Variance analysis improvements
- Parallel experiment support via git worktrees

## License

MIT

## Credits

Built by [Joaquin Mulet](https://github.com/JoaquinMulet) with [Claude Code](https://claude.com/claude-code).

Standing on the shoulders of:
- [Andrej Karpathy](https://github.com/karpathy/autoresearch) — the original autoresearch vision
- [Udit Goenka](https://github.com/uditgoenka/autoresearch) — generalized autoresearch to non-ML tasks, Metric/Guard separation
- [Frank Bria](https://github.com/frankbria/ralph-claude-code) — the Ralph Loop pattern for Claude Code (fresh context per iteration via stop-hook re-invocation)
