#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

mix_release() {
    echo "==> Building OTP release..."
    cd "$PROJECT_DIR"

    MIX_ENV=prod mix deps.get --only prod
    MIX_ENV=prod mix assets.deploy
    MIX_ENV=prod mix release desktop --overwrite

    echo "==> OTP release built."
    echo "Artifacts at: _build/prod/rel/desktop/"
}

dev() {
    echo "==> Starting in dev mode..."
    cd "$PROJECT_DIR"
    WORTH_DESKTOP=1 mix run --no-halt
}

case "${1:-build}" in
    release)  mix_release ;;
    build)    mix_release ;;
    dev)      dev ;;
    *)
        echo "Usage: $0 {release|build|dev}"
        echo ""
        echo "  release  - Build OTP release with desktop installer"
        echo "  build    - Same as release"
        echo "  dev      - Start elixir-desktop in dev mode"
        exit 1
        ;;
esac