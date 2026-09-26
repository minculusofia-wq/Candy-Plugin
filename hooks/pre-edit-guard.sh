#!/bin/bash
#
# pre-edit-guard.sh (PreToolUse : Write, Edit, Read, Grep)
# Protege les fichiers de secrets : ni ecrits (Write, Edit), ni lus (Read, Grep).
# Signale les fichiers de deploiement a l'ecriture.
#
# La liste des fichiers de secrets vit dans detection-secrets.py (.env et ses
# variantes, *.env, *.pem, *.key, ~/.ssh hors .pub et config, keystore,
# wallet, mnemonic, .netrc, ~/.claude.json…), partagee avec protect-secrets.
# Jusqu'a la 0.3.4, l'outil Read affichait un .env sans que rien ne l'arrete,
# et backend.env, *.pem ou les cles de ~/.ssh n'etaient pas proteges.
#

set -e
H="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"

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
# Outil Grep : son chemin est dans « path », pas « file_path ». En mode
# « content », il affiche les lignes d'un fichier, meme cache ou ignore par
# git ; -A, -B et -C y ajoutent les lignes voisines. Les noms seuls (defaut) et
# les comptes restent permis. Un dossier est parcouru comme grep -r ; il n'est
# refuse que si le motif trouve une ligne qui porte une valeur — ou s'il est
# trop grand pour etre verifie.
GREP=$(printf '%s' "$INPUT" | python3 -I -c "
import importlib.util, json, os, sys
d = json.loads(sys.stdin.buffer.read().decode('utf-8', 'replace'))
if not isinstance(d, dict) or d.get('tool_name') != 'Grep':
    print('NON'); sys.exit(0)
t = d.get('tool_input') if isinstance(d.get('tool_input'), dict) else {}
if t.get('output_mode') != 'content':
    print('OK'); sys.exit(0)
def charger(nom, chemin):
    spec = importlib.util.spec_from_file_location(nom, chemin); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
ds = charger('ds', sys.argv[1]); ac = charger('ac', sys.argv[2])
ac._detection = lambda: ds
cwd = d.get('cwd') if isinstance(d.get('cwd'), str) else os.getcwd()
chemin, motif = str(t.get('path') or cwd), str(t.get('glob') or '')
# Le glob est developpe comme ripgrep ({.env,x}) et juge comme un joker de bash.
if motif and any(ac.designe_un_secret(m.split('/')[-1], None, True, ds) for m in ac.accolades(motif)):
    print('SECRET'); sys.exit(0)
if ds.est_fichier_de_secrets(chemin):
    print('SECRET'); sys.exit(0)
if os.path.isdir(chemin):
    options = ['-r'] + [f'--include={m}' for m in ac.accolades(motif) if motif]
    try:
        trouves = ac.recherche_recursive('grep', [chemin], options, None, ds)
    except ac.TropGrand:
        print('TROP_GRAND'); sys.exit(0)
    drapeaux = ['-i'] if t.get('-i') else []
    # multiline : un motif sur plusieurs lignes, que la lecture ligne a ligne
    # ne verrait jamais ; juge comme des lignes voisines (relecture de la 0.3.5).
    if any(t.get(k) for k in ('-A', '-B', '-C', 'context', 'multiline')):
        drapeaux.append('-C=1')
    if trouves and ac.motif_trouve('rg', trouves, [str(t.get('pattern') or '')], drapeaux, ds):
        print('SECRET'); sys.exit(0)
print('OK')
" "$H/detection-secrets.py" "$H/analyse-commande.py" 2>/dev/null) || refuser_illisible

FILE_PATH=$(json_get file_path) || refuser_illisible

if [[ -z "$FILE_PATH" && "$GREP" == "NON" ]]; then
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
refuser_lecture() {
    echo "BLOCKED" >&2
    echo "" >&2
    echo "Lecture bloquee : fichier de secrets (.env, cle, wallet, identifiants) — son contenu" >&2
    echo "arriverait en clair dans la conversation." >&2
    echo "Pour verifier qu'une variable existe : grep -c '^NOM=' fichier. Les noms seuls : cut -d= -f1 fichier." >&2
    echo "Un reglage qui n'est pas un secret : grep '^DRY_RUN=' fichier. Un modele (.env.example) se lit." >&2
    echo "Une URL de RPC ou de webhook, un sujet de notification sont des secrets." >&2
    exit 2
}

if [[ "$GREP" == "TROP_GRAND" ]]; then
    echo "BLOCKED" >&2
    echo "" >&2
    echo "Recherche refusee : le dossier est trop grand pour verifier qu'aucun fichier de secrets" >&2
    echo "(.env, cle, wallet) ne serait affiche. La lancer sur un sous-dossier (src/, backend/…)." >&2
    exit 2
fi
[[ "$GREP" == "SECRET" ]] && refuser_lecture
[[ "$GREP" == "OK" ]] && exit 0

OUTIL=$(printf '%s' "$INPUT" | python3 -I -c "
import sys, json
d = json.loads(sys.stdin.buffer.read().decode('utf-8', 'replace'))
print((d.get('tool_name') or '') if isinstance(d, dict) else '')
" 2>/dev/null) || refuser_illisible
# Toutes les variantes de .env (.env.local, backend.env, .env-prod, .env~…)
# portent des secrets ; seuls les modeles sans valeur (.env.example,
# *.template) et les cles publiques (.pub) restent libres.
SECRET=$(printf '%s' "$INPUT" | python3 -I "$H/detection-secrets.py" fichier 2>/dev/null) || refuser_illisible
if [[ "$SECRET" == "SECRET" ]]; then
    [[ "$OUTIL" == "Read" ]] && refuser_lecture
    refuser_secret
fi
# Une lecture ordinaire : rien a signaler (l'avertissement ci-dessous ne
# concerne que l'ecriture).
[[ "$OUTIL" == "Read" ]] && exit 0

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
