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

section "Déclencheurs — la parole sur une vraie demande d'analyse"
parle "un rapport demandé"                   "fais-moi un rapport sur cette approche"
parle "une analyse demandée"                 "analyse ce fichier et dis-moi"
parle "le verbe analyser"                    "peux-tu analyser la logique de calcul"
parle "une revue critique"                   "une revue critique de mon approche"
parle "la pertinence d'un choix"             "quelle est la pertinence de ce choix"
parle "le pluriel compte aussi"              "fais deux rapports separes"

bilan
