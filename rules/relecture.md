# Relecture : `/code-review` et les relecteurs

`/code-review` est une dépense de l'utilisateur : beaucoup de quota aux niveaux
locaux, des crédits pour `ultra` après ses passages gratuits. Claude la propose,
avec la commande exacte et la raison en une ligne, et ne la lance jamais
lui-même, même si Claude Code le lui permet (le verrou est décrit dans
`/fin-phase`, étape 3). La proposer à tort use ce qui la rend utile : que
l'utilisateur la prenne au sérieux quand elle arrive.

La proposer, c'est dire d'office, dans le même message :
- **quand** : avant ce qui éprouve le code (essai sur l'appareil, prompt de la
  conversation suivante), parce qu'elle peut le changer — l'étape 1 de l'essai
  ne se donne qu'une fois ses constats traités ;
- **où** : à taper ici, dans cette conversation, où ses constats reviennent à
  Claude qui les corrige — sans en changer au message suivant ;
- **une cible à la fois** ; et quand aucune n'est utile, le dire en une ligne.

## Quand la proposer

La question qui tranche : **si ce code se trompe, le verrait-on tard, et
est-ce que ça coûterait cher — en argent, en sécurité d'une personne, en
données perdues ou exposées ?** Une capture d'écran qui suffit à s'en
apercevoir dit non.

**Toujours — non négociable**, sur une tâche d'une des **cinq familles** (la
seule liste : `advisor.md` et `/fin-phase` y renvoient) :
1. **l'argent** : passage et annulation d'ordres, taille de position, adresse de
   dépôt ou de remboursement, validation d'adresse, envoi depuis un wallet,
   retrait, et tout calcul d'argent (commission, affiliation, classement de
   routes, edge, kelly, seuils de risque) ;
2. **les secrets, les clés, le chiffrement, le protocole** : schéma
   d'environnement, authentification, dérivation de clé, format de coffre,
   valeur de protocole, tout ce qui peut finir dans un journal, une sortie de CI
   ou un fichier commité ;
3. **les données personnelles ou enregistrées** : base, sauvegarde et
   restauration, coordonnées, position, micro ;
4. **une alerte qui doit partir** : chemin d'une alerte, notification d'urgence —
   un défaut y reste muet jusqu'au jour où il compte ;
5. **l'irréversible** : migration, purge, suppression, changement de format de
   stockage, déploiement, passage en réel, publication.

**Jamais** : de la documentation seule, des chaînes de traduction seules, un
affichage qui ne calcule rien de neuf, un diagnostic qui ne change aucun
comportement d'exécution.

**Entre les deux** (table de correspondance, script de contrôle, colonne de
tableau de bord, refactor sans changement de comportement) : les deux
relecteurs gratuits d'abord, et n'escalader que s'ils remontent du structurel.

## Quel niveau

| Ce qui est relu | Niveau proposé |
|---|---|
| Le cœur de l'argent ou d'une clé, sur une cible étroite (passage d'ordre, envoi depuis un wallet, dérivation de clé, format de coffre) | `max` sur cette cible seule, en prévenant qu'il peut buter sur la limite d'usage ; `xhigh` en repli |
| Une des cinq familles, sur quelques fichiers ou une phase entière | `xhigh`, ciblé sur les fichiers concernés ou la plage de commits sans la documentation seule |
| Entre les deux, quand les gratuits ont remonté du structurel | `high`, ciblé |

Jamais `max` par réflexe : il bute sur la limite d'usage avant la fin.
**Toujours une cible** — une plage `<base>...<fin>` ou un dossier : tout étant
commité, une relecture sans cible ne relit que ce qui ne l'est pas.

## Les relecteurs gratuits

`relecteur-securite` et `relecteur-de-phase` (les agents fournis par le
plugin) : sans facturation à part ni coût de contexte — ils consomment tout de
même le quota. Les passer à chaque fin de phase est le défaut, pas l'exception.

- Relancer un relecteur après une correction : lui donner le numéro du tour,
  les constats déjà rapportés et le commit du passage précédent (section
  « Relecture en plusieurs tours » des deux agents) — sinon il relit tout et
  redit les mêmes constats.
- Au troisième tour qui trouve encore : arrêter de corriger et revoir
  l'approche (`reflexes-de-travail.md` §4).
- Pas de REVIEW.md dans les projets : `/code-review` ne le lit pas. Les pièges
  à relire vont dans le `CLAUDE.md` du projet.
