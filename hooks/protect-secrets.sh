#!/bin/bash
#
# protect-secrets.sh (PreToolUse : Bash, Monitor, Write, Edit)
#
# Refuse trois choses :
#   1. une VALEUR secrete dans une commande, un fichier ecrit ou une edition :
#      un nom sensible suivi d'une valeur qui en a l'allure (=, : YAML, JSON),
#      une cle 0x + 64 hexadecimaux hors d'un nom de hash, une cle PEM ;
#   2. une commande qui AFFICHE un fichier de secrets (.env et ses copies,
#      cle, wallet, ~/.claude.json, environnement d'un processus), en local
#      comme sur un serveur par ssh, joker (.env*), grep -r et git (show,
#      log -p, diff) compris. Restent permis : grep -c / -q / -l,
#      cut -d= -f1, sed 's/=.*//', un tube qui ne garde que les noms
#      (… | cut -d= -f1), et un reglage non secret (grep '^DRY_RUN=' .env,
#      sans -A, -B, -C ni -v) ;
#   3. un git add qui emporterait un fichier de secrets non ignore — on le
#      demande a git lui-meme, dans le depot vise (git -C, cd x && …).
#
# Jusqu'a la 0.3.4 : « cat .env » passait, le garde de git add lisait un motif
# de texte (-Av, ./, :/, git stage, git -C passaient) et ne regardait que le
# .env du dossier d'ouverture.
#
# Ce qu'il NE bloque PAS : une valeur vide ou nulle, une variable
# d'environnement, un gabarit, un hash nomme comme tel (tx_hash, condition_id).
# Un garde-fou qu'on contourne trois fois par jour finit desinstalle, et c'est
# alors le vrai secret qui passe.
#
# La detection vit dans detection-secrets.py (valeurs, noms de fichiers) et
# analyse-commande.py (lecture de la commande comme bash), en un seul appel.
# Les messages sont des textes fixes : ni chemin, ni nom, ni valeur n'y
# figurent — la raison d'un refus arrive a Claude, et un nom de dossier choisi
# y deviendrait une consigne.
#
# Il reste un rappel mecanique, pas un audit de securite. Ne jamais lire son
# silence comme la preuve qu'il n'y a pas de secret.

set -u
H="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
INPUT=$(cat)

# Si l'analyse echoue (python3 absent ou en panne), l'action est REFUSEE : un
# hook qui sort en 1 ou 127 ne bloque rien, et l'action passait
# (/code-review du 2026-09-24).
refuser_illisible() {
    echo "Action refusee : ce garde-fou n'a pas pu lire l'action (Python introuvable ou en panne)." >&2
    echo "Reparer Python, puis relancer. Un garde-fou qui ne voit rien ne laisse rien passer." >&2
    exit 2
}

VERDICT=$(printf '%s' "$INPUT" | python3 -I "$H/analyse-commande.py" protection 2>/dev/null) || refuser_illisible

case "$VERDICT" in
    VALEUR*)
        case "${VERDICT#VALEUR$'\t'}" in
            commande) OU="la commande" ;;
            fichier) OU="le contenu du fichier ecrit" ;;
            *) OU="l'edition" ;;
        esac
        echo "BLOCKED" >&2
        echo "" >&2
        echo "Valeur qui ressemble a un secret dans $OU (nom sensible avec une valeur, cle 0x + 64 hexa, ou cle PEM)." >&2
        echo "Ne jamais ecrire un secret en clair : le lire depuis une variable d'environnement (.env non suivi par git)." >&2
        echo "Si c'est un hash (transaction, identifiant), le nommer comme tel : tx_hash, condition_id." >&2
        exit 2
        ;;
    LECTURE)
        echo "BLOCKED" >&2
        echo "" >&2
        echo "Lecture refusee : cette commande afficherait le contenu d'un fichier de secrets" >&2
        echo "(.env, cle, wallet, environnement d'un processus), en local ou sur un serveur." >&2
        echo "Pour verifier qu'une variable existe : grep -c '^NOM=' fichier. Les noms seuls : cut -d= -f1 fichier." >&2
        echo "Un reglage qui n'est pas un secret : grep '^DRY_RUN=' fichier (sans -A, -B, -C ni -v)." >&2
        echo "Une URL de RPC ou de webhook, un sujet de notification sont des secrets." >&2
        exit 2
        ;;
    TROP_GRAND)
        echo "BLOCKED" >&2
        echo "" >&2
        echo "Recherche refusee : le dossier parcouru est trop grand pour verifier qu'aucun fichier" >&2
        echo "de secrets (.env, cle, wallet) ne serait affiche." >&2
        echo "La limiter a un sous-dossier, ou exclure les secrets : --exclude='.env*' --exclude='*.pem'." >&2
        exit 2
        ;;
    AJOUT)
        echo "BLOCKED" >&2
        echo "" >&2
        echo "Ce git add emporterait un fichier de secrets (.env, cle, wallet) que .gitignore n'ignore pas." >&2
        echo "Ajouter ce fichier au .gitignore, puis relancer le git add." >&2
        exit 2
        ;;
    AJOUT_INCONNU)
        echo "BLOCKED" >&2
        echo "" >&2
        echo "Ce git add n'a pas pu etre verifie a temps (depot trop grand, ou git bloque)." >&2
        echo "Ajouter les fichiers par leur nom (git add chemin/fichier), sans -A ni « . »." >&2
        exit 2
        ;;
    OK)
        exit 0
        ;;
    *)
        refuser_illisible
        ;;
esac
