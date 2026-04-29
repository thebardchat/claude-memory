# ShaneBrain Mesh

The set of nodes that participate in ShaneBrain. **Tailscale hostnames only — no IPs in this public file.** Per-node IPs and credentials live on the nodes themselves and in `shanebrain_vault`.

## Node roles

| Hostname | Role | Phase 1 services | Phase 3 target |
|---|---|---|---|
| `shanebrain` | Orchestrator (Pi 5, 16GB) | `shanebrain-mcp` (8100), `shanebrain-weaviate` (8080), Ollama (11434), MEGA Crew, claudemd-sync, Angel Cloud Gateway (4200), n8n (5678), Redis | Demoted to Weaviate read-replica + Redis hot-cache + MCP/Ollama/Gateway local |
| `neworleans` | Heavy-lifter (Surface Pro) | (Phase 1: passive — repo only) | Weaviate primary, n8n nightly distill |
| `gulfshores` | Pi-offload candidate (Surface Pro, coming online 2026-04-28, headless Linux server profile) | (TBD on bring-up) | Final role chosen at bring-up after live inventory of what's currently on the Pi. Candidates: Buddy Claude, Mega Dashboard, ShaneBrain Agents, Voice Dump Pipeline, or selected MEGA Crew bots. |
| `pulsar` | Cluster node | Ollama (llama3.1:8b — fastest inference) | Same |
| `bullfrog` | Cluster node | Ollama (codellama) | Same |
| `jaxton` | Independent laptop | Variable | Same |
| `mexico` | Cluster node | Variable Ollama models | Same |
| ~~`ultra`~~ | (was: heavy-lifter) | **Offline — replaced by `neworleans` + `gulfshores`** | n/a |

## What each node has after bootstrap

After running `docs/NODE-BOOTSTRAP.md`:

- `~/claude-memory` cloned and (optionally) auto-pulled hourly.
- A suggested global `~/.claude/CLAUDE.md` (never auto-overwritten) that points back to `~/claude-memory` as the project source of truth.
- Any Claude Code session started on the node finds `CLAUDE.md` immediately and knows the active phase, branch, and next action.

That's the **discovery layer**. The continuity layer (SessionContext + hooks calling Weaviate) is what Phase 1 builds on top.

## What is canonical where

| Concern | Lives on | Read via |
|---|---|---|
| Architecture, runbooks, hooks, design docs | This repo (`thebardchat/claude-memory`), cloned to `~/claude-memory` on every node | `git pull` or the systemd timer |
| Identity, values, mesh, hardware constants, red lines | Each node's `~/.claude/CLAUDE.md` (private, per-node) | Auto-loaded by Claude Code |
| Per-session distilled state | Weaviate `SessionContext` class on `shanebrain` (Pi 5 today, `ultra` after Phase 3) | MCP tools `shanebrain_session_start_context` / `shanebrain_distill_session` once Phase 1 lands |
| Conversation logs | Weaviate `ConversationTurn` class | MCP `shanebrain_search_conversations`, `shanebrain_log_conversation` |
| Secrets, tokens, credentials | `shanebrain_vault` (Weaviate) | MCP `shanebrain_vault_search`, never copied into committed configs |
| Per-bot memory (MEGA Crew) | Weaviate `BotMemory`, filtered by `bot_name` | The bot itself, gated by Arc |

## How nodes reach each other

- All addressing by Tailscale hostname (`shanebrain`, `ultra`, `pulsar`, …).
- Pi-host services from Pi-Docker containers: `172.17.0.1` (the Docker bridge gateway IP — neither `localhost` nor `host.docker.internal`). See `.claude/projects/-home-shanebrain/CLAUDE.md` for the canonical rule.
- Cross-node HTTP (e.g., `shanebrain-mcp` from `ultra`): `http://shanebrain:8100/mcp` over Tailscale.
- Public surface (Phase 2+): a single Angel Cloud Gateway route at the gateway's public hostname, bearer-authenticated, never exposes Weaviate or MCP directly.

## Adding a new node

1. Get the node on Tailscale.
2. SSH in via Termius.
3. Run `docs/NODE-BOOTSTRAP.md` Steps 1–3.
4. Add a row to the table above (PR on the active branch).
5. If the node will run a service (not just be a Claude surface), add the service to the table and update `docs/ARCHITECTURE.md` with where it fits in the read/write paths.

## Removing a node

1. Disable the systemd timer if running: `systemctl --user disable --now claude-memory-pull.timer`.
2. Remove the row from this table.
3. Tailscale removal happens out-of-band via the admin console.

## Why this file exists

Before this file, every Claude session on every non-Pi node started cold — it didn't know what `shanebrain` was, what `ultra` was for, or what its own role was relative to the brain. This file is the discovery layer's manifest, sanitized for a public repo. Operator-detailed snapshots (with IPs, ports, container internals) stay in each node's own `~/.claude/projects/` directory or in `shanebrain_vault`.
