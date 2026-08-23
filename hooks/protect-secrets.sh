#!/bin/bash
#
# protect-secrets.sh - Bloque les commits/affichages de secrets
# Protege: cles privees, API keys, mnemoniques, passwords
#

set -e

# Lire l'input du hook (tool_input de Claude)
INPUT=$(cat)
json_get() { python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('tool_input',{}).get('$1',''))" <<< "$INPUT" 2>/dev/null; }
COMMAND=$(json_get command)
FILE_PATH=$(json_get file_path)
CONTENT=$(json_get content)
NEW_STRING=$(json_get new_string)

# Patterns de secrets a bloquer
SECRET_PATTERNS=(
    '0x[a-fA-F0-9]{64}'                    # Cle privee ETH/Polygon
    'PRIVATE_KEY\s*=\s*["\x27]?[^\s]+'     # Variable PRIVATE_KEY avec valeur
    'API_KEY\s*=\s*["\x27]?[^\s]+'         # Variable API_KEY avec valeur
    'API_SECRET\s*=\s*["\x27]?[^\s]+'      # Variable API_SECRET avec valeur
    'SECRET_KEY\s*=\s*["\x27]?[^\s]+'      # Variable SECRET_KEY avec valeur
    'MNEMONIC\s*=\s*["\x27]?[^\s]+'        # Mnemonique
    'seed\s*phrase'                          # Seed phrase
    'password\s*=\s*["\x27][^\s]+'          # Passwords hardcodes
)

check_content() {
    local text="$1"
    local source="$2"

    if [[ -z "$text" ]]; then
        return 0
    fi

    for pattern in "${SECRET_PATTERNS[@]}"; do
        if echo "$text" | grep -qEi "$pattern"; then
            echo "BLOCKED"
            echo ""
            echo "Secret detecte dans $source"
            echo "Pattern: $pattern"
            echo ""
            echo "Ne jamais committer ou afficher des secrets."
            echo "Utilisez des variables d'environnement (.env) a la place."
            exit 2
        fi
    done
}

# Verifier les commandes git add/commit qui incluent des .env
if [[ -n "$COMMAND" ]]; then
    if echo "$COMMAND" | grep -qE 'git\s+add.*\.env($|\s)|git\s+add\s+-A|git\s+add\s+\.'; then
        # Verifier si .env est dans le repertoire
        PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
        if [[ -f "$PROJECT_DIR/.env" ]]; then
            # Verifier que .gitignore contient .env
            if [[ ! -f "$PROJECT_DIR/.gitignore" ]] || ! grep -q '\.env' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
                echo "BLOCKED"
                echo ""
                echo "Tentative d'ajouter .env au git sans .gitignore!"
                echo "Ajoutez .env a votre .gitignore d'abord."
                exit 2
            fi
        fi
    fi

    # Verifier le contenu de echo/cat pour des secrets
    check_content "$COMMAND" "commande bash"
fi

# Verifier le contenu des fichiers ecrits/edites
if [[ -n "$CONTENT" ]]; then
    check_content "$CONTENT" "contenu du fichier ($FILE_PATH)"
fi

if [[ -n "$NEW_STRING" ]]; then
    check_content "$NEW_STRING" "edition du fichier ($FILE_PATH)"
fi

exit 0
