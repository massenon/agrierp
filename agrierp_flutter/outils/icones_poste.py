# -*- coding: utf-8 -*-
"""Ticket H1 — les icônes du poste dans le style du web : Material Symbols Outlined.

    py outils/icones_poste.py               # fonte + classe SymbolesAgri, d'après les icônes employées
    py outils/icones_poste.py --remplacer   # en plus : Icons.x -> SymbolesAgri.y dans lib/ et test/
    py outils/icones_poste.py --verifier    # contrôle seul, rien n'est écrit

Pourquoi : le web affiche Material Symbols OUTLINED (`material-symbols-outlined`, FILL 0), le poste affichait
les Material Icons PLEINES de Flutter. Même nom, autre dessin : la même icône de menu n'avait pas la même
silhouette sur les deux surfaces.

Source : la fonte COMPLÈTE du web (`agrierp_laravel/resources/fonts/MaterialSymbolsOutlined-complete.woff2`),
lue par le `catalogue()` de `agrierp_laravel/outils/sous_ensemble_icones.py` (nom -> glyphe par les
ligatures). Le poste n'utilise pas les ligatures : il lui faut le POINT DE CODE de chaque glyphe, lu dans la
cmap. Sous-ensemble aux seules icônes employées, axes figés au réglage du web (`app.css` : FILL 0, wght 400,
GRAD 0, opsz 24). Le web ne remplit une icône que dans sa barre de navigation MOBILE, absente du poste.

Prérequis : pip install fonttools brotli
"""
import glob
import io
import os
import re
import sys

from chemins import LARAVEL, RACINE

sys.path.insert(0, os.path.join(LARAVEL, 'outils'))
from sous_ensemble_icones import catalogue  # noqa: E402

COMPLETE = os.path.join(LARAVEL, 'resources/fonts/MaterialSymbolsOutlined-complete.woff2')
FONTE = os.path.join(RACINE, 'assets/fonts/MaterialSymbolsOutlined.ttf')
CLASSE = os.path.join(RACINE, 'lib/core/theme/symboles_agri.dart')

# Noms Flutter sans équivalent direct dans Material Symbols.
RENOMMEES = {'info_outline': 'info'}

FLUTTER = re.compile(r'\bIcons\.([a-z_0-9]+)\b')
POSTE = re.compile(r'\bSymbolesAgri\.(?!famille\b)([a-z_0-9]+)\b')


def symbole(nom_flutter):
    """`Icons.check_circle_outlined` -> `check_circle` : le style vient de la fonte, pas du nom."""
    if nom_flutter in RENOMMEES:
        return RENOMMEES[nom_flutter]
    return re.sub(r'_(outlined|rounded|sharp)$', '', nom_flutter)


def sources():
    return [p for motif in ('lib/**/*.dart', 'test/**/*.dart')
            for p in glob.glob(os.path.join(RACINE, motif), recursive=True)
            if not p.endswith('symboles_agri.dart')]


def employees():
    flutter, poste = set(), set()
    for chemin in sources():
        # Les commentaires citent parfois `Icons.x` : seul le code compte.
        texte = '\n'.join(l.split('//')[0] for l in io.open(chemin, encoding='utf-8').read().splitlines())
        flutter |= set(FLUTTER.findall(texte))
        poste |= set(POSTE.findall(texte))
    return flutter, poste


def remplacer(connues):
    modifies = 0
    for chemin in sources():
        texte = io.open(chemin, encoding='utf-8').read()

        def un(m):
            nom = symbole(m.group(1))
            return 'SymbolesAgri.' + nom if nom in connues else m.group(0)

        neuf = FLUTTER.sub(un, texte)
        if neuf == texte:
            continue
        if 'symboles_agri.dart' not in neuf:
            relatif = os.path.relpath(CLASSE, os.path.dirname(chemin)).replace('\\', '/')
            cible = ("import 'package:agrierp/core/theme/symboles_agri.dart';"
                     if '/test/' in chemin.replace('\\', '/') else "import '%s';" % relatif)
            # Après le dernier import existant : `dart format` n'est jamais lancé sur un fichier entier.
            imports = list(re.finditer(r"^import [^\n]+;\n", neuf, re.M))
            pos = imports[-1].end() if imports else 0
            neuf = neuf[:pos] + cible + '\n' + neuf[pos:]
        io.open(chemin, 'w', encoding='utf-8', newline='\n').write(neuf)
        modifies += 1
    return modifies


def fabriquer(noms, cat, source):
    from fontTools import subset
    from fontTools.varLib import instancer

    cmap = source.getBestCmap()
    inverse = {}
    for point, glyphe in cmap.items():
        inverse.setdefault(glyphe, point)
    points = {n: inverse[cat[n]] for n in noms}

    options = subset.Options()
    options.layout_features = []
    options.name_IDs = ['*']
    options.notdef_outline = True
    reducteur = subset.Subsetter(options=options)
    reducteur.populate(unicodes=sorted(points.values()))
    reducteur.subset(source)
    source = instancer.instantiateVariableFont(
        source, {'FILL': 0, 'wght': 400, 'GRAD': 0, 'opsz': 24}, inplace=True, updateFontNames=False)
    # ⚠️ La source est un WOFF2 : sans ceci, `save` réécrit du WOFF2 sous l'extension .ttf, que Flutter ne lit pas.
    source.flavor = None
    os.makedirs(os.path.dirname(FONTE), exist_ok=True)
    source.save(FONTE)

    lignes = [
        '// GÉNÉRÉ par outils/icones_poste.py — ne pas éditer à la main.',
        '// ignore_for_file: constant_identifier_names',
        "import 'package:flutter/widgets.dart';",
        '',
        '/// Ticket H1 — icônes Material Symbols OUTLINED, le style du web (`material-symbols-outlined`, FILL 0).',
        '///',
        "/// ⚠️ N'employez plus `Icons.x` : même nom, dessin PLEIN, autre silhouette que le web. Un garde-fou",
        '/// (`test/symboles_agri_test.dart`) refuse `Icons.` dans `lib/`. Pour une icône nouvelle : l\'écrire',
        '/// `Icons.nom`, lancer `py outils/icones_poste.py --remplacer`.',
        'abstract final class SymbolesAgri {',
        "  static const famille = 'MaterialSymbolsOutlined';",
        '',
    ]
    for n in sorted(points):
        ident = n if not n[0].isdigit() else 'n' + n
        lignes.append('  static const IconData %s = IconData(0x%x, fontFamily: famille);' % (ident, points[n]))
    lignes.append('}')
    io.open(CLASSE, 'w', encoding='utf-8', newline='\n').write('\n'.join(lignes) + '\n')
    return points


def main():
    from fontTools.ttLib import TTFont

    complete = TTFont(COMPLETE)
    cat = catalogue(complete)
    flutter, poste = employees()
    noms = {symbole(n) for n in flutter} | poste
    absentes = sorted(n for n in noms if n not in cat)
    if absentes:
        print('ICÔNES SANS ÉQUIVALENT MATERIAL SYMBOLS :', ', '.join(absentes))
        print('Ajoutez-les à RENOMMEES dans cet outil.')
        return 1

    if '--verifier' in sys.argv:
        if flutter:
            print('Icons. encore employées :', ', '.join(sorted(flutter)))
        presentes = set(re.findall(r'IconData ([a-z_0-9]+) =', io.open(CLASSE, encoding='utf-8').read()))
        manquantes = sorted(n for n in noms if n not in presentes)
        if manquantes:
            print('MANQUANTES DANS SymbolesAgri :', ', '.join(manquantes))
            return 1
        print('icônes conformes :', len(noms))
        return 0

    points = fabriquer(noms, cat, complete)
    print('icônes :', len(points), '; fonte : %.1f Ko' % (os.path.getsize(FONTE) / 1024.0))
    if '--remplacer' in sys.argv:
        print('fichiers modifiés :', remplacer(set(points)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
