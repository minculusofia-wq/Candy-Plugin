# Le contrôle universel du plugin cherche une cible « test » dans ce fichier.
# C'est ainsi que le plugin se contrôle lui-même.

.PHONY: test test-rapide

test:
	@bash tests/lancer.sh

# Le controle de fin de tour prefere cette cible quand elle existe : la suite
# complete demande dix-sept secondes, celle-ci huit.
test-rapide:
	@bash tests/lancer.sh --rapide
