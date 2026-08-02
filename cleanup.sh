#!/bin/sh
# cleanup.sh - manual cleanup for AGR campaigns (host side).
#
# Removes everything this stack created: containers, campaign volumes,
# compose network, built images, and optionally docker system cache.
#
# POSIX sh (no bash) so it runs anywhere: directly on Linux, or on Windows
# via the docker CLI image:
#   docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
#     -v "$(pwd)/cleanup.sh:/cleanup.sh:ro" docker:28-cli sh /cleanup.sh [campaign]
#
# Usage:
#   ./cleanup.sh                     # remove ALL agr campaigns
#   ./cleanup.sh synth               # remove ONE campaign
#   CLEANUP_PRUNE_SYSTEM=1 ./cleanup.sh   # also docker system prune -f
set -u

PRUNE_SYSTEM="${CLEANUP_PRUNE_SYSTEM:-0}"

# campaigns: explicit args, or derive from existing agloop-* containers
if [ "$#" -gt 0 ]; then
    CAMPAIGNS="$*"
else
    CAMPAIGNS=$(docker ps -a --filter "name=agloop-" --format "{{.Names}}" \
        | sed 's/^agloop-//' | sort -u)
    [ -z "$CAMPAIGNS" ] && CAMPAIGNS="main"
fi

for C in $CAMPAIGNS; do
    echo "== cleaning campaign: $C =="
    for c in agloop agdash agwatch agclean; do
        docker rm -f "${c}-${C}" >/dev/null 2>&1 && echo "  removed container ${c}-${C}" || true
    done
    for v in "agr-${C}_agldata" "agr-${C}_agrshared" "agr-${C}_seed-empty"; do
        docker volume rm "$v" >/dev/null 2>&1 && echo "  removed volume $v" || true
    done
    docker network rm "agr-${C}_default" >/dev/null 2>&1 && echo "  removed network agr-${C}_default" || true
done

# images are shared across campaigns - remove once
docker image rm agr-agloop agr-agwatch agr-agdash >/dev/null 2>&1 \
    && echo "removed built images (agr-agloop, agr-agwatch, agr-agdash)" || true

if [ "$PRUNE_SYSTEM" = "1" ]; then
    echo "== docker system prune -f =="
    docker system prune -f
fi

echo "cleanup done"
