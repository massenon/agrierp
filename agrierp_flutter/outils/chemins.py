"""Ticket A7 — chemins du dépôt pour les outils, résolus comme `test/chemins_depot.dart`.

Ordre : variable d'environnement (`AGRIERP_LARAVEL`, `AGRIERP_PROTOTYPE`), puis le monorepo, puis
l'ancien emplacement Windows du développeur. Le premier dossier existant gagne.
"""
import os

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace('\\', '/')
_MONOREPO = os.path.dirname(RACINE)


def _premier(variable, candidats):
    impose = os.environ.get(variable)
    if impose:
        return impose
    for c in candidats:
        if os.path.isdir(c):
            return c
    return candidats[0]


LARAVEL = _premier('AGRIERP_LARAVEL', [_MONOREPO + '/agrierp_laravel', 'C:/laragon/www/agrierp'])
PROTO = _premier('AGRIERP_PROTOTYPE', [
    _MONOREPO + '/prototype_html', 'C:/Projects/agrierp_laravel/prototype_html',
])
