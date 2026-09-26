#!/usr/bin/env python3
#
# analyse-commande.py — lire une commande comme bash la lit, pour les
# garde-fous qui en dépendent : protect-secrets.sh (affichage d'un fichier de
# secrets, git add qui l'emporterait), validate-before-push.sh (le dépôt
# réellement poussé) et rule12-phase-debug-required.sh (le commit de clôture).
# Appelé par eux, jamais branché seul.
#
# Pourquoi un vrai découpage : jusqu'à la 0.3.4, ces garde-fous reconnaissaient
# la commande par des motifs de texte. « cat .env » passait, « git -C x push »
# n'était pas contrôlé, « cd x && git push » contrôlait le mauvais dossier,
# « git add -Av » passait, un « \\ » + retour à la ligne entre git et commit
# échappait au garde de clôture, et un corps de message qui citait une clôture
# passée bloquait un commit ordinaire.
#
# Limite assumée : une lecture statique ne voit pas ce qu'une variable
# contiendra à l'exécution (cat "$F", git -C "$D" push). Il reste un rappel
# mécanique, pas un audit : ne jamais lire son silence comme une preuve.
#
# Entrée : le JSON du hook sur stdin. Sortie : un mot sur stdout.
#   analyse-commande.py protection  →  VALEUR\t<où> | LECTURE | TROP_GRAND | AJOUT | AJOUT_INCONNU | OK
#   analyse-commande.py pousses     →  « <dossier>\t<références> » pour chaque git push, un par ligne
#   analyse-commande.py cloture     →  « OUI\t<dossier> » | NON
# Toute panne (entrée illisible, exception) sort en code 3 : le garde-fou
# appelant refuse alors la commande au lieu de la laisser passer.

import glob
import json
import os
import re
import shlex
import sys
from urllib.parse import unquote

PROFONDEUR = 6
INCONNU = "__texte_calcule__"          # commande dont le texte n'est connu qu'à l'exécution
ENVELOPPES = {"sudo", "env", "nohup", "time", "exec", "command", "builtin", "caffeinate",
              "timeout", "nice", "xargs", "stdbuf", "doas", "watch", "screen", "setsid", "disown"}
MOTS_CLES = {"!", "if", "then", "do", "else", "elif", "while", "until", "function"}
INTERPRETES = {"bash", "sh", "zsh", "dash", "ksh"}
OPTIONS_ENVELOPPES = {"sudo": "ugphCDrtU", "doas": "uC", "timeout": "sk", "nice": "n",
                      "env": "uC", "xargs": "IanLPdsE", "stdbuf": "ioe", "exec": "a", "watch": "nd",
                      "screen": "Stc"}
SEPARATEURS = {";", "&&", "||", "|", "&", "(", ")", "()", "|&", ";;", ";&", "{", "}"}
REDIRECTIONS = {">", ">>", "<", "<<", "<<<", ">&", "<&", ">|", "&>", "&>>"}
DOCUMENT = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_]\w*)\1")

def sans_documents(texte, corps=None, infos=None):
    """Retire le corps des documents <<EOF : ce n'est pas une commande (un
    message de commit qui cite un script de déploiement ne déploie rien).
    Un « << » écrit entre guillemets n'ouvre rien : les guillemets sont suivis,
    y compris « "$(cat <<'EOF' … EOF)" », la forme courante des commits.
    Les corps retirés sont rangés dans « corps », un par « << », dans l'ordre :
    celui qui alimente un interprète (bash <<EOF) est relu comme un script."""
    sortie, attente, pile = [], [], [None]
    corps = corps if corps is not None else []
    infos = infos if infos is not None else []
    i, n = 0, len(texte)
    while i < n:
        c, haut = texte[i], pile[-1]
        libre = haut in (None, "$(", "$(m")
        # Un commentaire (# en début de mot, hors guillemets) est recopié tel
        # quel : une apostrophe dedans (« # l'essai ») n'ouvre rien ; sinon
        # elle inversait l'état des guillemets.
        if c == "#" and libre and (i == 0 or texte[i - 1] in " \t\n;&|()"):
            j = texte.find("\n", i)
            j = n if j < 0 else j
            sortie.append(texte[i:j])
            i = j
            continue
        if c == "\n" and libre and attente:
            sortie.append(c)
            i += 1
            for fin, place in attente:              # saute chaque corps jusqu'à sa ligne de fin
                lignes = []
                while i < n:
                    j = texte.find("\n", i)
                    j = n if j == -1 else j
                    ligne, i = texte[i:j], min(j + 1, n)
                    if ligne.strip() == fin:
                        break
                    lignes.append(ligne)
                corps[place] = "\n".join(lignes)
            attente = []
            continue
        if haut == "'":
            if c == "'":
                pile.pop()
        elif c == "\\":
            sortie.append(texte[i:i + 2])
            i += 2
            continue
        elif texte.startswith("$(", i):
            # « $( » en début de mot devient des mots de la ligne ; au milieu
            # d'un mot ou entre guillemets, un texte relu à part.
            debut_de_mot = haut != '"' and (i == 0 or texte[i - 1] in " \t\n;&|()<>")
            pile.append("$(" if debut_de_mot else "$(m")
            sortie.append("$(")
            i += 2
            continue
        elif haut == '"':
            if c == '"':
                pile.pop()
        elif c == ")" and haut in ("$(", "$(m"):
            pile.pop()
        elif c in "'\"":
            pile.append(c)
        elif texte.startswith("<<", i) and not texte.startswith("<<<", i):
            m = DOCUMENT.match(texte, i)
            corps.append("")
            # Visible = un « << » que la ligne découpée montrera comme un mot :
            # ni entre guillemets, ni dans un $( ) collé à un mot.
            infos.append([m.group(2) if m else "", all(x in (None, "$(") for x in pile)])
            if m:
                attente.append((m.group(2), len(corps) - 1))
        sortie.append(c)
        i += 1
    return "".join(sortie)


PONCTUATION = set("();<>|&")
# Les opérateurs de bash, du plus long au plus court. Lue « comme shlex »,
# toute ponctuation qui se suit formerait un seul mot : « )&& », « ); »,
# « &&( » deviendraient des mots inconnus, et la commande suivante passerait
# pour un argument (« (cd x && ls)&&cat .env »).
OPERATEURS = sorted(["&&", "||", ";;&", ";;", ";&", "|&", "&>>", "&>", ">>", ">&", ">|", "<<<", "<<-", "<<", "<&",
                     "<>", "<(", ">(", "(", ")", ";", "&", "|", "<", ">"], key=len, reverse=True)


def fin_de_substitution(t, k):
    """Indice de la « ) » qui ferme le « $( » ouvert juste avant t[k]."""
    prof, i, n = 1, k, len(t)
    while i < n:
        c = t[i]
        if c == "\\":
            i += 2
            continue
        if c == "'":
            j = t.find("'", i + 1)
            if j < 0:
                raise ValueError("apostrophe non fermée")
            i = j + 1
            continue
        if c == '"':
            i += 1
            while i < n and t[i] != '"':
                i += 2 if t[i] == "\\" else 1
            i += 1
            continue
        if c == "(":
            prof += 1
        elif c == ")":
            prof -= 1
            if prof == 0:
                return i
        i += 1
    raise ValueError("$( non fermé")


ECHAPPEMENTS_C = {"a": b"\a", "b": b"\b", "e": b"\x1b", "E": b"\x1b", "f": b"\f", "n": b"\n", "r": b"\r",
                  "t": b"\t", "v": b"\v", "\\": b"\\", "'": b"'", '"': b'"', "?": b"?"}


def chaine_ansi_c(t, j):
    """Le texte d'un $'…' qui commence en t[j] (après « $' ») décodé comme bash
    (\\x2e, \\056, \\u00e9, \\cA, \\'…), et l'indice qui suit l'apostrophe
    fermante. Jusqu'à la relecture de la 0.3.5, cat $'\\x2eenv' passait, et
    $'a\\'b' faisait échouer tout le découpage."""
    res, n = bytearray(), len(t)
    while j < n:
        c = t[j]
        if c == "'":
            return res.decode("utf-8", "replace"), j + 1
        if c == "\\" and j + 1 < n:
            d = t[j + 1]
            m = None
            if d in ECHAPPEMENTS_C:
                res += ECHAPPEMENTS_C[d]
                j += 2
            elif d in "01234567":
                m = re.match(r"[0-7]{1,3}", t[j + 1:])
                res.append(int(m.group(0), 8) & 0xFF)
                j += 1 + len(m.group(0))
            elif d == "x" and re.match(r"[0-9A-Fa-f]", t[j + 2:j + 3]):
                m = re.match(r"[0-9A-Fa-f]{1,2}", t[j + 2:])
                res.append(int(m.group(0), 16))
                j += 2 + len(m.group(0))
            elif d in "uU" and re.match(r"[0-9A-Fa-f]", t[j + 2:j + 3]):
                m = re.match(r"[0-9A-Fa-f]{1,%d}" % (4 if d == "u" else 8), t[j + 2:])
                try:
                    res += chr(int(m.group(0), 16)).encode("utf-8")
                except (ValueError, OverflowError):
                    pass
                j += 2 + len(m.group(0))
            elif d == "c" and j + 2 < n:
                res.append(ord(t[j + 2]) & 0x1F)
                j += 3
            else:
                res += ("\\" + d).encode("utf-8")
                j += 2
        else:
            res += c.encode("utf-8", "replace")
            j += 1
    raise ValueError("$' non fermé")


def lexer(texte):
    """Découpe comme bash : mots décodés (apostrophes, guillemets, barres
    obliques), ponctuation groupée comme shlex (&&, >>, 2>…), commentaires
    retirés, « \\ » + retour à la ligne = continuation. Rend (mots,
    substitutions) : le corps de chaque $( … ) et `…` écrit ENTRE GUILLEMETS
    DOUBLES, que bash exécute. shlex laisse ces corps dans un mot
    (X="$(cat .env)" passerait pour une simple affectation), garde la barre
    oblique de « \\$ » entre guillemets, et prend une continuation de ligne pour
    une fin de commande."""
    mots, subs, cur = [], [], None
    i, n = 0, len(texte)
    t = texte

    def fin():
        nonlocal cur
        if cur is not None:
            mots.append(cur)
            cur = None

    while i < n:
        c = t[i]
        if c in " \t\r":
            fin()
            i += 1
        elif c == "\n":
            fin()
            mots.append(";")
            i += 1
        elif c == "#" and cur is None:
            j = t.find("\n", i)
            i = n if j < 0 else j
        elif c in PONCTUATION:
            fin()
            op = next(o for o in OPERATEURS if t.startswith(o, i))
            mots.append("<<" if op == "<<-" else op)
            i += len(op)
        elif c == "`":
            fin()
            mots.append(";")                        # `cmd` hors guillemets : une commande à part
            i += 1
        elif c == "\\":
            if t.startswith("\n", i + 1):
                i += 2                              # continuation de ligne
            else:
                cur = (cur or "") + t[i + 1:i + 2]
                i += 2
        elif c == "'":
            j = t.find("'", i + 1)
            if j < 0:
                raise ValueError("apostrophe non fermée")
            cur = (cur or "") + t[i + 1:j]
            i = j + 1
        elif c == '"':
            i += 1
            morceau = []
            while True:
                if i >= n:
                    raise ValueError("guillemet non fermé")
                c = t[i]
                if c == '"':
                    i += 1
                    break
                if c == "\\" and i + 1 < n and t[i + 1] in '$`"\\\n':
                    if t[i + 1] != "\n":
                        morceau.append(t[i + 1])
                    i += 2
                elif t.startswith("$(", i) and not t.startswith("$((", i):
                    j = fin_de_substitution(t, i + 2)
                    subs.append(t[i + 2:j])
                    morceau.append(t[i:j + 1])
                    i = j + 1
                elif c == "`":
                    j = i + 1
                    while j < n and t[j] != "`":
                        j += 2 if t[j] == "\\" else 1
                    if j >= n:
                        raise ValueError("accent grave non fermé")
                    subs.append(t[i + 1:j])
                    morceau.append(t[i:j + 1])
                    i = j + 1
                else:
                    morceau.append(c)
                    i += 1
            cur = (cur or "") + "".join(morceau)
        elif c == "$" and t.startswith("$'", i):
            decode, i = chaine_ansi_c(t, i + 2)
            cur = (cur or "") + decode
        elif c == "$" and t.startswith('$"', i):
            i += 1                                  # $"…" : une chaîne traduite, lue comme "…"
        elif c == "$" and cur is not None and t.startswith("$(", i) and not t.startswith("$((", i):
            # /proc/$(pgrep -f app)/environ : le mot reste entier, le corps
            # est relu.
            j = fin_de_substitution(t, i + 2)
            subs.append(t[i + 2:j])
            cur += t[i:j + 1]
            i = j + 1
        else:
            cur = (cur or "") + c
            i += 1
    fin()
    return mots, subs


def decouper_complet(texte):
    """(mots, substitutions, documents) ; chaque document est
    [nom de fin, corps, visible, déjà rattaché]."""
    corps, infos = [], []
    t = sans_documents(texte, corps, infos)
    t = re.sub(r"\$\{IFS\}|\$IFS\b", " ", t)
    mots, subs = lexer(t)
    return mots, subs, [[nom, c, vis, False] for c, (nom, vis) in zip(corps, infos)]


def decouper(texte):
    """(mots, substitutions entre guillemets, corps des documents <<)."""
    docs = []
    t = sans_documents(texte, docs)
    t = re.sub(r"\$\{IFS\}|\$IFS\b", " ", t)       # ${IFS} vaut une espace : cat${IFS}.env
    mots, subs = lexer(t)
    return mots, subs, docs


def options_interprete(mots):
    """(indice du script, code donné par -c ou None, bash -n) pour bash, sh,
    zsh… -o/+o/-O/+O et --rcfile/--init-file prennent une valeur ; +e, +x sont
    des options : « bash -o pipefail -c "…" » est relu comme « bash -c »."""
    j, syntaxe = 1, False
    while j < len(mots) and len(mots[j]) > 1 and mots[j][0] in "-+":
        o = mots[j]
        if o == "--":
            return j + 1, None, syntaxe
        if o in ("-o", "+o", "-O", "+O", "--rcfile", "--init-file"):
            j += 2
            continue
        if not o.startswith("--"):
            lettres = o[1:]
            if o[0] == "-" and "c" in lettres:
                return j + 2, (mots[j + 1] if j + 1 < len(mots) else ""), syntaxe
            if o[0] == "-" and "n" in lettres:
                syntaxe = True
            if lettres[-1:] in ("o", "O"):
                j += 2                              # -eo pipefail : la valeur suit
                continue
        j += 1
    return j, None, syntaxe


def commandes_et_entrees(texte, prof=0, suite=False, heritage=None):
    """Chaque commande simple de la ligne, les mots de tête qui n'exécutent rien
    d'autre (sudo, env, if, VAR=x…) retirés, le code passé à bash -c, bash <<<,
    eval, env -S et find -exec ouvert et relu, avec ce qui entre dans chaque commande :
    [(mots, écrit, [(genre, valeur)])], genre = « fichier » (< f),
    « texte » (<<< t), « document » (corps d'un <<EOF), « prefixe » (VAR=…
    placé devant la commande). suite=True ajoute un 4e élément : le
    séparateur qui suit la commande (« | » pour un tube), ou None."""
    if prof > PROFONDEUR:
        raise ValueError("imbrication trop profonde")
    res, cur, ecrit, entrees = [], [], False, []
    mots, subs, docs = decouper_complet(texte)
    # Les corps des documents d'un $( ) relu à part ont été retirés du texte de
    # la ligne : ils sont transmis au texte relu (heritage).
    caches = [d for d in docs if not d[2]]

    def document(nom):
        """Le corps du document « << nom » : rattaché par son nom, pas par son
        rang : un « "$(cat <<'EOF' …)" » plus tôt décalerait tous les suivants."""
        corps = None
        for choix in (lambda d: d[0] == nom, lambda d: True):
            d = next((d for d in docs if d[2] and not d[3] and choix(d)), None)
            if d is not None:
                d[3], corps = True, d[1]
                break
        if not corps and heritage:
            # Texte relu à part : son corps a été retiré plus haut, on le reprend.
            h = next((h for h in heritage if not h[3] and h[0] == nom), None)
            if h is not None:
                h[3], corps = True, h[1]
        return corps or ""

    def fermer(sep=None):
        if cur:
            res.append((cur, ecrit, entrees, sep))
        elif ecrit:
            res.append(([":"], True, [], sep))      # « > fichier » seul : il vide le fichier
        elif any(g == "fichier" for g, _ in entrees):
            res.append((["cat"], False, entrees, sep))  # « $(< f) » : bash lit le fichier, comme cat

    i = 0
    while i < len(mots):
        m = mots[i]
        if m in SEPARATEURS or m == "$" or m in ("<(", ">("):
            fermer(m)                               # <( ) et >( ) : une commande à part
            cur, ecrit, entrees = [], False, []
        elif m in REDIRECTIONS or re.fullmatch(r"[<>&|]*[<>][<>&|]*", m):
            cible = mots[i + 1] if i + 1 < len(mots) else ""
            if ">" in m and not (cible == "/dev/null" or re.fullmatch(r"&?\d+|&?-", cible)):
                ecrit = True                        # > f, >> f, &> f, 2> f : un fichier est écrit
            elif m == "<<<":
                entrees.append(("texte", cible))    # bash <<< "code" : le texte est un script
            elif m == "<":
                entrees.append(("fichier", cible))  # bash < script.sh
            elif m == "<<":
                entrees.append(("document", document(cible)))
            if cur and re.fullmatch(r"\d+", cur[-1]):
                cur.pop()                           # le « 2 » de « 2> » n'est pas un argument
            i += 1                                  # la cible n'est pas un mot de la commande
        else:
            cur.append(m)
        i += 1
    fermer()

    sortie = []
    for orig, ecrit, entrees, sep in res:
        mots_cmd = sans_enveloppe(orig)
        tete = orig[:len(orig) - len(mots_cmd)]
        entrees = entrees + [("prefixe", w.split("=", 1)[0]) for w in tete
                             if re.fullmatch(r"[A-Za-z_]\w*=.*", w)]
        if mots_cmd and any(os.path.basename(w) == "xargs" for w in tete):
            entrees = entrees + [("xargs", "")]     # ses arguments viennent de la commande d'avant
        if not mots_cmd:
            if any(os.path.basename(w.lstrip("\\")) in ("sudo", "doas", "su") for w in tete):
                mots_cmd = ["sudo"]                 # sudo -s, sudo -i : un shell root qui lit son entrée
            elif suite and any(os.path.basename(w) == "xargs" for w in tete):
                mots_cmd = ["xargs"]                # « … | xargs » seul : repère pour les tubes
            elif suite and tete and os.path.basename(tete[0].lstrip("\\")) == "env":
                mots_cmd = ["env"]                  # « env » seul affiche l'environnement
            else:
                continue
        nom = os.path.basename(mots_cmd[0].lstrip("\\"))
        if nom in INTERPRETES or mots_cmd == ["sudo"]:
            j, code, _ = options_interprete(mots_cmd)
            if code is not None:
                sortie.extend(commandes_et_entrees(code, prof + 1, suite))
            for genre, cible in entrees:
                if genre in ("texte", "document"):
                    sortie.extend(commandes_et_entrees(cible, prof + 1, suite))
                elif genre == "fichier" and code is None and j >= len(mots_cmd):
                    mots_cmd = mots_cmd + [cible]   # bash < script.sh : comme bash script.sh
        elif nom == "eval":
            code = " ".join(mots_cmd[1:])
            if "$" in code or "`" in code:
                sortie.append(([INCONNU], ecrit, [], None) if suite else ([INCONNU], ecrit, []))
            else:
                sortie.extend(commandes_et_entrees(code, prof + 1, suite))
        elif nom == "tmux":
            # tmux new -d -s app 'cat .env' : la commande de la fenêtre est relue.
            k = 1
            while k < len(mots_cmd) and mots_cmd[k].startswith("-"):
                k += 2 if mots_cmd[k] in ("-L", "-S", "-f") else 1
            if k < len(mots_cmd) and mots_cmd[k] in ("new", "new-session", "new-window", "neww", "split-window",
                                                      "splitw", "respawn-pane", "respawnp", "send-keys", "send"):
                k += 1
                reste = []
                while k < len(mots_cmd):
                    w = mots_cmd[k]
                    if w.startswith("-") and not reste:
                        k += 2 if w in ("-s", "-n", "-t", "-c", "-e", "-x", "-y", "-F", "-l", "-p") else 1
                        continue
                    reste.append(w)
                    k += 1
                if reste:
                    sortie.extend(commandes_et_entrees(" ".join(reste), prof + 1, suite))
        elif nom == "find":
            # {} vaut chaque fichier trouvé : on le remplace par le nom cherché
            # (find . -name .env -exec cat {} \; affiche le .env).
            cherche = ""
            for k in range(1, len(mots_cmd) - 1):
                if mots_cmd[k] in ("-name", "-iname", "-path", "-ipath"):
                    cherche = mots_cmd[k + 1]
            k = 1
            while k < len(mots_cmd):
                if mots_cmd[k] in ("-exec", "-execdir", "-ok", "-okdir"):
                    fin = k + 1
                    while fin < len(mots_cmd) and mots_cmd[fin] not in ("+", ";"):
                        fin += 1
                    code = " ".join(shlex.quote(cherche if w == "{}" else w)
                                    for w in mots_cmd[k + 1:fin] if w != "{}" or cherche)
                    sortie.extend(commandes_et_entrees(code, prof + 1, suite))
                    k = fin
                k += 1
        sortie.append((mots_cmd, ecrit, entrees, sep) if suite else (mots_cmd, ecrit, entrees))
    # $( ) et `…` : bash les exécute, on les relit.
    transmis = caches + [h for h in heritage or [] if not h[3]]
    for corps in subs:
        sortie.extend(commandes_et_entrees(corps, prof + 1, suite, transmis))
    return sortie

LANCEURS_DE_PROJET = {"uv", "poetry", "pipenv", "pdm", "rye", "hatch"}


def sans_enveloppe(mots):
    """Retire VAR=x, sudo, env, nohup, screen, uv run, if, !… en tête : le vrai
    programme suit."""
    i = 0
    while i < len(mots):
        m = mots[i]
        nom = os.path.basename(m.lstrip("\\"))
        if re.fullmatch(r"[A-Za-z_]\w*=.*", m) or m in MOTS_CLES:
            i += 1
        elif nom in LANCEURS_DE_PROJET and i + 1 < len(mots) and mots[i + 1] == "run":
            i += 2                                  # uv run …, poetry run …
            while i < len(mots) and mots[i].startswith("-"):
                i += 2 if mots[i] in ("--with", "--python", "-p", "--env-file", "--project", "--directory") else 1
        elif nom in ENVELOPPES:
            i += 1
            avec_valeur = OPTIONS_ENVELOPPES.get(nom, "")
            while i < len(mots) and (mots[i].startswith("-") or re.fullmatch(r"[\d.]+[smhd]?", mots[i])
                                     or re.fullmatch(r"[A-Za-z_]\w*=.*", mots[i])):
                o = mots[i]
                if nom == "env" and (o.startswith("-S") or o.startswith("--split-string")):
                    # env -S 'cat .env' : la chaîne est découpée en commande.
                    valeur = o.split("=", 1)[1] if "=" in o else (o[2:] if o.startswith("-S") and len(o) > 2
                                                                   else (mots[i + 1] if i + 1 < len(mots) else ""))
                    suite = mots[i + 1:] if (len(o) > 2 and not o.startswith("--")) or "=" in o else mots[i + 2:]
                    return sans_enveloppe(shlex.split(valeur) + suite)
                if o.startswith("-") and not o.startswith("--") and len(o) >= 2 and o[-1] in avec_valeur:
                    i += 1                          # sudo -u bob, screen -dmS nom : la valeur suit
                i += 1
        else:
            break
    return mots[i:]

# --- ssh : la commande envoyée au serveur ----------------------------------

OPTIONS_SSH_AVEC_VALEUR = set("BbcDEeFIiJLlmOoPpQRSWw")


def options_ssh(mots, i):
    """Saute les options de ssh à partir de mots[i] (-vvv, -tt, -i k, -ik, -p22,
    -oX=Y). Rend (indice du premier mot qui n'est pas une option, « -- » vu)."""
    while i < len(mots):
        m = mots[i]
        if m == "--":
            return i + 1, True
        if not m.startswith("-") or m == "-":
            return i, False
        for k, c in enumerate(m[1:], 1):
            if c in OPTIONS_SSH_AVEC_VALEUR:
                if k == len(m) - 1:
                    i += 1                          # la valeur est le mot suivant
                break                               # sinon elle est collée : -p22
        i += 1
    return i, False


def commande_distante(mots):
    """Le texte que ssh envoie au serveur, ou None pour une session interactive.
    Seules les options de ssh sont retirées : celles d'avant l'hôte, et celles
    collées juste après (ssh serveur -p 22 …), que ssh relit aussi : le reste
    de la ligne est la commande distante, options comprises."""
    i, fini = options_ssh(mots, 1)
    if i >= len(mots):
        return None                                 # pas d'hôte
    i += 1                                          # l'hôte
    if not fini:
        i, _ = options_ssh(mots, i)
    reste = mots[i:]
    return " ".join(reste) if reste else None


# --- Secrets : lecture d'un fichier de secrets, git add qui l'emporterait ------
# Jusqu'à la 0.3.4, rien n'arrêtait « cat .env », « grep KEY .env » ni
# ssh serveur "cat /srv/app/.env" : le contenu arrivait en clair dans la
# conversation. Les formes qui n'affichent que des noms, des comptes ou un
# réglage non secret restent permises.

def _detection():
    import importlib.util
    chemin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "detection-secrets.py")
    spec = importlib.util.spec_from_file_location("detection_secrets", chemin)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


LECTEURS = {"cat", "less", "more", "head", "tail", "bat", "nl", "tac", "od", "xxd", "hexdump",
            "strings", "base64", "zcat", "zless", "zmore", "diff", "tr", "column", "paste", "jq",
            "yq", "sort", "uniq", "fold", "rev", "pr", "expand", "awk", "gawk", "sed", "cut",
            "grep", "egrep", "fgrep", "zgrep", "rg", "ag", "done", "vim", "vi", "view", "nano",
            "sdiff", "comm", "tee"}
CHERCHEURS = {"grep", "egrep", "fgrep", "zgrep", "rg", "ag"}
# D'autres programmes qui affichent ou envoient un fichier nommé en argument, y
# compris en valeur d'option (dd if=f, openssl -in f, curl -d @f, curl file://f).
# La liste ne sera jamais complète : elle couvre les formes courantes, et un
# programme qui lit un fichier sans le nommer (un script, dotenv) passe.
LECTEURS_EN_PLUS = {"dd", "tar", "bsdtar", "gtar", "zip", "gzip", "gunzip", "bzip2", "xz", "zstd", "lz4",
                    "compress", "curl", "wget", "iconv", "look", "openssl", "sqlite3", "base32", "basenc",
                    "uuencode", "gpg", "age", "split", "csplit", "cmp", "fmt", "vis", "ex", "ed", "nvim",
                    "emacs", "micro", "pico", "textutil", "nc", "ncat", "netcat", "socat", "mail", "mailx",
                    "sendmail", "http", "xh", "hexyl", "view", "unexpand", "join", "nl"}
# Interprètes : le code qu'ils reçoivent (-c, -e, un document <<EOF) est lu,
# et un nom de fichier de secrets écrit dans une chaîne compte comme une lecture.
INTERPRETES_CODE = re.compile(r"(python[\d.]*|pypy[\d.]*|perl[\d.]*|ruby|irb|node|nodejs|deno|bun|php[\d.]*|"
                              r"lua[\d.]*|luajit|Rscript|osascript|tclsh|julia)$")
# Options suivies d'une valeur, par commande (la valeur n'est pas un fichier lu).
A_VALEUR = {"grep": "efmABCdD", "egrep": "efmABCdD", "fgrep": "efmABCdD", "zgrep": "efmABCdD",
            "rg": "efmABCgtT", "ag": "fmABCG", "sed": "ef", "awk": "Ffv", "gawk": "Ffv",
            "cut": "dfcb", "head": "nc", "tail": "nc", "sort": "oktST", "column": "sct",
            "jq": "", "yq": "", "diff": "", "od": "AjNtw", "xxd": "cglos"}
# Commandes dont le premier argument est un programme ou un motif, pas un fichier.
PROGRAMME_D_ABORD = CHERCHEURS | {"sed", "awk", "gawk", "jq", "yq", "tr"}
# ntfy, topic, webhook, rpc, dsn : un sujet de notification se lit comme un mot
# de passe (quiconque le connaît lit et envoie les alertes), une URL de RPC ou
# un DSN portent souvent leur clé.
# Relecture de la 0.3.5 : url, api, database, session… manquaient (DATABASE_URL,
# ALCHEMY_API, ETH_WSS_URL passaient pour des réglages).
NOM_SECRET = re.compile(r"key|secret|token|pass|pwd|cred|auth|mnemonic|seed|priv|wallet|signer"
                        r"|ntfy|topic|webhook|rpc|dsn|url|uri|api|database|(^|_)db(_|$)|conn|wss|blind|salt"
                        r"|cookie|session|jwt|bearer|account|keypair|(^|_)[ps]k(_|$)", re.I)
# Valeur d'un réglage qui peut s'afficher : booléen, nombre, mot court.
INOFFENSIF = re.compile(r"(?i)true|false|yes|no|on|off|none|null|-?\d{1,12}(\.\d+)?|[a-z][a-z_-]{0,11}")
REGLAGE = re.compile(r"\^(?:\(([A-Za-z_][A-Za-z0-9_|]*)\)|([A-Za-z_][A-Za-z0-9_]*))=(\.\*)?\$?")
CONTEXTE_GREP = set("ABCvz")
CONTEXTE_GREP_LONG = ("--context", "--after-context", "--before-context", "--invert-match", "--null-data",
                      "--passthru", "--file")


LONGUES_A_VALEUR = {"--exclude", "--include", "--exclude-dir", "--exclude-from", "--label", "--max-count",
                    "--after-context", "--before-context", "--glob", "--type", "--type-not", "--ignore-file"}


def lire_arguments(nom, args, motifs=None):
    """(fichiers lus, programme ou motif, options vues). Chaque motif donné
    (-e répétés compris) est ajouté à « motifs » si la liste est fournie."""
    valeurs = A_VALEUR.get(nom, "")
    fichiers, programme, options, i, fini = [], None, [], 0, False
    donne_par_option = False
    motifs = motifs if motifs is not None else []
    while i < len(args):
        a = args[i]
        if not fini and a == "--":
            fini = True
        elif not fini and a in LONGUES_A_VALEUR and "=" not in a and i + 1 < len(args):
            options.append(a + "=" + args[i + 1])
            i += 1                                  # grep --exclude '.env*' : un motif, pas un fichier
        elif nom in ("sed", "gsed") and a == "-i" and i + 1 < len(args) and args[i + 1] == "":
            options.append(a)
            i += 1                                  # sed -i '' (macOS) : '' est le suffixe
        elif not fini and a.startswith("-") and len(a) > 1:
            options.append(a)
            if a.startswith("--"):
                if a in ("--regexp", "--file", "--expression") and i + 1 < len(args):
                    programme, donne_par_option = args[i + 1], True
                    motifs.append(programme)
                    i += 1
                elif a.startswith(("--regexp=", "--expression=")):
                    programme, donne_par_option = a.split("=", 1)[1], True
                    motifs.append(programme)
            else:
                for k, c in enumerate(a[1:], 1):
                    if c in valeurs:
                        valeur = a[k + 1:] or (args[i + 1] if i + 1 < len(args) else "")
                        if not a[k + 1:]:
                            i += 1
                        options.append(f"-{c}={valeur}")
                        if c in "ef" and nom in PROGRAMME_D_ABORD:
                            programme, donne_par_option = valeur, True
                            motifs.append(valeur)
                        break
        elif nom in PROGRAMME_D_ABORD and programme is None and not donne_par_option:
            programme = a
            motifs.append(a)
        elif nom == "tr":
            pass                                    # tr n'a que des ensembles de caractères
        else:
            fichiers.append(a)
        i += 1
    return fichiers, programme, options


def lecture_masquee(nom, programme, options, motifs=None):
    """La commande n'affiche que des noms, des comptes, ou un réglage non secret."""
    courtes = "".join(o[1:] for o in options if not o.startswith("--") and "=" not in o)
    lettres = courtes + "".join(o[1] for o in options if re.fullmatch(r"-[A-Za-z]=.*", o))
    motifs = motifs if motifs else [programme or ""]
    if nom in CHERCHEURS:
        if set(courtes) & set("cqlL") or any(o in ("--count", "--quiet", "--silent", "--files-with-matches",
                                                     "--files-without-match") for o in options):
            return True
        # grep '^DRY_RUN=' .env : un réglage nommé, qui n'a rien d'un secret.
        # Pas avec -A/-B/-C (lignes voisines), -v (tout le reste), -z, -f
        # fichier de motifs ; et CHAQUE motif doit être un réglage.
        if set(lettres) & CONTEXTE_GREP or "f" in lettres or any(o.split("=", 1)[0] in CONTEXTE_GREP_LONG for o in options):
            return False
        if "o" in courtes and all(re.fullmatch(r"\^(\[\^=\]|\[[A-Za-z0-9_-]+\]|\\w)[+*]=?", m)
                                  or not re.search(r"[.\[\]*+?{}\\]", m) for m in motifs):
            return True                             # grep -oE '^[A-Z_]+=', grep -o '"(token|secret)"' : des mots
        for m in motifs:
            r = REGLAGE.fullmatch(m)
            if not r or any(NOM_SECRET.search(n) for n in (r.group(1) or r.group(2)).split("|")):
                return False
        return "reglage"                            # permis si la VALEUR lue l'est (reglages_inoffensifs)
    if nom == "cut":
        return "-d==" in options and "-f=1" in options and "--complement" not in options
    if nom == "sed":
        return bool(re.fullmatch(r"s(.)=\.\*\1\1[gp]*", (programme or "").strip()))
    if nom in ("jq", "yq"):
        # ~/.claude.json : seulement les noms (| keys), un compte, un type, ou
        # les compteurs d'usage, qui ne portent aucun jeton.
        f = (programme or "").strip()
        if re.search(r"[,;$]|debug|stderr|input", f):
            return False                            # « , » sort deux valeurs ; debug écrit sur stderr
        fin = re.split(r"\|", f)[-1].strip().rstrip(")?").strip()
        return fin in ("keys", "keys_unsorted", "length", "type") \
            or bool(re.fullmatch(r"\.(pluginUsage|skillUsage)\b[\w.\[\]\"| -]*", f))
    if nom in ("awk", "gawk"):
        return "-F==" in options and re.fullmatch(r"\{\s*print \$1\s*\}", (programme or "").strip()) is not None
    return False


JOKER = re.compile(r"[*?\[{]")
# Filtres qui laissent passer ce qu'ils lisent (cat .env | sort affiche tout).
FILTRES = {"grep", "egrep", "fgrep", "sed", "sort", "uniq", "head", "tail", "tr", "awk", "gawk", "cut",
           "column", "rev", "fold", "expand"}


def accolades(motif):
    """.env{,.local} → [.env, .env.local] (un niveau, comme bash)."""
    m = re.search(r"\{([^{}]*,[^{}]*)\}", motif)
    if not m:
        return [motif]
    return [r for x in m.group(1).split(",") for r in accolades(motif[:m.start()] + x + motif[m.end():])]


def reglages_inoffensifs(motifs, fichiers, dossier):
    """grep '^DRY_RUN=' .env : permis si chaque valeur que la commande
    afficherait est un booléen, un nombre ou un mot court. Jusqu'à la
    relecture de la 0.3.5, seul le nom était jugé : grep '^DATABASE_URL=' .env
    affichait le mot de passe de la base."""
    noms = set()
    for m in motifs:
        r = REGLAGE.fullmatch(m)
        if not r:
            return False
        noms.update(n.lower() for n in (r.group(1) or r.group(2)).split("|"))
    chemins = []
    for f in fichiers:
        c = os.path.expanduser(f)
        c = c if os.path.isabs(c) or not dossier else os.path.join(dossier, c)
        try:
            chemins += glob.glob(c) if JOKER.search(f) else [c]
        except (re.error, OSError, ValueError):
            return False
    for c in chemins:
        try:
            with open(c, encoding="utf-8", errors="replace") as h:
                lignes = h.read(2_000_000).splitlines()
        except FileNotFoundError:
            continue                                # rien à afficher
        except OSError:
            return False
        for ligne in lignes:
            m = re.match(r"\s*(?:export\s+)?([A-Za-z_]\w*)\s*=\s*(.*)$", ligne)
            if m and m.group(1).lower() in noms:
                v = re.sub(r"\s+#.*$", "", m.group(2)).strip().strip("'\"")
                if v and not INOFFENSIF.fullmatch(v):
                    return False
    return True


def chaines_du_code(code):
    """Les chaînes entre guillemets d'un code (python -c, node -e, awk…) : un
    nom de fichier y est toujours écrit ainsi."""
    return [m.group(2) for m in re.finditer(r"""(["'])((?:(?!\1).)+)\1""", code or "")]


def chemins_du_mot(w):
    """Les chemins qu'un argument peut désigner : lui-même, la valeur d'une
    option (if=f, --file=f), @f (curl -d @f), file:///chemin."""
    res = [w]
    if "=" in w:
        res.append(w.split("=", 1)[1])
    if w.startswith("@"):
        res.append(w[1:])
    m = re.match(r"(?i)file://(?:localhost)?(/.*)", w)
    if m:
        res.append(unquote(m.group(1)))
    return [x for x in res if x]


def noms_passes_a_xargs(cmds, k, dossier, distant, detection):
    """« … | xargs cat » : xargs donne à cat les noms qu'écrit la commande
    d'avant. Les fichiers de secrets qu'elle peut écrire, ou [] :
    find sans -name → ceux du dossier parcouru ; find -name '.env*', echo .env,
    grep -rl → ceux qu'ils désignent. Jusqu'à la relecture de la 0.3.5, xargs
    était une simple enveloppe et cat arrivait sans argument."""
    if k == 0 or cmds[k - 1][3] not in ("|", "|&"):
        return []
    mots = cmds[k - 1][0]
    nom = os.path.basename(mots[0].lstrip("\\"))
    if nom in ("find", "fd", "fdfind"):
        motifs = [mots[i + 1] for i in range(len(mots) - 1)
                  if mots[i] in ("-name", "-iname", "-path", "-ipath", "-g", "--glob")]
        if motifs:
            return [m for m in motifs if designe_un_secret(m.split("/")[-1], dossier, True, detection)]
        racines = [a for a in mots[1:] if not a.startswith("-") and a not in ("!", "(", ")")][:1] or ["."]
        return recherche_recursive("grep", racines, ["-r"], dossier, detection)
    if nom == "ls":
        options = "".join(a[1:] for a in mots[1:] if a.startswith("-") and not a.startswith("--"))
        tous = bool(set(options) & set("aA"))
        res = []
        for d in [a for a in mots[1:] if not a.startswith("-")] or ["."]:
            base = os.path.join(dossier or "", os.path.expanduser(d))
            if not os.path.isdir(base):
                if designe_un_secret(d, dossier, distant, detection):
                    res.append(base)                # ls .env | xargs cat
                continue
            try:
                noms = os.listdir(base)
            except OSError:
                noms = []
            res += [os.path.join(base, x) for x in noms if (tous or not x.startswith("."))
                    and detection.est_fichier_de_secrets(os.path.join(base, x))]
        return res
    if nom in CHERCHEURS:
        fichiers, _, options = lire_arguments(nom, mots[1:])
        courtes = "".join(o[1:] for o in options if not o.startswith("--") and "=" not in o)
        if set(courtes) & set("lL") or "--files-with-matches" in options:
            directs = [f for f in fichiers if designe_un_secret(f, dossier, distant, detection)]
            return directs or ([] if distant else recherche_recursive(nom, fichiers, options, dossier, detection))
    return [x for a in mots[1:] for x in chemins_du_mot(a) if designe_un_secret(x, dossier, distant, detection)]


def designe_un_secret(arg, dossier, distant, detection):
    """L'argument désigne-t-il un fichier de secrets ? Un joker est développé
    comme bash dans le dossier de la commande ; à distance, où rien ne se
    développe ici, son dernier morceau est jugé (.env*). Un lien vers un
    fichier de secrets en est un (detection-secrets suit les liens)."""
    if detection.est_fichier_de_secrets(arg):
        return True
    if not distant and dossier and not JOKER.search(arg) and not os.path.isabs(os.path.expanduser(arg)):
        if detection.est_fichier_de_secrets(os.path.join(dossier, os.path.expanduser(arg))):
            return True
    if not JOKER.search(arg):
        return False
    for motif in accolades(arg):
        if detection.est_fichier_de_secrets(motif):
            return True
        if not JOKER.search(motif):
            continue
        chemin = os.path.expanduser(motif)
        if not distant and (dossier or os.path.isabs(chemin)):
            try:
                trouves = glob.glob(chemin if os.path.isabs(chemin) else os.path.join(dossier, chemin))
            except (re.error, OSError, ValueError):
                trouves = []                        # [z-a] : un motif que bash ne développe pas non plus
            if any(detection.est_fichier_de_secrets(t) for t in trouves):
                return True
            if trouves:
                continue
        dernier = motif.rstrip("/").split("/")[-1].lower()
        if not re.fullmatch(r"[\w.*?\[\]{}~,-]+", dernier):
            continue                                # un script sed, un motif : pas un nom de fichier
        if dernier.startswith(".en") or dernier == "environ" or re.search(
                r"\.env\b|\.(pem|key)$|wallet|keystore|mnemonic|id_(rsa|ed25519|ecdsa|dsa)", dernier):
            return True
    return False


NON_SECRET_VAR = re.compile(r"(?i)_(sock|path|file|dir|home|id|url_path)$|^(pwd|oldpwd|ssh_agent_pid)$")
VARIABLE = re.compile(r"\$(?:\{(#?)([A-Za-z_]\w*)([^}]*)\}|([A-Za-z_]\w*))")


def variable_secrete(mot):
    """« $PRIVATE_KEY », « ${API_KEY} », « ${API_KEY:-x} » affichent la valeur ;
    « ${API_KEY:+défini} » et « ${#API_KEY} », non."""
    avant = None
    while avant != mot:                             # $( [ -n "$API_KEY" ] && echo oui ) : un test, pas un affichage
        avant, mot = mot, re.sub(r"\$\([^()]*\)|`[^`]*`", "", mot)
    for m in VARIABLE.finditer(mot):
        if m.group(2) and (m.group(1) or m.group(3).startswith((":+", "+"))):
            continue
        nom = m.group(2) or m.group(4)
        if NOM_SECRET.search(nom) and not NON_SECRET_VAR.search(nom):
            return True
    return False


def copie_d_un_secret(nom, args, dossier, distant, detection):
    """cp .env /tmp/e.txt, scp serveur:/srv/app/.env /tmp/x : un secret copié
    sous un nom neutre se lirait ensuite sans garde.
    Une copie sous un nom de secret (.env.bak, backend/.env, sauvegarde/) reste
    permise."""
    a_valeur = {"scp": "PioFSlcJ", "rsync": "e", "install": "mogt"}.get(nom, "")
    pos, sauter = [], False
    for a in args:
        if sauter:
            sauter = False
        elif a.startswith("-") and len(a) > 1:
            sauter = not a.startswith("--") and a[-1] in a_valeur
        else:
            pos.append(a)
    if len(pos) < 2:
        return False
    distante = re.compile(r"^[\w.@-]+:(?!//)")
    dest = pos[-1]
    dest = dest.split(":", 1)[1] if nom in ("scp", "rsync") and distante.match(dest) else dest
    for src in pos[:-1]:
        loin = nom in ("scp", "rsync") and bool(distante.match(src))
        chemin = src.split(":", 1)[1] if loin else src
        if not designe_un_secret(chemin, dossier, distant or loin, detection):
            continue
        cible = dest
        if cible.endswith("/") or (dossier and os.path.isdir(os.path.join(dossier, os.path.expanduser(cible)))):
            cible = os.path.join(cible, os.path.basename(chemin.rstrip("/")))
        if not detection.est_fichier_de_secrets(cible):
            return True
    return False


class TropGrand(Exception):
    """Le dossier est trop grand pour être parcouru à temps : on ne sait pas."""


LIMITE_PARCOURS = 20000


def recherche_recursive(nom, fichiers, options, dossier, detection):
    """grep -r (et rg --hidden) sur un dossier qui contient un fichier de
    secrets affiche ses lignes : grep -r lit les fichiers cachés et ignore
    .gitignore. On parcourt le dossier comme lui, --exclude compris."""
    import fnmatch
    courtes = "".join(o[1:] for o in options if not o.startswith("--") and "=" not in o)
    if nom in ("grep", "egrep", "fgrep", "zgrep"):
        recursif = bool(set(courtes) & set("rR")) or any(
            o.startswith(("--recursive", "--dereference-recursive", "-d=recurse", "--directories=recurse")) for o in options)
        caches = True
    elif nom in ("rg", "ag"):
        recursif = True
        caches = "." in courtes or "--hidden" in options or courtes.count("u") >= 2 or "--unrestricted" in options
    else:
        return []
    if not recursif:
        return []
    exclus = [o.split("=", 1)[1].strip("'\"") for o in options if o.startswith(("--exclude=", "--glob=!", "-g=!"))]
    exclus = [e[1:] if e.startswith("!") else e for e in exclus]
    exclus_dir = [o.split("=", 1)[1].strip("'\"") for o in options if o.startswith("--exclude-dir=")]
    # --include=*.md (grep), -g '*.md' (rg) : seuls ces fichiers sont lus.
    inclus = [o.split("=", 1)[1].strip("'\"") for o in options
              if o.startswith(("--include=", "--glob=", "-g=")) and not o.split("=", 1)[1].startswith("!")]
    trouves, vus = [], 0
    for d in (fichiers or ["."]):
        racine = os.path.join(dossier or "", os.path.expanduser(d))
        if not os.path.isdir(racine):
            continue
        for base, sous, noms in os.walk(racine):
            sous[:] = [x for x in sous if x not in (".git", "node_modules", "__pycache__", "site-packages")
                       and not x.startswith(("venv", ".venv")) and (caches or not x.startswith("."))
                       and not any(fnmatch.fnmatch(x, e) for e in exclus_dir)]
            for f in noms:
                vus += 1
                if vus > LIMITE_PARCOURS:
                    # S'arrêter en rendant la liste partielle laissait passer
                    # « grep -r KEY » lancé depuis un dossier immense : on ne
                    # sait pas, donc on le dit. Même si un fichier de secrets a
                    # déjà été vu : un autre peut suivre (relecture de la 0.3.5).
                    raise TropGrand()
                if (not caches and f.startswith(".")) or any(fnmatch.fnmatch(f, e) for e in exclus):
                    continue
                if inclus and not any(fnmatch.fnmatch(f, e) for e in inclus):
                    continue
                if detection.est_fichier_de_secrets(os.path.join(base, f)):
                    trouves.append(os.path.join(base, f))
    return trouves


def ligne_secrete(ligne, fichier, detection):
    """Une ligne qui porte une valeur : dans un .env, toute affectation ; ailleurs
    (~/.claude.json…), une valeur que detection-secrets reconnaît."""
    b = os.path.basename(fichier).lower()
    if ".env" in b or b.startswith(("env-", "env.")) or b.endswith("env"):
        return bool(re.match(r"\s*(export\s+)?[A-Za-z_]\w*\s*=\s*\S", ligne))
    return bool(detection.valeur_secrete(ligne))


def motif_trouve(nom, fichiers, motifs, options, detection):
    """Le motif de grep trouve-t-il une ligne qui porte un secret dans ces
    fichiers ? Lu ici, rien n'est affiché : « grep -rn TODO . » près d'un .env
    qui ne contient pas TODO ne montre rien du .env. Motif illisible : oui."""
    courtes = "".join(o[1:] for o in options if not o.startswith("--") and "=" not in o)
    if "v" in courtes or "--invert-match" in options:
        return True
    # -A / -B / -C : les lignes voisines d'une ligne trouvée s'affichent aussi,
    # qu'elles portent le motif ou non (un « ^# » qui ne trouve que des
    # commentaires montrerait les valeurs d'à côté).
    if set(courtes) & set("ABC") or any(re.fullmatch(r"-[ABC]=.*", o) for o in options) \
            or any(o.split("=", 1)[0] in ("--context", "--after-context", "--before-context") for o in options):
        return True
    # -f : les motifs sont dans un fichier, qu'on ne lit pas ici.
    if any(o.startswith(("-f=", "--file")) for o in options):
        return True
    if "F" in courtes or nom == "fgrep" or "--fixed-strings" in options:
        rx = [re.escape(m) for m in motifs]
    elif "E" in courtes or "P" in courtes or nom in ("egrep", "rg", "ag") or "--extended-regexp" in options:
        rx = list(motifs)
    else:
        rx = [bre_en_python(m) for m in motifs]
    if not ("F" in courtes or nom == "fgrep" or "--fixed-strings" in options):
        rx = [classes_posix(r) for r in rx]
        if None in rx:
            return True                             # une classe inconnue : on ne sait pas ce qu'elle trouve
    drapeaux = re.I if ("i" in courtes or "--ignore-case" in options) else 0
    if "w" in courtes:
        rx = [rf"\b(?:{r})\b" for r in rx]
    try:
        compiles = [re.compile(r, drapeaux) for r in rx]
    except re.error:
        return True
    for f in fichiers:
        try:
            with open(f, encoding="utf-8", errors="replace") as h:
                if any(ligne_secrete(l, f, detection) for l in h.read(2_000_000).splitlines()
                       if any(c.search(l) for c in compiles)):
                    return True
        except OSError:
            continue
    return False


CLASSES_POSIX = {"alpha": "a-zA-Z", "digit": "0-9", "alnum": "a-zA-Z0-9", "upper": "A-Z", "lower": "a-z",
                 "space": r"\s", "blank": r" \t", "punct": r"!-/:-@\[-`{-~", "print": r"\x20-\x7e",
                 "graph": r"\x21-\x7e", "xdigit": "0-9A-Fa-f", "cntrl": r"\x00-\x1f\x7f", "word": r"\w"}


def classes_posix(rx):
    """[[:print:]], \\< \\>, [[:<:]] de grep → Python, qui ne les connaît pas :
    jusqu'à la relecture de la 0.3.5, grep -r '[[:print:]]' trouvait tout et
    le hook, rien. None si une classe est inconnue."""
    rx = rx.replace("[[:<:]]", r"\b").replace("[[:>:]]", r"\b")
    inconnues = []

    def classe(m):
        v = CLASSES_POSIX.get(m.group(1))
        if v is None:
            inconnues.append(m.group(1))
        return v or ""
    rx = re.sub(r"\[:(\w+):\]", classe, rx)
    rx = rx.replace(r"\<", r"\b").replace(r"\>", r"\b")
    return None if inconnues else rx


def bre_en_python(motif):
    """Motif grep de base (BRE) → Python : \\( \\) \\| \\{ \\} \\+ \\? sont des
    opérateurs, ( ) | { } + ? seuls sont littéraux."""
    sortie, i = [], 0
    while i < len(motif):
        c = motif[i]
        if c == "\\" and i + 1 < len(motif):
            d = motif[i + 1]
            sortie.append(d if d in "(){}+?|" else c + d)
            i += 2
            continue
        sortie.append("\\" + c if c in "(){}+?|" else c)
        i += 1
    return "".join(sortie)


def sortie_masquee(cmds, k, texte, sources=None, dossier=None):
    """La sortie du lecteur cmds[k] part-elle dans un tube qui ne garde que
    les noms ou un compte (cat .env | cut -d= -f1, … | grep -c, … | wc -l) ?
    « export $(grep -v '^#' .env | xargs) » aussi : la sortie devient des
    variables, rien ne s'affiche."""
    j = k
    while cmds[j][3] == "|":
        if j + 1 >= len(cmds):
            break
        j += 1
        mots = cmds[j][0]
        nom = os.path.basename(mots[0].lstrip("\\"))
        if nom == "wc":
            return True
        if nom == "xargs":
            return len(mots) == 1 and bool(re.search(r"\bexport\s+[\"']?\$\([^()]*\|\s*xargs\s*\)", texte))
        if nom in LECTEURS:
            motifs = []
            _, programme, options = lire_arguments(nom, mots[1:], motifs)
            masque = lecture_masquee(nom, programme, options, motifs)
            if masque == "reglage":
                return bool(sources) and reglages_inoffensifs(motifs, sources, dossier)
            if masque:
                return True
        if nom not in FILTRES:
            return False
    return False


GIT_NOMS_SEULS = {"--stat", "--name-only", "--name-status", "--shortstat", "--numstat", "--summary",
                  "-s", "--no-patch", "--dirstat", "--quiet"}
GIT_PATCH = {"-p", "-u", "--patch", "--full-diff", "-P"}


def git_affiche_un_secret(sous, args, dossier, detection):
    """git show HEAD:.env, git log -p -- .env, git diff --no-index a .env,
    git show <sha> d'un commit qui touche .env… On demande à git
    les NOMS des fichiers concernés (--name-only), jamais leur contenu."""
    import subprocess
    if sous not in ("show", "log", "diff", "stash", "cat-file", "grep", "whatchanged"):
        return False
    if sous == "stash":
        if not args or args[0] != "show":
            return False
        args, sous = args[1:], "stash show"
    options = [a for a in args if a.startswith("-")]
    if sous == "grep":
        if set("".join(o[1:] for o in options if not o.startswith("--"))) & set("clLq") or \
                any(o in ("--count", "--files-with-matches", "--name-only", "--quiet") for o in options):
            return False
    elif GIT_NOMS_SEULS & set(options) and not GIT_PATCH & set(options):
        return False
    if sous in ("log", "whatchanged", "stash show") and not (GIT_PATCH & set(options)
                                                              or any(re.fullmatch(r"-[A-Za-z]*p[A-Za-z]*", o) for o in options)):
        return False                                # git log sans -p : des titres, pas de contenu
    apres = args[args.index("--") + 1:] if "--" in args else []
    avant = args[:args.index("--")] if "--" in args else args
    if sous == "grep" and not any(o in ("-e", "-f", "--regexp") or o.startswith(("-e", "-f")) for o in options):
        premier = next((k for k, a in enumerate(avant) if not a.startswith("-")), None)
        if premier is not None:
            avant = avant[:premier] + avant[premier + 1:]   # git grep MOTIF [rev] [-- chemins]
    chemins = apres + [a.split(":", 1)[1] for a in avant if ":" in a and not a.startswith("-")]
    chemins += [a for a in avant if not a.startswith("-") and ":" not in a
                and (sous in ("diff", "grep") or (dossier and os.path.exists(os.path.join(dossier, a))))]
    if any(designe_un_secret(c, dossier, False, detection) for c in chemins):
        return True
    if not dossier or not os.path.isdir(dossier) or sous == "cat-file" or apres \
            or any(":" in a and not a.startswith("-") for a in avant):
        return False                                # rev:chemin est un fichier, déjà jugé par son nom
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    revs = [a for a in avant if not a.startswith("-") and not a.startswith(("--output", "--ext-diff"))]
    if sous == "grep":
        cmd = ["ls-files", "-z"]
    elif sous == "diff" and "--no-index" in options:
        return False
    else:
        base = {"show": ["show", "--format="], "log": ["log", "--format="], "whatchanged": ["log", "--format="],
                "diff": ["diff"], "stash show": ["stash", "show"]}[sous]
        garde = [o for o in options if o not in GIT_PATCH and not re.fullmatch(r"-[A-Za-z]*p[A-Za-z]*", o)
                 and not o.startswith(("--output", "--ext-diff", "--textconv", "--exec"))]
        cmd = base + ["--name-only", "-z", "--no-ext-diff", "--no-textconv"] + garde + revs
        if sous in ("log", "whatchanged"):
            cmd.insert(1, "-n")
            cmd.insert(2, "5000")
    try:
        r = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", dossier] + cmd,
                           capture_output=True, env=env, timeout=10, stdin=subprocess.DEVNULL)
    except OSError:
        return False                                # pas de git : rien à afficher
    except subprocess.TimeoutExpired:
        return True                                 # on ne sait pas ce que la commande montrerait
    noms = r.stdout.decode("utf-8", "replace").replace("\n", "\0").split("\0")
    return any(detection.est_fichier_de_secrets(f) for f in noms if f)


def suivre_dossier(nom, mots, dossier, pile):
    """cd, pushd, popd : le dossier courant après la commande."""
    if nom == "popd":
        return pile.pop() if pile else None
    args = [a for a in mots[1:] if a not in ("-P", "-L", "-e", "-@", "--")]
    cible = os.path.expanduser(args[0]) if args else os.path.expanduser("~")
    if nom == "pushd":
        pile.append(dossier)
    if "$" in cible or "`" in cible or cible == "-":
        return None
    return cible if os.path.isabs(cible) else (os.path.join(dossier, cible) if dossier else None)


def verdict_secret(texte, detection=None, prof=0, depart=None, distant=False):
    detection = detection or _detection()
    cmds = commandes_et_entrees(texte, suite=True)
    dossier, pile, charge = depart, [], False
    for k, (mots, _, entrees, _) in enumerate(cmds):
        lus = [v for g, v in entrees if g == "fichier"]
        nom = os.path.basename(mots[0].lstrip("\\"))
        if nom in ("cd", "pushd", "popd"):
            dossier = suivre_dossier(nom, mots, dossier, pile)
            continue
        # Lectures indirectes : un .env chargé puis
        # l'environnement affiché, une variable secrète affichée, un secret
        # copié sous un nom neutre.
        if nom in ("source", ".") and len(mots) > 1 and designe_un_secret(mots[1], dossier, distant, detection):
            charge = True
            continue
        if nom in ("cp", "mv", "install", "ditto", "scp", "rsync", "ln") and \
                copie_d_un_secret(nom, mots[1:], dossier, distant, detection):
            return "SECRET"
        affiche = False
        if nom in ("echo", "printf"):
            affiche = any(variable_secrete(a) for a in mots[1:])
        elif nom == "printenv":
            noms = [a for a in mots[1:] if not a.startswith("-")]
            affiche = any(NOM_SECRET.search(x) and not NON_SECRET_VAR.search(x) for x in noms) or (charge and not noms)
        elif charge and ((nom in ("env", "set") and len(mots) == 1)
                         or (nom in ("export", "declare", "typeset", "readonly")
                             and (len(mots) == 1 or any(o in ("-p", "-x") for o in mots[1:])))):
            affiche = True                          # declare, export seuls : tout l'environnement
        if affiche:
            if sortie_masquee(cmds, k, texte):
                continue
            return "SECRET"
        if nom == "ssh":
            distante = commande_distante(mots)
            if distante and prof < PROFONDEUR and verdict_secret(distante, detection, prof + 1, None, True) == "SECRET":
                return "SECRET"
            continue
        if nom == "git" and not distant:
            d, i = depot_vise(mots, dossier)
            if i < len(mots) and git_affiche_un_secret(mots[i], mots[i + 1:], d or dossier, detection):
                return "SECRET"
            continue
        if nom == "ps":
            # ps e, ps eww, ps auxe, ps -E : l'environnement des processus.
            # -e seul (tous les processus, Linux) reste libre.
            args, sauter = mots[1:], False
            for a in args:
                if sauter:
                    sauter = False
                elif a == "-E" or (re.fullmatch(r"[A-Za-z]+", a) and "e" in a):
                    return "SECRET"
                elif re.fullmatch(r"-[A-Za-z]*[oOpuUGtCqg]", a):
                    sauter = True
            continue
        if nom == "systemctl" and "show" in mots and any("Environment" in a for a in mots):
            return "SECRET"
        code = INTERPRETES_CODE.match(nom) is not None
        # « … | xargs cat » : les noms viennent de la commande d'avant.
        venus = []
        if any(g == "xargs" for g, _ in entrees) and (nom in LECTEURS or nom in LECTEURS_EN_PLUS or code):
            venus = noms_passes_a_xargs(cmds, k, dossier, distant, detection)
        if code or nom in LECTEURS_EN_PLUS:
            # Interprètes (python -c, node -e, perl, un document <<EOF) et autres
            # lecteurs (dd if=f, curl -d @f, openssl -in f, tar, iconv…).
            candidats = [x for a in mots[1:] if not (code and a.startswith("-")) for x in chemins_du_mot(a)]
            if code:
                candidats += [x for a in mots[1:] for x in chaines_du_code(a)]
                candidats += [x for g, v in entrees if g in ("texte", "document") for x in chaines_du_code(v)]
            else:
                candidats += [x for a in mots[1:] if re.search(r"\s", a) for x in a.split()]
            if venus or any(designe_un_secret(x, dossier, distant, detection) for x in candidats + lus):
                if sortie_masquee(cmds, k, texte):
                    continue
                return "SECRET"
            continue
        if nom not in LECTEURS:
            continue
        motifs = []
        fichiers, programme, options = lire_arguments(nom, mots[1:], motifs)
        if nom == "tee":
            fichiers = []                           # tee écrit ses arguments ; seul « < f » est lu
        # awk 'BEGIN{getline l < ".env"}', sed 'r .env' : un fichier nommé dans le programme.
        if programme and nom in ("awk", "gawk"):
            fichiers = fichiers + chaines_du_code(programme)
        elif programme and nom in ("sed", "gsed"):
            fichiers = fichiers + re.findall(r"(?:^|[;{}\n/!$\d])\s*[rR]\s*([^\s;}]+)", programme)
        secrets = [f for f in fichiers + lus if designe_un_secret(f, dossier, distant, detection)]
        if venus:
            secrets += venus if nom not in CHERCHEURS else [v for v in venus if os.path.isfile(v)]
            if nom in CHERCHEURS and secrets and not motif_trouve(nom, secrets, motifs, options, detection):
                continue
        if not secrets:
            caches = [] if distant else recherche_recursive(nom, fichiers, options, dossier, detection)
            if not caches or not motif_trouve(nom, caches, motifs, options, detection):
                continue
            secrets = caches
        masque = lecture_masquee(nom, programme, options, motifs)
        if masque == "reglage":
            masque = reglages_inoffensifs(motifs, secrets, dossier)
        if masque or sortie_masquee(cmds, k, texte, secrets, dossier):
            continue
        return "SECRET"
    return "OK"


GIT_CONNUES = {"add", "commit", "push", "pull", "fetch", "status", "log", "diff", "show", "checkout", "switch",
               "branch", "merge", "rebase", "reset", "restore", "stash", "tag", "remote", "clone", "init",
               "rev-parse", "ls-files", "config", "grep", "blame", "cherry-pick", "revert", "mv", "rm",
               "describe", "archive", "worktree", "submodule", "clean", "bisect", "notes", "reflog", "shortlog",
               "apply", "am", "format-patch", "fsck", "gc", "cat-file", "ls-tree", "for-each-ref", "stage",
               "update-index", "whatchanged", "help", "version", "var", "cherry", "range-diff", "sparse-checkout"}


def sous_commande(mots, i, dossier):
    """(sous-commande, arguments) de « git … <sous-commande> », alias résolu :
    « git p » avec alias.p = push est un push, « git -c alias.x=push x »
    aussi. git config est lu, rien n'est exécuté ; un alias « !… » (commande
    shell) est jugé sur ses mots."""
    import subprocess
    if i >= len(mots):
        return "", []
    nom, reste = mots[i], mots[i + 1:]
    if nom in GIT_CONNUES or not re.fullmatch(r"[\w-]{1,40}", nom):
        return nom, reste
    # git -c alias.x=push x : l'alias est donné sur la ligne même.
    for k in range(1, i):
        if mots[k] == "-c" and k + 1 < i and mots[k + 1].lower().startswith(f"alias.{nom.lower()}="):
            valeur = mots[k + 1].split("=", 1)[1]
            try:
                mots_alias = shlex.split(valeur.lstrip("!"))
            except ValueError:
                mots_alias = valeur.lstrip("!").split()
            if valeur.startswith("!"):
                g = next((j + 1 for j, w in enumerate(mots_alias) if os.path.basename(w) == "git"), None)
                mots_alias = mots_alias[g:] if g is not None else mots_alias
            return (mots_alias[0], mots_alias[1:] + reste) if mots_alias else (nom, reste)
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    try:
        r = subprocess.run(["git", "-c", "core.fsmonitor=false"] + (["-C", dossier] if dossier and os.path.isdir(dossier) else [])
                           + ["config", "--get", f"alias.{nom}"], capture_output=True, env=env, timeout=5,
                           stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return nom, reste
    valeur = r.stdout.decode("utf-8", "replace").strip()
    if r.returncode != 0 or not valeur:
        return nom, reste
    try:
        mots_alias = shlex.split(valeur.lstrip("!"))
    except ValueError:
        mots_alias = valeur.lstrip("!").split()
    if valeur.startswith("!"):
        # alias shell : « !git push origin HEAD » ; on garde la 1re sous-commande git citée
        k = next((j + 1 for j, w in enumerate(mots_alias) if os.path.basename(w) == "git"), None)
        mots_alias = mots_alias[k:] if k is not None else mots_alias
    return (mots_alias[0], mots_alias[1:] + reste) if mots_alias else (nom, reste)


def dossier_de_git_dir(valeur, dossier):
    """--git-dir=x/.git → x ; --git-dir=x → x ."""
    chemin = os.path.join(dossier or "", os.path.expanduser(valeur))
    return os.path.dirname(chemin.rstrip("/")) if os.path.basename(chemin.rstrip("/")) == ".git" else chemin


def depot_vise(mots, dossier):
    """Le dossier où git travaille : -C (cumulés), --work-tree, sinon le dossier courant."""
    i = 1
    while i < len(mots) and mots[i].startswith("-"):
        o = mots[i]
        if o == "-C" and i + 1 < len(mots):
            dossier = os.path.join(dossier or "", os.path.expanduser(mots[i + 1])) if dossier or \
                os.path.isabs(os.path.expanduser(mots[i + 1])) else None
            i += 2
            continue
        if o.startswith("--work-tree="):
            dossier = os.path.join(dossier or "", os.path.expanduser(o.split("=", 1)[1]))
        elif o.startswith("--git-dir="):
            dossier = dossier_de_git_dir(o.split("=", 1)[1], dossier)
        elif o in ("--work-tree", "--git-dir", "-c", "--namespace", "--exec-path") and i + 1 < len(mots):
            if o == "--work-tree":
                dossier = os.path.join(dossier or "", os.path.expanduser(mots[i + 1]))
            elif o == "--git-dir":
                dossier = dossier_de_git_dir(mots[i + 1], dossier)
            i += 2
            continue
        i += 1
    return dossier, i


def ajouts_git(texte, depart):
    """[(dossier, arguments de git add)] pour chaque git add / git stage, en
    suivant les cd qui le précèdent sur la ligne (cd x && git add .)."""
    dossier, res, pile = depart, [], []
    for mots, _, _ in commandes_et_entrees(texte):
        nom = os.path.basename(mots[0].lstrip("\\"))
        if nom in ("cd", "pushd", "popd"):
            dossier = suivre_dossier(nom, mots, dossier, pile)
        elif nom == "git":
            d, i = depot_vise(mots, dossier)
            sous, args = sous_commande(mots, i, d or dossier or depart)
            if sous in ("add", "stage"):
                res.append((d, args))
            elif sous == "update-index" and "--add" in args:
                autres = [a for a in args if a != "--add"]
                res.append((d, autres + (["--all"] if "--stdin" in autres or "--index-info" in autres else [])))
    # « … | xargs git add » : xargs est une enveloppe, git add arrive sans chemin
    # visible ; il est jugé comme « git add -A ».
    if re.search(r"\bxargs\b[^|;&]*\bgit\b[^|;&]*\b(add|stage)\b", texte):
        res = [(d, a if any(not x.startswith("-") for x in a) else a + ["--all"]) for d, a in res]
    # git add $(…), git add "$f", git add `…` : le chemin n'est connu qu'à
    # l'exécution ; jugé comme « git add -A » (relecture de la 0.3.5).
    if re.search(r"\bgit\b[^|;&\n]*\b(add|stage|update-index)\b[^|;&\n]*[$`]", texte):
        res = [(d, [x for x in a if "$" not in x and "`" not in x] + ["--all"]) for d, a in res]
    return res


def depots_pousses(texte, depart):
    """Le dossier de chaque « git … push » de la ligne, en suivant -C,
    --work-tree et les cd qui le précèdent. Jusqu'à la 0.3.4, le contrôle avant
    push ne partait que sur le texte « git push » et vérifiait le dossier
    d'ouverture de la session : « git -C autre-depot push » n'était pas
    contrôlé, « cd x && git push » contrôlait le mauvais dossier."""
    dossier, res, pile = depart, [], []
    # GIT_DIR=x git push, GIT_WORK_TREE=x, env -C x git push : le dossier est
    # posé avant la commande.
    impose = None
    m = re.search(r"\bGIT_WORK_TREE=(\S+)", texte) or re.search(r"\benv\b[^;&|\n]*?\s(?:-C\s*|--chdir=)(\S+)", texte)
    if m:
        impose = os.path.join(depart or "", os.path.expanduser(m.group(1).strip("'\"")))
    elif re.search(r"\bGIT_DIR=(\S+)", texte):
        impose = dossier_de_git_dir(re.search(r"\bGIT_DIR=(\S+)", texte).group(1).strip("'\""), depart)
    for mots, _, _ in commandes_et_entrees(texte):
        nom = os.path.basename(mots[0].lstrip("\\"))
        if nom in ("cd", "pushd", "popd"):
            dossier = suivre_dossier(nom, mots, dossier, pile)
        elif nom == "git":
            d, i = depot_vise(mots, dossier)
            sous, args = sous_commande(mots, i, d or dossier or depart)
            if sous == "push":
                if impose and d == dossier:
                    d = impose
                # Un dossier qui n'existe pas encore (git clone x && cd x) ou une
                # variable : repli sur le dossier de départ, jamais un refus.
                if not d or not os.path.isdir(d):
                    d = depart
                res.append((d, references_poussees(args)))
    return [(d, r) for d, r in res if d]


def references_poussees(args):
    """Les branches que « git push [options] distant ref… » envoie : le côté
    source de chaque refspec ; aucune nommée → HEAD ; --all → toutes."""
    if any(a in ("--all", "--branches", "--mirror") for a in args):
        return ["--all"]
    positions, i = [], 0
    while i < len(args):
        a = args[i]
        if a in ("--repo", "-o", "--push-option", "--receive-pack", "--exec"):
            i += 2
            continue
        if not a.startswith("-"):
            positions.append(a)
        i += 1
    refs = []
    for r in positions[1:]:
        source = r.lstrip("+").split(":", 1)[0]
        if source and re.fullmatch(r"[\w./@{}^~-]+", source):
            refs.append(source)
    return refs or ["HEAD"]


def ajout_secret(texte, depart):
    """SECRET si un git add emporterait un fichier de secrets : on le demande à
    git lui-même (fichiers non suivis et modifiés que l'ajout prendrait), au lieu
    de deviner la forme de la commande (--all, ./, :/, -Av passaient)."""
    import subprocess
    detection = _detection()
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    for dossier, args in ajouts_git(texte, depart):
        options = [a for a in args if a.startswith("-") and a != "-"]
        chemins = [a for a in args if not a.startswith("-") or a == "-"]
        # ':!.env' exclut le .env : pas un ajout ; git l'applique
        # lui-même dans ls-files plus bas.
        exclusions = [c for c in chemins if c.startswith((":!", ":^", ":(exclude)"))]
        if any(detection.est_fichier_de_secrets(c) for c in chemins if c not in exclusions):
            return "SECRET"                         # git add .env, git add -f .env
        tout = any(o in ("-A", "--all", "-u", "--update") or o.startswith("--pathspec-from-file")
                   or (not o.startswith("--") and set(o[1:]) & set("Au")) for o in options)
        force = any(o in ("-f", "--force") or (not o.startswith("--") and "f" in o[1:]) for o in options)
        if not chemins and not tout:
            continue
        if not dossier or not os.path.isdir(dossier):
            dossier = depart if depart and os.path.isdir(depart) else None
        if not dossier:
            continue
        cmd = ["git", "-c", "core.fsmonitor=false", "-C", dossier, "ls-files", "-z", "-o", "-m"]
        if not force:
            cmd.append("--exclude-standard")
        cmd += ["--"] + ((chemins if len(exclusions) < len(chemins) else [":/"] + chemins) or [":/"])
        try:
            r = subprocess.run(cmd, capture_output=True, env=env, timeout=20, stdin=subprocess.DEVNULL)
        except OSError:
            continue                                # pas de git : rien à ajouter
        except subprocess.TimeoutExpired:
            return "INCONNU"                        # on ne sait pas ce que l'ajout emporterait
        if r.returncode != 0:
            continue                                # pas un dépôt git : rien à ajouter
        if any(detection.est_fichier_de_secrets(f) for f in r.stdout.decode("utf-8", "replace").split("\0") if f):
            return "SECRET"
    return "OK"

# --- Clôture de phase (rule12) -----------------------------------------------

MARQUEURS_CLOTURE = (
    re.compile(r"(?i)cl(?:o|ô)ture\s*\(\s*phase\s*\d+"),
    re.compile(r"(?i)\(\s*phase\s*\d+[^)]*\)\s*:\s*cl(?:o|ô)ture\b"),
    re.compile(r"(?i:phase)\s*\d+.*\bLIVR(?:E|É)E\b"),
)


def titre(message):
    """La première ligne non vide : le titre du commit."""
    return next((l.strip() for l in (message or "").splitlines() if l.strip()), "")[:4000]


def porte_cloture(message):
    t = titre(message)
    return any(m.search(t) for m in MARQUEURS_CLOTURE)


def porte_cloture_quelque_part(texte):
    return any(any(m.search(l[:4000]) for m in MARQUEURS_CLOTURE) for l in texte.splitlines())


def lire_message(chemin):
    """Un fichier ordinaire, lu sans bloquer (ni tube ni /dev/zero) ; un lien
    est suivi. None s'il n'existe pas encore."""
    import stat
    try:
        fd = os.open(chemin, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return None
    with os.fdopen(fd, "rb") as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
            return ""
        return f.read(160000).decode("utf-8", "replace")[:40000]


def messages_du_commit(args):
    """(valeurs de -m, fichiers de -F) de « git commit … » ou « git merge … » :
    -m x, -mx, --message=x, -am x, -F f, -aF f, --file=f."""
    msgs, fichiers, k = [], [], 0
    while k < len(args):
        a = args[k]
        suivant = args[k + 1] if k + 1 < len(args) else ""
        if a == "--":
            break
        if a in ("-m", "--message"):
            msgs.append(suivant)
            k += 2
            continue
        if a in ("-F", "--file"):
            fichiers.append(suivant)
            k += 2
            continue
        if a.startswith("--message="):
            msgs.append(a.split("=", 1)[1])
        elif a.startswith("--file="):
            fichiers.append(a.split("=", 1)[1])
        elif a.startswith("-") and not a.startswith("--"):
            for p, c in enumerate(a[1:], 1):
                if c in "mF":
                    valeur = a[p + 1:] or suivant
                    (msgs if c == "m" else fichiers).append(valeur)
                    if not a[p + 1:]:
                        k += 1
                    break
                if c in "cCt":                      # -c/-C <commit>, -t <modèle> : une valeur
                    if not a[p + 1:]:
                        k += 1
                    break
        k += 1
    return msgs, fichiers


def commit_de_cloture(texte, depart):
    """Le dossier d'un « git commit » (ou merge) dont le TITRE porte un marqueur
    de clôture, ou None. Jusqu'à la 0.3.4, rule12 découpait la commande à la
    main : un « \\ » + retour à la ligne entre git
    et commit passait, et le marqueur était cherché dans toute la commande (un
    git log --grep ou un corps de message qui cite une clôture passée
    bloquait un commit ordinaire)."""
    docs = decouper(texte)[2]
    tous_les_mots = []
    dossier, pile = depart, []
    for mots, _, entrees in commandes_et_entrees(texte):
        tous_les_mots += mots
        nom = os.path.basename(mots[0].lstrip("\\"))
        if nom in ("cd", "pushd", "popd"):
            dossier = suivre_dossier(nom, mots, dossier, pile)
            continue
        if nom != "git":
            continue
        d, i = depot_vise(mots, dossier)
        ici = d or dossier or depart
        sous, args = sous_commande(mots, i, ici)
        if sous not in ("commit", "merge"):
            continue
        msgs, fichiers = messages_du_commit(args)
        candidats = []
        if msgs:
            premier = msgs[0]
            if "$(" in premier or "`" in premier:
                # -m "$(cat <<'EOF' … EOF)" : le titre est la 1re ligne du document ;
                # -m "$(cat f)" : celle du fichier.
                m = re.search(r"\bcat\s+([^\s)<>|;&]+)\s*\)", premier)
                lu = lire_message(os.path.join(ici, os.path.expanduser(m.group(1)))) if m else None
                candidats += [lu] if lu is not None else list(docs)
            else:
                candidats.append(premier)
        for f in fichiers:
            if f == "-":
                candidats += [v for g, v in entrees if g in ("document", "texte")] or list(docs)
                continue
            lu = lire_message(os.path.join(ici, os.path.expanduser(f)))
            # Absent : créé par cette même commande (printf … > m.txt && git
            # commit -F m.txt) ; ses mots et documents sont jugés.
            candidats += [lu] if lu is not None else list(docs) + tous_les_mots
        if any(porte_cloture(c) for c in candidats if c):
            return ici
    return None


# --- Point d'entrée ------------------------------------------------------------

# Une commande que ce lecteur ne sait pas découper (guillemet non fermé) :
# bash non plus ne l'exécuterait, il s'arrête sur une erreur de syntaxe. On la
# lit alors prudemment, par motifs. Avant, l'erreur sortait en code 3 et le
# garde-fou refusait avec un faux motif (« Python introuvable »).
# Une recherche récursive ou des noms passés par xargs, dans une ligne
# illisible : elle peut montrer un .env sans le nommer.
RECHERCHE_BRUTE = re.compile(r"\b[efz]?grep\b[^|;&\n]*\s-\w*[rR]|\b(rg|ag)\b|\bxargs\b|\$\(\s*<")
NOM_DE_SECRET_BRUT = re.compile(r"\.env\b|\.pem\b|\.key\b|/environ\b|id_(rsa|ed25519|ecdsa|dsa)\b|wallet|keystore|"
                                r"mnemonic|\.claude\.json|\.git-credentials|\.netrc", re.I)


def lire_entree():
    d = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    d = d if isinstance(d, dict) else {}
    t = d.get("tool_input") if isinstance(d.get("tool_input"), dict) else {}
    texte = t.get("command") or ""
    texte = texte if isinstance(texte, str) else ""
    depart = d.get("cwd") if isinstance(d.get("cwd"), str) else ""
    depart = depart or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    return t, texte, depart


def protection(t, texte, depart):
    detection = _detection()
    for ou, cle in (("commande", "command"), ("fichier", "content"), ("edition", "new_string"),
                    ("edition", "new_source")):
        v = t.get(cle)
        if isinstance(v, str) and detection.valeur_secrete(v):
            return f"VALEUR\t{ou}"
    if not texte:
        return "OK"
    try:
        if verdict_secret(texte, detection, depart=depart) == "SECRET":
            return "LECTURE"
    except TropGrand:
        return "TROP_GRAND"
    except ValueError:
        if NOM_DE_SECRET_BRUT.search(texte) or RECHERCHE_BRUTE.search(texte):
            return "LECTURE"
    try:
        ajout = ajout_secret(texte, depart)
    except ValueError:
        # Illisible, mais la ligne parle d'un git add : on juge le dépôt de
        # départ comme pour « git add -A ».
        ajout = ajout_secret("git add -A", depart) if re.search(r"\bgit\b", texte) and \
            re.search(r"\b(add|stage)\b", texte) else "OK"
    return {"SECRET": "AJOUT", "INCONNU": "AJOUT_INCONNU"}.get(ajout, "OK")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    t, texte, depart = lire_entree()
    if mode == "protection":
        print(protection(t, texte, depart))
    elif mode == "pousses":
        try:
            pousses = depots_pousses(texte, depart)
        except ValueError:
            # Illisible : si la ligne parle de push, on contrôle le départ.
            pousses = [(depart, ["HEAD"])] if re.search(r"\bpush\b", texte) else []
        for dossier, refs in dict.fromkeys((d, " ".join(r)) for d, r in pousses):
            print(f"{dossier}\t{refs}")
    elif mode == "cloture":
        texte = texte[:40000]
        try:
            dossier = commit_de_cloture(texte, depart)
        except ValueError:
            # Illisible : on lit le texte entier, prudemment.
            dossier = depart if re.search(r"\bcommit\b", texte) and porte_cloture_quelque_part(texte) else None
        print(f"OUI\t{dossier}" if dossier else "NON")
    else:
        raise SystemExit(3)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(3)
