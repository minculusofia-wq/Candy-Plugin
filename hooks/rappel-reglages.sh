#!/bin/bash
#
# rappel-reglages.sh (SessionStart, toutes les sources : startup, resume, clear, compact)
#
# Une seule ligne : rappelle a Claude le format du conseil en cinq lignes (le
# modele, puis mode, curseur d'effort, ultracode, advisor), a donner au debut
# de chaque tache, chacune justifiee en une ligne. Detail :
# rules/choix-du-modele.md (« Cinq lignes ») et rules/advisor.md.
# Pour SessionStart, la sortie texte (code 0) est ajoutee au contexte de Claude.
#

set -u
cat >/dev/null 2>&1 || true

echo "Début de tâche : recommander d'office CINQ lignes, chacune justifiée en une ligne — le MODÈLE (Opus 5.5 écrit, Sonnet 5.5 lit et cherche, Fable 5.1 d'entrée pour une conception qui engage des mois ou après un échec d'Opus sur un défaut dur), puis les quatre réglages : mode (plan/auto), effort (low à max), ultracode (oui/non), advisor (Fable consulté seulement aux moments qui décident d'une tâche des cinq familles de relecture.md, jamais dans un subagent ni sous Fable — rules/advisor.md). Viser la réussite du premier coup : dans le doute, un cran au-dessus. Se taire sur l'une des cinq, le modèle compris, est une faute (rules/choix-du-modele.md)."
exit 0
