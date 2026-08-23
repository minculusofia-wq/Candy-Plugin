---
description: Fin de phase d une app — controle mecanique, porte de sortie relue point par point, ce qui exige l appareil reel, documents, commit
---

# Fin de phase

> **Note pour qui lit ce dépôt.** Ce fichier est le rituel réel de l'auteur sur une
> app iOS découpée en phases, gardé tel quel plutôt que réduit à un modèle vide :
> il cite ses documents (`ROADMAP.md`, carnet de bord), ses pièges numérotés et ses
> arbitrages datés. À lire comme un exemple à adapter, pas comme une recette
> universelle.

Quand l'utilisateur écrit « fin de phase », « phase X terminée », ou qu'une phase d'un
plan d'app vient d'être construite.

**Pour les apps.** Les bots utilisent `/fin-session`.

## Le principe, avant tout le reste

Cette commande **ne peut pas déclarer une phase terminée toute seule.**

Les pièges n°25 à 27 d'un projet réel ont tous passé les 8 contrôles au vert :
un bouton mort le jour où sa fonction est née, une pile de navigation qui survit
au verrouillage, un écran d'accueil illisible en très grande taille. Tous trouvés
par l'utilisateur sur son appareil. Aucun par un test.

Une commande qui rendrait un vert de fin de phase sans lui serait exactement le
défaut que tout ce dispositif existe pour empêcher : **un garde-fou muet pris
pour une validation.**

Elle rend donc **trois verdicts possibles, jamais deux** :

| Verdict | Ce qu'il veut dire |
|---|---|
| `ROUGE` | Un contrôle machine échoue. On s'arrête, on corrige. |
| `EN ATTENTE DE TON APPAREIL` | Tout est vert côté machine, il reste des points que l'utilisateur seul tranche. |
| `VERT` | L'utilisateur a répondu à tout. |

## 1. Situer la phase

- La phase 🟡 courante se lit dans `ROADMAP.md`, **qui fait foi**.
- Sa fiche se lit dans le carnet de bord de l'app (`ios/BUILD_PLAN.md` sur
  un projet réel — chercher l'équivalent sur un autre projet, ne pas le supposer).
- Annoncer : quelle phase, son objectif, sa porte de sortie en une ligne.

Si aucune phase n'est ouverte, le dire et s'arrêter. Ne pas en inventer une.

## 2. Contrôle mécanique

Lancer le contrôle du projet, **détecté et non supposé**, dans cet ordre :

1. `ios/verifier.sh` s'il existe → le lancer via `make verifier` depuis `ios/`
   (c'est la forme documentée comme porte de sortie ; la lancer telle qu'elle est
   écrite, au moins une fois).
2. Sinon, un `Makefile` avec une cible `verifier` ou `test` à la racine.
3. Sinon, repli : `${CLAUDE_PLUGIN_ROOT}/hooks/verifier-projet.sh "$PWD"`.

**Afficher la sortie réelle**, pas un résumé. « Les tests passent » n'est pas un
verdict.

Une seule ligne rouge ⇒ verdict `ROUGE`. Corriger **un seul** problème, relancer,
puis passer au suivant. Ne jamais corriger plusieurs choses d'un coup.

Sur ce projet, le contrôle dure environ 10 minutes depuis la phase 8. C'est normal,
ne pas le raccourcir ni le sauter.

## 3. Proposer la relecture adversariale — sans jamais la lancer

Le contrôle machine est vert. **C'est le moment de la relecture adversariale**,
avant l'appareil réel : plusieurs relecteurs indépendants qui cherchent à démolir le
travail sous des angles différents, au lieu d'un seul qui relit.

Ce qu'elle a rendu sur la phase 8 d'un projet réel : **trois fuites** que ni les 483
tests, ni la relecture ordinaire n'avaient vues (D-76, piège n°28) — après les
quatre défauts déjà trouvés sur l'appareil réel. Sept défauts sur une phase, zéro par
les tests.

Le proposer, avec le niveau d'insistance qui correspond à la phase :

| La phase touche à | Formulation |
|---|---|
| Chiffrement, clés, secrets, micro, position, données personnelles | « Cette phase touche à `<quoi>`. Je te conseille de lancer `/code-review max` avant de passer à l'appareil réel. En complément je peux passer les subagents `relecteur-securite` et `relecteur-de-phase`, qui ne coûtent rien. » |
| Écrans, navigation, réglages seulement | Le mentionner en une ligne, puis passer. |

**Ne jamais la lancer.** C'est une commande de l'utilisateur, facturée à part. Claude n'a
ni le droit ni les moyens de la déclencher — la proposer, attendre, et poursuivre
s'il passe. Un « non » ne se redemande pas deux fois dans la même phase.

Si elle est lancée, ses conclusions se traitent **avant** l'étape suivante : un
défaut trouvé ici change ce qu'il faut regarder sur l'appareil.

## 4. Relire la porte de sortie, point par point

**C'est l'étape qui décide.** Le reste ne fait que la préparer.

Extraire la ligne « Porte de sortie » de la section `### Phase N` de `ROADMAP.md`
et la découper en points distincts. Pour chacun :

- soit il est **prouvé par un test ou une capture** → le montrer, et le dire prouvé ;
- soit il exige l'appareil réel ou l'œil de l'utilisateur → il part dans la liste de l'étape 5 ;
- soit il n'est **pas fait** → verdict `ROUGE`, la phase n'est pas finie.

Poser les points **un par un**, en attendant la réponse. Ne jamais en grouper
plusieurs : L'utilisateur répond à ce qu'il lit en premier et le reste passe.

Ne jamais déclarer un point acquis parce qu'il « a l'air » fait.

## 5. Ce que seul l'appareil réel tranche

Lister explicitement, et n'en cocher aucun sans réponse de l'utilisateur :

- **Une capture réelle en `AccessibilityXXXL`**, dans les deux sens de défilement,
  pour tout écran que la phase a créé ou modifié. Un test qui vérifie
  `isHittable` ne vérifie rien de ce qui se voit : un élément peut être
  parfaitement atteignable **et** tronqué, ou posé sur un autre (piège n°27).
- **La preuve vidéo** si un écran de la phase affiche **ou reçoit** une partie
  d'un secret (piège n°20). Aucun outil en ligne de commande ne filme un appareil
  réel : cette preuve est manuelle et datée, à refaire à chaque fois.
- **Le parcours réel** de la fonction livrée, sur l'appareil — en faisant ce que
  l'écran propose, y compris les boutons que les tests n'appuient jamais
  (piège n°25).
- Tout écran enveloppé dans une couche de protection de capture : sa mise en page
  se vérifie sur appareil, jamais au simulateur seul (piège n°18).

## 6. Les documents

Ce que la phase a produit doit être écrit **avant** le commit, pas après :

- **Décisions prises pendant la phase** → `votre-app/DECISIONS.md` (ou le journal
  de décisions du projet).
- **Pièges découverts** → section « Pièges connus » de `CLAUDE.md`, numérotés à la
  suite. Un piège trouvé et non écrit sera retrouvé deux fois.
- **Carnet de bord**, **état du projet**, **changelog** → mis à jour dans le même
  mouvement. Le garde-fou au commit refuse un changement d'état de phase dans
  `ROADMAP.md` si ses documents compagnons ne bougent pas avec.
- L'entête « Dernière mise à jour » de chaque `.md` touché porte la date du jour —
  le garde-fou au commit le refuse sinon.

Puis relancer le contrôle de cohérence du projet et montrer son verdict.

## 7. Rendre le verdict

Écrire le verdict en clair, avec :

- ce qui est prouvé, et par quoi ;
- **la liste nominative de ce qui reste à vérifier**, si le verdict est
  `EN ATTENTE DE TON APPAREIL`.

## 8. Commit et push

**Sauf en `ROUGE`, le commit part.** Ne pas demander l'autorisation.

Le message de commit porte, en clair, la liste des points en attente. Une dette
écrite vaut mieux qu'un blocage contourné : bloquer ferait sauter le dispositif
au bout de deux fois.

Puis écrire le témoin que le hook de commit de phase attend, avec le verdict
dedans :

```bash
printf '%s\n' "<VERDICT> — <points en attente, un par ligne>" > "$PWD/.claude-phase-debug-done"
```

## 9. Fermer la phase — seulement en `VERT`

**Ces deux gestes n'ont lieu QUE si le verdict est `VERT`** :

- passer la phase 🟢 dans `ROADMAP.md` et propager aux documents compagnons ;
- poser l'étiquette git `phase-N-done`.

En `EN ATTENTE DE TON APPAREIL`, la phase **garde son 🟡** et **aucune étiquette
n'est posée**. Tranché par l'utilisateur le 2026-08-08 : un 🟢 et une étiquette sont des
affirmations historiques. Si elles peuvent mentir, plus rien dans la roadmap n'est
fiable.

Quand l'utilisateur revient avec ses réponses, reprendre à l'étape 5, puis fermer.

## 10. Fermer la conversation — ne PAS compacter

Une fois la phase close, dire explicitement, sans attendre que l'utilisateur le
demande :

> « Phase X close. Ouvre une conversation neuve, en mode plan, pour la phase Y —
>   ne compacte pas celle-ci. Effort conseillé : `<cran>`, parce que <motif>. »

**Le cran d'effort de la phase suivante se conseille ICI, pas là-bas.** Le
niveau d'effort est fixé avant que Claude reçoive le premier message : dans la
conversation neuve, il est trop tard pour le conseiller. C'est au moment de
fermer la phase précédente que la roadmap est ouverte et que le contenu de la
suivante est connu — le conseil ne coûte alors rien.

Lire la section `### Phase Y` de `ROADMAP.md` et appliquer la grille de
la règle « choix du modèle » :

| Ce que contient la phase | Cran |
|---|---|
| Écrans, navigation, réglages, tests, refactor — sans zone sensible | `high` |
| Sécurité, chiffrement, clés, secrets, micro, position, argent réel | `xhigh` |
| Un **arbitrage d'architecture** qui engage les phases suivantes, ou un bug déjà corrigé deux fois sans succès | `max` |
| Phase sensible **et** large — chiffrement, micro, position, déclencheurs, alerte réelle | **ultracode** — le point violet, au bout du MÊME curseur, jamais en plus d'un cran |

Une phase d'app descend rarement sous `high`, et `max` ne se conseille **pas**
parce qu'une phase est longue : une phase est longue, pas dure. En cas de doute
sur la présence d'une zone sensible : ne pas descendre.

**Ultracode est le cran au-dessus de `max`, sur le même curseur** : Claude découpe la phase et
lance plusieurs agents en parallèle qui se contredisent avant de retenir quoi que
ce soit. Le plus cher de loin. Ne pas le conseiller quand le goulot d'étranglement
de la phase est l'appareil de l'utilisateur et non la couverture de Claude — une phase
d'écrans n'en tire rien.

### DEUX réglages — et ultracode est le BOUT du curseur d'effort

⚠️ **Cette section annonçait « trois curseurs » jusqu'au 2026-08-19, et c'était
FAUX.** L'utilisateur l'a relevé en montrant sa capture de l'interface : le curseur
d'effort porte **cinq points puis un point violet au bout**. Ultracode est la
**sixième position de ce curseur**, pas un interrupteur à côté — on ne peut donc
**pas** être en `xhigh` *et* en ultracode. Le conseil donné à la clôture de la
phase 12 — « mode plan, effort `xhigh`, ultracode oui » — décrivait une
combinaison **qui n'existe pas**, et l'utilisateur a dû poser la question une seconde
fois en deux phases.

**Deux réglages, tous deux fixés AVANT le premier message :**

| Réglage | Ses positions |
|---|---|
| **Le mode** | plan / edit / auto |
| **Le curseur** | `low` · `medium` · `high` · `xhigh` · `max` · **ultracode** (violet) |

⚠️ **Ne jamais nommer un cran ET ultracode dans le même conseil.**

⚠️ Les énumérer à la file les fait lire comme une **séquence dans le temps** —
« je fais le plan en `xhigh`, puis je bascule en ultracode pour construire ».
C'est faux : le curseur ne bouge pas quand le plan est accepté, et ultracode
tourne **pendant le plan aussi**.

Écrire donc, toujours dans cette forme :

> « Deux réglages à mettre **en même temps**, avant d'envoyer ton premier
>   message : mode **plan**, curseur sur **`<cran ou ultracode>`**. »

Et donner **la phrase exacte que l'utilisateur peut taper** en ouvrant :

> « Porte d'entrée de la phase N d'abord, ne code rien. »

Cette phrase vaut mieux qu'un réglage bien compris : une consigne dans le premier
message tient quel que soit le mode, alors qu'un réglage mal lu ne se rattrape
pas. _Et il n'est pas établi que le mode plan retienne les agents lancés en
parallèle par ultracode : le dire quand on conseille les deux ensemble._

### Écrire le conseil pour qu'il survive à la fermeture de la conversation

Ce conseil est calculé **ici**, dans la conversation qui se ferme — et il sert
**là-bas**, dans celle qui s'ouvre, parfois des heures plus tard. L'utilisateur ne peut
pas s'en souvenir : le déposer dans un fichier que le hook `SessionStart`
(`${CLAUDE_PLUGIN_ROOT}/hooks/ouverture-de-phase.sh`) relira automatiquement à l'ouverture
suivante.

```bash
cat > "$PWD/.claude-phase-suivante" <<'FIN'
Phase <N+1> — <titre>
Mode : plan (non négociable pour ouvrir une phase)
Effort : <cran>, parce que <motif en une ligne>
Ultracode : <oui, parce que …> / <non, le goulot est l'appareil réel>
Relecture adversariale à la sortie : <oui, parce que …> / <non>
FIN
```

Le fichier est **remplacé** à chaque fin de phase, jamais complété : un conseil
périmé est pire que pas de conseil. Le laisser hors de git (`.gitignore`) — il
décrit un réglage de session, pas un état du projet.

**Et dire aussi si la phase qui s'ouvre méritera une relecture adversariale à sa
sortie.** C'est un autre bouton, pas un sixième cran : l'effort règle la
profondeur pendant la construction, `/code-review max` ajoute des relecteurs
indépendants sur le travail fini. Le signaler dès l'ouverture évite d'y penser
trop tard — et permet à l'utilisateur de prévoir le coût.

**Ne jamais proposer un compactage entre deux phases.** Un compactage garde un
résumé de la session : les impasses de la phase écoulée sont compressées, pas
effacées, et elles continuent d'orienter le raisonnement. Trois raisons de plus,
propres aux phases :

- **Le mode se choisit au démarrage d'une conversation.** Ouvrir une phase se
  fait en mode plan ; après un compactage, on est toujours dans la conversation
  précédente, dans son mode.
- **La porte d'entrée exige de relire les documents à froid.** Une session
  compactée croit déjà les connaître — c'est ainsi que la phase 9 d'un projet réel
  s'est ouverte sur un carnet de bord périmé de trois jours.
- **Le contexte utile est déjà écrit ailleurs** : roadmap, journal de décisions,
  carnet de bord, pièges. Une phase terminée n'a rien à transmettre par la
  mémoire de conversation.

_Le compactage garde un seul usage : **au milieu** d'une phase trop longue, quand
on ne peut pas repartir sans perdre le fil. Cette étape proposait le compactage
jusqu'au 2026-08-08 — héritée d'une règle écrite pour les bots, où le découpage
en phases était rare et le contexte moins chargé._

## Ce que cette commande ne fait jamais

- Déclarer une phase terminée sans les réponses de l'utilisateur.
- Poser une étiquette ou un 🟢 sur une phase dont un point reste en attente.
- Résumer la sortie d'un contrôle au lieu de la montrer.
- Grouper les questions de la porte de sortie.
- Proposer un compactage pour enchaîner sur la phase suivante.
- **Lancer elle-même la relecture adversariale** — elle la propose, l'utilisateur décide.
