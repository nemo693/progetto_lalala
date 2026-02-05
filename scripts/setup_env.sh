#!/bin/bash
# AlpineNav cloud environment setup
# Runs as a SessionStart hook in Claude Code on the web.
# Installs Flutter, Android SDK, and prepares the project for building.
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
  flutter precache --android
  echo "Flutter installed: $(flutter --version --machine | head -1)"
else
  echo "Flutter already available: $(flutter --version --machine | head -1)"
  if [ -n "$CLAUDE_ENV_FILE" ]; then
    echo "PATH=$(dirname "$(which flutter)"):$PATH" >> "$CLAUDE_ENV_FILE"
  fi
fi

# ── 2. Install Android SDK ─────────────────────────────────────────────────
ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_HOME

if [ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
  echo "Installing Android SDK command-line tools..."
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  curl -fsSL -o /tmp/cmdline-tools.zip \
    "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -f /tmp/cmdline-tools.zip
  echo "Android cmdline-tools installed."
fi

if [ ! -d "$ANDROID_HOME/platform-tools" ]; then
  echo "Installing Android platform-tools..."
  curl -fsSL -o /tmp/platform-tools.zip \
    "https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
  unzip -q /tmp/platform-tools.zip -d "$ANDROID_HOME"
  rm -f /tmp/platform-tools.zip
  echo "platform-tools installed."
fi

if [ ! -d "$ANDROID_HOME/platforms/android-36" ]; then
  echo "Installing Android platform 36..."
  curl -fsSL -o /tmp/platform-36.zip \
    "https://dl.google.com/android/repository/platform-36_r02.zip"
  unzip -q /tmp/platform-36.zip -d /tmp/platform-36-extract
  # The zip may contain android-16 or android-36 as the top-level dir
  mv /tmp/platform-36-extract/android-* "$ANDROID_HOME/platforms/android-36" 2>/dev/null || true
  rm -rf /tmp/platform-36.zip /tmp/platform-36-extract
  echo "Android platform 36 installed."
fi

if [ ! -d "$ANDROID_HOME/build-tools/34.0.0" ]; then
  echo "Installing Android build-tools 34.0.0..."
  curl -fsSL -o /tmp/build-tools.zip \
    "https://dl.google.com/android/repository/build-tools_r34-linux.zip"
  unzip -q /tmp/build-tools.zip -d /tmp/build-tools-extract
  mkdir -p "$ANDROID_HOME/build-tools/34.0.0"
  cp -r /tmp/build-tools-extract/android-*/* "$ANDROID_HOME/build-tools/34.0.0/"
  rm -rf /tmp/build-tools.zip /tmp/build-tools-extract
  echo "build-tools 34.0.0 installed."
fi

# Accept licenses
mkdir -p "$ANDROID_HOME/licenses"
echo -e "\n24333f8a63b6825ea9c5514f83c2829b004d1fee" > "$ANDROID_HOME/licenses/android-sdk-license"
echo -e "\n84831b9409646a918e30573bab4c9c91346d8abd" > "$ANDROID_HOME/licenses/android-sdk-preview-license"

# Configure Flutter to use this SDK
flutter config --android-sdk "$ANDROID_HOME" 2>/dev/null || true

# Persist ANDROID_HOME for subsequent commands
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "ANDROID_HOME=$ANDROID_HOME" >> "$CLAUDE_ENV_FILE"
fi

echo "Android SDK configured at $ANDROID_HOME"

# ── 3. Set up Gradle proxy for cloud environments ──────────────────────────
# In cloud environments, Java/Gradle cannot use the authenticated HTTP proxy
# directly. We start a local forwarding proxy and configure Gradle to use it.
if [ -n "$HTTP_PROXY" ]; then
  GRADLE_DIR="$HOME/.gradle"
  mkdir -p "$GRADLE_DIR"

  # Download Gradle distribution manually (curl works with the proxy)
  GRADLE_DIST_URL="https://services.gradle.org/distributions/gradle-8.14-all.zip"
  GRADLE_HASH=$(python3 -c "import hashlib; print(hashlib.md5(b'$GRADLE_DIST_URL').hexdigest())")
  GRADLE_CACHE_DIR="$GRADLE_DIR/wrapper/dists/gradle-8.14-all/$GRADLE_HASH"

  if [ ! -f "$GRADLE_CACHE_DIR/gradle-8.14-all.zip.ok" ]; then
    echo "Pre-caching Gradle 8.14 distribution..."
    mkdir -p "$GRADLE_CACHE_DIR"
    curl -fsSL "$GRADLE_DIST_URL" -o "$GRADLE_CACHE_DIR/gradle-8.14-all.zip"
    unzip -q "$GRADLE_CACHE_DIR/gradle-8.14-all.zip" -d "$GRADLE_CACHE_DIR"
    touch "$GRADLE_CACHE_DIR/gradle-8.14-all.zip.ok"
    touch "$GRADLE_CACHE_DIR/gradle-8.14-all.zip.lck"
    echo "Gradle 8.14 cached."
  fi

  # Start local forwarding proxy for Gradle/Java
  if ! python3 -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('127.0.0.1',18080)); s.close()" 2>/dev/null; then
    echo "Starting local proxy for Gradle..."
    python3 "$(dirname "$0")/gradle_proxy.py" &
    sleep 1
  fi

  # Configure Gradle to use local proxy
  cat > "$GRADLE_DIR/gradle.properties" <<PROPS
systemProp.http.proxyHost=127.0.0.1
systemProp.http.proxyPort=18080
systemProp.https.proxyHost=127.0.0.1
systemProp.https.proxyPort=18080
org.gradle.jvmargs=-Xmx4g
PROPS
  echo "Gradle proxy configured."
fi

# ── 4. Generate Android scaffold if missing ────────────────────────────────
PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJ_DIR"

if [ ! -d "android" ]; then
  echo "Generating Android scaffold with flutter create..."
  flutter create --org com.alpinenav --project-name alpinenav --platforms android .
  echo "Android scaffold created."
fi

# ── 5. Install dependencies ───────────────────────────────────────────────
echo "Running flutter pub get..."
flutter pub get

echo "=== Setup complete ==="
flutter doctor --verbose 2>&1 | tail -5
