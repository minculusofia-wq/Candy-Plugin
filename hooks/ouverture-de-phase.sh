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
#   - trouve la prochaine phase non livree dans la roadmap ;
#   - affiche en point rouge ce que jeu-de-documents.sh trouve de rouge ;
#   - relit le conseil ecrit par /fin-phase, s'il existe ;
#   - verifie mecaniquement les deux points de la porte d'entree qu'une
#     commande peut verifier seule : depot propre, depot pousse.
#
# Au-dela de 10 000 caracteres, Claude Code ne transmet d'une sortie de hook
# qu'un apercu des 2 000 premiers (doc hooks, « JSON output »). Jusqu'a la
# 0.3.4, les alertes git venaient en dernier, et un long conseil ou une longue
# liste de rouges les faisait disparaitre. Elles viennent donc juste sous le
# titre, le conseil est coupe a 3 000 caracteres et la liste des rouges a
# 25 lignes.
#
# Il ne remplace PAS la porte d'entree : lire les documents et verifier les
# constats a la source reste le travail de Claude. Il empeche seulement de
# demarrer sans savoir qu'elle existe.
#
# Silencieux hors d'un projet a phases — aucune roadmap, aucune sortie.
#
# ⚠️ Ce silence a deja laisse passer un plan de phases ecrit AVANT que la
# roadmap existe, livre sur un jeu de documents incomplet et faux. Le jeu de
# documents est donc controle dans TOUS les projets, roadmap ou pas, par
# jeu-de-documents.sh (SessionStart). Ici, ses rouges s'affichent en plus comme
# points rouges de la porte d'entree.
#

set -u

# Le dossier de ce hook, lu AVANT le cd vers le projet : apres, un $0 relatif ne
# mene plus nulle part (vu par tests/06-paquet.sh).
ICI="$(cd "$(dirname "$0")" && pwd)"
PROJET="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJET" 2>/dev/null || exit 0
# Une session ouverte dans backend/ ou docs/ garde la porte du projet entier :
# jusqu'a la 0.3.4, la roadmap n'etait cherchee que dans ce sous-dossier, et la
# porte se taisait.
ORIGINE="$PROJET"
# git sans rien lancer de ce que le depot configure (surveillant de fichiers,
# verification de signature) : ce hook tourne a l'ouverture, avant tout accord.
g() { git -c core.fsmonitor=false -c log.showSignature=false -c gpg.program=false "$@"; }
RACINE_DEPOT=$(g rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$RACINE_DEPOT" ]]; then
    PROJET="$RACINE_DEPOT"
    cd "$PROJET" 2>/dev/null || exit 0
fi

# Consomme l'entree JSON du hook sans la lire : on ne depend d'aucun champ.
cat >/dev/null 2>&1 || true

# La liste des chemins possibles vit dans jeu-de-documents.sh, qui en a aussi
# besoin pour reconnaitre une app par phases : une seule liste.
JEU="$ICI/jeu-de-documents.sh"
ROADMAP=$(python3 -I "$JEU" --roadmap "$PROJET" 2>/dev/null)
CODE=$?
if [[ "$CODE" != 0 ]]; then
    # --roadmap sort en 0 avec ou sans roadmap : tout autre code est une panne.
    # Muet ici serait le pire : on croirait qu'il n'y a pas de roadmap — et on
    # perdrait aussi les controles « propre / pousse » qui suivent.
    echo "⚠️ ouverture-de-phase : $JEU a echoue (code $CODE) — roadmap non cherchee,"
    echo "   porte d'entree NON controlee. La faire a la main (porte-de-phase.md)."
    exit 0
fi
[[ -n "$ROADMAP" ]] || exit 0
ROADMAP_REL="${ROADMAP#$PROJET/}"

# --- Le point 4, pour sa partie mecanique : le jeu de documents --------------
# Calcule AVANT de chercher la prochaine phase : une roadmap au format non
# reconnu (« ## Phase N ») faisait sortir le hook avant ce bloc, et le rouge
# n'arrivait jamais a la porte.
bloc_documents() {
    local SORTIE CODE_JEU
    SORTIE=$(python3 -I "$JEU" --rouges "$PROJET" 2>&1)
    CODE_JEU=$?
    case $CODE_JEU in
        0) return 1 ;;
        1)  echo "🔴 POINT ROUGE — jeu de documents (point 4) :"
            local N
            N=$(printf '%s\n' "$SORTIE" | wc -l | tr -d ' ')
            printf '%s\n' "$SORTIE" | head -25 | sed 's/^/     /'
            [[ "$N" -gt 25 ]] && echo "     … et $((N - 25)) autre(s) ligne(s) : python3 -I \"$JEU\" --rouges \"$PROJET\""
            echo "   Le corriger dans cette conversation, avant tout plan et toute ligne"
            echo "   de code (une-info-un-fichier.md)." ;;
        *)  echo "⚠️ Controle du jeu de documents hors service (code $CODE_JEU) : $SORTIE"
            echo "   Le point 4 est donc entierement a verifier a la main." ;;
    esac
    echo
    return 0
}
BLOC_DOCS=$(bloc_documents)

# --- La prochaine phase : la premiere ligne « ### Phase N » sans 🟢 ----------
#
# Le marqueur fait foi dans la roadmap. On ne devine pas depuis un autre
# document.
PROCHAINE=$(grep -E '^### Phase [0-9]+' "$ROADMAP" 2>/dev/null \
    | grep -v '🟢' \
    | head -1 \
    | sed -E 's/^### (Phase [0-9]+)[^0-9].*/\1/')

if [[ -z "$PROCHAINE" ]]; then
    # Aucune phase ouverte reconnue — toutes livrees, ou format inconnu. Le
    # rappel de porte n'a pas lieu d'etre, mais un rouge du jeu de documents
    # doit quand meme se voir : un plan de phases peut etre en train de s'ecrire.
    if [[ -n "$BLOC_DOCS" ]]; then
        echo "=== PORTE D'ENTREE — $ROADMAP_REL (aucune phase ouverte reconnue) ==="
        echo
        echo "$BLOC_DOCS"
        echo "=== FIN PORTE D'ENTREE ==="
    fi
    exit 0
fi

NUMERO=$(echo "$PROCHAINE" | grep -oE '[0-9]+')

# --- Les deux points que ce hook peut trancher seul --------------------------
# Calcules ici, affiches juste sous le titre (voir l'en-tete).
alertes_git() {
    if g rev-parse --git-dir >/dev/null 2>&1; then
        NB_SALE=$(g status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$NB_SALE" != "0" ]]; then
            echo "⚠️ DEPOT NON PROPRE — $NB_SALE fichier(s) non commite(s) :"
            g status --porcelain 2>/dev/null | head -5 | sed 's/^/     /'
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

        BRANCHE=$(g rev-parse --abbrev-ref HEAD 2>/dev/null)
        if g rev-parse --verify "origin/$BRANCHE" >/dev/null 2>&1; then
            AVANCE=$(g rev-list --count "origin/$BRANCHE..HEAD" 2>/dev/null || echo 0)
            if [[ "$AVANCE" != "0" ]]; then
                echo "⚠️ $AVANCE COMMIT(S) NON POUSSE(S) sur $BRANCHE."
                echo "   Le controle avant commit ne peut pas le voir : ce point (3) est"
                echo "   a la charge de Claude."
                echo
            fi
        fi
    fi
}
ALERTES_GIT=$(alertes_git)

echo "=== PORTE D'ENTREE — $PROCHAINE ==="
echo
[[ -n "$ALERTES_GIT" ]] && { echo "$ALERTES_GIT"; echo; }
echo "Si cette conversation OUVRE cette phase, avant toute ligne de code (rules/porte-de-phase.md) :"
echo "  1. lancer le controle du projet et montrer sa sortie reelle ;"
echo "  2. verifier que le depot est propre ;"
echo "  3. verifier qu'il est pousse ;"
echo "  4. verifier que le jeu de documents est complet et que les documents"
echo "     d'etat disent tous la meme chose ;"
echo "  5. verifier les constats assignes a cette phase A LA SOURCE — sur"
echo "     un projet réel, trois constats d'audit sur quatre se sont reveles faux ou a"
echo "     moitie faux en allant lire le fichier cite."
echo "Puis ecrire le plan et attendre la validation de l'utilisateur."
echo
echo "Un point rouge = la phase ne s'ouvre pas. On le corrige d'abord."
echo
[[ -n "$BLOC_DOCS" ]] && { echo "$BLOC_DOCS"; echo; }
echo "Le reste du point 4 — les documents disent-ils la MEME chose ? — aucun"
echo "script ne le verifie. « Tu peux demarrer » ne se dit qu'apres l'avoir fait."
echo

# --- Le conseil de reglage, ecrit par /fin-phase a la cloture precedente -----
# /fin-phase l'ecrit a la racine du depot ; jusqu'a la 0.3.4, il n'etait
# cherche que dans le dossier de la session, qui reste lu en second.
CONSEIL=""
for c in "$PROJET/.claude-phase-suivante" "$ORIGINE/.claude-phase-suivante"; do
    [[ -e "$c" || -L "$c" ]] && { CONSEIL="$c"; break; }
done
# /fin-phase l'ecrit hors de git et l'y exclut. Il n'est donc lu que s'il est
# un fichier ordinaire (pas un lien) que git ignore : un conseil suivi, sous une
# autre casse, en lien vers un fichier hors du depot (une cle), ou dans un
# projet sans .git (archive) peut venir d'ailleurs, et son texte arriverait a
# Claude comme une consigne (relecture de securite de la 0.3.5, deux passes).
if [[ -n "$CONSEIL" ]] && { [[ -L "$CONSEIL" || ! -f "$CONSEIL" ]] || ! g -C "$(dirname "$CONSEIL")" check-ignore -q -- "$(basename "$CONSEIL")" 2>/dev/null; }; then
    echo "⚠️ Conseil de phase (.claude-phase-suivante) non lu : il n'est pas exclu de git, ou n'est pas un fichier ordinaire."
    echo "   /fin-phase l'ecrit et l'exclut de git ; un autre peut venir d'un depot clone. Le relire soi-meme."
    echo
    CONSEIL=""
fi
if [[ -n "$CONSEIL" ]]; then
    echo "--- Reglage conseille pour cette phase (ecrit a la cloture de la precedente) ---"
    python3 -I -c 'import sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
print(t[:3000].rstrip())
if len(t) > 3000:
    print("[... conseil coupe a 3 000 caracteres : le lire en entier dans " + sys.argv[1] + "]")' "$CONSEIL"
    echo
    echo "⚠️ DEUX reglages, pas trois : le mode (plan/edit/auto) et le curseur"
    echo "   d'effort, dont ultracode est la DERNIERE position — pas un interrupteur"
    echo "   a part. Les deux se fixent AVANT le premier message — c'est le plus"
    echo "   simple — et jamais en suite d'etapes. Si le curseur de cette"
    echo "   conversation ne correspond pas au conseil, le DIRE en une ligne avec la"
    echo "   commande a taper (/effort <cran>) : sur Opus 5.5 et Fable 5.1, le"
    echo "   changement garde le cache ; sur un autre modele, plus tard, il fait"
    echo "   relire la conversation sans cache."
    echo
fi

echo "Roadmap : $ROADMAP_REL, section « ### $PROCHAINE » (numero $NUMERO)."
echo "=== FIN PORTE D'ENTREE ==="

exit 0
