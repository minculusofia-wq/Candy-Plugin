#!/bin/bash
#
# L'audit des .md : son compteur doit compter, et il ne doit pas signaler ce
# qui est seulement CITÉ.
#
# Deux défauts d'origine. Le compteur était incrémenté à l'intérieur d'un
# sous-processus : la valeur se perdait en sortant, et le bilan affichait zéro
# sous des lignes rouges. Et l'audit signalait la documentation qui explique ce
# qu'il attrape — le même piège usage/mention que relire-ma-reponse.sh avait
# déjà résolu en retirant les citations avant de juger.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$RACINE/hooks/session-end-md-audit.sh"
BAC=$(mktemp -d)
trap 'rm -rf "$BAC"' EXIT

mkdir -p "$BAC/projet"
cd "$BAC/projet"
git init -q && git config user.email t@t.t && git config user.name t

cat > A.md <<'EOF'
# Document A

Un vrai lien cassé : [le guide](GUIDE-ABSENT.md)
Un deuxième : [autre](docs/PARTI.md)
Un lien valide : [B](B.md)
Un lien externe : [site](https://example.com)
Une mention citée, à ignorer : `[fichier.py:42](chemin#L42)`
Un vrai statut : cette section est à créer
Une mention citée : le contrôle cherche « à créer » et « à trancher »
EOF
echo "# Document B" > B.md
cat > C.md <<'EOF'
# Document C
Un exemple dans un bloc de code, à ignorer :
```
[modèle](FICHIER-ABSENT.md)
statut : à trancher
```
EOF

SORTIE=$(bash "$AUDIT" "$BAC/projet" 2>&1)

section "Audit des .md — le compteur compte vraiment"
verifie "les deux vrais liens cassés sont comptés" \
        1 "$(echo "$SORTIE" | grep -c 'Liens casses          : 2')"
verifie "le bilan est cohérent avec ce qui est affiché" \
        1 "$(echo "$SORTIE" | grep -c 'TOTAL : 3 point')"
bash "$AUDIT" "$BAC/projet" >/dev/null 2>&1
verifie "des problèmes trouvés donnent une sortie non nulle" 1 $?

section "Audit des .md — ce qui est cité n'est pas signalé"
verifie "un lien entre accents graves est ignoré" \
        0 "$(echo "$SORTIE" | grep -c 'chemin')"
verifie "un lien dans un bloc de code est ignoré" \
        0 "$(echo "$SORTIE" | grep -c 'FICHIER-ABSENT')"
verifie "un statut entre guillemets français est ignoré" \
        1 "$(echo "$SORTIE" | grep -c 'Statuts contradictoires : 1')"
verifie "aucune ligne n'est affichée deux fois" \
        1 "$(echo "$SORTIE" | grep -c 'A.md:3')"

section "Audit des .md — les deux contrôles qui lisent l'historique"
# Le dépôt d'exemple ci-dessus n'a aucun commit : les contrôles 2 (références à
# un fichier supprimé) et 3 (date de mise à jour périmée) lisent l'historique
# git et ne s'exécutaient donc jamais. Le groupe prétendait couvrir quatre
# contrôles et n'en exerçait que deux.
mkdir -p "$BAC/historique/docs"
(
  cd "$BAC/historique"
  git init -q && git config user.email t@t.t && git config user.name t
  echo "# Guide" > docs/GUIDE.md
  echo "# Document parti" > docs/PARTI.md
  printf '# Suivi\n\nDernière mise à jour : 2020-01-01\n\nLe détail est dans docs/PARTI.md\n' > SUIVI.md
  git add docs SUIVI.md && git commit -qm depart
  git rm -q docs/PARTI.md && git commit -qm suppression
) >/dev/null 2>&1

HISTO=$(bash "$AUDIT" "$BAC/historique" 2>&1)

verifie "une mention d'un fichier supprimé est comptée" \
        1 "$(echo "$HISTO" | grep -c 'Fichiers supprimes    : 1')"
verifie "  et la ligne fautive est montrée" \
        1 "$(echo "$HISTO" | grep -c "SUIVI.md:5 → mention de 'docs/PARTI.md'")"
verifie "une date de mise à jour périmée est comptée" \
        1 "$(echo "$HISTO" | grep -c 'Dates obsoletes       : 1')"
verifie "  le bilan additionne bien les deux" \
        1 "$(echo "$HISTO" | grep -c 'TOTAL : 2 point')"

section "Audit des .md — le dépôt lui-même sort propre"
bash "$AUDIT" "$RACINE" >/dev/null 2>&1
verifie "aucun signalement sur Candy-Plugin" 0 $?

bilan
