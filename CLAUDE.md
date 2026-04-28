# CLAUDE.md — REPO (claude-memory)

Scope: this repository only. Defers to `~/.claude/CLAUDE.md` for identity, values, mesh, red lines, banned words. This file adds project-specific instructions only.

> Why two files? See [`docs/CLAUDE-md-precedence.md`](docs/CLAUDE-md-precedence.md). The short rule: **global owns WHO/WHY. Repo owns WHAT/HOW. Repo can add, never relax.**

## What this repo is

The continuity layer for ShaneBrain — design, docs, and the public landing page for the single source-of-truth memory primitive (`SessionContext`) that every Claude surface and external model reads at session start and writes at session end.

- Public landing page: https://thebardchat.github.io/claude-memory/
- Canonical design: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Precedence rules: [`docs/CLAUDE-md-precedence.md`](docs/CLAUDE-md-precedence.md)
- Global file template: [`docs/global-CLAUDE.md.template.md`](docs/global-CLAUDE.md.template.md)

## What this repo is NOT

- Not the source for `shanebrain-mcp` (lives on `shanebrain` Pi).
- Not the source for the Weaviate schema (defined inside `shanebrain-mcp`).
- Not a backup of memory contents (Weaviate snapshots go elsewhere).
- Not a duplicate of identity, values, or red lines from global. Reference, don't restate.

## Branch policy

- **Active development branch:** `claude/multi-agent-memory-architecture-1cx6b`
- **Default branch:** `master`
- Push to `master` requires explicit user approval.
- New work starts a new branch; the active branch is rebased or replaced when phases close.

## Project state

| Phase | Scope | Status |
|---|---|---|
| 1 | Claude Code SessionStart/Stop hooks + `SessionContext` class | **Active** |
| 2 | Angel Cloud Gateway public `/mcp/*` route + Claude.ai Project template + Agent SDK helper | Pending |
| 3 | `ultra` migration, multi-tenant for TheirNameBrain, backup/restore, schema versioning | Pending |

Current phase details live in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Conventions specific to this repo

- **This is a public repo.** Tailscale hostnames are fine. Vault contents, bearer tokens, per-machine secrets, and full IP ranges are not.
- **Architectural decisions live in `docs/ARCHITECTURE.md`.** Update it in the same commit as the change.
- **MCP tool signatures get added to `docs/ARCHITECTURE.md` before they're implemented in `shanebrain-mcp`.**
- **Don't add top-level files without a clear owner.** Repo root stays narrow: `CLAUDE.md`, `LICENSE`, `index.html`, `docs/`, `.github/`, `.claude/`.

## Verify before writing Phase 2 code

Confirm against current Anthropic docs first (see `docs/ARCHITECTURE.md` "Verify before Phase 2 code" for full list):

- Anthropic Projects file size limit.
- Claude.ai MCP connector token storage on web vs. mobile.
- Claude.ai Memory feature interaction with injected `SessionContext`.
- Tailscale Funnel vs. Angel Cloud Gateway as the public path — pick one.

## Single next action (Phase 1 kickoff)

Run on the Pi to verify what `context_snapshot` actually does today — every downstream decision (ratify vs. replace) hinges on this one answer:

```bash
docker exec shanebrain-mcp \
  grep -nA 40 'def context_snapshot\|@mcp.tool.*context_snapshot' /app/server.py
```

If it returns a markdown digest keyed by something stable, ratify it as `shanebrain_session_start_context` and skip building a new tool — go straight to writing `.claude/hooks/session-start.sh`. If it's a thin search wrapper, build the new tool per the Phase 1 signature in `docs/ARCHITECTURE.md` and deprecate `context_snapshot`.

## When in doubt

- Read `docs/ARCHITECTURE.md` before proposing alternatives.
- Read `docs/CLAUDE-md-precedence.md` before adding to either CLAUDE.md.
- Local beats cloud. Extend beats build. Surface conflicts as a question.
