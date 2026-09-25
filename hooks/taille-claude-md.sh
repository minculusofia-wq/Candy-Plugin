#!/bin/bash
#
# taille-claude-md.sh — appele par jeu-de-documents.sh, qui tourne au
# SessionStart (startup, resume, clear) et fond ce message dans son bilan :
# deux messages d'ouverture sur les memes documents, c'etait un de trop.
#
# Une ligne d'avertissement quand le CLAUDE.md du projet depasse 200 lignes,
# ou 25 000 octets. Ne bloque rien, ne corrige rien.
#
# Pourquoi 200 : c'est la cible de la doc officielle de Claude Code
# (code.claude.com/docs/en/memory.md, paragraphe « Size ») — au-dela, le fichier
# coute plus de contexte et ses consignes sont moins bien suivies. La regle
# rules/une-info-un-fichier.md dit ou ranger le surplus.
#
# Pourquoi 25 000 octets : c'est un CHOIX de ce plugin, pas une regle de la doc
# pour CLAUDE.md. Jusqu'a la 0.3.4, seules les lignes comptaient : 150 lignes
# de 500 caracteres (75 Ko) passaient sans alerte. Le seuil reprend celui que la
# doc fixe pour MEMORY.md (memory.md, « 200 lines or 25KB »).
#
# Sortie JSON : `systemMessage` s'affiche pour l'utilisateur, `additionalContext`
# arrive dans le contexte de Claude (hooks.md, « JSON output » et « SessionStart
# decision control »). Construite avec python3 : pas de jq, qui n'est pas
# garanti sur toutes les machines.
#

set -u

cat >/dev/null 2>&1 || true

PROJET="${CLAUDE_PROJECT_DIR:-$PWD}"
LIMITE=200
LIMITE_OCTETS=25000

TROP=""
for FICHIER in "$PROJET/CLAUDE.md" "$PROJET/.claude/CLAUDE.md"; do
    [ -f "$FICHIER" ] || continue
    NB=$(wc -l < "$FICHIER" | tr -d ' ')
    OCTETS=$(wc -c < "$FICHIER" | tr -d ' ')
    [ "$NB" -gt "$LIMITE" ] || [ "$OCTETS" -gt "$LIMITE_OCTETS" ] || continue
    TROP="${TROP:+$TROP, }${FICHIER#"$PROJET/"} : $NB lignes, $((OCTETS / 1000)) Ko"
done

[ -n "$TROP" ] || exit 0

LIGNE="⚠️ $TROP — la doc officielle vise moins de $LIMITE lignes par CLAUDE.md, et ce plugin alerte aussi au-delà de $((LIMITE_OCTETS / 1000)) Ko. Le surplus se range selon la règle « une information, un seul fichier » (rules/une-info-un-fichier.md)."

python3 -I -c 'import json, sys
m = sys.argv[1]
print(json.dumps({"systemMessage": m,
                  "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": m}},
                 ensure_ascii=True))' "$LIGNE"
exit 0
