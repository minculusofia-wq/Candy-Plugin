# Choix du modèle et du niveau d'effort

Conseiller le cran le plus pertinent **au démarrage d'une tâche**, jamais au
milieu — changer de modèle en cours de session vide le cache et fait re-payer
tout le contexte accumulé.

## Deux réglages, pas trois

| Réglage | Ses positions |
|---|---|
| **Le mode** | plan / edit / auto |
| **Le curseur** | `low` · `medium` · `high` · `xhigh` · `max` · **ultracode** (violet) |

⚠️ **Ultracode est la 6ᵉ position du curseur d'effort, pas un interrupteur à
part.** On ne peut donc pas être en `xhigh` *et* en ultracode. Ne jamais nommer un
cran ET ultracode dans le même conseil.

⚠️ Les deux réglages se mettent **en même temps**, avant le premier message. Le
curseur ne bouge pas quand un plan est accepté : ultracode tourne pendant le plan
aussi, et c'est là qu'il sert le plus.

## Quel cran pour quelle demande

| Ce que l'utilisateur demande | Cran |
|---|---|
| Question factuelle, lecture d'un fichier | `low` |
| Explication, rapport, analyse, recherche | `medium` |
| Code ordinaire, tests, refactor simple | `high` |
| Sécurité, crypto, risque, argent réel, architecture, construire une phase | `xhigh` |
| Un problème **dur**, pas un travail **long** — voir ci-dessous | `max` |
| Phase **sensible ET large** : chiffrement, micro, position, alerte réelle | **ultracode** |

**`max` seulement dans trois cas** — une tâche grosse ne suffit pas, une phase
d'app est longue mais pas dure :
1. Le même défaut a résisté à deux corrections (repartir aussi en conversation neuve)
2. Une décision de sécurité ou de chiffrement difficile à annuler (dérivation de
   clé, format de coffre, valeur de protocole)
3. Un arbitrage d'architecture qui engage les phases suivantes

**Ultracode** : Claude découpe la tâche, lance des agents en parallèle et les fait
se contredire. Le plus cher, de loin. À laisser éteint pour les conversations, les
questions, la documentation, et chaque fois que le goulot est l'appareil physique de l'utilisateur —
dix agents ne trouvent pas un bouton mort.

## Changer de modèle

**Sonnet 5** seulement si les trois sont vraies : travail en volume et répétitif,
résultat vérifiable mécaniquement, aucun jugement critique. **Jamais** sur
sécurité, crypto, paramètres de risque, taille de position, exécution d'ordres,
clés/wallets/fonds réels, arbitrage d'architecture.

**Fable 5** : session autonome très longue, problème dur donné d'un bloc, migration
transverse. Signaler le surcoût et les 30 jours de conservation des données.

**Avant toute bascule** : les agents délégués tournent déjà sur Sonnet 5 et
n'entament pas le contexte du fil principal. C'est le premier réflexe.

## Relecture : `/code-review`

`/code-review max` pour une relecture large. `/code-review ultra` existe aussi,
en nombre d'usages limité par compte — le garder pour ce qui le mérite.

En complément, gratuits et sans coût de contexte : les subagents
`relecteur-securite` et `relecteur-de-phase` (les agents fournis par le plugin).

## Format du conseil, et quoi faire si le cran se révèle trop bas

Une ligne, avant de commencer, avec le motif et le gain attendu. Pas une question
qui bloque : L'utilisateur applique ou ignore. Ce conseil est écrit par `/fin-phase`
dans `.claude-phase-suivante` et relu par le hook `ouverture-de-phase.sh`.

Claude ne peut pas changer le cran en cours de conversation. Mais **se taire quand
il est trop bas est une faute** — le dire en une ligne sans arrêter le travail :

> « Deuxième correction sur le même défaut sans résultat — la cause n'est pas là
>   où je regarde. Ça mérite `max`, dans une conversation neuve. Je continue en
>   attendant. »

Au début d'une phase → rouvrir au bon cran (le code est sur le disque). Presque
finie → finir et compenser par `/code-review max` à la sortie.

**Interdit** : proposer une bascule de modèle au milieu d'une tâche engagée ;
descendre sur une zone sensible ; changer de modèle ou d'effort sans le dire.
