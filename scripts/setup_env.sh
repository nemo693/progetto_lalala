#!/bin/bash
# AlpineNav cloud environment setup
# Runs as a SessionStart hook in Claude Code on the web.
# Installs Flutter and prepares the project for building.
#
# MapLibre + OpenFreeMap require no API keys or tokens.
# Mapbox tokens are only needed in Phase 5 (3D terrain).
#
# On local machines this script exits immediately.

set -e

# Only run in remote (cloud) environments
if [ "$CLAUDE_CODE_REMOTE" != "true" ]; then
  exit 0
fi

echo "=== AlpineNav environment setup ==="

# ── 1. Install Flutter SDK ──────────────────────────────────────────────────
if ! command -v flutter &> /dev/null; then
  echo "Installing Flutter SDK (stable)..."
  git clone --depth 1 https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
  # Persist PATH for subsequent commands in this session
  if [ -n "$CLAUDE_ENV_FILE" ]; then
    echo "PATH=$HOME/flutter/bin:$PATH" >> "$CLAUDE_ENV_FILE"
  fi
  # Accept licenses non-interactively
  yes | flutter doctor --android-licenses 2>/dev/null || true
  flutter precache --android
  echo "Flutter installed: $(flutter --version --machine | head -1)"
else
  echo "Flutter already available: $(flutter --version --machine | head -1)"
  if [ -n "$CLAUDE_ENV_FILE" ]; then
    echo "PATH=$(dirname "$(which flutter)"):$PATH" >> "$CLAUDE_ENV_FILE"
  fi
fi

# ── 2. Generate Android scaffold if missing ────────────────────────────────
PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJ_DIR"

if [ ! -d "android" ]; then
  echo "Generating Android scaffold with flutter create..."
  flutter create --org com.alpinenav --project-name alpinenav --platforms android .
  echo "Android scaffold created."
fi

# ── 3. Install dependencies ───────────────────────────────────────────────
echo "Running flutter pub get..."
flutter pub get

echo "=== Setup complete ==="
flutter doctor --verbose 2>&1 | tail -5
