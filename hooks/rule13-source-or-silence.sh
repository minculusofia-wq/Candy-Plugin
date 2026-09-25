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

# La detection se fait en Python, en mots entiers Unicode — la meme quelle que
# soit la langue du systeme. Historique :
# - en sous-chaine, « edge » se declenchait sur « knowledge » ; les mots de
#   jargon trading (edge, sweep, longshot, scanner, mm, market maker) ont ete
#   retires : trop generiques hors de ce domaine, inutiles dedans ;
# - retires ensuite : « revue », « comment ... bot », « verifie ... code » — ils
#   reagissaient aux consignes de phase et aux demandes de relecture de code ;
# - jusqu'a la 0.3.4, grep lisait « par rapport a » comme une demande de
#   rapport, un chemin (analyses/rapport-juin.md) ou un nom de fichier
#   (analyse-commande.py) comme un mot, et sous la langue C le « e » accentue
#   de « rapporte » comme une frontiere de mot. Chemins, noms de fichiers et
#   « par rapport a » sont retires avant de chercher.
# Les messages automatiques ne sont pas des demandes de l'utilisateur : avis de
# fin d'une tache de fond, rapport d'un sous-agent, message d'une autre session.
# Rejeu d'un mois de messages de l'auteur : pres de trois declenchements sur
# quatre venaient d'eux.
DECLENCHE=$(python3 -I -c '
import json, re, sys, unicodedata
try:
    d = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
except ValueError:
    sys.exit(0)
p = d.get("prompt") if isinstance(d, dict) else None
if not isinstance(p, str) or p.lstrip().startswith(("<task-notification", "<agent-message", "<cross-session-message")):
    sys.exit(0)
t = unicodedata.normalize("NFC", p).lower()
t = re.sub(r"\S*[/\\]\S*", " ", t)
t = re.sub(r"\S+\.(?:md|py|sh|json|jsonl|txt|ya?ml|toml|log|csv|js|ts|tsx|swift|go|rs|html|css)\b", " ", t)
t = re.sub(r"\bpar rapport (?:à|a|au|aux)\b", " ", t)
if re.search(r"\b(?:rapports?|analyses?|analyser|pertinence|critiques?|strat[eé]gies?|que penses|qu.en penses|pourquoi le bot)\b", t):
    print("oui")
' <<< "$INPUT" 2>/dev/null) || true

[[ "$DECLENCHE" == "oui" ]] || exit 0

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

exit 0
