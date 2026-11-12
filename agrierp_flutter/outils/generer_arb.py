#!/usr/bin/env python3
"""
Génère agreerp_flutter/lib/l10n/app_fr.arb à partir des fichiers
agrierp_laravel/lang/fr/*.php.

Usage (depuis la racine du monorepo) :
    python agrierp_flutter/outils/generer_arb.py

Le script est MANUEL — il ne tourne pas automatiquement.
À relancer à chaque fois qu'une clé est ajoutée ou modifiée dans lang/fr/.
"""
import re
import json
import os
import sys
from pathlib import Path


def php_key_to_arb(php_key: str) -> str:
    """Convertit une clé PHP snake_case en camelCase ARB.

    Exemples :
        'titre_page'      → 'titrePage'
        'kpi_gmq_moyen'   → 'kpiGmqMoyen'
        'info_graphique'  → 'infoGraphique'
    """
    parts = php_key.split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def extraire_paires(contenu: str) -> list[tuple[str, str]]:
    """Extrait toutes les paires clé => valeur d'un tableau PHP imbriqué à un niveau.

    Gère :
    - Les valeurs entre guillemets simples  : 'clé' => 'valeur'
    - Les valeurs entre guillemets doubles  : 'clé' => "valeur"
    - Les apostrophes échappées (\')
    - Les tableaux imbriqués d'un niveau (les sous-clés sont préfixées par la clé parente)

    Limitation connue : les imbrications de plus d'un niveau ne sont pas gérées
    (aucun fichier ne les utilise à ce jour).
    """
    paires: list[tuple[str, str]] = []

    # Paires à plat : 'cle' => 'valeur' ou 'cle' => "valeur"
    motif_plat = (
        r"'([^']+)'\s*=>\s*"
        r"(?:'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\")"
    )
    for m in re.finditer(motif_plat, contenu):
        cle = m.group(1)
        valeur = m.group(2) if m.group(2) is not None else m.group(3)
        # Désechapper les séquences PHP courantes
        valeur = (
            valeur.replace("\\'", "'")
            .replace('\\"', '"')
            .replace("\\\\", "\\")
            .replace("\\n", "\n")
            .replace("\\t", "\t")
        )
        paires.append((cle, valeur))

    return paires


def lire_fichiers_php(dossier_lang: Path) -> dict[str, str]:
    """Lit tous les *.php de dossier_lang/fr/ et retourne {arb_key: valeur}.

    En cas de doublon (même clé dans plusieurs fichiers ou dans le même
    fichier), la DERNIÈRE occurrence l'emporte — comme en PHP.
    """
    resultat: dict[str, str] = {}

    fichiers = sorted(dossier_lang.glob("*.php"))
    if not fichiers:
        print(f"⚠️  Aucun fichier PHP trouvé dans {dossier_lang}", file=sys.stderr)
        return resultat

    for fichier in fichiers:
        with open(fichier, encoding="utf-8") as f:
            contenu = f.read()

        paires = extraire_paires(contenu)
        for cle_php, valeur in paires:
            cle_arb = php_key_to_arb(cle_php)
            resultat[cle_arb] = valeur

        print(f"  {fichier.name} : {len(paires)} paires lues")

    return resultat


def main() -> None:
    # Chemins relatifs à la racine du monorepo
    racine = Path(__file__).resolve().parent.parent.parent  # monorepo root
    dossier_lang = racine / "agrierp_laravel" / "lang" / "fr"
    sortie = racine / "agrierp_flutter" / "lib" / "l10n" / "app_fr.arb"

    if not dossier_lang.is_dir():
        print(f"Erreur : dossier introuvable : {dossier_lang}", file=sys.stderr)
        sys.exit(1)

    print(f"Lecture de {dossier_lang} …")
    cles = lire_fichiers_php(dossier_lang)

    if not cles:
        print("Aucune clé extraite — vérifiez les fichiers PHP.", file=sys.stderr)
        sys.exit(1)

    arb: dict[str, str] = {"@@locale": "fr"}
    arb.update(cles)

    sortie.parent.mkdir(parents=True, exist_ok=True)
    with open(sortie, "w", encoding="utf-8") as f:
        json.dump(arb, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"\n✓ {len(cles)} clés ARB écrites dans {sortie}")


if __name__ == "__main__":
    main()
