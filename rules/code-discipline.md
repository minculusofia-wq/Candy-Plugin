# Discipline de code

## Avant de coder
- TOUJOURS lire et comprendre le code existant avant de le modifier
- Vérifier que la feature demandée n'existe pas déjà dans le projet
- Comprendre les dépendances entre les fichiers avant de toucher à quoi que ce soit

## Nouvelle feature
- Proposer un plan court à l'utilisateur AVANT de coder (2-3 lignes max, en langage simple)
- Attendre sa validation avant d'implémenter
- Après implémentation, tester la feature ET vérifier que l'existant marche encore

## Git — ceinture de sécurité
- Faire un commit AVANT de commencer à modifier du code (snapshot de l'état actuel)
- Faire un commit APRÈS chaque fix ou feature qui fonctionne
- Messages de commit clairs et en français : "fix: le bot ne s'arrête plus après 3 pertes" ou "ajout: alerte quand drawdown > 10%"
- Si un changement casse quelque chose et que le fix n'est pas évident, proposer à l'utilisateur de revenir au commit précédent
