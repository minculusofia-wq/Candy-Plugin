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
echo -e "${YELLOW}📋 Syntax checking...${NC}"

# Python syntax
# Les dossiers a ignorer sont reconnus par leur nom, SOUS le projet : filtrer le
# chemin complet ignorait tout un projet range dans un dossier « devenv ».
PYTHON_FILES=$(find "$PROJECT_DIR" -mindepth 1 \
    \( -type d \( -name "*venv*" -o -name __pycache__ -o -name node_modules -o -name .git \) -prune \) \
    -o \( -type f -name "*.py" -print \) 2>/dev/null | head -20)
if [[ -n "$PYTHON_FILES" ]]; then
    SYNTAX_ERRORS=0
    # Une ligne par fichier : un chemin avec des espaces reste un seul fichier.
    while IFS= read -r file; do
        if ! python3 -I -m py_compile "$file" 2>/dev/null; then
            echo -e "${RED}✗ Syntax error in $file${NC}"
            SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        fi
    done <<< "$PYTHON_FILES"
    if [[ $SYNTAX_ERRORS -eq 0 ]]; then
        echo -e "${GREEN}✓ Python syntax OK${NC}"
    else
        FAILURES=$((FAILURES + SYNTAX_ERRORS))
    fi
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
