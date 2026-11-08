#!/bin/bash
#
# Le hook Stop affirmation-sans-source : il refuse une phrase qui attribue à
# l'utilisateur un hébergement (« tes sites passent par Vercel ») quand ni un de
# ses messages ni un résultat d'outil de la conversation ne nomme cet hébergeur.
#
# Faute d'origine : « tes sites passent par Vercel » et « tes bots tournent sur
# un serveur à toi », écrits sans aucune source. relire-ma-reponse ne l'avait
# pas vue : la phrase ne contenait aucune formule d'hésitation.
# Chaque cas tourne sur une transcription jetable.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$RACINE/hooks/affirmation-sans-source.py"
BAC=$(mktemp -d)
trap 'rm -rf "$BAC"' EXIT
export TMPDIR="$BAC"

# essai <id> <réponse> <message utilisateur> <résultat d'outil> → code du hook
essai() {
    python3 -I -c '
import json, sys
id_, reponse, user, outil, chemin = sys.argv[1:6]
with open(chemin, "w", encoding="utf-8") as f:
    f.write(json.dumps({"type": "user", "message": {"role": "user", "content": user}}) + "\n")
    if outil:
        f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [
            {"type": "tool_result", "tool_use_id": "x", "content": outil}]}}) + "\n")
    f.write(json.dumps({"type": "assistant", "message": {"role": "assistant",
            "content": [{"type": "text", "text": reponse}]}}) + "\n")
print(json.dumps({"last_assistant_message": reponse, "transcript_path": chemin, "prompt_id": id_}))
' "$1" "$2" "$3" "$4" "$BAC/t-$1.jsonl" | python3 -I "$HOOK" >/dev/null 2>"$BAC/stderr"
    echo $?
}

section "Affirmation d'hébergement sans source"
verifie "tes sites passent par un hébergeur jamais cité : refusé" 2 \
    "$(essai a1 'Tes sites passent par Vercel.' 'regarde la doc' '')"
verifie "tes bots tournent sur un serveur jamais cité : refusé" 2 \
    "$(essai a2 'Tes bots tournent sur un serveur à toi.' 'ok' '')"
verifie "hébergeur cité seulement dans la réponse de Claude : refusé" 2 \
    "$(essai a3 'Vercel est gratuit. Tes sites passent par Vercel.' 'ok' '')"
verifie "le refus nomme l'hébergeur fautif" 0 \
    "$(grep -c -i 'vercel' "$BAC/stderr" | awk '{print ($1 > 0) ? 0 : 1}')"

section "Affirmation établie ou hors sujet"
verifie "hébergeur dit par l'utilisateur : accepté" 0 \
    "$(essai b1 'Tes sites tournent sur Cloudflare Workers.' 'on a 2 sites sur cloudflare' '')"
verifie "hébergeur lu dans un résultat d'outil : accepté" 0 \
    "$(essai b2 'Ton site de liste tourne sur un VPS.' 'regarde' 'Hébergement : VPS avec Caddy')"
verifie "phrase citée entre guillemets : acceptée" 0 \
    "$(essai b3 'J'"'"'avais écrit « tes sites passent par Vercel » : faux.' 'ok' '')"
verifie "hébergeur cité sans possessif : accepté" 0 \
    "$(essai b4 'Vercel propose un plan gratuit.' 'ok' '')"
verifie "réponse sans rapport : acceptée" 0 \
    "$(essai b5 'Le test est vert.' 'ok' '')"

section "Garde-fous du hook lui-même"
verifie "un seul refus par message (le second passe)" 0 \
    "$(essai a1 'Tes sites passent par Vercel.' 'regarde la doc' '')"
verifie "transcription illisible : jamais bloquer" 0 \
    "$(printf '%s' '{"last_assistant_message":"Tes bots tournent sur un serveur.","transcript_path":"/inexistant","prompt_id":"z"}' | python3 -I "$HOOK" >/dev/null 2>&1; echo $?)"
verifie "entrée qui n'est pas du JSON : jamais bloquer" 0 \
    "$(printf 'pas du json' | python3 -I "$HOOK" >/dev/null 2>&1; echo $?)"

bilan
