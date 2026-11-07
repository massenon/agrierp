# Spécimens de présentation — AgriERP

> **SPÉCIMENS DE DÉMONSTRATION — aucune facture réelle, rien n'a été transmis à la DGI.**
> Noms, montants, IFU (`9999999999999`, `8888888888888`), NIM, code MeCeF, compteurs et QR sont **fictifs** et marqués « FICTIF » ou « SPÉCIMEN ». Ne pas scanner les QR, ne pas utiliser ces fichiers comme pièces.

Tous les PDF sont produits par le **vrai code** d'AgriERP (`PdfExportService`, vues Blade `exports.*`, `MecefFactureBuilder`), à partir de données de démonstration. Seuls le filigrane et le bandeau « SPÉCIMEN » sont ajoutés après coup, page par page.

| Fichier | Contenu | Produit par |
|---|---|---|
| `facture_simple_A4.pdf` | Facture normale, mention « Facture simple — non normalisée DGI » | `exports.facture-vente` |
| `facture_normalisee_A4.pdf` | Facture normalisée : nom et IFU du client, AIB 5 % (montant « calculé par la DGI » fictif), remise, QR, code MeCeF / NIM / compteurs **fictifs** | `exports.facture-vente` |
| `document_A4_exemple.pdf` | Document officiel A4 : un bon de commande, avec l'en-tête et le logo de la ferme | `exports.bon-commande` |
| `ticket_essai_mecef.pdf` | Ticket de caisse étroit (80 mm) pour l'essai d'une machine MeCeF : lignes, totaux, TVA par groupe, AIB, mode de paiement, QR fictif | `exports.ticket-essai-mecef` |
| `ticket_essai_mecef.json` | La charge utile de test au format du pilote Eltrade CC300 (`bill.spec.json` : `vt`, `seller_id`, `seller_name`, `payments`, `products` avec `tax`, `price` entier TTC, `items`, `aib`) | `MecefFactureBuilder` puis `ChargeBoitierEltrade` |
| `apercus/*.png` | Première page de chaque PDF, pour un coup d'œil sans ouvrir les PDF | `pdftoppm` |

Le `.json` et le ticket décrivent la **même** vente d'essai (21 300 FCFA TTC). Le JSON n'a jamais été envoyé à un vrai boîtier : le mode boîtier n'est pas construit (MECEF-2) et le schéma est celui de `bill.spec.json`, lu, pas essayé.

## Régénérer

Depuis la racine du monorepo (PHP 8.3, `composer install` déjà fait dans `agrierp_laravel/`) :

```bash
php presentation/generer.php
```

- La base est une **SQLite en mémoire** créée à chaque lancement (`migrate`) : la base de développement n'est **jamais** ouverte, le script refuse de continuer si la connexion n'est pas `:memory:`.
- Aucun appel réseau, aucun jeton : le module MeCeF n'est jamais appelé.
- Les identifiants et la date de démonstration sont fixes : deux lancements donnent les mêmes numéros de facture (`FV-2026-5A1E00`, …).
- Les aperçus PNG demandent `pdftoppm` (paquet `poppler-utils`) ; sans lui, les PDF sont régénérés et les PNG laissés tels quels.
- Le logo des documents est celui de la ferme (`agrierp_laravel/public/assets/images/logo_ferme_ecole_officiel.png`) tant qu'aucun logo n'est choisi dans Paramètres > Données de l'Entreprise.
