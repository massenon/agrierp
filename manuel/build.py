# -*- coding: utf-8 -*-
"""
Construit le manuel d'utilisation AgriERP au format PDF.

  1. assemble src/part*.html
  2. sépare la couverture (impression pleine page, sans en-tête ni pied)
  3. applique deux corrections typographiques automatiques :
       - les encadrés longs sont autorisés à se couper entre deux pages
       - les sections courtes sont regroupées pour ne pas laisser un
         paragraphe orphelin en tête de page
  4. imprime les deux parties via Chrome, puis les fusionne et reconstruit
     les signets du PDF
"""
import io
import os
import re
import subprocess

RACINE = os.path.dirname(os.path.abspath(__file__))
os.chdir(RACINE)

# ---------------------------------------------------------------- assemblage
parts = [io.open('src/part%d.html' % i, encoding='utf-8').read() for i in range(7)]
html = '\n'.join(parts)

style_fin = html.index('</style>') + len('</style>')
entete_html = html[:style_fin]
corps = html[style_fin:]

# ---------------------------------------------------------------- couverture
m = re.search(r'<div class="couverture">.*?\n</div>', corps, re.S)
if not m:
    raise SystemExit('couverture introuvable')
couverture = m.group(0).replace('break-after:page;', '')
corps = corps[:m.start()] + corps[m.end():]

# ------------------------------------------- encadrés longs : coupure permise
def marquer_notes(txt):
    n = [0]

    def rempl(mo):
        bloc = mo.group(0)
        texte = re.sub(r'<[^>]+>', '', bloc)
        if len(texte) > 430 and 'longue' not in mo.group(1):
            n[0] += 1
            return bloc.replace('class="note ' + mo.group(1) + '"',
                                'class="note ' + mo.group(1) + ' longue"', 1)
        return bloc

    out = re.sub(r'<div class="note (\w+)">.*?</div></div>', rempl, txt, flags=re.S)
    print('  encadres longs rendus secables : %d' % n[0])
    return out

corps = marquer_notes(corps)

# ------------------------------------ sections courtes : regroupées (orphelins)
BLOC = re.compile(r'(?s)(<h2>.*?)(?=<h2>|</section>)')

def grouper(txt):
    n = [0]

    def rempl(mo):
        bloc = mo.group(1)
        # jamais de regroupement s'il contient une figure ou un tableau :
        # le bloc serait trop haut et créerait un vide plus grand encore.
        if '<figure' in bloc or '<table' in bloc:
            return bloc
        nu = re.sub(r'<[^>]+>', '', bloc)
        if len(nu) > 450:
            return bloc
        n[0] += 1
        return '<div class="groupe">' + bloc + '</div>'

    out = BLOC.sub(rempl, txt)
    print('  sections courtes regroupees      : %d' % n[0])
    return out

corps = grouper(corps)


# ---------------------------- renumérotation automatique des figures
def renumeroter_figures(txt):
    """Renumérote « Figure N.M » dans l'ordre d'apparition, chapitre par chapitre."""
    chapitre = [None]
    compteur = [0]
    total = [0]

    def rempl(mo):
        if mo.group(1):                      # début d'un chapitre
            chapitre[0] = mo.group(1)
            compteur[0] = 0
            return mo.group(0)
        compteur[0] += 1
        total[0] += 1
        num = chapitre[0] if chapitre[0] and chapitre[0].isdigit() else mo.group(2)
        return '<b>Figure %s.%d</b>' % (num, compteur[0])

    motif = re.compile(r'<div class="ch-num">([^<]+)</div>|<b>Figure (\d+)\.\d+</b>')
    out = motif.sub(rempl, txt)
    print('  figures renumerotees             : %d' % total[0])
    return out


corps = renumeroter_figures(corps)

io.open('couverture.html', 'w', encoding='utf-8').write(entete_html + couverture)
io.open('corps.html', 'w', encoding='utf-8').write(entete_html + corps)
io.open('manuel.html', 'w', encoding='utf-8').write(entete_html + couverture + corps)
print('  HTML assemble : %d octets' % len(entete_html + couverture + corps))

# ---------------------------------------------------------------- impression
subprocess.run(['php', os.path.join(RACINE, 'imprimer.php')], check=True)

# ------------------------------------------------------- fusion + signets
import pymupdf  # noqa: E402

cov = pymupdf.open('out_couverture.pdf')
cor = pymupdf.open('out_corps.pdf')
toc = cor.get_toc()

doc = pymupdf.open()
doc.insert_pdf(cov)
doc.insert_pdf(cor)
doc.set_toc([[lvl, titre, page + cov.page_count] for lvl, titre, page in toc])
doc.set_metadata({
    'title': "AgriERP — Manuel d'utilisation",
    'author': 'Dr MASSENON Rhodes, Docteur en Génie Logiciel et IA',
    'subject': "Manuel d'utilisation d'AgriERP — Ferme École Olouwachegoun. Maîtrise d'ouvrage : PAEB. Accompagnement : Cabinet FAGUEZ SARL. Éditeur : Dr MASSENON Rhodes.",
    'keywords': 'AgriERP, manuel, élevage, ventes, stocks, comptabilité, Bénin, PAEB, Cabinet FAGUEZ SARL, MASSENON Rhodes',
})
cible = os.path.join(os.path.dirname(RACINE), 'Manuel_Utilisation_AgriERP.pdf')
doc.save(cible, garbage=4, deflate=True)
print('\nPDF : %s' % cible)
print('      %d pages, %d signets, %.2f Mo'
      % (doc.page_count, len(toc), os.path.getsize(cible) / 1048576))
