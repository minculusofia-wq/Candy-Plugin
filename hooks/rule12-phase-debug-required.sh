#!/bin/bash
#
# rule12-phase-debug-required.sh (PreToolUse: Bash)
#
# Un commit de phase ne part pas sans etre passe par la commande de cloture.
#
# Se declenche quand Claude tente un `git commit` dont le message mentionne
# « Phase N ». Bloque si la commande de cloture n'a pas tourne.
#
# CE QU'IL PROUVE, ET CE QU'IL NE PROUVE PAS
# ------------------------------------------
# Il prouve que la commande a tourne. Il ne prouve RIEN sur la qualite du
# travail : il lit un temoin, pas un resultat. C'est un rappel mecanique, pas
# une validation — ne jamais lire son silence comme un feu vert.
#
# Il ne bloque PAS un commit dont des points restent a verifier sur l'appareil
# reel. Tranche par l'utilisateur le 2026-08-08 : le commit part avec la liste ecrite
# de ce qui reste, et c'est la phase qui garde son 🟡. Bloquer ferait contourner
# le dispositif au bout de deux fois ; une dette ecrite vaut mieux.
#
# Reecrit le 2026-08-08. La version precedente recopiait la procedure de debug
# des bots — backend local, endpoints, DRY_RUN — dans son message d'erreur, en
# troisieme exemplaire d'une procedure qui vit dans /debug. Elle envoie
# desormais vers la commande, sans rien recopier.
#

set -e

INPUT=$(cat)
json_get() { python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('tool_input',{}).get('$1',''))" <<< "$INPUT" 2>/dev/null; }

COMMAND=$(json_get command)

# Ne se declenche que sur git commit
if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
    exit 0
fi

# ... et seulement si le message mentionne une phase numerotee
if ! echo "$COMMAND" | grep -qiE '\bphase\s*[0-9]+\b'; then
    exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TEMOIN="${PROJECT_DIR}/.claude-phase-debug-done"

# Le temoin est ecrit par /fin-phase (apps) ou /fin-session (bots), juste avant
# le commit, et porte le verdict rendu. Il est deja couvert par .gitignore.
if [[ -f "$TEMOIN" ]]; then
    if [[ $(find "$TEMOIN" -mmin -30 2>/dev/null) ]]; then
        VERDICT=$(head -1 "$TEMOIN" 2>/dev/null)
        [[ -n "$VERDICT" ]] && echo "  · cloture de phase : ${VERDICT}" >&2
        # Retire pour forcer un nouveau passage a la phase suivante.
        rm -f "$TEMOIN"
        exit 0
    fi
    rm -f "$TEMOIN"
fi

cat >&2 <<'EOF'
=== COMMIT DE PHASE SANS PASSAGE PAR LA COMMANDE DE CLOTURE ===

Tu commites une phase, mais la commande de cloture n'a pas tourne (aucun temoin
de moins de 30 minutes).

  - Projet APP decoupe en phases  ->  /fin-phase
  - Projet BOT                    ->  /fin-session

La procedure complete est DANS la commande. Ne pas l'improviser ici, ne pas la
recopier : c'est en la recopiant qu'elle a fini en trois exemplaires divergents.

Rappel de ce que /fin-phase impose, dans l'ordre : controle mecanique du projet,
porte de sortie de la phase relue POINT PAR POINT, liste de ce que seul l'appareil réel
tranche, mise a jour des documents, verdict a trois etats, puis commit.

Le 🟢 dans ROADMAP.md et l'etiquette `phase-N-done` ne se posent QU'EN VERT.

POURQUOI :
Sans cloture, les defauts s'empilent d'une phase a l'autre et deviennent
impossibles a isoler. Et une phase declaree livree qui ne l'est pas rend toute
la roadmap non fiable.

=== FIN ===
EOF

exit 2
