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
# Les hooks du plugin lui-même sont branchés dans son hooks.json, à côté de ce
# script, et non dans settings.json : sans cette lecture, le contrôle ne les
# voyait jamais (l'avertissement de pre-edit-guard est resté muet sans être
# vu). BASH_SOURCE et non $0 : lancé par « bash -s », $0 vaut « bash » et c'est
# le hooks.json du dossier courant — peut-être un dépôt piégé — qui était lu.
python3 -I - "$CLAUDE" "${BASH_SOURCE[0]:-}" <<'PYMUET'
import json, os, re, sys
claude, source = sys.argv[1], sys.argv[2]
plugin_hooks = ""
if source and os.path.isfile(source):
    plugin_hooks = os.path.join(os.path.dirname(os.path.realpath(source)), "hooks.json")
C = sys.stdout.isatty()
R, J, V, N = ("\033[0;31m", "\033[0;33m", "\033[0;32m", "\033[0m") if C else ("", "", "", "")

CONTEXTE = {"UserPromptSubmit", "UserPromptExpansion", "SessionStart", "PostModelSwitch"}
JSON = re.compile(r"systemMessage|additionalContext|permissionDecision|hookSpecificOutput|[\"']decision[\"']")
AFFICHE = re.compile(r"(^|;|&&|\|\||\{|\bthen|\bdo|\belse)\s*(echo|printf|cat)\b")
# Un texte écrit en toutes lettres sur stdout (echo "…", printf '%s' "…",
# print("…"), cat <<EOF) est du texte simple, sauf s'il commence par une
# accolade. Sans ce repérage, un JSON écrit n'importe où dans le fichier
# rendait tout le hook « entendu ». Toutes les analyses ci-dessous sont
# linéaires : un fichier de hook piégé ne doit pas bloquer /maintenance.
VARIABLE = re.compile(r"\$\{\w+\}|\$\w+|%[-\d.]*[sdif]|\\[ntre]|\\033\[[\d;]*m")
LITTERAL_PY = re.compile(r"""(?:\bprint|sys\.stdout\.write)\(\s*[fFrRbB]{0,2}(\"\"\"|'''|"|')(.*?)\1""", re.S)
CHAINES = re.compile(r"\"(?:[^\"\\]|\\.)*\"|'[^']*'")
HEREDOC = re.compile(r"(?<!<)<<-?\s*(['\"]?)([A-Za-z_]\w*)\1")
FONCTION = re.compile(r"^\s*(?:function\s+)?([\w-]+)\s*\(\)\s*\{")
# Une sortie standard renvoyée ailleurs : > f, >> f, 1> f, &> f, >/dev/null.
# Pas 2>/dev/null ni >&2, qui laissent stdout où elle est.
VERS_FICHIER = re.compile(r"(?:^|[^\d&<>])>>?(?!&)|\b1>>?(?!&)|&>")
# « if f », « while ! f » : les mots-clés sont sautés pour trouver le nom appelé.
APPEL = re.compile(r"(\$\(|`|^|[;&|{(]|\bthen\b|\bdo\b|\belse\b)\s*(?:(?:if|elif|while|until|!)\s+){0,3}([\w-]+)")

def texte_simple(litteral):
    if not litteral or "$(" in litteral or "`" in litteral:
        return False                                    # valeur calculée : peut être du JSON
    reste = VARIABLE.sub("", litteral).strip()
    return bool(reste) and not reste.startswith("{") and bool(re.search(r"[^\W\d_]", reste))

def litteral_sh(l):
    """Le texte écrit par le premier echo/printf de la ligne, ou None."""
    m = re.search(r"\b(echo|printf)\b", l)
    if not m:
        return None
    reste = l[m.end():m.end() + 4096]
    reste = re.sub(r"^(?:\s+-[a-zA-Z]{1,3}){0,3}\s+", "", reste, count=1)
    q = re.match(r"""(["'])(.*?)\1""", reste)
    if q and m.group(1) == "printf" and re.fullmatch(r"%s(?:\\n)?", q.group(2)):
        suite = re.match(r"""\s+(["'])(.*?)\1""", reste[q.end():])
        return suite.group(2) if suite else None
    if q:
        return q.group(2)
    if m.group(1) == "echo":
        nu = re.match(r"""([^\s"'$;|&>{(][^;|&>]*)""", reste)
        return nu.group(1) if nu else None
    return None

def propre(t):
    """Un nom lu dans un fichier de réglages ne pilote pas le terminal."""
    return re.sub(r"[\x00-\x1f\x7f-\x9f‎‏‪-‮⁦-⁩]", "?", str(t))

def lignes_py(code):
    """Lignes logiques : un print( sur plusieurs lignes, ou une chaîne entre
    triples guillemets, forment une seule instruction. Lecture caractère par
    caractère : commentaires, chaînes et guillemets échappés sont reconnus."""
    sortie, cur, prof, etat = [], [], 0, None
    for l in code:
        cur.append(l)
        i, n = 0, len(l)
        while i < n:
            c = l[i]
            if etat is None:
                if c == "#":
                    break
                if l.startswith('"""', i) or l.startswith("'''", i):
                    etat = l[i:i + 3]
                    i += 3
                    continue
                if c in "\"'":
                    etat = c
                elif c in "([{":
                    prof += 1
                elif c in ")]}":
                    prof -= 1
            elif c == "\\":
                i += 2
                continue
            elif len(etat) == 1 and c == etat:
                etat = None
            elif len(etat) == 3 and l.startswith(etat, i):
                etat = None
                i += 3
                continue
            i += 1
        if etat in ('"', "'"):
            etat = None                                 # chaîne simple jamais fermée : on referme
        if etat is None and prof <= 0:
            sortie.append("\n".join(cur))
            cur, prof = [], 0
    if cur:
        sortie.append("\n".join(cur))
    return sortie

def masque(l):
    """La ligne, avec le contenu des chaînes remplacé par « _ » (même longueur)."""
    return CHAINES.sub(lambda m: m.group(0)[0] + "_" * (len(m.group(0)) - 2) + m.group(0)[-1], l)

def sorties_sh(code):
    """(stdout, stderr, texte simple) d'un script shell, en tenant compte des
    lignes coupées par « \\ », des groupes { … } >&2, des fonctions (appelées,
    capturées par $(…), ou renvoyées vers stderr), de exec 1>&2 et des
    documents <<EOF."""
    lignes, cur = [], ""
    for l in code:                                      # recolle les « \ » de fin de ligne
        if l.rstrip().endswith("\\"):
            cur += l.rstrip()[:-1] + " "
        else:
            lignes.append(cur + l)
            cur = ""
    if cur:
        lignes.append(cur)
    masques = [masque(l) for l in lignes]

    # Premier passage : documents <<EOF, groupes, fonctions.
    corps_heredoc, premiere_ligne = set(), {}
    vers_stderr, vers_fichier, corps_fonction, fonction_de = set(), set(), {}, {}
    pile, fin_heredoc, attente = [], None, None
    for i, l in enumerate(lignes):
        if fin_heredoc is not None:
            corps_heredoc.add(i)
            if l.strip() == fin_heredoc:
                fin_heredoc = None
            elif attente is not None and l.strip():
                premiere_ligne[attente] = l             # la première ligne non vide du corps
                attente = None
            continue
        nu = masques[i]
        for m in HEREDOC.finditer(nu):
            avant = nu[:m.start()]
            if avant.count("((") > avant.count("))"):
                continue                                # $((1<<n)) : un décalage, pas un document
            brut = HEREDOC.match(l, m.start())
            fin_heredoc = brut.group(2) if brut else m.group(2)
            attente = i
            break
        f = FONCTION.match(nu)
        if f:
            if nu[f.end():].rstrip().rstrip(";").rstrip().endswith("}"):
                corps_fonction.setdefault(f.group(1), set()).add(i)
                fonction_de[i] = f.group(1)
            else:
                pile.append(("f", f.group(1), i))
        elif nu.strip() == "{":
            pile.append(("g", None, i))
        elif nu.lstrip().startswith("}") and pile:
            genre, nom, debut = pile.pop()
            if genre == "f":
                corps_fonction.setdefault(nom, set()).update(range(debut, i + 1))
                for k in range(debut, i + 1):
                    fonction_de.setdefault(k, nom)
            elif ">&2" in nu:
                vers_stderr.update(range(debut, i + 1))
            elif VERS_FICHIER.search(nu[nu.index("}") + 1:]):
                vers_fichier.update(range(debut, i + 1))

    # Appels des fonctions : chaque appel dit où va leur sortie. Le corps ne
    # compte comme message que si au moins un appel l'envoie sur stdout.
    appels = {nom: set() for nom in corps_fonction}
    for i, nu in enumerate(masques):
        if i in corps_heredoc or not appels:
            continue
        # Une seule lecture de la ligne pour sa redirection : relire la suite
        # de la ligne à chaque appel coûtait un temps quadratique.
        sortie = "stderr" if ">&2" in nu else ("fichier" if VERS_FICHIER.search(nu) else "stdout")
        for m in APPEL.finditer(nu):
            nom = m.group(2)
            if nom not in appels or fonction_de.get(i) == nom:
                continue
            appels[nom].add("capture" if m.group(1) in ("$(", "`") else sortie)
    ignorees, vers_stderr_fn = set(), set()
    for nom, rang in corps_fonction.items():
        if "stdout" in appels[nom]:
            continue                                    # appelée au moins une fois vers stdout
        if "stderr" in appels[nom]:
            vers_stderr_fn.update(rang)
        else:
            ignorees.update(rang)                       # capturée ou jamais appelée : pas un message

    stdout = stderr = simple = False
    tout_vers_stderr = False
    for i, l in enumerate(lignes):
        if i in corps_heredoc or i in ignorees or i in vers_fichier:
            continue
        nu = masques[i]
        if re.match(r"^\s*exec\s+1?>&2\s*$", nu):
            tout_vers_stderr = True                     # exec 1>&2 : la suite part sur stderr
            continue
        # Un echo placé dans $(…) ou entre accents graves est capturé : il
        # n'écrit rien (« INPUT=$(cat || echo '{}') »).
        libres = [m for m in AFFICHE.finditer(nu)
                  if nu[:m.start()].count("$(") <= nu[:m.start()].count(")")
                  and nu[:m.start()].count("`") % 2 == 0]
        if not libres:
            continue
        if re.search(r"(?<!\|)\|(?!\|)", nu):           # echo ... | grep : un test, pas une sortie
            continue
        if ">&2" in nu or i in vers_stderr or i in vers_stderr_fn or tout_vers_stderr:
            stderr = True
        elif VERS_FICHIER.search(HEREDOC.sub("", nu)):  # vers un fichier ou /dev/null
            continue
        else:
            stdout = True
            if i in premiere_ligne or (HEREDOC.search(nu) and i not in premiere_ligne):
                simple = simple or texte_simple(premiere_ligne.get(i, ""))
            else:
                simple = simple or texte_simple(litteral_sh(l))
    return stdout, stderr, simple

# Chemin d'un hook personnel : ~, $HOME, "$HOME" entre guillemets, ${HOME}, ou
# le chemin complet. Seule la première forme était reconnue : un hook branché
# autrement échappait au contrôle. Recherche par find, en un seul passage :
# une regex du chemin complet prenait un temps quadratique sur une longue
# commande.
MARQUE = "/.claude/hooks/"
SEPARATEURS = set(" \t\n\"'|;&=(`")
NOM = re.compile(r"[\w.-]+")
PLUGIN = re.compile(r"\$\{?CLAUDE_PLUGIN_ROOT\}?/hooks/(?P<nom>[\w.-]+)")

def reperes(commande):
    """Pour chaque position : début du mot, et début du morceau de commande
    (après le dernier |, ; ou &) — c'est là qu'on lit l'interprète."""
    mot, morceau, m1, m2 = [], [], 0, 0
    for k, c in enumerate(commande):
        mot.append(m1)
        morceau.append(m2)
        if c in SEPARATEURS:
            m1 = k + 1
        if c in "|;&":
            m2 = k + 1
    return mot, morceau

def perso(commande):
    if MARQUE not in commande:
        return
    mot, morceau = reperes(commande)
    i = commande.find(MARQUE)
    while i != -1:
        fin = i + len(MARQUE)
        m = NOM.match(commande, fin)
        debut = mot[i]
        prefixe = commande[debut:i] if i - debut <= 4096 else None
        if prefixe == "" and debut >= 2 and commande[debut - 1] in "\"'":
            # « "$HOME"/.claude/hooks/x » : le mot est entre guillemets, fermés
            # juste avant la barre.
            ouvre = commande.rfind(commande[debut - 1], max(0, debut - 4097), debut - 1)
            if ouvre != -1:
                prefixe, debut = commande[ouvre + 1:debut - 1], ouvre
        # Au-delà de 4 096 caractères, ce n'est pas un chemin de fichier : le
        # recopier à chaque occurrence coûtait un temps quadratique.
        if m and prefixe is not None and m.group() not in (".", ".."):
            nom = m.group()
            if prefixe in ("~", "$HOME", "${HOME}"):
                yield morceau[debut], debut, os.path.join(claude, "hooks", nom), "hooks/" + nom
            elif prefixe.startswith("/"):
                # Chemin complet : c'est ce fichier-là qui tourne, lui qu'on lit.
                yield morceau[debut], debut, prefixe + MARQUE + nom, prefixe + MARQUE + nom
        i = commande.find(MARQUE, fin)

def du_plugin(commande, dossier):
    trouves = list(PLUGIN.finditer(commande))
    if not trouves:
        return
    mot, morceau = reperes(commande)
    for m in trouves:
        debut = mot[m.start()]
        yield (morceau[debut], debut, os.path.join(dossier, m.group("nom")),
               "plugin:hooks/" + m.group("nom"))

# (chemin du script, étiquette, événement) -> lancé par python3 ?
branches = {}
def lire(hooks, trouver, *args):
    """Rend False si la liste des hooks n'a pas la forme attendue."""
    if hooks is None:
        return True
    if not isinstance(hooks, dict):
        return False
    ok = True
    for evt, groupes in hooks.items():
        for g in (groupes if isinstance(groupes, list) else [None]):
            liste = g.get("hooks") if isinstance(g, dict) else None
            if not isinstance(liste, list):
                ok = False
                continue
            for h in liste:
                if isinstance(h, dict) and "command" not in h:
                    continue                    # hook http, prompt… : pas de script
                commande = h.get("command") if isinstance(h, dict) else None
                if not isinstance(commande, str):
                    ok = False
                    continue
                for coupe, debut, chemin, etiquette in trouver(commande, *args):
                    # « cat | python3 -I ~/... » est lancé par python3.
                    avant = commande[max(coupe, debut - 4096):debut]
                    branches.setdefault((chemin, etiquette, evt), "python" in avant)
    return ok

n_forme = 0
perso_lu = False          # pas de ✓ sur des hooks qu'on n'a pas pu lire
chemin_reglages = os.path.join(claude, "settings.json")
if not os.path.isfile(chemin_reglages):
    print(f"  {V}✓{N} aucun settings.json : aucun hook personnel branché")
else:
    try:
        reglages = json.load(open(chemin_reglages, encoding="utf-8"))
    except (OSError, ValueError, RecursionError):
        reglages = None
        print(f"  {R}✗{N} settings.json illisible : impossible de savoir quels hooks sont branchés")
        n_forme += 1
    perso_lu = reglages is not None
    if reglages is not None and not (isinstance(reglages, dict) and lire(reglages.get("hooks"), perso)):
        print(f"  {R}✗{N} settings.json : la liste des hooks n'a pas la forme attendue, "
              "une partie n'est pas contrôlée")
        n_forme += 1
n_perso = len(branches)

if plugin_hooks and os.path.isfile(plugin_hooks):
    try:
        contenu = json.load(open(plugin_hooks, encoding="utf-8"))
    except (OSError, ValueError, RecursionError):
        contenu = None
    if not (isinstance(contenu, dict) and
            lire(contenu.get("hooks"), du_plugin, os.path.dirname(plugin_hooks))):
        print(f"  {R}✗{N} hooks.json du plugin illisible ou mal formé : ses hooks ne sont "
              "pas tous contrôlés")
        n_forme += 1

def muet(chemin, evt, lance_en_python):
    """Rend la raison pour laquelle personne n'entend ce hook, ou None."""
    if not os.path.isfile(chemin):
        return None
    try:
        lignes = open(chemin, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return None
    en_py = lance_en_python or bool(lignes and "python" in lignes[0])
    code = [l for l in lignes if not l.lstrip().startswith("#")]
    if en_py:
        stdout = stderr = simple = False
        for l in lignes_py(code):
            if "sys.stderr" in l and re.search(r"print\(|\.write\(", l):
                stderr = True
            elif re.search(r"\bprint\(|sys\.stdout\.write", l):
                stdout = True
                m = LITTERAL_PY.search(l)
                simple = simple or bool(m and texte_simple(m.group(2)))
    else:
        stdout, stderr, simple = sorties_sh(code)
    texte = "\n".join(code)
    bloque = re.search(r"(^|[^\w$])exit\s+2\b", texte) or \
        (en_py and re.search(r"sys\.exit\(\s*2\s*\)|\breturn\s+2\b", texte))
    erreur = re.search(r"(^|[^\w$])exit\s+[13-9]", texte) or \
        (en_py and re.search(r"sys\.exit\(\s*[13-9]", texte))
    json_ = JSON.search(texte)
    entendu = bloque or erreur or json_ or (evt in CONTEXTE and stdout)
    if (stdout or stderr) and not entendu:
        return ("ses messages sortent avec le code 0 — seul le journal de débogage "
                "les reçoit, ni Claude ni l'utilisateur ne les voient")
    # Doc hooks : en code 2, la raison du blocage est lue sur stderr (ou dans le
    # JSON) ; en code 1, seule la première ligne de stderr s'affiche. Un message
    # sur stdout n'arrive à personne.
    if (bloque or erreur) and stdout and not stderr and not json_:
        return ("sort en code d'erreur avec ses messages sur stdout — la raison "
                "n'arrive ni à Claude ni à l'utilisateur (il faut stderr)")
    # Bloquer quelque part ne rend pas entendu le reste du hook. Hors des
    # événements de contexte, un texte simple sur stdout n'arrive à personne,
    # quel que soit le code : en 0 il part au journal de débogage, en 2 la
    # raison se lit sur stderr, en 1 seule la première ligne de stderr
    # s'affiche. pre-edit-guard passait ainsi : il bloquait les .env, et son
    # avertissement « fichier sensible » ne sortait jamais. Et écrire un JSON
    # ailleurs dans le fichier n'y change rien : un texte en toutes lettres
    # reste perdu.
    if (simple or (stdout and not json_)) and evt not in CONTEXTE:
        return ("une partie de ses messages sort en texte simple sur stdout — sur "
                "cet événement, ni Claude ni l'utilisateur ne les voient (il faut "
                "stderr avec un code 2, ou du JSON)")
    # Un code 1 ne bloque rien : un hook qui parle de bloquer sans jamais sortir
    # en code 2 laisse passer ce qu'il croit arrêter.
    if erreur and not bloque and not json_ and \
            re.search(r"\bbloqu|\bblock", "\n".join(lignes), re.I):
        return ("parle de bloquer mais ne sort jamais en code 2 — le code 1 "
                "laisse passer l'action")
    return None

n = n_plugin = 0
for (chemin, etiquette, evt), en_python in sorted(branches.items(), key=lambda x: (x[0][2], x[0][1])):
    raison = muet(chemin, evt, en_python)
    if raison:
        print(f"  {J}⚠{N} {propre(etiquette)} ({propre(evt)}) : {raison}")
        n += 1
        n_plugin += etiquette.startswith("plugin:")
if n - n_plugin == 0 and perso_lu:
    print(f"  {V}✓{N} {n_perso} branchement(s), aucun hook ne parle dans le vide")
if len(branches) > n_perso and n_plugin == 0:
    print(f"  {V}✓{N} hooks du plugin : {len(branches) - n_perso} contrôlé(s), aucun ne parle dans le vide")
sys.exit(min(n + n_forme, 250))
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
python3 -I - "$CLAUDE" <<'PYMEM'
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
python3 -I - "$CLAUDE" <<'PYDUP'
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
