#!/bin/bash
#
# motif-panne.sh — source par les garde-fous qui REFUSENT quand la lecture de
# l'action echoue (protect-secrets, pre-edit-guard, rule12, sans-verif,
# validate-before-push). Lance seul (controle du paquet), il ne fait rien.
#
# motif_panne <code> ecrit sur stderr POURQUOI la lecture a echoue, en essayant
# Python lui-meme :
#   - python3 introuvable (127)            → « Python introuvable »
#   - python3 present mais ne demarre pas  → « Python en panne »
#   - python3 demarre                      → le lecteur du PLUGIN a plante
#
# Jusqu'a la 0.7.0, tout echec etait annonce « Python introuvable ou en panne »,
# meme quand Python allait bien : sous Windows, os.O_NONBLOCK manquait au
# lecteur de « git commit -F », il sortait en 3, et le refus faisait chercher
# la panne au mauvais endroit.

motif_panne() {
    local code="${1:-?}" essai=0
    # Dans une liste « || » : sous set -e (rule12, pre-edit-guard), un essai
    # nu qui echoue ferait sortir le hook en 127 ou 1 — non bloquants, l'action
    # passerait.
    python3 -I -c '' >/dev/null 2>&1 || essai=$?
    if [[ $essai == 127 ]]; then
        echo "Python introuvable : Python 3 n'est pas accessible aux hooks (absent, ou hors du PATH)."
        echo "Installer Python 3 ou le rendre accessible, puis relancer."
    elif [[ $essai != 0 ]]; then
        echo "Python en panne : Python 3 existe mais ne demarre pas (code $essai)."
        echo "Reparer Python, puis relancer."
    else
        echo "Le lecteur du plugin a plante sur cette entree (code $code) ; Python, lui, fonctionne."
        echo "C'est un defaut de candy-plugin, pas de Python : le signaler avec l'action refusee."
    fi
    echo "Un garde-fou qui ne voit rien ne laisse rien passer."
} >&2
