#!/bin/bash
#
# Une copie locale de ces hooks (dans ~/.claude/hooks) est-elle restée
# identique au plugin ?
#
# Né de l'alignement du 2026-10-05 : la copie de l'auteur et le plugin avaient
# divergé dans les deux sens, chacun fermant des failles que l'autre laissait
# ouvertes. Un setup qui tient une telle copie la déclare dans
# ~/.claude/candy-copie-locale.txt (un fichier par ligne, avec sa politique) et
# fournit ~/.claude/scripts/alignement-candy.py ; ce groupe le lance contre CET
# arbre du plugin. Un correctif fait d'un seul côté rend alors la suite rouge,
# quel que soit le dépôt touché. Sans liste déclarée, le groupe est sauté.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
LISTE="$HOME/.claude/candy-copie-locale.txt"
CONTROLE="$HOME/.claude/scripts/alignement-candy.py"

section "Copie locale — identique au plugin"
if [ -f "$LISTE" ] && [ -f "$CONTROLE" ]; then
    SORTIE=$(python3 -I "$CONTROLE" --plugin "$RACINE" 2>&1); CODE=$?
    printf '%s\n' "$SORTIE" | sed 's/^/    /'
    verifie "les fichiers « identique » de la copie locale le sont" 0 "$CODE"
else
    saute "copie locale identique au plugin" "aucune copie locale déclarée (~/.claude/candy-copie-locale.txt)"
fi

bilan
