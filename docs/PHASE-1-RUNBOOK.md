# Phase 1 Runbook — ShaneBrain Continuity Layer

Single goal: **a fresh Claude Code session on `shanebrain`, started from Termius via Tailscale, reads its prior state from Weaviate at start and writes its distilled state at end. Zero cold start.**

Run order matters. Each step is independently verifiable — if a connection drops mid-step, re-run that step. Steps 6–9 are the only ones that mutate the MCP server; everything before is read-only.

> **Authority note:** You have authority to adapt this runbook when reality differs (library version, transport, file paths). Commit the adaptation in the same change. After every step, `shanebrain_log_conversation` mode=CODE with what you did and what's next. See `CLAUDE.md` "Decision authority" and "Session handoff" sections.

## Verified state (2026-04-28)

- Step 0 preflight ✓ — services healthy, Pi confirmed `shanebrain`.
- Step 2 verdict ✓ — `shanebrain_context_snapshot` is identity-snapshot, kept; new tools to be added alongside.
- `weaviate-client` is **v4.21.0**. Use `DockerWeaviateHelper` from `/app/weaviate_bridge.py`. Reach Ollama from the Weaviate container at `http://172.17.0.1:11434` (Pi-host rule).
- MCP transport is **StreamableHTTP at `/mcp`** — Pi hooks call Weaviate v1 REST directly, not MCP.

---

## Step 0 — Operator preflight (Termius, on the Pi)

Goal: confirm you're on `shanebrain` and the local services are alive.

```bash
hostname
docker ps --filter name=shanebrain --format '{{.Names}}\t{{.Status}}'
curl -fsS http://localhost:8080/v1/.well-known/ready && echo OK
curl -fsS http://localhost:8100/ >/dev/null && echo "MCP responding"
ollama list | head -5
```

**Expect:** `shanebrain`. Containers `shanebrain-weaviate` + `shanebrain-mcp` healthy. `OK` from Weaviate. `MCP responding`. Ollama lists `nomic-embed-text` and `llama3.2:1b` or `:3b`.

**If fails:** `docker ps -a` to find the dead container; `docker logs --tail 50 shanebrain-mcp` for cause. Stop here until services are up.

---

## Step 1 — Pull this repo to the Pi

Goal: get `claude-memory` on the Pi at a known path.

```bash
# First time:
git clone https://github.com/thebardchat/claude-memory ~/claude-memory
cd ~/claude-memory

# If already cloned:
cd ~/claude-memory && git fetch origin && \
  git checkout claude/multi-agent-memory-architecture-1cx6b && \
  git pull origin claude/multi-agent-memory-architecture-1cx6b
```

**Expect:** clean working tree on branch `claude/multi-agent-memory-architecture-1cx6b`.

---

## Step 2 — Verify what `context_snapshot` does today

Goal: the gating decision. Ratify the existing tool or build a replacement.

```bash
docker exec shanebrain-mcp \
  grep -nA 40 'def context_snapshot\|@mcp.tool.*context_snapshot' /app/server.py
```

**Branch on the result:**

- **Returns a markdown digest keyed by `session_id` or `surface`** → ratify it as `shanebrain_session_start_context`. **Skip to Step 7.**
- **Returns a thin `search_conversations` wrapper or has no stable key** → build the new tools. **Continue to Step 3.**
- **No output (tool doesn't exist)** → build the new tools. **Continue to Step 3.**

Write the verdict in your terminal so the next step knows the path:

```bash
echo "context_snapshot verdict: <ratify|replace|missing>" > /tmp/shanebrain/cs-verdict
```

---

## Step 3 — Define the `SessionContext` class in Weaviate

Goal: one new class. Idempotent — re-running is safe. v4 syntax, reuses `DockerWeaviateHelper`.

```bash
docker exec shanebrain-mcp python3 - <<'PY'
import sys
sys.path.insert(0, '/app')
from weaviate_bridge import DockerWeaviateHelper
from weaviate.classes.config import Configure, Property, DataType

with DockerWeaviateHelper() as h:
    if h.client.collections.exists("SessionContext"):
        print("SessionContext exists — leaving alone")
    else:
        h.client.collections.create(
            name="SessionContext",
            vectorizer_config=Configure.Vectorizer.text2vec_ollama(
                api_endpoint="http://172.17.0.1:11434",
                model="nomic-embed-text",
            ),
            properties=[
                Property(name="session_id",         data_type=DataType.TEXT),
                Property(name="surface",            data_type=DataType.TEXT),
                Property(name="started_at",         data_type=DataType.DATE),
                Property(name="ended_at",           data_type=DataType.DATE),
                Property(name="summary",            data_type=DataType.TEXT),
                Property(name="open_decisions",     data_type=DataType.TEXT_ARRAY),
                Property(name="in_flight",          data_type=DataType.TEXT_ARRAY),
                Property(name="last_touched_paths", data_type=DataType.TEXT_ARRAY),
                Property(name="tenant",             data_type=DataType.TEXT),
                Property(name="schema_version",     data_type=DataType.INT),
            ],
        )
        print("Created SessionContext")
PY
```

**Expect:** `Created SessionContext` (first run) or `SessionContext exists — leaving alone` (subsequent runs).

**Why these choices:**
- `DockerWeaviateHelper` — reuses existing connection wiring (no new client code).
- `172.17.0.1:11434` — Weaviate runs on `shanebrain-network` bridge, so it reaches host Ollama via the Docker bridge gateway IP per the Pi rule.
- `collections.exists()` first — idempotent.

---

## Step 4 — Add the two new MCP tools to `server.py`

Goal: read and write tools, both idempotent.

**Reality (verified 2026-04-28):** `/app` is NOT volume-mounted. `server.py` is baked into the image. Edit workflow:

```bash
# 1. Backup inside container
docker exec shanebrain-mcp cp /app/server.py /app/server.py.bak

# 2. Pull to host, edit, push back
docker cp shanebrain-mcp:/app/server.py /tmp/server.py
# ... edit /tmp/server.py ...
docker cp /tmp/server.py shanebrain-mcp:/app/server.py

# 3. Compile-check before restart
docker exec shanebrain-mcp python3 -m py_compile /app/server.py && echo "COMPILE OK"
```

**weaviate-client is v4.21.0** — v3 `weaviate.Client(...)` is removed. Use the existing `_weaviate()` context manager and `weaviate.classes.query` imports. The code below is what was actually deployed.

Insert as **GROUP 16** immediately before the `# Entry point` block. Do not replace existing tools.

```python
# ===========================================================================
# GROUP 16: Session Continuity — 2 tools
# Per-session state: read at start, write at end. Keyed by session_id+surface.
# Complements shanebrain_context_snapshot (identity) with session continuity.
# ===========================================================================

@mcp.tool(
    name="shanebrain_session_start_context",
    annotations={"readOnlyHint": True, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False},
)
def shanebrain_session_start_context(surface: str, session_id: str, tenant: str = "shane") -> str:
    """
    Return a markdown digest for session boot: last SessionContext for this
    surface + top 5 open_decisions across all surfaces + last 3 in-flight items.
    Inject into system prompt so Claude never starts cold.
    """
    import datetime as dt
    from weaviate.classes.query import Sort, Filter

    with _weaviate() as h:
        col = h.client.collections.get("SessionContext")

        last = col.query.fetch_objects(
            filters=Filter.by_property("surface").equal(surface),
            sort=Sort.by_property("started_at", ascending=False),
            limit=1,
        )

        recent = col.query.fetch_objects(
            sort=Sort.by_property("started_at", ascending=False),
            limit=20,
        )

    lines = [f"# SessionContext — surface={surface}", ""]

    rows = last.objects
    if rows:
        r = rows[0].properties
        lines.append(f"## Last session ({r.get('ended_at') or 'in-flight'})")
        lines.append(r.get("summary") or "(no summary)")
        if r.get("in_flight"):
            lines.append("\n### In-flight")
            lines += [f"- {x}" for x in r["in_flight"]]
        if r.get("last_touched_paths"):
            lines.append("\n### Last touched")
            lines += [f"- `{x}`" for x in r["last_touched_paths"]]
    else:
        lines.append("_No prior SessionContext for this surface._")

    open_d = []
    for obj in recent.objects:
        for d in (obj.properties.get("open_decisions") or []):
            open_d.append((obj.properties.get("surface"), d))
            if len(open_d) >= 5:
                break
        if len(open_d) >= 5:
            break
    if open_d:
        lines.append("\n## Open decisions across surfaces")
        for s, d in open_d:
            lines.append(f"- ({s}) {d}")

    lines.append("")
    lines.append(
        f"_session_id: {session_id} | tenant: {tenant} | generated: {dt.datetime.utcnow().isoformat()}Z_"
    )
    return "\n".join(lines)


@mcp.tool(
    name="shanebrain_distill_session",
    annotations={"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False},
)
def shanebrain_distill_session(
    session_id: str,
    surface: str,
    summary: str = "",
    open_decisions: list[str] | None = None,
    in_flight: list[str] | None = None,
    last_touched_paths: list[str] | None = None,
    tenant: str = "shane",
) -> dict:
    """
    Upsert SessionContext keyed by session_id. Call at session end to persist
    what was done, what's open, and what files were touched. Idempotent.
    """
    import datetime as dt
    from weaviate.classes.query import Filter

    now = dt.datetime.utcnow().isoformat(timespec="seconds") + "Z"
    obj = {
        "session_id": session_id,
        "surface": surface,
        "ended_at": now,
        "summary": summary,
        "open_decisions": open_decisions or [],
        "in_flight": in_flight or [],
        "last_touched_paths": last_touched_paths or [],
        "tenant": tenant,
        "schema_version": 1,
    }

    with _weaviate() as h:
        col = h.client.collections.get("SessionContext")

        existing = col.query.fetch_objects(
            filters=Filter.by_property("session_id").equal(session_id),
            limit=1,
        )

        if existing.objects:
            uuid = existing.objects[0].uuid
            col.data.update(uuid=uuid, properties=obj)
            return {"status": "updated", "uuid": str(uuid)}
        else:
            obj["started_at"] = now
            uuid = col.data.insert(properties=obj)
            return {"status": "created", "uuid": str(uuid)}
```

**Smoke-test (fastest — tests Python function directly, bypasses MCP transport):**

```bash
# Write path
docker exec shanebrain-mcp python3 -c "
import sys, warnings; sys.path.insert(0, '/app'); warnings.filterwarnings('ignore')
from server import shanebrain_distill_session
print(shanebrain_distill_session(
    session_id='smoke-test-1', surface='claude_code',
    summary='runbook smoke test',
    open_decisions=['verify hooks fire on next session'],
))
"

# Read path — should return the summary above
docker exec shanebrain-mcp python3 -c "
import sys, warnings; sys.path.insert(0, '/app'); warnings.filterwarnings('ignore')
from server import shanebrain_session_start_context
print(shanebrain_session_start_context(surface='claude_code', session_id='smoke-test-read-1'))
"
```

**Expect write:** `{'status': 'created', 'uuid': '...'}`. **Expect read:** markdown starting with `# SessionContext — surface=claude_code` containing the written summary.

---

## Step 5 — Restart MCP and verify the tools loaded

**Reality:** The startup log prints a hardcoded tool count ("35 tools") — not dynamic. Verify by importing directly.

```bash
docker restart shanebrain-mcp && sleep 4
docker logs --tail 10 shanebrain-mcp 2>&1 | grep -E 'Starting|error|Traceback'

# Verify both functions loaded
docker exec shanebrain-mcp python3 -c "
import sys, warnings; sys.path.insert(0, '/app'); warnings.filterwarnings('ignore')
import server
print('session_start_context:', callable(server.shanebrain_session_start_context))
print('distill_session:', callable(server.shanebrain_distill_session))
"
```

**Expect:** no Traceback in logs; both print `True`.

**Note:** MCP transport is StreamableHTTP at `/mcp` (JSON-RPC envelopes). Plain REST `curl http://localhost:8100/tools/...` returns 404 — that is expected. Use the python3 import method above for smoke tests, or the MCP client tools if available.

---

## Step 6 — Verify the hooks

The hooks are committed at `.claude/hooks/session-start.sh` and `.claude/hooks/session-end.sh`. Settings at `.claude/settings.json`.

**Hook strategy (verified 2026-04-28):** hooks call Weaviate v1 REST directly (`http://localhost:8080/v1/graphql`). They do NOT call MCP tools via `/tools/*` (those return 404 on StreamableHTTP transport). The MCP tools exist for Phase 2 surfaces.

**Write-path note:** `POST /v1/objects` triggers vectorization via nomic-embed-text (~2.8s). Stop hook uses 10s timeout for write operations to avoid false "timed out" failures.

```bash
cat .claude/settings.json
ls -la .claude/hooks/
bash .claude/hooks/session-start.sh
```

**Expect:** the start hook prints `# SessionContext — surface=claude_code` markdown with last session summary, or `<!-- ShaneBrain SessionContext unavailable... -->` if no prior records exist. Both are success — non-blocking is the contract.

---

## Step 7 — Eat the dog food: start a fresh Claude session in this repo

```bash
cd ~/claude-memory
claude
```

When the session opens, the SessionStart hook fires and the digest is injected as additionalContext. Ask Claude:

> "What did you read at session start? Quote the SessionContext header."

**Expect:** Claude quotes the `# SessionContext — surface=claude_code` block. If it can't, the hook didn't fire — verify `cat .claude/settings.json` matches the `{matcher, hooks: [{type, command}]}` schema. Different Claude Code versions accept different shapes.

Do a small piece of work in that session. End the session with `/quit` or Ctrl-D. The Stop hook fires; SessionContext is upserted.

Verify the write happened (weaviate-client v4 syntax):

```bash
curl -fsS -X POST http://localhost:8080/v1/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{Get{SessionContext(sort:[{path:[\"ended_at\"],order:desc}],limit:3){session_id surface summary ended_at}}}"}' \
  | python3 -m json.tool
```

**Expect:** the most recent row has `surface=claude_code` and an `ended_at` within the last few minutes.

---

## Step 8 — Commit the runbook outcome and stop

```bash
cd ~/claude-memory
git status
# If ARCHITECTURE.md or CLAUDE.md needs an update reflecting what context_snapshot
# actually did, edit, then:
git add -A
git commit -m "Phase 1 verified: SessionContext live, hooks firing, end-to-end working"
git push origin claude/multi-agent-memory-architecture-1cx6b
```

Phase 1 is done. The Pi-Termius surface is the first to never start cold.

---

## Failure recovery

| Symptom | First check |
|---|---|
| Hook script returns nothing | `bash -x .claude/hooks/session-start.sh` to trace |
| MCP tool 404 on `/tools/*` | Expected — transport is StreamableHTTP at `/mcp`. Test tools via `docker exec shanebrain-mcp python3 -c "import sys; sys.path.insert(0,'/app'); ..."` |
| Weaviate v3 client error | weaviate-client is v4.21.0; v3 `weaviate.Client(...)` is removed. Use `_weaviate()` helper or v1 REST |
| Stop hook write times out | Vectorization via nomic-embed-text takes ~2.8s; hook uses 10s timeout. Increase if still timing out |
| `172.17.0.1` unreachable from Weaviate container | Confirmed reachable on shanebrain. If not, find gateway with `docker network inspect shanebrain-network` |
| SessionStart hook fires but Claude doesn't see context | Hook output appears in system-reminder under `SessionStart:startup hook success:` — check logs |

## What this runbook does NOT do

- Phase 2 (Angel Cloud Gateway public route, Claude.ai Project template, Agent SDK helper). See `docs/ARCHITECTURE.md`.
- Phase 3 (Ultra migration, multi-tenant, backups). See `docs/ARCHITECTURE.md`.
- Modify `claudemd-sync` or any MEGA Crew bot. Untouched by Phase 1.
