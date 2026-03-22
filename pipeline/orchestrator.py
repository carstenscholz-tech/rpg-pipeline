"""Main orchestrator — polls GitHub Issues, dispatches agents, commits results.

This is the heart of the automated pipeline. It:
1. Polls GitHub for issues labeled 'pipeline:ready'
2. Classifies each task
3. Dispatches to content/art/code agents in dependency order
4. Validates outputs via review agent
5. Commits to git and updates the issue
"""

import json
import logging
import subprocess
import sys
import time
from pathlib import Path

from pipeline import config
from pipeline import task_classifier
from pipeline.agents import art_agent, code_agent, content_agent, review_agent
from pipeline.comfyui import postprocess

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# GitHub helpers (via gh CLI)
# ---------------------------------------------------------------------------

def _gh(args: list[str], check: bool = True) -> str:
    """Run a gh CLI command and return stdout."""
    result = subprocess.run(
        ["gh"] + args,
        capture_output=True,
        text=True,
        cwd=str(config.PROJECT_ROOT),
    )
    if check and result.returncode != 0:
        logger.error("gh command failed: %s\nstderr: %s", " ".join(args), result.stderr)
        raise subprocess.CalledProcessError(result.returncode, "gh")
    return result.stdout.strip()


def get_ready_issues() -> list[dict]:
    """Get all issues labeled pipeline:ready."""
    output = _gh([
        "issue", "list",
        "--label", config.PIPELINE_READY_LABEL,
        "--state", "open",
        "--json", "number,title,body,labels",
    ])
    if not output:
        return []
    return json.loads(output)


def update_issue_labels(issue_number: int, remove: str | None = None, add: str | None = None):
    """Update labels on an issue."""
    args = ["issue", "edit", str(issue_number)]
    if remove:
        args.extend(["--remove-label", remove])
    if add:
        args.extend(["--add-label", add])
    _gh(args, check=False)


def comment_on_issue(issue_number: int, body: str):
    """Add a comment to an issue."""
    _gh(["issue", "comment", str(issue_number), "--body", body])


def close_issue(issue_number: int):
    """Close an issue."""
    _gh(["issue", "close", str(issue_number)])


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

def _git(args: list[str]) -> str:
    result = subprocess.run(
        ["git"] + args,
        capture_output=True,
        text=True,
        cwd=str(config.PROJECT_ROOT),
    )
    return result.stdout.strip()


def git_commit_and_push(files: list[Path], message: str):
    """Stage specific files, commit, and push."""
    for f in files:
        rel = f.relative_to(config.PROJECT_ROOT) if f.is_absolute() else f
        _git(["add", str(rel)])

    # Check if there's anything to commit
    status = _git(["status", "--porcelain"])
    if not status:
        logger.info("No changes to commit")
        return

    _git(["commit", "-m", message])
    _git(["push"])
    logger.info("Committed and pushed: %s", message)


# ---------------------------------------------------------------------------
# Task execution
# ---------------------------------------------------------------------------

def execute_content_subtask(specs: dict, description: str) -> list[Path]:
    """Execute a content generation subtask. Returns paths of created files."""
    content_type = specs.get("content_type")
    region = specs.get("region")
    files = []

    if content_type == "npc":
        data = content_agent.generate_npc(description, region)
        npc_id = data.get("npc_id", "unknown")
        files.append(config.DATA_DIR / "npcs" / f"{npc_id}.json")
        # Auto-generate dialogue for the NPC
        try:
            content_agent.generate_dialogue(npc_id)
            files.append(config.DATA_DIR / "dialogue" / f"{npc_id}_dialogue.json")
        except Exception as e:
            logger.warning("Dialogue generation failed: %s", e)

    elif content_type == "quest":
        data = content_agent.generate_quest(description, region)
        quest_id = data.get("quest_id", "unknown")
        files.append(config.DATA_DIR / "quests" / f"{quest_id}.json")

    elif content_type == "items":
        items = content_agent.generate_items(description)
        for item in items:
            files.append(config.DATA_DIR / "items" / f"{item.get('item_id', 'unknown')}.json")

    elif content_type == "zone":
        data = content_agent.generate_zone(description, region)
        zone_id = data.get("zone_id", "unknown")
        files.append(config.DATA_DIR / "maps" / f"{zone_id}.json")

    elif content_type == "dialogue":
        # Extract NPC ID from description
        npc_id = description.lower().replace(" ", "_").split("for_")[-1] if "for" in description else description
        content_agent.generate_dialogue(npc_id)
        files.append(config.DATA_DIR / "dialogue" / f"{npc_id}_dialogue.json")

    elif content_type == "world_bible":
        content_agent.generate_world_bible()
        files.append(config.DATA_DIR / "lore" / "world_bible.json")

    else:
        logger.warning("Unknown content type: %s, generating as NPC", content_type)
        data = content_agent.generate_npc(description, region)
        files.append(config.DATA_DIR / "npcs" / f"{data.get('npc_id', 'unknown')}.json")

    return files


def execute_art_subtask(specs: dict, description: str, context: dict) -> list[Path]:
    """Execute an art generation subtask. Returns paths of created files."""
    asset_type = specs.get("asset_type")
    entity_id = specs.get("entity_id", "unknown")
    files = []

    if asset_type == "character":
        # Get description from content context if available
        char_desc = description
        if "content" in context:
            for f in context.get("content_files", []):
                if f.suffix == ".json" and entity_id in f.name:
                    data = json.loads(f.read_text(encoding="utf-8"))
                    char_desc = f"{data.get('name', '')}, {data.get('personality_description', '')}"
                    break

        raw_frames = art_agent.generate_character_sprite(entity_id, char_desc)
        if raw_frames:
            sheet = postprocess.process_character_sprites(entity_id, raw_frames)
            files.append(sheet)

    elif asset_type == "tileset":
        raw = art_agent.generate_tileset(entity_id, description)
        if raw:
            processed = postprocess.process_tileset(entity_id, raw)
            files.append(processed)

    elif asset_type == "item_icon":
        raw = art_agent.generate_item_icon(entity_id, description)
        if raw:
            processed = postprocess.process_item_icon(entity_id, raw)
            files.append(processed)

    return files


def execute_code_subtask(specs: dict, description: str, context: dict) -> list[Path]:
    """Execute a code generation subtask. Returns paths of created files."""
    # Gather related files for context
    related = []
    for f in context.get("content_files", []):
        related.append(f)

    written, errors = code_agent.generate_and_write(description, related_files=related)

    if errors:
        logger.warning("Code validation errors: %s", errors)
        # Retry once with error feedback
        retry_desc = f"{description}\n\nPrevious attempt had these errors, fix them:\n" + "\n".join(errors)
        written, errors = code_agent.generate_and_write(retry_desc, related_files=related)

    return written


# ---------------------------------------------------------------------------
# Main processing loop
# ---------------------------------------------------------------------------

def process_issue(issue: dict):
    """Process a single GitHub issue through the full pipeline."""
    number = issue["number"]
    title = issue["title"]
    body = issue.get("body", "")

    logger.info("=" * 60)
    logger.info("Processing issue #%d: %s", number, title)
    logger.info("=" * 60)

    # Update status
    update_issue_labels(number, remove=config.PIPELINE_READY_LABEL, add=config.PIPELINE_IN_PROGRESS_LABEL)

    try:
        # Classify
        classification = task_classifier.classify(title, body)
        logger.info("Classification: %s", classification["primary_category"])

        # Execute subtasks in priority order
        context = {"content_files": [], "art_files": [], "code_files": []}
        all_files = []

        subtasks = sorted(classification.get("subtasks", []), key=lambda s: s.get("priority", 99))

        for subtask in subtasks:
            cat = subtask["category"]
            desc = subtask["description"]
            logger.info("Executing %s subtask: %s", cat, desc)

            if cat == "content":
                specs = classification.get("content_specs", {})
                files = execute_content_subtask(specs, desc)
                context["content_files"].extend(files)
                all_files.extend(files)

            elif cat == "art":
                specs = classification.get("art_specs", {})
                files = execute_art_subtask(specs, desc, context)
                context["art_files"].extend(files)
                all_files.extend(files)

            elif cat == "code":
                specs = classification.get("code_specs", {})
                files = execute_code_subtask(specs, desc, context)
                context["code_files"].extend(files)
                all_files.extend(files)

        # Validate all outputs
        review = review_agent.validate_all(all_files)

        if review.passed:
            # Commit and close
            git_commit_and_push(all_files, f"Pipeline: {title} (#{number})")
            update_issue_labels(number, remove=config.PIPELINE_IN_PROGRESS_LABEL, add=config.PIPELINE_DONE_LABEL)
            comment_on_issue(number, f"Pipeline completed successfully.\n\n{review.summary}")
            close_issue(number)
            logger.info("Issue #%d completed successfully", number)
        else:
            # Flag for human review
            update_issue_labels(
                number,
                remove=config.PIPELINE_IN_PROGRESS_LABEL,
                add=config.PIPELINE_NEEDS_HUMAN_LABEL,
            )
            comment_on_issue(
                number,
                f"Pipeline completed with validation errors. Manual review needed.\n\n{review.summary}",
            )
            logger.warning("Issue #%d needs human review:\n%s", number, review.summary)

    except Exception as e:
        logger.error("Issue #%d failed: %s", number, e, exc_info=True)
        update_issue_labels(
            number,
            remove=config.PIPELINE_IN_PROGRESS_LABEL,
            add=config.PIPELINE_NEEDS_HUMAN_LABEL,
        )
        comment_on_issue(number, f"Pipeline failed with error:\n```\n{e}\n```")


def run_watch():
    """Main polling loop — watches for ready issues and processes them."""
    logger.info("Starting pipeline watcher (polling every %ds)...", config.POLL_INTERVAL_SECONDS)
    logger.info("Repo: %s", config.GITHUB_REPO)
    logger.info("Label: %s", config.PIPELINE_READY_LABEL)

    while True:
        try:
            issues = get_ready_issues()
            if issues:
                logger.info("Found %d ready issue(s)", len(issues))
                for issue in issues:
                    process_issue(issue)
            else:
                logger.debug("No ready issues found")
        except Exception as e:
            logger.error("Polling error: %s", e)

        time.sleep(config.POLL_INTERVAL_SECONDS)


def run_single(issue_number: int):
    """Process a single issue by number."""
    output = _gh([
        "issue", "view", str(issue_number),
        "--json", "number,title,body,labels",
    ])
    issue = json.loads(output)
    process_issue(issue)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )

    parser = argparse.ArgumentParser(description="RPG Pipeline Orchestrator")
    parser.add_argument("--watch", action="store_true", help="Start polling loop")
    parser.add_argument("--issue", type=int, help="Process a single issue by number")
    parser.add_argument("--bootstrap", action="store_true", help="Generate world bible and initial content")
    args = parser.parse_args()

    if args.watch:
        run_watch()
    elif args.issue:
        run_single(args.issue)
    elif args.bootstrap:
        logger.info("Bootstrapping game world...")
        content_agent.generate_world_bible()
        logger.info("World bible generated! Create issues on GitHub to generate more content.")
    else:
        parser.print_help()
