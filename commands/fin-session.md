---
description: Fin de session — debug optionnel, audit des .md, chaque information dans son fichier, commit unique et push
---

# Fin de session

Quand l'utilisateur écrit "fin de session" :

## 0. Question debug (OBLIGATOIRE en premier)
Demander à l'utilisateur : "Debug complet avant la suite ? oui/non"

Attendre sa réponse avant de continuer.

- Si **oui** → appliquer la procédure de `/debug`, version **complète**, sans en
  sauter une étape (y compris la séquence de fin : tuer les processus locaux).

  ⚠️ La procédure de débogage n'est écrite **qu'à un seul endroit** : `/debug`.
  Elle a existé en trois exemplaires jusqu'au 2026-08-08 — ici, dans `/debug`, et
  dans un `/debug-phase` depuis supprimé — et les trois avaient divergé. Ne pas la
  recopier ici, même « pour aller plus vite ».

  Ne PAS passer à l'étape 1 tant que le projet n'est pas sain.

- Si **non** → passer directement à l'étape 1

> **Cette commande est celle des bots.** Une app dont le travail est découpé en
> phases se clôt avec `/fin-phase`, qui relit la porte de sortie de la phase et
> refuse de la déclarer terminée sans vérification sur l'appareil réel.

## 0.5 Audit automatique des .md (OBLIGATOIRE)

Avant toute mise à jour manuelle, lancer le script d'audit qui scanne tous les .md du projet et détecte les obsolescences :

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/session-end-md-audit.sh "$CLAUDE_PROJECT_DIR"
```

Le script vérifie 4 choses :
1. **Liens markdown cassés** (vers fichiers/dossiers supprimés) — ✗ rouge = à corriger systématiquement
2. **Mentions de fichiers/dossiers supprimés** dans les 50 derniers commits — ✗ rouge
3. **Dates "Dernière mise à jour" obsolètes** sur fichiers récemment commités — ⚠ jaune
4. **Statuts contradictoires** (« à créer », « à trancher ») sur des éléments existants — ⚠ jaune

**Règle absolue :** chaque ligne ✗ rouge DOIT être corrigée avant le commit final. Les ⚠ jaunes doivent être vérifiées au cas par cas (peuvent être légitimes : questions stratégiques ouvertes, sections historiques de CHANGELOG).

Si le script retourne code 1 (issues détectées), je traite chaque point ligne par ligne, puis je relance le script jusqu'à ce qu'il retourne 0.

## 1. Documentation : chaque information dans son fichier

Appliquer `rules/une-info-un-fichier.md`. On ne relit pas tous les `.md` un par
un : on part de ce que la session a appris ou changé, et chaque fait s'écrit
**une fois**, dans le fichier qui porte son sujet. Pour un bot ou un service qui
tourne :

| Ce que la session a produit | Où ça va |
|---|---|
| Piège, commande, convention encore valables | `CLAUDE.md` — une ligne au sommaire des pièges, qui renvoie au détail |
| Détail d'un piège lié à des fichiers précis | `.claude/rules/<sujet>.md` avec `paths:` |
| Logique de décision, paramètres et leurs valeurs **relues dans le code** | `STRATEGY.md` |
| Récit daté : ce qui a cassé, la cause racine, le correctif, la mise en prod | `JOURNAL.md`, ajouté à la fin sous la date du jour |
| Déploiement, service, variables attendues (jamais leur valeur) | `DEPLOY.md` |
| Analyse chiffrée : backtest, résultats, étude | `analyses/<date>-<sujet>.md` |

Un fichier ne se modifie que si la session a rendu son contenu faux ou
incomplet.

**Projet existant qui s'écarte du jeu** (`MEMORY.md`, `strategy-spec.md`,
stratégie dans le README, journal sous un autre nom…) : écrire dans le fichier
qui porte **déjà** le sujet — en créer un du jeu à côté ferait une deuxième
copie. Signaler l'écart au résumé, sans restructurer : le rangement se fait
projet par projet, à la demande de l'utilisateur.

## 2. Commit unique + push
Un SEUL commit final regroupant code (si debug fait) + la documentation mise à jour.
- Message clair en français résumant la session
- Le commit se fait sans demander
- **Le push, lui, se demande** : montrer le message de commit et attendre le
  feu vert avant d'envoyer
- Pas de commit "docs: maj" séparé

## 3. Résumé
- Debug fait ou non (et résultat si oui)
- Quels fichiers de documentation ont reçu quoi, et pourquoi celui-là
- Les écarts du projet à la règle, signalés et non corrigés — dont un
  `CLAUDE.md` au-delà de 200 lignes (`wc -l CLAUDE.md`)
- État final du projet
