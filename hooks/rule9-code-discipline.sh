#!/bin/bash
#
# rule9-code-discipline.sh (PreToolUse: Edit|Write)
# Regle 9: Discipline de code - commit avant de modifier
#
# Warner si le working tree a beaucoup de modifs non committees.
#

set -e

INPUT=$(cat)
json_get() { python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('tool_input',{}).get('$1',''))" <<< "$INPUT" 2>/dev/null; }

FILE_PATH=$(json_get file_path)

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if ! git -C "$PROJECT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# Compter les fichiers modifies non committes
UNCOMMITTED_COUNT=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# Si plus de 10 fichiers modifies, avertir
if [[ "$UNCOMMITTED_COUNT" -gt 10 ]]; then
    echo "=== REGLE 9: CODE-DISCIPLINE ===" >&2
    echo "Working tree sale: $UNCOMMITTED_COUNT fichiers non committes" >&2
    echo "L'utilisateur prefere des commits frequents (ceinture de securite)." >&2
    echo "Considere faire un commit AVANT de continuer a modifier du code." >&2
    echo "=== FIN REGLE 9 ===" >&2
fi

exit 0
