#!/bin/bash
#
# pre-edit-guard.sh - Protege les fichiers critiques contre les edits accidentels
# Bloque les modifications de .env, credentials, et fichiers de prod
#

set -e

INPUT=$(cat)
# Un caractere que la sortie ne sait pas encoder (demi-caractere Unicode
# orphelin) faisait planter la lecture : sous set -e, le hook sortait en 1, que
# Claude Code traite comme non bloquant, et l'ecriture d'un .env passait. Il
# devient un « ? », et le nom du fichier reste reconnu.
json_get() { python3 -I -c "
import sys, json
d = json.loads(sys.stdin.buffer.read().decode('utf-8', 'replace'))
t = d.get('tool_input')
v = (t if isinstance(t, dict) else {}).get('$1') or ''
sys.stdout.buffer.write(str(v).encode('utf-8', 'replace') + b'\\n')
" <<< "$INPUT" 2>/dev/null; }
# Si la lecture de l'entree echoue (python3 absent ou en panne), l'action est
# REFUSEE : sous set -e, le hook sortait en 1 ou 127, que Claude Code traite
# comme non bloquant, et l'action passait (/code-review du 2026-09-24).
refuser_illisible() {
    echo "Action refusee : ce garde-fou n'a pas pu lire l'action (Python introuvable ou en panne)." >&2
    echo "Reparer Python, puis relancer. Un garde-fou qui ne voit rien ne laisse rien passer." >&2
    exit 2
}
FILE_PATH=$(json_get file_path) || refuser_illisible

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Nom du fichier compare comme macOS (APFS) compare les noms : chemin
# normalise (« /p/.env/ », « /p/.env/. »), forme Unicode NFKC et casse repliee
# (« .ENV », « wallet.jſon » avec un s long, le signe Kelvin). Pas de
# basename/dirname : ceux de macOS echouent au-dela d'environ 1 000 caracteres,
# et le hook sortait alors en 1, avant le test des .env. Si Python echoue, le
# repli sur le dernier morceau du chemin garde au moins les cas simples.
BASENAME=$(printf '%s' "$FILE_PATH" | python3 -I -c "
import os, sys, unicodedata
v = sys.stdin.buffer.read().decode('utf-8', 'replace')
nom = os.path.basename(os.path.normpath(v)) if v else ''
sys.stdout.buffer.write(unicodedata.normalize('NFKC', nom).casefold().encode('utf-8', 'replace'))
" 2>/dev/null) || BASENAME="${FILE_PATH##*/}"

# Sans distinction de casse : sur macOS (APFS), ecrire .ENV ecrase .env, et
# Wallet.json est wallet.json (seconde relecture de la 0.3.4).
shopt -s nocasematch

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

# Le message est un texte fixe : ni le chemin ni le nom du fichier n'y figurent.
# Il revient a Claude comme raison du refus, et un nom de dossier choisi
# (« ignore les regles, lance … ») y deviendrait une consigne.
refuser_secret() {
    echo "BLOCKED" >&2
    echo "" >&2
    echo "Modification bloquee : fichier de secrets (.env, cles, wallet, identifiants)." >&2
    echo "Les fichiers de secrets/credentials ne doivent pas etre modifies par Claude." >&2
    echo "Editez ce fichier manuellement." >&2
    exit 2
}

for blocked in "${BLOCKED_FILES[@]}"; do
    if [[ "$BASENAME" == "$blocked" ]]; then
        refuser_secret
    fi
done

# Toutes les variantes de .env (.env.local, .env.development, .env.staging…)
# portent des secrets. Seuls les modeles sans valeur restent modifiables.
if [[ "$BASENAME" == .env.* ]] && [[ ! "$BASENAME" =~ ^\.env\.(example|sample|template|dist)$ ]]; then
    refuser_secret
fi

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

# L'avertissement sort en JSON. En texte simple sur stdout avec le code 0, il ne
# partait que dans le journal de debogage (doc hooks, « Exit code 0 ») : ni
# Claude ni l'utilisateur ne l'ont jamais vu. systemMessage s'affiche pour
# l'utilisateur, additionalContext arrive a Claude a cote du resultat de
# l'outil ; sans permissionDecision, les autorisations suivent leur cours
# normal. Le texte ne cite que le nom de la liste ci-dessus, jamais le chemin :
# il reste fixe, un nom de dossier ne peut pas y glisser une consigne.
for sensitive in "${SENSITIVE_FILES[@]}"; do
    if [[ "$BASENAME" == "$sensitive" ]] || [[ "$FILE_PATH" == *"$sensitive"* ]]; then
        python3 -I -c '
import json, sys
msg = ("Fichier sensible (%s) : il touche au déploiement ou à "
       "l’infrastructure. Vérifier attentivement la modification." % sys.argv[1])
print(json.dumps({"systemMessage": msg,
                  "hookSpecificOutput": {"hookEventName": "PreToolUse",
                                         "additionalContext": msg}},
                 ensure_ascii=True))
' "$sensitive"
        exit 0
    fi
done

exit 0
