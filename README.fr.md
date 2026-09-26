# Candy Plugin

*[English version](README.md) · Français*

<p align="center">
  <img src="docs/candy-fr.png" alt="Candy Plugin — des garde-fous pour Claude Code. Il ne dit jamais que ça a l'air bon." width="100%">
</p>

[![MIT](https://img.shields.io/github/license/minculusofia-wq/Candy-Plugin?style=flat-square&color=555)](LICENSE)
![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-8A63D2?style=flat-square)
![Langue](https://img.shields.io/badge/contenu-fran%C3%A7ais-1f6feb?style=flat-square)

<p align="center">
  <img src="docs/apercu-fr.png" alt="Le même contrôle sur trois projets : tout passe (sortie 0), deux contrôles échouent et tous sont listés (sortie 1), aucun moyen de vérifier ce projet (sortie 2)" width="100%">
</p>

<p align="center"><i>Trois projets, trois verdicts. Il ne dit jamais « ça a l'air bon ».</i></p>

Un plugin Claude Code, en français, qui empêche trois choses :

1. **Que Claude affirme sans avoir lu.** Chaque chiffre, chaque nom de fichier,
   chaque contrainte technique doit porter sa source `fichier:ligne`.
2. **Que Claude vous flatte.** Verdict en première phrase, failles avant qualités,
   pas de « oui mais » déguisé.
3. **Que « c'est fait » soit dit sans preuve.** Un contrôle universel détecte tout
   seul comment vérifier le projet courant et rend un verdict.

Aucune de ces règles ne sort d'un article de blog. Chacune a été écrite après
coup, le jour où un « c'est fait » s'est révélé faux — sur des bots en production
comme sur une app mobile.

## Installation

```
/plugin marketplace add minculusofia-wq/Candy-Plugin
/plugin install candy-plugin
```

Les règles (`rules/`) ne sont pas chargées par le plugin : Claude Code les lit
depuis votre dossier personnel. Copiez celles qui vous intéressent :

```
cp -R rules/*.md ~/.claude/rules/
```

Elles fonctionnent séparément — prenez-en une, pas les neuf.

## Ce que ça contient

| | |
|---|---|
| **9 règles** | vérifier avant d'affirmer · honnêteté brutale · discipline de code · porte de phase · choix du modèle · réflexes de travail · style de communication · routage des commandes · une information, un seul fichier |
| **6 commandes** | `/verifier` `/debug` `/fin-phase` `/fin-session` `/maj-docs` `/maintenance` |
| **2 agents** | `relecteur-securite` · `relecteur-de-phase` (contexte neuf, ne consomment pas la conversation) |
| **12 hooks + 8 scripts** | rappel d'ouverture de phase, rappel des tâches en attente sur un projet, rappel d'entretien du setup, contrôle du jeu de documents à chaque ouverture (fichiers manquants, hors du jeu, CLAUDE.md trop long), fichiers de secrets gardés en écriture et en lecture, protection des secrets (une valeur écrite, un `.env` affiché, un `git add` qui l'emporterait), contrôle avant push (le dépôt et les commits réellement poussés), contrôle du projet en fin de tour (borné dans le temps, seulement sur ce qui a bougé pendant le tour), relecture de la réponse en fin de tour, contrôle du setup lui-même |

### La pièce la plus utile : `hooks/verifier-projet.sh`

Un script sans configuration qui, sur n'importe quel projet, cherche de quoi le
vérifier (tests, lint, types, build) et rend trois verdicts possibles :

- `0` tout passe
- `1` au moins un contrôle échoue
- `2` **aucun moyen de vérification n'existe dans ce projet** — le cas le plus
  utile, celui que personne ne signale d'habitude

### Les rappels par projet

Quand une tâche doit attendre la prochaine ouverture d'un projet, écrivez-la une
fois dans `~/.claude/rappels-projets.txt` :

```
~/Desktop/mon-app | ranger la documentation | ~/notes/consigne.md |
~/Desktop/mon-app | ouvrir la phase 4 | - | ROADMAP.md::^### Phase 3.*🟢
```

Une ligne par tâche : le dossier du projet, la tâche, où lire le détail, et une
condition facultative. `fichier::motif` n'affiche la ligne que si ce fichier du
projet contient le motif — ici, pas avant que la phase 3 soit marquée 🟢.

À l'ouverture du projet, ou d'un de ses sous-dossiers, la tâche s'affiche et
Claude la reçoit avec son détail. Il suffit de répondre « go ». Une fois la
tâche faite, sa ligne se retire. Sans ce fichier, le hook ne dit rien.

### Le rappel d'entretien

`/maintenance` n'a pas à être retenue. À l'ouverture d'une session dans `~` ou
`~/.claude` — jamais dans un projet, où il détournerait du travail —, le hook
`rappel-entretien.sh` la propose dans deux cas :

- le dernier entretien a plus de 30 jours, ou n'a jamais eu lieu ;
- la session tourne sur un modèle Opus ou Fable qui n'a encore jamais servi à
  relire les consignes. Des consignes écrites pour un modèle plus ancien peuvent
  gêner le suivant, qui les suit plus littéralement : l'étape 3 de
  `/maintenance` les fait auditer par la sous-commande `prompt-audit` de la
  skill `claude-api`, écarte ce qui retirerait une règle née d'un incident, et
  vous présente le reste en une seule liste à valider.

Il suffit de répondre « go ». Le reste du temps, le hook ne dit rien.

## Pour quels projets ? Bots, apps, et tout le reste

Ces règles sont nées sur deux terrains : des **bots de trading** qui tournent en
continu sur un serveur, et une **app iOS** construite phase par phase. La plus
grande partie ne dépend ni de l'un ni de l'autre.

| Ce qui marche partout | Spécifique aux bots et services qui tournent | Spécifique aux apps découpées en phases |
|---|---|---|
| **Règles** : vérifier avant d'affirmer · honnêteté brutale · discipline de code · réflexes de travail · choix du modèle · routage des commandes · une information, un seul fichier | La section « stratégies de bots » de `brutal-honesty.md` | `porte-de-phase.md` |
| **Commandes** : `/verifier` · `/maj-docs` · `/maintenance` | `/debug` (mode simulation, jamais sur le serveur) · `/fin-session` | `/fin-phase` |
| **Agents** : `relecteur-securite` | Sa section « fonds et transactions » | `relecteur-de-phase` |
| **Hooks** : contrôle du projet, contrôle du setup, protection des secrets, garde avant écriture, relecture de la réponse, audit des `.md`, contrôle du jeu de documents, rappel des tâches en attente, rappel d'entretien | `rule13-source-or-silence.sh` | `ouverture-de-phase.sh` · `rule12-phase-debug-required.sh` |

**En clair :** si vous ne faites ni bot ni app à phases, prenez la première
colonne — c'est déjà l'essentiel. Rien n'oblige à tout installer : les règles se
copient une par une, et un hook se retire en supprimant sa ligne dans
`hooks/hooks.json`.

`/fin-phase` mérite un avertissement à part : ses 300 lignes sont le rituel réel
de l'auteur sur une app iOS, gardé entier plutôt que vidé en modèle creux. Il
cite ses propres documents, ses pièges numérotés, ses arbitrages datés. À lire
comme un exemple à adapter — la forme se réutilise, le contenu non.

Les exemples parlent de trading et d'iPhone parce que c'est là que ces règles ont
été payées cher. Le principe, lui, ne change pas : **rien n'est vrai parce que
Claude l'a écrit** — ni sur un bot, ni sur une app, ni sur un script de trois
lignes.

## `/fin-session` ou `/fin-phase` ? La question qu'on se pose le plus

Les deux ferment un travail. Elles ne ferment pas la même chose.

**`/fin-session` ferme une séance.** Le projet, lui, continue de tourner — un bot
en production n'est jamais « fini ». La commande laisse le dépôt propre : debug
optionnel, audit des `.md`, mise à jour de la doc, **un seul** commit, push, résumé.
Elle ne juge pas le travail, elle le range.

**`/fin-phase` ferme une livraison.** Une app découpée en phases atteint des états
qu'on déclare atteints — et cette déclaration peut être fausse. La commande relit
la porte de sortie de la phase **point par point**, liste ce que seul l'appareil
réel peut trancher, et rend un verdict à **trois** états :

| Verdict | Ce qu'il veut dire |
|---|---|
| `ROUGE` | Un contrôle machine échoue. On s'arrête, on corrige. |
| `EN ATTENTE DE TON APPAREIL` | Tout est vert côté machine, il reste des points que vous seul tranchez. |
| `VERT` | Vous avez répondu à tout. |

Le 🟢 dans la roadmap et l'étiquette git ne se posent **qu'en `VERT`**.

### Comment choisir en trois secondes

> **Votre projet a-t-il une roadmap avec des phases numérotées, dont certaines
> ne se vérifient qu'à la main — sur un téléphone, un écran, un appareil réel ?**
>
> Oui → `/fin-phase`. Non → `/fin-session`.

En pratique : un bot, un script, un service qui tourne → `/fin-session`. Une app
construite phase par phase → `/fin-phase`.

### Ce qui se passe si vous vous trompez

| | |
|---|---|
| `/fin-session` sur une app à phases | Le dépôt est propre et la doc à jour, mais **rien n'a vérifié que la phase est réellement livrée**. Une phase passe en 🟢 sur la foi de tests qui ne voient pas un bouton mort. |
| `/fin-phase` sur un bot | La commande cherche une roadmap et une porte de sortie qui n'existent pas. Elle s'arrête sans rien casser — mais elle ne fait rien d'utile. |

Un garde-fou pris pour une validation est pire que pas de garde-fou : c'est
exactement ce que `/fin-phase` existe pour empêcher, et c'est pourquoi elle refuse
de conclure seule.

### Les deux se répondent

`/fin-phase` tient la **porte de sortie** d'une phase. La règle
[porte-de-phase.md](rules/porte-de-phase.md) tient la **porte d'entrée** de la
suivante, et le hook `ouverture-de-phase.sh` la rappelle au démarrage de la
conversation d'après. Une phase ne se ferme pas sans vous, et la suivante ne
s'ouvre pas sur un état faux.

Le hook `jeu-de-documents.sh` vérifie à chaque ouverture, dans tout projet, que
les documents attendus par [une-info-un-fichier.md](rules/une-info-un-fichier.md)
sont là — il lit le tableau de la règle, il n'en garde pas de copie. Un fichier
manquant devient un point rouge de la porte d'entrée, et la porte s'applique dès
l'écriture d'un plan de phases : un plan dont la première phase ne peut pas
s'ouvrir est un plan faux.

## Tests

```
make test
```

`make test` affiche le nombre de groupes et de cas : *j'envoie ceci à ce hook,
j'attends ce verdict*. Chaque défaut corrigé a ses cas, joués sur la version qui
avait le défaut : ils doivent y échouer — un test qui passe toujours ne vaut
rien. Le groupe 09 rejoue l'incident qui a fait naître le contrôle du jeu de
documents, et les pannes qu'il doit signaler au lieu de se taire. Voir
[tests/README.md](tests/README.md).

## Prérequis

- `python3` (utilisé par les hooks). **Indispensable** : sans lui, les garde-fous
  refusent au lieu de laisser passer — Claude ne peut plus lancer de commande ni
  écrire de fichier tant que `python3` n'est pas réparé, et le message de refus le
  dit. Un garde-fou aveugle qui laisse tout passer est pire qu'un garde-fou qui
  bloque. **Pas de `jq`** — il n'est pas garanti
  sur toutes les machines, et un hook qui dépend d'un binaire absent échoue en
  silence : sur une machine qui ne l'avait pas, le contrôle avant push ne se
  déclenchait tout simplement jamais. Cette dépendance a été supprimée.
- **Claude Code 2.1.196 ou plus récent** pour la relecture de la réponse : elle
  lit le champ `prompt_id` pour n'intervenir qu'une fois par message, et les
  versions antérieures ne l'envoient pas. En dessous, elle ne signale qu'une
  faute sur deux.
- `pytest` et `npm` sont **facultatifs**, et seulement pour les tests du paquet :
  quelques cas vérifient que le contrôle universel lance bien ces familles. Sans
  eux, ces cas sont sautés en le disant, et la suite reste verte.
- Testé sur macOS. Les hooks sont du bash POSIX-ish ; Linux devrait passer, non testé.
- **À savoir** : en fin de tour, si un fichier de code a changé *pendant le
  tour* dans un dépôt git, le contrôle universel lance la suite de tests du
  projet depuis la racine du dépôt — c'est son travail. Il est coupé à 240
  secondes, et s'il n'a pas fini, il le dit au lieu de laisser croire que tout
  passe. Dans un dépôt dont vous ne connaissez pas le code, c'est ce code qui
  tourne. Les hooks, eux, n'exécutent jamais un module Python posé dans le
  projet (`python3 -I`, vérifié par `tests/06-paquet.sh`). Pour savoir ce qui a
  bougé pendant le tour, le plugin relève l'état du dépôt à chaque message, dans
  son dossier de données (`~/.claude/plugins/data/`).
- **Ce qui tourne, se lit ou sort, en plus** : le code du plugin lui-même n'envoie rien
  sur le réseau. `/verifier` lance aussi la cible `make audit` du projet
  quand son Makefile en a une — un audit des dépendances (`pip-audit`,
  `npm audit`) passe par le réseau ; le contrôle de fin de tour la saute.
  `/maintenance` lit vos transcriptions de conversation
  (`~/.claude/projects/*.jsonl`) sur votre machine pour compter les relectures
  et relire le setup ; rien n'en sort.
- **À savoir aussi** : Claude ne lit plus un fichier de secrets — ni `.env` et
  ses variantes, ni clé (`.pem`, `.key`, `~/.ssh`), ni wallet. L'outil Read, la
  recherche Grep et une commande comme `cat .env` sont refusés. Ce qui ne montre
  que les noms reste permis : `grep -c`, `cut -d= -f1`, et la lecture d'un
  réglage dont la valeur est un booléen, un nombre ou un mot court
  (`grep '^DRY_RUN=' .env`). Si vous voulez que Claude voie une valeur,
  copiez-la vous-même dans la conversation. C'est un filet contre les façons
  courantes d'afficher un secret — lecteurs, interprètes, `xargs`, liens,
  recherche récursive —, pas une barrière : un programme qui lit le fichier
  sans le nommer (un script, une bibliothèque dotenv) passe.
- **Les limites de ce filet, connues et laissées telles quelles.** Trois
  relectures de sécurité l'ont montré : chaque forme ajoutée en ouvre une
  autre et refuse du travail ordinaire, donc la liste ne grandit plus. Passent
  aujourd'hui : une boucle `for f in .env …; do cat "$f"` ; `xargs` après
  plusieurs tubes (`find … | sort | xargs cat`) ; `find -exec sh -c '…'` ;
  `cat $(pwd)/.env` ; `read -r l < .env` ; `source .env` suivi d'un interprète
  qui lit `os.environ` ; `git log -U0`, `--patch-with-stat`, `reflog -p`,
  `format-patch --stdout` d'un `.env` commité ; `docker inspect` ; une archive
  d'un `.env` sous un nom neutre (`tar -czf sauvegarde.tgz .env`), relue
  ensuite. Deux limites qui ne sont pas des affichages : les commandes git que
  les hooks lancent (`ls-files`, `check-ignore`, `status`) obéissent à la
  configuration du dépôt, hooks de git compris — elle ne se clone pas, mais un
  dépôt déjà présent la porte, et une archive qui livre son dossier `.git`
  livre aussi son `info/exclude` : un conseil de phase rangé dedans est lu ;
  et la porte d'entrée cite les noms des fichiers non commités (`git status`),
  donc un nom de fichier du dépôt arrive dans le contexte de Claude.

## Ce qui n'est pas là, volontairement

Les règles de trading, les seuils de risque et les patterns de stratégie de
l'auteur. Ils ne servent qu'à ses bots.

Deux hooks ont été retirés avant publication plutôt que livrés cassés : l'un
bloquait toute commande `ssh` (contrainte très personnelle, et sa liste
d'exceptions se désarmait avec n'importe quelle commande contenant le mot
magique), l'autre réclamait un commit à la fin de *chaque tour* au lieu de
chaque session.

Trois autres ont été retirés ensuite, après une mesure sur un mois de
conversations de l'auteur. `rule7-readme-before-push.sh` et
`rule9-code-discipline.sh` écrivaient leurs avertissements puis sortaient avec
le code 0 : Claude Code envoie alors ces messages au seul journal de débogage,
et personne ne les a jamais vus. `skills-reminder.sh` réagissait à des mots, pas
au sens : près de trois déclenchements sur quatre venaient de messages
automatiques (fins de tâches, rapports de sous-agents, commandes dépliées), et sur un échantillon de vrais
messages, il ne tombait juste qu'une fois sur cinq. Le contrôle du setup
repère désormais ce genre de hook muet.

## Support

Partagé tel quel. Les issues sont lues, pas garanties.

## Licence

MIT.
