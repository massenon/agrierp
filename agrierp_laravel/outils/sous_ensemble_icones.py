# -*- coding: utf-8 -*-
"""Reduit la fonte Material Symbols aux seules icones employees par l'application.

    python outils/sous_ensemble_icones.py            # releve + fabrication
    python outils/sous_ensemble_icones.py --verifier # controle seul, rien n'est ecrit

Pourquoi : la fonte complete pese 3,87 Mo pour 4271 icones, dont l'application
en emploie moins de 200. C'etait 94 % de la charge reseau de la page de
connexion (audit Lighthouse du 24/08/2026 : « Avoid enormous network payloads
— 4 136 Kio »). Le sous-ensemble tombe a ~37 Ko.

Prerequis : pip install fonttools brotli
"""
import glob
import io
import json
import os
import re
import subprocess
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPLETE = os.path.join(RACINE, 'resources/fonts/MaterialSymbolsOutlined-complete.woff2')
LISTE = os.path.join(RACINE, 'resources/fonts/icones-embarquees.json')
SORTIE = os.path.join(RACINE, 'public/assets/fonts/MaterialSymbolsOutlined.woff2')

# Les composants de ligature : un nom d'icone s'ecrit en toutes lettres.
ALPHABET = 'abcdefghijklmnopqrstuvwxyz0123456789_'


def catalogue(fonte):
    """Nom d'icone -> glyphe, lu dans la table de ligatures de la fonte.

    ⚠️ LES COMPOSANTS SE TRADUISENT PAR LA CMAP, JAMAIS PAR LEUR NOM DE
    GLYPHE. Le chiffre « 2 » a pour nom de glyphe « two » : concatener les
    noms donnerait « inventorytwo » au lieu de « inventory_2 », et « network »
    contient deja la suite t-w-o.

    ⚠️ LA CASSE NE COMPTE PAS : la fonte fait pointer « A » et « a » sur le
    meme glyphe, si bien que les noms ressortent en capitales.
    """
    inverse = {}
    for point, nom in fonte.getBestCmap().items():
        inverse.setdefault(nom, chr(point))

    trouves = {}

    def visiter(table):
        if table.__class__.__name__ == 'ExtensionSubst':
            visiter(table.ExtSubTable)
            return
        if not hasattr(table, 'ligatures'):
            return
        for premier, ligatures in table.ligatures.items():
            for ligature in ligatures:
                composants = [premier] + list(ligature.Component)
                if all(c in inverse for c in composants):
                    nom = ''.join(inverse[c] for c in composants).lower()
                    trouves[nom] = ligature.LigGlyph

    for lookup in fonte['GSUB'].table.LookupList.Lookup:
        for table in lookup.SubTable:
            visiter(table)

    return trouves


def icones_employees(connues):
    """Tout nom d'icone que l'application peut afficher.

    Trois sources, et la troisieme est un filet : une icone peut venir d'un
    litteral (`<span …>pets</span>`), d'un tableau PHP (`'icon' => 'egg'`) ou
    d'une expression que rien ne permet de suivre statiquement
    (`$species->icon`, un ternaire, une valeur en base). Le filet retient donc
    TOUT jeton du code qui se trouve etre un nom d'icone valide : quelques
    dizaines de glyphes en trop coutent moins qu'une icone manquante, qui
    s'afficherait a l'ecran sous la forme de son propre nom en toutes lettres.
    """
    fichiers = []
    for motif in ('resources/views/**/*.blade.php', 'app/**/*.php',
                  'resources/js/**/*.js', 'public/assets/js/**/*.js'):
        fichiers += glob.glob(os.path.join(RACINE, motif), recursive=True)

    span = re.compile(r'material-symbols-outlined[^>]*>(.*?)<', re.I | re.S)
    citee = re.compile(r"'([a-z0-9_]{2,40})'|\"([a-z0-9_]{2,40})\"")
    cle = re.compile(r"""icon['"]?\s*(?:=>|:|=)\s*['"]([a-z0-9_]{2,40})['"]""", re.I)
    jeton = re.compile(r'[a-z][a-z0-9_]{2,39}')

    retenues = set()
    for chemin in fichiers:
        texte = io.open(chemin, encoding='utf-8', errors='replace').read()
        for m in span.finditer(texte):
            contenu = m.group(1).strip()
            if re.fullmatch(r'[a-z0-9_]+', contenu):
                retenues.add(contenu)
            else:
                retenues |= {(a or b) for a, b in citee.findall(m.group(1))}
        retenues |= {m.group(1) for m in cle.finditer(texte)}
        retenues |= {m.group(0) for m in jeton.finditer(texte)}

    # Les icones stockees en base (`livestock_species.icon`,
    # `notifications.icon`) ne sont dans aucun fichier : elles arrivent par
    # `php artisan tinker`, injectees dans la liste versionnee.
    return {i for i in retenues if i in connues}


def fabriquer(noms, catalogue_icones, source):
    from fontTools import subset
    from fontTools.varLib import instancer

    cmap = source.getBestCmap()
    composants = {cmap[p] for c in ALPHABET
                  for p in (ord(c), ord(c.upper())) if p in cmap}

    options = subset.Options()
    options.layout_features = ['liga', 'clig', 'rlig', 'ccmp', 'calt']
    # ⚠️ SANS CECI LE SOUS-ENSEMBLE NE MAIGRIT PAS. La fermeture OpenType
    # rajoute tout glyphe atteignable par ligature depuis les lettres
    # retenues — c'est-a-dire les 4271 icones. Mesure : 3,0 Mo avec la
    # fermeture, 253 Ko sans.
    options.layout_closure = False
    options.name_IDs = ['*']
    options.notdef_outline = True

    reducteur = subset.Subsetter(options=options)
    reducteur.populate(glyphs=sorted(composants | {catalogue_icones[n] for n in noms}))
    reducteur.subset(source)

    # ⚠️ SEUL L'AXE `FILL` SERT DANS L'APPLICATION (etat actif du menu, voir
    # `layouts/app.blade.php`). Figer wght, GRAD et opsz a leur valeur par
    # defaut supprime leurs deltas `gvar` : 253 Ko -> 37 Ko. Retirer `FILL`
    # aussi casserait l'icone pleine de l'onglet courant.
    source = instancer.instantiateVariableFont(
        source, {'wght': 400, 'GRAD': 0, 'opsz': 24},
        inplace=True, updateFontNames=False)

    source.flavor = 'woff2'
    source.save(SORTIE)


def main():
    from fontTools.ttLib import TTFont

    verifier = '--verifier' in sys.argv

    complete = TTFont(COMPLETE)
    connues = catalogue(complete)

    versionnees = set(json.load(io.open(LISTE, encoding='utf-8')))
    employees = icones_employees(connues)

    absentes = sorted(employees - versionnees)
    if absentes:
        print('ICONES EMPLOYEES ET NON EMBARQUEES :', ', '.join(absentes))
        print("Ajoutez-les a resources/fonts/icones-embarquees.json puis "
              "relancez cet outil.")
        return 1

    print('icones du catalogue     :', len(connues))
    print('icones embarquees       :', len(versionnees))
    if verifier:
        embarquee = TTFont(SORTIE)
        presentes = set(catalogue(embarquee))
        manquantes = sorted(versionnees - presentes)
        print('icones dans la fonte    :', len(presentes))
        if manquantes:
            print('MANQUANTES DANS LA FONTE :', ', '.join(manquantes))
            return 1
        print('sous-ensemble conforme.')
        return 0

    fabriquer(versionnees, connues, complete)
    print('ecrit : %s (%.1f Ko, contre %.1f Ko pour la fonte complete)' % (
        os.path.relpath(SORTIE, RACINE),
        os.path.getsize(SORTIE) / 1024.0,
        os.path.getsize(COMPLETE) / 1024.0))
    return 0


if __name__ == '__main__':
    sys.exit(main())
