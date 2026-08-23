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
# RUN TESTS (if available)
# =====================
echo -e "${YELLOW}🧪 Checking for tests...${NC}"

# Python tests
if [[ -f "$PROJECT_DIR/pytest.ini" ]] || [[ -d "$PROJECT_DIR/tests" ]] || find "$PROJECT_DIR" -name "test_*.py" -o -name "*_test.py" 2>/dev/null | head -1 | grep -q .; then
    echo "Found Python tests, running pytest..."
    if command -v pytest &> /dev/null; then
        if pytest "$PROJECT_DIR" --tb=short -q 2>/dev/null; then
            echo -e "${GREEN}✓ Python tests passed${NC}"
        else
            echo -e "${RED}✗ Python tests failed${NC}"
            FAILURES=$((FAILURES + 1))
        fi
    elif command -v python &> /dev/null && python -m pytest --version &> /dev/null; then
        if python -m pytest "$PROJECT_DIR" --tb=short -q 2>/dev/null; then
            echo -e "${GREEN}✓ Python tests passed${NC}"
        else
            echo -e "${RED}✗ Python tests failed${NC}"
            FAILURES=$((FAILURES + 1))
        fi
    else
        echo -e "${YELLOW}⚠ pytest not installed, skipping Python tests${NC}"
    fi
fi

# Node.js tests
if [[ -f "$PROJECT_DIR/package.json" ]]; then
    if command -v jq &> /dev/null && jq -e '.scripts.test' "$PROJECT_DIR/package.json" &> /dev/null; then
        TEST_SCRIPT=$(jq -r '.scripts.test' "$PROJECT_DIR/package.json")
        if [[ "$TEST_SCRIPT" != "null" ]] && [[ "$TEST_SCRIPT" != *"no test"* ]]; then
            echo "Found npm test script, running..."
            cd "$PROJECT_DIR"
            if npm test 2>/dev/null; then
                echo -e "${GREEN}✓ Node.js tests passed${NC}"
            else
                echo -e "${RED}✗ Node.js tests failed${NC}"
                FAILURES=$((FAILURES + 1))
            fi
        fi
    fi
fi

echo ""

# =====================
# SYNTAX CHECK
# =====================
echo -e "${YELLOW}📋 Syntax checking...${NC}"

# Python syntax
PYTHON_FILES=$(find "$PROJECT_DIR" -name "*.py" -not -path "*venv*" -not -path "*__pycache__*" 2>/dev/null | head -20)
if [[ -n "$PYTHON_FILES" ]]; then
    SYNTAX_ERRORS=0
    for file in $PYTHON_FILES; do
        if ! python -m py_compile "$file" 2>/dev/null; then
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
    exit 1
fi

echo -e "${GREEN}✅ All validations passed! Push proceeding...${NC}"
exit 0
