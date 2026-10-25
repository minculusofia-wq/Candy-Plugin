# Advisor — un renfort aux moments qui décident

Opus fait le travail ; l'advisor (Fable) relit toute la conversation et conseille,
puis Opus continue. Il se règle une fois sur Fable (`/advisor fable`, enregistré
dans `advisorModel` ; sur les plans où Fable se facture en crédits d'usage,
`/model fable` donne d'abord le consentement). Ce qui fait ensuite son utilité et
sa dépense, c'est **quand** Claude le consulte — et ça, cette règle le fixe
(aucun réglage ne force ni ne plafonne les appels ; les consignes, si).

Chaque consultation coûte cher et fait attendre plusieurs minutes : il relit
toute la conversation, sans cache, d'autant plus qu'elle est longue.

## Qui fait quoi

| Cas | Réglage |
|---|---|
| La difficulté est dans chaque étape : conception qui engage des mois, défaut dur sur lequel Opus a échoué | tout sur Fable, en conversation neuve, et `/advisor off` (Fable conseillé par Fable n'apporte rien) |
| Le travail est courant, mais une erreur coûterait cher : une tâche d'une des cinq familles de `relecture.md` | Opus, et l'advisor consulté aux moments ci-dessous |
| Tout le reste : lecture, recherche, documentation, écrans, mise en page, rendu visuel | Opus seul — l'advisor reste branché, il n'est pas consulté |

## Quand le consulter, sur une tâche des cinq familles

1. **Avant de figer une décision** : l'approche, un format, une valeur de
   protocole, l'ordre d'un déploiement — même quand la tâche a l'air d'une simple
   liste de corrections : les meilleures prises viennent de décisions qui
   n'étaient pas dans la liste. Le plus tôt possible : la conversation est courte,
   l'appel coûte moins.
2. **Juste avant une étape qu'on ne peut pas défaire** : déploiement, migration
   ou purge de données, passage en réel, publication.
3. **Quand une correction a échoué sur un même défaut**, ou au troisième constat
   d'un relecteur sur la même famille de défauts : pour décider d'arrêter, de
   réduire ou de refondre — pas pour un correctif de plus (puis
   `reflexes-de-travail.md` §4).
4. **Quand son conseil contredit un fichier, un test ou un relecteur** : vérifier
   à la source, puis le reconsulter avec les faits sous les yeux, au lieu de
   suivre l'un ou l'autre.

Pas d'appel « avant de dire fini » : c'est le plus cher, et il n'apporte surtout
que des retouches — le contrôle du projet et les relecteurs font ce travail. Sauf
juste avant une livraison qu'on ne peut pas défaire (point 2).

Deux à quatre consultations par tâche suffisent. Session longue : une
conversation neuve plutôt qu'une consultation de plus. Advisor en panne (délai
dépassé, indisponible) : ne pas attendre ; sur une décision sensible, lancer un
relecteur ou un subagent Plan à la place.

## Ce qu'il n'est pas

- **Pas une preuve** : « l'advisor valide » ne remplace ni le test ni la
  relecture. Les relecteurs restent dus (`relecture.md`) : ils démontent des
  approches que l'advisor avait validées.
- **Pas dans un subagent** : un subagent (relecteurs, Explore, Plan,
  general-purpose) ne consulte jamais l'advisor. Il en hérite, et ses appels
  finissent par dépasser ceux de la session principale sans rien prouver de plus.
- **Pas sous Fable** : quand la conversation tourne sur Fable, `/advisor off`.

## Ce que Claude dit

- Dans les cinq lignes (`choix-du-modele.md`) : « Advisor : consulté avant
  <décision> / avant <étape irréversible>, parce que … », ou « Advisor : pas
  consulté, parce que … ». Coupé alors que la tâche le demande : « tape
  `/advisor fable` ».
- Après une consultation qui a changé quelque chose, une ligne à l'utilisateur :
  ce qu'elle a changé. Ses réponses ne se relisent pas dans les transcriptions :
  c'est la seule trace de ce qu'il rapporte.
