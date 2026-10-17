# -*- coding: utf-8 -*-
"""Phase 1D de AUDIT_FIDELISATION.md — captures comparees, prototype | poste.

    AUDIT_RENDU=1 flutter test test/capture_ecrans_test.dart --update-goldens
    py outils/captures.py            # prototype (Chrome headless) + montages

Produit, dans `build/audit/captures/` :
  proto_<page>.png     le prototype, 1280x720, rendu par Chrome headless
  poste_<page>.png     le poste, meme taille (ecrit par le banc Flutter)
  compare_<page>.png   les deux cote a cote, prototype a gauche

⚠️ CE QUE CES IMAGES PROUVENT, ET CE QU'ELLES NE PROUVENT PAS.
  * Elles montrent la MISE EN PAGE : alignements, dimensions, couleurs, ce qui
    est coupe ou deborde. C'est exactement ce que ni l'analyseur ni les tests de
    contenu ne voient.
  * Les DONNEES different (base vide au poste, jeu de demonstration au
    prototype, format de date) : ne pas les compter comme des ecarts.
  * Le banc rend sous la plateforme Windows avec Segoe UI et les icones Material
    du SDK — la police que le poste utilise reellement faute d'Inter embarquee.
    Les emoji manquent (case vide) : artefact du banc, pas du poste.
  * Chrome charge Tailwind et Inter depuis Internet : sans reseau, le prototype
    se rend sans style. Un montage dont la gauche est un texte brut signale cela.
"""
import io
import os
import subprocess
import sys

from PIL import Image, ImageDraw
from chemins import PROTO, RACINE  # A7 : chemins résolus, plus de C:/ en dur

SORTIE = RACINE + '/build/audit/captures'
CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'

PAGES = [
    'dashboard', 'gestion-elevage', 'elevage-dashboard', 'suivi-reproduction',
    'soins-vaccins-hub', 'parametres-elevage', 'ventes-devis',
    'creances-clients', 'achats-commandes', 'fournisseurs', 'saisie-depenses',
    'gestion-stocks', 'catalogue-produits', 'facturation', 'personnel-stages',
    'administration', 'comptabilite-hub', 'parametres-hub', 'rapports-exports',
    'mon-profil', 'notifications', 'aide-a-propos', 'contact-editeur',
    'bilan-technico-economique', 'rh-attestations', 'animal-details',
]


def capturer_proto(page, force=False):
    cible = '%s/proto_%s.png' % (SORTIE, page.replace('-', '_'))
    if os.path.exists(cible) and not force:
        return cible
    out = cible.replace('/', '\\')
    subprocess.run([
        CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars',
        '--window-size=1280,720', '--virtual-time-budget=8000',
        '--screenshot=' + out,
        'file:///%s/%s.html' % (PROTO, page)],
        capture_output=True, timeout=120)
    return cible


def montage(page):
    cle = page.replace('-', '_')
    a = '%s/proto_%s.png' % (SORTIE, cle)
    b = '%s/poste_%s.png' % (SORTIE, cle)
    if not (os.path.exists(a) and os.path.exists(b)):
        return None
    ia, ib = Image.open(a).convert('RGB'), Image.open(b).convert('RGB')
    h = max(ia.height, ib.height)
    m = Image.new('RGB', (ia.width + ib.width + 24, h + 28), (90, 90, 90))
    d = ImageDraw.Draw(m)
    d.text((8, 6), 'PROTOTYPE  ' + page, fill=(255, 255, 255))
    d.text((ia.width + 32, 6), 'POSTE FLUTTER  ' + page, fill=(255, 255, 255))
    m.paste(ia, (0, 28))
    m.paste(ib, (ia.width + 24, 28))
    sortie = '%s/compare_%s.png' % (SORTIE, cle)
    m.save(sortie)
    return sortie


if __name__ == '__main__':
    os.makedirs(SORTIE, exist_ok=True)
    force = '--force' in sys.argv
    pages = [p for p in sys.argv[1:] if not p.startswith('--')] or PAGES
    for p in pages:
        capturer_proto(p, force)
        r = montage(p)
        print('%-24s %s' % (p, 'OK' if r else 'poste_ manquant'))
