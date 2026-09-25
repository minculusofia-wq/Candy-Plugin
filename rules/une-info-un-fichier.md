# Une information, un seul fichier

Chaque fait d'un projet vit dans un seul fichier ; les autres y renvoient sans
le recopier. Deux copies finissent toujours par se contredire.

| Fichier | Ce qu'il contient |
|---|---|
| `CLAUDE.md` | Ce qui instruit : conventions, commandes, et le sommaire des pièges — une ligne par piège, qui renvoie au détail. Moins de 200 lignes : au-delà, la doc officielle dit qu'il coûte plus de contexte et qu'il est moins bien suivi. |
| `.claude/rules/*.md` avec `paths:` | Le détail d'un piège lié à des fichiers. Ne se charge que quand Claude lit ces fichiers. |
| `JOURNAL.md` | Ce qui raconte : daté, on ajoute à la fin, on ne réécrit pas le passé. |
| `CONTEXT.md` | Le glossaire, rien d'autre — et seulement si le projet a son jargon. |

- Pas de `MEMORY.md` dans un nouveau projet : la mémoire automatique suffit.
- Aucun nombre gravé (tests, fichiers, lignes…) : écrire la commande qui le donne.
- Un import `@fichier` dans CLAUDE.md se charge dès l'ouverture : il n'allège rien.

## Le jeu de fichiers par type de projet

Ce tableau est **la seule liste** : `hooks/jeu-de-documents.sh` le lit tel quel
à chaque ouverture de session. Garder sa forme — une ligne par type, noms en
MAJUSCULES séparés par des virgules, `X ou Y` pour une alternative, dossier entre
backticks terminé par `/`.

| Type | Obligatoires | Facultatifs |
|---|---|---|
| Bot ou service qui tourne | CLAUDE, STRATEGY, JOURNAL, DEPLOY | README, CONTEXT, `analyses/` |
| App par phases | CLAUDE, SPEC, ROADMAP, JOURNAL ou DECISIONS, README | CONTEXT, `docs/` |
| Petit projet | CLAUDE | README, CONTEXT |

- Un bot est reconnu par `hooks/est-un-bot.sh` : la liste
  `~/.claude/projets-bots.txt` d'abord, puis le nom du dossier et les
  bibliothèques de trading. Une app par phases a une roadmap (`ROADMAP.md`,
  `docs/ROADMAP.md`, `docs/ROADMAP-PROD.md`). Un bot qui a une roadmap cumule
  son jeu et la ROADMAP.
- Un nom compte avec ses variantes (`STRATEGY-v2.md`, `docs/ROADMAP-PROD.md`)
  à la racine ou dans `docs/` ; sous le nom exact dans un autre sous-dossier
  (`app/DECISIONS.md`) ; un dossier du même nom compte aussi (`specs/` pour
  SPEC). Sauf CLAUDE et README : à la racine seulement (ou `.claude/CLAUDE.md`)
  — un `frontend/CLAUDE.md` généré par un framework n'est pas celui du projet.
- ROADMAP porte l'état en tête. CONTEXT seulement si le projet a son jargon ;
  README d'un petit projet si quelqu'un d'autre s'en sert ; `docs/` d'une app
  pour les guides ciblés.
- `analyses/` devient obligatoire dès qu'une analyse existe dans le projet.

Le contrôle : celui du jeu de documents, lancé à chaque ouverture de session et
par `/verifier` — 🔴 un fichier obligatoire manque ou un lien est cassé,
🟡 un fichier est hors du jeu (`MEMORY.md`, skill projet qui redit le contexte
du projet, `.md` inconnu à la racine).

Une information nouvelle va dans le fichier du jeu qui porte déjà son sujet.
Un document hors du jeu ne se crée pas sans en donner la raison à l'utilisateur.

Portée : ce qui s'écrit à partir de maintenant. Un projet existant qui s'en
écarte se signale ; il se range projet par projet, à la demande de l'utilisateur.
**Exception** : avant l'écriture d'un plan de phases ou l'ouverture d'une phase,
l'alignement est une condition d'entrée, à faire sans attendre la demande de
l'utilisateur — dans la même conversation, avant de livrer le plan (voir
`porte-de-phase.md`).
