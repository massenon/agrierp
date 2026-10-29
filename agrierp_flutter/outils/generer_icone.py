# -*- coding: utf-8 -*-
"""Ticket ENV1 (demande 2) — l'icône de l'application : le logo de la ferme, en `.ico` multi-tailles.

    py outils/generer_icone.py             # écrit windows/runner/resources/app_icon.ico
    py outils/generer_icone.py --verifier  # contrôle seul : l'.ico du dépôt est-il celui que ce script produirait ?

Source : `assets/images/logo.png` (le même fichier que le poste affiche, jamais redessiné).
Sortie : `windows/runner/resources/app_icon.ico`, référencé par `windows/runner/Runner.rc` (`IDI_APP_ICON`, donc
icône de l'exécutable, de la fenêtre et de la barre des tâches, en production comme en `flutter run -d windows`)
et par `installer/agrierp.iss` (`SetupIconFile`, raccourcis, programme désinstallable).

Tailles : 16, 24, 32, 48, 64, 128 et 256 px.

  * Le logo n'est pas carré (424 x 391) : il est POSÉ au centre d'une toile carrée, jamais étiré. Les marges
    prennent la couleur de fond du logo (échantillonnée dans ses quatre coins, ici le blanc) pour que le
    carré de l'icône reste uniforme sur la barre des tâches, claire ou sombre.
  * Format écrit à la main plutôt que par `Image.save(..., format='ICO')` : Pillow encode toutes les entrées en
    PNG, que d'anciens `rc.exe` refusent. Ici, 256 px en PNG (seul cas toléré partout depuis Vista) et les
    autres tailles en BMP 32 bits (BGRA + masque AND), le format historique que tout compilateur de ressources lit.
  * Reproductible : mêmes entrées, mêmes octets (aucune date, aucun hasard).

Prérequis : pip install pillow
"""
import io
import os
import struct
import sys

from PIL import Image

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(RACINE, 'assets', 'images', 'logo.png')
ICONE = os.path.join(RACINE, 'windows', 'runner', 'resources', 'app_icon.ico')
TAILLES = (16, 24, 32, 48, 64, 128, 256)


def toile_carree(logo):
    """Pose le logo au centre d'une toile carrée de la couleur de ses coins : aucune déformation."""
    logo = logo.convert('RGBA')
    l, h = logo.size
    coins = [logo.getpixel(p) for p in ((0, 0), (l - 1, 0), (0, h - 1), (l - 1, h - 1))]
    fond = max(set(coins), key=coins.count)
    cote = max(l, h)
    toile = Image.new('RGBA', (cote, cote), fond)
    toile.alpha_composite(logo, ((cote - l) // 2, (cote - h) // 2))
    return toile


def entree_bmp(image):
    """Image BMP d'une icône : en-tête BITMAPINFOHEADER (hauteur doublée), pixels BGRA de bas en haut, masque AND."""
    n = image.size[0]
    pixels = image.convert('RGBA').load()
    xor = bytearray()
    for y in range(n - 1, -1, -1):
        for x in range(n):
            r, g, b, a = pixels[x, y]
            xor += bytes((b, g, r, a))
    ligne_masque = ((n + 31) // 32) * 4
    masque = bytes(ligne_masque * n)  # tout à 0 : l'opacité vient du canal alpha
    entete = struct.pack('<IiiHHIIiiII', 40, n, n * 2, 1, 32, 0, len(xor) + len(masque), 0, 0, 0, 0)
    return entete + bytes(xor) + masque


def entree_png(image):
    tampon = io.BytesIO()
    image.convert('RGBA').save(tampon, format='PNG', optimize=True)
    return tampon.getvalue()


def construire():
    with Image.open(LOGO) as logo:
        base = toile_carree(logo)
    donnees = []
    for t in TAILLES:
        redim = base.resize((t, t), Image.LANCZOS)
        donnees.append((t, entree_png(redim) if t == 256 else entree_bmp(redim)))
    sortie = bytearray(struct.pack('<HHH', 0, 1, len(donnees)))
    decalage = 6 + 16 * len(donnees)
    for t, d in donnees:
        sortie += struct.pack('<BBBBHHII', 0 if t == 256 else t, 0 if t == 256 else t, 0, 0, 1, 32, len(d), decalage)
        decalage += len(d)
    for _, d in donnees:
        sortie += d
    return bytes(sortie)


def memes_images(a, b, tolerance=2.0):
    """Même icône, à l'octet près OU presque : mêmes tailles et pixels décodés quasi identiques.

    L'encodage PNG (zlib) et le rééchantillonnage LANCZOS varient d'une version de Pillow à l'autre : comparer les
    octets rendait le contrôle rouge sur un autre poste alors que l'image était la même. L'écart moyen par canal
    doit rester sous `tolerance` (sur 255) ; un autre logo en donne des dizaines."""
    try:
        ia, ib = Image.open(io.BytesIO(a)), Image.open(io.BytesIO(b))
        if set(ia.info.get('sizes', ())) != set(ib.info.get('sizes', ())):
            return False
        for taille in sorted(ia.info['sizes']):
            pa = ia.ico.getimage(taille).convert('RGBA').tobytes()
            pb = ib.ico.getimage(taille).convert('RGBA').tobytes()
            if len(pa) != len(pb):
                return False
            if sum(abs(x - y) for x, y in zip(pa, pb)) / len(pa) > tolerance:
                return False
        return True
    except Exception:
        return False


def main():
    octets = construire()
    if '--verifier' in sys.argv:
        with open(ICONE, 'rb') as f:
            existant = f.read()
        ok = existant == octets or memes_images(existant, octets)
        print('app_icon.ico à jour' if ok else 'app_icon.ico DIFFÈRE : relancer outils/generer_icone.py')
        sys.exit(0 if ok else 1)
    with open(ICONE, 'wb') as f:
        f.write(octets)
    print(f'{ICONE} écrit ({len(octets)} octets, tailles {TAILLES})')


if __name__ == '__main__':
    main()
