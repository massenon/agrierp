# -*- coding: utf-8 -*-
"""Phase 1B et 1C de AUDIT_FIDELISATION.md — barre laterale et barre superieure.

    py outils/audit_chrome.py      # ecrit RAPPORT_CHROME.md

Ce qui est MESURE (extrait des deux sources, compare par programme) :
  * groupes de la barre : intitule, ordre, roles (`data-role-group`)
  * entrees : libelle, icone, ordre, page cible <-> ecran de l'enum
  * fil d'Ariane de chaque page <-> ce que la barre superieure en affiche
  * visibilite par role : groupe masque (prototype) vs entree estompee (poste)
  * croisement `data-role-group` x `RBAC_PAGE_MAP` : deux representations des
    droits dans le MEME prototype, qui ne coincident pas

Ce qui est RELEVE mais pas encore MESURE (une valeur par ligne, avec sa source) :
  largeur, hauteur, tailles de police, icones, couleurs — comparees a des
  valeurs lues dans le source Dart par expression reguliere. Aucun rendu : la
  phase 1D (captures comparees) reste a faire avec un navigateur.

⚠️ Un ecart n'est pas un defaut. Plusieurs sont des decisions deja prises
(controles de fenetre, selecteur de role de demonstration). Le rapport les
range en « assume » quand le code ou CLAUDE.md le dit, jamais par defaut.
"""
import html
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import association_ecrans as asso  # noqa: E402

RACINE, PROTO = asso.RACINE, asso.PROTO
ROLES = ('admin', 'caissier', 'animalier', 'comptable')


def lire(p):
    return io.open(p, encoding='utf-8', errors='ignore').read()


def decode(s):
    s = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), s)
    return s.replace('&amp;', '&').replace("\\'", "'")


# ───────────────────────── prototype : sidebar.js ───────────────────────────
def sidebar_proto():
    js = lire(PROTO + '/assets/js/sidebar.js')
    js = decode(js)
    debut = js.index('<aside id="sidebar"')
    fin = js.index('</nav>', debut)
    bloc = js[debut:fin]
    groupes = []
    for m in re.finditer(
            r'<div data-role-group="([^"]*)"><p[^>]*>([^<]*)</p>(.*?)</div></div>',
            bloc, re.S):
        roles = m.group(1).split(',')
        entrees = []
        for a in re.finditer(
                r'<a href="([^"]+)"[^>]*><span[^>]*>([a-z_0-9]+)</span>'
                r'<span[^>]*>([^<]*)</span></a>', m.group(3)):
            entrees.append({'page': a.group(1), 'icone': a.group(2),
                            'libelle': a.group(3).strip()})
        groupes.append({'titre': m.group(2).strip(), 'roles': roles,
                        'entrees': entrees})
    return groupes, js


# ───────────────────────── poste : main.dart ────────────────────────────────
def sidebar_poste():
    src = lire(RACINE + '/lib/main.dart')
    debut = src.index('static const arborescence')
    fin = src.index('];\n', debut)
    bloc = re.sub(r'//[^\n]*', '', src[debut:fin])
    groupes = []
    for m in re.finditer(r"\(\s*'([^']+)',\s*\[(.*?)\],\s*\),", bloc, re.S):
        entrees = []
        for e in re.finditer(
                r"\(\s*Icons\.(\w+),\s*'([^']+)',\s*EcranPoste\.(\w+),?\s*\)",
                m.group(2), re.S):
            entrees.append({'icone': e.group(1), 'libelle': e.group(2),
                            'ecran': e.group(3)})
        groupes.append({'titre': m.group(1), 'entrees': entrees})
    return groupes, src


# ───────────────────────── permissions ──────────────────────────────────────
def carte_rbac():
    src = lire(RACINE + '/lib/core/auth/permissions_poste.dart')
    debut = src.index('static const Map<String, List<String>?> carte')
    bloc = src[debut:src.index('};', debut)]
    res = {}
    for m in re.finditer(r"'(\w+)':\s*(null|\[(.*?)\])", bloc, re.S):
        res[m.group(1)] = None if m.group(2) == 'null' else \
            re.findall(r"'([a-z0-9-]+\.html)'", m.group(3))
    return res


def autorise(carte, role, page):
    if role not in carte:
        return True
    p = carte[role]
    return True if p is None else page in p


# ───────────────────────── fil d'Ariane ─────────────────────────────────────
def fil_proto(page):
    chemin = os.path.join(PROTO, page)
    if not os.path.exists(chemin):
        return None
    m = re.search(r'<header\b.*?</header>', lire(chemin), re.S)
    if not m:
        return None
    n = re.search(r'<nav class="hidden sm:flex[^>]*>(.*?)</nav>', m.group(0),
                  re.S)
    if not n:
        return None
    t = html.unescape(re.sub(r'<[^>]+>', ' ', n.group(1)))
    return ' '.join(t.split())


# ───────────────────────── rapport ───────────────────────────────────────────
def main():
    gp, js = sidebar_proto()
    gf, src = sidebar_poste()
    pages_enum = asso.enum_pages()
    carte = carte_rbac()
    L, w = [], None
    L = []
    w = L.append

    ecarts = []  # (gravite, zone, constat, preuve)

    def ecart(gravite, zone, constat, preuve):
        ecarts.append((gravite, zone, constat, preuve))

    w('# RAPPORT CHROME — barre latérale (1B) et barre supérieure (1C)')
    w('')
    w('Généré par `outils/audit_chrome.py` (ticket AF1.1). Sources : '
      '`prototype_html/assets/js/sidebar.js`, l\'en-tête `<header>` des pages '
      '(identique sur 97 pages), `common.js` §8 ; côté poste `lib/main.dart` '
      '(`_BarreLaterale.arborescence`), `lib/core/widgets/barre_superieure.dart`, '
      '`lib/core/auth/permissions_poste.dart`.')
    w('')
    w('> ⚠️ **Mesuré** = extrait des deux sources et comparé par programme. '
      '**Relevé** = valeur lue dans le source, jamais vue à l\'écran : aucun '
      'rendu n\'a été comparé (phase 1D, à faire avec un navigateur et le poste '
      'lancé). Gravité : *bloquant* = une tâche de l\'utilisateur est '
      'impossible ; *majeur* = un élément du prototype manque ou diffère '
      'structurellement ; *mineur* = écart de style.')
    w('')

    # ---- 1B.1 groupes et entrees
    w('## 1B.1 Groupes et entrées (mesuré)')
    w('')
    tp = [g['titre'] for g in gp]
    tf = [g['titre'] for g in gf if g['titre'] != 'POSTE']
    w('| | Prototype | Poste |')
    w('|---|---|---|')
    w('| groupes | %d | %d (+ `POSTE`, hors maquette, dit) |' % (len(tp), len(tf)))
    w('| entrées | %d | %d |' % (sum(len(g['entrees']) for g in gp),
                                   sum(len(g['entrees']) for g in gf
                                       if g['titre'] != 'POSTE')))
    w('| ordre des groupes | — | %s |' % (
        'identique' if tp == tf else 'DIFFÉRENT'))
    w('')
    w('| Groupe | Entrée | Icône proto | Icône poste | Page → écran | Verdict |')
    w('|---|---|---|---|---|---|')
    nb_ok = nb_ko = 0
    for g in gp:
        cible = next((x for x in gf if x['titre'] == g['titre']), None)
        for i, e in enumerate(g['entrees']):
            f = cible['entrees'][i] if cible and i < len(cible['entrees']) \
                else None
            probs = []
            icone_p = e['icone']
            icone_f = f['icone'] if f else '—'
            if not f:
                probs.append('entrée absente')
            else:
                if f['libelle'] != e['libelle']:
                    probs.append('libellé « %s »' % f['libelle'])
                if f['icone'] != e['icone']:
                    probs.append('icône')
                if pages_enum.get(f['ecran']) != e['page']:
                    probs.append('écran → %s' % pages_enum.get(f['ecran']))
            if probs:
                nb_ko += 1
                ecart('majeur', 'barre latérale', 'Entrée « %s » : %s' % (
                    e['libelle'], ', '.join(probs)), 'sidebar.js ↔ main.dart')
            else:
                nb_ok += 1
            w('| %s | %s | %s | %s | %s | %s |' % (
                g['titre'], e['libelle'], icone_p, icone_f,
                (f and pages_enum.get(f['ecran'])) or '—',
                '✔' if not probs else '✘ ' + ', '.join(probs)))
    w('')
    w('**%d entrées conformes, %d écarts.**' % (nb_ok, nb_ko))
    w('')

    # ---- 1B.2 visibilite par role
    w('## 1B.2 Visibilité par rôle (mesuré)')
    w('')
    w('Le prototype masque un GROUPE entier selon `data-role-group`. Le poste '
      'rend TOUS les groupes à tous les rôles et **estompe** les entrées que '
      '`PermissionsPoste` refuse (`embarque = ecrans.contains(ecran)`, '
      '`main.dart`) — décision du client consignée dans le docblock de '
      '`arborescence`.')
    w('')
    w('| Rôle | Groupes visibles (prototype) | Entrées visibles au prototype mais '
      'REFUSÉES par `RBAC_PAGE_MAP` | Entrées masquées au prototype mais '
      'AUTORISÉES |')
    w('|---|---|---|---|')
    contradictions = []
    for r in ROLES:
        vis = [g for g in gp if r in g['roles']]
        refus, autor = [], []
        for g in gp:
            for e in g['entrees']:
                a = autorise(carte, r, e['page'])
                v = r in g['roles']
                if v and not a:
                    refus.append(e['libelle'])
                if a and not v:
                    autor.append(e['libelle'])
        contradictions.append((r, refus, autor))
        w('| %s | %d / %d | %s | %s |' % (
            r, len(vis), len(gp), ', '.join(refus) or '—',
            ', '.join(autor) or '—'))
    w('')
    w('⚠️ **Le prototype porte deux représentations des droits qui ne '
      'coïncident pas** : la barre (`data-role-group`, par groupe) et '
      '`RBAC_PAGE_MAP` (par page). Un rôle voit des entrées que la carte lui '
      'refuse, et inversement. Ce n\'est pas un défaut du poste : c\'est une '
      'contradiction du prototype, à consigner avec les arbitrages de la '
      'phase 5 — **non tranchée ici**.')
    w('')
    ecart('majeur', 'barre latérale / RBAC',
          'Le poste ne MASQUE aucun groupe selon le rôle (il estompe). '
          'CLAUDE.md dit « the sidebar hides forbidden entries » : le code dit '
          'l\'inverse (décision client du docblock). À reconfirmer — la phrase '
          'de CLAUDE.md est fausse ou périmée.',
          'main.dart `arborescence` docblock ; CLAUDE.md § RBAC')

    # ---- 1B.3 elements non listes dans la barre
    w('## 1B.3 Éléments de `sidebar.js` autres que la liste (mesuré par '
      'recherche dans le source Dart)')
    w('')
    w('| Élément du prototype | Présent au poste | Gravité |')
    w('|---|---|---|')
    elements = [
        ('En-tête « Agri**ERP** » (ERP en `accent-yellow`) + sous-titre '
         '« Ferme École Olouwachegoun »',
         'Ferme École Olouwachegoun' in src.replace('É', 'É')
         and "'AgriERP'" not in src, 'mineur',
         "le poste écrit 'AgriERP' d'une seule couleur, sans sous-titre"),
        ('Bouton « Synchroniser » jaune en pied de barre',
         'SyncButton' in src, None, ''),
        ('Bloc utilisateur (nom + rôle en capitales)',
         'roleLibelle' in src, None, ''),
        ('Menu flottant droit (`right-floating-menu`, barre repliée)',
         'right-floating' in src or 'menu flottant' in src.lower(),
         'majeur',
         'barre repliée : le poste ne propose pas les 6 raccourcis'),
        ('Bouton rond « Accès rapide Élevage & Modules » + panneau de 10 '
         'raccourcis', 'Accès Rapide' in src or 'Accès rapide' in src,
         'majeur',
         'aucun accès rapide aux fiches d\'espèce hors « Gestion Élevage »'),
        ('Bouton rond « Visite guidée de cette page » (`startTourGuide`)',
         'Visite guidée' in src, 'majeur', 'absent, non documenté'),
    ]
    for lib, present, grav, note in elements:
        if grav is None:
            w('| %s | oui | — |' % lib)
            continue
        if present:
            w('| %s | oui | — |' % lib)
        else:
            w('| %s | **non** — %s | %s |' % (lib, note, grav))
            ecart(grav, 'barre latérale', lib + ' — ' + note, 'sidebar.js')
    w('')

    # ---- 1B.4 style
    def px(rx, texte, defaut='?'):
        m = re.search(rx, texte, re.S)
        return m.group(1) if m else defaut

    larg_f = px(r'return Container\(\s*width: (\d+),\s*color: AgriColors\.brandForest',
                src)
    w('## 1B.4 Dimensions et style (relevé — non rendu)')
    w('')
    w('| Propriété | Prototype (Tailwind → px) | Poste (source Dart) | Gravité |')
    w('|---|---|---|---|')
    lignes = [
        ('largeur de la barre', '`w-72` = 288', larg_f, 'majeur'
         if larg_f != '288' else None),
        ('taille du libellé d\'entrée', '`text-[13px]` = 13',
         'AgriTypography.xs = 13.6' if 'fontSize: AgriTypography.xs,\n'
         '                  fontWeight: selectionne' in src else '?', 'mineur'),
        ('icône d\'entrée', '`text-[20px]` = 20',
         px(r'Icon\(\s*icone,\s*size: (\d+)', src), 'mineur'),
        ('titre de groupe', '`text-[10px]` gras, `tracking-wider`, blanc/40',
         'fontSize 10, gras, letterSpacing 0.8, white38', 'mineur'),
        ('couleur du libellé', '`text-white/90`', 'white (100 %)', 'mineur'),
        ('padding d\'entrée', '`px-sm py-xs`', 'horizontal md, vertical 9',
         'mineur'),
        ('survol', '`hover:bg-white/10`', 'InkWell sans fond de survol',
         'mineur'),
    ]
    for p, a, b, g in lignes:
        w('| %s | %s | %s | %s |' % (p, a, b, g or '—'))
        if g:
            ecart(g, 'barre latérale', '%s : prototype %s, poste %s' % (p, a, b),
                  'sidebar.js ↔ main.dart')
    w('')

    # ---- 1C
    w('## 1C. Barre supérieure')
    w('')
    w('### 1C.1 Fil d\'Ariane, page par page (mesuré)')
    w('')
    w('Le prototype écrit « Groupe > Page » (casse normale) dans l\'en-tête de '
      'chaque page ; le poste l\'écrit `$groupe > $ecran` avec `groupe` pris '
      'tel quel dans `arborescence` — **en capitales**.')
    w('')
    w('| Page | Fil du prototype | Fil du poste | Verdict |')
    w('|---|---|---|---|')
    nb = n_casse = n_texte = 0
    lignes_fil = []
    for g in gf:
        if g['titre'] == 'POSTE':
            continue
        for e in g['entrees']:
            lignes_fil.append((pages_enum.get(e['ecran']),
                               '%s > %s' % (g['titre'], e['libelle'])))
    # Fiches d'espece : le poste les titre `PRODUCTION ÉLEVAGE & SOINS > <nom>`
    # (`_libelleFiche`, main.dart) sans qu'elles figurent dans la barre.
    fiches = dict(re.findall(r"EcranPoste\.(\w+) => '([^']+)'",
                             src[src.index('_libelleFiche'):]))
    for nom, lib in fiches.items():
        lignes_fil.append((pages_enum.get(nom),
                           'PRODUCTION ÉLEVAGE & SOINS > %s' % lib))
    for page, ff in lignes_fil:
        fp = fil_proto(page) if page else None
        nb += 1
        if fp == ff:
            v = '✔'
        elif fp and fp.lower() == ff.lower():
            v = '✘ casse'
            n_casse += 1
        else:
            v = '✘ texte'
            n_texte += 1
        w('| %s | %s | %s | %s |' % (page, fp or '—', ff, v))
    w('')
    w('**%d fils sur %d différents : %d par la seule casse, %d par le texte.**'
      % (n_casse + n_texte, nb, n_casse, n_texte))
    w('')
    # Le prototype se contredit lui-meme : un meme groupe de la barre y porte
    # plusieurs graphies dans les en-tetes de ses pages.
    graphies = {}
    for page, ff in lignes_fil:
        fp = fil_proto(page) if page else None
        if fp and ' > ' in fp:
            graphies.setdefault(ff.split(' > ')[0], set()).add(
                fp.split(' > ')[0])
    for groupe, g in sorted(graphies.items()):
        if len(g) > 1:
            w('⚠️ **Le prototype se contredit** : le groupe « %s » est écrit '
              '%s selon les pages. Aucune graphie du poste ne peut être '
              'fidèle à toutes — **arbitrage client**, non tranché ici.' % (
                  groupe, ' / '.join('« %s »' % x for x in sorted(g))))
            w('')
    if n_texte:
        ecart('majeur', 'barre supérieure',
              "Fil d'Ariane : %d pages sur %d portent un TEXTE différent du "
              'prototype (« Élevage & Soins » ≠ « PRODUCTION ÉLEVAGE & SOINS », '
              'libellés de page renommés, groupe absent sur Facturation / '
              'Administration / Comptabilité). Cause : le poste dérive le fil de '
              'la barre latérale (`_situation`, main.dart), or le prototype ne '
              "l'écrit pas depuis la barre." % (n_texte, nb),
              'en-tête <header> des pages ↔ main.dart `_situation`')
    if n_casse:
        ecart('mineur', 'barre supérieure',
              "Fil d'Ariane : %d pages ne diffèrent que par la casse" % n_casse,
              'idem')

    w('### 1C.2 Éléments de l\'en-tête (relevé + recherche dans le source)')
    w('')
    w('| Élément du prototype | Poste | Statut | Gravité |')
    w('|---|---|---|---|')
    bs = lire(RACINE + '/lib/core/widgets/barre_superieure.dart')
    h_f = px(r'height: (\d+),\s*padding: const EdgeInsets\.symmetric\(horizontal',
             bs)
    items = [
        ('Hauteur `h-16` = 64', 'height: %s' % h_f,
         'écart' if h_f != '64' else 'conforme',
         'mineur' if h_f != '64' else None),
        ('Bascule du menu `menu_open` 22 px, `text-outline`',
         'IconButton 20 px, brandForest', 'écart de style', 'mineur'),
        ('Recherche « Recherche globale ERP… » `w-64`, active',
         '220 px, **désactivée**, « Recherche (application web) »',
         'assumé (docblock : la recherche parcourt des écrans que le poste n\'a '
         'pas)', None),
        ('Pastille « Sync » jaune, icône qui tourne, toujours « Sync »',
         'verte au repos, jaune « Sync · n en attente » sinon',
         'assumé en partie : ajoute le compteur d\'attente (utile) mais change '
         'la couleur au repos', 'mineur'),
        ('Sélecteur de rôle, boutons de test des popups',
         'absents', 'exclus par CLAUDE.md (widgets de démonstration)', None),
        ('Cloche + badge rouge animé « 3 »',
         'cloche sans badge (aucun compteur : notifications côté serveur)',
         'assumé (docblock)', None),
        ('Menu déroulant de notifications (Toutes / Non lues, 4 lignes, '
         '« Voir toutes les notifications »)',
         'aucun : un SnackBar renvoie au web',
         'ÉCART — dépend du ticket `notifications` (phase 2)', 'majeur'),
        ('Menu profil « Administrateur ▾ » : Mon Profil · Aide & À Propos · '
         'Contactez l\'Éditeur · Paramètres · Déconnexion',
         'ABSENT (le nom d\'utilisateur est en pied de barre latérale)',
         'ÉCART — voir 1C.3', 'bloquant'),
        ('Commandes de fenêtre (réduire / fermer)', 'présentes',
         'ajout assumé (fenêtre sans cadre)', None),
    ]
    for a, b, c, g in items:
        w('| %s | %s | %s | %s |' % (a, b, c, g or '—'))
        if g:
            ecart(g, 'barre supérieure', a + ' → ' + b, 'header ↔ '
                  'barre_superieure.dart')
    w('')
    w('### 1C.3 La déconnexion n\'est branchée à rien')
    w('')
    w('`AuthService.deconnecter()` existe (`lib/core/auth/auth_service.dart:153`) '
      'et est testé (`test/auth_service_test.dart:261`), mais **aucun écran ne '
      'l\'appelle** — vérifié par recherche dans `lib/`. Sur un poste partagé '
      'par le caissier et l\'animalier, la seule façon de changer d\'utilisateur '
      'est de fermer l\'application. Le menu profil du prototype porte ce lien ; '
      'son absence est donc plus qu\'un écart de présentation.')
    w('')
    w('⚠️ À confirmer par un essai sur le poste lancé : je n\'ai fait que lire '
      'le source.')
    w('')

    # ---- synthese
    w('## Synthèse des écarts')
    w('')
    ordre = {'bloquant': 0, 'majeur': 1, 'mineur': 2}
    w('| Gravité | Zone | Constat | Source |')
    w('|---|---|---|---|')
    for g, z, c, p in sorted(ecarts, key=lambda x: ordre[x[0]]):
        w('| %s | %s | %s | %s |' % (g, z, c.replace('|', '/'), p))
    w('')
    n = {k: sum(1 for e in ecarts if e[0] == k) for k in ordre}
    w('**%d bloquant · %d majeur · %d mineur.**' % (n['bloquant'], n['majeur'],
                                                  n['mineur']))
    w('')
    return '\n'.join(L), n


if __name__ == '__main__':
    texte, n = main()
    io.open(os.path.join(RACINE, 'RAPPORT_CHROME.md'), 'w',
            encoding='utf-8').write(texte)
    print(n)
