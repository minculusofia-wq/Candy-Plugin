---
description: Entretien du dossier ~/.claude — controle mecanique du setup, relecture des transcriptions, propositions de correction des regles et des memoires
---

# Entretien du setup

À lancer une fois par mois.

`~/.claude` est le seul « projet » que rien ne contrôle : `/verifier` y répond
« AUCUN MOYEN DE VERIFICATION TROUVE », et c'est normal — ce dossier n'est le
projet de personne. C'est aussi pour ça qu'un mécanisme peut y mourir sans que
rien ne le signale : un hook déclaré mais dont le script a disparu, un skill au
mauvais format donc jamais chargé, une mémoire qui affirme une échéance dépassée
depuis des semaines.

Deux étapes. La première est mécanique et rapide. La seconde relit le passé et
**propose** — elle ne corrige jamais seule.

---

## Étape 1 — Contrôle mécanique

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/verifier-setup.sh
```

Six points : hooks branchés ou appelés, skills chargeables, mémoires périmées,
historique, duplication règle ↔ hook, poids du setup.

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
python3 ${CLAUDE_PLUGIN_ROOT}/hooks/compter-relectures.py 30   # 30 derniers jours
python3 ${CLAUDE_PLUGIN_ROOT}/hooks/compter-relectures.py      # tout l'historique
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
dernier entretien (date dans `~/.claude/.maintenance-dernier-releve`), ou à
défaut sur trente jours.

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

## Règles de la commande

- **Ne rien corriger automatiquement.** L'utilisateur accepte ou refuse chaque
  proposition, une par une.
- **Un commit par acceptation**, avec un message qui dit ce qui change et
  pourquoi — si le setup est versionné, chaque acceptation redevient annulable.
- Terminer en montrant la sortie de `verifier-setup.sh` après les corrections
  acceptées. Pas « c'est propre » — la sortie réelle.
