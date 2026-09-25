#!/bin/bash
#
# Le contrôle de fin de tour (hook Stop) : il lance le contrôle du projet quand
# du code a bougé PENDANT le tour, depuis la racine du dépôt, et rend la main
# à temps.
#
# Jusqu'à la 0.3.4 : aucune limite de temps (une suite qui pend faisait pendre
# le hook jusqu'à son annulation, verdict jeté) ; rien ne partait depuis un
# sous-dossier, pour un dossier nouveau, pour un nom avec espace ou accent, ni
# après un commit fait pendant le tour ; du code modifié AVANT le tour faisait
# contrôler une simple question ; relancé par l'autre hook Stop, il ne
# recontrôlait jamais ; la sortie des tests arrivait à Claude sans cadre.
# Chaque cas tourne dans un dépôt jetable.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$RACINE/hooks/controle-si-code-modifie.sh"
BAC=$(mktemp -d)
trap 'rm -rf "$BAC"' EXIT
export CONTROLE_ETATS="$BAC/etats"

depot() {  # depot <nom> <contenu de la cible test du Makefile>
    local d="$BAC/$1"
    mkdir -p "$d" && git -C "$d" init -q && git -C "$d" config user.email t@t.t && git -C "$d" config user.name t
    printf 'test:\n\t@%s\n' "$2" > "$d/Makefile"
    printf 'x = 1\n' > "$d/app.py"
    git -C "$d" add -A && git -C "$d" -c commit.gpgsign=false commit -qm depart
    echo "$d"
}
fin() {  # fin <cwd> [transcription] → code de sortie du hook (sans relevé de début de tour)
    python3 -I -c 'import json, sys; print(json.dumps({"cwd": sys.argv[1], "transcript_path": sys.argv[2], "stop_hook_active": False}))' "$1" "${2:-}" \
        | env CONTROLE_BUDGET="${BUDGET:-60}" bash "$HOOK" >/dev/null 2>"$BAC/stderr"; echo $?
}
debut_tour() {  # debut_tour <cwd> : le relevé du UserPromptSubmit
    python3 -I -c 'import json, sys; print(json.dumps({"cwd": sys.argv[1], "session_id": "essai"}))' "$1" \
        | python3 -I "$RACINE/hooks/controle-fin-de-tour.py" debut
}
fin_s() {  # fin_s <cwd> [stop_hook_active] → code, avec la session « essai »
    python3 -I -c 'import json, sys; print(json.dumps({"cwd": sys.argv[1], "session_id": "essai", "stop_hook_active": sys.argv[2] == "1"}))' "$1" "${2:-0}" \
        | env CONTROLE_BUDGET="${BUDGET:-60}" bash "$HOOK" >/dev/null 2>"$BAC/stderr"; echo $?
}

section "Fin de tour — ce qui déclenche le contrôle"
D_ROUGE=$(depot rouge "exit 1")
D_VERT=$(depot vert "true")
verifie "rien de modifié : rien" 0 "$(fin "$D_ROUGE")"
printf '# doc\n' > "$D_ROUGE/NOTES.md"
verifie "seulement de la doc : rien" 0 "$(fin "$D_ROUGE")"
rm "$D_ROUGE/NOTES.md"
printf 'x = 2\n' > "$D_ROUGE/app.py"
verifie "code modifié, contrôle rouge : REFUSE la fin du tour" 2 "$(fin "$D_ROUGE")"
mkdir -p "$D_ROUGE/sous/dossier"
verifie "depuis un sous-dossier : le contrôle part de la racine" 2 "$(fin "$D_ROUGE/sous/dossier")"
git -C "$D_ROUGE" checkout -q app.py
mkdir -p "$D_ROUGE/nouveau"; printf 'y = 1\n' > "$D_ROUGE/nouveau/module.py"
verifie "dossier nouveau non suivi : contrôle lancé" 2 "$(fin "$D_ROUGE")"
rm -rf "$D_ROUGE/nouveau"
printf 'z = 1\n' > "$D_ROUGE/stratégie v2.py"
verifie "nom avec espace et accent : contrôle lancé" 2 "$(fin "$D_ROUGE")"
rm -f "$D_ROUGE/stratégie v2.py"
# Commit fait pendant le tour : le dépôt est propre, mais du code a bougé.
T="$BAC/transcription.jsonl"
python3 -I -c 'import json, datetime as d
t = (d.datetime.now(d.timezone.utc) - d.timedelta(seconds=30)).isoformat().replace("+00:00", "Z")
print(json.dumps({"type": "user", "timestamp": t, "message": {"role": "user", "content": "corrige le module"}}))' > "$T"
sleep 1
printf 'x = 3\n' > "$D_ROUGE/app.py" && git -C "$D_ROUGE" -c commit.gpgsign=false commit -qam "fix: x"
verifie "commit fait pendant le tour : contrôle lancé" 2 "$(fin "$D_ROUGE" "$T")"
verifie "sans transcription, dépôt propre : rien" 0 "$(fin "$D_ROUGE")"
printf 'x = 2\n' > "$D_VERT/app.py"
verifie "code modifié, contrôle vert : laisse passer" 0 "$(fin "$D_VERT")"
verifie "hors dépôt git : rien" 0 "$(fin "$BAC")"
verifie "déjà relancé par un hook Stop, sans relevé : rien" \
        0 "$(printf '{"cwd": "%s", "stop_hook_active": true}' "$D_ROUGE" | bash "$HOOK" >/dev/null 2>&1; echo $?)"

section "Fin de tour — il rend la main à temps"
LENT=$(depot lent "sleep 999")
printf 'x = 2\n' > "$LENT/app.py"
debut=$(date +%s); code=$(BUDGET=3 fin "$LENT"); duree=$(( $(date +%s) - debut ))
verifie "contrôle trop long : il rend la main, et refuse" 2 "$code"
verifie "  en moins de 15 s" 1 "$([ "$duree" -lt 15 ] && echo 1 || echo 0)"
verifie "  et le dit à Claude" 1 "$(grep -qi 'interrompu' "$BAC/stderr" && echo 1 || echo 0)"
verifie "  aucun processus du contrôle ne survit" 0 "$(pgrep -f 'sleep 999' >/dev/null && echo 1 || echo 0)"
FOND=$(depot fond "(sleep 998 &); true")
printf 'x = 2\n' > "$FOND/app.py"
debut=$(date +%s); code=$(BUDGET=20 fin "$FOND"); duree=$(( $(date +%s) - debut ))
verifie "un processus laissé en arrière-plan : vert" 0 "$code"
verifie "  en moins de 15 s" 1 "$([ "$duree" -lt 15 ] && echo 1 || echo 0)"
verifie "  et il est tué" 0 "$(pgrep -f 'sleep 998' >/dev/null && echo 1 || echo 0)"
verifie "hooks.json donne au hook plus de temps que son budget (300 s > 240 s)" \
        1 "$(python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1]))["hooks"]["Stop"]
t = [h.get("timeout", 600) for g in d for h in g["hooks"] if "controle-si-code-modifie" in h["command"]]
print(int(bool(t) and all(x > 240 for x in t)))' "$RACINE/hooks/hooks.json")"

section "Fin de tour — ce qui a bougé PENDANT le tour"
ROUGE2=$(depot rouge2 "echo ligne-de-sortie; exit 1")
printf 'x = 9\n' > "$ROUGE2/app.py"                      # modifié AVANT le tour
debut_tour "$ROUGE2"
verifie "code modifié avant le tour, simple question : rien" 0 "$(fin_s "$ROUGE2")"
sleep 1; printf 'x = 10\n' > "$ROUGE2/app.py"            # modifié PENDANT le tour
verifie "code modifié pendant le tour : contrôle lancé" 2 "$(fin_s "$ROUGE2")"
verifie "  sa sortie est encadrée comme une donnée" \
        1 "$(grep -q 'SORTIE DU CONTROLE' "$BAC/stderr" && grep -q 'FIN DE LA SORTIE DU CONTROLE' "$BAC/stderr" && echo 1 || echo 0)"
verifie "relancé sans nouveau changement : rien" 0 "$(fin_s "$ROUGE2" 1)"
sleep 1; printf 'x = 11\n' > "$ROUGE2/app.py"
verifie "relancé après un nouveau changement : recontrôle" 2 "$(fin_s "$ROUGE2" 1)"
git -C "$ROUGE2" checkout -q app.py; debut_tour "$ROUGE2"
printf 'x = 12\n' > "$ROUGE2/app.py" && git -C "$ROUGE2" -c commit.gpgsign=false commit -qam "fix: y"
verifie "commit pendant le tour (avec relevé) : contrôle lancé" 2 "$(fin_s "$ROUGE2")"
# Sans relevé : la transcription, lue sans plafond, même au-delà de 4 Mo, et
# une ligne « user » mal formée ne fait pas planter le contrôle.
ROUGE3=$(depot rouge3 "exit 1")
T3="$BAC/longue.jsonl"
python3 -I -c 'import json, datetime as d, sys
t = (d.datetime.now(d.timezone.utc) - d.timedelta(seconds=30)).isoformat().replace("+00:00", "Z")
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "timestamp": t, "message": {"role": "user", "content": "corrige"}}) + "\n")
    bruit = json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "x" * 1000}]}})
    for _ in range(5000):
        f.write(bruit + "\n")
    f.write(json.dumps({"type": "user", "message": "texte au lieu d un objet"}) + "\n")' "$T3"
sleep 1; printf 'x = 3\n' > "$ROUGE3/app.py" && git -C "$ROUGE3" -c commit.gpgsign=false commit -qam "fix: z"
verifie "transcription de plus de 4 Mo : contrôle lancé" 2 "$(fin "$ROUGE3" "$T3")"
# Relancé par l'AUTRE hook Stop (relire-ma-reponse) après un contrôle vert, puis
# code cassé : le contrôle repart ; des tests qui écrivent un fichier à chaque
# passage ne font pas boucler le blocage.
AUTRE=$(depot autre "! grep -q casse app.py")
debut_tour "$AUTRE"
sleep 1; printf 'x = 5\n' > "$AUTRE/app.py"
verifie "contrôle vert pendant le tour" 0 "$(fin_s "$AUTRE")"
verifie "relancé par un autre hook, rien changé : rien" 0 "$(fin_s "$AUTRE" 1)"
sleep 1; printf 'casse = 1\n' > "$AUTRE/app.py"
verifie "relancé par un autre hook, code cassé ensuite : contrôle" 2 "$(fin_s "$AUTRE" 1)"
printf '# note\n' > "$AUTRE/NOTES.md"
verifie "après un contrôle, seulement de la doc : rien" 0 "$(fin_s "$AUTRE" 1)"
TRACE=$(depot trace "date +%s > trace.log; exit 1")
debut_tour "$TRACE"
sleep 1; printf 'x = 6\n' > "$TRACE/app.py"
verifie "des tests qui écrivent un fichier : refuse une fois" 2 "$(fin_s "$TRACE")"
verifie "  sans boucle ensuite" 0 "$(fin_s "$TRACE" 1)"
verifie "les relevés vont dans le dossier donné, pas ailleurs" 1 "$([ -f "$CONTROLE_ETATS/essai.json" ] && echo 1 || echo 0)"

section "Fin de tour — un relevé qu'on ne peut pas croire"
# Sans dossier de données du plugin, les relevés vont dans le dossier temporaire
# partagé : un dossier ouvert à tous n'est pas cru, sinon un autre compte y
# déposerait un relevé « rien n'a bougé » qui fait taire le contrôle.
FAUX=$(depot faux "exit 1")
printf 'x = 7\n' > "$FAUX/app.py"
OUVERT="$BAC/etats-ouverts"
CONTROLE_ETATS="$OUVERT" debut_tour "$FAUX"             # relevé qui dit : app.py déjà modifié
chmod 777 "$OUVERT"
verifie "dossier des relevés ouvert à tous : relevé ignoré, contrôle lancé" \
        2 "$(CONTROLE_ETATS="$OUVERT" fin_s "$FAUX")"
chmod 700 "$OUVERT"
verifie "  le même relevé, dans un dossier à soi : cru" 0 "$(CONTROLE_ETATS="$OUVERT" fin_s "$FAUX")"
# Un relevé abîmé dont le « head » commence par -- : git ne le lit pas comme
# une option (git diff --output=… écrirait un fichier).
INJ="$BAC/etats-inj"; mkdir -m 700 "$INJ"
python3 -I -c 'import json, sys
json.dump({"racine": sys.argv[1], "head": "--output=" + sys.argv[2], "fichiers": {}}, open(sys.argv[3], "w"))' \
    "$(cd "$FAUX" && pwd -P)" "$BAC/injecte" "$INJ/essai.json"
verifie "relevé au head piégé : contrôle lancé" 2 "$(CONTROLE_ETATS="$INJ" fin_s "$FAUX")"
verifie "  et git n'a rien écrit" 0 "$(ls "$BAC" | grep -c '^injecte')"
# Historique réécrit pendant le tour (le commit du relevé n'existe plus) : on
# ne sait pas ce qui a bougé, le contrôle part.
REEC="$BAC/etats-reec"
CONTROLE_ETATS="$REEC" debut_tour "$FAUX"
python3 -I -c 'import json, sys
e = json.load(open(sys.argv[1])); e["head"] = "0" * 40; json.dump(e, open(sys.argv[1], "w"))' "$REEC/essai.json"
verifie "commit du relevé disparu : contrôle lancé" 2 "$(CONTROLE_ETATS="$REEC" fin_s "$FAUX")"

bilan
