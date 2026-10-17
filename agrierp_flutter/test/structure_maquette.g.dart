// GÉNÉRÉ — structure des écrans du prototype.
//
// ⚠️⚠️ **NE PAS ÉDITER À LA MAIN.** Produit par `outils/structure.py`
// depuis `prototype_html`. Le contrôle de vocabulaire (F0.42) vérifie que
// chaque MOT existe ; celui-ci vérifie la STRUCTURE — la suite ordonnée des
// colonnes de chaque tableau, et le nombre de cartes d'indicateur.
//
// Un tableau dont les colonnes sont dans le désordre, ou dont une colonne
// du milieu manque, passe le contrôle de vocabulaire sans broncher : chaque
// mot pris séparément est bien présent quelque part dans l'écran.
//
// ⚠️ LES EN-TÊTES À DEUX NIVEAUX SONT APLATIS SUR LEURS FEUILLES : la
// Balance Générale coiffe trois groupes (`colspan=2`) d'une rangée
// Débit/Crédit — huit colonnes réelles, pas onze.
//
// Régénération : `python outils/structure.py <pages...>`
library;

/// Suites ordonnées d'en-têtes de colonnes, par page.
const tableauxMaquette = <String, List<List<String>>>{
  'ajouter-fournisseur.html': [
    ["Nom", "Contact", "Catégorie", "Statut", "Actions"],
  ],
  'archivage-documents.html': [
    [
      "Document",
      "Catégorie",
      "Date Archivage",
      "Expiration",
      "Statut",
      "Actions",
    ],
  ],
  'audit-logs.html': [
    ["Horodatage", "Utilisateur", "Action", "Module", "Actions"],
  ],
  'balance-generale.html': [
    [
      "N° Compte",
      "Libellé",
      "Débit",
      "Crédit",
      "Débit",
      "Crédit",
      "Débit",
      "Crédit",
    ],
  ],
  'bons-commande.html': [
    ["Produit", "Qté", "P.U", "Total", "(sans libelle)"],
    [
      "Réf Commande",
      "Date d'Émission",
      "Livraison Attendue",
      "Fournisseur",
      "Montant Estimé",
      "Statut",
      "Actions",
    ],
  ],
  'catalogue-view.html': [
    ["SKU", "Désignation", "Catégorie", "Stock", "Tarif", "Actions"],
  ],
  'dettes-fournisseurs.html': [
    ["Fournisseur", "Montant Dû", "Échéance", "Statut", "Actions"],
  ],
  'documents-administratifs.html': [
    ["Document", "Type", "Bénéficiaire", "Date", "Statut", "Actions"],
  ],
  'elevage-dashboard.html': [
    [
      "Bande",
      "Espèce",
      "Dernière Pesée",
      "Poids Précédent (g)",
      "Poids Actuel (g)",
      "Jours Écoulés",
      "GMQ (g/jour)",
      "Statut vs Objectif",
    ],
    [
      "Maladie / Symptôme",
      "Espèce",
      "Cas 2025",
      "Cas 2026",
      "Évolution",
      "Période de Sensibilité",
    ],
  ],
  'enregistrer-achat.html': [
    ["Designation", "Qte", "P.U", "Total", "(sans libelle)"],
    ["Reference", "Fournisseur", "Date", "Montant", "Statut", "Actions"],
  ],
  'facturation.html': [
    ["N° Facture", "Client", "Date", "Montant TTC", "Statut MeCeF", "Actions"],
  ],
  'feuille-pointage.html': [
    ["Employé", "Date", "Arrivée", "Départ", "Statut", "Actions"],
  ],
  'fiches-fournisseurs.html': [
    [
      "(sans libelle)",
      "Nom",
      "Catégorie",
      "Total Achats (Année)",
      "Dernière commande",
      "Statut",
      "Actions",
    ],
  ],
  'gestion-courriers.html': [
    ["Référence", "Type", "Objet", "Partie", "Date", "Actions"],
  ],
  'gestion-paie.html': [
    [
      "Employé",
      "Poste",
      "Salaire Brut",
      "Absences",
      "Ret. Absences",
      "Ret. CNSS",
      "Net à Payer",
      "Statut",
      "Actions",
    ],
  ],
  'gestion-stocks.html': [
    [
      "Code",
      "Designation",
      "Categorie",
      "Stock",
      "PMP Unit.",
      "Valeur",
      "Urgence",
      "Actions",
    ],
    [
      "Date / Heure",
      "Reference",
      "Produit",
      "Type",
      "Motif",
      "Quantite",
      "Valeur",
    ],
  ],
  'gestion-utilisateurs.html': [
    ["Nom", "Email", "Rôle", "Statut", "Actions"],
  ],
  'grand-livre.html': [
    ["Date", "N° Pièce", "Libellé", "Débit", "Crédit", "Solde Progressif"],
  ],
  'historique-avances.html': [
    ["Client", "Montant Avance", "Solde Restant", "Date", "Statut", "Actions"],
  ],
  'historique-ventes.html': [
    [
      "Facture",
      "Client",
      "Date",
      "Articles",
      "Remise",
      "Total TTC",
      "Payé",
      "Reste",
      "Mode",
      "Statut",
      "Actions",
    ],
    ["Désignation", "Qté", "P.U", "Total"],
    ["Désignation", "Qté", "P.U", "Total"],
  ],
  'journal-comptable.html': [
    ["N° Pièce", "Date", "Libellé", "Débit", "Crédit", "Montant", "Actions"],
  ],
  'liste-achats.html': [
    [
      "Référence Achat",
      "Date",
      "Fournisseur",
      "Catégorie",
      "Montant Total",
      "Statut",
      "Actions",
    ],
  ],
  'liste-clients.html': [
    [
      "(sans libelle)",
      "Nom",
      "Téléphone",
      "Ville",
      "Total Achats",
      "Solde Dû",
      "Statut",
      "Actions",
    ],
  ],
  'parametres-elevage.html': [
    [
      "Espèce",
      "Stade Physiologique / Tranche d'Âge",
      "Ration Normative (g / tête / jour)",
      "Actions",
    ],
    [
      "Jour / Période",
      "Traitement Prévu",
      "Produit Conseillé",
      "Posologie",
      "Délai Rémanence",
      "Actions",
    ],
    [
      "Nom du Type d'Aliment",
      "Espèce Cible",
      "Poids Sac Standard (Kg)",
      "Prix Indicatif (FCFA / Kg)",
      "Actions",
    ],
  ],
  'plan-comptable.html': [
    ["N° Compte", "Intitulé", "Classe", "Actions"],
  ],
  'registre-employes.html': [
    ["Nom", "Fonction", "Date d'embauche", "Salaire", "Statut", "Actions"],
  ],
  'registre-stagiaires.html': [
    [
      "Nom",
      "Établissement d'Origine",
      "Période",
      "Frais de Scolarité",
      "Statut",
      "Actions",
    ],
  ],
  'roles-permissions.html': [
    [
      "Role",
      "Dashboard",
      "Ventes & Devis",
      "Achats & Charges",
      "Stocks",
      "Elevage & Soins",
      "RH",
      "Comptabilite",
      "Administration",
      "Parametres",
      "Actions",
    ],
    ["Fichier", "Date", "Taille", "Actions"],
  ],
  'seuils-alerte.html': [
    ["Produit", "Stock actuel", "Seuil configuré", "Statut", "Actions"],
  ],
  'suivi-dettes.html': [
    [
      "Débiteur",
      "Facture Associée",
      "Échéance",
      "Total Facturé",
      "Solde Restant",
      "Actions",
    ],
  ],
  'suivi-reproduction.html': [
    [
      "Bande",
      "N° Lapine",
      "Date Saillie",
      "Mâle N°",
      "Résultat Palpation",
      "Nés (Vivants)",
      "Sevrés (M/F)",
      "Morts S/Mère",
      "Poids Moyen (g)",
      "Cages",
      "Statut Physio",
      "Actions Cycle",
    ],
    [
      "Code Incubation",
      "Bande Reproducteurs",
      "Date Incubation (J0)",
      "Éclosion Attendue (J+21)",
      "Œufs Couvés",
      "Poussins Nés",
      "Taux Éclosion (%)",
      "Parc / Bâtiment",
      "Statut",
      "Action",
    ],
    [
      "Bande",
      "N° Truie",
      "Date Saillie",
      "Verrat N°",
      "Retour Chaleur (J+21)",
      "Mise Bas Attendue (J+114)",
      "Porcelets Nés",
      "Sevrage (J+42)",
      "Statut Physio",
      "Action",
    ],
    [
      "Parc / Fosse",
      "Code Bac Ponte",
      "Date Placement",
      "Œufs Pondus (terre)",
      "Éclosion Attendue (J+25)",
      "Naissains Nés",
      "Taux Éclosion (%)",
      "Statut",
      "Action",
    ],
  ],
  'vms-calendrier.html': [
    [
      "Lot / Bande",
      "19/7",
      "20/7",
      "21/7",
      "22/7",
      "23/7",
      "24/7",
      "25/7",
      "26/7",
      "27/7",
      "28/7",
      "29/7",
      "30/7",
      "31/7",
      "1/8",
    ],
  ],
  'vms-registre.html': [
    [
      "Date",
      "Lot / Espèce",
      "Type d'action",
      "Produit",
      "Dose",
      "Statut",
      "Actions",
    ],
  ],
  'rapport-recettes-depenses.html': [
    ["Date", "Libellé", "Montant"],
    ["Date", "Libellé", "Montant"],
  ],
  'rapport-tresorerie.html': [
    ["Date", "Solde Caisse", "Solde Banque", "Solde Total", "Actions"],
  ],
  'rapport-creances.html': [
    ["Client", "Montant Dû", "Échéance", "Actions"],
  ],
  'rapport-dettes.html': [
    ["Fournisseur", "Montant Dû", "Échéance", "Actions"],
  ],
  'rapport-elevage-synth.html': [
    [
      "Date",
      "Lot / Souche",
      "Mères Pondeuses",
      "Mères Couveuses",
      "Mères Éleveuses",
      "Poussins S/Mères",
      "Sevrés M",
      "Sevrés F",
      "Morts M",
      "Morts F",
      "Morts SM",
      "Géniteurs",
      "Effectif Malade",
    ],
    [
      "Date",
      "Lot",
      "Sexe Vendu",
      "Qté Vendue",
      "Montant Vente (FCFA)",
      "Effectif Final",
      "Traitement Administré",
      "Dose",
      "Signes de Maladie Observés",
    ],
    [
      "Âge (Sem.)",
      "Jour",
      "Total Œufs Récoltés (OR)",
      "Taux Ponte %",
      "Cassés/Fêlés (OF)",
      "Commercialisables (OR-OF)",
      "Stock Restant Hier (SRH)",
      "Total Stock (TS)",
      "Sorties Vente OS (Plateaux)",
      "Stock Final (Plateaux + Vrac)",
    ],
  ],
  'rapport-stocks-synth.html': [
    ["Catégorie", "Valeur Stock", "Sous Seuil", "Actions"],
  ],
  'mon-profil.html': [
    ["Date / Heure", "Action", "Module", "IP"],
  ],
  'notifications.html': [
    ["Date / Heure", "Catégorie", "Message", "Gravité", "Statut", "Actions"],
  ],
  'animal-details.html': [
    ["Action", "Impact Automatique"],
    ["Date", "Type d'Opération", "Détail", "Opérateur"],
    ["Date", "Aliment", "Quantité", "Coût"],
    ["Date", "Traitement / Vaccin", "Dose", "Vétérinaire"],
    [
      "Date Saillie",
      "Mâle",
      "Mise Bas Prévue (J+31)",
      "Nés",
      "Vivants",
      "Statut",
    ],
    ["Date", "Type", "Détail"],
  ],
  'ajouter-produit.html': [
    ["Produit", "Catégorie", "Prix Unitaire", "Statut", "Actions"],
  ],
  'profile-fournisseur.html': [
    ["Reference", "Date", "Categorie", "Montant", "Statut"],
    ["BC N", "Emission", "Livraison", "Montant", "Statut"],
  ],
};

/// Nombre de cartes d'indicateur (`border-l-4`), par page.
const cartesMaquette = <String, int>{
  'ajouter-fournisseur.html': 2,
  'archivage-documents.html': 2,
  'audit-logs.html': 2,
  'balance-generale.html': 2,
  'bons-commande.html': 0,
  'catalogue-view.html': 0,
  'dettes-fournisseurs.html': 3,
  'documents-administratifs.html': 2,
  'elevage-dashboard.html': 15,
  'enregistrer-achat.html': 0,
  'facturation.html': 3,
  'feuille-pointage.html': 3,
  'fiches-fournisseurs.html': 2,
  'gestion-courriers.html': 3,
  'gestion-paie.html': 4,
  'gestion-stocks.html': 4,
  'gestion-utilisateurs.html': 2,
  'grand-livre.html': 3,
  'historique-avances.html': 3,
  'historique-ventes.html': 4,
  'journal-comptable.html': 3,
  'liste-achats.html': 4,
  'liste-clients.html': 3,
  'modes-paiement.html': 3,
  'modules-actifs.html': 0,
  'parametres-elevage.html': 0,
  'parametres.html': 0,
  'plan-comptable.html': 2,
  'registre-employes.html': 2,
  'registre-stagiaires.html': 4,
  'roles-permissions.html': 4,
  'seuils-alerte.html': 2,
  'suivi-dettes.html': 4,
  'suivi-reproduction.html': 4,
  'vms-calendrier.html': 0,
  'vms-registre.html': 4,
  'rapports-exports.html': 0,
  'rapport-recettes-depenses.html': 3,
  'rapport-tresorerie.html': 0,
  'rapport-creances.html': 0,
  'rapport-dettes.html': 0,
  'rapport-elevage-synth.html': 4,
  'rapport-stocks-synth.html': 0,
  'mon-profil.html': 0,
  'notifications.html': 3,
  'aide-a-propos.html': 0,
  'contact-editeur.html': 0,
  'bilan-technico-economique.html': 4,
  'rh-attestations.html': 0,
  'animal-details.html': 3,
  'ajouter-produit.html': 2,
  'profile-fournisseur.html': 0,
};

/// Cartes d'indicateur par PANNEAU d'onglet, pour les pages qui portent tous
/// leurs onglets dans un seul fichier.
///
/// ⚠️⚠️ **LE TOTAL NE SUFFIT PAS SUR CES PAGES-LÀ** (ticket F0.54). Un écran
/// peut en oublier quatre sur un onglet et en ajouter trois sur un autre : la
/// somme passerait presque. C'est exactement ce qui s'est produit sur
/// `elevage-dashboard.html` — 11 rendues contre 15 relevées, l'écart réel
/// étant de **−4 sur « Bilan », −3 sur « Prévision » et +3 sur « Sanitaire »**.
/// Le relevé par panneau permet au contrôle de dire OÙ.
const cartesParPanneau = <String, Map<String, int>>{
  'elevage-dashboard.html': {
    'dash-tab-synthese': 4,
    'dash-tab-gmq': 4,
    'dash-tab-bilan': 4,
    'dash-tab-sanitaire': 0,
    'dash-tab-prevision': 3,
  },
  'gestion-stocks.html': {
    'stock-tab-tableau': 0,
    'stock-tab-mouvements': 0,
    'stock-tab-ajustements': 0,
  },
};
