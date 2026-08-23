# Candy Plugin

*[English version](README.md) · Français*

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

Elles fonctionnent séparément — prenez-en une, pas les huit.

## Ce que ça contient

| | |
|---|---|
| **8 règles** | vérifier avant d'affirmer · honnêteté brutale · discipline de code · porte de phase · choix du modèle · réflexes de travail · style de communication · routage des commandes |
| **5 commandes** | `/verifier` `/debug` `/fin-phase` `/fin-session` `/maj-docs` |
| **2 agents** | `relecteur-securite` · `relecteur-de-phase` (contexte neuf, ne consomment pas la conversation) |
| **13 hooks + 2 scripts** | rappel d'ouverture de phase, garde avant écriture, protection des secrets, contrôle avant push, relecture de la réponse en fin de tour |

### La pièce la plus utile : `hooks/verifier-projet.sh`

Un script sans configuration qui, sur n'importe quel projet, cherche de quoi le
vérifier (tests, lint, types, build) et rend trois verdicts possibles :

- `0` tout passe
- `1` au moins un contrôle échoue
- `2` **aucun moyen de vérification n'existe dans ce projet** — le cas le plus
  utile, celui que personne ne signale d'habitude

## Pour quels projets ? Bots, apps, et tout le reste

Ces règles sont nées sur deux terrains : des **bots de trading** qui tournent en
continu sur un serveur, et une **app iOS** construite phase par phase. La plus
grande partie ne dépend ni de l'un ni de l'autre.

| Ce qui marche partout | Spécifique aux bots et services qui tournent | Spécifique aux apps découpées en phases |
|---|---|---|
| **Règles** : vérifier avant d'affirmer · honnêteté brutale · discipline de code · réflexes de travail · choix du modèle · routage des commandes | La section « stratégies de bots » de `brutal-honesty.md` | `porte-de-phase.md` |
| **Commandes** : `/verifier` · `/maj-docs` | `/debug` (mode simulation, jamais sur le serveur) · `/fin-session` | `/fin-phase` |
| **Agents** : `relecteur-securite` | Sa section « fonds et transactions » | `relecteur-de-phase` |
| **Hooks** : contrôle du projet, protection des secrets, garde avant écriture, README avant push, relecture de la réponse, audit des `.md` | `rule5-debug-local-only.sh` (bloque SSH sauf lecture seule) · `rule13-source-or-silence.sh` | `ouverture-de-phase.sh` · `rule12-phase-debug-required.sh` |

**En clair :** si vous ne faites ni bot ni app à phases, prenez la première
colonne — c'est déjà l'essentiel. Rien n'oblige à tout installer : les règles se
copient une par une, et un hook se retire en supprimant sa ligne dans
`hooks/hooks.json`.

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

## Prérequis

- `jq` et `python3` (utilisés par les hooks)
- Testé sur macOS. Les hooks sont du bash POSIX-ish ; Linux devrait passer, non testé.
- Le hook `skills-reminder.sh` propose `/grill-with-docs` et `/tdd`, qui sont des
  skills tierces non fournies ici. Sans elles, il ne fait que suggérer.

## Ce qui n'est pas là, volontairement

Les règles de trading, les seuils de risque et les patterns de stratégie de
l'auteur. Ils ne servent qu'à ses bots.

## Support

Partagé tel quel. Les issues sont lues, pas garanties.

## Licence

MIT.
