<?php

namespace App\Livewire\Aide;

use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 1.5 (Sprint 1) — aide-a-propos.html → page statique
 *
 * Contenu 100% documentaire (description des modules, FAQ) — pas de
 * donnée métier, donc pas de requête Eloquent (Document 00 §2.1 concerne
 * les données d'exploitation, pas le texte d'aide du logiciel lui-même).
 * Implémenté comme composant Livewire trivial (aucune propriété publique,
 * aucune action serveur) uniquement pour la cohérence de routage/layout
 * avec le reste de l'application (Rule 1, PROMPT_AVOID_ERREURS_LARAVEL_LIVEWIRE.md)
 * — la recherche et l'accordéon FAQ sont entièrement gérés côté client en
 * Alpine.js (aucun aller-retour serveur nécessaire pour filtrer du texte
 * statique).
 */
#[Layout('layouts.app')]
class Index extends Component
{
    public function getModulesProperty(): array
    {
        return [
            ['href' => '/dashboard', 'icon' => 'dashboard', 'title' => 'Tableau de Bord', 'description' => "Vue consolidée de l'activité de la ferme : ventes du jour, trésorerie, alertes de stock et effectifs vivants."],
            ['href' => '/gestion-elevage', 'icon' => 'pets', 'title' => 'Gestion Élevage', 'description' => 'Suivi des bandes/lots (Cuniculture, Aviculture, Porciculture), fiches journalières, reproduction et transformation.'],
            ['href' => '/soins-vaccins-hub', 'icon' => 'vaccines', 'title' => 'Soins et Vaccins', 'description' => 'Registre vétérinaire, calendrier de prophylaxie et suivi sanitaire du cheptel.'],
            ['href' => '/ventes-devis', 'icon' => 'point_of_sale', 'title' => 'Ventes & Devis', 'description' => 'Caisse POS, devis, historique des ventes et gestion des retours.'],
            ['href' => '/creances-clients', 'icon' => 'payments', 'title' => 'Clients et Créances', 'description' => 'Répertoire clients, suivi des dettes, relances et avances sur commande.'],
            ['href' => '/achats-commandes', 'icon' => 'local_shipping', 'title' => 'Achats & Commandes', 'description' => 'Enregistrement des achats, bons de commande et suivi des livraisons fournisseurs.'],
            ['href' => '/gestion-stocks', 'icon' => 'inventory_2', 'title' => 'Gestion Stocks', 'description' => "Valorisation des stocks, mouvements, ajustements d'inventaire."],
            ['href' => '/facturation', 'icon' => 'receipt_long', 'title' => 'Facturation & MeCeF', 'description' => 'Facturation normalisée conforme à la réglementation fiscale béninoise (DGI).'],
            ['href' => '/personnel-stages', 'icon' => 'badge', 'title' => 'Personnel & Stages', 'description' => 'Registre du personnel, pointage, paie et attestations de travail/stage.'],
            ['href' => '/comptabilite-hub', 'icon' => 'account_balance', 'title' => 'Comptabilité', 'description' => "Journal comptable, bilan, comptabilité analytique et clôture d'exercice (SYSCOHADA)."],
            ['href' => '/administration', 'icon' => 'folder_shared', 'title' => 'Administration', 'description' => 'Gestion des courriers, archivage des documents et documents administratifs de la ferme.'],
            ['href' => '/rapports-exports', 'icon' => 'picture_as_pdf', 'title' => 'Rapports & Exports', 'description' => 'États financiers et zootechniques : recettes/dépenses, trésorerie, créances, dettes, élevage, stocks.'],
        ];
    }

    public function getFaqsProperty(): array
    {
        return [
            ['question' => 'Comment enregistrer une nouvelle vente ?', 'answer' => 'Rendez-vous dans Ventes & Devis > Enregistrer Vente, sélectionnez les produits, un client (ou Client Anonyme), puis validez le mode de règlement.'],
            ['question' => "Comment créer une nouvelle bande d'élevage ?", 'answer' => "Utilisez Gestion Élevage > Enregistrer Sujets pour la première saisie (naissance ou achat), puis suivez son évolution dans l'onglet Bandes / Lots."],
            ['question' => "Comment fonctionne l'alerte de stock d'aliment ?", 'answer' => "Le système calcule l'autonomie en jours (stock disponible ÷ consommation théorique du cheptel). Une alerte critique s'affiche automatiquement si elle descend sous 3 jours."],
            ['question' => 'Comment générer une attestation de travail ou de stage ?', 'answer' => "Allez dans Personnel & Stages > Attestations, sélectionnez la personne concernée, puis cliquez sur Générer l'Attestation."],
            ['question' => 'Comment activer ou désactiver un module (ex. Escargots) ?', 'answer' => "Rendez-vous dans Paramètres > Modules Actifs pour activer/désactiver indépendamment chaque espèce d'élevage."],
            ['question' => 'Comment clôturer un exercice comptable ?', 'answer' => "Depuis Comptabilité & Admin > Clôture d'Exercice, suivez l'assistant en 3 étapes : inventaire, solde des comptes, génération des écritures d'à-nouveaux."],
            ['question' => "Comment masquer la barre latérale pour plus d'espace de travail ?", 'answer' => "Cliquez sur l'icône de menu à côté du fil d'Ariane dans l'en-tête. Un ruban d'accès rapide apparaît alors sur le bord droit."],
        ];
    }

    public function render()
    {
        return view('livewire.aide.index', ['title' => 'Aide & À Propos']);
    }
}
