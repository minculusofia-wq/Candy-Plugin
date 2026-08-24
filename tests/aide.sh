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
SAUTES=0
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

# outil <nom> — vrai si l'outil est utilisable sur cette machine.
outil() { command -v "$1" >/dev/null 2>&1; }

# saute <description> <raison> — un cas qu'on ne peut pas jouer ici.
# Le paquet ne dépend que de python3 ; quelques cas ont besoin de pytest ou de
# npm pour exister. Plutôt que de les compter pour verts ou de laisser une suite
# rouge sans explication, on les saute EN LE DISANT.
saute() {
    SAUTES=$((SAUTES + 1))
    printf '  %s·%s %s %s(%s)%s\n' "$GRIS" "$NC" "$1" "$GRIS" "$2" "$NC"
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

# texte_injecte <chemin du hook> <json d'entree> — ce que le hook écrit sur la
# SORTIE NORMALE, la seule que Claude Code lit comme du contexte injecté.
#
# La sortie d'erreur est mise de côté volontairement : elle était fusionnée avec
# l'autre, si bien qu'un hook qui se plaignait passait pour un hook qui parle —
# vérifié, un simple avertissement faisait échouer les cinq cas qui attendent le
# silence.
texte_injecte() {
    printf '%s' "$2" | bash "$1" 2>/dev/null
}

# lignes_injectees <chemin du hook> <json d'entree> — combien de lignes le hook
# écrit sur la sortie normale.
lignes_injectees() {
    texte_injecte "$1" "$2" | grep -c . || true
}

# contient <chemin du hook> <json d'entree> <texte attendu> — rend 1 si le hook
# a bien injecté CE texte-là. Compter les lignes ne suffit pas : n'importe quelle
# ligne comptait, même sans rapport avec la règle.
contient() {
    texte_injecte "$1" "$2" | grep -qF "$3" && echo 1 || echo 0
}

bilan() {
    printf '\n%s%s=== BILAN ===%s\n' "$GRAS" "$GRIS" "$NC"
    if [ "$SAUTES" -gt 0 ]; then
        printf '  %s cas joués, %s en échec, %s%s sauté(s)%s\n' "$TOTAL" "$ECHECS" "$GRIS" "$SAUTES" "$NC"
    else
        printf '  %s cas joués, %s en échec\n' "$TOTAL" "$ECHECS"
    fi
    if [ "$ECHECS" -eq 0 ]; then
        printf '  %sTout passe.%s\n\n' "$VERT" "$NC"
        return 0
    fi
    echo "  ${ROUGE}${ECHECS} cas en échec — le travail n'est PAS terminé.${NC}"
    echo
    return 1
}
