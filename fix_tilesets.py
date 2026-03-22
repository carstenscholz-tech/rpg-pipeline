"""Fix tileset images by removing white/transparent edge pixels between tiles.

The AI-generated tilesets at 128x128 contain 4x4 grids of 32x32 tiles, but
individual tiles may have white or transparent pixels at their edges from the
generation process, causing visible gaps when rendered in-game.

This script:
1. Loads each tileset PNG (128x128)
2. For each 32x32 tile cell, finds white (R>240, G>240, B>240) or transparent pixels
3. Replaces those pixels with the average color of nearby non-white neighbors
4. Saves the fixed tileset back
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

TILESETS_DIR = Path("D:/Claude/rpg-pipeline/assets/tilesets")
TILE_SIZE = 32
ATLAS_COLS = 4
ATLAS_ROWS = 4

# Tileset files to process
TILESET_FILES = [
    "grass_plains.png",
    "cobblestone_town.png",
    "forest_floor.png",
    "water_river.png",
    "cave_dungeon.png",
    "wooden_buildings.png",
]


def is_white_or_transparent(r, g, b, a, white_threshold=240):
    """Check if a pixel is white or transparent."""
    if a < 128:
        return True
    if r > white_threshold and g > white_threshold and b > white_threshold:
        return True
    return False


def fix_tile(tile_array):
    """Fix a single 32x32 tile by replacing white/transparent pixels with neighbor averages.

    Args:
        tile_array: numpy array of shape (32, 32, 4) in RGBA format

    Returns:
        Fixed tile array
    """
    h, w = tile_array.shape[:2]
    result = tile_array.copy()

    # Build mask of bad pixels
    r, g, b, a = result[:, :, 0], result[:, :, 1], result[:, :, 2], result[:, :, 3]
    bad_mask = ((a < 128) | ((r > 240) & (g > 240) & (b > 240)))

    if not np.any(bad_mask):
        return result

    bad_count = np.sum(bad_mask)
    logger.debug("  Found %d bad pixels in tile", bad_count)

    # If almost all pixels are bad, this tile is essentially empty - fill with a neutral color
    total_pixels = h * w
    if bad_count > total_pixels * 0.9:
        # Find any good pixels to use as reference
        good_mask = ~bad_mask
        if np.any(good_mask):
            avg_color = np.mean(result[good_mask], axis=0).astype(np.uint8)
            result[:, :] = avg_color
            result[:, :, 3] = 255
        return result

    # For each bad pixel, replace with the average of its non-bad neighbors
    # Use iterative approach: keep replacing until no bad pixels remain or max iterations
    for iteration in range(10):
        new_bad_count = 0
        for y in range(h):
            for x in range(w):
                if not bad_mask[y, x]:
                    continue

                # Collect non-bad neighbors (including diagonals)
                neighbors = []
                for dy in range(-2, 3):
                    for dx in range(-2, 3):
                        if dy == 0 and dx == 0:
                            continue
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and not bad_mask[ny, nx]:
                            neighbors.append(result[ny, nx])

                if neighbors:
                    avg = np.mean(neighbors, axis=0).astype(np.uint8)
                    result[y, x] = avg
                    result[y, x, 3] = 255  # Ensure fully opaque
                    bad_mask[y, x] = False
                else:
                    new_bad_count += 1

        if new_bad_count == 0:
            break

    # Final pass: any remaining bad pixels get the tile's average color
    remaining_bad = bad_mask.copy()
    if np.any(remaining_bad):
        good_pixels = result[~remaining_bad]
        if len(good_pixels) > 0:
            avg_color = np.mean(good_pixels, axis=0).astype(np.uint8)
            result[remaining_bad] = avg_color
            # Make sure alpha is 255 for all replaced pixels
            for y in range(h):
                for x in range(w):
                    if remaining_bad[y, x]:
                        result[y, x, 3] = 255

    return result


def fix_tileset(filepath):
    """Fix all tiles in a tileset image."""
    img = Image.open(filepath).convert("RGBA")
    img_array = np.array(img)

    h, w = img_array.shape[:2]
    logger.info("Processing %s (%dx%d)", filepath.name, w, h)

    # If image isn't the expected size, resize it
    expected_w = TILE_SIZE * ATLAS_COLS
    expected_h = TILE_SIZE * ATLAS_ROWS
    if w != expected_w or h != expected_h:
        logger.info("  Resizing from %dx%d to %dx%d", w, h, expected_w, expected_h)
        img = img.resize((expected_w, expected_h), Image.Resampling.NEAREST)
        img_array = np.array(img)
        h, w = img_array.shape[:2]

    total_fixed = 0

    # Process each tile
    for row in range(ATLAS_ROWS):
        for col in range(ATLAS_COLS):
            y1 = row * TILE_SIZE
            y2 = y1 + TILE_SIZE
            x1 = col * TILE_SIZE
            x2 = x1 + TILE_SIZE

            tile = img_array[y1:y2, x1:x2].copy()

            # Count bad pixels before fix
            r, g, b, a = tile[:, :, 0], tile[:, :, 1], tile[:, :, 2], tile[:, :, 3]
            bad_before = np.sum((a < 128) | ((r > 240) & (g > 240) & (b > 240)))

            if bad_before > 0:
                fixed_tile = fix_tile(tile)
                img_array[y1:y2, x1:x2] = fixed_tile
                total_fixed += bad_before
                logger.info("  Tile (%d,%d): fixed %d pixels", col, row, bad_before)

    # Also fix any gaps BETWEEN tiles (at tile boundaries)
    # Ensure edge pixels of adjacent tiles are consistent
    for row in range(ATLAS_ROWS):
        for col in range(ATLAS_COLS):
            y1 = row * TILE_SIZE
            x1 = col * TILE_SIZE

            # Fix right edge: blend with left edge of next tile
            if col < ATLAS_COLS - 1:
                for y in range(y1, min(y1 + TILE_SIZE, h)):
                    px_right = img_array[y, x1 + TILE_SIZE - 1]
                    px_next_left = img_array[y, x1 + TILE_SIZE]
                    # If either is still white-ish, copy from the other
                    if px_right[0] > 240 and px_right[1] > 240 and px_right[2] > 240:
                        img_array[y, x1 + TILE_SIZE - 1] = px_next_left
                    if px_next_left[0] > 240 and px_next_left[1] > 240 and px_next_left[2] > 240:
                        img_array[y, x1 + TILE_SIZE] = px_right

            # Fix bottom edge: blend with top edge of next tile
            if row < ATLAS_ROWS - 1:
                for x in range(x1, min(x1 + TILE_SIZE, w)):
                    px_bottom = img_array[y1 + TILE_SIZE - 1, x]
                    px_next_top = img_array[y1 + TILE_SIZE, x]
                    if px_bottom[0] > 240 and px_bottom[1] > 240 and px_bottom[2] > 240:
                        img_array[y1 + TILE_SIZE - 1, x] = px_next_top
                    if px_next_top[0] > 240 and px_next_top[1] > 240 and px_next_top[2] > 240:
                        img_array[y1 + TILE_SIZE, x] = px_bottom

    # Ensure all pixels are fully opaque (no transparency in tilesets)
    img_array[:, :, 3] = 255

    # Save
    result = Image.fromarray(img_array)
    result.save(filepath)
    logger.info("  Saved %s (fixed %d total pixels)", filepath.name, total_fixed)
    return total_fixed


def main():
    print("\n" + "=" * 60)
    print("  FIX TILESETS - Remove white gaps and transparent edges")
    print("=" * 60)

    total_fixed_all = 0

    for filename in TILESET_FILES:
        filepath = TILESETS_DIR / filename
        if not filepath.exists():
            logger.warning("Missing tileset: %s", filepath)
            continue

        fixed = fix_tileset(filepath)
        total_fixed_all += fixed

    print("\n" + "=" * 60)
    print(f"  DONE: Fixed {total_fixed_all} total pixels across all tilesets")
    print("=" * 60)


if __name__ == "__main__":
    main()
