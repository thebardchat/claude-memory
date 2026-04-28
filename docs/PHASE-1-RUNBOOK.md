# Phase 1 Runbook — ShaneBrain Continuity Layer

Single goal: **a fresh Claude Code session on `shanebrain`, started from Termius via Tailscale, reads its prior state from Weaviate at start and writes its distilled state at end. Zero cold start.**

Run order matters. Each step is independently verifiable — if a connection drops mid-step, re-run that step. Steps 6–9 are the only ones that mutate the MCP server; everything before is read-only.

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

Goal: one new class. Idempotent — re-running is safe.

```bash
docker exec shanebrain-mcp python - <<'PY'
import weaviate
client = weaviate.Client("http://shanebrain-weaviate:8080")

if client.schema.exists("SessionContext"):
    print("SessionContext exists — leaving alone")
else:
    client.schema.create_class({
        "class": "SessionContext",
        "vectorizer": "text2vec-ollama",
        "moduleConfig": {
            "text2vec-ollama": {
                "apiEndpoint": "http://host.docker.internal:11434",
                "model": "nomic-embed-text"
            }
        },
        "properties": [
            {"name": "session_id",         "dataType": ["text"]},
            {"name": "surface",            "dataType": ["text"]},
            {"name": "started_at",         "dataType": ["date"]},
            {"name": "ended_at",           "dataType": ["date"]},
            {"name": "summary",            "dataType": ["text"]},
            {"name": "open_decisions",     "dataType": ["text[]"]},
            {"name": "in_flight",          "dataType": ["text[]"]},
            {"name": "last_touched_paths", "dataType": ["text[]"]},
            {"name": "tenant",             "dataType": ["text"]},
            {"name": "schema_version",     "dataType": ["int"]},
        ],
    })
    print("Created SessionContext")
PY
```

**Expect:** `Created SessionContext` (first run) or `SessionContext exists — leaving alone` (subsequent runs).

**Note:** Weaviate-in-Docker reaches host Ollama via `host.docker.internal` (added to the container's hosts); if your container can't, see `.claude/projects/-home-shanebrain/CLAUDE.md` rule about `172.17.0.1` and adjust the `apiEndpoint`.

---

## Step 4 — Add the two new MCP tools to `server.py`

Goal: read and write tools, both idempotent.

The exact location to edit: `/app/server.py` **inside the `shanebrain-mcp` container**. The container mounts the host source — verify the host path on your Pi (commonly `/mnt/shanebrain-raid/shanebrain-core/mcp/server.py` or wherever the volume mounts) before editing on the host:

```bash
docker inspect shanebrain-mcp \
  --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
```

Edit on the host, then restart the container in Step 5. **Append** these two tool definitions; do not replace existing ones.

```python
@mcp.tool()
def shanebrain_session_start_context(surface: str, session_id: str, tenant: str = "shane") -> str:
    """Return a markdown digest for session boot: last SessionContext for this
    surface + top 5 open_decisions across all surfaces + last 3 PersonalDoc
    'red line' entries. Markdown shape, ready for system-prompt injection."""
    import weaviate, datetime as dt
    c = weaviate.Client("http://shanebrain-weaviate:8080")

    last = (c.query
        .get("SessionContext", ["session_id", "surface", "summary", "open_decisions",
                                "in_flight", "last_touched_paths", "ended_at"])
        .with_where({"path": ["surface"], "operator": "Equal", "valueText": surface})
        .with_sort([{"path": ["started_at"], "order": "desc"}])
        .with_limit(1)
        .do())

    decisions = (c.query
        .get("SessionContext", ["open_decisions", "surface", "started_at"])
        .with_sort([{"path": ["started_at"], "order": "desc"}])
        .with_limit(20)
        .do())

    lines = [f"# SessionContext — surface={surface}", ""]
    rows = (last.get("data", {}).get("Get", {}).get("SessionContext") or [])
    if rows:
        r = rows[0]
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
    for r in (decisions.get("data", {}).get("Get", {}).get("SessionContext") or []):
        for d in (r.get("open_decisions") or []):
            open_d.append((r.get("surface"), d))
            if len(open_d) >= 5:
                break
        if len(open_d) >= 5:
            break
    if open_d:
        lines.append("\n## Open decisions across surfaces")
        for s, d in open_d:
            lines.append(f"- ({s}) {d}")

    lines.append("")
    lines.append(f"_session_id: {session_id} | tenant: {tenant} | generated: {dt.datetime.utcnow().isoformat()}Z_")
    return "\n".join(lines)


@mcp.tool()
def shanebrain_distill_session(
    session_id: str,
    surface: str,
    summary: str | None = None,
    open_decisions: list[str] | None = None,
    in_flight: list[str] | None = None,
    last_touched_paths: list[str] | None = None,
    tenant: str = "shane",
) -> dict:
    """Upsert SessionContext keyed by session_id. Idempotent."""
    import weaviate, datetime as dt
    c = weaviate.Client("http://shanebrain-weaviate:8080")
    now = dt.datetime.utcnow().isoformat() + "Z"

    existing = (c.query
        .get("SessionContext", ["_additional { id }"])
        .with_where({"path": ["session_id"], "operator": "Equal", "valueText": session_id})
        .with_limit(1).do())

    obj = {
        "session_id": session_id,
        "surface": surface,
        "ended_at": now,
        "summary": summary or "",
        "open_decisions": open_decisions or [],
        "in_flight": in_flight or [],
        "last_touched_paths": last_touched_paths or [],
        "tenant": tenant,
        "schema_version": 1,
    }

    rows = existing.get("data", {}).get("Get", {}).get("SessionContext") or []
    if rows:
        uuid = rows[0]["_additional"]["id"]
        c.data_object.update(obj, "SessionContext", uuid)
        return {"status": "updated", "uuid": uuid}
    else:
        obj["started_at"] = now
        uuid = c.data_object.create(obj, "SessionContext")
        return {"status": "created", "uuid": uuid}
```

**Note:** Weaviate client API is v3-style above. If `shanebrain-mcp` runs `weaviate-client>=4`, port the calls to `client.collections.get(...)`. Check with `docker exec shanebrain-mcp pip show weaviate-client | grep Version`.

---

## Step 5 — Restart MCP and verify the tools loaded

```bash
docker restart shanebrain-mcp
sleep 3
docker logs --tail 50 shanebrain-mcp | grep -E 'session_start_context|distill_session|error|Traceback'
```

**Expect:** both tool names appear in the load log; no traceback. If a traceback appears, fix `server.py` and repeat Step 5.

Quick read-path smoke test:

```bash
curl -fsS -X POST http://localhost:8100/tools/shanebrain_session_start_context \
  -H 'Content-Type: application/json' \
  -d '{"surface":"claude_code","session_id":"runbook-test-1"}'
```

**Expect:** markdown starting with `# SessionContext — surface=claude_code`.

Quick write-path smoke test:

```bash
curl -fsS -X POST http://localhost:8100/tools/shanebrain_distill_session \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"runbook-test-1","surface":"claude_code","summary":"runbook smoke test","open_decisions":["verify hooks fire on next session"]}'
```

**Expect:** `{"status":"created", ...}` first time, `"updated"` after.

Re-run the read; the summary should now appear under "Last session."

---

## Step 6 — Verify the hooks are present in this repo

The hooks are already committed at `.claude/hooks/session-start.sh` and `.claude/hooks/session-end.sh`. Settings at `.claude/settings.json`. Confirm:

```bash
cat .claude/settings.json
ls -la .claude/hooks/
bash .claude/hooks/session-start.sh
```

**Expect:** the SessionStart hook prints either the markdown digest from Step 5's read test or the `<!-- ... unavailable ... -->` fallback comment. **Either is success — non-blocking is the contract.**

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

Verify the write happened:

```bash
docker exec shanebrain-mcp python -c "
import weaviate
c = weaviate.Client('http://shanebrain-weaviate:8080')
r = c.query.get('SessionContext',['session_id','surface','summary','ended_at']).with_sort([{'path':['ended_at'],'order':'desc'}]).with_limit(3).do()
import json; print(json.dumps(r, indent=2))
"
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
| MCP tool 404 | `curl http://localhost:8100/tools` to list registered tools |
| Weaviate client errors | `docker exec shanebrain-mcp pip show weaviate-client` — port v3 → v4 if needed |
| `host.docker.internal` not resolving | Use `172.17.0.1` per the Pi rule in `.claude/projects/-home-shanebrain/CLAUDE.md` |
| SessionStart hook fires but Claude doesn't see context | SessionStart stdout is injected as additional context automatically. If not appearing, check that the hook is actually firing (`bash -x .claude/hooks/session-start.sh`) and that stdout is non-empty |

## What this runbook does NOT do

- Phase 2 (Angel Cloud Gateway public route, Claude.ai Project template, Agent SDK helper). See `docs/ARCHITECTURE.md`.
- Phase 3 (Ultra migration, multi-tenant, backups). See `docs/ARCHITECTURE.md`.
- Modify `claudemd-sync` or any MEGA Crew bot. Untouched by Phase 1.
