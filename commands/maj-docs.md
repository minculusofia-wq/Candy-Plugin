---
description: Mettre a jour tous les fichiers .md du projet courant (README, CLAUDE.md, MEMORY.md, specs, docs) — audit automatique, correction des obsolescences, commit et push
---

# Mise à jour de toute la documentation du projet

Mettre à jour **tous** les fichiers `.md` du projet courant, pas seulement le README. Exécuter les étapes dans l'ordre, sans en sauter.

## Étape 1 : identifier le périmètre

1. Déterminer le projet via le working directory courant.
2. Lister tous les `.md` du projet.
3. Exclure au jugement : dépendances (`node_modules/`, `venv/`, `.venv/`), builds, fichiers générés automatiquement, dossiers `archives/`.
4. Annoncer à l'utilisateur le nombre de `.md` dans le périmètre.

## Étape 2 : audit automatique (obligatoire)

Lancer le script d'audit sur le projet :

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/session-end-md-audit.sh "$PWD"
```

Le script vérifie 4 choses :
1. **Liens markdown cassés** (vers fichiers/dossiers supprimés) — ✗ rouge
2. **Mentions de fichiers/dossiers supprimés** dans les 50 derniers commits — ✗ rouge
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

## Étape 4 : mettre à jour chaque fichier selon son rôle

### README.md
- **Partie stratégie en premier** (langage business, sans jargon) : ce que fait le bot en une phrase, sur quel marché, sa logique de décision (quand il achète, quand il vend, pourquoi), les paramètres clés avec leur **valeur exacte actuelle** (lue dans le code, pas de mémoire)
- **Partie technique ensuite** : stack, lancement en local (commandes exactes), ports, variables d'environnement, structure des dossiers principaux, déploiement VPS
- Section « Pièges connus » si un piège majeur a été découvert
- Le créer s'il n'existe pas

### CLAUDE.md
- Description courte de la stratégie
- Comment lancer en local
- Ports, variables d'environnement
- Pièges connus, décisions d'architecture
- Le créer s'il n'existe pas

### MEMORY.md
- Nouveaux pièges découverts → fiche dédiée
- Décisions d'architecture récentes
- Bugs importants + cause racine
- Le créer s'il n'existe pas

### strategy-spec.md (si présent)
- Logique de décision si elle a évolué
- Paramètres clés et **valeurs actuelles vérifiées dans le code**

### CHANGELOG.md (si présent)
- Ajouter les changements non encore consignés
- Ne jamais réécrire les entrées historiques

### Tous les autres .md
Même critère : modifier uniquement si obsolète.

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
- Push automatique
- Ne PAS demander à l'utilisateur pour le commit/push — le faire directement

## Étape 7 : résumé

Rendre compte en trois points :
1. Quels `.md` ont été modifiés et pourquoi
2. Quels `.md` ont été vérifiés mais laissés tels quels
3. Ce que l'audit a détecté et corrigé (liens cassés, mentions mortes, dates)
