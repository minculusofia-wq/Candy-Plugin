# Textes pour le partage

Trois angles, trois images. Chaque affirmation ci-dessous a été vérifiée dans le
dépôt — ne rien ajouter qui ne soit pas dans le code.

## Version retenue

Publiée avec `candy-fr.png` (ou `candy-en.png`).

**Français**

> J'ai mis ma config Claude Code dans un plugin.
>
> Le cœur, c'est un contrôle qui cherche seul comment vérifier le projet ouvert,
> lance tout ce qu'il trouve, et rend un verdict. Il ne dit jamais que ça a l'air bon.
>
> Sorti de mon usage réel : bots de trading et app iOS.
>
> github.com/minculusofia-wq/Candy-Plugin

**English**

> I put my Claude Code config into a plugin.
>
> At its core: a check that figures out on its own how to verify the project you
> have open, runs everything it finds, and returns a verdict. It never says it
> looks good.
>
> Comes straight out of my own work: trading bots and an iOS app.
>
> Heads up: the rules and messages are in French.
>
> github.com/minculusofia-wq/Candy-Plugin

Aucun point après l'URL : collé à la fin d'un lien, il finit parfois inclus
dedans et le lien casse.

---

## Les images

| fichier | quand l'utiliser |
|---|---|
| `candy-fr.png` · `candy-en.png` | l'identité : le bonbon, le nom, ce que fait l'outil. La plus douce, la plus lisible en aperçu. |
| `post-x-audit.png` | l'histoire de l'audit : ce que chaque garde-fou annonçait, ce qu'il faisait. |
| `post-x.png` | le produit : les trois verdicts et leurs codes de sortie. |

Le dessin du bonbon est original. Ne jamais le remplacer par une image du dessin
animé Candy Candy : l'œuvre appartient à ses autrices et à son studio, et un
dépôt public qui la reprend s'expose à un retrait.

---

## Angle 0 — l'identité · image `candy-fr.png`

> Claude annonce que c'est fait. Sur quoi tu te bases pour le croire ?
>
> J'ai écrit un plugin qui ajoute à Claude Code un contrôle tout bête : il
> cherche seul comment vérifier le projet courant, lance tout ce qu'il trouve, et
> rend un verdict. Il ne dit jamais que ça a l'air bon.
>
> github.com/minculusofia-wq/Candy-Plugin

---

## Angle 1 — l'histoire · image `docs/post-x-audit.png`

> J'ai écrit une douzaine de garde-fous pour Claude Code.
>
> Puis je les ai tous exécutés, un par un, avec de vraies entrées.
>
> Quatre faisaient le contraire de ce qu'ils annonçaient. L'un d'eux n'avait
> jamais tourné une seule fois — il dépendait d'un outil absent de mon Mac, et
> échouait en silence.
>
> Tout est corrigé, testé, et en ligne.
>
> github.com/minculusofia-wq/Candy-Plugin

**Variante courte**

> Mes garde-fous affichaient « bloqué ».
> Ils ne bloquaient rien.
>
> Un outil qui ment sur ce qu'il fait est pire que pas d'outil. Je les ai tous
> repris, un par un, avec le test qui le prouve.
>
> github.com/minculusofia-wq/Candy-Plugin

---

## Angle 2 — le produit · image `docs/post-x.png`

> Claude annonce que c'est fait. Sur quoi tu te bases pour le croire ?
>
> Ce plugin ajoute un contrôle qui cherche tout seul comment vérifier le projet
> courant, lance TOUT ce qu'il trouve, et rend un verdict :
>
> · tout passe
> · voici les contrôles qui échouent — tous, sans exception
> · **rien ne permet de vérifier ce projet** ← le cas que rien d'autre ne signale
>
> Il ne dit jamais « ça a l'air bon ».
>
> github.com/minculusofia-wq/Candy-Plugin

---

## Ce qu'il ne faut PAS écrire

- « ça marche à tous les coups », « plus jamais de bug » — le contrôle lit un
  résultat, il ne garantit rien sur la qualité du travail
- un chiffre de gain de temps : aucune mesure n'existe
- « testé sur des dizaines de projets » : le dépôt n'a aucun test automatique,
  les vérifications ont été faites à la main

## À savoir avant de poster

Le contenu du plugin est en **français** (règles, commandes, messages). Le
README principal est en anglais. Un lecteur anglophone qui installe reçoit des
messages en français — c'est écrit en clair dans le README, mais ça vaut d'être
redit dans le fil si l'audience est internationale.
