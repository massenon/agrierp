# -*- coding: utf-8 -*-
"""Releve la STRUCTURE d'une page du prototype, pas seulement son vocabulaire.

    python outils/structure.py liste-achats.html [autres.html...]

Le controle de vocabulaire (`inventaire.py`, ticket F0.42) verifie que chaque
mot du prototype existe dans l'ecran porte. Il ne dit rien de la STRUCTURE :
un tableau dont les colonnes sont dans le desordre, une colonne oubliee au
milieu, une carte d'indicateur en moins — tout cela passe, chaque mot pris
separement etant present quelque part.

Cet outil releve donc, par page :
  * la SUITE ORDONNEE des en-tetes de chaque tableau (`<thead><th>`) ;
  * le nombre de CARTES D'INDICATEUR (`border-l-4 border-l-<couleur>`) ;
  * la suite ordonnee des ONGLETS (`hub-tab-btn`).

⚠️ LES BLOCS <script> SONT RETIRES, comme pour l'inventaire : les pages
construisent des lignes en JavaScript, et leurs chaines ne sont pas des
en-tetes de colonnes.
"""
import io
import json
import os
import re
import sys

PROTO = r'C:/Projects/agrierp_laravel/prototype_html'

SCRIPTS = re.compile(r'<script\b.*?</script>', re.S | re.I)
CHROME = re.compile(r'<(aside|nav)\b.*?</\1>|<header\b.*?</header>', re.S | re.I)

# ⚠️⚠️ LE GABARIT DE CARTE EST `border-l-4` SUIVI DE SA COULEUR `border-l-<x>`,
# ET LA SECONDE MOITIE COMPTE (ticket F0.54).
#
# Le releve d'origine ne cherchait que `border-l-4`, en affirmant que ce gabarit
# etait unique dans toute la maquette. Il ne l'est pas : `bons-commande.html`
# emploie `border-l-4 border-brand-forest pl-sm` — sans `-l` sur la couleur —
# pour accentuer un GROUPE DE CHAMPS, « Date de Livraison Attendue ». Compte
# comme carte, il reclamait a l'ecran porte un indicateur qui n'existe pas.
#
# Verifie sur les 43 pages relevees : c'est le SEUL cas. L'affirmation d'origine
# etait donc juste a une page pres — et cette page suffisait a faire echouer un
# controle sur un ecran parfaitement conforme.
CARTE = re.compile(r'border-l-4\s+border-l-')


def texte(fragment):
    """Texte visible d'un fragment HTML, balises et icones retirees."""
    fragment = re.sub(
        r'<span[^>]*material-symbols-outlined[^>]*>.*?</span>', ' ',
        fragment, flags=re.S)
    fragment = re.sub(r'<[^>]+>', ' ', fragment)
    fragment = fragment.replace('&amp;', '&').replace('&nbsp;', ' ')
    fragment = fragment.replace('&eacute;', 'e').replace('&egrave;', 'e')
    return ' '.join(fragment.split())


def cellules(rangee):
    """Les `<th>` d'une rangee, avec leurs portees."""
    trouvees = []
    for cellule in re.finditer(r'<th\b([^>]*)>(.*?)</th>', rangee, re.S | re.I):
        attributs, contenu = cellule.group(1), cellule.group(2)
        largeur = re.search(r'colspan\s*=\s*["\']?(\d+)', attributs, re.I)
        hauteur = re.search(r'rowspan\s*=\s*["\']?(\d+)', attributs, re.I)
        t = texte(contenu)
        trouvees.append({
            # Une colonne d'action sans libelle existe (`<th></th>`) : elle
            # compte dans la structure, on la nomme pour pouvoir la comparer.
            'libelle': t if t else '(sans libelle)',
            'colspan': int(largeur.group(1)) if largeur else 1,
            'rowspan': int(hauteur.group(1)) if hauteur else 1,
        })
    return trouvees


def colonnes_feuilles(entete):
    """Suite des colonnes REELLES d'un en-tete, groupes aplatis.

    ⚠️⚠️ UN EN-TETE PEUT AVOIR DEUX NIVEAUX. La Balance Generale coiffe trois
    groupes (`colspan=2`) — Solde Ouverture, Mouvements Periode, Solde Final —
    d'une seconde rangee Debit/Credit, et garde deux colonnes pleine hauteur
    (`rowspan=2`). Concatener les deux rangees donnait ONZE colonnes pour HUIT
    reelles : le tableau conforme passait pour fautif, et un tableau fautif
    aurait pu passer pour conforme.
    """
    rangees = re.findall(r'<tr\b.*?</tr>', entete, re.S | re.I)
    if not rangees:
        return []

    premiere = cellules(rangees[0])
    seconde = cellules(rangees[1]) if len(rangees) > 1 else []

    if not seconde:
        return [c['libelle'] for c in premiere]

    feuilles = []
    reste = list(seconde)
    for cellule in premiere:
        if cellule['colspan'] > 1:
            # Le groupe cede la place a ses sous-colonnes.
            for _ in range(cellule['colspan']):
                if reste:
                    feuilles.append(reste.pop(0)['libelle'])
        else:
            feuilles.append(cellule['libelle'])

    feuilles.extend(c['libelle'] for c in reste)
    return feuilles


def structure(chemin):
    brut = io.open(chemin, encoding='utf-8', errors='replace').read()
    corps = CHROME.sub(' ', SCRIPTS.sub(' ', brut))

    tableaux = []
    for entete in re.finditer(r'<thead\b.*?</thead>', corps, re.S | re.I):
        colonnes = colonnes_feuilles(entete.group(0))
        if colonnes:
            tableaux.append(colonnes)

    cartes = len(CARTE.findall(corps))

    onglets = [texte(m.group(1)) for m in
               re.finditer(r'<button[^>]*hub-tab-btn[^>]*>(.*?)</button>',
                           corps, re.S | re.I)]

    return {'tableaux': tableaux, 'cartes': cartes, 'onglets': onglets,
            'cartes_par_panneau': panneaux(corps)}


# ⚠️⚠️ UN PANNEAU D'ONGLET EST UN FRERE DES AUTRES, JAMAIS UN IMBRIQUE. C'est
# ce qui permet de decouper sans analyser le HTML : le contenu d'un panneau va
# de sa balise ouvrante a celle du panneau suivant.
PANNEAU = re.compile(
    r'<div[^>]*id="([a-z0-9-]+)"[^>]*class="[^"]*tab-panel[^"]*"',
    re.I)


def panneaux(corps):
    """Cartes d'indicateur par panneau d'onglet, quand la page en a.

    ⚠️⚠️ POURQUOI CE RELEVE EXISTE (ticket F0.54). Certaines pages portent TOUS
    leurs onglets dans le MEME fichier — `elevage-dashboard.html` en a cinq.
    Le total de leurs cartes ne dit alors pas grand-chose : l'ecran porte peut
    en oublier quatre sur un onglet et en ajouter trois sur un autre, et la
    somme passerait a peu pres. C'est arrive : 11 cartes rendues contre 15
    relevees, alors que l'ecart REEL etait de -7 et +3 sur deux onglets
    differents.

    Un releve par panneau permet au controle de dire OU manque la carte.
    """
    reperes = list(PANNEAU.finditer(corps))
    if not reperes:
        return {}

    trouves = {}
    for i, m in enumerate(reperes):
        fin = reperes[i + 1].start() if i + 1 < len(reperes) else len(corps)
        trouves[m.group(1)] = len(CARTE.findall(corps[m.start():fin]))

    return trouves


if __name__ == '__main__':
    resultat = {}
    for page in sys.argv[1:]:
        resultat[page] = structure(os.path.join(PROTO, page))

    print(json.dumps(resultat, ensure_ascii=False, indent=2))
