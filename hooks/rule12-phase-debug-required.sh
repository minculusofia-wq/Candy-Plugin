#!/bin/bash
#
# rule12-phase-debug-required.sh (PreToolUse : Bash, Monitor ; PostToolUse : Bash, mode « apres »)
#
# Un commit de CLOTURE de phase ne part pas sans etre passe par /fin-phase.
#
# Se declenche seulement quand Claude tente un `git commit` dont le message
# porte un marqueur de cloture :
#   - `cloture(phase N): …` — le marqueur que /fin-phase impose (etape 8) ;
#   - `(phase N…): cloture` et « phase N … LIVREE » en capitales — les formes
#     que prenaient les clotures avant ce marqueur.
# Tous les autres commits passent, meme s'ils citent une phase : « fix(phase 13):
# … » est un commit ordinaire en cours de phase. Mesure sur l'historique d'un
# projet reel : 131 messages citent « phase N », 7 sont des clotures, et ce sont
# les 7 que ce hook reconnait.
#
# /fin-session ne clot pas de phase : son commit ne porte jamais ce marqueur.
#
# CE QU'IL PROUVE, ET CE QU'IL NE PROUVE PAS
# ------------------------------------------
# Il prouve que la commande a tourne. Il ne prouve RIEN sur la qualite du
# travail : il lit un temoin, pas un resultat. C'est un rappel mecanique, pas
# une validation — ne jamais lire son silence comme un feu vert.
#
# Il ne bloque PAS un commit dont des points restent a verifier sur l'appareil
# reel. Tranche par l'utilisateur le 2026-08-08 : le commit part avec la liste ecrite
# de ce qui reste, et c'est la phase qui garde son 🟡. Bloquer ferait contourner
# le dispositif au bout de deux fois ; une dette ecrite vaut mieux.
#
# Reecrit le 2026-08-08. La version precedente recopiait la procedure de debug
# des bots — backend local, endpoints, DRY_RUN — dans son message d'erreur, en
# troisieme exemplaire d'une procedure qui vit dans /debug. Elle envoie
# desormais vers la commande, sans rien recopier.
#
# Corrige dans la 0.3.3 : il se declenchait sur tout message citant « phase N »,
# donc bloquait chaque commit ordinaire en cours de phase. Et /fin-phase
# ecrivait le temoin APRES le commit : la vraie cloture etait refusee aussi.
#
# Corrige dans la 0.3.5 : la commande etait decoupee a la main. Un « \ » +
# retour a la ligne entre git et commit, un message range dans un fichier
# (-F), git merge -m ou un alias (git ci) passaient ; un git log --grep ou un
# corps de message qui citait une cloture passee bloquait un commit ordinaire ;
# le temoin etait cherche dans le dossier d'ouverture de la session au lieu de
# la racine du depot ; et il etait consomme AVANT le commit — un commit refuse
# ensuite (pre-commit du projet, autre garde-fou, refus de l'utilisateur)
# obligeait a refaire /fin-phase.
#
# Limite connue : un message REPRIS d'un commit existant (--amend sans -m,
# -C <commit>, --reuse-message) n'est pas lu ; il faut le vouloir.
#

set -e
H="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
INPUT=$(cat)

# La commande est lue par analyse-commande.py (mode « cloture »), comme bash la
# lit : « \ » + retour a la ligne, $( ), documents <<EOF, cd/pushd, git -C,
# --git-dir. Seul le TITRE du message compte (1re ligne de -m, du fichier -F,
# ou du document de « -m "$(cat <<'EOF' …)" ») : un git log --grep ou un corps
# de message qui cite une cloture passee ne bloque plus un commit ordinaire.
# Sortie : « OUI<tab>dossier du commit » ou « NON ».
# Mode « apres » (PostToolUse, la commande a reussi) : si c'etait un commit de
# cloture et que le dernier commit du depot porte bien le marqueur (moins de
# 10 minutes), le temoin est retire — il ne sert qu'une fois.
#
# Filtre rapide : sans « git », aucun commit a lire (ce hook tourne sur chaque
# commande, avant et apres elle).
[[ "$INPUT" == *git* ]] || exit 0
if [[ "${1:-}" == "apres" ]]; then
    SORTIE=$(printf '%s' "$INPUT" | python3 -I "$H/analyse-commande.py" cloture 2>/dev/null) || exit 0
    [[ "$SORTIE" == OUI$'\t'* ]] || exit 0
    RACINE=$(git -C "${SORTIE#OUI$'\t'}" -c core.fsmonitor=false rev-parse --show-toplevel 2>/dev/null) || exit 0
    FAIT=$(git -C "$RACINE" -c core.fsmonitor=false log -1 --format='%ct%n%s' 2>/dev/null | python3 -I -c '
import importlib.util, sys, time
l = sys.stdin.read().split("\n", 1)
spec = importlib.util.spec_from_file_location("a", sys.argv[1]); a = importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
ok = len(l) == 2 and l[0].strip().isdigit() and time.time() - int(l[0]) < 600 and a.porte_cloture(l[1])
print("oui" if ok else "non")' "$H/analyse-commande.py" 2>/dev/null) || exit 0
    # Un commit est-il vraiment apparu depuis la verification ? « git commit …;
    # echo fin » reussit meme si le commit echoue : sans nouveau commit, le
    # temoin reste.
    REPERE=$(git -C "$RACINE" -c core.fsmonitor=false rev-parse --git-path claude-cloture-avant 2>/dev/null) || REPERE=""
    [[ -n "$REPERE" && "$REPERE" != /* ]] && REPERE="$RACINE/$REPERE"
    if [[ -n "$REPERE" && -f "$REPERE" ]]; then
        AVANT=$(cat "$REPERE" 2>/dev/null) || AVANT=""
        MAINTENANT=$(git -C "$RACINE" -c core.fsmonitor=false rev-parse -q --verify HEAD 2>/dev/null) || MAINTENANT=""
        [[ "$AVANT" == "$MAINTENANT" ]] && FAIT="non"
        [[ "$FAIT" == "oui" ]] && rm -f "$REPERE" 2>/dev/null
    fi
    T="$RACINE/.claude-phase-debug-done"
    if [[ "$FAIT" == "oui" && -f "$T" && ! -L "$T" ]]; then
        SUIVI=$(git -C "$RACINE" -c core.fsmonitor=false ls-files -- ':(icase).claude-phase-debug-done' 2>/dev/null) || SUIVI="erreur"
        [[ -z "$SUIVI" ]] && { rm -f "$T" 2>/dev/null || true; }
    fi
    exit 0
fi

SORTIE=$(printf '%s' "$INPUT" | python3 -I "$H/analyse-commande.py" cloture 2>/dev/null) || SORTIE="illisible"

# Si la lecture echoue (python3 absent ou en panne), le commit est REFUSE :
# « CLOTURE="" » laissait passer une cloture (/code-review du 2026-09-24).
if [[ "$SORTIE" == "illisible" || -z "$SORTIE" ]]; then
    echo "Action refusee : ce garde-fou n'a pas pu lire la commande (Python introuvable ou en panne)." >&2
    echo "Reparer Python, puis relancer. Un garde-fou qui ne voit rien ne laisse rien passer." >&2
    exit 2
fi
[[ "$SORTIE" == OUI$'\t'* ]] || exit 0

# Le temoin est a la racine du depot du COMMIT, la ou /fin-phase l'ecrit
# (« git rev-parse --show-toplevel ») : chercher dans CLAUDE_PROJECT_DIR
# refusait une cloture des que la session n'etait pas ouverte a la racine.
# Repli sur le dossier du projet si ce n'est pas un depot.
DOSSIER="${SORTIE#OUI$'\t'}"
PROJECT_DIR=$(git -C "$DOSSIER" -c core.fsmonitor=false rev-parse --show-toplevel 2>/dev/null) \
    || PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TEMOIN="${PROJECT_DIR}/.claude-phase-debug-done"

# Le temoin est ecrit par /fin-phase (etape 8), juste AVANT le commit.
# Relecture de securite de la 0.3.3 : un temoin fourni par le depot lui-meme
# ouvrait la porte sans /fin-phase — suivi par git (date du clone), suivi sous
# une autre casse (macOS et Windows ne distinguent pas les majuscules), lien
# symbolique, ou date dans le futur. Il ne vaut donc que s'il est un fichier
# ordinaire, date de moins de 30 minutes et pas du futur, et que git confirme
# qu'il n'est pas suivi — si git ne peut pas repondre, il ne vaut rien. Son
# contenu n'est jamais affiche.
if [[ -e "$TEMOIN" || -L "$TEMOIN" ]]; then
    # Sans les variables qui changent la lecture des chemins : avec
    # GIT_LITERAL_PATHSPECS, « :(icase) » etait pris au pied de la lettre.
    SUIVI=$(env -u GIT_LITERAL_PATHSPECS -u GIT_GLOB_PATHSPECS -u GIT_NOGLOB_PATHSPECS -u GIT_ICASE_PATHSPECS \
        git -C "$PROJECT_DIR" -c core.fsmonitor=false ls-files -- ':(icase).claude-phase-debug-done' 2>/dev/null) || SUIVI="erreur"
    ETAT=$(python3 -I -c '
import os, stat, sys, time
try:
    infos = os.lstat(sys.argv[1])
except OSError:
    sys.exit(0)
age = time.time() - infos.st_mtime
if stat.S_ISREG(infos.st_mode) and -60 <= age <= 1800:
    print("valide")
else:
    print("ordinaire" if stat.S_ISREG(infos.st_mode) else "autre")
' "$TEMOIN" 2>/dev/null) || ETAT=""
    if [[ -z "$SUIVI" ]]; then
        # Valide : le commit passe, et le temoin RESTE jusqu'a ce que le commit
        # ait vraiment eu lieu (mode « apres », PostToolUse). Jusqu'a la 0.3.4,
        # il etait efface ici : un commit refuse ensuite (autre garde-fou,
        # utilisateur, pre-commit) consommait le temoin, et /fin-phase etait a
        # refaire.
        if [[ "$ETAT" == "valide" ]]; then
            # Le commit courant est note (dans .git, jamais suivi) : le mode
            # « apres » n'effacera le temoin que si un NOUVEAU commit est apparu.
            REPERE=$(git -C "$PROJECT_DIR" -c core.fsmonitor=false rev-parse --git-path claude-cloture-avant 2>/dev/null) || REPERE=""
            if [[ -n "$REPERE" ]]; then
                [[ "$REPERE" = /* ]] || REPERE="$PROJECT_DIR/$REPERE"
                git -C "$PROJECT_DIR" -c core.fsmonitor=false rev-parse -q --verify HEAD > "$REPERE" 2>/dev/null || : > "$REPERE" 2>/dev/null || true
            fi
            exit 0
        fi
        # Perime (plus de 30 minutes) : retire. Un lien ou un dossier n'est pas
        # touche. Un rm qui echoue ne doit pas faire sortir le hook en 1
        # (set -e) : le code 1 laisse passer, et son message contiendrait un chemin.
        if [[ "$ETAT" == "ordinaire" ]]; then
            rm -f "$TEMOIN" 2>/dev/null || true
        fi
    fi
fi

cat >&2 <<'EOF'
=== CLOTURE DE PHASE SANS PASSAGE PAR /fin-phase ===

Ce commit clot une phase (marqueur « cloture(phase N) » ou « LIVREE »), mais
/fin-phase n'a pas tourne : aucun temoin valable (absent, de plus de 30
minutes, ou suivi par git — il ne doit jamais etre commite).

Clore une phase, c'est /fin-phase. La procedure complete est DANS la commande :
ne pas l'improviser ici, ne pas la recopier.

Si ce commit n'est pas une cloture (correction en cours de phase, fin de
session), il ne porte pas ce marqueur : « fix(phase N): … » passe.

Le 🟢 dans ROADMAP.md et l'etiquette `phase-N-done` ne se posent QU'EN VERT.

=== FIN ===
EOF

exit 2
