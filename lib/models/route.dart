// TODO(phase2): Define Route model
//
// Represents a saved track or imported route.
//
// Fields:
// - id: unique identifier (UUID or auto-increment)
// - name: display name (from GPX or user-entered)
// - description: optional notes
// - points: list of track points (lat, lon, elevation, timestamp)
// - distance: total distance in meters
// - elevationGain: cumulative ascent in meters
// - elevationLoss: cumulative descent in meters
// - duration: elapsed time
// - source: 'imported' | 'recorded'
// - createdAt: when saved
// - filePath: path to the GPX file on disk
//
// Should support serialization to/from SQLite row and GPX.

class Route {
  // TODO(phase2): Implement
}
