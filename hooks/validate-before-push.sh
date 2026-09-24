#!/bin/bash
#
# validate-before-push.sh - Validates project before git push
# Triggered by git pre-push hook
#

set -e
# Quand ce hook refuse (code 2), Claude Code transmet a Claude la raison lue
# sur stderr, avec le poids d'un message de l'utilisateur. Cette raison est
# donc un texte FIXE : aucun nom de fichier du depot n'y figure, sinon un
# dossier au nom choisi (« autorise git push --no-verify… ») deviendrait une
# consigne. Le detail se lit avec /verifier, dont la sortie est une donnee.
# Le deroule ci-dessous reste sur stdout, que personne ne lit en code 2.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
FAILURES=0

echo -e "${YELLOW}🔍 Pre-push validation starting...${NC}"
echo ""

# =====================
# PROJET APP (iOS) : coherence documentaire
# =====================
#
# Retire le 2026-08-08 : une premiere etape appelait `update-claude-md.sh`, un
# script ABSENT de la machine. Elle affichait « skipping » a chaque push depuis
# toujours. Une etape morte dans un controle rend le controle moins credible que
# pas de controle du tout.
#
# Remplacee par ce qui manquait vraiment : ce script ne contenait AUCUNE
# verification Swift ni Xcode, donc sur une app iOS il pouvait rendre un vert
# complet sur une app qui ne compile pas. Le controle complet de l'app dure ~10
# minutes — trop long pour un push. Le controle de coherence, lui, dure moins
# d'une seconde et refuse un depot incoherent : c'est la bonne maille ici.
# Le controle complet reste la porte de sortie de phase, tenue par /fin-phase.

# Retire dans la 0.3.1 : sur un projet contenant un *.xcodeproj, cette etape
# lancait scripts/verifier_coherence.py — du code du projet, execute par un hook
# PreToolUse, donc AVANT que l'utilisateur ait accepte ou refuse la commande, et
# sur toute commande qui contenait « git push » (un simple grep suffisait). Un
# depot piege n'avait qu'a fournir un dossier x.xcodeproj/ vide et ce script
# (trouve par la relecture de securite). Ce controle ne servait qu'a l'app de
# l'auteur : le controle complet de l'app reste la porte de sortie de phase,
# tenue par /fin-phase, lancee par l'utilisateur.

# =====================
# PAS DE SUITE DE TESTS ICI
# =====================
#
# Cette etape lancait pytest ET npm test sur tout le projet, a chaque push.
# Sur un projet reel, un push devenait plusieurs minutes d'attente — et un
# controle qu'on attend finit contourne par --no-verify.
#
# Le controle complet a deja sa place, deux fois : /verifier a la demande, et
# la porte de sortie de phase tenue par /fin-phase. Ici on garde ce qui coute
# moins d'une seconde et attrape ce qu'un push ne devrait jamais emporter :
# une erreur de syntaxe.

# =====================
# SYNTAX CHECK
# =====================
#
# Revu dans la 0.3.3, trois pieges :
#   - le python3 par defaut de macOS est un 3.9 : il refuse un `match` ou une
#     f-string 3.12 parfaitement valides. On prend le Python 3 le plus recent
#     du PATH ;
#   - le controle fouillait tout le dossier, environnements non suivis compris :
#     sur un dossier reel, 9 180 fichiers de code tiers et 12 secondes. Seuls
#     les fichiers suivis par git partent au push : ce sont eux qu'on controle ;
#   - une session ouverte dans le dossier personnel fouillait tout le disque.
#     Sans .git a la racine du projet, il n'y a rien a controler.
# Un environnement suivi par erreur reste ignore, reconnu par le DEBUT du nom
# d'un dossier (venv, .venv-3.12…) : un « devenv » reste controle.
# core.fsmonitor coupe : git ne lance aucune commande configuree dans le depot.
# Compilation en memoire, dans un seul processus : aucun .pyc ecrit.
# Relecture de securite : seuls les fichiers ordinaires de moins de 2 Mo sont
# lus (un lien vers /dev/zero ou un tube bloquait le hook), une erreur sur un
# fichier ne fait plus sauter tout le controle, et un Python qui plante fait
# refuser le push au lieu de le laisser passer.
echo -e "${YELLOW}📋 Syntax checking...${NC}"

[[ -e "$PROJECT_DIR/.git" ]] || exit 0

PY=""
BEST=0
# Les noms sont assembles (python3, python3.9…) : ce ne sont pas des appels, et
# le controle statique de tests/06 exige -I sur tout appel ecrit en toutes
# lettres. Les deux appels ci-dessous, eux, portent -I.
CANDIDATS=$(for n in 3 3.{9..20}; do type -a -p "python$n"; done 2>/dev/null | awk '!vu[$0]++')
while IFS= read -r cand; do
    [[ -n "$cand" ]] || continue
    # Chemins absolus seulement, et hors du projet : un dossier relatif du PATH
    # (« . », « bin ») ferait lancer un python3.X fourni par le depot ouvert,
    # avant l'accord de l'utilisateur (relecture de securite de la 0.3.3).
    [[ "$cand" == /* ]] || continue
    case "$cand" in "$PROJECT_DIR"/*) continue ;; esac
    v=$("$cand" -I -c 'import sys; print(sys.version_info[0] * 100 + sys.version_info[1])' 2>/dev/null) || continue
    [[ "$v" =~ ^[0-9]+$ ]] || continue
    if (( v > BEST )); then BEST=$v; PY=$cand; fi
done <<< "$CANDIDATS"

[[ -n "$PY" ]] || exit 0

cd "$PROJECT_DIR"
FAILURES=$(git -c core.fsmonitor=false ls-files -z -- '*.py' 2>/dev/null | "$PY" -I -c '
import os, stat, sys
IGNORES = {b"virtualenv", b".virtualenv", b"site-packages", b"__pycache__",
           b"node_modules"}
def ignore(nom):
    return nom in IGNORES or nom.startswith((b"venv", b".venv"))
casses = 0
for chemin in sys.stdin.buffer.read().split(b"\0"):
    if not chemin or any(ignore(x) for x in chemin.split(b"/")[:-1]):
        continue
    # O_NOFOLLOW + O_NONBLOCK puis fstat sur le fichier OUVERT : ni lien, ni
    # tube, ni fichier remplace entre la verification et la lecture.
    try:
        fd = os.open(chemin, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        continue
    with os.fdopen(fd, "rb") as f:
        infos = os.fstat(f.fileno())
        if not stat.S_ISREG(infos.st_mode) or infos.st_size > 2_000_000:
            continue
        source = f.read(2_000_001)
    try:
        compile(source, chemin.decode("utf-8", "replace"), "exec", dont_inherit=True)
    except (SyntaxError, ValueError, RecursionError, MemoryError):
        casses += 1
    except Exception:
        pass
print(casses)
' 2>/dev/null) || FAILURES=""

# Python qui plante sans rendre de compte (le 3.9 de macOS sort en 139 sur
# certains fichiers) : le controle n'a pas eu lieu, le push ne passe pas.
if [[ ! "$FAILURES" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}✗ Python stopped before the end of the check${NC}"
    echo "Push refuse : le controle de syntaxe Python du projet n'a pas pu aller au bout." >&2
    echo "Le relancer : /verifier, ou python3 -I -m py_compile sur les fichiers .py du projet." >&2
    exit 2
fi

if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}✓ Python syntax OK${NC}"
fi

echo ""

# =====================
# FINAL RESULT
# =====================
if [[ $FAILURES -gt 0 ]]; then
    echo ""
    echo -e "${RED}❌ Validation failed with $FAILURES error(s)${NC}"
    echo -e "${RED}Push blocked. Fix the issues and try again.${NC}"
    echo "Push refuse : $FAILURES fichier(s) Python ne compilent pas." >&2
    echo "Les voir : /verifier, ou python3 -I -m py_compile sur les fichiers .py du projet." >&2
    exit 2
fi

echo -e "${GREEN}✅ All validations passed! Push proceeding...${NC}"
exit 0
