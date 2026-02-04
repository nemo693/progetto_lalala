// TODO(phase2): Implement GpxService for GPX import, export, and recording
//
// Key responsibilities:
// - Import: Parse GPX files into Route/Waypoint models
//   - Support tracks (<trk>), routes (<rte>), and waypoints (<wpt>)
//   - Handle multiple track segments (<trkseg>)
//   - Extract metadata: name, description, time, elevation
// - Export: Generate GPX XML from Route/Waypoint models
// - Record: Accumulate GPS fixes into a track during recording
//   - Compute running stats: distance, elevation gain/loss, elapsed time
//   - Apply basic filtering (discard fixes with poor accuracy)
//   - Support pause/resume
//
// Uses the `gpx` package for parsing and generation.
// Large files should be parsed in an isolate to avoid UI jank.

class GpxService {
  // TODO(phase2): Implement
}
