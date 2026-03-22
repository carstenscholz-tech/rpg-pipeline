"""Post-process all raw ComfyUI output into game-ready assets.

Reads the generation manifest and processes:
- Tilesets → palette enforce only (already 128x128, no resize)
- Character sprites → LANCZOS downscale to 64x64, transparency cleanup, sprite sheet assembly
- NPC sprites → LANCZOS downscale to 64x64, transparency cleanup
- Enemy sprites → LANCZOS downscale to 64x64, transparency cleanup
- Item icons → LANCZOS downscale to 48x48, transparency cleanup
- UI elements → LANCZOS downscale to 24x24, transparency cleanup
- Portraits → LANCZOS downscale to 128x128, no transparency
- Environment objects → LANCZOS downscale to 64x64, transparency cleanup
- VFX → keep at 128x128, black background → transparent
- World map → keep at original size, no processing
"""

import json
import logging
from pathlib import Path
from PIL import Image

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

RAW_DIR = Path("D:/Claude/rpg-pipeline/assets/raw")
ASSETS_DIR = Path("D:/Claude/rpg-pipeline/assets")

# Sprite sizes per category
CHAR_SPRITE_SIZE = 64
NPC_SPRITE_SIZE = 64
ENEMY_SPRITE_SIZE = 64
ICON_SIZE = 48
UI_SIZE = 24
PORTRAIT_SIZE = 128
ENVIRONMENT_SIZE = 64
VFX_SIZE = 128
TILE_SIZE = 32

# ENDESGA-32 inspired palette (only used for tilesets)
PALETTE_RGB = [
    (190, 74, 47), (215, 118, 67), (234, 212, 170), (228, 166, 114),
    (184, 111, 80), (115, 62, 57), (62, 39, 49), (24, 20, 37),
    (255, 0, 68), (255, 132, 38), (255, 214, 53), (73, 231, 134),
    (38, 166, 91), (26, 104, 76), (17, 55, 53), (62, 137, 72),
    (99, 199, 77), (254, 231, 97), (247, 118, 34), (172, 50, 50),
    (102, 57, 49), (143, 86, 59), (223, 113, 38), (217, 160, 102),
    (238, 195, 154), (251, 242, 54), (68, 137, 26), (55, 148, 110),
    (75, 105, 47), (89, 86, 82), (155, 173, 183), (245, 245, 245),
]


def nearest_color(r, g, b):
    best = PALETTE_RGB[0]
    best_dist = float("inf")
    for pr, pg, pb in PALETTE_RGB:
        dist = (r - pr)**2 + (g - pg)**2 + (b - pb)**2
        if dist < best_dist:
            best_dist = dist
            best = (pr, pg, pb)
    return best


def enforce_palette(img):
    """Snap every opaque pixel to the nearest palette color. Only used for tilesets."""
    if img.mode == "RGBA":
        pixels = img.load()
        w, h = img.size
        for y in range(h):
            for x in range(w):
                r, g, b, a = pixels[x, y]
                if a > 128:
                    nr, ng, nb = nearest_color(r, g, b)
                    pixels[x, y] = (nr, ng, nb, a)
                else:
                    pixels[x, y] = (0, 0, 0, 0)
        return img
    else:
        rgb = img.convert("RGB")
        pixels = rgb.load()
        w, h = rgb.size
        for y in range(h):
            for x in range(w):
                r, g, b = pixels[x, y]
                pixels[x, y] = nearest_color(r, g, b)
        return rgb


def cleanup_transparency(img, threshold=30):
    """Detect the solid background color from corners and make it transparent."""
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    pixels = img.load()
    w, h = img.size
    corners = [pixels[0, 0], pixels[w - 1, 0], pixels[0, h - 1], pixels[w - 1, h - 1]]
    bg = max(set(corners), key=corners.count)
    bg_r, bg_g, bg_b = bg[0], bg[1], bg[2]
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            dist = abs(r - bg_r) + abs(g - bg_g) + abs(b - bg_b)
            if dist < threshold:
                pixels[x, y] = (0, 0, 0, 0)
    return img


def cleanup_black_transparency(img, threshold=30):
    """Remove black background (used for VFX). Treats near-black as transparent."""
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if r + g + b < threshold:
                pixels[x, y] = (0, 0, 0, 0)
    return img


def downscale_lanczos_then_snap(img, target_size):
    """Two-step downscale: LANCZOS for quality, then nearest neighbor for pixel-perfect snap."""
    img = img.resize((target_size, target_size), Image.Resampling.LANCZOS)
    img = img.resize((target_size, target_size), Image.Resampling.NEAREST)
    return img


# ---------------------------------------------------------------------------
# Tilesets: already 128x128 (4x4 grid of 32px tiles). Just enforce palette.
# ---------------------------------------------------------------------------
def process_tilesets(tileset_ids):
    out_dir = ASSETS_DIR / "tilesets"
    out_dir.mkdir(parents=True, exist_ok=True)
    for tid in tileset_ids:
        raw = RAW_DIR / f"{tid}_raw.png"
        if not raw.exists():
            logger.warning("Missing tileset: %s", raw)
            continue
        img = Image.open(raw).convert("RGB")
        img = enforce_palette(img)
        # Do NOT resize — tilesets are already at the correct 128x128 size.
        # Only snap if the raw image is not exactly 128x128.
        if img.size != (128, 128):
            img = img.resize((128, 128), Image.Resampling.NEAREST)
        out = out_dir / f"{tid}.png"
        img.save(out)
        logger.info("Tileset: %s -> %s (%dx%d)", tid, out, img.width, img.height)


# ---------------------------------------------------------------------------
# Character sprites: 512x512 raw -> 64x64 per frame, assembled into sheets
# ---------------------------------------------------------------------------
def process_player_sprites(class_ids):
    out_dir = ASSETS_DIR / "sprites" / "characters"
    out_dir.mkdir(parents=True, exist_ok=True)
    directions = ["front", "back", "left", "right"]

    for cid in class_ids:
        frames = []
        for dir_name in directions:
            for frame in range(3):
                raw = RAW_DIR / f"{cid}_{dir_name}_{frame}.png"
                if not raw.exists():
                    logger.warning("Missing: %s", raw)
                    continue
                img = Image.open(raw).convert("RGBA")
                img = downscale_lanczos_then_snap(img, CHAR_SPRITE_SIZE)
                img = cleanup_transparency(img)
                # No palette enforcement — it destroys detail at small sizes
                frame_out = out_dir / f"{cid}_{dir_name}_{frame}.png"
                img.save(frame_out)
                frames.append(frame_out)

        # Assemble sprite sheet (4 rows x 3 cols at 64x64 per cell = 192x256)
        if len(frames) >= 12:
            sheet = Image.new("RGBA",
                              (CHAR_SPRITE_SIZE * 3, CHAR_SPRITE_SIZE * 4),
                              (0, 0, 0, 0))
            for i, fp in enumerate(frames[:12]):
                row = i // 3
                col = i % 3
                f = Image.open(fp)
                sheet.paste(f, (col * CHAR_SPRITE_SIZE, row * CHAR_SPRITE_SIZE))
            sheet_path = out_dir / f"{cid}_sheet.png"
            sheet.save(sheet_path)
            logger.info("Sprite sheet: %s (%dx%d)", sheet_path, sheet.width, sheet.height)
        else:
            logger.warning("Only %d/12 frames for %s, skipping sheet", len(frames), cid)


# ---------------------------------------------------------------------------
# NPC sprites: 512x512 raw -> single 64x64 images
# ---------------------------------------------------------------------------
def process_npc_sprites(sprite_ids):
    out_dir = ASSETS_DIR / "sprites" / "npcs"
    out_dir.mkdir(parents=True, exist_ok=True)
    for sid in sprite_ids:
        raw = RAW_DIR / f"{sid}_front.png"
        if not raw.exists():
            logger.warning("Missing: %s", raw)
            continue
        img = Image.open(raw).convert("RGBA")
        img = downscale_lanczos_then_snap(img, NPC_SPRITE_SIZE)
        img = cleanup_transparency(img)
        # No palette enforcement
        out = out_dir / f"{sid}.png"
        img.save(out)
        logger.info("NPC sprite: %s -> %s", sid, out)


# ---------------------------------------------------------------------------
# Enemy sprites: 512x512 raw -> single 64x64 images
# ---------------------------------------------------------------------------
def process_enemy_sprites(sprite_ids):
    out_dir = ASSETS_DIR / "sprites" / "enemies"
    out_dir.mkdir(parents=True, exist_ok=True)
    for sid in sprite_ids:
        raw = RAW_DIR / f"{sid}_front.png"
        if not raw.exists():
            logger.warning("Missing: %s", raw)
            continue
        img = Image.open(raw).convert("RGBA")
        img = downscale_lanczos_then_snap(img, ENEMY_SPRITE_SIZE)
        img = cleanup_transparency(img)
        # No palette enforcement
        out = out_dir / f"{sid}.png"
        img.save(out)
        logger.info("Enemy sprite: %s -> %s", sid, out)


# ---------------------------------------------------------------------------
# Item icons: 512x512 raw -> 48x48
# ---------------------------------------------------------------------------
def process_icons(item_ids, subfolder="icons"):
    out_dir = ASSETS_DIR / "items" / subfolder
    out_dir.mkdir(parents=True, exist_ok=True)
    for iid in item_ids:
        raw = RAW_DIR / f"{iid}_raw.png"
        if not raw.exists():
            logger.warning("Missing: %s", raw)
            continue
        img = Image.open(raw).convert("RGBA")
        img = downscale_lanczos_then_snap(img, ICON_SIZE)
        img = cleanup_transparency(img)
        # No palette enforcement
        out = out_dir / f"{iid}.png"
        img.save(out)
        logger.info("Icon: %s -> %s", iid, out)


# ---------------------------------------------------------------------------
# UI elements: 512x512 raw -> 24x24
# ---------------------------------------------------------------------------
def process_ui(ui_ids):
    out_dir = ASSETS_DIR / "ui"
    out_dir.mkdir(parents=True, exist_ok=True)
    for uid in ui_ids:
        raw = RAW_DIR / f"{uid}_raw.png"
        if not raw.exists():
            logger.warning("Missing: %s", raw)
            continue
        img = Image.open(raw).convert("RGBA")
        img = downscale_lanczos_then_snap(img, UI_SIZE)
        img = cleanup_transparency(img)
        # No palette enforcement
        out = out_dir / f"{uid}.png"
        img.save(out)
        logger.info("UI: %s -> %s", uid, out)


# ---------------------------------------------------------------------------
# Portraits: 512x512 raw -> 128x128, no transparency
# ---------------------------------------------------------------------------
def process_portraits(portrait_ids):
    out_dir = ASSETS_DIR / "portraits"
    out_dir.mkdir(parents=True, exist_ok=True)
    for pid in portrait_ids:
        raw = RAW_DIR / f"{pid}_raw.png"
        if not raw.exists():
            # Also try without _raw suffix
            raw = RAW_DIR / f"{pid}.png"
        if not raw.exists():
            logger.warning("Missing portrait: %s", pid)
            continue
        img = Image.open(raw).convert("RGB")
        img = img.resize((PORTRAIT_SIZE, PORTRAIT_SIZE), Image.Resampling.LANCZOS)
        out = out_dir / f"{pid}.png"
        img.save(out)
        logger.info("Portrait: %s -> %s", pid, out)


# ---------------------------------------------------------------------------
# Environment objects: 512x512 raw -> 64x64, transparency cleanup
# ---------------------------------------------------------------------------
def process_environment(env_ids):
    out_dir = ASSETS_DIR / "sprites" / "environment"
    out_dir.mkdir(parents=True, exist_ok=True)
    for eid in env_ids:
        raw = RAW_DIR / f"{eid}_raw.png"
        if not raw.exists():
            raw = RAW_DIR / f"{eid}.png"
        if not raw.exists():
            logger.warning("Missing environment: %s", eid)
            continue
        img = Image.open(raw).convert("RGBA")
        img = downscale_lanczos_then_snap(img, ENVIRONMENT_SIZE)
        img = cleanup_transparency(img)
        out = out_dir / f"{eid}.png"
        img.save(out)
        logger.info("Environment: %s -> %s", eid, out)


# ---------------------------------------------------------------------------
# VFX: keep at 128x128, black background -> transparent
# ---------------------------------------------------------------------------
def process_vfx(vfx_ids):
    out_dir = ASSETS_DIR / "vfx"
    out_dir.mkdir(parents=True, exist_ok=True)
    for vid in vfx_ids:
        raw = RAW_DIR / f"{vid}_raw.png"
        if not raw.exists():
            raw = RAW_DIR / f"{vid}.png"
        if not raw.exists():
            logger.warning("Missing VFX: %s", vid)
            continue
        img = Image.open(raw).convert("RGBA")
        # Resize to 128x128 if not already
        if img.size != (VFX_SIZE, VFX_SIZE):
            img = img.resize((VFX_SIZE, VFX_SIZE), Image.Resampling.LANCZOS)
        img = cleanup_black_transparency(img)
        out = out_dir / f"{vid}.png"
        img.save(out)
        logger.info("VFX: %s -> %s", vid, out)


# ---------------------------------------------------------------------------
# World map: keep at original size (1024x1024), no processing
# ---------------------------------------------------------------------------
def process_worldmap(map_ids):
    out_dir = ASSETS_DIR / "maps"
    out_dir.mkdir(parents=True, exist_ok=True)
    for mid in map_ids:
        raw = RAW_DIR / f"{mid}_raw.png"
        if not raw.exists():
            raw = RAW_DIR / f"{mid}.png"
        if not raw.exists():
            logger.warning("Missing world map: %s", mid)
            continue
        img = Image.open(raw).convert("RGB")
        # Keep at original size — no resize, no transparency, no palette
        out = out_dir / f"{mid}.png"
        img.save(out)
        logger.info("World map: %s -> %s (%dx%d)", mid, out, img.width, img.height)


# ---------------------------------------------------------------------------
# Scan raw directory for files matching a pattern (fallback when manifest
# doesn't have a category)
# ---------------------------------------------------------------------------
def scan_raw_for_category(prefix):
    """Scan RAW_DIR for files starting with prefix, return list of base IDs."""
    ids = set()
    for f in RAW_DIR.glob(f"{prefix}*"):
        if f.suffix.lower() != ".png":
            continue
        name = f.stem
        # Strip common suffixes
        for suffix in ("_raw", "_front", "_back", "_left", "_right"):
            if name.endswith(suffix):
                name = name[: -len(suffix)]
                break
        # Strip frame numbers like _0, _1, _2
        parts = name.rsplit("_", 1)
        if len(parts) == 2 and parts[1].isdigit():
            name = parts[0]
        ids.add(name)
    return sorted(ids)


def main():
    manifest_path = RAW_DIR / "generation_manifest.json"
    if not manifest_path.exists():
        logger.error("No generation manifest found! Run generate_starter_art.py first.")
        return

    manifest = json.loads(manifest_path.read_text())

    print("\n" + "=" * 60)
    print("  POST-PROCESSING ASSETS")
    print(f"  Generated: {manifest.get('success', '?')}/{manifest.get('total', '?')}")
    print("=" * 60)

    # --- Standard categories from manifest ---
    print("\n> Processing tilesets...")
    process_tilesets(manifest.get("tilesets", []))

    print("\n> Processing player sprites...")
    process_player_sprites(manifest.get("player_classes", []))

    print("\n> Processing NPC sprites...")
    process_npc_sprites(manifest.get("npcs", []))

    print("\n> Processing enemy sprites...")
    process_enemy_sprites(manifest.get("enemies", []))

    print("\n> Processing item icons...")
    process_icons(manifest.get("items", []))

    print("\n> Processing UI elements...")
    process_ui(manifest.get("ui", []))

    # --- New categories (use manifest if present, otherwise scan raw dir) ---
    print("\n> Processing portraits...")
    portrait_ids = manifest.get("portraits", [])
    if not portrait_ids:
        portrait_ids = scan_raw_for_category("portrait")
    process_portraits(portrait_ids)

    print("\n> Processing environment objects...")
    env_ids = manifest.get("environment", [])
    if not env_ids:
        env_ids = scan_raw_for_category("env_")
    process_environment(env_ids)

    print("\n> Processing VFX...")
    vfx_ids = manifest.get("vfx", [])
    if not vfx_ids:
        vfx_ids = scan_raw_for_category("vfx_")
    process_vfx(vfx_ids)

    print("\n> Processing world map...")
    map_ids = manifest.get("worldmap", [])
    if not map_ids:
        map_ids = scan_raw_for_category("worldmap")
    process_worldmap(map_ids)

    print("\n" + "=" * 60)
    print("  POST-PROCESSING COMPLETE")
    print("=" * 60)

    # Count final assets
    total_assets = 0
    asset_dirs = [
        ASSETS_DIR / "tilesets",
        ASSETS_DIR / "sprites",
        ASSETS_DIR / "items",
        ASSETS_DIR / "ui",
        ASSETS_DIR / "portraits",
        ASSETS_DIR / "vfx",
        ASSETS_DIR / "maps",
    ]
    for d in asset_dirs:
        if d.exists():
            count = len(list(d.rglob("*.png")))
            total_assets += count
            print(f"  {d.relative_to(ASSETS_DIR)}: {count} files")
    print(f"  TOTAL: {total_assets} game-ready assets")


if __name__ == "__main__":
    main()
