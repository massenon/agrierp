# -*- coding: utf-8 -*-
"""Audit de fidelite v2 — phase 0 de AUDIT_FIDELISATION.md (ticket AF1.0).

    py outils/audit_fidelite.py          # ecrit RAPPORT_FIDELITE_2.md + audit_fidelite.json

Ce qui change par rapport a l'audit n° 1 :

  1. L'association page -> ecran est DEDUITE (`association_ecrans.py`), non plus
     ecrite a la main. Une page sans ecran n'est plus mesuree contre tout le
     code : elle est declaree absente.
  2. Les exemptions du test `fidelite_libelles_test.dart` sont LUES, puis
     classees — (a) assumee, (b) non portee, (c) oubli — au lieu d'etre comptees
     comme des absences brutes.
  3. Trois taux, jamais un seul :
       STRICT   libelle trouve dans un litteral de l'ecran, sans aucune exemption
       ASSUME   strict + ecarts (a) motives + donnees de demonstration
       NON PORTE  ecarts (b), qui deviennent des tickets
     et le reste, (c), est le travail non fait ou non classe.
  4. Les faux negatifs sont isoles : un libelle absent mais dont une chaine de
     l'ecran est tres proche est liste a part (« reformulation probable »), il
     n'abaisse ni ne releve aucun taux tant qu'un humain ne l'a pas tranche.

⚠️ LA CLASSIFICATION DES MOTIFS EST UNE PROPOSITION. Les motifs viennent du
test (donc de decisions de tickets passes) ; le rangement en (a)/(b) est le
mien, fait par motif, visible dans MOTIFS ci-dessous et a valider. Un motif
inconnu tombe en `a classer`, jamais en (a) par defaut.
"""
import difflib
import glob
import io
import json
import os
import re
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import association_ecrans as asso  # noqa: E402
import inventaire as inv  # noqa: E402
import structure as st  # noqa: E402

RACINE = asso.RACINE
PROTO = asso.PROTO
os.chdir(RACINE)


# ───────────────────────── lecture du code Dart ─────────────────────────────
def chaines(src):
    """Litteraux de chaine d'une source Dart, commentaires exclus.

    Meme regle que `chainesDe` du test (F0.53) : un commentaire ou un
    identifiant ne tient pas lieu de libelle.
    """
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            while i < n and src[i] != '\n':
                i += 1
            continue
        if src.startswith('/*', i):
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        brut = c == 'r' and i + 1 < n and src[i + 1] in '\'"'
        d0 = i + 1 if brut else i
        c = src[d0]
        if c in '\'"':
            tri = src.startswith(c * 3, d0)
            d = c * 3 if tri else c
            j = d0 + len(d)
            buf = []
            while j < n and not src.startswith(d, j):
                if not brut and src[j] == '\\' and j + 1 < n:
                    buf.append(src[j + 1])
                    j += 2
                    continue
                buf.append(src[j])
                j += 1
            i = j + len(d)
            out.append(''.join(buf))
            continue
        i += 1
    return '\n'.join(out)


def lire(f):
    return io.open(f, encoding='utf-8', errors='ignore').read()


CODE = {f.replace(os.sep, '/'): chaines(lire(f))
        for f in glob.glob('lib/**/*.dart', recursive=True)}


def _plat(s):
    s = unicodedata.normalize(
        'NFD', s.replace('’', "'").replace(chr(160), ' ')
        .replace('œ', 'oe').replace('Œ', 'oe'))
    return ''.join(ch for ch in s if unicodedata.category(ch) != 'Mn')


def norm(s):
    return re.sub(r'[\s*:]+', ' ', _plat(s).lower()).strip()


_NC = {}


def contient(code, libelle):
    """Libelle dans le code, accents et casse ignores (arbitrage F0.51)."""
    if code not in _NC:
        _NC[code] = norm(code)
    return norm(libelle) in _NC[code]


# ───────────────────────── exemptions du test ────────────────────────────────
def _jetons(bloc):
    """Jetons ('s', texte) | ('{',) | ('}',) | (':',) | (',',) d'un bloc Dart."""
    jt, i, n = [], 0, len(bloc)
    while i < n:
        if bloc.startswith('//', i):
            while i < n and bloc[i] != '\n':
                i += 1
            continue
        c = bloc[i]
        brut = c == 'r' and i + 1 < n and bloc[i + 1] in '\'"'
        d0 = i + 1 if brut else i
        q = bloc[d0]
        if q in '\'"':
            j, buf = d0 + 1, []
            while j < n and bloc[j] != q:
                if not brut and bloc[j] == '\\' and j + 1 < n:
                    buf.append(bloc[j + 1])
                    j += 2
                    continue
                buf.append(bloc[j])
                j += 1
            texte = ''.join(buf)
            # deux litteraux separes par des blancs seuls se concatenent
            if jt and jt[-1][0] == 's' and jt[-1][2]:
                jt[-1] = ('s', jt[-1][1] + texte, True)
            else:
                jt.append(('s', texte, True))
            i = j + 1
            continue
        if c in '{}:,':
            jt.append((c,))
        i += 1
    # `True` n'a servi qu'a la concatenation
    return [(t[0], t[1]) if t[0] == 's' else t for t in jt]


def _bloc(src, ancre):
    debut = src.index(ancre)
    debut = src.index('{', debut)
    prof, i = 0, debut
    while i < len(src):
        ch = src[i]
        if src.startswith('//', i):
            while i < len(src) and src[i] != '\n':
                i += 1
            continue
        if ch in '\'"':
            brut = src[i - 1] == 'r'
            j = i + 1
            while j < len(src) and src[j] != ch:
                j += 2 if (not brut and src[j] == '\\') else 1
            i = j + 1
            continue
        if ch == '{':
            prof += 1
        elif ch == '}':
            prof -= 1
            if prof == 0:
                return src[debut + 1:i]
        i += 1
    raise ValueError(ancre)


def exemptions_du_test():
    """(globales {label: motif}, par_page {page: {label: motif}})."""
    src = lire('test/fidelite_libelles_test.dart')
    glob_ = {}
    jt = _jetons(_bloc(src, 'const exemptions ='))
    for k in range(len(jt) - 2):
        if jt[k][0] == 's' and jt[k + 1][0] == ':' and jt[k + 2][0] == 's':
            glob_[jt[k][1]] = jt[k + 2][1]

    par_page = {}
    jt = _jetons(_bloc(src, 'const exemptionsParPage ='))
    k = 0
    while k < len(jt) - 2:
        if jt[k][0] == 's' and jt[k + 1][0] == ':' and jt[k + 2][0] == '{':
            page, k = jt[k][1], k + 3
            par_page[page] = {}
            while k < len(jt) and jt[k][0] != '}':
                if (jt[k][0] == 's' and k + 2 < len(jt)
                        and jt[k + 1][0] == ':' and jt[k + 2][0] == 's'):
                    par_page[page][jt[k][1]] = jt[k + 2][1]
                    k += 3
                else:
                    k += 1
        k += 1
    return glob_, par_page


# ───────────────────── classification des motifs ───────────────────────────
# Classe : A = divergence assumee et motivee ; B = fonctionnalite non portee
# (devient un ticket) ; D = donnee de demonstration / composant porteur.
# Ordre = priorite. Chaque ligne dit POURQUOI.
MOTIFS = [
    # --- D : pas un contenu a porter
    # --- A : ecarts assumes de F0.67 (Ajouter / Modifier un Produit)
    (r'titre de gabarit', 'A', 'titre de gabarit, Laravel et le poste disent autrement'),
    (r'le gabarit du prototype porte UN prix', 'A',
     'regle metier Fourchette / Sur devis plutot que le gabarit'),
    (r'doublon du bouton', 'A', 'le « + » est une icône, le bouton existe'),
    (r'suppression définitive non disponible', 'A',
     'archiver suffit et ne détruit rien'),
    (r'une dette est générée par un achat', 'A',
     "la dette naît de l'achat, elle ne se modifie pas"),
    (r'modification : le poste porte', 'A', 'libellé de modification reformulé'),
    (r'création à la volée non portée', 'B',
     'creation de produit depuis ce formulaire non construite'),
    (r'se fait au Catalogue Produits', 'A', 'ecran voisin, deja porte'),
    (r'liste (de produits )?embarquée', 'A',
     'liste deja portee au Catalogue, pas redessinee'),
    (r'valeur de démonstration|widget de démonstration', 'D',
     'donnee de demonstration du prototype'),
    (r'porté par (Bouton|la modale)', 'D', 'porte par un composant partage'),
    (r'accordéon|bouton flottant mobile|affordance mobile', 'D',
     'affordance de petit ecran, sans objet sur le poste'),
    (r'notation LaTeX', 'A', 'defaut du prototype signale, arbitrage client'),
    (r'non accentué', 'A', 'arbitrage d\'accentuation ouvert (F0.51)'),
    (r"option que le PDF du serveur n'applique pas|choix de format que le PDF",
     'A', "option que ni le PDF du serveur ni la page web n'appliquent (F0.64)"),
    (r"génération faite depuis l'onglet Attestations", 'A',
     "meme fonction, portee par un autre onglet (F0.64)"),
    (r"matrice sans donnée|aucun mouvement ne se déclare|"
     r"onglet .* sans (source|table)|colonne reformulée|"
     r"aucun opérateur n'est enregistré|colonne absente : le soin de bande|"
     r"valeur de démonstration \(l'identifiant", 'A',
     "ecart repris de la page web (Laravel 14.16), arbitre par le client (F0.65)"),
    (r'composé avec|filtre alimenté par les catégories réelles|'
     r'colonne rendue sous sa variante', 'A',
     'meme contenu, forme dynamique'),
    # --- A : le serveur / la securite / l'integrite l'imposent
    (r'référentiel en lecture seule|servis en lecture seule|'
     r'lecture seule au poste', 'A',
     'le serveur ignore tout envoi sur ce referentiel (CLAUDE.md)'),
    (r'réservée? au web|réservé au web|gardée? sur le serveur|'
     r'gardées sur le serveur|calculés? sur le web|calculée? sur le serveur|'
     r'aucun secret|non descendues? au poste|création de compte', 'A',
     'effet comptable ou secret que le poste ne doit pas porter'),
    (r'ecriture generee|facture créée à la caisse|intégrité fiscale', 'A',
     'regle metier : l\'ecriture / la facture nait d\'une operation'),
    (r'encaissement non embarqué|envoi impossible hors ligne|'
     r'aucune table de modèles|règlement fournisseur', 'A',
     'effet financier sans canal d\'envoi fiable'),
    (r'calendrier calculé|rendu par le Calendrier|porté par la modale', 'A',
     'meme fonction, rendue ailleurs dans l\'ecran'),
    (r'saisie faite sur la fiche|onglet rendu en résumé|'
     r'projection rendue en tableau', 'A', 'meme donnee, autre presentation'),
    # --- B : fonctionnalite qui manque au poste
    (r"chaîne d'édition officielle non embarquée", 'B',
     'MOTIF PERIME : ExportOfficiel existe depuis F0.52'),
    (r"chaîne d'édition non embarquée", 'B',
     'MOTIF PERIME : ExportOfficiel/ExportTableur existent depuis F0.52'),
    (r"écran qui n'appelle pas la chaîne", 'B',
     'bouton inerte, ticket de recablage deja annonce (F0.52)'),
    (r"chaîne d'import non embarquée", 'B',
     'import de fichier : aucun selecteur de fichier dans pubspec.yaml'),
    (r'import de fichier non embarqué', 'B', 'idem import'),
    (r'ni sélecteur de fichier', 'B', 'aucun selecteur de fichier'),
    (r'module non embarqué|non embarqué', 'B', 'ecran/section non porte'),
    (r'non synchronisé|absente? du schéma|absences de stagiaire', 'B',
     'donnee non descendue au poste : decision de synchronisation a prendre'),
    (r'secretariat non embarque', 'B', 'ecran de saisie non porte'),
    (r'saisie non portée', 'A', 'bon servi en lecture seule'),
    (r'colonne du tableau des sauvegardes', 'A',
     'sauvegardes gardees sur le serveur'),
    (r'le PMP est calculé par le serveur', 'A', 'calcul serveur'),
]
MOTIFS = [(re.compile(m, re.I), c, why) for m, c, why in MOTIFS]


def classer_motif(motif):
    for rx, classe, why in MOTIFS:
        if rx.search(motif):
            return classe, why
    return '?', 'motif non reconnu — a classer a la main'


# Pages dont le titre differe de l'onglet qui les porte : l'heuristique « titre
# absent » les jugerait non portees. Chaque entree cite sa PREUVE, verifiee par
# grep dans `lib/` — pas une impression.
PORTEE_PARTIELLE = {
    'bilan-technico-economique.html':
        "onglet « Bilan Technico-Économique » (dashboard_elevage_screen.dart:32)",
    'cloture-exercice.html':
        "carte « Clôture Périodique & Annuelle » (comptabilite_screen.dart:35)",
}

# Equivalences DOCUMENTEES : le libelle du prototype n'est pas a la lettre dans
# l'ecran, et ce n'est pas un oubli. Cle = libelle exact du prototype.
# ⚠️ Une equivalence se prouve (la variante est bien dans l'ecran) ; sans la
# variante, elle ne compte pas.
EQUIVALENCES = {
    'Poids Moyen Constatéd': (
        'Poids Moyen Constaté',
        'coquille du prototype : un « d » parasite dans quatre pages'),
    'Coût Total du Lot': (
        'Coût Total Connu du Lot',
        "écart (a) repris de Laravel (ticket 14.49) : la main d'œuvre reste hors "
        "du calcul, un « Coût Total » sans réserve serait un chiffre faux "
        "présenté comme complet"),
    '+ Filtrer la Période': (
        'Filtrer la Période',
        'variante « + » du bouton flottant mobile (cf. « + Nouveau … » exemptes)'),
}

# Libelle « demonstration » : porte une date, un numero de jour, un code lot...
DEMO = re.compile(
    r'\d{1,2}/\d{1,2}/\d{4}|\bJour \d+\b|\b[A-Z]{2,4}-\d{4}-\d{2,}|'
    r'\bJour X\b|\(Bande B\d|\(Naissains\)|\(Engraissement\)|'
    r'\b(Cage|Parc|Logette|Maternité|Bâtiment|Poussinière|Fosse|'
    r'Escargotière) [A-Z]\d')


# ───────────────────────── mesure d'une page ─────────────────────────────────
def corps(p):
    b = lire(os.path.join(PROTO, p))
    m = re.search(r'<body\b[^>]*>(.*)</body>', b, re.S | re.I)
    c = m.group(1) if m else b
    return inv.CHROME.sub(' ', inv.SCRIPTS.sub(' ', c))


def cartes(c):
    res = []
    for m in re.finditer(r'<div\b[^>]*border-l-4\s+border-l-[^>]*>', c):
        depth, pos, seg = 1, m.end(), None
        for t in re.finditer(r'<(/?)div\b', c[pos:]):
            depth += -1 if t.group(1) else 1
            if depth == 0:
                seg = c[pos:pos + t.start()]
                break
        if seg is None:
            seg = c[pos:pos + 400]
        noeuds = [inv.texte(x) for x in re.split(r'<[^>]+>', seg)]
        noeuds = [x for x in noeuds if x and re.search(r'[A-Za-zÀ-ÿ]{3,}', x)]
        res.append(noeuds[0] if noeuds else '?')
    return res


def titre_page(c):
    m = re.search(r'<h[12]\b[^>]*>(.*?)</h[12]>', c, re.S | re.I)
    return inv.texte(m.group(1)) if m else ''


def proche(libelle, lignes):
    """Meilleure chaine de l'ecran proche d'un libelle absent."""
    n = norm(libelle)
    if len(n) < 6:
        return None, 0.0
    best, score = None, 0.0
    for l in lignes:
        nl = norm(l)
        if abs(len(nl) - len(n)) > max(8, len(n) // 2):
            continue
        r = difflib.SequenceMatcher(None, n, nl).ratio()
        if r > score:
            best, score = l, r
    return best, score


CATEGORIES = ('titres', 'boutons', 'colonnes', 'etiquettes', 'cartes',
              'onglets')


def auditer(page, assoc, ex_glob, ex_page):
    a = assoc[page]
    c = corps(page)
    code = '\n'.join(CODE.get(f, '') for f in a['fichiers'])
    lignes = [l for l in code.split('\n') if 3 <= len(l) <= 120]
    lab = inv.libelles(os.path.join(PROTO, page))
    s = st.structure(os.path.join(PROTO, page))
    libs = {k: list(lab[k]) for k in ('titres', 'boutons', 'colonnes',
                                       'etiquettes')}
    libs['cartes'] = cartes(c)
    libs['onglets'] = list(s['onglets'])

    a_ecran = bool(a['fichiers'])
    titre_ok = bool(a_ecran and contient(code, titre_page(c))) \
        if titre_page(c) else a_ecran
    # Page portee « en partie » : son titre ou la majorite de ses mots existent.
    r = {'page': page, 'fichiers': a['fichiers'], 'sources': a['sources'],
         'parent': a['parent'], 'ecran': a_ecran, 'titre_present': titre_ok,
         'compte': {'strict': 0, 'A': 0, 'B': 0, 'C': 0, 'D': 0},
         'categories': {}, 'absents': [], 'quasi': [], 'total': 0}

    # Premier passage : trouve / pas trouve.
    for cat in CATEGORIES:
        for l in libs[cat]:
            r['total'] += 1
            if a_ecran and (contient(code, l) or contient(code, l.upper())):
                r['compte']['strict'] += 1
                r['categories'].setdefault(cat, [0, 0])[0] += 1
                r['categories'][cat][1] += 1
                continue
            r['categories'].setdefault(cat, [0, 0])[1] += 1
            classe, motif, why = None, None, None
            if l in ex_glob:
                motif = ex_glob[l]
            elif l in ex_page.get(page, {}):
                motif = ex_page[page][l]
            if motif is not None:
                classe, why = classer_motif(motif)
            elif l in EQUIVALENCES and a_ecran and contient(
                    code, EQUIVALENCES[l][0]):
                classe, motif, why = 'A', EQUIVALENCES[l][1],                     'equivalence documentee'
            elif DEMO.search(l):
                classe, motif, why = 'D', 'valeur de demonstration probable', \
                    'date / jour / code lot fige sur le jeu de demo'
            r['absents'].append({'cat': cat, 'libelle': l, 'classe': classe,
                                 'motif': motif, 'pourquoi': why})

    # Deuxieme passage : pages sans ecran, ou classe non posee.
    page_non_portee = (not a_ecran) or (
        page not in PORTEE_PARTIELLE
        and page not in asso.portages_test() and not titre_ok
        and r['compte']['strict'] / max(r['total'], 1) < 0.5)
    r['page_non_portee'] = page_non_portee
    for x in r['absents']:
        if x['classe'] is None:
            if page_non_portee:
                x['classe'], x['pourquoi'] = 'B', (
                    'page sans ecran' if not a_ecran else
                    'page non portee : titre absent et moins de la moitie du '
                    'vocabulaire present')
            else:
                x['classe'], x['pourquoi'] = 'C', (
                    'ni trouve ni exempte, sur une page portee : oubli ou '
                    'reformulation')
                best, sc = proche(x['libelle'], lignes)
                if best and sc >= 0.82:
                    x['quasi'] = {'chaine': best, 'ratio': round(sc, 2)}
                    r['quasi'].append(x)
        r['compte'][x['classe'] if x['classe'] in 'ABCD' else 'C'] += 1
    return r


def tout():
    assoc = asso.associer()
    ex_glob, ex_page = exemptions_du_test()
    res = [auditer(p, assoc, ex_glob, ex_page) for p in sorted(assoc)]
    return res, ex_glob, ex_page


# ───────────────────────────── rapport ───────────────────────────────────────
def pct(a, b):
    return '%5.1f %%' % (100.0 * a / b) if b else '    — '


def totaux(res):
    t = {'strict': 0, 'A': 0, 'B': 0, 'C': 0, 'D': 0, 'total': 0}
    for r in res:
        for k in ('strict', 'A', 'B', 'C', 'D'):
            t[k] += r['compte'][k]
        t['total'] += r['total']
    return t


def rapport(res, ex_glob, ex_page):
    t = totaux(res)
    L = []
    w = L.append
    w('# RAPPORT DE FIDÉLITÉ n° 2 — poste Flutter vs prototype HTML')
    w('')
    w('Généré par `outils/audit_fidelite.py` (ticket AF1.0). **Ce rapport remplace '
      "l'annexe A de `AUDIT_FIDELISATION.md`** : il est reproductible, "
      "l'association page → écran est déduite et non plus écrite à la main.")
    w('')
    w('> ⚠️ La classe (a)/(b) de chaque motif est **une proposition**, rangée '
      'par motif (table `MOTIFS` de `outils/audit_fidelite.py`). Les motifs '
      'viennent des tickets passés ; leur rangement n\'a pas été validé par le '
      'client. Un motif inconnu est signalé `?`, jamais rangé en (a) par défaut.')
    w('')
    w('## 1. Les trois taux')
    w('')
    w('| Taux | Définition | Valeur |')
    w('|---|---|---|')
    w('| **Strict** | libellé trouvé dans un littéral de l\'écran, sans aucune '
      'exemption | %s (%d / %d) |' % (pct(t['strict'], t['total']).strip(),
                                       t['strict'], t['total']))
    ass = t['strict'] + t['A'] + t['D']
    w('| **Assumé** | strict + écarts (a) motivés + données de démonstration | '
      '%s (%d / %d) |' % (pct(ass, t['total']).strip(), ass, t['total']))
    w('| **Non porté** | écarts (b) : fonctionnalité absente, ticket à ouvrir | '
      '%s (%d) |' % (pct(t['B'], t['total']).strip(), t['B']))
    w('| **Oubli / non classé** | (c) : sur une page portée, ni trouvé ni '
      'exempté | %s (%d) |' % (pct(t['C'], t['total']).strip(), t['C']))
    w('')
    w('Pour mémoire, l\'audit n° 1 donnait **58,4 %** (1 351 / 2 314) — un taux '
      'qui mélangeait ces quatre réalités. Le dénominateur peut différer de '
      'quelques unités : les cartes et onglets sont comptés ici par page '
      'portée.')
    w('')

    # par categorie
    w('## 2. Par catégorie (strict)')
    w('')
    w('| Catégorie | Retrouvés | Total | Taux strict |')
    w('|---|---|---|---|')
    for cat in CATEGORIES:
        f = sum(r['categories'].get(cat, [0, 0])[0] for r in res)
        n = sum(r['categories'].get(cat, [0, 0])[1] for r in res)
        w('| %s | %d | %d | %s |' % (cat, f, n, pct(f, n).strip()))
    w('')

    # etat des pages
    sans = [r for r in res if not r['ecran']]
    nonp = [r for r in res if r['ecran'] and r['page_non_portee']]
    w('## 3. Association page → écran')
    w('')
    srcs = {}
    for r in res:
        k = '+'.join(r['sources']) or 'aucune'
        srcs[k] = srcs.get(k, 0) + 1
    w('%d pages mesurées. Sources des associations : %s.' % (
        len(res), ', '.join('%s %d' % kv for kv in sorted(srcs.items()))))
    w('')
    w('**Sans écran (%d)** : %s.' % (len(sans),
                                    ', '.join(r['page'] for r in sans)))
    w('')
    w('**Écran parent mais page non portée (%d)** — le titre de la page est '
      'absent de l\'écran associé et moins de la moitié de son vocabulaire y '
      'figure : %s.' % (len(nonp), ', '.join(r['page'] for r in nonp)))
    w('')

    # exemptions
    w('## 4. Les exemptions du test, classées')
    w('')
    ctr = {}
    for lbl, mo in ex_glob.items():
        ctr.setdefault(classer_motif(mo)[0], []).append(('global', lbl, mo))
    for pg, d in ex_page.items():
        for lbl, mo in d.items():
            ctr.setdefault(classer_motif(mo)[0], []).append((pg, lbl, mo))
    total_ex = sum(len(v) for v in ctr.values())
    w('%d exemptions (%d globales, %d par page).' % (
        total_ex, len(ex_glob), sum(len(d) for d in ex_page.values())))
    w('')
    w('| Classe | Nombre | Sens |')
    w('|---|---|---|')
    sens = {'A': 'divergence assumée et motivée — reste une exemption',
            'B': 'fonctionnalité non portée — devient un ticket',
            'D': 'donnée de démonstration / composant porteur — sans objet',
            '?': 'motif non reconnu — à classer à la main'}
    for k in ('A', 'B', 'D', '?'):
        w('| %s | %d | %s |' % (k, len(ctr.get(k, [])), sens[k]))
    w('')
    w('### 4.1 Exemptions (b) — ce qui devient un ticket')
    w('')
    par_motif = {}
    for pg, lbl, mo in ctr.get('B', []):
        par_motif.setdefault(mo, []).append(lbl)
    for mo, l in sorted(par_motif.items(), key=lambda kv: -len(kv[1])):
        w('- **%s** — %d libellés : %s' % (
            mo, len(l), ' · '.join(l[:8]) + (' …' if len(l) > 8 else '')))
    w('')
    if ctr.get('?'):
        w('### 4.2 Motifs non reconnus')
        w('')
        for pg, lbl, mo in ctr['?']:
            w('- `%s` › %s — « %s »' % (pg, lbl, mo))
        w('')

    # quasi
    quasi = [(r['page'], x) for r in res for x in r['quasi']]
    w('## 5. Faux négatifs probables (%d)' % len(quasi))
    w('')
    w('Libellé absent à la lettre mais dont une chaîne de l\'écran est très '
      'proche (ratio ≥ 0,82). **À trancher à la main** : reformulation à '
      'rétablir, ou équivalence à documenter. Non comptés comme trouvés.')
    w('')
    for pg, x in quasi:
        w('- `%s` — « %s » ≈ « %s » (%.2f)' % (
            pg, x['libelle'], x['quasi']['chaine'], x['quasi']['ratio']))
    w('')

    # par page
    w('## 6. Page par page')
    w('')
    w('Colonnes : S = strict, A = assumé (a), B = non porté (b), C = oubli (c), '
      'D = démonstration.')
    w('')
    w('| Page | Écran | Total | Strict | S | A | B | C | D |')
    w('|---|---|---|---|---|---|---|---|---|')
    for r in sorted(res, key=lambda r: (r['compte']['strict'] / max(r['total'], 1))):
        c = r['compte']
        ecran = ', '.join(os.path.basename(f) for f in r['fichiers'][:1]) \
            or '**AUCUN**'
        w('| %s | %s | %d | %s | %d | %d | %d | %d | %d |' % (
            r['page'], ecran, r['total'], pct(c['strict'], r['total']).strip(),
            c['strict'], c['A'], c['B'], c['C'], c['D']))
    w('')

    # oublis (c)
    w('## 7. Oublis (c) — à corriger')
    w('')
    n = 0
    for r in sorted(res, key=lambda r: -r['compte']['C']):
        cs = [x for x in r['absents'] if x['classe'] == 'C']
        if not cs:
            continue
        n += 1
        w('- **%s** (%d) : %s' % (
            r['page'], len(cs),
            ' · '.join('%s [%s]' % (x['libelle'], x['cat']) for x in cs[:14])
            + (' …' if len(cs) > 14 else '')))
    if not n:
        w('Aucun.')
    w('')
    return '\n'.join(L)


if __name__ == '__main__':
    res, eg, ep = tout()
    io.open('audit_fidelite.json', 'w', encoding='utf-8').write(
        json.dumps(res, ensure_ascii=False, indent=1))
    io.open('RAPPORT_FIDELITE_2.md', 'w', encoding='utf-8').write(
        rapport(res, eg, ep))
    t = totaux(res)
    print('%d pages' % len(res))
    print('strict %d/%d  A %d  B %d  C %d  D %d' % (
        t['strict'], t['total'], t['A'], t['B'], t['C'], t['D']))
