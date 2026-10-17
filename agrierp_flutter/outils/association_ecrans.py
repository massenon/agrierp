# -*- coding: utf-8 -*-
"""Associe chaque page du prototype a l'ecran Flutter qui la porte.

    python outils/association_ecrans.py          # tableau + pages sans ecran

Ticket AF1.0 (phase 0 de AUDIT_FIDELISATION.md). L'audit n° 1 tenait cette
association dans une table `EXTRA` ecrite a la main : 33 pages en restaient
sans ecran, et leur score etait calcule contre TOUT le code (plus generoux, donc
faux). Elle est desormais DEDUITE, et chaque association dit d'ou elle vient :

  enum     page de l'enum `EcranPoste` -> classe d'ecran de `main.dart` -> fichier
  hub      page chargee en `<iframe src=...>` par un hub deja associe
  carte    page citee par une carte de navigation du hub comptable
  hors-enum ecran hors menu (login) cite a la main, avec sa raison
  test     table `portages` de `test/fidelite_libelles_test.dart`
  parent   onglet INTERNE d'un ecran (le prototype garde un fichier, le portage
           n'en fait qu'un onglet) — table PARENTS ci-dessous, a justifier
  aucune   rien ne la porte : c'est un constat, pas un oubli de l'outil

⚠️ La priorite va de la plus fiable a la moins fiable. Une page peut cumuler
plusieurs sources : on les garde toutes, la plus fiable en tete.
"""
import glob
import io
import os
import re
import sys
from chemins import PROTO, RACINE  # A7 : chemins résolus, plus de C:/ en dur


# Pages sans objet pour un audit de fidelite (technique, publique, doublon).
HORS_PERIMETRE = {
    'index.html': 'page technique du prototype',
    'landing-page.html': 'page publique marketing',
    'welcome.html': 'page publique marketing',
    'logout.html': 'action seule, pas de vue',
    'comptabilite-hub_1.html': 'ancienne variante du hub',
    'fiche-volailles-pondeuses_old.html': 'ancienne variante de la fiche',
    # ⚠️ CODE MORT CONFIRMÉ (ticket F0.66) : aucun fichier — page, `sidebar.js`,
    # script ou feuille de style — ne les nomme (`outils/pages_orphelines.py`), et
    # la table de Laravel les range hors périmètre. La phase 0 les avait comptés
    # comme « onglets internes » d'un hub : un taux de fidélité mesuré sur des
    # écrans que personne ne peut ouvrir.
    'tableau-stocks.html': 'code mort : fusionné dans gestion-stocks.html (onglet '
                           '« Tableau & Valorisation »), zéro lien entrant',
    'mouvement-stock.html': 'code mort : fusionné dans gestion-stocks.html (onglet '
                            '« Journal des Mouvements »), zéro lien entrant',
    'ajustements-stock.html': 'code mort : fusionné dans gestion-stocks.html '
                              '(onglet « Ajustement / Correction »), zéro lien entrant',
    'rapport-recettes.html': 'orphelin : remplacé par rapport-recettes-depenses.html '
                             '(🚫 dans la table de Laravel), zéro lien entrant',
    'rapport-depenses.html': 'orphelin : remplacé par rapport-recettes-depenses.html '
                             '(🚫 dans la table de Laravel), zéro lien entrant',
}

# Onglets internes : le prototype garde un fichier HTML, le portage n'en fait
# qu'un onglet de l'ecran parent. Source : table de AUDIT_FIDELITE_94_ECRANS.md
# cote Laravel (« *(onglet interne)* » / « *(section interne)* »), recoupee avec
# la liste des `<iframe>` des hubs.
PARENTS = {
    'analyse-croissance.html': 'elevage-dashboard.html',
    'prevision-croissance.html': 'elevage-dashboard.html',
    'suivi-sanitaire-analyse.html': 'elevage-dashboard.html',
    'bilan-technico-economique.html': 'elevage-dashboard.html',
    'catalogue-view.html': 'catalogue-produits.html',
    'seuils-alerte.html': 'catalogue-produits.html',
    'animal-details.html': 'fiche-lapins.html',
    'profile-fournisseur.html': 'fournisseurs.html',
    'profile-client.html': 'creances-clients.html',
    'pos-interface.html': 'ventes-devis.html',
    'historique-ventes.html': 'ventes-devis.html',
    'devis.html': 'ventes-devis.html',
    'retours-avoirs.html': 'ventes-devis.html',
    'rapport-mensuel.html': 'rapports-exports.html',
    'rapport-bilan.html': 'comptabilite-hub.html',
    'enregistrer-sujets.html': 'gestion-elevage.html',
    'gestion-bandes.html': 'gestion-elevage.html',
    'transformation.html': 'gestion-elevage.html',
    'fiche-volailles.html': 'gestion-elevage.html',
}


def lire(chemin):
    return io.open(chemin, encoding='utf-8', errors='ignore').read()


def enum_pages():
    """{nom d'entree: page} depuis `EcranPoste`."""
    src = lire(RACINE + '/lib/core/auth/permissions_poste.dart')
    bloc = src.split('enum EcranPoste {', 1)[1].split('};', 1)[0] \
        if '};' in src else src
    bloc = re.sub(r'///[^\n]*', '', bloc)
    return {n: p for n, p in re.findall(r"(\w+)\('([a-z0-9-]+\.html)'\)", bloc)}


def classes_ecran():
    """{classe: fichier relatif} pour tous les `class XxxScreen`."""
    res = {}
    for f in glob.glob(RACINE + '/lib/**/*.dart', recursive=True):
        for c in re.findall(r'^class (\w+Screen)\b', lire(f), re.M):
            res[c] = os.path.relpath(f, RACINE).replace(os.sep, '/')
    return res


def routage():
    """{nom d'entree EcranPoste: classe d'ecran} depuis `main.dart`."""
    src = lire(RACINE + '/lib/main.dart')
    return dict(re.findall(r'EcranPoste\.(\w+)\s*=>\s*(\w+Screen)\(', src))


def fichiers_lies(fichier):
    """L'ecran et son depot (`x_screen.dart` -> `x_repository.dart`) s'il existe."""
    res = [fichier]
    depot = fichier.replace('_screen.dart', '_repository.dart')
    if depot != fichier and os.path.exists(os.path.join(RACINE, depot)):
        res.append(depot)
    return res


def enfants_iframe(page):
    chemin = os.path.join(PROTO, page)
    if not os.path.exists(chemin):
        return []
    corps = re.sub(r'<script\b.*?</script>', ' ', lire(chemin), flags=re.S | re.I)
    return list(dict.fromkeys(
        re.findall(r'<iframe[^>]*\bsrc="([a-z0-9-]+\.html)"', corps)))


def enfants_cartes(page):
    """Cartes de navigation d'un hub (hors chrome partage)."""
    chemin = os.path.join(PROTO, page)
    corps = lire(chemin)
    corps = re.sub(r'<script\b.*?</script>', ' ', corps, flags=re.S | re.I)
    corps = re.sub(r'<(aside|nav)\b.*?</\1>|<header\b.*?</header>', ' ',
                   corps, flags=re.S | re.I)
    return list(dict.fromkeys(
        re.findall(r'href="([a-z0-9-]+\.html)"', corps)))


def portages_test():
    """La table `portages` du test de fidelite."""
    src = lire(RACINE + '/test/fidelite_libelles_test.dart')
    debut = src.index('const portages')
    fin = src.index('};', debut)
    res = {}
    for page, corps in re.findall(
            r"'([a-z0-9-]+\.html)':\s*\[(.*?)\]", src[debut:fin], re.S):
        res[page] = re.findall(r"'(lib/[^']+)'", corps)
    return res


def associer():
    """{page: {'fichiers': [...], 'sources': [...], 'parent': str|None}}"""
    pages = sorted(os.path.basename(f) for f in glob.glob(PROTO + '/*.html'))
    pages = [p for p in pages if p not in HORS_PERIMETRE]
    res = {p: {'fichiers': [], 'sources': [], 'parent': None} for p in pages}

    def ajouter(page, fichiers, source, parent=None):
        if page not in res:
            return
        r = res[page]
        for f in fichiers:
            if f not in r['fichiers']:
                r['fichiers'].append(f)
        if source not in r['sources']:
            r['sources'].append(source)
        if parent and not r['parent']:
            r['parent'] = parent

    # 1. enum + routage
    classes, route = classes_ecran(), routage()
    for nom, page in enum_pages().items():
        cl = route.get(nom)
        if cl and cl in classes:
            ajouter(page, fichiers_lies(classes[cl]), 'enum')

    # 2. hubs : iframes puis cartes
    for hub in list(res):
        if not res[hub]['fichiers'] or 'enum' not in res[hub]['sources']:
            continue
        for enfant in enfants_iframe(hub):
            ajouter(enfant, res[hub]['fichiers'], 'hub', hub)
    if res.get('comptabilite-hub.html', {}).get('fichiers'):
        for enfant in enfants_cartes('comptabilite-hub.html'):
            ajouter(enfant, res['comptabilite-hub.html']['fichiers'], 'carte',
                    'comptabilite-hub.html')

    # 2b. ecrans hors menu (non listes dans l'enum, ouverts avant la barre)
    ajouter('login.html', ['lib/features/auth/login_screen.dart'], 'hors-enum')

    # 3. test de fidelite (le plus fin : il nomme le fichier exact)
    for page, fichiers in portages_test().items():
        ajouter(page, fichiers, 'test')

    # 4. onglets internes declares
    for page, parent in PARENTS.items():
        if parent in res and res[parent]['fichiers']:
            ajouter(page, res[parent]['fichiers'], 'parent', parent)

    return res


if __name__ == '__main__':
    a = associer()
    sans = [p for p, v in a.items() if not v['fichiers']]
    for p, v in a.items():
        print('%-40s %-14s %s' % (p, '+'.join(v['sources']) or 'AUCUNE',
                                   ', '.join(os.path.basename(f)
                                             for f in v['fichiers'])))
    print()
    print('%d pages, %d sans ecran : %s' % (len(a), len(sans), ', '.join(sans)))
