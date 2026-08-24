#!/bin/bash
#
# protect-secrets.sh - Refuse d'ecrire un secret en clair dans le depot
#
# CE QU'IL BLOQUE, ET POURQUOI SI PEU
# -----------------------------------
# Une VALEUR qui ressemble a un secret, affectee a un nom sensible :
#     PRIVATE_KEY = "0x3f8a..."
# Rien d'autre. Pas le nom de variable seul, pas une chaine hexadecimale
# isolee, pas un mot dans une phrase.
#
# La version precedente cherchait un nom de variable suivi d'un signe egal,
# n'importe ou. Elle bloquait `api_key = None`, tout hash de transaction ou sha256
# (0x suivi de 64 hexa) et jusqu'a la documentation qui parle de phrases de
# recuperation de portefeuille. Un garde-fou qu'on contourne trois fois par
# jour finit desinstalle, et c'est alors le vrai secret qui passe.
#
# Ne sont donc PAS bloques : une valeur vide ou nulle, un appel a une variable
# d'environnement, un gabarit, une valeur trop courte ou sans entropie.
#
# Il reste un rappel mecanique, pas un audit de securite : il lit du texte
# ligne a ligne. Ne jamais lire son silence comme la preuve qu'il n'y a pas de
# secret.
#

set -e

INPUT=$(cat)

# --- Detection : une valeur qui ressemble a un secret ---
TROUVE=$(printf '%s' "$INPUT" | python3 -c '
import sys, json, re

try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

ti = d.get("tool_input", {}) or {}
morceaux = [
    ("commande bash", ti.get("command", "")),
    ("contenu du fichier (%s)" % ti.get("file_path", ""), ti.get("content", "")),
    ("edition du fichier (%s)" % ti.get("file_path", ""), ti.get("new_string", "")),
]

NOM = (r"(?:private[_-]?key|secret[_-]?key|api[_-]?key|api[_-]?secret|"
       r"client[_-]?secret|access[_-]?token|auth[_-]?token|mnemonic|"
       r"passphrase|password|passwd)")

CITE = re.compile(NOM + r"\s*[:=]\s*([\"\x27])(?P<v>(?:(?!\1).)*)\1", re.I)
NUE  = re.compile(NOM + r"\s*=\s*(?P<v>[^\s\"\x27#;]+)\s*$", re.I | re.M)

GABARIT = re.compile(r"[$<>{}()\[\]]|^(?:os\.|process\.|env\.|import\b)", re.I)
FACTICE = re.compile(r"^(?:x{3,}|\.{3,}|\*{3,}|-{3,}|none|null|nil|true|false|"
                     r"your[_-]|my[_-]|the[_-]|test|dummy|fake|sample|example|"
                     r"placeholder|changeme|change[_-]me|todo|fixme|secret|"
                     r"redacted|hidden|masked)", re.I)

def ressemble_a_un_secret(v):
    v = v.strip()
    if len(v) < 16:
        return False
    if GABARIT.search(v):
        return False
    if FACTICE.match(v):
        return False
    mots = v.split()
    if len(mots) >= 8:
        return all(m.isalpha() for m in mots)
    if len(mots) > 1:
        return False
    return any(c.isdigit() for c in v) and any(c.isalpha() for c in v)

for source, texte in morceaux:
    if not texte:
        continue
    for motif in (CITE, NUE):
        for m in motif.finditer(texte):
            if ressemble_a_un_secret(m.group("v")):
                extrait = m.group(0).strip()
                if len(extrait) > 60:
                    extrait = extrait[:57] + "..."
                print("%s\t%s" % (source, extrait))
                sys.exit(0)
' 2>/dev/null)

if [[ -n "$TROUVE" ]]; then
    SOURCE="${TROUVE%%$'\t'*}"
    EXTRAIT="${TROUVE#*$'\t'}"
    echo "BLOCKED"
    echo ""
    echo "Valeur qui ressemble a un secret dans $SOURCE"
    echo "  $EXTRAIT"
    echo ""
    echo "Ne jamais ecrire un secret en clair dans le depot."
    echo "Le lire depuis une variable d'environnement (.env non suivi par git)."
    exit 2
fi

# --- Garde .env : refuser de suivre un .env qui n'est pas ignore ---
COMMAND=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('tool_input',{}).get('command',''))" 2>/dev/null)

if [[ -n "$COMMAND" ]] && echo "$COMMAND" | grep -qE 'git\s+add.*\.env($|\s)|git\s+add\s+-A|git\s+add\s+\.'; then
    PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        if [[ ! -f "$PROJECT_DIR/.gitignore" ]] || ! grep -q '\.env' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
            echo "BLOCKED"
            echo ""
            echo "Ce projet a un .env, et .gitignore ne l'ignore pas."
            echo "Ajouter .env au .gitignore avant de faire un git add."
            exit 2
        fi
    fi
fi

exit 0
