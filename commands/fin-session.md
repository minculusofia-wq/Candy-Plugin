---
description: Fin de session — debug optionnel, audit des .md, chaque information dans son fichier, commit unique et push
---

# Fin de session

Quand l'utilisateur écrit "fin de session" :

## 0. Debug (OBLIGATOIRE en premier)
Décider sans poser la question — les tests sont une décision technique (voir
`rules/communication-style.md`, « Qui décide quoi ») — et l'annoncer en une
ligne : debug complet si du code a été modifié pendant la session, rien sinon.

- **Code modifié** → appliquer la procédure de `/debug` jusqu'aux tests verts et à
  la séquence de fin (tuer les processus locaux) — **sans ses étapes de commit, de
  push et de question de déploiement** : cette commande fait un commit unique à la
  fin (étape 2) et demande avant de pousser ; un déploiement se décide à part,
  avec l'utilisateur. Appliquer `/debug` en entier faisait commiter et pousser
  deux fois.

  ⚠️ La procédure de débogage n'est écrite **qu'à un seul endroit** : `/debug`.
  Elle a existé en trois exemplaires jusqu'au 2026-08-08 — ici, dans `/debug`, et
  dans un `/debug-phase` depuis supprimé — et les trois avaient divergé. Ne pas la
  recopier ici, même « pour aller plus vite ».

  Ne PAS passer à l'étape 1 tant que le projet n'est pas sain.

- **Rien de modifié** → passer directement à l'étape 1

> **Cette commande est celle des projets sans phases**, bots compris. Un projet
> découpé en phases — une app, ou un bot dont la `ROADMAP.md` a des
> `### Phase N` — se clôt avec `/fin-phase`, qui relit la porte de sortie de la
> phase et refuse de la déclarer terminée sans vérification.

## 0.5 Audit automatique des .md (OBLIGATOIRE)

Avant toute mise à jour manuelle, lancer le script d'audit qui scanne tous les .md du projet et détecte les obsolescences :

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/session-end-md-audit.sh "$(git -C "${CLAUDE_PROJECT_DIR}" rev-parse --show-toplevel 2>/dev/null || pwd)"
```

Le script vérifie 4 choses :
1. **Liens markdown cassés** (vers fichiers/dossiers supprimés) — ✗ rouge = à corriger systématiquement
2. **Mentions de fichiers/dossiers supprimés** dans les 50 derniers commits — ✗ rouge (hors journaux, décisions et `analyses/`, qui racontent le passé)
3. **Dates "Dernière mise à jour" obsolètes** sur fichiers récemment commités — ⚠ jaune
4. **Statuts contradictoires** (« à créer », « à trancher ») sur des éléments existants — ⚠ jaune

**Règle absolue :** chaque ligne ✗ rouge DOIT être corrigée avant le commit final. Les ⚠ jaunes doivent être vérifiées au cas par cas (peuvent être légitimes : questions stratégiques ouvertes, sections historiques de CHANGELOG).

Si le script retourne code 1 (issues détectées), je traite chaque point ligne par ligne, puis je relancer le script jusqu'à ce qu'il ne reste aucun ✗ rouge. Un ⚠ jaune vérifié et légitime peut rester : le script sort alors encore en code 1, ce n'est pas un échec.

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

**Le jeu de documents** : lancer `python3 -I ${CLAUDE_PLUGIN_ROOT}/hooks/jeu-de-documents.sh "$(git -C "${CLAUDE_PROJECT_DIR}" rev-parse --show-toplevel 2>/dev/null || pwd)"`
et reporter sa sortie au résumé.

**Projet existant qui s'écarte du jeu** (`MEMORY.md`, skill projet, stratégie
dans le README… — une variante de nom comme `strategy-spec.md` n'est pas un
écart, le contrôle l'accepte) : écrire dans le fichier qui porte **déjà** le
sujet — en créer un du jeu à côté ferait une deuxième copie. Signaler l'écart au
résumé, sans restructurer : le rangement se fait projet par projet, à la demande
de l'utilisateur — **sauf** pour un projet qui a une roadmap : avant sa phase
suivante, l'alignement est une condition d'entrée, à faire en tête de la
conversation suivante sans attendre (`une-info-un-fichier.md`, « Exception »).

## 2. Commit unique + push
Un SEUL commit final regroupant code (si debug fait) + la documentation mise à jour.
- Message clair en français résumant la session
- Le commit se fait sans demander
- Jamais le marqueur `cloture(phase N)` ni « LIVREE » : ce commit ne clôt pas de
  phase (c'est `/fin-phase`), et le hook de clôture le refuserait
- **Le push, lui, se demande** : montrer le message de commit et attendre le
  feu vert avant d'envoyer
- Pas de commit "docs: maj" séparé

## 3. Résumé
- Debug fait ou non (et résultat si oui)
- Quels fichiers de documentation ont reçu quoi, et pourquoi celui-là
- Les écarts du projet à la règle, signalés et non corrigés — la sortie du
  contrôle du jeu de documents
- État final du projet
