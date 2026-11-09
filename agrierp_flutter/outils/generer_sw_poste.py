#!/usr/bin/env python3
"""PWA-2 — génère la liste de précache et la VERSION de `poste_sw.js` dans un build web du poste.

Usage : python3 outils/generer_sw_poste.py build/web

Lit le dossier construit, retient l'ENVELOPPE STATIQUE (code, moteur, polices, icônes, `index.html` statique, `sqlite3.wasm`,
`drift_worker.js`), calcule une VERSION (SHA-256 du contenu de ces fichiers) et remplace les deux marqueurs du gabarit
`poste_sw.js` copié par Flutter. Rien d'autre n'est précaché : aucune donnée, aucune page authentifiée.
"""
import hashlib
import json
import sys
from pathlib import Path

# Ne sont JAMAIS précachés : le service worker lui-même, le stub de Flutter (il se désinscrit), les rendus WebAssembly
# `skwasm`, `wimp`, `webparagraph` (le build JS standard ne les charge pas), les cartes de symboles et les fichiers de travail du build.
EXCLUS_NOMS = {"poste_sw.js", "flutter_service_worker.js", ".last_build_id"}
EXCLUS_FRAGMENTS = ("skwasm", "wimp", "webparagraph", ".symbols", ".map")


def retenu(rel: str) -> bool:
    nom = rel.rsplit("/", 1)[-1]
    if nom in EXCLUS_NOMS:
        return False
    return not any(f in rel for f in EXCLUS_FRAGMENTS)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    racine = Path(sys.argv[1]).resolve()
    gabarit = racine / "poste_sw.js"
    if not gabarit.is_file():
        print(f"poste_sw.js introuvable dans {racine} : le build web a-t-il tourné ?", file=sys.stderr)
        return 1

    fichiers = sorted(
        p.relative_to(racine).as_posix() for p in racine.rglob("*") if p.is_file() and retenu(p.relative_to(racine).as_posix())
    )
    manquants = [f for f in ("index.html", "main.dart.js", "flutter.js", "sqlite3.wasm", "drift_worker.js", "manifest.json") if f not in fichiers]
    if manquants:
        print(f"Enveloppe incomplète, il manque : {', '.join(manquants)}", file=sys.stderr)
        return 1

    h = hashlib.sha256()
    for f in fichiers:
        h.update(f.encode())
        h.update((racine / f).read_bytes())
    version = h.hexdigest()[:16]

    texte = gabarit.read_text(encoding="utf-8")
    if "@@VERSION@@" not in texte or "/*@@LISTE@@*/" not in texte:
        print("Les marqueurs @@VERSION@@ et /*@@LISTE@@*/ manquent dans poste_sw.js", file=sys.stderr)
        return 1
    texte = texte.replace("@@VERSION@@", version).replace("/*@@LISTE@@*/[]", json.dumps(fichiers, indent=0))
    gabarit.write_text(texte, encoding="utf-8")

    octets = sum((racine / f).stat().st_size for f in fichiers)
    print(f"poste_sw.js : version {version}, {len(fichiers)} fichiers précachés ({octets / 1_000_000:.1f} Mo)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
