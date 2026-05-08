#!/bin/sh
set -e

# Build an elixir-desktop release with installer.
# Usage:
#   ./build.sh          — build installer for current platform
#   ./build.sh release  — build OTP release only (no installer)

export MIX_ENV=prod

echo "==> Installing deps..."
mix deps.get --only prod

echo "==> Building assets..."
mix assets.deploy

echo "==> Compiling..."
mix compile --force

if [ "${1}" = "release" ]; then
  echo "==> Building OTP release only..."
  mix release desktop --overwrite
else
  echo "==> Building OTP release with installer..."
  mix release desktop --overwrite
fi

echo "==> Build complete."

if [ "${1}" = "run" ]; then
  echo "==> Starting Worth..."
  WORTH_DESKTOP=1 _build/prod/rel/worth/bin/desktop start
fi