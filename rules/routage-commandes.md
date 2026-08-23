# Routage vers les commandes

Certaines procédures de l'utilisateur sont des commandes, pas des règles permanentes. Le
détail complet est dans la commande — ne pas improviser une version approximative,
lancer la commande.

| Ce que l'utilisateur écrit | Lancer |
|---|---|
| « debug », « debug rapide », « debug <nom du bot> » | `/debug` |
| « fin de session » — **projets bots** | `/fin-session` |
| « fin de phase », « phase X terminée » — **projets apps** | `/fin-phase` |
| « mets à jour la doc », « maj des md », ou avant un `git push` qui impacte la doc | `/maj-docs` |

Deux commandes de clôture : `/fin-session` pour les bots, `/fin-phase` pour les
apps découpées en phases.

## Règle absolue

Ne PAS demander « quel type de debug ? » ni « tu veux que je lance la commande ? ».
Le déclencheur suffit — lancer directement.

Ces commandes contiennent des étapes obligatoires (ordre des tests, un fix à la
fois, marker de phase, commit + push automatiques). Les suivre intégralement.
