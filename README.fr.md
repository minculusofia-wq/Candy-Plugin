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
