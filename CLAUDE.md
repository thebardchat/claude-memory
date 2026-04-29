# CLAUDE.md — REPO (claude-memory)

Scope: this repository only. Defers to `~/.claude/CLAUDE.md` for identity, values, mesh, red lines, banned words. This file adds project-specific instructions only.

> Why two files? See [`docs/CLAUDE-md-precedence.md`](docs/CLAUDE-md-precedence.md). The short rule: **global owns WHO/WHY. Repo owns WHAT/HOW. Repo can add, never relax.**

---

## Decision authority — when to act, when to ask

You (any Claude session in this repo) have authority to **DECIDE AND EXECUTE** without consulting Shane on:

- Library version adaptations (e.g., `weaviate-client` v3 → v4 syntax — the running version wins).
- Transport mechanism choices when multiple work (e.g., direct Weaviate REST vs MCP for the local Pi hooks).
- File path adjustments (where things actually live in the running environment vs. what the runbook assumed).
- Idempotency, dedup, and retry strategies.
- **Adapting the runbook itself when reality differs** — commit the runbook update in the same change.

**CONSULT Shane** before acting on:

- Schema changes (adding/removing classes or properties).
- Anything that touches MEGA Crew bots or the Arc gatekeeper.
- Pushes to `master` (always — branch policy).
- Anything that conflicts with a global `CLAUDE.md` red line.
- Anything that risks data loss or that takes a service offline for more than a brief restart.

Default to **acting + committing** rather than asking. Round-trip-through-Shane is the failure mode this repo exists to fix. Shane is on a phone over SSH; every prompt costs him time he does not have.

---

## Session handoff via existing MCP tools (until SessionContext lands)

Until the new `SessionContext` class is built and the hooks call it, use the existing 42 MCP tools to thread continuity across sessions. **Do this every session, every meaningful step.**

- **At session start:** `shanebrain_search_conversations` for "Phase 1" or whatever's active. Read what the prior session left behind.
- **After each meaningful step (3, 4, 5, …):** `shanebrain_log_conversation` mode=`CODE` with: what was done, what was decided, what's next, what's blocked. One short paragraph.
- **For decisions worth keeping across phases:** `shanebrain_add_knowledge` with category=`phase1-continuity`.

This is the eat-our-own-dog-food protocol. The architect session (claude.ai/web) reads the repo via commits. Pi Claude reads MCP via these calls. **Both stay in sync without Shane acting as relay.**

Once `SessionContext` and the new hooks land at end of Phase 1, this manual protocol is replaced by the automatic SessionStart/Stop flow.

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

1. `docs/MESH.md` — which Shane node you're probably on, what role it plays, what services it runs.
2. `docs/MEGA-CREW.md` — **MEGA Crew is a separate product line**, not infrastructure. 16 bots, evolution loop via Gemini, Arc gatekeeping, daily noir comic published to GitHub + Cloudflare. Read this before recommending the removal of anything Ollama- or Pi-related.
3. `docs/ARCHITECTURE.md` — the design (SessionContext schema, read/write paths, integration table, phased rollout). **Read before proposing alternatives.**
4. `docs/PHASE-1-RUNBOOK.md` — the active task. Numbered, paste-ready commands. **This is what you execute.**
5. `docs/NODE-BOOTSTRAP.md` — only if you're being set up on a new node, or if the user asks how a node should reach this repo.
6. `docs/CLAUDE-md-precedence.md` — only if asked about CLAUDE.md scope or conflicts.
7. `.claude/projects/-home-shanebrain/CLAUDE.md` — **inherited environment snapshot, dated 2026-04-03 (v3.4)**. Useful for stable facts: the `172.17.0.1` Docker-to-host rule, MEGA Crew zones, cluster topology, Shane's working style. **Treat the per-port service list as historical, not current** — services come and go (e.g., open-webui was removed). For the current running state, run `docker ps` and `systemctl list-units --type=service --state=running` on the Pi. Read for context; do not modify this file.

### 3. What you are working on

**Phase 1 — Claude Code SessionStart/Stop hooks + `SessionContext` Weaviate class.** Active. Branch `claude/multi-agent-memory-architecture-1cx6b`.

**Verified facts (2026-04-28):**
- Pi services healthy: `shanebrain-mcp`, `shanebrain-weaviate` (both Up 3+ days).
- `weaviate-client` is **v4.21.0** in the MCP container — v3 syntax is removed. Reuse `DockerWeaviateHelper` from `/app/weaviate_bridge.py`.
- MCP transport is **StreamableHTTP at `/mcp`** (JSON-RPC envelopes), not plain REST `/tools/<name>`. Local Pi hooks should call Weaviate v1 REST directly; the MCP tools are for non-Pi surfaces (Phase 2).
- `shanebrain_context_snapshot` (server.py:1471) exists but is the **identity** snapshot (sobriety, profile, family). **Keep it.** Our new tools (`shanebrain_session_start_context`, `shanebrain_distill_session`) coexist alongside it.

**Active step:** `docs/PHASE-1-RUNBOOK.md` Step 3 (define `SessionContext` collection in v4 syntax) → Step 4 (add the two new MCP tools).

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
- Mesh manifest: [`docs/MESH.md`](docs/MESH.md)
- MEGA Crew product line: [`docs/MEGA-CREW.md`](docs/MEGA-CREW.md)
- Per-node bootstrap: [`docs/NODE-BOOTSTRAP.md`](docs/NODE-BOOTSTRAP.md)
- Backup-and-wipe (Windows → Linux): [`docs/BACKUP-AND-WIPE.md`](docs/BACKUP-AND-WIPE.md)
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
