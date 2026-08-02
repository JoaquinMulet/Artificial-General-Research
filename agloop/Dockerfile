# agloop: the AGR campaign container (loop + iterate + opencode agent).
#
# Multi-stage:
#   stage build  -> full C++ toolchain (GCC, CMake, Eigen deps) for repos with
#                   native extensions (pybind11-style C++ modules).
#   stage runtime -> slim runtime: python + node (opencode CLI) + scripts.
#
# The repo under campaign is bind-mounted at /work. Nothing is copied from it
# into the image: the image is a generic AGR runtime, the volume is the repo.

# ---------- stage: build ----------
FROM python:3.13-slim AS build

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        g++ gcc make cmake git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ---------- stage: runtime ----------
FROM build AS runtime

# node 20 LTS + opencode CLI (the agent runs inside this container)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g opencode-ai

# campaign python deps (superset of requirements.txt; the repo's own deps are
# installed at image build time by the agent via the repo tooling)
RUN pip install --no-cache-dir \
        numpy pandas scikit-learn scipy rich tqdm matplotlib opencv-python-headless \
        setuptools numba pybind11[global]

ENV PATH="/opt/agr:${PATH}" \
    OPENCODE_DISABLE_AUTOUPDATE=1 \
    PYTHONUNBUFFERED=1

COPY loop.sh iterate.sh healthcheck.sh entrypoint.sh /opt/agr/
RUN chmod +x /opt/agr/*.sh

WORKDIR /work
ENTRYPOINT ["/opt/agr/entrypoint.sh"]
