"""Central configuration for the RPG pipeline."""

from pathlib import Path
import os

# === Paths ===
PROJECT_ROOT = Path("D:/Claude/rpg-pipeline")
ASSETS_DIR = PROJECT_ROOT / "assets"
DATA_DIR = PROJECT_ROOT / "data"
RAW_OUTPUT_DIR = ASSETS_DIR / "raw"
SCENES_DIR = PROJECT_ROOT / "scenes"
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
TESTS_DIR = PROJECT_ROOT / "tests"

# Pipeline internals
PIPELINE_DIR = PROJECT_ROOT / "pipeline"
WORKFLOWS_DIR = PIPELINE_DIR / "comfyui" / "workflows"
REFERENCE_POSES_DIR = PIPELINE_DIR / "comfyui" / "reference_poses"
PROMPT_TEMPLATES_DIR = PIPELINE_DIR / "templates" / "prompts"
GDSCRIPT_TEMPLATES_DIR = PIPELINE_DIR / "templates" / "gdscript"
SCHEMAS_DIR = PIPELINE_DIR / "schemas"

# === ComfyUI ===
COMFYUI_API = "http://127.0.0.1:8188"
COMFYUI_ROOT = Path("D:/ComfyUI_windows_portable/ComfyUI")

# === LM Studio ===
LMSTUDIO_API = "http://localhost:1234/v1"
CONTENT_MODEL = "glm-4.7-flash-uncensored"  # Creative content (story, dialogue)
CODE_MODEL = "qwen3.5-35b-a3b"  # Structured output + code

# === Claude API (fallback for complex code) ===
CLAUDE_MODEL = "claude-sonnet-4-20250514"
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")

# === Godot ===
GODOT_EXECUTABLE = "D:/Godot/Godot_v4.6.1-stable_win64_console.exe"

# === GitHub ===
GITHUB_REPO = os.environ.get("GITHUB_REPO", "carstenscholz-tech/rpg-pipeline")
PIPELINE_READY_LABEL = "pipeline:ready"
PIPELINE_IN_PROGRESS_LABEL = "pipeline:in-progress"
PIPELINE_DONE_LABEL = "pipeline:done"
PIPELINE_NEEDS_HUMAN_LABEL = "pipeline:needs-human"

# === Generation Settings ===
SPRITE_SIZE = 32  # Pixels per game tile/sprite
SPRITE_GEN_RESOLUTION = 256  # ComfyUI generation resolution
TILESET_GEN_RESOLUTION = 512  # For tileset grid generation
MAX_PALETTE_COLORS = 32
MAX_RETRIES = 3

# === Timeouts (seconds) ===
CONTENT_TIMEOUT = 300  # 5 min
ART_TIMEOUT = 900  # 15 min
CODE_TIMEOUT = 600  # 10 min

# === Polling ===
POLL_INTERVAL_SECONDS = 300  # 5 min
