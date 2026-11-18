"""motif-panne.py — un garde-fou qui n'a pas pu lire l'action la REFUSE (code 2),
quel que soit l'état de motif-panne.sh : présent, absent ou cassé.

motif-panne.sh (0.7.1) ne fait que dire POURQUOI la lecture a échoué. Sous
« set -e » et le bash 3.2 de macOS, « . motif-panne.sh || repli » faisait
sortir pre-edit-guard et rule12 en 1 quand le fichier manquait — code que
Claude Code traite comme non bloquant : un .env était lu (/code-review xhigh
de la PR n° 2). La copie locale de ~/.claude n'avait justement pas ce fichier.

Usage : python3 -I motif-panne.py <dossier des hooks>   → code 0 si tout passe.
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

base = tempfile.mkdtemp(prefix="essai-motif.")
projet = os.path.join(base, "projet")
os.makedirs(projet)
subprocess.run(["git", "init", "-q", projet], check=True)
open(os.path.join(projet, "msg.txt"), "w").write("fix: une correction\n")
open(os.path.join(projet, "notes.txt"), "w").write("rien\n")

# Une action par garde-fou, qui l'oblige à passer par le lecteur.
ACTIONS = [
    ("protect-secrets.sh", "Bash", {"command": "cat notes.txt"}),
    ("sans-verif.sh", "Bash", {"command": "git commit -m x"}),
    ("validate-before-push.sh", "Bash", {"command": "git push"}),
    ("rule12-phase-debug-required.sh", "Bash", {"command": "git commit -F msg.txt"}),
    ("pre-edit-guard.sh", "Read", {"file_path": os.path.join(projet, "notes.txt")}),
]


def copie(nom, motif, lecteur_casse):
    d = os.path.join(base, nom)
    shutil.copytree(H, d, ignore=shutil.ignore_patterns("__pycache__"))
    m = os.path.join(d, "motif-panne.sh")
    if motif == "absent":
        os.remove(m)
    elif motif == "cassé":
        with open(m, "w", encoding="utf-8") as f:
            f.write("motif_panne() {\n    echo \"tronque\n")      # guillemet et accolade jamais fermés
    if lecteur_casse:
        for lecteur in ("analyse-commande.py", "detection-secrets.py"):
            with open(os.path.join(d, lecteur), "a", encoding="utf-8") as f:
                f.write("\nraise RuntimeError('lecteur casse pour l essai')\n")
    return d


def jouer(hooks, hook, outil, entree):
    return c.lancer(hooks, hook, outil, entree, cwd=projet, env={"CLAUDE_PROJECT_DIR": projet})


try:
    for motif in ("présent", "absent", "cassé"):
        section(f"Lecteur en panne, motif-panne.sh {motif} : toujours refusé (2)")
        d = copie(f"casse-{motif}", motif, True)
        for hook, outil, entree in ACTIONS:
            code, _, err = jouer(d, hook, outil, entree)
            attendre(f"{hook} : refusé", (2, 1), (code, int("ne laisse rien passer" in err)), err[:160])

    for motif in ("absent", "cassé"):
        section(f"Lecteur sain, motif-panne.sh {motif} : rien ne change")
        d = copie(f"sain-{motif}", motif, False)
        env_ = os.path.join(projet, ".env")
        open(env_, "w").write("X=1\n")
        attendre("pre-edit-guard.sh, Read .env : refusé", 2, jouer(d, "pre-edit-guard.sh", "Read", {"file_path": env_})[0])
        attendre("pre-edit-guard.sh, Read notes.txt : permis", 0,
                 jouer(d, "pre-edit-guard.sh", "Read", {"file_path": os.path.join(projet, "notes.txt")})[0])
        attendre("protect-secrets.sh, cat .env : refusé", 2, jouer(d, "protect-secrets.sh", "Bash", {"command": "cat .env"})[0])
        attendre("rule12, commit -F ordinaire : permis", 0,
                 jouer(d, "rule12-phase-debug-required.sh", "Bash", {"command": "git commit -F msg.txt"})[0])
        os.remove(env_)

    section("Le motif dit la vraie panne")
    d = copie("motif-lecteur", "présent", True)
    code, _, err = jouer(d, "protect-secrets.sh", "Bash", {"command": "cat notes.txt"})
    attendre("lecteur qui plante : « lecteur du plugin », Python hors de cause", (2, 1, 0),
             (code, int("lecteur du plugin a plante" in err), int("Python introuvable" in err)), err[:160])
finally:
    shutil.rmtree(base, ignore_errors=True)
sys.exit(c.bilan())
