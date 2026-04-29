# Global CLAUDE.md — Template

This is a **template** for `~/.claude/CLAUDE.md`. It is not auto-installed.

## How to use this file

1. Read it. Compare against your existing `~/.claude/CLAUDE.md`.
2. Merge what's missing. Keep what's already there if it works.
3. Do not symlink this template — `~/.claude/CLAUDE.md` evolves with you, this template is a reference snapshot.

The content below the `---` is the recommended global file body. Copy from there.

---

```markdown
# CLAUDE.md — GLOBAL (Shane / ShaneBrain)

Scope: every Claude session. Repo CLAUDE.md files may extend but not override what's below.

## Source of truth — claude-memory repo (read this first)

The architecture for ShaneBrain — design, runbooks, hooks, mesh manifest, precedence rules — lives at:

- **GitHub:** https://github.com/thebardchat/claude-memory
- **Local clone (every node):** `~/claude-memory`

Every Claude session on every node defers to that repo for project architecture. This global file owns **identity**. The repo owns **project**. If the repo doesn't exist locally, clone it (`git clone https://github.com/thebardchat/claude-memory.git ~/claude-memory`). Then read `~/claude-memory/CLAUDE.md` — it tells you the active phase, the branch, and what's in flight.

To set up a fresh node: see `~/claude-memory/docs/NODE-BOOTSTRAP.md`.

## Identity

- User: Shane. Builder of ShaneBrain.
- The equation: Claude (intelligence) + Weaviate (memory) + MCP (nervous system) = ShaneBrain.
- Values: Faith. Family. Sobriety. Local-first. The left-behind user.
- The brain stays at home, on hardware Shane owns.

## Communication

- Banned words: streamline, revolutionary, "in today's rapidly evolving landscape," "it's important to note."
- No filler. Direct. Markdown headers in long answers. Code blocks for code, config, and commands.
- Match length to the task. Short question gets a short answer.
- State results and decisions. Do not narrate internal deliberation.

## Mesh — Tailscale, hostnames only

- `shanebrain` — Pi 5 16GB. Orchestrator. Current Weaviate primary, MCP host.
- `ultra` — OptiPlex XE3. Designated heavy-lifter. Future Weaviate primary.
- `pulsar`, `bullfrog`, `mexico`, `gulfshores`, `neworleans` — cluster nodes.
- `jaxton` — independent.
- All addressing via Tailscale hostnames. Never paste raw IPs into committed configs.
- Pulsar Blockchain Security and Pulsar Sentinel PQC (port 8250 on Pi) run on every node.

## Hardware constants

- Pi 5 RAM is tight. Do not propose loading additional Ollama models.
- `nomic-embed-text` is the embedding model. Already loaded. Reuse it for any new embedding work.
- `OLLAMA_MAX_LOADED_MODELS=1`, `OLLAMA_NUM_PARALLEL=1`. Both are deliberate. Do not raise.

## Memory — the canonical store

- Weaviate on `shanebrain:8080` is the canonical store today. `ultra` is the migration target.
- `shanebrain-mcp` on port 8100 is the read/write surface. Use the MCP tools, do not bypass them.
- `claudemd-sync` (systemd, inotifywait) watches `CLAUDE.md` and broadcasts on save. Do not duplicate that job.
- `Arc` gatekeeps MEGA Crew writes. Do not bypass Arc.
- Per-bot memory uses `BotMemory` filtered by `bot_name`. Cross-session memory uses `SessionContext`.

## Red lines (subset — full set in `shanebrain_vault` under `red_lines`)

- No new SaaS over $50/month.
- No cloud dependency for memory continuity. Public surface only on Angel Cloud Gateway.
- No raw IPs in committed configs (Tailscale hostnames only).
- No new top-level files without a clear owner.
- No bypassing Arc on MEGA Crew writes.

## Default behavior

- Use Tailscale hostnames.
- Use the `shanebrain` MCP server, not direct Weaviate calls, when an MCP tool exists.
- Read the repo's `CLAUDE.md` and any `docs/ARCHITECTURE.md` before answering project-specific questions.
- Extend before building. Every "build" item is a week of risk.

## Precedence

This file is the floor. A repo `CLAUDE.md` may add stricter rules but may not relax anything above. Conflicts on identity, values, mesh, hardware, or red lines are resolved in favor of this file. Conflicts on project behavior (branches, build commands, file layout) are resolved in favor of the repo file. See `docs/CLAUDE-md-precedence.md` in the `claude-memory` repo for the full rule set.

## When in doubt

- Local beats cloud.
- Extend beats build.
- Surface conflicts as a question. Never silently override.
```
