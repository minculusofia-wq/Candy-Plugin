"""sans-verif.py — sans-verif.sh refuse un git qui sauterait les hooks du dépôt
(--no-verify, -n de commit et am, core.hooksPath sur la ligne, HUSKY, SKIP,
GIT_CONFIG_*, git config qui change core.hooksPath), à travers sudo, env,
bash -c, $( ), eval, <<EOF et les alias git — et laisse passer le travail
ordinaire, dont un message de commit qui cite ces mots.

Né dans la 0.4.4. Les options sont celles de git 2.54 (« git <cmd> -h ») : -n
vaut --no-verify pour commit et am seulement ; les -m et -c d'am sont des
drapeaux.

Garde aussi une régression trouvée en écrivant ce garde : un second dictionnaire
d'options nommé comme celui de grep l'écrasait, et protect-secrets laissait
passer « grep -rn --include .env KEY . ». Aucun nom global ne doit être défini
deux fois dans analyse-commande.py.

Usage : python3 -I sans-verif.py <dossier des hooks>   → code 0 si tout passe.
"""
import ast
import importlib.util
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile

_spec = importlib.util.spec_from_file_location(
    "commun", os.path.join(os.path.dirname(os.path.abspath(__file__)), "commun.py"))
c = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(c)
attendre, section = c.attendre, c.section
H = sys.argv[1]
HOOK = os.path.join(H, "sans-verif.sh")
NV = "--no-" + "verify"
base = tempfile.mkdtemp(prefix="essai-sans-verif.")
depot = os.path.join(base, "depot")
# Alias permanents du dépôt : résolus par le garde (git config --get alias.x).
ALIAS = {"ci": "commit -n", "envoie": "!git -c core.hooksPath=/x commit", "c2": "commit -n", "ci2": "c2",
         "shci": "!sh -c 'git commit -n'", "cm": "!git add -A && git commit -n -m",
         "shc": "!sh -c 'git commit -m x'", "p": "push", "p2": "p", "sp": "!git push origin HEAD",
         "opt": "-c core.hooksPath=/x commit"}


def lancer(cmd=None, cwd=depot, brut=None, env=None):
    entree = brut if brut is not None else json.dumps({"tool_input": {"command": cmd}, "cwd": cwd}).encode()
    r = subprocess.run(["bash", HOOK], input=entree, capture_output=True, cwd=cwd, timeout=60,
                       env=env or dict(os.environ, CLAUDE_PROJECT_DIR=depot))
    return r.returncode


# Huit bash -c emboîtés : plus profond que PROFONDEUR (6) dans l'analyseur.
PROFOND = "git -c include.path=/tmp/x commit -m y"
for _ in range(8):
    PROFOND = "bash -c " + shlex.quote(PROFOND)

passent = [
    'git commit -m "no-verify dans le message"',
    'git commit -m "fix: x"',
    f'git commit -m "doc: le garde refuse {NV} et -n"',
    f"git commit -m \"$(cat <<'EOF'\nfeat: garde {NV}\n\nHUSKY=0 SKIP=x GIT_CONFIG_PARAMETERS core.hooksPath\nEOF\n)\"",
    f"git commit -F - <<'EOF'\nfeat: {NV} -n HUSKY=0\nEOF",
    "git commit -amn",                              # -a, puis -m de valeur « n »
    "git commit -uno -m x",                         # --untracked-files=no
    "git commit -- -n",                             # -n est un chemin après --
    "git commit -m x && git push",
    "git push -n origin main",                      # --dry-run
    "git push -u origin HEAD",
    "git merge -n autre",                           # --no-stat
    f'git merge -m "{NV} cité" autre',
    f"git merge -m {NV} autre",                     # valeur de -m
    "git pull -n",
    "git rebase -n main",
    "git cherry-pick -n abc",                       # --no-commit
    "git am -m p.patch",                            # -m d'am : --message-id
    "git log -n 3",
    f"grep -n {NV[2:]} f",
    f"echo {NV}",
    "git -c core.hooksPath=/x status",              # status ne lance aucun hook
    "git config --get core.hooksPath",
    "git config --show-origin --get-all core.hooksPath",
    "git config core.hooksPath",
    "git config get core.hooksPath",
    "git config -l",
    "git config user.name x",
    "SKIP=1 pytest",
    "HUSKY=0 npm test",
    "git status",
    'echo "x',                                      # guillemet non fermé, sans git
    # relecture de sécurité du 2026-10-04 : -n hors commit/am après un eval
    'eval "$(ssh-agent -s)" && git log -n 3', 'eval "$X" && git log --oneline -n 5',
    'HUSKY=0 bash -c "git status"', "git config --type=path --get core.hooksPath",
    # relecture xhigh de la 0.4.4 : faux refus
    f'eval "$(ssh-agent -s)" && git commit -m "doc: le garde refuse {NV}"',
    "eval \"$(ssh-agent -s)\" && git commit -m 'feat: option am -n'",
    "eval \"$(ssh-agent -s)\" && git commit -m 'option --skip=x'",
    "SKIP=1 pytest && git commit -m x", "HUSKY=0 npm test; git push",
    "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*' git commit -m x",
    "git shc", "git p2", "git sp",
]
refuses = [
    f"git commit {NV} -m x", f"git commit -m x {NV}", f"git push {NV}", f"git push origin main {NV}",
    f"git merge {NV} autre", f"git pull {NV}", f"git cherry-pick {NV} abc", f"git rebase {NV} main",
    f"git am {NV} p.patch", "git commit --no-verif -m x", "git push --no-v",
    "git commit -n -m x", "git commit -an -m x", "git commit -anm x", "git commit -vn",
    "git am -n p.patch", "git am -mn p.patch", "git am -kn p.patch",
    # core.hooksPath ou include sur la ligne de commande
    "git -c core.hooksPath=/dev/null commit -m x", "git -c CORE.HOOKSPATH=/dev/null commit -m x",
    "git --config-env=core.hooksPath=V commit -m x", "git --config-env core.hooksPath=V commit -m x",
    "git --config-env core.hooksPath=V push", "git -c include.path=/tmp/x commit -m x",
    "git -c includeIf.gitdir:/x/.path=/tmp/x push", "git -c core.hooksPath=/dev/null cherry-pick abc",
    # enveloppes et commandes dans les commandes
    f"sudo git commit {NV} -m x", "sudo -u bob git commit -n -m x", f"env A=1 git commit {NV} -m x",
    f"timeout 30 git push {NV}", f"nohup git push {NV} &", "command git commit -n -m x",
    "\\git commit -n -m x", "/usr/bin/git commit -n -m x", f"git -C {depot} commit -n -m x",
    f'bash -c "git commit {NV} -m x"', f"sh -c 'git push {NV}'", f'bash -lc "cd /tmp && git push {NV}"',
    "x=$(git commit -n -m y)", f'OUT="$(git push {NV} 2>&1)"', f'eval "git commit {NV} -m x"',
    f"bash <<'EOF'\ngit commit {NV} -m x\nEOF", f"git \\\n  commit {NV} -m x",
    "(cd /tmp && git commit -n -m x)", f"echo ok; git push {NV}", f"$'git' commit {NV}",
    f"$'\\x67it' commit {NV}", f"xargs git commit {NV} -m x", "if git commit -n -m x; then echo ok; fi",
    f"find . -name x -exec git commit {NV} -m x \\;", f"env -S 'git commit {NV} -m x'",
    # alias
    f"git -c alias.ci='commit {NV}' ci -m x", "git -c alias.ci='!git commit -n' ci -m x",
    "git ci -m x", "git envoie -m x", "git ci2 -m x", "git shci",
    # variables qui sautent les hooks
    "HUSKY=0 git commit -m x", "HUSKY_SKIP_HOOKS=1 git commit -m x", "SKIP=lint git commit -m x",
    "export HUSKY=0; git commit -m x", "export SKIP=lint && git push", "env SKIP=x git push",
    "sudo env HUSKY=0 git commit -m x", "declare -x HUSKY=0; git commit -m x",
    "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x",
    "GIT_CONFIG_PARAMETERS=\"'core.hooksPath'='/dev/null'\" git commit -m x",
    # git config qui change le dossier des hooks
    "git config core.hooksPath /dev/null", "git config --local core.hooksPath ''",
    "git config --global core.hooksPath /tmp/x", "git config --unset core.hooksPath",
    "git config --unset-all core.hooksPath", "git config --replace-all core.hooksPath x",
    "git config set core.hooksPath x", "git config unset core.hooksPath",
    "git config --remove-section core", "git config rename-section core autre", "git config -e",
    "git config --edit", "git config include.path /tmp/x", f"git -C {depot} config core.hooksPath x",
    "git config --remove-section --file .git/config core",
    # commandes que git lance lui-même
    f'git rebase -x "git commit --amend {NV}" main', 'git rebase --exec="git commit --amend -n" main',
    f"git rebase -ix 'git commit --amend {NV}' main", f"git rebase --ex 'git commit --amend {NV}' main",
    f"git rebase --exe 'git commit --amend {NV}' main",
    f"git submodule foreach 'git commit {NV} -m x'",
    f"git submodule --quiet foreach --recursive git commit {NV} -m x",
    f"git bisect run git commit {NV} -m x",
    # options globales à valeur séparée, et eval au texte calculé
    f"git --attr-source HEAD commit {NV} -m x", f"git --attr-source HEAD push {NV}",
    f'eval "git commit {NV} -m $MSG"', f'eval "git push {NV} origin $(git branch --show-current)"',
    # plus profond que PROFONDEUR : relu sur le texte, prudemment
    PROFOND,
    # guillemets déséquilibrés : bash ne lancerait rien, on refuse par prudence
    f'git commit {NV} -m "x',
    # relecture de sécurité du 2026-10-04 : valeur en tiret, variable posée sur bash -c
    "git config core.hooksPath -x", "git config --global core.hooksPath -nulle",
    'HUSKY=0 bash -c "git commit -m x"', 'env GIT_CONFIG_PARAMETERS=x sh -c "git push"',
    'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/x bash -c "git commit -m x"',
    # relecture xhigh de la 0.4.4 : alias shell, config transmise aux git lancés par git
    "git cm wip", "git opt -m x",
    "git -c core.hooksPath=/dev/null submodule foreach 'git commit -m x'",
    "git -c core.hooksPath=/dev/null bisect run git commit -m x",
    "HUSKY=0 git submodule foreach 'git commit -m x'",
    "git -c core.hooksPath=/dev/null shc", "HUSKY=0 git shc",
    f"cd {depot} && git rebase -x 'git ci' main",
    "git -c alias.a=b -c alias.b='commit -n' a",
    "git -c alias.a='!git b' -c alias.b='commit -n' a",
    f'X={NV}; eval "git commit $X -m y"',
]

try:
    subprocess.run(["git", "init", "-q", depot], check=True)
    for nom, valeur in ALIAS.items():
        subprocess.run(["git", "-C", depot, "config", f"alias.{nom}", valeur], check=True)

    section("Travail ordinaire : passe")
    for cmd in passent:
        attendre(f"passe : {cmd[:60]!r}", 0, lancer(cmd))

    section("Hooks du dépôt sautés : refusé")
    for cmd in refuses:
        attendre(f"refusé : {cmd.replace(depot, '…')[:60]!r}", 2, lancer(cmd, cwd=base if depot in cmd else depot))

    section("Entrée piégée ou illisible : refusée, jamais passée")
    piege = json.dumps({"tool_input": {"command": f"git commit {NV} -m x # \ud800"}, "cwd": depot}).encode()
    attendre("demi-caractère Unicode orphelin", 2, lancer(brut=piege))
    brut = json.dumps({"tool_input": {"command": f"git commit {NV} -m x # @@"}, "cwd": depot}).encode()
    attendre("octet invalide brut", 2, lancer(brut=brut.replace(b"@@", b"\xff\xfe")))
    attendre("JSON illisible", 2, lancer(brut=b"{"))
    attendre("sans python3 : refus, jamais passage", 2,
             lancer("git status", env={"PATH": "/bin:/usr/sbin", "HOME": os.environ["HOME"]}))

    section("Le contrôle avant push voit les options globales à valeur séparée")
    # « git --attr-source HEAD push » : la valeur était prise pour la
    # sous-commande, et le push n'était pas contrôlé.
    # Les alias en chaîne (p2 → p → push) et les alias shell (« !git push »)
    # sont suivis par TOUS les garde-fous, pas seulement celui-ci.
    for cmd in ("git --attr-source HEAD push", "git --config-env core.editor=E push", "git p2", "git sp"):
        r = subprocess.run(["python3", "-I", os.path.join(H, "analyse-commande.py"), "pousses"],
                           input=json.dumps({"tool_input": {"command": cmd}, "cwd": depot}).encode(),
                           capture_output=True, timeout=60)
        attendre(f"push vu : {cmd!r}", True, r.stdout.decode().startswith(depot))

    section("Aucun nom global défini deux fois dans l'analyseur")
    arbre = ast.parse(open(os.path.join(H, "analyse-commande.py"), encoding="utf-8").read())
    vus, doubles = set(), []
    for n in arbre.body:
        noms = [n.name] if isinstance(n, (ast.FunctionDef, ast.ClassDef)) else \
            [t.id for t in getattr(n, "targets", []) if isinstance(t, ast.Name)]
        for nom in noms:
            if nom in vus:
                doubles.append(nom)
            vus.add(nom)
    attendre("noms globaux uniques", [], doubles)
finally:
    shutil.rmtree(base, ignore_errors=True)

sys.exit(c.bilan())
