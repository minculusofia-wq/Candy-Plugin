"""commun.py — les outils des essais Python (groupe 11).

Même contrat que aide.sh : « j'envoie CECI à ce hook, j'attends CE code ».
Chaque cas s'affiche comme dans les groupes bash (✓ / ✗), et le bilan donne le
nombre de cas joués. Toute chaîne qui ressemble à un secret est ASSEMBLÉE par
morceaux (voir aide.sh) : ce dépôt ne contient aucun faux secret en clair.
"""
import json
import os
import subprocess
import sys

VERT, ROUGE, GRIS, GRAS, NC = (("\033[0;32m", "\033[0;31m", "\033[0;90m", "\033[1m", "\033[0m")
                                if sys.stdout.isatty() else ("",) * 5)
etat = {"n": 0, "echecs": 0}


def j(*morceaux):
    return "".join(morceaux)


def section(titre):
    print(f"\n{GRAS}{titre}{NC}")


def attendre(libelle, attendu, obtenu, detail=""):
    etat["n"] += 1
    if attendu == obtenu:
        print(f"  {VERT}✓{NC} {libelle}")
    else:
        etat["echecs"] += 1
        print(f"  {ROUGE}✗{NC} {libelle} {GRIS}(attendu {attendu}, obtenu {obtenu}) {detail}{NC}")


def lancer(hooks, hook, outil, entree, cwd=None, env=None, arguments=()):
    """(code, stdout, stderr) du hook, avec le JSON que Claude Code enverrait."""
    donnees = {"tool_name": outil, "tool_input": entree}
    if cwd:
        donnees["cwd"] = cwd
    e = dict(os.environ, **(env or {}))
    r = subprocess.run(["bash", os.path.join(hooks, hook), *arguments], input=json.dumps(donnees).encode(),
                       capture_output=True, env=e, cwd=cwd or None, timeout=120)
    return r.returncode, r.stdout.decode(errors="replace"), r.stderr.decode(errors="replace")


def bilan():
    print(f"\n{GRAS}{GRIS}=== BILAN ==={NC}")
    print(f"  {etat['n']} cas joués, {etat['echecs']} en échec")
    if etat["echecs"]:
        print(f"  {ROUGE}{etat['echecs']} cas en échec — le travail n'est PAS terminé.{NC}\n")
        return 1
    print(f"  {VERT}Tout passe.{NC}\n")
    return 0
