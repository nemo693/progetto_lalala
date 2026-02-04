# AlpineNav

Offline-first outdoor navigation for skitouring, hiking, and climbing in the Alps.

Built with Flutter and MapLibre GL. Android only (for now).

<!-- TODO: screenshots -->

## Features (planned)

- Offline map downloads (MBTiles)
- GPX import/export and track recording
- Italian regional orthophotos via WMS
- 3D terrain visualization (Mapbox, Phase 5)
- Minimal, gloves-friendly UI

See [docs/ROADMAP.md](docs/ROADMAP.md) for the full feature plan.

## Prerequisites

- Flutter SDK >= 3.27.0
- Android Studio (for Android SDK and emulator)
- No API keys needed for Phases 1–4 (MapLibre + OpenFreeMap are fully open)

## Setup

```bash
# Clone
git clone <repo-url>
cd alpinenav

# Generate Android scaffold (if not present)
flutter create --org com.alpinenav --project-name alpinenav --platforms android .

# Install dependencies
flutter pub get

# Run
flutter run
```

## Building

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release
```

## Project Structure

```
lib/
  main.dart              # Entry point
  screens/               # UI screens
  services/              # Business logic and data access
  models/                # Data models
  utils/                 # Utilities (tile math, etc.)
docs/
  ARCHITECTURE.md        # Technical architecture
  DATA_SOURCES.md        # Italian geoportal endpoints
  ROADMAP.md             # Feature roadmap
scripts/
  setup_env.sh           # Cloud environment setup (Claude Code on the web)
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

The mapping layer is abstracted behind a `MapProvider` interface. The active implementation uses MapLibre GL (open source, no API keys). A Mapbox implementation will be added in Phase 5 for 3D terrain, swappable without touching the rest of the app.

## License

GPL-3.0 — see [LICENSE](LICENSE) for details.

GPL was chosen because:
- Ensures derivatives remain open source
- Compatible with most dependencies
- Appropriate for a tool that processes public geospatial data
- Can be relicensed later if needed (as sole copyright holder)
