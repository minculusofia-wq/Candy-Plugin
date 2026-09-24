#!/bin/bash
#
# rappel-projet.sh (SessionStart : startup, resume, clear)
#
# A l'ouverture d'un projet, affiche la tache qui l'attend, lue dans
# ~/.claude/rappels-projets.txt. Silencieux si la liste n'existe pas ou si rien
# n'attend ce projet.
#
# POURQUOI
# --------
# Avec beaucoup de projets, personne ne se souvient de ce qu'il fallait dire a
# Claude en rouvrant tel ou tel dossier. Une tache « a faire plus tard sur ce
# projet » s'ecrit une fois dans la liste ; elle s'affiche d'elle-meme a
# l'ouverture, et il suffit de repondre « go ». La session qui la termine retire
# sa ligne.
#
# Format d'une ligne : dossier | tache | ou lire le detail | condition
#   ~/Desktop/mon-app | ranger la documentation | ~/notes/consigne.md |
#   La condition, facultative, s'ecrit fichier::motif : le rappel ne s'affiche
#   que si <dossier>/<fichier> contient une ligne qui correspond au motif
#   (grep -E). Exemple : ROADMAP.md::^### Phase 3.*🟢 — rien tant que la phase 3
#   n'est pas close. Pas de « | » dans le motif.
#
# Sortie JSON construite avec python3 (pas de jq) : systemMessage pour
# l'utilisateur, additionalContext pour Claude — ecrit comme des faits, ce que
# la doc de Claude Code recommande pour ce champ.
#

set -u

cat >/dev/null 2>&1 || true

# RAPPELS_PROJETS ne sert qu'aux tests, pour pointer une autre liste.
LISTE="${RAPPELS_PROJETS:-$HOME/.claude/rappels-projets.txt}"
[ -f "$LISTE" ] || exit 0
PROJET=$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && pwd) || exit 0

nettoie() {  # retire les espaces en tete et en fin
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

POUR_UTILISATEUR=""
POUR_CLAUDE=""
while IFS='|' read -r DOSSIER TACHE DETAIL CONDITION || [ -n "$DOSSIER" ]; do
    DOSSIER=$(nettoie "$DOSSIER")
    case "$DOSSIER" in ''|'#'*) continue ;; esac
    TACHE=$(nettoie "${TACHE:-}")
    DETAIL=$(nettoie "${DETAIL:-}")
    CONDITION=$(nettoie "${CONDITION:-}")
    DOSSIER="${DOSSIER/#\~/$HOME}"
    DOSSIER="${DOSSIER%/}"

    # Le projet ouvert est ce dossier, ou un de ses sous-dossiers.
    [ "$PROJET" = "$DOSSIER" ] || [ "${PROJET#"$DOSSIER"/}" != "$PROJET" ] || continue

    if [ -n "$CONDITION" ]; then
        FICHIER="${CONDITION%%::*}"
        MOTIF="${CONDITION#*::}"
        grep -qE "$MOTIF" "$DOSSIER/$FICHIER" 2>/dev/null || continue
    fi

    POUR_UTILISATEUR+="📌 En attente sur ce projet : $TACHE. Réponds « go » pour lancer, ou « plus tard »."$'\n'
    POUR_CLAUDE+="Tâche en attente sur ce projet, inscrite dans ~/.claude/rappels-projets.txt : $TACHE. Détail : ${DETAIL:-aucun}. L'utilisateur l'a inscrite pour qu'elle lui soit proposée en une phrase dès la première réponse : « go » la lance, « plus tard » la laisse en attente. Une fois la tâche finie, sa ligne est retirée de ~/.claude/rappels-projets.txt."$'\n'
done < "$LISTE"

[ -n "$POUR_UTILISATEUR" ] || exit 0

python3 -I -c 'import json, sys
print(json.dumps({"systemMessage": sys.argv[1],
                  "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.argv[2]}},
                 ensure_ascii=True))' "${POUR_UTILISATEUR%$'\n'}" "${POUR_CLAUDE%$'\n'}"
exit 0
