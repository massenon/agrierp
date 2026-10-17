# RAPPORT VISUEL — captures comparées (phase 1D)

Généré avec `test/capture_ecrans_test.dart` + `outils/captures.py` (ticket AF1.4). Images dans `build/audit/captures/` : `proto_*.png`, `poste_*.png`, `compare_*.png` (prototype à gauche).

> ⚠️ **Ce qui a été regardé à l'œil : 2 paires sur 19** (`dashboard` à 1280×720 et 1920×1080 ; `gestion-stocks` à 1280×720). Les 17 autres montages sont produits mais **non examinés** — ce rapport ne dit rien d'eux. Les données diffèrent (base vide au poste), les emoji sont absents du banc : ce ne sont pas des défauts.

## Constats vérifiés

| Gravité | Constat | Preuve |
|---|---|---|
| **bloquant** | **La barre latérale ne défile pas et déborde.** Contenu = 1 259 px de haut (débordement de 539 px à 720 px). À 1080 px, la barre est coupée après « Paramètres Général » : « Rapports & Exports », le groupe `POSTE` (**Synchronisation**, **Paramètres du poste**), le bouton **Synchroniser** et le bloc utilisateur sont hors fenêtre. En mode release le débordement est rogné, donc inatteignable. Ne tient qu'à partir de ~1 260 px de hauteur. | `poste_dashboard_1280x720.png`, `poste_dashboard_1920x1080.png`, `build/audit/alertes_capture.txt` |
| majeur | Pas de police Inter : le poste s'affiche en Segoe UI (voir `RAPPORT_JETONS.md` § 6). | capture (même rendu sur tous les écrans) |
| majeur | Entrées de la barre : pas de 39 px au poste contre 32 px au prototype — c'est l'une des causes du débordement. | `compare_dashboard.png` |
| majeur | Titres de groupe **centrés** au poste, alignés à gauche au prototype (`Column` en `crossAxisAlignment` centré). | `compare_dashboard.png` |
| majeur | Cartes d'indicateur de `gestion-stocks` : débordement de 10 px en bas (bande rouge et noire en debug) ; le prototype montre en plus le lien « Recalculer PMP » dans la première carte. | `compare_gestion_stocks.png`, alertes `écran gestion-stocks` |
| majeur | Barre latérale 240 px au lieu de 288 px (`w-72`). | `compare_dashboard.png` |
| mineur | En-tête de barre : « ERP » non jaune, pas de sous-titre « Ferme École Olouwachegoun », pas de filet de séparation. | idem |
| mineur | Entrée active : texte jaune (`accent-yellow`) au prototype, blanc gras au poste. | idem |
| mineur | Barre supérieure : 56 px au lieu de 64 px ; fil d'Ariane « PILOTAGE > Tableau de Bord » au lieu de « Tableau de Bord ». | idem + `RAPPORT_CHROME.md` |
| mineur | Valeur des cartes KPI : ~22 px au poste, plus grande (`md:text-2xl`) au prototype. | `compare_dashboard.png` |
| absent | Boutons ronds flottants « Accès rapide » et « Visite guidée ». | `RAPPORT_CHROME.md` § 1B.3 |

## Débordements relevés pendant les captures (Segoe UI, 1280×720)

`coque` 539 px (barre latérale) · `elevage-dashboard` 1 px · `gestion-stocks` 10 px (×3) · `soins-vaccins-hub` 14 px. Source : `build/audit/alertes_capture.txt`.

## Non fait

- Examen visuel des 17 autres paires, et à 1920×1080 pour les écrans autres que le tableau de bord.
- Comparaison avec des données (base peuplée).
- Contrôle manuel final par une personne sur le poste réellement lancé : **seul garant** que le débordement de la barre se produit bien en release (déduit ici du comportement de Flutter, non essayé sur l'exécutable).
