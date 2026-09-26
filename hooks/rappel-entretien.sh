#!/bin/bash
#
# rappel-entretien.sh (SessionStart : startup, resume, clear)
#
# Propose /maintenance quand elle sert, au lieu de compter sur la memoire de
# l'utilisateur. Silencieux sinon.
#
# POURQUOI
# --------
# Une commande a lancer « une fois par mois » finit par ne plus l'etre :
# personne ne retient toutes les commandes. Et l'audit des consignes (skill
# claude-api, sous-commande prompt-audit) n'a de sens qu'a l'arrivee d'un
# nouveau modele. Meme reponse que rappel-projet.sh : le rappel s'affiche a
# l'ouverture, il suffit de repondre « go ».
#
# QUAND
# -----
# Seulement dans ~ ou ~/.claude : l'entretien porte sur ~/.claude, et ouvert
# dans un projet, le rappel detournerait du travail en cours.
#   1. dernier entretien il y a plus de 30 jours, jamais fait, ou date
#      illisible (~/.claude/.maintenance-dernier-releve, ecrit par
#      verifier-setup.sh a l'etape 1 de /maintenance) ;
#   2. modele Opus ou Fable jamais audite : absent de ~/.claude/.audit-consignes
#      (une ligne « date modele » par audit, ecrite a l'etape 3 de /maintenance).
#      Sonnet et Haiku ne declenchent pas ce rappel : l'audit juge ce qui a
#      vieilli dans des consignes, et choix-du-modele.md reserve Sonnet au
#      travail sans jugement critique.
#
# Le champ « model » figure dans l'entree SessionStart (code de Claude Code
# 2.1.280) ; l'appel qui suit /clear ne le renseigne pas, seul le point 1 joue
# alors. « claude-opus-5-5[1m] » compte comme « claude-opus-5-5 », des DEUX
# cotes de la comparaison : ne le retirer que de l'entree laissait le rappel
# parler a vie si le fichier avait recu l'identifiant avec son suffixe.
#
# Une panne n'est pas un silence : si le calcul plante, le hook le dit.
# Sortie JSON construite avec python3 (pas de jq), en ASCII : avec un terminal
# en latin-1, l'emoji faisait planter l'ecriture et le repli s'affichait a
# chaque session. « python3 -I » : sans lui, un json.py pose dans ~ s'executait.
# « pwd -P » des deux cotes : un dossier personnel atteint par un lien
# symbolique rendait le hook muet pour toujours.
#

set -u

ENTREE=$(cat 2>/dev/null || true)

# RAPPEL_MAISON et RAPPEL_AUJOURDHUI ne servent qu'aux tests : un autre dossier
# personnel, une autre date.
MAISON=$(cd "${RAPPEL_MAISON:-$HOME}" 2>/dev/null && pwd -P) || exit 0
CLAUDE="$MAISON/.claude"

PROJET=$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && pwd -P) || exit 0
[ "$PROJET" = "$MAISON" ] || [ "$PROJET" = "$MAISON/.claude" ] || exit 0

python3 -I - "$CLAUDE" "${RAPPEL_AUJOURDHUI:-}" "$ENTREE" <<'PY'
import datetime, json, os, re, sys

claude, aujourdhui, entree = sys.argv[1], sys.argv[2], sys.argv[3]
auj = datetime.date.fromisoformat(aujourdhui) if aujourdhui else datetime.date.today()
raisons = []

# 1. Entretien en retard
releve = os.path.join(claude, ".maintenance-dernier-releve")
if not os.path.isfile(releve):
    raisons.append("aucun entretien enregistré")
else:
    try:
        with open(releve, encoding="utf-8", errors="replace") as f:
            dernier = datetime.date.fromisoformat(f.readline().split()[0])
    except (OSError, IndexError, ValueError):
        raisons.append("date du dernier entretien illisible")
    else:
        jours = (auj - dernier).days
        if jours > 30:
            raisons.append(f"dernier entretien il y a {jours} jours")

# 2. Modele jamais audite
def nu(modele):
    """« claude-opus-5-5[1m] » -> « claude-opus-5-5 »."""
    return re.sub(r"\[.*$", "", modele.strip()).lower()

try:
    modele = json.loads(entree).get("model") or ""
except (ValueError, AttributeError):
    modele = ""
modele = nu(modele) if isinstance(modele, str) else ""
# Un identifiant de modele, rien d'autre : ce texte est recopie dans le contexte
# de Claude. Sauts de ligne, consignes glissees, sequences de terminal -> ignore.
if not re.fullmatch(r"[a-z0-9][a-z0-9._:/@-]{0,100}", modele):
    modele = ""

a_auditer = False
if re.search(r"opus|fable", modele):
    audites = set()
    try:
        with open(os.path.join(claude, ".audit-consignes"), encoding="utf-8", errors="replace") as f:
            for ligne in f:
                champs = ligne.split()
                if len(champs) >= 2:
                    audites.add(nu(champs[1]))
    except OSError:
        pass
    if modele not in audites:
        a_auditer = True
        raisons.append(f"consignes jamais relues pour {modele}")

if not raisons:
    sys.exit(0)

texte = " ; ".join(raisons)
pour_claude = (
    f"Entretien du setup dû, détecté par le hook rappel-entretien.sh : {texte}. "
    "L'utilisateur a installé ce rappel pour que l'entretien lui soit proposé en une phrase "
    "dès la première réponse : « go » lance /maintenance, « plus tard » le laisse en attente "
    "jusqu'à la prochaine ouverture."
)
if a_auditer:
    pour_claude += (
        f" L'étape 3 de /maintenance (audit des consignes) est due pour {modele}. "
        f"Une fois l'audit clos, la ligne à ajouter à ~/.claude/.audit-consignes est "
        f"« {auj.isoformat()} {modele} » : c'est elle qui fait taire ce rappel."
    )
print(json.dumps({"systemMessage": f"🧰 Entretien du setup à faire ({texte}). Réponds « go » pour lancer, ou « plus tard ».",
                  "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": pour_claude}},
                 ensure_ascii=True))
PY
STATUT=$?
[ "$STATUT" = 0 ] || echo '{"systemMessage": "⚠️ rappel-entretien.sh a planté : rappel de /maintenance HORS SERVICE"}'
exit 0
