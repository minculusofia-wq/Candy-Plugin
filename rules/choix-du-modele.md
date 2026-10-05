# Choix du modèle et du niveau d'effort

Conseiller le couple modèle + cran **au démarrage d'une tâche**. Changer de
**modèle** en cours de session vide le cache et fait re-payer tout le contexte
accumulé. Changer de **cran d'effort**, non : sur Opus 5.5 et Fable 5.1, avec un
abonnement Claude ou une clé d'API, le cache reste intact (doc Claude Code,
prompt-caching, « Changing effort level »). Sur les autres modèles, changer
d'effort vide encore le cache.

## Quatre réglages, tous recommandés d'office

| Réglage | Ses positions |
|---|---|
| **Le mode** | plan / edit / auto |
| **Le curseur** | `low` · `medium` · `high` · `xhigh` · `max` |
| **Ultracode** | interrupteur oui / non, indépendant du curseur |
| **L'advisor** | non, ou un modèle conseiller (Fable) — voir « Advisor » plus bas |

**Au début de chaque tâche, Claude recommande les quatre, chacun justifié en une
ligne** (format : dernière section). Se taire sur l'un des quatre est une faute —
y compris pour dire « non » : « advisor : non, corrections listées » est une
réponse, un silence n'en est pas une.

⚠️ **Ultracode est un interrupteur indépendant du cran** (Claude Code v2.1.284
ou plus récent ; doc model-config : « a Claude Code setting rather than a model
effort level […] at whichever effort level the session runs at »). Dans le
sélecteur `/effort`, `Tab` le bascule sans toucher au cran ; `/effort ultracode`
l'allume sans changer le cran non plus (« leaves the effort level unchanged ») —
seul le drapeau de lancement `claude --effort ultracode` met aussi `xhigh`. On
peut donc conseiller « `high` + ultracode ». Avant v2.1.284, c'était une 6ᵉ
position qui remplaçait le cran.

⚠️ Mode, curseur et ultracode se mettent **en même temps**, avant le premier
message. Le curseur ne bouge pas quand un plan est accepté : ultracode tourne
pendant le plan aussi, et c'est là qu'il sert le plus. L'advisor se règle à
part, avec `/advisor` : l'activer ou le couper en cours de session garde le
cache (doc advisor, « Impact on prompt caching »).

Avant le premier message, c'est le plus simple. Ils ne sont pas verrouillés pour
autant : `/effort <cran>` change le curseur à tout moment, même pendant que
Claude travaille — sur Opus 5.5 et Fable 5.1, sans perdre le cache ; sur un autre
modèle, au prix d'une relecture sans cache de toute la conversation.

**Ce que `/effort` enregistre** (doc model-config) : un cran validé par `Entrée`
dans le sélecteur, ou tapé après `/effort`, devient le défaut **du modèle** —
enregistré sous `modelSettings` dans les réglages utilisateur — et vaut pour
les sessions suivantes ; `s` dans le sélecteur le garde pour la session
seulement. `max` ne vaut que pour la session en cours, sauf s'il vient de la
variable `CLAUDE_CODE_EFFORT_LEVEL`. Ni cette variable ni le réglage
`effortLevel` n'acceptent `ultracode` ; s'ils fixent le cran, ultracode reste
allumé à ce cran.

## Quel cran pour quelle demande

| Ce que l'utilisateur demande | Cran |
|---|---|
| Question factuelle, lecture d'un fichier | `low` |
| Explication, rapport, analyse, recherche | `medium` |
| Code ordinaire, tests, refactor simple, une phase d'écrans sans zone sensible | `high` |
| Sécurité, crypto, risque, argent réel, architecture, une phase qui touche une zone sensible | `xhigh` |
| Un problème **dur**, pas un travail **long** — voir ci-dessous | `max` |
| Phase **sensible ET large** : chiffrement, micro, position, alerte réelle | le cran qui convient **+ ultracode** |

**`max` seulement dans trois cas** — une tâche grosse ne suffit pas, une phase
d'app est longue mais pas dure :
1. Le même défaut a résisté à deux corrections (repartir aussi en conversation neuve)
2. Une décision de sécurité ou de chiffrement difficile à annuler (dérivation de
   clé, format de coffre, valeur de protocole)
3. Un arbitrage d'architecture qui engage les phases suivantes

**Ultracode** : Claude découpe la tâche, lance des agents en parallèle et les fait
se contredire. Il n'envoie rien de plus au modèle : ce qu'il ajoute, c'est
l'orchestration de workflows par Claude Code, au cran où la session tourne (doc
model-config). Il s'ajoute au cran : `max` + ultracode garde la profondeur et
ajoute la largeur. Le plus cher, de loin. À laisser éteint pour les
conversations, les questions, la documentation, et chaque fois que le goulot est
l'appareil physique de l'utilisateur — dix agents ne trouvent pas un bouton mort.

**Le test, trois questions, toutes à « oui »** — un seul « non », et ultracode
est du gaspillage :
1. **Le travail se découpe-t-il en morceaux indépendants ?** Auditer 40 fichiers
   selon 5 angles, oui. Concevoir un modèle probabiliste, non : c'est une seule
   chaîne de raisonnement, et dix agents ne la raccourcissent pas.
2. **La vérification croisée apporte-t-elle quelque chose ?** Des agents qui se
   contredisent trouvent des défauts ; des agents qui exécutent une spec claire
   font la même chose en dix exemplaires.
3. **Les subagents gratuits ne suffisent-ils vraiment pas ?** `relecteur-securite`
   et `relecteur-de-phase` couvrent déjà l'audit large d'un dépôt, sans
   facturation à part. C'est la question qui élimine la plupart des tentations.

## Changer de modèle

**Sonnet 5.5** seulement si les trois sont vraies : travail en volume et répétitif,
résultat vérifiable mécaniquement, aucun jugement critique. **Jamais** sur
sécurité, crypto, paramètres de risque, taille de position, exécution d'ordres,
clés/wallets/fonds réels, arbitrage d'architecture.

**Fable 5.1** : session autonome très longue, problème dur donné d'un bloc, migration
transverse. Signaler le surcoût et les 30 jours de conservation des données.

**Avant toute bascule** : les agents délégués n'entament pas le contexte du fil
principal. C'est le premier réflexe. Mais déléguer ne fait **pas** passer sur
Sonnet : Explore, Plan et general-purpose tournent sur le modèle de la
conversation, tant que `CLAUDE_CODE_SUBAGENT_MODEL` n'est pas réglé (sous Fable,
Explore passe sur l'Opus de l'alias `opus`) ; un subagent dont la définition
porte `model: opus` tourne sur Opus quel que soit le modèle de la conversation
(doc Claude Code, sub-agents).

### La bascule que personne n'a demandée : le message signalé

Fable, Opus 5.5, Sonnet 5.5 et Opus 5 passent chaque requête à des classifieurs
de sécurité. Par défaut, une requête signalée est relancée sur un modèle plus
ancien — sous Fable et Opus 5.5 : Opus 4.8 en cybersécurité, Opus 5 en
biologie ; sous Sonnet 5.5 : Sonnet 5 en cybersécurité, un refus en biologie —
et **toute la suite de la session reste sur cet ancien modèle**, au même cran
d'effort, avec un simple avis dans la transcription (doc Claude Code,
model-config, « Automatic model fallback »). La première requête porte
`CLAUDE.md` et l'état git : un dépôt qui parle de sécurité peut déclencher la
bascule d'entrée. `claude --safe-mode` dit si ce sont les personnalisations
(CLAUDE.md, skills, hooks) qui la déclenchent.

Pour décider soi-même, mettre dans `~/.claude/settings.json` :

```json
{ "switchModelsOnFlag": false }
```

(ou `/config` → « Switch models when a message is flagged »). La session se met
alors en pause : passer sur l'ancien modèle, ou reformuler sur le modèle
courant. En mode non interactif (`claude -p`), la requête signalée se termine
par un refus au lieu de basculer.

Quand cette pause arrive, Claude le signale en une ligne et propose de
reformuler plutôt que de basculer.

## Advisor — un conseiller plus fort, consulté en cours de tâche

Source : doc Claude Code, page « advisor ». Le modèle principal consulte, à des
moments qu'il choisit, un second modèle plus fort qui reçoit **toute la
conversation**, appels d'outils compris, et rend des conseils avant de continuer.

- **Expérimental** : « Behavior, pricing, and availability may change ». API
  Anthropic seulement (ni Bedrock, ni Vertex, ni Foundry).
- **Pairage** : le conseiller doit être au moins aussi capable que le modèle
  principal. Sous Opus 5.5 : Fable, ou Opus 5 ou plus récent ; Sonnet et Haiku
  sont refusés. Sous Fable 5.1 : Fable 5.1 seul.
- **Il relit toute la conversation à chaque consultation**, sans cache : plus la
  session est longue, plus chaque appel coûte, au tarif du modèle conseiller en
  plus du principal. Sur les plans où Fable se facture en crédits d'usage, le
  conseiller aussi.
- **Claude choisit le moment** (avant de s'engager, quand une erreur revient,
  avant de déclarer fini) ; aucun réglage ne force ni ne plafonne les appels.
- **Commandes** : `/advisor fable`, `/advisor off`, ou `claude --advisor fable`.
- **Fable conseiller, sur les plans où Fable se facture en crédits d'usage** :
  Claude Code ne l'applique qu'après le consentement unique à cette
  facturation, qui se donne par `/model fable` ; avant, `/advisor fable`
  renvoie vers `/model fable` (doc advisor, « Fable advisor and usage
  credits »).

**Recommander oui, avec Fable sous Opus 5.5** (surcoût : tarif Fable sur toute
la conversation à chaque consultation) : une conception difficile — architecture,
modèle probabiliste, protocole, format de stockage — ou un défaut qui a déjà
résisté à une correction. Un Opus conseillé par Opus apporte peu : ne pas le
recommander.

**Recommander non** : des corrections listées, de la documentation, de la
lecture ou de la recherche, une tâche courte. Le dire en une ligne quand même.

L'advisor n'est pas une relecture : il conseille pendant le travail ;
`/code-review` et les subagents relisent après.

## Relecture : `/code-review`

**Quand la proposer — la question qui tranche** : si ce code se trompe, est-ce
que quelqu'un perd de l'argent, ou est-ce qu'une capture d'écran suffit à s'en
apercevoir ?

- **Toujours** : du code qui touche des fonds (passage d'ordres, adresse de
  dépôt, envoi depuis un wallet, retrait), qui calcule de l'argent (commission,
  taille de position, seuils de risque), des secrets (schéma d'environnement,
  authentification, dérivation de clé, tout ce qui peut atterrir dans un
  journal ou un fichier commité), ou de l'irréversible (migration de base,
  purge, format de stockage).
- **Jamais** : de la documentation seule, des traductions seules, un affichage
  qui ne calcule rien de neuf, un diagnostic qui ne change aucun comportement.
  La proposer à tort use la seule chose qui la rend utile : qu'on la prenne au
  sérieux quand elle est proposée.
- **Entre les deux** : les relecteurs gratuits d'abord, et n'escalader que
  s'ils remontent quelque chose de structurel.

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

**Cinq lignes** — le modèle, puis les quatre réglages —, avant de commencer,
chacune avec son motif en une ligne. Pas une question qui bloque : l'utilisateur
applique ou ignore. Le modèle se dit même quand c'est celui de la session : en
changer se fait au démarrage d'une conversation neuve, jamais en cours de route
(le cache est lié au modèle).

> Modèle : <Opus 5.5 par défaut / Sonnet 5.5 si les trois conditions de « Changer de modèle » sont vraies / Fable 5.1 pour un problème dur donné d'un bloc>, parce que …
> Mode : <plan / auto>, parce que …
> Effort : <low … max>, parce que …
> Ultracode : <oui / non>, parce que …
> Advisor : <non / Fable, surcoût à chaque consultation>, parce que …

Ce conseil est écrit par `/fin-phase` dans `.claude-phase-suivante` et relu par
le hook `ouverture-de-phase.sh` ; le hook `rappel-reglages.sh` rappelle ce format
à chaque ouverture de session.

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
