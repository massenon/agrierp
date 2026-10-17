# -*- coding: utf-8 -*-
"""Phase 3 de AUDIT_FIDELISATION.md — pages du prototype SANS AUCUN LIEN ENTRANT.

    py outils/pages_orphelines.py

Une page que ni une autre page, ni `sidebar.js`, ni aucun script ne nomme est
inatteignable depuis le prototype : on ne peut pas y arriver en cliquant. Ce n'est
pas une fonctionnalite a porter, c'est du code mort — et la compter dans un taux de
fidelite fait baisser le taux d'un ecran qui n'existe pas.

⚠️ POURQUOI CET OUTIL EXISTE. La phase 0 avait classe `tableau-stocks`,
`mouvement-stock` et `ajustements-stock` comme « onglets internes » de
`gestion-stocks.html`, d'apres une ligne du tableau Laravel. C'etait faux : les
onglets du hub sont des panneaux INLINE, et ces trois fichiers n'etaient liés par
personne (`CROISEMENT_ECRANS_INSTRUCTION.md` : « code mort confirme »). Le plan les
rangeait pourtant parmi les « ecrans partiels » a completer. La liste se CALCULE donc,
au lieu de se recopier.

⚠️ LIMITE : un lien construit dynamiquement (`'page-' + nom + '.html'`) echappe a
la recherche. Le resultat est une liste de CANDIDATES, confirmee ensuite par une
lecture — pas un verdict.
"""
import glob
import os
import re
from chemins import PROTO  # A7 : chemins résolus, plus de C:/ en dur



def sources():
    """{chemin relatif: texte} de tout ce qui peut nommer une page."""
    fichiers = (glob.glob(PROTO + '/*.html') + glob.glob(PROTO + '/assets/js/*.js')
                + glob.glob(PROTO + '/assets/css/*.css'))
    return {os.path.relpath(f, PROTO).replace('\\', '/'):
            open(f, encoding='utf-8', errors='ignore').read() for f in fichiers}


def liens_entrants(page, textes):
    """Fichiers (autres que la page elle-meme) qui citent son nom."""
    motif = re.compile(r'(?<![A-Za-z0-9_-])' + re.escape(page)
                       + r'(?![A-Za-z0-9_-])')
    return [f for f, t in textes.items() if f != page and motif.search(t)]


def orphelines():
    textes = sources()
    pages = sorted(os.path.basename(f) for f in glob.glob(PROTO + '/*.html'))
    return [p for p in pages if not liens_entrants(p, textes)]


def verifier():
    """Chaque page classee « zero lien entrant » l'est-elle ENCORE ?

    ⚠️ Une mise a jour du prototype peut relier une page jusque-la morte : elle
    redevient un ecran a porter, et le classement « hors perimetre » ment. Rend
    la liste des pages dont le motif promet l'orphelinat sans qu'il tienne.
    """
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from association_ecrans import HORS_PERIMETRE

    textes = sources()
    return [p for p, motif in HORS_PERIMETRE.items()
            if 'zéro lien entrant' in motif and liens_entrants(p, textes)]


if __name__ == '__main__':
    textes = sources()
    pages = sorted(os.path.basename(f) for f in glob.glob(PROTO + '/*.html'))
    orph = [p for p in pages if not liens_entrants(p, textes)]
    print('%d pages, %d sans aucun lien entrant :' % (len(pages), len(orph)))
    for p in orph:
        print('  ', p)

    menteurs = verifier()
    if menteurs:
        print()
        print('⚠️ CLASSEES « zero lien entrant » MAIS LIEES DEPUIS :', menteurs)
        raise SystemExit(1)
    print()
    print('Les pages classees « zero lien entrant » le sont toujours.')
