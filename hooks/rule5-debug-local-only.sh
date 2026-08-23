#!/bin/bash
#
# rule5-debug-local-only.sh (PreToolUse: Bash)
# Regle 5: Debug en local uniquement, jamais sur VPS
#
# Bloque ssh, scp, rsync vers un VPS.
#

set -e

INPUT=$(cat)
json_get() { python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('tool_input',{}).get('$1',''))" <<< "$INPUT" 2>/dev/null; }

COMMAND=$(json_get command)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Detecter les commandes de connexion VPS
VPS_PATTERNS=(
    '^ssh\s'
    '\sssh\s'
    '^scp\s'
    '\sscp\s'
    '^rsync\s.*@'
    '^ssh-add'
    'ssh\s+.*@'
)

# Exceptions autorisees (scripts de deploiement explicites)
DEPLOY_EXCEPTIONS=(
    'deploy_to_vps.sh'
    'deploy.sh'
    'bash.*deploy'
)

# Verifier si c'est un deploiement autorise
for exception in "${DEPLOY_EXCEPTIONS[@]}"; do
    if echo "$COMMAND" | grep -qE "$exception"; then
        exit 0
    fi
done

# Exceptions LECTURE SEULE autorisees (verification post-deploiement)
# Claude peut verifier que le bot tourne bien apres que l'utilisateur a deploye
# mais ne peut rien modifier/redemarrer/tuer.
# On autorise uniquement si la commande SSH ne contient QUE des verbes read-only.
READ_ONLY_COMMANDS='^(pgrep|pidof|ps|curl -s|curl -w|grep|tail|head|cat|ls|stat|wc|awk|sed -n|sort|uniq|echo|date|df|du|uptime|free|which|test -|\[ -)'

# Verifier si c'est une commande SSH read-only
if echo "$COMMAND" | grep -qE '(^ssh\s|\sssh\s|ssh\s+.*@)'; then
    # Extraire la partie apres le dernier " (commande distante)
    # Format attendu: ssh ... "cmd_distante"
    REMOTE_CMD=$(echo "$COMMAND" | python3 -c "
import sys, re
line = sys.stdin.read()
# Chercher la partie entre guillemets doubles (commande distante)
matches = re.findall(r'\"([^\"]*)\"|\x27([^\x27]*)\x27', line)
if matches:
    # Prendre la derniere (la commande distante arrive apres les options ssh)
    last = matches[-1]
    print(last[0] or last[1])
" 2>/dev/null)

    if [[ -n "$REMOTE_CMD" ]]; then
        # Verifier que CHAQUE sous-commande (separee par ; && || |) est read-only
        # On rejette si on trouve des verbes dangereux
        DANGEROUS='(^|\s|;|&&|\|\||\|)\s*(rm|mv|cp|touch|mkdir|rmdir|chmod|chown|kill|pkill|killall|fuser|nohup|systemctl|service|reboot|shutdown|apt|pip|dd|tee|truncate|>|>>|sed -i|python|bash|sh|nano|vim|vi|git (push|commit|reset|checkout|pull)|source)'
        if echo "$REMOTE_CMD" | grep -qE "$DANGEROUS"; then
            echo "BLOCKED" >&2
            echo "" >&2
            echo "=== REGLE 5 VIOLEE: DEBUG-LOCAL-ONLY ===" >&2
            echo "Commande SSH contient une action modificatrice: $REMOTE_CMD" >&2
            echo "" >&2
            echo "Seules les commandes de LECTURE SEULE sont autorisees sur le VPS" >&2
            echo "(pgrep, curl -s, tail, grep, cat, ls, etc.)" >&2
            echo "Pour modifier/redemarrer: lance ton script de deploiement manuellement." >&2
            echo "=== FIN REGLE 5 ===" >&2
            exit 2
        fi
        # Commande SSH read-only autorisee
        exit 0
    fi
fi

# Exception LECTURE SEULE: scp en TELECHARGEMENT (VPS -> local)
# Copier un fichier DEPUIS le VPS vers la machine locale est de la lecture pure :
# ca ne modifie rien sur le VPS. On l'autorise.
# Un download a la source distante (user@host:chemin) AVANT la destination locale.
# Un upload (local -> VPS) a la destination distante en DERNIER : on continue a le bloquer.
if echo "$COMMAND" | grep -qE '(^scp\s|\sscp\s)'; then
    # Recuperer les arguments apres "scp" (en ignorant les options -i/-o/-P/-r etc.)
    IS_DOWNLOAD=$(echo "$COMMAND" | python3 -c "
import sys, shlex
line = sys.stdin.read().strip()
try:
    toks = shlex.split(line)
except ValueError:
    print('NO'); sys.exit()
# Isoler les tokens scp (apres un eventuel cd ... &&)
if 'scp' in toks:
    toks = toks[toks.index('scp')+1:]
else:
    print('NO'); sys.exit()
# Retirer les options et leurs valeurs
opts_with_val = {'-i','-o','-P','-l','-c','-F','-S','-J','-W'}
args = []
i = 0
while i < len(toks):
    t = toks[i]
    if t in opts_with_val:
        i += 2; continue
    if t.startswith('-'):
        i += 1; continue
    args.append(t); i += 1
# Il faut au moins source + dest
if len(args) < 2:
    print('NO'); sys.exit()
src, dest = args[0], args[-1]
src_remote = ':' in src and '@' in src.split(':',1)[0]
dest_remote = ':' in dest and '@' in dest.split(':',1)[0]
# Download autorise : source distante, destination locale
print('YES' if (src_remote and not dest_remote) else 'NO')
" 2>/dev/null)

    if [[ "$IS_DOWNLOAD" == "YES" ]]; then
        # scp en telechargement (VPS -> local) : lecture seule, autorise
        exit 0
    fi
fi

# Verifier si c'est une commande SSH/SCP/rsync
for pattern in "${VPS_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qE "$pattern"; then
        echo "BLOCKED" >&2
        echo "" >&2
        echo "=== REGLE 5 VIOLEE: DEBUG-LOCAL-ONLY ===" >&2
        echo "Commande: $COMMAND" >&2
        echo "" >&2
        echo "Debug interdit sur le VPS. Toujours debugger en LOCAL." >&2
        echo "Meme si le bot tourne en prod sur un VPS, le debug se fait sur" >&2
        echo "la copie locale. L'utilisateur redeploiera avec son script." >&2
        echo "" >&2
        echo "Si c'est un deploiement legitime, utilise le script deploy_to_vps.sh" >&2
        echo "ou equivalent du projet." >&2
        echo "=== FIN REGLE 5 ===" >&2
        exit 2
    fi
done

exit 0
