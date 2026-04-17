#!/bin/sh
set -e

# Mirror the GitHub Actions desktop-release workflow for local testing.
# Usage:
#   ./build.sh          — build only
#   ./build.sh run      — build and run the Tauri binary

export MIX_ENV=prod

# Detect OS for platform-specific release directory name
case "$(uname -s)" in
  Linux*)  os="linux" ;;
  Darwin*) os="darwin" ;;
  MINGW*|MSYS*|CYGWIN*) os="windows" ;;
  *) echo "Unsupported OS"; exit 1 ;;
esac

release_dir="rel/desktop/src-tauri/rel-${os}"

echo "==> Building OTP release (${os})..."
mix deps.get --only prod
mix assets.deploy
mix compile --force
mix release desktop --overwrite --path "${release_dir}"

# Some NIFs (e.g. EXLA) ship read-only .so files. Tauri copies resources
# preserving permissions, so a second build can't overwrite them. Fix this
# by ensuring all files in the release are owner-writable.
find "${release_dir}" -type f ! -perm -u+w -exec chmod u+w {} +

echo "==> Preparing Tauri frontend dist..."
mkdir -p rel/desktop/src-tauri/dist
cp rel/desktop/src-tauri/dist_splash.html rel/desktop/src-tauri/dist/index.html

echo "==> Building Tauri app..."
cd rel/desktop/src-tauri
cargo tauri build --config "{\"bundle\":{\"resources\":{\"rel-${os}\":\"rel\"}}}"
cd -

echo "==> Build complete."
echo "Artifacts at: rel/desktop/src-tauri/target/release/bundle/"

if [ "$1" = "run" ]; then
  echo "==> Starting Worth desktop..."
  rel/desktop/src-tauri/target/release/worth-desktop
fi
