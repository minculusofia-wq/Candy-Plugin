# Choix du modèle et des réglages

Au démarrage de chaque tâche, Claude recommande le modèle et quatre réglages,
chacun justifié en une ligne (format : « Cinq lignes », en bas). Se taire sur
l'une des cinq lignes, y compris pour dire « non », est une faute.

## Le principe : réussir du premier coup

Le bon réglage est celui qui réussit du premier coup : on compte le coût de la
tâche entière, pas celui d'un passage.
- Dans le doute, monter d'un cran.
- Monter quand une erreur se verrait tard (calcul, argent, sécurité, données),
  quand la tâche est longue, et après un premier essai raté — monter, ne pas
  relancer au même cran.
- Un modèle plus fort à un cran plus bas vaut mieux qu'un plus faible poussé
  (Opus `high` > Sonnet `xhigh`).

## Le modèle

| Modèle | Pour |
|---|---|
| **Opus 5.5** (`claude-opus-5-5`) | le défaut pour tout ce qui écrit : code, tests, documents, configuration, migration — y compris ce qui « paraît simple » |
| **Fable 5.1** | dès le départ pour une conception qui engage des mois (architecture, modèle probabiliste, protocole, format de stockage) ; après **un** échec d'Opus sur un défaut dur, en conversation neuve ; une migration transverse donnée d'un bloc ; une longue session autonome sans l'utilisateur |
| **Sonnet 5.5** | lire, chercher, explorer, résumer — jamais de code de production, Haiku non plus |

- Fable : dire le surcoût (×2,5 sur Opus) et la conservation des données 30 jours ;
  pas pour une tâche seulement grosse. Les prix : skill `claude-api`, jamais de mémoire.
- Le modèle se choisit au démarrage : en changer en cours de session fait
  re-payer tout le contexte. Déléguer ne fait pas passer sur Sonnet : les
  subagents tournent sur le modèle de la conversation, les `relecteur-*` sur Opus.
- `"switchModelsOnFlag": false` dans `~/.claude/settings.json` (ou `/config`) :
  un message signalé par les classifieurs de sécurité met la session en pause au
  lieu de la basculer sur un ancien modèle ; à la pause, reformuler plutôt que
  basculer.

## Quatre réglages, tous recommandés d'office

Le mode (`plan` si l'approche mérite d'être vue avant d'être codée, sinon
`auto`), le curseur d'effort, ultracode et l'advisor. Les trois premiers se
mettent avant le premier message et ne bougent pas quand un plan est accepté ;
l'advisor se règle par `/advisor`. Changer l'advisor garde le cache ; changer
de cran aussi, sur Opus 5.5 et Fable 5.1 seulement.

## Le curseur d'effort

| Point de départ, ajusté par le principe | Cran |
|---|---|
| Lire un fichier, répondre à une question factuelle | `low` |
| Chercher, explorer, comparer des sources ; rédiger un rapport, une analyse, de la documentation | `medium` |
| Écrire du code ordinaire, des tests, un refactor | `high` |
| Écrire du code qui touche l'argent, les secrets, l'exécution d'ordres | `xhigh` |
| Décision où l'exactitude prime sur le coût : dérivation de clé, format de coffre, choix irréversible | `max` |

- Un projet sensible suit la grille comme le reste : `max` là où l'exactitude
  prime, pas par défaut. Un travail mêlé reçoit un cran par tâche, et le conseil
  propose de baisser quand la suite le permet.
- `/effort` enregistre le cran choisi comme défaut du modèle pour les sessions
  suivantes (`modelSettings`) ; `s` dans le sélecteur le garde pour la session
  seulement. Une tâche qui écrit du code : proposer le cran de la grille avant
  le premier fichier touché.
- Cran trop bas en cours de route : le dire en une ligne, sans s'arrêter —
  « Ce travail touche <zone> : tape `/effort <cran>` (cache gardé), je continue. »

## Ultracode

Des agents en parallèle qui se contredisent ; `/effort ultracode` l'ajoute sans
changer le cran. Claude le recommande de lui-même quand les deux réponses sont
oui — un seul non, et c'est non :
1. Le travail se découpe-t-il en morceaux indépendants ?
2. Une erreur se verrait-elle tard, ou coûterait-elle cher ?

Toujours non sur une chaîne de raisonnement unique (une conception, c'est
Fable), et quand le goulot n'est pas le calcul : l'appareil de l'utilisateur,
une donnée qui n'existe pas encore, une décision qui lui revient.

## Advisor

Un renfort : Opus travaille, Fable conseille aux moments qui décident, sur une
tâche d'une des cinq familles de `relecture.md`. Quand le consulter, quand
c'est de l'argent jeté, ce qu'il n'est pas : `advisor.md`.

## Cinq lignes

Avant de commencer, chacune avec son motif — pas une question qui bloque,
l'utilisateur applique ou ignore. Le modèle se dit même quand c'est celui de la
session.

> Modèle : <Opus 5.5 / Fable 5.1 / Sonnet 5.5>, parce que …
> Mode : <plan / auto>, parce que …
> Effort : <low … max>, parce que …
> Ultracode : <oui / non>, parce que …
> Advisor : <consulté avant … / pas consulté / `/advisor fable` / `/advisor off`>, parce que …

**Interdit** : proposer une bascule de modèle au milieu d'une tâche engagée ;
descendre sur une zone sensible ; changer de modèle ou d'effort sans le dire.
