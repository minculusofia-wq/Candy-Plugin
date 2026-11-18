#!/bin/bash
#
# motif-panne.sh <code> — dit POURQUOI un garde-fou n'a pas pu lire l'action.
# Appele par protect-secrets, pre-edit-guard, rule12, sans-verif et
# validate-before-push, uniquement quand ils refusent. Lance sans argument
# (controle du paquet), il ne fait rien.
#
# Le motif, ecrit sur stderr, est trouve en essayant Python lui-meme :
#   - python3 introuvable (127)            → « Python introuvable »
#   - python3 present mais ne demarre pas  → « Python en panne »
#   - python3 demarre                      → le lecteur du PLUGIN a echoue
#
# Jusqu'a la 0.7.0, tout echec etait annonce « Python introuvable ou en panne »,
# meme quand Python allait bien : sous Windows, os.O_NONBLOCK manquait au
# lecteur de « git commit -F », il sortait en 3, et le refus faisait chercher
# la panne au mauvais endroit (PR n° 2).
#
# Ce fichier est LANCE (bash motif-panne.sh), jamais charge par « . » : sous
# « set -e » et le bash 3.2 de macOS, un « . » qui echoue — fichier absent ou
# casse — faisait sortir le garde-fou en 1, que Claude Code traite comme non
# bloquant : l'action passait (/code-review xhigh de la PR n° 2). Lance a part,
# il ne peut que se taire ; le garde-fou a son propre texte de repli et sort
# en 2 quoi qu'il arrive (tests/essais/motif-panne.py).

[[ $# -ge 1 ]] || exit 0
code="$1"
essai=0
python3 -I -c '' >/dev/null 2>&1 || essai=$?
{
    if [[ $essai == 127 ]]; then
        echo "Python introuvable : Python 3 n'est pas accessible aux hooks (absent, ou hors du PATH)."
        echo "Installer Python 3 ou le rendre accessible, puis relancer."
    elif [[ $essai != 0 ]]; then
        echo "Python en panne : Python 3 existe mais ne demarre pas (code $essai)."
        echo "Reparer Python, puis relancer."
    elif [[ $code =~ ^[1-9][0-9]*$ ]]; then
        echo "Le lecteur du plugin a plante sur cette entree (code $code) ; Python, lui, fonctionne."
        echo "C'est un defaut de candy-plugin, pas de Python : le signaler avec l'action refusee."
    else
        echo "Le lecteur du plugin a rendu une reponse inattendue ; Python, lui, fonctionne."
        echo "C'est un defaut de candy-plugin, pas de Python : le signaler avec l'action refusee."
    fi
} >&2
exit 0
