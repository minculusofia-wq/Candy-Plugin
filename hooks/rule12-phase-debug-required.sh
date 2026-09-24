#!/bin/bash
#
# rule12-phase-debug-required.sh (PreToolUse: Bash)
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

set -e

INPUT=$(cat)

# Lecture du JSON et reconnaissance du marqueur en Python : les accents
# (clôture, LIVRÉE) y sont fiables quelle que soit la langue du systeme.
CLOTURE=$(python3 -I -c '
import json, re, sys
try:
    commande = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace")).get("tool_input", {}).get("command", "") or ""
except Exception:
    sys.exit(3)                      # illisible : le hook refuse
# Tout est lineaire ou borne (relecture de securite de la 0.3.3) : une regex
# a options repetees s emballait sur une suite de « -C », et les motifs de
# cloture coutent en carre de la longueur d une ligne. On lit donc au plus
# 40 000 caracteres, 4 000 par ligne : un message de commit tient dedans.
commande = commande[:40000]
# « git … commit » dans un meme segment de commande (entre ; & | et fin de
# ligne) : couvre cd x&&git commit, \git, git --git-dir d commit, git -C "a b".
commit = False
for segment in re.split(r"[;&|\n]", commande):
    m = re.search(r"\bgit\b", segment)
    if m and re.search(r"\bcommit\b", segment[m.end():]):
        commit = True
        break
if not commit:
    sys.exit(0)
marqueurs = (
    r"(?i)cl(?:o|ô)ture\s*\(\s*phase\s*\d+",
    r"(?i)\(\s*phase\s*\d+[^)]*\)\s*:\s*cl(?:o|ô)ture\b",
    r"(?i:phase)\s*\d+.*\bLIVR(?:E|É)E\b",
)
for ligne in commande.splitlines():
    ligne = ligne[:4000]
    if any(re.search(m, ligne) for m in marqueurs):
        print("oui")
        break
' <<< "$INPUT" 2>/dev/null) || CLOTURE="illisible"

# Si la lecture echoue (python3 absent ou en panne), le commit est REFUSE :
# « CLOTURE="" » laissait passer une cloture (/code-review du 2026-09-24).
if [[ "$CLOTURE" == "illisible" ]]; then
    echo "Action refusee : ce garde-fou n'a pas pu lire la commande (Python introuvable ou en panne)." >&2
    echo "Reparer Python, puis relancer. Un garde-fou qui ne voit rien ne laisse rien passer." >&2
    exit 2
fi
[[ "$CLOTURE" == "oui" ]] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
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
        # Non suivi : on peut le retirer, qu'il vaille ou non. Un lien ou un
        # dossier n'est pas touche.
        # Un rm qui echoue ne doit pas faire sortir le hook en 1 (set -e) : le
        # code 1 laisse passer, et son message contiendrait un chemin.
        if [[ "$ETAT" == "valide" || "$ETAT" == "ordinaire" ]]; then
            rm -f "$TEMOIN" 2>/dev/null || true
        fi
        # Retire pour forcer un nouveau passage a la phase suivante.
        if [[ "$ETAT" == "valide" ]]; then
            exit 0
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
