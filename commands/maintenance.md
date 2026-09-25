---
description: Entretien du dossier ~/.claude — controle mecanique du setup, relecture des transcriptions, propositions de correction des regles et des memoires
---

# Entretien du setup

Rien à retenir : le hook `rappel-entretien.sh` la propose de lui-même à
l'ouverture d'une session dans `~` ou `~/.claude`, quand le dernier entretien a
plus de 30 jours ou qu'un modèle Opus ou Fable n'a jamais servi à relire les
consignes. Il suffit de répondre « go ».

`~/.claude` est le seul « projet » que rien ne contrôle : `/verifier` y répond
« AUCUN MOYEN DE VERIFICATION TROUVE », et c'est normal — ce dossier n'est le
projet de personne. C'est aussi pour ça qu'un mécanisme peut y mourir sans que
rien ne le signale : un hook déclaré mais dont le script a disparu, un skill au
mauvais format donc jamais chargé, une mémoire qui affirme une échéance dépassée
depuis des semaines.

Trois étapes. La première est mécanique et rapide. La deuxième relit le passé et
**propose** — elle ne corrige jamais seule. La troisième ne tourne que si le
modèle de la session n'a jamais été audité.

---

## Étape 1 — Contrôle mécanique

**Avant de le lancer, noter la date de `~/.claude/.maintenance-dernier-releve`**
(s'il existe) : avec `--releve`, le contrôle la réécrit à la date du jour, et
c'est la date lue avant qui borne l'étape 2b. Relue après, elle donnerait
« aujourd'hui », donc une relecture vide.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/verifier-setup.sh --releve
```

`--releve` n'appartient qu'à cette étape : c'est lui qui date l'entretien et
remet à zéro le rappel mensuel. Un contrôle lancé à la main, ou celui de la fin
de cette commande, s'en passe.

Sept points : hooks branchés ou appelés, hooks entendus, skills chargeables,
mémoires périmées, historique, duplication règle ↔ hook, poids du setup.

### Interpréter

**Rien à signaler** → le dire en une ligne et passer à l'étape 2.

**Un ou plusieurs points** → les traiter **un par un**, en relançant le contrôle
entre chaque. Jamais plusieurs corrections d'un coup : en cas de régression, on
ne saurait plus laquelle est en cause.

Trois pièges, tous rencontrés en écrivant ce contrôle :

- Un hook peut être **appelé par une commande** au lieu d'être branché dans
  `settings.json`. Le script teste les deux — ne pas le contredire de mémoire.
- Une phrase partagée entre une règle et un hook n'est pas toujours à supprimer.
  La règle énonce ce qui vaut **en permanence**, le hook injecte **au moment
  utile**. Ne dédoubler que si le hook se déclenche à coup sûr quand la règle
  servirait.
- « Le setup n'est pas un dépôt git » est un avertissement, pas une panne. Mais
  tant qu'il n'en est pas un, aucune modification d'une règle ou d'une mémoire
  n'est annulable. Un `git init` local suffit ; avant d'ajouter un remote,
  relire ce que contiennent les hooks — un chemin de serveur ou une adresse y
  traîne vite.

---

## Étape 2 — Relecture des transcriptions

C'est le passage **hors session** : rien pendant le travail ne peut voir un
défaut qui se répète **entre** les sessions, puisque chacune repart d'un
contexte vide.

### 2a. Le compte mécanique, d'abord

Le hook `relire-ma-reponse.sh` publie une correction chaque fois qu'une réponse
a enfreint une règle. Ces corrections sont enregistrées dans les transcriptions
et se comptent :

```bash
python3 -I ${CLAUDE_PLUGIN_ROOT}/hooks/compter-relectures.py 30   # 30 derniers jours
python3 -I ${CLAUDE_PLUGIN_ROOT}/hooks/compter-relectures.py   # tout l'historique
```

**Ne pas compter au `grep`.** Les transcriptions contiennent aussi la sortie des
commandes lancées pendant les sessions — y compris d'anciens comptages. Un
`grep` sur les `.jsonl` se compte lui-même : mesuré une fois, il annonçait 37
puis 60 violations là où il y en avait 19. Le script ne retient que la signature
exacte du hook, que rien d'autre ne produit.

Lire le résultat : une règle enfreinte bien plus souvent qu'une autre n'est pas
plus importante, elle est **moins bien appliquée ou moins bien écrite**. Si une
seule formule domine le compte, se demander si la règle la nomme assez
clairement — et si oui, ne rien changer : c'est le hook qui fait le travail, et
il le fait.

### 2b. Le passage de fond, en sous-agent

Lancer un sous-agent — jamais dans la conversation courante, les transcriptions
rempliraient le contexte pour rien.

Périmètre : les fichiers `.jsonl` de `~/.claude/projects/` modifiés depuis le
dernier entretien (la date notée avant l'étape 1), ou à défaut sur trente
jours.

Trois questions, et rien d'autre :

1. **Quelle erreur s'est répétée sur plusieurs sessions ?** → candidate à une
   nouvelle règle, ou à la reformulation d'une règle qui ne prend pas.
2. **Quelle règle n'a jamais été suivie d'effet ?** → candidate à la suppression.
   Une règle que rien ne déclenche coûte du contexte à chaque session pour rien.
3. **Quelle mémoire est contredite par ce qui s'est passé depuis ?** → candidate
   à la correction ou à la suppression.

### Ce que le sous-agent doit rendre

Pour **chaque** proposition, dans cet ordre :

- le diff exact, fichier et lignes
- **au moins deux extraits de transcription** qui le justifient, avec le nom du
  fichier — sans quoi ce n'est qu'une opinion de plus
- combien de fois le motif apparaît

Une proposition sans extrait se jette. C'est la seule différence entre une
relecture utile et une réécriture au hasard.

---

## Étape 3 — Audit des consignes pour le modèle courant

**Seulement si** le modèle de la session — Opus ou Fable — n'a pas encore sa
ligne dans `~/.claude/.audit-consignes`. Son identifiant est celui que donne le
rappel d'entretien ; lancée à la main, celui de la session sans le suffixe entre
crochets (`claude-opus-5-5`, pas `claude-opus-5-5[1m]`). Sinon, le dire en une
ligne et sauter l'étape.

Des consignes écrites pour un modèle plus ancien peuvent gêner le suivant : un
modèle récent les suit plus littéralement. La sous-commande `prompt-audit` de la
skill `claude-api` les repère, et propose un diff qu'elle n'applique jamais
sans l'accord de l'utilisateur.

### Lancer

Un sous-agent `general-purpose`, pour garder les fichiers lus hors de la
conversation. Il charge la skill `claude-api` avec `prompt-audit`, **en nommant
le modèle cible** — sans nom, l'audit le déduit lui-même du dossier — et rend le
rapport et le diff proposé, sans rien appliquer.

Périmètre : ce que l'utilisateur a écrit ou copié dans `~/.claude` —
`CLAUDE.md`, `rules/`, `commands/`, `agents/`, le texte que ses `hooks/`
injectent, et les skills de `skills/` qu'il a écrites lui-même. Hors périmètre :
les skills téléchargées, les fichiers des plugins installés (une mise à jour
écraserait la correction : la signaler à l'utilisateur, qui décide s'il
prévient l'auteur — jamais d'issue ouverte à sa place), et les `CLAUDE.md` des
projets, qui se traitent chacun dans leur propre session.

### Trier, puis présenter

- **Écarter d'office** toute proposition qui retire ou assouplit une règle
  citant un incident, une date, ou une des quatre zones où l'utilisateur décide
  (argent, irréversible, dépense, produit — voir `communication-style.md`), et
  toute proposition qui touche aux paramètres de risque ou affaiblit un
  garde-fou de sécurité (protection des secrets, contrôle avant push, garde
  avant écriture). L'audit range les récits d'incident parmi le texte daté ;
  ici, ils sont la raison de la règle. Un « Jamais » né d'un incident n'est pas
  une formule vieillie.
- **Présenter le reste** en une liste courte, une ligne par changement, en
  langage simple, avec ce qui a été écarté et pourquoi. Tout changement dans
  `hooks/`, ou sur une ligne qui dit « Jamais », « Ne jamais », « Toujours »
  (ou NEVER, ALWAYS, MUST), se montre **en diff exact**, fichier et lignes, pas seulement en une ligne.
  L'utilisateur valide la liste d'un « go », ou retire des lignes.
- **Rien ne s'applique si `~/.claude` n'est pas un dépôt git** : aucune
  modification ne serait annulable. Proposer le `git init` local de l'étape 1,
  et s'arrêter là.
- Appliquer ce qui est validé, un commit par changement. Dans `hooks/`, ne
  changer que du texte, jamais la logique ; puis `bash -n` sur le hook, et un
  passage avec une entrée ordinaire qui doit sortir en 0 avec une sortie
  d'erreur vide, résultat montré. Une apostrophe ajoutée dans un bloc
  `python3 -I -c '…'` casse le hook : il peut alors bloquer toutes les
  commandes, ou ne plus rien bloquer du tout.

### Clore

Ajouter la ligne `AAAA-MM-JJ <modèle>` à `~/.claude/.audit-consignes`, même si
aucun changement n'a été retenu : c'est ce qui fait taire le rappel.

---

## Règles de la commande

- **Ne rien corriger automatiquement.** L'utilisateur accepte ou refuse chaque
  proposition — une par une à l'étape 2, en une liste à l'étape 3.
- **Un commit par acceptation**, avec un message qui dit ce qui change et
  pourquoi — si le setup est versionné, chaque acceptation redevient annulable.
- Terminer en montrant la sortie de `verifier-setup.sh` après les corrections
  acceptées. Pas « c'est propre » — la sortie réelle.
