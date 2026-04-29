#!/usr/bin/env bash
# Stop hook — marks session closed in Weaviate.
#
# TRANSPORT RATIONALE: see session-start.sh. Pi hooks use Weaviate v1 REST
# directly. For meaningful summaries (open_decisions, in_flight, touched paths),
# call shanebrain_distill_session MCP tool explicitly during the session before
# stopping. This hook is a safety net: it upserts a stub so the next session
# always has an ended_at marker even if distillation wasn't called.
#
# MULTI-NODE: works from any Tailscale-bound node. WEAVIATE default resolves to
# localhost on shanebrain (Pi), Tailscale hostname `shanebrain` everywhere else.
# Surface is per-node (`claude_code:<hostname>`) so each machine threads its own
# continuity instead of overwriting a shared one.
#
# Upsert logic: if a SessionContext already exists for this session_id
# (written by shanebrain_distill_session during the session), PATCH ended_at
# only. If not, create a minimal stub.
#
# NON-BLOCKING: failures log to stderr and exit 0.

set -u

NODE="$(hostname 2>/dev/null || echo unknown)"
SESSION_ID="$(cat /tmp/shanebrain/claude-session-id 2>/dev/null || echo "unknown-$(date +%s)")"
SURFACE="claude_code:${NODE}"

if [ "$NODE" = "shanebrain" ]; then
  WEAVIATE_DEFAULT="http://localhost:8080"
else
  WEAVIATE_DEFAULT="http://shanebrain:8080"
fi
WEAVIATE="${SHANEBRAIN_WEAVIATE_URL:-$WEAVIATE_DEFAULT}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$SESSION_ID" "$SURFACE" "$WEAVIATE" "$NOW" <<'PY'
import sys, json, urllib.request

session_id, surface, weaviate, now = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def post(url, data, timeout=10):
    req = urllib.request.Request(url, data=json.dumps(data).encode(),
                                  headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())

def patch(url, data):
    req = urllib.request.Request(url, data=json.dumps(data).encode(),
                                  headers={"Content-Type": "application/json"}, method="PATCH")
    urllib.request.urlopen(req, timeout=10)

# Check if this session already has a SessionContext (fast read, short timeout)
gql = {"query": '{Get{SessionContext(where:{path:["session_id"],operator:Equal,valueText:"' + session_id + '"},limit:1){_additional{id}session_id}}}'}
try:
    rows = post(weaviate + "/v1/graphql", gql, timeout=3).get("data", {}).get("Get", {}).get("SessionContext") or []
except Exception:
    rows = []

try:
    if rows:
        obj_id = rows[0]["_additional"]["id"]
        patch(weaviate + f"/v1/objects/SessionContext/{obj_id}", {"properties": {"ended_at": now}})
    else:
        post(weaviate + "/v1/objects", {
            "class": "SessionContext",
            "properties": {
                "session_id": session_id, "surface": surface,
                "started_at": now, "ended_at": now,
                "summary": "Session closed without explicit distillation.",
                "tenant": "shane", "schema_version": 1,
                "open_decisions": [], "in_flight": [], "last_touched_paths": [],
            }
        })
except Exception as e:
    print(f"shanebrain: session-end write failed: {e}", file=sys.stderr)
PY

exit 0
