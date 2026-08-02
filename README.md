# agr-docker

Containerized infrastructure for running **AGR campaigns** (Autonomous General
Research optimization loops) in Docker Compose. One deployment = one campaign.

This repository contains **only the infrastructure shell** - the campaign's
harness (`program.md`, `benchmark.py`, `STRATEGY.md`, agent definitions) lives
in each campaign repo and is mounted in at runtime. Nothing campaign-specific
is baked into the images.

```
agr-docker/
├── docker-compose.yml      # one campaign per deployment
├── .env.example            # copy to .env and edit
├── agloop/                 # the campaign: loop + iterate + opencode agent
│   ├── Dockerfile          # multi-stage: C++ toolchain + python + node/opencode
│   ├── entrypoint.sh       # git safe.directory + heartbeat + exec loop
│   ├── loop.sh             # iteration driver (timeout, resume, heartbeat)
│   ├── iterate.sh          # same-window ref measurement + agent launch
│   └── healthcheck.sh      # heartbeat freshness
├── agwatch/                # watchdog: heartbeat + docker restart (atomic)
│   └── watchdog.sh
└── agdash/                 # read-only dashboard (:8080) + JSON API
    └── server.py
```

## Why containers (vs the old process-scraping harness)

| Old approach (Windows process scraping) | This stack |
|---|---|
| Watchdog detected processes via WMI/CIM | Container identity: `docker restart agloop-<campaign>` is atomic and unique by name - duplicates are impossible by construction |
| `loop.pid` files drifted and the monitor killed the wrong loop | No pid files exist; the container IS the identity |
| Host services (AV, sync daemons, background tasks) thrashed measurement windows | Loop runs isolated in a container with pinned `cpus:`/`memory:` limits |
| A hung iteration left stale processes | Hard timeout per iteration + `docker restart` on stale heartbeat |
| Dashboard regenerated inside the loop (blocking) | Dashboard is a separate read-only container |

## Quick start

```bash
# 1. configure
cp .env.example .env
#    edit: AGR_CAMPAIGN, AGR_REPO_URL (or AGR_SEED_DIR), OPENCODE_CONFIG_DIR

# 2. build + start
docker compose up -d --build

# 3. watch
docker compose logs -f agloop-<CAMPAIGN>
open http://localhost:8080          # dashboard (auto-refresh)
curl localhost:8080/api/state        # same-window reference JSON
curl localhost:8080/api/results      # last 50 rows of results.tsv

# 4. stop / restart / destroy
docker compose stop
docker compose restart agloop-<CAMPAIGN>
docker compose down                  # volumes persist unless -v
```

**Try it in 5 minutes (no LLM):** the repository ships a ready-made synthetic
campaign under `examples/synthetic-campaign/` (benchmark, agent definition,
program.md, results header, STRATEGY.md). Point `AGR_SEED_DIR` at it, set
`AGR_DRY_RUN=1`, and `docker compose up -d` - the loop runs end to end and
auto-cleans on completion. Then swap in your real campaign.

> **Windows users (PowerShell):** the commands above are bash. PowerShell
> equivalents: `docker compose` works the same; for the manual cleanup use
> the docker CLI image form shown in the Cleanup section. `~` never expands
> in `.env` - always use absolute paths (e.g. `C:/Users/<you>/.config/opencode`).

## Adding a campaign

1. Set `AGR_CAMPAIGN` to a short name (e.g. `myapp`). Container names and
   volumes become `agloop-myapp`, `agldata-myapp`, ... - fully isolated.
   Volumes are prefixed with the project name (e.g. `agr-myapp_agldata`).
2. Seed the working copy: set `AGR_REPO_URL` (cloned on first start) or
   `AGR_SEED_DIR` (a local dir copied once into the volume). The volume is the
   campaign's workspace; the live repo on the host is never touched.
3. Make sure the campaign repo has the expected harness files:
   `program.md`, `benchmark.py` (or set `AGR_BENCH_CMD`), and an agent
   definition at `.opencode/agents/agr-optimizer.md`.
4. `docker compose up -d --build` (from this directory, or with
   `--project-directory`/`-f` if deploying several campaigns).

Run several campaigns concurrently with per-campaign overrides:

```bash
docker compose --env-file .env.myapp -p agr-myapp up -d
docker compose --env-file .env.other -p agr-other up -d
```

## Quiet windows and cross-campaign mutex

Two campaigns on the same machine share the thermal budget. Their
same-window reference (`ref_*` in `state.json`) absorbs measurement noise, but
two heavy campaigns measuring simultaneously corrupt each other's windows.

* **Quiet window** (`AGR_QUIET_WINDOW=HH:MM-HH:MM`): the loop only runs
  iterations (measurements) inside that window - e.g. schedule heavy
  campaigns at non-overlapping times. No coordinator needed.
* **File mutex** (`AGR_LOCK_FILE=/shared/agr.lock`): iterate.sh takes an
  exclusive lock (via `flock`, wait `AGR_LOCK_WAIT_S`) on the shared
  `agrshared` volume before measuring. Collision-free even with overlapping
  windows; default off.
* **Deterministic metrics** beat both: if the campaign's benchmark does not
  depend on wall-clock, contention only slows it down - it never corrupts it.

## Secrets

Agent auth is mounted at runtime, read-only:

```
OPENCODE_CONFIG_DIR=/absolute/path/to/opencode-config   # host dir (NO ~)
```

Mounted to `/root/.config/opencode:ro` in the container. Auth is never copied
into the image - the image builds without any secret, so the built image can
be pushed to any registry. `.env` is gitignored.

## Model variants (thinking levels)

`AGR_VARIANT` is OPTIONAL. The stack only passes `--variant` to `opencode`
when you set it - an unknown variant makes opencode silently fall back to the
agent's default, so only set values that your provider/model actually define.

How to discover which variants (thinking levels) a model supports - the same
catalog opencode uses:

```bash
# the opencode model catalog (single source used by the CLI)
curl https://models.dev/api.json | jq '.provider_id.models."model-name".variants'

# example: does deepseek-v4-flash have variants?
curl https://models.dev/api.json | jq '."opencode-go".models."deepseek-v4-flash".variants'
#   -> null (no thinking levels: do NOT set AGR_VARIANT)

# example: gemini flash classically ships low/high
curl https://models.dev/api.json | jq '."google".models."gemini-2.5-flash".variants'
#   -> {"low": ..., "high": ...}  -> set AGR_VARIANT=high if you want it
```

Rules of thumb:
- Variants are defined per provider/model (`provider.<id>.models.<m>.variants`
  in `opencode.json`) or in the models.dev catalog; built-ins differ per
  provider (Anthropic: `high`/`max`, OpenAI: `none`..`xhigh`, Google: `low`/`high`).
- In the TUI you cycle them with the `variant_cycle` keybind after picking a
  model in `/models`; `opencode models` lists models but not variants.
- If you are unsure, leave `AGR_VARIANT` empty - the agent runs with its
  default configuration.

DeepSeek special case (verified against api-docs.deepseek.com): the
`deepseek` provider has NO variants in the catalog (chat, reasoner,
v4-flash, v4-pro), so `--variant max` is silently ignored there - do not set
`AGR_VARIANT` for them. If you still want thinking levels on DeepSeek, use
its Anthropic-compatible endpoint (`https://api.deepseek.com/anthropic`) as
the provider `baseURL` in `opencode.json` - the `thinking` field is
supported there (`budget_tokens` is ignored, and unknown model names are
mapped to `deepseek-v4-flash`).

## Validation checklist (dry-run)

**Phase A - infrastructure (no LLM):**
1. `docker compose build` succeeds.
2. `AGR_DRY_RUN=1 docker compose up -d agloop-<CAMPAIGN>`: loop runs
   iterations end-to-end without an agent (synthetic row appended to
   `results.tsv`), heartbeat stays fresh.
3. Watchdog restart on STALE HEARTBEAT (this is the real watchdog path -
   `docker kill` is NOT a valid test: the loop's `restart: on-failure` would
   relaunch it on its own):
   ```bash
   docker exec agloop-<CAMPAIGN> sh -c 'touch -d "1 hour ago" /work/agr_logs/heartbeat'
   # within AGR_CHECK_INTERVAL_S (default 300s), agwatch-<CAMPAIGN> must log
   # "heartbeat stale ... - restarting agloop-<CAMPAIGN>" and the loop comes
   # back with a fresh heartbeat:
   docker compose logs agwatch-<CAMPAIGN>
   docker exec agloop-<CAMPAIGN> sh -c 'stat -c %Y /work/agr_logs/heartbeat'
   ```
4. Dashboard: `http://localhost:8080` serves a page; `/api/state`,
   `/api/results`, `/api/heartbeat` return data.
5. Auto-cleanup (if `AGR_AUTO_CLEANUP=1`): when the loop completes, the
   host is left clean - no containers, volumes, images or networks with the
   campaign's names remain.

**Phase B - one real iteration (agent):**
1. Seed the volume with a **copy** of the campaign repo (with `.git`).
2. With real auth mounted, let one full iteration run: agent edits code,
   runs its benchmark, guard PASS, and appends its row to `results.tsv`.
3. Confirm `state.json` `ref_valid: true` and that the agent compared against
   `ref_*` (no cross-window comparisons).

## Daily commands

```bash
docker compose ps                      # health of the 3 services
docker compose logs -f agloop-main     # follow the loop
docker compose logs agwatch-main       # watchdog decisions
docker compose exec agloop-main bash   # shell into the campaign
docker compose down && docker compose up -d   # full clean restart (state in volumes survives)
```

## Cleanup (leave the machine as you found it)

The stack cleans up after itself, two ways:

**Automatic on completion.** When the loop finishes all iterations
("AGR LOOP COMPLETE", container exits 0), the watchdog launches an ephemeral
cleaner container (`agclean-<campaign>`, `--rm`) that removes the campaign
containers, volumes, compose network and built images. With
`AGR_AUTO_CLEANUP=1` the Docker host is left exactly as it was before the
campaign started. The cleaner is a separate short-lived container because the
watchdog must also remove itself and its own image - impossible in-process.

**Manual.** `cleanup.sh` removes one or all campaigns on demand:

```bash
# Linux:
./cleanup.sh                    # remove ALL campaigns + images
./cleanup.sh synth              # remove ONE campaign
CLEANUP_PRUNE_SYSTEM=1 ./cleanup.sh   # also docker system prune -f

# Windows (no bash on the host needed):
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$(pwd)/cleanup.sh:/cleanup.sh:ro" docker:28-cli sh /cleanup.sh [campaign]
```

**Validation.** After a run (auto or manual), confirm the host is clean:

```bash
docker ps -a --format "{{.Names}}" | grep -E "agloop|agwatch|agdash|agclean"   # empty
docker volume ls --format "{{.Name}}" | grep "^agr-"                           # empty
docker images --format "{{.Repository}}:{{.Tag}}" | grep "^agr-"               # empty
docker network ls --format "{{.Name}}" | grep "agr-"                           # empty
```

Campaign results are never lost by cleanup: the agent commits each accepted
experiment to the campaign repo's git history, so the container volume is a
workspace, not the source of truth.

## Design notes

* **One loop per container.** Docker rejects a second container with the same
  name, so the duplicate-loop failure mode is structurally impossible.
* **Hard iteration timeout.** `timeout -k 60` kills the whole process tree;
  timed-out iterations are recorded in `agr_logs/completed.txt` so resume
  skips them.
* **Heartbeat = health.** The loop touches `agr_logs/heartbeat` each
  iteration; both docker's native healthcheck and `agwatch` use its age.
* **Same-window reference.** `iterate.sh` measures the current HEAD in the
  current window (`state.json`) before launching the agent; the agent is
  instructed to compare only against `ref_*`.
* **Toolchain.** The `agloop` image includes a full C++ build stage (GCC,
  CMake) for repos with native extensions (pybind11-style). Repos that are
  pure Python are unaffected. A campaign whose checksums are
  platform-specific must regenerate its baseline inside the container
  (`benchmark.py --save`) - see the campaign's own docs.
