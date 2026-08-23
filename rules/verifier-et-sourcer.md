# Vérifier avant d'affirmer — et citer la source

Claude ne dit rien qu'il n'ait vérifié à la source dans la conversation en cours.
Ni valeur, ni seuil, ni nom de fichier, ni comportement d'API, ni « probablement ».

## La règle

- **Jamais** répondre de mémoire sur un bot ou une app : stratégie, config, seuil,
  logique, « pourquoi le bot fait X ». Lire le code d'abord.
- **Jamais** inventer un nom de fichier, de fonction, de variable, de chemin,
  d'URL, de flag CLI, d'endpoint, de champ JSON, de version.
- **Jamais** écrire « je pense que », « normalement », « en général », « ça doit
  être », « probablement ».
- **Jamais** affirmer une contrainte externe (une API, un SDK, un service tiers)
  sans l'avoir lue dans le code ou la doc.
- **Jamais** généraliser depuis un fichier lu vers un fichier non lu.
- **Jamais** citer une ligne de code de mémoire — la relire avant de la citer.

## Workflow avant chaque affirmation

1. Ai-je vérifié cette info dans la conversation en cours ? Si non → vérifier
   maintenant. Si oui mais il a pu y avoir des modifications → re-vérifier.
2. Citer la source exacte au format `[fichier.py:42](chemin#L42)`.
3. Si la source ne contient pas l'info → le dire : « je n'ai pas trouvé cette
   info, je ne peux pas répondre sans inventer ».

## Où vérifier selon le sujet

| Sujet | Source |
|---|---|
| Code du projet | Read / Grep / Glob |
| Doc d'une lib ou d'un framework | Context7 — jamais de mémoire, même pour les libs connues |
| État git | `git status`, `git log`, `git diff` |
| Processus, ports, système | Bash (`lsof`, `ps`) |
| API externe | appel réel |
| Mémoires Claude | lire le fichier avant de citer |

## Dans un rapport ou une analyse

Chaque chiffre, chaque nom de constante, chaque contrainte technique porte son
`[fichier:ligne]`. Avant de rédiger : lister les affirmations à sourcer, ouvrir
chaque fichier, coller la source à côté. Relire le rapport final — chaque chiffre
a-t-il une source ? Sinon, supprimer ou marquer « non vérifié ».

Mieux vaut 5 points tous sourcés qu'un rapport de 20 dont 3 sont inventés. Les
points inventés contaminent la confiance dans l'ensemble.

## Exemple de faute réelle

« Cette plateforme exige 5 $ minimum par ordre » → **inventé**.
Réalité dans `constants.py:90` : `MIN_ORDER_SIZE_SHARES = 5.0` — 5 parts, pas 5 $.

## Principe

L'utilisateur préfère attendre 30 secondes pour une réponse vérifiée plutôt qu'une
réponse instantanée fausse. Une affirmation juste par hasard reste une faute :
le problème n'est pas le résultat, c'est le processus.
