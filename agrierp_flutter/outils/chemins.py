"""OBSOLÈTE depuis le 09/11/2026 : la maquette HTML n'existe plus ; outil conservé pour mémoire.

Ticket A7 — chemins du dépôt pour les outils, résolus comme `test/chemins_depot.dart`.

`LARAVEL` reste valable : variable d'environnement `AGRIERP_LARAVEL`, puis le monorepo, puis l'ancien
emplacement Windows du développeur (le premier dossier existant gagne).

`PROTO` (dossier `prototype_html/`) n'est plus une source : la maquette est retirée du projet (décision du
client, ticket A8) et la vue Blade du web fait seule foi. Le nom reste importable pour les outils conservés,
mais son accès s'arrête avec un message explicite si le dossier est absent.
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


def __getattr__(nom):
    """`PROTO` est résolu à la demande : un outil qui n'en a pas besoin n'échoue pas à l'import."""
    if nom == 'PROTO':
        proto = _premier('AGRIERP_PROTOTYPE', [
            _MONOREPO + '/prototype_html', 'C:/Projects/agrierp_laravel/prototype_html',
        ])
        if not os.path.isdir(proto):
            raise SystemExit(
                "Maquette HTML introuvable (%s) : OBSOLÈTE depuis le 09/11/2026, la maquette "
                "`prototype_html/` est retirée du projet (décision du client, ticket A8). Cet outil ne "
                "peut plus s'exécuter ; la référence de fidélité est la vue Blade du web."
                % proto)
        return proto
    raise AttributeError(nom)
