"""Post-processing for ComfyUI-generated pixel art assets.

Handles palette enforcement, grid snapping, transparency cleanup,
sprite sheet assembly, and tileset atlas creation.
"""

import logging
from pathlib import Path

from PIL import Image

from pipeline import config

logger = logging.getLogger(__name__)

# ENDESGA-32 inspired palette (32 colors for consistent pixel art)
PALETTE_RGB = [
    (190, 74, 47),    # dark red
    (215, 118, 67),   # orange
    (234, 212, 170),  # skin light
    (228, 166, 114),  # skin mid
    (184, 111, 80),   # skin dark
    (115, 62, 57),    # brown dark
    (62, 39, 49),     # near-black
    (24, 20, 37),     # darkest
    (255, 0, 68),     # bright red
    (255, 132, 38),   # bright orange
    (255, 214, 53),   # yellow
    (73, 231, 134),   # green light
    (38, 166, 91),    # green mid
    (26, 104, 76),    # green dark
    (17, 55, 53),     # green darkest
    (62, 137, 72),    # forest green
    (99, 199, 77),    # lime
    (254, 231, 97),   # gold
    (247, 118, 34),   # pumpkin
    (172, 50, 50),    # crimson
    (102, 57, 49),    # brown
    (143, 86, 59),    # brown light
    (223, 113, 38),   # copper
    (217, 160, 102),  # tan
    (238, 195, 154),  # cream
    (251, 242, 54),   # neon yellow
    (68, 137, 26),    # olive
    (55, 148, 110),   # teal
    (75, 105, 47),    # moss
    (89, 86, 82),     # gray
    (155, 173, 183),  # silver
    (245, 245, 245),  # white
]


def _nearest_palette_color(r: int, g: int, b: int) -> tuple[int, int, int]:
    """Find the nearest color in the palette by Euclidean distance."""
    best = PALETTE_RGB[0]
    best_dist = float("inf")
    for pr, pg, pb in PALETTE_RGB:
        dist = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if dist < best_dist:
            best_dist = dist
            best = (pr, pg, pb)
    return best


def enforce_palette(img: Image.Image, max_colors: int = config.MAX_PALETTE_COLORS) -> Image.Image:
    """Reduce image to the fixed palette."""
    if img.mode == "RGBA":
        # Preserve alpha channel
        rgb = img.convert("RGB")
        alpha = img.getchannel("A")

        pixels = rgb.load()
        w, h = rgb.size
        for y in range(h):
            for x in range(w):
                r, g, b = pixels[x, y]
                pixels[x, y] = _nearest_palette_color(r, g, b)

        result = rgb.convert("RGBA")
        result.putalpha(alpha)
        return result
    else:
        pixels = img.load()
        w, h = img.size
        for y in range(h):
            for x in range(w):
                r, g, b = pixels[x, y][:3]
                pixels[x, y] = _nearest_palette_color(r, g, b)
        return img


def grid_snap(img: Image.Image, target_size: int = config.SPRITE_SIZE) -> Image.Image:
    """Downscale to target sprite size using nearest-neighbor for crisp pixels."""
    return img.resize((target_size, target_size), Image.Resampling.NEAREST)


def cleanup_transparency(img: Image.Image, bg_threshold: int = 30) -> Image.Image:
    """Convert near-uniform background to transparent.

    Samples corner pixels to detect background color, then makes all
    similar pixels transparent.
    """
    if img.mode != "RGBA":
        img = img.convert("RGBA")

    pixels = img.load()
    w, h = img.size

    # Sample corners to find background color
    corners = [pixels[0, 0], pixels[w-1, 0], pixels[0, h-1], pixels[w-1, h-1]]
    # Use most common corner color as background
    bg = max(set(corners), key=corners.count)
    bg_r, bg_g, bg_b = bg[0], bg[1], bg[2]

    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            dist = abs(r - bg_r) + abs(g - bg_g) + abs(b - bg_b)
            if dist < bg_threshold:
                pixels[x, y] = (0, 0, 0, 0)

    return img


def assemble_sprite_sheet(
    frames: list[Path],
    rows: int = 4,
    cols: int = 3,
    cell_size: int = config.SPRITE_SIZE,
) -> Image.Image:
    """Assemble individual sprite frames into a sheet.

    Expected order: down_0, down_1, down_2, up_0, up_1, up_2,
                    left_0, left_1, left_2, right_0, right_1, right_2
    (4 rows × 3 cols)
    """
    sheet_w = cols * cell_size
    sheet_h = rows * cell_size
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))

    for i, frame_path in enumerate(frames[:rows * cols]):
        row = i // cols
        col = i % cols
        frame = Image.open(frame_path).convert("RGBA")
        frame = grid_snap(frame, cell_size)
        sheet.paste(frame, (col * cell_size, row * cell_size))

    return sheet


def slice_tileset(
    tileset_img: Image.Image,
    tile_size: int = config.SPRITE_SIZE,
) -> list[Image.Image]:
    """Slice a tileset image into individual tiles."""
    w, h = tileset_img.size
    cols = w // tile_size
    rows = h // tile_size
    tiles = []
    for row in range(rows):
        for col in range(cols):
            box = (col * tile_size, row * tile_size,
                   (col + 1) * tile_size, (row + 1) * tile_size)
            tiles.append(tileset_img.crop(box))
    return tiles


# ---------------------------------------------------------------------------
# Full processing pipelines
# ---------------------------------------------------------------------------

def process_character_sprites(
    character_id: str,
    raw_frames: list[Path],
) -> Path:
    """Full pipeline: raw frames → palette → grid snap → transparency → sheet.

    Returns path to the final sprite sheet.
    """
    processed = []
    direction_order = ["down", "up", "left", "right"]

    # Sort frames by direction and frame number
    sorted_frames = []
    for direction in direction_order:
        dir_frames = sorted(
            [f for f in raw_frames if f"_{direction}_" in f.name],
            key=lambda p: p.name,
        )
        sorted_frames.extend(dir_frames)

    for frame_path in sorted_frames:
        img = Image.open(frame_path).convert("RGBA")
        img = cleanup_transparency(img)
        img = grid_snap(img)
        img = enforce_palette(img)
        processed.append(img)

    # Save individual processed frames
    processed_paths = []
    for i, img in enumerate(processed):
        direction = direction_order[i // 3]
        frame_num = i % 3
        out_path = config.ASSETS_DIR / "sprites" / "characters" / f"{character_id}_{direction}_{frame_num}.png"
        out_path.parent.mkdir(parents=True, exist_ok=True)
        img.save(out_path)
        processed_paths.append(out_path)

    # Assemble sheet
    sheet = assemble_sprite_sheet(processed_paths)
    sheet_path = config.ASSETS_DIR / "sprites" / "characters" / f"{character_id}_sheet.png"
    sheet.save(sheet_path)
    logger.info("Sprite sheet saved: %s (%dx%d)", sheet_path, sheet.width, sheet.height)

    return sheet_path


def process_tileset(tileset_id: str, raw_path: Path) -> Path:
    """Full pipeline: raw tileset → palette → grid snap → save."""
    img = Image.open(raw_path).convert("RGB")
    img = enforce_palette(img)

    # Downscale to proper tile grid
    tile_count = img.width // config.SPRITE_SIZE  # Approximate
    target_size = tile_count * config.SPRITE_SIZE
    img = img.resize((target_size, target_size), Image.Resampling.NEAREST)

    out_path = config.ASSETS_DIR / "tilesets" / f"{tileset_id}_tileset.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    logger.info("Tileset saved: %s", out_path)
    return out_path


def process_item_icon(item_id: str, raw_path: Path) -> Path:
    """Full pipeline: raw icon → transparency → palette → downscale → save."""
    img = Image.open(raw_path).convert("RGBA")
    img = cleanup_transparency(img)
    img = grid_snap(img)
    img = enforce_palette(img)

    out_path = config.ASSETS_DIR / "items" / "icons" / f"{item_id}.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    logger.info("Item icon saved: %s", out_path)
    return out_path
