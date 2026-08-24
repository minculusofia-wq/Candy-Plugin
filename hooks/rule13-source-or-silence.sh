#!/bin/bash
#
# rule13-source-or-silence.sh (UserPromptSubmit)
# Regle 13: Source ou silence dans les rapports strategie
#
# Declencheur: prompt qui demande un rapport/analyse sur une strategie ou le code du bot.
# Action: injecte un rappel fort pour forcer Claude a sourcer chaque affirmation
# chiffree/technique par un fichier:ligne verifie.
#

set -e

INPUT=$(cat)
PROMPT=$(python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('prompt',''))" <<< "$INPUT" 2>/dev/null)

if [[ -z "$PROMPT" ]]; then
    exit 0
fi

PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Mots ENTIERS uniquement. En sous-chaine, « edge » se declenchait sur
# « knowledge » : le prompt « ajoute un champ knowledge au formulaire » recevait
# le pave complet de la regle. Les mots de jargon trading (edge, sweep, longshot,
# scanner, mm, market maker) ont ete retires : trop generiques hors de ce domaine,
# inutiles dedans puisque « rapport » et « analyse » couvrent le vrai declencheur.
TRIGGERS=(
    '\brapports?\b'
    '\banalyses?\b'
    '\banalyser\b'
    '\bpertinence\b'
    '\brevues?\b'
    '\bcritiques?\b'
    '\bstrat[eé]gies?\b'
    '\bque penses\b'
    "\\bqu.en penses\\b"
    '\bpourquoi le bot\b'
    '\bcomment\b.*\bbot\b'
    '\bverifie\b.*\bcode\b'
)

TRIGGERED=false
for trigger in "${TRIGGERS[@]}"; do
    if echo "$PROMPT_LOWER" | grep -qE "$trigger"; then
        TRIGGERED=true
        break
    fi
done

if [[ "$TRIGGERED" == "true" ]]; then
    cat <<'EOF'
=== REGLE 13 ACTIVE: SOURCE-OR-SILENCE ===
Rapport/analyse detecte. Chaque affirmation chiffree ou technique DOIT etre sourcee.

INTERDICTIONS ABSOLUES:
- Citer un chiffre (seuil, minimum, defaut, duree) sans [fichier.py:ligne]
- Affirmer une contrainte d'API externe (API tierce, SDK, service) sans source
- Nommer une variable/constante/fonction sans l'avoir lue a la source
- Generaliser depuis un fichier lu vers un fichier non lu
- Ecrire "le bot fait X" sans fichier:ligne qui le prouve

OBLIGATIONS:
- Avant chaque chiffre: Read ou Grep le fichier, coller [fichier:ligne](chemin#Lligne)
- Si info non trouvable: ecrire "je n'ai pas trouve cette info" (pas d'affirmation floue)
- Relire le rapport final: chaque chiffre a une source? Sinon supprimer ou marquer "non verifie"

WORKFLOW AVANT REDACTION:
1. Lister les affirmations chiffrees a sourcer
2. Ouvrir chaque fichier, relire la ligne exacte
3. Rediger en collant fichier:ligne a cote de chaque affirmation
4. Si tu t'apprete a ecrire "cette API exige X" ou "le SDK refuse Y" sans l'avoir lu: STOP

PRINCIPE:
Mieux vaut 5 points tous sources qu'un rapport de 20 points dont 3 sont inventes.
Les points inventes contaminent la confiance dans l'ensemble.
Une affirmation juste par hasard reste une faute — le probleme c'est le processus.

EXEMPLE DE FAUTE RECENTE (a ne pas refaire):
"Cette plateforme exige $5 minimum par ordre" → INVENTE
Realite dans [constants.py:90]: MIN_ORDER_SIZE_SHARES = 5.0 (5 shares, pas $5)
=== FIN REGLE 13 ===
EOF
fi

exit 0
