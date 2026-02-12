# Italian Geospatial Data Sources

## Custom WMS Sources

AlpineNav allows you to add your own custom WMS sources. This is useful for:
- Regional geoportals not included in the built-in sources
- Private/licensed orthophoto services
- Experimental or testing WMS endpoints
- Updated versions of existing sources with better quality/coverage

### Adding Custom WMS Sources

1. Tap the download button (cloud icon) on the map screen
2. Select **"Custom WMS sources"** from the bottom sheet
3. Tap the **+** icon in the top right
4. Fill in the WMS details:
   - **ID**: Unique identifier (lowercase, alphanumeric, hyphens/underscores only)
   - **Display Name**: Human-readable name shown in the map source picker
   - **WMS Base URL**: The GetMap endpoint URL (e.g., `https://example.com/wms`)
   - **Layer Name(s)**: WMS layer identifier(s) (e.g., `orthophoto_2024`)
   - **Attribution**: Copyright/source attribution text
   - **Coordinate System**: Usually `EPSG:3857` (Web Mercator)
   - **Image Format**: `image/jpeg` (smaller, no transparency) or `image/png`
   - **Tile Size**: `256` or `512` pixels

Custom sources are saved locally and persist across app restarts. They appear in the map source picker alongside built-in sources, marked with an orange WMS badge.

### Finding WMS Parameters

To find the correct parameters for a WMS service:

1. Locate the service's **GetCapabilities** URL (usually the base URL + `?service=WMS&request=GetCapabilities`)
2. Open it in a browser and look for:
   - `<Layer><Name>` — this is your layer name
   - `<CRS>` or `<SRS>` — coordinate systems supported (prefer EPSG:3857)
   - `<Format>` — image formats supported (prefer image/jpeg for orthophotos)

Example GetCapabilities:
```
https://example.com/wms?service=WMS&request=GetCapabilities
```

### Example Custom WMS

**Veneto Orthophoto 2023** (example):
- **ID**: `veneto_ortho_2023`
- **Display Name**: `Veneto Orthophoto 2023`
- **WMS Base URL**: `https://idt2.regione.veneto.it/geoserver/wms`
- **Layer Name**: `ortofoto_2023`
- **Attribution**: `© Regione Veneto`
- **CRS**: `EPSG:3857`
- **Format**: `image/jpeg`
- **Tile Size**: `256`

## National Orthophotos

### AGEA 2023

National-coverage RGB orthophotos from the Italian agricultural agency (AGEA).

| Property | Value |
|----------|-------|
| WMS endpoint | `https://servizigis.regione.emilia-romagna.it/wms/agea2023_rgb` |
| Protocol | WMS 1.3.0 |
| Layer | `agea2023_rgb` |
| Resolution | ~20 cm/px |
| Acquisition | April-July 2023 |
| CRS | EPSG:3857, EPSG:32632, EPSG:4326 |
| Format | image/png, image/jpeg |
| Coverage | National (served through regional endpoints) |
| Access | Free, no authentication |

**GetCapabilities**:
```
https://servizigis.regione.emilia-romagna.it/wms/agea2023_rgb?request=GetCapabilities&service=WMS
```

**Notes**:
- Most recent national orthophoto coverage (2023)
- High resolution (20 cm/px), significantly better than PCN 2012 (50 cm/px)
- RGB color imagery
- Suitable for detailed terrain analysis and route planning

### PCN (Portale Cartografico Nazionale)

National-coverage orthophotos managed by the Ministry of Environment.

| Property | Value |
|----------|-------|
| WMS endpoint | `http://wms.pcn.minambiente.it/ogc?map=/ms_ogc/WMS_v1.3/raster/ortofoto_colore_12.map` |
| Protocol | WMS 1.3.0 |
| Layer | `ortofoto_colore_12` |
| Resolution | ~50 cm/px |
| CRS | EPSG:4326, EPSG:3857, EPSG:32632 |
| Format | image/png, image/jpeg |
| Coverage | National |
| Access | Free, no authentication |

**GetCapabilities**:
```
http://wms.pcn.minambiente.it/ogc?map=/ms_ogc/WMS_v1.3/raster/ortofoto_colore_12.map&SERVICE=WMS&REQUEST=GetCapabilities
```

**Sample GetMap request** (Web Mercator, 256x256 tile):
```
http://wms.pcn.minambiente.it/ogc?map=/ms_ogc/WMS_v1.3/raster/ortofoto_colore_12.map
  &SERVICE=WMS
  &VERSION=1.3.0
  &REQUEST=GetMap
  &LAYERS=ortofoto_colore_12
  &CRS=EPSG:3857
  &BBOX={xmin},{ymin},{xmax},{ymax}
  &WIDTH=256
  &HEIGHT=256
  &FORMAT=image/jpeg
```

**Notes**:
- Server can be slow; implement timeouts and retries
- JPEG preferred over PNG for orthophotos (smaller, no transparency needed)
- Request in EPSG:3857 to match Web Mercator tile grid directly

## Regional Geoportals

### Veneto

| Property | Value |
|----------|-------|
| Portal | https://idt2.regione.veneto.it/ |
| WMS | TBD (check GetCapabilities) |
| Resolution | Up to 20 cm in some areas |
| CRS | EPSG:32632 (UTM 32N), EPSG:6706 |
| Notes | High-quality recent flights available |

### Lombardia

| Property | Value |
|----------|-------|
| Portal | https://www.geoportale.regione.lombardia.it/ |
| WMS | TBD (check GetCapabilities) |
| Resolution | Variable, up to 20 cm |
| CRS | EPSG:32632 |
| Notes | Multiple flight years available |

### Piemonte

| Property | Value |
|----------|-------|
| Portal | https://www.geoportale.piemonte.it/ |
| WMS | TBD (check GetCapabilities) |
| Resolution | Variable |
| CRS | EPSG:32632 |

### Trentino-Alto Adige

#### Trentino (Provincia Autonoma di Trento)

| Property | Value |
|----------|-------|
| Portal | https://siat.provincia.tn.it/stem/ |
| Data portal | http://www.territorio.provincia.tn.it/ |
| WMS (Orthophoto 2015) | `https://siat.provincia.tn.it/geoserver/stem/ecw-rgb-2015/wms` |
| WMS (LiDAR Hillshade) | `https://siat.provincia.tn.it/geoserver/stem/wms` |
| Resolution (Ortho) | 0.2 m (RGB, 2015 flight) |
| Resolution (LiDAR) | 1-2 m DTM (2014/2018 integrated) |
| CRS | EPSG:32632, EPSG:3857 |
| Format | image/jpeg, image/png |
| Coverage | Full provincial territory |
| Access | Free, no authentication |

**GetCapabilities (Orthophoto 2015)**:
```
https://siat.provincia.tn.it/geoserver/stem/ecw-rgb-2015/wms?request=GetCapabilities&service=WMS&version=1.3.0
```

**GetCapabilities (LiDAR/DTM layers)**:
```
https://siat.provincia.tn.it/geoserver/stem/wms?request=GetCapabilities&service=WMS
```

**Notes**:
- Excellent quality 0.2m RGB orthophotos from 2015 flight
- LiDAR coverage includes DTM, hillshade (soleggiamento), DSM
- LiDAR data from 2014 survey integrated with 2018 flights
- Available layers:
  - `ecw-rgb-2015` (orthophoto 2015, 0.2m resolution)
  - `dtm_315_wg` (DTM hillshade with 315° azimuth - northwest lighting)
  - 2019 orthophoto exists but WMS endpoint not yet confirmed
- Data downloadable in GeoTIFF and ECW formats from https://siat.provincia.tn.it/stem/
- Hillshade layer uses 315° azimuth (standard northwest illumination angle)

#### Alto Adige (Bolzano)

| Property | Value |
|----------|-------|
| Portal (Bolzano) | http://geokatalog.buergernetz.bz.it/ |
| WMS | TBD |
| Resolution | Variable |
| CRS | EPSG:32632 |

## DTM Sources

### Tinitaly

| Property | Value |
|----------|-------|
| Resolution | 10 m |
| Coverage | National |
| Format | GeoTIFF |
| CRS | EPSG:32632 (UTM 32N) |
| Access | Free download after registration |
| URL | http://tinitaly.pi.ingv.it/ |
| Notes | Good for national-scale terrain; insufficient for detailed mountaineering |

### Regional LiDAR DTM

Higher resolution available from regional geoportals:

| Region | Resolution | Notes |
|--------|-----------|-------|
| Trentino | 1 m | Excellent LiDAR coverage |
| Alto Adige | 2.5 m | Full coverage |
| Veneto | 1-5 m | Mountain areas well covered |
| Lombardia | 5 m | Variable coverage |
| Piemonte | 5 m | Mountain areas |
| Valle d'Aosta | 2 m | Full regional coverage |
| Friuli VG | 1 m | Good LiDAR coverage |

## Coordinate System Notes

### Common CRS in Italian data

| EPSG | Name | Use |
|------|------|-----|
| 4326 | WGS84 Geographic | GPS coordinates (lat/lon) |
| 3857 | Web Mercator | Mapbox tiles, web maps |
| 32632 | UTM Zone 32N | Most Italian regional data |
| 32633 | UTM Zone 33N | Eastern Italy (Puglia, etc.) |
| 3003 | Monte Mario / Italy 1 | Legacy Italian cartography |
| 6706 | RDN2008 | Modern Italian national datum |

### Conversion strategy

All data must be served to MapLibre in **EPSG:3857** (Web Mercator) for raster tiles, or **EPSG:4326** for GeoJSON.

For WMS requests:
1. Compute the tile's bounding box in EPSG:3857
2. Request from WMS in EPSG:3857 if supported
3. If not supported, request in the source CRS and reproject client-side (computationally expensive — avoid if possible)

Most Italian WMS endpoints support EPSG:3857 in addition to their native CRS. Always verify via GetCapabilities.

## Data Quality Considerations

- **Temporal**: Orthophotos may be years old. Check flight date metadata.
- **Positional accuracy**: National orthophotos ~1m; regional can be better.
- **Coverage gaps**: Mountain shadows, clouds in some flights.
- **Availability**: Government WMS servers can be unreliable. Always cache aggressively.
- **Rate limiting**: Unknown for most endpoints. Be conservative with parallel requests.

## Implementation Notes

### WMS to tile conversion

To use WMS data as a tile layer in MapLibre:

1. For each visible tile (z/x/y), compute its bounding box in EPSG:3857
2. Send a WMS GetMap request for that bbox at 256x256 or 512x512 pixels
3. Store the response image in the MBTiles cache
4. Serve from cache on subsequent requests

This effectively creates a custom raster tile source from any WMS endpoint.

### Practical zoom levels

| Zoom | Approx. ground resolution | Use case |
|------|--------------------------|----------|
| 10 | ~150 m/px | Regional overview |
| 13 | ~19 m/px | Valley-level navigation |
| 15 | ~5 m/px | Trail-level navigation |
| 17 | ~1.2 m/px | Detailed terrain (matches 50cm ortho) |
| 18 | ~0.6 m/px | Maximum useful for 50cm orthophotos |

Downloading tiles at zoom 10-17 for a typical skitouring route with 2km buffer produces ~500-2000 tiles, roughly 20-80 MB depending on terrain complexity.
