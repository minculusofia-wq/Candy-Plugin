#!/bin/bash
# Rappel skills /grill-with-docs et /tdd
# Détecte les demandes de feature/build/fix et m'injecte un rappel discret
# pour que je propose à l'utilisateur d'utiliser une skill avant de coder.

INPUT=$(cat)
PROMPT=$(python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('prompt',''))" <<< "$INPUT" 2>/dev/null)

if [ -z "$PROMPT" ]; then
  exit 0
fi

# Mots-clés indiquant une nouvelle feature, un build, un fix non-trivial
DEV_TRIGGERS=(
  "ajouter" "ajoute" "implementer" "implémenter" "implemente" "implémente"
  "construire" "construis" "creer" "créer" "cree" "crée"
  "developper" "développer" "developpe" "développe"
  "build" "ecrire" "écrire" "ecris" "écris"
  "nouvelle feature" "nouvelle fonctionnalite" "nouvelle fonctionnalité"
  "refactor" "refacto" "refactorer"
  "from scratch" "depuis zero" "depuis zéro"
  "phase 1" "phase 2" "phase 3"
)

# Mots-clés indiquant une décision stratégique (council pertinent)
DECISION_TRIGGERS=(
  "je dois choisir" "j'hesite" "j'hésite" "lequel choisir" "laquelle choisir"
  "pivoter" "stopper" "arrêter le bot" "arreter le bot"
  "decision" "décision" "irreversible" "irréversible" "trancher"
  "avec mon associé" "avec mon associe"
  "go ou no go" "go/no-go" "je lance" "je l ancie" "ou j'attends"
  "stop ou continue" "stop ou pas"
  "quel nom" "quel pays" "quel positionnement"
  "valider l'idee" "valider l'idée"
)

LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

DEV_MATCH=0
for trigger in "${DEV_TRIGGERS[@]}"; do
  if echo "$LOWER" | grep -qF "$trigger"; then
    DEV_MATCH=1
    break
  fi
done

DECISION_MATCH=0
for trigger in "${DECISION_TRIGGERS[@]}"; do
  if echo "$LOWER" | grep -qF "$trigger"; then
    DECISION_MATCH=1
    break
  fi
done

# Si rien ne matche, sortir silencieusement
if [ "$DEV_MATCH" -eq 0 ] && [ "$DECISION_MATCH" -eq 0 ]; then
  exit 0
fi

# Construire le rappel en fonction des matches
echo "=== RAPPEL SKILLS DISPONIBLES ==="

if [ "$DECISION_MATCH" -eq 1 ]; then
  cat << 'EOF'
Cette demande ressemble à une DÉCISION STRATÉGIQUE.

AVANT de répondre, propose à l'utilisateur :
- `/llm-council` ou "council this:" → si la décision est irréversible, a un vrai coût en cas d'erreur, ou implique plusieurs options à départager (5 conseillers IA débattent, peer review anonyme, verdict avec UNE action concrète)

Format : "Avant de répondre, on lance le council ? Sinon je te réponds direct."
NE PAS lancer le council toi-même, JUSTE PROPOSER.

EOF
fi

if [ "$DEV_MATCH" -eq 1 ]; then
  cat << 'EOF'
Cette demande ressemble à une nouvelle feature, un build, ou un refactor.

AVANT de coder, propose à l'utilisateur UNE SEULE des options suivantes (s'il y en a une pertinente) :
- `/grill-with-docs` → si la demande est ambigüe ou si tu n'es pas sûr de ce que l'utilisateur veut exactement (clarifier les specs par questions)
- `/tdd` → si c'est du code from scratch ou une logique critique testable (tests d'abord, code après)

Format : "Avant de coder, on lance /[skill] ? Sinon j'y vais direct."
Si la demande est triviale ou évidente : pas besoin de skill, code direct.
NE PAS lancer la skill toi-même, JUSTE PROPOSER.

EOF
fi

echo "=== FIN RAPPEL ==="
exit 0
