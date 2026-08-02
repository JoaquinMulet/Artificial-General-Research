#!/usr/bin/env bash
# agloop entrypoint: single responsibility per container = ONE campaign loop.
# Docker guarantees name uniqueness (docker rejects a second 'agloop'), so a
# duplicate loop is impossible by construction - no pid files, no WMI, no CIM.
set -euo pipefail

# The bind-mounted repo is owned by the host user; git refuses to operate in
# it otherwise. /work is the single source of truth (repo + agr_logs).
git config --global --add safe.directory /work || true
git config --global user.name  "${AGR_GIT_NAME:-AGR Loop}"
git config --global user.email "${AGR_GIT_EMAIL:-agr-loop@local}"

# Agent auth: /auth is mounted read-only from the host. opencode needs to
# WRITE its own config dir, so seed a writable one from /auth on first start.
# Copy ONLY the essentials: top-level config files + agents/ + commands/.
# node_modules/ and skills/ are heavy (tens of MB, thousands of small files)
# and copy pathologically slow through the Docker Desktop bind mount.
mkdir -p /root/.config/opencode
if [ -d /auth ] && [ -n "$(ls -A /auth 2>/dev/null)" ]; then
    for f in /auth/*; do
        [ -f "$f" ] && cp -n "$f" /root/.config/opencode/ 2>/dev/null || true
    done
    for d in agents commands; do
        [ -d "/auth/$d" ] && cp -rn "/auth/$d" /root/.config/opencode/ 2>/dev/null || true
    done
    # provider credentials store (opencode auth) lives under ~/.local/share;
    # the host data dir is mounted at /authdata (OPENCODE_DATA_DIR)
    mkdir -p /root/.local/share/opencode
    if [ -f /authdata/auth.json ]; then
        cp -a /authdata/auth.json /root/.local/share/opencode/auth.json 2>/dev/null || true
    elif [ -f /auth/auth.json ]; then
        cp -a /auth/auth.json /root/.local/share/opencode/auth.json 2>/dev/null || true
    fi
else
    echo "WARNING: /auth is empty or missing - the agent will have no auth." >&2
    echo "Set OPENCODE_CONFIG_DIR to an absolute path with your opencode credentials." >&2
fi

# --- seed the campaign working copy on first start ---------------------
# /work is a named volume: empty on first run. Populate it either from a git
# URL (AGR_REPO_URL) or from the mounted /seed dir (AGR_SEED_DIR). On later
# starts the volume already has the repo and nothing is overwritten.
if [ ! -f /work/.git/HEAD ] && [ ! -f /work/program.md ]; then
    if [ -n "${AGR_REPO_URL:-}" ]; then
        echo "seeding /work from git: ${AGR_REPO_URL}"
        git clone --quiet "$AGR_REPO_URL" /work
    elif [ -d /seed ] && [ -n "$(ls -A /seed 2>/dev/null)" ]; then
        echo "seeding /work from /seed"
        cp -a /seed/. /work/
    else
        echo "WARNING: /work is empty and no seed available (AGR_REPO_URL unset, /seed empty)" >&2
    fi
fi

# ensure /work is a git repo (seeds may be plain directories, not clones):
# the loop/agent need HEAD for the reference and commits for the log.
if [ ! -d /work/.git ]; then
    echo "initializing git repo in /work"
    git -C /work init -q
    git -C /work add -A 2>/dev/null || true
    git -C /work -c user.name="${AGR_GIT_NAME:-AGR Loop}" \
        -c user.email="${AGR_GIT_EMAIL:-agr-loop@local}" \
        commit -qm "seed campaign (initial)" 2>/dev/null || true
fi

mkdir -p /work/agr_logs
touch /work/agr_logs/heartbeat

# Optional per-start build hook: repos with native extensions (e.g. pybind11
# C++ modules) need `pip install -e . --no-deps` + `setup.py build_ext
# --inplace` so the benchmark can import the package. Runs on EVERY start:
# `pip install -e` registers the package in this container's ephemeral
# site-packages (lost on container recreation), while build_ext --inplace is
# no-op when the .so is already built (setuptools timestamp check).
# Example: AGR_BUILD_CMD="python3 -m pip install -e . --no-deps -q && python3 setup.py build_ext --inplace"
if [ -n "${AGR_BUILD_CMD:-}" ]; then
    echo "running build hook: ${AGR_BUILD_CMD}"
    (cd /work && eval "${AGR_BUILD_CMD}") || { echo "BUILD HOOK FAILED" >&2; exit 1; }
fi

exec /opt/agr/loop.sh
