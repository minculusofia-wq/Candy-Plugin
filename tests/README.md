# Les tests

```
make test          # les six groupes, 89 cas, environ 18 secondes
make test-rapide   # le sous-ensemble de fin de tour, environ 8 secondes
```

Six groupes, 89 cas. Chacun dit la même chose : *j'envoie ceci à ce hook,
j'attends ce verdict*.

| groupe | ce qu'il garde |
|---|---|
| `01-verifier-projet.sh` | le contrôle universel lance TOUS les contrôles trouvés, et rend les quatre verdicts justes |
| `02-protect-secrets.sh` | la protection des secrets bloque une valeur, jamais un nom de variable |
| `03-declencheurs.sh` | « source ou silence » se tait sur le travail ordinaire |
| `04-blocages.sh` | les hooks qui annoncent bloquer sortent bien en 2 |
| `05-audit-md.sh` | l'audit des `.md` compte juste et ignore ce qui est cité |
| `06-paquet.sh` | le paquet reste installable et ne dépend que de `python3` |

## Deux modes

`make test` joue tout. `make test-rapide` écarte les deux groupes les plus longs
(`01` et `02`) et les nomme à l'écran : c'est le contrôle de fin de tour, huit
secondes au lieu de dix-huit. Un contrôle qu'on attend finit contourné — mais
une couverture réduite qu'on ne dit pas se lit comme une couverture complète,
d'où les noms affichés et le renvoi vers `/verifier`.

## Les cas sautés

Le paquet ne dépend que de `python3`. Treize cas ont besoin de `pytest` ou de
`npm` pour exister — ils vérifient que le contrôle universel lance bien ces
familles. Sans ces outils, ces cas sont **sautés en le disant** (« pytest absent
de cette machine »), pas comptés pour verts. Le bilan affiche alors le nombre de
cas sautés.

## Ce que ces tests prouvent, et ce qu'ils ne prouvent pas

Ils prouvent qu'un défaut corrigé ne revient pas. Chacun a été vérifié en
remettant le défaut d'origine : les défauts des deux chantiers font tomber les
tests quand on les réintroduit. Un test qui passe toujours ne sert à rien — il
doit savoir dire non.

Une relecture a montré que cette exigence se vérifie mal soi-même : trois de ces
tests passaient toujours, et l'un d'eux couvrait le seul cas que son auteur avait
en tête pendant que le défaut revenait par un autre chemin. Remettre le défaut
ne suffit pas : il faut le remettre AILLEURS que là où on l'attend.

Ils ne prouvent rien sur ce qui n'est pas couvert. Ils ne remplacent pas une
installation réelle : deux des défauts trouvés pendant le chantier — le
manifeste refusé et la dépendance à `jq` — ne se voyaient qu'en installant le
plugin pour de vrai. `06-paquet.sh` les couvre maintenant, mais la même limite
vaut pour la suite : le prochain défaut de ce genre se trouvera de la même
façon, en s'en servant.

## Une convention à respecter

Les chaînes qui ressemblent à des secrets ou à des commandes ssh sont
**assemblées**, jamais écrites en clair. Deux raisons : les garde-fous
installés chez qui lance ces tests les intercepteraient — c'est arrivé
plusieurs fois pendant l'écriture — et un dépôt public n'a pas à contenir de
faux secrets qui déclenchent les alertes des autres.

Les outils communs sont dans `aide.sh`.
