#!/bin/bash
#
# pre-edit-guard.sh - Protege les fichiers critiques contre les edits accidentels
# Bloque les modifications de .env, credentials, et fichiers de prod
#

set -e

INPUT=$(cat)
json_get() { python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('tool_input',{}).get('$1',''))" <<< "$INPUT" 2>/dev/null; }
FILE_PATH=$(json_get file_path)

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

BASENAME=$(basename "$FILE_PATH")
DIRNAME=$(dirname "$FILE_PATH")

# Fichiers bloques (ne jamais editer via Claude)
BLOCKED_FILES=(
    ".env"
    ".env.production"
    ".env.prod"
    "credentials.json"
    "keystore.json"
    "wallet.json"
    "private_key.txt"
    "secret.key"
)

for blocked in "${BLOCKED_FILES[@]}"; do
    if [[ "$BASENAME" == "$blocked" ]]; then
        echo "BLOCKED"
        echo ""
        echo "Modification bloquee: $FILE_PATH"
        echo "Les fichiers de secrets/credentials ne doivent pas etre modifies par Claude."
        echo "Editez ce fichier manuellement."
        exit 2
    fi
done

# Avertissement pour les fichiers sensibles (pas bloque mais signale)
SENSITIVE_FILES=(
    "docker-compose.yml"
    "docker-compose.yaml"
    "Dockerfile"
    "deploy.sh"
    "deploy.py"
    "Makefile"
    ".github"
    "nginx.conf"
)

for sensitive in "${SENSITIVE_FILES[@]}"; do
    if [[ "$BASENAME" == "$sensitive" ]] || [[ "$FILE_PATH" == *"$sensitive"* ]]; then
        echo ""
        echo "FICHIER SENSIBLE: $FILE_PATH"
        echo "Ce fichier affecte le deploiement/infrastructure."
        echo "Verifiez attentivement les modifications."
        break
    fi
done

exit 0
