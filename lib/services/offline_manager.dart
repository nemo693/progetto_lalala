// TODO(phase3): Implement OfflineManager for tile downloading and caching
//
// Key responsibilities:
// - Download tiles for a bounding box at specified zoom levels
// - Download tiles for a buffered route corridor
// - Store tiles in MBTiles format (SQLite)
// - Report download progress (tile count, bytes, estimated remaining)
// - Cancel ongoing downloads
// - List cached regions with metadata (name, bounds, size, date)
// - Delete cached regions
// - Provide storage usage statistics
//
// Tile download strategy:
// 1. Compute tile indices for the target area at each zoom level
// 2. Check which tiles are already cached
// 3. Download missing tiles with concurrency limit (4-8 parallel requests)
// 4. Retry failed tiles with exponential backoff
// 5. Insert into MBTiles database in batches
//
// For WMS tiles (phase4):
// - Same flow but construct WMS GetMap URLs instead of Mapbox tile URLs
// - Separate MBTiles database per WMS source

class OfflineManager {
  // TODO(phase3): Implement
}
