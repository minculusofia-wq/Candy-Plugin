#!/bin/bash
#
# taille-claude-md.sh — appele par jeu-de-documents.sh, qui tourne au
# SessionStart (startup, resume, clear) et fond ce message dans son bilan :
# deux messages d'ouverture sur les memes documents, c'etait un de trop.
#
# Une ligne d'avertissement quand le CLAUDE.md du projet depasse 200 lignes.
# Ne bloque rien, ne corrige rien.
#
# Pourquoi 200 : c'est la cible de la doc officielle de Claude Code
# (code.claude.com/docs/en/memory.md, paragraphe « Size ») — au-dela, le fichier
# coute plus de contexte et ses consignes sont moins bien suivies. La regle
# rules/une-info-un-fichier.md dit ou ranger le surplus.
#
# Sortie JSON : `systemMessage` s'affiche pour l'utilisateur, `additionalContext`
# arrive dans le contexte de Claude (hooks.md, « JSON output » et « SessionStart
# decision control »). Construite avec python3 : pas de jq, absent par defaut
# sur les anciens macOS.
#

set -u

cat >/dev/null 2>&1 || true

PROJET="${CLAUDE_PROJECT_DIR:-$PWD}"
LIMITE=200

TROP=""
for FICHIER in "$PROJET/CLAUDE.md" "$PROJET/.claude/CLAUDE.md"; do
    [ -f "$FICHIER" ] || continue
    NB=$(wc -l < "$FICHIER" | tr -d ' ')
    [ "$NB" -gt "$LIMITE" ] || continue
    TROP="${TROP:+$TROP, }${FICHIER#"$PROJET/"} : $NB lignes"
done

[ -n "$TROP" ] || exit 0

LIGNE="⚠️ $TROP — la doc officielle vise moins de $LIMITE lignes par CLAUDE.md. Le surplus se range selon la règle « une information, un seul fichier » (rules/une-info-un-fichier.md)."

python3 -I -c 'import json, sys
m = sys.argv[1]
print(json.dumps({"systemMessage": m,
                  "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": m}},
                 ensure_ascii=True))' "$LIGNE"
exit 0
