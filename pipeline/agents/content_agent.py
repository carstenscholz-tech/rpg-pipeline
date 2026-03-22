"""Content generation agent using LM Studio local LLMs.

Generates game content (world bible, NPCs, quests, items, dialogue, maps)
as structured JSON files consumed by Godot at runtime.
"""

import json
import logging
import time
from pathlib import Path
from typing import Any

import httpx
from jinja2 import Environment, FileSystemLoader

from pipeline import config

logger = logging.getLogger(__name__)

# Jinja2 environment for prompt templates
_template_env = Environment(
    loader=FileSystemLoader(str(config.PROMPT_TEMPLATES_DIR)),
    keep_trailing_newline=True,
)


def _call_lm_studio(
    prompt: str,
    model: str = config.CONTENT_MODEL,
    temperature: float = 0.7,
    max_tokens: int = 4096,
    json_mode: bool = True,
) -> str:
    """Call LM Studio's OpenAI-compatible API."""
    payload: dict[str, Any] = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    if json_mode:
        payload["response_format"] = {"type": "json_object"}

    with httpx.Client(timeout=config.CONTENT_TIMEOUT) as client:
        resp = client.post(
            f"{config.LMSTUDIO_API}/chat/completions",
            json=payload,
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]


def _parse_json_response(text: str) -> dict:
    """Extract JSON from LLM response, handling markdown fences."""
    text = text.strip()
    if text.startswith("```"):
        # Strip markdown code fences
        lines = text.split("\n")
        lines = [l for l in lines if not l.strip().startswith("```")]
        text = "\n".join(lines)
    return json.loads(text)


def _render_template(template_name: str, **kwargs) -> str:
    """Render a Jinja2 prompt template."""
    tmpl = _template_env.get_template(template_name)
    return tmpl.render(**kwargs)


def _load_world_bible() -> dict:
    """Load the world bible if it exists."""
    path = config.DATA_DIR / "lore" / "world_bible.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {}


def _load_existing_content(content_type: str) -> list[dict]:
    """Load all existing content of a given type for context."""
    content_dir = config.DATA_DIR / content_type
    results = []
    if content_dir.exists():
        for f in content_dir.glob("*.json"):
            try:
                results.append(json.loads(f.read_text(encoding="utf-8")))
            except json.JSONDecodeError:
                logger.warning("Failed to parse %s", f)
    return results


def _save_content(content_type: str, content_id: str, data: dict) -> Path:
    """Save generated content to the data directory."""
    out_dir = config.DATA_DIR / content_type
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{content_id}.json"
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    logger.info("Saved %s to %s", content_id, path)
    return path


# ---------------------------------------------------------------------------
# Public generation methods
# ---------------------------------------------------------------------------


def generate_world_bible() -> dict:
    """Generate the master world bible (one-time bootstrap)."""
    prompt = _render_template("world_bible_gen.j2")
    logger.info("Generating world bible...")

    for attempt in range(config.MAX_RETRIES):
        try:
            raw = _call_lm_studio(prompt, model=config.CODE_MODEL, max_tokens=8192)
            data = _parse_json_response(raw)
            _save_content("lore", "world_bible", data)
            logger.info("World bible generated with %d regions", len(data.get("major_regions", [])))
            return data
        except (json.JSONDecodeError, httpx.HTTPError) as e:
            logger.warning("Attempt %d failed: %s", attempt + 1, e)
            time.sleep(2)

    raise RuntimeError("Failed to generate world bible after retries")


def generate_npc(description: str, region: str | None = None) -> dict:
    """Generate a single NPC."""
    world_bible = _load_world_bible()
    existing_npcs = _load_existing_content("npcs")

    prompt = _render_template(
        "npc_gen.j2",
        description=description,
        region=region,
        world_bible=world_bible,
        existing_npcs=existing_npcs,
    )
    logger.info("Generating NPC: %s", description)

    for attempt in range(config.MAX_RETRIES):
        try:
            raw = _call_lm_studio(prompt, model=config.CODE_MODEL)
            data = _parse_json_response(raw)
            npc_id = data.get("npc_id", description.lower().replace(" ", "_"))
            _save_content("npcs", npc_id, data)
            return data
        except (json.JSONDecodeError, httpx.HTTPError) as e:
            logger.warning("NPC gen attempt %d failed: %s", attempt + 1, e)
            time.sleep(2)

    raise RuntimeError(f"Failed to generate NPC '{description}' after retries")


def generate_quest(description: str, region: str | None = None) -> dict:
    """Generate a quest."""
    world_bible = _load_world_bible()
    existing_quests = _load_existing_content("quests")
    existing_npcs = _load_existing_content("npcs")

    prompt = _render_template(
        "quest_gen.j2",
        description=description,
        region=region,
        world_bible=world_bible,
        existing_quests=existing_quests,
        existing_npcs=existing_npcs,
    )
    logger.info("Generating quest: %s", description)

    for attempt in range(config.MAX_RETRIES):
        try:
            raw = _call_lm_studio(prompt, model=config.CODE_MODEL)
            data = _parse_json_response(raw)
            quest_id = data.get("quest_id", description.lower().replace(" ", "_"))
            _save_content("quests", quest_id, data)
            return data
        except (json.JSONDecodeError, httpx.HTTPError) as e:
            logger.warning("Quest gen attempt %d failed: %s", attempt + 1, e)
            time.sleep(2)

    raise RuntimeError(f"Failed to generate quest '{description}' after retries")


def generate_items(description: str, count: int = 10) -> list[dict]:
    """Generate a batch of items."""
    world_bible = _load_world_bible()
    existing_items = _load_existing_content("items")

    prompt = _render_template(
        "item_gen.j2",
        description=description,
        count=count,
        world_bible=world_bible,
        existing_items=existing_items,
    )
    logger.info("Generating %d items: %s", count, description)

    for attempt in range(config.MAX_RETRIES):
        try:
            raw = _call_lm_studio(prompt, model=config.CODE_MODEL, max_tokens=8192)
            data = _parse_json_response(raw)
            items = data.get("items", [data] if "item_id" in data else [])
            for item in items:
                item_id = item.get("item_id", "unknown")
                _save_content("items", item_id, item)
            return items
        except (json.JSONDecodeError, httpx.HTTPError) as e:
            logger.warning("Item gen attempt %d failed: %s", attempt + 1, e)
            time.sleep(2)

    raise RuntimeError(f"Failed to generate items '{description}' after retries")


def generate_dialogue(npc_id: str) -> dict:
    """Generate dialogue tree for an existing NPC."""
    npc_path = config.DATA_DIR / "npcs" / f"{npc_id}.json"
    if not npc_path.exists():
        raise FileNotFoundError(f"NPC '{npc_id}' not found at {npc_path}")

    npc_data = json.loads(npc_path.read_text(encoding="utf-8"))
    world_bible = _load_world_bible()
    existing_quests = _load_existing_content("quests")

    prompt = _render_template(
        "dialogue_gen.j2",
        npc_data=npc_data,
        world_bible=world_bible,
        existing_quests=existing_quests,
    )
    logger.info("Generating dialogue for NPC: %s", npc_id)

    for attempt in range(config.MAX_RETRIES):
        try:
            raw = _call_lm_studio(prompt, model=config.CONTENT_MODEL)
            data = _parse_json_response(raw)
            _save_content("dialogue", f"{npc_id}_dialogue", data)
            return data
        except (json.JSONDecodeError, httpx.HTTPError) as e:
            logger.warning("Dialogue gen attempt %d failed: %s", attempt + 1, e)
            time.sleep(2)

    raise RuntimeError(f"Failed to generate dialogue for '{npc_id}' after retries")


def generate_zone(description: str, region: str | None = None) -> dict:
    """Generate a zone/map definition."""
    world_bible = _load_world_bible()
    existing_maps = _load_existing_content("maps")
    existing_npcs = _load_existing_content("npcs")

    prompt = _render_template(
        "zone_gen.j2",
        description=description,
        region=region,
        world_bible=world_bible,
        existing_maps=existing_maps,
        existing_npcs=existing_npcs,
    )
    logger.info("Generating zone: %s", description)

    for attempt in range(config.MAX_RETRIES):
        try:
            raw = _call_lm_studio(prompt, model=config.CODE_MODEL, max_tokens=8192)
            data = _parse_json_response(raw)
            zone_id = data.get("zone_id", description.lower().replace(" ", "_"))
            _save_content("maps", zone_id, data)
            return data
        except (json.JSONDecodeError, httpx.HTTPError) as e:
            logger.warning("Zone gen attempt %d failed: %s", attempt + 1, e)
            time.sleep(2)

    raise RuntimeError(f"Failed to generate zone '{description}' after retries")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse
    import sys

    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    parser = argparse.ArgumentParser(description="Content generation agent")
    parser.add_argument(
        "--generate",
        choices=["world_bible", "npc", "quest", "items", "dialogue", "zone"],
        required=True,
    )
    parser.add_argument("--description", default="", help="Description of what to generate")
    parser.add_argument("--region", default=None, help="Region/zone context")
    parser.add_argument("--npc-id", default=None, help="NPC ID (for dialogue generation)")
    parser.add_argument("--count", type=int, default=10, help="Number of items to generate")
    args = parser.parse_args()

    try:
        if args.generate == "world_bible":
            result = generate_world_bible()
        elif args.generate == "npc":
            result = generate_npc(args.description, args.region)
        elif args.generate == "quest":
            result = generate_quest(args.description, args.region)
        elif args.generate == "items":
            result = generate_items(args.description, args.count)
        elif args.generate == "dialogue":
            if not args.npc_id:
                parser.error("--npc-id required for dialogue generation")
            result = generate_dialogue(args.npc_id)
        elif args.generate == "zone":
            result = generate_zone(args.description, args.region)

        print(json.dumps(result, indent=2))
    except Exception as e:
        logger.error("Generation failed: %s", e)
        sys.exit(1)
