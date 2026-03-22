"""Art generation agent using ComfyUI API.

Generates pixel art game assets: character sprites, tilesets, item icons, UI elements.
Communicates with ComfyUI via its REST/WebSocket API.
"""

import json
import logging
import time
import uuid
from pathlib import Path
from typing import Any

import httpx
import websocket

from pipeline import config

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# ComfyUI API helpers
# ---------------------------------------------------------------------------

def _queue_prompt(workflow: dict) -> str:
    """Submit a workflow to ComfyUI and return the prompt ID."""
    payload = {"prompt": workflow, "client_id": str(uuid.uuid4())}
    with httpx.Client(timeout=30) as client:
        resp = client.post(f"{config.COMFYUI_API}/prompt", json=payload)
        resp.raise_for_status()
        return resp.json()["prompt_id"]


def _wait_for_completion(prompt_id: str, timeout: int = config.ART_TIMEOUT) -> dict:
    """Poll ComfyUI history until the prompt completes."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        with httpx.Client(timeout=10) as client:
            resp = client.get(f"{config.COMFYUI_API}/history/{prompt_id}")
            if resp.status_code == 200:
                history = resp.json()
                if prompt_id in history:
                    return history[prompt_id]
        time.sleep(2)
    raise TimeoutError(f"ComfyUI prompt {prompt_id} did not complete in {timeout}s")


def _download_image(filename: str, subfolder: str = "", output_dir: Path | None = None) -> Path:
    """Download a generated image from ComfyUI."""
    params = {"filename": filename}
    if subfolder:
        params["subfolder"] = subfolder
    params["type"] = "output"

    with httpx.Client(timeout=30) as client:
        resp = client.get(f"{config.COMFYUI_API}/view", params=params)
        resp.raise_for_status()

    dest_dir = output_dir or config.RAW_OUTPUT_DIR
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / filename
    dest.write_bytes(resp.content)
    logger.info("Downloaded %s to %s", filename, dest)
    return dest


def _load_workflow(workflow_name: str) -> dict:
    """Load a ComfyUI workflow JSON template."""
    path = config.WORKFLOWS_DIR / workflow_name
    return json.loads(path.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Workflow parameter injection
# ---------------------------------------------------------------------------

def _inject_params(workflow: dict, params: dict[str, Any]) -> dict:
    """Inject parameters into a ComfyUI workflow template.

    Looks for placeholder strings like {{positive_prompt}}, {{seed}}, etc.
    in node inputs and replaces them.
    """
    workflow_str = json.dumps(workflow)
    for key, value in params.items():
        placeholder = "{{" + key + "}}"
        if isinstance(value, str):
            # Escape JSON special chars in string values
            escaped = json.dumps(value)[1:-1]  # Strip outer quotes
            workflow_str = workflow_str.replace(placeholder, escaped)
        else:
            workflow_str = workflow_str.replace(f'"{placeholder}"', json.dumps(value))
            workflow_str = workflow_str.replace(placeholder, str(value))
    return json.loads(workflow_str)


# ---------------------------------------------------------------------------
# High-level generation methods
# ---------------------------------------------------------------------------

def generate_character_sprite(
    character_id: str,
    description: str,
    seed: int | None = None,
) -> list[Path]:
    """Generate a 4-direction character sprite set.

    Returns list of paths to generated images (4 directions × 3 frames = 12 images).
    """
    if seed is None:
        seed = hash(character_id) % (2**32)

    directions = [
        ("down", "front facing, walking forward, PixelartFSS"),
        ("up", "back facing, walking away, PixelartBSS"),
        ("left", "left facing, walking left, PixelartLSS"),
        ("right", "right facing, walking right, PixelartRSS"),
    ]

    generated = []
    workflow_template = _load_workflow("character_sprite.json")

    for dir_name, dir_prompt in directions:
        for frame in range(3):
            positive = (
                f"pixel art, top-down RPG character sprite, {description}, "
                f"{dir_prompt}, 32x32 sprite, clean pixel grid, "
                f"transparent background, game asset, centered"
            )
            negative = (
                "blurry, anti-aliased, smooth, 3D, realistic, photograph, "
                "noise, text, watermark, signature, multiple characters"
            )

            params = {
                "positive_prompt": positive,
                "negative_prompt": negative,
                "seed": seed + frame + hash(dir_name) % 1000,
                "width": config.SPRITE_GEN_RESOLUTION,
                "height": config.SPRITE_GEN_RESOLUTION,
            }

            workflow = _inject_params(workflow_template, params)

            try:
                prompt_id = _queue_prompt(workflow)
                result = _wait_for_completion(prompt_id)

                # Extract output images from result
                outputs = result.get("outputs", {})
                for node_id, node_output in outputs.items():
                    for image_info in node_output.get("images", []):
                        filename = image_info["filename"]
                        subfolder = image_info.get("subfolder", "")
                        dest = _download_image(filename, subfolder)
                        # Rename to standard convention
                        final_name = f"{character_id}_{dir_name}_{frame}.png"
                        final_path = config.RAW_OUTPUT_DIR / final_name
                        dest.rename(final_path)
                        generated.append(final_path)

            except Exception as e:
                logger.error("Failed to generate %s_%s_%d: %s", character_id, dir_name, frame, e)

    logger.info("Generated %d/%d sprite frames for %s", len(generated), 12, character_id)
    return generated


def generate_tileset(
    tileset_id: str,
    terrain_type: str,
    seed: int | None = None,
) -> Path | None:
    """Generate a tileset grid image."""
    if seed is None:
        seed = hash(tileset_id) % (2**32)

    positive = (
        f"pixel art tileset, top-down view, {terrain_type} terrain, "
        f"seamless, RPG game tiles, 32x32 grid, 4x4 tile variations, "
        f"game asset, clean pixels"
    )
    negative = (
        "blurry, anti-aliased, smooth, 3D, realistic, photograph, "
        "noise, text, watermark, characters, people"
    )

    try:
        workflow = _load_workflow("tileset_gen.json")
        workflow = _inject_params(workflow, {
            "positive_prompt": positive,
            "negative_prompt": negative,
            "seed": seed,
            "width": config.TILESET_GEN_RESOLUTION,
            "height": config.TILESET_GEN_RESOLUTION,
        })

        prompt_id = _queue_prompt(workflow)
        result = _wait_for_completion(prompt_id)

        outputs = result.get("outputs", {})
        for node_id, node_output in outputs.items():
            for image_info in node_output.get("images", []):
                filename = image_info["filename"]
                subfolder = image_info.get("subfolder", "")
                dest = _download_image(filename, subfolder)
                final_path = config.RAW_OUTPUT_DIR / f"{tileset_id}_raw.png"
                dest.rename(final_path)
                logger.info("Generated tileset: %s", final_path)
                return final_path

    except Exception as e:
        logger.error("Failed to generate tileset %s: %s", tileset_id, e)
        return None


def generate_item_icon(
    item_id: str,
    item_name: str,
    item_type: str = "weapon",
    seed: int | None = None,
) -> Path | None:
    """Generate a single item icon."""
    if seed is None:
        seed = hash(item_id) % (2**32)

    positive = (
        f"pixel art item icon, {item_name}, {item_type}, "
        f"RPG inventory icon, 32x32, transparent background, "
        f"clean pixels, game asset, centered, single item"
    )
    negative = (
        "blurry, anti-aliased, smooth, 3D, realistic, photograph, "
        "noise, text, watermark, multiple items, character"
    )

    try:
        workflow = _load_workflow("item_icon.json")
        workflow = _inject_params(workflow, {
            "positive_prompt": positive,
            "negative_prompt": negative,
            "seed": seed,
            "width": config.SPRITE_GEN_RESOLUTION,
            "height": config.SPRITE_GEN_RESOLUTION,
        })

        prompt_id = _queue_prompt(workflow)
        result = _wait_for_completion(prompt_id)

        outputs = result.get("outputs", {})
        for node_id, node_output in outputs.items():
            for image_info in node_output.get("images", []):
                filename = image_info["filename"]
                subfolder = image_info.get("subfolder", "")
                dest = _download_image(filename, subfolder)
                final_path = config.RAW_OUTPUT_DIR / f"{item_id}_icon_raw.png"
                dest.rename(final_path)
                logger.info("Generated item icon: %s", final_path)
                return final_path

    except Exception as e:
        logger.error("Failed to generate item icon %s: %s", item_id, e)
        return None


# ---------------------------------------------------------------------------
# Batch operations
# ---------------------------------------------------------------------------

def generate_character_sprites_batch(characters: list[dict]) -> dict[str, list[Path]]:
    """Generate sprites for multiple characters sequentially.

    Each character dict should have: character_id, description.
    Sequential to avoid VRAM conflicts.
    """
    results = {}
    for char in characters:
        cid = char["character_id"]
        desc = char["description"]
        paths = generate_character_sprite(cid, desc)
        results[cid] = paths
    return results


def generate_item_icons_batch(items: list[dict]) -> dict[str, Path | None]:
    """Generate icons for multiple items sequentially."""
    results = {}
    for item in items:
        iid = item["item_id"]
        name = item.get("name", iid)
        itype = item.get("type", "item")
        path = generate_item_icon(iid, name, itype)
        results[iid] = path
    return results


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse

    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    parser = argparse.ArgumentParser(description="Art generation agent")
    parser.add_argument(
        "--generate",
        choices=["character", "tileset", "item_icon"],
        required=True,
    )
    parser.add_argument("--id", required=True, help="Asset ID")
    parser.add_argument("--description", default="", help="Description for generation")
    parser.add_argument("--terrain", default="grass", help="Terrain type (for tilesets)")
    parser.add_argument("--seed", type=int, default=None, help="Random seed")
    args = parser.parse_args()

    if args.generate == "character":
        paths = generate_character_sprite(args.id, args.description or args.id, args.seed)
        print(f"Generated {len(paths)} frames")
    elif args.generate == "tileset":
        path = generate_tileset(args.id, args.terrain, args.seed)
        print(f"Generated: {path}")
    elif args.generate == "item_icon":
        path = generate_item_icon(args.id, args.description or args.id, seed=args.seed)
        print(f"Generated: {path}")
