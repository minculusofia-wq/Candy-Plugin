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

| Type | Fichiers |
|---|---|
| Bot ou service qui tourne | CLAUDE, STRATEGY, JOURNAL, DEPLOY, dossier `analyses/` |
| App par phases | CLAUDE, SPEC, ROADMAP (état en tête), JOURNAL ou DECISIONS, CONTEXT si jargon, README, guides ciblés si le sujet existe |
| Petit projet | CLAUDE (+ README si quelqu'un d'autre s'en sert) |

Une information nouvelle va dans le fichier du jeu qui porte déjà son sujet.
Un document hors du jeu ne se crée pas sans en donner la raison à l'utilisateur.

Portée : ce qui s'écrit à partir de maintenant. Un projet existant qui s'en
écarte se signale ; il se range projet par projet, à la demande de l'utilisateur.
