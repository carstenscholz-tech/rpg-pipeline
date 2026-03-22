"""Task classifier — categorizes GitHub issues into art/content/code tasks."""

import json
import logging
from typing import Any

import httpx

from pipeline import config

logger = logging.getLogger(__name__)

CLASSIFICATION_PROMPT = """Classify this game development task for a top-down 2D RPG. Return JSON only.

Task title: {title}
Task body: {body}

Categories:
- "art": needs sprite/tileset/icon generation (visual assets via ComfyUI)
- "content": needs story/quest/NPC/item/dialogue/map data generation (JSON via LLM)
- "code": needs GDScript implementation or bug fix (code generation)
- "mixed": needs multiple categories

Output this exact JSON format:
{{
  "primary_category": "art|content|code|mixed",
  "subtasks": [
    {{
      "category": "art|content|code",
      "description": "specific description of what to generate",
      "priority": 1
    }}
  ],
  "art_specs": {{
    "asset_type": "character|tileset|item_icon|ui|null",
    "description": "what the art should look like",
    "entity_id": "snake_case_id for the asset"
  }},
  "content_specs": {{
    "content_type": "npc|quest|items|dialogue|zone|world_bible|null",
    "description": "what content to generate",
    "region": "region_id or null"
  }},
  "code_specs": {{
    "feature_type": "system|behavior|ui|integration|bugfix|null",
    "description": "what code to write"
  }}
}}

Rules:
- For "mixed" tasks, break into subtasks ordered by dependency (content first, then art, then code)
- Example: "Add a baker NPC" is mixed: content (NPC data + dialogue), art (baker sprite), code (shop integration)
- Example: "Fix inventory stacking bug" is pure code
- Example: "Create grass tileset" is pure art
- Example: "Write quest about dragon slaying" is content + code (quest data + quest handler)
- Priority 1 = do first, 2 = do second, etc.

Output ONLY the JSON."""


def classify(title: str, body: str = "") -> dict[str, Any]:
    """Classify a task by calling the local LLM."""
    prompt = CLASSIFICATION_PROMPT.format(title=title, body=body)

    for attempt in range(config.MAX_RETRIES):
        try:
            with httpx.Client(timeout=60) as client:
                resp = client.post(
                    f"{config.LMSTUDIO_API}/chat/completions",
                    json={
                        "model": config.CODE_MODEL,
                        "messages": [{"role": "user", "content": prompt}],
                        "temperature": 0.1,
                        "max_tokens": 2048,
                        "response_format": {"type": "json_object"},
                    },
                )
                resp.raise_for_status()
                text = resp.json()["choices"][0]["message"]["content"]

            # Parse JSON, stripping markdown fences if present
            text = text.strip()
            if text.startswith("```"):
                lines = text.split("\n")
                lines = [l for l in lines if not l.strip().startswith("```")]
                text = "\n".join(lines)

            result = json.loads(text)

            # Validate structure
            if "primary_category" not in result:
                logger.warning("Missing primary_category, retrying")
                continue
            if "subtasks" not in result:
                result["subtasks"] = [
                    {"category": result["primary_category"], "description": title, "priority": 1}
                ]

            logger.info("Classified '%s' as %s with %d subtasks",
                        title, result["primary_category"], len(result["subtasks"]))
            return result

        except (json.JSONDecodeError, httpx.HTTPError, KeyError) as e:
            logger.warning("Classification attempt %d failed: %s", attempt + 1, e)

    # Fallback: assume mixed
    logger.warning("Classification failed, defaulting to 'mixed'")
    return {
        "primary_category": "mixed",
        "subtasks": [
            {"category": "content", "description": title, "priority": 1},
            {"category": "art", "description": title, "priority": 2},
            {"category": "code", "description": title, "priority": 3},
        ],
        "art_specs": {"asset_type": None, "description": "", "entity_id": ""},
        "content_specs": {"content_type": None, "description": "", "region": None},
        "code_specs": {"feature_type": None, "description": ""},
    }


if __name__ == "__main__":
    import sys

    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    title = sys.argv[1] if len(sys.argv) > 1 else "Add a baker NPC to Lumbridge who sells bread"
    body = sys.argv[2] if len(sys.argv) > 2 else ""
    result = classify(title, body)
    print(json.dumps(result, indent=2))
