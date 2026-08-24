# Les tests

```
make test
```

Six groupes, une soixantaine de cas. Chacun dit la même chose : *j'envoie ceci
à ce hook, j'attends ce verdict*.

| groupe | ce qu'il garde |
|---|---|
| `01-verifier-projet.sh` | le contrôle universel lance TOUS les contrôles trouvés, et rend les quatre verdicts justes |
| `02-protect-secrets.sh` | la protection des secrets bloque une valeur, jamais un nom de variable |
| `03-declencheurs.sh` | « source ou silence » se tait sur le travail ordinaire |
| `04-blocages.sh` | les hooks qui annoncent bloquer sortent bien en 2 |
| `05-audit-md.sh` | l'audit des `.md` compte juste et ignore ce qui est cité |
| `06-paquet.sh` | le paquet reste installable et ne dépend que de `python3` |

## Ce que ces tests prouvent, et ce qu'ils ne prouvent pas

Ils prouvent qu'un défaut corrigé ne revient pas. Chacun a été vérifié en
remettant le défaut d'origine : les cinq défauts majeurs du chantier font
tomber les tests quand on les réintroduit. Un test qui passe toujours ne sert à
rien — il doit savoir dire non.

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
