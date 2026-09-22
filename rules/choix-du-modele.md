# Choix du modèle et du niveau d'effort

Conseiller le cran le plus pertinent **au démarrage d'une tâche**, jamais au
milieu — changer de modèle, et sur la plupart des modèles changer d'effort, en
cours de session vide le cache et fait re-payer tout le contexte accumulé (doc
Claude Code, prompt-caching, « Changing effort level » ; Fable 5.1 garde son
cache quand l'effort change, avec une clé API ou un abonnement Claude).

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

Avant le premier message, c'est là qu'ils ne coûtent rien. Ils ne sont pas
verrouillés pour autant : `/effort <cran>` change le curseur à tout moment, même
pendant que Claude travaille, au prix d'une relecture sans cache de toute la
conversation.

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

### La bascule que personne n'a demandée : le message signalé

Fable 5.1, Fable 5 et Opus 5.5 passent chaque requête à des classifieurs de
sécurité. Par défaut, une requête signalée en cybersécurité est relancée sur
Opus 4.8, en biologie sur Opus 5 — et **toute la suite de la session reste sur
cet ancien modèle**, avec un simple avis dans la transcription (doc Claude Code,
model-config, « Automatic model fallback »). Le contrôle porte sur tout le
contexte, CLAUDE.md et état git compris : un dépôt qui parle de sécurité peut
déclencher la bascule dès la première requête.

Pour décider soi-même, mettre dans `~/.claude/settings.json` :

```json
{ "switchModelsOnFlag": false }
```

(ou `/config` → « Switch models when a message is flagged »). La session se met
alors en pause : passer sur l'ancien modèle, ou reformuler sur le modèle
courant. En mode non interactif (`claude -p`), la requête signalée s'arrête sur
une erreur au lieu de basculer.

Quand cette pause arrive, Claude le signale en une ligne et propose de
reformuler plutôt que de basculer.

## Relecture : `/code-review`

`/code-review max` pour une relecture large. `/code-review ultra` existe aussi,
en nombre d'usages limité par compte — le garder pour ce qui le mérite.

En complément, gratuits et sans coût de contexte : les subagents
`relecteur-securite` et `relecteur-de-phase` (les agents fournis par le plugin).

## Format du conseil, et quoi faire si le cran se révèle trop bas

Une ligne, avant de commencer, avec le motif et le gain attendu. Pas une question
qui bloque : L'utilisateur applique ou ignore. Ce conseil est écrit par `/fin-phase`
dans `.claude-phase-suivante` et relu par le hook `ouverture-de-phase.sh`.

Claude ne peut pas changer le cran lui-même ; l'utilisateur le peut, avec
`/effort`. Mais **se taire quand il est trop bas est une faute** — le dire en une
ligne sans arrêter le travail, avec la commande à taper :

> « Ce travail touche <zone> : il mérite `max`. Tape `/effort max` — la
>   prochaine réponse relira la conversation sans cache. Je continue en
>   attendant. »

Au début d'une conversation → `/effort` tout de suite, ça ne coûte presque rien.
En pleine conversation → le coût est une relecture complète : `/effort` si la
suite est sensible, sinon finir et compenser par `/code-review max` à la sortie.
Après deux corrections ratées sur le même défaut, le problème n'est plus le cran
mais le contexte encombré : conversation neuve, au bon cran (voir
`reflexes-de-travail.md`, « Repartir propre après deux échecs »).

**Interdit** : proposer une bascule de modèle au milieu d'une tâche engagée ;
descendre sur une zone sensible ; changer de modèle ou d'effort sans le dire.
