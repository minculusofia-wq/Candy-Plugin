#!/bin/bash
#
# rule7-readme-before-push.sh (PreToolUse: Bash)
# Regle 7: README a jour avant chaque push
#
# Verifie si les modifs impactent le README avant git push.
#

set -e

INPUT=$(cat)
json_get() { python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('tool_input',{}).get('$1',''))" <<< "$INPUT" 2>/dev/null; }

COMMAND=$(json_get command)

# Ne se declenche que sur git push
if ! echo "$COMMAND" | grep -qE 'git\s+push'; then
    exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if ! git -C "$PROJECT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# Verifier que le README existe
README=""
for candidate in README.md README.MD Readme.md readme.md; do
    if [[ -f "$PROJECT_DIR/$candidate" ]]; then
        README="$PROJECT_DIR/$candidate"
        break
    fi
done

if [[ -z "$README" ]]; then
    echo "=== REGLE 7: README manquant ===" >&2
    echo "Aucun README trouve dans $PROJECT_DIR" >&2
    echo "Creer un README.md avec: stack, lancement local, ports, .env, strategie" >&2
    echo "=== FIN REGLE 7 ===" >&2
    exit 0
fi

# Detecter si des fichiers importants ont change depuis le dernier push
CHANGED_FILES=$(git -C "$PROJECT_DIR" diff --name-only @{u}..HEAD 2>/dev/null || echo "")

if [[ -z "$CHANGED_FILES" ]]; then
    exit 0
fi

# Fichiers qui DEVRAIENT impacter le README
IMPACTFUL_PATTERNS=(
    'requirements\.txt$'
    'package\.json$'
    '\.env\.example$'
    'config\.py$'
    'settings\.py$'
    'main\.py$'
    'app\.py$'
    'docker-compose\.yml$'
    'Dockerfile$'
    'strategy\.py$'
)

README_LAST_COMMIT=$(git -C "$PROJECT_DIR" log -1 --format=%H -- "$README" 2>/dev/null || echo "")
README_CHANGED=$(echo "$CHANGED_FILES" | grep -iE 'readme' || echo "")

IMPACTFUL_CHANGES=""
for pattern in "${IMPACTFUL_PATTERNS[@]}"; do
    MATCH=$(echo "$CHANGED_FILES" | grep -E "$pattern" || echo "")
    if [[ -n "$MATCH" ]]; then
        IMPACTFUL_CHANGES="$IMPACTFUL_CHANGES\n$MATCH"
    fi
done

if [[ -n "$IMPACTFUL_CHANGES" ]] && [[ -z "$README_CHANGED" ]]; then
    echo "=== REGLE 7: README peut etre obsolete ===" >&2
    echo "Fichiers changes qui peuvent impacter le README:" >&2
    echo -e "$IMPACTFUL_CHANGES" >&2
    echo "" >&2
    echo "Le README n'a pas ete modifie depuis le dernier push." >&2
    echo "Verifier et mettre a jour avant de pusher." >&2
    echo "=== FIN REGLE 7 ===" >&2
fi

exit 0
