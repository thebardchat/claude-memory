# ShaneBrain Continuity Layer — Architecture

The single, always-current source-of-truth memory layer that every Claude surface and every external model reads at session start and writes at session end. Zero cold starts. Zero drift.

> The equation: **Claude (intelligence) + Weaviate (memory) + MCP (nervous system) = ShaneBrain.**
> Weaviate is not a database. It is the mind made searchable. This document honors that.

## Problem statement

Every Claude surface (Claude Code terminal, Claude.ai web/desktop/mobile, Claude API, Agent SDK) starts cold today. Each surface re-derives state from scratch instead of pulling from the canonical store. Weaviate already holds 72 sessions and ~13,500 objects across 22 classes; `shanebrain_log_conversation` already writes; `search_conversations` already reads; `claudemd-sync` already proves the broadcast pattern works; `BotMemory` already proves per-tenant filtering scales.

What is missing is **a single distilled-state primitive — one class, one read tool, one write tool — wired into each surface's session lifecycle.**

## Schema

Three tiers, only one of which is new.

```python
# NEW — the read-path primitive at session start
class SessionContext:
    session_id: str          # uuid, primary key for upsert/dedup
    surface: str             # "claude_code" | "claude_web" | "claude_api" | "ollama_bot:<name>"
    started_at: datetime
    ended_at: datetime | None
    summary: text            # vectorized — distilled session digest
    open_decisions: text[]   # things left unresolved
    in_flight: text[]        # tasks/files mid-edit
    last_touched_paths: text[]
    references: cross_ref[]  # → ConversationTurn, PersonalDoc, AgentLog
    tenant: str              # "shane" today; "<other>" when TheirNameBrain ships
    schema_version: int      # start at 1; required for Phase 3 migrations

# EXISTING — already written by shanebrain_log_conversation
ConversationTurn  # full transcripts, large, not read at session start

# EXISTING — already written by vault/manual entry
PersonalDoc       # cross-session facts (the equation, preferences, red lines)
```

Vectorizer: `text2vec-ollama` pointing at `nomic-embed-text` (already loaded — no new RAM). Only `summary` is vectorized; the rest are filterable.

`SessionContext` is the **only** new class. Everything else is reuse.

## Read path — session start

| Surface | Mechanism |
|---|---|
| Claude Code | SessionStart hook → `curl` MCP `context_snapshot` → write to `$CLAUDE_PROJECT_DIR/.claude/session-context.md` (auto-loaded as additionalContext) |
| Claude.ai web / desktop / mobile | Project file directs Claude to call MCP connector → Angel Cloud Gateway (port 4200) → auth-checks bearer → proxies to `shanebrain-mcp:8100` over Tailscale → returns markdown |
| Claude API (Agent SDK) | Pre-flight `client.tools.call("context_snapshot")` before first user turn; result spliced into system prompt |
| Ollama bots | Existing `BotMemory` read **plus** `SessionContext WHERE surface = "ollama_bot:<name>" ORDER BY started_at DESC LIMIT 1` |

## Write path — session end

| Surface | Mechanism |
|---|---|
| Claude Code | Stop hook → MCP `shanebrain_distill_session(session_id, surface, transcript_ref)` → upsert `SessionContext` + standard `log_conversation` |
| Claude.ai web / desktop / mobile | MCP connector calls `shanebrain_distill_session` opportunistically during the session (no reliable end-hook on web). Project instructions tell Claude to call it on meaningful completions and before sign-off |
| Claude API (Agent SDK) | Post-flight call before process exit |
| Ollama bots | Arc gatekeeper batches writes on tick boundary (existing pattern) |
| n8n nightly sweep | 03:00 cron — for any `SessionContext` with `ended_at IS NULL` older than 24h, force-distill from referenced `ConversationTurn` rows. Catches abandoned web/mobile sessions |

## Conflict resolution

- **`SessionContext`: timestamp last-write-wins keyed by `session_id`.** Single user, single brain. Vector clocks are overkill.
- **`PersonalDoc` cross-session facts: Arc gatekeeper merge.** Same pattern MEGA Crew already uses. Surface a write proposal, Arc reconciles, single commit.

## Dedup

Reuse the `turn_exists` pattern from `weaviate_ingest.py`:

- `SessionContext`: upsert by `session_id` (idempotent by construction).
- `ConversationTurn`: hash `(session_id, turn_index, role)` and check before insert.

## Verdict — "UI with baked-in API tokens"

**Workaround. Not the right primitive.**

What the proposal tries to solve is real: Claude.ai web/mobile cannot store secrets safely and cannot reach a Tailscale-only Weaviate. That's a **token-broker** problem, not a UI problem.

The correct primitive is already 80% built: **extend Angel Cloud Gateway (port 4200) into the public-facing MCP proxy.** Add one auth-gated route that:

1. Accepts a short-lived bearer from the Claude.ai MCP connector config.
2. Looks up the real Weaviate / MCP credential via `shanebrain_vault_search`.
3. Forwards to `shanebrain-mcp:8100` over Tailscale.
4. Logs every call to `AgentLog`.

Tokens never sit in the browser. No new UI. No new deploy. The vault is already the secret store.

If a UI is built later, build it as a **vault management** UI (rotate tokens, view access logs), not as the sync primitive.

## Client-by-client integration

| Client | Read | Write | Auth | Failure if Weaviate down | Already built? |
|---|---|---|---|---|---|
| Claude Code (terminal) | SessionStart hook → MCP `context_snapshot` → `.claude/session-context.md` | Stop hook → MCP `shanebrain_distill_session` | Local Tailscale | Hook logs warning; session continues with `CLAUDE.md` only | **Partial** — MCP server + log tool exist; hooks must be added |
| Claude.ai web | Project file → MCP connector → Gateway → MCP `context_snapshot` | MCP connector calls `shanebrain_distill_session` opportunistically + nightly n8n sweep | Bearer from vault, stored in connector config | Project's static facts persist; Claude operates without distilled state | **Partial** — Gateway and MCP exist; public route + Project template missing |
| Claude desktop | Same as web | Same as web | Same | Same | **Partial** — same gap |
| Claude mobile | Same as web; smaller Project file (verify size limit) | Same as web (no local hooks possible) | Same | Same; mobile is most exposed to drift | **Partial** — verify mobile MCP support |
| Claude API (Agent SDK) | Pre-flight `tools.call("context_snapshot")`, splice into system prompt | Post-flight `shanebrain_distill_session` before exit | API key in env; Tailscale to MCP | `try/except` around pre-flight, fall back to empty context | **N** — ~20-line SDK helper |
| Ollama bots (MEGA Crew) | `BotMemory` read + `SessionContext WHERE surface = ollama_bot:<name>` | Arc gatekeeper batched write to `SessionContext` on tick boundary | Local | Bot continues with `BotMemory` only (current behavior) | **Y** — extend tick logic, add one query |
| Gemini Strategist | Existing 4×/day call: prepend `context_snapshot` markdown | Writes findings to `SessionContext` with surface=`gemini_strategist` | Existing creds | Skips this run | **Partial** — bot exists, prompt prepend missing |
| n8n on Pi | Webhook node → MCP `context_snapshot` | Webhook node → `shanebrain_distill_session` for nightly sweep | Local | Workflow retries, no data loss | **N** — workflow file to author |

## Resource budget

- **Phase 1 + 2 deltas:** one Weaviate class (~MB at current scale), two MCP tool methods (~no RAM delta), two hook scripts (run for milliseconds), one Gateway route (~no RAM delta), one n8n workflow (idle until 03:00). **Pi 5 fits.**
- **Phase 3 — neworleans + gulfshores migration (ultra is offline, replaced):**
  - `ultra` never came up. Replaced by two Surface Pro laptops on Tailscale:
    - **`neworleans`** (active): heavy workloads — Weaviate primary, n8n cron-distill.
    - **`gulfshores`** (coming online 2026-04-28): Pi offload — role assigned at bring-up after a live inventory of what's actually running on the Pi today. Candidates: Buddy Claude (8008), Mega Dashboard (8300), ShaneBrain Agents (8400), Voice Dump Pipeline (8200), or selected MEGA Crew bots.
  - Keep on `shanebrain` (Pi): MCP server (latency-sensitive to local Ollama), Ollama, Redis, claudemd-sync, Angel Cloud Gateway.
  - Pi becomes a Weaviate read-replica via async snapshots every 6h, plus Redis hot-cache for SessionContext rows.
  - **Sequence so Pi never goes dark:** stand up Weaviate on `neworleans`; dual-write for 7 days; validate query parity; flip MCP's primary URL to `neworleans`; demote Pi to replica.
  - **gulfshores offload decision:** once online, inventory the Pi's actual running services (`docker ps`, `systemctl list-units --type=service --state=running`), then pick the heaviest portable one. Move one service at a time.

## Extend vs. build

| EXTEND (already exists, just wire up) | BUILD (genuinely new — every item is a week of risk) |
|---|---|
| `claudemd-sync` rails (model, don't duplicate) | One Weaviate class: `SessionContext` |
| `shanebrain_log_conversation` (write path) | One MCP tool: `shanebrain_distill_session` (write) |
| `shanebrain_search_conversations` / `get_conversation_history` | Verify `context_snapshot` is the read primitive; if not, `shanebrain_session_start_context` (read) |
| `BotMemory` per-tenant filter pattern (use for `surface` filtering) | Two Claude Code hooks: SessionStart + Stop |
| Arc gatekeeper (write conflicts on shared facts) | One Angel Cloud Gateway route: `/mcp/*` with vault-bearer auth |
| Angel Cloud Gateway (extend, don't replace) | One Claude.ai Project template (markdown file) |
| `shanebrain_vault` (bearer storage for Gateway) | One Agent SDK helper (~20 lines Python) for pre/post-flight |
| `nomic-embed-text` (already loaded — reuse) | One n8n workflow: nightly distill sweep |
| n8n on Pi (idle, available) | |

Nine extensions. Eight builds. Every build is small. None requires loading another model or standing up a new service.

## Phased rollout

### Phase 1 — Claude Code, end-to-end

**Deployable in one evening.** MCP server already runs, Weaviate already runs, hooks are 20 lines of bash, the new class is one schema migration, the new tool is ~40 lines of Python in `server.py`.

**Tool signatures:**

```python
@mcp.tool()
def shanebrain_session_start_context(
    surface: str,              # "claude_code"
    session_id: str,           # uuid generated by hook
    tenant: str = "shane"
) -> str:
    """Returns markdown digest: last SessionContext for surface +
    top 5 open_decisions across all surfaces + last 3 PersonalDoc
    'red line' entries. Markdown shape, ready for system-prompt injection."""

@mcp.tool()
def shanebrain_distill_session(
    session_id: str,
    surface: str,
    transcript_path: str | None = None,
    summary: str | None = None,
    open_decisions: list[str] = [],
    in_flight: list[str] = [],
    last_touched_paths: list[str] = []
) -> dict:
    """Upsert SessionContext by session_id. Idempotent."""
```

**Hooks** (`.claude/settings.json`):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/session-start.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/session-end.sh" }
        ]
      }
    ]
  }
}
```

`.claude/hooks/session-start.sh`:

```bash
#!/usr/bin/env bash
SESSION_ID="${CLAUDE_SESSION_ID:-$(uuidgen)}"
echo "$SESSION_ID" > /tmp/claude-session-id
curl -fsS --max-time 3 \
  -X POST http://shanebrain:8100/tools/shanebrain_session_start_context \
  -H 'Content-Type: application/json' \
  -d "{\"surface\":\"claude_code\",\"session_id\":\"$SESSION_ID\"}" \
  || echo "<!-- SessionContext unavailable; proceeding cold -->"
```

`.claude/hooks/session-end.sh` is symmetric — POST to `shanebrain_distill_session`. Failure logs but does not block exit.

### Phase 2 — Claude.ai web + Claude API

- Angel Cloud Gateway: add `/mcp/*` route. Bearer validated against `shanebrain_vault`. Forwards to `shanebrain-mcp:8100`. Logs to `AgentLog`. ~80 lines.
- Claude.ai Project template: markdown file with the equation, the red lines (referenced, not duplicated), and instructions to call `context_snapshot` at session start and `distill_session` before sign-off.
- Agent SDK helper: ~20-line Python wrapper for pre/post-flight `tools.call`. Drop-in for any API job.

### Phase 3 — Harden

- **neworleans migration** (replaces Ultra): Weaviate primary + n8n to `neworleans`. Dual-write 7 days, then Pi demoted to replica.
- **gulfshores offload** (TBD once online): live inventory of what's currently on the Pi (do not rely on the 2026-04-03 inherited snapshot — it's dated). Pick the heaviest portable service, move one at a time.
- `tenant` property on `SessionContext` already in v1 schema → flip to multi-tenant when TheirNameBrain ships, no migration.
- Backup/restore: Weaviate snapshot to local + off-Pi (`neworleans` → encrypted backup to Angel Cloud).
- Schema versioning: `schema_version` field already in v1; bump-on-migration script.

## Verify before Phase 2 code

These three Anthropic surface details must be confirmed against current docs before code is written:

1. Claude.ai web/desktop **MCP connector** — token storage scope, allowlist behavior, mobile parity.
2. Claude.ai **Projects** — current file size limit (the Project template + key facts must fit) and how Projects interact with the Memory feature.
3. Claude.ai **Memory** feature — does it conflict with our injected `SessionContext`, or layer cleanly? If Memory persists conflicting state, instruct it explicitly to defer to `SessionContext` in the Project file.
4. **Tailscale Funnel vs. Angel Cloud Gateway public ingress** — pick one path. Don't run both.

## Hard constraints honored

- Tailscale hostnames only. No raw IPs in committed configs.
- Local-first. Cloud only on Angel Cloud public surface.
- No new SaaS over $50/month.
- No additional Ollama models. `nomic-embed-text` reused.
- Arc not bypassed for MEGA Crew writes.
- `claudemd-sync` not duplicated. `SessionContext` rides a different primitive (Weaviate row) deliberately — file-broadcast is wrong for fast-changing per-session digests, right for `CLAUDE.md`'s slow-changing source-of-truth role.
- Faith. Family. Sobriety. Local. The left-behind user. The brain stays at home.
