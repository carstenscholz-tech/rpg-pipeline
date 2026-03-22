"""Batch art generation for the Hearthholm starter zone.

Generates all essential assets via ComfyUI sequentially (one at a time).
"""

import json
import logging
import sys
import time
import uuid
from pathlib import Path

import httpx

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

COMFYUI_API = "http://127.0.0.1:8188"
RAW_DIR = Path("D:/Claude/rpg-pipeline/assets/raw")
RAW_DIR.mkdir(parents=True, exist_ok=True)

NEG_SPRITE = "blurry, anti-aliased, smooth, 3D, realistic, photograph, noise, text, watermark, signature, multiple characters, border, frame"
NEG_TILE = "blurry, anti-aliased, smooth, 3D, realistic, photograph, noise, text, watermark, characters, people, border"
NEG_ICON = "blurry, anti-aliased, smooth, 3D, realistic, photograph, noise, text, watermark, multiple items, character, border"


def generate_one(name: str, positive: str, negative: str, seed: int,
                 width: int, height: int, out_name: str) -> bool:
    """Generate a single image, wait for completion, download it."""
    logger.info("Generating: %s", name)

    workflow = {
        "1": {"class_type": "CheckpointLoaderSimple",
              "inputs": {"ckpt_name": "sd_xl_base_1.0.safetensors"}},
        "2": {"class_type": "LoraLoader",
              "inputs": {"lora_name": "pixel-art-xl.safetensors",
                         "model": ["1", 0], "clip": ["1", 1],
                         "strength_model": 0.8, "strength_clip": 0.8}},
        "3": {"class_type": "CLIPTextEncode",
              "inputs": {"clip": ["2", 1], "text": positive}},
        "4": {"class_type": "CLIPTextEncode",
              "inputs": {"clip": ["2", 1], "text": negative}},
        "5": {"class_type": "EmptyLatentImage",
              "inputs": {"batch_size": 1, "height": height, "width": width}},
        "6": {"class_type": "KSampler",
              "inputs": {"cfg": 7, "denoise": 1,
                         "latent_image": ["5", 0], "model": ["2", 0],
                         "negative": ["4", 0], "positive": ["3", 0],
                         "sampler_name": "euler_ancestral", "scheduler": "normal",
                         "seed": seed, "steps": 25}},
        "7": {"class_type": "VAEDecode",
              "inputs": {"samples": ["6", 0], "vae": ["1", 2]}},
        "8": {"class_type": "SaveImage",
              "inputs": {"filename_prefix": "rpg_gen", "images": ["7", 0]}}
    }

    try:
        cid = str(uuid.uuid4())
        resp = httpx.post(f"{COMFYUI_API}/prompt",
                          json={"prompt": workflow, "client_id": cid}, timeout=30)
        resp.raise_for_status()
        pid = resp.json()["prompt_id"]

        # Poll until done (max 5 min)
        for _ in range(150):
            time.sleep(2)
            r = httpx.get(f"{COMFYUI_API}/history/{pid}", timeout=15)
            if r.status_code == 200 and pid in r.json():
                result = r.json()[pid]
                outputs = result.get("outputs", {})
                for nid, nout in outputs.items():
                    for img_info in nout.get("images", []):
                        fname = img_info["filename"]
                        subfolder = img_info.get("subfolder", "")
                        # Download
                        params = {"filename": fname, "type": "output"}
                        if subfolder:
                            params["subfolder"] = subfolder
                        dl = httpx.get(f"{COMFYUI_API}/view", params=params, timeout=30)
                        dl.raise_for_status()
                        dest = RAW_DIR / out_name
                        dest.write_bytes(dl.content)
                        logger.info("  ✓ %s (%d KB)", out_name, len(dl.content) // 1024)
                        return True
                # Prompt completed but no images?
                logger.warning("  ⚠ Prompt completed but no images found")
                return False

        logger.error("  ✗ Timeout waiting for %s", name)
        return False

    except Exception as e:
        logger.error("  ✗ Failed %s: %s", name, e)
        return False


# ── Asset definitions ────────────────────────────────────────────────────

TILESETS = [
    ("grass_plains", "pixel art tileset, top-down RPG, lush green grass terrain, dirt patches, small flowers, 4x4 seamless tile grid, game asset, clean pixels, vibrant colors"),
    ("cobblestone_town", "pixel art tileset, top-down RPG, cobblestone street, town path, stone pavement variations, 4x4 seamless tile grid, game asset, clean pixels, medieval village"),
    ("forest_floor", "pixel art tileset, top-down RPG, dark forest floor, fallen leaves, tree roots, moss, mushrooms, 4x4 seamless tile grid, game asset, clean pixels"),
    ("water_river", "pixel art tileset, top-down RPG, water surface, river tiles, shore edges, ripples, 4x4 seamless tile grid, game asset, clean pixels, blue water"),
    ("cave_dungeon", "pixel art tileset, top-down RPG, dark cave floor, rocky terrain, stalactite shadows, crystals, 4x4 seamless tile grid, game asset, clean pixels"),
    ("wooden_buildings", "pixel art tileset, top-down RPG, medieval wooden building walls, rooftops, doors, windows, 4x4 tile grid, game asset, clean pixels, cozy village"),
]

PLAYER_CLASSES = [
    ("class_knight", "armored knight, steel plate armor, longsword, red cape"),
    ("class_ranger", "ranger archer, green leather armor, hooded cloak, longbow"),
    ("class_mage", "wizard mage, purple robes, pointed hat, glowing staff"),
    ("class_rogue", "rogue thief, dark leather armor, dual daggers, hood"),
    ("class_cleric", "holy cleric, white and gold robes, golden mace, holy symbol"),
]

DIRECTIONS = [("front", "front facing"), ("back", "back facing"), ("left", "left side"), ("right", "right side")]

NPCS = [
    ("npc_guildmaster_rowan", "grizzled man, eye patch, leather armor, guild tabard, war hammer, gray beard"),
    ("npc_blacksmith_ironbark", "dwarf blacksmith, massive arms, leather apron, braided brown beard, hammer"),
    ("npc_merchant_marta", "plump cheerful woman, colorful dress, apron, red hair in bun"),
    ("npc_innkeeper_bess", "tall woman innkeeper, practical dress, ale mug, brown hair"),
    ("npc_alchemist_elara", "ancient elf woman, silver hair, green robes, glowing eyes, potions"),
    ("npc_cleric_aldwin", "elderly monk, white robes, bald head, prayer beads, gentle"),
    ("npc_trainer_kira", "athletic woman warrior, leather armor, training sword, short dark hair"),
    ("npc_farmer_aldric", "weathered old farmer, straw hat, simple clothes, pitchfork"),
    ("npc_captain_holt", "stern guard captain, chainmail armor, guard tabard, sword, scarred"),
    ("npc_ranger_theron", "young wood elf, camouflage cloak, longbow, face paint"),
    ("npc_mysterious_stranger", "hooded mysterious figure, dark flowing cloak, face in shadow, magical glow"),
]

ENEMIES = [
    ("enemy_field_rat", "giant rat, brown fur, red eyes, bared teeth, aggressive, small"),
    ("enemy_slime_green", "green slime blob, translucent, bubbling, simple face"),
    ("enemy_goblin_scout", "goblin scout, green skin, leather scraps, rusty dagger, sneaky"),
    ("enemy_goblin_warrior", "goblin warrior, green skin, crude iron armor, wooden shield, sword"),
    ("enemy_goblin_shaman", "goblin shaman, green skin, bone necklace, wooden staff, magic sparks"),
    ("enemy_wolf", "gray wolf, bared fangs, prowling, thick fur, yellow eyes"),
    ("enemy_alpha_wolf", "large black alpha wolf, scarred face, red eyes, imposing"),
    ("enemy_skeleton", "skeleton warrior, rusty sword, tattered shield, glowing blue eyes"),
    ("enemy_bat_swarm", "swarm of bats, dark purple, red eyes, wings spread"),
    ("enemy_chieftain_grukk", "massive goblin chieftain, heavy armor, war club, crown of bones, boss creature"),
]

ITEM_ICONS = [
    ("wpn_rusty_sword", "rusty iron sword, chipped blade, worn grip", "weapon"),
    ("wpn_iron_sword", "iron longsword, polished blade, leather hilt", "weapon"),
    ("wpn_training_bow", "simple wooden shortbow, frayed string", "weapon"),
    ("wpn_oak_staff", "wooden wizard staff, small crystal top", "weapon"),
    ("wpn_iron_dagger", "iron dagger, sharp blade, dark grip", "weapon"),
    ("wpn_golden_mace", "golden holy mace, glowing, ornate", "weapon"),
    ("arm_leather_cap", "leather cap, brown helmet, stitched", "armor"),
    ("arm_iron_helm", "iron knight helmet, visor, metallic", "armor"),
    ("arm_cloth_robe", "purple wizard robe, magical shimmer", "armor"),
    ("arm_leather_vest", "brown leather vest, buckles, ranger", "armor"),
    ("arm_iron_shield", "round iron shield, guard emblem", "armor"),
    ("arm_chainmail", "chainmail shirt, silvery rings", "armor"),
    ("con_health_potion", "red health potion, glass bottle, glowing red", "consumable"),
    ("con_mana_potion", "blue mana potion, glass bottle, glowing blue", "consumable"),
    ("con_bread", "loaf of bread, golden brown, rustic", "food"),
    ("con_cooked_meat", "cooked meat on bone, grilled, steaming", "food"),
    ("con_antidote", "green antidote potion, small vial", "consumable"),
    ("mat_goblin_ear", "severed goblin ear, green, pointy", "material"),
    ("mat_wolf_pelt", "gray wolf pelt, folded fur", "material"),
    ("mat_iron_ore", "chunk of iron ore, dark metallic rock", "material"),
    ("mat_herb_silverleaf", "glowing silver herb leaf, magical plant", "material"),
    ("mat_bone_fragment", "bone fragment, white, cracked", "material"),
    ("tool_pickaxe", "iron pickaxe, wooden handle", "tool"),
    ("tool_fishing_rod", "simple fishing rod, wooden pole, hook", "tool"),
    ("currency_gold", "gold coin, shiny, stamped face", "currency"),
    ("item_guild_badge", "bronze guild badge, adventurer emblem", "quest item"),
    ("item_old_key", "rusty old iron key, ornate handle", "quest item"),
]

UI_ELEMENTS = [
    ("ui_heart_full", "red heart, full health, game UI, 16x16"),
    ("ui_heart_empty", "empty heart outline, gray, game UI, 16x16"),
    ("ui_mana_orb", "blue mana orb, glowing, game UI, 16x16"),
    ("ui_xp_star", "golden star, experience point, game UI, 16x16"),
    ("ui_coin_small", "small gold coin, game UI, 16x16"),
]


def main():
    total = 0
    success = 0
    failed = []

    # ── Phase 1: Tilesets ──
    print("\n" + "="*60)
    print("  PHASE 1: TILESETS (6)")
    print("="*60)
    for tid, prompt in TILESETS:
        total += 1
        ok = generate_one(tid, prompt, NEG_TILE,
                          seed=hash(tid) % (2**32), width=512, height=512,
                          out_name=f"{tid}_raw.png")
        if ok:
            success += 1
        else:
            failed.append(tid)

    # ── Phase 2: Player sprites (5 classes × 4 dirs × 3 frames = 60) ──
    print("\n" + "="*60)
    print("  PHASE 2: PLAYER SPRITES (60)")
    print("="*60)
    for cid, desc in PLAYER_CLASSES:
        for dir_name, dir_desc in DIRECTIONS:
            for frame in range(3):
                total += 1
                prompt = (f"pixel art RPG character sprite, {desc}, "
                          f"{dir_desc}, walking animation frame {frame+1} of 3, "
                          f"32x32 sprite, top-down RPG, centered, single character")
                ok = generate_one(
                    f"{cid}_{dir_name}_{frame}", prompt, NEG_SPRITE,
                    seed=hash(f"{cid}_{dir_name}") % (2**32) + frame,
                    width=256, height=256,
                    out_name=f"{cid}_{dir_name}_{frame}.png")
                if ok:
                    success += 1
                else:
                    failed.append(f"{cid}_{dir_name}_{frame}")

    # ── Phase 3: NPC sprites (11) ──
    print("\n" + "="*60)
    print("  PHASE 3: NPC SPRITES (11)")
    print("="*60)
    for nid, desc in NPCS:
        total += 1
        prompt = (f"pixel art RPG NPC character, {desc}, "
                  f"front facing, standing idle, 32x32 sprite, top-down RPG, centered")
        ok = generate_one(nid, prompt, NEG_SPRITE,
                          seed=hash(nid) % (2**32), width=256, height=256,
                          out_name=f"{nid}_front.png")
        if ok:
            success += 1
        else:
            failed.append(nid)

    # ── Phase 4: Enemy sprites (10) ──
    print("\n" + "="*60)
    print("  PHASE 4: ENEMY SPRITES (10)")
    print("="*60)
    for eid, desc in ENEMIES:
        total += 1
        prompt = (f"pixel art RPG monster, {desc}, "
                  f"front facing, battle stance, 32x32 sprite, top-down RPG, centered")
        ok = generate_one(eid, prompt, NEG_SPRITE,
                          seed=hash(eid) % (2**32), width=256, height=256,
                          out_name=f"{eid}_front.png")
        if ok:
            success += 1
        else:
            failed.append(eid)

    # ── Phase 5: Item icons (27) ──
    print("\n" + "="*60)
    print("  PHASE 5: ITEM ICONS (27)")
    print("="*60)
    for entry in ITEM_ICONS:
        iid, desc, itype = entry
        total += 1
        prompt = (f"pixel art item icon, {desc}, {itype}, "
                  f"RPG inventory icon, 32x32, transparent background, clean pixels, centered")
        ok = generate_one(iid, prompt, NEG_ICON,
                          seed=hash(iid) % (2**32), width=256, height=256,
                          out_name=f"{iid}_raw.png")
        if ok:
            success += 1
        else:
            failed.append(iid)

    # ── Phase 6: UI elements (5) ──
    print("\n" + "="*60)
    print("  PHASE 6: UI ELEMENTS (5)")
    print("="*60)
    for uid, desc in UI_ELEMENTS:
        total += 1
        prompt = f"pixel art, {desc}, clean crisp pixels, game UI element, centered, transparent background"
        ok = generate_one(uid, prompt, NEG_ICON,
                          seed=hash(uid) % (2**32), width=256, height=256,
                          out_name=f"{uid}_raw.png")
        if ok:
            success += 1
        else:
            failed.append(uid)

    # ── Summary ──
    print("\n" + "="*60)
    print(f"  GENERATION COMPLETE: {success}/{total} succeeded")
    if failed:
        print(f"  Failed ({len(failed)}): {', '.join(failed[:10])}{'...' if len(failed) > 10 else ''}")
    print("="*60)

    manifest = {
        "tilesets": [t[0] for t in TILESETS],
        "player_classes": [c[0] for c in PLAYER_CLASSES],
        "npcs": [n[0] for n in NPCS],
        "enemies": [e[0] for e in ENEMIES],
        "items": [i[0] for i in ITEM_ICONS],
        "ui": [u[0] for u in UI_ELEMENTS],
        "failed": failed,
        "total": total,
        "success": success,
    }
    (RAW_DIR / "generation_manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"\nManifest saved. Run postprocess_assets.py next.")


if __name__ == "__main__":
    main()
