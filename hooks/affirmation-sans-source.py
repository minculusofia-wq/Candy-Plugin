#!/usr/bin/env python3
"""Stop : refuse une affirmation d'hébergement que rien dans la conversation n'a établie.

Faute d'origine (2026-11-08) : « tes sites passent par Vercel », « tes bots
tournent sur un serveur à toi » — écrits sans qu'aucun message de l'utilisateur ni
aucun résultat d'outil de la conversation ne le dise. Le hook relire-ma-reponse
ne l'a pas vue : elle ne contenait aucune formule d'hésitation.

Principe : on cherche, hors citations, une phrase qui attribue à l'utilisateur un
site / bot / projet / app ET un hébergeur ou un type de machine, avec un verbe
d'hébergement. Chaque hébergeur nommé doit apparaître dans la conversation
(message de l'utilisateur ou résultat d'outil, jamais dans les réponses de Claude
elles-mêmes — sinon une erreur se validerait toute seule).

Limites assumées : il ne juge que cette forme de phrase (possessif + sujet +
verbe d'hébergement + hébergeur). Il s'exécute après l'affichage de la réponse
et ne peut que faire publier une correction d'une ligne (voir relire-ma-reponse).
Exit 0 : rien. Exit 2 : correction à publier. Jamais bloquant sur entrée illisible.
"""

import json
import os
import re
import sys
import unicodedata
from pathlib import Path

HEBERGEURS = (
    "vercel", "cloudflare", "netlify", "railway", "render", "heroku", "fly.io",
    "aws", "gcp", "azure", "ovh", "hetzner", "digitalocean", "droplet", "vps",
    "serveur", "github pages", "firebase", "supabase", "neon",
)
SUJETS = r"(?:sites?|bots?|projets?|apps?|applications?|backends?|bases?|domaines?|dashboards?)"
POSSESSIF = r"(?:tes|ton|ta|vos|votre|ses|son|sa)"
VERBES = (
    r"(?:tourne\w*|passe\w*|heberge\w*|deploye\w*|sont sur|est sur|sont chez|est chez|"
    r"sont heberge\w*|est heberge\w*|vivent sur|vit sur|reposent sur|repose sur)"
)
PHRASE = re.compile(
    rf"\b{POSSESSIF}\b[^.!?\n]{{0,60}}\b{SUJETS}\b[^.!?\n]{{0,80}}\b{VERBES}\b[^.!?\n]*",
)


def sans_accents(t: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFD", t.lower()) if unicodedata.category(c) != "Mn"
    )


def citations_retirees(t: str) -> str:
    t = re.sub(r"```.*?```", " ", t, flags=re.S)
    t = re.sub(r"`[^`\n]*`", " ", t)
    t = re.sub(r"«[^»]*»", " ", t)
    t = re.sub(r'"[^"\n]*"', " ", t)
    return t


def textes(contenu) -> list[str]:
    """Texte brut d'un champ content (str, ou liste de blocs)."""
    if isinstance(contenu, str):
        return [contenu]
    sortie: list[str] = []
    if isinstance(contenu, list):
        for bloc in contenu:
            if isinstance(bloc, str):
                sortie.append(bloc)
            elif isinstance(bloc, dict):
                if bloc.get("type") == "tool_result":
                    sortie += textes(bloc.get("content"))
                elif bloc.get("type") == "text":
                    sortie.append(str(bloc.get("text", "")))
    return sortie


def preuves(chemin: str) -> str:
    """Tout ce qui vient de l'utilisateur ou des outils (jamais des réponses de Claude)."""
    morceaux: list[str] = []
    try:
        with open(chemin, encoding="utf-8") as f:
            for ligne in f:
                try:
                    e = json.loads(ligne)
                except ValueError:
                    continue
                if not isinstance(e, dict) or e.get("type") != "user":
                    continue
                m = e.get("message")
                if isinstance(m, dict):
                    morceaux += textes(m.get("content"))
    except OSError:
        return None
    return sans_accents("\n".join(morceaux))


def main() -> int:
    try:
        entree = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0
    if not isinstance(entree, dict):
        return 0
    reponse = entree.get("last_assistant_message") or ""
    chemin = entree.get("transcript_path") or ""
    if not isinstance(reponse, str) or not reponse.strip() or not chemin:
        return 0

    pid = str(entree.get("prompt_id") or entree.get("session_id") or "inconnu")
    marqueur = Path(os.environ.get("TMPDIR", "/tmp")) / f".affirm-{re.sub(r'[^A-Za-z0-9_-]', '', pid)}"
    if marqueur.exists():
        marqueur.unlink(missing_ok=True)
        return 0

    corps = sans_accents(citations_retirees(reponse))
    base = None
    sans_preuve: list[tuple[str, str]] = []
    for m in PHRASE.finditer(corps):
        phrase = m.group(0)
        for h in HEBERGEURS:
            if re.search(rf"\b{re.escape(h)}\b", phrase):
                if base is None:
                    base = preuves(chemin)
                    if base is None:
                        return 0  # transcription illisible : jamais bloquer
                if not re.search(rf"\b{re.escape(h)}\b", base):
                    sans_preuve.append((h, phrase.strip()[:120]))
    if not sans_preuve:
        return 0

    marqueur.write_text("1", encoding="utf-8")
    detail = "\n".join(f"  - « {h} » dans : {p}" for h, p in sans_preuve)
    sys.stderr.write(
        "=== AFFIRMATION SANS SOURCE ===\n"
        "Tu viens d'attribuer un hébergement à l'utilisateur, et aucun de ses messages ni aucun "
        "résultat d'outil de cette conversation ne le dit :\n"
        f"{detail}\n\n"
        "La réponse est DÉJÀ affichée. Publier UNE phrase : lire la source (CLAUDE.md du "
        "projet, wrangler.jsonc, deploy.sh…) puis corriger, ou écrire « je n'ai pas "
        "trouvé cette info ». Rien d'autre.\n"
        "=== FIN ===\n"
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
