# Plan de correction — suite à la revue de code

> Écrit le 2026-08-24, après une relecture du commit `ae23348` (« des tests
> automatiques : le plugin se contrôle enfin lui-même »).
>
> **Chaque constat ci-dessous a été rejoué en exécution réelle avant d'être
> écrit ici.** Ne pas re-diagnostiquer : corriger.
>
> À supprimer du dépôt une fois le chantier terminé.

## Pourquoi ce document existe

Le chantier de correction du matin s'est bien passé : huit défauts corrigés
depuis un plan écrit, chacun avec son test de preuve.

L'après-midi, la même session a ajouté une suite de tests automatiques et
corrigé un défaut de sa propre initiative, sans plan. Elle a réintroduit le
défaut numéro un du chantier du matin sans le voir, parce que le test qu'elle
venait d'écrire pour l'en empêcher ne couvre que le cas qu'elle avait en tête.

C'est la raison d'être de ce document et d'une session neuve : l'auteur d'un
code est le moins bien placé pour relire ce qu'il vient d'écrire.

---

## PRIORITÉ 1 — le faux feu vert est de retour

**Fichier :** `hooks/verifier-projet.sh`, lignes 79-92

**Le défaut.** Le garde ajouté l'après-midi ne cherche des fichiers de test
Python que dans trois dossiers : `.`, `tests` et `test`. Toute autre
disposition — et ce sont les plus courantes — n'est plus détectée, pytest n'est
pas lancé, et le projet est déclaré vert alors que sa suite échoue.

**Test qui le prouve (rejoué, confirmé).** Un projet contenant :
- un `Makefile` dont la cible `test` réussit
- une suite en échec dans `tests/unit/test_ko.py`

affiche `TOUT PASSE` et sort en **0**. Confirmé aussi pour `backend/tests/` et
`src/tests/`.

Sans Makefile, le même projet rend le verdict `AUCUN MOYEN DE VERIFICATION
TROUVE` en sortie 2 — que `controle-si-code-modifie.sh` traduit en « ne bloque
pas ». La fin de tour est donc autorisée sur une suite cassée.

**Pourquoi le test ne l'a pas vu.** `tests/01-verifier-projet.sh` range ses
fichiers d'exemple à plat, dans `tests/test_ko.py`. Le cas imbriqué n'existe pas
dans la suite.

**Ce qu'il faut.** Ne pas deviner à la place de pytest. Pytest distingue déjà
« aucun test collecté » (code 5) d'un vrai échec. Traiter le code 5 dans la
fonction `lancer` comme « ce contrôle n'existe pas ici » — ni échec, ni contrôle
trouvé — couvre toutes les dispositions que pytest sait lire : dossiers
imbriqués, `conftest.py`, `testpaths` d'un `pyproject.toml`, motifs de nommage
personnalisés. L'approche par liste de dossiers devra être rallongée
indéfiniment, et rate déjà les trois dispositions les plus répandues.

**Critère de réussite.**
1. Le projet `Makefile` + `tests/unit/test_ko.py` sort en **1** et liste
   `ECHEC pytest`.
2. Idem pour `backend/tests/` et `src/tests/`.
3. Le dépôt Candy-Plugin lui-même, dont les tests sont des scripts shell, reste
   en **0** sans que pytest ne soit compté en échec.
4. Un cas imbriqué est ajouté à `tests/01-verifier-projet.sh`.

---

## PRIORITÉ 2 — deux tests qui ne peuvent pas échouer

Le fichier `tests/README.md` affirme : « un test qui passe toujours ne vaut
rien ». Ces deux-là passent toujours.

### 2a. Le contrôle « aucun hook ne plante »

**Fichier :** `tests/06-paquet.sh`, lignes 55-66

**Le défaut.** La boucle lance chaque `hooks/*.sh` avec `bash`. Or
`relire-ma-reponse.sh` est un script Python — `hooks.json` le lance d'ailleurs
avec `python3`. Sous bash il meurt sur une erreur de syntaxe et sort en 2, code
que le seuil `-gt 2` accepte comme un blocage normal.

**Vérifié.** `bash hooks/relire-ma-reponse.sh` → code 2 (erreur de syntaxe
ligne 49). `python3 hooks/relire-ma-reponse.sh` → code 0. Le test est vert dans
les deux cas.

**Ce qu'il faut.** Lancer chaque hook avec l'interpréteur que `hooks.json` lui
associe réellement, et distinguer un vrai plantage d'un blocage attendu.

**Critère de réussite.** Introduire une erreur de syntaxe dans n'importe quel
hook fait tomber ce test.

### 2b. Le contrôle « aucune dépendance à jq »

**Fichier :** `tests/06-paquet.sh`, ligne 35

**Le défaut.** Le test exclut `hooks/controle-si-code-modifie.sh` en entier,
pour faire taire une occurrence qui se trouve dans un **commentaire**. Ce
fichier n'est donc plus surveillé du tout.

**Vérifié.** La seule occurrence du dépôt est le commentaire de la ligne 25 de
ce fichier. Y ajouter un vrai appel à `jq` laisse le test vert — et le plugin
embarquerait une dépendance que le README promet absente.

**Ce qu'il faut.** Retirer les lignes de commentaire avant de chercher, au lieu
d'exclure un fichier.

**Critère de réussite.** Ajouter un appel réel à `jq` dans n'importe quel hook,
commentaires compris, fait tomber ce test.

---

## PRIORITÉ 3 — trois contournements de la protection des secrets

**Fichier :** `hooks/protect-secrets.sh`, lignes 53, 56, 72

**Les défauts (les trois vérifiés, code 0 = laissé passer).**

| valeur | pourquoi elle passe |
|---|---|
| une clé de vingt lettres sans aucun chiffre | ligne 72 exige un chiffre |
| une valeur commençant par `secret` | ligne 56 traite `secret` comme un mot d'exemple |
| une valeur contenant une accolade | ligne 53 exempte tout ce qui ressemble à un gabarit |

Une valeur équivalente contenant un chiffre est bien bloquée : la protection
fonctionne, mais son filtre est trop large sur ces trois axes.

**Ce qu'il faut.** Resserrer chacun des trois filtres sans réintroduire les faux
positifs corrigés le matin. Les huit cas qui doivent passer restent dans
`tests/02-protect-secrets.sh` — ils ne doivent pas bouger.

**Critère de réussite.** Les trois valeurs ci-dessus bloquent, les huit cas
légitimes passent toujours, et les trois nouveaux cas sont ajoutés à la suite.

---

## PRIORITÉ 4 — ce que la suite prétend couvrir sans le couvrir

### 4a. La fenêtre de trente minutes du témoin de phase
`tests/04-blocages.sh` ne teste que « témoin absent », « témoin frais » et
« témoin consommé ». La péremption à trente minutes
(`rule12-phase-debug-required.sh:50`) n'est jamais exercée : la supprimer laisse
les dix cas verts. Il faut un témoin daté dans le passé.

### 4b. Deux des quatre contrôles de l'audit des `.md`
`tests/05-audit-md.sh` crée son dépôt d'exemple sans aucun commit (vérifié :
zéro `git commit` dans la mise en place). Les contrôles 2 (références à des
fichiers supprimés) et 3 (dates périmées) lisent l'historique git et ne
s'exécutent donc jamais. Le compteur du contrôle 2 est justement celui qui a la
forme fautive que le groupe prétend surveiller.

### 4c. Le comptage des lignes injectées
`tests/aide.sh:68` fusionne la sortie d'erreur avec la sortie normale avant de
compter. Un hook qui plante compte comme un hook qui parle, et un simple
avertissement fait échouer les cas qui attendent le silence. Il faut compter la
sortie normale seule et vérifier qu'elle contient bien le texte de la règle.

### 4d. Le lanceur s'arrête au neuvième groupe
`tests/lancer.sh:22` cherche `tests/0*.sh`. Un dixième groupe ne serait jamais
lancé, et le bilan afficherait quand même « tout passe ».

### 4e. Les images en syntaxe markdown ne sont pas vérifiées
`tests/06-paquet.sh:69` ne regarde que les balises HTML. Une image écrite en
syntaxe markdown et pointant vers un fichier absent partirait en public sans
alerte.

---

## PRIORITÉ 5 — deux choix « à trancher », pas des défauts

### 5a. La suite exige des outils que le README dit ne pas exiger
Vérifié : sans `pytest` ni `npm` accessibles, trois cas de
`tests/01-verifier-projet.sh` échouent, plus un de `tests/04-blocages.sh`. Or
les README annoncent `python3` comme seul prérequis, et `tests/README.md`
répète que le paquet « ne dépend que de python3 ».

Deux issues : déclarer ces outils comme prérequis des tests, ou sauter les cas
concernés quand l'outil est absent en le disant clairement. Ne pas laisser un
contributeur face à une suite rouge sans explication.

### 5b. La suite tourne à chaque fin de tour
Mesuré : `make test` prend **14 secondes**. `controle-si-code-modifie.sh`
considère les fichiers `.sh` comme du code, donc toute modification d'un hook ou
d'un test déclenche la suite entière avant que le tour puisse se terminer.

C'est exactement le raisonnement qui avait fait retirer la suite complète du
contrôle avant push : « un contrôle qu'on attend finit contourné ». L'argument
vaut davantage pour un contrôle à chaque tour que pour un contrôle à chaque
push.

Décision « à trancher » : accepter les quatorze secondes, ou réserver la suite complète à
`/verifier` et ne garder qu'un sous-ensemble rapide en fin de tour.

---

## Protocole — obligatoire à chaque correction

Une correction, un test, puis la suivante. Jamais deux d'un coup.

Après chaque correction :
1. rejouer le test qui prouvait le défaut, et montrer sa sortie réelle ;
2. lancer `make test` en entier — aucune régression tolérée ;
3. pour toute correction d'un test, **remettre le défaut que ce test surveille**
   et vérifier qu'il tombe. Un test qui ne sait pas dire non ne compte pas.

**Ne jamais annoncer une correction faite sans montrer la sortie réelle.**

## Ce qu'il ne faut PAS toucher

- Les 8 règles de `rules/`, les 2 agents, `relire-ma-reponse.sh`.
- Les huit cas « qui doivent passer » de `tests/02-protect-secrets.sh` : ce sont
  les faux positifs corrigés le matin, ils ne doivent jamais redevenir rouges.
- L'anonymisation, et la convention d'assemblage des chaînes sensibles décrite
  dans `tests/README.md`.
- L'identité visuelle : ne jamais remplacer le bonbon par une image du dessin
  animé Candy Candy.

## Clôture

1. `make test` au vert, sortie montrée.
2. `bash hooks/verifier-projet.sh .` en sortie 0, sortie montrée.
3. Mettre à jour `tests/README.md` si le nombre de groupes ou de cas change.
4. Supprimer ce fichier.
5. Un seul commit, message clair en français, puis push.
