#!/bin/bash
#
# rappel-reglages.sh (SessionStart, toutes les sources : startup, resume, clear, compact)
#
# Une seule ligne : rappelle a Claude le format du conseil en cinq lignes (le
# modele, puis mode, curseur d'effort, ultracode, advisor), a donner au debut
# de chaque tache, chacune justifiee en une ligne. Detail :
# rules/choix-du-modele.md (« Cinq lignes », et les trois conditions de Sonnet).
# Pour SessionStart, la sortie texte (code 0) est ajoutee au contexte de Claude.
#

set -u
cat >/dev/null 2>&1 || true

echo "Début de tâche : recommander d'office CINQ lignes, chacune justifiée en une ligne — le MODÈLE (Opus 5.5 par défaut ; Sonnet 5.5 seulement si le travail est en volume et répétitif, vérifiable mécaniquement ET sans aucun jugement critique ; Fable 5.1 pour un problème dur donné d'un bloc), puis les quatre réglages : mode (plan/auto), effort (low à max), ultracode (oui/non), advisor (non, ou Fable avec son surcoût). Se taire sur l'une des cinq, le modèle compris, est une faute (rules/choix-du-modele.md)."
exit 0
