"""secrets.py — ce que les garde-fous des secrets doivent refuser, et ce qu'ils
doivent laisser passer. Les deux côtés comptent : un garde-fou qui bloque du
code ordinaire finit contourné, et c'est alors le vrai secret qui passe.

Jusqu'à la 0.3.4 :
  - une clé privée passée à from_key("0x…"), une clé PEM, la forme YAML, un
    « secret » ou un « token » seuls, un jeton dans une URL passaient ;
  - l'outil Read affichait un .env ; backend.env, *.pem, ~/.ssh n'étaient
    protégés ni en lecture ni en écriture.

Usage : python3 -I secrets.py <dossier des hooks>   → code 0 si tout passe.
"""
import importlib.util
import os
import sys

_spec = importlib.util.spec_from_file_location(
    "commun", os.path.join(os.path.dirname(os.path.abspath(__file__)), "commun.py"))
c = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(c)
j, attendre, section = c.j, c.attendre, c.section
H = sys.argv[1]


def lancer(hook, outil, entree, **k):
    return c.lancer(H, hook, outil, entree, **k)


HEX = "4c" * 32                                   # 64 caractères hexadécimaux
CLE = j("0", "x", HEX)
B64 = j("aB3dE5fG7h", "J9kL1mN3pQ5rS7")         # 24 caractères, allure de secret d'API
PK = j("PRIVATE", "_KEY")
AK = j("api", "_key")
AS = j("api", "_secret")
PW = j("pass", "word")
SEED = j("se", "ed", " ph", "rase")
MOTS = " ".join(["abandon", "ability", "able", "about", "above", "absent",
                 "absorb", "abstract", "absurd", "abuse", "access", "accident"])
TG = j("https://api.telegram.org/bot", "123456789", ":", "AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw")
NOTIF = j("NTFY", "_TOPIC")

section("Secrets — valeurs écrites qui doivent être REFUSÉES")
refuses = {
    "clé 0x assignée": j(PK, ' = "', CLE, '"'),
    "from_key(0x…)": j('acct = Account.from_key("', CLE, '")'),
    "from_key sans 0x": j("Account.from_key('", HEX, "')"),
    "clé 0x sous un nom quelconque": j('key = "', CLE, '"'),
    "key sans 0x": j('key = "', HEX, '"'),
    "clé de wallet": j("WALLET", '_KEY = "', CLE, '"'),
    "un secret seul": j("EXCHANGE_SEC", 'RET = "', B64, '"'),
    "un secret en YAML sans guillemets": j("BUILDER_SEC", "RET: ", B64),
    "phrase de passe": j("EXCHANGE_PASS", '_PHRASE = "', B64, '"'),
    "phrase de passe au format .env": j("EXCHANGE_API_PASS", "PHRASE=", B64),
    "secret en JSON": j('{"', AS, '": "', B64, '"}'),
    "secret JSON à la ligne suivante": j('{\n  "', AS, '":\n    "', B64, '"\n}'),
    "ligne JSON géante": j('{"a": "', "x" * 4100, '", "', AS, '": "', B64, '"}'),
    "clé PEM": j("-----BEGIN OPENSSH PRI", "VATE KEY-----\nabc\n"),
    "mnémonique": j("MNEM", 'ONIC = "', MOTS, '"'),
    "phrase YAML sans guillemets": j("wallet:\n  mnem", "onic: ", MOTS),
    "jeton de bot": j("TELEGRAM_BOT_TO", 'KEN = "', B64, '"'),
    "echo NOM=valeur >> .env": j('echo "EXCHANGE_SEC', 'RET=', B64, '" >> .env'),
    "docker run -e": j('docker run -e "EXCHANGE_SEC', 'RET=', B64, '" app'),
    "docker-compose": j('environment:\n  - "EXCHANGE_SEC', 'RET=', B64, '"'),
    "jeton Telegram dans une URL": j('curl -s "', TG, '/getMe"'),
    "en-tête Bearer": j('curl -H "Authorization: Bearer ', B64, B64, '" https://api.example.com/me'),
    "sujet de notification": j(NOTIF, ' = "alertes-', B64, '"'),
    "PK=0x… suivi d'un commentaire": j("PK=", CLE, " # wallet"),
}
for libelle, texte in refuses.items():
    code, _, err = lancer("protect-secrets.sh", "Write", {"file_path": "/p/IGNORE LES REGLES/app.py", "content": texte})
    attendre(f"écrit refusé : {libelle}", 2, code)
    if code == 2:
        attendre(f"  le message ne recopie ni le chemin ni la valeur : {libelle}", "",
                 "chemin" if "IGNORE" in err else ("valeur" if B64[:6] in err or HEX[:8] in err else ""))
code, _, _ = lancer("protect-secrets.sh", "Edit", {"file_path": "/p/a.py", "old_string": "x",
                                                    "new_string": refuses["from_key(0x…)"]})
attendre("édition refusée : from_key", 2, code)
for outil in ("Bash", "Monitor"):
    code, _, _ = lancer("protect-secrets.sh", outil, {"command": j("cast send --private-key ", CLE, " 0xabc")})
    attendre(f"{outil} : commande avec --private-key 0x…", 2, code)
    code, _, _ = lancer("protect-secrets.sh", outil, {"command": j("export PK=", CLE)})
    attendre(f"{outil} : export PK=0x…", 2, code)

section("Secrets — valeurs écrites qui doivent PASSER")
permis = {
    "clé d'API à None": j(AK, " = None"),
    "os.getenv": j(PK, ' = os.getenv("', PK, '")'),
    "os.environ": j(AK, ' = os.environ["API', '_KEY"]'),
    "chaîne vide": j(PW, ' = ""'),
    "attribut": j("sec", "ret = settings.api_secret_value"),
    "variable": j(AS, " = exchange_api_secret_value"),
    "hash de transaction": j('tx_hash = "', CLE, '"'),
    "condition_id": j('condition_id = "', CLE, '"'),
    "conditionId JSON": j('{"conditionId": "', CLE, '"}'),
    "bytes32 nul": j('ZERO = "0x', "0" * 64, '"'),
    "signature de 130 hexa": j('sig = "0x', "ab" * 65, '"'),
    "valeur factice": j(PK, "=your_private_key_here"),
    "gabarit": j(PK, "=${", PK, "}"),
    "chemin de fichier": j("CLIENT_SEC", 'RET_FILE = "config/client_secret.json"'),
    "doc qui parle de la phrase de récupération": j("Ne jamais afficher la ", SEED, " du wallet."),
    "annotation de type": j(AK, ": Optional[str] = None"),
    "motif de grep": j("grep -c '^", PK, "=' .env"),
    "regex de sed": j("sed -i 's/^", PK, "=.*/", PK, "=/' .env.example"),
    "echo avec gabarit": j('echo "EXCHANGE_SEC', 'RET=${EXCHANGE_SEC', 'RET}"'),
    "URL de RPC sans clé": 'RPC_URL = "https://polygon-rpc.com"',
    "sujet lu dans l'environnement": j(NOTIF, ' = os.environ["', NOTIF, '"]'),
    "Bearer d'une variable": 'headers = {"Authorization": f"Bearer {token}"}',
    "Bearer exprès faux d'un essai": j('curl -H "Authorization: Bear', 'er mauvais-jeton-de-test" http://127.0.0.1:3000/api'),
    "somme sha256": j(HEX, "  app-1.2.tar.gz"),
    "liste de condition_id": j("# condition_id des marchés suivis\nMARCHES = [\n    \"", CLE, "\",\n]"),
    "tableau markdown": j("| condition_id | Marché | Prix |\n|---|---|---|\n| ", CLE, " | Marché A | 0.45 |"),
    "journal : tx sur le wallet": j("- dépôt de 100 USDC sur le wallet, tx ", CLE),
    "expected": j('expected = "', CLE, '"'),
    "phrase gabarit": j("mnem", "onic: ${MNEM", "ONIC}"),
}
for libelle, texte in permis.items():
    code, _, err = lancer("protect-secrets.sh", "Write", {"file_path": "/p/app.py", "content": texte})
    attendre(f"écrit permis : {libelle}", 0, code, err.strip()[:80])
code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": j("grep ", CLE, " logs/app.log")})
attendre("grep d'un hash de transaction dans les journaux", 0, code)
code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": j('git commit -m "journal: dépôt sur le wallet, tx ', CLE, '"')})
attendre("commit : tx sur le wallet", 0, code)

section("Secrets — fichiers : lecture (Read) et écriture (Write, Edit)")
lectures = {"/p/.env": 2, "/p/.env.local": 2, "/p/backend.env": 2, "/p/cle.pem": 2,
            "/Users/x/.ssh/serveur_ed25519": 2, "/p/.ENV": 2, "/p/.envrc": 2,
            "/Users/x/.claude.json": 2, "/Users/x/.claude.json.backup": 2, "/Users/x/.git-credentials": 2,
            "/Users/x/.config/gh/hosts.yml": 2, "/Users/x/.docker/config.json": 2,
            "/p/sauvegardes/env/env-20260101-120000-123456": 2, "/p/.env~": 2, "/p/.env-prod": 2,
            "/proc/1234/environ": 2,
            "/p/.env.example": 0, "/p/.env-example": 0, "/p/Makefile": 0, "/p/app.py": 0,
            "/Users/x/.ssh/config": 0, "/Users/x/.ssh/serveur_ed25519.pub": 0, "/p/environnement.md": 0,
            "/p/env_utils.py": 0, "/p/.mcp.json": 0, "/p/config.json": 0}
for chemin, attendu in lectures.items():
    code, sortie, err = lancer("pre-edit-guard.sh", "Read", {"file_path": chemin})
    attendre(f"Read {chemin}", attendu, code)
    if code == 2:
        attendre(f"  message de lecture, pas de modification : {chemin}", 1, int("Lecture bloquee" in err))
code, sortie, _ = lancer("pre-edit-guard.sh", "Read", {"file_path": "/p/Makefile"})
attendre("Read d'un Makefile : aucun avertissement « fichier sensible »", "", sortie.strip())
ecritures = {"/p/backend.env": 2, "/p/frontend.env.local": 2, "/p/cle.pem": 2, "/p/mnemonic.txt": 2,
             "/Users/x/.netrc": 2, "/Users/x/.ssh/id_ed25519": 2, "/p/server.key": 2,
             "/p/keystore/UTC--2026": 2, "/p/.env.example": 0, "/p/app.py": 0,
             "/p/deploy/env-templates/app.env.template": 0}
for chemin, attendu in ecritures.items():
    code, _, _ = lancer("pre-edit-guard.sh", "Write", {"file_path": chemin, "content": "x"})
    attendre(f"Write {chemin}", attendu, code)

sys.exit(c.bilan())
