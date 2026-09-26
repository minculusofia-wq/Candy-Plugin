#!/bin/bash
#
# est-un-bot.sh — ce dossier (ou ce fichier) appartient-il a un bot de trading ?
#
# Source unique de la detection. Appelee par jeu-de-documents.sh, qui en deduit
# le jeu de documents attendu (une-info-un-fichier.md, ligne « Bot »).
#
# Une detection devinee sans liste fait fausse route dans les deux sens : un
# ancien classement « tout ce qui n'est pas une app iOS est un bot » envoyait les
# regles de trading a des sites web et a des apps. D'ou l'ordre ci-dessous : la
# liste de l'utilisateur d'abord, les indices ensuite.
#
# Usage : est-un-bot.sh [--raison] [--filet-seul] <chemin>
#   code retour 0 = bot, 1 = pas un bot
#   --raison     : ecrit pourquoi, en un mot (liste, nom, dependance:..., ...)
#   --filet-seul : ignore ~/.claude/projets-bots.txt, pour tester le filet seul
#
# ~/.claude/projets-bots.txt est facultatif : un dossier par ligne (« ~ »
# accepte), « !dossier » pour exclure, « # » pour commenter.
#
# Ordre de decision, le premier qui tranche gagne :
#   1. hors projet : le dossier personnel, ~/Desktop lui-meme,
#      ~/.claude, /tmp                                             -> non
#   2. ligne « !dossier » de ~/.claude/projets-bots.txt            -> non
#   3. ligne « dossier » de ~/.claude/projets-bots.txt             -> oui
#   4. un .xcodeproj dans le projet : c'est une app                -> non
#   5. filet : « bot » ou « bots » comme mot dans le nom du dossier -> oui
#   6. filet : bibliotheque de trading dans les dependances        -> oui
#   sinon                                                          -> non
#

set -u

LISTE="$HOME/.claude/projets-bots.txt"
RAISON=0
FILET_SEUL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --raison)     RAISON=1; shift ;;
        --filet-seul) FILET_SEUL=1; shift ;;
        *)            break ;;
    esac
done

reponse() {  # reponse <0|1> <raison>
    [ "$RAISON" = 1 ] && echo "$2"
    exit "$1"
}

CHEMIN="${1:-}"
[ -n "$CHEMIN" ] || reponse 1 "aucun-chemin"

# Un fichier (ou un fichier pas encore cree, cas d'un Write) : remonter jusqu'au
# premier dossier qui existe.
[ -d "$CHEMIN" ] || CHEMIN=$(dirname "$CHEMIN")
while [ ! -d "$CHEMIN" ] && [ "$CHEMIN" != "/" ]; do CHEMIN=$(dirname "$CHEMIN"); done
CHEMIN=$(cd "$CHEMIN" 2>/dev/null && pwd) || reponse 1 "introuvable"

# --- 1. Hors projet ----------------------------------------------------------
case "$CHEMIN" in
    "$HOME"|"$HOME/Desktop"|/|/tmp|/tmp/*|/private/tmp|/private/tmp/*) reponse 1 "hors-projet" ;;
    "$HOME/.claude"|"$HOME/.claude/"*)                  reponse 1 "hors-projet" ;;
esac

# --- 2 et 3. La liste --------------------------------------------------------
if [ "$FILET_SEUL" = 0 ] && [ -f "$LISTE" ]; then
    VERDICT=""
    while IFS= read -r LIGNE || [ -n "$LIGNE" ]; do
        LIGNE="${LIGNE%%[[:space:]]}"
        case "$LIGNE" in ''|'#'*) continue ;; esac
        EXCLU=0
        [ "${LIGNE:0:1}" = "!" ] && { EXCLU=1; LIGNE="${LIGNE:1}"; }
        LIGNE="${LIGNE/#\~/$HOME}"
        LIGNE="${LIGNE%/}"
        if [ "$CHEMIN" = "$LIGNE" ] || [ "${CHEMIN#"$LIGNE"/}" != "$CHEMIN" ]; then
            # Une exclusion gagne toujours, meme si le dossier est aussi liste.
            [ "$EXCLU" = 1 ] && reponse 1 "exclu-par-la-liste"
            VERDICT="liste"
        fi
    done < "$LISTE"
    [ -n "$VERDICT" ] && reponse 0 "$VERDICT"
fi

# --- La racine du projet -----------------------------------------------------
# Sous ~/Desktop, le premier niveau : des projets y vivent sans depot git.
# Ailleurs, la racine du depot git.
case "$CHEMIN" in
    "$HOME/Desktop/"*)
        RELATIF="${CHEMIN#"$HOME/Desktop/"}"
        RACINE="$HOME/Desktop/${RELATIF%%/*}" ;;
    *)
        RACINE=$(git -C "$CHEMIN" -c core.fsmonitor=false -c log.showSignature=false rev-parse --show-toplevel 2>/dev/null) || RACINE="$CHEMIN" ;;
esac

# --- 4. Une app --------------------------------------------------------------
if find "$RACINE" -maxdepth 3 -name "*.xcodeproj" -print -quit 2>/dev/null | grep -q .; then
    reponse 1 "app-xcode"
fi

# --- 5. Le nom ---------------------------------------------------------------
if basename "$RACINE" | grep -qiE '(^|[^[:alpha:]])bots?([^[:alpha:]]|$)'; then
    reponse 0 "nom"
fi

# --- 6. Les dependances ------------------------------------------------------
# Le nom du paquet doit etre entier : precede d'un debut de ligne, d'un espace
# ou d'un guillemet, suivi d'un operateur de version, d'un guillemet, d'un
# crochet ou d'une fin de ligne. Sans cette exigence, @solana/web3.js et
# "web3.*" dans un reglage mypy passaient pour du trading.
# Les lignes commentees (# ou //) ne comptent pas.
LIBS='py[-_]clob[-_]client[a-z0-9_-]*|hyperliquid[a-z0-9_-]*|ccxt|kalshi[a-z0-9_-]*|web3'
MOTIF="(^|[[:space:]\"'])($LIBS)([][[:space:]\"'<>=~!;,]|\$)"
while IFS= read -r -d '' FICHIER; do
    TROUVE=$(grep -viE '^[[:space:]]*(#|//)' "$FICHIER" 2>/dev/null \
        | grep -oiE "$MOTIF" | head -1 | grep -oiE "$LIBS" | head -1)
    [ -n "$TROUVE" ] && reponse 0 "dependance:$TROUVE"
done < <(find "$RACINE" -maxdepth 3 \
    \( -name node_modules -o -name .venv -o -name venv -o -name .git -o -name .next \
       -o -name __pycache__ -o -name dist -o -name build \) -prune \
    -o -type f \( -name 'requirements*.txt' -o -name pyproject.toml -o -name package.json \
       -o -name setup.py -o -name setup.cfg -o -name Pipfile \) -print0 2>/dev/null)

reponse 1 "aucun-signe"
