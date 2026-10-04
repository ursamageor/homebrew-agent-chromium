# agent-chromium — agent guide

This project packages **ungoogled-chromium plus a few extensions** into one neat package for agent
browser work: a browser that agents (Playwright, CDP, computer-use runs) can install, launch, and drive
predictably, with the extensions they need already set up.

The package has to live **side by side with ursamageor's daily ungoogled-chromium**
(`/Applications/Chromium.app`). Out of the box, both use the same app path, bundle ID, and profile
folder. So the agent build needs its own app name, bundle ID, and data folder, and must never read or
write the daily profile. Start with [`.agents/knowledge/isolation/`](.agents/knowledge/isolation/)
before changing how the app is installed or launched.

## The `.agents/` folder

`AGENTS.md` is the single instruction file for every agent brand (Claude Code, Codex, …) — do not
add a `CLAUDE.md`, it would shadow this file for Claude Code. Everything else agents need lives
under `.agents/`:

```
AGENTS.md                    canonical agent instructions — the only instruction file
.agents/skills/              project skills (canonical home; `.claude/skills` is a symlink to it)
.agents/plans/<name>/        plans — one subfolder per plan
.agents/notes/<topic>/       working notebook — one subfolder per topic
.agents/knowledge/<topic>/   reference docs and specs — one subfolder per topic
.agents/archived/            retired docs — archived/{plans,notes,knowledge}/<name>/
.agents/.env.agents          env vars for agents — gitignored
.claude/skills               symlink → ../.agents/skills; nothing else lives in .claude/ for now
```

Only `.agents/skills/` and `.agents/knowledge/` are committed; the rest of `.agents/` is gitignored
and local to this machine.

### Plans — `.agents/plans/<plan-name>/`

One subfolder per plan: the plan itself plus any prototypes and supporting notes written for it.
Multi-part or multi-phase work belongs here. Plan files that Claude Code's plan mode writes
directly into `.agents/plans/` are the one allowed flat file.

### Notes — `.agents/notes/<topic>/`

The notebook: sketches, ideas, handoffs between sessions, quirks that took a while to track down,
long design back-and-forths, risks to keep an eye on. Write a note whenever something should be
written down somewhere — polish is optional. Reuse a topic folder when one fits; otherwise create
one.

### Knowledge — `.agents/knowledge/<topic>/`

The formal layer: specs, reference docs, info maps — things solidly chosen in the design and worth
coming back to. Add or change knowledge only when asked or when permission has been given; getting
a knowledge doc into good shape may take a whole session. If knowledge grows large,
`.agents/knowledge/INDEX.md` maps it — the only file allowed outside a topic subfolder.

### Archive — `.agents/archived/`

Retired plans, notes, and knowledge move to `.agents/archived/<plans|notes|knowledge>/<name>/`.
Archived material is history, never current instruction — don't execute or trust an archived plan.

### Environment — `.agents/.env.agents`

Environment variables meant for agents (tokens, hosts, IDs). Gitignored and typically low
sensitivity: read it (`cat` or `source`) when you need a value; never commit it.

## Ground rules

- **Never touch the daily profile.** Tests and experiments must not read or write
  `~/Library/Application Support/Chromium` or `~/Library/Caches/Chromium`. Test on a copy of the app,
  and when the target data folder is unproven, guard the run (`scripts/guarded-run.sh`, see the isolation doc).
- **Subfolders, always.** Every document under `plans/`, `notes/`, and `knowledge/` lives in a
  clearly named subfolder — nothing at the root of those folders except `knowledge/INDEX.md` and
  plan-mode files.
- **Mature workflows become skills.** A workflow still stabilizing lives in notes; once it is
  repeatable it becomes a skill in `.agents/skills/`.
- **Markdown style:** wrap lines around 102–112 characters, hard stop at 112.
