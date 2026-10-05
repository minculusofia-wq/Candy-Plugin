#!/bin/bash
#
# Le contrôle universel : il doit lancer TOUS les contrôles qu'il trouve,
# pas seulement la première famille rencontrée.
#
# Le défaut d'origine : chaque famille était conditionnée à « aucun contrôle
# trouvé jusqu'ici ». Un Makefile qui passe suffisait à masquer une suite de
# tests en échec, et le verdict tombait à « TOUT PASSE » en sortie 0.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
CONTROLE="$RACINE/hooks/verifier-projet.sh"
BAC=$(mktemp -d)
trap 'rm -rf "$BAC"' EXIT

section "Contrôle universel — les quatre verdicts"

# Ces cas ont besoin de pytest et de npm pour EXISTER : ils vérifient que le
# contrôle lance bien ces deux familles. Le paquet, lui, ne dépend que de
# python3 — sur une machine sans ces outils, les cas sont sautés en le disant
# plutôt que d'afficher une suite rouge sans explication.
if outil pytest && outil npm; then

# --- un Makefile qui passe, une suite Python et une suite Node en échec ---
mkdir -p "$BAC/melange/tests"
printf 'test:\n\t@true\n' > "$BAC/melange/Makefile"
printf 'def test_ko():\n    assert False\n' > "$BAC/melange/tests/test_ko.py"
printf '{"name":"m","scripts":{"test":"exit 1"}}\n' > "$BAC/melange/package.json"

SORTIE=$(bash "$CONTROLE" "$BAC/melange" 2>&1); CODE=$?
verifie "un Makefile qui passe ne masque plus le reste" 1 "$CODE"
verifie "  la suite Python en échec est signalée" \
        1 "$(echo "$SORTIE" | grep -c 'ECHEC  pytest')"
verifie "  la suite Node en échec est signalée" \
        1 "$(echo "$SORTIE" | grep -c 'ECHEC  npm test')"
verifie "  le contrôle qui passe reste listé" \
        1 "$(echo "$SORTIE" | grep -c 'OK     make test')"
verifie "  le verdict ne dit pas que tout passe" \
        0 "$(echo "$SORTIE" | grep -c 'TOUT PASSE')"

# --- sans Makefile : les deux familles doivent tourner quand même ---
mkdir -p "$BAC/deux/tests"
printf 'def test_ko():\n    assert False\n' > "$BAC/deux/tests/test_ko.py"
printf '{"name":"d","scripts":{"test":"exit 1"}}\n' > "$BAC/deux/package.json"
SORTIE=$(bash "$CONTROLE" "$BAC/deux" 2>&1)
verifie "sans Makefile, Python et Node sont tous deux lancés" \
        2 "$(echo "$SORTIE" | grep -c 'ECHEC ')"

# --- tout vert ---
mkdir -p "$BAC/vert/tests"
printf 'def test_ok():\n    assert True\n' > "$BAC/vert/tests/test_ok.py"
printf '{"name":"v","scripts":{"test":"exit 0"}}\n' > "$BAC/vert/package.json"
bash "$CONTROLE" "$BAC/vert" >/dev/null 2>&1
verifie "un projet sain sort en 0" 0 $?

else
    saute "les sept cas qui font tourner une suite Python et une suite Node" \
          "pytest ou npm absent de cette machine"
fi

# --- un dossier « tests » qui ne contient PAS de tests Python ---
# Trouvé en écrivant ces tests : le contrôle lançait pytest dès qu'un dossier
# tests existait. Sur ce dépôt-ci, dont les tests sont des scripts shell, pytest
# ne collectait rien, sortait en 5, et le projet était déclaré en échec.
mkdir -p "$BAC/shell/tests"
printf 'test:\n\t@true\n' > "$BAC/shell/Makefile"
printf '#!/bin/bash\nexit 0\n' > "$BAC/shell/tests/cas.sh"
SORTIE=$(bash "$CONTROLE" "$BAC/shell" 2>&1); CODE=$?
verifie "un dossier tests sans test Python ne déclenche pas pytest" \
        0 "$(echo "$SORTIE" | grep -c 'pytest')"
verifie "  et le projet reste au vert" 0 "$CODE"

# --- une suite Python rangée en sous-dossier ---
# Le contrôle cherchait les fichiers de test dans trois dossiers seulement :
# « . », « tests » et « test ». Les trois dispositions ci-dessous — les plus
# répandues — n'étaient pas vues : pytest n'était pas lancé, et un Makefile qui
# passe suffisait à décrocher un « TOUT PASSE » sur une suite cassée.
section "Contrôle universel — les tests rangés en sous-dossier"

if ! outil pytest; then
    saute "les six cas de suites rangées en sous-dossier" "pytest absent de cette machine"
fi
for cas in "tests/unit" "backend/tests" "src/tests"; do
    outil pytest || continue
    DOSSIER="$BAC/imbrique-$(echo "$cas" | tr / -)"
    mkdir -p "$DOSSIER/$cas"
    printf 'test:\n\t@true\n' > "$DOSSIER/Makefile"
    printf 'def test_ko():\n    assert False\n' > "$DOSSIER/$cas/test_ko.py"

    SORTIE=$(bash "$CONTROLE" "$DOSSIER" 2>&1); CODE=$?
    verifie "une suite en échec dans $cas/ est vue" \
            1 "$(echo "$SORTIE" | grep -c 'ECHEC  pytest')"
    verifie "  et le Makefile qui passe ne la masque pas" 1 "$CODE"
done

# --- le contrôle ne laisse aucune trace dans le projet ---
# Lancer pytest partout a un effet de bord : il dépose un dossier de cache dans
# le projet, même sans une seule ligne de Python. Un contrôle ne salit pas ce
# qu'il contrôle — et ce dossier finit enregistré par erreur.
section "Contrôle universel — il ne laisse rien derrière lui"

mkdir -p "$BAC/propre/tests"
printf 'test:\n\t@true\n' > "$BAC/propre/Makefile"
printf '#!/bin/bash\nexit 0\n' > "$BAC/propre/tests/cas.sh"
AVANT=$(ls -a "$BAC/propre" | sort)
bash "$CONTROLE" "$BAC/propre" >/dev/null 2>&1
APRES=$(ls -a "$BAC/propre" | sort)
verifie "aucun fichier créé dans le projet contrôlé" "$AVANT" "$APRES"

# --- rien à quoi se fier : le cas que rien d'autre ne signale ---
mkdir -p "$BAC/vide"
bash "$CONTROLE" "$BAC/vide" >/dev/null 2>&1
verifie "un projet sans aucun moyen de vérification sort en 2" 2 $?

section "Contrôle universel — ce que la 0.4.0 corrige"
# Un faux pytest, qui compte ses appels : ces cas n'ont pas besoin du vrai.
mkdir -p "$BAC/outils"
cat > "$BAC/outils/pytest" <<'FIN'
#!/bin/bash
echo "appel : $*" >> "$COMPTEUR_PYTEST"
exit 0
FIN
chmod +x "$BAC/outils/pytest"
# « make test » qui lance pytest : pytest ne tourne plus une seconde fois.
mkdir -p "$BAC/deuxfois"
printf 'test:\n\tpytest -q\n' > "$BAC/deuxfois/Makefile"
: > "$BAC/compte-deuxfois"
env PATH="$BAC/outils:$PATH" COMPTEUR_PYTEST="$BAC/compte-deuxfois" bash "$CONTROLE" "$BAC/deuxfois" >/dev/null 2>&1
verifie "make test lance pytest : pytest ne tourne qu'une fois" 1 "$(grep -c . "$BAC/compte-deuxfois")"
# … mais une cible test qui ne l'appelle pas ne masque toujours rien.
mkdir -p "$BAC/masque"
printf 'test:\n\t@true\n' > "$BAC/masque/Makefile"
: > "$BAC/compte-masque"
env PATH="$BAC/outils:$PATH" COMPTEUR_PYTEST="$BAC/compte-masque" bash "$CONTROLE" "$BAC/masque" >/dev/null 2>&1
verifie "« test: @true » : pytest tourne quand même" 1 "$(grep -c . "$BAC/compte-masque")"
# 0.5.0 : « test: test-back », test-back lançant pytest dans backend/ (une
# disposition réelle) : seule la recette de « test: » était lue, et pytest
# était relancé depuis la racine, une seconde fois.
mkdir -p "$BAC/prealable/backend"
printf 'test: test-back\n\ntest-back:\n\tcd backend && pytest -q\n' > "$BAC/prealable/Makefile"
: > "$BAC/compte-prealable"
env PATH="$BAC/outils:$PATH" COMPTEUR_PYTEST="$BAC/compte-prealable" bash "$CONTROLE" "$BAC/prealable" >/dev/null 2>&1
verifie "test: test-back (qui lance pytest) : les tests du backend ne tournent qu'une fois" 1 "$(grep -vc -- '--ignore=backend' "$BAC/compte-prealable")"
# « $(MAKE) -C backend test » : ni la cible du backend ni pytest ne sont relancés.
mkdir -p "$BAC/sousmake/backend"
printf 'test:\n\t$(MAKE) -C backend test\n' > "$BAC/sousmake/Makefile"
printf 'test:\n\tpytest -q\n' > "$BAC/sousmake/backend/Makefile"
: > "$BAC/compte-sousmake"
env PATH="$BAC/outils:$PATH" COMPTEUR_PYTEST="$BAC/compte-sousmake" bash "$CONTROLE" "$BAC/sousmake" >/dev/null 2>&1
verifie "make -C backend test : les tests du backend ne tournent qu'une fois" 1 "$(grep -vc -- '--ignore=backend' "$BAC/compte-sousmake")"
# pytest lancé par une variable de Make (« $(PYTEST) -q », la forme de quatre
# projets réels) : sans développer la variable, pytest était relancé.
mkdir -p "$BAC/variable"
printf 'PYTEST = pytest\n\ntest:\n\t$(PYTEST) -q\n' > "$BAC/variable/Makefile"
: > "$BAC/compte-variable"
env PATH="$BAC/outils:$PATH" COMPTEUR_PYTEST="$BAC/compte-variable" bash "$CONTROLE" "$BAC/variable" >/dev/null 2>&1
verifie "test: \$(PYTEST) -q : pytest ne tourne qu'une fois" 1 "$(grep -c . "$BAC/compte-variable")"
# La cible test est dans backend/Makefile, sans Makefile à la racine.
mkdir -p "$BAC/seulbackend/backend"
printf 'PYTEST := pytest\ntest:\n\t$(PYTEST) tests/ -v\n' > "$BAC/seulbackend/backend/Makefile"
: > "$BAC/compte-seulbackend"
env PATH="$BAC/outils:$PATH" COMPTEUR_PYTEST="$BAC/compte-seulbackend" bash "$CONTROLE" "$BAC/seulbackend" >/dev/null 2>&1
verifie "backend/Makefile seul, test: \$(PYTEST) : les tests du backend ne tournent qu'une fois" 1 "$(grep -vc -- '--ignore=backend' "$BAC/compte-seulbackend")"
# Relecture de sécurité de la 0.5.0 : sauter un contrôle n'est permis que s'il
# est sûr d'être couvert. Un « cd backend » dans une cible d'installation
# faisait sauter les tests du backend (TOUT PASSE sur une suite rouge) ; une
# cible test du backend faisait sauter les tests de la racine.
mkdir -p "$BAC/installe/backend"
printf 'install:\n\tcd backend && echo x\n\ntest: install\n\t@echo ok\n' > "$BAC/installe/Makefile"
printf 'test:\n\t@echo ECHEC; exit 1\n' > "$BAC/installe/backend/Makefile"
bash "$CONTROLE" "$BAC/installe" >/dev/null 2>&1
verifie "un cd backend sans tests à la racine ne masque pas l'échec du backend" 1 $?
mkdir -p "$BAC/racine-et-backend/backend" "$BAC/racine-et-backend/tests"
printf 'test:\n\tpytest -q\n' > "$BAC/racine-et-backend/backend/Makefile"
printf 'def test_racine():\n    assert True\n' > "$BAC/racine-et-backend/tests/test_racine.py"
: > "$BAC/compte-racine"
env PATH="$BAC/outils:$PATH" COMPTEUR_PYTEST="$BAC/compte-racine" bash "$CONTROLE" "$BAC/racine-et-backend" >/dev/null 2>&1
verifie "tests à la racine ET dans backend/ : la racine tourne aussi, sans le backend" "1 1" \
        "$(grep -vc -- '--ignore=backend' "$BAC/compte-racine") $(grep -c -- '--ignore=backend' "$BAC/compte-racine")"
# VERIFIER_A_BLANC=1 : la liste des contrôles, sans en lancer aucun.
: > "$BAC/compte-blanc"
SORTIE=$(env PATH="$BAC/outils:$PATH" COMPTEUR_PYTEST="$BAC/compte-blanc" VERIFIER_A_BLANC=1 bash "$CONTROLE" "$BAC/masque" 2>&1); CODE=$?
verifie "à blanc : code 0, rien ne tourne, pytest listé" "0 0 1" \
        "$CODE $(grep -c . "$BAC/compte-blanc") $(echo "$SORTIE" | grep -c '\[A BLANC\] pytest')"
# Le script test que crée « npm init » n'est pas un test.
if outil npm; then
    mkdir -p "$BAC/npminit"
    printf '{"name":"n","scripts":{"test":"echo \\"Error: no test specified\\" && exit 1"}}\n' > "$BAC/npminit/package.json"
    SORTIE=$(bash "$CONTROLE" "$BAC/npminit" 2>&1); CODE=$?
    verifie "le test par défaut de npm init n'est pas lancé" 0 "$(echo "$SORTIE" | grep -c 'npm test')"
    verifie "  et ne met pas le projet en échec" 2 "$CODE"
    # Un package.json illisible lance npm test : son échec se voit, il ne passe
    # pas pour un projet sans contrôle.
    mkdir -p "$BAC/npmcasse"
    printf '{"name": "n", "scripts": {"test": \n' > "$BAC/npmcasse/package.json"
    bash "$CONTROLE" "$BAC/npmcasse" >/dev/null 2>&1
    verifie "package.json illisible : npm test lancé, et en échec" 1 $?
else
    saute "le test par défaut de npm init n'est pas lancé" "npm absent de cette machine"
    saute "package.json illisible : npm test lancé" "npm absent de cette machine"
fi
# L'audit des dépendances ne tourne pas en fin de tour.
mkdir -p "$BAC/audit"
printf 'test:\n\t@true\naudit:\n\t@exit 1\n' > "$BAC/audit/Makefile"
SORTIE=$(VERIFIER_SANS_AUDIT=1 bash "$CONTROLE" "$BAC/audit" 2>&1); CODE=$?
verifie "VERIFIER_SANS_AUDIT=1 : make audit n'est pas lancé" 0 "$(echo "$SORTIE" | grep -c 'make audit')"
verifie "  et le projet reste vert" 0 "$CODE"
# La variable est posée à 0 explicitement : cette suite tourne aussi sous le
# hook de fin de tour, qui exporte VERIFIER_SANS_AUDIT=1 — héritée, elle faisait
# échouer ce cas alors que rien n'avait changé (vu le 2026-09-26).
SORTIE=$(VERIFIER_SANS_AUDIT=0 bash "$CONTROLE" "$BAC/audit" 2>&1)
verifie "sans elle, /verifier lance toujours make audit" 1 "$(echo "$SORTIE" | grep -c 'ECHEC  make audit')"
# Sans fichier temporaire, le contrôle n'a pas tourné : c'est un échec, pas un
# projet « sans moyen de vérification » que la fin de tour laisse passer.
mkdir -p "$BAC/sanstmp"
printf 'test:\n\t@true\n' > "$BAC/sanstmp/Makefile"
TMPDIR="$BAC/nexiste-pas" bash "$CONTROLE" "$BAC/sanstmp" >/dev/null 2>&1
verifie "fichier temporaire impossible : échec, pas « aucun contrôle »" 1 $?
# Un test qui laisse un processus en arrière-plan ne fait plus attendre.
mkdir -p "$BAC/fond"
printf 'test:\n\t@(sleep 997 &); true\n' > "$BAC/fond/Makefile"
debut=$(date +%s); bash "$CONTROLE" "$BAC/fond" >/dev/null 2>&1; duree=$(( $(date +%s) - debut ))
pkill -f 'sleep 997' 2>/dev/null
verifie "un processus laissé en arrière-plan ne fait pas attendre le contrôle" 1 "$([ "$duree" -lt 10 ] && echo 1 || echo 0)"

bilan
