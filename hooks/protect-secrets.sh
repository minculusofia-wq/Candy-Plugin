#!/bin/bash
#
# protect-secrets.sh - Refuse d'ecrire un secret en clair dans le depot
#
# CE QU'IL BLOQUE, ET POURQUOI SI PEU
# -----------------------------------
# Une VALEUR qui ressemble a un secret, affectee a un nom sensible :
#     PRIVATE_KEY = "0x3f8a..."
# Rien d'autre. Pas le nom de variable seul, pas une chaine hexadecimale
# isolee, pas un mot dans une phrase.
#
# La version precedente cherchait un nom de variable suivi d'un signe egal,
# n'importe ou. Elle bloquait `api_key = None`, tout hash de transaction ou sha256
# (0x suivi de 64 hexa) et jusqu'a la documentation qui parle de phrases de
# recuperation de portefeuille. Un garde-fou qu'on contourne trois fois par
# jour finit desinstalle, et c'est alors le vrai secret qui passe.
#
# Ne sont donc PAS bloques : une valeur vide ou nulle, un appel a une variable
# d'environnement, un gabarit, une valeur trop courte ou sans entropie.
#
# Il reste un rappel mecanique, pas un audit de securite : il lit du texte
# ligne a ligne. Ne jamais lire son silence comme la preuve qu'il n'y a pas de
# secret.
#

set -e
H="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"

INPUT=$(cat)

# Si la lecture de l'entree echoue (python3 absent ou en panne), l'action est
# REFUSEE : sous set -e, le hook sortait en 1 ou 127, que Claude Code traite
# comme non bloquant, et l'action passait (/code-review du 2026-09-24).
refuser_illisible() {
    echo "Action refusee : ce garde-fou n'a pas pu lire l'action (Python introuvable ou en panne)." >&2
    echo "Reparer Python, puis relancer. Un garde-fou qui ne voit rien ne laisse rien passer." >&2
    exit 2
}

# --- 1. Une valeur secrete ecrite ou tapee ---
# La detection vit dans detection-secrets.py, partagee avec pre-edit-guard et
# analyse-commande. Jusqu'a la 0.3.4, elle ne connaissait ni « secret » ni
# « token » seuls, ni la forme YAML, ni une cle PEM, ni from_key("0x…").
# Le message est un texte fixe : ni chemin, ni nom, ni debut de valeur. La
# raison d'un refus arrive a Claude, et un nom de dossier choisi y deviendrait
# une consigne.
VALEUR=$(printf '%s' "$INPUT" | python3 -I "$H/detection-secrets.py" valeur 2>/dev/null) || refuser_illisible
if [[ -n "$VALEUR" ]]; then
    case "${VALEUR%%$'\t'*}" in
        commande) OU="la commande" ;;
        fichier) OU="le contenu du fichier ecrit" ;;
        *) OU="l'edition" ;;
    esac
    echo "BLOCKED" >&2
    echo "" >&2
    echo "Valeur qui ressemble a un secret dans $OU (nom sensible avec une valeur, cle 0x + 64 hexa, ou cle PEM)." >&2
    echo "Ne jamais ecrire un secret en clair : le lire depuis une variable d'environnement (.env non suivi par git)." >&2
    echo "Si c'est un hash (transaction, identifiant), le nommer comme tel : tx_hash, condition_id." >&2
    exit 2
fi

# --- Garde .env : refuser de suivre un .env qui n'est pas ignore ---
# Lecture robuste (relecture de securite de la 0.3.4) : un demi-caractere
# Unicode orphelin faisait planter ce print, le hook sortait en 1 (non
# bloquant) et le git add du .env passait.
COMMAND=$(printf '%s' "$INPUT" | python3 -I -c "import sys,json; sys.stdout.reconfigure(errors='replace'); d=json.loads(sys.stdin.buffer.read().decode('utf-8', 'replace')); t=d.get('tool_input') if isinstance(d, dict) else None; print((t if isinstance(t, dict) else {}).get('command') or '')" 2>/dev/null) || refuser_illisible

# Le point doit etre le chemin ENTIER. Sans l'ancre de fin, le motif attrapait
# aussi « git add .claude-plugin/... » et bloquait une commande parfaitement normale
# des lors qu'un .env trainait dans le dossier.
if [[ -n "$COMMAND" ]] && echo "$COMMAND" | grep -qE 'git\s+add\s+.*\.env($|\s)|git\s+add\s+(-A|--all)($|\s)|git\s+add\s+\.($|\s)'; then
    PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        if [[ ! -f "$PROJECT_DIR/.gitignore" ]] || ! grep -q '\.env' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
            echo "BLOCKED" >&2
            echo "" >&2
            echo "Ce projet a un .env, et .gitignore ne l'ignore pas." >&2
            echo "Ajouter .env au .gitignore avant de faire un git add." >&2
            exit 2
        fi
    fi
fi

exit 0
