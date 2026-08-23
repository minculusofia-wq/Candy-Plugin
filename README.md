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
