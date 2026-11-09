# Ressources de l'attestation (PDF)

Le PDF est produit par le serveur (`App\Services\AttestationService`, vue `resources/views/exports/attestation.blade.php`)
pour le web ET pour le poste : une seule fabrique, un seul visuel.

| Fichier | Rôle |
|---|---|
| `images/logo-ferme.png` | logo officiel de la ferme (= `public/assets/images/logo_ferme_ecole_officiel.png`), en-tête |
| `images/filigrane.png` | le même logo, fond transparent, opacité 26 % : filigrane central |
| `images/decor-floral.png` | décor floral des coins (haut droit, bord droit, bas gauche), extrait du modèle fourni par le client |
| `fonts/Caladea-*.ttf` | équivalent libre de Cambria (corps du texte) — licence Apache 2.0 |
| `fonts/Carlito-*.ttf` | équivalent libre de Calibri (date, numéro) — licence SIL OFL 1.1 |
| `fonts/Bevan-400.ttf` | slab serif gras du titre « FERME ÉCOLE OLOUWACHEGOUN » — licence SIL OFL 1.1 |
| `outils/extraire_decor.py` | script qui a produit `decor-floral.png` à partir de la capture du modèle (2000 × 1413) |

⚠️ Pour remplacer le décor ou le logo : remplacer le fichier PNG (même nom). Un décor extrait d'une capture est une
approximation : si le client fournit le modèle d'origine (Word / PDF), extraire les visuels de ce fichier.
