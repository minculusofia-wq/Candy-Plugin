---
description: Lancer le controle complet du projet courant (tests, qualite, types, securite, jeu de documents) et rendre le verdict
---

# Contrôle du projet

Lancer le contrôle universel sur la racine du dépôt — pas sur le dossier courant,
qui glisse souvent dans `backend/` ou `ios/` au fil d'une session :

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/verifier-projet.sh "$(git -C "${CLAUDE_PROJECT_DIR}" rev-parse --show-toplevel 2>/dev/null || pwd)"
```

Le script détecte seul comment vérifier le projet — Makefile, tests Python, projet Node — sans configuration préalable.

## Interpréter le résultat

**Tout passe** → annoncer le verdict en une ligne, avec la liste des contrôles qui sont passés.

**Un ou plusieurs échecs** → le travail n'est pas terminé. Corriger **un seul** problème, relancer le contrôle, puis passer au suivant. Ne jamais corriger plusieurs choses d'un coup : en cas de régression, on ne sait plus laquelle est en cause.

**Aucun moyen de vérification trouvé** → c'est le cas le plus important. Le projet n'a rien qui permette de savoir si une modification casse quelque chose.

Dans ce cas :
1. Le dire clairement à l'utilisateur
2. Regarder ce que fait le projet et mettre en place le contrôle minimal qui a du sens pour lui — une cible `test` dans un `Makefile` suffit, le contrôle la reconnaît — puis l'annoncer en une ligne
3. Pour un bot de trading, le contrôle doit **obligatoirement** inclure le mode simulation — aucun ordre réel ne part pendant les tests
4. Une fois en place, relancer le contrôle et vérifier qu'il passe

## Le jeu de documents

Puis lancer le contrôle du jeu de documents (`rules/une-info-un-fichier.md`) sur
la même racine, et montrer sa sortie :

```bash
python3 -I ${CLAUDE_PLUGIN_ROOT}/hooks/jeu-de-documents.sh "$(git -C "${CLAUDE_PROJECT_DIR}" rev-parse --show-toplevel 2>/dev/null || pwd)"
```

🔴 un fichier obligatoire manque ou un lien est cassé ; 🟡 un fichier est hors du
jeu, ou `CLAUDE.md` est trop long. Ce bilan ne change pas le verdict du contrôle
du projet, mais un 🔴 est un point rouge de la porte de phase
(`rules/porte-de-phase.md`, point 4). Le même contrôle tourne à chaque ouverture
de session.

## Règle

Ne jamais annoncer qu'un travail est terminé sans avoir lancé ce contrôle et montré son résultat. « Ça a l'air bon » n'est pas un verdict.
