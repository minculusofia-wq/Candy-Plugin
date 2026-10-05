"""secrets-copie-locale.py — les cas des garde-fous des secrets écrits dans une
copie locale de ce plugin, pendant ses propres relectures de sécurité
(2026-09-24 à 26). Les deux copies avaient divergé ; leur comparaison du
2026-10-05 a montré que la copie locale fermait des formes que le plugin
laissait passer. Pour que les deux jugent à l'identique, ces cas sont rejoués
ici tels quels, en plus de secrets.py : un même cas joué deux fois ne coûte
que du temps, un cas oublié laisse rouvrir un trou.

Toute valeur piégée est assemblée par morceaux : ce fichier ne contient aucun
secret, et les garde-fous ne refusent pas de l'écrire.

Usage : python3 -I secrets-copie-locale.py <dossier des hooks>   → code 0 si tout passe.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

_spec = importlib.util.spec_from_file_location(
    "commun", os.path.join(os.path.dirname(os.path.abspath(__file__)), "commun.py"))
commun = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(commun)
j, attendre, section = commun.j, commun.attendre, commun.section
H = sys.argv[1]
os.makedirs(os.path.expanduser("~/.cache"), exist_ok=True)   # dossier des essais qui ne doivent pas être sous /tmp


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


def lancer(hook, outil, entree, cwd=None, env=None):
    return commun.lancer(H, hook, outil, entree, cwd=cwd, env=env)


# --- 1. Valeurs secrètes écrites (Write, Edit) -------------------------------
section("Secrets (copie locale) — Valeurs secrètes écrites (Write, Edit)")
ecrits_refuses = {
    "clé 0x assignée": j(PK, ' = "', CLE, '"'),
    "from_key(0x…)": j('acct = Account.from_key("', CLE, '")'),
    "clé 0x sous un nom quelconque": j('key = "', CLE, '"'),
    "clé de wallet": j('WALLET', '_KEY = "', CLE, '"'),
    "secret d'échange": j("EXCHANGE_SEC", 'RET = "', B64, '"'),
    "BUILDER_SECRET en YAML": j("BUILDER_SEC", "RET: ", B64),
    "phrase de passe": j("EXCHANGE_PASS", '_PHRASE = "', B64, '"'),
    "passphrase en .env": j("EXCHANGE_API_PASS", "PHRASE=", B64),
    "secret en JSON": j('{"', AS, '": "', B64, '"}'),
    "clé PEM": j("-----BEGIN OPENSSH PRI", "VATE KEY-----\nabc\n"),
    "mnémonique": j("MNEM", 'ONIC = "', MOTS, '"'),
    "jeton de bot": j("TELEGRAM_BOT_TO", 'KEN = "', B64, '"'),
}
ecrits_permis = {
    "clé d'API à None": j(AK, " = None"),
    "os.getenv": j(PK, ' = os.getenv("', PK, '")'),
    "os.environ": j(AK, ' = os.environ["API', '_KEY"]'),
    "chaîne vide": j(PW, ' = ""'),
    "attribut": j("sec", "ret = settings.exchange_secret_value"),
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
}
for libelle, texte in ecrits_refuses.items():
    code, _, err = lancer("protect-secrets.sh", "Write", {"file_path": "/p/app.py", "content": texte})
    attendre(f"écrit refusé : {libelle}", 2, code)
    if code == 2 and "/p/app.py" in err:
        attendre(f"message sans chemin : {libelle}", "sans chemin", "chemin recopié")
for libelle, texte in ecrits_permis.items():
    code, _, err = lancer("protect-secrets.sh", "Write", {"file_path": "/p/app.py", "content": texte})
    attendre(f"écrit permis : {libelle}", 0, code, err.strip()[:80])
code, _, _ = lancer("protect-secrets.sh", "Edit", {"file_path": "/p/a.py", "old_string": "x",
                                                    "new_string": ecrits_refuses["from_key(0x…)"]})
attendre("édition refusée : from_key", 2, code)

# --- 2. Commandes qui affichent un secret (Bash, Monitor) ---------------------
section("Secrets (copie locale) — Commandes qui affichent un secret (Bash, Monitor)")
S = "ss" + "h"
commandes_refusees = [
    "cat .env", "cat backend/.env", "head -5 .env.local", "less .env.production",
    "grep -i database backend/.env", "cat .env | grep KEY", "bash -c 'cat .env'",
    "awk '{print}' .env", "sed -n 1,5p .env", "xxd .env", "cat frontend.env.local",
    "cat cle.pem", "cat ~/.ssh/serveur_vps", "cat /proc/1234/environ",
    "tr '\\0' '\\n' < /proc/1/environ", "while read l; do echo $l; done < .env",
    j("grep '^", PK, "=' .env"),
    f'{S} vps "cat /opt/bot/.env"', f"{S} vps cat /opt/bot/.env",
    f"{S} -i k root@h 'grep KEY /opt/bot/.env'", f"{S} vps 'cat /proc/42/environ'",
    # relecture de sécurité du 2026-09-25 : $( ) entre guillemets, continuation de ligne
    'echo "$(cat .env)"', 'X="$(grep KEY backend/.env)"; echo "$X"', "cat \\\n  .env",
    f"{S} vps \\\n  'cat /opt/bot/.env'",
]
commandes_permises = [
    j("grep -c '^", PK, "=' .env"), "grep -q KEY .env", "grep -l x .env backend/.env",
    "cut -d= -f1 .env", "sed 's/=.*//' .env", "grep -E '^DRY_RUN=' .env",
    "grep '^LIVE_TRADING=' backend/.env", "awk -F= '{print $1}' .env", "cat .env.example",
    "ls -la .env", "test -f .env && echo ok", "source .env && python run.py",
    "set -a; . ./.env; set +a", "wc -l .env", 'grep -rn "\\.env" src/', "grep .env README.md",
    "cat ~/.ssh/serveur_vps.pub", "cat ~/.ssh/config", f"{S} -i ~/.ssh/serveur_vps vps tail -n 5 f",
    f"{S} vps 'grep -c KEY /opt/bot/.env'", "cp .env.example .env.bak", "cat app.py", "git status",
]
for outil in ("Bash", "Monitor"):
    for c in commandes_refusees:
        code, _, _ = lancer("protect-secrets.sh", outil, {"command": c})
        attendre(f"{outil} refusé : {c!r}", 2, code)
for c in commandes_permises:
    code, _, err = lancer("protect-secrets.sh", "Bash", {"command": c})
    attendre(f"Bash permis : {c!r}", 0, code, err.strip()[:80])
code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": j("cast send --private-key ", CLE, " 0xabc")})
attendre("commande avec --private-key 0x…", 2, code)
code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": j("export PK=", CLE)})
attendre("export PK=0x…", 2, code)
code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": j("grep ", CLE, " logs/bot.log")})
attendre("grep d'un hash de transaction dans les journaux", 0, code)

# --- 3. git add qui emporterait un fichier de secrets -------------------------
section("Secrets (copie locale) — git add qui emporterait un fichier de secrets")
base = tempfile.mkdtemp(prefix="essai-secrets.")
try:
    depot = os.path.join(base, "depot")
    os.makedirs(os.path.join(depot, "src"))
    subprocess.run(["git", "init", "-q", depot], check=True)
    open(os.path.join(depot, ".env"), "w").write("X=1\n")
    open(os.path.join(depot, ".gitignore"), "w").write("node_modules/\n")
    open(os.path.join(depot, "src", "app.py"), "w").write("x = 1\n")
    ailleurs = os.path.join(base, "ailleurs")
    os.makedirs(ailleurs)
    refuses = ["git add -A", "git add --all", "git add .", "git add ./", "git add :/", "git add -Av",
               "git add .env", "git stage -A", f"git -C {depot} add -A", f"cd {depot} && git add ."]
    for c in refuses:
        cwd = ailleurs if c.startswith(("git -C", "cd ")) else depot
        code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": c}, cwd=cwd, env={"CLAUDE_PROJECT_DIR": cwd})
        attendre(f"git add refusé : {c.replace(base, '…')!r}", 2, code)
    for c in ["git add .gitignore", "git add src/app.py", "git add src/", "git status"]:
        code, _, err = lancer("protect-secrets.sh", "Bash", {"command": c}, cwd=depot, env={"CLAUDE_PROJECT_DIR": depot})
        attendre(f"git add permis : {c!r}", 0, code, err.strip()[:80])
    # .env ignoré : git add -A est permis, git add -f .env ne l'est pas
    open(os.path.join(depot, ".gitignore"), "a").write(".env\n")
    code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": "git add -A"}, cwd=depot, env={"CLAUDE_PROJECT_DIR": depot})
    attendre("git add -A avec .env ignoré", 0, code)
    code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": "git add -f .env"}, cwd=depot, env={"CLAUDE_PROJECT_DIR": depot})
    attendre("git add -f .env", 2, code)
finally:
    shutil.rmtree(base, ignore_errors=True)

# --- 4. Noms de fichiers : lecture (Read) et écriture (Write, Edit) -----------
section("Secrets (copie locale) — Noms de fichiers : lecture (Read) et écriture (Write, Edit)")
lectures = {"/p/.env": 2, "/p/.env.local": 2, "/p/backend.env": 2, "/p/cle.pem": 2,
            "/Users/x/.ssh/serveur_vps": 2, "/p/.ENV": 2, "/p/.envrc": 2,
            "/p/.env.example": 0, "/p/Makefile": 0, "/p/app.py": 0, "/Users/x/.ssh/config": 0,
            "/Users/x/.ssh/serveur_vps.pub": 0, "/p/environnement.md": 0}
for chemin, attendu in lectures.items():
    code, sortie, _ = lancer("pre-edit-guard.sh", "Read", {"file_path": chemin})
    attendre(f"Read {chemin}", attendu, code)
    if chemin == "/p/Makefile":
        attendre("Read Makefile sans avertissement", "", sortie.strip())
ecritures = {"/p/backend.env": 2, "/p/frontend.env.local": 2, "/p/cle.pem": 2, "/p/mnemonic.txt": 2,
             "/Users/x/.netrc": 2, "/p/.env.example": 0, "/p/app.py": 0,
             "/p/deploy/env-templates/bot.env.template": 0}
for chemin, attendu in ecritures.items():
    code, _, _ = lancer("pre-edit-guard.sh", "Write", {"file_path": chemin, "content": "x"})
    attendre(f"Write {chemin}", attendu, code)

# --- 5. Relecture de sécurité du 2026-09-25 (SECRETS-01 à 16) ------------------
section("Secrets (copie locale) — Relecture de sécurité du 2026-09-25 (SECRETS-01 à 16)")
NTFY = j("NTFY", "_TOPIC")
TG = j("https://api.telegram.org/bot", "123456789", ":", "AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw")
refuses_5 = [
    # 01 : ~/.claude.json porte les jetons des serveurs MCP
    "jq '.mcpServers' ~/.claude.json", "sed -n '1,80p' ~/.claude.json", "cat ~/.claude.json",
    "jq '.mcpServers | keys, .mcpServers' ~/.claude.json",
    # 02 : joker
    f"{S} vps \"cat /opt/bot/.env*\"", "grep -n KEY .env*", "head -50 backend/.env*",
    # 04 : réglage « non secret » qui en est un
    j("grep '^", NTFY, "=' backend/.env"), "grep '^POLYGON_RPC_URL=' .env",
    # 06 : copies de .env
    "cat backend/sauvegardes/env/env-20260923-132048-937630", "cat .env~", "cat .env-prod",
    # 07 : options de contexte, d'inversion, plusieurs motifs
    "grep -A5 '^DRY_RUN=' .env", "grep -v '^DRY_RUN=' .env", "cut -d= -f1 --complement .env",
    j("grep -e '^DRY_RUN=' -e '^", PK, "=' .env"), "grep -E '^DRY_RUN=|^POLY' .env",
    # 11 : un tube qui ne masque rien
    "cat .env | grep KEY", "cat .env | sort", "grep -v '^#' .env",
    # 14, 15 : environnement des processus
    f"{S} vps 'ps eww -C python3'", "ps auxe", "sdiff .env.example .env", "tee /dev/null < .env",
    "tr '\\0' '\\n' < /proc/$(pgrep -f run.py)/environ", f"{S} vps 'cat /proc/$(pgrep -f run.py)/environ'",
    f"{S} vps 'systemctl show bot -p Environment'",
]
permis_5 = [
    "jq '.mcpServers | keys' ~/.claude.json", "jq '.pluginUsage' ~/.claude.json", "grep -c github ~/.claude.json",
    "ls -la .env*", "grep -c KEY .env*", "grep -n TODO *.py",
    "grep -n '^DRY_RUN=' .env", "grep -E '^(DRY_RUN|LIVE_TRADING)=' .env",
    "cat .env | cut -d= -f1", "grep -v '^#' .env | cut -d= -f1", "cat .env | wc -l",
    "export $(grep -v '^#' .env | xargs) && python3 run.py", "grep -oE '^[A-Z_]+=' .env", "sed -n 's/=.*//p' .env",
    f"{S} vps 'ps aux'", f"{S} vps 'ps -ef | grep python'", "ps -p 123 -o pid,etime",
    "cat /tmp/environnement.md", "echo x | tee -a notes.txt",
]
dossier_5 = tempfile.mkdtemp(prefix="essai-secrets-joker.", dir=os.path.expanduser("~/.cache"))
open(os.path.join(dossier_5, "backend.env"), "w").write("X=1\n")
open(os.path.join(dossier_5, "app.py"), "w").write("x = 1\n")
for c in refuses_5:
    code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": c})
    attendre(f"Bash refusé (relecture) : {c!r}", 2, code)
for c in permis_5:
    code, _, err = lancer("protect-secrets.sh", "Bash", {"command": c})
    attendre(f"Bash permis (relecture) : {c!r}", 0, code, err.strip()[:80])
code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": "grep -n x *"}, cwd=dossier_5)
attendre("grep x * dans un dossier qui contient backend.env", 2, code)
os.remove(os.path.join(dossier_5, "backend.env"))
code, _, err = lancer("protect-secrets.sh", "Bash", {"command": "grep -n x *"}, cwd=dossier_5)
attendre("grep x * dans un dossier sans secret", 0, code, err.strip()[:80])
shutil.rmtree(dossier_5, ignore_errors=True)

# 03 : git affiche un .env commité
base = tempfile.mkdtemp(prefix="essai-secrets-git.")
try:
    depot = os.path.join(base, "depot")
    subprocess.run(["git", "init", "-q", depot], check=True)
    g = ["git", "-C", depot, "-c", "user.email=a@b", "-c", "user.name=a"]
    open(os.path.join(depot, "app.py"), "w").write("x = 1\n")
    subprocess.run(g + ["add", "app.py"], check=True)
    subprocess.run(g + ["commit", "-qm", "un"], check=True)
    sain = subprocess.run(g + ["rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    open(os.path.join(depot, ".env"), "w").write("X=1\n")
    subprocess.run(g + ["add", "-f", ".env"], check=True)
    subprocess.run(g + ["commit", "-qm", "deux"], check=True)
    fautif = subprocess.run(g + ["rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    env_git = {"CLAUDE_PROJECT_DIR": depot}
    for c in ["git show HEAD:.env", "git log -p -- .env", "git log --all -p", "git diff --no-index .env.example .env",
              f"git show {fautif}", "git grep X", f"git -C {depot} show {fautif}"]:
        code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": c}, cwd=depot, env=env_git)
        attendre(f"git refusé : {c.replace(depot, '…')!r}", 2, code)
    for c in ["git log --oneline --all -- .env", f"git show {sain}", f"git show --stat {fautif}",
              "git log -p -- app.py", "git grep -c X", "git status", "git diff app.py"]:
        code, _, err = lancer("protect-secrets.sh", "Bash", {"command": c}, cwd=depot, env=env_git)
        attendre(f"git permis : {c.replace(depot, '…')!r}", 0, code, err.strip()[:80])
    # 12, 13 : git add
    depot2 = os.path.join(base, "depot2")
    subprocess.run(["git", "init", "-q", depot2], check=True)
    open(os.path.join(depot2, ".env"), "w").write("X=1\n")
    open(os.path.join(depot2, "liste.txt"), "w").write(".env\n")
    env2 = {"CLAUDE_PROJECT_DIR": depot2}
    code, _, err = lancer("protect-secrets.sh", "Bash", {"command": "git add . ':!.env'"}, cwd=depot2, env=env2)
    attendre("git add . ':!.env'", 0, code, err.strip()[:80])
    for c in ["git ls-files -o --exclude-standard | xargs git add", "git add --pathspec-from-file=liste.txt",
              f"pushd {depot2} && git add -A"]:
        code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": c}, cwd=depot2 if not c.startswith("pushd") else base, env=env2)
        attendre(f"git add refusé : {c.replace(depot2, '…')!r}", 2, code)
finally:
    shutil.rmtree(base, ignore_errors=True)

# Valeurs écrites (05, 08, 09, 10, 16)
TXT = j('"X', 'Y"')
ecrits_5_refuses = {
    "echo \"NOM=valeur\" >> .env": j('echo "EXCHANGE_SEC', 'RET=', B64, '" >> .env'),
    "docker run -e": j('docker run -e "EXCHANGE_SEC', 'RET=', B64, '" bot'),
    "compose": j('environment:\n  - "EXCHANGE_SEC', 'RET=', B64, '"'),
    "jeton Telegram dans une URL": j('curl -s "', TG, '/getMe"'),
    "Bearer": j('curl -H "Authorization: Bearer ', B64, B64, '" https://api.example.com/me'),
    "sujet ntfy": j(NTFY, ' = "app-', B64, '"'),
    "from_key sans 0x": j("Account.from_key('", HEX, "')"),
    "key sans 0x": j('key = "', HEX, '"'),
    "phrase YAML sans guillemets": j("wallet:\n  mnem", "onic: ", MOTS),
    "JSON à la ligne suivante": j('{\n  "', AS, '":\n    "', B64, '"\n}'),
    "ligne JSON géante": j('{"a": "', "x" * 4100, '", "', AS, '": "', B64, '"}'),
    "PK=0x… wallet": j("PK=", CLE, " # wallet"),
}
ecrits_5_permis = {
    "echo avec gabarit": j('echo "EXCHANGE_SEC', 'RET=${EXCHANGE_SEC', 'RET}"'),
    "gabarit long": j('echo "BUILDER_SEC', 'RET=${BUILDER_SEC', 'RET}"'),
    "RPC sans clé": 'POLYGON_RPC_URL = "https://polygon-rpc.com"',
    "sujet ntfy lu dans l'environnement": j(NTFY, ' = os.environ["', NTFY, '"]'),
    "Bearer d'une variable": 'headers = {"Authorization": f"Bearer {token}"}',
    "Bearer exprès faux d'un essai": j('curl -H "Authorization: Bear', 'er mauvais-jeton-de-test" http://127.0.0.1:3000/api'),
    "somme sha256": j(HEX, "  bot-1.2.tar.gz"),
    "liste de condition_id": j("# condition_id des marchés suivis\nMARCHES = [\n    \"", CLE, "\",\n]"),
    "tableau markdown": j("| condition_id | Marché | Prix |\n|---|---|---|\n| ", CLE, " | Marché A | 0.45 |"),
    "journal : tx sur le wallet": j("- 2026-09-25 : dépôt sur le wallet, tx ", CLE),
    "expected": j('expected = "', CLE, '"'),
    "phrase gabarit": j("mnem", "onic: ${MNEM", "ONIC}"),
}
for libelle, texte in ecrits_5_refuses.items():
    code, _, _ = lancer("protect-secrets.sh", "Write", {"file_path": "/p/app.py", "content": texte})
    attendre(f"écrit refusé (relecture) : {libelle}", 2, code)
for libelle, texte in ecrits_5_permis.items():
    code, _, err = lancer("protect-secrets.sh", "Write", {"file_path": "/p/app.py", "content": texte})
    attendre(f"écrit permis (relecture) : {libelle}", 0, code, err.strip()[:80])
code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": j('git commit -m "journal: dépôt sur le wallet, tx ', CLE, '"')})
attendre("commit : tx sur le wallet", 0, code)

lectures_5 = {"/Users/x/.claude.json": 2, "/Users/x/.claude.json.backup": 2, "/Users/x/.git-credentials": 2,
              "/Users/x/.config/gh/hosts.yml": 2, "/Users/x/.docker/config.json": 2,
              "/p/backend/sauvegardes/env/env-20260923-132048-937630": 2,
              "/p/backend/sauvegardes/env/env.local-20260923-172208-586730": 2,
              "/p/.env~": 2, "/p/.env-prod": 2, "/p/.env-example": 0, "/p/env_utils.py": 0,
              "/p/.mcp.json": 0, "/p/config.json": 0}
for chemin, attendu in lectures_5.items():
    code, _, _ = lancer("pre-edit-guard.sh", "Read", {"file_path": chemin})
    attendre(f"Read {chemin}", attendu, code)

# --- 6. /code-review xhigh du 2026-09-25 : Grep, grep -r, lectures indirectes ---
section("Secrets (copie locale) — /code-review xhigh du 2026-09-25 : Grep, grep -r, lectures indirectes")
dossier_6 = tempfile.mkdtemp(prefix="essai-secrets-r.", dir=os.path.expanduser("~/.cache"))
os.makedirs(os.path.join(dossier_6, "src"))
open(os.path.join(dossier_6, ".env"), "w").write(j("API", "_KEY=", B64, "\nDRY_RUN=true\n"))
open(os.path.join(dossier_6, "src", "app.py"), "w").write("x = 1\n")
refuses_6 = [
    "grep -rn API_KEY .", "grep -r KEY", "grep -R KEY ./", "rg --hidden KEY", "rg -uu KEY .",
    "cp .env /tmp/e.txt && cat /tmp/e.txt", f"{S} vps 'true' && scp vps:/opt/bot/.env /tmp/x && cat /tmp/x",
    j("source .env && echo $", PK), "set -a; . ./.env; env", j('echo "${', PK, ':-absent}"'), j('echo "$', PK, '"'), j("printenv ", PK),
    "source .env; export -p", "source .env && env | grep KEY",
    # /code-review xhigh du 2026-10-04 : options de grep à valeur séparée (un
    # nom global écrasé par le garde sans-verif les faisait mal lire)
    "grep -rn --include .env KEY .", "grep -rn --exclude-dir node_modules KEY .",
]
permis_6 = [
    "grep -rln API_KEY .", "grep -rc KEY .", "grep -rn x src/", "grep -rn TODO .", "grep -rn KEY --include='*.py' .", "grep -rn KEY --exclude='.env*' .", "rg KEY",
    "cp .env.example .env", "cp .env .env.bak", "cp .env sauvegarde/", "scp vps:/opt/bot/.env backend/.env",
    "source .env && python3 run.py", "echo ${API_KEY:+défini}", "echo $DRY_RUN", "printenv PATH",
    "source .env && env | grep -c KEY", "set -a; . ./.env; set +a", 'echo "$PWD/x.jpg"',
    j('echo "clé posée ? $([ -n "$', PK, '" ] && echo oui || echo non)"'),
    "grep -rn --include '*.py' KEY .",
]
for c in refuses_6:
    code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": c}, cwd=dossier_6)
    attendre(f"Bash refusé (revue) : {c!r}", 2, code)
for c in permis_6:
    code, _, err = lancer("protect-secrets.sh", "Bash", {"command": c}, cwd=dossier_6)
    attendre(f"Bash permis (revue) : {c!r}", 0, code, err.strip()[:80])
env_p = os.path.join(dossier_6, ".env")
for libelle, entree, attendu in [
    ("Grep content sur .env", {"pattern": "KEY", "path": env_p, "output_mode": "content"}, 2),
    ("Grep sur .env, noms seuls (défaut)", {"pattern": "KEY", "path": env_p}, 0),
    ("Grep count sur .env", {"pattern": "KEY", "path": env_p, "output_mode": "count"}, 0),
    ("Grep content, glob .env*", {"pattern": "KEY", "path": dossier_6, "glob": ".env*", "output_mode": "content"}, 2),
    ("Grep content sur app.py", {"pattern": "x", "path": os.path.join(dossier_6, "src", "app.py"), "output_mode": "content"}, 0),
    ("Grep content sur un dossier, motif absent du .env", {"pattern": "x = 1", "path": dossier_6, "output_mode": "content"}, 0),
    # relecture de sécurité du lot suivant : accolades, dossier entier
    ("Grep content, glob {.env,x}", {"pattern": "KEY", "path": dossier_6, "glob": "{.env,x}", "output_mode": "content"}, 2),
    ("Grep content sur un dossier, motif dans le .env", {"pattern": "API_KEY", "path": dossier_6, "output_mode": "content"}, 2),
    ("Grep content sur un dossier, glob *.py", {"pattern": "API_KEY", "path": dossier_6, "glob": "*.py", "output_mode": "content"}, 0),
]:
    code, _, _ = lancer("pre-edit-guard.sh", "Grep", entree)
    attendre(libelle, attendu, code)
shutil.rmtree(dossier_6, ignore_errors=True)

# --- 7. Portage des corrections de Candy 0.4.0 (2026-09-26) ------------------
section("Secrets (copie locale) — Portage des corrections de la 0.4.0 (2026-09-26)")
# Chaque défaut a d'abord été reproduit ici, sur les hooks locaux.
dossier_7 = tempfile.mkdtemp(prefix="essai-secrets-7.")
os.makedirs(os.path.join(dossier_7, "src"))
open(os.path.join(dossier_7, ".env"), "w").write(j("DRY_RUN=true\n", "API", "_KEY=", B64, "\n"))
open(os.path.join(dossier_7, "src", "app.py"), "w").write("x = 1\n")


def bash_7(commande, cwd=None):
    code, _, err = lancer("protect-secrets.sh", "Bash", {"command": commande}, cwd=cwd or dossier_7)
    return code, err


# Guillemets : une commande que bash refuserait de lancer (guillemet non fermé)
# était refusée avec le faux motif « Python introuvable » ; $'a\'b' (apostrophe
# échappée dans une chaîne $'…') faisait échouer tout le découpage.
for c in ['echo "abc', "echo $'a\\'b'", "printf $'x\\ty\\n'", "cat $'notes\\x2etxt'", 'git commit -m "abc']:
    code, err = bash_7(c)
    attendre(f"Bash permis (guillemets) : {c!r}", 0, code, err.strip()[:80])
for c in ['cat .env "', "cat $'\\x2eenv'", "cat $'.e\\156v'"]:
    code, err = bash_7(c)
    attendre(f"Bash refusé (guillemets) : {c!r}", 2, code)
    attendre(f"  sans le faux motif « Python introuvable » : {c!r}", 0, int("Python introuvable" in err))

# Redirections : le « 1 » de « -f 1 > f » était retiré comme le « 2 » de « 2> f »,
# et cut -d= -f (sans champ) passait pour un affichage de la ligne entière.
for c in ["cut -d= -f 1 < .env > noms.txt", "cut -d= -f 1 < .env", "cut -d= -f 1 .env 2> err.txt"]:
    code, err = bash_7(c)
    attendre(f"Bash permis (redirection) : {c!r}", 0, code, err.strip()[:80])
for c in ["cut -d= -f 2 < .env", "cut -d= -f 2 < .env 2> err.txt", "cat .env 2>/dev/null", "cat .env 2>&1"]:
    code, err = bash_7(c)
    attendre(f"Bash refusé (redirection) : {c!r}", 2, code)


def git_7(d, *args):
    subprocess.run(["git", "-C", d, "-c", "user.email=a@b", "-c", "user.name=a", "-c", "commit.gpgsign=false", *args],
                   capture_output=True, check=True)


# git add -u n'ajoute que des fichiers SUIVIS : un .env non suivi le faisait refuser.
depot_7 = os.path.join(dossier_7, "depot-u")
os.makedirs(depot_7)
git_7(depot_7, "init", "-q")
open(os.path.join(depot_7, "app.py"), "w").write("x = 1\n")
git_7(depot_7, "add", "app.py")
git_7(depot_7, "commit", "-qm", "un")
open(os.path.join(depot_7, "app.py"), "w").write("x = 2\n")
open(os.path.join(depot_7, ".env"), "w").write("X=1\n")
for c in ["git add -u", "git add --update", "git add -u app.py", "git add -uv"]:
    code, err = bash_7(c, cwd=depot_7)
    attendre(f"Bash permis (git add -u, .env non suivi) : {c!r}", 0, code, err.strip()[:80])
for c in ["git add -A", "git add .", "git add -uA", "git add -u .env", "git add --update --all"]:
    code, err = bash_7(c, cwd=depot_7)
    attendre(f"Bash refusé (git add, .env non suivi) : {c!r}", 2, code)
suivi_7 = os.path.join(dossier_7, "depot-suivi")
os.makedirs(suivi_7)
git_7(suivi_7, "init", "-q")
open(os.path.join(suivi_7, ".env"), "w").write("X=1\n")
git_7(suivi_7, "add", "-f", ".env")
git_7(suivi_7, "commit", "-qm", "un")
open(os.path.join(suivi_7, ".env"), "w").write("X=2\n")
code, _ = bash_7("git add -u", cwd=suivi_7)
attendre("Bash refusé : git add -u avec un .env SUIVI modifié", 2, code)

# Un alias vers add n'était pas suivi : « git ajoute -A » (alias du dépôt) et
# « git -c alias.tout=add tout . » emportaient le .env non suivi.
subprocess.run(["git", "-C", depot_7, "config", "alias.ajoute", "add"], check=True)
for c in ["git ajoute -A", "git ajoute .", "git -c alias.tout=add tout .", "git -c 'alias.tout=!git add' tout -A"]:
    code, err = bash_7(c, cwd=depot_7)
    attendre(f"Bash refusé (alias vers git add) : {c!r}", 2, code)
for c in ["git ajoute app.py", "git ajoute -u", "git -c alias.tout=add tout app.py", "git -c alias.st=status st"]:
    code, err = bash_7(c, cwd=depot_7)
    attendre(f"Bash permis (alias vers git add, sans le .env) : {c!r}", 0, code, err.strip()[:80])

# rg -z et ag -z cherchent dans les archives : ce n'est pas le -z de grep (un
# seul « enregistrement » pour tout le fichier, qui affiche le .env entier).
for c in ["rg -z '^DRY_RUN=' .env", "ag -z '^DRY_RUN=' .env", "rg --search-zip '^DRY_RUN=' .env"]:
    code, err = bash_7(c)
    attendre(f"Bash permis (réglage, archives) : {c!r}", 0, code, err.strip()[:80])
for c in ["grep -z '^DRY_RUN=' .env", "rg --null-data '^DRY_RUN=' .env", "rg -z -C1 '^DRY_RUN=' .env",
          "rg -z '^API_KEY=' .env"]:
    code, err = bash_7(c)
    attendre(f"Bash refusé (grep -z, contexte, nom secret) : {c!r}", 2, code)

# git grep : un fichier suivi au nom de clé (tests/fixtures/dummy.key) faisait
# refuser tout git grep du dépôt, quel que soit le motif. Il est jugé comme
# grep -r, sur le contenu — et chaque ligne d'un fichier de clé est secrète.
fixt_7 = os.path.join(dossier_7, "depot-grep")
os.makedirs(os.path.join(fixt_7, "tests", "fixtures"))
git_7(fixt_7, "init", "-q")
open(os.path.join(fixt_7, "tests", "fixtures", "dummy.key"), "w").write(
    j("-----BEGIN ", "FAKE-----\n", "abcdef\n", "-----END ", "FAKE-----\n"))
open(os.path.join(fixt_7, "app.py"), "w").write("x = 1  # TODO\n")
git_7(fixt_7, "add", "-A")
git_7(fixt_7, "commit", "-qm", "un")
for c in ["git grep TODO", "git grep -n TODO", "git grep -e TODO", "git grep -c abcdef", "grep -rn TODO ."]:
    code, err = bash_7(c, cwd=fixt_7)
    attendre(f"Bash permis (git grep, motif absent de la clé) : {c!r}", 0, code, err.strip()[:80])
for c in ["git grep abcdef", "git grep -n abcdef", "git grep -e abcdef", "git grep -i ABCDEF", "grep -rn abcdef ."]:
    code, err = bash_7(c, cwd=fixt_7)
    attendre(f"Bash refusé (le motif est dans la clé) : {c!r}", 2, code)

# sed -i réécrit le fichier sur place sans rien afficher : il était refusé comme
# une « Lecture ». Seules les commandes qui restent dans le fichier (s/// sans w
# ni e, d, p) sont permises ; w, r, e… font sortir ou entrer autre chose.
for c in ["sed -i 's/^DRY_RUN=true/DRY_RUN=false/' .env", "sed -i '' 's/^DRY_RUN=true/DRY_RUN=false/' .env",
          "sed -i.bak 's/^DRY_RUN=true/DRY_RUN=false/' .env", "sed -i -e 's/^DRY_RUN=true/DRY_RUN=false/' .env",
          "sed -i '' 's#^DRY_RUN=true#DRY_RUN=false#g' .env", "sed -i '' '/^# config/d' .env",
          "sed -i '' -e 's/^DRY_RUN=true/DRY_RUN=false/' -e 's/^MODE=a/MODE=b/' .env",
          "sed --in-place 's/^DRY_RUN=true/DRY_RUN=false/' .env"]:
    code, err = bash_7(c)
    attendre(f"Bash permis (sed -i) : {c!r}", 0, code, err.strip()[:80])
for c in ["sed 's/^DRY_RUN=true/DRY_RUN=false/' .env", "sed -i 's/^DRY/X/w /dev/stdout' .env",
          "sed -i '1,99w /dev/stdout' .env", "sed -i -e 's/a/b/' -e '1,5w /dev/stderr' .env", "sed -i 's/a/b/e' .env"]:
    code, err = bash_7(c)
    attendre(f"Bash refusé (sed qui affiche) : {c!r}", 2, code)

# L'environnement d'un fil d'exécution : /proc/<pid>/task/<tid>/environ passait.
for c in ["cat /proc/1/task/1/environ", "cat /proc/self/task/1/environ", "tr '\\0' '\\n' < /proc/1/task/2/environ",
          "cat /proc/1/environ"]:
    code, err = bash_7(c)
    attendre(f"Bash refusé (environnement d'un processus) : {c!r}", 2, code)
for c in ["cat /proc/1/task/1/status", "cat /proc/1/status", "ls /proc/1/task", "cat notes/environ"]:
    code, err = bash_7(c)
    attendre(f"Bash permis (pas un environnement) : {c!r}", 0, code, err.strip()[:80])

# grep '^NOM=' .env : jugé sur la VALEUR lue (booléen, nombre, mot court), avec
# un veto sur les noms qui disent eux-mêmes clé, jeton, mot de passe. Jusqu'ici
# le nom seul tranchait : DATABASE_URL affichait le mot de passe de la base.
reg_7 = os.path.join(dossier_7, "reglages")
os.makedirs(reg_7)
open(os.path.join(reg_7, ".env"), "w").write(j(
    "DRY_RUN=true\nMAX_API_CALLS=100\nSESSION_TIMEOUT=3600\nLOG_LEVEL=info\n",
    "DATABASE_URL=postgres://u", ":motdepasse", "@h/db\n", "API_BASE=https://api.exemple.invalid/v1\n",
    "DB_PASS", "WORD=abc\n"))
for c in ["grep '^DRY_RUN=' .env", "grep '^MAX_API_CALLS=' .env", "grep '^SESSION_TIMEOUT=' .env",
          "grep '^LOG_LEVEL=' .env", "grep -E '^(DRY_RUN|MAX_API_CALLS)=' .env", "cat .env | grep '^DRY_RUN='",
          "grep '^ABSENT=' .env", f"{j('ss', 'h')} srv \"grep '^DRY_RUN=' /srv/app/.env\""]:
    code, err = bash_7(c, cwd=reg_7)
    attendre(f"Bash permis (réglage à valeur banale) : {c!r}", 0, code, err.strip()[:80])
for c in ["grep '^DATABASE_URL=' .env", "grep '^API_BASE=' .env", "grep -E '^(MAX_API_CALLS|DATABASE_URL)=' .env",
          "cat .env | grep '^DATABASE_URL='", "cd \"$B\" && grep '^DATABASE_URL=' .env", j("grep '^DB_PASS", "WORD=' .env"),
          f"{j('ss', 'h')} srv \"grep '^DATABASE_URL=' /srv/app/.env\""]:
    code, err = bash_7(c, cwd=reg_7)
    attendre(f"Bash refusé (valeur ou nom de secret) : {c!r}", 2, code)

# Fenêtre -A/-B/-C : grep -r près d'un .env ne jugeait que la ligne trouvée ;
# « ^# réglages » ne trouve qu'un commentaire, mais -A1 affiche la ligne d'après.
ctx_7 = os.path.join(dossier_7, "contexte")
os.makedirs(os.path.join(ctx_7, "src"))
open(os.path.join(ctx_7, ".env"), "w").write(j("# réglages\n", "API", "_KEY=", B64, "\n"))
open(os.path.join(ctx_7, "src", "app.py"), "w").write("def foo():\n    return 1\n")
open(os.path.join(ctx_7, "credentials.json"), "w").write(j('{\n  "client', '_secret":\n    "', B64, '"\n}\n'))
open(os.path.join(ctx_7, "cle.pem"), "w").write(j("-----BEGIN ", "FAKE-----\n", "corpsdecle\n", "-----END ", "FAKE-----\n"))
for c in ["grep -rn -C2 'def foo' .", "grep -rn -9 'def foo' .", "grep -rn --context=2 'def foo' .",
          "grep -rn -A1 'return 1' .", "rg -U 'def foo\\(\\):\\n' ."]:
    code, err = bash_7(c, cwd=ctx_7)
    attendre(f"Bash permis (fenêtre sans secret) : {c!r}", 0, code, err.strip()[:80])
for c in ["grep -rn -A3 '^#' .", "grep -rn -A1 '^# réglages' .", "grep -rn --after-context=2 '^# réglages' .",
          "grep -rn -9 '^# réglages' .", "grep -rnA1 '^# réglages' .", "grep -rn -B6 '^-----END' .",
          j("grep -rn -A1 client", "_secret ."), "grep -rz 'réglages' .", "grep -rn --passthru réglages .",
          "rg --hidden -U '# réglages[\\s\\S]*' ."]:
    code, err = bash_7(c, cwd=ctx_7)
    attendre(f"Bash refusé (la fenêtre affiche un secret) : {c!r}", 2, code)
for libelle, entree, attendu in [
    ("Grep -A 2 'def foo'", {"pattern": "def foo", "path": ctx_7, "output_mode": "content", "-A": 2}, 0),
    ("Grep multiline 'def foo\\n'", {"pattern": "def foo\\(\\):\\n", "path": ctx_7, "output_mode": "content",
                                     "multiline": True}, 0),
    ("Grep -A 1 '^# réglages'", {"pattern": "^# réglages", "path": ctx_7, "output_mode": "content", "-A": 1}, 2),
    ("Grep -C 1 '^# réglages'", {"pattern": "^# réglages", "path": ctx_7, "output_mode": "content", "-C": 1}, 2),
    ("Grep -B 6 '^-----END'", {"pattern": "^-----END", "path": ctx_7, "output_mode": "content", "-B": 6}, 2),
    ("Grep -A 1 client_secret (valeur JSON à la ligne)", {"pattern": j("client", "_secret"), "path": ctx_7,
                                                          "output_mode": "content", "-A": 1}, 2),
    ("Grep multiline '# réglages\\nAPI'", {"pattern": "réglages\\nAPI", "path": ctx_7, "output_mode": "content",
                                           "multiline": True}, 2),
]:
    code, _, _ = lancer("pre-edit-guard.sh", "Grep", entree)
    attendre(f"Grep {'refusé' if attendu else 'permis'} : {libelle}", attendu, code)

# Outil Grep : le glob n'était comparé qu'au nom du fichier (« **/*.json »,
# « config/*.json » ne trouvaient rien), un seul glob était lu (« *.py,*.json »),
# [^_] (négation de ripgrep) restait littéral, et « ~ » n'était pas développé.
glob_7 = os.path.join(dossier_7, "globs")
os.makedirs(os.path.join(glob_7, "config"))
for rel in ("wallet.json", os.path.join("config", "wallet.json")):
    open(os.path.join(glob_7, rel), "w").write(j('{"', "private", '_key": "', B64, '"}\n'))
open(os.path.join(glob_7, "app.py"), "w").write("x = 1\n")
maison_7 = os.path.join(dossier_7, "maison")
os.makedirs(os.path.join(maison_7, "proj"))
open(os.path.join(maison_7, "proj", ".env"), "w").write(j("API", "_KEY=", B64, "\n"))
for libelle, entree, attendu, env in [
    ("glob **/*.json", {"glob": "**/*.json"}, 2, None), ("glob config/*.json", {"glob": "config/*.json"}, 2, None),
    ("globs « *.py,*.json »", {"glob": "*.py,*.json"}, 2, None), ("globs « *.py *.json »", {"glob": "*.py *.json"}, 2, None),
    ("glob [^_]*.json", {"glob": "[^_]*.json"}, 2, None), ("glob config/[^_]*.json", {"glob": "config/[^_]*.json"}, 2, None),
    ("path relatif config, glob *.json", {"path": "config", "glob": "*.json"}, 2, None),
    ("path ~/proj", {"path": "~/proj", "pattern": "KEY"}, 2, {"HOME": maison_7}),
    ("glob **/*.py", {"glob": "**/*.py"}, 0, None), ("glob config/*.py", {"glob": "config/*.py"}, 0, None),
    ("globs « *.md,*.py »", {"glob": "*.md,*.py"}, 0, None), ("glob [^_]*.py", {"glob": "[^_]*.py"}, 0, None),
    ("path ~/proj, motif absent", {"path": "~/proj", "pattern": "absent"}, 0, {"HOME": maison_7}),
]:
    entree = dict({"pattern": "key", "path": glob_7, "output_mode": "content"}, **entree)
    code, _, _ = lancer("pre-edit-guard.sh", "Grep", dict(entree), cwd=glob_7, env=env)
    attendre(f"Grep {'refusé' if attendu else 'permis'} : {libelle}", attendu, code)

# Dossier trop grand : le parcours s'arrêtait à 20 000 fichiers et rendait une
# liste partielle, sans rien dire — un .env au-delà passait. Désormais : refus
# avec son propre motif au-delà de la limite (abaissée ici pour l'essai).
grand_7 = os.path.join(dossier_7, "grand")
for k in range(21):
    os.makedirs(os.path.join(grand_7, f"d{k}"))
    for i in range(1000):
        open(os.path.join(grand_7, f"d{k}", f"f{i}.txt"), "w").close()
open(os.path.join(grand_7, ".env"), "w").write("X=1\n")
open(os.path.join(grand_7, "d20", ".env"), "w").write(j("API", "_KEY=", B64, "\n"))
petit_7 = {"CANDY_LIMITE_PARCOURS": "5000"}
code, _, err = lancer("protect-secrets.sh", "Bash", {"command": "grep -rn KEY ."}, cwd=grand_7, env=petit_7)
attendre("grep -r au-delà de la limite : refusé", 2, code)
attendre("  avec son propre motif, qui propose de limiter la recherche", 1, int("trop grand" in err))
code, _, _ = lancer("pre-edit-guard.sh", "Grep", {"pattern": "KEY", "path": grand_7, "output_mode": "content"},
                    cwd=grand_7, env=petit_7)
attendre("outil Grep au-delà de la limite : refusé", 2, code)
code, err = bash_7("grep -rn KEY d0/", cwd=grand_7)
attendre("le même grep limité à un sous-dossier : permis", 0, code, err.strip()[:80])
code, _, _ = lancer("protect-secrets.sh", "Bash", {"command": "grep -rn KEY ."}, cwd=grand_7,
                    env={"CANDY_LIMITE_PARCOURS": "999999999"})
attendre("la variable ne relève pas la limite : 21 000 fichiers jugés sur le fond (KEY : refusé)", 2, code)
code, err = bash_7("grep -rn 'fn main' --include='*.rs' .", cwd=grand_7)
attendre("grep -r --include='*.rs' sur 21 000 fichiers : permis", 0, code, err.strip()[:80])
code, _, _ = lancer("pre-edit-guard.sh", "Grep", {"pattern": "fn main", "path": grand_7, "output_mode": "content"},
                    cwd=grand_7)
attendre("outil Grep sur 21 000 fichiers, motif absent des .env : permis", 0, code)

# git qui dépasse sa limite de temps : dans le garde de git add, l'exception
# n'était pas rattrapée (refus au faux motif « Python introuvable ») ; pour git
# show/log/grep, le délai dépassé laissait passer. Le délai est simulé.
import importlib.util
_spec = importlib.util.spec_from_file_location("ac_essai", os.path.join(H, "analyse-commande.py"))
ac_7 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ac_7)
_spec = importlib.util.spec_from_file_location("ds_essai", os.path.join(H, "detection-secrets.py"))
ds_7 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ds_7)
_vrai_run = subprocess.run


def _lent(cmd, *a, **k):
    if cmd and cmd[0] == "git" and any(x in cmd for x in ("ls-files", "show", "log")):
        raise subprocess.TimeoutExpired(cmd, k.get("timeout") or 1)
    return _vrai_run(cmd, *a, **k)


subprocess.run = _lent
try:
    try:
        obtenu = ac_7.ajout_secret("git add -A", depot_7)
    except Exception as e:
        obtenu = type(e).__name__
    attendre("git add -A, git trop lent : « INCONNU », pas une exception", "INCONNU", obtenu)
    try:
        obtenu = ac_7.git_affiche_un_secret("show", ["HEAD"], depot_7, ds_7)
    except Exception as e:
        obtenu = type(e).__name__
    attendre("git show HEAD, git trop lent : refusé (on ne sait pas ce qu'il montrerait)", True, obtenu)
finally:
    subprocess.run = _vrai_run

# Les git lancés par le garde ne doivent exécuter aucun programme configuré par
# le dépôt : avec log.showSignature, « git show HEAD » faisait lancer le
# gpg.program de .git/config (un dépôt reçu en archive peut le porter).
piege_7 = os.path.join(dossier_7, "piege")
os.makedirs(piege_7)
git_7(piege_7, "init", "-q")
open(os.path.join(piege_7, "app.py"), "w").write("x = 1\n")
git_7(piege_7, "add", "app.py")
git_7(piege_7, "commit", "-qm", "un")
_g = ["git", "-C", piege_7]
_arbre = subprocess.run(_g + ["rev-parse", "HEAD^{tree}"], capture_output=True, text=True).stdout.strip()
_parent = subprocess.run(_g + ["rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
_objet = (f"tree {_arbre}\nparent {_parent}\nauthor a <a@b> 1700000000 +0000\ncommitter a <a@b> 1700000000 +0000\n"
          "gpgsig -----BEGIN PGP SIGNATURE-----\n \n iQEzBAABCAAdFiEE\n -----END PGP SIGNATURE-----\n\nsigne\n")
_sha = subprocess.run(_g + ["hash-object", "-t", "commit", "-w", "--stdin"], input=_objet, capture_output=True,
                      text=True).stdout.strip()
subprocess.run(_g + ["update-ref", "HEAD", _sha], check=True)
open(os.path.join(piege_7, "app.py"), "w").write("x = 2\n")
temoins_7 = {}
for cle in ("gpg.program", "core.fsmonitor"):
    t = os.path.join(dossier_7, "temoin-" + cle)
    prog = os.path.join(dossier_7, "prog-" + cle + ".sh")
    open(prog, "w").write(f"#!/bin/sh\ntouch '{t}'\nexit 1\n")
    os.chmod(prog, 0o755)
    subprocess.run(_g + ["config", cle, prog], check=True)
    temoins_7[cle] = t
subprocess.run(_g + ["config", "log.showSignature", "true"], check=True)
for c in ["git show HEAD", "git log -p -1", "git show HEAD:app.py", "git add -A", "git diff HEAD~1", "git grep x",
          "git -c alias.z=add z -A", "git z -A"]:
    lancer("protect-secrets.sh", "Bash", {"command": c}, cwd=piege_7, env={"CLAUDE_PROJECT_DIR": piege_7})
for cle, t in temoins_7.items():
    attendre(f"protect-secrets ne lance jamais le {cle} du dépôt", 0, int(os.path.exists(t)))

# ssh + document <<EOF : le document est le script lancé sur le serveur quand la
# commande distante lit son entrée (aucune commande, bash -s, sudo -i, su -…).
# Seul « ssh srv 'cat …' » était jugé : « ssh srv <<EOF cat .env EOF » passait.
S7 = j("ss", "h")
LIRE_7 = "cat /srv/app/.env"
for c in [f"{S7} srv <<'EOF'\n{LIRE_7}\nEOF", f"{S7} srv bash -s <<'EOF'\n{LIRE_7}\nEOF",
          f"{S7} srv 'bash -s' <<'EOF'\ncd /srv/app\ngrep KEY .env\nEOF", f"{S7} srv sudo -u app bash <<EOF\n{LIRE_7}\nEOF",
          f"{S7} srv 'sudo -u app bash -s' <<EOF\n{LIRE_7}\nEOF", f"{S7} srv 'sudo -u app bash -s' <<'EOF'\n{LIRE_7}\nEOF",
          f"{S7} srv sudo -i <<EOF\n{LIRE_7}\nEOF", f"{S7} srv bash -e <<'EOF'\n{LIRE_7}\nEOF",
          f"{S7} srv sh -e <<'EOF'\n{LIRE_7}\nEOF", f"{S7} srv sudo -u app bash -e <<'EOF'\n{LIRE_7}\nEOF",
          f"{S7} srv bash -euo pipefail <<'EOF'\n{LIRE_7}\nEOF", f"{S7} srv bash -s prod <<'EOF'\n{LIRE_7}\nEOF",
          f"{S7} srv bash /dev/stdin <<'EOF'\n{LIRE_7}\nEOF", f"{S7} srv sudo su - app <<'EOF'\n{LIRE_7}\nEOF",
          f"{S7} srv su - app <<'EOF'\n{LIRE_7}\nEOF", f"{S7} srv 'cd /srv/app && bash -s' <<'EOF'\n{LIRE_7}\nEOF",
          f"{S7} srv fish <<'EOF'\n{LIRE_7}\nEOF", f"{S7} srv bash <<< '{LIRE_7}'",
          f"{S7} srv python3 - <<EOF\nprint(open('/srv/app/.env').read())\nEOF",
          f"{S7} srv python3 /dev/stdin <<'EOF'\nprint(open('/srv/app/.env').read())\nEOF"]:
    code, err = bash_7(c)
    attendre(f"Bash refusé (ssh + document) : {c[:60]!r}", 2, code)
for c in [f"{S7} srv <<'EOF'\nsystemctl status bot\nEOF", f"{S7} srv bash -s <<'EOF'\ntail -n 50 /var/log/bot.log\nEOF",
          f"{S7} srv 'cat > /tmp/notes.txt' <<'EOF'\n{LIRE_7}\nEOF", f"{S7} srv bash deploy.sh <<'EOF'\n{LIRE_7}\nEOF",
          f"{S7} srv python3 - <<'EOF'\nprint(1)\nEOF",
          f"{S7} srv python3 - <<'EOF'\nimport os\nprint(os.path.exists('/srv/app/.env'))\nEOF"]:
    code, err = bash_7(c)
    attendre(f"Bash permis (ssh + document sans lecture de secret) : {c[:60]!r}", 0, code, err.strip()[:80])

# Refus gênants retirés : une variable de boucle nommée key, une écriture
# redirigée vers un fichier de secrets, la valeur de --exclude, env $(… | xargs),
# du code source rangé sous wallet/ ou keystore/.
gene_7 = os.path.join(dossier_7, "genes")
os.makedirs(os.path.join(gene_7, "src", "wallet"))
os.makedirs(os.path.join(gene_7, "src", "keystore"))
open(os.path.join(gene_7, ".env"), "w").write(j("# x\n", "API", "_KEY=", B64, "\n"))
open(os.path.join(gene_7, "src", "wallet", "mnemonic.py"), "w").write("def generer():\n    return None\n")
open(os.path.join(gene_7, "src", "keystore", "index.ts"), "w").write("export const x = 1\n")
open(os.path.join(gene_7, "src", "keystore", "cle.json"), "w").write("{}\n")
open(os.path.join(gene_7, "mnemonic.txt"), "w").write("mots\n")
AK7 = j("API", "_KEY")
for c in ["for key in a b c; do echo $key; done", f'echo "{AK7}=${AK7}" > .env.prod', f'echo "{AK7}=${AK7}" >> .env',
          "rsync -avz --exclude .env ./ srv:/srv/app", "rsync -avz --exclude=.env ./ srv:/srv/app",
          "env $(grep -v '^#' .env | xargs) node server.js", "cat src/wallet/mnemonic.py"]:
    code, err = bash_7(c, cwd=gene_7)
    attendre(f"Bash permis (refus gênant retiré) : {c!r}", 0, code, err.strip()[:80])
for c in [f"echo ${AK7}", f"for x in a; do echo ${AK7}; done", f'echo "{AK7}=${AK7}"', f'echo "{AK7}=${AK7}" > notes.txt',
          f'echo "${AK7}" | tee .env.prod', "rsync -avz .env srv:/tmp/x", "echo $(grep -v '^#' .env | xargs)",
          "cat mnemonic.txt", "cat src/keystore/cle.json", "cat src/keystore/index.ts"]:
    code, err = bash_7(c, cwd=gene_7)
    attendre(f"Bash refusé (voisin d'un refus retiré) : {c!r}", 2, code)
for f, attendu in [(os.path.join(gene_7, "src", "wallet", "mnemonic.py"), 0),
                   (os.path.join(gene_7, "src", "keystore", "index.ts"), 2),
                   (os.path.join(gene_7, "mnemonic.txt"), 2), (os.path.join(gene_7, "src", "keystore", "cle.json"), 2)]:
    code, _, _ = lancer("pre-edit-guard.sh", "Read", {"file_path": f})
    attendre(f"Read {'refusé' if attendu else 'permis'} : {os.path.relpath(f, gene_7)}", attendu, code)
# Relecture de sécurité du portage : l'exception « code source » passait avant
# les dossiers dédiés aux clés — keystore/key.ts ou ~/.ssh/backup.sh, lus ou
# ajoutés par git add, n'étaient plus protégés. Un dossier keystore/ ou .ssh/
# reste un coffre, quelle que soit l'extension (src/keystore/index.ts compris).
coffre_7 = os.path.join(dossier_7, "coffre")
os.makedirs(os.path.join(coffre_7, "keystore"))
os.makedirs(os.path.join(coffre_7, ".ssh"))
git_7(coffre_7, "init", "-q")
open(os.path.join(coffre_7, "keystore", "key.ts"), "w").write(j('export const k = "', CLE, '"\n'))
open(os.path.join(coffre_7, ".ssh", "backup.sh"), "w").write("x\n")
for c in ["cat keystore/key.ts", "cat .ssh/backup.sh", "git add keystore/key.ts", "git add .ssh/backup.sh"]:
    code, err = bash_7(c, cwd=coffre_7)
    attendre(f"Bash refusé (fichier de code dans un coffre) : {c!r}", 2, code)
for f in (os.path.join(coffre_7, "keystore", "key.ts"), os.path.join(coffre_7, ".ssh", "backup.sh")):
    code, _, _ = lancer("pre-edit-guard.sh", "Read", {"file_path": f})
    attendre(f"Read refusé : {os.path.relpath(f, coffre_7)}", 2, code)

# grep -r affichait une ligne d'un fichier de secrets reconnu par son nom
# (wallet.json, .pgpass, credentials…) dès qu'elle ne ressemblait pas elle-même
# à une valeur : une phrase de récupération, un mot de passe en clair.
# « cat wallet.json » était refusé, « grep -rn apple . » non (préexistant,
# trouvé par la relecture de sécurité du portage).
noms_7 = os.path.join(dossier_7, "noms-exacts")
os.makedirs(os.path.join(noms_7, "src"))
open(os.path.join(noms_7, "wallet.json"), "w").write('{"data": "apple banana cherry dog"}\n')
open(os.path.join(noms_7, ".pgpass"), "w").write(j("myhost:5432:mydb:appuser:", "hunter", "deux\n"))
open(os.path.join(noms_7, "src", "app.py"), "w").write("x = 1  # TODO\n")
for c in ["grep -rn apple .", "grep -rn 5432 .", "rg --hidden 5432 ."]:
    code, err = bash_7(c, cwd=noms_7)
    attendre(f"Bash refusé (ligne d'un fichier de secrets) : {c!r}", 2, code)
for c in ["grep -rn TODO .", "grep -rn 'x = 1' ."]:
    code, err = bash_7(c, cwd=noms_7)
    attendre(f"Bash permis (motif absent des fichiers de secrets) : {c!r}", 0, code, err.strip()[:80])
for libelle, motif, attendu in [("apple", "apple", 2), ("TODO", "TODO", 0)]:
    code, _, _ = lancer("pre-edit-guard.sh", "Grep", {"pattern": motif, "path": noms_7, "output_mode": "content"})
    attendre(f"Grep {'refusé' if attendu else 'permis'} sur le dossier : {libelle}", attendu, code)

shutil.rmtree(dossier_7, ignore_errors=True)

sys.exit(commun.bilan())
