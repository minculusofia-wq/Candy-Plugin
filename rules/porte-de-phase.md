# Porte d'entrée d'une phase — rien ne s'ouvre sur un état faux

S'applique à deux moments, sur tout projet découpé en phases — ou qui est en
train de l'être :

- **quand Claude écrit un plan de phases** (roadmap, découpage en lots) ;
- **avant d'écrire la première ligne d'une nouvelle phase**.

Les contrôles vérifient les fichiers **touchés** par un commit, jamais ceux qui
**auraient dû** l'être. Un document d'état périmé passe donc entre les mailles, et
une session qui démarre dessus repart sur une base fausse sans que personne le voie.

## À vérifier, dans cet ordre

1. **Le contrôle du projet est vert** — lancé maintenant, sortie montrée. Pas
   « était vert tout à l'heure ». S'il n'existe aucun moyen de vérification, en
   mettre un en place avant d'aller plus loin, et l'annoncer.
2. **Le dépôt est propre** — rien de non commité.
3. **Le dépôt est poussé** — aucun commit en avance sur le distant. Le contrôle
   avant commit ne peut pas le voir : c'est à la charge de Claude.
4. **Le jeu de documents est complet, et ils disent tous la même chose.**
   - La partie mécanique : le contrôle du jeu de documents de `/verifier`, sortie
     montrée. Un 🔴 est un point rouge de la porte.
   - La partie qu'aucun script ne voit : relire les documents d'état entre eux et
     contre le code — la phase close est marquée close partout, aucun document
     n'annonce un état de contrôle périmé, aucun skill ou fichier chargé
     automatiquement ne dit le contraire du code (mode réel/simulation, valeurs).
5. **Les constats assignés à la phase sont vérifiés à la source**, pas traités
   tels quels. Sur un projet réel, trois constats d'audit sur quatre se sont révélés faux
   ou à moitié faux en allant lire le fichier cité.

## Un plan de phases commence par la porte, il ne la contient pas

Les cinq points sont une **étape préalable**, faite et verte avant que le plan
soit livré — jamais une tâche rangée dans la phase 0. **Un plan livré dont la
première phase ne peut pas s'ouvrir est un plan faux.**

Incident réel, sur un bot de trading : la remise à plat des documents avait été
rangée dans la phase 0, STRATEGY, JOURNAL et DEPLOY manquaient, et le skill
projet annonçait un mode simulation sur un bot qui tradait en réel. Claude a dit
deux fois « tu peux démarrer » après n'avoir vérifié que les points 2 et 3 —
ceux que `ouverture-de-phase.sh` contrôle seul. C'est l'utilisateur qui a dû
demander « on a tous les .md ? ».

## Ce que Claude dit avant de commencer

Une ligne par point, avec le résultat réel : tests verts et leur nombre, dépôt
propre, N commits poussés, jeu de documents vert et documents relus, constats
vérifiés. Pas « tout est à jour ».

**« Tu peux démarrer » ne se dit qu'après les cinq points**, y compris ceux
qu'aucun script ne vérifie. Un hook qui ne dit rien n'est pas un point vert.

**Si un point est rouge, la phase ne s'ouvre pas.** Le corriger d'abord, même si
c'est dix minutes de documents ennuyeux.

## Ce que cette règle ne remplace pas

La **porte de sortie** de la phase précédente, tenue par `/fin-phase` : contrôle
du projet, porte de sortie relue point par point, installation sur l'appareil,
contrôle visuel par l'utilisateur, puis commit.

Les deux se répondent : `/fin-phase` refuse de fermer une phase sans le passage
sur l'appareil réel, celle-ci refuse d'en ouvrir une sur un état faux.
