#!/usr/bin/env python3
"""Relit la reponse de Claude et lui fait publier une correction quand elle
contient une formule interdite.

⚠️ CE QU'IL NE PEUT PAS FAIRE — LU LE 2026-08-08, EN PRODUCTION
---------------------------------------------------------------
Ce controle s'execute APRES que la reponse est affichee. Il ne la retire pas :
il empeche seulement le tour de se terminer, et Claude AJOUTE du texte a la
suite.

La premiere version de ce fichier a ete construite sur la croyance inverse —
« la reponse ne t'arrive pas, tu ne vois que la version corrigee ». C'est faux,
et l'utilisateur l'a vu le jour meme : il a recu DEUX fois la meme reponse, l'originale
puis sa reecriture.

Consequence directe : un controle de LONGUEUR est ici contre-productif. Une
reponse de 60 lignes s'affiche, la reecriture de 20 s'ajoute dessous, et l'utilisateur
en lit 80. Le controle de longueur a donc ete RETIRE — ne pas le remettre.

Ne restent que les controles ou une correction courte apporte quelque chose :
une formule de flatterie ou une supposition non verifiee valent d'etre
retractees en une ligne, parce que c'est le FOND qui est faux, pas le format.

CE QU'IL NE FAIT PAS NON PLUS
-----------------------------
Il ne juge pas si le contenu etait utile — ca ne se mesure pas. Il ne cherche pas
les « commandes a taper » : montrer la SORTIE d'une commande est legitime, et
certaines (/effort) ne peuvent pas etre lancees par Claude. Un controle bruyant
finit ignore.

ANTI-BOUCLE
-----------
Il n'intervient qu'UNE fois par message de l'utilisateur.

Codes de sortie : 0 = rien a dire. 2 = Claude doit publier une correction courte.
"""

import json
import os
import re
import sys
import unicodedata
from pathlib import Path

LIGNES_MAX = 40

# Les formules interdites par la regle « honnetete brutale ». Comparaison faite
# sans accents ni casse : « Ça dépend » et « ca depend » sont la meme faute.
FLATTERIE = (
    "c'est une bonne question",
    "bonne question",
    "bonne intuition",
    "bon reflexe",
    "tu as raison de",
    "c'est interessant",
    "c'est pertinent",
    "c'est pas bete",
    "il y a du vrai dans ce que tu dis",
    "je comprends ton raisonnement, cependant",
    "c'est une approche valable parmi d'autres",
    "hesite pas",
    "n'hesite pas",
)

# Les formules interdites par la regle « ne rien inventer ». Elles signalent une
# affirmation non verifiee — exactement ce que la regle existe pour empecher.
# Ajoutees le 2026-08-08 : le controle ne couvrait que 2 regles sur 12, et
# celle-ci est la seule autre qui se verifie mecaniquement, sans faux positif.
# La regle demande d'ecrire « je vais verifier » puis de verifier, jamais de
# livrer une approximation.
SUPPOSITION = (
    "je pense que",
    "je crois que",
    "il me semble",
    "normalement c'est",
    "en general c'est",
    "ca doit etre",
    "ca devrait etre",
    "probablement",
)

# Quand l'utilisateur demande ca, la longueur est le format attendu, pas une derive.
DEMANDE_LONGUE = (
    "analyse", "analyser", "rapport", "explique", "explication", "detaille",
    "detail", "compare", "comparaison", "audit", "avis", "critique", "resume",
    "presente", "pourquoi", "comment",
)


def sans_accents(texte: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFD", texte.lower())
        if unicodedata.category(c) != "Mn"
    )


def dernier_message_utilisateur(chemin: str) -> str:
    """Le dernier message de l'utilisateur, lu dans la transcription."""
    try:
        lignes = Path(chemin).read_text(encoding="utf-8").splitlines()
    except OSError:
        return ""
    for ligne in reversed(lignes):
        try:
            evenement = json.loads(ligne)
        except ValueError:
            continue
        if evenement.get("type") != "user":
            continue
        contenu = evenement.get("message", {}).get("content")
        if isinstance(contenu, str):
            return contenu
        if isinstance(contenu, list):
            return " ".join(
                bloc.get("text", "") for bloc in contenu
                if isinstance(bloc, dict) and bloc.get("type") == "text"
            )
    return ""


def citations_retirees(reponse: str) -> str:
    """Retire ce qui est CITE, pour ne juger que ce qui est AFFIRME.

    Faux positif trouve le 2026-08-08, une minute apres la mise en service : le
    controle a refuse la reponse qui annoncait sa propre livraison, parce qu'un
    tableau y CITAIT « bonne question » comme exemple de ce qu'il attrape.

    Un projet réel connait deja ce piege — son garde-fou Swift laisse une
    ligne de commentaire citer la formulation qu'elle interdit. Un controle qui
    ne distingue pas l'usage de la mention interdit d'expliquer ses propres
    regles.

    Sont donc retires : les blocs de code, les extraits entre accents graves,
    les segments entre guillemets francais ou droits.
    """
    sans = re.sub(r"```.*?```", " ", reponse, flags=re.S)
    sans = re.sub(r"`[^`\n]*`", " ", sans)
    sans = re.sub(r"«[^»]*»", " ", sans)
    sans = re.sub(r'"[^"\n]*"', " ", sans)
    return sans


def longueur_utile(reponse: str) -> int:
    """Lignes non vides, blocs de code exclus.

    Un bloc de code est une PREUVE — la sortie reelle d'un controle, un extrait
    de fichier. Le compter comme du bavardage pousserait a masquer les preuves,
    ce qui est l'inverse du but.
    """
    sans_code = re.sub(r"```.*?```", "", reponse, flags=re.S)
    return len([l for l in sans_code.splitlines() if l.strip()])


def main() -> int:
    try:
        entree = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0  # Jamais bloquer sur une entree illisible.

    reponse = entree.get("last_assistant_message") or ""
    if not reponse.strip():
        return 0

    # ─── Anti-boucle : un seul refus par message de l'utilisateur ───────────────────
    prompt_id = entree.get("prompt_id") or entree.get("session_id") or "inconnu"
    marqueur = Path(
        os.environ.get("TMPDIR", "/tmp")
    ) / f".relecture-{re.sub(r'[^A-Za-z0-9_-]', '', prompt_id)}"
    if marqueur.exists():
        marqueur.unlink(missing_ok=True)
        return 0

    demande = sans_accents(dernier_message_utilisateur(entree.get("transcript_path", "")))
    corps = sans_accents(citations_retirees(reponse))
    motifs: list[str] = []

    # ─── 1. Formules de flatterie ───────────────────────────────────────
    trouvees = [f for f in FLATTERIE if sans_accents(f) in corps]
    if trouvees:
        motifs.append(
            "formule(s) interdite(s) par la regle d'honnetete brutale : "
            + ", ".join(f'« {f} »' for f in trouvees)
        )

    # ─── 2. Suppositions non verifiees ─────────────────────────────────
    supposees = [f for f in SUPPOSITION if sans_accents(f) in corps]
    if supposees:
        motifs.append(
            "supposition(s) interdite(s) par la regle « ne rien inventer » : "
            + ", ".join(f'« {f} »' for f in supposees)
            + ". Verifier a la source, ou ecrire « je n'ai pas trouve cette info »."
        )

    # Le controle de LONGUEUR a ete retire le 2026-08-08 — voir l'entete : il
    # rallongeait ce qu'il pretendait raccourcir.

    if not motifs:
        return 0

    marqueur.write_text("1", encoding="utf-8")
    detail = "\n".join(f"  - {m}" for m in motifs)
    sys.stderr.write(
        "=== RELECTURE ===\n"
        f"{detail}\n\n"
        "La reponse est DEJA affichee — la reecrire en entier la ferait lire deux "
        "fois. Publier UNE SEULE phrase de correction : retirer la formule fautive "
        "et donner l'information verifiee, ou dire qu'elle ne l'est pas. "
        "Rien d'autre.\n"
        "=== FIN RELECTURE ===\n"
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
