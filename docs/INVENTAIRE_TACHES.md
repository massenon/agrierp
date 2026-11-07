# Inventaire des tâches réalisées (toutes conversations) — au 07/11/2026

État : tout est commité et poussé sur `claude/sleepy-dijkstra-uvt68t`. Dernières suites complètes : Laravel 2977 verts, Flutter 4055 verts (18 sautés).

## 1. Hygiène et socle
- G : `agrierp_db.sql` retiré du dépôt et de tout l'historique (hash et jetons) ; `.env.production.example` créé.
- E7 / A7 : chemins de tests (`AGRIERP_LARAVEL`, `AGRIERP_PROTOTYPE`), script `build_windows.bat`, installateur Inno Setup.
- H1, K1, K8 : directive de fidélité absolue web ↔ poste, menu du compte, titre, ruban, icônes Material Symbols.
- H6 : directive de clonage local. K7 : registre, plan, points ouverts.
- S-T1 à S-T12 : méthode TATACORA (essai à cinq postes, curseur serveur, interblocages, fuseaux, inventaires).
- Blueprint réutilisable de synchronisation multi-postes (`docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md`).

## 2. Élevage
- E1 transfert entre bandes ; E3 sélecteur de bande ; E4 glossaire Lapins ; H2 glossaires des autres espèces.
- I1 dons sur toutes les fiches ; I2 sections des deux côtés ; EL-1 Transformation (web puis poste).
- H3 règle du rappel des soins ; H8/H8b infirmerie et calendrier ; H9/H9b Paramètres Élevage ; POP1–4 fenêtre « Rappels du jour ».
- Traitements sans saillie ; estimation automatique du poids ; Gestion Bandes (boutons sur une ligne).
- VOL-1 Volailles Reproducteurs : effectif par catégorie calculé (Reproducteur / Jeune / Poussin), départ obligatoire, ventes et rations par catégorie.
- VOL-2 Volailles Pondeuses : quatre stades (Poussin ponte, Poussin en croissance, Poulette, Pondeuse), trois passages, produit « Poussin d'un jour (ponte) », rations 130/80/30 confirmées, migrations vérifiées sur MariaDB.

## 3. Ventes, achats, stocks
- VC-1 encaisser une créance ; VC-2/VC-3 relances et profil client ; VC-4 modifier/archiver une avance ; VC-5 MeCeF désactivé (facturation conservée).
- AV1/AV2 avoirs et retours ; DEV devis ; AC-1 à AC-4 achats (bons de commande, +fournisseur/+produit, justificatifs, dettes).
- ST-1/ST-2 archiver un produit, seuils d'alerte ; H14 stock négatif ; achats : catégorie « Autre », date, recherche, filtre, montants payé/total/dette.
- Ventes-Devis : panier réorganisé ; doublons de catégories supprimés.

## 4. Comptabilité et exercices
- CP-1 à CP-5 : plan comptable, écritures manuelles, immobilisations, clôture d'exercice, rapprochement bancaire au poste.
- DEP1–DEP5 dépenses multilignes ; U13/U14 dépenses et paie ; AUT-1 PDF du rapprochement.
- EX1–EX8 bascule et clôture d'exercice (N / N-1 / N+1, lecture seule) ; H4 réouverture d'un exercice.
- Hub Comptabilité : douze cartes identiques web et poste ; Bilan de l'Entreprise et Balance Âgée portés au poste ; période du tableau de bord modifiable (web + poste).

## 5. RH, utilisateurs, sécurité
- RH-1 à RH-4 registres, pointage, paie ; RH-Q1 à Q3 ; UT-1 utilisateurs au poste.
- MDP-1 : plus de « Mot de passe oublié ? », réinitialisation par l'administrateur, code de secours, changement forcé.
- VL-1/VL-2 verrou du poste ; VW verrou de session web ; écrans de verrouillage sans phrases d'explication.
- H5 vider les sessions ; AUT-4 sessions, sauvegardes, appairage autonomes.

## 6. Attestations
- ATT-1 à ATT-3 : fidélité au modèle, signataires selon la durée, PDF produit au poste, numéro attribué par le serveur.
- Signature du Directeur centrée, date d'attestation modifiable (web + poste + API).
- Documents hors code (non versionnés) : deux PV de fin de mission, quatre attestations de bonne fin d'exécution, papier à en-tête.

## 7. Paramètres, aide, ergonomie
- PA-1 à PA-8, AUT-2 logo et favicon, AUT-3 e-mail à la place du SMS, H9 réglages.
- E6 assistant de démarrage (module éteint par défaut) ; AIDE-1 bouton d'aide flottant, aide par écran, visite guidée.
- Marque renommée LogiAgriERP ; page expirée sans confirmation navigateur.
- Menu latéral à 14 px ; menu contextuel « Actualiser » ; modale de synchronisation agrandie ; toasts sans doublon ; en-têtes de tableau cadrés.
- J1 à J4 audit des écarts web ↔ poste et corrections ; H13 synchronisation automatique par lots de 50.

## 8. Reste ouvert
- Départ par stade demandé à la création d'une bande (aujourd'hui : à l'ouverture de la fiche) — décision « laisser » ou « création » attendue.
- Rendu réel (navigateur, Windows) de la fiche Pondeuses, du hub à douze cartes, des pages Bilan et Balance Âgée — captures attendues du client.
- Libellé « Jeune » (au lieu de « Poulet ») à confirmer vis-à-vis du glossaire validé plus tôt.
- Jamais vérifié sur Windows : installateur Inno Setup, fenêtre sans bordure, désinstallation avec sauvegarde.
