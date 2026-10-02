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

## Commandes intégrées à proposer

Claude ne peut pas les lancer : il les propose en une ligne, avec la commande à
taper, sans s'arrêter. `/effort`, `/advisor` et `/code-review` sont déjà
proposés par `choix-du-modele.md` — pas répétés ici. Source : doc Claude Code,
`commands.md`, relue le 2026-10-02.

| Quand Claude constate… | Proposer |
|---|---|
| Une mauvaise direction prise, du code à défaire | `/rewind` — ramène le code et la conversation à un point précédent |
| Une conversation longue, ou un deuxième échec sur le même défaut | `/context` (ce qui remplit la conversation), puis `/clear` |
| Une question de l'utilisateur hors du sujet en cours | `/btw <question>` — répondue sans entrer dans l'historique |
| Une longue tâche finie, ou un doute sur la dépense | `/usage` — coût de la session et limites du forfait |

## Règle absolue

Ne PAS demander « quel type de debug ? » ni « tu veux que je lance la commande ? ».
Le déclencheur suffit — lancer directement.

Ces commandes contiennent des étapes obligatoires (ordre des tests, un fix à la
fois, marqueur de phase, commit — et push tel que chaque commande le prévoit :
`/fin-session` et `/maj-docs` le demandent). Les suivre intégralement.
