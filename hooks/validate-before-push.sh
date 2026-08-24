#!/bin/bash
#
# validate-before-push.sh - Validates project before git push
# Triggered by git pre-push hook
#

set -e

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

if find "$PROJECT_DIR" -maxdepth 3 -name "*.xcodeproj" -print -quit 2>/dev/null | grep -q .; then
    echo -e "${YELLOW}📱 Projet app détecté — contrôle de cohérence...${NC}"
    if [[ -f "$PROJECT_DIR/scripts/verifier_coherence.py" ]]; then
        if python3 "$PROJECT_DIR/scripts/verifier_coherence.py" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Cohérence documentaire OK${NC}"
        else
            echo -e "${RED}✗ Cohérence documentaire ÉCHOUÉE${NC}"
            python3 "$PROJECT_DIR/scripts/verifier_coherence.py" 2>&1 | grep '✗' | head -10
            FAILURES=$((FAILURES + 1))
        fi
    else
        echo -e "${YELLOW}⚠ pas de contrôle de cohérence dans ce projet${NC}"
    fi
    echo -e "${YELLOW}ℹ Le contrôle complet de l'app (~10 min) est la porte de sortie de phase, pas du push — voir /fin-phase.${NC}"
    echo ""
fi

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
PYTHON_FILES=$(find "$PROJECT_DIR" -name "*.py" -not -path "*venv*" -not -path "*__pycache__*" 2>/dev/null | head -20)
if [[ -n "$PYTHON_FILES" ]]; then
    SYNTAX_ERRORS=0
    for file in $PYTHON_FILES; do
        if ! python3 -m py_compile "$file" 2>/dev/null; then
            echo -e "${RED}✗ Syntax error in $file${NC}"
            SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        fi
    done
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
    exit 2
fi

echo -e "${GREEN}✅ All validations passed! Push proceeding...${NC}"
exit 0
