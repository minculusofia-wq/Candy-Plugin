# Réflexes de travail

Quatre réflexes qui s'appliquent à tous les projets, anciens et nouveaux.

## 1. Ne jamais dire « c'est fait » sans preuve

Avant d'annoncer qu'un travail est terminé, lancer le contrôle du projet :

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/verifier-projet.sh "$PWD"
```

Montrer le résultat. Pas « les tests passent » — la sortie réelle.

Si le script répond qu'aucun moyen de vérification n'existe dans ce projet, le dire à l'utilisateur et proposer d'en mettre un en place avant d'aller plus loin. Un projet sans contrôle oblige l'utilisateur à vérifier lui-même chaque modification.

## 2. Déléguer les recherches larges

Quand répondre suppose de fouiller beaucoup de fichiers — « où est géré X ? », « comment marche Y ? », « est-ce que Z existe quelque part ? » — utiliser l'agent `Explore` plutôt que lire les fichiers un par un.

Tout ce qui est lu directement encombre la conversation en cours. Un agent séparé explore de son côté et ne ramène que la conclusion.

Ne pas déléguer quand on sait déjà quel fichier ouvrir : le lire directement.

## 3. Cadrer avant de construire

Pour tout travail qui touche plusieurs fichiers, ou dont l'approche n'est pas évidente : explorer et écrire le plan **avant** de coder. Passer par le mode plan.

Sauter cette étape quand le changement tient en une phrase (corriger une faute, ajouter une ligne de log, renommer quelque chose).

Pour une grosse fonctionnalité : interroger l'utilisateur d'abord avec l'outil de questions — implémentation, cas limites, arbitrages — jusqu'à ce que tout soit couvert, écrire la spec dans un fichier, puis l'exécuter dans une conversation neuve.

## 4. Repartir propre après deux échecs

Si une même erreur a été corrigée deux fois sans succès, la conversation est encombrée d'approches ratées qui polluent le raisonnement.

Le dire à l'utilisateur et proposer de repartir d'une conversation neuve avec une consigne plus précise, enrichie de ce qui a été appris. Une session propre avec une bonne consigne bat presque toujours une longue session pleine de corrections.
