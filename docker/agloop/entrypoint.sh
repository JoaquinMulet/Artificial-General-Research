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
mkdir -p /root/.config/opencode
if [ -d /auth ] && [ -n "$(ls -A /auth 2>/dev/null)" ]; then
    cp -a /auth/. /root/.config/opencode/ 2>/dev/null || true
    # provider credentials store (opencode auth) lives under ~/.local/share
    if [ -f /auth/auth.json ]; then
        mkdir -p /root/.local/share/opencode
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

exec /opt/agr/loop.sh
