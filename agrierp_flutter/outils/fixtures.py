# -*- coding: utf-8 -*-
"""Ajoute des pages du prototype aux deux jeux d'epreuves des tests.

    python outils/fixtures.py rapports-exports.html rapport-tresorerie.html ...

⚠️⚠️ CE SCRIPT MANQUAIT, ET C'EST POURQUOI IL EXISTE. Les deux fichiers
`test/*_maquette.g.dart` portent depuis leur creation l'avertissement « NE PAS
EDITER A LA MAIN — regeneration : python outils/inventaire.py <pages...> ».
Mais `inventaire.py` et `structure.py` n'impriment que du JSON : personne ne
pouvait REELLEMENT regenerer les fichiers, et chaque ticket y a donc ajoute ses
pages a la main — exactement ce que l'en-tete interdit.

⚠️⚠️ **IL AJOUTE, IL NE REGENERE PAS — ET C'EST UN CONSTAT, PAS UN CHOIX DE
CONFORT.** Une regeneration complete des 39 pages deja presentes produit un
resultat DIFFERENT de ce qu'elles contiennent : les etiquettes de champ
(`<label>`) figurent pour certaines pages et pas pour d'autres — 77 dans le
fichier, 118 a la regeneration. Les epreuves ont donc ete constituees ticket
par ticket, avec des ajustements manuels non reproductibles.

Reconcilier les 39 pages avec leur source demanderait de reexaminer chaque
exemption de `fidelite_libelles_test` : **cela merite son propre ticket**, et
non un effet de bord d'un ticket qui porte un autre ecran. En attendant, ce
script garantit au moins que les pages NOUVELLES entrent sans etre tapees a la
main.
"""
import io
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import inventaire  # noqa: E402
import structure  # noqa: E402

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INVENTAIRE = os.path.join(RACINE, 'test', 'inventaire_maquette.g.dart')
STRUCTURE = os.path.join(RACINE, 'test', 'structure_maquette.g.dart')


def chaine(valeur):
    """Litteral Dart entre guillemets doubles, comme les fichiers existants.

    ⚠️ LE `$` EST ECHAPPE. Dart y voit une INTERPOLATION : la maquette ecrit
    « Lapines Reproductrices ($R_1..R_n$) », et le litteral non echappe ne
    compile pas — « Expected an identifier ». Le defaut ne se voit qu'a la
    generation, jamais a la lecture du HTML.
    """
    return json.dumps(valeur, ensure_ascii=False).replace('$', r'\$')


def lire(chemin):
    return io.open(chemin, encoding='utf-8').read()


def ecrire(chemin, contenu):
    io.open(chemin, 'w', encoding='utf-8', newline='\n').write(contenu)


def deja_presentes(source):
    return set(re.findall(r"'([a-z0-9-]+\.html)':", source))


def bloc_inventaire(page):
    trouves = inventaire.libelles(os.path.join(inventaire.PROTO, page))

    # L'inventaire est APLATI : titres, colonnes, boutons, etiquettes dans cet
    # ordre — celui des entrees deja en place.
    mots = []
    for cle in ('titres', 'colonnes', 'boutons', 'etiquettes'):
        for mot in trouves[cle]:
            if mot not in mots:
                mots.append(mot)

    lignes = ["  '%s': [\n" % page]
    lignes += ['    %s,\n' % chaine(m) for m in mots]
    lignes.append('  ],\n')
    return ''.join(lignes)


def ajouter_inventaire(pages):
    source = lire(INVENTAIRE)
    presentes = deja_presentes(source)

    ajouts = ''.join(bloc_inventaire(p) for p in pages if p not in presentes)
    if not ajouts:
        return 0

    # La derniere accolade ferme la table : on insere juste avant.
    coupe = source.rindex('};')
    ecrire(INVENTAIRE, source[:coupe] + ajouts + source[coupe:])
    return len([p for p in pages if p not in presentes])


def ajouter_structure(pages):
    source = lire(STRUCTURE)

    tete, _, queue = source.partition('const cartesMaquette = <String, int>{')
    presentes = deja_presentes(tete)

    tableaux = ''
    cartes = ''
    ajoutees = 0

    for page in pages:
        releve = structure.structure(os.path.join(structure.PROTO, page))

        # ⚠️ Une page SANS tableau n'entre pas dans `tableauxMaquette` : le hub
        # `rapports-exports.html` n'en porte aucun, et une entree vide ferait
        # echouer un controle sur une page qui n'a rien a controler.
        if releve['tableaux'] and page not in presentes:
            lignes = ["  '%s': [\n" % page]
            for colonnes in releve['tableaux']:
                lignes.append(
                    '    [%s],\n' % ', '.join(chaine(c) for c in colonnes))
            lignes.append('  ],\n')
            tableaux += ''.join(lignes)
            ajoutees += 1

        if ("'%s':" % page) not in queue:
            cartes += "  '%s': %d,\n" % (page, releve['cartes'])

    if tableaux:
        coupe = tete.rindex('};')
        tete = tete[:coupe] + tableaux + tete[coupe:]

    if cartes:
        # ⚠️ LA PREMIÈRE accolade fermante, pas la dernière. `queue` contient
        # aussi `cartesParPanneau`, plus bas : `rindex` y posait la page, avec
        # un entier là où la table attend une table (ticket F0.57 — le fichier
        # ne compilait plus).
        coupe = queue.index('\n};') + 1
        queue = queue[:coupe] + cartes + queue[coupe:]

    ecrire(STRUCTURE, tete + 'const cartesMaquette = <String, int>{' + queue)
    return ajoutees


if __name__ == '__main__':
    pages = sys.argv[1:]
    if not pages:
        print(__doc__)
        sys.exit(1)

    n1 = ajouter_inventaire(pages)
    n2 = ajouter_structure(pages)

    subprocess.call(
        ['dart', 'format', 'test/inventaire_maquette.g.dart',
         'test/structure_maquette.g.dart'],
        cwd=RACINE, shell=(os.name == 'nt'))

    print('%d page(s) ajoutee(s) a l inventaire, %d a la structure.' % (n1, n2))
