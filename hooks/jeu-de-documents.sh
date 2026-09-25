#!/usr/bin/env python3
#
# jeu-de-documents.py — le projet a-t-il le jeu de documents que la regle attend ?
#
# Pourquoi ce controle existe
# ---------------------------
# Sur un bot de trading, Claude a ecrit une roadmap en 6 phases puis dit deux
# fois « tu peux demarrer la phase 0 » alors que STRATEGY, JOURNAL et DEPLOY
# manquaient, qu'un MEMORY.md trainait a la racine et que le skill projet, charge
# automatiquement, annoncait un mode simulation sur un bot qui tradait en reel.
# Les regles existaient et etaient chargees ; elles n'etaient appliquees que si
# Claude y pensait. C'est l'utilisateur qui a du demander « on a tous les .md ? ».
#
# Ce script rend le point mecanique. Il ne corrige rien : il dit ce qui manque
# (ROUGE) et ce qui est hors du jeu (JAUNE).
#
# Une information, un fichier : le jeu attendu vit dans le tableau de la regle
# une-info-un-fichier.md, que ce script LIT — la copie installee dans
# ~/.claude/rules/ si elle existe, sinon celle du plugin. Aucune liste de
# fichiers attendus n'est ecrite ici. Les chemins de la roadmap, eux, vivent ICI
# et nulle part ailleurs : ouverture-de-phase.sh les demande avec --roadmap.
#
# Il reutilise, sans les recopier (meme dossier que lui) :
#   - est-un-bot.sh           : bot ou pas, et « hors-projet » ;
#   - session-end-md-audit.sh : liens casses, fichiers supprimes, statuts ;
#   - taille-claude-md.sh     : CLAUDE.md au-dela de 200 lignes.
#
# Python, sous une extension .sh comme relire-ma-reponse.sh : hooks.json le lance
# avec python3.
#
# Usage :
#   jeu-de-documents.sh [DOSSIER]            rapport lisible ; code 1 si rouge
#   jeu-de-documents.sh --rouges [DOSSIER]   seulement les lignes rouges
#   jeu-de-documents.sh --hook               SessionStart : JSON, silence si rien
#   jeu-de-documents.sh --roadmap [DOSSIER]  chemin de la roadmap, ou rien ; code 0
# Code 2 : le tableau de la regle est illisible. Code 3 : plantage. Jamais un
# silence : en --hook, les deux sortent en message.
#

import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import date

HOOKS = os.path.dirname(os.path.abspath(__file__))
REGLE_PLUGIN = os.path.join(os.path.dirname(HOOKS), "rules", "une-info-un-fichier.md")
REGLE_INSTALLEE = os.path.expanduser("~/.claude/rules/une-info-un-fichier.md")
REGLE = os.environ.get("JEU_REGLE") or (
    REGLE_INSTALLEE if os.path.isfile(REGLE_INSTALLEE) else REGLE_PLUGIN)
# Une copie installee avant ce controle a l'ancien tableau, illisible : on se
# rabat alors sur la regle du plugin et on le dit, plutot que d'afficher
# « hors service » a chaque ouverture de session.
AVIS_REGLE = []
# Hors de ~/.claude : ce dossier est souvent sous git, un cache y laisserait des
# fichiers non commites a chaque session.
CACHE = os.environ.get("JEU_CACHE") or os.path.join(os.path.expanduser("~/.cache"), "claude-jeu-de-documents")

# Ces deux-la ne comptent qu'a la racine du projet (ou .claude/CLAUDE.md) : un
# frontend/CLAUDE.md genere par Next.js (« @AGENTS.md ») ou un frontend/README.md
# ne sont pas les documents du projet. Voir la regle, « Un nom compte… ».
A_LA_RACINE = {"claude", "readme"}

# Les deux conventions rencontrees : ROADMAP.md a la racine, ou dans docs/.
# ouverture-de-phase.sh les lit ici.
ROADMAP_CHEMINS = ["ROADMAP.md", "docs/ROADMAP-PROD.md", "docs/ROADMAP.md"]

# Dossiers jamais fouilles : dependances, builds, historique.
# .claude/ aussi : ses commandes et skills ne sont pas des documents du projet
# (une commande « audit-x.md » passerait pour une analyse egaree).
IGNORES = {".claude", "node_modules", ".venv", "venv", ".git", "archives", "build", "dist",
           ".next", "__pycache__", ".pytest_cache", ".mypy_cache"}

# Un .md dont le nom dit « analyse » ou « audit » est une analyse.
MOT_ANALYSE = re.compile(r"analy|audit", re.I)

# Debut du nom de ligne dans le tableau (« Bot ou service qui tourne »).
TYPES = {"bot": "Bot", "app": "App par phases", "petit": "Petit projet"}


class TableauIllisible(Exception):
    pass


# --------------------------------------------------------------- la regle ---
def lire_tableau():
    """La regle choisie ; si c'est une copie installee illisible, celle du plugin."""
    try:
        return lire_tableau_de(REGLE)
    except TableauIllisible:
        if REGLE == REGLE_INSTALLEE and os.path.isfile(REGLE_PLUGIN) \
                and not os.environ.get("JEU_REGLE"):
            jeu = lire_tableau_de(REGLE_PLUGIN)
            AVIS_REGLE.append("~/.claude/rules/une-info-un-fichier.md est d'une version "
                              "ancienne, sans le tableau que ce controle lit : la recopier "
                              "depuis rules/ du plugin")
            return jeu
        raise


def lire_tableau_de(regle):
    """{type: (obligatoires, facultatifs)}. Un obligatoire est une liste
    d'alternatives (« JOURNAL ou DECISIONS »). Un nom finissant par / est un
    dossier."""
    try:
        texte = open(regle, encoding="utf-8").read()
    except OSError as e:
        raise TableauIllisible(f"{regle} introuvable ({e.strerror})")

    def elements(cellule):
        sortie = []
        for morceau in cellule.split(","):
            alternatives = [a.strip().strip("`").strip() for a in re.split(r"\bou\b", morceau)]
            alternatives = [a for a in alternatives if a]
            if alternatives:
                sortie.append(alternatives)
        return sortie

    jeu = {}
    for ligne in texte.splitlines():
        cellules = [c.strip() for c in ligne.strip().strip("|").split("|")]
        if len(cellules) != 3:
            continue
        for cle, nom in TYPES.items():
            if cellules[0] == nom or cellules[0].startswith(nom + " "):
                jeu[cle] = (elements(cellules[1]), [a for g in elements(cellules[2]) for a in g])
    manquants = [TYPES[c] for c in TYPES if c not in jeu]
    if manquants:
        raise TableauIllisible(
            f"le tableau de {regle} n'a pas de ligne pour : "
            + ", ".join(manquants))
    for cle, (obl, _) in jeu.items():
        if not obl:
            raise TableauIllisible(f"ligne « {TYPES[cle]} » sans fichier obligatoire")
    return jeu


# ---------------------------------------------------------------- le projet ---
def trouver_roadmap(projet):
    for rel in ROADMAP_CHEMINS:
        if os.path.isfile(os.path.join(projet, rel)):
            return rel
    return None


def est_un_bot(projet):
    """(bot?, raison). Reutilise est-un-bot.sh — la detection n'est pas recopiee."""
    try:
        r = subprocess.run(["bash", os.path.join(HOOKS, "est-un-bot.sh"), "--raison", projet],
                           capture_output=True, text=True, timeout=15)
        return r.returncode == 0, r.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return False, "erreur"


def est_un_projet(projet, raison):
    if raison == "hors-projet":
        return False
    if os.path.isfile(os.path.join(projet, "CLAUDE.md")):
        return True
    r = subprocess.run(["git", "-C", projet, "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True)
    return r.returncode == 0


def correspond(nom_fichier, element):
    """STRATEGY accepte STRATEGY.md, strategy-spec.md, STRATEGY_v2.md."""
    if not nom_fichier.lower().endswith(".md"):
        return False
    tige = nom_fichier[:-3].lower()
    e = element.lower()
    return tige == e or re.match(re.escape(e) + r"[-_. ]", tige) is not None


def md_du_niveau(dossier):
    try:
        return sorted(f for f in os.listdir(dossier)
                      if f.lower().endswith(".md") and os.path.isfile(os.path.join(dossier, f)))
    except OSError:
        return []


def parcourir(projet, profondeur_max=4):
    """Tous les .md du projet, hors dossiers ignores : chemins relatifs."""
    sortie = []
    base = projet.rstrip("/").count(os.sep)
    for racine, dossiers, fichiers in os.walk(projet):
        dossiers[:] = [d for d in dossiers if d not in IGNORES]
        if racine.count(os.sep) - base >= profondeur_max:
            dossiers[:] = []
        for f in fichiers:
            if f.lower().endswith(".md"):
                sortie.append(os.path.relpath(os.path.join(racine, f), projet))
    return sortie


def skills_du_projet(projet):
    """Skills du projet qui decrivent le projet lui-meme : une seconde copie du
    contexte, chargee automatiquement, que personne ne tient a jour. Celui de
    l'incident ne partageait que 2 lignes sur 110 avec CLAUDE.md — une
    comparaison de texte l'aurait rate. On le reconnait a ce qu'il se presente
    comme le projet : son nom, son dossier."""
    dossier = os.path.join(projet, ".claude", "skills")
    nom_projet = os.path.basename(projet.rstrip("/"))
    compact = re.sub(r"[^a-z0-9]", "", nom_projet.lower())
    trouves = []
    try:
        entrees = sorted(os.listdir(dossier))
    except OSError:
        return trouves
    for e in entrees:
        skill = os.path.join(dossier, e, "SKILL.md")
        if not os.path.isfile(skill):
            continue
        try:
            tete = open(skill, encoding="utf-8", errors="replace").read(3000)
        except OSError:
            continue
        m = re.search(r"^---\s*$(.*?)^---\s*$", tete, re.S | re.M)
        entete = m.group(1) if m else ""
        nom = re.search(r"^name:\s*(.+)$", entete, re.M)
        desc = re.search(r"^description:\s*(.+)$", entete, re.M)
        nom = nom.group(1).strip() if nom else e
        desc = desc.group(1) if desc else ""
        if (len(compact) >= 4 and compact in re.sub(r"[^a-z0-9]", "", nom.lower())) \
                or nom_projet in desc or re.sub(r"[^a-z0-9]", "", e.lower()) == compact:
            trouves.append(f".claude/skills/{e}")
    return trouves


# --------------------------------------------------- les controles reutilises ---
def cle_audit(projet, tous_md):
    """Ce dont depend l'audit : l'historique git, l'etat du depot, les .md."""
    def git(*a):
        r = subprocess.run(["git", "-C", projet, *a], capture_output=True, text=True)
        return r.stdout
    h = hashlib.sha256()
    h.update(git("rev-parse", "HEAD").encode())
    h.update(git("status", "--porcelain").encode())
    for f in sorted(tous_md):
        try:
            st = os.stat(os.path.join(projet, f))
            h.update(f"{f}:{st.st_mtime_ns}:{st.st_size}\n".encode())
        except OSError:
            pass
    h.update(open(os.path.join(HOOKS, "session-end-md-audit.sh"), "rb").read())
    h.update(date.today().isoformat().encode())  # le controle des dates en depend
    return h.hexdigest()


def audit_md(projet, tous_md):
    """(lignes rouges, nombre de jaunes) de session-end-md-audit.sh.

    Mis en cache : l'audit a coute ~9 s sur un projet de 63 .md et 48 fichiers
    supprimes dans l'historique — trop pour chaque ouverture de session. Le cache n'est reutilise que si ni git, ni les .md, ni l'audit
    lui-meme, ni la date n'ont bouge."""
    cache = os.path.join(CACHE, hashlib.sha256(projet.encode()).hexdigest()[:16] + ".json")
    cle = cle_audit(projet, tous_md)
    try:
        memo = json.load(open(cache, encoding="utf-8"))
        if memo.get("cle") == cle:
            return memo["rouges"], memo["jaunes"]
    except (OSError, ValueError, KeyError):
        pass
    try:
        r = subprocess.run(["bash", os.path.join(HOOKS, "session-end-md-audit.sh"), projet],
                           capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        # Une lenteur n'est pas un defaut de documents : jaune, jamais rouge.
        return [], ["audit .md interrompu apres 30 s — le lancer a la main"]
    except OSError as e:
        return [], [f"audit .md impossible ({e.strerror})"]
    # Seules les lignes qui COMMENCENT par le symbole : le bilan de l'audit
    # contient aussi « Les ✗ rouges sont des erreurs », qui n'en est pas une.
    croix = [l.strip()[1:].strip() for l in r.stdout.splitlines() if l.strip().startswith("✗")]
    # Rouge de porte = une preuve : le lien casse. La « mention d'un fichier
    # supprime » cherche le chemin comme un bout de texte — la suppression d'un
    # README.md racine rend suspecte toute mention de README.md, meme d'un autre
    # dossier (vu sur un vrai projet : une table de clonage). Un indice ne
    # bloque pas une phase : jaune.
    rouges = [c for c in croix if "lien casse" in c]
    mentions = [c for c in croix if "lien casse" not in c]
    jaunes = []
    if mentions:
        jaunes.append(f"{len(mentions)} mention(s) de fichier supprime a verifier : "
                      + " ; ".join(mentions[:3]) + (" ; …" if len(mentions) > 3 else ""))
    nb = sum(1 for l in r.stdout.splitlines() if l.strip().startswith("⚠"))
    if nb:
        jaunes.append(f"{nb} date(s) ou statut(s) a verifier — detail : "
                      f"bash {os.path.join(HOOKS, 'session-end-md-audit.sh')} \"{projet}\"")
    try:
        os.makedirs(CACHE, exist_ok=True)
        json.dump({"cle": cle, "rouges": rouges, "jaunes": jaunes},
                  open(cache, "w", encoding="utf-8"), ensure_ascii=False)
    except OSError:
        pass
    return rouges, jaunes


def taille_claude_md(projet):
    try:
        env = dict(os.environ, CLAUDE_PROJECT_DIR=projet)
        r = subprocess.run(["bash", os.path.join(HOOKS, "taille-claude-md.sh")], input="",
                           capture_output=True, text=True, timeout=10, env=env)
        if r.stdout.strip():
            return json.loads(r.stdout)["systemMessage"].lstrip("⚠️ ").strip()
    except (OSError, subprocess.SubprocessError, ValueError, KeyError):
        pass
    return None


# ------------------------------------------------------------------ bilan ---
def racine_du_projet(dossier):
    """Une session ouverte dans backend/ ou docs/ examine le projet entier : sans
    ca, un bot complet ouvert dans backend/ sortait « CLAUDE, STRATEGY,
    JOURNAL, DEPLOY manquants »."""
    r = subprocess.run(["git", "-C", dossier, "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else dossier


def examiner(projet, jeu):
    projet = racine_du_projet(os.path.abspath(projet))
    bot, raison = est_un_bot(projet)
    if not est_un_projet(projet, raison):
        return None
    roadmap = trouver_roadmap(projet)
    alerte_detection = raison in ("erreur", "")

    if bot:
        obligatoires = list(jeu["bot"][0])
        facultatifs = list(jeu["bot"][1])
        if roadmap:
            obligatoires.append(["ROADMAP"])
        genre = "bot + roadmap" if roadmap else "bot"
    elif roadmap:
        obligatoires, facultatifs = list(jeu["app"][0]), list(jeu["app"][1])
        genre = "app par phases"
    else:
        obligatoires, facultatifs = list(jeu["petit"][0]), list(jeu["petit"][1])
        genre = "petit projet"

    racine_md = md_du_niveau(projet)
    tous_md = parcourir(projet)

    # Un obligatoire se cherche a la racine et un niveau en dessous : docs/, ou
    # le sous-projet d'un depot a plusieurs dossiers (app/DECISIONS.md,
    # app/specs/). Les exiger a la racine bloquerait une porte d'entree pour une
    # question de rangement, pas de contenu.
    # Variantes de nom (strategy-spec.md) : a la racine et dans docs/ seulement.
    # Ailleurs un niveau en dessous, le nom exact : sinon un
    # « paris/journal-des-paris.md » (un autre journal) validait le JOURNAL du
    # bot — faux vert vu sur un vrai projet.
    presents = [os.path.basename(f) for f in tous_md
                if f.count(os.sep) == 0 or (f.count(os.sep) == 1 and f.lower().startswith("docs" + os.sep))]
    exacts = [os.path.basename(f) for f in tous_md if f.count(os.sep) == 1
              and not f.lower().startswith("docs" + os.sep)]
    dossiers = set()
    for f in tous_md:
        parties = f.split(os.sep)[:-1]
        for p in parties[:2]:
            dossiers.add(p.lower())
    a_la_racine = list(racine_md)
    if os.path.isfile(os.path.join(projet, ".claude", "CLAUDE.md")):
        a_la_racine.append("CLAUDE.md")

    rouges, jaunes = [], list(AVIS_REGLE)
    if alerte_detection:
        jaunes.append("est-un-bot.sh n'a pas repondu : projet controle comme non-bot, "
                      "le type est peut-etre faux")

    manquants = []
    for alternatives in obligatoires:
        fichiers = [a for a in alternatives if not a.endswith("/")]
        if not fichiers:
            continue
        ou = a_la_racine if all(a.lower() in A_LA_RACINE for a in fichiers) else presents + a_la_racine
        # Un dossier du meme nom compte aussi : specs/ contient la SPEC.
        if any(correspond(p, a) for p in ou for a in fichiers) \
                or (ou is not a_la_racine
                    and (any(p.lower() == a.lower() + ".md" for p in exacts for a in fichiers)
                         or any(a.lower() in dossiers or a.lower() + "s" in dossiers for a in fichiers))):
            continue
        manquants.append(" ou ".join(f"{a}.md" for a in fichiers))
    if manquants:
        rouges.append("manquant : " + ", ".join(manquants))
    connus = [a for g in obligatoires for a in g] + facultatifs
    connus_fichiers = [a for a in connus if not a.endswith("/")]

    # Hors du jeu a la racine (MEMORY.md a son propre message plus bas ; une
    # analyse aussi, quand le jeu a un dossier analyses/).
    range_analyses = "analyses/" in connus
    hors = [f for f in racine_md
            if f.upper() != "MEMORY.MD"
            and not any(correspond(f, a) for a in connus_fichiers)
            and not (range_analyses and MOT_ANALYSE.search(f))]
    if hors:
        jaunes.append("hors du jeu : " + ", ".join(hors))

    memoires = [f for f in tous_md if os.path.basename(f).upper() == "MEMORY.MD"]
    if memoires:
        jaunes.append(", ".join(memoires) + " : la memoire automatique suffit, son contenu "
                      "va dans le fichier du jeu qui porte son sujet")

    for s in skills_du_projet(projet):
        jaunes.append(f"{s} : skill projet qui redit le contexte du projet, charge a chaque "
                      "session et tenu a jour par personne — son contenu va dans le jeu")

    # Les analyses. `analyses/` n'est exige qu'une fois une analyse ecrite.
    if range_analyses:
        dossier_analyses = os.path.isdir(os.path.join(projet, "analyses"))
        egarees = [f for f in tous_md
                   if MOT_ANALYSE.search(os.path.basename(f))
                   and not f.startswith("analyses" + os.sep)]
        if egarees and not dossier_analyses:
            rouges.append("analyses/ manquant alors que des analyses existent : " + ", ".join(egarees))
        elif egarees:
            jaunes.append("analyse(s) hors de analyses/ : " + ", ".join(egarees))

    audit_rouges, audit_jaunes = audit_md(projet, tous_md)
    rouges += audit_rouges
    jaunes += audit_jaunes

    taille = taille_claude_md(projet)
    if taille:
        jaunes.append(taille)

    return {"genre": genre, "roadmap": roadmap, "rouges": rouges, "jaunes": jaunes}


def rapport(b):
    lignes = [f"=== JEU DE DOCUMENTS — {b['genre']} ==="]
    lignes += [f"🔴 {r}" for r in b["rouges"]]
    lignes += [f"🟡 {j}" for j in b["jaunes"]]
    if not b["rouges"] and not b["jaunes"]:
        lignes.append("🟢 jeu complet, rien hors du jeu")
    lignes.append("Regle : ~/.claude/rules/une-info-un-fichier.md")
    return "\n".join(lignes)


# ------------------------------------------------------------------- main ---
def main(argv):
    mode = "rapport"
    args = []
    for a in argv:
        if a in ("--hook", "--rouges", "--roadmap"):
            mode = a[2:]
        else:
            args.append(a)
    projet = args[0] if args else os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())

    if mode == "roadmap":
        # Code 0 dans les deux cas, chemin ou rien : un code non nul veut dire
        # PANNE et rien d'autre. « Pas de roadmap » en 1 se confondait avec un
        # plantage de Python — et ouverture-de-phase.sh se taisait sur les deux.
        # A la racine du depot, comme le bilan : depuis backend/, rien n'etait
        # trouve et la porte d'entree se taisait (jusqu'a la 0.3.4).
        projet = racine_du_projet(os.path.abspath(projet))
        rel = trouver_roadmap(projet)
        if rel:
            print(os.path.join(projet, rel))
        return 0

    if mode == "hook":
        try:
            sys.stdin.read()
        except (OSError, ValueError):
            pass

    try:
        jeu = lire_tableau()
    except TableauIllisible as e:
        message = f"⚠️ Controle du jeu de documents HORS SERVICE : {e}."
        if mode == "hook":
            print(json.dumps({"systemMessage": message, "hookSpecificOutput": {
                "hookEventName": "SessionStart", "additionalContext": message}}, ensure_ascii=True))
            return 0
        print(message, file=sys.stderr)
        return 2

    b = examiner(projet, jeu)
    if b is None:
        return 0

    if mode == "rouges":
        for r in b["rouges"]:
            print(r)
        return 1 if b["rouges"] else 0

    if mode == "hook":
        if not b["rouges"] and not b["jaunes"]:
            return 0
        resume = f"Jeu de documents ({b['genre']}) : "
        morceaux = []
        if b["rouges"]:
            morceaux.append(f"🔴 {len(b['rouges'])} rouge(s) — {b['rouges'][0]}")
        if b["jaunes"]:
            morceaux.append(f"🟡 {len(b['jaunes'])} a ranger")
        contexte = rapport(b) + (
            "\n\nUn ROUGE interdit de livrer un plan de phases et d'ouvrir une phase tant "
            "qu'il n'est pas corrige, dans cette conversation (porte-de-phase.md). "
            "Un JAUNE se range avant tout plan de phases (une-info-un-fichier.md, "
            "« Exception »). Ranger, deplacer ou retirer un fichier est une decision "
            "technique : la prendre, a la corbeille plutot qu'en suppression, et "
            "l'annoncer en une ligne (communication-style.md).")
        print(json.dumps({"systemMessage": resume + " · ".join(morceaux),
                          "hookSpecificOutput": {"hookEventName": "SessionStart",
                                                 "additionalContext": contexte}},
                         ensure_ascii=True))
        return 0

    print(rapport(b))
    return 1 if b["rouges"] else 0


if __name__ == "__main__":
    # Un controle qui plante ne doit jamais ressembler a un controle vert.
    # Code 3, et en hook un message visible. (Une erreur de syntaxe echappe a
    # ce filet : le branchement dans settings.json a son propre « || echo ».)
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # noqa: BLE001 — tout plantage doit se voir
        message = f"⚠️ Controle du jeu de documents HORS SERVICE : plantage ({type(e).__name__}: {e})."
        if "--hook" in sys.argv:
            print(json.dumps({"systemMessage": message, "hookSpecificOutput": {
                "hookEventName": "SessionStart", "additionalContext": message}}, ensure_ascii=True))
            sys.exit(0)
        print(message, file=sys.stderr)
        sys.exit(3)
