# -*- coding: utf-8 -*-
"""Ticket CONF-2 — l'icône de site PAR DÉFAUT : le logo officiel de la Ferme École OLOUWACHEGOUN.

    python3 outils/generer_favicon_ferme.py

Source : `public/assets/images/logo_ferme_ecole_officiel.png` (le logo officiel, jamais redessiné).
Sorties (dans `public/assets/images/`) : `favicon.ico` (16, 32, 48, 64 px, PNG intégrés) et `favicon-32.png`.
Méthode de `agrierp_flutter/outils/generer_icone.py` : le logo n'est pas carré, il est POSÉ au centre d'une toile
carrée de la couleur de ses coins, jamais étiré. Prérequis : pip install pillow.
"""
import os

from PIL import Image

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOSSIER = os.path.join(RACINE, 'public', 'assets', 'images')
LOGO = os.path.join(DOSSIER, 'logo_ferme_ecole_officiel.png')


def toile_carree(logo):
    logo = logo.convert('RGBA')
    l, h = logo.size
    coins = [logo.getpixel(p) for p in ((0, 0), (l - 1, 0), (0, h - 1), (l - 1, h - 1))]
    fond = max(set(coins), key=coins.count)
    cote = max(l, h)
    toile = Image.new('RGBA', (cote, cote), fond)
    toile.alpha_composite(logo, ((cote - l) // 2, (cote - h) // 2))
    return toile


def main():
    with Image.open(LOGO) as logo:
        base = toile_carree(logo)
    base.resize((256, 256), Image.LANCZOS).save(os.path.join(DOSSIER, 'favicon.ico'), format='ICO', sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
    base.resize((32, 32), Image.LANCZOS).save(os.path.join(DOSSIER, 'favicon-32.png'), format='PNG', optimize=True)
    print('favicon.ico et favicon-32.png écrits dans', DOSSIER)


if __name__ == '__main__':
    main()
