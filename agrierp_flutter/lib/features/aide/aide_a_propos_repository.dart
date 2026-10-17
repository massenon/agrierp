import '../../core/auth/permissions_poste.dart';

/// Une carte de « Modules du Logiciel ».
class ModuleAide {
  const ModuleAide({
    required this.titre,
    required this.description,
    required this.ecran,
  });

  final String titre;
  final String description;

  /// Écran du poste que la carte ouvre.
  final EcranPoste ecran;
}

/// Une question de la foire aux questions.
class QuestionAide {
  const QuestionAide({required this.question, required this.reponse});

  final String question;
  final String reponse;
}

/// Contenu de `prototype_html/aide-a-propos.html` — de la DOCUMENTATION, pas des
/// données : aucune table, aucune requête, aucun tirage.
///
/// ⚠️⚠️ **LA PRÉSENTATION DES STRUCTURES SUIT LARAVEL, PAS LE PROTOTYPE.** Le
/// prototype écrit « en partenariat avec FAGUEZ SARL » et ne nomme que deux
/// structures ; la surface web (tickets 15.7 / 15.8) dit « avec
/// l'accompagnement du Cabinet FAGUEZ SARL. Édité par Dr MASSENON Rhodes,
/// Docteur en Génie Logiciel et IA » — les TROIS structures. Sur un fait
/// d'attribution, ce qui a été validé côté serveur l'emporte, comme pour le pied
/// de page des PDF.
///
/// ⚠️⚠️ **SIX RÉPONSES SUR SEPT SONT ÉCRITES POUR LE POSTE — DÉCISION DU
/// COMMANDITAIRE.** Le texte du prototype décrit la surface web : il envoie
/// l'utilisateur vers des menus que le poste n'a pas (« Enregistrer Sujets »,
/// « Clôture d'Exercice », la génération d'attestation), lui promet de
/// désactiver un module (le poste l'affiche seulement), de choisir un client
/// (la caisse ne vend qu'au Client Anonyme) et un « ruban d'accès rapide »
/// absent. Chaque réponse dit donc ce que le poste fait réellement, et nomme le
/// web quand c'est lui qui agit. Seule la première phrase de la dernière suit le
/// prototype.
///
/// ⚠️ **L'ALERTE D'AUTONOMIE SUIT LARAVEL, PAS LE PROTOTYPE** : le prototype dit
/// « alerte critique sous 3 jours » ; `RaiseFeedAutonomyAlertAction` lève
/// l'alerte à 3 jours ou moins et ne la déclare CRITIQUE qu'à 1 jour ou moins.
/// Sur une règle métier, le serveur l'emporte.
///
/// ⚠️ **CES TEXTES SONT DATÉS** : ils décrivent le poste d'aujourd'hui. Le jour
/// où il porte Enregistrer Sujets, la clôture ou les attestations, la réponse
/// correspondante devient fausse — à relire à chaque ticket qui porte un de ces
/// écrans.
class AideAProposRepository {
  const AideAProposRepository();

  /// ⚠️ Doit rester celle de `pubspec.yaml` : un test les compare. Une version
  /// affichée qui ne dit pas celle qui tourne rend un rapport de défaut
  /// inexploitable.
  static const version = '1.0.0';

  static const descriptionLogiciel =
      "Logiciel de gestion intégrée pour la Ferme École OLOUWACHEGOUN "
      "(Attan-Ewé, Ikpinlè, Adja-Ouèrè, Bénin), développé dans le cadre du "
      "Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB), avec "
      "l'accompagnement du Cabinet FAGUEZ SARL. Édité par Dr MASSENON Rhodes, "
      'Docteur en Génie Logiciel et IA.';

  static const couvertureLogiciel =
      "AgriERP couvre l'ensemble du cycle d'exploitation : élevage "
      '(cuniculture, aviculture, porciculture), ventes et POS, stocks, '
      'comptabilité SYSCOHADA, ressources humaines et facturation normalisée '
      'MeCeF.';

  /// Les douze modules, dans l'ordre de la maquette.
  static const modules = <ModuleAide>[
    ModuleAide(
      titre: 'Tableau de Bord',
      description:
          "Vue consolidée de l'activité de la ferme : ventes du jour, "
          'trésorerie, alertes de stock et effectifs vivants.',
      ecran: EcranPoste.tableauDeBord,
    ),
    ModuleAide(
      titre: 'Gestion Élevage',
      description:
          'Suivi des bandes/lots (Cuniculture, Aviculture, Porciculture), '
          'fiches journalières, reproduction et transformation.',
      ecran: EcranPoste.gestionElevage,
    ),
    ModuleAide(
      titre: 'Soins et Vaccins',
      description:
          'Registre vétérinaire, calendrier de prophylaxie et suivi sanitaire '
          'du cheptel.',
      ecran: EcranPoste.soinsEtVaccins,
    ),
    ModuleAide(
      titre: 'Ventes & Devis',
      description:
          'Caisse POS, devis, historique des ventes et gestion des retours.',
      ecran: EcranPoste.ventesEtDevis,
    ),
    ModuleAide(
      titre: 'Clients et Créances',
      description:
          'Répertoire clients, suivi des dettes, relances et avances sur '
          'commande.',
      ecran: EcranPoste.clientsEtCreances,
    ),
    ModuleAide(
      titre: 'Achats & Commandes',
      description:
          'Enregistrement des achats, bons de commande et suivi des '
          'livraisons fournisseurs.',
      ecran: EcranPoste.achatsEtCommandes,
    ),
    ModuleAide(
      titre: 'Gestion Stocks',
      description:
          "Valorisation des stocks, mouvements, ajustements d'inventaire.",
      ecran: EcranPoste.gestionStocks,
    ),
    ModuleAide(
      titre: 'Facturation & MeCeF',
      description:
          'Facturation normalisée conforme à la réglementation fiscale '
          'béninoise (DGI).',
      ecran: EcranPoste.facturation,
    ),
    ModuleAide(
      titre: 'Personnel & Stages',
      description:
          'Registre du personnel, pointage, paie et attestations de '
          'travail/stage.',
      ecran: EcranPoste.personnelEtStages,
    ),
    ModuleAide(
      titre: 'Comptabilité',
      description:
          "Journal comptable, bilan, comptabilité analytique et clôture "
          "d'exercice (SYSCOHADA).",
      ecran: EcranPoste.comptabilite,
    ),
    ModuleAide(
      titre: 'Administration',
      description:
          'Gestion des courriers, archivage des documents et documents '
          'administratifs de la ferme.',
      ecran: EcranPoste.administrationEtDocument,
    ),
    ModuleAide(
      titre: 'Rapports & Exports',
      description:
          'États financiers et zootechniques : recettes/dépenses, '
          'trésorerie, créances, dettes, élevage, stocks.',
      ecran: EcranPoste.rapportsEtExports,
    ),
  ];

  /// Les sept questions, dans l'ordre de la maquette.
  static const questions = <QuestionAide>[
    QuestionAide(
      question: 'Comment enregistrer une nouvelle vente ?',
      reponse:
          'Rendez-vous dans Ventes & Devis > Enregistrer Vente, ajoutez les '
          'produits puis choisissez le mode de règlement. Le poste vend au '
          'Client Anonyme : une vente à crédit ou sur avance, qui suppose un '
          "client identifié, se fait sur l'application web.",
    ),
    QuestionAide(
      question: "Comment créer une nouvelle bande d'élevage ?",
      reponse:
          'Une bande ne se crée pas sur le poste : elle est enregistrée sur '
          "l'application web (Gestion Élevage > Enregistrer Sujets) et "
          'descend ici à la prochaine synchronisation. Une fois reçue, ouvrez '
          "Gestion Élevage, choisissez l'espèce et saisissez la fiche "
          'journalière de la bande.',
    ),
    QuestionAide(
      question: "Comment fonctionne l'alerte de stock d'aliment ?",
      reponse:
          "Le serveur calcule l'autonomie en jours (stock disponible ÷ "
          "consommation théorique du cheptel) et lève une alerte dès qu'elle "
          'descend à 3 jours ou moins, critique à 1 jour ou moins. Le poste ne '
          "calcule pas cette autonomie : l'alerte lui parvient à la "
          'synchronisation, dans le Centre de Notifications (la cloche).',
    ),
    QuestionAide(
      question: 'Comment générer une attestation de travail ou de stage ?',
      reponse:
          'Le poste ne génère pas les attestations : un document officiel '
          "exige l'en-tête, le filigrane, la signature numérisée et le cachet "
          "de la ferme, qu'il n'embarque pas. La génération se fait sur "
          "l'application web (Personnel & Stages > Attestations).",
    ),
    QuestionAide(
      question: 'Comment activer ou désactiver un module (ex. Escargots) ?',
      reponse:
          'Paramètres Général > Modules Actifs montre quelles espèces la ferme '
          "exploite. L'activation ou la désactivation se fait sur "
          "l'application web ; elle atteint le poste à la synchronisation, et "
          "une espèce désactivée disparaît alors de ses fiches.",
    ),
    QuestionAide(
      question: 'Comment clôturer un exercice comptable ?',
      reponse:
          "La clôture d'exercice se fait uniquement sur l'application web, "
          'en 3 étapes : inventaire, solde des comptes, écritures '
          "d'à-nouveaux. Elle ne se lance pas depuis un poste, qui peut ne pas "
          'avoir reçu les dernières pièces : la page Comptabilité > Clôture '
          'Périodique & Annuelle du poste le rappelle.',
    ),
    QuestionAide(
      question:
          "Comment masquer la barre latérale pour plus d'espace de travail ?",
      // ⚠️ ADAPTÉE : voir l'en-tête de la classe (pas de ruban d'accès rapide).
      reponse:
          "Cliquez sur l'icône de menu à côté du fil d'Ariane dans l'en-tête. "
          "Cliquez de nouveau dessus pour la rétablir.",
    ),
  ];

  /// Questions retenues par la recherche.
  ///
  /// ⚠️ **COMME LE PROTOTYPE : LA QUESTION ET LA RÉPONSE.** Il compare le terme
  /// au `textContent` de l'élément entier ; chercher « stock » ramène donc aussi
  /// les réponses qui en parlent. Comparaison en minuscules faite en Dart — pas
  /// de `LIKE`, qui ne ramène pas la casse hors ASCII (« Élevage »).
  static List<QuestionAide> rechercher(String terme) {
    final t = terme.toLowerCase().trim();
    if (t.isEmpty) return questions;

    return [
      for (final q in questions)
        if (q.question.toLowerCase().contains(t) ||
            q.reponse.toLowerCase().contains(t))
          q,
    ];
  }
}
