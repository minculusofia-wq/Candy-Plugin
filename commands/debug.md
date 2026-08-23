---
description: Debug complet du projet en local (backend, frontend, endpoints, tests) avec correction bug par bug
---

# Debug Workflow

Quand l'utilisateur dit "debug" (tout seul ou suivi du nom d'un bot) :

IMPORTANT : Toujours debugger EN LOCAL sur la machine de l'utilisateur, jamais sur un VPS.
Même si le bot tourne sur un VPS en production, le debug se fait sur la copie locale.
L'utilisateur redéploiera ensuite avec son propre script de déploiement.

## "debug" = debug COMPLET de tout le projet
1. Identifier le projet via le working directory courant
2. Lire le code pour comprendre la stack (FastAPI, Node, etc.)
3. Lancer le backend (et frontend si applicable) EN LOCAL
4. Vérifier les logs pour erreurs/warnings
5. Tester TOUS les endpoints et fonctionnalités du projet — pas seulement le dernier travail. Les bugs peuvent venir de modifications précédentes.
6. Corriger UNE erreur à la fois, puis re-tester avant de passer à la suivante
7. Après toutes les corrections, faire un test complet EN MODE DRY RUN (s'assurer que DRY_RUN=true dans .env local) pour vérifier qu'aucune régression n'a été introduite et que le bot fonctionne correctement sans placer de vrais ordres
8. Si un dossier tests/ existe dans le projet, lancer tous les tests et vérifier que tout passe. Si les tests échouent après un fix, le fix est mauvais — l'annuler et chercher une autre approche

## "debug rapide" = debug du DERNIER travail uniquement
1. Identifier ce qui vient d'être modifié (git diff ou contexte de la conversation)
2. Lancer le serveur EN LOCAL en mode DRY RUN
3. Tester uniquement les fonctionnalités liées au dernier changement
4. Corriger si nécessaire
5. Vérifier rapidement que l'existant n'est pas cassé

## SÉQUENCE DE FIN (obligatoire après debug complet ou rapide)
1. Tuer tous les processus locaux lancés pendant le debug (uvicorn, next dev, node, python)
2. Vérifier qu'aucun processus ne tourne en arrière-plan sur les ports du projet
3. Git commit avec message clair en français : "fix: [description des bugs corrigés]"
4. Git push automatiquement
5. Ne PAS demander à l'utilisateur pour le commit/push — le faire directement
6. Demander à l'utilisateur : "Debug terminé, tous les tests passent. Tu veux que je déploie sur le VPS ?"
7. Si l'utilisateur dit oui → lancer le script de déploiement du projet (deploy_to_vps.sh ou équivalent)
8. Si l'utilisateur dit non → s'arrêter là

RÈGLES ANTI-RÉGRESSION :
- Ne JAMAIS corriger plusieurs bugs en même temps — un fix, un test, puis le suivant
- Avant de modifier du code, comprendre POURQUOI il est écrit comme ça (il peut y avoir une raison)
- Ne modifier QUE le code lié au bug — ne pas refactorer ou "améliorer" le code autour
- Après chaque fix, relancer le serveur et vérifier que les fonctionnalités existantes marchent encore
- Si un fix casse autre chose, annuler le fix et chercher une autre approche

Ne PAS demander de précisions, ne PAS demander "quel type de debug".
Ne PAS proposer de debugger sur le VPS ou donner des commandes SSH.
Ne PAS donner des commandes à taper — exécuter soi-même.
L'utilisateur n'est pas dev, il délègue toute la partie technique à Claude.
