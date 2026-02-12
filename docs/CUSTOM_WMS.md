# Custom WMS Sources

AlpineNav supports user-defined custom WMS sources, allowing you to add your own orthophoto layers, hillshades, or other WMS endpoints alongside the built-in map sources.

## Features

- **Persistent storage**: Custom WMS sources are saved locally and persist across app restarts
- **Full offline support**: Custom WMS layers can be downloaded for offline use just like built-in sources
- **Easy management**: Add, edit, and delete custom sources through a dedicated UI
- **Flexible configuration**: Configure all WMS parameters (URL, layers, CRS, format, tile size, attribution)

## User Interface

### Accessing Custom WMS Management

1. On the map screen, tap the **download button** (cloud icon) in the top-right corner
2. From the bottom sheet, select **"Custom WMS sources"**
3. The custom WMS screen shows all your custom sources with their details

### Adding a Custom WMS Source

1. In the Custom WMS screen, tap the **+** button in the top-right
2. Fill in the WMS parameters:
   - **ID**: Unique identifier (lowercase letters, numbers, hyphens, underscores only)
     - Example: `my_custom_orthophoto`, `region_lidar`
     - Cannot be changed after creation
   - **Display Name**: Human-readable name shown in the map source picker
     - Example: "Veneto Orthophoto 2024", "My Region LiDAR"
   - **WMS Base URL**: The WMS GetMap endpoint
     - Example: `https://example.com/geoserver/wms`
     - Can include query parameters if the endpoint requires them
   - **Layer Name(s)**: WMS layer identifier from GetCapabilities
     - Example: `orthophoto_2024`, `my_layer`
     - Can specify multiple layers separated by commas
   - **Attribution**: Copyright/source attribution
     - Example: "© My Region Geoportal"
   - **Coordinate System**: CRS for WMS requests (dropdown)
     - Options: `EPSG:3857`, `EPSG:4326`, `EPSG:32632`, `EPSG:32633`
     - Default: `EPSG:3857` (Web Mercator, recommended)
   - **Image Format**: Response format (dropdown)
     - Options: `image/jpeg` (smaller files, no transparency), `image/png` (larger, supports transparency)
     - Default: `image/jpeg` (recommended for orthophotos)
   - **Tile Size**: Pixels per tile (dropdown)
     - Options: `256`, `512`
     - Default: `256` (recommended)
3. Tap **"Add"** to save

### Editing a Custom WMS Source

1. In the Custom WMS screen, tap the **edit icon** next to a source
2. Modify any fields except the ID (ID is immutable)
3. Tap **"Update"** to save changes

### Deleting a Custom WMS Source

1. In the Custom WMS screen, tap the **delete icon** next to a source
2. Confirm deletion in the dialog

**Note**: Deleting a custom source does NOT delete offline regions downloaded for that source. Those regions remain available in the "Manage offline regions" screen.

## Using Custom WMS Sources

Once added, custom WMS sources appear in the map source picker alongside built-in sources:

1. Tap the **layers button** (stacked squares icon) on the map screen
2. Custom WMS sources are listed after the built-in WMS sources
3. Custom sources are marked with an **orange WMS badge** for easy identification
4. Tap a custom source to switch to it

Custom WMS sources can be downloaded for offline use:

1. Switch to the custom WMS source
2. Tap the **download button** (cloud icon)
3. Select "Download visible area" or "Download around route"
4. Configure zoom range and name, then start download

Downloaded tiles are cached locally and served when offline, just like built-in sources.

## Finding WMS Parameters

To find the correct parameters for a WMS service:

### 1. Locate the GetCapabilities URL

Most WMS services provide a GetCapabilities endpoint that describes available layers and supported formats. The URL is usually:

```
{BASE_URL}?service=WMS&request=GetCapabilities
```

For example:
```
https://siat.provincia.tn.it/geoserver/stem/wms?service=WMS&request=GetCapabilities
```

### 2. Open GetCapabilities in a Browser

Open the URL in a web browser. You'll see an XML document with the service metadata.

### 3. Extract WMS Parameters

Look for these elements in the XML:

- **WMS Base URL**: Found in `<OnlineResource>` tags, usually at the top
- **Layer Name**: Found in `<Layer><Name>` tags
  ```xml
  <Layer>
    <Name>orthophoto_2024</Name>
    <Title>Orthophoto 2024</Title>
    ...
  </Layer>
  ```
- **Coordinate Systems**: Found in `<CRS>` or `<SRS>` tags within each layer
  ```xml
  <CRS>EPSG:3857</CRS>
  <CRS>EPSG:4326</CRS>
  <CRS>EPSG:32632</CRS>
  ```
- **Image Formats**: Found in `<Format>` tags under `<GetMap>`
  ```xml
  <GetMap>
    <Format>image/jpeg</Format>
    <Format>image/png</Format>
  </GetMap>
  ```

### 4. Recommended Settings

- **CRS**: Prefer `EPSG:3857` (Web Mercator) if supported — this matches the internal tile grid and avoids reprojection overhead
- **Format**: Use `image/jpeg` for orthophotos (smaller file size, faster downloads), `image/png` for data with transparency (hillshades with overlay)
- **Tile Size**: Use `256` unless you have a specific reason to use `512`

## Example: Adding Trentino Orthophoto

Let's add the Trentino 2015 orthophoto as a custom source (this is already built-in, but serves as a good example):

1. **Find GetCapabilities**:
   ```
   https://siat.provincia.tn.it/geoserver/stem/ecw-rgb-2015/wms?request=GetCapabilities&service=WMS&version=1.3.0
   ```

2. **Extract parameters from the XML**:
   - Base URL: `https://siat.provincia.tn.it/geoserver/stem/ecw-rgb-2015/wms`
   - Layer name: `ecw-rgb-2015` (from `<Layer><Name>`)
   - Supported CRS: `EPSG:3857`, `EPSG:32632`, `EPSG:4326` (from `<CRS>` tags)
   - Supported formats: `image/jpeg`, `image/png`

3. **Fill in the form**:
   - **ID**: `trentino_ortho_custom`
   - **Display Name**: `Trentino Orthophoto 2015 (Custom)`
   - **WMS Base URL**: `https://siat.provincia.tn.it/geoserver/stem/ecw-rgb-2015/wms`
   - **Layer Name**: `ecw-rgb-2015`
   - **Attribution**: `© Provincia Autonoma di Trento`
   - **CRS**: `EPSG:3857`
   - **Format**: `image/jpeg`
   - **Tile Size**: `256`

4. **Tap "Add"** and the source is now available in the map source picker.

## Technical Implementation

### File Storage

Custom WMS sources are stored in JSON format at:
```
{app_documents_directory}/custom_wms_sources.json
```

Each source is serialized with all configuration parameters (id, name, wmsBaseUrl, wmsLayers, wmsCrs, wmsFormat, attribution, tileSize, avgTileSizeBytes).

### Service: CustomWmsService

`lib/services/custom_wms_service.dart` manages the lifecycle of custom sources:

- `initialize()`: Loads custom sources from disk on app startup
- `addSource(MapSource)`: Adds a new custom source (validates uniqueness, type)
- `updateSource(String id, MapSource)`: Updates an existing source
- `deleteSource(String id)`: Removes a custom source
- `customSources`: Getter for all loaded custom sources

### UI: WmsSourcesScreen

`lib/screens/wms_sources_screen.dart` provides the management UI:

- **List view**: Shows all custom sources with name, layer, URL
- **Add button**: Opens a dialog to create a new source
- **Edit button**: Opens a dialog to modify an existing source
- **Delete button**: Confirms and removes a source

### Integration with Map Screen

The map screen (`lib/screens/map_screen.dart`) merges custom sources with built-in sources:

- `_availableSources` getter calls `MapSource.allWithCustom(customWmsService.customSources)`
- Map source picker displays all sources (built-in + custom) in order
- Custom sources work identically to built-in WMS sources (same offline download, caching, rendering)

### Offline Support

Custom WMS sources use the same offline infrastructure as built-in WMS sources:

- WMS tiles are fetched via `WmsTileServer` and cached in the WMS tile cache
- Offline regions are tracked in `wms_regions.json` with a `styleUrl` field of `wms://{sourceId}`
- Downloads work through the same foreground service with progress tracking

## Limitations

- **WMS only**: Currently only WMS sources can be added as custom sources. Vector tile sources and XYZ raster sources are not supported for custom addition (built-in sources only).
- **ID immutability**: Once created, a source's ID cannot be changed (it's used as the cache key). To change the ID, delete and re-create the source.
- **No validation**: The app does not validate WMS URLs or test connectivity before saving. Invalid URLs will fail when you try to use the source.

## Troubleshooting

### "Invalid ID" error when adding a source

- Ensure the ID contains only lowercase letters, numbers, hyphens (`-`), and underscores (`_`)
- No spaces, uppercase letters, or special characters allowed
- Example valid IDs: `my_source`, `ortho-2024`, `custom_wms_1`

### Source appears in picker but shows blank tiles

- Check the WMS Base URL is correct (copy from GetCapabilities)
- Verify the Layer Name exactly matches the name in GetCapabilities (case-sensitive)
- Ensure the CRS is supported by the server (check GetCapabilities `<CRS>` tags)
- Try switching format from JPEG to PNG or vice versa

### Download fails or times out

- The WMS server may be slow or rate-limited
- Try reducing the zoom range to download fewer tiles
- Check network connectivity
- Some WMS servers block bulk downloads — try a smaller area first

### Custom source not appearing in map picker

- Ensure you tapped "Add" or "Update" to save the source
- Restart the app if the source was added but isn't showing
- Check `custom_wms_sources.json` exists in the app documents directory

## Future Enhancements

Possible future improvements:

- **URL validation**: Test WMS URL on save and show error if unreachable
- **GetCapabilities parser**: Auto-fill parameters by parsing GetCapabilities XML
- **Source preview**: Show a small map preview when configuring a source
- **Import/export**: Share custom source configurations as JSON files
- **XYZ raster support**: Allow adding custom XYZ tile sources (e.g., private tile servers)
