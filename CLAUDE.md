# CLAUDE.md — REPO (claude-memory)

Scope: this repository only. Defers to `~/.claude/CLAUDE.md` for identity, values, mesh, red lines, banned words. This file adds project-specific instructions only.

> Why two files? See [`docs/CLAUDE-md-precedence.md`](docs/CLAUDE-md-precedence.md). The short rule: **global owns WHO/WHY. Repo owns WHAT/HOW. Repo can add, never relax.**

---

## If you are a Claude session reading this for the first time — START HERE

You are most likely running on `shanebrain` (Pi 5), reached over Tailscale from Termius. Before doing anything else:

### 1. Confirm where you are

```bash
hostname                                                      # expect: shanebrain
docker ps --filter name=shanebrain --format '{{.Names}}\t{{.Status}}'
curl -fsS http://localhost:8080/v1/.well-known/ready && echo "Weaviate OK"
curl -fsS http://localhost:8100/ >/dev/null && echo "MCP OK"
```

### 2. Read these files in this order

1. `docs/ARCHITECTURE.md` — the design (SessionContext schema, read/write paths, integration table, phased rollout). **Read before proposing alternatives.**
2. `docs/PHASE-1-RUNBOOK.md` — the active task. Numbered, paste-ready commands. **This is what you execute.**
3. `docs/CLAUDE-md-precedence.md` — only if asked about CLAUDE.md scope or conflicts.
4. `.claude/projects/-home-shanebrain/CLAUDE.md` — **inherited environment snapshot (v3.4, 2026-04-03)**. The authoritative reference for ports, services, container names, cluster nodes, MEGA Crew, the `172.17.0.1` Docker-to-host rule, and Shane's working style. Read for context; do not modify.

### 3. What you are working on

**Phase 1 — Claude Code SessionStart/Stop hooks + `SessionContext` Weaviate class.** Active. Branch `claude/multi-agent-memory-architecture-1cx6b`.

**The single next decision** is the gating step in [`docs/PHASE-1-RUNBOOK.md`](docs/PHASE-1-RUNBOOK.md) Step 2: `docker exec shanebrain-mcp grep -nA 40 'def context_snapshot' /app/server.py`. Do that first. The result branches the rest of Phase 1.

### 4. The hooks in this repo are already wired

- `.claude/settings.json` registers SessionStart and Stop hooks.
- `.claude/hooks/session-start.sh` calls MCP `shanebrain_session_start_context`, falls back to existing `context_snapshot`, prints an HTML comment if both fail.
- `.claude/hooks/session-end.sh` calls MCP `shanebrain_distill_session`, no-op on failure.

Both hooks **never block the session.** They are safe to commit before the MCP tools exist; they will activate the moment the tools are added in Step 4 of the runbook.

---

## Operator context — Termius via Tailscale

- Shane works from his phone via Termius SSH into `shanebrain` (Pi 5) over Tailscale.
- Commands must be paste-friendly on a small screen — short, single-block, no long heredocs unless unavoidable.
- Each runbook step is independently re-runnable; if SSH drops mid-step, re-run that step, do not start over.
- Local services on the Pi reach each other via `localhost`. Cross-mesh calls use Tailscale hostnames (`shanebrain`, `ultra`, `pulsar`, `bullfrog`, etc.) — never raw IPs in committed configs.
- Docker containers on the Pi reaching Pi host services use `172.17.0.1` (not `localhost`, not `host.docker.internal`). See `.claude/projects/-home-shanebrain/CLAUDE.md` for the canonical rule.

---

## What this repo is

The continuity layer for ShaneBrain — design, docs, working hooks, and the public landing page for the single source-of-truth memory primitive (`SessionContext`) that every Claude surface and external model reads at session start and writes at session end.

- Public landing page: https://thebardchat.github.io/claude-memory/
- Canonical design: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Active runbook: [`docs/PHASE-1-RUNBOOK.md`](docs/PHASE-1-RUNBOOK.md)
- Precedence rules: [`docs/CLAUDE-md-precedence.md`](docs/CLAUDE-md-precedence.md)
- Global file template: [`docs/global-CLAUDE.md.template.md`](docs/global-CLAUDE.md.template.md)
- Inherited environment snapshot: [`.claude/projects/-home-shanebrain/CLAUDE.md`](.claude/projects/-home-shanebrain/CLAUDE.md)

## What this repo is NOT

- Not the source for `shanebrain-mcp` (lives on `shanebrain` Pi, edited per runbook Step 4).
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
| 1 | Claude Code SessionStart/Stop hooks + `SessionContext` class | **Active — runbook ready** |
| 2 | Angel Cloud Gateway public `/mcp/*` route + Claude.ai Project template + Agent SDK helper | Pending |
| 3 | `ultra` migration, multi-tenant for TheirNameBrain, backup/restore, schema versioning | Pending |

## Conventions specific to this repo

- **This is a public repo.** Tailscale hostnames are fine. Vault contents, bearer tokens, per-machine secrets, and full IP ranges are not.
- **Architectural decisions live in `docs/ARCHITECTURE.md`.** Update it in the same commit as the change.
- **MCP tool signatures get added to `docs/ARCHITECTURE.md` before they're implemented in `shanebrain-mcp`.**
- **Don't add top-level files without a clear owner.** Repo root stays narrow: `CLAUDE.md`, `LICENSE`, `index.html`, `docs/`, `.github/`, `.claude/`.

## Verify before writing Phase 2 code

Confirm against current Anthropic docs first:

- Anthropic Projects file size limit.
- Claude.ai MCP connector token storage on web vs. mobile.
- Claude.ai Memory feature interaction with injected `SessionContext`.
- Tailscale Funnel vs. Angel Cloud Gateway as the public path — pick one.

## When in doubt

- Read `docs/ARCHITECTURE.md` before proposing alternatives.
- Read `docs/CLAUDE-md-precedence.md` before adding to either CLAUDE.md.
- Local beats cloud. Extend beats build. Surface conflicts as a question.
