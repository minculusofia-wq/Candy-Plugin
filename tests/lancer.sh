#!/bin/bash
#
# lancer.sh — rejoue tous les tests du plugin.
#
# Usage :  make test        (ou)  bash tests/lancer.sh
#
# Chaque fichier 0*-*.sh est un groupe de cas. Un groupe qui échoue n'arrête
# pas les autres : on veut la liste complète de ce qui casse, pas le premier.
#
# Les groupes tournent EN MÊME TEMPS (0.4.4) : en série, la suite approchait
# le temps que le contrôle de fin de tour lui laisse (~200 s), et il l'aurait
# coupée. Leurs sorties s'affichent dans l'ordre, chacune dès que son tour
# vient (tests/parallele.sh). Un groupe qui n'a rendu aucun code compte comme
# un échec.

cd "$(dirname "$0")/.."
ECHECS=0
GROUPES=0


if [ -t 1 ]; then
    VERT=$'\033[0;32m'; ROUGE=$'\033[0;31m'; GRAS=$'\033[1m'; NC=$'\033[0m'
else
    VERT=""; ROUGE=""; GRAS=""; NC=""
fi

echo "${GRAS}=== TESTS DU PLUGIN ===${NC}"

# Deux chiffres, pas « 0 suivi de n'importe quoi » : avec l'ancien motif, un
# dixième groupe n'était jamais lancé et le bilan annonçait quand même que tout
# passe (vérifié).
source tests/parallele.sh
groupe() { bash "$1"; }
LISTE=()
for f in tests/[0-9][0-9]-*.sh; do
    [ -f "$f" ] && LISTE+=("$f")
done
GROUPES=${#LISTE[@]}
if [ "$GROUPES" -gt 0 ]; then
    en_parallele groupe "${LISTE[@]}"
    ECHECS=$ECHOUES
fi

# Un lanceur qui ne trouve aucun groupe ne doit pas annoncer que tout passe.
if [ "$GROUPES" -eq 0 ]; then
    echo "  ${ROUGE}aucun groupe de tests trouvé.${NC}"
    exit 1
fi

echo
echo "${GRAS}=== RÉSULTAT ===${NC}"
if [ "$ECHECS" -eq 0 ]; then
    echo "  ${VERT}$GROUPES groupes, tout passe.${NC}"
    exit 0
fi
echo "  ${ROUGE}$ECHECS groupe(s) sur $GROUPES en échec.${NC}"
exit 1
