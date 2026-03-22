"""Review agent — validates generated content, art, and code."""

import json
import logging
import subprocess
from pathlib import Path

import jsonschema
from PIL import Image

from pipeline import config

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Content validation
# ---------------------------------------------------------------------------

def _load_schema(schema_name: str) -> dict:
    path = config.SCHEMAS_DIR / f"{schema_name}_schema.json"
    return json.loads(path.read_text(encoding="utf-8"))


def validate_json_schema(data: dict, schema_name: str) -> list[str]:
    """Validate data against a JSON schema. Returns list of errors."""
    try:
        schema = _load_schema(schema_name)
        jsonschema.validate(data, schema)
        return []
    except jsonschema.ValidationError as e:
        return [f"Schema validation: {e.message}"]
    except FileNotFoundError:
        return [f"Schema '{schema_name}' not found"]


def validate_referential_integrity() -> list[str]:
    """Check that all cross-references in data/ are valid."""
    errors = []

    # Load all content
    npcs = _load_all("npcs")
    quests = _load_all("quests")
    items = _load_all("items")
    maps = _load_all("maps")
    dialogues = _load_all("dialogue")

    npc_ids = {n.get("npc_id") for n in npcs}
    item_ids = {i.get("item_id") for i in items}
    quest_ids = {q.get("quest_id") for q in quests}
    zone_ids = {m.get("zone_id") for m in maps}
    dialogue_ids = {d.get("dialogue_id") for d in dialogues}

    # Check quest references
    for quest in quests:
        qid = quest.get("quest_id", "?")
        for prereq in quest.get("prerequisites", []):
            if prereq not in quest_ids:
                errors.append(f"Quest '{qid}' references unknown prerequisite '{prereq}'")
        for step in quest.get("steps", []):
            if step.get("target_npc") and step["target_npc"] not in npc_ids:
                errors.append(f"Quest '{qid}' step references unknown NPC '{step['target_npc']}'")
        for reward_item in quest.get("rewards", {}).get("items", []):
            if reward_item.get("item_id") and reward_item["item_id"] not in item_ids:
                errors.append(f"Quest '{qid}' rewards unknown item '{reward_item['item_id']}'")

    # Check NPC references
    for npc in npcs:
        nid = npc.get("npc_id", "?")
        for quest_given in npc.get("quests_given", []):
            if quest_given not in quest_ids:
                errors.append(f"NPC '{nid}' gives unknown quest '{quest_given}'")
        if npc.get("dialogue_tree_id") and npc["dialogue_tree_id"] not in dialogue_ids:
            # Dialogue might not exist yet — warn, don't error
            logger.warning("NPC '%s' references missing dialogue '%s'", nid, npc["dialogue_tree_id"])

    # Check item drop sources
    for item in items:
        iid = item.get("item_id", "?")
        for drop in item.get("drop_sources", []):
            enemy_id = drop.get("enemy_id", "")
            # Enemies might be defined in zone data, skip strict check for now
            if drop.get("drop_rate", 0) > 1 or drop.get("drop_rate", 0) < 0:
                errors.append(f"Item '{iid}' has invalid drop rate from '{enemy_id}'")

    return errors


def _load_all(content_type: str) -> list[dict]:
    content_dir = config.DATA_DIR / content_type
    results = []
    if content_dir.exists():
        for f in content_dir.glob("*.json"):
            try:
                results.append(json.loads(f.read_text(encoding="utf-8")))
            except json.JSONDecodeError:
                logger.warning("Failed to parse %s", f)
    return results


# ---------------------------------------------------------------------------
# Art validation
# ---------------------------------------------------------------------------

def validate_sprite(image_path: Path, expected_size: tuple[int, int] | None = None) -> list[str]:
    """Validate a sprite image."""
    errors = []
    try:
        img = Image.open(image_path)
    except Exception as e:
        return [f"Cannot open image: {e}"]

    # Dimension check
    if expected_size and img.size != expected_size:
        errors.append(f"Expected {expected_size}, got {img.size}")

    # Color count check
    if img.mode in ("P",):
        color_count = len(img.getcolors(maxcolors=256) or [])
    else:
        quantized = img.quantize(colors=256)
        colors = quantized.getcolors(maxcolors=256)
        color_count = len(colors) if colors else 0

    if color_count > config.MAX_PALETTE_COLORS:
        errors.append(f"Too many colors: {color_count} (max {config.MAX_PALETTE_COLORS})")

    # Transparency check (for sprites, not tilesets)
    if img.mode == "RGBA":
        alpha = img.getchannel("A")
        pixels = list(alpha.getdata())
        transparent_count = sum(1 for p in pixels if p == 0)
        total = len(pixels)
        if transparent_count == 0:
            errors.append("No transparent pixels found (expected transparent background)")
        if transparent_count == total:
            errors.append("Image is entirely transparent")

    # Not empty check
    if img.size[0] == 0 or img.size[1] == 0:
        errors.append("Image has zero dimensions")

    return errors


def validate_sprite_sheet(
    image_path: Path,
    rows: int = 4,
    cols: int = 3,
    cell_size: int = 32,
) -> list[str]:
    """Validate a sprite sheet has the right grid dimensions."""
    errors = []
    try:
        img = Image.open(image_path)
    except Exception as e:
        return [f"Cannot open image: {e}"]

    expected_w = cols * cell_size
    expected_h = rows * cell_size
    if img.size != (expected_w, expected_h):
        errors.append(f"Sheet should be {expected_w}x{expected_h}, got {img.size}")

    return errors


# ---------------------------------------------------------------------------
# Code validation
# ---------------------------------------------------------------------------

def validate_gdscript(script_path: Path) -> list[str]:
    """Validate GDScript syntax using Godot headless mode."""
    errors = []
    try:
        result = subprocess.run(
            [config.GODOT_EXECUTABLE, "--headless", "--check-only", "--script", str(script_path)],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=str(config.PROJECT_ROOT),
        )
        if result.returncode != 0:
            errors.append(f"GDScript syntax error: {result.stderr.strip()}")
    except FileNotFoundError:
        errors.append(f"Godot executable not found at '{config.GODOT_EXECUTABLE}'")
    except subprocess.TimeoutExpired:
        errors.append("GDScript validation timed out")
    return errors


# ---------------------------------------------------------------------------
# Full validation pass
# ---------------------------------------------------------------------------

class ReviewResult:
    def __init__(self):
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.files_validated: int = 0

    @property
    def passed(self) -> bool:
        return len(self.errors) == 0

    @property
    def summary(self) -> str:
        status = "PASSED" if self.passed else "FAILED"
        parts = [f"Review {status}: {self.files_validated} files validated"]
        if self.errors:
            parts.append(f"Errors ({len(self.errors)}):")
            parts.extend(f"  - {e}" for e in self.errors)
        if self.warnings:
            parts.append(f"Warnings ({len(self.warnings)}):")
            parts.extend(f"  - {w}" for w in self.warnings)
        return "\n".join(parts)


def validate_all(changed_files: list[Path] | None = None) -> ReviewResult:
    """Run all validation checks on changed files or everything."""
    result = ReviewResult()

    # Validate JSON content
    schema_map = {
        "npcs": "npc",
        "quests": "quest",
        "items": "item",
    }

    for content_type, schema_name in schema_map.items():
        content_dir = config.DATA_DIR / content_type
        if not content_dir.exists():
            continue
        for f in content_dir.glob("*.json"):
            if changed_files and f not in changed_files:
                continue
            try:
                data = json.loads(f.read_text(encoding="utf-8"))
                errors = validate_json_schema(data, schema_name)
                result.errors.extend(errors)
                result.files_validated += 1
            except json.JSONDecodeError as e:
                result.errors.append(f"Invalid JSON in {f.name}: {e}")

    # Referential integrity
    integrity_errors = validate_referential_integrity()
    result.errors.extend(integrity_errors)

    # Validate sprites
    for sprite_dir in [
        config.ASSETS_DIR / "sprites" / "characters",
        config.ASSETS_DIR / "sprites" / "npcs",
        config.ASSETS_DIR / "sprites" / "enemies",
    ]:
        if not sprite_dir.exists():
            continue
        for img_path in sprite_dir.glob("*_sheet.png"):
            if changed_files and img_path not in changed_files:
                continue
            errors = validate_sprite_sheet(img_path)
            result.errors.extend(errors)
            result.files_validated += 1

    for icon_path in (config.ASSETS_DIR / "items" / "icons").glob("*.png"):
        if changed_files and icon_path not in changed_files:
            continue
        errors = validate_sprite(icon_path)
        # Icon validation is advisory, not blocking
        result.warnings.extend(errors)
        result.files_validated += 1

    # Validate GDScript files
    for gd_file in config.SCRIPTS_DIR.rglob("*.gd"):
        if changed_files and gd_file not in changed_files:
            continue
        errors = validate_gdscript(gd_file)
        result.errors.extend(errors)
        result.files_validated += 1

    return result


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    result = validate_all()
    print(result.summary)
