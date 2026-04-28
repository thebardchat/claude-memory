"""
ShaneBrain Agent SDK helper — pre/post-flight SessionContext for API jobs.

Usage:
    from agent_sdk_helper import ShaneBrainSession

    with ShaneBrainSession(surface="my_job") as ctx:
        # ctx.system_prompt includes the SessionContext markdown
        response = client.beta.messages.create(
            model="claude-opus-4-7",
            system=ctx.system_prompt + YOUR_SYSTEM_PROMPT,
            messages=[...],
            mcp_servers=ctx.mcp_servers,
            tools=ctx.mcp_tools,
            betas=["mcp-client-2025-11-20"],
        )
        # On exit, ctx.distill() is called automatically.
        # Call ctx.distill() explicitly mid-job to record richer state.

Requirements:
    pip install anthropic
    env: ANTHROPIC_API_KEY, SHANEBRAIN_MCP_URL, SHANEBRAIN_MCP_BEARER
"""

import os
import uuid
import anthropic

SHANEBRAIN_MCP_URL = os.environ.get("SHANEBRAIN_MCP_URL", "https://cloud.theangel.com/mcp")
SHANEBRAIN_MCP_BEARER = os.environ.get("SHANEBRAIN_MCP_BEARER", "")


class ShaneBrainSession:
    def __init__(self, surface: str = "claude_api", tenant: str = "shane"):
        self.surface = surface
        self.tenant = tenant
        self.session_id = str(uuid.uuid4())
        self.client = anthropic.Anthropic()
        self._start_context = ""
        self._distilled = False

    # --- MCP server definition for use in messages.create() ---

    @property
    def mcp_servers(self) -> list[dict]:
        return [{
            "type": "url",
            "url": SHANEBRAIN_MCP_URL,
            "name": "shanebrain",
            "authorization_token": SHANEBRAIN_MCP_BEARER,
        }]

    @property
    def mcp_tools(self) -> list[dict]:
        return [{"type": "mcp_toolset", "mcp_server_name": "shanebrain"}]

    # --- Pre-flight: fetch SessionContext ---

    def fetch_context(self) -> str:
        """Call shanebrain_session_start_context and return markdown digest."""
        try:
            resp = self.client.beta.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=512,
                messages=[{
                    "role": "user",
                    "content": (
                        f"Call shanebrain_session_start_context with "
                        f"surface={self.surface!r} and session_id={self.session_id!r}. "
                        "Return only the raw tool result, no commentary."
                    ),
                }],
                mcp_servers=self.mcp_servers,
                tools=self.mcp_tools,
                betas=["mcp-client-2025-11-20"],
            )
            for block in resp.content:
                if hasattr(block, "type") and block.type == "mcp_tool_result":
                    for c in block.content:
                        if hasattr(c, "text"):
                            return c.text
        except Exception as e:
            return f"<!-- shanebrain_session_start_context unavailable: {e} -->"
        return "<!-- shanebrain_session_start_context: no result -->"

    @property
    def system_prompt(self) -> str:
        if not self._start_context:
            self._start_context = self.fetch_context()
        return self._start_context + "\n\n"

    # --- Post-flight: distill session ---

    def distill(
        self,
        summary: str = "",
        open_decisions: list[str] | None = None,
        in_flight: list[str] | None = None,
        last_touched_paths: list[str] | None = None,
    ) -> None:
        """Upsert SessionContext for this session. Safe to call multiple times."""
        if self._distilled and not summary:
            return
        try:
            args = {
                "session_id": self.session_id,
                "surface": self.surface,
                "summary": summary,
                "open_decisions": open_decisions or [],
                "in_flight": in_flight or [],
                "last_touched_paths": last_touched_paths or [],
                "tenant": self.tenant,
            }
            arg_str = ", ".join(f"{k}={v!r}" for k, v in args.items() if v or k in ("session_id", "surface", "summary"))
            self.client.beta.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=256,
                messages=[{
                    "role": "user",
                    "content": f"Call shanebrain_distill_session with {arg_str}. Return only the tool result.",
                }],
                mcp_servers=self.mcp_servers,
                tools=self.mcp_tools,
                betas=["mcp-client-2025-11-20"],
            )
            self._distilled = True
        except Exception:
            pass  # non-blocking

    # --- Context manager ---

    def __enter__(self):
        self._start_context = self.fetch_context()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if not self._distilled:
            summary = "Session completed." if exc_type is None else f"Session ended with error: {exc_type.__name__}"
            self.distill(summary=summary)
        return False
