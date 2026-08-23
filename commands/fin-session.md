---
description: Fin de session — debug optionnel, audit des .md, mise a jour docs, commit unique et push
---

# Fin de session

Quand l'utilisateur écrit "fin de session" :

## 0. Question debug (OBLIGATOIRE en premier)
Demander à l'utilisateur : "Debug complet avant la suite ? oui/non"

Attendre sa réponse avant de continuer.

- Si **oui** → appliquer la procédure de `/debug`, version **complète**, sans en
  sauter une étape (y compris la séquence de fin : tuer les processus locaux).

  ⚠️ La procédure de débogage n'est écrite **qu'à un seul endroit** : `/debug`.
  Elle a existé en trois exemplaires jusqu'au 2026-08-08 — ici, dans `/debug`, et
  dans un `/debug-phase` depuis supprimé — et les trois avaient divergé. Ne pas la
  recopier ici, même « pour aller plus vite ».

  Ne PAS passer à l'étape 1 tant que le projet n'est pas sain.

- Si **non** → passer directement à l'étape 1

> **Cette commande est celle des bots.** Une app dont le travail est découpé en
> phases se clot avec `/fin-phase`, qui relit la porte de sortie de la phase et
> refuse de la déclarer terminée sans vérification sur l'appareil réel.

## 0.5 Audit automatique des .md (OBLIGATOIRE)

Avant toute mise à jour manuelle, lancer le script d'audit qui scanne tous les .md du projet et détecte les obsolescences :

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/session-end-md-audit.sh "$CLAUDE_PROJECT_DIR"
```

Le script vérifie 4 choses :
1. **Liens markdown cassés** (vers fichiers/dossiers supprimés) — ✗ rouge = à corriger systématiquement
2. **Mentions de fichiers/dossiers supprimés** dans les 50 derniers commits — ✗ rouge
3. **Dates "Dernière mise à jour" obsolètes** sur fichiers récemment commités — ⚠ jaune
4. **Statuts contradictoires** (à créer / à trancher) sur des éléments existants — ⚠ jaune

**Règle absolue :** chaque ligne ✗ rouge DOIT être corrigée avant le commit final. Les ⚠ jaunes doivent être vérifiées au cas par cas (peuvent être légitimes : questions stratégiques ouvertes, sections historiques de CHANGELOG).

Si le script retourne code 1 (issues détectées), je traite chaque point ligne par ligne, puis je relance le script jusqu'à ce qu'il retourne 0.

## 1. Mise à jour de TOUS les .md du projet
Lister tous les fichiers .md du projet et les mettre à jour selon leur rôle.

Exclure au jugement : dépendances, builds, fichiers générés automatiquement.
Modifier un .md uniquement si son contenu est devenu obsolète à cause de la session. Sinon le laisser tel quel.

### CLAUDE.md
- Description courte (stratégie du bot)
- Comment lancer en local
- Ports, variables d'environnement
- Pièges connus, décisions d'architecture

### README.md
- Partie stratégie en langage business
- Partie technique (stack, lancement, ports, .env, structure, déploiement)
- Créer s'il n'existe pas

### MEMORY.md du projet
- Nouveaux pitfalls → fiche dédiée
- Décisions d'architecture de la session
- Bugs importants + cause racine
- Créer s'il n'existe pas

### strategy-spec.md (si présent)
- Logique de décision si elle a évolué
- Paramètres clés et valeurs actuelles

### Tous les autres .md du projet
Vérifier chacun et appliquer le même critère (modifier uniquement si obsolète).

## 2. Commit unique + push
Un SEUL commit final regroupant code (si debug fait) + tous les .md mis à jour.
- Message clair en français résumant la session
- Push automatique
- Pas de commit "docs: maj" séparé

## 3. Résumé
- Debug fait ou non (et résultat si oui)
- Quels .md ont été modifiés et pourquoi
- Quels .md ont été vérifiés mais laissés tels quels
- État final du projet
