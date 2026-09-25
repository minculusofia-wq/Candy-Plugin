#!/bin/bash
#
# « Source ou silence » : il doit se déclencher sur une vraie demande de
# rapport, et se taire sur le reste.
#
# Le défaut d'origine : les mots étaient cherchés en sous-chaîne. « edge » se
# trouvant dans « knowledge », le prompt « ajoute un champ knowledge au
# formulaire » recevait le pavé complet de la règle.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$RACINE/hooks/rule13-source-or-silence.sh"

# muet <description> <prompt> — le hook ne doit rien écrire
muet()      { verifie "$1" 0 "$(lignes_injectees "$HOOK" "$(entree_prompt "$2")" | awk '{print ($1>0)?1:0}')"; }
# parle <description> <prompt> — le hook doit injecter LA RÈGLE, pas juste une
# ligne quelconque : on vérifie le texte, pas seulement qu'il y en a un.
REGLE="=== REGLE 13 ACTIVE: SOURCE-OR-SILENCE ==="
parle()     { verifie "$1" 1 "$(contient "$HOOK" "$(entree_prompt "$2")" "$REGLE")"; }

section "Déclencheurs — le silence sur le travail ordinaire"
muet  "un mot qui en contient un autre"      "ajoute un champ knowledge au formulaire"
muet  "un terme technique voisin"            "corrige le scanner de codes-barres"
muet  "une classe à renommer"                "renomme la classe CommandManager"
muet  "une couleur à changer"                "change la couleur du bouton"
muet  "un fichier à déplacer"                "deplace ce fichier dans un autre dossier"
muet  "une relecture de code demandée"       "fais une revue de code de la phase 3"
muet  "« comment » et « bot » dans la phrase" "comment je garde ca en memoire pour mon bot"

section "Déclencheurs — ni « par rapport à », ni « rapporté », ni un chemin"
# Jusqu'à la 0.3.4 : grep lisait « par rapport à » comme une demande de rapport,
# un chemin ou un nom de fichier comme un mot, et, sous la langue C, le « é » de
# « rapporté » comme une frontière de mot.
muet  "« par rapport à »"                     "compare par rapport à la version d'hier"
muet  "« rapporté »"                          "le bug rapporté hier est corrigé"
muet  "un chemin de fichier"                  "ouvre analyses/rapport-juin.md"
muet  "un nom de fichier"                     "corrige le hook analyse-commande.py"
parle "une vraie demande à côté d'un chemin"  "analyse le fichier hooks/x.sh"
verifie "« rapporté » muet aussi avec LC_ALL=C" 0 \
        "$(printf '%s' "$(entree_prompt "le bug rapporté hier est corrigé")" | LC_ALL=C bash "$HOOK" 2>/dev/null | grep -cF "$REGLE")"

section "Déclencheurs — les messages automatiques ne sont pas des demandes"
muet  "l'avis de fin d'une tâche de fond"    "<task-notification> <task-id>a1</task-id> rapport : analyse terminee"
muet  "le rapport d'un sous-agent"           "<agent-message from=\"a1\"> analyse du module"
muet  "un message d'une autre conversation"  "<cross-session-message from=\"x\"> rapport pret"

section "Déclencheurs — la parole sur une vraie demande d'analyse"
parle "un rapport demandé"                   "fais-moi un rapport sur cette approche"
parle "une analyse demandée"                 "analyse ce fichier et dis-moi"
parle "le verbe analyser"                    "peux-tu analyser la logique de calcul"
parle "une revue critique"                   "une revue critique de mon approche"
parle "la pertinence d'un choix"             "quelle est la pertinence de ce choix"
parle "le pluriel compte aussi"              "fais deux rapports separes"
parle "« stratégie » avec son accent"        "que vaut cette stratégie ?"

section "Déclencheurs — l'accent tient aussi avec la langue C"
verifie "« stratégie » reconnue avec LC_ALL=C" 1 \
        "$(printf '%s' "$(entree_prompt "que vaut cette stratégie ?")" | LC_ALL=C bash "$HOOK" 2>/dev/null | grep -cF "$REGLE")"

bilan
