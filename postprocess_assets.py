"""Post-process all raw ComfyUI output into game-ready assets.

Reads the generation manifest and processes:
- Tilesets → palette enforce, grid snap
- Character sprites → transparency cleanup, palette, grid snap, sprite sheet assembly
- NPC/Enemy sprites → transparency, palette, grid snap
- Item icons → transparency, palette, grid snap
- UI elements → transparency, palette, grid snap
"""

import json
import logging
from pathlib import Path
from PIL import Image

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

RAW_DIR = Path("D:/Claude/rpg-pipeline/assets/raw")
ASSETS_DIR = Path("D:/Claude/rpg-pipeline/assets")
SPRITE_SIZE = 32
TILE_SIZE = 32

# ENDESGA-32 inspired palette
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
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    pixels = img.load()
    w, h = img.size
    corners = [pixels[0,0], pixels[w-1,0], pixels[0,h-1], pixels[w-1,h-1]]
    bg = max(set(corners), key=corners.count)
    bg_r, bg_g, bg_b = bg[0], bg[1], bg[2]
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            dist = abs(r - bg_r) + abs(g - bg_g) + abs(b - bg_b)
            if dist < threshold:
                pixels[x, y] = (0, 0, 0, 0)
    return img


def grid_snap(img, size=SPRITE_SIZE):
    return img.resize((size, size), Image.Resampling.NEAREST)


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
        # Snap to 4x4 tile grid (128x128 final)
        target = TILE_SIZE * 4
        img = img.resize((target, target), Image.Resampling.NEAREST)
        out = out_dir / f"{tid}.png"
        img.save(out)
        logger.info("Tileset: %s → %s (%dx%d)", tid, out, img.width, img.height)


def process_player_sprites(class_ids):
    out_dir = ASSETS_DIR / "sprites" / "characters"
    out_dir.mkdir(parents=True, exist_ok=True)
    directions = ["front", "back", "left", "right"]

    for cid in class_ids:
        frames = []
        all_found = True
        for dir_name in directions:
            for frame in range(3):
                raw = RAW_DIR / f"{cid}_{dir_name}_{frame}.png"
                if not raw.exists():
                    logger.warning("Missing: %s", raw)
                    all_found = False
                    continue
                img = Image.open(raw).convert("RGBA")
                img = cleanup_transparency(img)
                img = grid_snap(img)
                img = enforce_palette(img)
                # Save individual frame
                frame_out = out_dir / f"{cid}_{dir_name}_{frame}.png"
                img.save(frame_out)
                frames.append(frame_out)

        # Assemble sprite sheet (4 rows × 3 cols)
        if len(frames) >= 12:
            sheet = Image.new("RGBA", (SPRITE_SIZE * 3, SPRITE_SIZE * 4), (0, 0, 0, 0))
            for i, fp in enumerate(frames[:12]):
                row = i // 3
                col = i % 3
                f = Image.open(fp)
                sheet.paste(f, (col * SPRITE_SIZE, row * SPRITE_SIZE))
            sheet_path = out_dir / f"{cid}_sheet.png"
            sheet.save(sheet_path)
            logger.info("Sprite sheet: %s (%dx%d)", sheet_path, sheet.width, sheet.height)
        else:
            logger.warning("Only %d/12 frames for %s, skipping sheet", len(frames), cid)


def process_single_sprites(sprite_ids, subfolder):
    out_dir = ASSETS_DIR / "sprites" / subfolder
    out_dir.mkdir(parents=True, exist_ok=True)
    for sid in sprite_ids:
        raw = RAW_DIR / f"{sid}_front.png"
        if not raw.exists():
            logger.warning("Missing: %s", raw)
            continue
        img = Image.open(raw).convert("RGBA")
        img = cleanup_transparency(img)
        img = grid_snap(img)
        img = enforce_palette(img)
        out = out_dir / f"{sid}.png"
        img.save(out)
        logger.info("Sprite: %s → %s", sid, out)


def process_icons(item_ids, subfolder="icons"):
    out_dir = ASSETS_DIR / "items" / subfolder
    out_dir.mkdir(parents=True, exist_ok=True)
    for iid in item_ids:
        raw = RAW_DIR / f"{iid}_raw.png"
        if not raw.exists():
            logger.warning("Missing: %s", raw)
            continue
        img = Image.open(raw).convert("RGBA")
        img = cleanup_transparency(img)
        img = grid_snap(img)
        img = enforce_palette(img)
        out = out_dir / f"{iid}.png"
        img.save(out)
        logger.info("Icon: %s → %s", iid, out)


def process_ui(ui_ids):
    out_dir = ASSETS_DIR / "ui"
    out_dir.mkdir(parents=True, exist_ok=True)
    for uid in ui_ids:
        raw = RAW_DIR / f"{uid}_raw.png"
        if not raw.exists():
            logger.warning("Missing: %s", raw)
            continue
        img = Image.open(raw).convert("RGBA")
        img = cleanup_transparency(img)
        img = grid_snap(img, 16)  # UI elements are 16x16
        img = enforce_palette(img)
        out = out_dir / f"{uid}.png"
        img.save(out)
        logger.info("UI: %s → %s", uid, out)


def main():
    manifest_path = RAW_DIR / "generation_manifest.json"
    if not manifest_path.exists():
        logger.error("No generation manifest found! Run generate_starter_art.py first.")
        return

    manifest = json.loads(manifest_path.read_text())

    print("\n" + "="*60)
    print("  POST-PROCESSING ASSETS")
    print(f"  Generated: {manifest['success']}/{manifest['total']}")
    print("="*60)

    print("\n> Processing tilesets...")
    process_tilesets(manifest["tilesets"])

    print("\n> Processing player sprites...")
    process_player_sprites(manifest["player_classes"])

    print("\n> Processing NPC sprites...")
    process_single_sprites(manifest["npcs"], "npcs")

    print("\n> Processing enemy sprites...")
    process_single_sprites(manifest["enemies"], "enemies")

    print("\n> Processing item icons...")
    process_icons(manifest["items"])

    print("\n> Processing UI elements...")
    process_ui(manifest["ui"])

    print("\n" + "="*60)
    print("  POST-PROCESSING COMPLETE")
    print("="*60)

    # Count final assets
    total_assets = 0
    for d in [ASSETS_DIR / "tilesets", ASSETS_DIR / "sprites", ASSETS_DIR / "items", ASSETS_DIR / "ui"]:
        if d.exists():
            count = len(list(d.rglob("*.png")))
            total_assets += count
            print(f"  {d.relative_to(ASSETS_DIR)}: {count} files")
    print(f"  TOTAL: {total_assets} game-ready assets")


if __name__ == "__main__":
    main()
