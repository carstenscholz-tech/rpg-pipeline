"""Code generation agent using LM Studio + Claude API fallback.

Generates GDScript code for Godot 4 game systems using a template+infill approach.
Simple tasks use local LLM via LM Studio; complex multi-file features fall back to Claude.
"""

import json
import logging
import re
import subprocess
from pathlib import Path
from typing import Any

import anthropic
import httpx
from jinja2 import Environment, FileSystemLoader

from pipeline import config

logger = logging.getLogger(__name__)

_template_env = Environment(
    loader=FileSystemLoader(str(config.GDSCRIPT_TEMPLATES_DIR)),
    keep_trailing_newline=True,
)

_prompt_env = Environment(
    loader=FileSystemLoader(str(config.PROMPT_TEMPLATES_DIR)),
    keep_trailing_newline=True,
)


# ---------------------------------------------------------------------------
# LLM backends
# ---------------------------------------------------------------------------

def _call_lm_studio(prompt: str, max_tokens: int = 4096) -> str:
    """Call local LLM via LM Studio for simple code generation."""
    with httpx.Client(timeout=config.CODE_TIMEOUT) as client:
        resp = client.post(
            f"{config.LMSTUDIO_API}/chat/completions",
            json={
                "model": config.CODE_MODEL,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.3,  # Lower temp for code
                "max_tokens": max_tokens,
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]


def _call_claude(prompt: str, max_tokens: int = 4096) -> str:
    """Call Claude API for complex multi-file code generation."""
    client = anthropic.Anthropic(api_key=config.ANTHROPIC_API_KEY)
    message = client.messages.create(
        model=config.CLAUDE_MODEL,
        max_tokens=max_tokens,
        messages=[{"role": "user", "content": prompt}],
    )
    return message.content[0].text


# ---------------------------------------------------------------------------
# Code parsing
# ---------------------------------------------------------------------------

def _parse_code_blocks(response: str) -> list[dict[str, str]]:
    """Extract file path + code pairs from LLM response.

    Expected format:
    ### FILE: res://path/to/file.gd
    ```gdscript
    code here
    ```
    """
    files = []
    pattern = r"###\s*FILE:\s*(.+?)\n```(?:gdscript|gd)?\n(.*?)```"
    matches = re.findall(pattern, response, re.DOTALL)

    for file_path, code in matches:
        file_path = file_path.strip()
        # Convert res:// path to absolute path
        if file_path.startswith("res://"):
            file_path = str(config.PROJECT_ROOT / file_path[6:])
        files.append({"path": file_path, "code": code.strip()})

    # Fallback: if no ### FILE markers, treat as single code block
    if not files:
        code_match = re.search(r"```(?:gdscript|gd)?\n(.*?)```", response, re.DOTALL)
        if code_match:
            files.append({"path": "", "code": code_match.group(1).strip()})

    return files


# ---------------------------------------------------------------------------
# Context assembly
# ---------------------------------------------------------------------------

def _get_existing_systems_summary() -> str:
    """Summarize existing GDScript systems for context."""
    summaries = []
    scripts_dir = config.SCRIPTS_DIR
    if not scripts_dir.exists():
        return "No existing systems."

    for gd_file in scripts_dir.rglob("*.gd"):
        rel = gd_file.relative_to(config.PROJECT_ROOT)
        # Read first 20 lines for summary
        lines = gd_file.read_text(encoding="utf-8").split("\n")[:20]
        header = "\n".join(lines)
        summaries.append(f"--- {rel} ---\n{header}\n")

    return "\n".join(summaries) if summaries else "No existing systems."


def _get_project_structure() -> str:
    """Get a tree of key project directories."""
    lines = []
    for d in [config.SCRIPTS_DIR, config.SCENES_DIR, config.DATA_DIR]:
        if d.exists():
            for f in sorted(d.rglob("*")):
                if f.is_file():
                    lines.append(str(f.relative_to(config.PROJECT_ROOT)))
    return "\n".join(lines[:50]) if lines else "Empty project."


# ---------------------------------------------------------------------------
# Code generation
# ---------------------------------------------------------------------------

def _build_code_prompt(task_description: str, related_files: list[Path] | None = None) -> str:
    """Build a comprehensive prompt for GDScript generation."""
    existing = _get_existing_systems_summary()
    structure = _get_project_structure()

    related_code = ""
    if related_files:
        for f in related_files:
            if f.exists():
                content = f.read_text(encoding="utf-8")
                rel = f.relative_to(config.PROJECT_ROOT) if str(f).startswith(str(config.PROJECT_ROOT)) else f
                related_code += f"\n--- {rel} ---\n{content}\n"

    return f"""You are a Godot 4 GDScript expert. Generate code for the following feature.

PROJECT CONTEXT:
- Godot 4.x, GDScript (not C#)
- Top-down 2D RPG
- Data-driven: game content is in JSON files loaded by GameData autoload
- Signal-based architecture: use EventBus autoload for cross-system communication

EXISTING SYSTEMS:
{existing}

PROJECT STRUCTURE:
{structure}

{f"RELATED CODE:{related_code}" if related_code else ""}

TASK: {task_description}

OUTPUT REQUIREMENTS:
- Output complete, runnable .gd files
- Use typed variables (var x: int = 0)
- Follow snake_case naming convention
- Emit signals via EventBus for UI updates
- Load data from GameData autoload, never hardcode game data
- For each file, write "### FILE: res://path/to/file.gd" then a gdscript code block

Output ONLY the code files, no other explanation.
"""


def generate_code(
    task_description: str,
    complexity: str = "auto",
    related_files: list[Path] | None = None,
) -> list[dict[str, str]]:
    """Generate GDScript code for a task.

    Args:
        task_description: What to implement.
        complexity: "simple" for local LLM, "complex" for Claude, "auto" to decide.
        related_files: Existing files to include as context.

    Returns:
        List of {path, code} dicts.
    """
    prompt = _build_code_prompt(task_description, related_files)

    # Auto-detect complexity
    if complexity == "auto":
        word_count = len(task_description.split())
        has_multiple_systems = any(
            kw in task_description.lower()
            for kw in ["system", "manager", "refactor", "integrate", "overhaul"]
        )
        complexity = "complex" if word_count > 50 or has_multiple_systems else "simple"

    for attempt in range(config.MAX_RETRIES):
        try:
            if complexity == "complex" and config.ANTHROPIC_API_KEY:
                logger.info("Using Claude API for complex task (attempt %d)", attempt + 1)
                response = _call_claude(prompt)
            else:
                logger.info("Using LM Studio for code generation (attempt %d)", attempt + 1)
                response = _call_lm_studio(prompt)

            files = _parse_code_blocks(response)
            if not files:
                logger.warning("No code blocks found in response")
                continue

            return files

        except Exception as e:
            logger.warning("Code gen attempt %d failed: %s", attempt + 1, e)

    raise RuntimeError(f"Failed to generate code for: {task_description}")


def render_template(template_name: str, **kwargs) -> str:
    """Render a GDScript Jinja2 template with parameters."""
    tmpl = _template_env.get_template(template_name)
    return tmpl.render(**kwargs)


# ---------------------------------------------------------------------------
# Write and validate
# ---------------------------------------------------------------------------

def write_code_files(files: list[dict[str, str]]) -> list[Path]:
    """Write generated code files to disk."""
    written = []
    for f in files:
        path = Path(f["path"])
        if not path.is_absolute():
            path = config.PROJECT_ROOT / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f["code"], encoding="utf-8")
        logger.info("Wrote %s", path)
        written.append(path)
    return written


def validate_code(file_path: Path) -> list[str]:
    """Validate GDScript syntax using Godot headless mode."""
    errors = []
    try:
        result = subprocess.run(
            [config.GODOT_EXECUTABLE, "--headless", "--check-only", "--script", str(file_path)],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=str(config.PROJECT_ROOT),
        )
        if result.returncode != 0:
            errors.append(result.stderr.strip())
    except FileNotFoundError:
        logger.warning("Godot not found, skipping syntax validation")
    except subprocess.TimeoutExpired:
        errors.append("Validation timed out")
    return errors


def generate_and_write(
    task_description: str,
    complexity: str = "auto",
    related_files: list[Path] | None = None,
) -> tuple[list[Path], list[str]]:
    """Generate code, write it, and validate. Returns (written_paths, errors)."""
    files = generate_code(task_description, complexity, related_files)
    written = write_code_files(files)

    all_errors = []
    for path in written:
        if path.suffix == ".gd":
            errors = validate_code(path)
            all_errors.extend(errors)

    return written, all_errors


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse
    import sys

    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    parser = argparse.ArgumentParser(description="Code generation agent")
    parser.add_argument("--task", required=True, help="Task description")
    parser.add_argument("--complexity", choices=["simple", "complex", "auto"], default="auto")
    parser.add_argument("--dry-run", action="store_true", help="Print code without writing")
    args = parser.parse_args()

    try:
        files = generate_code(args.task, args.complexity)
        for f in files:
            print(f"\n### FILE: {f['path']}")
            print(f["code"])

        if not args.dry_run:
            written, errors = generate_and_write(args.task, args.complexity)
            if errors:
                print(f"\nValidation errors: {errors}")
                sys.exit(1)
            print(f"\nWrote {len(written)} files successfully")
    except Exception as e:
        logger.error("Failed: %s", e)
        sys.exit(1)
