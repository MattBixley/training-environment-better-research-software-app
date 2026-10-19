#!/usr/bin/env bash
#
# Run the training session on your own machine, without deploying anything.
#
# This starts the same container image the cluster runs and prints a URL to
# open. What it does not reproduce is the Open OnDemand wrapper around it: no
# password, no k8s, no NFS home directories, no LDAP. Everything a learner
# actually does inside the session - git, venv, pip, pytest, mkdocs - behaves
# identically. The home directory is thrown away when the container stops.
#
# Usage:
#   ./run-local.sh              # run the released image for this checkout
#   ./run-local.sh --build      # build from this checkout first
#   ./run-local.sh --shell      # drop to a terminal instead
#
set -euo pipefail

REGISTRY_IMAGE="ghcr.io/mattbixley/training-environment-better-research-software-app"

# Derive the tag from this checkout rather than hardcoding one. A pinned
# default goes stale the moment a release is cut, and then this script quietly
# runs an old image while claiming to be the current app. Falls back to
# :latest outside a git checkout.
default_image() {
    local tag
    tag=$(git -C "$(dirname "${BASH_SOURCE[0]}")" describe --tags --abbrev=0 2>/dev/null || true)
    echo "${REGISTRY_IMAGE}:${tag:-latest}"
}

IMAGE="$(default_image)"
PORT=8443
CPUS="2"
MEMORY="4g"
BUILD=0
SHELL_ONLY=0

# \s is a GNU extension that BSD sed (macOS) does not understand, so spell the
# optional space out longhand.
usage() { sed -n '2,15p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --image)   IMAGE="$2"; shift 2 ;;
        --port)    PORT="$2"; shift 2 ;;
        --cpus)    CPUS="$2"; shift 2 ;;
        --memory)  MEMORY="$2"; shift 2 ;;
        --build)   BUILD=1; shift ;;
        --shell)   SHELL_ONLY=1; shift ;;
        -h|--help) usage ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [[ "$BUILD" == "1" ]]; then
    echo "Building from this checkout..."
    IMAGE="brs-app:local"
    docker build -t "$IMAGE" "$(dirname "$0")/docker"
fi

# The cluster runs amd64, so an image we have to pull should be the amd64 one
# even on an Apple Silicon Mac - it runs under emulation, slowly but correctly.
# An image already present locally is used as-is, whatever it was built for;
# forcing a platform on it would trigger a pointless pull.
PLATFORM=()
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    if [[ "$(uname -m)" == "arm64" || "$(uname -m)" == "aarch64" ]]; then
        PLATFORM=(--platform linux/amd64)
        echo "Note: pulling the amd64 image; it runs under emulation and is slow"
        echo "      to start. Use --build for a native image if you are iterating."
    fi
fi

# -i needs a terminal on stdin. Without this the script cannot be run from a
# pipe, a CI job or the background, which is exactly how you would smoke-test it.
TTY=(-t)
[[ -t 0 ]] && TTY=(-it)

# The image has no user of its own (training users come from LDAP), so run as
# an arbitrary uid with a writable home, the way a learner's session does.
# macOS still ships bash 3.2, where expanding an empty array under `set -u` is
# an "unbound variable" error. The ${a[@]+"${a[@]}"} form expands to nothing
# when the array is empty instead of failing.
COMMON=(
    --rm
    "${TTY[@]}"
    ${PLATFORM[@]+"${PLATFORM[@]}"}
    --cpus "$CPUS"
    --memory "$MEMORY"
    --user 1000:1000
    -e HOME=/tmp/learner
    -e TERM=xterm-256color
)

# Mirror what template/script.sh.erb does on the cluster, so the session you
# see locally has the same contents as the deployed one.
STAGE='
    mkdir -p "${HOME}/.local/share/code-server/User"
    [[ -e "${HOME}/spacewalks" ]] || cp -a /opt/spacewalks "${HOME}/spacewalks"
    rsync --ignore-existing -a /opt/code-server/extensions/ "${HOME}/.local/share/code-server/extensions/"
    cp -n /opt/code-server/settings.json "${HOME}/.local/share/code-server/User/settings.json" || true
    cd "${HOME}"
'

if [[ "$SHELL_ONLY" == "1" ]]; then
    exec docker run "${COMMON[@]}" "$IMAGE" bash -lc "set -e; ${STAGE} exec bash -l"
fi

cat <<BANNER

  Starting the Better Research Software session locally.

    Resources    : $CPUS CPUs, $MEMORY RAM
    Image        : $IMAGE

  VS Code will be at:     http://localhost:${PORT}/
  Press Ctrl-C to stop.

BANNER

exec docker run "${COMMON[@]}" -p "${PORT}:8443" "$IMAGE" bash -lc "
    set -e
    ${STAGE}
    exec code-server --auth none --bind-addr 0.0.0.0:8443 --disable-telemetry \
        --extensions-dir \"\${HOME}/.local/share/code-server/extensions\" \"\${HOME}/spacewalks\"
"
