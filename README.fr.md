# Candy Plugin

*[English version](README.md) · Français*

Un plugin Claude Code, en français, qui empêche trois choses :

1. **Que Claude affirme sans avoir lu.** Chaque chiffre, chaque nom de fichier,
   chaque contrainte technique doit porter sa source `fichier:ligne`.
2. **Que Claude vous flatte.** Verdict en première phrase, failles avant qualités,
   pas de « oui mais » déguisé.
3. **Que « c'est fait » soit dit sans preuve.** Un contrôle universel détecte tout
   seul comment vérifier le projet courant et rend un verdict.

Écrit et éprouvé au quotidien par quelqu'un qui n'est pas développeur, et qui
avait besoin que l'outil dise non.

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
