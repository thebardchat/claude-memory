# CLAUDE.md Precedence — Global vs Repo

The single rule that resolves "which file owns this?"

## Two files, two scopes

| File | Path | Loads when | Owns |
|---|---|---|---|
| **Global** | `~/.claude/CLAUDE.md` | Every Claude Code session, every repo, every machine the user works from | Identity, values, mesh constants, hardware constraints, red lines, banned words, communication style |
| **Repo** | `<repo>/CLAUDE.md` | Sessions inside this repository only | Project purpose, branch policy, file layout, build/test commands, project conventions, current phase |

Both files load. Both apply. They are layered, not exclusive.

## The seven rules

1. **Global owns identity. Repo owns project behavior.** A repo file does not redefine who Shane is, what the mesh is, what the equation is, or what the red lines are. A global file does not name your branches.

2. **Repo may add. Repo may not relax.** A repo can add stricter rules ("in this repo, no new dependencies without an issue"). A repo cannot remove a global red line.

3. **Identity wins on identity questions. Repo wins on project questions.** If a repo file says "use breezy tone" and global says "no filler, banned words apply," the banned words list still applies — tone layers on top of the floor that global sets.

4. **Both files declare scope on line 1.**
   - Global: `Scope: every Claude session. Repo CLAUDE.md files may extend but not override what's below.`
   - Repo: `Scope: this repository only. Defers to ~/.claude/CLAUDE.md for identity, values, mesh, red lines.`

5. **Don't duplicate facts.** If a fact lives in global, do not restate it in a repo file. Reference the global file by name. Duplication is how drift starts — two copies will eventually disagree, and the wrong one will win on the wrong day.

6. **One source of truth per concern.**
   - Stable facts (mesh hostnames, hardware RAM ceilings, embedding model, vault location) → global.
   - Changing facts (active branch, current phase, today's TODO, file layout) → repo.
   - When unsure, ask: "would another repo of mine need this fact?" If yes, global. If no, repo.

7. **Conflict surfaces as a question, not a silent override.** If a Claude session detects a real conflict between global and repo (not the layered case in rule 3, but a genuine contradiction — e.g., global says "no SaaS over $50/mo," repo says "use $200/mo service X"), Claude must surface the conflict to the user before acting. Silent override is the failure mode this whole document exists to prevent.

## What this prevents

- **The drift problem.** Two CLAUDE.md files saying overlapping things, slowly disagreeing over months, until Claude picks the wrong one.
- **The override problem.** A repo file accidentally relaxing a red line because identity was duplicated and edited in only one place.
- **The "which one am I reading" problem.** Scope declared on line 1 of each file means every session knows.
- **The dilution problem.** Project-specific noise (branch names, build commands) leaking into global and showing up in unrelated sessions.

## Quick test

Before adding a line to either CLAUDE.md, ask:

- Is this true for every project I will ever touch? → **global**
- Is this true only here? → **repo**
- Is this duplicated from the other file? → **delete it; reference instead**
- Does this contradict the other file? → **stop, surface to user, do not commit**
