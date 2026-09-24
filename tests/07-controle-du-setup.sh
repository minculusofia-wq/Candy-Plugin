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
        0 "$(echo "$SORTIE" | grep -c "branche.sh n'est ni branché")"

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
# Six points : orphelin, hook muet (branche.sh écrit en fin de tour avec le
# code 0), trois skills, échéance, duplication, absence de dépôt.
# Le compteur se perdait dans les sous-processus : le bilan annonçait moins.
AFFICHES=$(echo "$SORTIE" | grep -cE '^  (✗|⚠) ')
COMPTES=$(echo "$SORTIE" | sed -n 's/^  \([0-9]*\) point(s).*/\1/p')
verifie "autant de points comptés que de lignes affichées" "$AFFICHES" "$COMPTES"
bash "$CONTROLE" "$CASSE" >/dev/null 2>&1
verifie "des problèmes trouvés donnent une sortie non nulle" 1 $?

# --- Hooks entendus, skills synchronisés, date dans un nom de fichier --------
ENTENDU="$BAC/entendu"
mkdir -p "$ENTENDU/hooks" "$ENTENDU/rules" "$ENTENDU/skills/synced/abc/pdf" \
         "$ENTENDU/projects/-projet-C/memory"
cat > "$ENTENDU/settings.json" <<'JSON'
{"hooks":{
 "Stop":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/muet-fin-de-tour.sh"},
                   {"type":"command","command":"python3 ~/.claude/hooks/relecture.py"}]}],
 "PreToolUse":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/bloque.sh"},
                         {"type":"command","command":"bash ~/.claude/hooks/rend-du-json.sh"},
                         {"type":"command","command":"bash ~/.claude/hooks/teste-seulement.sh"},
                         {"type":"command","command":"bash ~/.claude/hooks/stdout-seulement.sh"},
                         {"type":"command","command":"bash ~/.claude/hooks/code-un.sh"}]}],
 "PostToolUse":[{"hooks":[{"type":"command","command":"bash \"$HOME/.claude/hooks/guillemets.sh\""},
                          {"type":"command","command":"bash ${HOME}/.claude/hooks/accolades.sh"},
                          {"type":"command","command":"bash __ENTENDU__/.claude/hooks/chemin-complet.sh"},
                          {"type":"command","command":"bash __AILLEURS__/.claude/hooks/ailleurs.sh"},
                          {"type":"command","command":"bash ~/.claude/hooks/json-et-texte.sh"},
                          {"type":"command","command":"bash ~/.claude/hooks/json-en-variable.sh"},
                          {"type":"command","command":"bash ~/.claude/hooks/avertit-et-refuse.sh"},
                          {"type":"command","command":"bash -c 'cat | python3 -I ~/.claude/hooks/sans-shebang.py'"}]}],
 "UserPromptSubmit":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/ajoute-du-contexte.sh"}]}]}}
JSON
# Un chemin complet est lu à ce chemin-là : c'est ce fichier qui tourne.
mkdir -p "$ENTENDU/.claude/hooks" "$BAC/ailleurs/.claude/hooks"
sed -i.bak -e "s#__ENTENDU__#$ENTENDU#" -e "s#__AILLEURS__#$BAC/ailleurs#" "$ENTENDU/settings.json"
for f in guillemets accolades; do
    printf 'echo "Personne ne lira ceci."\nexit 0\n' > "$ENTENDU/hooks/$f.sh"
done
printf 'echo "Personne ne lira ceci."\nexit 0\n' > "$ENTENDU/.claude/hooks/chemin-complet.sh"
printf 'echo "Personne ne lira ceci."\nexit 0\n' > "$BAC/ailleurs/.claude/hooks/ailleurs.sh"
printf 'if [ -n "$X" ]; then echo '"'"'{"systemMessage": "x"}'"'"'; exit 0; fi\necho "Attention, fichier sensible."\nexit 0\n' \
    > "$ENTENDU/hooks/json-et-texte.sh"
printf 'OUT='"'"'{"systemMessage": "x"}'"'"'\necho "$OUT"\nexit 0\n' > "$ENTENDU/hooks/json-en-variable.sh"
printf 'if [ -n "$X" ]; then echo "Refus." >&2; exit 2; fi\necho "Attention, fichier sensible."\nexit 0\n' \
    > "$ENTENDU/hooks/avertit-et-refuse.sh"
printf 'print("Rappel que personne ne lira.")\n' > "$ENTENDU/hooks/sans-shebang.py"
printf 'echo "Pensez a commiter." >&2\nexit 0\n'            > "$ENTENDU/hooks/muet-fin-de-tour.sh"
printf 'echo "Bloque : raison." >&2\nexit 2\n'              > "$ENTENDU/hooks/bloque.sh"
printf "echo '{\"systemMessage\": \"attention\"}'\nexit 0\n" > "$ENTENDU/hooks/rend-du-json.sh"
printf 'if echo "$X" | grep -q a; then exit 0; fi\nexit 0\n'  > "$ENTENDU/hooks/teste-seulement.sh"
printf 'echo "Rappel pour Claude."\nexit 0\n'                > "$ENTENDU/hooks/ajoute-du-contexte.sh"
printf 'echo "BLOCKED : raison."\nexit 2\n'                > "$ENTENDU/hooks/stdout-seulement.sh"
printf '# Bloque le push si les tests echouent.\necho "Tests en echec." >&2\nexit 1\n' \
    > "$ENTENDU/hooks/code-un.sh"
printf '#!/usr/bin/env python3\nimport sys\ndef main():\n    sys.stderr.write("corrige\\n")\n    return 2\nsys.exit(main())\n' \
    > "$ENTENDU/hooks/relecture.py"
printf -- '---\nname: s\n---\n# skill synchronisé\n' > "$ENTENDU/skills/synced/abc/pdf/SKILL.md"
printf -- '---\nname: c\n---\n\nPrévue en xhigh, faite en max (analyse-2020-01-01.md:12).\n' \
    > "$ENTENDU/projects/-projet-C/memory/precedent.md"
SORTIE_E=$(bash "$CONTROLE" "$ENTENDU" 2>&1)

section "Hooks entendus — branché ne veut pas dire entendu"
verifie "un hook de fin de tour qui écrit avec le code 0 est signalé muet" \
        1 "$(echo "$SORTIE_E" | grep -c 'muet-fin-de-tour.sh (Stop) : ses messages sortent avec le code 0')"
verifie "un hook qui bloque (sortie 2) ne l'est pas" \
        0 "$(echo "$SORTIE_E" | grep -c 'bloque.sh')"
verifie "un hook qui rend du JSON ne l'est pas" \
        0 "$(echo "$SORTIE_E" | grep -c 'rend-du-json.sh')"
verifie "un echo qui sert de test (echo | grep) n'est pas une sortie" \
        0 "$(echo "$SORTIE_E" | grep -c 'teste-seulement.sh')"
verifie "un message normal à l'envoi d'un prompt arrive bien à Claude" \
        0 "$(echo "$SORTIE_E" | grep -c 'ajoute-du-contexte.sh')"
verifie "un script python qui renvoie 2 par return est entendu" \
        0 "$(echo "$SORTIE_E" | grep -c 'relecture.py')"
verifie "un hook qui bloque avec sa raison sur stdout est signalé (la raison se lit sur stderr)" \
        1 "$(echo "$SORTIE_E" | grep -c 'stdout-seulement.sh (PreToolUse) : sort en code d.erreur avec ses messages sur stdout')"
verifie "un hook qui parle de bloquer mais sort en code 1 est signalé (il laisse passer)" \
        1 "$(echo "$SORTIE_E" | grep -c 'code-un.sh (PreToolUse) : parle de bloquer mais ne sort jamais en code 2')"
verifie "un settings.json sans hook : rien à signaler" \
        1 "$(bash "$CONTROLE" "$VIERGE" 2>&1 | grep -c '0 branchement(s), aucun hook ne parle dans le vide')"

# Seul « ~/.claude/hooks/… » sans guillemets était reconnu : le même hook muet,
# branché autrement, passait le contrôle.
for f in guillemets accolades chemin-complet; do
    verifie "un hook muet branché par un autre chemin ($f) est signalé" \
            1 "$(echo "$SORTIE_E" | grep -c "$f.sh (PostToolUse) : ses messages sortent avec le code 0")"
done
verifie "un script python sans en-tête, lancé par « python3 -I », est lu comme du python" \
        1 "$(echo "$SORTIE_E" | grep -c 'sans-shebang.py (PostToolUse) : ses messages sortent avec le code 0')"
# Bloquer dans un cas suffisait à rendre tout le hook « entendu » : c'est ainsi
# que l'avertissement « fichier sensible » de pre-edit-guard est resté muet.
verifie "un hook qui bloque ailleurs mais avertit en texte simple est signalé" \
        1 "$(echo "$SORTIE_E" | grep -c 'avertit-et-refuse.sh (PostToolUse) : une partie de ses messages sort en texte simple')"
verifie "un chemin complet vers un autre dossier : c'est ce fichier-là qui est lu" \
        1 "$(echo "$SORTIE_E" | grep -c "$BAC/ailleurs/.claude/hooks/ailleurs.sh (PostToolUse) : ses messages sortent avec le code 0")"
# Un JSON écrit quelque part rendait tout le fichier « entendu ».
verifie "un hook qui rend du JSON dans un cas mais du texte simple dans l'autre est signalé" \
        1 "$(echo "$SORTIE_E" | grep -c 'json-et-texte.sh (PostToolUse) : une partie de ses messages sort en texte simple')"
verifie "un JSON rangé dans une variable puis écrit n'est pas du texte simple" \
        0 "$(echo "$SORTIE_E" | grep -c 'json-en-variable.sh')"

section "Hooks entendus — les formes courantes, dans les deux sens"
# Seconde relecture de la 0.3.4 : des hooks légitimes (stderr écrit en groupe,
# sur deux lignes, fonction dont on capture la valeur) étaient signalés à
# tort, et des messages perdus (|| echo, printf '%s', cat <<EOF, print sur
# plusieurs lignes, echo sans guillemets) passaient.
FINS="$BAC/fins"
mkdir -p "$FINS/hooks"
cat > "$FINS/settings.json" <<'JSON'
{"hooks":{"PostToolUse":[{"hooks":[
 {"type":"command","command":"bash ~/.claude/hooks/groupe-stderr.sh"},
 {"type":"command","command":"python3 -I ~/.claude/hooks/py-stderr-deux-lignes.py"},
 {"type":"command","command":"bash ~/.claude/hooks/suite-de-ligne.sh"},
 {"type":"command","command":"bash ~/.claude/hooks/fonction-capturee.sh"},
 {"type":"command","command":"bash ~/.claude/hooks/ou-echo.sh"},
 {"type":"command","command":"bash ~/.claude/hooks/printf-format.sh"},
 {"type":"command","command":"bash ~/.claude/hooks/cat-heredoc.sh"},
 {"type":"command","command":"python3 -I ~/.claude/hooks/print-deux-lignes.py"},
 {"type":"command","command":"bash ~/.claude/hooks/echo-nu.sh"},
 {"type":"command","command":"bash \"$HOME\"/.claude/hooks/guillemets-fermes.sh"},
 {"type":"command","command":"bash \"${HOME}\"/.claude/hooks/accolades-fermees.sh"}]}]}}
JSON
JSONAILLEURS='if [ -n "$X" ]; then echo '"'"'{"systemMessage": "x"}'"'"'; exit 0; fi'
printf 'if [ -n "$X" ]; then\n  {\n    echo "Refus : raison."\n    echo "Detail."\n  } >&2\n  exit 2\nfi\nexit 0\n' \
    > "$FINS/hooks/groupe-stderr.sh"
printf 'import sys\nif len(sys.argv) > 5:\n    print("Refus : une raison longue, sur deux lignes.",\n          file=sys.stderr)\n    sys.exit(2)\n' \
    > "$FINS/hooks/py-stderr-deux-lignes.py"
printf 'if [ -n "$X" ]; then\n  echo "Refus : raison." \\\n    >&2\n  exit 2\nfi\n' > "$FINS/hooks/suite-de-ligne.sh"
printf 'chemin() {\n  echo "$1/config"\n}\nC=$(chemin /tmp)\nif [ ! -f "$C" ]; then echo "Absent." >&2; exit 2; fi\n' \
    > "$FINS/hooks/fonction-capturee.sh"
printf 'test -f /nulle-part || echo "Fichier absent."\nexit 0\n' > "$FINS/hooks/ou-echo.sh"
printf '%s\nprintf '"'"'%%s\\n'"'"' "Attention, texte perdu."\n' "$JSONAILLEURS" > "$FINS/hooks/printf-format.sh"
printf '%s\ncat <<EOF\nAttention, texte perdu.\nEOF\n' "$JSONAILLEURS" > "$FINS/hooks/cat-heredoc.sh"
printf 'import json, sys\nif len(sys.argv) > 5:\n    print(json.dumps({"systemMessage": "x"}))\nprint(\n    "Attention, texte perdu."\n)\n' \
    > "$FINS/hooks/print-deux-lignes.py"
printf '%s\necho Attention texte perdu\n' "$JSONAILLEURS" > "$FINS/hooks/echo-nu.sh"
printf 'echo "Personne ne lira ceci."\nexit 0\n' > "$FINS/hooks/guillemets-fermes.sh"
printf 'echo "Personne ne lira ceci."\nexit 0\n' > "$FINS/hooks/accolades-fermees.sh"
SORTIE_FINS=$(bash "$CONTROLE" "$FINS" 2>&1)
for f in groupe-stderr.sh py-stderr-deux-lignes.py suite-de-ligne.sh fonction-capturee.sh; do
    verifie "hook légitime, pas signalé : $f" 0 "$(echo "$SORTIE_FINS" | grep -c "$f")"
done
verifie "« cmd || echo » est une sortie : signalé" \
        1 "$(echo "$SORTIE_FINS" | grep -c 'ou-echo.sh (PostToolUse) : ses messages sortent avec le code 0')"
for f in printf-format.sh cat-heredoc.sh print-deux-lignes.py echo-nu.sh; do
    verifie "texte perdu malgré un JSON ailleurs, signalé : $f" \
            1 "$(echo "$SORTIE_FINS" | grep -c "$f (PostToolUse) : une partie de ses messages sort en texte simple")"
done
for f in guillemets-fermes.sh accolades-fermees.sh; do
    verifie "« \"\$HOME\"/… » entre guillemets fermés avant la barre : $f signalé" \
            1 "$(echo "$SORTIE_FINS" | grep -c "$f (PostToolUse) : ses messages sortent avec le code 0")"
done

section "Hooks entendus — troisième relecture : oublis et fausses alertes"
TROIS="$BAC/trois"
mkdir -p "$TROIS/hooks"
python3 -I - "$TROIS" <<'PY'
import json, os, sys
d = sys.argv[1]
perdu = 'echo "Attention, texte perdu."'
refus_py = 'if len(sys.argv) > 5:\n    print("Refus.", file=sys.stderr)\n    sys.exit(2)\n'
triple = "'" * 3
hooks = {
    # doivent être signalés
    "py-commentaire.py": 'import sys\nx = 1  # (voir la doc\nprint("Attention, texte perdu.")\n' + refus_py,
    "py-triple-chaine.py": 'import sys\ns = "' + triple + '"\nprint("Attention, texte perdu.")\n' + refus_py,
    "py-echappe.py": 'import sys\ns = "il a dit \\"(\\""\nprint("Attention, texte perdu.")\n' + refus_py,
    "fonction-capturee-et-appelee.sh": 'msg() { ' + perdu + '; }\nX=$(msg)\nmsg\nexit 0\n',
    "groupe-2-devnull.sh": '{\n  ' + perdu + '\n} 2>/dev/null\nexit 0\n',
    "decalage.sh": 'N=$((1<<n))\n' + perdu + '\nexit 0\n',
    "heredoc-en-chaine.sh": 'X="cat <<FIN"\n' + perdu + '\nexit 0\n',
    "fonction-mixte.sh": 'log() {\n  echo "$1"\n}\nif [ -n "$X" ]; then log "Refus." >&2; exit 2; fi\nlog "Attention."\nexit 0\n',
    "appel-dans-if.sh": 'verifie() { ' + perdu + '; }\nif verifie; then :; fi\nexit 0\n',
    "echo-2-devnull.sh": perdu + ' 2>/dev/null\nexit 0\n',
    # ne doivent pas l'être
    "heredoc-vers-fichier.sh": 'cat <<EOF > "$F"\ntexte\nEOF\ncat <<EOF >> "$LOG"\ntexte\nEOF\nexit 0\n',
    "printf-calcule.sh": 'if [ -n "$X" ]; then exit 2; fi\nprintf \'%s\\n\' "$(jq -nc --arg m x \'{systemMessage: $m}\')"\n',
    "exec-stderr.sh": 'exec 1>&2\necho "Refus."\nexit 2\n',
    "echo-capture.sh": 'INPUT=$(cat 2>/dev/null || echo \'{}\')\nexit 0\n',
}
for nom, texte in hooks.items():
    open(os.path.join(d, "hooks", nom), "w").write(texte)
cmd = lambda nom: ("python3 -I ~/.claude/hooks/" if nom.endswith(".py") else "bash ~/.claude/hooks/") + nom
json.dump({"hooks": {"PostToolUse": [{"hooks": [{"type": "command", "command": cmd(n)} for n in hooks]}]}},
          open(os.path.join(d, "settings.json"), "w"))
PY
SORTIE_T=$(bash "$CONTROLE" "$TROIS" 2>&1)
for f in py-commentaire.py py-triple-chaine.py py-echappe.py fonction-capturee-et-appelee.sh \
         groupe-2-devnull.sh decalage.sh heredoc-en-chaine.sh fonction-mixte.sh appel-dans-if.sh \
         echo-2-devnull.sh; do
    verifie "message perdu, signalé : $f" 1 "$(echo "$SORTIE_T" | grep -c "$f (PostToolUse)")"
done
for f in heredoc-vers-fichier.sh printf-calcule.sh exec-stderr.sh echo-capture.sh; do
    verifie "hook légitime, pas signalé : $f" 0 "$(echo "$SORTIE_T" | grep -c "$f")"
done

# Des fichiers de hooks piégés pour être lents : 16 000 fonctions d'une ligne
# prenaient 71 s. Le contrôle doit finir en moins de 5 s.
LENT="$BAC/lent"
mkdir -p "$LENT/hooks"
python3 -I - "$LENT" <<'PY'
import json, os, sys
d = sys.argv[1]
hooks = {
    "fonctions.sh": "".join(f"f{i}() {{ :; }}\n" for i in range(16000)) + "f1;" * 5000 + "\n",
    "parenthese.py": "x = (\n" + "1,\n" * 50000,
    "triple.py": 'x = """\n' + "texte\n" * 50000,
    "heredocs.sh": "".join(f"cat <<E{i}\nx\nE{i}\n" for i in range(10000)),
    "options.sh": "echo " + "-echo " * 10000 + "\nprintf " + "-printf " * 10000 + "\n",
    "espaces.sh": "f() { :; }" + " " * 20000 + "x\n",
}
for nom, texte in hooks.items():
    open(os.path.join(d, "hooks", nom), "w").write(texte)
cmd = lambda nom: ("python3 -I ~/.claude/hooks/" if nom.endswith(".py") else "bash ~/.claude/hooks/") + nom
json.dump({"hooks": {"Stop": [{"hooks": [{"type": "command", "command": cmd(n)} for n in hooks]}]}},
          open(os.path.join(d, "settings.json"), "w"))
PY
verifie "des fichiers de hooks piégés pour être lents : contrôle fini en moins de 5 s" \
        0 "$(python3 -I -c '
import subprocess, sys
try:
    r = subprocess.run(["bash", sys.argv[1], sys.argv[2]], capture_output=True, timeout=5)
    sortie = (r.stdout + r.stderr).decode("utf-8", "replace")
    print(0 if "=== BILAN ===" in sortie and "Traceback" not in sortie else 1)
except subprocess.TimeoutExpired:
    print(1)
' "$CONTROLE" "$LENT")"

section "Hooks entendus — /code-review : lignes logiques, fonctions, fichiers absents"
REVUE="$BAC/revue"
mkdir -p "$REVUE/hooks"
python3 -I - "$REVUE" <<'PY'
import json, os, sys
d = sys.argv[1]
perdu = 'echo "Texte simple perdu."'
hooks = {
    # doivent être signalés
    "fonction-multiligne.sh": ('json_get() { python3 -I -c "\nimport sys\nprint(1)\n" <<< "$X" 2>/dev/null; }\n'
                               'V=$(json_get a)\n' + perdu + '\n[[ -n "$V" ]] || {\n  exit 0\n}\n'),
    "fonction-stderr-et-texte.sh": ('err() { echo "$*"; } >&2\nif [ -n "$X" ]; then err "Refus."; exit 2; fi\n'
                                    + perdu + '\nexit 0\n'),
    "comparaison.sh": '(( X > 0 )) && ' + perdu + '\nexit 0\n',
    "case.sh": 'case "$x" in a) ' + perdu + ' ;; esac\nexit 0\n',
    "command-echo.sh": 'command ' + perdu + '\nexit 0\n',
    "trap.sh": 'fin() { ' + perdu + '; }\ntrap fin EXIT\nexit 0\n',
    "document-barre.sh": "python3 - <<'PY'\nx = 1 + \\\nPY\n" + perdu + "\nexit 0\n",
    # ne doivent pas l'être
    "fonction-stderr.sh": 'err() { echo "$*"; } >&2\nif [ -n "$X" ]; then err "Refus."; exit 2; fi\nexit 0\n',
    "variable-par-defaut.sh": ('OUT=$(python3 -c \'import json; print(json.dumps({"systemMessage": "x"}))\')\n'
                               'echo "${OUT:-}"\n'),
    "echo-capture-puis-json.sh": 'JSON=\'{"systemMessage": "x"}\'\nD=$(echo "Valeur"); echo "$JSON"\n',
    "printf-v.sh": 'printf -v MSG \'%s\' "x"\nexit 0\n',
}
for nom, texte in hooks.items():
    open(os.path.join(d, "hooks", nom), "w").write(texte)
commandes = ["bash ~/.claude/hooks/" + n for n in hooks] + ["bash ~/.claude/hooks/absent.sh"]
json.dump({"hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": c} for c in commandes]}]}},
          open(os.path.join(d, "settings.json"), "w"))
PY
SORTIE_R=$(bash "$CONTROLE" "$REVUE" 2>&1)
for f in fonction-multiligne.sh fonction-stderr-et-texte.sh comparaison.sh case.sh command-echo.sh \
         trap.sh document-barre.sh; do
    verifie "message perdu, signalé : $f" 1 "$(echo "$SORTIE_R" | grep -c "$f (PreToolUse)")"
done
for f in fonction-stderr.sh variable-par-defaut.sh echo-capture-puis-json.sh printf-v.sh; do
    verifie "hook légitime, pas signalé : $f" 0 "$(echo "$SORTIE_R" | grep -c "$f")"
done
# Doc hooks : un chemin mal tapé désactive le garde-fou sans rien dire.
verifie "un hook branché dont le fichier n'existe pas est signalé" \
        1 "$(echo "$SORTIE_R" | grep -c "absent.sh (PreToolUse) : branché, mais le fichier n'existe pas")"

# Une ligne pleine d'echo : les recompter à chaque echo coûtait un temps
# quadratique (5,5 s pour 200 Ko).
LIGNE="$BAC/ligne"
mkdir -p "$LIGNE/hooks"
python3 -I -c 'import sys; open(sys.argv[1] + "/hooks/l.sh", "w").write("x;" + "echo;" * 120000 + "\n")' "$LIGNE"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/l.sh"}]}]}}' > "$LIGNE/settings.json"
verifie "une ligne de 600 Ko pleine d'echo : contrôle fini en moins de 5 s" \
        0 "$(python3 -I -c '
import subprocess, sys
try:
    r = subprocess.run(["bash", sys.argv[1], sys.argv[2]], capture_output=True, timeout=5)
    sortie = (r.stdout + r.stderr).decode("utf-8", "replace")
    print(0 if "=== BILAN ===" in sortie and "Traceback" not in sortie else 1)
except subprocess.TimeoutExpired:
    print(1)
' "$CONTROLE" "$LIGNE")"

section "Hooks entendus — un réglage mal formé ne fait pas planter le contrôle"
FORME="$BAC/forme"
mkdir -p "$FORME/hooks"
for reglage in '{"hooks":[1]}' '{"hooks":{"Stop":"abc"}}' '{"hooks":{"Stop":["x"]}}' \
               '{"hooks":{"Stop":[{"hooks":["x",{"command":42}]}]}}' '[1]' \
               '{"hooks":{"Stop":{"hooks":[]}}}'; do
    printf '%s' "$reglage" > "$FORME/settings.json"
    SORTIE_F=$(bash "$CONTROLE" "$FORME" 2>&1)
    verifie "$reglage : signalé, sans trace Python" \
            "1 0" "$(echo "$SORTIE_F" | grep -c "n'a pas la forme attendue") $(echo "$SORTIE_F" | grep -c 'Traceback')"
done
printf '{"hooks":{"Stop":[{"hooks":[{"type":"http","url":"https://exemple.invalid"}]}]}}' > "$FORME/settings.json"
verifie "un hook sans commande (http) n'est pas une forme inattendue" \
        0 "$(bash "$CONTROLE" "$FORME" 2>&1 | grep -c "n'a pas la forme attendue")"
printf '{' > "$FORME/settings.json"
verifie "settings.json illisible : les hooks du plugin sont quand même contrôlés" \
        1 "$(bash "$CONTROLE" "$FORME" 2>&1 | grep -c 'hooks du plugin : [0-9]* contrôlé(s)')"
verifie "settings.json illisible : pas de « ✓ 0 branchement(s) » qui contredirait l'alerte" \
        0 "$(bash "$CONTROLE" "$FORME" 2>&1 | grep -c ' branchement(s), aucun hook ne parle')"
python3 -I -c 'import sys; open(sys.argv[1], "w").write("[" * 200000 + "]" * 200000)' "$FORME/settings.json"
verifie "un settings.json imbriqué sur 200 000 niveaux : signalé, sans trace Python" \
        "1 0" "$(bash "$CONTROLE" "$FORME" 2>&1 | grep -c 'settings.json illisible') $(bash "$CONTROLE" "$FORME" 2>&1 | grep -c Traceback)"
# La regex du chemin complet prenait 24 s sur 80 000 caractères ; la recopie
# du préfixe à chaque occurrence, 12 s sur celle-ci. Il en faut moins d'une.
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"%s"}]}]}}' \
    "$(python3 -I -c 'print("/" * 300000 + "a/.claude/hooks/" * 20000)')" > "$FORME/settings.json"
verifie "une commande de 600 000 caractères est lue en moins de 5 s, jusqu'au bilan" \
        0 "$(python3 -I -c '
import subprocess, sys
try:
    r = subprocess.run(["bash", sys.argv[1], sys.argv[2]], capture_output=True, timeout=5)
    sortie = (r.stdout + r.stderr).decode("utf-8", "replace")
    print(0 if "=== BILAN ===" in sortie and "Traceback" not in sortie else 1)
except subprocess.TimeoutExpired:
    print(1)
' "$CONTROLE" "$FORME")"

section "Hooks du plugin — contrôlés eux aussi"
# Ils sont branchés dans hooks.json, pas dans settings.json : le contrôle ne
# les lisait jamais.
verifie "les hooks du plugin sont contrôlés, et aucun ne parle dans le vide" \
        1 "$(bash "$CONTROLE" "$VIERGE" 2>&1 | grep -c 'hooks du plugin : [0-9]* contrôlé(s), aucun ne parle dans le vide')"
FAUX="$BAC/faux-plugin"
mkdir -p "$FAUX/hooks"
cp "$CONTROLE" "$FAUX/hooks/"
cat > "$FAUX/hooks/hooks.json" <<'JSON'
{"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/bavard.sh\""}]}]}}
JSON
printf 'echo "Personne ne lira ceci."\nexit 0\n' > "$FAUX/hooks/bavard.sh"
verifie "un hook muet du plugin est signalé" \
        1 "$(bash "$FAUX/hooks/verifier-setup.sh" "$VIERGE" 2>&1 | grep -c 'plugin:hooks/bavard.sh (PostToolUse) : ses messages sortent avec le code 0')"
ln -s "$CONTROLE" "$BAC/lien-vers-le-controle.sh"
verifie "lancé par un lien symbolique, il trouve quand même les hooks du plugin" \
        1 "$(bash "$BAC/lien-vers-le-controle.sh" "$VIERGE" 2>&1 | grep -c 'hooks du plugin : [0-9]* contrôlé(s)')"
# Lancé par « bash -s », $0 vaut « bash » : le hooks.json lu était celui du
# dossier courant, et un nom d'événement piégé s'affichait tel quel.
PIEGE_H="$BAC/depot-piege"
mkdir -p "$PIEGE_H/hooks"
python3 -I -c '
import json, sys
json.dump({"hooks": {"Post\033[31mX\nFAUX\u009b31m\u202eZ": [{"hooks": [{"type": "command",
           "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/bavard.sh"}]}]}}, open(sys.argv[1], "w"))
' "$PIEGE_H/hooks.json"
printf 'echo "x"\n' > "$PIEGE_H/bavard.sh"
touch "$PIEGE_H/bash"      # le nom que prend $0 : un fichier du dépôt peut le porter
SORTIE_S=$(cd "$PIEGE_H" && bash -s -- "$VIERGE" < "$CONTROLE" 2>&1)
verifie "lancé par « bash -s », il ne lit pas le hooks.json du dossier courant" \
        0 "$(echo "$SORTIE_S" | grep -c 'plugin:')"
cp "$PIEGE_H/hooks.json" "$FAUX/hooks/hooks.json"
printf 'echo "x"\n' > "$FAUX/hooks/bavard.sh"
verifie "un nom d'événement piégé ne pilote pas le terminal" \
        "1 0" "$(bash "$FAUX/hooks/verifier-setup.sh" "$VIERGE" 2>&1 | grep -cF 'Post?[31mX?FAUX?31m?Z') $(bash "$FAUX/hooks/verifier-setup.sh" "$VIERGE" 2>&1 | grep -c "$(printf '\033')")"

section "Faux positifs retirés"
verifie "les skills synchronisés par Claude Code ne sont pas « jamais chargés »" \
        0 "$(echo "$SORTIE_E" | grep -c 'synced')"
verifie "une date dans un nom de fichier n'est pas une échéance" \
        0 "$(echo "$SORTIE_E" | grep -c 'precedent.md')"

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
