# rpg-pipeline

An experiment in **AI-driven game development**: a multi-agent Python pipeline that generates the content, art and code for a playable top-down RPG built in **Godot 4**.

The repo contains both the pipeline and its output — a small but complete RPG world ("Aethermoor") with a starter town, wilderness zone, quest chains, NPC dialogue, character classes, combat, inventory and shops.

## How it works

Four cooperating agents, orchestrated from `pipeline/`:

| Agent | Role |
|---|---|
| `content_agent` | Generates structured game data — world lore, NPCs, dialogue trees, quests, items, enemies, classes — as JSON under `data/` |
| `art_agent` | Generates pixel-art assets (sprites, tilesets, item icons, portraits, maps) via the **ComfyUI** API (REST + WebSocket) |
| `code_agent` | Generates the GDScript gameplay systems under `scripts/` from the content specs |
| `review_agent` | Validates output consistency before assets and code land in the project |

The Godot project (`project.godot`, `scenes/`, `scripts/`) consumes the generated data directly — dialogue, quests and items are all data-driven from the JSON the pipeline produces.

## What's in the generated game

- **Hearthholm** (starter town) and **Oldroot Forest** (wilderness zone)
- 11 NPCs with dialogue trees — blacksmith, alchemist, guildmaster, a mysterious stranger…
- 9 quests, 3 character classes, and a full item catalogue (weapons, armour, consumables, materials)
- GDScript systems: combat, dialogue, inventory, quest tracking, shops, spawning, zone management

## Stack

- **Godot 4** (GDScript) — game runtime
- **Python** — agent pipeline and orchestration
- **ComfyUI** — local image generation for all art
- **Jinja** — code/content templating

## Status

A working proof-of-concept, part of ongoing exploration of AI-assisted game production at [Biological Games](https://biological.games).
