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
    saute "le validateur officiel accepte le paquet" "la commande claude est absente de cette machine"
fi

section "Paquet — aucune dépendance non annoncée"
# On retire les lignes entièrement en commentaire avant de chercher, au lieu
# d'exclure un fichier. L'exclusion faisait taire une occurrence qui n'était
# qu'un commentaire — mais elle retirait DU MÊME COUP tout le fichier de la
# surveillance : un vrai appel à jq y passait inaperçu (vérifié).
# Seules les lignes tout en commentaire sont retirées : un « # » au milieu d'une
# ligne peut se trouver dans une chaîne, et masquerait un appel réel.
verifie "aucun hook n'appelle jq" \
        0 "$(sed 's/^[[:space:]]*#.*$//' hooks/*.sh hooks/hooks.json 2>/dev/null | grep -cE '(^|[^a-zA-Z0-9_.-])jq($|[^a-zA-Z0-9_.-])')"
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
# Chaque hook est lancé avec l'interpréteur que hooks.json lui associe VRAIMENT.
# Tout lancer avec bash rendait ce contrôle inutile : relire-ma-reponse.sh est un
# script Python, il mourait sur une erreur de syntaxe et sortait en 2 — un code
# que l'ancien seuil « plus grand que 2 » prenait pour un blocage normal.
#
# Sur une entrée ordinaire (« ls », « bonjour »), aucun hook n'a de raison de
# bloquer ni de se plaindre : on exige la sortie 0 ET le silence sur la sortie
# d'erreur. Une erreur de syntaxe, où qu'elle soit, viole l'un ou l'autre.
INTERPRETEURS=$(python3 - <<'FIN_PY_INTERP'
import json, re
d = json.dumps(json.load(open("hooks/hooks.json")))
motif = r'(bash|python3) \\"\$\{CLAUDE_PLUGIN_ROOT\}/hooks/([a-zA-Z0-9._-]+\.sh)\\"'
for interp, nom in re.findall(motif, d):
    print(nom, interp)
FIN_PY_INTERP
)

# Premier contrôle : la syntaxe, lue en entier. Lancer le hook ne suffit pas —
# bash n'analyse un script qu'au fur et à mesure, donc une faute placée après le
# point de sortie n'est jamais vue. Vérifié : elle passait inaperçue.
CASSES=""
for f in hooks/*.sh; do
    NOM="$(basename "$f")"
    INTERP=$(echo "$INTERPRETEURS" | awk -v n="$NOM" '$1==n {print $2; exit}')
    [ -n "$INTERP" ] || INTERP=bash
    if [ "$INTERP" = "python3" ]; then
        python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$f" 2>/dev/null \
            || CASSES="$CASSES $NOM"
    else
        bash -n "$f" 2>/dev/null || CASSES="$CASSES $NOM"
    fi
done
verifie "chaque hook est lisible par son interpréteur :$CASSES" "" "$CASSES"

# Second contrôle : le comportement réel.
PLANTES=0
DETAIL=""
for f in hooks/*.sh; do
    NOM="$(basename "$f")"
    # Ceux-là attendent un dossier en argument, pas du JSON : ils ont leurs
    # propres groupes de cas (01, 05 et 07).
    case "$NOM" in
        verifier-projet.sh|session-end-md-audit.sh|verifier-setup.sh) continue ;;
    esac
    INTERP=$(echo "$INTERPRETEURS" | awk -v n="$NOM" '$1==n {print $2; exit}')
    [ -n "$INTERP" ] || INTERP=bash
    ERREUR=$(printf '{"tool_input":{"command":"ls"},"prompt":"bonjour","cwd":"/tmp"}' \
        | CLAUDE_PROJECT_DIR=/tmp "$INTERP" "$f" 2>&1 >/dev/null)
    CODE=$?
    if [ "$CODE" -ne 0 ] || [ -n "$ERREUR" ]; then
        PLANTES=$((PLANTES + 1))
        DETAIL="$DETAIL $NOM(code=$CODE)"
    fi
done
verifie "aucun hook ne plante ni ne se plaint :$DETAIL" 0 "$PLANTES"

section "Paquet — les images des README existent"
ABSENTES=$(python3 - <<'PY'
import re, os
n = 0
for f in ("README.md", "README.fr.md"):
    texte = open(f).read()
    # Les deux ecritures possibles. Seules les balises HTML etaient regardees :
    # une image en syntaxe markdown pointant vers un fichier absent partait en
    # public sans un mot (verifie).
    cibles = (re.findall(r'<img src="([^"]+)"', texte)
              + [c.split()[0].strip("<>") for c in re.findall(r'!\[[^\]]*\]\(([^)]+)\)', texte) if c.strip()])
    for src in cibles:
        if not src.startswith("http") and not os.path.exists(src):
            n += 1
print(n)
PY
)
verifie "aucune image manquante" 0 "$ABSENTES"

bilan
