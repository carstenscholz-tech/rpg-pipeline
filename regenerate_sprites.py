"""
Regenerate all character sprites, NPC sprites, enemy sprites, and item icons
using ComfyUI with improved prompts. Tilesets are NOT regenerated.
"""

import httpx
import json
import time
import os
import sys
from pathlib import Path
from datetime import datetime

COMFYUI_URL = "http://127.0.0.1:8188"
OUTPUT_DIR = Path("D:/Claude/rpg-pipeline/assets/raw")
POLL_INTERVAL = 2  # seconds
TIMEOUT = 300  # 5 minutes max per image
BASE_SEED = 42000

# ─── Negative prompt (shared) ───────────────────────────────────────────────
NEGATIVE = (
    "blurry, anti-aliased, smooth gradients, 3D render, realistic, photograph, "
    "noise, text, watermark, multiple characters, border, frame, background details, "
    "scene, landscape, complex background, multiple items"
)

# ─── Player classes ──────────────────────────────────────────────────────────
PLAYER_CLASSES = {
    "class_knight": "armored knight with steel plate armor, red cape, sword and shield",
    "class_ranger": "ranger archer with green leather armor, hooded cloak, longbow and quiver",
    "class_mage": "wizard mage with purple robes, pointed hat, glowing magical staff",
    "class_rogue": "rogue thief with dark leather armor, dual daggers, hood and mask",
    "class_cleric": "holy cleric with white and gold robes, golden mace, holy symbol pendant",
}

DIRECTIONS = {
    "front": "front facing, walking toward viewer",
    "back": "back facing, walking away",
    "left": "left side profile, walking left",
    "right": "right side profile, walking right",
}
FRAMES_PER_DIRECTION = 3

# ─── NPCs ────────────────────────────────────────────────────────────────────
NPCS = {
    "npc_guildmaster_rowan": "grizzled middle-aged man with eye patch, leather armor with guild tabard, gray beard, war hammer",
    "npc_blacksmith_ironbark": "stocky dwarf blacksmith with massive arms, leather apron, braided brown beard, smithing hammer",
    "npc_merchant_marta": "plump cheerful woman merchant with colorful dress, apron with pockets, red hair in bun",
    "npc_innkeeper_bess": "tall woman innkeeper with practical brown dress, ale mug in hand, brown hair",
    "npc_alchemist_elara": "ancient elf woman sage with silver hair, flowing green robes, glowing eyes, potion bottle",
    "npc_cleric_aldwin": "elderly bald monk in white robes, prayer beads, gentle expression, holy symbol",
    "npc_trainer_kira": "athletic woman warrior with leather armor, training sword, short dark hair, fierce look",
    "npc_farmer_aldric": "weathered old farmer with straw hat, simple clothes, pitchfork, sun-tanned",
    "npc_captain_holt": "stern guard captain with chainmail armor, guard tabard, sword at hip, scarred face",
    "npc_ranger_theron": "young wood elf with camouflage cloak, longbow, face paint, alert eyes",
    "npc_mysterious_stranger": "tall hooded mysterious figure with dark flowing cloak, face hidden in shadow, faint magical glow",
}

# ─── Enemies ─────────────────────────────────────────────────────────────────
ENEMIES = {
    "enemy_field_rat": "giant rat with brown fur, red eyes, bared teeth, small aggressive creature",
    "enemy_slime_green": "green slime blob, translucent, bubbling, simple cute face",
    "enemy_goblin_scout": "small goblin with green skin, leather scraps, rusty dagger, sneaky",
    "enemy_goblin_warrior": "goblin warrior with green skin, crude iron armor, wooden shield, short sword",
    "enemy_goblin_shaman": "goblin shaman with green skin, bone necklace, wooden staff, magical purple sparks",
    "enemy_wolf": "gray wolf with bared fangs, prowling stance, thick fur, yellow eyes",
    "enemy_alpha_wolf": "large black alpha wolf, scarred face, glowing red eyes, imposing",
    "enemy_skeleton": "skeleton warrior with rusty sword, tattered shield, glowing blue eyes",
    "enemy_bat_swarm": "dark purple bat with red eyes, wings spread wide",
    "enemy_chieftain_grukk": "massive goblin chieftain with heavy crude armor, bone crown, war club, scarred green skin",
}

# ─── Items ───────────────────────────────────────────────────────────────────
ITEMS = {
    "wpn_rusty_sword": "rusty iron sword with chipped blade and worn leather grip",
    "wpn_iron_sword": "polished iron longsword with leather wrapped hilt",
    "wpn_training_bow": "simple wooden shortbow with frayed string",
    "wpn_oak_staff": "wooden wizard staff with small glowing crystal on top",
    "wpn_iron_dagger": "sharp iron dagger with dark leather grip",
    "wpn_golden_mace": "ornate golden holy mace with glowing aura",
    "arm_leather_cap": "brown leather cap helmet, stitched",
    "arm_iron_helm": "iron knight helmet with visor, metallic shine",
    "arm_cloth_robe": "folded purple wizard robe with magical shimmer",
    "arm_leather_vest": "brown leather vest armor with buckles",
    "arm_iron_shield": "round iron shield with town guard emblem",
    "arm_chainmail": "silvery chainmail shirt with metal rings",
    "con_health_potion": "single red health potion glass bottle with cork, glowing red liquid",
    "con_mana_potion": "single blue mana potion glass bottle with cork, glowing blue liquid",
    "con_bread": "golden brown loaf of rustic bread",
    "con_cooked_meat": "grilled meat on bone, steaming",
    "con_antidote": "small green antidote vial with bright green liquid",
    "mat_goblin_ear": "severed green pointy goblin ear",
    "mat_wolf_pelt": "folded gray wolf fur pelt",
    "mat_iron_ore": "chunk of dark metallic iron ore rock",
    "mat_herb_silverleaf": "glowing silver magical herb leaf",
    "mat_bone_fragment": "white cracked bone fragment",
    "tool_pickaxe": "iron pickaxe with wooden handle",
    "tool_fishing_rod": "simple wooden fishing rod with line and hook",
    "currency_gold": "shiny gold coin with stamped face",
    "item_guild_badge": "bronze adventurer guild badge emblem pin",
    "item_old_key": "rusty ornate iron key",
}

# ─── UI Elements ─────────────────────────────────────────────────────────────
UI_ELEMENTS = {
    "ui_heart_full": "red pixel heart, full health, game UI icon",
    "ui_heart_empty": "gray empty heart outline, game UI icon",
    "ui_mana_orb": "blue glowing mana orb, game UI icon",
    "ui_xp_star": "golden star, experience point, game UI icon",
    "ui_coin_small": "small gold coin, game UI icon",
}


def build_workflow(positive: str, negative: str, seed: int) -> dict:
    """Build the ComfyUI workflow dict."""
    return {
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": "sd_xl_base_1.0.safetensors"},
        },
        "2": {
            "class_type": "LoraLoader",
            "inputs": {
                "lora_name": "pixel-art-xl.safetensors",
                "model": ["1", 0],
                "clip": ["1", 1],
                "strength_model": 0.9,
                "strength_clip": 0.9,
            },
        },
        "3": {
            "class_type": "CLIPTextEncode",
            "inputs": {"clip": ["2", 1], "text": positive},
        },
        "4": {
            "class_type": "CLIPTextEncode",
            "inputs": {"clip": ["2", 1], "text": negative},
        },
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {"batch_size": 1, "height": 512, "width": 512},
        },
        "6": {
            "class_type": "KSampler",
            "inputs": {
                "cfg": 7.5,
                "denoise": 1,
                "latent_image": ["5", 0],
                "model": ["2", 0],
                "negative": ["4", 0],
                "positive": ["3", 0],
                "sampler_name": "euler_ancestral",
                "scheduler": "normal",
                "seed": seed,
                "steps": 30,
            },
        },
        "7": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["6", 0], "vae": ["1", 2]},
        },
        "8": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": "rpg_v2", "images": ["7", 0]},
        },
    }


def queue_prompt(client: httpx.Client, workflow: dict) -> str:
    """Submit a workflow to ComfyUI and return the prompt_id."""
    payload = {"prompt": workflow}
    resp = client.post(f"{COMFYUI_URL}/prompt", json=payload, timeout=30)
    resp.raise_for_status()
    return resp.json()["prompt_id"]


def wait_for_completion(client: httpx.Client, prompt_id: str) -> dict:
    """Poll /history/{prompt_id} until the job completes. Returns history entry."""
    start = time.time()
    while time.time() - start < TIMEOUT:
        resp = client.get(f"{COMFYUI_URL}/history/{prompt_id}", timeout=30)
        resp.raise_for_status()
        data = resp.json()
        if prompt_id in data:
            return data[prompt_id]
        time.sleep(POLL_INTERVAL)
    raise TimeoutError(f"Prompt {prompt_id} did not complete within {TIMEOUT}s")


def download_image(client: httpx.Client, history_entry: dict, output_path: Path):
    """Download the generated image from ComfyUI and save it."""
    outputs = history_entry.get("outputs", {})
    # Find the SaveImage node output (node "8")
    images_info = None
    for node_id, node_output in outputs.items():
        if "images" in node_output:
            images_info = node_output["images"]
            break
    if not images_info or len(images_info) == 0:
        raise RuntimeError("No images found in workflow output")

    img = images_info[0]
    filename = img["filename"]
    subfolder = img.get("subfolder", "")
    img_type = img.get("type", "output")

    params = {"filename": filename, "subfolder": subfolder, "type": img_type}
    resp = client.get(f"{COMFYUI_URL}/view", params=params, timeout=60)
    resp.raise_for_status()

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(resp.content)
    return len(resp.content)


def generate_image(
    client: httpx.Client,
    positive: str,
    negative: str,
    seed: int,
    output_path: Path,
    label: str,
    index: int,
    total: int,
) -> bool:
    """Generate a single image end-to-end. Returns True on success."""
    try:
        workflow = build_workflow(positive, negative, seed)
        prompt_id = queue_prompt(client, workflow)
        history = wait_for_completion(client, prompt_id)
        size_bytes = download_image(client, history, output_path)
        size_kb = size_bytes / 1024
        print(f"  [OK] {label} ({size_kb:.0f}KB) [{index}/{total}]")
        return True
    except Exception as e:
        print(f"  [FAIL] {label} FAILED: {e} [{index}/{total}]")
        return False


def build_generation_list() -> list[dict]:
    """Build the full list of generation tasks."""
    tasks = []
    seed_counter = BASE_SEED

    # ── Player classes: 4 directions x 3 frames = 12 per class ───────────
    for cls_name, cls_desc in PLAYER_CLASSES.items():
        for direction, dir_prompt in DIRECTIONS.items():
            for frame in range(FRAMES_PER_DIRECTION):
                positive = (
                    f"pixel art, 16-bit SNES RPG style, single character sprite, "
                    f"{cls_desc}, {dir_prompt}, standing idle pose, chibi proportions, "
                    f"centered on solid magenta background, clean crisp pixels, "
                    f"no anti-aliasing, retro game character, isolated sprite"
                )
                filename = f"{cls_name}_{direction}_{frame}.png"
                label = f"{cls_name}_{direction}_{frame}"
                seed = seed_counter + frame
                tasks.append({
                    "positive": positive,
                    "seed": seed,
                    "output": OUTPUT_DIR / filename,
                    "label": label,
                    "category": "player",
                    "asset_name": cls_name,
                })
            seed_counter += 100

    # ── NPCs: 1 front-facing each ────────────────────────────────────────
    for npc_name, npc_desc in NPCS.items():
        positive = (
            f"pixel art, 16-bit SNES RPG style, single character sprite, "
            f"{npc_desc}, front facing, standing idle pose, chibi proportions, "
            f"centered on solid green background, clean crisp pixels, "
            f"no anti-aliasing, retro game character, isolated sprite"
        )
        filename = f"{npc_name}_front.png"
        tasks.append({
            "positive": positive,
            "seed": seed_counter,
            "output": OUTPUT_DIR / filename,
            "label": f"{npc_name}_front",
            "category": "npc",
            "asset_name": npc_name,
        })
        seed_counter += 100

    # ── Enemies: 1 front-facing each ─────────────────────────────────────
    for enemy_name, enemy_desc in ENEMIES.items():
        positive = (
            f"pixel art, 16-bit SNES RPG style, single monster sprite, "
            f"{enemy_desc}, front facing, battle stance, chibi proportions, "
            f"centered on solid dark gray background, clean crisp pixels, "
            f"retro game monster, isolated sprite"
        )
        filename = f"{enemy_name}_front.png"
        tasks.append({
            "positive": positive,
            "seed": seed_counter,
            "output": OUTPUT_DIR / filename,
            "label": f"{enemy_name}_front",
            "category": "enemy",
            "asset_name": enemy_name,
        })
        seed_counter += 100

    # ── Items: 1 each ────────────────────────────────────────────────────
    for item_name, item_desc in ITEMS.items():
        positive = (
            f"pixel art item icon, {item_desc}, single item centered on solid black background, "
            f"16-bit retro RPG inventory icon, clean crisp pixels, no anti-aliasing, "
            f"isolated object, simple"
        )
        filename = f"{item_name}_raw.png"
        tasks.append({
            "positive": positive,
            "seed": seed_counter,
            "output": OUTPUT_DIR / filename,
            "label": f"{item_name}_raw",
            "category": "item",
            "asset_name": item_name,
        })
        seed_counter += 100

    # ── UI elements: 1 each ──────────────────────────────────────────────
    for ui_name, ui_desc in UI_ELEMENTS.items():
        positive = (
            f"pixel art item icon, {ui_desc}, single item centered on solid black background, "
            f"16-bit retro RPG inventory icon, clean crisp pixels, no anti-aliasing, "
            f"isolated object, simple"
        )
        filename = f"{ui_name}_raw.png"
        tasks.append({
            "positive": positive,
            "seed": seed_counter,
            "output": OUTPUT_DIR / filename,
            "label": f"{ui_name}_raw",
            "category": "ui",
            "asset_name": ui_name,
        })
        seed_counter += 100

    return tasks


def update_manifest(tasks: list[dict], successes: int, failures: int):
    """Write/update generation_manifest.json."""
    manifest_path = OUTPUT_DIR / "generation_manifest.json"

    # Load existing manifest to preserve tileset info
    existing = {}
    if manifest_path.exists():
        try:
            existing = json.loads(manifest_path.read_text(encoding="utf-8"))
        except Exception:
            pass

    # Keep tilesets from existing manifest
    tilesets = existing.get("tilesets", [])

    # Build asset lists from tasks
    player_classes = sorted(set(t["asset_name"] for t in tasks if t["category"] == "player"))
    npcs = sorted(set(t["asset_name"] for t in tasks if t["category"] == "npc"))
    enemies = sorted(set(t["asset_name"] for t in tasks if t["category"] == "enemy"))
    items = sorted(set(t["asset_name"] for t in tasks if t["category"] == "item"))
    ui_elements = sorted(set(t["asset_name"] for t in tasks if t["category"] == "ui"))

    generated_files = [t["output"].name for t in tasks]

    manifest = {
        "tilesets": tilesets,
        "player_classes": player_classes,
        "npcs": npcs,
        "enemies": enemies,
        "items": items,
        "ui_elements": ui_elements,
        "generation_info": {
            "date": datetime.now().isoformat(),
            "workflow": "SDXL + pixel-art-xl LoRA",
            "resolution": "512x512",
            "total_generated": successes,
            "total_failed": failures,
            "total_attempted": successes + failures,
        },
        "generated_files": sorted(generated_files),
    }

    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"\nManifest updated: {manifest_path}")


def main():
    print("=" * 60)
    print("RPG Sprite Regeneration (v2 - improved prompts)")
    print("=" * 60)

    # Check ComfyUI connectivity
    try:
        with httpx.Client() as client:
            resp = client.get(f"{COMFYUI_URL}/system_stats", timeout=10)
            resp.raise_for_status()
            print(f"ComfyUI connected at {COMFYUI_URL}")
    except Exception as e:
        print(f"ERROR: Cannot connect to ComfyUI at {COMFYUI_URL}: {e}")
        sys.exit(1)

    # Build task list
    tasks = build_generation_list()
    total = len(tasks)
    print(f"\nTotal images to generate: {total}")
    print(f"  Player sprites: {sum(1 for t in tasks if t['category'] == 'player')}")
    print(f"  NPC sprites:    {sum(1 for t in tasks if t['category'] == 'npc')}")
    print(f"  Enemy sprites:  {sum(1 for t in tasks if t['category'] == 'enemy')}")
    print(f"  Item icons:     {sum(1 for t in tasks if t['category'] == 'item')}")
    print(f"  UI elements:    {sum(1 for t in tasks if t['category'] == 'ui')}")
    print()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    successes = 0
    failures = 0
    failed_labels = []

    current_category = None
    with httpx.Client() as client:
        for i, task in enumerate(tasks, 1):
            # Print category headers
            if task["category"] != current_category:
                current_category = task["category"]
                header = {
                    "player": "Player Class Sprites",
                    "npc": "NPC Sprites",
                    "enemy": "Enemy Sprites",
                    "item": "Item Icons",
                    "ui": "UI Elements",
                }[current_category]
                print(f"\n--- {header} ---")

            ok = generate_image(
                client,
                task["positive"],
                NEGATIVE,
                task["seed"],
                task["output"],
                task["label"],
                i,
                total,
            )
            if ok:
                successes += 1
            else:
                failures += 1
                failed_labels.append(task["label"])

    # Update manifest
    update_manifest(tasks, successes, failures)

    # Final summary
    print("\n" + "=" * 60)
    print("GENERATION COMPLETE")
    print(f"  Successes: {successes}/{total}")
    print(f"  Failures:  {failures}/{total}")
    if failed_labels:
        print(f"\n  Failed assets:")
        for label in failed_labels:
            print(f"    - {label}")
    print("=" * 60)


if __name__ == "__main__":
    main()
