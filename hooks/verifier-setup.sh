#!/bin/bash
#
# verifier-setup.sh — le contrôle du dossier ~/.claude lui-même.
#
# POURQUOI
# --------
# Le contrôle universel `verifier-projet.sh` répond « AUCUN MOYEN DE
# VERIFICATION TROUVE » quand on le lance sur ~/.claude. C'est normal : ce
# dossier n'est le projet de personne. Résultat, c'est le seul endroit où un
# mécanisme peut mourir sans que rien ne le signale.
#
# Les pannes visées ne cassent rien — elles ne font plus rien, et c'est pire :
#   · un hook déclaré dans settings.json dont le script n'existe plus ;
#   · un hook branché qui écrit ses messages là où personne ne les lit ;
#   · un fichier de skill au mauvais format, donc jamais chargé ;
#   · une mémoire qui affirme une échéance dépassée depuis des semaines ;
#   · la même consigne écrite dans une règle ET dans un hook, donc envoyée
#     deux fois dans la même fenêtre de contexte.
#
# Ne corrige rien. Signale, et rend la main.
#
# Usage :  bash verifier-setup.sh [dossier]     (défaut : ~/.claude)
# Code retour : 0 si rien à signaler, 1 sinon.
#

set -u

CLAUDE="${1:-$HOME/.claude}"
ALERTES=0

if [ -t 1 ]; then
    R=$'\033[0;31m'; J=$'\033[0;33m'; V=$'\033[0;32m'; N=$'\033[0m'
else
    R=""; J=""; V=""; N=""
fi

alerte() { printf '  %s✗%s %s\n' "$R" "$N" "$1"; ALERTES=$((ALERTES + 1)); }
avert()  { printf '  %s⚠%s %s\n' "$J" "$N" "$1"; ALERTES=$((ALERTES + 1)); }
ok()     { printf '  %s✓%s %s\n' "$V" "$N" "$1"; }

if [ ! -d "$CLAUDE" ]; then
    echo "Dossier introuvable : $CLAUDE"
    exit 1
fi

echo "=== CONTRÔLE DU SETUP $CLAUDE ==="
echo "Date : $(date +%Y-%m-%d)"
echo

# ---------------------------------------------------------------- 1. Hooks ---
# Un script de hooks/ est vivant s'il est branché dans settings.json OU appelé
# par une commande ou une règle. Ne tester que settings.json est le piège : un
# outil lancé par une commande passerait pour un orphelin (vérifié — cette
# erreur a été commise en écrivant ce script).
echo "[1/7] Hooks : branchés ou appelés ailleurs"
AV=$ALERTES
NB=0
if [ -d "$CLAUDE/hooks" ]; then
    for f in "$CLAUDE"/hooks/*.sh "$CLAUDE"/hooks/*.py; do
        [ -f "$f" ] || continue
        b=$(basename "$f")
        NB=$((NB + 1))
        grep -q "$b" "$CLAUDE/settings.json" 2>/dev/null && continue
        grep -rq "$b" "$CLAUDE/commands" "$CLAUDE/rules" "$CLAUDE/hooks" \
            --exclude="$b" 2>/dev/null && continue
        avert "hooks/$b n'est ni branché dans settings.json ni appelé par une commande ou une règle"
    done
fi
[ "$ALERTES" = "$AV" ] && ok "$NB script(s) personnel(s), tous branchés ou appelés"

# ------------------------------------------------------ 2. Hooks entendus ---
# Branché ne veut pas dire entendu. Sur le poste d'origine, quatre hooks
# branchés écrivaient leurs avertissements depuis leur installation sans que ni
# Claude ni l'utilisateur ne les aient jamais vus — et le contrôle 1 les disait
# vivants.
#
# La règle vient de la doc de Claude Code (hooks.md, « Exit code 0 » et « Other
# exit codes ») : ce qu'un hook écrit en sortant avec 0 part dans le journal de
# débogage, sauf un message normal (stdout) sur UserPromptSubmit,
# UserPromptExpansion, SessionStart ou PostModelSwitch. Un hook est entendu
# s'il bloque (sortie 2), s'il rend du JSON (systemMessage, additionalContext,
# decision...), ou s'il sort en erreur (l'utilisateur voit une ligne « hook
# error »).
#
# Lecture du code, pas exécution : un hook écrit autrement peut tromper ce
# contrôle, il se vérifie alors à la main. Un hook qui n'écrit rien (il agit sur
# un fichier) n'est pas concerné.
echo
echo "[2/7] Hooks : entendus par quelqu'un"
python3 - "$CLAUDE" <<'PYMUET'
import json, os, re, sys
claude = sys.argv[1]
C = sys.stdout.isatty()
R, J, V, N = ("\033[0;31m", "\033[0;33m", "\033[0;32m", "\033[0m") if C else ("", "", "", "")

chemin_reglages = os.path.join(claude, "settings.json")
if not os.path.isfile(chemin_reglages):
    print(f"  {V}✓{N} aucun settings.json : aucun hook personnel branché")
    sys.exit(0)
try:
    reglages = json.load(open(chemin_reglages, encoding="utf-8"))
except (OSError, ValueError):
    print(f"  {R}✗{N} settings.json illisible : impossible de savoir quels hooks sont branchés")
    sys.exit(1)

CONTEXTE = {"UserPromptSubmit", "UserPromptExpansion", "SessionStart", "PostModelSwitch"}
JSON = re.compile(r"systemMessage|additionalContext|permissionDecision|hookSpecificOutput|[\"']decision[\"']")
AFFICHE = re.compile(r"(^|;|&&|\bthen|\bdo|\belse)\s*(echo|printf|cat)\b")

# (nom du script, événement) -> lancé par python3 ?
branches = {}
for evt, groupes in (reglages.get("hooks") or {}).items():
    for g in groupes or []:
        for h in g.get("hooks", []):
            for interprete, nom in re.findall(r"(\S+)\s+(?:~|\$HOME)/\.claude/hooks/([\w.-]+)", h.get("command", "")):
                branches.setdefault((nom, evt), "python" in interprete)

def muet(nom, evt, lance_en_python):
    chemin = os.path.join(claude, "hooks", nom)
    if not os.path.isfile(chemin):
        return False
    lignes = open(chemin, encoding="utf-8", errors="replace").read().splitlines()
    en_py = lance_en_python or bool(lignes and "python" in lignes[0])
    code = [l for l in lignes if not l.lstrip().startswith("#")]
    stdout = stderr = False
    for l in code:
        if en_py:
            if "sys.stderr" in l and re.search(r"print\(|\.write\(", l):
                stderr = True
            elif re.search(r"\bprint\(|sys\.stdout\.write", l):
                stdout = True
            continue
        nu = re.sub(r"\"[^\"]*\"|'[^']*'", '""', l)   # le texte entre guillemets ne compte pas
        if not AFFICHE.search(nu):
            continue
        if re.search(r"(?<!\|)\|(?!\|)", nu):           # echo ... | grep : un test, pas une sortie
            continue
        if ">&2" in nu:
            stderr = True
        elif ">" in nu:                                 # vers un fichier ou /dev/null
            continue
        else:
            stdout = True
    texte = "\n".join(code)
    bloque = re.search(r"(^|[^\w$])exit\s+2\b", texte) or \
        (en_py and re.search(r"sys\.exit\(\s*2\s*\)|\breturn\s+2\b", texte))
    erreur = re.search(r"(^|[^\w$])exit\s+[13-9]", texte) or \
        (en_py and re.search(r"sys\.exit\(\s*[13-9]", texte))
    entendu = bloque or erreur or JSON.search(texte) or (evt in CONTEXTE and stdout)
    return (stdout or stderr) and not entendu

n = 0
for (nom, evt), en_python in sorted(branches.items(), key=lambda x: (x[0][1], x[0][0])):
    if muet(nom, evt, en_python):
        print(f"  {J}⚠{N} hooks/{nom} ({evt}) : ses messages sortent avec le code 0 — "
              f"seul le journal de débogage les reçoit, ni Claude ni l'utilisateur ne les voient")
        n += 1
if n == 0:
    print(f"  {V}✓{N} {len(branches)} branchement(s), aucun hook ne parle dans le vide")
sys.exit(min(n, 250))
PYMUET
ALERTES=$((ALERTES + $?))

# --------------------------------------------------------------- 3. Skills ---
# Claude Code ne charge un skill que sous la forme skills/<nom>/SKILL.md.
# Un .md posé à la racine, ou un dossier dont le SKILL.md est enfoui plus bas,
# reste inerte sur le disque sans jamais rien signaler.
echo
echo "[3/7] Skills : chargeables"
AV=$ALERTES
NB=0
if [ -d "$CLAUDE/skills" ]; then
    for d in "$CLAUDE"/skills/*; do
        [ -e "$d" ] || continue
        b=$(basename "$d")
        [ "$b" = "README.md" ] && continue
        # skills/synced/ est rempli par Claude Code lui-même (skills claude.ai,
        # avec un manifest.json), hors de la convention skills/<nom>/SKILL.md :
        # le signaler comme « jamais chargé » serait faux.
        [ "$b" = "synced" ] && continue
        if [ -d "$d" ]; then
            if [ -f "$d/SKILL.md" ]; then
                NB=$((NB + 1))
            else
                PROFOND=$(find "$d" -name "SKILL.md" 2>/dev/null | head -1)
                if [ -n "$PROFOND" ]; then
                    alerte "skills/$b/ : SKILL.md présent mais trop profond (${PROFOND#$CLAUDE/}) — jamais chargé"
                else
                    alerte "skills/$b/ : aucun SKILL.md — jamais chargé"
                fi
            fi
        else
            alerte "skills/$b : fichier à la racine de skills/ — un skill doit être un dossier contenant SKILL.md"
        fi
    done
fi
[ "$ALERTES" = "$AV" ] && ok "$NB skill(s), tous chargeables"

# ------------------------------------------------------------- 4. Mémoires ---
# Deux façons pour une mémoire de devenir fausse sans que personne le voie :
# une échéance écrite au passé, ou un fichier que plus rien n'a touché.
# En Python : bash ne sait pas compter les alertes produites dans un pipe.
echo
echo "[4/7] Mémoires : échéances et fraîcheur"
AV=$ALERTES
python3 - "$CLAUDE" <<'PYMEM'
import os, re, sys, glob, datetime
claude = sys.argv[1]
C = sys.stdout.isatty()
R, J, V, N = ("\033[0;31m", "\033[0;33m", "\033[0;32m", "\033[0m") if C else ("", "", "", "")

# Un dossier de mémoires PAR PROJET, pas un seul.
dossiers = sorted(glob.glob(os.path.join(claude, "projects", "*", "memory")))
if not dossiers:
    print(f"  {V}✓{N} aucun dossier de mémoires — rien à vérifier")
    sys.exit(0)

INTENT = re.compile(r"pr[ée]vu|[àa] tester|reste [àa]|[àa] faire|[ée]ch[ée]ance", re.I)
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
auj = datetime.date.today()
limite = auj - datetime.timedelta(days=60)
n = total = 0

for mem in dossiers:
    projet = os.path.basename(os.path.dirname(mem))
    try:
        noms = sorted(os.listdir(mem))
    except OSError:
        continue
    for nom in noms:
        if not nom.endswith(".md") or nom == "MEMORY.md":
            continue
        chemin = os.path.join(mem, nom)
        total += 1
        try:
            lignes = open(chemin, encoding="utf-8", errors="replace").readlines()
        except OSError:
            continue
        for i, ligne in enumerate(lignes, 1):
            # Une date dans un nom de fichier n'est pas une échéance :
            # « prévue en xhigh (analyse-2026-09-08.md:857) » était signalée.
            ligne = re.sub(r"\S+\.(?:md|py|txt|json|sh|csv|log)\b\S*", " ", ligne)
            if not INTENT.search(ligne):
                continue
            for d in DATE.findall(ligne):
                try:
                    depassee = datetime.date.fromisoformat(d) < auj
                except ValueError:
                    continue
                if depassee:
                    print(f"  {R}✗{N} {projet}/memory/{nom}:{i} → échéance {d} dépassée")
                    n += 1
        mod = datetime.date.fromtimestamp(os.path.getmtime(chemin))
        if mod < limite:
            print(f"  {J}⚠{N} {projet}/memory/{nom} : non modifiée depuis le {mod} — encore vraie ?")
            n += 1

if n == 0:
    print(f"  {V}✓{N} {total} mémoire(s) dans {len(dossiers)} projet(s), aucune périmée ni oubliée")
else:
    print(f"  ({total} mémoire(s) examinée(s) dans {len(dossiers)} projet(s))")
sys.exit(min(n, 250))
PYMEM
ALERTES=$((ALERTES + $?))

# ------------------------------------------------------------------ 5. Git ---
# Un avertissement, pas une erreur : un setup non versionné est le cas normal
# au départ. Le signaler une fois par mois suffit à ce que la question se pose.
echo
echo "[5/7] Historique : le setup est-il annulable ?"
AV=$ALERTES
if git -C "$CLAUDE" rev-parse --git-dir >/dev/null 2>&1; then
    SALE=$(git -C "$CLAUDE" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "$SALE" != 0 ] && avert "$SALE fichier(s) non commité(s) dans le setup"
    DERNIER=$(git -C "$CLAUDE" log -1 --format=%ct 2>/dev/null)
    LIMITE=$(date -v-30d +%s 2>/dev/null || date -d "30 days ago" +%s)
    if [ -n "$DERNIER" ] && [ "$DERNIER" -lt "$LIMITE" ]; then
        avert "aucun commit depuis plus de 30 jours"
    fi
    [ "$ALERTES" = "$AV" ] && ok "dépôt propre, commit récent"
else
    avert "$CLAUDE n'est pas un dépôt git — aucune modification des règles ou des mémoires n'est annulable"
    echo "     Un « git init » local suffit. Avant d'ajouter un remote : relire ce"
    echo "     que contiennent les hooks, un chemin de serveur ou une adresse y"
    echo "     traîne vite."
fi

# ---------------------------------------------------------- 6. Duplication ---
# Une même consigne présente dans une règle ET dans un hook arrive deux fois
# dans la même fenêtre de contexte, souvent formulée différemment.
# En Python : iconv s'arrête au premier caractère non convertible sur macOS
# (les hooks contiennent des flèches et des symboles), ce qui donnait un faux
# négatif silencieux.
echo
echo "[6/7] Duplication règle ↔ hook"
AV=$ALERTES
python3 - "$CLAUDE" <<'PYDUP'
import os, sys, glob, unicodedata
claude = sys.argv[1]
C = sys.stdout.isatty()
J, V, N = ("\033[0;33m", "\033[0;32m", "\033[0m") if C else ("", "", "")

def norm(t):
    t = unicodedata.normalize("NFD", t)
    t = "".join(c for c in t if not unicodedata.combining(c))
    t = "".join(c if (c.isalnum() or c.isspace()) else " " for c in t.lower())
    return " ".join(t.split())

htxt = []
for f in glob.glob(os.path.join(claude, "hooks", "*.sh")):
    try:
        htxt.append(norm(open(f, encoding="utf-8", errors="replace").read()))
    except OSError:
        pass
htxt = " ".join(htxt)

n = 0
for f in sorted(glob.glob(os.path.join(claude, "rules", "*.md"))):
    b = os.path.basename(f)
    try:
        lignes = open(f, encoding="utf-8", errors="replace").readlines()
    except OSError:
        continue
    for ligne in lignes:
        l = norm(ligne)
        if len(l) >= 50 and l in htxt:
            print(f"  {J}⚠{N} rules/{b} : phrase présente aussi dans un hook → \"{l[:60]}...\"")
            n += 1
if n == 0:
    print(f"  {V}✓{N} aucune consigne présente à la fois dans une règle et dans un hook")
else:
    print("     Une règle énonce ce qui vaut en permanence, un hook l'injecte au")
    print("     moment utile. Ne dédoubler que si le hook se déclenche à coup sûr")
    print("     quand la règle servirait.")
sys.exit(min(n, 250))
PYDUP
ALERTES=$((ALERTES + $?))

# --------------------------------------------------------------- 7. Poids ---
echo
echo "[7/7] Poids du setup"
RELEVE="$CLAUDE/.maintenance-dernier-releve"
KO=$(du -sk "$CLAUDE" 2>/dev/null | awk '{print $1}')
LISIBLE=$(du -sh "$CLAUDE" 2>/dev/null | awk '{print $1}')
if [ -f "$RELEVE" ]; then
    PREC=$(head -1 "$RELEVE" | awk '{print $2}')
    QUAND=$(head -1 "$RELEVE" | awk '{print $1}')
    if [ -n "${PREC:-}" ] && [ "$PREC" -gt 0 ] 2>/dev/null; then
        DELTA=$(( (KO - PREC) * 100 / PREC ))
        if [ "$DELTA" -gt 30 ]; then
            avert "le setup a grossi de ${DELTA}% depuis le $QUAND ($LISIBLE) — regarder ce qui a gonflé"
        else
            ok "$LISIBLE (${DELTA}% depuis le $QUAND)"
        fi
    else
        ok "$LISIBLE"
    fi
else
    ok "$LISIBLE — premier relevé, sert de référence au prochain contrôle"
fi
[ -n "${KO:-}" ] && echo "$(date +%Y-%m-%d) $KO" > "$RELEVE" 2>/dev/null

# --------------------------------------------------------------- BILAN -------
echo
echo "=== BILAN ==="
if [ "$ALERTES" = 0 ]; then
    printf '  %sRien à signaler.%s Le setup est cohérent.\n' "$V" "$N"
    exit 0
fi
printf '  %s%s point(s) à regarder.%s Rien n'"'"'a été corrigé automatiquement.\n' "$J" "$ALERTES" "$N"
exit 1
