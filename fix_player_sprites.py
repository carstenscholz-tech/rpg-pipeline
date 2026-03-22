"""Fix player class sprites by extracting the most prominent character from each raw 512x512 image.

The raw images from ComfyUI show a "character selection screen" with multiple characters
instead of a single isolated character. This script:
1. Loads each raw 512x512 class sprite
2. Detects the background color from corners
3. Creates a mask of non-background pixels
4. Finds the bounding box of the largest character cluster
5. If the bounding box is too wide (>60% of image), focuses on center third
6. Crops with padding and resizes to 64x64
7. Saves individual frames and reassembles sprite sheets
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

RAW_DIR = Path("D:/Claude/rpg-pipeline/assets/raw")
OUT_DIR = Path("D:/Claude/rpg-pipeline/assets/sprites/characters")
SPRITE_SIZE = 64
BG_THRESHOLD = 40  # Color distance threshold for background detection
CLASSES = ["class_knight", "class_ranger", "class_mage", "class_rogue", "class_cleric"]
DIRECTIONS = ["front", "back", "left", "right"]
FRAMES = [0, 1, 2]


def get_background_color(img_array):
    """Sample corners to determine the background color."""
    h, w = img_array.shape[:2]
    # Sample 10x10 patches from each corner
    patch_size = 10
    corners = [
        img_array[:patch_size, :patch_size],           # top-left
        img_array[:patch_size, w-patch_size:],          # top-right
        img_array[h-patch_size:, :patch_size],          # bottom-left
        img_array[h-patch_size:, w-patch_size:],        # bottom-right
    ]
    # Average all corner pixels
    all_corner_pixels = np.concatenate([c.reshape(-1, c.shape[-1]) for c in corners], axis=0)
    bg_color = np.median(all_corner_pixels, axis=0).astype(np.uint8)
    return bg_color


def create_foreground_mask(img_array, bg_color, threshold=BG_THRESHOLD):
    """Create a boolean mask of pixels that differ from background."""
    # Use only RGB channels for comparison
    rgb = img_array[:, :, :3].astype(np.int16)
    bg_rgb = bg_color[:3].astype(np.int16)
    # Manhattan distance
    diff = np.sum(np.abs(rgb - bg_rgb), axis=2)
    mask = diff > threshold
    return mask


def find_largest_cluster_bbox(mask):
    """Find the bounding box of all non-background pixels."""
    rows = np.any(mask, axis=1)
    cols = np.any(mask, axis=0)
    if not np.any(rows) or not np.any(cols):
        return None
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    return (rmin, cmin, rmax, cmax)


def find_best_character_region(mask, img_width, img_height):
    """Find the best single character region in the mask.

    If the bounding box of all foreground pixels is very wide (>60% of image),
    it means multiple characters are present. In that case, analyze vertical
    strips to find the most prominent single character.
    """
    bbox = find_largest_cluster_bbox(mask)
    if bbox is None:
        return (0, 0, img_height - 1, img_width - 1)

    rmin, cmin, rmax, cmax = bbox
    bbox_width = cmax - cmin
    bbox_height = rmax - rmin

    # If bounding box is wider than 60% of image, multiple characters detected
    if bbox_width > img_width * 0.6:
        logger.info("  Wide bbox detected (%d px, %.0f%%), searching for best character...",
                     bbox_width, 100 * bbox_width / img_width)

        # Strategy: divide the foreground area into vertical strips and find
        # the strip with the most foreground pixels (the most prominent character)
        num_strips = 6
        strip_width = img_width // num_strips
        best_strip = 0
        best_count = 0

        for s in range(num_strips):
            x_start = s * strip_width
            x_end = min((s + 1) * strip_width, img_width)
            strip_mask = mask[:, x_start:x_end]
            count = np.sum(strip_mask)
            if count > best_count:
                best_count = count
                best_strip = s

        # Now focus on this strip and its neighbors for the character
        center_x = best_strip * strip_width + strip_width // 2

        # Search area: +/- 30% of image width around the center of the best strip
        search_radius = int(img_width * 0.20)
        search_left = max(0, center_x - search_radius)
        search_right = min(img_width, center_x + search_radius)

        # Get the bounding box within this search area
        sub_mask = mask[:, search_left:search_right]
        sub_bbox = find_largest_cluster_bbox(sub_mask)
        if sub_bbox is not None:
            sr_min, sc_min, sr_max, sc_max = sub_bbox
            return (sr_min, search_left + sc_min, sr_max, search_left + sc_max)

    return bbox


def extract_character(raw_path):
    """Extract the most prominent character from a raw sprite image."""
    img = Image.open(raw_path).convert("RGBA")
    img_array = np.array(img)
    h, w = img_array.shape[:2]

    # Get background color
    bg_color = get_background_color(img_array)
    logger.info("  Background color: RGB(%d, %d, %d)", bg_color[0], bg_color[1], bg_color[2])

    # Create foreground mask
    mask = create_foreground_mask(img_array, bg_color)

    # Find the best character region
    bbox = find_best_character_region(mask, w, h)
    if bbox is None:
        logger.warning("  No foreground found, using full image")
        cropped = img
    else:
        rmin, cmin, rmax, cmax = bbox

        # Add padding (5% of image size on each side)
        pad = int(max(w, h) * 0.05)
        rmin = max(0, rmin - pad)
        cmin = max(0, cmin - pad)
        rmax = min(h - 1, rmax + pad)
        cmax = min(w - 1, cmax + pad)

        # Make the crop square (use the larger dimension)
        crop_h = rmax - rmin
        crop_w = cmax - cmin
        size = max(crop_h, crop_w)

        # Center the crop
        center_r = (rmin + rmax) // 2
        center_c = (cmin + cmax) // 2
        half = size // 2

        r1 = max(0, center_r - half)
        r2 = min(h, center_r + half)
        c1 = max(0, center_c - half)
        c2 = min(w, center_c + half)

        logger.info("  Crop region: (%d,%d) to (%d,%d) [%dx%d]", c1, r1, c2, r2, c2-c1, r2-r1)
        cropped = img.crop((c1, r1, c2, r2))

    # Make the background transparent
    cropped_array = np.array(cropped)
    bg_color = get_background_color(cropped_array)
    fg_mask = create_foreground_mask(cropped_array, bg_color, threshold=BG_THRESHOLD)

    # Set background pixels to transparent
    cropped_array[~fg_mask] = [0, 0, 0, 0]
    result = Image.fromarray(cropped_array)

    # Resize to target size using LANCZOS
    result = result.resize((SPRITE_SIZE, SPRITE_SIZE), Image.Resampling.LANCZOS)

    return result


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("\n" + "=" * 60)
    print("  FIX PLAYER SPRITES - Extract single character from raw images")
    print("=" * 60)

    total_processed = 0
    total_failed = 0

    for class_name in CLASSES:
        print(f"\n> Processing {class_name}...")
        frames_for_sheet = []

        for direction in DIRECTIONS:
            for frame_num in FRAMES:
                raw_filename = f"{class_name}_{direction}_{frame_num}.png"
                raw_path = RAW_DIR / raw_filename

                if not raw_path.exists():
                    logger.warning("Missing: %s", raw_path)
                    total_failed += 1
                    continue

                logger.info("Processing %s...", raw_filename)
                try:
                    result = extract_character(raw_path)

                    # Save individual frame
                    out_path = OUT_DIR / raw_filename
                    result.save(out_path)
                    logger.info("  Saved: %s", out_path)

                    frames_for_sheet.append(result)
                    total_processed += 1
                except Exception as e:
                    logger.error("  FAILED: %s - %s", raw_filename, e)
                    total_failed += 1

        # Assemble sprite sheet (3 cols x 4 rows of 64x64 = 192x256)
        if len(frames_for_sheet) >= 12:
            sheet = Image.new("RGBA", (SPRITE_SIZE * 3, SPRITE_SIZE * 4), (0, 0, 0, 0))
            for i, frame_img in enumerate(frames_for_sheet[:12]):
                row = i // 3
                col = i % 3
                sheet.paste(frame_img, (col * SPRITE_SIZE, row * SPRITE_SIZE))
            sheet_path = OUT_DIR / f"{class_name}_sheet.png"
            sheet.save(sheet_path)
            logger.info("Sprite sheet: %s (%dx%d)", sheet_path, sheet.width, sheet.height)
        else:
            logger.warning("Only %d/12 frames for %s, skipping sheet", len(frames_for_sheet), class_name)

    print("\n" + "=" * 60)
    print(f"  DONE: {total_processed} processed, {total_failed} failed")
    print("=" * 60)


if __name__ == "__main__":
    main()
