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
# Dans un module Python, « jq » peut n'être qu'une donnée (le nom d'une commande
# que le lecteur reconnaît) : seul un appel de sous-processus compte.
verifie "aucun module Python des hooks n'appelle jq" \
        0 "$(grep -cE '(run|Popen|call|check_output|check_call)\(\s*\[\s*["'"'"']jq["'"'"']' hooks/*.py 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')"
verifie "aucun hook n'appelle python sans le 3" \
        0 "$(grep -rhoE '(^|[^a-z0-9_.-])python ' hooks/*.sh 2>/dev/null | grep -c .)"

section "Paquet — tout ce qui est branché existe"
MANQUANTS=$(python3 - <<'PY'
import json, os, re
d = json.load(open("hooks/hooks.json"))
refs = set(re.findall(r'hooks/([a-zA-Z0-9._-]+\.(?:sh|py))', json.dumps(d)))
print(sum(1 for r in refs if not os.path.exists("hooks/" + r)))
PY
)
verifie "chaque hook branché est présent sur le disque" 0 "$MANQUANTS"

# L'outil Monitor lance une commande shell comme Bash, et Read affiche un
# fichier : un matcher « Bash » ou « Write|Edit » est un nom exact (doc hooks,
# « Matcher »). Jusqu'à la 0.3.4, aucun garde-fou des commandes ne voyait
# Monitor, et rien ne regardait Read.
BRANCHEMENTS=$(python3 -I - <<'PY'
import json, re
d = json.load(open("hooks/hooks.json"))["hooks"].get("PreToolUse", [])
def outils(hook):
    return {o for g in d for h in g["hooks"] if hook in h["command"] for o in re.split(r"[|,]", g.get("matcher", ""))}
manque = []
for hook in ("protect-secrets.sh", "rule12-phase-debug-required.sh", "validate-before-push.sh"):
    for o in ("Bash", "Monitor"):
        if o not in outils(hook):
            manque.append(f"{hook}:{o}")
for o in ("Write", "Edit", "Read", "Grep"):
    if o not in outils("pre-edit-guard.sh"):
        manque.append(f"pre-edit-guard.sh:{o}")
# Le témoin de /fin-phase n'est retiré qu'après le commit réellement passé.
apres = [h["command"] for g in json.load(open("hooks/hooks.json"))["hooks"].get("PostToolUse", [])
         if "Bash" in re.split(r"[|,]", g.get("matcher", "")) for h in g["hooks"]]
if not any("rule12-phase-debug-required.sh" in c and c.rstrip("'").endswith(" apres") for c in apres):
    manque.append("PostToolUse:rule12 apres")
print(" ".join(manque))
PY
)
verifie "les garde-fous voient Bash et Monitor, et la lecture d'un fichier :${BRANCHEMENTS:+ }$BRANCHEMENTS" "" "$BRANCHEMENTS"

verifie "les hooks retirés du paquet public ne sont pas revenus" \
        0 "$(ls hooks/rule5-debug-local-only.sh hooks/rule6-session-end.sh hooks/rule7-readme-before-push.sh \
                hooks/rule9-code-discipline.sh hooks/skills-reminder.sh 2>/dev/null | grep -c .)"

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
motif = r'(bash|python3)(?: -I)? \\"\$\{CLAUDE_PLUGIN_ROOT\}/hooks/([a-zA-Z0-9._-]+\.(?:sh|py))\\"'
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
# Les modules Python des hooks (.py) : toujours lus par python3. Un .py cassé
# ferait refuser toutes les commandes par les garde-fous qui l'importent.
for f in hooks/*.py; do
    [ -f "$f" ] || continue
    python3 -I -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' "$f" 2>/dev/null \
        || CASSES="$CASSES $(basename "$f")"
done
verifie "chaque hook est lisible par son interpréteur :$CASSES" "" "$CASSES"

# Second contrôle : le comportement réel.
PLANTES=0
DETAIL=""
BRANCHES_PY=$(echo "$INTERPRETEURS" | awk '$1 ~ /\.py$/ {print "hooks/" $1}')
for f in hooks/*.sh $BRANCHES_PY; do
    NOM="$(basename "$f")"
    # Ceux-là attendent un dossier en argument, pas du JSON : ils ont leurs
    # propres groupes de cas (01, 05, 07 et 09).
    case "$NOM" in
        verifier-projet.sh|session-end-md-audit.sh|verifier-setup.sh|est-un-bot.sh) continue ;;
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

section "Paquet — un module posé dans le projet ne s'exécute jamais"
# « python3 -c », « python3 - » et « python3 -m » placent le dossier courant —
# celui du projet — en tête des chemins de modules ; « python3 script.py » y
# place le dossier du script. Un json.py à la racine d'un dépôt s'exécutait à
# chaque message tapé, avec les droits de l'utilisateur, sans rien changer de
# visible (trouvé par la relecture de sécurité de la 0.3.1). « python3 -I »
# ferme la porte.
#
# Deux contrôles, parce que l'un seul ne suffit pas (vérifié) :
#   · statique : tout appel à python3 dans les hooks porte -I. C'est lui qui voit
#     un script lancé depuis le dossier temporaire, qu'on ne peut pas piéger ici ;
#   · réel : chaque branchement de hooks.json rejoué tel quel dans un projet
#     piégé — avec de quoi faire parler chaque hook jusqu'à son Python (une
#     tâche en attente, un CLAUDE.md trop long). Sans elles, quatre appels sur
#     quatorze restaient verts même privés de -I.
# verifier-projet.sh n'est pas concerné : faire tourner le code du projet est
# son travail.
SANS_I=$(python3 - <<'FIN_PY_I'
import glob, re
n = []
for f in sorted(glob.glob("hooks/*.sh")) + ["hooks/hooks.json"]:
    for i, ligne in enumerate(open(f, encoding="utf-8"), 1):
        if ligne.lstrip().startswith("#"):
            continue
        # python3 en toutes lettres, et les interpretes choisis par
        # validate-before-push, lances en tete de commande (« $("$cand" »,
        # « | "$PY" ») : ceux-la aussi.
        for m in re.finditer(r"(?<![\w.-])python3(?![\w.-])|(?:\$\(|\|\s*|^\s*)\"\$(?:PY|cand)\"", ligne):
            if not ligne[m.end():].startswith(" -I"):
                n.append(f"{f}:{i}")
# Dans les modules .py, un python3 lancé en sous-processus (« "python3" » ou
# sys.executable dans une liste d'arguments) doit porter "-I" juste après.
for f in sorted(glob.glob("hooks/*.py")):
    for i, ligne in enumerate(open(f, encoding="utf-8"), 1):
        if ligne.lstrip().startswith("#"):
            continue
        for m in re.finditer(r"([\"'])python3\1|sys\.executable", ligne):
            if not re.match(r"\s*,\s*([\"'])-I\1", ligne[m.end():]):
                n.append(f"{f}:{i}")
print(" ".join(n))
FIN_PY_I
)
verifie "tout appel à python3 dans les hooks porte -I :${SANS_I:+ }$SANS_I" "" "$SANS_I"

PIEGE=$(mktemp -d)
trap 'rm -rf "$PIEGE"' EXIT
for m in json py_compile re glob datetime unicodedata; do
    cat > "$PIEGE/$m.py" <<EOF
open("$PIEGE/.temoin", "a").write("$m\n")
raise ImportError("module piégé")
EOF
done
printf 'ligne\n%.0s' $(seq 201) > "$PIEGE/CLAUDE.md"
# Un dépôt avec un .py commité : sans lui, le contrôle avant push s'arrête
# avant son Python (il lit les commits) et ce rejeu ne vérifie rien pour lui.
git -C "$PIEGE" init -q && printf 'x = 1\n' > "$PIEGE/app.py" && git -C "$PIEGE" add app.py \
    && git -C "$PIEGE" -c user.email=t@t.t -c user.name=t -c commit.gpgsign=false commit -qm piege
printf '%s | tâche piégée | - |\n' "$PIEGE" > "$PIEGE/.rappels.txt"
FAUTIFS=""
# Deux fichiers : a.txt passe par le chemin ordinaire, Dockerfile par la branche
# « fichier sensible » de pre-edit-guard, qui a son propre appel à python3.
for FICHIER in a.txt Dockerfile; do
ENTREE_PIEGE=$(python3 -c 'import json,sys; p=sys.argv[1]; print(json.dumps({"tool_input":{"command":"git push","file_path":p+"/"+sys.argv[2],"content":"x","new_string":"x"},"prompt":"bonjour","cwd":p,"last_assistant_message":"Voila.","session_id":"test","source":"startup"}))' "$PIEGE" "$FICHIER")
N=0
while IFS= read -r CMD; do
    [ -n "$CMD" ] || continue
    N=$((N + 1))
    rm -f "$PIEGE/.temoin"
    ( cd "$PIEGE" && printf '%s' "$ENTREE_PIEGE" \
        | env CLAUDE_PLUGIN_ROOT="$RACINE" CLAUDE_PROJECT_DIR="$PIEGE" RAPPEL_MAISON="$PIEGE" \
              RAPPELS_PROJETS="$PIEGE/.rappels.txt" JEU_CACHE="$PIEGE/.cache-jeu" \
              CONTROLE_ETATS="$PIEGE/.etats" bash -c "$CMD" >/dev/null 2>&1 )
    [ -f "$PIEGE/.temoin" ] && FAUTIFS="$FAUTIFS hooks.json#$N($(printf '%s' "$CMD" | grep -oE 'hooks/[a-zA-Z0-9._-]+' | tail -1 | sed 's#hooks/##'), $FICHIER)"
done <<< "$(python3 -c 'import json
for groupes in json.load(open("hooks/hooks.json"))["hooks"].values():
    for g in groupes:
        for h in g["hooks"]:
            print(h["command"])')"
done
# Le contrôle du setup n'est pas branché : /maintenance le lance depuis le
# dossier où l'on se trouve.
rm -f "$PIEGE/.temoin"
mkdir -p "$PIEGE/reglages/projects/p/memory"
printf 'x\n' > "$PIEGE/reglages/projects/p/memory/a.md"
printf 'x\n' > "$PIEGE/reglages/settings.json"
( cd "$PIEGE" && bash "$RACINE/hooks/verifier-setup.sh" "$PIEGE/reglages" >/dev/null 2>&1 )
[ -f "$PIEGE/.temoin" ] && FAUTIFS="$FAUTIFS verifier-setup.sh"
verifie "aucun hook n'exécute un module posé dans le projet (json, re, glob…) :$FAUTIFS" "" "$FAUTIFS"

section "Paquet — rien ne présente l'utilisateur comme débutant"
# /debug affirmait à tout utilisateur du plugin « L'utilisateur n'est pas dev »
# (0.3.4, commands/debug.md). Le profil décrit par communication-style.md est
# facultatif ; aucun texte livré n'a à supposer qui lit.
PROFIL=$(git ls-files '*.md' 2>/dev/null | tr '\n' '\0' | xargs -0 grep -n -i -E \
    "pas dev([^a-z]|$)|non-dev|n.est pas (un )?d[ée]veloppeu|non-d[ée]veloppeu|d[ée]butant|not a dev|non-dev|isn.t a dev|beginner" \
    2>/dev/null | grep -v '^tests/06-paquet.sh' | cut -d: -f1-2 | tr '\n' ' ')
verifie "aucun .md ne dit que l'utilisateur n'est pas développeur :${PROFIL:+ }$PROFIL" "" "$PROFIL"

section "Paquet — les règles et les commandes désignent ce qui existe"
# Les règles se copient à la main dans ~/.claude/rules (README) : Claude Code n'y
# remplace aucune variable, et ${CLAUDE_PLUGIN_ROOT} est vide dans l'outil Bash
# (doc des plugins, « Where each variable resolves »). Cinq chemins de la 0.3.4
# devenaient « bash /hooks/verifier-projet.sh ». Une règle désigne donc une
# commande du plugin, jamais un fichier.
verifie "aucune règle n'écrit de chemin \${CLAUDE_PLUGIN_ROOT} :$(grep -ln 'CLAUDE_PLUGIN_ROOT' rules/*.md 2>/dev/null | tr '\n' ' ')" \
        0 "$(grep -c 'CLAUDE_PLUGIN_ROOT' rules/*.md 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')"
CITEES=$(grep -ohE '`/[a-z][a-z-]+`' rules/*.md 2>/dev/null | tr -d '`/' | sort -u)
ABSENTES=""
for c in $CITEES; do
    case "$c" in effort|model|plugin|code-review|clear|compact|config|mcp|hooks) continue ;; esac
    [ -f "commands/$c.md" ] || ABSENTES="$ABSENTES $c"
done
verifie "chaque commande citée par une règle existe :$ABSENTES" "" "$ABSENTES"
# Dans une commande, seule la forme ${CLAUDE_PROJECT_DIR} est remplacée ; sans
# accolades, elle arrive vide dans Bash (fin-session, 0.3.4).
verifie "aucune commande n'écrit \$CLAUDE_PROJECT_DIR sans accolades" \
        0 "$(grep -c '\$CLAUDE_PROJECT_DIR' commands/*.md 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')"
# Les contrôles portent sur la racine du dépôt : « $PWD » glisse dans backend/
# ou ios/ au fil d'une session, et le contrôle ne voyait plus que ce dossier.
verifie "aucune commande ne lance un contrôle sur \"\$PWD\" :$(grep -nE '(verifier-projet|session-end-md-audit|jeu-de-documents)\.sh"? "\$PWD"' commands/*.md | cut -d: -f1-2 | tr '\n' ' ')" \
        0 "$(grep -cE '(verifier-projet|session-end-md-audit|jeu-de-documents)\.sh"? "\$PWD"' commands/*.md | awk -F: '{s+=$2} END {print s+0}')"
verifie "/verifier lance aussi le contrôle du jeu de documents" \
        1 "$(grep -c 'hooks/jeu-de-documents.sh' commands/verifier.md)"

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
