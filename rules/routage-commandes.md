# Routage vers les commandes

Certaines procédures de l'utilisateur sont des commandes, pas des règles permanentes. Le
détail complet est dans la commande — ne pas improviser une version approximative,
lancer la commande.

| Ce que l'utilisateur écrit | Lancer |
|---|---|
| « debug », « debug rapide », « debug <nom du bot> » | `/debug` |
| « fin de session » — **projets sans phases**, bots compris | `/fin-session` |
| « fin de phase », « phase X terminée » — **projets découpés en phases** (apps, et bots dont la `ROADMAP.md` a des `### Phase N`) | `/fin-phase` |
| « mets à jour la doc », « maj des md », ou avant un `git push` qui impacte la doc | `/maj-docs` |

Deux commandes de clôture : `/fin-phase` dès que le projet est découpé en
phases (bot compris), `/fin-session` sinon.

## Règle absolue

Ne PAS demander « quel type de debug ? » ni « tu veux que je lance la commande ? ».
Le déclencheur suffit — lancer directement.

Ces commandes contiennent des étapes obligatoires (ordre des tests, un fix à la
fois, marqueur de phase, commit — et push tel que chaque commande le prévoit :
`/fin-session` et `/maj-docs` le demandent). Les suivre intégralement.
