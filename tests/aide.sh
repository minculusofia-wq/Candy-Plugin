#!/bin/bash
#
# aide.sh — les outils communs aux tests.
#
# Un test dit : « j'envoie CECI à ce hook, j'attends CE code de sortie ».
# Rien de plus. Les codes de sortie sont le contrat de Claude Code :
#   0 = laisse passer   ·   2 = bloque   ·   1 = erreur non bloquante
#
# Les chaînes qui ressemblent à des secrets ou à des commandes ssh sont
# ASSEMBLÉES au lieu d'être écrites en clair. Deux raisons : les garde-fous
# installés sur la machine de qui lance ces tests les intercepteraient, et un
# dépôt public n'a pas à contenir de faux secrets qui déclenchent les alertes
# des autres.

TOTAL=0
ECHECS=0
SECTION=""

if [ -t 1 ]; then
    VERT=$'\033[0;32m'; ROUGE=$'\033[0;31m'; GRIS=$'\033[0;90m'; GRAS=$'\033[1m'; NC=$'\033[0m'
else
    VERT=""; ROUGE=""; GRIS=""; GRAS=""; NC=""
fi

section() { SECTION="$1"; printf '\n%s%s%s\n' "$GRAS" "$1" "$NC"; }

# verifie <description> <code attendu> <code obtenu>
verifie() {
    TOTAL=$((TOTAL + 1))
    if [ "$2" = "$3" ]; then
        printf '  %s✓%s %s\n' "$VERT" "$NC" "$1"
    else
        ECHECS=$((ECHECS + 1))
        printf '  %s✗%s %s %s(attendu %s, obtenu %s)%s\n' "$ROUGE" "$NC" "$1" "$GRIS" "$2" "$3" "$NC"
    fi
}

# code_hook <chemin du hook> <json d'entree> [variables d'env...]
# Rend le code de sortie du hook, sortie standard et erreur mises de cote.
code_hook() {
    local hook="$1" entree="$2"; shift 2
    printf '%s' "$entree" | env "$@" bash "$hook" >/dev/null 2>&1
    echo $?
}

# entree_commande <la commande> -> le JSON qu'envoie Claude Code
entree_commande() {
    python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1"
}

# entree_ecriture <chemin> <contenu>
entree_ecriture() {
    python3 -c 'import json,sys; print(json.dumps({"tool_input":{"file_path":sys.argv[1],"content":sys.argv[2],"new_string":sys.argv[2]}}))' "$1" "$2"
}

# entree_prompt <le prompt>
entree_prompt() {
    python3 -c 'import json,sys; print(json.dumps({"prompt":sys.argv[1]}))' "$1"
}

# entree_fin_de_tour <dossier du projet>
entree_fin_de_tour() {
    python3 -c 'import json,sys; print(json.dumps({"cwd":sys.argv[1],"last_assistant_message":"Voila.","session_id":"test"}))' "$1"
}

# lignes_injectees <chemin du hook> <json d'entree> — pour les hooks qui
# n'ont pas de code de sortie parlant : ce qui compte est ce qu'ils écrivent.
lignes_injectees() {
    printf '%s' "$2" | bash "$1" 2>&1 | grep -c . || true
}

bilan() {
    printf '\n%s%s=== BILAN ===%s\n' "$GRAS" "$GRIS" "$NC"
    printf '  %s cas joués, %s en échec\n' "$TOTAL" "$ECHECS"
    if [ "$ECHECS" -eq 0 ]; then
        printf '  %sTout passe.%s\n\n' "$VERT" "$NC"
        return 0
    fi
    echo "  ${ROUGE}${ECHECS} cas en échec — le travail n'est PAS terminé.${NC}"
    echo
    return 1
}
