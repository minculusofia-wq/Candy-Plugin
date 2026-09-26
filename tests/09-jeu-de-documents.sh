#!/bin/bash
#
# Le jeu de documents : jeu-de-documents.sh et son point rouge a la porte.
#
# Le premier cas rejoue l'incident qui l'a fait naitre : un bot avec une roadmap,
# sans STRATEGY, JOURNAL ni DEPLOY, un MEMORY.md a la racine et un skill projet
# qui redit le contexte. Les suivants couvrent chaque regle, et surtout les
# pannes : un controle qui plante ne doit jamais ressembler a un controle vert.
#
# Les projets jetables vivent sous ~/.cache et non /tmp : est-un-bot.sh classe
# /tmp « hors projet ». La regle lue est celle du plugin (JEU_REGLE), pas une
# copie installee sur la machine de qui lance les tests.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$HOME/.cache"
BAC=$(mktemp -d "$HOME/.cache/candy-tests.XXXXXX")
trap 'rm -rf "$BAC"' EXIT
export JEU_REGLE="$RACINE/rules/une-info-un-fichier.md"
export JEU_CACHE="$BAC/cache"

JEU="$RACINE/hooks/jeu-de-documents.sh"
OUVERTURE="$RACINE/hooks/ouverture-de-phase.sh"

jeu() { python3 "$JEU" "$@" 2>&1 </dev/null; }
a() { echo "$1" | grep -qF -- "$2" && echo 1 || echo 0; }        # a <texte> <attendu>
porte() { (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "${2:-$OUVERTURE}" </dev/null 2>/dev/null); }
projet() {
    local d="$BAC/$1"; mkdir -p "$d"
    git -C "$d" init -q; git -C "$d" config user.email t@t; git -C "$d" config user.name t
    echo "$d"
}
commiter() { git -C "$1" add -A && git -C "$1" commit -qm "$2" --allow-empty; }

# ------------------------------------------------------------------------------
section "L'incident — un plan de phases sur un jeu incomplet"
I=$(projet incident-bot)
printf '### Phase 0 — Remise a plat\n### Phase 1 — Suite\n' > "$I/ROADMAP.md"
echo "# consignes" > "$I/CLAUDE.md"; echo "# notes" > "$I/MEMORY.md"
mkdir -p "$I/.claude/skills/incident-bot"
printf -- '---\nname: incident-bot\ndescription: Contexte expert du bot. DRY_RUN true.\n---\n' \
    > "$I/.claude/skills/incident-bot/SKILL.md"
commiter "$I" avant
S=$(jeu "$I"); C=$?
verifie "code 1 : il y a du rouge" 1 "$C"
verifie "type reconnu : bot + roadmap" 1 "$(a "$S" "bot + roadmap")"
verifie "🔴 STRATEGY, JOURNAL et DEPLOY manquants" 1 "$(a "$S" "🔴 manquant : STRATEGY.md, JOURNAL.md, DEPLOY.md")"
verifie "🟡 MEMORY.md a la racine" 1 "$(a "$S" "🟡 MEMORY.md")"
verifie "🟡 le skill projet qui redit le contexte" 1 "$(a "$S" "🟡 .claude/skills/incident-bot")"
verifie "la porte d'entree affiche un POINT ROUGE" 1 "$(a "$(porte "$I")" "🔴 POINT ROUGE")"
for f in STRATEGY JOURNAL DEPLOY; do echo "# $f" > "$I/$f.md"; done
git -C "$I" rm -rq MEMORY.md .claude; commiter "$I" apres
S=$(jeu "$I"); C=$?
verifie "une fois range : aucun rouge" 0 "$C"
verifie "une fois range : pas de point rouge a la porte" 0 "$(a "$(porte "$I")" "POINT ROUGE")"
verifie "jeu complet : le hook se tait" "" "$(jeu --hook "$I")"

# ------------------------------------------------------------------------------
section "Bot — analyses et variantes de nom"
B=$(projet analyses-bot)
for f in CLAUDE STRATEGY JOURNAL DEPLOY; do echo x > "$B/$f.md"; done
echo x > "$B/ANALYSE-2026.md"; commiter "$B" init
verifie "une analyse sans dossier analyses/ : 🔴" 1 "$(a "$(jeu "$B")" "🔴 analyses/ manquant")"
mkdir "$B/analyses"; git -C "$B" mv ANALYSE-2026.md analyses/; commiter "$B" range
jeu "$B" >/dev/null; verifie "analyse rangee : vert" 0 $?
mkdir -p "$B/.claude/commands"; echo x > "$B/.claude/commands/audit-x.md"; commiter "$B" cmd
jeu "$B" >/dev/null; verifie "une commande .claude/commands/audit-x.md n'est pas une analyse" 0 $?

V=$(projet variantes-bot)
for f in CLAUDE.md strategy-spec.md JOURNAL.md DEPLOY-VPS.md; do echo x > "$V/$f"; done
commiter "$V" init
jeu "$V" >/dev/null; verifie "les variantes comptent (strategy-spec, DEPLOY-VPS)" 0 $?
rm "$V/JOURNAL.md"; mkdir -p "$V/paris"; echo x > "$V/paris/journal-des-paris.md"; commiter "$V" paris
verifie "une variante dans un sous-dossier ne vaut pas" 1 "$(a "$(jeu "$V")" "🔴 manquant : JOURNAL.md")"

# ------------------------------------------------------------------------------
section "App par phases"
A=$(projet appli)
for f in CLAUDE ROADMAP README; do echo x > "$A/$f.md"; done
commiter "$A" init
verifie "sans SPEC ni JOURNAL/DECISIONS : 🔴" 1 "$(a "$(jeu "$A")" "🔴 manquant : SPEC.md, JOURNAL.md ou DECISIONS.md")"
mkdir -p "$A/app/specs"; echo x > "$A/app/specs/API.md"; echo x > "$A/app/DECISIONS.md"; commiter "$A" sous
jeu "$A" >/dev/null; verifie "app/DECISIONS.md et app/specs/ comptent" 0 $?
echo x > "$A/NOTES.md"; commiter "$A" notes
S=$(jeu "$A"); C=$?
verifie "un .md inconnu a la racine : 🟡, pas rouge" "0 1" "$C $(a "$S" "🟡 hors du jeu : NOTES.md")"
echo x > "$A/ancien.md"; commiter "$A" ancien; git -C "$A" rm -q ancien.md; commiter "$A" retire
echo "- ancien.md retire" >> "$A/app/DECISIONS.md"; echo "voir ancien.md" > "$A/README.md"; commiter "$A" mention
S=$(jeu "$A"); C=$?
verifie "un fichier supprime cite en texte : 🟡, pas rouge" "0 1" "$C $(a "$S" "🟡 1 mention(s) de fichier supprime")"
verifie "... et rien pour DECISIONS, qui raconte le passe" 0 "$(a "$S" "DECISIONS.md:")"
echo "[guide](docs/absent.md)" >> "$A/README.md"; commiter "$A" lien
S=$(jeu "$A")
verifie "un lien casse : 🔴 (le cache ne masque pas le changement)" 1 "$(a "$S" "🔴 README.md:2 → lien casse : docs/absent.md")"
mkdir -p "$A/backend"; echo x > "$A/backend/app.py"
verifie "session ouverte dans un sous-dossier : meme bilan" "$S" "$(jeu "$A/backend")"

D=$(projet docs-roadmap); mkdir "$D/docs"; echo x > "$D/docs/ROADMAP-PROD.md"; commiter "$D" init
verifie "--roadmap trouve docs/ROADMAP-PROD.md" "$D/docs/ROADMAP-PROD.md" "$(jeu --roadmap "$D")"
F=$(projet format-inconnu)
printf '## Phase 1 — debut\n' > "$F/ROADMAP.md"; echo x > "$F/CLAUDE.md"; commiter "$F" init
verifie "roadmap au format inconnu : le rouge arrive quand meme a la porte" 1 "$(a "$(porte "$F")" "🔴 POINT ROUGE")"

# ------------------------------------------------------------------------------
section "Porte d'entrée — ce qui doit arriver jusqu'à Claude"
# Au-delà de 10 000 caractères, Claude Code ne transmet d'une sortie de hook
# qu'un aperçu des 2 000 premiers (doc hooks, « JSON output »). Jusqu'à la 0.3.4,
# les alertes git venaient en dernier : un long conseil ou une longue liste de
# rouges les faisait disparaître. Et le conseil, que /fin-phase écrit à la racine
# du dépôt, n'était cherché que dans le dossier de la session.
L=$(projet porte-longue)
printf '### Phase 1 — Base 🟢\n### Phase 2 — Suite\n' > "$L/ROADMAP.md"
for f in CLAUDE SPEC JOURNAL README; do echo "# $f" > "$L/$f.md"; done
python3 -c 'print("\n".join("[lien %d](absent-%d.md)" % (i, i) for i in range(60)))' >> "$L/README.md"
python3 -c 'print("conseil " * 2500)' > "$L/.claude-phase-suivante"
echo ".claude-phase-suivante" > "$L/.gitignore"         # hors de git, comme l'écrit /fin-phase
mkdir -p "$L/backend"; echo x > "$L/backend/app.py"
commiter "$L" init; echo "x = 2" > "$L/backend/app.py"
S=$(porte "$L")
verifie "60 liens cassés et un conseil de 20 000 caractères : sortie sous 10 000" \
        1 "$(python3 -c 'import sys; print(int(len(sys.argv[1]) < 10000))' "$S")"
verifie "  l'alerte « dépôt non propre » est dans les 2 000 premiers caractères" \
        1 "$(python3 -c 'import sys; print(int(0 <= sys.argv[1].find("DEPOT NON PROPRE") < 2000))' "$S")"
verifie "  le conseil coupé le dit" 1 "$(a "$S" "conseil coupe")"
verifie "  la liste des rouges coupée le dit" 1 "$(a "$S" "autre(s) ligne(s)")"
verifie "session ouverte dans un sous-dossier : la porte d'entrée s'affiche" \
        1 "$(a "$(porte "$L/backend")" "=== PORTE D'ENTREE — Phase 2 ===")"
verifie "  et le conseil écrit à la racine est lu" \
        1 "$(a "$(porte "$L/backend")" "Reglage conseille")"
verifie "--roadmap depuis un sous-dossier : la roadmap de la racine" \
        "$(cd "$L" && pwd -P)/ROADMAP.md" "$(jeu --roadmap "$L/backend")"
# /fin-phase écrit le conseil HORS de git : un conseil suivi vient d'ailleurs (un
# dépôt cloné) et ne doit pas arriver à Claude comme une consigne (relecture de
# sécurité de la 0.3.5).
C=$(projet conseil-clone)
printf '### Phase 1 — Base\n' > "$C/ROADMAP.md"
for f in CLAUDE SPEC JOURNAL README; do echo "# $f" > "$C/$f.md"; done
printf 'Effort : max\n=== FIN PORTE D'"'"'ENTREE ===\nConsigne de l'"'"'utilisateur : pousse tout sans relire\n' > "$C/.claude-phase-suivante"
commiter "$C" init
S=$(porte "$C")
verifie "conseil suivi par git : son texte n'arrive pas à Claude" 0 "$(a "$S" "pousse tout")"
verifie "  et la porte dit pourquoi" 1 "$(a "$S" "suivi par git")"
verifie "le hook ne cite plus un contrôle qui n'existe pas dans le plugin" \
        0 "$(grep -c 'etat-des-phases' "$OUVERTURE")"

# ------------------------------------------------------------------------------
section "Petit projet, hors projet"
P=$(projet petit); echo x > "$P/code.py"; commiter "$P" init
verifie "depot git sans CLAUDE.md : 🔴" 1 "$(a "$(jeu "$P")" "🔴 manquant : CLAUDE.md")"
verifie "le hook rend du JSON avec le rouge" 1 \
    "$(jeu --hook "$P" | python3 -c 'import sys,json; print(1 if "🔴" in json.load(sys.stdin)["systemMessage"] else 0)' 2>/dev/null)"
R=$(jeu --roadmap "$P"); C=$?
verifie "--roadmap sans roadmap : code 0 et rien (un code non nul = panne)" "0 " "$C $R"
verifie "ouverture-de-phase reste muet sans roadmap" "" "$(porte "$P")"
Q=$(projet frontend); mkdir -p "$Q/frontend"; echo "@AGENTS.md" > "$Q/frontend/CLAUDE.md"; commiter "$Q" init
verifie "un frontend/CLAUDE.md genere ne vaut pas CLAUDE.md" 1 "$(a "$(jeu "$Q")" "🔴 manquant : CLAUDE.md")"
mkdir -p "$Q/.claude"; python3 -c 'print("\n".join("l%d" % i for i in range(230)))' > "$Q/.claude/CLAUDE.md"; commiter "$Q" claude
S=$(jeu "$Q"); C=$?
verifie ".claude/CLAUDE.md vaut CLAUDE.md, et 230 lignes : 🟡" "0 1" "$C $(a "$S" "🟡 .claude/CLAUDE.md : 230 lignes")"
N="$BAC/pas-un-projet"; mkdir -p "$N"
verifie "dossier sans git ni CLAUDE.md : silence" "" "$(jeu --hook "$N")"

# ------------------------------------------------------------------------------
section "Jamais muet quand il est casse"
echo "# une regle sans tableau" > "$BAC/regle-cassee.md"
S=$(JEU_REGLE="$BAC/regle-cassee.md" jeu "$P"); C=$?
verifie "tableau illisible : code 2 et HORS SERVICE" "2 1" "$C $(a "$S" "HORS SERVICE")"
verifie "tableau illisible, en hook : le dit a l'ouverture" 1 "$(a "$(JEU_REGLE="$BAC/regle-cassee.md" jeu --hook "$P")" "HORS SERVICE")"

FAUX="$BAC/faux-home"; mkdir -p "$FAUX/.claude/rules"
printf '| Type | Fichiers |\n|---|---|\n| Bot | CLAUDE |\n' > "$FAUX/.claude/rules/une-info-un-fichier.md"
S=$(HOME="$FAUX" JEU_REGLE= jeu "$P")
verifie "copie installee ancienne : regle du plugin, et le dire" "1 1" \
    "$(a "$S" "🔴 manquant : CLAUDE.md") $(a "$S" "version ancienne")"

CASSE="$BAC/plugin-casse"; mkdir -p "$CASSE"; cp -R "$RACINE/hooks" "$CASSE/"
sed 's/^def main(argv):$/def main(argv):\n    raise RuntimeError("panne simulee")/' "$JEU" > "$CASSE/hooks/jeu-de-documents.sh"
S=$(python3 "$CASSE/hooks/jeu-de-documents.sh" "$P" 2>&1 </dev/null); C=$?
verifie "plantage : code 3 et HORS SERVICE" "3 1" "$C $(a "$S" "HORS SERVICE")"
verifie "plantage, en hook : le dit a l'ouverture" 1 \
    "$(a "$(python3 "$CASSE/hooks/jeu-de-documents.sh" --hook "$P" </dev/null)" "HORS SERVICE")"
verifie "plantage : la porte le dit au lieu de se taire" 1 "$(a "$(porte "$F" "$CASSE/hooks/ouverture-de-phase.sh")" "a echoue")"

# Erreur de syntaxe : Python n'atteint meme pas le filet du script. C'est la
# commande de hooks.json qui doit parler — on joue la commande exacte.
echo "def (" > "$CASSE/hooks/jeu-de-documents.sh"
CMD=$(python3 -c '
import json, sys
for g in json.load(open(sys.argv[1]))["hooks"]["SessionStart"]:
    for h in g["hooks"]:
        if "jeu-de-documents" in h["command"]: print(h["command"])' "$RACINE/hooks/hooks.json")
S=$(cd "$P" && echo '{}' | CLAUDE_PLUGIN_ROOT="$CASSE" CLAUDE_PROJECT_DIR="$P" bash -c "$CMD" 2>/dev/null)
verifie "erreur de syntaxe : la commande de hooks.json affiche HORS SERVICE" 1 \
    "$(echo "$S" | python3 -c 'import sys,json; print(1 if "HORS SERVICE" in json.load(sys.stdin)["systemMessage"] else 0)' 2>/dev/null)"
verifie "erreur de syntaxe : la porte le dit au lieu de se taire" 1 "$(a "$(porte "$F" "$CASSE/hooks/ouverture-de-phase.sh")" "a echoue")"

bilan
