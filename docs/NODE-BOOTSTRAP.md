# Node Bootstrap

How to set up any of Shane's nodes so its Claude Code sessions automatically know about this repo as the project-architecture source.

**Goal:** SSH into any node (`shanebrain`, `ultra`, `pulsar`, `bullfrog`, `jaxton`, etc.) via Termius/Tailscale, paste one block, and from then on every Claude Code session on that node finds the brain's design before asking what to do.

## Step 1 — Clone the repo to a known path

### Linux / macOS / Git-Bash on Windows

Paste:

```bash
git clone https://github.com/thebardchat/claude-memory.git ~/claude-memory 2>/dev/null \
  || (cd ~/claude-memory && git fetch origin && git pull)
ls ~/claude-memory/CLAUDE.md && echo "Repo present at ~/claude-memory"
```

The `||` branch makes it safe to re-run — clones if missing, pulls if already present.

### Windows native cmd.exe (bullfrog, pulsar, jaxton)

`cmd.exe` doesn't expand `~`. Use `%USERPROFILE%`:

```cmd
cd /d %USERPROFILE%
git clone https://github.com/thebardchat/claude-memory.git claude-memory
cd claude-memory
git pull
dir CLAUDE.md
```

If the repo is already cloned, the `git clone` will print "destination path already exists" — ignore it; the `git pull` on the next line gets the latest.

> **Note for Windows operators:** Shane prefers `cmd.exe` over PowerShell on Windows nodes (per `.claude/projects/-home-shanebrain/CLAUDE.md`). Inside a Claude Code session, the Bash tool runs git-bash and understands `~` — so bash blocks pasted INTO Claude work. The `cmd.exe` syntax above is for the OS shell outside Claude.

## Step 2 — Suggest a global `~/.claude/CLAUDE.md` (does not overwrite)

### Linux / macOS / Git-Bash

Paste:

```bash
mkdir -p ~/.claude
if [ ! -f ~/.claude/CLAUDE.md ]; then
  cp ~/claude-memory/docs/global-CLAUDE.md.template.md ~/.claude/CLAUDE.md.suggested
  echo "No existing ~/.claude/CLAUDE.md. Suggested template copied to ~/.claude/CLAUDE.md.suggested."
  echo "Review it. When you're ready: mv ~/.claude/CLAUDE.md.suggested ~/.claude/CLAUDE.md"
else
  cp ~/claude-memory/docs/global-CLAUDE.md.template.md ~/.claude/CLAUDE.md.template-latest
  echo "Existing ~/.claude/CLAUDE.md preserved."
  echo "Latest template at ~/.claude/CLAUDE.md.template-latest — diff and merge by hand:"
  echo "  diff ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.template-latest"
fi
```

This **never** overwrites your real global file. It either suggests one (if missing) or drops the latest template alongside for manual diff/merge.

### Windows native cmd.exe

```cmd
if not exist %USERPROFILE%\.claude mkdir %USERPROFILE%\.claude
if not exist %USERPROFILE%\.claude\CLAUDE.md (
  copy /Y %USERPROFILE%\claude-memory\docs\global-CLAUDE.md.template.md %USERPROFILE%\.claude\CLAUDE.md.suggested
  echo Suggested template at %%USERPROFILE%%\.claude\CLAUDE.md.suggested
  echo Review then: move %%USERPROFILE%%\.claude\CLAUDE.md.suggested %%USERPROFILE%%\.claude\CLAUDE.md
) else (
  copy /Y %USERPROFILE%\claude-memory\docs\global-CLAUDE.md.template.md %USERPROFILE%\.claude\CLAUDE.md.template-latest
  echo Existing global preserved. Latest template at %%USERPROFILE%%\.claude\CLAUDE.md.template-latest
)
```

## Step 3 — Smoke test

### Linux / macOS / Git-Bash
```bash
cd ~/claude-memory && claude
```

### Windows native cmd.exe
```cmd
cd /d %USERPROFILE%\claude-memory
claude
```

When the session opens, ask:

> What's the active phase, what branch, and what's the single next thing to do?

You should get back: Phase 1, branch `claude/multi-agent-memory-architecture-1cx6b`, and whatever the runbook says is next. If you don't, the session didn't read `CLAUDE.md` — check that the file exists at `~/claude-memory/CLAUDE.md` and that Claude Code's working directory is `~/claude-memory`.

## Optional — auto-update via systemd user timer

If you want the node to auto-pull master every hour:

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/claude-memory-pull.service <<'EOF'
[Unit]
Description=Pull latest claude-memory repo
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=%h/claude-memory
ExecStart=/usr/bin/git pull --ff-only origin master
EOF

cat > ~/.config/systemd/user/claude-memory-pull.timer <<'EOF'
[Unit]
Description=Hourly claude-memory pull

[Timer]
OnBootSec=2min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now claude-memory-pull.timer
systemctl --user list-timers | grep claude-memory
```

If you're working on a feature branch on this node, the `--ff-only` flag means the pull silently skips when your local state diverges — no surprises. Disable per-node with `systemctl --user disable --now claude-memory-pull.timer`.

## What this gives you

- Every Claude Code session on any of Shane's nodes lands with `CLAUDE.md` already loaded telling it: this is the brain, here's the active phase, here's the branch, here's what to do next.
- Per-node specifics (which services run where, what role this node plays) live in `docs/MESH.md` — also auto-loaded once the repo is cloned.
- No node-specific secrets in this public repo. Vault contents stay in `shanebrain_vault`. Per-machine config stays in each node's own `~/.claude/CLAUDE.md` (which the template seeds but never overwrites).

## What this does NOT do

- Does not install Claude Code itself. Each node needs `claude` already on PATH.
- Does not configure Tailscale, Docker, Ollama, or any other infrastructure on the node.
- Does not push secrets or credentials. Use `shanebrain_vault_search` from inside any session.
- Does not symlink `~/.claude/CLAUDE.md` to the template. The global file is per-node and evolves; the template is a reference snapshot you merge from when something changes.
