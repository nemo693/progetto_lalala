#!/usr/bin/env python3
"""
Compute terrain analysis products from Trentino LiDAR DTM.

This script downloads DTM from the STEM portal (or uses local file) and computes:
- Slope (degrees)
- Aspect (0-360°)
- Terrain Ruggedness Index (TRI)
- Colorized visualizations

Usage:
    python compute_terrain_analysis.py --dtm dtm_trentino.tif --output-dir ./output

Requirements:
    pip install rasterio numpy scipy matplotlib gdal
"""

import argparse
import sys
from pathlib import Path
import numpy as np
import rasterio
from rasterio.plot import show
from scipy.ndimage import convolve
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


def load_dtm(tif_path: str) -> tuple:
    """Load DTM GeoTIFF as numpy array. Returns (array, profile)."""
    with rasterio.open(tif_path) as src:
        dtm = src.read(1).astype(float)
        profile = src.profile
        logger.info(f"Loaded DTM: {dtm.shape}, CRS: {profile['crs']}, "
                   f"pixel size: {profile.get('transform', None)}")
    return dtm, profile


def compute_slope(dtm: np.ndarray, cellsize: float = 1.0, algorithm: str = 'zevenbergen_thorne') -> np.ndarray:
    """
    Compute slope in degrees.

    Args:
        dtm: 2D elevation array
        cellsize: DEM resolution in map units (1.0 for 1m LiDAR)
        algorithm: 'zevenbergen_thorne' (accurate) or 'horn' (faster)

    Returns:
        2D slope array in degrees (0-90)
    """
    if algorithm == 'zevenbergen_thorne':
        # Zevenbergen & Thorne (1987) — recommended for LiDAR
        kernel_x = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=float) / (8 * cellsize)
        kernel_y = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=float) / (8 * cellsize)
    elif algorithm == 'horn':
        # Horn (1981) — simpler, faster
        kernel_x = np.array([[-1, 0, 1], [-1, 0, 1], [-1, 0, 1]], dtype=float) / (6 * cellsize)
        kernel_y = np.array([[-1, -1, -1], [0, 0, 0], [1, 1, 1]], dtype=float) / (6 * cellsize)
    else:
        raise ValueError(f"Unknown algorithm: {algorithm}")

    # Compute gradients
    grad_x = convolve(dtm, kernel_x, mode='constant', cval=np.nan)
    grad_y = convolve(dtm, kernel_y, mode='constant', cval=np.nan)

    # Slope from gradient magnitude
    slope_rad = np.arctan(np.sqrt(grad_x**2 + grad_y**2))
    slope_deg = np.degrees(slope_rad)

    logger.info(f"Slope: min={np.nanmin(slope_deg):.2f}°, "
               f"max={np.nanmax(slope_deg):.2f}°, "
               f"mean={np.nanmean(slope_deg):.2f}°")

    return slope_deg


def compute_aspect(dtm: np.ndarray, cellsize: float = 1.0) -> np.ndarray:
    """
    Compute aspect in degrees (0° = North, 90° = East, 180° = South, 270° = West).

    Args:
        dtm: 2D elevation array
        cellsize: DEM resolution in map units

    Returns:
        2D aspect array (0-360°), with -1 for flat cells
    """
    # Zevenbergen & Thorne gradient kernels
    kernel_x = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=float) / (8 * cellsize)
    kernel_y = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=float) / (8 * cellsize)

    grad_x = convolve(dtm, kernel_x, mode='constant', cval=np.nan)
    grad_y = convolve(dtm, kernel_y, mode='constant', cval=np.nan)

    # Aspect from atan2
    # Note: -grad_x for compass orientation (counterclockwise from East)
    aspect_rad = np.arctan2(grad_y, -grad_x)
    aspect_deg = np.degrees(aspect_rad)
    aspect_deg = (aspect_deg + 360) % 360  # Normalize to 0-360

    # Mark flat cells (slope < 1°) as -1
    slope_rad = np.arctan(np.sqrt(grad_x**2 + grad_y**2))
    slope_deg = np.degrees(slope_rad)
    aspect_deg = np.where(slope_deg < 1.0, -1, aspect_deg)

    logger.info(f"Aspect: computed for {np.count_nonzero(aspect_deg != -1)} non-flat cells, "
               f"{np.count_nonzero(aspect_deg == -1)} flat cells")

    return aspect_deg


def compute_tri(dtm: np.ndarray) -> np.ndarray:
    """
    Compute Terrain Ruggedness Index: sqrt( mean((dh)^2) ) for 8 neighbors.

    Measures terrain roughness (0 = flat, higher = rougher).
    """
    logger.info("Computing Terrain Ruggedness Index...")
    tri = np.zeros_like(dtm, dtype=float)

    for i in range(1, dtm.shape[0] - 1):
        for j in range(1, dtm.shape[1] - 1):
            center = dtm[i, j]
            # 8 neighbors
            neighbors = [
                dtm[i-1, j-1], dtm[i-1, j], dtm[i-1, j+1],
                dtm[i, j-1],                dtm[i, j+1],
                dtm[i+1, j-1], dtm[i+1, j], dtm[i+1, j+1],
            ]
            diffs = [(center - n) ** 2 for n in neighbors]
            tri[i, j] = np.sqrt(np.mean(diffs))

    logger.info(f"TRI: min={np.min(tri):.2f}, max={np.max(tri):.2f}, mean={np.mean(tri):.2f}")
    return tri


def colorize_slope(slope_array: np.ndarray, algorithm: str = 'skitour') -> np.ndarray:
    """
    Colorize slope array to RGB for visualization.

    Args:
        slope_array: 2D slope in degrees (0-90)
        algorithm: 'skitour' or 'climbing'

    Returns:
        3D RGB array (3, height, width) with uint8 values
    """
    if algorithm == 'skitour':
        # Ski touring color scheme
        # Green: safe, gentle
        # Yellow: moderate, requires technique
        # Red: steep, avalanche/rockfall risk
        bins = [0, 20, 45, 90]
        colors = [
            (0, 200, 0),      # Green
            (255, 255, 0),    # Yellow
            (255, 0, 0),      # Red
        ]
    elif algorithm == 'climbing':
        # Rock climbing color scheme
        bins = [0, 20, 35, 50, 90]
        colors = [
            (0, 0, 255),      # Blue: walk
            (0, 255, 0),      # Green: scramble
            (255, 255, 0),    # Yellow: moderate
            (255, 0, 0),      # Red: hard/exposed
        ]
    else:
        raise ValueError(f"Unknown algorithm: {algorithm}")

    h, w = slope_array.shape
    rgb = np.zeros((3, h, w), dtype=np.uint8)

    # Assign colors
    for i, (lower, upper) in enumerate(zip(bins[:-1], bins[1:])):
        mask = (slope_array >= lower) & (slope_array < upper)
        rgb[0, mask] = colors[i][0]  # R
        rgb[1, mask] = colors[i][1]  # G
        rgb[2, mask] = colors[i][2]  # B

    logger.info(f"Colorized slope ({algorithm}): {np.count_nonzero(rgb[0])} colored pixels")
    return rgb


def colorize_aspect(aspect_array: np.ndarray) -> np.ndarray:
    """
    Colorize aspect array to 8-direction compass.

    N=red, NE=yellow, E=green, SE=cyan, S=blue, SW=magenta, W=white, NW=orange
    """
    h, w = aspect_array.shape
    rgb = np.zeros((3, h, w), dtype=np.uint8)

    # Define 8 compass directions
    # Aspect angles: N=0, NE=45, E=90, SE=135, S=180, SW=225, W=270, NW=315
    directions = [
        (0, 22.5, (255, 0, 0)),       # N: red
        (22.5, 67.5, (255, 255, 0)),  # NE: yellow
        (67.5, 112.5, (0, 255, 0)),   # E: green
        (112.5, 157.5, (0, 255, 255)), # SE: cyan
        (157.5, 202.5, (0, 0, 255)),  # S: blue
        (202.5, 247.5, (255, 0, 255)), # SW: magenta
        (247.5, 292.5, (255, 255, 255)), # W: white
        (292.5, 337.5, (255, 165, 0)), # NW: orange
        (337.5, 360, (255, 0, 0)),    # N (wrap): red
    ]

    for lower, upper, color in directions:
        mask = (aspect_array >= lower) & (aspect_array < upper)
        rgb[0, mask] = color[0]
        rgb[1, mask] = color[1]
        rgb[2, mask] = color[2]

    # Flat cells (aspect=-1): gray
    flat_mask = aspect_array == -1
    rgb[0, flat_mask] = 128
    rgb[1, flat_mask] = 128
    rgb[2, flat_mask] = 128

    logger.info(f"Colorized aspect: 8 compass directions")
    return rgb


def save_raster(array: np.ndarray, profile: dict, output_path: str,
                nodata: float = -9999) -> None:
    """Save numpy array as GeoTIFF."""
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Handle 2D or 3D arrays
    if array.ndim == 2:
        profile.update(dtype=rasterio.float32, count=1, nodata=nodata)
        with rasterio.open(output_path, 'w', **profile) as dst:
            dst.write(array.astype(rasterio.float32), 1)
    else:  # 3D RGB
        profile.update(dtype=rasterio.uint8, count=3, nodata=None)
        with rasterio.open(output_path, 'w', **profile) as dst:
            for i in range(3):
                dst.write(array[i].astype(rasterio.uint8), i + 1)

    logger.info(f"Saved: {output_path} ({array.nbytes / 1e6:.1f} MB)")


def main():
    parser = argparse.ArgumentParser(
        description='Compute terrain analysis from Trentino LiDAR DTM',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python compute_terrain_analysis.py --dtm dtm.tif --output-dir ./terrain
  python compute_terrain_analysis.py --dtm dtm.tif --skip-tri --skip-aspect
        """
    )

    parser.add_argument('--dtm', type=str, required=True,
                       help='Path to DTM GeoTIFF (from STEM portal)')
    parser.add_argument('--output-dir', type=str, default='./terrain_analysis',
                       help='Output directory for results')
    parser.add_argument('--skip-tri', action='store_true',
                       help='Skip TRI computation (slow on large files)')
    parser.add_argument('--skip-aspect', action='store_true',
                       help='Skip aspect computation')
    parser.add_argument('--slope-algorithm', type=str, default='zevenbergen_thorne',
                       choices=['zevenbergen_thorne', 'horn'],
                       help='Slope algorithm')
    parser.add_argument('--colorize-slope', type=str, default='skitour',
                       choices=['skitour', 'climbing'],
                       help='Slope colorization scheme')

    args = parser.parse_args()

    # Validate input
    dtm_path = Path(args.dtm)
    if not dtm_path.exists():
        logger.error(f"DTM file not found: {dtm_path}")
        sys.exit(1)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    logger.info(f"Loading DTM from {dtm_path}...")
    dtm, profile = load_dtm(str(dtm_path))

    logger.info("Computing slope...")
    slope = compute_slope(dtm, cellsize=1.0, algorithm=args.slope_algorithm)
    save_raster(slope, profile, str(output_dir / 'slope_degrees.tif'))

    if not args.skip_aspect:
        logger.info("Computing aspect...")
        aspect = compute_aspect(dtm, cellsize=1.0)
        save_raster(aspect, profile, str(output_dir / 'aspect_degrees.tif'), nodata=-1)

        logger.info("Colorizing aspect...")
        aspect_rgb = colorize_aspect(aspect)
        save_raster(aspect_rgb, profile, str(output_dir / 'aspect_colorized.tif'))

    logger.info("Colorizing slope...")
    slope_rgb = colorize_slope(slope, algorithm=args.colorize_slope)
    save_raster(slope_rgb, profile, str(output_dir / 'slope_colorized.tif'))

    if not args.skip_tri:
        logger.info("Computing Terrain Ruggedness Index...")
        tri = compute_tri(dtm)
        save_raster(tri, profile, str(output_dir / 'tri.tif'))

    logger.info(f"\n✓ Done! Results in {output_dir}")
    logger.info(f"  slope_degrees.tif (raw)")
    logger.info(f"  slope_colorized.tif (ski touring color scheme)")
    logger.info(f"  aspect_degrees.tif (raw)")
    logger.info(f"  aspect_colorized.tif (compass colors)")
    if not args.skip_tri:
        logger.info(f"  tri.tif (terrain ruggedness)")


if __name__ == '__main__':
    main()
