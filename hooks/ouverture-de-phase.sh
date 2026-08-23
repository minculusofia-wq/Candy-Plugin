#!/bin/bash
#
# ouverture-de-phase.sh (SessionStart)
#
# Rappelle a Claude, a CHAQUE ouverture de conversation dans un projet decoupe
# en phases, ce qu'il doit faire avant d'ecrire la premiere ligne.
#
# Pourquoi ce hook existe
# -----------------------
# La regle « porte-de-phase » et l'etape 10 de /fin-phase disent toutes deux la
# meme chose : une phase s'ouvre en mode plan, sur des documents relus a froid.
# Mais ces deux textes vivent dans la conversation PRECEDENTE. Le 2026-08-16,
# L'utilisateur a ouvert la phase 12 sans la consigne, simplement parce qu'il ne
# pouvait pas s'en souvenir six heures plus tard — et il a demande qu'on
# automatise ce qu'il risquait d'oublier.
#
# Ce hook deplace le rappel la ou il sert : au demarrage de la conversation
# suivante, pas a la fin de la precedente.
#
# Ce qu'il fait, et rien de plus :
#   - trouve la prochaine phase non livree dans ROADMAP.md ;
#   - relit le conseil ecrit par /fin-phase, s'il existe ;
#   - verifie mecaniquement les deux points de la porte d'entree qu'une
#     commande peut verifier seule : depot propre, depot pousse.
#
# Il ne remplace PAS la porte d'entree : lire les documents et verifier les
# constats a la source reste le travail de Claude. Il empeche seulement de
# demarrer sans savoir qu'elle existe.
#
# Silencieux hors d'un projet a phases — aucun ROADMAP.md, aucune sortie.
#

set -u

PROJET="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJET" 2>/dev/null || exit 0

# Consomme l'entree JSON du hook sans la lire : on ne depend d'aucun champ.
cat >/dev/null 2>&1 || true

ROADMAP="$PROJET/ROADMAP.md"
[[ -f "$ROADMAP" ]] || exit 0

# --- La prochaine phase : la premiere ligne « ### Phase N » sans 🟢 ----------
#
# Le marqueur fait foi dans ROADMAP.md — c'est la meme source que le controle
# `etat-des-phases` du garde-fou. On ne devine pas depuis un autre document.
PROCHAINE=$(grep -E '^### Phase [0-9]+' "$ROADMAP" 2>/dev/null \
    | grep -v '🟢' \
    | head -1 \
    | sed -E 's/^### (Phase [0-9]+)[^0-9].*/\1/')

[[ -n "$PROCHAINE" ]] || exit 0

NUMERO=$(echo "$PROCHAINE" | grep -oE '[0-9]+')

echo "=== PORTE D'ENTREE — $PROCHAINE ==="
echo
echo "Si cette conversation OUVRE cette phase, avant toute ligne de code :"
echo "  1. lancer le controle du projet et montrer sa sortie reelle ;"
echo "  2. verifier que le depot est propre ET pousse ;"
echo "  3. verifier que les documents d'etat disent tous la meme chose ;"
echo "  4. verifier les constats assignes a cette phase A LA SOURCE — sur"
echo "     un projet réel, trois constats d'audit sur quatre se sont reveles faux ou a"
echo "     moitie faux en allant lire le fichier cite ;"
echo "  5. ecrire le plan et attendre la validation de l'utilisateur."
echo
echo "Un point rouge = la phase ne s'ouvre pas. On le corrige d'abord."
echo

# --- Le conseil de reglage, ecrit par /fin-phase a la cloture precedente -----
CONSEIL="$PROJET/.claude-phase-suivante"
if [[ -f "$CONSEIL" ]]; then
    echo "--- Reglage conseille pour cette phase (ecrit a la cloture de la precedente) ---"
    cat "$CONSEIL"
    echo
    echo "⚠️ DEUX reglages, pas trois : le mode (plan/edit/auto) et le curseur"
    echo "   d'effort, dont ultracode est la DERNIERE position — pas un interrupteur"
    echo "   a part. Les deux se fixent AVANT le premier message, jamais en suite"
    echo "   d'etapes. Si le reglage de cette conversation ne correspond pas au"
    echo "   conseil, le DIRE en une ligne et continuer."
    echo
fi

# --- Les deux points que ce hook peut trancher seul --------------------------
if git rev-parse --git-dir >/dev/null 2>&1; then
    NB_SALE=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$NB_SALE" != "0" ]]; then
        echo "⚠️ DEPOT NON PROPRE — $NB_SALE fichier(s) non commite(s) :"
        git status --porcelain 2>/dev/null | head -5 | sed 's/^/     /'
        [[ "$NB_SALE" -gt 5 ]] && echo "     … et $((NB_SALE - 5)) autre(s)"
        echo
        echo "   Deux lectures, et il faut trancher AVANT de continuer :"
        echo "   — si cette conversation OUVRE la phase, elle ne s'ouvre pas la-dessus ;"
        echo "   — si du travail est EN COURS (ici ou dans une autre conversation sur le"
        echo "     meme depot), ne rien annuler, ne rien commiter a la place de l'autre."
        echo
        echo "   Dans les deux cas : du code non commite n'est ni datable ni"
        echo "   reproductible. C'est ce qui a rendu l'incident du piege n°51 impossible"
        echo "   a prouver — 17 fichiers hors de git, le dernier commit vieux de 2 jours."
        echo
    fi

    BRANCHE=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if git rev-parse --verify "origin/$BRANCHE" >/dev/null 2>&1; then
        AVANCE=$(git rev-list --count "origin/$BRANCHE..HEAD" 2>/dev/null || echo 0)
        if [[ "$AVANCE" != "0" ]]; then
            echo "⚠️ $AVANCE COMMIT(S) NON POUSSE(S) sur $BRANCHE."
            echo "   Le controle avant commit ne peut pas le voir — c'est le seul point"
            echo "   de la porte d'entree qui reste a la charge de Claude."
            echo
        fi
    fi
fi

echo "Roadmap : ROADMAP.md, section « ### $PROCHAINE » (numero $NUMERO)."
echo "=== FIN PORTE D'ENTREE ==="

exit 0
