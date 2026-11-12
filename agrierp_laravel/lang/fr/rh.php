<?php
/**
 * Ticket F1 — Localisation du module RH.
 * Toutes les chaînes visibles des vues Blade livewire/rh/*.
 * Généré le 12/11/2026 — 183 clés.
 */
return [

    // ── Hub Personnel & Stages — onglets ─────────────────────────────────────
    'tab_registre_employes'   => 'Registre Employés',
    'tab_registre_stagiaires' => 'Registre Stagiaires',
    'tab_feuille_pointage'    => 'Feuille de Pointage',
    'tab_gestion_paie'        => 'Gestion de la Paie',
    'tab_attestations'        => 'Attestations',

    // ── Registre des Employés — entête ───────────────────────────────────────
    'titre_registre_employes' => 'Registre des Employés',
    'desc_registre_employes'  => 'Répertoire du personnel permanent de la ferme.',

    // ── Registre des Employés — boutons ──────────────────────────────────────
    'bouton_exporter_pdf'   => 'Exporter PDF',
    'bouton_nouvel_employe' => 'Nouvel Employé',

    // ── Registre des Employés — KPI ──────────────────────────────────────────
    'kpi_employes_actifs' => 'Employés actifs',
    'kpi_nouveaux_annee'  => 'Nouveaux (année)',

    // ── Partagé : filtres / recherche ────────────────────────────────────────
    'filtre_tous_statuts'  => 'Tous les statuts',
    'placeholder_rechercher' => 'Rechercher...',

    // ── Partagé : colonnes communes ──────────────────────────────────────────
    'col_nom'     => 'Nom',
    'col_statut'  => 'Statut',
    'col_actions' => 'Actions',
    'col_employe' => 'Employé',
    'col_date'    => 'Date',

    // ── Registre des Employés — colonnes spécifiques ─────────────────────────
    'col_fonction'      => 'Fonction',
    'col_date_embauche' => 'Date d\'embauche',
    'col_salaire'       => 'Salaire',

    // ── Statuts des employés ─────────────────────────────────────────────────
    'statut_actif'    => 'Actif',
    'statut_conge'    => 'Congé',
    'statut_suspendu' => 'Suspendu',
    'statut_archive'  => 'Archivé',
    'lecture_seule'   => 'Lecture seule',

    // ── Registre des Employés — messages vides ───────────────────────────────
    'msg_aucun_employe' => 'Aucun employé pour le moment.',

    // ── Registre des Employés — modal ────────────────────────────────────────
    'modal_titre_modifier_employe' => 'Modifier — Registre des Employés',
    'modal_titre_nouvel_employe'   => 'Nouvel Employé',

    // ── Partagé : libellés de formulaire ─────────────────────────────────────
    'label_prenom'           => 'Prénom *',
    'label_nom'              => 'Nom *',
    'label_statut'           => 'Statut',
    'option_selectionner'    => '-- Sélectionner --',
    'bouton_annuler'         => 'Annuler',
    'bouton_enregistrer'     => 'Enregistrer',

    // ── Registre des Employés — labels spécifiques ───────────────────────────
    'label_fonction'      => 'Fonction *',
    'label_date_embauche' => 'Date d\'embauche *',
    'label_salaire_base'  => 'Salaire de base (FCFA)',

    // ── Registre des Employés — options de fonction ──────────────────────────
    'option_chef_elevage'    => 'Chef d\'élevage',
    'option_comptable'       => 'Comptable',
    'option_gardien'         => 'Gardien',
    'option_vendeuse_pos'    => 'Vendeuse POS',
    'option_ouvrier_agricole' => 'Ouvrier agricole',

    // ── Registre des Stagiaires — entête ─────────────────────────────────────
    'titre_registre_stagiaires' => 'Registre des Stagiaires',
    'desc_registre_stagiaires'  => 'Suivi des stagiaires, frais de formation, absences et attestations — distinct du personnel permanent.',

    // ── Registre des Stagiaires — boutons ────────────────────────────────────
    'bouton_nouveau_stagiaire' => 'Nouveau Stagiaire',

    // ── Registre des Stagiaires — KPI ────────────────────────────────────────
    'kpi_stagiaires_actifs'   => 'Stagiaires Actifs',
    'kpi_frais_collectes'     => 'Frais Collectés',
    'kpi_frais_en_attente'    => 'Frais en Attente',
    'kpi_attestations_emises' => 'Attestations Émises',

    // ── Registre des Stagiaires — filtres ────────────────────────────────────
    'filtre_en_cours' => 'En cours',
    'filtre_termine'  => 'Terminé',

    // ── Registre des Stagiaires — colonnes ───────────────────────────────────
    'col_etablissement_origine' => 'Établissement d\'Origine',
    'col_periode'               => 'Période',
    'col_frais_scolarite'       => 'Frais de Scolarité',

    // ── Statuts stagiaires / frais ───────────────────────────────────────────
    'statut_paye'       => 'Payé',
    'statut_en_attente' => 'En attente',
    'statut_en_cours'   => 'En cours',
    'statut_termine'    => 'Terminé',

    // ── Registre des Stagiaires — messages vides ─────────────────────────────
    'msg_aucun_stagiaire' => 'Aucun stagiaire pour le moment.',

    // ── Registre des Stagiaires — modal création/modification ────────────────
    'modal_titre_modifier_stagiaire' => 'Modifier le Stagiaire',
    'modal_titre_nouveau_stagiaire'  => 'Nouveau Stagiaire',
    'label_etablissement_origine'    => 'Établissement d\'origine *',
    'label_date_debut'               => 'Date de début *',
    'label_date_fin'                 => 'Date de fin',
    'label_frais_stage'              => 'Frais de stage (FCFA)',
    'label_frais_regle'              => 'Frais réglé',

    // ── Registre des Stagiaires — modal absences ─────────────────────────────
    'modal_titre_absences' => 'Absences',
    'label_date_absence'   => 'Date *',
    'label_motif'          => 'Motif',
    'bouton_ajouter_absence' => "Ajouter l'absence",
    'msg_aucune_absence'   => 'Aucune absence enregistrée.',

    // ── Feuille de Pointage — entête ─────────────────────────────────────────
    'titre_feuille_pointage' => 'Feuille de Pointage',
    'desc_feuille_pointage'  => 'Suivi quotidien des heures de présence du personnel.',

    // ── Feuille de Pointage — boutons ────────────────────────────────────────
    'bouton_enregistrer_pointage' => 'Enregistrer un Pointage',

    // ── Feuille de Pointage — KPI ────────────────────────────────────────────
    'kpi_presents_jour' => 'Présents (jour)',
    'kpi_absents'       => 'Absents',
    'kpi_retards'       => 'Retards',

    // ── Feuille de Pointage — filtres / statuts ──────────────────────────────
    'filtre_present' => 'Présent',
    'filtre_absent'  => 'Absent',
    'filtre_retard'  => 'Retard',

    // ── Feuille de Pointage — colonnes ───────────────────────────────────────
    'col_arrivee' => 'Arrivée',
    'col_depart'  => 'Départ',

    // ── Statuts de pointage ──────────────────────────────────────────────────
    'statut_present' => 'Présent',
    'statut_absent'  => 'Absent',
    'statut_retard'  => 'Retard',

    // ── Feuille de Pointage — messages vides ─────────────────────────────────
    'msg_aucun_pointage' => 'Aucun pointage pour le moment.',

    // ── Feuille de Pointage — modal ──────────────────────────────────────────
    'modal_titre_modifier_pointage'    => 'Modifier le Pointage',
    'modal_titre_enregistrer_pointage' => 'Enregistrer un Pointage',
    'label_employe'          => 'Employé *',
    'label_date_pointage'    => 'Date *',
    'label_heure_arrivee'    => 'Heure d\'arrivée',
    'label_heure_depart'     => 'Heure de départ',
    'label_statut_pointage'  => 'Statut *',
    'info_un_pointage_par_jour' => 'Un seul pointage par employé et par jour — une nouvelle saisie sur la même date modifie le pointage existant.',

    // ── Gestion de la Paie — entête ──────────────────────────────────────────
    'titre_gestion_paie' => 'Gestion de la Paie',
    'desc_gestion_paie'  => 'Calcul automatique des retenues croisées avec la Feuille de Pointage.',

    // ── Gestion de la Paie — boutons ─────────────────────────────────────────
    'bouton_exporter_paie' => 'Exporter',

    // ── Gestion de la Paie — KPI ─────────────────────────────────────────────
    'kpi_masse_salariale'      => 'Masse Salariale',
    'kpi_bulletins_emis'       => 'Bulletins Émis',
    'kpi_charges_cnss'         => 'Charges Sociales (CNSS)',
    'kpi_en_attente_paiement'  => 'En Attente de Paiement',

    // ── Gestion de la Paie — info (texte découpé pour éviter le HTML dans les clés) ──
    'info_calcul_retenues_intro'   => 'Les retenues d\'absence sont calculées automatiquement :',
    'info_calcul_retenues_formule' => '(Salaire Brut / 26 jours ouvrés) x Jours d\'absence non justifiée',
    'info_calcul_retenues_suite'   => ', croisées avec les données de la Feuille de Pointage. La retenue CNSS (3.6%) s\'applique systématiquement sur le brut.',

    // ── Gestion de la Paie — colonnes ────────────────────────────────────────
    'col_poste'            => 'Poste',
    'col_salaire_brut'     => 'Salaire Brut',
    'col_absences'         => 'Absences',
    'col_ret_absences'     => 'Ret. Absences',
    'col_ret_cnss'         => 'Ret. CNSS',
    'col_ret_its'          => 'Ret. ITS',
    'col_net_a_payer'      => 'Net à Payer',
    'col_charges_patronales' => 'Charges patronales',

    // ── Gestion de la Paie — badges / messages ───────────────────────────────
    'msg_bareme_non_renseigne' => 'Barème non renseigné',
    'msg_aucun_employe_actif'  => 'Aucun employé actif pour le moment.',

    // ── Gestion de la Paie — modal bulletin ──────────────────────────────────
    'bulletin_periode_prefix'    => 'Période : ',
    'bulletin_salaire_brut'      => 'Salaire Brut',
    'bulletin_jours_absence'     => "Jours d'absence non justifiée",
    'bulletin_retenue_absences'  => 'Retenue Absences',
    'bulletin_retenue_cnss'      => 'Retenue CNSS (3.6%)',
    'bulletin_net_a_payer'       => 'Net à Payer',
    'bouton_fermer'              => 'Fermer',

    // ── Attestations — entête ────────────────────────────────────────────────
    'titre_attestations' => 'Attestations de Travail & de Stage',
    'desc_attestations'  => 'Personnalisez les modèles officiels, puis générez et téléchargez les attestations certifiées au format PDF.',

    // ── Attestations — onglets internes ──────────────────────────────────────
    'tab_generer_attestation'   => 'Générer une Attestation',
    'tab_personnaliser_modeles' => 'Personnaliser les Modèles',

    // ── Attestations — formulaire de génération ───────────────────────────────
    'section_choix_fiche'          => '1. Choix de la Fiche',
    'option_employe_permanent'     => 'Employé Permanent',
    'option_stagiaire_formation'   => 'Stagiaire en Formation',
    'label_nom_personne'           => 'Nom de la personne *',
    'label_poste_attestation'      => 'Poste',
    'label_etablissement_attestation' => 'Établissement',
    'label_type_contrat'           => 'Type de Contrat',
    'option_cdi'                   => 'CDI',
    'option_cdd'                   => 'CDD',
    'option_stage_conventionne'    => 'Stage conventionné',
    'label_civilite'               => 'Civilité',
    'option_monsieur'              => 'M. (Monsieur)',
    'option_madame'                => 'Mme (Madame)',
    'label_date_debut_attestation' => 'Date de Début',
    'label_date_fin_attestation'   => 'Date de Fin',
    'label_date_attestation'       => "Date de l'attestation",
    'info_date_attestation'        => "Imprimée après « :lieu, le ». Vide : la date du jour.",
    'label_domaines_formation'     => 'Domaines de formation (optionnel)',
    'label_appreciation'           => 'Appréciation (optionnel)',
    'placeholder_appreciation'     => 'Assiduité, rigueur, compétences acquises...',
    'label_duree_calculee'         => 'Durée calculée :',
    'msg_aucun_signataire'         => "Aucun signataire n'est appelé par la règle de ce modèle (voir « Personnaliser les Modèles »).",
    'info_signataires_modele'      => "Champs vides : le modèle s'applique. Qui signe, et à partir de quelle durée, se règle dans « Personnaliser les Modèles ».",
    'bouton_generer_attestation'   => "Générer l'Attestation",
    'apercu_simplifie'             => 'Aperçu simplifié : le PDF reprend le modèle officiel (décor, filigrane, polices).',
    'msg_selectionner_personne'    => 'Sélectionnez une personne pour prévisualiser l\'attestation.',
    'attestation_en_foi'           => 'En foi de quoi, la présente attestation lui est délivrée pour servir et valoir ce que de droit.',
    'attestation_de_travail'       => 'Attestation de Travail',
    'attestation_de_formation'     => 'Attestation de Formation',

    // ── Attestations — signataires (formulaire de génération) ────────────────
    'sig_intitule'       => 'Intitulé',
    'sig_nom_label'      => 'Nom',
    'sig_fonction_label' => 'Fonction',

    // ── Attestations — palier (description dynamique) ────────────────────────
    'sig_palier_court_desc' => "le promoteur seul (jusqu'à :n mois)",
    'sig_palier_long_desc'  => 'trois signataires (attestation de plus de :n mois)',

    // ── Attestations — personnalisation des modèles ───────────────────────────
    'modele_employe_titre'     => 'Modèle - Attestation de Travail (Employé)',
    'modele_stagiaire_titre'   => 'Modèle - Attestation de Formation (Stagiaire)',
    'label_texte_certificat'   => 'Texte du certificat',
    'info_balises_employe'     => 'Balises : [NOM], [POSTE], [CONTRAT], [DATE_DEBUT], [DATE_FIN], [DATE_DEBUT_LONGUE], [DATE_FIN_LONGUE], [DUREE], [DE_DUREE], [CIVILITE], [CIVILITE_LONGUE], [TITRE_NOM], [ACCORD_E]. **texte** s\'imprime en gras.',
    'info_balises_stagiaire'   => 'Balises : [NOM], [SPECIALITE], [ETABLISSEMENT], [DATE_DEBUT], [DATE_FIN], [DATE_DEBUT_LONGUE], [DATE_FIN_LONGUE], [DUREE], [DE_DUREE], [CIVILITE], [CIVILITE_LONGUE], [TITRE_NOM], [ACCORD_E], [DATE_NAISSANCE], [DATE_NAISSANCE_LONGUE], [LIEU_NAISSANCE]. **texte** s\'imprime en gras.',
    'bouton_enregistrer_modele' => 'Enregistrer ce Modèle',

    // ── Attestations — règle de signature ────────────────────────────────────
    'sig_reglage_titre'    => 'Signataires et règle de signature',
    'sig_palier_court_intro' => 'Palier court : jusqu\'à',
    'sig_palier_mois_inclus' => 'inclus',
    'sig_palier_info'      => '; au-delà, palier long. Durée comptée de la date de début à la date de fin (à aujourd\'hui sans date de fin).',
    'sig_directeur_general' => 'Directeur Général (le promoteur)',
    'sig_examinateur'      => 'Examinateur',
    'sig_president_jury'   => 'Président du Jury',
    'sig_intitule_imprime' => 'Intitulé imprimé (vide : aucun)',
    'sig_nom_placeholder'  => 'Nom',
    'sig_fonction_placeholder' => 'Fonction',
    'sig_signe_court'      => 'Signe le palier court',
    'sig_signe_long'       => 'Signe le palier long',
    'label_appreciation_imprimee' => 'Imprimer l\'appréciation par défaut (modifiable à chaque émission)',
    'info_appreciation_vide' => 'Vide : la phrase standard du modèle officiel. **texte** s\'imprime en gras. Balises : [CIVILITE_LONGUE], [NOM], [TITRE_NOM], [ACCORD_E].',
    'bouton_enregistrer_regle' => 'Enregistrer la règle de signature',
];
