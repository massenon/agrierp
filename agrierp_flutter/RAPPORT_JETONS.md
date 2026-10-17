# RAPPORT JETONS — design tokens et valeurs en dur (phase 1D, partie mesurable)

Généré par `outils/audit_jetons.py` (ticket AF1.3). **Aucun rendu** : comparaison de sources. Ne dit rien de l'alignement.

## 1. Couleurs (`tailwind-config.js` ↔ `AgriColors`)

| Jeton | Prototype | Poste | Verdict |
|---|---|---|---|
| brand-forest | #052E16 | #052E16 | ✔ |
| brand-forest-dark | #00210D | #00210D | ✔ |
| brand-emerald | #065F46 | #065F46 | ✔ |
| accent-yellow | #FFD55F | #FFD55F | ✔ |
| error-red | #DC2626 | #DC2626 | ✔ |
| error-deep | #BA1A1A | #BA1A1A | ✔ |
| error-bg | #FFDAD6 | #FFDAD6 | ✔ |
| info-blue | #2563EB | #2563EB | ✔ |
| surface-bg | #F8F9FA | #F8F9FA | ✔ |
| surface-card | #FFFFFF | #FFFFFF | ✔ |
| surface-zebra | #F3F4F5 | #F3F4F5 | ✔ |
| outline-variant | #BEC9C2 | #BEC9C2 | ✔ |
| outline | #6F7973 | #6F7973 | ✔ |
| on-surface | #191C1D | #191C1D | ✔ |

**14 / 14 couleurs identiques.** Couleurs du poste absentes du prototype : aucune.

## 2. Espacements (`spacing`) et rayons (`borderRadius`)

| Jeton | Prototype (px) | Poste | Verdict |
|---|---|---|---|
| spacing.xs | 4 | 4 | ✔ |
| spacing.sm | 8 | 8 | ✔ |
| spacing.md | 16 | 16 | ✔ |
| spacing.lg | 24 | 24 | ✔ |
| spacing.xl | 32 | 32 | ✔ |
| spacing.2xl | 48 | 48 | ✔ |
| borderRadius.lg | 8 (0.5rem) | 8 | ✔ |
| borderRadius.xl | 12 (0.75rem) | 12 | ✔ |

## 3. Tailles de police : celles du prototype

Tailles distinctes utilisées par le prototype (échelle Tailwind avec la surcharge `text-xs` = 13,6 px, plus les `text-[Npx]` arbitraires) : **8, 9, 10, 11, 12, 13, 13.6, 14, 15, 16, 18, 20, 22, 24, 26, 28, 30, 36, 40, 44**.

## 4. Tailles de police écrites en dur qui n'existent PAS dans le prototype

`conformite_portage_test.dart` n'en verrouille que trois (12, 12.5, 13). Les autres passent sans bruit.

| Taille | Occurrences | Fichiers |
|---|---|---|
| 9.5 | 5 | fiche_escargots_screen.dart (1), fiche_lapins_screen.dart (1), fiche_pondeuses_screen.dart (1), fiche_porcs_screen.dart (1), fiche_reproducteurs_screen.dart (1) |
| 10.5 | 19 | tableau_mensuel.dart (1), saisie_depenses_screen.dart (1), fiche_escargots_screen.dart (4), fiche_lapins_screen.dart (3), fiche_pondeuses_screen.dart (3), fiche_porcs_screen.dart (3) … |
| 11.5 | 7 | barre_superieure.dart (1), fiche_escargots_screen.dart (1), fiche_lapins_screen.dart (1), fiche_pondeuses_screen.dart (2), fiche_porcs_screen.dart (1), fiche_reproducteurs_screen.dart (1) |
| 32 | 1 | synchronisation_screen.dart (1) |
| 90 | 1 | document_officiel.dart (1) |

Au total 334 tailles écrites en dur, dont 33 hors prototype.

## 5. Couleurs écrites en dur hors `agri_tokens.dart`

| Valeur | Occurrences | Fichiers | Classe Tailwind du prototype |
|---|---|---|---|
| `Color(0xFFF59E0B)` | 2 | fiche_pondeuses_screen.dart | `amber-500` (6 emplois dans le prototype) ✔ |
| `Color(0x99000000)` | 1 | modale_agri.dart | `bg-black/60` (4 emplois dans le prototype) ✔ |
| `Color(0x80000000)` | 1 | modale_agri.dart | `bg-black/50` (138 emplois dans le prototype) ✔ |
| `Color(0xFFB45309)` | 1 | fiche_pondeuses_screen.dart | `amber-700` (3 emplois dans le prototype) ✔ |
| `Color(0xFF78350F)` | 1 | fiche_pondeuses_screen.dart | `amber-900` (3 emplois dans le prototype) ✔ |

## 6. Police de caractères

| | Valeur |
|---|---|
| police du prototype | **Inter**, graisses 400, 500, 600, 700, 800 (Google Fonts) |
| jeton du poste | `AgriTypography.famille` = 'Inter' |
| emplois du jeton dans `lib/` | **0** |
| section `fonts:` dans `pubspec.yaml` | **non** |
| Inter installée dans `C:\Windows\Fonts` | non (Segoe UI seule) |

⚠️ **Le jeton est déclaré mais jamais appliqué, et la police n'est pas embarquée** : le poste s'affiche dans la police système de Windows, pas en Inter. Aucun test ni analyseur ne peut le voir — c'est un défaut de rendu pur, présent sur **tous** les écrans. Il change aussi la largeur du texte, donc les débordements et les retours à la ligne.

## Synthèse

**0 bloquant · 1 majeur · 5 mineur.**
