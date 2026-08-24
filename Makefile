# Le contrôle universel du plugin cherche une cible « test » dans ce fichier.
# C'est ainsi que le plugin se contrôle lui-même.

.PHONY: test

test:
	@bash tests/lancer.sh
