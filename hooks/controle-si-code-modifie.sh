#!/bin/bash
#
# controle-si-code-modifie.sh  (hook Stop)
#
# Lance le controle du projet UNIQUEMENT si du code a bouge pendant le tour,
# et bloque la fin du tour si le controle echoue.
#
# - Hors depot git            -> ne fait rien
# - Rien n'a bouge pendant    -> ne fait rien (une simple question ne declenche rien,
#   le tour                      meme si du code etait deja modifie avant)
# - Uniquement de la doc      -> ne bloque pas
# - Au moins un fichier code  -> lance verifier-projet.sh sur la RACINE du depot,
#   (modifie, nouveau, ou        en 240 s au plus (CONTROLE_BUDGET)
#    commite pendant le tour)    sortie 0 -> laisse passer
#                                sortie 1 -> BLOQUE et renvoie la sortie reelle des tests,
#                                            encadree comme une donnee du depot
#                                sortie 2 -> ne bloque pas (aucun moyen de verification :
#                                            la consigne vit dans rules/reflexes-de-travail.md)
#                                trop long -> BLOQUE et dit que le controle n'a rien prouve
#
# Le coeur est dans controle-fin-de-tour.py. Jusqu'a la 0.3.4, ce hook n'avait
# aucune limite de temps, et ne partait ni d'un sous-dossier, ni pour un
# dossier nouveau, ni pour un nom avec espace ou accent, ni apres un commit
# fait pendant le tour. Le budget de 240 s tient sous le « timeout » de 300 s
# donne a ce hook dans hooks.json.
#
# python3 et non jq : jq n'est pas garanti sur toutes les machines.
#
set -u
H="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
exec python3 -I "$H/controle-fin-de-tour.py" "${CONTROLE_BUDGET:-240}"
