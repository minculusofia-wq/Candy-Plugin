#!/bin/bash
#
# Le paquet lui-même : il doit être installable, et ne dépendre que de ce qu'il
# annonce.
#
# Deux défauts trouvés en installant vraiment le plugin, qu'aucun test de hook
# isolé ne pouvait révéler : le manifeste était refusé par le validateur — donc
# personne n'aurait pu l'installer — et deux garde-fous dépendaient de jq,
# absent par défaut sur macOS, ce qui les faisait échouer en silence.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RACINE"

section "Paquet — les manifestes"
python3 -c "import json,sys; json.load(open('.claude-plugin/marketplace.json'))" 2>/dev/null
verifie "le manifeste du marketplace est du JSON valide" 0 $?
python3 -c "import json,sys; json.load(open('.claude-plugin/plugin.json'))" 2>/dev/null
verifie "le manifeste du plugin est du JSON valide" 0 $?
python3 -c "import json,sys; json.load(open('hooks/hooks.json'))" 2>/dev/null
verifie "le branchement des hooks est du JSON valide" 0 $?

verifie "la description du marketplace est au bon endroit" \
        1 "$(python3 -c "import json; d=json.load(open('.claude-plugin/marketplace.json')); print(1 if 'description' in d.get('metadata',{}) and 'description' not in d else 0)")"

if command -v claude >/dev/null 2>&1; then
    verifie "le validateur officiel accepte le paquet" \
            1 "$(claude plugin validate . 2>&1 | grep -c 'Validation passed')"
else
    printf '  %s·%s validateur officiel absent, contrôle sauté\n' "$GRIS" "$NC"
fi

section "Paquet — aucune dépendance non annoncée"
verifie "aucun hook n'appelle jq" \
        0 "$(grep -rlE '(^|[^a-z-])jq ' hooks/*.sh hooks/hooks.json 2>/dev/null | grep -v '^hooks/controle-si-code-modifie.sh$' | grep -c .)"
verifie "aucun hook n'appelle python sans le 3" \
        0 "$(grep -rhoE '(^|[^a-z0-9_.-])python ' hooks/*.sh 2>/dev/null | grep -c .)"

section "Paquet — tout ce qui est branché existe"
MANQUANTS=$(python3 - <<'PY'
import json, os, re
d = json.load(open("hooks/hooks.json"))
refs = set(re.findall(r'hooks/([a-zA-Z0-9._-]+\.sh)', json.dumps(d)))
print(sum(1 for r in refs if not os.path.exists("hooks/" + r)))
PY
)
verifie "chaque hook branché est présent sur le disque" 0 "$MANQUANTS"

verifie "les hooks retirés du paquet public ne sont pas revenus" \
        0 "$(ls hooks/rule5-debug-local-only.sh hooks/rule6-session-end.sh 2>/dev/null | grep -c .)"

section "Paquet — aucun hook ne plante sur une entrée ordinaire"
PLANTES=0
for f in hooks/*.sh; do
    case "$(basename "$f")" in
        verifier-projet.sh|session-end-md-audit.sh) continue ;;
    esac
    printf '{"tool_input":{"command":"ls"},"prompt":"bonjour","cwd":"/tmp"}' \
        | CLAUDE_PROJECT_DIR=/tmp bash "$f" >/dev/null 2>&1
    [ $? -gt 2 ] && PLANTES=$((PLANTES + 1))
done
verifie "aucun hook ne sort d'un code imprévu" 0 "$PLANTES"

section "Paquet — les images des README existent"
ABSENTES=$(python3 - <<'PY'
import re, os
n = 0
for f in ("README.md", "README.fr.md"):
    for src in re.findall(r'<img src="([^"]+)"', open(f).read()):
        if not src.startswith("http") and not os.path.exists(src):
            n += 1
print(n)
PY
)
verifie "aucune image manquante" 0 "$ABSENTES"

bilan
