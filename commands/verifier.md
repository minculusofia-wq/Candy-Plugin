---
description: Lancer le controle complet du projet courant (tests, qualite, types, securite) et rendre le verdict
---

# Contrôle du projet

Lancer le contrôle universel sur le projet courant :

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/verifier-projet.sh "$PWD"
```

Le script détecte seul comment vérifier le projet — Makefile, tests Python, projet Node — sans configuration préalable.

## Interpréter le résultat

**Tout passe** → annoncer le verdict en une ligne, avec la liste des contrôles qui sont passés.

**Un ou plusieurs échecs** → le travail n'est pas terminé. Corriger **un seul** problème, relancer le contrôle, puis passer au suivant. Ne jamais corriger plusieurs choses d'un coup : en cas de régression, on ne sait plus laquelle est en cause.

**Aucun moyen de vérification trouvé** → c'est le cas le plus important. Le projet n'a rien qui permette de savoir si une modification casse quelque chose.

Dans ce cas :
1. Le dire clairement à l'utilisateur
2. Regarder ce que fait le projet et proposer le contrôle minimal qui a du sens pour lui
3. Pour un bot de trading, le contrôle doit **obligatoirement** inclure le mode simulation — aucun ordre réel ne part pendant les tests
4. Une fois en place, relancer le contrôle et vérifier qu'il passe

## Règle

Ne jamais annoncer qu'un travail est terminé sans avoir lancé ce contrôle et montré son résultat. « Ça a l'air bon » n'est pas un verdict.
