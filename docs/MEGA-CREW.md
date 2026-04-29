# MEGA Crew

A separate product line inside ShaneBrain, not infrastructure. **Treat it as load-bearing until verified otherwise.**

## What it is

Sixteen Python bots, each a character with a defined purpose, running 24/7 on `shanebrain` (Pi 5). Their logs aggregate over a 24-hour cycle into a story arc that gets rendered as a **noir-style comic book** and published to **GitHub + Cloudflare** with a new episode every day.

The bots are also designed to **evolve their own code**, with **Gemini Sidekick** suggesting changes and **Arc** (one of the bots) gatekeeping every commit before any change lands.

## The 16 bots and their zones

Per `.claude/projects/-home-shanebrain/CLAUDE.md` (2026-04-03 snapshot — verify against current `bot_status.json` if drifted):

| Zone | Bots | Purpose |
|---|---|---|
| Brain | Sparky, Volt, Neon, Glitch | Sparky: training mining. Volt: drift detection. Neon: Weaviate embedding. Glitch: adversarial testing. |
| Left Hand | Rivet, Torch, Weld | Rivet: dedup + format. Torch: prompt suggestions. Weld: commit executor (the only bot Arc lets push). |
| Right Hand | Blaze, Arc, Flux | Blaze: context injection. **Arc: gatekeeper — nothing writes core files without Arc approval.** Flux: health monitor. |
| Left Foot | Bolt, Stomp, Grind | Bolt: log pattern analysis. Stomp: memory conflict resolution. Grind: bulk re-embedding. |
| Right Foot | Crank, Spike, Forge | Crank: scheduler. Spike: IQ benchmarking. Forge: tool stub drafter (drops to `/mnt/shanebrain-raid/shanebrain-core/tools/pending/` for Shane review). |

## The pipeline (design intent)

```
24h tick cycle
  ↓ each bot writes to bus.db (SQLite at /mnt/shanebrain-raid/shanebrain-core/mega/bus.db)
  ↓ logs aggregate into a daily story arc
  ↓ noir-style render (model TBD)
  ↓ comic episode pushed to GitHub repo (URL TBD — confirm with Shane)
  ↓ Cloudflare publishes
  ↓ new episode visible "every day"

Parallel: evolution loop
  ↓ Gemini Sidekick reviews bot code
  ↓ proposes refactor / addition
  ↓ Arc evaluates against the 50 red lines
  ↓ Arc approves / rejects
  ↓ Weld executes the approved commit
```

## Dependencies — current

- **Ollama on Pi (port 11434)** with `llama3.1:8b` and `mega-brain` model — used by bots for inference.
- **Possibly Ollama cluster proxy (port 11435)** routing heavy inference to `pulsar` (priority 1, llama3.1:8b). Needs verification — see "Verification queue" below.
- **Weaviate `BotMemory` class** filtered by `bot_name`, vectorized via `text2vec-ollama` (`nomic-embed-text`).
- **Arc** gates writes to core files (the `Stomp`, `Grind`, `Weld` operations).
- **systemd service `mega-crew.service`** at `/mnt/shanebrain-raid/shanebrain-core/mega/`.
- **Supervisor**: `crew_supervisor.py` — launches all 16, restarts crashes, writes `bot_status.json` every 30s.
- **Persona**: `/mnt/shanebrain-raid/shanebrain-core/mega/persona.json`.
- **Training corpus**: `/mnt/shanebrain-raid/shanebrain-core/mega/training.jsonl` (growing).

## Status — needs verification

Shane himself flagged uncertainty (2026-04-29): "I would have to check to make sure that the evolving and helping is actually happening." Until verified, treat the following as **design intent, not confirmed running**:

- ☐ Are all 16 bots currently up? Check `bot_status.json` and `systemctl status mega-crew`.
- ☐ Is the evolution loop firing? Look at recent commits authored by `Weld` in core repos. If silent for >7 days, the loop is broken.
- ☐ Is Gemini Sidekick still being called? Check Gemini API logs / billing for recent activity.
- ☐ Is Arc actually evaluating proposals? Search bus.db for recent Arc decisions.
- ☐ Is the comic publishing daily? Check the comic GitHub repo (URL: TBD with Shane) for episode timestamps.
- ☐ Is Cloudflare serving the latest episode?

## Verification queue (do when there's time, not tonight)

```bash
# On shanebrain:
systemctl status mega-crew
cat /mnt/shanebrain-raid/shanebrain-core/mega/bot_status.json | jq '.bots | length, .last_updated'
ls -lt /mnt/shanebrain-raid/shanebrain-core/tools/pending/ | head
sqlite3 /mnt/shanebrain-raid/shanebrain-core/mega/bus.db \
  "SELECT bot_name, MAX(ts) FROM messages GROUP BY bot_name;"
```

Whatever comes back tells you whether MEGA Crew is doing the thing it was designed to do. If yes, it's load-bearing — keep Ollama on the Pi, keep `mega-crew.service`, keep Pulsar in the cluster routing if it's serving heavy inference. If no, that's a separate decision: revive or retire.

## Hard rules (do not violate)

- **Never bypass Arc** when MEGA Crew bots are involved in writes (this is a global red line).
- **Don't move MEGA Crew off the Pi** without a planned migration — they share `bus.db` SQLite, and the supervisor pattern depends on shared local filesystem.
- **Don't kill the Pi's Ollama daemon** without confirming MEGA Crew's inference path. The `llama3.1:8b` and `mega-brain` models on Ollama are part of MEGA Crew's runtime.

## Why this doc exists

Two Claude sessions in a row (mine, 2026-04-29) almost recommended decommissioning components MEGA Crew depends on — Open WebUI being a related cleanup, then Ollama broadly. That happened because MEGA Crew's purpose wasn't captured anywhere a Claude session would read at boot. This doc fixes that.

If you're a Claude session reading this for the first time: **do not propose removing or downgrading anything in the "Dependencies — current" list above without first running the "Verification queue" and surfacing the result to Shane.**
