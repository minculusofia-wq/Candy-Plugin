#!/bin/bash
#
# controle-si-code-modifie.sh  (hook Stop)
#
# Lance le controle du projet UNIQUEMENT si du code a bouge pendant le tour,
# et bloque la fin du tour si le controle echoue.
#
# - Hors depot git            -> ne fait rien
# - Aucun fichier modifie     -> ne fait rien (une simple question ne declenche rien)
# - Uniquement de la doc      -> ne bloque pas
# - Au moins un fichier code  -> lance verifier-projet.sh
#       sortie 0 -> laisse passer
#       sortie 1 -> BLOQUE et renvoie la sortie reelle des tests
#       sortie 2 -> ne bloque pas, signale qu'il manque un controle
#
set -u

INPUT=$(cat 2>/dev/null || echo '{}')

# Anti-boucle : si Claude a deja ete relance par un hook Stop, ne pas rebloquer.
if echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    exit 0
fi

# python3 et non jq : jq n'est pas installe par defaut sur macOS. Un hook qui
# depend d'un binaire absent echoue en SILENCE — ici il aurait controle le mauvais
# dossier, ou rien du tout, sans le moindre message. python3 est deja requis par
# tous les autres hooks du paquet.
PROJET=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
[ -z "$PROJET" ] && PROJET="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJET" 2>/dev/null || exit 0

# 1. Hors depot git -> rien
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# 2. Rien de modifie -> rien
MODIFIES=$(git status --porcelain 2>/dev/null | awk '{print $NF}')
[ -z "$MODIFIES" ] && exit 0

# 3. Uniquement de la doc -> ne bloque pas
CODE_TOUCHE=0
while IFS= read -r f; do
    case "$f" in
        *.py|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.swift|*.go|*.rs|*.rb|*.java|*.kt|*.php|*.sh|*.sql|*.prisma|*.vue|*.svelte|*.c|*.h|*.cpp)
            CODE_TOUCHE=1; break ;;
    esac
done <<< "$MODIFIES"
[ "$CODE_TOUCHE" -eq 0 ] && exit 0

# 4. Du code a bouge -> controle
# --rapide : si le projet declare une cible « test-rapide », c'est elle qui
# tourne ici. La suite complete reste celle de /verifier.
SORTIE=$(bash "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/hooks/verifier-projet.sh" "$PROJET" --rapide 2>&1)
CODE=$?

case "$CODE" in
    0) exit 0 ;;
    2)
        echo "=== AUCUN MOYEN DE VERIFICATION DANS CE PROJET ===" >&2
        echo "Du code a ete modifie mais rien ne permet de savoir si ca casse quelque chose." >&2
        echo "Le signaler à l'utilisateur et proposer de mettre un controle en place." >&2
        exit 0
        ;;
    *)
        echo "=== CONTROLE DU PROJET EN ECHEC — LE TRAVAIL N'EST PAS TERMINE ===" >&2
        echo "$SORTIE" >&2
        echo "" >&2
        echo "Corriger les echecs ci-dessus avant d'annoncer que c'est fait." >&2
        echo "Montrer la sortie reelle du controle, pas une affirmation." >&2
        exit 2
        ;;
esac
