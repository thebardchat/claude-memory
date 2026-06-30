# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repo (`thebardchat/claude-memory`) tracks the Claude Code session state for `/home/shanebrain`:
- `.claude/projects/-home-shanebrain/CLAUDE.md` — full project-level context (672 lines, authoritative)
- `Desktop/SHANEBRAIN.bat` — Windows launcher (SSH into Pi + runs preflight + launches Claude)

All real ShaneBrain code lives at `/mnt/shanebrain-raid/shanebrain-core/`.

## Session Start (every session, no exceptions)

```bash
bash /mnt/shanebrain-raid/shanebrain-core/scripts/preflight.sh
```

Then call MCP tools in order: `shanebrain_daily_briefing` → `shanebrain_system_health` → `shanebrain_search_conversations`

## Session End (every session)

```bash
# MCP tools — always run all three
shanebrain_log_conversation   # mode: CODE / CHAT / DISPATCH
shanebrain_daily_note_add     # journal entry + mood tag
shanebrain_add_knowledge      # anything worth keeping
```

CLAUDE.md auto-distributes via `claudemd-sync` systemd service — never manually copy it.

## Key Commands

```bash
# Check services
systemctl status mega-dashboard pulsar-ai pironman5 shanebrain-discord shanebrain-alerter angel-cloud-gateway

# Docker swarm status
docker service ls && docker node ls

# Gemma inference cluster (replaces Ollama — fully deleted 2026-05-07)
curl http://biloxi:8080/v1/models
curl http://gulfshores:8080/v1/models
curl http://alaska:8080/v1/models

# MCP server health
curl http://localhost:8100/health

# Weaviate health (on neworleans)
curl http://neworleans:8080/v1/.well-known/ready

# SSH to cluster nodes
ssh alaska@alaska    # Zorin OS 18.1, family comms
ssh mexico@mexico    # family comms node
ssh gulfshores@gulfshores  # dev/build node
ssh hubby@pulsar00100      # Windows utility node
```

## Architecture

**Controller:** Pi 5 (`shanebrain`, `100.67.120.6`) — runs all systemd services, Docker swarm manager  
**Data node:** `neworleans` — Weaviate 1.36.2 (port 8080) + N8N (port 5678)  
**Inference:** Docker Swarm `llama-server` service across biloxi/gulfshores/alaska (port 8080, OpenAI-compatible)  
**MCP:** `shanebrain-mcp` Docker container, port 8100, 44 tools total

Main service ports on Pi: `4200` Angel Cloud, `8100` MCP, `8300` Mega Dashboard, `8400` Agents, `9000` Portainer

**MEGA Crew:** 17 Docker bot containers at `mega/bots/docker-compose.yml`. Arc is gatekeeper, Weld is applier. Bot LLM inference disabled (Ollama deleted) — replacement not yet chosen.

**Weaviate:** `text2vec-transformers` (MiniLM-L6-v2, 384-dim) via `t2v-transformers` container on Pi port 8090. 25 collections. `ShaneTodo` is the only non-vectorized collection.

## Environment Rules

- No Ollama — fully deleted 2026-05-07. Use Gemma cluster (`biloxi/gulfshores/alaska:8080`) for free inference
- Tailscale hostnames only — never raw IPs
- `set -a && source .env && set +a` to export vars to Python subprocesses
- Pironman5 service controls fans — never disable it
- Python 3.13: `cgi` module removed; use `--break-system-packages` for pip installs
- `host.docker.internal` doesn't resolve on Linux — use `localhost` or `172.17.0.1` from containers
- Pi can't reach phone via Taildrop (different Tailscale owners) — serve files via angel-cloud static or email links
