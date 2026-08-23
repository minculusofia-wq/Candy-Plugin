#!/bin/bash
#
# rule6-session-end.sh (Stop)
# Regle 6: Fin de session - verifier git, CLAUDE.md, MEMORY.md
#
# Detecte fichiers non committes et rappelle les obligations de fin de session.
#

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Verifier si on est dans un git repo
if ! git -C "$PROJECT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# Detecter fichiers modifies non committes
UNCOMMITTED=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null)
UNPUSHED=$(git -C "$PROJECT_DIR" log --oneline @{u}.. 2>/dev/null || echo "")

NEEDS_ACTION=false
MESSAGES=""

if [[ -n "$UNCOMMITTED" ]]; then
    NEEDS_ACTION=true
    MESSAGES="$MESSAGES\n- Fichiers modifies non committes:\n$UNCOMMITTED"
fi

if [[ -n "$UNPUSHED" ]]; then
    NEEDS_ACTION=true
    MESSAGES="$MESSAGES\n- Commits non pushes:\n$UNPUSHED"
fi

# Verifier CLAUDE.md
if [[ ! -f "$PROJECT_DIR/CLAUDE.md" ]]; then
    MESSAGES="$MESSAGES\n- CLAUDE.md manquant dans le projet"
fi

# Verifier MEMORY.md (optionnel selon session-end.md)
if [[ ! -f "$PROJECT_DIR/MEMORY.md" ]]; then
    MESSAGES="$MESSAGES\n- MEMORY.md manquant (optionnel mais recommande)"
fi

if [[ "$NEEDS_ACTION" == "true" ]]; then
    echo "=== REGLE 6: SESSION-END ===" >&2
    echo -e "$MESSAGES" >&2
    echo "" >&2
    echo "Actions a faire AVANT de finir la session:" >&2
    echo "1. Commit les fichiers modifies (message clair en francais)" >&2
    echo "2. Push vers le remote" >&2
    echo "3. Mettre a jour CLAUDE.md si la stack/strategie a change" >&2
    echo "4. Mettre a jour MEMORY.md avec nouveaux pitfalls/decisions" >&2
    echo "=== FIN REGLE 6 ===" >&2
fi

exit 0
