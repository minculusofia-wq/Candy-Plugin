#!/bin/bash
#
# Les deux rappels d'ouverture de session : ils parlent quand il y a lieu, se
# taisent sinon, et rendent un JSON que Claude Code sait lire.
#
#   · taille-claude-md.sh : un CLAUDE.md au-delà de 200 lignes est signalé ;
#   · rappel-projet.sh : la tâche inscrite pour un projet s'affiche à son
#     ouverture, et seulement là.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
TAILLE="$RACINE/hooks/taille-claude-md.sh"
RAPPEL="$RACINE/hooks/rappel-projet.sh"
BAC=$(mktemp -d)
trap 'rm -rf "$BAC"' EXIT

# sortie <hook> <projet> [VAR=valeur...] — ce que le hook écrit sur la sortie normale
sortie() { local h="$1" p="$2"; shift 2; printf '{"source":"startup"}' | env CLAUDE_PROJECT_DIR="$p" "$@" bash "$h" 2>/dev/null; }
# message <json> — le systemMessage, vide si le JSON est absent ou invalide
message() { python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except ValueError: sys.exit(0)
if d.get("hookSpecificOutput", {}).get("hookEventName") == "SessionStart": print(d.get("systemMessage", ""))'; }
lignes() { python3 -c 'import sys; print("\n".join("ligne %d" % i for i in range(int(sys.argv[1]))))' "$1"; }

# --- CLAUDE.md trop long ------------------------------------------------------
mkdir -p "$BAC/long" "$BAC/juste" "$BAC/cache/.claude" "$BAC/vide"
lignes 201 > "$BAC/long/CLAUDE.md"
lignes 200 > "$BAC/juste/CLAUDE.md"
lignes 250 > "$BAC/cache/.claude/CLAUDE.md"

section "CLAUDE.md trop long — une ligne, rien de plus"
verifie "201 lignes : signalé, avec le compte" \
        1 "$(sortie "$TAILLE" "$BAC/long" | message | grep -c 'CLAUDE.md : 201 lignes')"
verifie "200 lignes pile : silence" \
        0 "$(sortie "$TAILLE" "$BAC/juste" | grep -c .)"
verifie ".claude/CLAUDE.md compte aussi" \
        1 "$(sortie "$TAILLE" "$BAC/cache" | message | grep -c '.claude/CLAUDE.md : 250 lignes')"
verifie "pas de CLAUDE.md : silence et sortie 0" \
        "0 0" "$(sortie "$TAILLE" "$BAC/vide" | grep -c .) $(printf '{}' | CLAUDE_PROJECT_DIR="$BAC/vide" bash "$TAILLE" >/dev/null 2>&1; echo $?)"

# --- Rappel de projet ---------------------------------------------------------
mkdir -p "$BAC/app/src" "$BAC/autre" "$BAC/phases"
printf '### Phase 1 — Base 🟢\n### Phase 2 — Suite\n' > "$BAC/phases/ROADMAP.md"
LISTE="$BAC/rappels.txt"
cat > "$LISTE" <<EOF
# un commentaire | ne compte pas | - |
$BAC/app | ranger la documentation | ~/notes/consigne.md |
$BAC/phases | ouvrir la phase 3 | - | ROADMAP.md::^### Phase 2.*🟢
$BAC/phases | relire la phase 1 | - | ROADMAP.md::^### Phase 1.*🟢
EOF

section "Rappel de projet — au bon endroit, au bon moment"
verifie "le projet inscrit reçoit sa tâche" \
        1 "$(sortie "$RAPPEL" "$BAC/app" RAPPELS_PROJETS="$LISTE" | message | grep -c 'En attente sur ce projet : ranger la documentation')"
verifie "un sous-dossier du projet aussi" \
        1 "$(sortie "$RAPPEL" "$BAC/app/src" RAPPELS_PROJETS="$LISTE" | message | grep -c 'ranger la documentation')"
verifie "un autre projet : silence" \
        0 "$(sortie "$RAPPEL" "$BAC/autre" RAPPELS_PROJETS="$LISTE" | grep -c .)"
verifie "condition non remplie (phase 2 pas verte) : pas de rappel" \
        0 "$(sortie "$RAPPEL" "$BAC/phases" RAPPELS_PROJETS="$LISTE" | message | grep -c 'ouvrir la phase 3')"
verifie "condition remplie (phase 1 verte) : le rappel s'affiche" \
        1 "$(sortie "$RAPPEL" "$BAC/phases" RAPPELS_PROJETS="$LISTE" | message | grep -c 'relire la phase 1')"
verifie "une ligne de commentaire n'est jamais un rappel" \
        0 "$(sortie "$RAPPEL" "$BAC/app" RAPPELS_PROJETS="$LISTE" | grep -c 'ne compte pas')"
verifie "pas de liste : silence et sortie 0" \
        "0 0" "$(sortie "$RAPPEL" "$BAC/app" RAPPELS_PROJETS="$BAC/absente.txt" | grep -c .) $(printf '{}' | CLAUDE_PROJECT_DIR="$BAC/app" RAPPELS_PROJETS="$BAC/absente.txt" bash "$RAPPEL" >/dev/null 2>&1; echo $?)"
verifie "Claude reçoit la tâche et où lire le détail" \
        1 "$(sortie "$RAPPEL" "$BAC/app" RAPPELS_PROJETS="$LISTE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' | grep -c 'Détail : ~/notes/consigne.md')"

bilan
