# Réflexes de travail

Cinq réflexes qui s'appliquent à tous les projets, anciens et nouveaux.

## 1. Ne jamais dire « c'est fait » sans preuve

Avant d'annoncer qu'un travail est terminé, lancer le contrôle du projet : la
commande `/verifier` du plugin, qui le lance sur la racine du dépôt.

Montrer le résultat. Pas « les tests passent » — la sortie réelle.

Si le contrôle répond qu'aucun moyen de vérification n'existe dans ce projet, en mettre un en place avant d'aller plus loin (une cible `test` dans un Makefile suffit : le contrôle la reconnaît) et l'annoncer en une ligne. Un projet sans contrôle oblige l'utilisateur à vérifier lui-même chaque modification.

## 2. Déléguer les recherches larges

Quand répondre suppose de fouiller beaucoup de fichiers — « où est géré X ? », « comment marche Y ? », « est-ce que Z existe quelque part ? » — utiliser l'agent `Explore` plutôt que lire les fichiers un par un.

Tout ce qui est lu directement encombre la conversation en cours. Un agent séparé explore de son côté et ne ramène que la conclusion.

Ne pas déléguer quand on sait déjà quel fichier ouvrir : le lire directement.

## 3. Cadrer avant de construire

Pour tout travail qui touche plusieurs fichiers, ou dont l'approche n'est pas évidente : explorer et écrire le plan **avant** de coder. Passer par le mode plan.

Sauter cette étape quand le changement tient en une phrase (corriger une faute, ajouter une ligne de log, renommer quelque chose).

**Avant d'écrire un plan**, auditer le jeu de `.md` : le contrôle du jeu de documents de `/verifier`, puis relire les documents contre le code. Corriger chaque écart **dans la même conversation, avant de livrer le plan** — jamais en faire une tâche du plan. Un plan de phases suit en plus `porte-de-phase.md` : sa première phase doit pouvoir s'ouvrir le jour où il est livré.

Pour une grosse fonctionnalité : interroger l'utilisateur d'abord avec l'outil de questions — sur le métier seulement : ce que la fonctionnalité doit faire, les cas limites vus côté utilisateur, les arbitrages de stratégie ; l'implémentation, Claude la tranche — jusqu'à ce que tout soit couvert, écrire la spec dans un fichier, puis l'exécuter dans une conversation neuve.

## 4. Repartir propre après deux échecs

Si une même erreur a été corrigée deux fois sans succès, la conversation est encombrée d'approches ratées qui polluent le raisonnement.

Le dire à l'utilisateur et proposer de repartir d'une conversation neuve avec une consigne plus précise, enrichie de ce qui a été appris. Une session propre avec une bonne consigne bat presque toujours une longue session pleine de corrections.

## 5. Un défaut repéré se dit, dans la réponse

Un défaut trouvé en travaillant — par un audit, un relecteur, un test ou une
lecture — se dit à l'utilisateur dans la réponse de la session où il est trouvé,
avec ce qu'il casse, même hors du périmètre ou de faible confiance (un constat
douteux se vérifie à la source, souvent en deux minutes). L'écrire seulement
dans une mémoire ne suffit pas : une mémoire ne se relit pas d'elle-même, et
plusieurs sessions peuvent passer devant sans rien dire. Avant un push ou une
publication, relire les points ouverts et les dire avant d'agir.
