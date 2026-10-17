# -*- coding: utf-8 -*-
"""Phase 1A de AUDIT_FIDELISATION.md — « le bon libelle au bon endroit ».

    AUDIT_RENDU=1 flutter test test/rendu_onglets_test.dart   # releve le rendu
    py outils/emplacement.py                                   # RAPPORT_EMPLACEMENT.md

L'audit de presence (`audit_fidelite.py`) dit si un mot existe dans le source
d'un ecran. Il ne dit pas s'il est dans le bon ONGLET, ni dans le bon ORDRE, ni
si une CARTE d'indicateur dit ce que dit celle du prototype (faiblesse n° 2 de
CLAUDE.md : « card labels are checked by nothing »).

Ce comparateur confronte, panneau par panneau :
  prototype  les libelles d'un onglet, dans l'ordre du document (titres,
             boutons, colonnes, etiquettes, cartes)
  poste      ce que l'arbre de widgets AFFICHE dans l'onglet correspondant
             (`build/audit/rendu_onglets.json`, produit par le banc de rendu)

Chaque libelle tombe dans UNE de ces classes :
  ici             rendu dans l'onglet attendu
  ailleurs        rendu, mais dans un AUTRE onglet : defaut d'emplacement
  source seul     absent du rendu a vide, present dans un litteral du source
                  (modale, contenu de ligne : le banc ne le voit pas)
  absent          ni rendu ni dans le source : voir l'audit de presence

⚠️ BASE VIDE. Le rendu est releve sur une base vide : un en-tete de tableau que
l'ecran ne dessine qu'avec des lignes tombe en « source seul », jamais en
« absent ». Ce rapport ne PROUVE donc pas qu'un libelle est affiche — il prouve
qu'il est AU BON ENDROIT quand il l'est, et qu'il est AU MAUVAIS quand il l'est.
"""
import io
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audit_fidelite as af  # noqa: E402
import association_ecrans as asso  # noqa: E402
import inventaire as inv  # noqa: E402

RACINE, PROTO = asso.RACINE, asso.PROTO
RENDU = os.path.join(RACINE, 'build', 'audit', 'rendu_onglets.json')

# cle du banc de rendu -> page du prototype
HUBS = {
    'tableau-de-bord': 'dashboard.html',
    'elevage-dashboard': 'elevage-dashboard.html',
    'suivi-reproduction': 'suivi-reproduction.html',
    'soins-vaccins-hub': 'soins-vaccins-hub.html',
    'parametres-elevage': 'parametres-elevage.html',
    'creances-clients': 'creances-clients.html',
    'gestion-stocks': 'gestion-stocks.html',
    'catalogue-produits': 'catalogue-produits.html',
    'ventes-devis': 'ventes-devis.html',
    'parametres-hub': 'parametres-hub.html',
    'rapports-exports': 'rapports-exports.html',
    'administration': 'administration.html',
    'personnel-stages': 'personnel-stages.html',
    'fournisseurs': 'fournisseurs.html',
    'achats-commandes': 'achats-commandes.html',
    'comptabilite-hub': 'comptabilite-hub.html',
}

# Hub comptable : entree du poste (cle `carte-<nom>`) -> page du prototype.
COMPTA = {
    'planComptable': 'plan-comptable.html',
    'journal': 'journal-comptable.html',
    'grandLivre': 'grand-livre.html',
    'balance': 'balance-generale.html',
    'etatsFinanciers': 'etats-financiers.html',
    'cloture': 'cloture-exercice.html',
    'analytique': 'comptabilite-analytique.html',
    'tva': 'declaration-tva.html',
    'rapprochement': 'rapprochement-bancaire.html',
}

# Identifiants de panneaux « a plat » du prototype, dans l'ordre du document.
PANNEAU = re.compile(
    r'<div[^>]*\bid="((?:panel|dash-tab|stock-tab|tx-panel)-[a-z]+)"[^>]*>')
BORNE = re.compile(r'<div[^>]*\bid="action-panel-[a-z]+"')
CARTE = re.compile(r'<div\b[^>]*border-l-4\s+border-l-[^>]*>')
BALISES = (('h2', 'titres'), ('h3', 'titres'), ('button', 'boutons'),
           ('th', 'colonnes'), ('label', 'etiquettes'))
EST_DATE = re.compile(r'^[0-9]{1,2}/[0-9]{1,2}$')


def lire(p):
    return io.open(p, encoding='utf-8', errors='ignore').read()


def corps_html(page):
    b = lire(os.path.join(PROTO, page))
    m = re.search(r'<body\b[^>]*>(.*)</body>', b, re.S | re.I)
    return inv.CHROME.sub(' ', inv.SCRIPTS.sub(' ', m.group(1) if m else b))


def libelles_ordonnes(html):
    """[(categorie, libelle)] dans l'ordre du document, doublons retires."""
    trouves = []
    for balise, cat in BALISES:
        for m in re.finditer(r'<%s\b[^>]*>(.*?)</%s>' % (balise, balise),
                             html, re.S | re.I):
            t = inv.texte(m.group(1))
            if len(t) >= 2 and '${' not in t and not EST_DATE.match(t):
                trouves.append((m.start(), cat, t))
    for m in CARTE.finditer(html):
        depth, pos, seg = 1, m.end(), None
        for t in re.finditer(r'<(/?)div\b', html[pos:]):
            depth += -1 if t.group(1) else 1
            if depth == 0:
                seg = html[pos:pos + t.start()]
                break
        seg = seg if seg is not None else html[pos:pos + 400]
        noeuds = [inv.texte(x) for x in re.split(r'<[^>]+>', seg)]
        noeuds = [x for x in noeuds if x and re.search(r'[A-Za-zÀ-ÿ]{3,}', x)]
        if noeuds:
            trouves.append((m.start(), 'cartes', noeuds[0]))
    trouves.sort()
    vus, res = set(), []
    for _, cat, t in trouves:
        if (cat, t) not in vus:
            vus.add((cat, t))
            res.append((cat, t))
    return res


def panneaux_proto(hub):
    """(commun, [(titre_onglet, html_du_panneau)]) pour un hub du prototype."""
    corps = corps_html(hub)
    iframes = asso.enfants_iframe(hub)
    if iframes:
        sans = re.sub(r'<iframe\b.*?</iframe>|<iframe\b[^>]*/?>', ' ', corps,
                      flags=re.S | re.I)
        return sans, [(p, corps_html(p)) for p in iframes]
    reperes = list(PANNEAU.finditer(corps))
    if not reperes:
        return corps, []
    borne = BORNE.search(corps)
    fin_globale = borne.start() if borne else len(corps)
    commun = corps[:reperes[0].start()]
    res = []
    for i, m in enumerate(reperes):
        fin = reperes[i + 1].start() if i + 1 < len(reperes) else fin_globale
        res.append((m.group(1), corps[m.start():fin]))
    return commun, res


def textes_panneau(p):
    """Chaines normalisees du panneau rendu : textes + champs + cartes."""
    out = [af.norm(s) for s in p['textes']]
    out += [af.norm(s) for s in p['champs']]
    out += [af.norm(c['libelle']) for c in p['cartes']]
    return out


def position(libelle, chaines):
    """Rang de la premiere chaine rendue qui porte le libelle (-1 sinon)."""
    n = af.norm(libelle)
    for i, s in enumerate(chaines):
        if n == s:
            return i
    for i, s in enumerate(chaines):
        if n in s:
            return i
    return -1


def position_exacte(libelle, chaines):
    """Rang d'une chaine STRICTEMENT egale — pour juger l'ordre.

    ⚠️ L'inclusion fabrique de fausses inversions : « Date » est contenu dans
    n'importe quel titre qui parle de date, bien avant la colonne du tableau.
    """
    n = af.norm(libelle)
    for i, s in enumerate(chaines):
        if n == s:
            return i
    return -1


def inversions(positions):
    inv_ = []
    for i in range(len(positions)):
        for j in range(i + 1, len(positions)):
            if positions[i] > positions[j]:
                inv_.append((i, j))
    return inv_


def main():
    if not os.path.exists(RENDU):
        sys.exit('Relevé de rendu absent : AUDIT_RENDU=1 flutter test '
                 'test/rendu_onglets_test.dart')
    rendu = json.load(io.open(RENDU, encoding='utf-8'))
    assoc = asso.associer()
    alertes = rendu.get('(alertes de rendu)', [])

    L = []
    w = L.append
    w('# RAPPORT D\'EMPLACEMENT — le bon libellé au bon endroit (phase 1A)')
    w('')
    w('Généré par `outils/emplacement.py` à partir de '
      '`build/audit/rendu_onglets.json` (banc `test/rendu_onglets_test.dart`, '
      'ticket AF1.2). **Le poste est rendu en widgets, pas lu dans le source.**')
    w('')
    w('> ⚠️ **Base vide.** Le rendu est relevé sans donnée : un en-tête de '
      'tableau ou un champ de modale que l\'écran ne dessine qu\'avec des '
      'lignes tombe en « source seul », jamais en « absent ». Ce rapport prouve '
      'qu\'un libellé est au bon (ou au mauvais) endroit **quand il est '
      'rendu** ; il ne prouve pas qu\'un libellé non rendu est affiché '
      'ailleurs en situation réelle.')
    w('')

    ecarts = []  # (gravite, ou, constat)
    resume = []
    details = []
    cartes_diff = []

    for cle, hub in HUBS.items():
        r = rendu.get(cle)
        if r is None or 'erreur' in r:
            resume.append((cle, None, r and r.get('erreur')))
            continue
        onglets = r['onglets']
        panneaux_rendus = r['panneaux']

        commun, pp = panneaux_proto(hub)
        n_f = len(onglets)
        if cle == 'tableau-de-bord':
            # Le prototype n'a pas d'onglets de contenu, seulement cinq listes
            # de transactions : on compare la page entiere au rendu par defaut.
            commun = ''
            paires = [('dashboard.html', corps_html(hub), '(par défaut)')]
        elif cle == 'comptabilite-hub':
            # ⚠️ APPARIEMENT PAR NOM, pas par rang : les cartes de navigation du
            # prototype ne sont pas dans l'ordre des entrees du poste.
            commun = ''
            paires = [('(accueil)', corps_html(hub), '(par défaut)')]
            for ot in onglets:
                page = COMPTA.get(ot)
                if page:
                    paires.append((page, corps_html(page), ot))
        else:
            paires = [(tp, html, onglets[i] if i < n_f else None)
                      for i, (tp, html) in enumerate(pp)]
            if len(pp) != n_f:
                ecarts.append(('majeur', cle, "nombre d'onglets : prototype %d, "
                               "poste %d" % (len(pp), n_f)))

        fichiers = assoc[hub]['fichiers']
        code = '\n'.join(af.CODE.get(f, '') for f in fichiers)
        tous = {t: textes_panneau(p) for t, p in panneaux_rendus.items()}

        lignes = []
        for tp, html, ot in paires:
            if ot is None:
                lignes.append((tp, None))
                continue
            rendu_panneau = panneaux_rendus.get(ot, {'textes': [], 'champs': [],
                                                       'cartes': []})
            chaines = textes_panneau(rendu_panneau)
            labs = [(c, t) for c, t in libelles_ordonnes(html)
                    if not af.DEMO.search(t)]
            # l'en-tete commun (hors panneaux) vaut aussi pour chaque onglet
            commun_labs = [(c, t) for c, t in libelles_ordonnes(commun)
                           if not af.DEMO.search(t)]

            cnt = {'ici': 0, 'ailleurs': 0, 'source seul': 0, 'absent': 0}
            ailleurs, positions = [], []
            for cat, lab in commun_labs + labs:
                pos = position(lab, chaines)
                if pos >= 0:
                    cnt['ici'] += 1
                    exact = position_exacte(lab, chaines)
                    if cat in ('titres', 'cartes', 'colonnes') and exact >= 0:
                        positions.append((exact, cat, lab))
                    continue
                autre = next((o for o, ch in tous.items()
                              if o != ot and o != '(par défaut)'
                              and position(lab, ch) >= 0), None)
                if autre:
                    cnt['ailleurs'] += 1
                    ailleurs.append((cat, lab, autre))
                elif af.contient(code, lab) or af.contient(code, lab.upper()):
                    cnt['source seul'] += 1
                else:
                    cnt['absent'] += 1

            inv_ = []
            for cat_o in ('titres', 'cartes', 'colonnes'):
                suite = [x for x in positions if x[1] == cat_o]
                for a, b in inversions([p for p, _, _ in suite]):
                    inv_.append((suite[a], suite[b]))
            # cartes : ordre et libelles
            # ⚠️ Les cartes d'un en-tete PARTAGE (au-dessus des onglets) sont
            # repetees dans chaque onglet par le poste : elles comptent pour tous.
            cp = [t for c, t in libelles_ordonnes(commun) if c == 'cartes'] +                  [t for c, t in libelles_ordonnes(html) if c == 'cartes']
            cf = [c['libelle'] for c in rendu_panneau['cartes']]
            diff = []
            for k in range(max(len(cp), len(cf))):
                a = cp[k] if k < len(cp) else None
                b = cf[k] if k < len(cf) else None
                if a is None or b is None or af.norm(a) != af.norm(b):
                    diff.append((k + 1, a, b))
            lignes.append((tp, ot, cnt, ailleurs, inv_, positions, cp, cf, diff))

            for cat, lab, autre in ailleurs:
                ecarts.append(('majeur', '%s › %s' % (cle, ot),
                               '« %s » (%s) est rendu dans « %s », pas ici'
                               % (lab, cat, autre)))
            if diff and (cp or cf):
                cartes_diff.append((cle, ot, tp, cp, cf, diff))
                ecarts.append(('majeur', '%s › %s' % (cle, ot),
                               'cartes : prototype %d, poste %d, %d '
                               'différence(s)' % (len(cp), len(cf), len(diff))))
            if inv_:
                ecarts.append(('mineur', '%s › %s' % (cle, ot),
                               '%d inversion(s) d\'ordre entre titres / '
                               'cartes / colonnes' % len(inv_)))
        resume.append((cle, lignes, None))

    # ---------------- ecriture ----------------
    w('## 1. Synthèse par écran et par onglet')
    w('')
    w('| Écran › onglet (prototype → poste) | Libellés | ici | ailleurs | '
      'source seul | absent | Cartes proto / poste | Inversions d\'ordre |')
    w('|---|---|---|---|---|---|---|---|')
    tot = {'ici': 0, 'ailleurs': 0, 'source seul': 0, 'absent': 0}
    for cle, lignes, err in resume:
        if lignes is None:
            w('| %s | **le banc n\'a pas pu monter l\'écran** : %s | | | | | | |'
              % (cle, err))
            continue
        for l in lignes:
            if l[1] is None:
                w('| %s › %s → **aucun onglet** | | | | | | | |' % (cle, l[0]))
                continue
            tp, ot, cnt, ailleurs, inv_, positions, cp, cf, diff = l
            n = sum(cnt.values())
            for k in tot:
                tot[k] += cnt[k]
            w('| %s › %s → %s | %d | %d | %d | %d | %d | %d / %d%s | %d |' % (
                cle, tp.replace('.html', ''), ot, n, cnt['ici'],
                cnt['ailleurs'], cnt['source seul'], cnt['absent'],
                len(cp), len(cf), ' ✘' if diff and (cp or cf) else '',
                len(inv_)))
    w('')
    n_tot = sum(tot.values())
    w('**Total : %d libellés — %d au bon endroit (%.1f %%), %d dans un autre '
      'onglet, %d dans le source seulement, %d absents.**' % (
          n_tot, tot['ici'], 100.0 * tot['ici'] / max(n_tot, 1),
          tot['ailleurs'], tot['source seul'], tot['absent']))
    w('')
    w('« absent » se recoupe avec le rapport de présence '
      '(`RAPPORT_FIDELITE_2.md`) ; « source seul » est ce que le banc à vide ne '
      'peut pas voir (modales, lignes de tableau).')
    w('')

    w('## 2. Libellés rendus dans le mauvais onglet')
    w('')
    mauvais = [e for e in ecarts if 'est rendu dans' in e[2]]
    if mauvais:
        for g, ou, c in mauvais:
            w('- **%s** — %s' % (ou, c))
    else:
        w('Aucun : tout libellé du prototype qui est rendu l\'est dans l\'onglet '
          'attendu.')
    w('')

    w('## 3. Cartes d\'indicateur : libellé et ordre (faiblesse n° 2 de CLAUDE.md)')
    w('')
    w('Le contrôle de comptage (F0.54) voit les cartes apparaître et disparaître '
      'mais jamais ce qu\'elles disent. Ici, libellé contre libellé, dans '
      'l\'ordre.')
    w('')
    declares = re.findall(r"'([a-z0-9-]+\.html)'", lire(os.path.join(
        RACINE, 'test', 'cartes_attendues.dart')))
    meme = [x for x in cartes_diff if len(x[3]) == len(x[4])]
    autre = [x for x in cartes_diff if len(x[3]) != len(x[4])]

    def ecrire(groupe):
        for cle, ot, tp, cp, cf, diff in groupe:
            decl = tp in declares
            w('#### %s › %s%s' % (cle, ot, ' *(page déjà citée dans '
                                  '`cartes_attendues.dart`)*' if decl else ''))
            w('')
            w('| # | Prototype | Poste |')
            w('|---|---|---|')
            for k, a_, b_ in diff:
                w('| %d | %s | %s |' % (k, a_ or '—', b_ or '—'))
            w('')

    w('### 3.1 Même nombre de cartes, libellés différents — INVISIBLES au '
      'contrôle de comptage')
    w('')
    if meme:
        w("Le compte est juste, donc F0.54 se tait. Ce sont les seuls écarts de "
          "cette section que rien ne pouvait voir avant ce rapport.")
        w('')
        ecrire(meme)
    else:
        w('Aucun.')
        w('')
    w('### 3.2 Nombre de cartes différent')
    w('')
    w("Déjà vus par le contrôle de comptage (voir `ecartsAssumes`, "
      "`ecartsATraiter`, `ecartsPanneaux`). Ils sont repris ici avec les "
      "libellés, que ce contrôle ne montre pas.")
    w('')
    ecrire(autre)
    for cle, ot, tp, cp, cf, diff in meme:
        ecarts.append(('majeur', '%s › %s' % (cle, ot),
                       "même nombre de cartes mais libellés différents : %s" %
                       ' / '.join('« %s » → « %s »' % (a_, b_)
                                  for _, a_, b_ in diff[:3] if a_ and b_)))

    w('## 4. Ordre des éléments')
    w('')
    w("Pour chaque onglet, les titres, cartes et colonnes rendus sont comparés à "
      "l'ordre du document du prototype, catégorie par catégorie, sur les seules "
      "correspondances EXACTES (l'inclusion de mots courts fabriquait de fausses "
      "inversions). Une inversion = deux éléments rendus dans l'ordre contraire.")
    w('')
    n_inv = 0
    for cle, lignes, err in resume:
        if not lignes:
            continue
        for l in lignes:
            if l[1] is None:
                continue
            tp, ot, cnt, ailleurs, inv_, positions, cp, cf, diff = l
            if inv_:
                n_inv += 1
                a, b = inv_[0]
                w('- **%s › %s** : %d inversion(s), p. ex. « %s » rendu avant '
                  "« %s » (le prototype les met dans l'ordre inverse)" % (
                      cle, ot, len(inv_), b[2], a[2]))
    if not n_inv:
        w('Aucune inversion détectée.')
    w('')

    w('## 5. Débordements de mise en page relevés au rendu (1280 px)')
    w('')
    if alertes:
        w('Levés par Flutter pendant le rendu à vide (`RenderFlex overflowed`) — '
          'visibles à l\'écran comme une bande jaune et noire en mode debug.')
        w('')
        for a in alertes:
            w('- **%s** — %s' % (a['ou'], a['message']))
            ecarts.append(('majeur' if 'right' in a['message'] else 'mineur',
                           a['ou'], a['message']))
    else:
        w('Aucun.')
    w('')

    w('## 6. Écrans que le banc n\'a pas couverts')
    w('')
    w('Fiches d\'espèce (5), Gestion Élevage, Saisie Dépenses, Facturation, '
      'Caisse, Synchronisation, Paramètres du poste : sans onglets au sens de la '
      'convention de clés, ils demandent un banc dédié (une fiche = une saisie '
      'journalière + un tableau mensuel). **Non mesurés** — ne pas les croire '
      'conformes au motif qu\'ils n\'apparaissent pas ici.')
    w('')

    w('## Synthèse')
    w('')
    ordre = {'bloquant': 0, 'majeur': 1, 'mineur': 2}
    n = {k: sum(1 for e in ecarts if e[0] == k) for k in ordre}
    w('**%d bloquant · %d majeur · %d mineur.**' % (n['bloquant'], n['majeur'],
                                                  n['mineur']))
    w('')
    return '\n'.join(L), n


if __name__ == '__main__':
    texte, n = main()
    io.open(os.path.join(RACINE, 'RAPPORT_EMPLACEMENT.md'), 'w',
            encoding='utf-8').write(texte)
    print(n)
