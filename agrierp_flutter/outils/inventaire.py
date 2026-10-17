# -*- coding: utf-8 -*-
"""Extrait l'inventaire des libelles structurants d'une page du prototype.

Libelles retenus : titres (h2/h3), boutons, en-tetes de colonnes (th),
etiquettes de champs (label). Ce sont ceux qui portent le vocabulaire de
l'ecran — ceux qu'un portage ne doit jamais reformuler.
"""
import html
import io
import json
import os
import re
import sys

PROTO = r'C:/Projects/agrierp_laravel/prototype_html'

# Blocs de chrome partages par les 97 pages : barre laterale, barre
# superieure, menu de notifications, navigation basse. Ils ne font pas partie
# de l'ecran porte.
CHROME = re.compile(
    r'<(aside|nav)\b.*?</\1>|<header\b.*?</header>',
    re.S | re.I,
)

# ⚠️⚠️ LES BLOCS <script> SONT RETIRES AVANT TOUT RELEVE. Les pages
# construisent des lignes de tableau en JavaScript : leurs chaines portent
# des apostrophes ECHAPPEES et des valeurs de demonstration (un numero de
# vente, une date de Gantt). Les relever produirait un inventaire qui
# n'existe sur aucun ecran — et un controle qui echoue sur du bruit finit
# par etre ignore.
SCRIPTS = re.compile(r'<script\b.*?</script>', re.S | re.I)


def texte(fragment):
    """Texte visible d'un fragment HTML, balises et icones retirees."""
    # Les icones Material sont des ligatures : leur contenu textuel n'est pas
    # un libelle mais un nom d'icone.
    fragment = re.sub(
        r'<span[^>]*material-symbols-outlined[^>]*>.*?</span>', ' ',
        fragment, flags=re.S)
    fragment = re.sub(r'<[^>]+>', ' ', fragment)
    fragment = html.unescape(fragment)
    return ' '.join(fragment.split())


def libelles(chemin):
    brut = io.open(chemin, encoding='utf-8').read()

    # Le corps seul, chrome retire.
    corps = brut
    m = re.search(r'<body\b[^>]*>(.*)</body>', brut, re.S | re.I)
    if m:
        corps = m.group(1)
    corps = SCRIPTS.sub(' ', corps)
    corps = CHROME.sub(' ', corps)

    trouves = {'titres': [], 'boutons': [], 'colonnes': [], 'etiquettes': []}

    for balise, cle in (('h2', 'titres'), ('h3', 'titres'),
                        ('button', 'boutons'), ('th', 'colonnes'),
                        ('label', 'etiquettes')):
        for m in re.finditer(r'<%s\b[^>]*>(.*?)</%s>' % (balise, balise),
                             corps, re.S | re.I):
            t = texte(m.group(1))
            # Un libelle utile fait au moins deux caracteres et n'est pas un
            # gabarit de rendu (`${...}`).
            if len(t) >= 2 and '${' not in t and t not in trouves[cle]:
                trouves[cle].append(t)

    # ⚠️ LES EN-TETES DE DATE NE SONT PAS DES LIBELLES. Le Gantt du
    # calendrier veterinaire ecrit une colonne par jour — « 19/7 », « 20/7 »
    # — figees sur la semaine de demonstration. Les relever ferait echouer
    # le controle sur des DONNEES, et un controle qui echoue sur du bruit
    # finit par etre ignore.
    est_date = re.compile(r'^[0-9]{1,2}/[0-9]{1,2}$')
    for cle in trouves:
        trouves[cle] = [l for l in trouves[cle] if not est_date.match(l)]

    return trouves


if __name__ == '__main__':
    resultat = {}
    for page in sys.argv[1:]:
        resultat[page] = libelles(os.path.join(PROTO, page))

    print(json.dumps(resultat, ensure_ascii=False, indent=2))
