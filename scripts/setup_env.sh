#!/bin/bash
# AlpineNav cloud environment setup
# Runs as a SessionStart hook in Claude Code on the web.
# Installs Flutter, configures Mapbox tokens, and prepares the project.
#
# Required environment variables (set in Claude Code web UI):
#   MAPBOX_ACCESS_TOKEN   - public token (pk.xxx) for runtime map rendering
#   MAPBOX_DOWNLOADS_TOKEN - secret token (sk.xxx) with DOWNLOADS:READ scope
#
# On local machines this script exits immediately (local devs manage their own env).

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
  # Ensure PATH is persisted even if Flutter was pre-installed
  if [ -n "$CLAUDE_ENV_FILE" ]; then
    echo "PATH=$(dirname "$(which flutter)"):$PATH" >> "$CLAUDE_ENV_FILE"
  fi
fi

# ── 2. Configure Mapbox secret token for Gradle downloads ──────────────────
# The Mapbox Maps SDK for Android requires a secret token with DOWNLOADS:READ
# scope to download the SDK artifacts from Mapbox's Maven repository.
if [ -n "$MAPBOX_DOWNLOADS_TOKEN" ]; then
  echo "Configuring Mapbox downloads token in gradle.properties..."
  mkdir -p "$HOME/.gradle"
  # Remove any existing entry, then append
  if [ -f "$HOME/.gradle/gradle.properties" ]; then
    sed -i '/MAPBOX_DOWNLOADS_TOKEN/d' "$HOME/.gradle/gradle.properties"
  fi
  echo "MAPBOX_DOWNLOADS_TOKEN=$MAPBOX_DOWNLOADS_TOKEN" >> "$HOME/.gradle/gradle.properties"
else
  echo "WARNING: MAPBOX_DOWNLOADS_TOKEN not set. Mapbox SDK download will fail."
  echo "  Set it in your Claude Code environment variables."
fi

# ── 3. Configure Mapbox public access token for runtime ────────────────────
if [ -n "$MAPBOX_ACCESS_TOKEN" ]; then
  PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  TOKEN_DIR="$PROJ_DIR/android/app/src/main/res/values"

  # Only write the token file if android/ scaffold exists (created in step 4)
  # We'll write it after flutter create if needed
  export _ALPINENAV_WRITE_TOKEN="true"
else
  echo "WARNING: MAPBOX_ACCESS_TOKEN not set. Map will not render at runtime."
  echo "  Set it in your Claude Code environment variables."
  export _ALPINENAV_WRITE_TOKEN="false"
fi

# ── 4. Generate Android scaffold if missing ────────────────────────────────
PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJ_DIR"

if [ ! -d "android" ]; then
  echo "Generating Android scaffold with flutter create..."
  flutter create --org com.alpinenav --project-name alpinenav --platforms android .
  echo "Android scaffold created."
fi

# ── 5. Write Mapbox public token XML (after android/ exists) ───────────────
if [ "$_ALPINENAV_WRITE_TOKEN" = "true" ]; then
  TOKEN_DIR="$PROJ_DIR/android/app/src/main/res/values"
  mkdir -p "$TOKEN_DIR"
  cat > "$TOKEN_DIR/mapbox_access_token.xml" <<XMLEOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="mapbox_access_token" translatable="false">$MAPBOX_ACCESS_TOKEN</string>
</resources>
XMLEOF
  echo "Mapbox access token written to $TOKEN_DIR/mapbox_access_token.xml"
fi

# ── 6. Install dependencies ───────────────────────────────────────────────
echo "Running flutter pub get..."
flutter pub get

echo "=== Setup complete ==="
flutter doctor --verbose 2>&1 | tail -5
