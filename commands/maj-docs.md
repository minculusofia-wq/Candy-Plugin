---
description: Mettre a jour la documentation (.md) du projet courant selon la regle une-info-un-fichier — audit automatique, chaque information dans son fichier, commit et push
---

# Mise à jour de la documentation du projet

Mettre la documentation du projet courant d'accord avec le code, en appliquant
`rules/une-info-un-fichier.md` : chaque information dans un seul fichier.
Exécuter les étapes dans l'ordre, sans en sauter.

## Étape 1 : identifier le périmètre

1. Déterminer le projet via le working directory courant.
2. Lister tous les `.md` du projet.
3. Exclure au jugement : dépendances (`node_modules/`, `venv/`, `.venv/`), builds, fichiers générés automatiquement, dossiers `archives/`.
4. Situer le projet et son jeu attendu avec le contrôle, sans refaire son travail
   à la main :

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/hooks/jeu-de-documents.sh "$PWD"
   ```

   Il donne le type (bot ou service qui tourne, app par phases, petit projet),
   les fichiers manquants (🔴), ceux hors du jeu (🟡) et la taille de `CLAUDE.md`.
5. Annoncer à l'utilisateur le nombre de `.md` dans le périmètre et les écarts :
   la sortie du contrôle, plus ce qu'aucun script ne voit — le même sujet traité
   dans deux fichiers.

## Étape 2 : audit automatique (obligatoire)

Lancer le script d'audit sur le projet :

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/session-end-md-audit.sh "$PWD"
```

Le script vérifie 4 choses :
1. **Liens markdown cassés** (vers fichiers/dossiers supprimés) — ✗ rouge
2. **Mentions de fichiers/dossiers supprimés** dans les 50 derniers commits — ✗ rouge (hors journaux, décisions et `analyses/`, qui racontent le passé)
3. **Dates « Dernière mise à jour » obsolètes** sur fichiers récemment commités — ⚠ jaune
4. **Statuts contradictoires** (« à créer », « à trancher ») sur des éléments qui existent — ⚠ jaune

**Règle absolue :** chaque ligne ✗ rouge DOIT être corrigée. Les ⚠ jaunes sont à vérifier au cas par cas — certaines sont légitimes (questions stratégiques ouvertes, sections historiques de CHANGELOG).

Traiter chaque point ligne par ligne, puis relancer le script jusqu'à ce qu'il ne retourne plus d'erreur.

## Étape 3 : comprendre ce qui a changé

Avant de modifier un `.md`, savoir ce qui a bougé :

```bash
git log --oneline -20
git diff HEAD~5 --stat
```

Un `.md` ne se modifie **que si son contenu est devenu obsolète**. Sinon le laisser tel quel — ne pas réécrire pour réécrire.

## Étape 4 : chaque information dans son fichier

Pour chaque fait qui a bougé (étape 3), trouver **le** fichier qui porte son
sujet et l'y écrire une fois ; ailleurs, un renvoi, pas une copie. Les rôles de
`CLAUDE.md`, `.claude/rules/`, `JOURNAL.md` et `CONTEXT.md` sont dans la règle.
Les autres fichiers du jeu :

- `STRATEGY.md` (bot ou service) : la logique de décision, les paramètres et
  leur **valeur actuelle vérifiée dans le code**.
- `DEPLOY.md` (bot ou service) : déploiement, service, variables attendues —
  jamais leur valeur.
- `analyses/` (bot ou service) : une analyse chiffrée par fichier daté.
- `SPEC.md` (app) : ce que l'app doit faire. `ROADMAP.md` : l'état, en tête.
- `DECISIONS.md` (app) : une décision, sa date, son motif — ajoutée à la fin,
  jamais réécrite.
- `README.md` : pour quelqu'un d'autre que l'auteur — à quoi sert le projet en
  langage clair d'abord, puis lancement.

Un fichier ne se modifie **que si son contenu est devenu faux ou incomplet**.

**Projet existant qui s'écarte du jeu** (`MEMORY.md`, `CHANGELOG.md`,
stratégie dans le README… — une variante de nom comme `strategy-spec.md` n'est
pas un écart, le contrôle l'accepte) : écrire dans le fichier qui porte
**déjà** le sujet — en créer un du jeu à côté ferait une deuxième copie.
Signaler l'écart au résumé, sans restructurer : le rangement se fait projet par
projet, à la demande de l'utilisateur — **sauf** avant un plan de phases ou
l'ouverture d'une phase, où l'alignement est une condition d'entrée à faire
sans attendre (`une-info-un-fichier.md`, « Exception »).

## Étape 5 : règles de rédaction

- **En français**
- Stratégie avant technique (l'utilisateur lit d'abord la stratégie)
- Pas de jargon dev dans la partie stratégie
- **Valeurs exactes**, jamais « environ X » ou « autour de Y »
- Chaque chiffre ou paramètre cité doit être **relu dans le code avant d'être écrit** — pas de valeur de mémoire
- Clair et concis, pas de pavés

## Étape 6 : commit et push

Un seul commit regroupant toutes les mises à jour de documentation.
- Message clair en français décrivant ce qui a été mis à jour
- Le commit se fait sans demander
- **Le push, lui, se demande** : montrer le message de commit et attendre le
  feu vert avant d'envoyer. Un push touche ce que d'autres voient ; ça ne se
  décide pas à la place de quelqu'un.

## Étape 7 : résumé

Rendre compte en trois points :
1. Quels fichiers ont reçu quoi, et pourquoi celui-là
2. Les écarts du projet à la règle, signalés et non corrigés
3. Ce que l'audit a détecté et corrigé (liens cassés, mentions mortes, dates)
