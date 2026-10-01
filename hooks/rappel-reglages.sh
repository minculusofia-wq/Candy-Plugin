#!/bin/bash
#
# rappel-reglages.sh (SessionStart, toutes les sources : startup, resume, clear, compact)
#
# Une seule ligne : rappelle a Claude le format du conseil en quatre points
# (mode, curseur d'effort, ultracode, advisor), a donner au debut de chaque
# tache, chacun justifie en une ligne. Detail : rules/choix-du-modele.md.
# Pour SessionStart, la sortie texte (code 0) est ajoutee au contexte de Claude.
#

set -u
cat >/dev/null 2>&1 || true

echo "Début de tâche : recommander d'office QUATRE réglages, chacun justifié en une ligne — mode (plan/auto), effort (low à max), ultracode (oui/non), advisor (non, ou Fable avec son surcoût). Se taire sur l'un des quatre est une faute (rules/choix-du-modele.md)."
exit 0
