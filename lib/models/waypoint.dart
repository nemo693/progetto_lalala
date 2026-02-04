// TODO(phase2): Define Waypoint model
//
// Represents a named point of interest (from GPX or user-created).
//
// Fields:
// - id: unique identifier
// - name: display name
// - description: optional notes
// - latitude: WGS84 latitude
// - longitude: WGS84 longitude
// - elevation: meters above sea level (optional)
// - symbol: icon type (e.g., 'summit', 'hut', 'parking', 'water')
// - routeId: associated route (nullable — can be standalone)
// - createdAt: when saved
//
// Should support serialization to/from SQLite row and GPX <wpt> element.

class Waypoint {
  // TODO(phase2): Implement
}
