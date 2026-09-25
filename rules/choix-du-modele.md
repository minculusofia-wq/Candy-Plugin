# Choix du modèle et du niveau d'effort

Conseiller le couple modèle + cran **au démarrage d'une tâche**. Changer de
**modèle** en cours de session vide le cache et fait re-payer tout le contexte
accumulé. Changer de **cran d'effort**, non : sur Opus 5.5 et Fable 5.1, avec un
abonnement Claude ou une clé d'API, le cache reste intact (doc Claude Code,
prompt-caching, « Changing effort level »). Sur les autres modèles, changer
d'effort vide encore le cache.

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

Avant le premier message, c'est le plus simple. Ils ne sont pas verrouillés pour
autant : `/effort <cran>` change le curseur à tout moment, même pendant que
Claude travaille — sur Opus 5.5 et Fable 5.1, sans perdre le cache ; sur un autre
modèle, au prix d'une relecture sans cache de toute la conversation.

## Quel cran pour quelle demande

| Ce que l'utilisateur demande | Cran |
|---|---|
| Question factuelle, lecture d'un fichier | `low` |
| Explication, rapport, analyse, recherche | `medium` |
| Code ordinaire, tests, refactor simple, une phase d'écrans sans zone sensible | `high` |
| Sécurité, crypto, risque, argent réel, architecture, une phase qui touche une zone sensible | `xhigh` |
| Un problème **dur**, pas un travail **long** — voir ci-dessous | `max` |
| Phase **sensible ET large** : chiffrement, micro, position, alerte réelle | **ultracode** |

**`max` seulement dans trois cas** — une tâche grosse ne suffit pas, une phase
d'app est longue mais pas dure :
1. Le même défaut a résisté à deux corrections (repartir aussi en conversation neuve)
2. Une décision de sécurité ou de chiffrement difficile à annuler (dérivation de
   clé, format de coffre, valeur de protocole)
3. Un arbitrage d'architecture qui engage les phases suivantes

**Ultracode** : Claude découpe la tâche, lance des agents en parallèle et les fait
se contredire. Au modèle, il envoie `xhigh` ; ce qu'il ajoute, c'est
l'orchestration de workflows par Claude Code (doc model-config). Face à `max`, il
échange de la profondeur contre de la largeur ; face à `xhigh`, il garde la même
profondeur. Le plus cher, de loin. À laisser éteint pour les conversations, les
questions, la documentation, et chaque fois que le goulot est l'appareil physique de l'utilisateur —
dix agents ne trouvent pas un bouton mort.

## Changer de modèle

**Sonnet 5** seulement si les trois sont vraies : travail en volume et répétitif,
résultat vérifiable mécaniquement, aucun jugement critique. **Jamais** sur
sécurité, crypto, paramètres de risque, taille de position, exécution d'ordres,
clés/wallets/fonds réels, arbitrage d'architecture.

**Fable 5** : session autonome très longue, problème dur donné d'un bloc, migration
transverse. Signaler le surcoût et les 30 jours de conservation des données.

**Avant toute bascule** : les agents délégués n'entament pas le contexte du fil
principal. C'est le premier réflexe. Mais déléguer ne fait **pas** passer sur
Sonnet : Explore, Plan et general-purpose tournent sur le modèle de la
conversation, tant que `CLAUDE_CODE_SUBAGENT_MODEL` n'est pas réglé (doc Claude
Code, sub-agents).

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

Proposer à chaque fois **le niveau adapté à ce qui est relu**, avec la commande
exacte, sa cible et la raison en une ligne — jamais `max` par réflexe :

| Ce qui est relu | Niveau proposé |
|---|---|
| Le cœur de l'argent ou d'une clé, sur une cible étroite (passage d'ordre, envoi de fonds, dérivation de clé, format de coffre) | `max` sur cette cible seule |
| Du code qui touche des fonds, des secrets ou de l'irréversible, sur quelques fichiers ou une phase entière | `xhigh`, ciblé sur les fichiers concernés ou la plage de commits |
| Le reste, quand les relecteurs gratuits ont remonté du structurel | `high`, ciblé |

**Toujours avec une cible** — une plage `<base>...<fin>` ou un dossier : tout
étant commité, une relecture sans cible ne relit que ce qui ne l'est pas.
`/code-review max` sur tout un diff peut buter sur la limite d'usage du compte
avant la fin ; une relecture ciblée qui va au bout vaut mieux. `/code-review
ultra` tourne dans le cloud : trois passages gratuits par compte Pro ou Max, une
seule fois, puis payés en crédits (doc ultrareview, « Pricing and free runs ») —
le garder pour ce qui le mérite.

C'est une dépense de l'utilisateur : Claude la propose et ne la lance pas, même
si Claude Code le lui permet (le verrou est décrit dans `/fin-phase`, étape 3).

En complément, sans facturation à part et sans coût de contexte — ils consomment
tout de même le quota, sur le modèle de la session : les subagents
`relecteur-securite` et `relecteur-de-phase` (les agents fournis par le plugin).

## Format du conseil, et quoi faire si le cran se révèle trop bas

Une ligne, avant de commencer, avec le motif et le gain attendu. Pas une question
qui bloque : L'utilisateur applique ou ignore. Ce conseil est écrit par `/fin-phase`
dans `.claude-phase-suivante` et relu par le hook `ouverture-de-phase.sh`.

Claude ne peut pas changer le cran lui-même ; l'utilisateur le peut, avec
`/effort`. Mais **se taire quand il est trop bas est une faute** — le dire en une
ligne sans arrêter le travail, avec la commande à taper :

> « Ce travail touche <zone> : il mérite `max`. Tape `/effort max`. Je continue
>   en attendant. »

Sur Opus 5.5 et Fable 5.1, `/effort` garde le cache à tout moment : le conseiller
dès que le cran se révèle trop bas, sans attendre la sortie. Sur un autre modèle,
le changement fait relire la conversation sans cache : `/effort` si la suite est
sensible, sinon finir et compenser par une `/code-review` au niveau adapté.
Après deux corrections ratées sur le même défaut, le problème n'est plus le cran
mais le contexte encombré : conversation neuve, au bon cran (voir
`reflexes-de-travail.md`, « Repartir propre après deux échecs »).

**Interdit** : proposer une bascule de modèle au milieu d'une tâche engagée ;
descendre sur une zone sensible ; changer de modèle ou d'effort sans le dire.
