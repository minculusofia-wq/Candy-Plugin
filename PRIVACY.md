# Privacy policy — Candy Plugin

*Last updated: 2026-09-26*

Candy Plugin runs entirely on your machine. Its author runs no server and
collects nothing: no analytics, no telemetry, no account.

## What leaves your machine

**The plugin's own code sends nothing over the network.**

One command can cause network traffic through *your project's* tooling:
`/verifier` runs your project's `make audit` target when your Makefile has one.
A dependency audit such as `pip-audit` or `npm audit` contacts its package
registry. The end-of-turn check never runs it.

Everything Claude reads through the plugin is part of your normal Claude Code
conversation and follows Anthropic's own terms for that conversation.

## What the plugin reads, locally

- **What Claude Code hands to its hooks**: the command about to run, the file
  about to be written and its content, Claude's reply at the end of a turn.
  The guards read them to block a secret from being written, printed or
  committed.
- **Secret files, to protect them**: to decide whether a command would print a
  secret, the guards may look at a local file such as `.env` or `.npmrc`. A
  value is never printed, stored or sent; refusal messages are fixed text.
- **Your project**: git state (`git status`, `git log`, `git ls-files`), its
  Markdown documents for the document-set check, and its test suite, which the
  end-of-turn check runs when code changed during the turn.
- **Your Claude Code setup**: `~/.claude/CLAUDE.md`, `~/.claude/rules/`,
  `~/.claude/skills/`, `~/.claude/settings.json`, and the optional files
  `~/.claude/rappels-projets.txt` and `~/.claude/projets-bots.txt`.
- **Your conversation transcripts** (`~/.claude/projects/*.jsonl`): read only
  by `/maintenance`, when you run it, to count reviews and audit the setup.
  Nothing is copied out of them.

## What the plugin writes, locally

| Where | What | Why |
|---|---|---|
| The plugin's data folder (`~/.claude/plugins/data/`), or the temp folder | The project's git state at each message | To know what changed during a turn |
| `~/.cache/claude-jeu-de-documents/` | Result of the document-set check, per project (file named by a hash of the path) | To avoid repeating the check |
| `.git/claude-cloture-avant` in your project | The current commit id | Phase-closing check |
| `~/.claude/.maintenance-dernier-releve` | The date and result of the last `/maintenance` | Maintenance reminder |
| The temp folder (`$TMPDIR`) | Empty markers and short-lived test output | One review per message; test run |

## Retention and deletion

Everything stays on your machine until you delete it. To remove it, uninstall
the plugin and delete the paths in the table above.

## Children

The plugin is a developer tool and is not intended for people under 18.

## Contact

Questions: open an issue at
<https://github.com/minculusofia-wq/Candy-Plugin/issues>.
