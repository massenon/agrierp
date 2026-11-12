<?php
/**
 * Ticket F1 — Localisation du module Stocks.
 * Toutes les chaînes visibles des vues Blade livewire/stocks/*.
 * Généré le 12/11/2026 — 118 clés.
 */
return [
    // -------------------------------------------------------------------------
    // gestion-stocks.blade.php
    // -------------------------------------------------------------------------
    'titre_gestion_stocks'            => 'Gestion des Stocks',
    'desc_gestion_stocks'             => 'Espace unifié : inventaire, mouvements et ajustements.',
    'lien_configurer_seuils'          => 'Configurer les Seuils d\'Alerte',

    'kpi_valorisation'                => 'Valorisation Stocks',
    'kpi_valorisation_caption'        => 'Basée sur le PMP réel (achats)',
    'kpi_alertes'                     => 'Alertes de Seuil',
    'kpi_rotation'                    => 'Rotation du Stock',
    'kpi_rotation_pending'            => 'un stock valorisable non nul sur le mois',
    'kpi_ecarts'                      => 'Écarts d\'Inventaire',
    'kpi_ecarts_caption'              => 'Ajustements du mois',

    'tab_tableau'                     => 'Tableau & Valorisation',
    'tab_mouvements'                  => 'Journal des Mouvements',
    'tab_ajustements'                 => 'Ajustement / Correction',

    'placeholder_designation_sku'     => 'Désignation ou SKU...',
    'filtre_categorie_toutes'         => 'Catégorie : Toutes',
    'bouton_exporter'                 => 'Exporter',
    'bouton_ajouter_stock'            => 'Ajouter Stock',

    'col_code'                        => 'Code',
    'col_designation'                 => 'Désignation',
    'col_categorie'                   => 'Catégorie',
    'col_stock'                       => 'Stock',
    'col_pmp'                         => 'PMP Unit.',
    'col_valeur'                      => 'Valeur',
    'col_urgence'                     => 'Urgence',
    'col_actions'                     => 'Actions',

    'badge_entree_non_saisie'         => 'Entrée non saisie',
    'badge_critique'                  => 'Critique',
    'badge_normal'                    => 'Normal',

    'msg_aucun_produit'               => 'Aucun produit pour le moment.',

    'modal_titre_ajouter_stock'       => 'Ajouter Stock',
    'label_date_nouveau_stock'        => 'Date du Nouveau Stock *',
    'label_produit'                   => 'Produit *',
    'label_quantite_ajoutee'          => 'Quantité Ajoutée *',
    'placeholder_quantite'            => 'ex : 20',
    'select_produit'                  => '-- Sélectionner un produit --',
    'select_selectionner'             => '-- Sélectionner --',
    'bouton_annuler'                  => 'Annuler',
    'bouton_enregistrer'              => 'Enregistrer',

    'col_date_heure'                  => 'Date / Heure',
    'col_reference'                   => 'Référence',
    'col_produit'                     => 'Produit',
    'col_type'                        => 'Type',
    'col_motif'                       => 'Motif',
    'col_quantite'                    => 'Quantité',

    'type_entree'                     => 'Entrée',
    'type_sortie'                     => 'Sortie',
    'type_ajustement'                 => 'Ajustement',

    'msg_aucun_mouvement'             => 'Aucun mouvement enregistré pour le moment.',

    'titre_saisir_ajustement'         => 'Saisir un ajustement d\'inventaire',
    'label_stock_theorique'           => 'Stock théorique',
    'label_stock_physique'            => 'Stock physique constaté',
    'label_ecart_calcule'             => 'Écart calculé',
    'label_motif_ecart'               => 'Motif de l\'écart',
    'select_motif_ecart'              => '-- Sélectionner selon le sens de l\'écart --',
    'optgroup_ecart_negatif'          => 'Écart négatif (perte)',
    'optgroup_ecart_positif'          => 'Écart positif (surplus)',
    'motif_casse'                     => 'Casse de matériel',
    'motif_vol'                       => 'Vol / Disparition',
    'motif_mortalite'                 => 'Mortalité non déclarée',
    'motif_erreur_pesee'              => 'Erreur de pesée d\'approvisionnement',
    'motif_peremption'                => 'Péremption dépassée',
    'motif_naissance'                 => 'Naissance non répertoriée',
    'motif_surplus'                   => 'Surplus de livraison',
    'motif_erreur_inventaire'         => 'Erreur d\'inventaire antérieur',
    'bouton_valider_ajustement'       => 'Valider l\'ajustement',
    'info_ecriture_charge'            => 'Si l\'écart est négatif, une écriture de charge exceptionnelle (compte 657) est générée automatiquement, valorisée au PMP.',

    // -------------------------------------------------------------------------
    // catalogue-produits.blade.php
    // -------------------------------------------------------------------------
    'titre_catalogue'                 => 'Catalogue Produits',
    'desc_catalogue'                  => 'Vue d\'ensemble visuelle de l\'offre commerciale de la ferme.',
    'bouton_nouveau_produit'          => 'Nouveau Produit',
    'filtre_tous'                     => 'Tous',
    'placeholder_rechercher_produit'  => 'Rechercher un produit ou un SKU...',
    'msg_aucun_produit_recherche'     => 'Aucun produit ne correspond à cette recherche.',

    'col_sku'                         => 'SKU',
    'col_tarif'                       => 'Tarif',

    'tab_voir_catalogue'              => 'Voir le Catalogue',
    'tab_seuils_alerte'               => 'Seuils d\'Alerte',

    // -------------------------------------------------------------------------
    // ajouter-produit.blade.php
    // -------------------------------------------------------------------------
    'titre_modifier_produit'          => 'Modifier le Produit',
    'titre_ajouter_produit'           => 'Ajouter un Produit',
    'desc_modifier_produit'           => 'Modification d\'une référence existante du catalogue.',
    'desc_ajouter_produit'            => 'Création d\'une nouvelle référence dans le catalogue produits de la ferme.',

    'label_nom_produit'               => 'Nom du produit *',
    'placeholder_nom_produit'         => 'ex : Œufs de table (plateau de 30)',
    'label_categorie'                 => 'Catégorie *',
    'label_filiere_elevage'           => 'Filière d\'élevage',
    'label_filiere_si_applicable'     => '(si applicable)',
    'select_aucune'                   => '-- Aucune --',
    'label_categorie_effectif'        => 'Catégorie d\'effectif',
    'label_categorie_effectif_vol'    => '(volailles)',
    'info_categorie_effectif'         => 'La vente de ce produit sort de cette catégorie (fiche Volailles Reproducteurs) ou de ce stade (fiche Pondeuses) : une catégorie de reproducteurs ne se vend que sur une bande de reproducteurs, un stade de pondeuses que sur une bande de pondeuses. Sans elle, la vente sur une bande de volailles est refusée.',
    'label_unite_comptage'            => 'Unité de comptage *',
    'placeholder_unite'               => 'ex : u, sac, plateau',
    'info_unite'                      => 'Toujours une unité de pièce/comptage — jamais une unité de poids (kg).',
    'label_mode_tarification'         => 'Mode de Tarification *',
    'option_fourchette'               => 'Fourchette',
    'option_sur_devis'                => 'Sur devis',
    'label_prix_min'                  => 'Prix Min (FCFA) *',
    'placeholder_prix_min'            => 'ex : 3000',
    'label_prix_max'                  => 'Prix Max (FCFA) *',
    'placeholder_prix_max'            => 'ex : 4000',
    'info_sur_devis'                  => 'Ce produit sera vendu sur devis (ex. cages sur mesure) — aucun prix indicatif à saisir ici.',
    'label_stock_initial'             => 'Stock Initial',
    'label_seuil_alerte'              => 'Seuil d\'Alerte',
    'label_tva'                       => 'TVA (%)',
    'label_description'               => 'Description',
    'bouton_enregistrer_modif'        => 'Enregistrer les modifications',

    // -------------------------------------------------------------------------
    // seuils-alerte.blade.php
    // -------------------------------------------------------------------------
    'titre_seuils_alerte'             => 'Seuils d\'Alerte',
    'desc_seuils_alerte'              => 'Configuration des seuils critiques déclenchant les alertes de réapprovisionnement.',
    'kpi_produits_sous_seuil'         => 'Produits sous seuil',
    'kpi_seuils_configures'           => 'Seuils configurés',
    'placeholder_rechercher'          => 'Rechercher...',
    'filtre_tous_statuts'             => 'Tous les statuts',
    'col_stock_actuel'                => 'Stock actuel',
    'col_seuil_configure'             => 'Seuil configuré',
    'col_statut'                      => 'Statut',

    'modal_titre_configurer_seuil'    => 'Configurer un Seuil',
    'label_seuil_alerte_modal'        => 'Seuil d\'Alerte *',

    // -------------------------------------------------------------------------
    // importation-masse.blade.php
    // -------------------------------------------------------------------------
    'titre_importation_masse'         => 'Importation en masse',
    'desc_importation_masse'          => 'Créez vos produits avec leur stock initial, vos clients, vos fournisseurs, vos employés, vos comptes comptables ou votre barème de rationnement à partir d\'un tableur Excel (.xlsx) : téléchargez le modèle, remplissez-le, déposez-le, vérifiez l\'aperçu, puis confirmez.',

    'etape_module'                    => 'Module',
    'etape_modele'                    => 'Modèle',
    'etape_fichier'                   => 'Fichier',
    'etape_apercu'                    => 'Aperçu',
    'etape_confirmation'              => 'Confirmation',
    'etape_rapport'                   => 'Rapport',

    'etape1_titre'                    => '1 · Que voulez-vous importer ?',
    'info_modules_role'               => 'Seuls les modules que votre rôle permet d\'importer sont proposés.',

    'etape2_titre'                    => '2 · Télécharger le modèle',
    'info_entetes'                    => 'Ne renommez pas les en-têtes : un fichier modifié est refusé avec la colonne en cause.',
    'info_montants'                   => 'Les montants sont des francs CFA entiers ; la création est SEULE : une fiche déjà présente est ignorée, jamais modifiée.',
    'bouton_telecharger_modele'       => 'Télécharger le modèle',
    'bouton_deposer_fichier'          => 'J\'ai le modèle rempli : déposer mon fichier',
    'bouton_changer_module'           => 'Changer de module',

    'etape3_titre'                    => '3 · Déposer le fichier',
    'dropzone_consigne'               => 'Glissez votre fichier .xlsx (ou .csv) ici, ou cliquez pour le choisir',
    'dropzone_envoi'                  => 'Envoi en cours…',
    'dropzone_lecture'                => 'Lecture et validation du fichier…',
    'bouton_retour_modele'            => 'Retour au modèle',

    'etape4_titre'                    => '4 · Aperçu — rien n\'est encore écrit',
    'alerte_bloquant'                 => 'L\'importation ne peut pas être confirmée.',
    'etape6_titre'                    => '6 · Rapport d\'importation',

    'kpi_lignes_lues'                 => 'Lignes lues',
    'kpi_creees'                      => 'Créées',
    'kpi_valides'                     => 'Valides',
    'kpi_ignorees'                    => 'Ignorées (déjà présentes)',
    'kpi_refusees'                    => 'Refusées',
    'info_stocks_ignores'             => 'Un produit déjà au catalogue est IGNORÉ : son stock initial n\'a pas été ajouté (deux déclarations du même article sont le même stock physique ; un écart se corrige par un inventaire).',

    'filtre_toutes_lignes'            => 'Toutes les lignes',
    'filtre_refusees'                 => 'Refusées seulement',
    'filtre_ignorees'                 => 'Ignorées seulement',
    'filtre_creees'                   => 'Créées seulement',
    'filtre_valides'                  => 'Valides seulement',

    'col_ligne'                       => 'Ligne',
    'col_valeurs_lues'                => 'Valeurs lues',
    'col_resultat'                    => 'Résultat',
    'col_motif_import'                => 'Motif',
    'msg_aucune_ligne_filtre'         => 'Aucune ligne pour ce filtre.',

    'bouton_changer_fichier'          => 'Changer de fichier',
    'bouton_abandonner'               => 'Abandonner',
    'bouton_telecharger_rapport'      => 'Télécharger le rapport',
    'bouton_corriger'                 => 'Corriger le fichier puis ré-importer',
    'bouton_nouvel_import'            => 'Nouvel import',

    'modal_confirmer_titre'           => '5 · Confirmer l\'importation',
    'bouton_confirmer_importation'    => 'Confirmer l\'importation',

    // Chaînes dynamiques (`:param` → remplacé par __('key', ['param' => val]))
    'label_theorique'                 => 'Théorique',
    'etape2_titre_module'             => '2 · Télécharger le modèle « :libelle »',
    'info_contenu_modele'             => 'Le modèle (version :version) contient une feuille « Instructions » (rôle de chaque colonne, formats, exemples), la feuille « Données » à remplir et les listes déroulantes à utiliser.',
    'info_limite_taille'              => 'Jusqu\'à :lignes lignes et :mo Mo par fichier.',
    'etape3_titre_module'             => '3 · Déposer le fichier « :libelle »',
    'dropzone_contrainte'             => 'Modèle « :libelle », version :version — :mo Mo et :lignes lignes au plus',
    'info_fichier_apercu'             => 'Fichier « :fichier » · modèle « :libelle » version :version.',
    'info_fichier_rapport'            => 'Fichier « :fichier » · terminé le :date.',
    'mot_ligne'                       => 'ligne',
    'mot_lignes'                      => 'lignes',
    'bouton_precedent'                => 'Précédent',
    'bouton_suivant'                  => 'Suivant',
    'bouton_importer'                 => 'Importer',
    'modal_lignes_valides_pl'         => 'lignes valides vont être écrites dans « :module ».',
    'modal_lignes_valides_sg'         => 'ligne valide va être écrite dans « :module ».',
    'modal_nb_exclus'                 => ':ignorees ignorée(s) et :refusees refusée(s) ne sont pas écrites.',
    'modal_stock_initial'             => 'Chaque stock initial entre par un mouvement « Stock initial ».',
    'modal_independance'              => 'L\'écriture se fait ligne par ligne : une ligne refusée n\'arrête pas les autres.',
];
