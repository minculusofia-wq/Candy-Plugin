"""cloture.py — rule12 : un commit de clôture de phase ne part pas sans
/fin-phase, quelle que soit la forme du commit, et un commit ordinaire n'est
jamais gêné.

Jusqu'à la 0.3.4, rule12 découpait la commande à la main :
  - « git commit -F fichier », « git merge -m », « git ci » (alias), « \\ » +
    retour à la ligne entre git et commit passaient sans /fin-phase ;
  - un « git log --grep » ou un corps de message qui citait une clôture passée
    bloquait un commit ordinaire ;
  - le témoin était cherché dans le dossier d'ouverture de la session, et
    consommé AVANT le commit : un commit refusé ensuite obligeait à refaire
    /fin-phase.

Usage : python3 -I cloture.py <dossier des hooks>   → code 0 si tout passe.
"""
import importlib.util
import json
import os
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
MARQUEUR = "clo" + "ture(phase 3): VERT"
base = tempfile.mkdtemp(prefix="essai-cloture.")
depot = os.path.join(base, "depot")
subprocess.run(["git", "init", "-q", depot], check=True)
# Le dépôt tel qu'on l'écrit dans une commande bash : sous Windows, « C:\…»
# perdrait ses « \ » à la lecture, et le commit viserait un dossier qui n'existe pas.
DS = depot.replace(os.sep, "/")
# « / » et non os.path.join : sous Windows, il mettrait un « \ » avant le nom,
# et le hook, qui trouve son dossier par ${BASH_SOURCE[0]%/*}, remonterait d'un
# cran — tout serait refusé faute de lecteur, pour une raison étrangère à l'essai.
HOOK = H + "/rule12-phase-debug-required.sh"


def lancer(cmd, cwd=depot, projet=depot, *arguments):
    r = subprocess.run(["bash", HOOK, *arguments],
                       input=json.dumps({"tool_input": {"command": cmd}, "cwd": cwd}).encode(),
                       capture_output=True, env=dict(os.environ, CLAUDE_PROJECT_DIR=projet), cwd=cwd, timeout=60)
    return r.returncode


def apres(cmd):
    r = subprocess.run(["bash", HOOK, "apres"],
                       input=json.dumps({"tool_input": {"command": cmd}, "cwd": depot}).encode(),
                       capture_output=True, env=dict(os.environ, CLAUDE_PROJECT_DIR=depot), cwd=depot, timeout=60)
    return r.returncode, r.stdout.decode()


try:
    section("Clôture de phase — toutes les formes du commit")
    open(os.path.join(depot, "msg-cloture.txt"), "w").write(MARQUEUR + "\n\ndétail\n")
    open(os.path.join(depot, "msg-ordinaire.txt"), "w").write("fix: une correction\n")
    attendre("-F fichier de clôture écrit plus tôt : refusé", 2, lancer("git commit -F msg-cloture.txt"))
    attendre("--file=fichier de clôture : refusé", 2, lancer("git commit --file=msg-cloture.txt"))
    attendre("-F chemin absolu, depuis ailleurs : refusé", 2, lancer(f"git -C {DS} commit -F {DS}/msg-cloture.txt", cwd=base))
    attendre("cd dépôt && git commit -F fichier : refusé", 2, lancer(f"cd {DS} && git commit -F msg-cloture.txt", cwd=base))
    attendre("-F fichier ordinaire : permis", 0, lancer("git commit -F msg-ordinaire.txt"))
    attendre("-F fichier créé par la même commande, ordinaire : permis", 0,
             lancer("printf 'fix: x' > m.txt && git commit -F m.txt"))
    attendre("marqueur dans la commande : refusé", 2, lancer(f'git commit -m "{MARQUEUR}"'))
    attendre("commit ordinaire : permis", 0, lancer('git commit -m "fix: x"'))
    try:
        os.symlink(os.path.join(depot, "msg-cloture.txt"), os.path.join(depot, "lien.txt"))
    except OSError:
        # Windows sans le mode développeur refuse de créer un lien : « -F
        # lien.txt » lit alors une copie, et le suivi du lien n'est pas prouvé ici.
        print("  (lien symbolique impossible sur cette machine : « -F lien.txt » lit une copie, le suivi du lien n'est pas éprouvé)")
        shutil.copy(os.path.join(depot, "msg-cloture.txt"), os.path.join(depot, "lien.txt"))
    refuses = [f'git \\\n  commit -m "{MARQUEUR}"', "git commit \\\n  -F msg-cloture.txt",
               f"git commit -m \"$(cat <<'EOF'\n{MARQUEUR}\n\ndétail\nEOF\n)\"",
               f"git commit -F - <<'FIN'\n{MARQUEUR}\nFIN", "git commit -aF msg-cloture.txt",
               f'git merge -m "{MARQUEUR}" autre', f"(cd {DS} && git commit -F msg-cloture.txt)",
               'git commit -m "$(cat msg-cloture.txt)"', "git commit -F lien.txt",
               f'git -c alias.fin=commit fin -m "{MARQUEUR}"',
               # relecture xhigh : un $( ) sans cat ni document laissait passer le marqueur
               f'git commit -m "$(printf %s "{MARQUEUR}")"',
               # 0.5.0 : un alias shell donné sur la ligne (cas de la copie locale),
               # et git écrit sans le mot « git » d'un seul tenant — le filtre
               # rapide sur le texte brut laissait passer la clôture.
               f"git -c 'alias.fin=!git commit' fin -m \"{MARQUEUR}\"",
               f'g\\it commit -m "{MARQUEUR}"', f"'g'it commit -m \"{MARQUEUR}\"",
               f"$'\\x67it' commit -m \"{MARQUEUR}\"",
               # zsh développe =git en chemin de git (relecture de la 0.5.0)
               f'=git commit -m "{MARQUEUR}"']
    for cmd in refuses:
        attendre(f"clôture refusée : {cmd.replace(depot, '…')[:55]!r}", 2, lancer(cmd, cwd=base if depot in cmd else depot))
    subprocess.run(["git", "-C", depot, "config", "alias.ci", "commit"], check=True)
    attendre("alias git ci = commit : refusé", 2, lancer(f'git ci -m "{MARQUEUR}"'))
    permis = [f'git log --grep "{MARQUEUR}" && git commit -m "fix: x"',
              f'git commit -m "fix: x" -m "suite de {MARQUEUR}"',
              f"git commit -m \"$(cat <<'EOF'\nfix: x\n\nprépare {MARQUEUR}\nEOF\n)\"",
              'git commit -m "$(date +%F) : fix x"',
              # 0.5.0, cas de la copie locale : titres calculés et alias ordinaires
              'git commit -m "$(date): ajout"', 'git commit -m "$(printf %s "fix: x")"',
              'git -c alias.fin=commit fin -m "fix: x"', f'git -c alias.fin=log fin --grep "{MARQUEUR}"']
    for cmd in permis:
        attendre(f"commit ordinaire permis : {cmd[:55]!r}", 0, lancer(cmd))

    section("Clôture de phase — le témoin, à la racine, gardé jusqu'au vrai commit")
    sous = os.path.join(depot, "sous")
    os.makedirs(sous)
    temoin = os.path.join(depot, ".claude-phase-debug-done")
    open(temoin, "w").write("ok")
    attendre("témoin à la racine, session ouverte dans un sous-dossier : permis", 0,
             lancer(f'git commit -m "{MARQUEUR}"', cwd=sous, projet=sous))
    attendre("-F clôture avec témoin valide : permis", 0, lancer("git commit -F msg-cloture.txt"))
    attendre("le témoin est encore là après la vérification", True, os.path.exists(temoin))
    attendre("seconde tentative après un refus du commit : permise", 0, lancer("git commit -F msg-cloture.txt"))
    g = ["git", "-C", depot, "-c", "user.email=a@b", "-c", "user.name=a", "-c", "commit.gpgsign=false"]
    subprocess.run(g + ["commit", "-q", "--allow-empty", "-m", "fix: ordinaire"], check=True)
    attendre("après un commit ordinaire : témoin gardé", (0, "", True),
             (*apres('git commit -m "fix: ordinaire"'), os.path.exists(temoin)))
    attendre("vérification avant le commit de clôture", 0, lancer("git commit -F msg-cloture.txt"))
    subprocess.run(g + ["commit", "-q", "--allow-empty", "-F", os.path.join(depot, "msg-cloture.txt")], check=True)
    attendre("après le commit de clôture : témoin retiré", (0, "", False),
             (*apres("git commit -F msg-cloture.txt"), os.path.exists(temoin)))
    # « git commit …; echo fin » réussit même quand le commit échoue : sans
    # nouveau commit depuis la vérification, le témoin reste.
    open(temoin, "w").write("ok")
    attendre("seconde clôture : vérification", 0, lancer("git commit -F msg-cloture.txt; echo fin"))
    attendre("seconde clôture échouée : témoin gardé", (0, "", True),
             (*apres("git commit -F msg-cloture.txt; echo fin"), os.path.exists(temoin)))
    attendre("une commande sans git ne lance rien, avant comme après", (0, 0), (lancer("ls -la"), apres("ls -la")[0]))

    # Jusqu'à la 0.7.0, lire_message() ouvrait le fichier de -F avec
    # os.O_NONBLOCK, absent sous Windows : le lecteur sortait en 3, et TOUT
    # « git commit -F » — ordinaire compris — était refusé au faux motif
    # « Python introuvable ». Le lecteur est joué seul, puis à travers le hook.
    section("Clôture de phase — « commit -F » lu sur toutes les plateformes")

    def lecteur(cmd):
        r = subprocess.run([sys.executable, "-I", os.path.join(H, "analyse-commande.py"), "cloture"],
                           input=json.dumps({"tool_input": {"command": cmd}, "cwd": depot}).encode(),
                           capture_output=True, cwd=depot, timeout=30)
        return r.returncode, r.stdout.decode(errors="replace").split("\t")[0].strip()

    def refus(cmd, hooks=H, env=None):
        r = subprocess.run(["bash", hooks + "/rule12-phase-debug-required.sh"],
                           input=json.dumps({"tool_input": {"command": cmd}, "cwd": depot}).encode(),
                           capture_output=True, env=dict(os.environ, CLAUDE_PROJECT_DIR=depot, **(env or {})),
                           cwd=depot, timeout=60)
        return r.returncode, r.stderr.decode(errors="replace")

    attendre("lecteur, -F fichier ordinaire : NON, sans planter", (0, "NON"), lecteur("git commit -F msg-ordinaire.txt"))
    attendre("lecteur, -F fichier de clôture : OUI, sans planter", (0, "OUI"), lecteur("git commit -F msg-cloture.txt"))
    attendre("lecteur, -F fichier absent : NON", (0, "NON"), lecteur("git commit -F absent.txt"))
    peripherique = "NUL" if os.name == "nt" else "/dev/zero"
    attendre(f"lecteur, -F {peripherique} : NON, sans attendre", (0, "NON"), lecteur(f"git commit -F {peripherique}"))
    if os.path.exists(temoin):
        os.remove(temoin)                           # sans témoin : la clôture doit être refusée
    code, err = refus("git commit -F msg-cloture.txt")
    attendre("hook, -F clôture : refusé pour /fin-phase, pas pour Python", (2, 0),
             (code, int("pas pu lire" in err)), err[:200])

    section("Lecture impossible — le refus dit laquelle des trois pannes")
    casse = os.path.join(base, "hooks-casses")
    shutil.copytree(H, casse, ignore=shutil.ignore_patterns("__pycache__"))
    with open(os.path.join(casse, "analyse-commande.py"), "a", encoding="utf-8") as h:
        h.write("\nraise RuntimeError('lecteur casse pour l essai')\n")
    code, err = refus("git commit -F msg-ordinaire.txt", hooks=casse)
    attendre("lecteur qui plante : refusé, motif « lecteur du plugin », Python mis hors de cause",
             (2, 1, 0), (code, int("lecteur du plugin a plante" in err), int("Python introuvable" in err)), err[:200])
    for code_faux, motif in ((127, "Python introuvable :"), (1, "Python en panne :")):
        faux = os.path.join(base, f"faux-python-{code_faux}")
        os.makedirs(faux)
        with open(os.path.join(faux, "python3"), "w", newline="\n") as h:
            h.write(f"#!/bin/bash\nexit {code_faux}\n")
        os.chmod(os.path.join(faux, "python3"), 0o755)
        code, err = refus("git commit -F msg-ordinaire.txt", env={"PATH": faux + os.pathsep + os.environ["PATH"]})
        attendre(f"python3 qui sort en {code_faux} : refusé (2, jamais {code_faux}), motif « {motif} »",
                 (2, 1), (code, int(motif in err)), err[:200])
finally:
    shutil.rmtree(base, ignore_errors=True)
sys.exit(c.bilan())
