#!/bin/bash
#
# La protection des secrets : elle doit bloquer une VALEUR qui ressemble à un
# secret, et rien d'autre.
#
# Le défaut d'origine : elle cherchait un nom de variable suivi d'un signe égal,
# n'importe où. Elle bloquait « une clé à None », tout hash de transaction, et
# jusqu'à la documentation qui parle de phrases de récupération. L'auteur la
# contournait plusieurs fois par jour — un garde-fou qu'on contourne finit
# désinstallé, et c'est alors le vrai secret qui passe.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$RACINE/hooks/protect-secrets.sh"
BAC=$(mktemp -d)
trap 'rm -rf "$BAC"' EXIT

# --- vocabulaire assemblé (voir l'en-tête de aide.sh) ---
CLE_API="api_key"
CLE_PRIVEE="PRIVATE_KEY"
MOT_DE_PASSE="password"
MNEMO="MNEMONIC"
HEX64="0x$(python3 -c 'print("ab12cd34"*8)')"
PHRASE_RECUP="$(printf 's%sd' 'ee') phrase"
DOUZE_MOTS="ridge quantum lantern velvet harbor mosaic pilgrim ember thistle cobalt murmur zenith"

ecriture() { verifie "$1" "$2" "$(code_hook "$HOOK" "$(entree_ecriture /tmp/exemple.py "$3")")"; }

section "Secrets — ce qui doit PASSER (aucun secret là-dedans)"
ecriture "une clé laissée à None"                0 "$CLE_API = None  # à renseigner"
ecriture "un hash de transaction"                0 "tx_hash = \"$HEX64\""
ecriture "de la doc sur les phrases de récupération" 0 "Ne jamais stocker la $PHRASE_RECUP en clair."
ecriture "une lecture de variable d'environnement" 0 "$CLE_API = os.getenv(\"CLE\")"
ecriture "une valeur vide"                       0 "$CLE_API = \"\""
ecriture "un gabarit shell"                      0 "$CLE_PRIVEE=\${$CLE_PRIVEE}"
ecriture "un exemple à remplir"                  0 "$CLE_API = \"your_${CLE_API}_here_xxxx\""
ecriture "une phrase en français"                0 "$MOT_DE_PASSE = \"a definir avec l equipe\""

# Deux formes très courantes, cassées en resserrant les filtres puis remises :
# elles passaient avant, elles doivent passer après. Un garde-fou qui bloque du
# code ordinaire finit désinstallé, et c'est alors le vrai secret qui passe.
ecriture "une clé passée en argument nommé"      0 "client = Client($CLE_API=reglages.cle_de_production)"
ecriture "un emplacement à remplir en majuscules" 0 "$CLE_API: \"REMPLACER_PAR_VOTRE_CLE\""

section "Secrets — ce qui doit BLOQUER (une vraie valeur)"
ecriture "une clé privée écrite en dur"          2 "$CLE_PRIVEE = \"$HEX64\""
ecriture "une clé d'API écrite en dur"           2 "$CLE_API = \"sk-proj-9Fj2LmQ8xT4vB7nR1cW0\""
ecriture "le même secret au format .env"         2 "$CLE_PRIVEE=$HEX64"
ecriture "une phrase de récupération de douze mots" 2 "$MNEMO = \"$DOUZE_MOTS\""

# Trois contournements trouvés à la relecture. Chacun passait (code 0) alors
# qu'une valeur équivalente avec un chiffre, sans accolade et sans le mot
# « secret » était bien bloquée : la protection marchait, ses trois filtres
# étaient seulement trop larges.
ecriture "une clé de vingt lettres, sans aucun chiffre" 2 "$CLE_API = \"abcdefghijklmnopqrst\""
ecriture "une valeur qui commence par le mot secret"    2 "$CLE_API = \"secretvalue9Xk2Lm4pQr\""
ecriture "une clé contenant une accolade"               2 "$CLE_PRIVEE = \"aZ4{9Fj2LmQ8xT4vB7nR1cW0\""

section "Secrets — le garde .env"
GIT_AJOUT="$(printf 'g%st a' 'i')dd"
mkdir -p "$BAC/env" && echo "CLE=valeur" > "$BAC/env/.env"
commande() { verifie "$1" "$2" "$(code_hook "$HOOK" "$(entree_commande "$3")" CLAUDE_PROJECT_DIR="$BAC/env")"; }

commande "un chemin qui commence par un point passe"  0 "$GIT_AJOUT .claude-plugin/manifeste.json"
commande "un fichier nommé passe"                     0 "$GIT_AJOUT hooks/exemple.sh"
commande "tout ajouter est refusé si .env traîne"     2 "$GIT_AJOUT ."
commande "l'ajout en masse est refusé"                2 "$GIT_AJOUT -A"
commande "ajouter le .env lui-même est refusé"        2 "$GIT_AJOUT .env"

echo ".env" > "$BAC/env/.gitignore"
commande "une fois .env ignoré, tout redevient permis" 0 "$GIT_AJOUT ."

section "Secrets — le reste du travail n'est pas gêné"
commande "une commande ordinaire passe"               0 "ls -la && npm run build"

bilan
