#!/usr/bin/env python3
"""Compte les fois ou une reponse a enfreint une regle, d'apres les
transcriptions.

Le hook relire-ma-reponse.sh publie une correction quand une reponse contient
une formule interdite. Cette correction est enregistree dans la transcription
comme une entree `isMeta: true` dont le contenu commence par
"Stop hook feedback:". C'est cette signature qu'on compte — et elle seule.

Compter avec un simple grep sur les .jsonl donne un resultat faux : les
transcriptions contiennent aussi la sortie des commandes lancees pendant les
sessions, y compris d'anciens comptages. Le compte se contamine alors lui-meme
— mesure : un grep annoncait 37 puis 60 violations la ou il y en avait 19.

Ce que le resultat veut dire : une regle enfreinte bien plus souvent qu'une
autre n'est pas plus importante, elle est moins bien appliquee ou moins bien
ecrite. Si une seule formule domine, se demander si la regle la nomme assez
clairement — et si oui, ne rien changer : c'est le hook qui fait le travail.

Usage : compter-relectures.py [jours] [dossier_projects]
   ex : compter-relectures.py 30
"""
import json
import os
import re
import sys
import datetime
from collections import Counter

JOURS = int(sys.argv[1]) if len(sys.argv) > 1 else 0
RACINE = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.claude/projects")

MARQUEUR = "=== RELECTURE ==="
MOTIF = re.compile(r"par la regle ([^:]+) : « ([^»]*) »")

limite = None
if JOURS > 0:
    limite = datetime.datetime.now().timestamp() - JOURS * 86400

regles, formules, sessions = Counter(), Counter(), set()
total = 0

for dossier, _, fichiers in os.walk(RACINE):
    for nom in fichiers:
        if not nom.endswith(".jsonl"):
            continue
        chemin = os.path.join(dossier, nom)
        if limite and os.path.getmtime(chemin) < limite:
            continue
        try:
            fh = open(chemin, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for ligne in fh:
                try:
                    d = json.loads(ligne)
                except Exception:
                    continue
                if d.get("type") != "user" or not d.get("isMeta"):
                    continue
                c = (d.get("message") or {}).get("content")
                if not isinstance(c, str):
                    continue
                if not c.startswith("Stop hook feedback:") or MARQUEUR not in c:
                    continue
                total += 1
                sessions.add(d.get("sessionId"))
                for regle, formule in MOTIF.findall(c):
                    regles[regle.strip()] += 1
                    formules[formule.strip()] += 1

periode = f"sur {JOURS} jours" if JOURS else "sur tout l'historique"
print(f"=== Regles enfreintes {periode} ===")
print(f"{total} correction(s) publiee(s), reparties sur {len(sessions)} session(s)\n")
if not total:
    print("  Aucune. Soit les regles tiennent, soit le hook ne tourne plus —")
    print("  verifier que relire-ma-reponse.sh est bien dans le bloc Stop.")
    sys.exit(0)
print("Par regle :")
for r, n in regles.most_common():
    print(f"  {n:4}  {r}")
print("\nPar formule :")
for f, n in formules.most_common(12):
    print(f"  {n:4}  « {f} »")
print("\nUne regle enfreinte bien plus souvent qu'une autre n'est pas plus")
print("importante : elle est moins bien appliquee, ou moins bien ecrite.")
