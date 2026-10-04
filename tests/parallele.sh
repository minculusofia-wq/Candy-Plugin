#!/bin/bash
#
# parallele.sh — lancer des fichiers de tests EN MÊME TEMPS, partagé par
# lancer.sh (les groupes) et 11-lecteur-de-commandes.sh (les essais Python).
#
# en_parallele <fonction> <fichier>… : lance « <fonction> <fichier> » pour
# chacun, en même temps. Les sorties s'affichent DANS L'ORDRE, chacune dès que
# son tour vient : si la suite est coupée (le contrôle de fin de tour la tue
# par SIGKILL à son budget), ce qui est fini a déjà été affiché. Jusqu'à la
# 0.4.4, tout attendait le dernier, et une coupure ne montrait rien (relecture
# xhigh). ECHOUES : le nombre de fichiers en échec ; un fichier qui n'a rendu
# aucun code en est un.
#
# LIMITE : un SIGKILL ne laisse rien nettoyer ; le dossier candy-tests.* reste
# alors dans TMPDIR. Ctrl-C et TERM, eux, arrêtent tout et nettoient.

# Le processus et toute sa descendance : tuer le seul sous-shell laissait
# tourner les tests qu'il avait lancés (vérifié avec bash 3.2, celui de macOS).
tuer_arbre() {
    local p
    for p in $(pgrep -P "$1"); do tuer_arbre "$p"; done
    kill "$1" 2>/dev/null
}

en_parallele() {
    local lanceur="$1" fond k=0 f
    shift
    local pids=()
    fond=$(mktemp -d "${TMPDIR:-/tmp}/candy-tests.XXXXXX")
    trap 'for k in "${pids[@]}"; do tuer_arbre "$k"; done; rm -rf "$fond"; exit 130' INT TERM
    for f in "$@"; do
        ( "$lanceur" "$f" > "$fond/$k.sortie" 2>&1 < /dev/null; echo $? > "$fond/$k.code" ) &
        pids+=("$!")
        k=$((k + 1))
    done
    ECHOUES=0
    k=0
    for f in "$@"; do
        wait "${pids[$k]}"
        cat "$fond/$k.sortie" 2>/dev/null
        [ "$(cat "$fond/$k.code" 2>/dev/null)" = 0 ] || ECHOUES=$((ECHOUES + 1))
        k=$((k + 1))
    done
    rm -rf "$fond"
    trap - INT TERM
}
