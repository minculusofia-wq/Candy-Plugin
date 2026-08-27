#!/bin/bash
#
# Le contrôle du setup : chaque panne visée doit être vue, et ce qui est
# légitime ne doit pas être signalé.
#
# Trois défauts d'origine, tous corrigés ici et gardés comme cas :
#   · un outil appelé par une commande passait pour un hook orphelin, parce que
#     seul settings.json était consulté ;
#   · le compteur d'alertes était incrémenté dans un sous-processus : la valeur
#     se perdait en sortant et le bilan annonçait moins de points qu'affiché ;
#   · un seul dossier de mémoires était lu alors qu'il y en a un PAR PROJET —
#     sur le poste d'origine, 45 mémoires sur 55 étaient ignorées.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
CONTROLE="$RACINE/hooks/verifier-setup.sh"
COMPTEUR="$RACINE/hooks/compter-relectures.py"
BAC=$(mktemp -d)
trap 'rm -rf "$BAC"' EXIT

# --- Un setup vierge, comme celui d'un nouvel utilisateur --------------------
VIERGE="$BAC/vierge"
mkdir -p "$VIERGE/hooks" "$VIERGE/skills" "$VIERGE/rules"
echo '{}' > "$VIERGE/settings.json"
SORTIE=$(bash "$CONTROLE" "$VIERGE" 2>&1)

section "Setup vierge — rien d'inventé"
verifie "aucun skill : le contrôle passe" \
        1 "$(echo "$SORTIE" | grep -c '0 skill(s), tous chargeables')"
verifie "aucune mémoire : rien à vérifier, pas une alerte" \
        1 "$(echo "$SORTIE" | grep -c 'aucun dossier de mémoires')"
verifie "l'absence de dépôt est un avertissement, pas une erreur" \
        1 "$(echo "$SORTIE" | grep -c 'pas un dépôt git')"
verifie "le bilan ne compte que ce point-là" \
        1 "$(echo "$SORTIE" | grep -c '1 point(s) à regarder')"

# --- Un setup avec chaque panne exactement une fois --------------------------
CASSE="$BAC/casse"
mkdir -p "$CASSE/hooks" "$CASSE/commands" "$CASSE/rules" \
         "$CASSE/skills/sans-skill-md" "$CASSE/skills/trop-profond/interne" \
         "$CASSE/projects/-projet-A/memory" "$CASSE/projects/-projet-B/memory"

# settings.json ne déclare qu'un seul des trois scripts
cat > "$CASSE/settings.json" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/branche.sh"}]}]}}
JSON
echo 'exit 0' > "$CASSE/hooks/branche.sh"
echo 'exit 0' > "$CASSE/hooks/appele-par-commande.sh"
echo 'exit 0' > "$CASSE/hooks/vraiment-orphelin.sh"
echo 'Lancer hooks/appele-par-commande.sh avant de finir.' > "$CASSE/commands/une-commande.md"

# skills : un fichier à la racine, un dossier vide, un SKILL.md trop profond
echo '# pas un skill' > "$CASSE/skills/a-la-racine.md"
echo '# rien' > "$CASSE/skills/sans-skill-md/NOTES.md"
echo '# enfoui' > "$CASSE/skills/trop-profond/interne/SKILL.md"

# mémoires : une échéance passée, une à venir, dans deux projets différents
printf -- '---\nname: a\n---\n\nReste à faire, prévu le 2020-01-01 : tester le truc.\n' \
    > "$CASSE/projects/-projet-A/memory/echue.md"
printf -- '---\nname: b\n---\n\nReste à faire, prévu le 2099-12-31 : rien ne presse.\n' \
    > "$CASSE/projects/-projet-B/memory/a-venir.md"

# duplication : une phrase longue partagée règle / hook, une phrase courte non
PHRASE="ne jamais annoncer un travail termine sans avoir montre la sortie reelle du controle"
printf '# Regle\n\n%s\n\nTrop court pour compter.\n' "$PHRASE" > "$CASSE/rules/une-regle.md"
printf 'echo "%s"\necho "Trop court pour compter."\n' "$PHRASE" >> "$CASSE/hooks/branche.sh"

SORTIE=$(bash "$CONTROLE" "$CASSE" 2>&1)

section "Hooks — branché, appelé, ou vraiment orphelin"
verifie "un script vraiment orphelin est signalé" \
        1 "$(echo "$SORTIE" | grep -c 'vraiment-orphelin.sh')"
verifie "un script appelé par une commande ne l'est PAS" \
        0 "$(echo "$SORTIE" | grep -c 'appele-par-commande.sh')"
verifie "un script branché dans settings.json ne l'est pas non plus" \
        0 "$(echo "$SORTIE" | grep -c 'hooks/branche.sh')"

section "Skills — les trois façons de ne jamais être chargé"
verifie "un .md à la racine de skills/ est signalé" \
        1 "$(echo "$SORTIE" | grep -c 'a-la-racine.md')"
verifie "un dossier sans SKILL.md est signalé" \
        1 "$(echo "$SORTIE" | grep -c 'sans-skill-md')"
verifie "un SKILL.md trop profond est signalé comme tel" \
        1 "$(echo "$SORTIE" | grep -c 'trop profond')"

section "Mémoires — tous les projets, pas seulement le premier"
verifie "une échéance dépassée est signalée" \
        1 "$(echo "$SORTIE" | grep -c 'echue.md:5 → échéance 2020-01-01 dépassée')"
verifie "une échéance à venir ne l'est pas" \
        0 "$(echo "$SORTIE" | grep -c 'a-venir.md')"
verifie "les deux projets sont examinés" \
        1 "$(echo "$SORTIE" | grep -c '2 projet(s)')"

section "Duplication — sur la longueur qui compte"
verifie "une phrase longue partagée règle/hook est signalée" \
        1 "$(echo "$SORTIE" | grep -c 'une-regle.md')"
verifie "une phrase courte ne l'est pas" \
        0 "$(echo "$SORTIE" | grep -c 'Trop court pour compter')"

section "Bilan — il compte ce qu'il affiche"
# Cinq points : orphelin, trois skills, échéance, duplication, absence de dépôt.
# Le compteur se perdait dans les sous-processus : le bilan annonçait moins.
AFFICHES=$(echo "$SORTIE" | grep -cE '^  (✗|⚠) ')
COMPTES=$(echo "$SORTIE" | sed -n 's/^  \([0-9]*\) point(s).*/\1/p')
verifie "autant de points comptés que de lignes affichées" "$AFFICHES" "$COMPTES"
bash "$CONTROLE" "$CASSE" >/dev/null 2>&1
verifie "des problèmes trouvés donnent une sortie non nulle" 1 $?

section "Comptage des relectures — le grep se comptait lui-même"
JS="$BAC/projects/-projet/session.jsonl"
mkdir -p "$(dirname "$JS")"
python3 - "$JS" <<'PYFIX'
import json, sys
vraie = ("Stop hook feedback:\n[relire-ma-reponse.sh]: === RELECTURE ===\n"
         "  - supposition(s) interdite(s) par la regle « ne rien inventer » : "
         "« probablement ».\n=== FIN RELECTURE ===")
# Le piege : une sortie de commande qui CONTIENT le marqueur sans etre une
# correction. Un grep sur le fichier la compterait comme une violation.
bruit = "=== RELECTURE ===\n  - supposition(s) interdite(s) par la regle « ne rien inventer »"
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write(json.dumps({"type": "user", "isMeta": True, "sessionId": "s1",
                        "message": {"role": "user", "content": vraie}}) + "\n")
    f.write(json.dumps({"type": "user", "isMeta": False, "sessionId": "s1",
                        "message": {"role": "user", "content": bruit}}) + "\n")
    f.write(json.dumps({"type": "assistant", "sessionId": "s1",
                        "message": {"role": "assistant", "content": bruit}}) + "\n")
PYFIX
CPT=$(python3 "$COMPTEUR" 0 "$BAC/projects" 2>&1)
verifie "une vraie correction est comptée" \
        1 "$(echo "$CPT" | grep -c '^1 correction')"
verifie "  la règle en cause est nommée" \
        1 "$(echo "$CPT" | grep -c 'ne rien inventer')"
verifie "un simple grep en aurait compté trois" \
        3 "$(grep -c 'RELECTURE' "$JS")"
verifie "un dossier sans transcription ne fait pas planter" \
        0 "$(python3 "$COMPTEUR" 0 "$BAC/absent" >/dev/null 2>&1; echo $?)"

section "Le dépôt du plugin sort propre"
bash "$CONTROLE" "$VIERGE" >/dev/null 2>&1
verifie "un setup vierge ne rend que l'avertissement de dépôt" 1 $?

bilan
