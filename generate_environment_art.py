#!/usr/bin/env python3
"""Generate all environmental, portrait, VFX, and world map art via ComfyUI."""

import httpx
import time
import os
import sys
import json
import random

COMFYUI_BASE = "http://127.0.0.1:8188"
OUTPUT_DIR = "D:/Claude/rpg-pipeline/assets/raw"
POLL_INTERVAL = 2
MAX_WAIT = 300  # 5 minutes per image
QUEUE_POLL_INTERVAL = 30

os.makedirs(OUTPUT_DIR, exist_ok=True)


def build_workflow(positive, negative, seed, w, h):
    return {
        '1': {'class_type': 'CheckpointLoaderSimple', 'inputs': {'ckpt_name': 'sd_xl_base_1.0.safetensors'}},
        '2': {'class_type': 'LoraLoader', 'inputs': {'lora_name': 'pixel-art-xl.safetensors', 'model': ['1', 0], 'clip': ['1', 1], 'strength_model': 0.9, 'strength_clip': 0.9}},
        '3': {'class_type': 'CLIPTextEncode', 'inputs': {'clip': ['2', 1], 'text': positive}},
        '4': {'class_type': 'CLIPTextEncode', 'inputs': {'clip': ['2', 1], 'text': negative}},
        '5': {'class_type': 'EmptyLatentImage', 'inputs': {'batch_size': 1, 'height': h, 'width': w}},
        '6': {'class_type': 'KSampler', 'inputs': {'cfg': 7.5, 'denoise': 1, 'latent_image': ['5', 0], 'model': ['2', 0], 'negative': ['4', 0], 'positive': ['3', 0], 'sampler_name': 'euler_ancestral', 'scheduler': 'normal', 'seed': seed, 'steps': 30}},
        '7': {'class_type': 'VAEDecode', 'inputs': {'samples': ['6', 0], 'vae': ['1', 2]}},
        '8': {'class_type': 'SaveImage', 'inputs': {'filename_prefix': 'rpg_env', 'images': ['7', 0]}}
    }


def build_workflow_custom(positive, negative, seed, w, h, steps=30, cfg=7.5):
    wf = build_workflow(positive, negative, seed, w, h)
    wf['6']['inputs']['steps'] = steps
    wf['6']['inputs']['cfg'] = cfg
    return wf


def wait_for_queue_clear(client):
    """Wait until the ComfyUI queue has no pending items."""
    while True:
        try:
            resp = client.get(f"{COMFYUI_BASE}/queue")
            resp.raise_for_status()
            data = resp.json()
            pending = len(data.get("queue_pending", []))
            running = len(data.get("queue_running", []))
            if pending == 0 and running == 0:
                print("Queue is clear. Starting environment generation.")
                return
            total = pending + running
            print(f"Waiting for sprite queue to clear... ({total} pending)")
            time.sleep(QUEUE_POLL_INTERVAL)
        except Exception as e:
            print(f"Error checking queue: {e}")
            time.sleep(QUEUE_POLL_INTERVAL)


def submit_prompt(client, workflow):
    """Submit a workflow to ComfyUI and return the prompt_id."""
    payload = {"prompt": workflow}
    resp = client.post(f"{COMFYUI_BASE}/prompt", json=payload)
    resp.raise_for_status()
    return resp.json()["prompt_id"]


def wait_for_completion(client, prompt_id):
    """Poll /history/{prompt_id} until the job is complete. Returns output info."""
    start = time.time()
    while time.time() - start < MAX_WAIT:
        try:
            resp = client.get(f"{COMFYUI_BASE}/history/{prompt_id}")
            resp.raise_for_status()
            data = resp.json()
            if prompt_id in data:
                outputs = data[prompt_id].get("outputs", {})
                return outputs
        except Exception:
            pass
        time.sleep(POLL_INTERVAL)
    raise TimeoutError(f"Timed out waiting for prompt {prompt_id}")


def download_image(client, filename, output_path):
    """Download an image from ComfyUI /view endpoint and save it."""
    resp = client.get(f"{COMFYUI_BASE}/view", params={"filename": filename, "type": "output"})
    resp.raise_for_status()
    with open(output_path, "wb") as f:
        f.write(resp.content)
    return len(resp.content)


def generate_image(client, name, positive, negative, w, h, index, total, steps=30, cfg=7.5):
    """Full pipeline: submit, wait, download, save."""
    seed = random.randint(0, 2**32 - 1)
    workflow = build_workflow_custom(positive, negative, seed, w, h, steps, cfg)

    try:
        prompt_id = submit_prompt(client, workflow)
        outputs = wait_for_completion(client, prompt_id)

        # Find the SaveImage node output
        filename = None
        for node_id, node_out in outputs.items():
            if "images" in node_out:
                for img in node_out["images"]:
                    filename = img.get("filename")
                    break
            if filename:
                break

        if not filename:
            print(f"[{index}/{total}] FAIL {name} (no output image found)")
            return False

        output_path = os.path.join(OUTPUT_DIR, f"{name}.png")
        size_bytes = download_image(client, filename, output_path)
        size_kb = size_bytes / 1024
        print(f"[{index}/{total}] OK {name} ({size_kb:.0f}KB)")
        return True

    except Exception as e:
        print(f"[{index}/{total}] FAIL {name} ({e})")
        return False


# ── Asset Definitions ──────────────────────────────────────────────────────────

ENV_NEGATIVE = "blurry, anti-aliased, smooth gradients, 3D render, realistic, photograph, noise, text, watermark, border, frame, people, characters, complex background"

ENVIRONMENT_OBJECTS = [
    ("env_oak_tree", "pixel art, 16-bit RPG top-down view, single large oak tree with green canopy, brown trunk, standing alone on solid green background, clean crisp pixels, game asset, isolated object"),
    ("env_pine_tree", "pixel art, 16-bit RPG top-down view, single tall pine tree, dark green conifer, standing alone on solid green background, clean crisp pixels, game asset, isolated object"),
    ("env_dead_tree", "pixel art, 16-bit RPG top-down view, single dead leafless tree with gnarled branches, dark bark, standing alone on solid dark green background, clean crisp pixels, game asset"),
    ("env_bush_green", "pixel art, 16-bit RPG top-down view, small green leafy bush shrub, standing alone on solid green background, clean crisp pixels, game asset, isolated object"),
    ("env_bush_flowers", "pixel art, 16-bit RPG top-down view, small flowering bush with colorful flowers, standing alone on solid green background, clean crisp pixels, game asset"),
    ("env_tall_grass", "pixel art, 16-bit RPG top-down view, patch of tall wild grass, swaying, on solid green background, clean crisp pixels, game asset"),
    ("env_mushroom_cluster", "pixel art, 16-bit RPG top-down view, cluster of red and brown mushrooms, on solid dark green background, clean crisp pixels, game asset"),
    ("env_rock_large", "pixel art, 16-bit RPG top-down view, single large gray boulder rock, mossy, on solid green background, clean crisp pixels, game asset, isolated object"),
    ("env_rock_small", "pixel art, 16-bit RPG top-down view, small gray stone rock, on solid green background, clean crisp pixels, game asset, isolated object"),
    ("env_crystal_blue", "pixel art, 16-bit RPG top-down view, glowing blue crystal formation, magical, on solid dark background, clean crisp pixels, game asset"),
    ("env_wooden_fence", "pixel art, 16-bit RPG top-down view, section of wooden fence, rustic, on solid green background, clean crisp pixels, game asset"),
    ("env_stone_wall", "pixel art, 16-bit RPG top-down view, section of stone brick wall, medieval, on solid green background, clean crisp pixels, game asset"),
    ("env_well", "pixel art, 16-bit RPG top-down view, stone water well with bucket and rope, medieval village, on solid green background, clean crisp pixels, game asset"),
    ("env_barrel", "pixel art, 16-bit RPG top-down view, single wooden barrel, medieval, on solid green background, clean crisp pixels, game asset, isolated object"),
    ("env_crate", "pixel art, 16-bit RPG top-down view, single wooden crate box, medieval, on solid green background, clean crisp pixels, game asset, isolated object"),
    ("env_campfire", "pixel art, 16-bit RPG top-down view, campfire with logs and orange flames, warm glow, on solid dark background, clean crisp pixels, game asset"),
    ("env_signpost", "pixel art, 16-bit RPG top-down view, wooden signpost with arrow, medieval, on solid green background, clean crisp pixels, game asset"),
    ("env_bridge_wooden", "pixel art, 16-bit RPG top-down view, small wooden bridge over water, planks, on solid blue-green background, clean crisp pixels, game asset"),
    ("env_tombstone", "pixel art, 16-bit RPG top-down view, old stone tombstone gravestone, cracked, on solid dark green background, clean crisp pixels, game asset"),
    ("env_lamp_post", "pixel art, 16-bit RPG top-down view, medieval iron lamp post with warm glowing light, on solid dark background, clean crisp pixels, game asset"),
    ("env_market_stall", "pixel art, 16-bit RPG top-down view, wooden market stall with awning, medieval village, on solid green background, clean crisp pixels, game asset"),
    ("env_fountain", "pixel art, 16-bit RPG top-down view, stone fountain with flowing water, town center, on solid gray background, clean crisp pixels, game asset"),
]

PORTRAIT_NEGATIVE = "blurry, anti-aliased, smooth gradients, 3D render, realistic, photograph, noise, text, watermark, full body, legs, feet, multiple people"

PORTRAITS = [
    ("portrait_guildmaster_rowan", "pixel art portrait, 16-bit RPG style, close-up face and shoulders, grizzled middle-aged man with eye patch, gray beard, weathered face, leather armor collar, stern but kind expression, warm lighting"),
    ("portrait_blacksmith_ironbark", "pixel art portrait, 16-bit RPG style, close-up face and shoulders, stocky dwarf with massive braided brown beard, soot on face, leather apron strap visible, gruff expression"),
    ("portrait_merchant_marta", "pixel art portrait, 16-bit RPG style, close-up face and shoulders, cheerful plump woman with red hair in bun, rosy cheeks, warm smile, colorful dress collar"),
    ("portrait_innkeeper_bess", "pixel art portrait, 16-bit RPG style, close-up face and shoulders, tall woman with brown hair, friendly smile, practical brown dress, warm tavern lighting"),
    ("portrait_alchemist_elara", "pixel art portrait, 16-bit RPG style, close-up face and shoulders, ancient elf woman with silver hair, glowing green eyes, mysterious, green robes"),
    ("portrait_cleric_aldwin", "pixel art portrait, 16-bit RPG style, close-up face and shoulders, elderly bald monk, gentle kind eyes, white robes, prayer beads around neck, serene"),
    ("portrait_trainer_kira", "pixel art portrait, 16-bit RPG style, close-up face and shoulders, fierce athletic woman with short dark hair, determined expression, leather armor, battle scars"),
    ("portrait_farmer_aldric", "pixel art portrait, 16-bit RPG style, close-up face and shoulders, weathered old farmer with straw hat, worried expression, sun-tanned wrinkled face"),
    ("portrait_captain_holt", "pixel art portrait, 16-bit RPG style, close-up face and shoulders, stern military man with scar across cheek, chainmail collar, guard tabard, no-nonsense expression"),
    ("portrait_ranger_theron", "pixel art portrait, 16-bit RPG style, close-up face and shoulders, young wood elf with face paint, alert bright eyes, camouflage hood, forest background hints"),
    ("portrait_mysterious_stranger", "pixel art portrait, 16-bit RPG style, close-up face and shoulders, hooded figure with face in deep shadow, only glowing eyes visible, mysterious dark cloak, magical aura"),
]

VFX_NEGATIVE = "blurry, 3D render, realistic, photograph, text, watermark, characters, people"

VFX_ITEMS = [
    ("vfx_slash", "pixel art, sprite sheet of sword slash effect, 4 frames horizontal, white and yellow slash arc, clean pixels, on solid black background, game VFX, 16-bit"),
    ("vfx_magic_bolt", "pixel art, sprite sheet of magic projectile, 4 frames horizontal, blue glowing energy bolt, clean pixels, on solid black background, game VFX, 16-bit"),
    ("vfx_heal", "pixel art, sprite sheet of healing effect, 4 frames horizontal, green sparkling particles rising upward, clean pixels, on solid black background, game VFX"),
    ("vfx_fire", "pixel art, sprite sheet of fire spell effect, 4 frames horizontal, orange and red flames, clean pixels, on solid black background, game VFX, 16-bit"),
    ("vfx_hit_spark", "pixel art, sprite sheet of hit impact spark, 4 frames horizontal, white and yellow star burst, clean pixels, on solid black background, game VFX"),
    ("vfx_poison", "pixel art, sprite sheet of poison effect, 4 frames horizontal, green toxic bubbles and drips, clean pixels, on solid black background, game VFX"),
    ("vfx_levelup", "pixel art, sprite sheet of level up celebration effect, 4 frames horizontal, golden light column with sparkles, clean pixels, on solid black background, game VFX"),
    ("vfx_loot_sparkle", "pixel art, sprite sheet of loot sparkle effect, 4 frames horizontal, golden twinkling stars, clean pixels, on solid black background, game VFX"),
]

WORLDMAP = [
    ("worldmap_aethermoor", "pixel art world map, 16-bit RPG overworld, top-down fantasy continent map, Aethermoor kingdom, central town Hearthholm in meadows, Oldroot Forest to the north with dark trees, Thornweald swamp to the northeast, mountains to the west with snow peaks, coastline to the south and east with blue ocean, river running through center, roads connecting locations, compass rose, clean crisp pixels, retro game map, SNES style, labeled regions"),
]

WORLDMAP_NEGATIVE = "blurry, 3D, realistic, photograph, text labels, modern, watermark"


def main():
    total = len(ENVIRONMENT_OBJECTS) + len(PORTRAITS) + len(VFX_ITEMS) + len(WORLDMAP)
    print(f"RPG Art Generation Pipeline")
    print(f"Total images to generate: {total}")
    print(f"Output directory: {OUTPUT_DIR}")
    print(f"ComfyUI API: {COMFYUI_BASE}")
    print("=" * 60)

    client = httpx.Client(timeout=60.0)

    # Check and wait for queue to clear
    print("\nChecking ComfyUI queue...")
    wait_for_queue_clear(client)
    print()

    successes = 0
    failures = 0
    idx = 0

    # ── Environment Objects (512x512) ──
    print("--- Environmental Objects (22 items, 512x512) ---")
    for name, prompt in ENVIRONMENT_OBJECTS:
        idx += 1
        ok = generate_image(client, name, prompt, ENV_NEGATIVE, 512, 512, idx, total)
        if ok:
            successes += 1
        else:
            failures += 1

    # ── NPC Portraits (512x512) ──
    print("\n--- NPC Dialogue Portraits (11 items, 512x512) ---")
    for name, prompt in PORTRAITS:
        idx += 1
        ok = generate_image(client, name, prompt, PORTRAIT_NEGATIVE, 512, 512, idx, total)
        if ok:
            successes += 1
        else:
            failures += 1

    # ── VFX (512x512) ──
    print("\n--- Combat Visual Effects (8 items, 512x512) ---")
    for name, prompt in VFX_ITEMS:
        idx += 1
        ok = generate_image(client, name, prompt, VFX_NEGATIVE, 512, 512, idx, total)
        if ok:
            successes += 1
        else:
            failures += 1

    # ── World Map (1024x1024) ──
    print("\n--- World Map (1 item, 1024x1024) ---")
    for name, prompt in WORLDMAP:
        idx += 1
        ok = generate_image(client, name, prompt, WORLDMAP_NEGATIVE, 1024, 1024, idx, total, steps=35, cfg=8.0)
        if ok:
            successes += 1
        else:
            failures += 1

    # ── Summary ──
    print("\n" + "=" * 60)
    print(f"GENERATION COMPLETE")
    print(f"  Successes: {successes}/{total}")
    print(f"  Failures:  {failures}/{total}")
    print(f"  Output:    {OUTPUT_DIR}")
    print("=" * 60)

    client.close()
    sys.exit(0 if failures == 0 else 1)


if __name__ == "__main__":
    main()
