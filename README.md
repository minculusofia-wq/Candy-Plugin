# Candy Plugin

*English · [Version française](README.fr.md)*

A Claude Code plugin that stops three things:

1. **Claude asserting things it hasn't read.** Every number, filename and technical
   constraint must carry its `file:line` source.
2. **Claude flattering you.** Verdict in the first sentence, flaws before merits,
   no "yes, but" in disguise.
3. **"It's done" without proof.** A universal check figures out on its own how to
   verify the current project and returns a verdict.

Written and used daily by someone who is not a developer, and who needed the tool
to say no.

**The content is in French** — the rules, the commands and the hook messages all
speak French to Claude, which answers in French. This README is the English one;
the plugin itself is not translated. Translating it is issue #1 if anyone wants it.

## Install

```
/plugin marketplace add minculusofia-wq/Candy-Plugin
/plugin install candy-plugin
```

Rules are not loaded by the plugin — Claude Code reads them from your own folder:

```
cp -R rules/*.md ~/.claude/rules/
```

They work on their own. Take one, not all eight.

## What's inside

| | |
|---|---|
| **8 rules** | verify before asserting · brutal honesty · code discipline · phase gate · model choice · working reflexes · communication style · command routing |
| **5 commands** | `/verifier` `/debug` `/fin-phase` `/fin-session` `/maj-docs` |
| **2 agents** | `relecteur-securite` · `relecteur-de-phase` — security and phase reviewers running in a fresh context, so they don't eat your conversation |
| **13 hooks + 2 scripts** | phase-opening reminder, pre-write guard, secret protection, pre-push check, answer review at the end of each turn |

### The most useful piece: `hooks/verifier-projet.sh`

A zero-config script that, on any project, looks for a way to verify it (tests,
lint, types, build) and returns one of three verdicts:

- `0` everything passes
- `1` at least one check fails
- `2` **there is no way to verify this project** — the most useful case, and the
  one nothing else tells you about

## Which projects is this for? Bots, apps, and everything else

These rules were forged on two fronts: **trading bots** running non-stop on a
server, and an **iOS app** built phase by phase. Most of it depends on neither.

| Works anywhere | Specific to bots and long-running services | Specific to apps built in phases |
|---|---|---|
| **Rules**: verify before asserting · brutal honesty · code discipline · working reflexes · model choice · command routing | The "bot strategies" section of `brutal-honesty.md` | `porte-de-phase.md` |
| **Commands**: `/verifier` · `/maj-docs` | `/debug` (dry-run mode, never on the server) · `/fin-session` | `/fin-phase` |
| **Agents**: `relecteur-securite` | Its "funds and transactions" section | `relecteur-de-phase` |
| **Hooks**: project check, secret protection, pre-write guard, README before push, answer review, `.md` audit | `rule5-debug-local-only.sh` (blocks SSH except read-only) · `rule13-source-or-silence.sh` | `ouverture-de-phase.sh` · `rule12-phase-debug-required.sh` |

**In short:** if you build neither bots nor phased apps, take the first column —
that's already the heart of it. Nothing forces you to install everything: rules
are copied one at a time, and a hook is removed by deleting its line in
`hooks/hooks.json`.

The examples talk about trading and iPhones because that's where these rules were
paid for. The principle doesn't change: **nothing is true because Claude wrote
it** — not on a bot, not on an app, not on a three-line script.

## `/fin-session` or `/fin-phase`? The question that comes up most

Both close a piece of work. They don't close the same thing.

**`/fin-session` closes a working session.** The project itself keeps running — a
bot in production is never "done". The command leaves the repo clean: optional
debug, `.md` audit, docs updated, **one** commit, push, summary. It doesn't judge
the work, it tidies it.

**`/fin-phase` closes a delivery.** An app built in phases reaches states you
declare reached — and that declaration can be false. The command re-reads the
phase's exit gate **point by point**, lists what only a real device can settle,
and returns one of **three** verdicts:

| Verdict | Meaning |
|---|---|
| `ROUGE` (red) | A machine check fails. Stop, fix it. |
| `EN ATTENTE DE TON APPAREIL` (waiting on your device) | Green on the machine side; some points only you can settle. |
| `VERT` (green) | You answered everything. |

The 🟢 in the roadmap and the git tag are only set on `VERT`.

### How to choose in three seconds

> **Does your project have a roadmap with numbered phases, some of which can only
> be checked by hand — on a phone, a screen, a real device?**
>
> Yes → `/fin-phase`. No → `/fin-session`.

In practice: a bot, a script, a running service → `/fin-session`. An app built
phase by phase → `/fin-phase`.

### What happens if you pick the wrong one

| | |
|---|---|
| `/fin-session` on a phased app | The repo is clean and the docs current, but **nothing checked that the phase was actually delivered**. A phase turns green on the strength of tests that can't see a dead button. |
| `/fin-phase` on a bot | It looks for a roadmap and an exit gate that don't exist. It stops without breaking anything — it just does nothing useful. |

A guardrail mistaken for a validation is worse than no guardrail: that is exactly
what `/fin-phase` exists to prevent, and why it refuses to conclude on its own.

### The two answer each other

`/fin-phase` holds the **exit gate** of a phase. The rule
[porte-de-phase.md](rules/porte-de-phase.md) holds the **entry gate** of the next
one, and the `ouverture-de-phase.sh` hook repeats it when the next conversation
starts. A phase never closes without you, and the next never opens on a false state.

## Requirements

- `jq` and `python3` (used by the hooks)
- Tested on macOS. The hooks are plain bash; Linux should work, untested.
- `skills-reminder.sh` suggests `/grill-with-docs` and `/tdd`, third-party skills
  not shipped here. Without them it only suggests.

## Deliberately not included

The author's trading rules, risk thresholds and strategy patterns. They only serve
their own bots.

## Support

Shared as is. Issues are read, not guaranteed.

## License

MIT.
