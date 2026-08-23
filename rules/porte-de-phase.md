# Porte d'entrée d'une phase — rien ne s'ouvre sur un état faux

S'applique **avant d'écrire la première ligne d'une nouvelle phase**, sur tout
projet découpé en phases.

Les contrôles vérifient les fichiers **touchés** par un commit, jamais ceux qui
**auraient dû** l'être. Un document d'état périmé passe donc entre les mailles, et
une session qui démarre dessus repart sur une base fausse sans que personne le voie.

## À vérifier, dans cet ordre

1. **Le contrôle du projet est vert** — lancé maintenant, sortie montrée. Pas
   « était vert tout à l'heure ». S'il n'existe aucun moyen de vérification, le
   dire et proposer d'en mettre un avant d'aller plus loin.
2. **Le dépôt est propre** — rien de non commité.
3. **Le dépôt est poussé** — aucun commit en avance sur le distant. Le contrôle
   avant commit ne peut pas le voir : c'est à la charge de Claude.
4. **Les documents d'état disent tous la même chose** — la phase close est marquée
   close partout, aucun document n'annonce un état de contrôle périmé.
5. **Les constats assignés à la phase sont vérifiés à la source**, pas traités
   tels quels. Sur un projet réel, trois constats d'audit sur quatre se sont révélés faux
   ou à moitié faux en allant lire le fichier cité.

## Ce que Claude dit avant de commencer

Une ligne par point, avec le résultat réel : tests verts et leur nombre, dépôt
propre, N commits poussés, documents alignés. Pas « tout est à jour ».

**Si un point est rouge, la phase ne s'ouvre pas.** Le corriger d'abord, même si
c'est dix minutes de documents ennuyeux.

## Ce que cette règle ne remplace pas

La **porte de sortie** de la phase précédente, tenue par `/fin-phase` : contrôle
du projet, porte de sortie relue point par point, installation sur l'appareil,
contrôle visuel par l'utilisateur, puis commit.

Les deux se répondent : `/fin-phase` refuse de fermer une phase sans le passage
sur l'appareil réel, celle-ci refuse d'en ouvrir une sur un état faux.
