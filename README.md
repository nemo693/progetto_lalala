# AlpineNav

Offline-first outdoor navigation for skitouring, hiking, and climbing in the Alps.

Built with Flutter and Mapbox Maps SDK. Android only (for now).

<!-- TODO: screenshots -->

## Features (planned)

- Offline map downloads (MBTiles)
- GPX import/export and track recording
- Italian regional orthophotos via WMS
- 3D terrain visualization
- Minimal, gloves-friendly UI

See [docs/ROADMAP.md](docs/ROADMAP.md) for the full feature plan.

## Prerequisites

- Flutter SDK >= 3.27.0
- Android Studio (for Android SDK and emulator)
- Mapbox account with access token

## Setup

```bash
# Clone
git clone <repo-url>
cd alpinenav

# Install dependencies
flutter pub get

# Configure Mapbox token (see below)

# Run
flutter run
```

### Mapbox Access Token

1. Create an account at https://account.mapbox.com/
2. Create an access token with the default scopes plus `DOWNLOADS:READ`
3. Configure the token for the SDK — see [Mapbox Flutter installation guide](https://docs.mapbox.com/android/maps/guides/install/)

The token must be available at build time. Do NOT commit it to the repo.

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
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

The mapping layer is abstracted behind a `MapProvider` interface to allow future migration from Mapbox to MapLibre when mobile 3D terrain support matures.

## License

GPL-3.0 — see [LICENSE](LICENSE) for details.

GPL was chosen because:
- Ensures derivatives remain open source
- Compatible with most dependencies
- Appropriate for a tool that processes public geospatial data
- Can be relicensed later if needed (as sole copyright holder)
