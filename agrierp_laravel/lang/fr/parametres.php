<?php

return [

    // ── Onglets du hub
    'onglet_roles'           => 'Rôles & Permissions',
    'onglet_entreprise'      => 'Données de l\'Entreprise',
    'onglet_facturation'     => 'Facturation normalisée (e-MECeF)',
    'onglet_email'           => 'Email (SMTP)',
    'onglet_modules'         => 'Modules Actifs',
    'onglet_utilisateurs'    => 'Gestion Utilisateurs',
    'onglet_postes'          => 'Postes & Appairage',
    'onglet_paiement'        => 'Modes de Paiement',
    'onglet_audit'           => 'Audit Logs',
    'onglet_corbeille'       => 'Corbeille',
    'onglet_reinitialisation' => 'Réinitialisation',
    'onglet_sauvegardes'     => 'Sauvegardes',

    // ── Données de l'entreprise — titres et descriptions
    'titre_donnees_entreprise'  => 'Données de l\'Entreprise',
    'desc_donnees_entreprise'   => 'Identité légale, fiscale et configuration technique de la Ferme École OLOUWACHEGOUN.',
    'section_infos_generales'   => 'Informations Générales',
    'section_infos_legales'     => 'Informations Légales & Fiscales',
    'section_config_email'      => 'Configuration Email (SMTP)',
    'section_logo'              => 'Logo de l\'Entreprise',
    'section_favicon'           => 'Favicon (Icône d\'Onglet)',
    'section_regime_tva'        => 'Régime de TVA',
    'section_charges_sociales'  => 'Charges sociales et fiscales sur salaires',

    // ── Données de l'entreprise — labels champs
    'label_raison_sociale'              => 'Raison Sociale *',
    'label_nom_promoteur'               => 'Nom du Promoteur',
    'label_adresse_siege'               => 'Adresse du Siège d\'Exploitation',
    'label_telephone_principal'         => 'Téléphone Principal',
    'label_email_contact'               => 'Email de Contact',
    'label_ifu'                         => 'Identifiant Fiscal Unique (IFU) *',
    'label_rccm'                        => 'Registre du Commerce (RCCM)',
    'label_cnss_salariale'              => 'CNSS salariale (%)',
    'label_vps'                         => 'VPS — Versement Patronal sur Salaires (%)',
    'label_cnss_patronale_pensions'     => 'CNSS patronale — pensions (%)',
    'label_cnss_patronale_famille'      => 'CNSS patronale — prestations familiales (%)',
    'label_cnss_patronale_risques'      => 'CNSS patronale — risques professionnels (%)',
    'label_assujettie_tva'              => 'Exploitation assujettie à la TVA',

    // ── Données de l'entreprise — aides et notes
    'info_mecef_facturation'  => 'Ces informations apparaissent sur toutes les factures normalisées MeCeF et les documents officiels générés par LogiAgriERP.',
    'lien_smtp_titre'         => 'Serveur d\'envoi, mot de passe et e-mail de test',
    'lien_smtp_detail'        => 'Se règlent dans l\'onglet Email (SMTP) — une seule configuration pour toute l\'application.',
    'aide_upload_logo'        => 'Glisser-déposer ou cliquer pour choisir un logo',
    'aide_format_logo'        => 'PNG carré, fond transparent recommandé, max 2 Mo',
    'aide_upload_favicon'     => 'Glisser-déposer ou cliquer pour choisir un favicon',
    'aide_format_favicon'     => 'ICO ou PNG 32x32px, max 500 Ko',
    'aide_cnss_salariale'     => 'Retenue sur le salarié — 3,6 % (branche pensions).',
    'aide_cnss_risques'       => 'De 1 à 4 % selon le niveau de risque de l\'entreprise.',
    'aide_tva_detail'         => 'Activé : les rubriques de TVA apparaissent et les montants sont présentés TTC ; les écritures ventilent la taxe (443 collectée, 445 déductible). Désactivé : aucune rubrique de TVA, les montants sont des montants HT, et aucune ligne de taxe n\'est comptabilisée. Le taux porté par chaque produit reste conservé au catalogue — rien n\'est à ressaisir le jour où l\'exploitation devient assujettie.',
    'desc_charges_sociales'   => 'Retenues salariales (prélevées sur le salarié, diminuent son net) et charges patronales (versées en plus par l\'employeur, sans toucher au net).',
    'lien_bareme_its_titre'   => 'Barème IR-PTS / ITS — tranches d\'imposition',
    'lien_bareme_its_detail'  => 'Progressif sur le net imposable, avec simulation immédiate du net à payer.',
    'info_facturation_emecef' => 'Le mode de facturation normalisée, le jeton et l\'adresse de l\'API e-MECeF se règlent dans l\'onglet Facturation normalisée (e-MECeF).',

    // ── Données de l'entreprise — boutons et confirms
    'btn_enregistrer_modifs'   => 'Enregistrer les Modifications',
    'btn_supprimer'            => 'Supprimer',
    'confirm_supprimer_logo'   => 'Supprimer le logo de l\'entreprise ? Le fichier sera effacé.',
    'confirm_supprimer_favicon' => 'Supprimer l\'icône du site de l\'entreprise ? Le fichier sera effacé.',

    // ── Email SMTP — titres et descriptions
    'titre_email_smtp'          => 'Email (SMTP)',
    'desc_email_smtp'           => 'Serveur d\'envoi des e-mails de la ferme (relances, notifications, réinitialisation des mots de passe). Une seule configuration pour toute l\'application.',
    'section_serveur_smtp'      => 'Serveur SMTP',
    'section_test_email'        => 'Envoyer un e-mail de test',
    'desc_test_email'           => 'Le test emploie la configuration enregistrée : enregistrez d\'abord une modification avant de la tester. Un e-mail part réellement.',

    // ── Email SMTP — labels champs
    'label_hote_smtp'           => 'Hôte SMTP *',
    'label_port_smtp'           => 'Port *',
    'label_securite_smtp'       => 'Sécurité',
    'label_utilisateur_smtp'    => 'Utilisateur SMTP',
    'label_mdp_smtp'            => 'Mot de Passe SMTP',
    'label_adresse_expedition'  => 'Adresse d\'Expédition',
    'label_destinataire_test'   => 'Destinataire du test',

    // ── Email SMTP — aides
    'aide_adresse_expedition' => 'Vide : l\'e-mail de contact (Données de l\'Entreprise) sert d\'expéditeur.',
    'aide_mdp_smtp'           => 'Chiffré en base — jamais réaffiché en clair une fois enregistré, jamais envoyé aux postes.',
    'info_smtp_postes'        => 'Chaque poste Windows a son propre réglage SMTP (Paramètres > Email (SMTP) du poste) : son mot de passe reste dans le coffre du système de ce poste et ne transite jamais par le serveur.',
    'mdp_smtp_enregistre'     => 'Mot de passe enregistré',
    'mdp_smtp_vide'           => 'Aucun mot de passe enregistré',
    'lien_effacer_mdp_smtp'   => 'Effacer le mot de passe',

    // ── Email SMTP — boutons
    'btn_enregistrer_smtp'    => 'Enregistrer la Configuration SMTP',
    'btn_envoyer_test'        => 'Envoyer un e-mail de test',

    // ── Email SMTP — placeholder
    'placeholder_destinataire_test' => 'Envoyer un e-mail de test à...',

    // ── Email SMTP — modal effacer mot de passe
    'titre_effacer_mdp_smtp'           => 'Effacer le mot de passe',
    'confirm_effacer_mdp_smtp'         => 'Si le serveur d\'envoi exige une authentification, aucun e-mail ne partira plus tant qu\'un nouveau mot de passe n\'aura pas été saisi.',
    'modal_effacer_mdp_smtp_item'      => 'Le mot de passe SMTP enregistré',
    'modal_effacer_mdp_smtp_titre'     => 'Effacer le mot de passe',
    'modal_effacer_mdp_smtp_confirmer' => 'Effacer le mot de passe',
    'modal_effacer_mdp_smtp_warning'   => 'Si le serveur d\'envoi exige une authentification, aucun e-mail ne partira plus tant qu\'un nouveau mot de passe n\'aura pas été saisi.',

    // ── Facturation e-MECeF — titres et descriptions
    'titre_facturation_emecef'  => 'Facturation normalisée (e-MECeF)',
    'desc_facturation_emecef'   => 'Renseignez ici le compte e-MECeF de la ferme pour transmettre ses factures normalisées à la DGI. Une facture normalisée n\'est plus modifiable ni annulable : elle se corrige par un avoir. Une facture simple n\'est jamais transmise.',
    'info_ou_jeton'             => 'Où trouver le jeton ?',
    'aide_ou_jeton'             => 'Le jeton (JWT) est délivré par la DGI pour le compte e-MECeF de votre IFU : connectez-vous au portail e-MECeF de la DGI avec l\'IFU de la ferme et copiez-y le jeton. Il est secret : chiffré sur le serveur, jamais affiché, jamais envoyé aux postes.',

    // ── Facturation e-MECeF — labels champs
    'label_mode_facturation'    => 'Mode de facturation normalisée',
    'label_ifu_emecef'          => 'IFU de l\'entreprise',
    'label_api_emecef'          => 'Adresse de l\'API e-MECeF',
    'label_jeton_emecef'        => 'Jeton e-MECeF (JWT)',
    'label_operateur_id'        => 'Identifiant de l\'opérateur',
    'label_operateur_nom'       => 'Nom de l\'opérateur (caissier par défaut)',

    // ── Facturation e-MECeF — aides
    'aide_ifu_emecef'       => '13 chiffres, celui du compte e-MECeF. C\'est le même IFU que celui de « Données de l\'Entreprise » : une seule saisie.',
    'aide_api_emecef'       => 'Pour un premier essai sans valeur fiscale, choisissez l\'environnement d\'essai. Ces deux adresses sont relevées dans le paquet de référence : confirmez-les avec le portail e-MECeF de la DGI.',
    'aide_mode_boitier'     => 'Mode boîtier : la transmission se fait par le poste Windows où le boîtier Eltrade CC300 est branché (fonction construite, pas encore essayée avec un vrai boîtier). Tant que le boîtier est absent, les factures restent en attente et partent dès son retour.',
    'aide_mode_desactive'   => 'Aucune facture n\'est transmise : la facturation reste un registre avec facture PDF.',
    'aide_mode_emecef'      => 'Les ventes choisies en « Facture normalisée » à l\'encaissement sont transmises à la DGI par le serveur.',
    'jeton_dans_config'     => 'Jeton défini dans la configuration du serveur',
    'btn_remplacer_jeton'   => 'Remplacer',
    'btn_effacer_jeton'     => 'Effacer',
    'confirm_effacer_jeton' => 'Effacer le jeton ? Plus aucune facture ne sera transmise tant qu\'un nouveau jeton n\'est pas saisi.',
    'aide_jeton_placeholder' => 'Collez le jeton délivré par la DGI',
    'info_test_mecef'       => 'Le test ne crée aucune facture : il vérifie la configuration puis lit l\'état du service e-MECeF.',

    // ── Facturation e-MECeF — boutons
    'btn_tester_config'     => 'Tester la configuration',
    'btn_enregistrer'       => 'Enregistrer',
    'label_ok'              => 'OK',
    'label_a_corriger'      => 'À corriger',

    // ── Gestion utilisateurs — titres et descriptions
    'titre_gestion_utilisateurs'  => 'Gestion des Utilisateurs',
    'desc_gestion_utilisateurs'   => 'Administration des comptes d\'accès à LogiAgriERP.',

    // ── Gestion utilisateurs — KPI
    'kpi_utilisateurs_actifs'  => 'Utilisateurs actifs',
    'kpi_roles_definis'        => 'Rôles définis',

    // ── Gestion utilisateurs — tableau
    'col_nom'       => 'Nom',
    'col_email'     => 'Email',
    'col_role'      => 'Rôle',
    'col_statut'    => 'Statut',
    'col_actions'   => 'Actions',

    // ── Gestion utilisateurs — statuts
    'statut_actif'       => 'Actif',
    'statut_desactive'   => 'Désactivé',
    'statut_mdp_changer' => 'Mot de passe à changer',

    // ── Gestion utilisateurs — filtres
    'filtre_tous_statuts'  => 'Tous les statuts',

    // ── Gestion utilisateurs — messages vide
    'msg_aucun_utilisateur' => 'Aucun utilisateur pour le moment.',

    // ── Gestion utilisateurs — boutons
    'btn_exporter_pdf'            => 'Exporter PDF',
    'btn_deconnecter_sessions'    => 'Déconnecter Toutes les Sessions',
    'btn_nouvel_utilisateur'      => 'Nouvel Utilisateur',

    // ── Gestion utilisateurs — modal vider sessions
    'titre_vider_sessions'   => 'Déconnecter toutes les sessions ?',
    'desc_vider_sessions'    => 'Tous les utilisateurs du site sont déconnectés et chaque poste Windows devra se reconnecter. Les saisies en attente sur les postes sont conservées et partiront après la reconnexion. Votre propre session reste ouverte. L\'action est journalisée.',
    'btn_deconnecter'        => 'Déconnecter',
    'btn_annuler'            => 'Annuler',

    // ── Gestion utilisateurs — modal réinitialiser mot de passe
    'titre_reinit_mdp'   => 'Réinitialiser le mot de passe',
    'desc_reinit_mdp'    => 'Choisissez un mot de passe temporaire et communiquez-le à la personne. Elle devra le changer à sa première connexion ; ses sessions et ses postes seront déconnectés. L\'action est journalisée (jamais le mot de passe).',
    'label_mdp_temp'     => 'Mot de passe temporaire *',
    'btn_reinitialiser'  => 'Réinitialiser',

    // ── Gestion utilisateurs — modal créer/modifier
    'label_nom_complet'   => 'Nom complet *',
    'label_nom_utilisateur' => 'Nom d\'utilisateur *',
    'aide_nom_utilisateur'  => 'Lettres, chiffres, point, tiret et souligne. Sans arobase.',
    'label_email_utilisateur' => 'Email *',
    'label_role_utilisateur'  => 'Rôle *',
    'label_mdp_utilisateur'   => 'Mot de passe *',
    'label_mdp_utilisateur_modif' => 'Nouveau mot de passe',
    'placeholder_mdp_conserver'   => 'Laisser vide pour conserver le mot de passe actuel',
    'placeholder_mdp_min8'        => 'Minimum 8 caractères',
    'placeholder_selectionner'    => '-- Sélectionner --',
    'btn_enregistrer_utilisateur' => 'Enregistrer',
    'titre_modifier_utilisateur'  => 'Modifier l\'Utilisateur',
    'titre_creer_utilisateur'     => 'Nouvel Utilisateur',

    // ── Gestion utilisateurs — tooltip boutons
    'title_modifier'   => 'Modifier',
    'title_reinit_mdp' => 'Réinitialiser le mot de passe',
    'title_archiver'   => 'Archiver',
    'title_reactiver'  => 'Réactiver',
    'label_lecture_seule' => 'Lecture seule',

    // ── Rôles & Permissions — titres et descriptions
    'titre_roles_permissions'  => 'Rôles & Permissions',
    'desc_roles_permissions'   => 'Matrice de droits d\'accès et sauvegardes de la base de données.',

    // ── Rôles & Permissions — KPI
    'kpi_roles_configures'     => 'Rôles configurés',
    'kpi_utilisateurs_assignes' => 'Utilisateurs assignés',
    'kpi_modules_couverts'     => 'Modules couverts',
    'kpi_derniere_sauvegarde'  => 'Dernière sauvegarde',

    // ── Rôles & Permissions — avertissement lecture seule
    'info_admin_seulement'  => 'Seul l\'administrateur peut créer, modifier ou supprimer un rôle. Vous pouvez consulter la matrice ci-dessous en lecture seule.',

    // ── Rôles & Permissions — matrice
    'titre_matrice_droits'  => 'Matrice des Droits d\'Accès',

    // ── Rôles & Permissions — sauvegardes
    'titre_sauvegardes_bdd'  => 'Sauvegardes de la Base de Données',
    'btn_generer_sauvegarde' => 'Générer une Sauvegarde',
    'col_fichier'            => 'Fichier',
    'col_date'               => 'Date',
    'col_taille'             => 'Taille',
    'msg_aucune_sauvegarde'  => 'Aucune sauvegarde générée pour le moment.',

    // ── Rôles & Permissions — boutons
    'btn_nouveau_role'    => 'Nouveau Rôle',
    'title_modifier_role' => 'Modifier le rôle',
    'title_supprimer_role' => 'Supprimer le rôle',
    'title_role_protege'  => 'Rôle protégé, ne peut pas être supprimé',

    // ── Rôles & Permissions — modal rôle
    'label_nom_role'       => 'Nom du rôle *',
    'aide_nom_role'        => 'Lettres minuscules, chiffres et tirets uniquement.',
    'label_modules_autorises' => 'Modules autorisés',
    'titre_modifier_role'  => 'Modifier le Rôle',
    'titre_creer_role'     => 'Nouveau Rôle',

    // ── Modes de paiement — titres et descriptions
    'titre_modes_paiement'  => 'Modes de Paiement',
    'desc_modes_paiement'   => 'Comptes de trésorerie (Classe 5 SYSCOHADA) : caisse, banques et mobile money.',

    // ── Modes de paiement — KPI
    'kpi_solde_caisse'       => 'Solde Caisse (531)',
    'kpi_solde_banques'      => 'Solde Banques (521)',
    'kpi_solde_mobile_money' => 'Solde Mobile Money (5212)',

    // ── Modes de paiement — sections
    'section_caisse'        => 'Caisse Physique (531)',
    'section_banques'       => 'Comptes Bancaires - Multi-Banques (521)',
    'section_mobile_money'  => 'Mobile Money - Multi-Opérateurs (5212)',
    'statut_actif_compte'   => 'Actif',

    // ── Modes de paiement — labels champs banque
    'label_banque'          => 'Banque *',
    'label_titulaire'       => 'Titulaire du Compte',
    'label_rib'             => 'RIB *',
    'label_iban'            => 'IBAN *',
    'label_sous_compte'     => 'Sous-compte Auxiliaire',
    'label_operateur'       => 'Opérateur *',
    'label_numero_telephone' => 'Numéro de Téléphone *',
    'label_titulaire_ligne' => 'Titulaire de la Ligne',
    'label_numero_serie_sim' => 'Numéro de Série SIM',

    // ── Modes de paiement — messages vide
    'msg_aucun_compte_bancaire'   => 'Aucun compte bancaire pour le moment.',
    'msg_aucune_ligne_momo'       => 'Aucune ligne Mobile Money pour le moment.',

    // ── Modes de paiement — boutons
    'btn_ajouter_banque'      => 'Ajouter un Compte Bancaire',
    'btn_ajouter_momo'        => 'Ajouter une Ligne Mobile Money',
    'btn_virement_interne'    => 'Virement Interne',
    'btn_effectuer_virement'  => 'Effectuer le Virement',

    // ── Modes de paiement — modal virement
    'titre_virement_interne'  => 'Virement Interne',
    'desc_virement_interne'   => 'Déplace des fonds entre deux comptes de trésorerie. L\'opération n\'est ni un produit ni une charge : elle débite le compte destinataire et crédite le compte source au grand livre, sans toucher au résultat.',
    'label_compte_source'     => 'Compte source *',
    'label_compte_dest'       => 'Compte destinataire *',
    'label_montant_virement'  => 'Montant (FCFA) *',
    'label_motif_virement'    => 'Motif',
    'aide_virement_solde'     => 'Un virement supérieur au solde du compte source est refusé : on ne vire pas un argent dont on ne dispose pas.',

    // ── Modes de paiement — modal ajouter banque
    'titre_ajouter_banque'  => 'Ajouter un Compte Bancaire',
    'titre_ajouter_momo'    => 'Ajouter une Ligne Mobile Money',

    // ── Modules actifs — titres et descriptions
    'titre_modules_actifs'  => 'Modules Actifs',
    'desc_modules_actifs'   => 'Activez ou désactivez indépendamment chaque espèce d\'élevage. La désactivation masque les menus et onglets concernés, sans jamais toucher à la comptabilité générale.',
    'libelle_futur'         => 'FUTUR',
    'module_enabled_detail' => 'Fiches, VMS, catalogue POS liés à cette filière',
    'module_futur_detail'   => 'Module en préparation — désactivé par défaut',
    'module_assistant'      => 'Assistant de démarrage',
    'module_assistant_detail' => 'Guide la mise en route de la ferme — désactivé par défaut',
    'info_modules_actifs'   => 'Ces réglages sont appliqués immédiatement sur tous les onglets de Gestion Élevage et du Dashboard Élevage. Les données déjà enregistrées d\'une espèce désactivée restent conservées et réapparaissent dès la réactivation du module.',

    // ── Postes & Appairage — titres et descriptions
    'titre_postes_appairage'  => 'Postes & Appairage',
    'desc_postes_appairage'   => 'Postes Windows appairés au serveur : un poste est appairé dès qu\'un compte s\'y connecte, et le reste jusqu\'à l\'expiration de son jeton ou sa révocation.',

    // ── Postes & Appairage — tableau
    'col_poste'           => 'Poste',
    'col_utilisateur'     => 'Utilisateur',
    'col_appaire_le'      => 'Appairé le',
    'col_dernier_contact' => 'Dernier contact',
    'col_expiration'      => 'Expiration',
    'col_dernier_envoi'   => 'Dernier envoi',
    'col_dernier_controle' => 'Dernier contrôle',
    'col_etat'            => 'État',
    'sans_expiration'     => 'Sans expiration',
    'msg_aucun_poste'     => 'Aucun poste n\'est appairé au serveur pour le moment.',

    // ── Postes & Appairage — boutons
    'btn_demander_synchro'    => 'Demander la synchronisation des postes',
    'btn_actualiser'          => 'Actualiser',

    // ── Postes & Appairage — note info
    'info_appairage'  => '« Révoquer l\'appairage » supprime les jetons de ce poste, pour tous les comptes qui s\'y sont connectés : utile pour un poste perdu, volé ou remplacé. « Demander la synchronisation » dépose une demande que chaque poste connecté lit dans les 30 secondes ; c\'est lui qui envoie et reçoit. L\'adresse du serveur et l\'identifiant de chaque poste se consultent sur le poste lui-même (Paramètres > Appairage).',

    // ── Audit Logs — titres et descriptions
    'titre_audit_logs'  => 'Audit Logs & Sécurité',
    'desc_audit_logs'   => 'Historique horodaté des actions sensibles effectuées dans LogiAgriERP.',

    // ── Audit Logs — KPI
    'kpi_evenements_24h'       => 'Événements (24h)',
    'kpi_connexions_echouees'  => 'Connexions échouées',
    'kpi_connexions_sous'      => 'Sur les dernières 24 h',

    // ── Audit Logs — tableau
    'col_horodatage'  => 'Horodatage',
    'col_action'      => 'Action',
    'col_module'      => 'Module',
    'msg_aucun_evenement' => 'Aucun événement pour le moment.',
    'label_audit_lecture_seule' => 'Lecture seule',
    'title_audit_lecture_seule' => 'Les journaux d\'audit sont immuables : aucune modification ni suppression n\'est possible.',

    // ── Audit Logs — modal export
    'btn_exporter_journal'  => 'Exporter le Journal',
    'titre_exporter_journal' => 'Exporter le Journal',
    'label_periode_export'   => 'Période à exporter *',
    'label_format_export'    => 'Format d\'export *',

    // ── Barème ITS — titres et descriptions
    'titre_bareme_its'  => 'Barème IR-PTS / ITS',
    'desc_bareme_its'   => 'Impôt sur les Traitements et Salaires — retenu à la source, progressif, assis sur le net imposable (salaire dû moins CNSS salariale).',

    // ── Barème ITS — bannières état
    'info_premiere_config'       => 'Première configuration — à valider avant toute paie réelle',
    'detail_premiere_config'     => 'Le barème ci-dessous est une valeur de départ : ni le prototype ni le cahier des charges ne le documentent. Faites-le confirmer par le Cabinet FAGUEZ, puis enregistrez. Après cet enregistrement, seul un administrateur pourra le modifier.',

    // ── Barème ITS — tableau tranches
    'titre_tranches'    => 'Tranches d\'imposition',
    'col_de'            => 'De (FCFA)',
    'col_a'             => 'À (FCFA)',
    'col_taux'          => 'Taux (%)',
    'btn_ajouter_tranche' => 'Ajouter une tranche',
    'aide_tranches'       => 'La première tranche part de 0, chaque tranche reprend exactement où la précédente s\'arrête, et la dernière reste sans plafond. Un barème troué ou chevauchant produirait un impôt faux sans lever la moindre erreur.',
    'btn_enregistrer_bareme' => 'Enregistrer le barème',

    // ── Barème ITS — simulation
    'titre_simulation'          => 'Simulation',
    'label_brut_simule'         => 'Salaire brut mensuel (FCFA)',
    'sim_salaire_du'            => 'Salaire dû',
    'sim_cnss_salariale'        => '− CNSS salariale',
    'sim_net_imposable'         => '= Net imposable',
    'sim_its'                   => '− ITS',
    'sim_net_a_payer'           => 'NET À PAYER',
    'sim_charges_patronales'    => 'Charges patronales en sus :',
    'sim_bareme_vide'           => 'Aucune tranche enregistrée : l\'ITS est nul faute de barème, et non parce que le salaire serait sous le seuil.',

    // ── Corbeille — titres et descriptions
    'titre_corbeille'  => 'Corbeille',
    'desc_corbeille'   => 'Rien n\'est effacé par erreur : tout enregistrement retiré d\'un module est archivé ici. Restaurez-le, ou supprimez-le définitivement quand il n\'a aucune conséquence.',

    // ── Corbeille — KPI
    'kpi_archives'     => 'Éléments archivés',
    'kpi_restaurables' => 'Restaurables',
    'kpi_supprimables' => 'Suppression définitive possible',

    // ── Corbeille — info
    'info_corbeille'  => 'Les écritures comptables n\'apparaissent pas ici : une écriture ne se supprime pas, elle se contre-passe. Les comptes utilisateurs non plus : leur réactivation se fait depuis Gestion Utilisateurs. Une dépense, une vente annulée ou un transfert annulé se consulte ici mais ne se restaure pas : sa contre-passation ou son mouvement ne seraient pas rejoués.',

    // ── Corbeille — filtres
    'label_recherche'       => 'Recherche',
    'placeholder_recherche' => 'Rechercher un élément archivé…',
    'label_type'            => 'Type',
    'filtre_tous_types'     => 'Tous les types',
    'label_archive_du'      => 'Archivé du',
    'label_archive_au'      => 'Au',
    'btn_reinitialiser_filtres' => 'Réinitialiser',

    // ── Corbeille — tableau
    'col_type'        => 'Type',
    'col_element'     => 'Élément',
    'col_detail'      => 'Détail',
    'col_archive_le'  => 'Archivé le',
    'col_archive_par' => 'Archivé par',
    'msg_corbeille_vide'           => 'La corbeille est vide — aucun élément archivé.',
    'msg_aucun_element_recherche'  => 'Aucun élément archivé ne correspond à cette recherche.',
    'btn_restaurer'                => 'Restaurer',
    'btn_supprimer_definitif'      => 'Supprimer définitivement',
    'prefix_non_restaurable'       => 'Non restaurable :',
    'prefix_suppression_impossible' => 'Suppression définitive impossible :',

    // ── Corbeille — modal suppression définitive
    'titre_suppression_definitive'  => 'Supprimer définitivement ?',
    'label_saisir_supprimer'        => 'Pour confirmer, saisissez le mot SUPPRIMER',
    'btn_supprimer_definitif_confirm' => 'Supprimer définitivement',

    // ── Sauvegardes — titres et descriptions
    'titre_sauvegardes'  => 'Sauvegardes de la Base de Données',
    'desc_sauvegardes'   => 'Une sauvegarde automatique est générée chaque nuit et conservée 30 jours. Téléchargez-la régulièrement : un fichier resté sur le serveur ne protège de rien si le serveur tombe.',

    // ── Sauvegardes — export module
    'section_export_module'  => 'Exporter un module seul',
    'label_choisir_module'   => '-- Choisir un module --',
    'btn_exporter_module'    => 'Exporter ce module',
    'aide_export_module'     => 'Un export de module contient les données de ce module uniquement, sans le schéma : il sert à transmettre ou à analyser, jamais à restaurer une exploitation complète.',

    // ── Sauvegardes — import module
    'section_import_module'  => 'Importer un module',
    'info_import_module'     => 'Le fichier est analysé, jamais exécuté : seules les insertions vers les tables du module choisi sont retenues. Toute autre instruction est refusée et signalée.',
    'label_sauvegarde'       => 'Sauvegarde',
    'label_choisir_fichier'  => '-- Choisir un fichier --',
    'label_module_cible'     => 'Module cible',
    'btn_importer'           => 'Importer',

    // ── Sauvegardes — modal import
    'titre_import_module'   => 'Remplacer les données de ce module ?',
    'desc_import_module'    => 'Les données actuelles du module sélectionné seront supprimées puis remplacées par celles du fichier. Les enregistrements d\'autres modules qui y font référence peuvent devenir orphelins. Générez une sauvegarde complète avant de poursuivre.',
    'btn_confirmer_import'  => 'Confirmer l\'import',

    // ── Sauvegardes — tableau fichiers
    'col_table'               => 'Table',
    'col_action'              => 'Action',
    'msg_aucune_sauvegarde_v2' => 'Aucune sauvegarde pour le moment — générez-en une avec le bouton ci-dessus.',
    'btn_telecharger'         => 'Télécharger',
    'btn_generer_sauvegarde_v2' => 'Générer une sauvegarde',

    // ── Réinitialisation — titres et descriptions
    'titre_reinitialisation'  => 'Réinitialisation des Données',
    'desc_reinitialisation'   => 'Vide les données d\'activité pour repartir d\'une base propre après une démonstration.',

    // ── Réinitialisation — mode démo
    'section_mode_demo'      => 'Mode démonstration',
    'desc_mode_demo'         => 'Tant qu\'il est désactivé, aucune réinitialisation n\'est possible — c\'est ce qui protège une exploitation en production d\'un effacement accidentel.',
    'mode_demo_actif'        => 'Activé',
    'mode_demo_inactif'      => 'Désactivé',

    // ── Réinitialisation — avertissement
    'titre_reinit_danger'   => 'Cette opération vide TOUTES les données d\'activité',
    'desc_reinit_danger'    => 'L\'application ne peut pas distinguer une vente de démonstration d\'une vente réelle : elles vivent dans la même table, avec la même forme. Ventes, achats, dépenses, mouvements de stock, fiches d\'élevage, soins, paies et écritures comptables seront supprimés — qu\'ils viennent d\'une démonstration ou d\'une activité réelle.',

    // ── Réinitialisation — blocs Supprimé / Conservé
    'section_supprime'  => 'Supprimé',
    'texte_supprime'    => 'Ventes et clients · Achats et fournisseurs · Dépenses · Mouvements de stock · Bandes, fiches journalières, transferts et soins vétérinaires · Employés, paies et stages · Écritures comptables, clôtures et immobilisations achetées · Courriers, archives et documents administratifs · Notifications',
    'texte_postes_reinit' => 'Les postes Windows effacent aussi leurs données d\'activité à leur prochaine synchronisation ; leurs saisies non encore envoyées sont perdues.',
    'section_conserve'  => 'Conservé',
    'texte_conserve'    => 'Comptes utilisateurs et rôles · Réglages de l\'entreprise · Plan comptable · Exercices et comptes de trésorerie · Catalogue produits · Espèces, rations, protocoles prophylactiques, normes de croissance · Centres de coût · Barème ITS · Modèles d\'attestation · Numérotation de l\'élevage · Immobilisations reprises d\'antériorité (remises hors comptabilité) · Journal d\'audit',

    // ── Réinitialisation — boutons
    'btn_reinitialiser_donnees'  => 'Réinitialiser les données',

    // ── Réinitialisation — modal
    'titre_modal_reinit'    => 'Réinitialiser toutes les données d\'activité ?',
    'desc_modal_reinit'     => 'Cette action est irréversible : les enregistrements supprimés ne passent pas par la corbeille et ne pourront pas être restaurés. Assurez-vous d\'avoir généré une sauvegarde de la base au préalable.',
    'label_saisir_reinit'   => 'Saisissez REINITIALISER pour confirmer',
    'btn_confirmer_reinit'  => 'Confirmer la réinitialisation',

    // ── Réinitialisation — état verrouillé
    'reinit_verrouillee'     => 'Réinitialisation verrouillée',
    'reinit_verrouilee_aide' => 'Activez le mode démonstration ci-dessus pour y accéder.',

    // ── Assistant de démarrage
    'titre_assistant'  => 'Bienvenue dans LogiAgriERP',
    'desc_assistant'   => 'Ce qu\'il faut en place avant la première saisie — constaté dans la base, pas à cocher.',
    'btn_plus_tard'    => 'Plus tard',
    'btn_terminer'     => 'Terminer',
    'label_recommande' => '(recommandé)',
    'btn_ouvrir_exercice' => 'Ouvrir l\'exercice',
    'btn_regler'          => 'Régler',

    'placeholder_sans_plafond' => 'sans plafond',
    'title_retirer_tranche'    => 'Retirer',
];
