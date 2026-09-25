#!/usr/bin/env python3
#
# detection-secrets.py — ce qui est un secret, à un seul endroit.
#
# Jusqu'à la 0.3.4, deux listes différentes vivaient dans deux hooks, et
# aucune ne se trompait dans le même sens : pre-edit-guard ignorait
# backend.env, *.pem et ~/.ssh ; protect-secrets ne connaissait ni « secret »
# ni « token » employés seuls, ni la forme YAML, ni une clé PEM, ni une clé
# privée passée à from_key("0x…").
#
# Appelé par :
#   pre-edit-guard.sh    detection-secrets.py fichier   (Write, Edit, Read)
#   protect-secrets.sh   detection-secrets.py valeur    (Bash, Monitor, Write, Edit)
#   analyse-commande.py  importé : est_fichier_de_secrets, valeur_secrete
#
# Entrée : le JSON du hook sur stdin. Sortie : un mot sur stdout.
#   fichier → SECRET | OK
#   valeur  → rien, ou « <où>\t<nom> » (où = commande | fichier | edition)
# Toute panne sort en code 3 : le hook appelant refuse l'action.
#
# Il reste un rappel mécanique, pas un audit : ne jamais lire son silence comme
# la preuve qu'il n'y a pas de secret.

import json
import os
import re
import sys
import unicodedata

# --- Fichiers de secrets ---------------------------------------------------------

MODELES = re.compile(r"[._-](example|sample|template|dist|tmpl|tpl|defaults?)$")
# ~/.claude.json porte en clair les jetons des serveurs MCP ; .git-credentials,
# gh/hosts.yml et .docker/config.json portent ceux de git, de gh et de Docker.
NOMS_EXACTS = {".env", ".envrc", "credentials", "credentials.json", "keystore.json", "wallet.json",
               "private_key.txt", "secret.key", ".netrc", ".pypirc", ".pgpass",
               "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa", ".claude.json", ".git-credentials"}
# Copies horodatées d'un .env (sauvegardes/env-20260101-120000, env.local-…).
COPIE_D_ENV = re.compile(r"env(\.[a-z]+)?-\d{8}-\d{6}(-\d+)?")
EXTENSIONS = (".pem", ".key", ".p12", ".pfx", ".keystore", ".jks")
SSH_PERMIS = {"config", "authorized_keys", "known_hosts", "known_hosts.old", "environment.example"}


def est_fichier_de_secrets(chemin):
    """Comparé comme macOS (APFS) compare les noms : chemin normalisé, forme
    NFKC, casse repliée (« .ENV », « wallet.jſon »). Les modèles sans valeur
    (.env.example, *.template) et les clés publiques (.pub) restent libres."""
    if not chemin or not isinstance(chemin, str):
        return False
    p = os.path.normpath(unicodedata.normalize("NFKC", chemin).casefold())
    parties = p.split(os.sep)
    b = parties[-1]
    if b.endswith(".pub") or MODELES.search(b):
        return False
    if b in NOMS_EXACTS or b.startswith((".env.", ".claude.json.")) or b.endswith(".env") or ".env." in b:
        return True
    if re.match(r"\.env[~_-]", b) or COPIE_D_ENV.fullmatch(b):
        return True                                 # .env~, .env-prod, .env_local, copies horodatées
    if (len(parties) >= 2 and parties[-2] == "gh" and b == "hosts.yml") or \
            (len(parties) >= 2 and parties[-2] == ".docker" and b == "config.json"):
        return True
    if b.endswith(EXTENSIONS) or "mnemonic" in b:
        return True
    if ".ssh" in parties[:-1] and b not in SSH_PERMIS and not b.startswith("known_hosts"):
        return True                                 # clés privées ssh (id_*, ou nommées librement)
    if "keystore" in parties[:-1]:
        return True
    if b == "environ" and len(parties) >= 3 and parties[-3] == "proc":
        return True                                 # /proc/<pid>/environ : l'environnement d'un processus
    return False


# --- Valeurs secrètes ---------------------------------------------------------

# Un nom qui annonce un secret…
SENSIBLE = re.compile(r"(priv(ate)?[_-]?key|secret|api[_-]?key|access[_-]?token|auth[_-]?token|"
                      r"refresh[_-]?token|(^|[_-])token$|bearer|mnemonic|seed[_-]?phrase|"
                      r"pass[_-]?phrase|password|passwd|wallet[_-]?key|signing[_-]?key|ntfy[_-]?topic)", re.I)
# … sauf s'il désigne autre chose que la valeur (CLIENT_SECRET_FILE, API_KEY_HEADER).
PAS_UNE_VALEUR = re.compile(r"[_-](name|file|path|dir|id|ids|arn|url|uri|env|var|header|field|type|"
                            r"len|length|hash|prefix|suffix|count|enabled|set|present|ok|regex|pattern)$", re.I)

CITE = re.compile(r"(?P<n>[A-Za-z_][\w.-]*)[\"']?\s*(?::=|=>|[:=])\s*(?P<q>[\"'])(?P<v>(?:(?!(?P=q)).){0,4000}?)(?P=q)")
# La valeur nue s'arrête aussi sur un guillemet : echo "API_SECRET=…" >> .env,
# docker run -e "…", - "…" d'un docker-compose.
NUE = re.compile(r"(?P<n>[A-Za-z_][\w.-]*)[\"']?\s*[:=]\s*(?P<v>[^\s\"'#;,&|)}\]]+)(?=\s|$|[#;,&|)}\]\"'])")

GABARIT = re.compile(r"""
      \$\{[^}]*\}? | \$\([^)]*\) | \{\{[^}]*\}\} | \$[A-Za-z_]\w*
    | <[^>]+>      | %\([^)]*\)s | \{[A-Za-z_]\w*\} | [()]
    | ^(?:os\.|process\.|env\.|import\b)
""", re.I | re.X)
FACTICE = re.compile(r"^(?:x{3,}|\.{3,}|\*{3,}|-{3,}|none|null|nil|true|false|"
                     r"your[_-]|my[_-]|the[_-]|test|dummy|fake|sample|example|"
                     r"placeholder|changeme|change[_-]me|todo|fixme|"
                     r"remplacer|remplir|votre[_-]|vos[_-]|a[_-]definir|"
                     r"redacted|hidden|masked)", re.I)
A_REMPLIR = re.compile(r"^[A-Z][A-Z_]*_[A-Z_]+$")


def ressemble_a_un_secret(v, entre_guillemets):
    v = v.strip()
    if v.startswith("eyJ") and len(v) >= 20:
        return True                                 # jeton JWT
    if len(v) < 16 or GABARIT.search(v) or FACTICE.match(v) or A_REMPLIR.match(v):
        return False
    if re.search(r"[*\\^]", v):
        return False                                # une expression régulière, pas une valeur
    if v.startswith(("/", "./", "../", "~/")) or re.match(r"https?://", v):
        return False
    if re.fullmatch(r"[\w.-]+(/[\w.-]+)+", v) and re.search(r"\.[A-Za-z0-9]{1,5}$", v):
        return False                                # config/client_secret.json
    mots = v.split()
    if len(mots) >= 8:
        return all(m.isalpha() for m in mots)       # phrase de récupération
    if len(mots) > 1:
        return False
    if not entre_guillemets:
        # Sans guillemets, dans du code, c'est souvent un nom de variable.
        if re.fullmatch(r"[A-Za-z_]\w*(\.[A-Za-z_]\w*)+", v):
            return False                            # settings.api_secret
        if re.fullmatch(r"[a-z_][a-z0-9_]*", v) and "_" in v:
            return False                            # exchange_api_secret
        if re.fullmatch(r"[A-Z_][A-Z0-9_]*", v) and "_" in v:
            return False                            # NOM_DE_CONSTANTE
    return any(c.isalpha() for c in v)


HEX64 = re.compile(r"(?<![0-9A-Za-z])0x[0-9a-fA-F]{64}(?![0-9a-fA-F])")
HEX64_NU = re.compile(r"(?<![0-9A-Za-z])[0-9a-fA-F]{64}(?![0-9A-Za-z])")
NOM_AVANT = re.compile(r"(?P<n>--?[\w-]+|[A-Za-z_][\w.-]*)[\"']?\s*(?:=>|:=|[:=(,\[]|\s)\s*[\"']?\s*$")
NOM_DE_HASH = re.compile(r"(hash|_id|id|digest|root|salt|sig|signature|nonce|(^|[_-])tx|expected|attendu)$", re.I)
CLE_DANS_LE_NOM = re.compile(r"key|priv|(^|[_-])pk($|[_-])|^pk|secret|signer|wallet|mnemonic|seed|"
                             r"account|credential", re.I)
CONTEXTE_HASH = re.compile(r"hash|\btx|txn|transaction|digest|sha|block|root|salt|condition|question|"
                           r"market|topic|event|sig|nonce|merkle|parent|collection|position|asset|order|"
                           r"receipt|\.log\b|logs?/|polygonscan|etherscan|explorer", re.I)
PEM = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")


def cle_0x(ligne, contexte=""):
    """Une clé privée 0x + 64 hexa. Un hash (transaction, condition_id…) a la
    même forme : on regarde le nom qui la précède, puis la ligne, puis les
    lignes au-dessus (en-tête d'un tableau, nom de la liste qui s'ouvre). Sans
    rien qui parle de hash, la valeur est traitée comme une clé.
    64 hexa SANS 0x : une clé seulement sous un nom de clé (from_key, key, pk),
    pas une somme sha256 affichée seule."""
    for m in HEX64.finditer(ligne):
        if len(set(m.group(0)[2:].lower())) <= 1:
            continue                                # 0x000…0, 0xfff…f
        avant = NOM_AVANT.search(ligne[:m.start()])
        nom = (avant.group("n").split(".")[-1] if avant else "")
        if nom and NOM_DE_HASH.search(nom):
            continue
        if nom and CLE_DANS_LE_NOM.search(nom):
            return nom
        if CONTEXTE_HASH.search(ligne) and not CLE_DANS_LE_NOM.search(ligne):
            continue
        if not nom and CONTEXTE_HASH.search(contexte) and not CLE_DANS_LE_NOM.search(ligne):
            continue                                # élément d'une liste de condition_id, ligne de tableau
        return nom or "0x…"
    for m in HEX64_NU.finditer(ligne):
        if len(set(m.group(0).lower())) <= 1:
            continue
        avant = NOM_AVANT.search(ligne[:m.start()])
        nom = (avant.group("n").split(".")[-1] if avant else "")
        if nom and CLE_DANS_LE_NOM.search(nom) and not NOM_DE_HASH.search(nom):
            return nom
    return None


# Jetons portés par une URL ou un en-tête, quel que soit le nom.
JETON_URL = re.compile(r"api\.telegram\.org/bot\d+:[\w-]{30,}"
                       r"|discord(?:app)?\.com/api/webhooks/\d+/[\w-]{40,}"
                       r"|(?:alchemy\.com|infura\.io|quiknode\.pro|quicknode\.com)\S*/v[23]/[\w-]{24,}"
                       r"|\bBearer\s+(?!\$|\{|<)[\w.~+/=-]{20,}", re.I)
# Phrase de récupération sans guillemets : le nom suivi de 11 mots ou plus.
PHRASE = re.compile(r"(?i)(mnemonic|seed[_-]?phrase|recovery[_-]?phrase)[\"']?\s*[:=]\s*[\"']?"
                    r"([a-z]+(?:\s+[a-z]+){10,})")


def valeur_secrete(texte):
    """Le nom qui porte un secret dans le texte, ou None."""
    if not texte or not isinstance(texte, str):
        return None
    if PEM.search(texte):
        return "clé PEM"
    for m in JETON_URL.finditer(texte):
        jeton = m.group(0).split()[-1]
        if not re.search(r"(?i)fake|test|mauvais|faux|wrong|invalid|bad|dummy|example|x{3,}", jeton):
            return "jeton dans une URL"             # un jeton exprès faux d'un essai reste libre
    m = PHRASE.search(texte)
    if m and not FACTICE.match(m.group(2)):
        return m.group(1)
    # "api_secret":⏎ "valeur" : la valeur JSON passée à la ligne suivante.
    texte = re.sub(r'("\s*:)[ \t]*\n[ \t]*(?=")', r"\1 ", texte)
    lignes = texte.splitlines()
    for k, ligne in enumerate(lignes):
        nom = cle_0x(ligne, "\n".join(lignes[max(0, k - 5):k]))
        if nom:
            return nom
        # Fenêtres de 4000 caractères qui se chevauchent : une ligne JSON géante
        # ne cache plus sa fin.
        for debut in range(0, max(1, len(ligne)), 3800):
            morceau = ligne[debut:debut + 4000]
            for motif, cite in ((CITE, True), (NUE, False)):
                for m in motif.finditer(morceau):
                    n = m.group("n").split(".")[-1]
                    if SENSIBLE.search(n) and not PAS_UNE_VALEUR.search(n) \
                            and ressemble_a_un_secret(m.group("v"), cite):
                        return n
    return None


def entree():
    d = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    t = d.get("tool_input") if isinstance(d, dict) else None
    return d, (t if isinstance(t, dict) else {})


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    d, ti = entree()
    if mode == "fichier":
        print("SECRET" if est_fichier_de_secrets(ti.get("file_path") or "") else "OK")
    elif mode == "valeur":
        for ou, cle in (("commande", "command"), ("fichier", "content"), ("edition", "new_string")):
            nom = valeur_secrete(ti.get(cle) or "")
            if nom:
                print(f"{ou}\t{nom[:40]}")
                return
    else:
        raise SystemExit(3)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(3)
