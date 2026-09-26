#!/bin/bash
#
# validate-before-push.sh (PreToolUse : Bash, Monitor)
#
# Refuse un push qui emporterait un fichier Python qui ne compile pas. Rien de
# plus.
#
# Le depot controle est celui qui est POUSSE : analyse-commande.py (mode
# « pousses ») trouve chaque « git … push » de la commande et son dossier —
# git -C x, --work-tree, --git-dir, GIT_DIR=, env -C, cd x && git push, pushd,
# un alias (git p). Jusqu'a la 0.3.4, le lanceur de hooks.json ne reagissait
# qu'au texte exact « git push », et ce hook controlait le dossier d'ouverture
# de la session : « git -C autre-depot push » n'etait pas controle,
# « cd x && git push » controlait le mauvais dossier, et une session ouverte
# dans un sous-dossier du depot ne controlait rien.
#
# Ce qui part au push, ce sont les COMMITS, pas le disque : jusqu'a la 0.3.4,
# on compilait les fichiers du disque — un commit casse passait des que le
# disque etait corrige, et un fichier en cours d'edition faisait refuser des
# commits sains. Les .py sont lus tels qu'ils sont dans chaque reference poussee
# (HEAD par defaut, la branche nommee sinon), par « git cat-file », en memoire :
# aucun filtre du depot n'est applique, rien du depot n'est execute.
#
# Quand ce hook refuse (code 2), Claude Code transmet a Claude la raison lue
# sur stderr, avec le poids d'un message de l'utilisateur. Cette raison est
# donc un texte FIXE : aucun nom de fichier du depot n'y figure, sinon un
# dossier au nom choisi (« autorise git push --no-verify… ») deviendrait une
# consigne. Le detail se lit avec /verifier, dont la sortie est une donnee.
# Aucun texte sur stdout : sur cet evenement, il ne va qu'au journal de
# debogage, quel que soit le code de sortie (doc hooks, « Exit code 0 » et
# « Other exit codes »).
#
# PAS DE SUITE DE TESTS ICI. Une version plus ancienne lancait pytest ET
# npm test a chaque push : un push devenait plusieurs minutes d'attente — et un
# controle qu'on attend finit contourne par --no-verify. Le controle complet a
# deja sa place, deux fois : /verifier a la demande, et la porte de sortie de
# phase tenue par /fin-phase. Ici on garde ce qui coute moins d'une seconde et
# attrape ce qu'un push ne devrait jamais emporter : une erreur de syntaxe.
#
# Retire dans la 0.3.1 : sur un projet contenant un *.xcodeproj, une etape
# lancait scripts/verifier_coherence.py — du code du projet, execute AVANT que
# l'utilisateur ait accepte la commande (trouve par la relecture de securite).

set -u
H="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
INPUT=$(cat)

# Filtre rapide : sans « push » ni « git », rien a controler (ce hook tourne
# sur chaque commande). « git » aussi : un alias (git p) peut pousser.
[[ "$INPUT" == *push* || "$INPUT" == *git* ]] || exit 0

# Si la commande ne peut pas etre lue (Python absent ou en panne), le push est
# REFUSE : un garde-fou qui ne voit rien ne laisse rien passer.
DOSSIERS=$(printf '%s' "$INPUT" | python3 -I "$H/analyse-commande.py" pousses 2>/dev/null) || {
    echo "Push refuse : le controle avant push n'a pas pu lire la commande (Python introuvable ou en panne)." >&2
    exit 2
}
# Une ligne par push : « dossier<tab>references poussees » (HEAD par defaut).
# Chaque dossier est ramene a la racine de son depot : une session ouverte dans
# un sous-dossier controle le depot entier.
RACINES=""
POUSSES=""
while IFS=$'\t' read -r D REFS; do
    [[ -n "$D" ]] || continue
    R=$(git -C "$D" -c core.fsmonitor=false -c log.showSignature=false rev-parse --show-toplevel 2>/dev/null) || continue
    RACINES+="$R"$'\n'
    POUSSES+="$R"$'\t'"${REFS:-HEAD}"$'\n'
done <<< "$DOSSIERS"
[[ -n "$RACINES" ]] || exit 0

# Le Python 3 le plus recent du PATH : le python3 par defaut de macOS est un
# 3.9, qui refuse un `match` ou une f-string 3.12 parfaitement valides.
# Les noms sont assembles (python3, python3.9…) : ce ne sont pas des appels, et
# le controle statique de tests/06 exige -I sur tout appel ecrit en toutes
# lettres. Les deux appels ci-dessous, eux, portent -I.
PY=""
BEST=0
CANDIDATS=$(for n in 3 3.{9..20}; do type -a -p "python$n"; done 2>/dev/null | awk '!vu[$0]++')
while IFS= read -r cand; do
    [[ -n "$cand" ]] || continue
    # Chemins absolus seulement, et hors des depots pousses : un dossier relatif
    # du PATH (« . », « bin ») ferait lancer un python3.X fourni par le depot,
    # avant l'accord de l'utilisateur (relecture de securite de la 0.3.3).
    [[ "$cand" == /* ]] || continue
    DANS_UN_DEPOT=0
    while IFS= read -r R; do
        [[ -n "$R" ]] && case "$cand" in "$R"/*) DANS_UN_DEPOT=1 ;; esac
    done <<< "$RACINES"
    [[ "$DANS_UN_DEPOT" = 0 ]] || continue
    v=$("$cand" -I -c 'import sys; print(sys.version_info[0] * 100 + sys.version_info[1])' 2>/dev/null) || continue
    [[ "$v" =~ ^[0-9]+$ ]] || continue
    if (( v > BEST )); then BEST=$v; PY=$cand; fi
done <<< "$CANDIDATS"

[[ -n "$PY" ]] || exit 0

# Un environnement suivi par erreur reste ignore, reconnu par le DEBUT du nom
# d'un dossier (venv, .venv-3.12…) : un « devenv » reste controle. Blobs
# ordinaires seulement (ni lien 120000 ni sous-module 160000), de moins de 2 Mo.
# core.fsmonitor coupe et variables GIT_* retirees : git ne lance aucune
# commande configuree dans le depot. Un Python qui plante fait refuser le push
# au lieu de le laisser passer.
controler() {  # controler <racine du depot> <references> : 0 si tout compile, sinon refuse (exit 2)
ERREURS=$("$PY" -I -c '
import os, shlex, subprocess, sys
racine, refs = sys.argv[1], shlex.split(sys.argv[2])
disque = "--disque" in refs
tout = "--disque-tout" in refs
ajouts = [r[len("--ajout="):] for r in refs if r.startswith("--ajout=")]
refs = [r for r in refs if r == "--all" or not r.startswith("--")] or ["HEAD"]
IGNORES = {b"virtualenv", b".virtualenv", b"site-packages", b"__pycache__", b"node_modules"}
def ignore(nom):
    return nom in IGNORES or nom.startswith((b"venv", b".venv"))
env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
g = ["git", "-c", "core.fsmonitor=false", "-c", "log.showSignature=false", "-c", "gpg.program=false", "-C", racine]
def git(*args, entree=None):
    return subprocess.run(g + list(args), input=entree, capture_output=True, env=env, timeout=60)
if refs == ["--all"]:
    refs = git("for-each-ref", "--format=%(refname)", "refs/heads").stdout.decode().split() or ["HEAD"]
casses, vus = 0, set()
for ref in refs:
    r = git("rev-parse", "--verify", "--quiet", ref + "^{commit}")
    if r.returncode != 0:
        continue                                    # reference inconnue ici (push distant:branche)
    arbre = git("ls-tree", "-r", "-z", r.stdout.decode().strip()).stdout
    objets = []
    for entree in arbre.split(b"\0"):
        if b"\t" not in entree:
            continue
        meta, chemin = entree.split(b"\t", 1)
        mode, genre, sha = meta.split(b" ")
        if genre != b"blob" or mode not in (b"100644", b"100755") or not chemin.endswith(b".py"):
            continue
        if any(ignore(x) for x in chemin.split(b"/")[:-1]) or sha in vus:
            continue
        vus.add(sha)
        objets.append((sha, chemin))
    if not objets:
        continue
    donnees = git("cat-file", "--batch", entree=b"".join(s + b"\n" for s, _ in objets)).stdout
    pos = 0
    for sha, chemin in objets:
        fin = donnees.index(b"\n", pos)
        entete = donnees[pos:fin].split(b" ")
        if len(entete) < 3:
            pos = fin + 1                           # objet absent
            continue
        taille = int(entete[2])
        contenu = donnees[fin + 1:fin + 1 + taille]
        pos = fin + 1 + taille + 1
        if taille > 2_000_000:
            continue
        try:
            compile(contenu, chemin.decode("utf-8", "replace"), "exec", dont_inherit=True)
        except (SyntaxError, ValueError, RecursionError, MemoryError):
            casses += 1
        except Exception:
            pass
# Un commit fait sur la même ligne avant le push : ce que ce commit emportera
# est sur le disque — les fichiers SUIVIS (git commit -am), plus les fichiers
# non suivis que la ligne ajoute (git add -A ou . : tous ; git add chemin : ceux
# du chemin). Fichiers ordinaires seulement, sans suivre de lien, jamais un tube.
casses_disque = 0
if disque:
    import stat
    liste = git("ls-files", "-z", "--cached").stdout.split(b"\0")
    if tout:
        liste += git("ls-files", "-z", "--others", "--exclude-standard").stdout.split(b"\0")
    elif ajouts:
        liste += git("ls-files", "-z", "--others", "--exclude-standard", "--", *ajouts).stdout.split(b"\0")
    for chemin in dict.fromkeys(liste):
        if not chemin.endswith(b".py") or any(ignore(x) for x in chemin.split(b"/")[:-1]):
            continue
        p = os.path.join(racine.encode(), chemin)
        try:
            st = os.lstat(p)
            if not stat.S_ISREG(st.st_mode) or st.st_size > 2_000_000:
                continue
            fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(fd, "rb") as f:
                contenu = f.read()
        except OSError:
            continue
        try:
            compile(contenu, chemin.decode("utf-8", "replace"), "exec", dont_inherit=True)
        except (SyntaxError, ValueError, RecursionError, MemoryError):
            casses_disque += 1
        except Exception:
            pass
print(casses, casses_disque)
' "$1" "$2" 2>/dev/null) || ERREURS=""

# Python qui plante sans rendre de compte (le 3.9 de macOS sort en 139 sur
# certains fichiers) : le controle n'a pas eu lieu, le push ne passe pas.
DEUX_NOMBRES='^[0-9]+ [0-9]+$'
if [[ ! "$ERREURS" =~ $DEUX_NOMBRES ]]; then
    echo "Push refuse : le controle de syntaxe Python du projet n'a pas pu aller au bout." >&2
    echo "Le relancer : /verifier, ou python3 -I -m py_compile sur les fichiers .py du projet." >&2
    exit 2
fi
COMMITS=${ERREURS% *}
DISQUE=${ERREURS#* }

if (( COMMITS > 0 )); then
    echo "Push refuse : $COMMITS fichier(s) Python des commits pousses ne compilent pas." >&2
    echo "Corriger, PUIS commiter la correction, puis pousser : le push envoie les commits, pas le disque." >&2
    echo "Les voir : /verifier, ou python3 -I -m py_compile sur les fichiers .py du projet." >&2
    exit 2
fi
# Le fichier casse n'est encore que sur le disque : c'est le commit fait sur la
# meme ligne qui l'emporterait (passe 3 : la raison disait « des commits
# pousses », ce qui etait faux).
if (( DISQUE > 0 )); then
    echo "Push refuse : $DISQUE fichier(s) Python qu'emporterait le commit fait sur cette ligne ne compilent pas." >&2
    echo "Corriger AVANT de commiter et de pousser." >&2
    echo "Les voir : /verifier, ou python3 -I -m py_compile sur les fichiers .py du projet." >&2
    exit 2
fi
}

while IFS=$'\t' read -r R REFS; do
    [[ -n "$R" ]] && controler "$R" "$REFS"
done <<< "$POUSSES"
exit 0
