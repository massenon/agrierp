import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/sync_columns.dart';

/// Résultat d'une synchronisation, rendu à l'écran tel quel.
///
/// ⚠️ LES REJETS SONT PORTÉS JUSQU'À L'UTILISATEUR. Le serveur répond table
/// par table avec les identifiants acceptés ET rejetés (avec motif) plutôt
/// qu'un « 200 OK » muet — précisément pour qu'un rejet ne disparaisse pas en
/// silence. Les avaler ici annulerait cette précaution : l'éleveur croirait
/// sa fiche envoyée alors qu'elle a été refusée.
class SyncOutcome {
  const SyncOutcome({
    required this.tire,
    required this.accepte,
    required this.rejete,
    this.motifs = const [],
    this.avertissements = const [],
    this.horsLigne = false,
  });

  const SyncOutcome.horsLigne()
    : tire = 0,
      accepte = 0,
      rejete = 0,
      motifs = const [],
      avertissements = const [],
      horsLigne = true;

  final int tire;
  final int accepte;
  final int rejete;
  final List<String> motifs;

  /// Ce que le tirage a constaté SANS refuser (ticket F0.84-bis) : journal à confirmer ou incomplet.
  /// Jamais un succès muet : l'écran le montre.
  final List<String> avertissements;
  final bool horsLigne;
}

/// Moteur de synchronisation — moitié cliente.
///
/// La moitié serveur existe déjà (`POST /api/auth/login`, `GET /api/sync/pull`,
/// `POST /api/sync/push`, jeton Sanctum nommé par appareil).
///
/// ⚠️ **PULL AVANT PUSH, TOUJOURS.** Pousser d'abord ferait travailler le
/// serveur sur des référentiels que l'appareil n'a pas encore reçus : une
/// vente portant un produit créé ailleurs serait rejetée pour « produit
/// inconnu » alors qu'il existe. Tirer d'abord rend ce rejet impossible.
///
/// ⚠️ **RIEN N'EST MARQUÉ `synced` AVANT L'ACCUSÉ DU SERVEUR.** Marquer à
/// l'envoi ferait disparaître de la file un enregistrement perdu en route :
/// l'appareil le croirait synchronisé et il n'existerait nulle part.
class SyncEngine {
  SyncEngine({
    required AppDatabase database,
    required Dio client,
    required String deviceId,
    Connectivity? connectivity,
    DateTime Function()? maintenant,
  }) : // `prefer_initializing_formals` suggère `this._client` : Dart
       // l'interdit sur un paramètre NOMMÉ privé. L'affectation explicite
       // est donc la seule forme possible ici.
       // ignore: prefer_initializing_formals
       _client = client,
       // ignore: prefer_initializing_formals
       _deviceId = deviceId,
       _db = database,
       _connectivity = connectivity ?? Connectivity(),
       _maintenant = maintenant ?? DateTime.now;

  final AppDatabase _db;
  final Dio _client;
  final String _deviceId;
  final Connectivity _connectivity;

  /// Horloge du poste — injectable pour les tests (F0.90). Elle date la RÉCEPTION d'une vente
  /// tirée du serveur (voir [_absorberVentes]).
  final DateTime Function() _maintenant;

  String get deviceId => _deviceId;

  Future<bool> estEnLigne() async {
    final etats = await _connectivity.checkConnectivity();
    return etats.any((e) => e != ConnectivityResult.none);
  }

  Future<SyncOutcome> synchroniser() async {
    if (!await estEnLigne()) {
      // ⚠️ HORS LIGNE N'EST PAS UNE ERREUR. C'est le mode de fonctionnement
      // NORMAL de cette ferme : le réseau est intermittent à Ikpinlè. Un
      // message d'erreur rouge à chaque tentative apprendrait à l'utilisateur
      // à ignorer les alertes — y compris les vraies.
      return const SyncOutcome.horsLigne();
    }

    _avertissements.clear();
    var tire = await _tirer();
    final (accepte, rejete, motifs) = await _pousser();

    // ⚠️ TIRAGE DE CONFIRMATION (ticket F0.73). Le poste tire AVANT de pousser : une
    // avance ou une imputation que le serveur vient d'accepter a modifié, côté serveur,
    // `amount_used` et `amount_paid` — que le poste affiche encore dans leur état
    // d'avant. Sans ce second tirage, une imputation acquittée cesse d'être « en attente »
    // (donc d'être déduite à l'écran) sans que le solde servi l'ait absorbée : le solde
    // REMONTERAIT jusqu'à la synchronisation suivante, et l'utilisateur pourrait imputer
    // une deuxième fois ce qui l'est déjà. Un échec réseau ici n'annule rien : tout est
    // déjà acquitté.
    // F0.78 : même tirage pour un courrier accepté — sans lui, sa référence resterait « — »
    // jusqu'à la synchronisation suivante.
    // F0.79 : et pour un document archivé accepté — le tirage de confirmation montre ce que
    // le serveur a réellement retenu (le poste n'invente aucune valeur côté serveur).
    // F0.80 : et pour un document administratif accepté — même raison.
    if (_financiersAcquittes > 0 ||
        _courriersAcquittes > 0 ||
        _archivesAcquittees > 0 ||
        _documentsAcquittes > 0) {
      try {
        tire += await _tirer();
      } on DioException {
        // L'affichage reste celui du tirage précédent jusqu'à la prochaine synchronisation.
      }
    }

    return SyncOutcome(
      tire: tire,
      accepte: accepte,
      rejete: rejete,
      motifs: motifs,
      avertissements: List.of(_avertissements),
    );
  }

  /// Avances, imputations, retours et remboursements fournisseurs acceptés par le dernier
  /// envoi (voir [synchroniser]) : tous modifient, côté serveur, un état que le poste affiche
  /// (`amount_used`, `returned_at`, créance ouverte) et que seul un second tirage rapporte.
  int _financiersAcquittes = 0;

  /// Courriers acceptés par le dernier envoi : la référence `CR-AAAA-NNN` que le serveur
  /// vient d'attribuer ne descend qu'au tirage suivant (F0.78).
  int _courriersAcquittes = 0;

  /// Documents archivés acceptés par le dernier envoi (F0.79) : déclenchent le tirage de
  /// confirmation.
  int _archivesAcquittees = 0;

  /// Documents administratifs acceptés par le dernier envoi (F0.80) : déclenchent le tirage de
  /// confirmation.
  int _documentsAcquittes = 0;

  /// Réglages (table `app_settings`, sans changement de schéma) du journal comptable — F0.84-bis.
  ///
  ///  - [cleJournalResync] : la resynchronisation UNIQUE du journal a été faite. Absente = le
  ///    premier tirage après la mise à jour redemande TOUT le journal (sans `since`) : un poste
  ///    corrompu avant F0.84 (lignes doublées sur une écriture ancienne, jamais retouchée) n'est
  ///    pas guéri par la purge, et le tirage incrémental ne la servira jamais.
  ///  - [cleJournalIncomplet] : le dernier tirage complet n'a pas pu rapporter toutes les écritures
  ///    annoncées actives. Présente = le prochain tirage est de nouveau complet (borné : 2 requêtes).
  ///  - [cleJournalVidageAttendu] : le serveur a annoncé UNE fois « aucune écriture active » alors
  ///    que le poste en contient. Présente = la prochaine annonce vide sera crue et purgera.
  ///  - [cleJournalResyncCreation] (F0.85) : la resynchronisation UNIQUE qui rapporte l'instant de
  ///    CRÉATION des écritures déjà présentes (colonne `created_at`, ajoutée au schéma v37). Il sert
  ///    au Grand Livre à départager deux pièces du même jour comme le serveur. ⚠️ Le réglage n'est
  ///    écrit que si le serveur SERT cette date : face à un serveur qui ne la sert pas encore (ticket
  ///    15.29 non déployé), le tirage reste complet à chaque synchronisation tant que cela dure —
  ///    sans quoi la date ne serait plus jamais rapportée une fois le serveur mis à jour.
  ///  - [cleFichesResync] (F0.94) : la resynchronisation UNIQUE des fiches journalières. Avant
  ///    F0.94 le poste n'absorbait pas `livestock_daily_entries` ; un poste déjà en service a un
  ///    curseur, et le tirage incrémental ne servirait JAMAIS les fiches modifiées avant lui (tout
  ///    l'historique saisi sur le web). Absente = le prochain tirage est complet, une fois.
  static const cleFichesResync = 'fiches_resync_f094';

  /// F0.95 — resynchronisation UNIQUE des fiches après le passage au schéma v38 : les fiches
  /// `synced` absorbées en v37 n'ont pas les colonnes d'effectif par catégorie, et le curseur est
  /// passé (le tirage incrémental ne les resservirait jamais). ⚠️ Écrite APRÈS tous les
  /// absorbeurs, et SEULEMENT si le serveur sert la ventilation (15.39) : face à un serveur pas
  /// encore à jour, le tirage reste complet à chaque synchronisation tant que cela dure (même
  /// règle que [cleJournalResyncCreation]) — sinon les colonnes ne descendraient jamais.
  static const cleFichesResyncCategories = 'fiches_resync_f095';

  /// Les dix colonnes de ventilation du serveur (migration `2026_10_15_000001`, 15.39).
  static const colonnesVentilation = [
    'mort_repro',
    'mort_sevre',
    'mort_jeune',
    'don_repro',
    'don_sevre',
    'don_jeune',
    'passage_sevre_jeune',
    'cat_depart_repro',
    'cat_depart_sevre',
    'cat_depart_jeune',
  ];

  /// Vrai si le dernier tirage a servi au moins une fiche SANS ces colonnes (serveur antérieur à
  /// 15.39) — renseigné par [_absorberFichesJournalieres].
  bool _fichesSansVentilation = false;
  static const cleJournalResync = 'journal_resync_f084bis';
  static const cleJournalResyncCreation = 'journal_resync_f085';
  static const cleJournalIncomplet = 'journal_incomplet';
  static const cleJournalVidageAttendu = 'journal_vidage_attendu';

  /// Ce que la synchronisation en cours a constaté sans refuser (voir [SyncOutcome.avertissements]).
  final List<String> _avertissements = [];

  /// Écritures annoncées actives par le dernier tirage et toujours absentes du poste après
  /// absorption (renseigné par [_absorberJournal]).
  int _journalManquants = 0;

  /// Vrai si le dernier tirage a servi au moins une écriture SANS la clé `created_at` (serveur
  /// antérieur au ticket 15.29) — renseigné par [_absorberJournal].
  bool _journalSansDateCreation = false;

  Future<String?> _lireReglage(String cle) async {
    final ligne = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(cle))).getSingleOrNull();
    return ligne?.value;
  }

  Future<void> _ecrireReglage(String cle, String valeur) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: cle, value: valeur),
      );

  Future<void> _effacerReglage(String cle) =>
      (_db.delete(_db.appSettings)..where((t) => t.key.equals(cle))).go();

  /// Récupère du serveur tout ce qui a changé depuis le dernier tirage.
  ///
  /// [complet] : tirage SANS `since`. Il sert (1) à la resynchronisation unique du journal,
  /// (2) à la relance unique quand le serveur annonce des écritures actives que le poste n'a
  /// pas, (3) au tirage qui suit un journal resté incomplet.
  Future<int> _tirer({bool complet = false}) async {
    // ⚠️ Lecture TOLÉRANTE : voir `etatDeSynchronisation` (table dupliquée).
    final etat = await _db.etatDeSynchronisation();

    final resyncFaite = await _lireReglage(cleJournalResync) != null;
    final resyncCreationFaite =
        await _lireReglage(cleJournalResyncCreation) != null;
    final etaitIncomplet = await _lireReglage(cleJournalIncomplet) != null;
    final resyncFichesFaite = await _lireReglage(cleFichesResync) != null;
    final resyncCategoriesFaite =
        await _lireReglage(cleFichesResyncCategories) != null;
    final toutRedemander =
        complet ||
        !resyncFaite ||
        !resyncCreationFaite ||
        etaitIncomplet ||
        !resyncFichesFaite ||
        !resyncCategoriesFaite;

    final reponse = await _client.get<Map<String, dynamic>>(
      '/api/sync/pull',
      queryParameters: {
        if (!toutRedemander && etat?.lastPulledAt != null)
          'since': etat!.lastPulledAt!.toUtc().toIso8601String(),
      },
    );

    final corps = reponse.data ?? const <String, dynamic>{};
    var recus = 0;
    _journalManquants = 0;
    _journalSansDateCreation = false;
    _fichesSansVentilation = false;

    recus += await _absorberCategories(corps['product_categories']);
    recus += await _absorberProduits(corps['products']);
    recus += await _absorberBandes(corps['livestock_lots']);
    // F0.94 — APRÈS les bandes : une bande créée sur le web arrive avec ses fiches dans le même
    // tirage, et une fiche d'une bande inconnue est refusée.
    recus += await _absorberFichesJournalieres(
      corps['livestock_daily_entries'],
    );
    recus += await _absorberRations(corps['feed_ration_standards']);
    recus += await _absorberRemanences(corps['veterinary_withdrawal_periods']);
    recus += await _absorberProphylaxie(
      corps['prophylaxis_schedule_standards'],
    );
    recus += await _absorberSoins(corps['veterinary_records']);
    recus += await _absorberReproduction(
      corps['livestock_reproduction_events'],
    );
    recus += await _absorberClients(corps['customers']);
    recus += await _absorberCreances(corps['receivables']);
    recus += await _absorberAvances(corps['customer_advances']);
    recus += await _absorberRelances(corps['customer_reminders']);
    recus += await _absorberProvendes(corps['feed_types']);
    recus += await _absorberNumerotation(corps['elevage_numbering']);
    recus += await _absorberFournisseurs(corps['suppliers']);
    recus += await _absorberBonsCommande(corps['purchase_orders']);
    recus += await _absorberAchats(corps['purchases']);
    recus += await _absorberCreancesFournisseurs(corps['supplier_credits']);
    recus += await _absorberDettes(corps['payables']);
    recus += await _absorberVentes(corps['sales']);
    recus += await _absorberEmployes(corps['employees']);
    recus += await _absorberStagiaires(corps['internships']);
    recus += await _absorberPointages(corps['attendance_records']);
    recus += await _absorberCourriers(corps['mails']);
    recus += await _absorberDocuments(corps['administrative_documents']);
    recus += await _absorberArchives(corps['archived_documents']);
    recus += await _absorberPlanComptable(corps['chart_of_accounts']);
    recus += await _absorberExercices(corps['fiscal_years']);
    recus += await _absorberJournal(
      corps['accounting_entries'],
      corps['accounting_entry_ids'],
      corps['accounting_entry_lines'],
    );
    recus += await _absorberEntreprise(corps['company_settings']);
    recus += await _absorberModules(corps['modules_config']);
    recus += await _absorberRoles(corps['roles']);
    recus += await _absorberUtilisateurs(corps['users']);
    recus += await _absorberAudit(corps['audit_logs']);
    recus += await _absorberNotifications(corps['notifications']);
    recus += await _absorberRevenusDeBande(corps['lot_revenues']);
    recus += await _absorberSujets(corps['animals']);
    recus += await _absorberEspeces(corps['livestock_species']);
    recus += await _absorberModelesAttestation(corps['attestation_templates']);
    recus += await _absorberCompteursAttestation(corps['attestation_counts']);
    recus += await _absorberComptesTresorerie(corps['treasury_accounts']);
    recus += await _absorberCategoriesDepense(corps['expense_categories']);

    // ⚠️ F0.84-bis : le serveur annonce des écritures actives que le poste n'a pas (cas réel :
    // créée entre la requête et `server_time`, donc plus jamais servie par `since`). UNE relance,
    // sans `since` — jamais une boucle. La relance note elle-même le curseur.
    if (_journalManquants > 0 && !complet) {
      return recus + await _tirer(complet: true);
    }
    if (_journalManquants > 0) {
      await _ecrireReglage(cleJournalIncomplet, '1');
      _avertissements.add(
        'Journal comptable incomplet : $_journalManquants écriture(s) annoncée(s) '
        'par le serveur manquent encore sur ce poste. Les états peuvent être faux ; '
        'la prochaine synchronisation redemandera tout le journal.',
      );
    } else if (etaitIncomplet) {
      await _effacerReglage(cleJournalIncomplet);
    }
    if (!resyncFaite) {
      await _ecrireReglage(cleJournalResync, '1');
    }
    // F0.85 : la date de création n'est « rapportée » que si le serveur la sert.
    if (!resyncCreationFaite && !_journalSansDateCreation) {
      await _ecrireReglage(cleJournalResyncCreation, '1');
    }
    // F0.94 : écrit seulement ICI, après TOUS les absorbeurs — un lot de fiches refusé lève une
    // `FormatException` plus haut, et la resynchronisation sera retentée au tirage suivant.
    if (!resyncFichesFaite) {
      await _ecrireReglage(cleFichesResync, '1');
    }
    // F0.95 : même place, et seulement si le serveur sert la ventilation par catégorie.
    if (!resyncCategoriesFaite && !_fichesSansVentilation) {
      await _ecrireReglage(cleFichesResyncCategories, '1');
    }

    // ⚠️ L'HORODATAGE VIENT DU SERVEUR (`server_time`), jamais de l'appareil.
    // Une tablette dont l'horloge retarde redemanderait sans cesse les mêmes
    // changements ; une qui avance en sauterait définitivement.
    final horlogeServeur = corps['server_time'];
    if (horlogeServeur is String) {
      await _db.noterEtatDeSynchronisation(
        tire: DateTime.parse(horlogeServeur),
      );
    }

    return recus;
  }

  Future<int> _absorberCategories(Object? brut) async {
    final lignes = _lignes(brut);

    await _db.batch((b) {
      for (final l in lignes) {
        final ligne = ProductCategoriesCompanion.insert(
          id: l['id'] as String,
          label: (l['label'] ?? '') as String,
          isActive: Value(_bool(l['is_active'])),
          updatedAt: Value(_date(l['updated_at'])),
        );
        // Le serveur fait autorite sur les referentiels : l'existant local est
        // remplace, jamais fusionne champ par champ.
        b.insert(
          _db.productCategories,
          ligne,
          onConflict: DoUpdate((_) => ligne),
        );
      }
    });

    return lignes.length;
  }

  Future<int> _absorberProduits(Object? brut) async {
    final lignes = _lignes(brut);

    // ⚠️⚠️ UN PRODUIT `pending` OU `conflict` N'EST PAS ÉCRASÉ PAR LE TIRAGE : il
    // n'existe (ou n'a changé) que sur ce poste, et l'effacer perdrait la saisie.
    // Un produit refusé (`conflict`) attend la décision de l'utilisateur.
    final protegees = {
      for (final p in await (_db.select(
        _db.products,
      )..where((t) => t.syncStatus.equalsValue(SyncStatus.synced).not())).get())
        p.id,
    };

    await _db.batch((b) {
      for (final l in lignes) {
        if (protegees.contains(l['id'])) continue;
        final ligne = produitDepuisJson(l);
        b.insert(_db.products, ligne, onConflict: DoUpdate((_) => ligne));
      }
    });

    return lignes.length;
  }

  /// Un produit tel que le serveur le décrit, prêt à être écrit.
  ///
  /// ⚠️ **PUBLIC ET PARTAGÉ** : le tirage et le formulaire « Ajouter un Produit »
  /// inscrivent un produit à partir de la MÊME lecture. Deux lectures parallèles
  /// d'un même JSON finissent par diverger (une colonne ajoutée à l'une seulement).
  static ProductsCompanion produitDepuisJson(Map<String, dynamic> l) =>
      ProductsCompanion.insert(
        id: l['id'] as String,
        sku: (l['sku'] ?? '') as String,
        name: (l['name'] ?? '') as String,
        categoryId: Value(l['category_id'] as String?),
        speciesId: Value(l['species_id'] as String?),
        unit: (l['unit'] ?? 'u') as String,
        pricingMode: (l['pricing_mode'] ?? 'fixe') as String,
        priceMin: Value(_reel(l['price_min'])),
        priceMax: Value(_reel(l['price_max'])),
        tvaRate: Value(_reel(l['tva_rate']) ?? 0),
        stockQty: Value(_reel(l['stock_qty']) ?? 0),
        alertThreshold: Value(_reel(l['alert_threshold'])),
        description: Value(l['description'] as String?),
        syncStatus: const Value(SyncStatus.synced),
        isActive: Value(_bool(l['is_active'])),
        updatedAt: Value(_date(l['updated_at'])),
      );

  Future<int> _absorberBandes(Object? brut) async {
    final lignes = _lignes(brut);

    await _db.batch((b) {
      for (final l in lignes) {
        final ligne = LivestockLotsCompanion.insert(
          id: l['id'] as String,
          code: (l['code'] ?? '') as String,
          speciesId: (l['species_id'] ?? '') as String,
          speciesCode: Value(l['species_code'] as String?),
          stage: Value(l['stage'] as String?),
          initialQuantity: Value(_entier(l['initial_quantity']) ?? 0),
          currentQuantity: Value(_entier(l['current_quantity']) ?? 0),
          createdDate: Value(_date(l['created_date'])),
          acquisitionCost: Value(_reel(l['acquisition_cost'])),
          productId: Value(l['product_id'] as String?),
          status: Value(l['status'] as String?),
          isActive: Value(_bool(l['is_active'])),
          updatedAt: Value(_date(l['updated_at'])),
        );
        b.insert(_db.livestockLots, ligne, onConflict: DoUpdate((_) => ligne));
      }
    });

    return lignes.length;
  }

  /// Fiches journalières du cheptel — FUSIONNÉES par identifiant (ticket F0.94).
  ///
  /// ⚠️⚠️ AVANT CE TICKET, AUCUN ABSORBEUR : `/sync/pull` sert `livestock_daily_entries` (filtre
  /// `updated_at > since`) et le poste ignorait la clé. Les journées saisies sur le web ne
  /// descendaient jamais, ni les fiches que le serveur recalcule en cascade après une vente
  /// antérieure (15.31). Aucune erreur : la clé était simplement lue par personne.
  ///
  /// Règles :
  ///  - **fusion, jamais suppression** : le tirage est incrémental, une fiche absente de la
  ///    réponse n'a simplement pas changé ;
  ///  - une fiche locale `pending` ou `conflict` n'est **ni écrasée ni supprimée** (elle n'existe,
  ///    ou n'a changé, que sur ce poste : le serveur arbitrera à l'envoi) ;
  ///  - une fiche `synced` prend la version du serveur, `effectif_final` compris (le serveur le
  ///    recalcule toujours ; le poste ne le reprend pas à son compte) ;
  ///  - ⚠️ MÊME BANDE, MÊME JOUR, AUTRE IDENTIFIANT (le poste a créé SA fiche avant d'avoir reçu
  ///    celle du web) : la fiche locale est CONSERVÉE, la version du serveur n'est pas écrite (la
  ///    contrainte locale `UNIQUE (lot_id, entry_date)` l'interdit, et supprimer la locale perdrait
  ///    la saisie) ; un avertissement le dit. À l'envoi, le serveur refuse la fiche du poste
  ///    (contrainte unique de `pushDailyEntries`) : elle passe en `conflict` avec son motif ;
  ///  - l'effectif courant de la bande (`livestock_lots.current_quantity`) n'est JAMAIS touché :
  ///    c'est le serveur qui le sert, par `_absorberBandes`.
  ///
  /// ⚠️ **STRICT** : identifiant ou bande non UUID, bande inconnue du poste, jour illisible ou
  /// impossible (format attendu `Y-m-d`, celui du cast `date:Y-m-d` du modèle), nombre négatif,
  /// fractionnaire, NaN ou infini, colonne obligatoire absente, horodatage illisible, doublon
  /// d'identifiant ou de (bande, jour) dans la réponse → [FormatException] et AUCUNE fiche écrite
  /// (transaction annulée) ; le curseur n'avance pas. Un nombre absent n'est jamais lu comme 0 —
  /// sauf `don`, nullable au serveur et non nullable au poste (le serveur le compte lui-même
  /// `don ?? 0`).
  ///
  /// F0.95 (schéma v38) — PORTÉES : les dix colonnes de ventilation (`mort_*`, `don_*`,
  /// `passage_sevre_jeune`, `cat_depart_*`), les catégories dérivées `cat_eff_repro/sevre/jeune`
  /// et `cat_eff_4`, la ventilation par sexe `effectif_m/f/sevres/smeres`. Clé ABSENTE (serveur
  /// pas à jour) = valeur locale gardée ; NULL explicite = inconnu. Une fiche `synced` prend les
  /// `effectif_final` et `cat_eff_*` recalculés par la cascade du serveur.
  ///
  /// ⚠️ COLONNES DU SERVEUR TOUJOURS NON PORTÉES : `feed_product_id`, `treatment_product_id`,
  /// `treatment_dose`, `symptomes`, `vente_sexe`, `vente_montant`. Le poste ne les envoie pas :
  /// `fill()` du serveur ne réécrit que les clés reçues, elles y restent intactes.
  Future<int> _absorberFichesJournalieres(Object? brut) async {
    if (brut == null) return 0;
    if (brut is! List) {
      throw const FormatException(
        'Fiches refusées : « livestock_daily_entries » n\'est pas une liste.',
      );
    }

    final formeUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    final formeJour = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
    final formeEntier = RegExp(r'^-?\d+$');

    int? entier(
      Map<String, dynamic> l,
      String cle,
      String id, {
      required bool requis,
    }) {
      final v = l[cle];
      if (v == null) {
        if (requis) {
          throw FormatException('Fiche $id refusée : « $cle » absent.');
        }
        return null;
      }
      int? n;
      if (v is int) {
        n = v;
      } else if (v is double && v.isFinite && v == v.truncateToDouble()) {
        n = v.toInt();
      } else if (v is String && formeEntier.hasMatch(v)) {
        n = int.tryParse(v);
      }
      if (n == null) {
        throw FormatException('Fiche $id refusée : « $cle » illisible ($v).');
      }
      if (n < 0) {
        throw FormatException('Fiche $id refusée : « $cle » négatif ($v).');
      }
      return n;
    }

    /// ⚠️⚠️ F0.95 — CLÉ ABSENTE ≠ NULL EXPLICITE. Absente : serveur antérieur à la colonne, la
    /// valeur locale est GARDÉE (`Value.absent`). Présente et nulle : le serveur dit « inconnu »,
    /// la valeur locale est remplacée par null. Présente : entier ≥ 0 strict (même lecture que
    /// les autres compteurs ; négatif, fractionnaire, NaN, infini ou illisible = lot refusé).
    Value<int?> optionnel(Map<String, dynamic> l, String cle, String id) =>
        l.containsKey(cle)
        ? Value(entier(l, cle, id, requis: false))
        : const Value.absent();

    double? reel(Map<String, dynamic> l, String cle, String id) {
      final v = l[cle];
      if (v == null) return null;
      final x = v is num
          ? v.toDouble()
          : v is String
          ? double.tryParse(v)
          : null;
      if (x == null || !x.isFinite) {
        throw FormatException('Fiche $id refusée : « $cle » illisible ($v).');
      }
      if (x < 0) {
        throw FormatException('Fiche $id refusée : « $cle » négatif ($v).');
      }
      return x;
    }

    // ── Validation complète AVANT toute écriture en base ────────────────────
    final ids = <String>{};
    final jours = <String>{};
    final fiches = <LivestockDailyEntriesCompanion>[];
    for (final e in brut) {
      if (e is! Map) {
        throw const FormatException(
          'Fiches refusées : un élément n\'est pas un objet.',
        );
      }
      final l = e.map((c, v) => MapEntry(c.toString(), v));

      final id = l['id'];
      if (id is! String || !formeUuid.hasMatch(id)) {
        throw FormatException('Fiche refusée : identifiant invalide ($id).');
      }
      if (!ids.add(id)) {
        throw FormatException('Fiche $id refusée : servie deux fois.');
      }
      final lot = l['lot_id'];
      if (lot is! String || !formeUuid.hasMatch(lot)) {
        throw FormatException('Fiche $id refusée : bande invalide ($lot).');
      }

      final jourBrut = l['entry_date'];
      final m = jourBrut is String ? formeJour.firstMatch(jourBrut) : null;
      DateTime? jour;
      if (m != null) {
        final (a, mo, j) = (
          int.parse(m[1]!),
          int.parse(m[2]!),
          int.parse(m[3]!),
        );
        final d = DateTime(a, mo, j);
        if (d.year == a && d.month == mo && d.day == j) jour = d;
      }
      if (jour == null) {
        throw FormatException(
          'Fiche $id refusée : jour illisible ($jourBrut).',
        );
      }
      if (!jours.add('$lot|${_jour(jour)}')) {
        throw FormatException(
          'Fiche $id refusée : deux fiches servies pour la même bande le ${_jour(jour)}.',
        );
      }

      final horodatageBrut = l['updated_at'];
      DateTime? horodatage;
      if (horodatageBrut != null) {
        horodatage = horodatageBrut is String ? _date(horodatageBrut) : null;
        if (horodatage == null) {
          throw FormatException(
            'Fiche $id refusée : horodatage illisible ($horodatageBrut).',
          );
        }
      }

      fiches.add(
        LivestockDailyEntriesCompanion(
          id: Value(id),
          lotId: Value(lot),
          entryDate: Value(jour),
          updatedAt: Value.absentIfNull(horodatage),
          achat: Value(entier(l, 'achat', id, requis: true)!),
          ne: Value(entier(l, 'ne', id, requis: true)!),
          mort: Value(entier(l, 'mort', id, requis: true)!),
          vente: Value(entier(l, 'vente', id, requis: true)!),
          don: Value(entier(l, 'don', id, requis: false) ?? 0),
          effectifFinal: Value(entier(l, 'effectif_final', id, requis: true)!),
          ponteTotal: Value(entier(l, 'ponte_total', id, requis: false)),
          ponteCasses: Value(entier(l, 'ponte_casses', id, requis: false)),
          feedQtyKg: Value(reel(l, 'feed_qty_kg', id)),
          weightSampleAvgG: Value(reel(l, 'weight_sample_avg_g', id)),
          // F0.95 — effectif par catégorie et ventilation par sexe (voir `optionnel`).
          mortRepro: optionnel(l, 'mort_repro', id),
          mortSevre: optionnel(l, 'mort_sevre', id),
          mortJeune: optionnel(l, 'mort_jeune', id),
          donRepro: optionnel(l, 'don_repro', id),
          donSevre: optionnel(l, 'don_sevre', id),
          donJeune: optionnel(l, 'don_jeune', id),
          passageSevreJeune: optionnel(l, 'passage_sevre_jeune', id),
          catDepartRepro: optionnel(l, 'cat_depart_repro', id),
          catDepartSevre: optionnel(l, 'cat_depart_sevre', id),
          catDepartJeune: optionnel(l, 'cat_depart_jeune', id),
          catEffRepro: optionnel(l, 'cat_eff_repro', id),
          catEffSevre: optionnel(l, 'cat_eff_sevre', id),
          catEffJeune: optionnel(l, 'cat_eff_jeune', id),
          catEff4: optionnel(l, 'cat_eff_4', id),
          effectifM: optionnel(l, 'effectif_m', id),
          effectifF: optionnel(l, 'effectif_f', id),
          effectifSevres: optionnel(l, 'effectif_sevres', id),
          effectifSmeres: optionnel(l, 'effectif_smeres', id),
        ),
      );
      // F0.95 — un serveur antérieur à 15.39 ne sert pas la ventilation : la resynchronisation
      // unique `fiches_resync_f095` ne doit alors PAS être marquée faite (voir `_tirer`).
      if (!colonnesVentilation.every(l.containsKey)) {
        _fichesSansVentilation = true;
      }
    }

    if (fiches.isEmpty) return 0;

    // ── Application, en une transaction ─────────────────────────────────────
    final avertissements = <String>[];
    await _db.transaction(() async {
      final codes = <String, String>{};
      final bandes = {for (final f in fiches) f.lotId.value}.toList();
      for (final morceau in _morceaux(bandes)) {
        for (final b in await (_db.select(
          _db.livestockLots,
        )..where((t) => t.id.isIn(morceau))).get()) {
          codes[b.id] = b.code;
        }
      }
      for (final f in fiches) {
        if (!codes.containsKey(f.lotId.value)) {
          throw FormatException(
            'Fiche ${f.id.value} refusée : bande inconnue du poste (${f.lotId.value}).',
          );
        }
      }

      for (final f in fiches) {
        final locale = await (_db.select(
          _db.livestockDailyEntries,
        )..where((t) => t.id.equals(f.id.value))).getSingleOrNull();

        // ⚠️⚠️ `pending` / `conflict` : intouchable (n'existe, ou n'a changé, que sur ce poste).
        if (locale != null && locale.syncStatus != SyncStatus.synced) continue;

        final occupante =
            await (_db.select(_db.livestockDailyEntries)..where(
                  (t) => Expression.and([
                    t.lotId.equals(f.lotId.value),
                    t.entryDate.equals(f.entryDate.value),
                  ]),
                ))
                .getSingleOrNull();
        if (occupante != null && occupante.id != f.id.value) {
          avertissements.add(
            _avertissementFicheEnDouble(
              occupante,
              codes[f.lotId.value] ?? f.lotId.value,
            ),
          );
          continue;
        }

        final ligne = f.copyWith(
          deviceId: Value(locale?.deviceId ?? 'serveur'),
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: Value(
            f.updatedAt.present
                ? f.updatedAt.value
                : locale?.updatedAt ?? _maintenant(),
          ),
        );
        await _db
            .into(_db.livestockDailyEntries)
            .insert(ligne, onConflict: DoUpdate((_) => ligne));
      }
    });

    _avertissements.addAll(avertissements);
    return fiches.length;
  }

  /// Avertissement d'une fiche servie que le poste ne peut pas écrire : (bande, jour) est déjà
  /// occupé localement par une AUTRE fiche, qui est conservée.
  static String _avertissementFicheEnDouble(
    LivestockDailyEntry locale,
    String bande,
  ) {
    final d = locale.entryDate;
    final jour =
        '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
    final suite = switch (locale.syncStatus) {
      SyncStatus.pending =>
        'La saisie de ce poste est conservée ; à l\'envoi, le serveur la refusera '
            '(une seule fiche par bande et par jour) : comparez les deux avant de trancher.',
      SyncStatus.conflict =>
        'La fiche refusée de ce poste est conservée : comparez les deux avant de trancher.',
      SyncStatus.synced =>
        'La copie de ce poste (une autre fiche, déjà synchronisée) est conservée, jamais '
            'supprimée par un tirage : écart à examiner.',
    };
    return 'Fiche du $jour (bande $bande) : le serveur en détient une autre, saisie ailleurs. '
        '$suite';
  }

  /// Rations normatives : référentiel éditable, remplacé à chaque tirage.
  ///
  /// ⚠️ Une réponse SANS la clé laisse les rations locales intactes plutôt que
  /// de les effacer : un serveur plus ancien qui ne les sert pas encore ne doit
  /// pas vider le référentiel d'un poste déjà à jour.
  /// Catalogue des types de provende — référentiel remplacé à chaque tirage.
  ///
  /// ⚠️ **REMPLACEMENT COMPLET** : un type d'aliment archivé côté serveur ne
  /// descend plus, et doit donc quitter l'écran du poste. Le garder ferait
  /// figurer au catalogue une provende que la ferme ne sert plus.
  Future<int> _absorberProvendes(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.feedTypes).go();

      for (final l in lignes) {
        await _db
            .into(_db.feedTypes)
            .insert(
              FeedTypesCompanion.insert(
                id: l['id'] as String,
                name: (l['name'] ?? '') as String,
                speciesId: Value(l['species_id'] as String?),
                speciesCode: Value(l['species_code'] as String?),
                speciesLabel: Value(l['species_label'] as String?),
                standardBagWeightKg: Value(_reel(l['standard_bag_weight_kg'])),
                pricePerKg: Value(_reel(l['price_per_kg'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Préfixes de numérotation — un OBJET, pas une collection.
  ///
  /// ⚠️ **LE SERVEUR SERT UNE TABLE SINGLETON.** La charge est une map de
  /// préfixes, pas une liste de lignes : la passer à `_lignes()` comme les
  /// autres tables ne donnerait rien. Elle est écrite sous une clé fixe pour
  /// qu'un second tirage remplace la ligne au lieu d'en empiler une autre.
  Future<int> _absorberNumerotation(Object? brut) async {
    if (brut is! Map) return 0;

    final l = brut.map((c, v) => MapEntry(c.toString(), v));

    final ligne = ElevageNumberingSettingsCompanion.insert(
      id: const Value('unique'),
      bandeFormat: Value(l['bande_format'] as String?),
      lapinePrefix: Value(l['lapine_prefix'] as String?),
      malePrefix: Value(l['male_prefix'] as String?),
      truiePrefix: Value(l['truie_prefix'] as String?),
      verratPrefix: Value(l['verrat_prefix'] as String?),
      porteePrefix: Value(l['portee_prefix'] as String?),
      volaillePrefix: Value(l['volaille_prefix'] as String?),
      parcPrefix: Value(l['parc_prefix'] as String?),
      escargotPrefix: Value(l['escargot_prefix'] as String?),
    );

    await _db
        .into(_db.elevageNumberingSettings)
        .insert(ligne, onConflict: DoUpdate((_) => ligne));

    return 1;
  }

  Future<int> _absorberRations(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.batch((b) {
      for (final l in lignes) {
        final ligne = FeedRationStandardsCompanion.insert(
          id: l['id'] as String,
          speciesCode: (l['species_code'] ?? '') as String,
          stageLabel: (l['stage_label'] ?? '') as String,
          rationGPerDay: _reel(l['ration_g_per_day']) ?? 0,
        );
        b.insert(
          _db.feedRationStandards,
          ligne,
          onConflict: DoUpdate((_) => ligne),
        );
      }
    });

    return lignes.length;
  }

  /// Périodes de rémanence vétérinaire encore actives.
  ///
  /// ⚠️ LA TABLE LOCALE EST REMPLACÉE, PAS COMPLÉTÉE. Le serveur n'envoie que
  /// les périodes ENCORE actives : conserver les anciennes bloquerait
  /// indéfiniment des bandes dont le délai d'attente est passé, et l'éleveur
  /// finirait par contourner l'alerte — y compris quand elle est vraie.
  ///
  /// ⚠️ Une réponse SANS la clé laisse l'existant intact plutôt que de tout
  /// effacer : un serveur plus ancien ne doit pas lever un blocage sanitaire.
  Future<int> _absorberRemanences(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.veterinaryWithdrawalPeriods).go();

      for (final l in lignes) {
        await _db
            .into(_db.veterinaryWithdrawalPeriods)
            .insert(
              VeterinaryWithdrawalPeriodsCompanion.insert(
                id: l['id'] as String,
                lotId: (l['lot_id'] ?? '') as String,
                productUsed: Value(l['product_used'] as String?),
                endDate: _date(l['end_date']) ?? DateTime.now(),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Cycle de reproduction par femelle nommée — reçu, jamais envoyé.
  ///
  /// ⚠️ **FUSION, PAS REMPLACEMENT.** Contrairement aux référentiels, le
  /// serveur ne sert PAS toute la table à chaque tirage : il descend les
  /// cycles `en_cours` plus l'historique modifié depuis le dernier tirage.
  /// Vider la table avant d'insérer effacerait donc tout l'historique clos dès
  /// le premier tirage incrémental — l'écran perdrait ses mises bas passées
  /// sans que rien ne le signale.
  Future<int> _absorberReproduction(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    // ⚠️⚠️ LES DECLARATIONS EN ATTENTE SONT PRESERVEES. Une saillie declaree
    // au poste et pas encore acquittee n'existe pas encore cote serveur : la
    // remplacer par le tirage l'effacerait purement et simplement, et
    // l'animalier n'aurait aucun moyen de le savoir.
    final enAttente = await (_db.select(
      _db.livestockReproductionEvents,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();
    final protegees = enAttente.map((e) => e.id).toSet();

    await _db.batch((b) {
      for (final l in lignes) {
        if (protegees.contains(l['id'])) continue;

        b.insert(
          _db.livestockReproductionEvents,
          LivestockReproductionEventsCompanion.insert(
            id: l['id'] as String,
            // ⚠️ UNE LIGNE TIREE N'A ETE ECRITE PAR AUCUN POSTE, et ne doit
            // jamais repartir a l'envoi — meme convention que le registre
            // veterinaire.
            deviceId: (l['device_id'] ?? 'serveur') as String,
            syncStatus: const Value(SyncStatus.synced),
            lotId: (l['lot_id'] ?? '') as String,
            motherRef: (l['mother_ref'] ?? '') as String,
            sireRef: Value(l['sire_ref'] as String?),
            saillieDate: Value(_date(l['saillie_date'])),
            palpationDate: Value(_date(l['palpation_date'])),
            miseBasDateExpected: Value(_date(l['mise_bas_date_expected'])),
            miseBasDateActual: Value(_date(l['mise_bas_date_actual'])),
            sevrageDateExpected: Value(_date(l['sevrage_date_expected'])),
            nesVivants: Value(_entier(l['nes_vivants'])),
            nesMorts: Value(_entier(l['nes_morts'])),
            status: Value((l['status'] ?? 'en_cours') as String),
            updatedAt: _date(l['updated_at']) ?? DateTime.now(),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });

    return lignes.length;
  }

  /// Fichier clients — fusionné par identifiant à chaque tirage.
  ///
  /// ⚠️⚠️ **FUSION, PAS REMPLACEMENT** (ticket F0.72). Le serveur ne sert que les clients
  /// MODIFIÉS depuis `since` : l'ancien « tout effacer puis réinsérer » ne laissait, dès le
  /// deuxième tirage, que le delta — la caisse perdait ses clients sans qu'aucune erreur ne
  /// le dise. Un client archivé descend avec `is_active = false` (le serveur ne filtre pas) :
  /// la fusion le désactive, les écrans ne proposent que les actifs.
  ///
  /// ⚠️ Une fiche `pending` ou `conflict` n'existe (ou n'a changé) que sur ce poste : le
  /// tirage ne l'écrase jamais.
  Future<int> _absorberClients(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      final protegees = {
        for (final c
            in await (_db.select(_db.customers)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          c.id,
      };

      for (final l in lignes) {
        if (protegees.contains(l['id'])) continue;

        await _db
            .into(_db.customers)
            .insertOnConflictUpdate(
              CustomersCompanion.insert(
                id: l['id'] as String,
                name: (l['name'] ?? '') as String,
                phone: Value(l['phone'] as String?),
                email: Value(l['email'] as String?),
                city: Value(l['city'] as String?),
                creditLimit: Value(_reel(l['credit_limit']) ?? 0),
                isActive: Value(_bool(l['is_active'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Créances encore dues — FUSIONNÉES par identifiant (ticket F0.73).
  ///
  /// ⚠️⚠️ **« TOUT EFFACER PUIS RÉINSÉRER » EST RETIRÉ.** Une imputation d'acompte se
  /// désigne par l'identifiant de sa créance : la table doit rester stable d'un tirage à
  /// l'autre, et une saisie du poste ne doit jamais perdre sa cible entre deux lignes
  /// d'une même transaction. La fusion met la ligne à jour (le serveur est maître de
  /// `amount_paid`), puis supprime ce que le serveur n'a PLUS servi.
  ///
  /// ⚠️ **LE SERVEUR SERT CE QUI RESTE DÛ SANS FILTRE `since`, plus ce qui a changé depuis
  /// `since`.** Une créance soldée entre deux tirages arrive donc UNE fois (soldée, parce
  /// qu'elle a changé), puis cesse d'être servie : elle est alors supprimée. La laisser
  /// à l'encours du poste ferait relancer un débiteur pour une facture déjà payée.
  Future<int> _absorberCreances(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      for (final l in lignes) {
        await _db
            .into(_db.receivables)
            .insertOnConflictUpdate(
              ReceivablesCompanion.insert(
                id: l['id'] as String,
                customerId: (l['customer_id'] ?? '') as String,
                saleId: Value(l['sale_id'] as String?),
                amount: _reel(l['amount']) ?? 0,
                amountPaid: Value(_reel(l['amount_paid']) ?? 0),
                dueDate: Value(_date(l['due_date'])),
                status: Value((l['status'] ?? 'en_cours') as String),
              ),
            );
      }

      final servies = [for (final l in lignes) l['id'] as String];
      await (_db.delete(
        _db.receivables,
      )..where((t) => t.id.isIn(servies).not())).go();
    });

    return lignes.length;
  }

  /// Avances versées par les clients — FUSIONNÉES par identifiant (ticket F0.73).
  ///
  /// ⚠️⚠️ **UNE AVANCE `pending` OU `conflict` N'EST NI ÉCRASÉE NI EFFACÉE** : elle
  /// n'existe (ou n'a changé) que sur ce poste. L'ancien « tout effacer puis réinsérer »
  /// aurait fait disparaître une saisie d'acompte au prochain tirage, sans un mot.
  ///
  /// ⚠️ **LE SERVEUR SERT LES AVANCES ACTIVES SANS FILTRE `since`** (`SyncController`) :
  /// une avance `synced` absente du tirage a donc été archivée côté serveur — elle est
  /// supprimée. `amount_used` vient toujours du serveur, jamais du poste.
  Future<int> _absorberAvances(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      final protegees = {
        for (final a
            in await (_db.select(_db.customerAdvances)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          a.id,
      };

      for (final l in lignes) {
        if (protegees.contains(l['id'])) continue;

        await _db
            .into(_db.customerAdvances)
            .insertOnConflictUpdate(
              CustomerAdvancesCompanion.insert(
                id: l['id'] as String,
                customerId: (l['customer_id'] ?? '') as String,
                amount: _reel(l['amount']) ?? 0,
                amountUsed: Value(_reel(l['amount_used']) ?? 0),
                advanceDate: Value(_date(l['advance_date'])),
                isActive: Value(_bool(l['is_active'])),
                treasuryAccountId: Value(l['treasury_account_id'] as String?),
                paymentMode: Value(l['payment_mode'] as String?),
                motif: Value(l['motif'] as String?),
                deviceId: Value(l['device_id'] as String?),
                syncStatus: const Value(SyncStatus.synced),
              ),
            );
      }

      final servies = [for (final l in lignes) l['id'] as String];
      await (_db.delete(_db.customerAdvances)..where(
            (t) => Expression.and([
              t.syncStatus.equalsValue(SyncStatus.synced),
              t.id.isIn(servies).not(),
            ]),
          ))
          .go();
    });

    return lignes.length;
  }

  /// Fournisseurs — référentiel remplacé à chaque tirage.
  ///
  /// ⚠️ **REMPLACEMENT COMPLET.** Un fournisseur archivé côté serveur disparaît
  /// du tirage : le garder proposerait à l'acheteur un partenaire que le
  /// serveur refuserait à l'envoi, sans qu'il comprenne pourquoi.
  Future<int> _absorberFournisseurs(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      // ⚠️⚠️ UNE FICHE `pending` OU `conflict` N'EST NI EFFACÉE NI ÉCRASÉE : elle n'existe
      // (ou n'a changé) que sur ce poste. Seules les fiches synchronisées sont remplacées
      // par le tirage — l'ensemble, comme avant.
      final protegees = {
        for (final f
            in await (_db.select(_db.suppliers)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          f.id,
      };

      await (_db.delete(
        _db.suppliers,
      )..where((t) => t.syncStatus.equalsValue(SyncStatus.synced))).go();

      for (final l in lignes) {
        if (protegees.contains(l['id'])) continue;

        await _db
            .into(_db.suppliers)
            .insert(
              SuppliersCompanion.insert(
                id: l['id'] as String,
                name: (l['name'] ?? '') as String,
                category: Value(l['category'] as String?),
                phone: Value(l['phone'] as String?),
                email: Value(l['email'] as String?),
                address: Value(l['address'] as String?),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Plan comptable — référentiel remplacé à chaque tirage.
  Future<int> _absorberPlanComptable(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.chartOfAccounts).go();

      for (final l in lignes) {
        await _db
            .into(_db.chartOfAccounts)
            .insert(
              ChartOfAccountsCompanion.insert(
                id: l['id'] as String,
                code: (l['code'] ?? '') as String,
                label: (l['label'] ?? '') as String,
                accountClass: Value(_entier(l['class'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Exercices comptables — référentiel remplacé à chaque tirage.
  Future<int> _absorberExercices(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.fiscalYears).go();

      for (final l in lignes) {
        await _db
            .into(_db.fiscalYears)
            .insert(
              FiscalYearsCompanion.insert(
                id: l['id'] as String,
                year: _entier(l['year']) ?? 0,
                startDate: Value(_date(l['start_date'])),
                endDate: Value(_date(l['end_date'])),
                status: Value(l['status'] as String?),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Journal comptable : écritures, identifiants des écritures actives, lignes — en UNE transaction.
  ///
  /// ⚠️⚠️ **TICKET F0.84 (serveur 15.28) — LE JOURNAL DU POSTE SE CORRIGE.** Avant, la fusion ne
  /// supprimait jamais rien : une écriture ARCHIVÉE sur le web restait au poste pour toujours, et une
  /// écriture MODIFIÉE (lignes supprimées puis recréées avec de nouveaux identifiants) gardait ses
  /// anciennes lignes en plus des nouvelles — montants doublés, sans aucune erreur.
  ///
  /// Contrat du tirage :
  ///  - `accounting_entries` : les écritures ACTIVES nouvelles ou modifiées depuis `since` ;
  ///  - `accounting_entry_lines` : TOUTES les lignes courantes de ces écritures (jamais une partie) ;
  ///  - `accounting_entry_ids` : les identifiants de TOUTES les écritures actives, SANS filtre `since`.
  ///
  /// Conséquences ici : (1) les lignes d'une écriture servie sont REMPLACÉES, jamais fusionnées ;
  /// (2) ce qui ne figure plus dans `accounting_entry_ids` est retiré, avec ses lignes. Rien ne suppose
  /// un tirage complet : un tirage incrémental suffit.
  ///
  /// ⚠️ **ANCIEN SERVEUR** : si `accounting_entry_ids` est ABSENT (`null`), aucune purge n'est faite —
  /// le poste ne peut pas savoir ce qui a disparu, et supposer « liste vide » viderait le journal.
  /// Limite documentée : une écriture archivée sur un tel serveur reste au poste.
  ///
  /// ⚠️ **TICKET F0.84-bis (suites de l'audit de F0.84)** :
  ///  - écriture annoncée active mais absente après absorption → `_journalManquants`, et [_tirer]
  ///    redemande UNE fois tout le journal (sans `since`), sinon le dit (`journal_incomplet`) ;
  ///  - liste des actives VIDE alors que le poste contient des écritures → pas de purge au premier
  ///    tirage, confirmée par une seconde annonce vide (`journal_vidage_attendu`) ;
  ///  - identifiants = vrais UUID ; montants NaN / ±Infinity refusés ;
  ///  - ⚠️ montant NÉGATIF : NON tranché (règle comptable à décider par le cabinet, voir le ticket).
  ///
  /// ⚠️ **LECTURE SEULE, DONC RIEN À PROTÉGER** : ces deux tables n'ont pas de `sync_status` et aucun
  /// dépôt ne les écrit (un test le verrouille). Aucune ligne `pending`/`conflict` n'existe à épargner.
  ///
  /// ⚠️ **STRICT** : toute entrée incohérente lève une [FormatException] AVANT la première écriture
  /// (identifiant invalide, doublon, date illisible, montant absent ou illisible, ligne dont l'écriture
  /// n'est pas servie, écriture servie mais absente des actives). Le curseur n'avance pas ; le prochain
  /// tirage repart du même point. Un montant absent n'est jamais lu comme 0, une date illisible jamais
  /// remplacée par « aujourd'hui ».
  Future<int> _absorberJournal(
    Object? ecrituresBrut,
    Object? idsActifsBrut,
    Object? lignesBrut,
  ) async {
    if (ecrituresBrut == null && lignesBrut == null && idsActifsBrut == null) {
      return 0;
    }

    List<Map<String, dynamic>> liste(Object? brut, String cle) {
      if (brut == null) return const [];
      if (brut is! List) {
        throw FormatException(
          'Journal refusé : « $cle » n\'est pas une liste.',
        );
      }
      return [
        for (final e in brut)
          if (e is Map)
            e.map((c, v) => MapEntry(c.toString(), v))
          else
            throw FormatException(
              'Journal refusé : « $cle » contient un élément qui n\'est pas un objet.',
            ),
      ];
    }

    // F0.84-bis : un vrai UUID (8-4-4-4-12 hexadécimal), plus seulement « 36 caractères ».
    final formeUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );

    String identifiant(Object? v, String contexte) {
      if (v is! String || !formeUuid.hasMatch(v)) {
        throw FormatException(
          'Journal refusé : identifiant invalide ($contexte : $v).',
        );
      }
      return v;
    }

    final ecritures = liste(ecrituresBrut, 'accounting_entries');
    final lignes = liste(lignesBrut, 'accounting_entry_lines');

    // ── Validation complète AVANT toute écriture en base ────────────────────
    final servies = <String>{};
    final entetes = <AccountingEntriesCompanion>[];
    for (final l in ecritures) {
      final id = identifiant(l['id'], 'écriture');
      if (!servies.add(id)) {
        throw FormatException(
          'Journal refusé : écriture $id servie deux fois.',
        );
      }
      final dateBrute = l['entry_date'];
      final date = dateBrute is String ? _date(dateBrute) : null;
      if (date == null) {
        throw FormatException(
          'Journal refusé : écriture $id, date illisible ($dateBrute).',
        );
      }
      // F0.85 : instant de CRÉATION (ticket 15.29), pour départager deux pièces du même jour au Grand
      // Livre. Absent = serveur plus ancien : on le dit au moteur (la resynchronisation n'est alors pas
      // marquée faite) mais on n'écrase JAMAIS une date déjà connue. Présent mais illisible = refus
      // (jamais « maintenant »).
      DateTime? creeLe;
      if (!l.containsKey('created_at')) {
        _journalSansDateCreation = true;
      } else if (l['created_at'] != null) {
        final brute = l['created_at'];
        creeLe = brute is String ? _date(brute) : null;
        if (creeLe == null) {
          throw FormatException(
            'Journal refusé : écriture $id, date de création illisible ($brute).',
          );
        }
      }
      entetes.add(
        AccountingEntriesCompanion.insert(
          id: id,
          fiscalYearId: Value(l['fiscal_year_id'] as String?),
          entryDate: date,
          reference: Value(l['reference'] as String?),
          sourceType: Value(l['source_type'] as String?),
          isLocked: Value(_bool(l['is_locked'])),
          createdAt: Value.absentIfNull(creeLe),
        ),
      );
    }

    final idsLignes = <String>{};
    final corps = <AccountingEntryLinesCompanion>[];
    for (final l in lignes) {
      final id = identifiant(l['id'], 'ligne');
      if (!idsLignes.add(id)) {
        throw FormatException('Journal refusé : ligne $id servie deux fois.');
      }
      final ecriture = identifiant(l['entry_id'], 'écriture de la ligne $id');
      if (!servies.contains(ecriture)) {
        throw FormatException(
          'Journal refusé : la ligne $id dépend de l\'écriture $ecriture, que ce tirage ne sert pas.',
        );
      }
      final compte = identifiant(l['account_id'], 'compte de la ligne $id');
      final debit = _reel(l['debit']);
      final credit = _reel(l['credit']);
      // F0.84-bis : NaN et ±Infinity sont refusés (`double.tryParse` les accepte, SQLite les range).
      // ⚠️ Un montant NÉGATIF n'est PAS tranché ici : règle comptable à décider (voir ticket).
      if (debit == null ||
          credit == null ||
          !debit.isFinite ||
          !credit.isFinite) {
        throw FormatException(
          'Journal refusé : ligne $id, montant absent ou illisible '
          '(débit ${l['debit']}, crédit ${l['credit']}).',
        );
      }
      corps.add(
        AccountingEntryLinesCompanion.insert(
          id: id,
          entryId: ecriture,
          accountId: compte,
          costCenterId: Value(l['cost_center_id'] as String?),
          debit: Value(debit),
          credit: Value(credit),
        ),
      );
    }

    Set<String>? actives;
    if (idsActifsBrut != null) {
      if (idsActifsBrut is! List) {
        throw const FormatException(
          'Journal refusé : « accounting_entry_ids » n\'est pas une liste.',
        );
      }
      actives = {
        for (final v in idsActifsBrut) identifiant(v, 'écriture active'),
      };
      final absentes = servies.difference(actives);
      if (absentes.isNotEmpty) {
        throw FormatException(
          'Journal refusé : écriture servie mais absente des écritures actives '
          '(${absentes.first}).',
        );
      }
    }

    // ⚠️ Copie FINALE : la variable `actives`, capturée par la transaction, n'est pas promue
    // en non-nulle par le compilateur Dart 3.13 (le build Windows échouait sur un SDK stable
    // récent). Aucune règle changée : même valeur, même test de nullité.
    final annoncees = actives;

    // ── Application, en une transaction ─────────────────────────────────────
    String? avertissementVidage;
    await _db.transaction(() async {
      for (final e in entetes) {
        await _db
            .into(_db.accountingEntries)
            .insert(e, onConflict: DoUpdate((_) => e));
      }

      // Les lignes d'une écriture servie sont REMPLACÉES : `updateManual` les recrée avec de
      // nouveaux identifiants, les anciennes ne sont plus servies — et ne doivent plus compter.
      for (final morceau in _morceaux(servies.toList())) {
        await (_db.delete(
          _db.accountingEntryLines,
        )..where((l) => l.entryId.isIn(morceau))).go();
      }
      for (final c in corps) {
        await _db.into(_db.accountingEntryLines).insert(c);
      }

      if (annoncees != null) {
        final locales = [
          for (final e in await _db.select(_db.accountingEntries).get()) e.id,
        ];

        // F0.84-bis — écritures annoncées actives et toujours absentes du poste : l'appelant relance
        // UNE fois le journal complet (voir `_tirer`).
        final presentes = locales.toSet();
        _journalManquants = annoncees.difference(presentes).length;

        // ⚠️⚠️ F0.84-bis — UNE LISTE VIDE N'EST PAS CRUE AU PREMIER TIRAGE. Un 200 avec
        // `accounting_entry_ids: []` peut venir d'un serveur branché sur une base vide ; l'avaler
        // viderait tout le journal local, qui ne se reconstruirait jamais. La réinitialisation
        // LÉGITIME produit la même réponse : la purge est donc repoussée d'un tirage et confirmée
        // par une seconde annonce vide. Aucune règle comptable : seule la prudence sur une
        // suppression irréversible.
        var purger = true;
        if (annoncees.isEmpty && locales.isNotEmpty) {
          if (await _lireReglage(cleJournalVidageAttendu) == null) {
            purger = false;
            await _ecrireReglage(cleJournalVidageAttendu, '1');
            avertissementVidage =
                'Le serveur annonce un journal comptable vide alors que ce poste '
                'contient ${locales.length} écriture(s) : rien n\'est supprimé pour '
                'l\'instant. Si le journal a réellement été réinitialisé, il sera vidé '
                'ici à la prochaine synchronisation.';
          } else {
            await _effacerReglage(cleJournalVidageAttendu);
          }
        } else {
          await _effacerReglage(cleJournalVidageAttendu);
        }
        if (!purger) return;

        final retirees = [
          for (final id in locales)
            if (!annoncees.contains(id)) id,
        ];
        for (final morceau in _morceaux(retirees)) {
          await (_db.delete(
            _db.accountingEntryLines,
          )..where((l) => l.entryId.isIn(morceau))).go();
          await (_db.delete(
            _db.accountingEntries,
          )..where((e) => e.id.isIn(morceau))).go();
        }

        // Lignes orphelines (écriture absente) : jamais conservées, elles fausseraient les états.
        final restantes = {
          for (final e in await _db.select(_db.accountingEntries).get()) e.id,
        };
        final orphelines = {
          for (final l in await _db.select(_db.accountingEntryLines).get())
            if (!restantes.contains(l.entryId)) l.entryId,
        };
        for (final morceau in _morceaux(orphelines.toList())) {
          await (_db.delete(
            _db.accountingEntryLines,
          )..where((l) => l.entryId.isIn(morceau))).go();
        }
      }
    });

    if (avertissementVidage != null) _avertissements.add(avertissementVidage!);

    return ecritures.length + lignes.length;
  }

  /// Découpe une liste d'identifiants pour rester sous la limite de variables de SQLite.
  static Iterable<List<String>> _morceaux(
    List<String> ids, [
    int taille = 500,
  ]) sync* {
    for (var i = 0; i < ids.length; i += taille) {
      yield ids.sublist(i, i + taille > ids.length ? ids.length : i + taille);
    }
  }

  /// Identité de la ferme — un OBJET, pas une collection.
  ///
  /// ⚠️⚠️ **LE SERVEUR NE SERT AUCUN SECRET**, et le poste n'a donc aucune
  /// colonne où en ranger : mots de passe SMTP et jetons SMS restent sur le
  /// serveur, même chiffrés. Un poste volé ne donne pas la boîte mail de la
  /// ferme.
  Future<int> _absorberEntreprise(Object? brut) async {
    if (brut is! Map) return 0;

    final l = brut.map((c, v) => MapEntry(c.toString(), v));

    final ligne = CompanySettingsCompanion.insert(
      id: const Value('unique'),
      companyName: Value(l['company_name'] as String?),
      promoterName: Value(l['promoter_name'] as String?),
      address: Value(l['address'] as String?),
      phone: Value(l['phone'] as String?),
      email: Value(l['email'] as String?),
      ifu: Value(l['ifu'] as String?),
      rccm: Value(l['rccm'] as String?),
      tvaEnabled: Value(_bool(l['tva_enabled'])),
      tvaDefaultRate: Value(_reel(l['tva_default_rate'])),
    );

    await _db
        .into(_db.companySettings)
        .insert(ligne, onConflict: DoUpdate((_) => ligne));

    return 1;
  }

  /// Modules d'espèce — référentiel remplacé à chaque tirage.
  ///
  /// ⚠️⚠️ **C'EST CE QUI DÉCIDE DES ESPÈCES VISIBLES.** Une ferme qui éteint
  /// l'héliciculture ne doit plus voir la fiche Escargots : la maquette masque
  /// les blocs `data-module`, le poste filtre ses cartes d'espèce.
  Future<int> _absorberModules(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.modulesConfig).go();

      for (final l in lignes) {
        await _db
            .into(_db.modulesConfig)
            .insert(
              ModulesConfigCompanion.insert(
                id: l['id'] as String,
                speciesCode: (l['species_code'] ?? '') as String,
                isEnabled: Value(_bool(l['is_enabled'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Rôles applicatifs — référentiel remplacé à chaque tirage.
  Future<int> _absorberRoles(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.rolesApplicatifs).go();

      for (final l in lignes) {
        final permissions = l['permissions'];

        await _db
            .into(_db.rolesApplicatifs)
            .insert(
              RolesApplicatifsCompanion.insert(
                id: (l['id'] ?? '').toString(),
                name: (l['name'] ?? '') as String,
                permissions: Value(
                  permissions is List ? permissions.join(', ') : null,
                ),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Utilisateurs — référentiel remplacé à chaque tirage.
  Future<int> _absorberUtilisateurs(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.utilisateurs).go();

      for (final l in lignes) {
        await _db
            .into(_db.utilisateurs)
            .insert(
              UtilisateursCompanion.insert(
                id: l['id'] as String,
                name: (l['name'] ?? '') as String,
                username: Value(l['username'] as String?),
                email: Value(l['email'] as String?),
                role: Value(l['role'] as String?),
                isActive: Value(_bool(l['is_active'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Journal d'audit — les cent dernières actions, remplacées à chaque tirage.
  Future<int> _absorberAudit(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.auditLogs).go();

      for (final l in lignes) {
        await _db
            .into(_db.auditLogs)
            .insert(
              AuditLogsCompanion.insert(
                id: l['id'] as String,
                userName: Value(l['user_name'] as String?),
                action: (l['action'] ?? '') as String,
                module: Value(l['module'] as String?),
                ipAddress: Value(l['ip_address'] as String?),
                createdAt: Value(_date(l['created_at'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Notifications de l'utilisateur du jeton — l'ENSEMBLE est remplacé à chaque
  /// tirage (ticket F0.59).
  ///
  /// ⚠️ **PAS DE TIRAGE INCRÉMENTAL** : « lue » et « supprimée » changent sans
  /// toucher à `created_at`, un `since` ne les verrait jamais. Le serveur envoie
  /// donc les 200 dernières visibles, et le poste remplace tout — une
  /// notification supprimée ailleurs disparaît ainsi d'ici.
  ///
  /// ⚠️ **ABSORBEUR STRICT** : une ligne sans identifiant ou sans message est
  /// REFUSÉE (l'exception remonte), jamais comblée par un texte inventé.
  Future<int> _absorberNotifications(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.notifications).go();

      for (final l in lignes) {
        await _db
            .into(_db.notifications)
            .insert(
              NotificationsCompanion.insert(
                id: l['id'] as String,
                type: (l['type'] ?? 'system') as String,
                category: Value((l['category'] ?? 'Système') as String),
                severity: Value((l['severity'] ?? 'info') as String),
                title: (l['title'] ?? '') as String,
                message: l['message'] as String,
                linkUrl: Value(l['link_url'] as String?),
                isRead: Value(_bool(l['is_read'])),
                createdAt: Value(_date(l['created_at'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Revenus par bande — l'ENSEMBLE est remplacé à chaque tirage (ticket F0.63).
  ///
  /// ⚠️ **UN TIRAGE SANS CE BLOC NE VIDE RIEN** (`brut == null`) : un serveur plus
  /// ancien n'envoie pas `lot_revenues`, et effacer les revenus connus sur ce
  /// silence les ferait disparaître.
  ///
  /// ⚠️ **UNE LISTE VIDE EST UNE RÉPONSE** : « aucune vente imputée à une bande ».
  /// La date de ce tirage est donc gardée À PART (`lot_revenues_tire_le`) : sans
  /// elle, le poste ne distinguerait pas « aucune vente » de « revenus jamais
  /// reçus », et afficherait « aucune vente » juste après une mise à jour, avant
  /// la première synchronisation.
  Future<int> _absorberRevenusDeBande(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.lotRevenues).go();

      for (final l in lignes) {
        await _db
            .into(_db.lotRevenues)
            .insert(
              LotRevenuesCompanion.insert(
                lotId: l['lot_id'] as String,
                productId: l['product_id'] as String,
                label: (l['label'] ?? '') as String,
                amount: _reel(l['amount']) ?? 0,
              ),
            );
      }

      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: cleRevenusTires,
              value: DateTime.now().toUtc().toIso8601String(),
            ),
          );
    });

    return lignes.length;
  }

  /// Clé de `app_settings` datant le dernier tirage des revenus par bande.
  static const cleRevenusTires = 'lot_revenues_tire_le';

  /// Espèces d'élevage actives — l'ENSEMBLE est remplacé à chaque tirage (F0.67).
  ///
  /// ⚠️ Un tirage sans ce bloc ne vide rien (serveur plus ancien). Une liste VIDE
  /// est une réponse : aucun module d'espèce n'est actif.
  Future<int> _absorberEspeces(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.livestockSpecies).go();

      for (final l in lignes) {
        await _db
            .into(_db.livestockSpecies)
            .insert(
              LivestockSpeciesCompanion.insert(
                id: l['id'] as String,
                code: l['code'] as String,
                label: l['label'] as String,
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Sujets suivis individuellement — l'ENSEMBLE est remplacé à chaque tirage
  /// (ticket F0.65).
  ///
  /// ⚠️ Un tirage sans ce bloc ne vide rien (serveur plus ancien). Absorbeur
  /// STRICT : un sujet sans identifiant lisible est refusé — il ne se retrouverait
  /// ni par son QR ni par la référence d'une saillie.
  Future<int> _absorberSujets(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.animals).go();

      for (final l in lignes) {
        await _db
            .into(_db.animals)
            .insert(
              AnimalsCompanion.insert(
                id: l['id'] as String,
                identifier: l['identifier'] as String,
                speciesLabel: Value(l['species_label'] as String?),
                lotId: Value(l['lot_id'] as String?),
                lotCode: Value(l['lot_code'] as String?),
                category: Value((l['category'] ?? 'reproducteur') as String),
                sex: Value((l['sex'] ?? 'F') as String),
                breed: Value(l['breed'] as String?),
                birthDate: Value(_date(l['birth_date'])),
                entryDate: Value(_date(l['entry_date'])),
                origin: Value(l['origin'] as String?),
                cage: Value(l['cage'] as String?),
                status: Value((l['status'] ?? 'actif') as String),
                exitDate: Value(_date(l['exit_date'])),
                exitReason: Value(l['exit_reason'] as String?),
                isActive: Value(_bool(l['is_active'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Modèles d'attestation — l'ENSEMBLE est remplacé à chaque tirage (F0.64).
  ///
  /// ⚠️ Un tirage sans ce bloc ne vide rien (serveur plus ancien). Absorbeur
  /// STRICT : un modèle sans identifiant ou sans texte est refusé, jamais comblé
  /// par un texte inventé — un modèle fait foi sur un document officiel.
  Future<int> _absorberModelesAttestation(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.attestationTemplates).go();

      for (final l in lignes) {
        await _db
            .into(_db.attestationTemplates)
            .insert(
              AttestationTemplatesCompanion.insert(
                id: l['id'] as String,
                type: l['type'] as String,
                bodyText: l['body_text'] as String,
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Nombre d'attestations émises, par type — ⚠️ UN DÉCOMPTE D'AUDIT DU SERVEUR.
  ///
  /// Le poste ne détient que les cent dernières lignes d'audit de la ferme : il
  /// ne peut pas recompter. Le serveur compte sur l'historique entier ; le poste
  /// garde ce nombre tel quel, dans `app_settings`.
  Future<int> _absorberCompteursAttestation(Object? brut) async {
    if (brut is! Map) return 0;

    var n = 0;
    for (final type in ['employe', 'stagiaire']) {
      final valeur = _entier(brut[type]);
      if (valeur == null) continue;

      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: cleAttestationsEmises(type),
              value: '$valeur',
            ),
          );
      n++;
    }
    return n;
  }

  /// Clé de `app_settings` portant le nombre d'attestations émises d'un type.
  static String cleAttestationsEmises(String type) =>
      'attestations_emises_$type';

  /// Courriers — FUSIONNÉS par identifiant (ticket F0.78).
  ///
  /// ⚠️⚠️ **« TOUT EFFACER PUIS RÉINSÉRER » EST RETIRÉ** : il aurait fait disparaître, au
  /// tirage suivant, un courrier saisi au poste et pas encore acquitté. Un courrier
  /// `pending` ou `conflict` n'est NI écrasé NI effacé : il n'existe (ou n'a changé) que
  /// sur ce poste.
  ///
  /// ⚠️ **LE SERVEUR SERT TOUS LES COURRIERS ACTIFS À CHAQUE TIRAGE**, plus les archivés
  /// dont `updated_at > since` (avec `is_active = false`). Donc : un archivé qui descend
  /// est retiré du poste ; un courrier `synced` absent du tirage a été archivé plus tôt
  /// (ou n'existe plus) — il est retiré aussi. La référence `CR-AAAA-NNN` vient toujours
  /// du serveur.
  ///
  /// ⚠️ **STRICT** : une ligne sans identifiant, sans objet, de type inconnu ou de date
  /// illisible est REFUSÉE (la transaction entière est annulée) — jamais comblée.
  Future<int> _absorberCourriers(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      final protegees = {
        for (final m
            in await (_db.select(_db.mails)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          m.id,
      };

      final servis = <String>{};

      for (final l in lignes) {
        final id = l['id'];
        final type = l['type'];
        final objet = l['subject'];

        if (id is! String || id.length != 36) {
          throw FormatException(
            'Courrier refusé : identifiant invalide ($id).',
          );
        }
        if (type != 'entrant' && type != 'sortant') {
          throw FormatException('Courrier $id refusé : type inconnu ($type).');
        }
        if (objet is! String || objet.trim().isEmpty) {
          throw FormatException('Courrier $id refusé : objet absent.');
        }
        final dateBrute = l['mail_date'];
        final date = _date(dateBrute);
        if (dateBrute != null && date == null) {
          throw FormatException(
            'Courrier $id refusé : date illisible ($dateBrute).',
          );
        }

        servis.add(id);
        if (protegees.contains(id)) continue;

        // Archivé côté serveur : il quitte la liste du poste (rien n'y est supprimé là-bas).
        if (l.containsKey('is_active') && !_bool(l['is_active'])) {
          await (_db.delete(_db.mails)..where((t) => t.id.equals(id))).go();
          continue;
        }

        await _db
            .into(_db.mails)
            .insertOnConflictUpdate(
              MailsCompanion.insert(
                id: id,
                reference: Value(l['reference'] as String?),
                type: type as String,
                subject: objet,
                party: Value(l['party'] as String?),
                mailDate: Value(date),
                isActive: const Value(true),
                syncStatus: const Value(SyncStatus.synced),
                knownByServer: const Value(true),
              ),
            );
      }

      // Une ligne synchronisée que le serveur n'a PAS servie n'est plus un courrier actif.
      await (_db.delete(_db.mails)..where(
            (t) => Expression.and([
              t.syncStatus.equalsValue(SyncStatus.synced),
              t.id.isIn(servis).not(),
            ]),
          ))
          .go();
    });

    return lignes.length;
  }

  /// Documents administratifs — FUSIONNÉS par identifiant (ticket F0.80), comme les courriers
  /// et les documents archivés.
  ///
  /// ⚠️⚠️ **« TOUT EFFACER PUIS RÉINSÉRER » EST RETIRÉ** : il aurait fait disparaître, au
  /// tirage suivant, un document saisi au poste et pas encore acquitté, et fait réapparaître un
  /// document retiré sur le web. Une ligne `pending` ou `conflict` n'est NI écrasée NI
  /// effacée : elle n'existe (ou n'a changé) que sur ce poste.
  ///
  /// ⚠️ **LE SERVEUR SERT TOUS LES DOCUMENTS ACTIFS À CHAQUE TIRAGE**, plus les retirés dont
  /// `updated_at > since` (avec `is_active = false`). Donc : un retiré qui descend est
  /// supprimé du poste ; une ligne `synced` absente du tirage a été retirée plus tôt (ou
  /// n'existe plus) — supprimée aussi.
  ///
  /// ⚠️ **STRICT** : identifiant ≠ 36 caractères, titre / type / bénéficiaire absents ou
  /// vides, date absente ou illisible, statut hors {signe, en_attente} → REFUSÉ (la transaction
  /// entière est annulée), jamais comblé. Un type hors de la liste proposée (texte libre) est
  /// conservé tel quel.
  Future<int> _absorberDocuments(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      final protegees = {
        for (final d
            in await (_db.select(_db.administrativeDocuments)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          d.id,
      };

      final servis = <String>{};

      for (final l in lignes) {
        final id = l['id'];
        final titre = l['title'];
        final type = l['type'];
        final beneficiaire = l['beneficiary'];
        final statut = l['status'];

        if (id is! String || id.length != 36) {
          throw FormatException(
            'Document administratif refusé : identifiant invalide ($id).',
          );
        }
        if (titre is! String || titre.trim().isEmpty) {
          throw FormatException(
            'Document administratif $id refusé : titre absent.',
          );
        }
        if (type is! String || type.trim().isEmpty) {
          throw FormatException(
            'Document administratif $id refusé : type absent.',
          );
        }
        if (beneficiaire is! String || beneficiaire.trim().isEmpty) {
          throw FormatException(
            'Document administratif $id refusé : bénéficiaire absent.',
          );
        }
        final dateBrute = l['doc_date'];
        final date = _date(dateBrute);
        if (date == null) {
          throw FormatException(
            'Document administratif $id refusé : date illisible ($dateBrute).',
          );
        }
        if (statut != 'signe' && statut != 'en_attente') {
          throw FormatException(
            'Document administratif $id refusé : statut inconnu ($statut).',
          );
        }

        servis.add(id);
        if (protegees.contains(id)) continue;

        // Retiré côté serveur : il quitte la liste du poste (rien n'y est supprimé là-bas).
        if (l.containsKey('is_active') && !_bool(l['is_active'])) {
          await (_db.delete(
            _db.administrativeDocuments,
          )..where((t) => t.id.equals(id))).go();
          continue;
        }

        await _db
            .into(_db.administrativeDocuments)
            .insertOnConflictUpdate(
              AdministrativeDocumentsCompanion.insert(
                id: id,
                title: titre,
                type: Value(type),
                beneficiary: Value(beneficiaire),
                docDate: Value(date),
                status: Value(statut as String),
                isActive: const Value(true),
                syncStatus: const Value(SyncStatus.synced),
                knownByServer: const Value(true),
              ),
            );
      }

      // Une ligne synchronisée que le serveur n'a PAS servie n'est plus un document actif.
      await (_db.delete(_db.administrativeDocuments)..where(
            (t) => Expression.and([
              t.syncStatus.equalsValue(SyncStatus.synced),
              t.id.isIn(servis).not(),
            ]),
          ))
          .go();
    });

    return lignes.length;
  }

  /// Documents archivés — FUSIONNÉS par identifiant (ticket F0.79), comme les courriers.
  ///
  /// ⚠️⚠️ **« TOUT EFFACER PUIS RÉINSÉRER » EST RETIRÉ** : il aurait fait disparaître, au
  /// tirage suivant, un document saisi au poste et pas encore acquitté. Une ligne
  /// `pending` ou `conflict` n'est NI écrasée NI effacée : elle n'existe (ou n'a changé) que
  /// sur ce poste.
  ///
  /// ⚠️ **LE SERVEUR SERT TOUS LES DOCUMENTS ACTIFS À CHAQUE TIRAGE**, plus les retirés dont
  /// `updated_at > since` (avec `is_active = false`). Donc : un retiré qui descend est
  /// supprimé du poste ; une ligne `synced` absente du tirage a été retirée plus tôt (ou n'existe
  /// plus) — supprimée aussi. Aucun statut n'est servi : il se calcule au poste.
  ///
  /// ⚠️ **STRICT** : identifiant ≠ 36 caractères, titre ou catégorie absents ou vides, date
  /// d'archivage absente ou illisible, échéance illisible → REFUSÉ (la transaction entière
  /// est annulée), jamais comblé.
  Future<int> _absorberArchives(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      final protegees = {
        for (final a
            in await (_db.select(_db.archivedDocuments)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          a.id,
      };

      final servis = <String>{};

      for (final l in lignes) {
        final id = l['id'];
        final titre = l['title'];
        final categorie = l['category'];

        if (id is! String || id.length != 36) {
          throw FormatException(
            'Document archivé refusé : identifiant invalide ($id).',
          );
        }
        if (titre is! String || titre.trim().isEmpty) {
          throw FormatException('Document archivé $id refusé : titre absent.');
        }
        if (categorie is! String || categorie.trim().isEmpty) {
          throw FormatException(
            'Document archivé $id refusé : catégorie absente.',
          );
        }
        final archiveBrute = l['archived_date'];
        final archive = _date(archiveBrute);
        if (archive == null) {
          throw FormatException(
            'Document archivé $id refusé : date d\'archivage illisible ($archiveBrute).',
          );
        }
        final echeanceBrute = l['expiry_date'];
        final echeance = _date(echeanceBrute);
        if (echeanceBrute != null && echeance == null) {
          throw FormatException(
            'Document archivé $id refusé : échéance illisible ($echeanceBrute).',
          );
        }

        servis.add(id);
        if (protegees.contains(id)) continue;

        // Retiré côté serveur : il quitte la liste du poste (rien n'y est supprimé là-bas).
        if (l.containsKey('is_active') && !_bool(l['is_active'])) {
          await (_db.delete(
            _db.archivedDocuments,
          )..where((t) => t.id.equals(id))).go();
          continue;
        }

        await _db
            .into(_db.archivedDocuments)
            .insertOnConflictUpdate(
              ArchivedDocumentsCompanion.insert(
                id: id,
                title: titre,
                category: Value(categorie),
                archivedDate: Value(archive),
                expiryDate: Value(echeance),
                isActive: const Value(true),
                syncStatus: const Value(SyncStatus.synced),
                knownByServer: const Value(true),
              ),
            );
      }

      // Une ligne synchronisée que le serveur n'a PAS servie n'est plus un document actif.
      await (_db.delete(_db.archivedDocuments)..where(
            (t) => Expression.and([
              t.syncStatus.equalsValue(SyncStatus.synced),
              t.id.isIn(servis).not(),
            ]),
          ))
          .go();
    });

    return lignes.length;
  }

  /// Employés — référentiel remplacé à chaque tirage.
  ///
  /// ⚠️ Un employé archivé côté serveur disparaît du tirage : le garder ferait
  /// pointer quelqu'un qui a quitté la ferme, et le pointage serait rejeté à
  /// l'envoi sans que le chef d'équipe comprenne.
  Future<int> _absorberEmployes(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.employees).go();

      for (final l in lignes) {
        await _db
            .into(_db.employees)
            .insert(
              EmployeesCompanion.insert(
                id: l['id'] as String,
                firstName: (l['first_name'] ?? '') as String,
                lastName: (l['last_name'] ?? '') as String,
                position: Value(l['position'] as String?),
                baseSalary: Value(_reel(l['base_salary'])),
                hireDate: Value(_date(l['hire_date'])),
                status: Value(l['status'] as String?),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Stagiaires — référentiel remplacé à chaque tirage.
  Future<int> _absorberStagiaires(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.internships).go();

      for (final l in lignes) {
        await _db
            .into(_db.internships)
            .insert(
              InternshipsCompanion.insert(
                id: l['id'] as String,
                firstName: (l['first_name'] ?? '') as String,
                lastName: (l['last_name'] ?? '') as String,
                school: Value(l['school'] as String?),
                startDate: Value(_date(l['start_date'])),
                endDate: Value(_date(l['end_date'])),
                monthlyFee: Value(_reel(l['monthly_fee'])),
                feePaid: Value(_bool(l['fee_paid'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Pointages — fusion, et un pointage `pending` reste intouchable.
  ///
  /// ⚠️⚠️ **CE QUI N'EST PAS PARTI N'EST PAS ÉCRASÉ.** Le pointage de ce matin
  /// n'existe que sur ce poste : l'effacer perdrait la seule trace de la
  /// présence, et la paie du mois se calcule dessus.
  Future<int> _absorberPointages(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    for (final l in lignes) {
      final id = l['id'] as String;

      final local = await (_db.select(
        _db.attendanceRecords,
      )..where((t) => t.id.equals(id))).getSingleOrNull();

      if (local != null && local.syncStatus != SyncStatus.synced) continue;

      final jour = _date(l['attendance_date']) ?? DateTime.now();

      final ligne = AttendanceRecordsCompanion.insert(
        id: id,
        deviceId: 'serveur',
        updatedAt: jour,
        syncStatus: const Value(SyncStatus.synced),
        employeeId: (l['employee_id'] ?? '') as String,
        attendanceDate: jour,
        checkIn: Value(l['check_in'] as String?),
        checkOut: Value(l['check_out'] as String?),
        status: (l['status'] ?? 'present') as String,
      );

      await _db
          .into(_db.attendanceRecords)
          .insert(ligne, onConflict: DoUpdate((_) => ligne));
    }

    return lignes.length;
  }

  /// Factures — c'est-à-dire les VENTES de toute la ferme.
  ///
  /// ⚠️⚠️ **FUSION, JAMAIS UN REMPLACEMENT — ET UNE VENTE `pending` EST
  /// INTOUCHABLE.** Elle n'existe que sur ce poste : encaissée au comptoir il y
  /// a dix minutes, pas encore envoyée. L'écraser perdrait la recette ET la
  /// sortie de stock qui l'accompagne.
  ///
  /// ⚠️ **LE STATUT MeCeF PEUT CHANGER SANS QUE LA VENTE CHANGE** : une
  /// retransmission réussie depuis le web touche `updated_at`, la facture
  /// redescend donc avec son nouveau statut. C'est la seule façon pour le poste
  /// d'apprendre qu'une transmission en erreur a été rattrapée.
  Future<int> _absorberVentes(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    for (final l in lignes) {
      final id = l['id'] as String;

      final locale = await (_db.select(
        _db.sales,
      )..where((t) => t.id.equals(id))).getSingleOrNull();

      if (locale != null && locale.syncStatus != SyncStatus.synced) continue;

      // TICKET F0.93 (réserve 2 de l'audit indépendant) : le repli lit l'horloge INJECTÉE,
      // comme `horodatage` ci-dessous — jamais `DateTime.now()`, invisible à un test figé.
      final vendueLe = _date(l['sold_at']) ?? _maintenant();

      // 🔴→✅ TICKET F0.90 (remarque B2 de l'audit) — `updatedAt` N'EST PLUS `sold_at`. Règle du
      // poste : `updatedAt` = instant de la SAISIE (ou, pour ce qui vient d'ailleurs, de la
      // RÉCEPTION), jamais le jour de la vente : une vente antidatée au 11 et saisie le 14 aurait
      // reçu un horodatage du 11. Le serveur ne sert NI `updated_at` NI `created_at` de la vente
      // (lu : `SyncController::pull`, bloc `$factures`) ; le poste n'invente donc rien :
      //  - vente déjà connue (saisie sur CE poste, ou déjà reçue) : son `updatedAt` est GARDÉ —
      //    un changement de statut MeCeF ne change pas l'instant où la vente a été saisie ;
      //  - vente inconnue : instant de la RÉCEPTION (horloge du poste).
      // Sans effet sur l'arbitrage aujourd'hui (une vente acquittée ne repart jamais) ; c'est la
      // valeur qui ne peut pas mentir le jour où elle servira.
      final horodatage = locale?.updatedAt ?? _maintenant();

      final ligne = SalesCompanion.insert(
        id: id,
        deviceId: 'serveur',
        updatedAt: horodatage,
        syncStatus: const Value(SyncStatus.synced),
        customerId: Value(l['customer_id'] as String?),
        customerName: Value(l['customer_name'] as String?),
        paymentMode: (l['payment_mode'] ?? 'especes') as String,
        total: _reel(l['total']) ?? 0,
        status: Value((l['status'] ?? 'validee') as String),
        mecefStatus: Value(l['mecef_status'] as String?),
        mecefQrRef: Value(l['mecef_qr_ref'] as String?),
        soldAt: vendueLe,
      );

      await _db
          .into(_db.sales)
          .insert(ligne, onConflict: DoUpdate((_) => ligne));
    }

    return lignes.length;
  }

  /// Dettes fournisseurs encore dues — référentiel remplacé à chaque tirage.
  ///
  /// ⚠️⚠️ **REMPLACEMENT COMPLET, ET C'EST VOULU.** Le serveur ne sert que ce
  /// qui reste dû : une dette réglée entre deux tirages DISPARAÎT de la charge.
  /// La fusionner la laisserait éternellement à l'ardoise du poste — et la
  /// ferme croirait devoir une somme déjà payée.
  Future<int> _absorberDettes(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.payables).go();

      for (final l in lignes) {
        await _db
            .into(_db.payables)
            .insert(
              PayablesCompanion.insert(
                id: l['id'] as String,
                supplierId: (l['supplier_id'] ?? '') as String,
                supplierName: Value(l['supplier_name'] as String?),
                purchaseId: Value(l['purchase_id'] as String?),
                amount: _reel(l['amount']) ?? 0,
                amountPaid: Value(_reel(l['amount_paid']) ?? 0),
                dueDate: Value(_date(l['due_date'])),
                status: Value(l['status'] as String?),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Bons de commande — référentiel remplacé à chaque tirage.
  Future<int> _absorberBonsCommande(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.purchaseOrders).go();

      for (final l in lignes) {
        await _db
            .into(_db.purchaseOrders)
            .insert(
              PurchaseOrdersCompanion.insert(
                id: l['id'] as String,
                supplierId: Value(l['supplier_id'] as String?),
                supplierName: Value(l['supplier_name'] as String?),
                expectedDeliveryDate: Value(_date(l['expected_delivery_date'])),
                status: Value(l['status'] as String?),
                createdAt: Value(_date(l['created_at'])),
                estimatedTotal: Value(_reel(l['estimated_total']) ?? 0),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Achats — fusion, et JAMAIS un remplacement.
  ///
  /// ⚠️⚠️ **UN ACHAT `pending` NE DOIT PAS ÊTRE ÉCRASÉ PAR LE TIRAGE.** Il
  /// n'existe que sur ce poste : une livraison reçue ce matin, pas encore
  /// envoyée. L'effacer perdrait la saisie ET la marchandise entrée en stock —
  /// c'est la règle déjà posée pour les cycles de reproduction (F0.35).
  ///
  /// ⚠️ Les lignes ne descendent pas : la liste d'achats de la maquette montre
  /// la pièce, pas son détail. Celles d'un achat local restent intactes.
  Future<int> _absorberAchats(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    for (final l in lignes) {
      final id = l['id'] as String;

      final local = await (_db.select(
        _db.purchases,
      )..where((t) => t.id.equals(id))).getSingleOrNull();

      if (local != null && local.syncStatus != SyncStatus.synced) continue;

      final ligne = PurchasesCompanion.insert(
        id: id,
        deviceId: 'serveur',
        updatedAt: _date(l['purchase_date']) ?? DateTime.now(),
        syncStatus: const Value(SyncStatus.synced),
        supplierId: (l['supplier_id'] ?? '') as String,
        supplierName: Value(l['supplier_name'] as String?),
        supplierCategory: Value(l['supplier_category'] as String?),
        paymentMode: (l['payment_mode'] ?? 'especes') as String,
        total: _reel(l['total']) ?? 0,
        hasDebt: Value(_bool(l['has_debt'])),
        purchaseDate: _date(l['purchase_date']) ?? DateTime.now(),
        // ⚠️ TICKET F0.74 — LE RETOUR EST SERVI PAR LE SERVEUR ET REMPLACE L'ÉTAT LOCAL.
        // `returned_at` et `supplier_credit` ne s'écrivent JAMAIS au poste. Une clé
        // ABSENTE (serveur plus ancien) laisse la colonne telle quelle ; une clé présente
        // mais nulle dit « pas retourné ».
        returnedAt: l.containsKey('returned_at')
            ? Value(_date(l['returned_at']))
            : const Value.absent(),
        supplierCredit: l.containsKey('supplier_credit')
            ? Value(_reel(l['supplier_credit']))
            : const Value.absent(),
      );

      await _db
          .into(_db.purchases)
          .insert(ligne, onConflict: DoUpdate((_) => ligne));
    }

    return lignes.length;
  }

  /// Créance OUVERTE par fournisseur (`supplier_credits`, ticket F0.74) — remplacée en
  /// entier à chaque tirage.
  ///
  /// ⚠️ **LE SERVEUR LA SERT SANS FILTRE `since`, ET SEULEMENT POUR LES FOURNISSEURS > 0** :
  /// un fournisseur absent du tirage n'a plus de créance (tout est remboursé). Une liste
  /// VIDE vide donc la table ; une clé ABSENTE (serveur plus ancien) ne touche à rien. La
  /// table n'a aucune écriture locale : rien de `pending` à protéger (les remboursements en
  /// attente vivent dans `supplier_refunds` et se déduisent à la lecture).
  Future<int> _absorberCreancesFournisseurs(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.supplierCredits).go();

      for (final l in lignes) {
        await _db
            .into(_db.supplierCredits)
            .insertOnConflictUpdate(
              SupplierCreditsCompanion.insert(
                supplierId: l['supplier_id'] as String,
                supplierName: Value(l['supplier_name'] as String?),
                openCredit: _reel(l['open_credit']) ?? 0,
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Relances déjà envoyées — référentiel remplacé à chaque tirage.
  ///
  /// ⚠️⚠️ **CE QUE LEUR ABSENCE COÛTAIT** : une file de relance où le débiteur
  /// contacté ce matin par WhatsApp est présenté exactement comme le voisin que
  /// personne n'a jamais appelé. Le poste faisait rappeler deux fois — la faute
  /// la plus visible pour un client, et la seule qu'il raconte.
  Future<int> _absorberRelances(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.customerReminders).go();

      for (final l in lignes) {
        await _db
            .into(_db.customerReminders)
            .insert(
              CustomerRemindersCompanion.insert(
                id: l['id'] as String,
                customerId: (l['customer_id'] ?? '') as String,
                receivableId: Value(l['receivable_id'] as String?),
                channel: (l['channel'] ?? 'courrier') as String,
                reminderDate: Value(_date(l['reminder_date'])),
                message: Value(l['message'] as String?),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Protocole prophylactique : référentiel remplacé à chaque tirage.
  /// Comptes de tresorerie — qui peut payer une depense.
  ///
  /// ⚠️ REMPLACEMENT COMPLET, PAS UNE FUSION. Un compte cloture cote serveur
  /// disparait du tirage : le garder proposerait un payeur qui n'existe plus,
  /// et la depense serait rejetee a l'envoi sans que l'animalier comprenne.
  Future<int> _absorberComptesTresorerie(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.treasuryAccounts).go();
      await _db.batch((b) {
        for (final l in lignes) {
          b.insert(
            _db.treasuryAccounts,
            TreasuryAccountsCompanion.insert(
              id: l['id'] as String,
              label: (l['label'] ?? '') as String,
              accountCode: Value(l['account_code'] as String?),
              type: Value(l['type'] as String?),
              balance: Value(_reel(l['balance']) ?? 0),
            ),
          );
        }
      });
    });

    return lignes.length;
  }

  /// Comptes de charge proposes a la saisie.
  ///
  /// ⚠️ MEME RAISON : la liste vit cote serveur (`Expense::CATEGORIES`) et un
  /// compte retire doit disparaitre du poste, sinon la depense part vers une
  /// imputation refusee.
  Future<int> _absorberCategoriesDepense(Object? brut) async {
    if (brut is! List) return 0;

    final libelles = brut.whereType<String>().toList();

    await _db.transaction(() async {
      await _db.delete(_db.expenseCategories).go();
      await _db.batch((b) {
        for (final libelle in libelles) {
          b.insert(
            _db.expenseCategories,
            ExpenseCategoriesCompanion.insert(label: libelle),
          );
        }
      });
    });

    return libelles.length;
  }

  Future<int> _absorberProphylaxie(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.batch((b) {
      for (final l in lignes) {
        final ligne = ProphylaxisScheduleStandardsCompanion.insert(
          id: l['id'] as String,
          speciesCode: (l['species_code'] ?? '') as String,
          periodLabel: (l['period_label'] ?? '') as String,
          // ⚠️ ABSENTES = NULLES, JAMAIS ZERO. Le serveur laisse ces bornes
          // vides pour les entrees calendaires (« Le 1er du mois ») dont la
          // base de calcul n'est pas le jour de cycle. Les remplacer par 0
          // les rendrait dues au premier jour de chaque bande.
          cycleDayStart: Value(_entier(l['cycle_day_start'])),
          cycleDayEnd: Value(_entier(l['cycle_day_end'])),
          treatment: (l['treatment'] ?? '') as String,
          productRecommended: Value(l['product_recommended'] as String?),
          dosage: Value(l['dosage'] as String?),
          withdrawalDays: Value(_entier(l['withdrawal_days']) ?? 0),
        );
        b.insert(
          _db.prophylaxisScheduleStandards,
          ligne,
          onConflict: DoUpdate((_) => ligne),
        );
      }
    });

    return lignes.length;
  }

  /// Registre des soins déjà administrés.
  ///
  /// ⚠️ CE QUI VIENT DU SERVEUR EST MARQUÉ `synced` : le renvoyer le ferait
  /// rejouer par l'Action serveur, qui recréerait une période de rémanence —
  /// la bande serait bloquée deux fois plus longtemps qu'elle ne doit l'être.
  ///
  /// ⚠️ `withdrawalDays` RESTE À ZÉRO pour un soin reçu : le délai a déjà été
  /// consommé par le serveur au moment de sa création, il n'est pas une donnée
  /// du registre.
  Future<int> _absorberSoins(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.batch((b) {
      for (final l in lignes) {
        final ligne = VeterinaryRecordsCompanion.insert(
          id: l['id'] as String,
          deviceId: (l['device_id'] ?? 'serveur') as String,
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: _date(l['updated_at']) ?? DateTime.now(),
          lotId: (l['lot_id'] ?? '') as String,
          actionType: (l['action_type'] ?? '') as String,
          productUsed: Value(l['product_used'] as String?),
          dose: Value(l['dose'] as String?),
          vetName: Value(l['vet_name'] as String?),
          symptomes: Value(l['symptomes'] as String?),
          cost: Value(_reel(l['cost'])),
          recordDate: _date(l['record_date']) ?? DateTime.now(),
        );
        b.insert(
          _db.veterinaryRecords,
          ligne,
          onConflict: DoUpdate((_) => ligne),
        );
      }
    });

    return lignes.length;
  }

  /// Envoie la file d'attente et n'acquitte QUE ce que le serveur a accepté.
  Future<(int, int, List<String>)> _pousser() async {
    // ⚠️ F0.89 — LES FICHES PARTENT DANS L'ORDRE DES JOURS. Le serveur recalcule l'effectif de
    // chaque fiche reçue à partir de la veille QU'IL CONNAÎT, dans l'ordre du tableau : une vente
    // antérieure crée sa fiche APRÈS celle du jour (ordre d'insertion inverse), et l'envoyer en
    // premier ferait partir le jour suivant d'une veille périmée.
    final fiches =
        await (_db.select(_db.livestockDailyEntries)
              ..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))
              ..orderBy([
                (t) => OrderingTerm(expression: t.entryDate),
                (t) => OrderingTerm(expression: t.lotId),
              ]))
            .get();

    final ventes = await (_db.select(
      _db.sales,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final ajustements = await (_db.select(
      _db.stockAdjustments,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final soins = await (_db.select(
      _db.veterinaryRecords,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final depenses = await (_db.select(
      _db.expenses,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final saillies = await (_db.select(
      _db.livestockReproductionEvents,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final achats = await (_db.select(
      _db.purchases,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final pointages = await (_db.select(
      _db.attendanceRecords,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final produits = await (_db.select(
      _db.products,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final fournisseurs = await (_db.select(
      _db.suppliers,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final reglements = await (_db.select(
      _db.supplierPayments,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final clients = await (_db.select(
      _db.customers,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final courriers = await (_db.select(
      _db.mails,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final archives = await (_db.select(
      _db.archivedDocuments,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final documents = await (_db.select(
      _db.administrativeDocuments,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final avances = await (_db.select(
      _db.customerAdvances,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final imputations = await (_db.select(
      _db.advanceImputations,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final retours = await (_db.select(
      _db.purchaseReturns,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final remboursements = await (_db.select(
      _db.supplierRefunds,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    _financiersAcquittes = 0;
    _courriersAcquittes = 0;
    _archivesAcquittees = 0;
    _documentsAcquittes = 0;

    if (fiches.isEmpty &&
        courriers.isEmpty &&
        archives.isEmpty &&
        documents.isEmpty &&
        retours.isEmpty &&
        remboursements.isEmpty &&
        avances.isEmpty &&
        imputations.isEmpty &&
        produits.isEmpty &&
        reglements.isEmpty &&
        fournisseurs.isEmpty &&
        clients.isEmpty &&
        ventes.isEmpty &&
        ajustements.isEmpty &&
        soins.isEmpty &&
        depenses.isEmpty &&
        saillies.isEmpty &&
        achats.isEmpty &&
        pointages.isEmpty) {
      return (0, 0, <String>[]);
    }

    final lignesDAchat = <String, List<PurchaseLine>>{};
    for (final a in achats) {
      lignesDAchat[a.id] = await (_db.select(
        _db.purchaseLines,
      )..where((t) => t.purchaseId.equals(a.id))).get();
    }

    final lignesDeVente = <String, List<SaleLine>>{};
    for (final v in ventes) {
      lignesDeVente[v.id] = await (_db.select(
        _db.saleLines,
      )..where((t) => t.saleId.equals(v.id))).get();
    }

    // ⚠️ F0.90 — fiches COMPLÈTES (modifiées au poste) et fiches D'IDENTITÉ (ventes en file dont la
    // fiche est déjà synchronisée) partent ensemble, triées par jour puis bande comme ci-dessus.
    // Une fiche `pending` n'est jamais aussi « d'identité » (filtre `synced`) : pas de doublon.
    final identites = await _fichesDIdentite(ventes, lignesDeVente);
    final fichesEnvoyees =
        [
          for (final f in fiches) (f, false),
          for (final f in identites) (f, true),
        ]..sort((a, b) {
          final jour = a.$1.entryDate.compareTo(b.$1.entryDate);
          return jour != 0 ? jour : a.$1.lotId.compareTo(b.$1.lotId);
        });

    // ⚠️ F0.95 — LE DÉPART NE PART QU'AVEC LA FICHE TÊTE DE CHAÎNE (D4) : la première fiche locale
    // de la bande au départ COMPLET. Un départ resté sur une fiche postérieure (le serveur l'ignore
    // et le signale) ferait refuser, à l'envoi, une simple correction de cette fiche (« effectif
    // de départ déjà fixé »).
    final tetes = <String>{};
    for (final lot in {for (final f in fiches) f.lotId}) {
      final tete =
          await (_db.select(_db.livestockDailyEntries)
                ..where(
                  (t) => Expression.and([
                    t.lotId.equals(lot),
                    t.catDepartRepro.isNotNull(),
                    t.catDepartSevre.isNotNull(),
                    t.catDepartJeune.isNotNull(),
                  ]),
                )
                ..orderBy([(t) => OrderingTerm(expression: t.entryDate)])
                ..limit(1))
              .getSingleOrNull();
      if (tete != null) tetes.add(tete.id);
    }

    final reponse = await _client.post<Map<String, dynamic>>(
      '/api/sync/push',
      data: {
        'device_id': _deviceId,
        'livestock_daily_entries': [
          for (final (f, identite) in fichesEnvoyees)
            identite
                ? _ficheIdentiteEnJson(f)
                : _ficheEnJson(f, tete: tetes.contains(f.id)),
        ],
        'sales': ventes
            .map((v) => _venteEnJson(v, lignesDeVente[v.id] ?? const []))
            .toList(),
        'stock_adjustments': ajustements.map(_ajustementEnJson).toList(),
        'veterinary_records': soins.map(_soinEnJson).toList(),
        'expenses': depenses.map(_depenseEnJson).toList(),
        'livestock_reproduction_events': saillies.map(_saillieEnJson).toList(),
        'purchases': achats
            .map((a) => _achatEnJson(a, lignesDAchat[a.id] ?? const []))
            .toList(),
        'attendance_records': pointages.map(_pointageEnJson).toList(),
        'products': produits.map(_produitEnJson).toList(),
        'supplier_payments': reglements.map(_reglementEnJson).toList(),
        // ⚠️ TICKET F0.74 — le serveur traite : achats → règlements → RETOURS →
        // REMBOURSEMENTS → … → ajustements de stock, quel que soit l'ordre des clés. Un
        // retour part dans le MÊME envoi que son achat (ou après lui) ; ⚠️ JAMAIS de
        // `stock_adjustments` pour un retour : le serveur décrémente et rejette toute
        // sortie qui le désigne.
        'purchase_returns': retours.map(_retourEnJson).toList(),
        'supplier_refunds': remboursements.map(_remboursementEnJson).toList(),
        'suppliers': fournisseurs.map(_fournisseurEnJson).toList(),
        'customers': clients.map(_clientEnJson).toList(),
        // ⚠️ F0.78 — la référence `CR-AAAA-NNN` ne part JAMAIS : le serveur l'attribue.
        'mails': courriers.map(_courrierEnJson).toList(),
        // ⚠️ F0.79 — retirer = {id, is_active:false} seulement ; aucun statut ne part.
        'archived_documents': archives.map(_archiveEnJson).toList(),
        // ⚠️ F0.80 — retirer = {id, is_active:false} seulement.
        'administrative_documents': documents.map(_documentEnJson).toList(),
        // ⚠️ Le serveur traite les avances AVANT les imputations (une imputation peut
        // viser l'avance du même envoi) : l'ordre des clés n'y change rien, mais
        // les deux voyagent ensemble dans le même paquet, jamais séparés.
        'customer_advances': avances.map(_avanceEnJson).toList(),
        'advance_imputations': imputations.map(_imputationEnJson).toList(),
      },
    );

    final corps = reponse.data ?? const <String, dynamic>{};
    var accepte = 0;
    var rejete = 0;
    final motifs = <String>[];

    accepte += await _acquitter(
      'livestock_daily_entries',
      corps['livestock_daily_entries'],
      (ids, statut) =>
          (_db.update(_db.livestockDailyEntries)..where((t) => t.id.isIn(ids)))
              .write(LivestockDailyEntriesCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'sales',
      corps['sales'],
      (ids, statut) => (_db.update(_db.sales)..where((t) => t.id.isIn(ids)))
          .write(SalesCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'livestock_reproduction_events',
      corps['livestock_reproduction_events'],
      (ids, statut) =>
          (_db.update(
            _db.livestockReproductionEvents,
          )..where((t) => t.id.isIn(ids))).write(
            LivestockReproductionEventsCompanion(syncStatus: Value(statut)),
          ),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'attendance_records',
      corps['attendance_records'],
      (ids, statut) =>
          (_db.update(_db.attendanceRecords)..where((t) => t.id.isIn(ids)))
              .write(AttendanceRecordsCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'purchases',
      corps['purchases'],
      (ids, statut) => (_db.update(_db.purchases)..where((t) => t.id.isIn(ids)))
          .write(PurchasesCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'stock_adjustments',
      corps['stock_adjustments'],
      (ids, statut) =>
          (_db.update(_db.stockAdjustments)..where((t) => t.id.isIn(ids)))
              .write(StockAdjustmentsCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'expenses',
      corps['expenses'],
      (ids, statut) => (_db.update(_db.expenses)..where((t) => t.id.isIn(ids)))
          .write(ExpensesCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'veterinary_records',
      corps['veterinary_records'],
      (ids, statut) =>
          (_db.update(_db.veterinaryRecords)..where((t) => t.id.isIn(ids)))
              .write(VeterinaryRecordsCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    // ⚠️ SEUL RÉFÉRENTIEL OÙ LE POSTE ÉCRIT (F0.67) : le serveur valide et engendre
    // le SKU définitif, qui revient au tirage suivant.
    accepte += await _acquitter(
      'products',
      corps['products'],
      (ids, statut) => (_db.update(_db.products)..where((t) => t.id.isIn(ids)))
          .write(ProductsCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'suppliers',
      corps['suppliers'],
      (ids, statut) => (_db.update(_db.suppliers)..where((t) => t.id.isIn(ids)))
          .write(SuppliersCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'customers',
      corps['customers'],
      (ids, statut) => (_db.update(_db.customers)..where((t) => t.id.isIn(ids)))
          .write(CustomersCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    // ⚠️ Un courrier accepté n'a pas encore sa référence : elle descend au tirage de
    // confirmation (voir [synchroniser]).
    final courriersAcceptes = await _acquitter(
      'mails',
      corps['mails'],
      (ids, statut) => _marquerCourriers(courriers, ids, statut),
      motifs,
      (n) => rejete += n,
    );
    accepte += courriersAcceptes;
    _courriersAcquittes = courriersAcceptes;

    final archivesAcceptees = await _acquitter(
      'archived_documents',
      corps['archived_documents'],
      (ids, statut) => _marquerArchives(archives, ids, statut),
      motifs,
      (n) => rejete += n,
    );
    accepte += archivesAcceptees;
    _archivesAcquittees = archivesAcceptees;

    final documentsAcceptes = await _acquitter(
      'administrative_documents',
      corps['administrative_documents'],
      (ids, statut) => _marquerDocuments(documents, ids, statut),
      motifs,
      (n) => rejete += n,
    );
    accepte += documentsAcceptes;
    _documentsAcquittes = documentsAcceptes;

    accepte += await _acquitter(
      'supplier_payments',
      corps['supplier_payments'],
      (ids, statut) =>
          (_db.update(_db.supplierPayments)..where((t) => t.id.isIn(ids)))
              .write(SupplierPaymentsCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    final avancesAcceptees = await _acquitter(
      'customer_advances',
      corps['customer_advances'],
      (ids, statut) =>
          (_db.update(_db.customerAdvances)..where((t) => t.id.isIn(ids)))
              .write(CustomerAdvancesCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    final imputationsAcceptees = await _acquitter(
      'advance_imputations',
      corps['advance_imputations'],
      (ids, statut) =>
          (_db.update(_db.advanceImputations)..where((t) => t.id.isIn(ids)))
              .write(AdvanceImputationsCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    // ⚠️ Retours et remboursements : le serveur ne renvoie un `id` en `accepted` qu'une fois
    // le stock, la dette, la trésorerie et l'écriture passés dans UNE transaction.
    final retoursAcceptes = await _acquitter(
      'purchase_returns',
      corps['purchase_returns'],
      (ids, statut) =>
          (_db.update(_db.purchaseReturns)..where((t) => t.id.isIn(ids))).write(
            PurchaseReturnsCompanion(syncStatus: Value(statut)),
          ),
      motifs,
      (n) => rejete += n,
    );

    final remboursementsAcceptes = await _acquitter(
      'supplier_refunds',
      corps['supplier_refunds'],
      (ids, statut) =>
          (_db.update(_db.supplierRefunds)..where((t) => t.id.isIn(ids))).write(
            SupplierRefundsCompanion(syncStatus: Value(statut)),
          ),
      motifs,
      (n) => rejete += n,
    );

    accepte +=
        avancesAcceptees +
        imputationsAcceptees +
        retoursAcceptes +
        remboursementsAcceptes;
    _financiersAcquittes =
        avancesAcceptees +
        imputationsAcceptees +
        retoursAcceptes +
        remboursementsAcceptes;

    await _db.noterEtatDeSynchronisation(envoye: DateTime.now());

    return (accepte, rejete, motifs);
  }

  /// Acquitte ou refuse des courriers ([envoyes] = ce qui est PARTI, tel quel).
  ///
  /// ⚠️⚠️ **LE STATUT NE CHANGE QUE SI LA LIGNE EST ENCORE CELLE QUI EST PARTIE** (F0.78-bis).
  /// Le poste reste utilisable pendant l'envoi : un courrier corrigé entre-temps serait sinon
  /// marqué `synced` sur l'accusé de son ANCIENNE version, et la correction ne partirait
  /// jamais. Si la ligne a changé, elle reste `pending` (elle repart au prochain envoi).
  ///
  /// ⚠️ Un courrier ACCEPTÉ est en revanche toujours « connu du serveur », quelle que soit
  /// la version : c'est ce qui autorisera plus tard son archivage.
  Future<void> _marquerCourriers(
    List<Mail> envoyes,
    List<String> ids,
    SyncStatus statut,
  ) async {
    if (statut == SyncStatus.synced) {
      await (_db.update(_db.mails)..where((t) => t.id.isIn(ids))).write(
        const MailsCompanion(knownByServer: Value(true)),
      );
    }

    for (final m in envoyes.where((m) => ids.contains(m.id))) {
      await (_db.update(_db.mails)..where(
            (t) => Expression.and([
              t.id.equals(m.id),
              t.type.equals(m.type),
              t.subject.equals(m.subject),
              m.party == null ? t.party.isNull() : t.party.equals(m.party!),
              m.mailDate == null
                  ? t.mailDate.isNull()
                  : t.mailDate.equals(m.mailDate!),
              t.isActive.equals(m.isActive),
              t.syncStatus.equalsValue(SyncStatus.pending),
            ]),
          ))
          .write(MailsCompanion(syncStatus: Value(statut)));
    }
  }

  /// Acquitte ou refuse des documents archivés ([envoyes] = ce qui est PARTI, tel quel).
  ///
  /// ⚠️⚠️ **LE STATUT NE CHANGE QUE SI LA LIGNE EST ENCORE CELLE QUI EST PARTIE** (même règle
  /// que [_marquerCourriers]) : un document corrigé ou retiré pendant l'envoi reste `pending`
  /// et repart. Un document ACCEPTÉ est en revanche toujours « connu du serveur ».
  Future<void> _marquerArchives(
    List<ArchivedDocument> envoyes,
    List<String> ids,
    SyncStatus statut,
  ) async {
    if (statut == SyncStatus.synced) {
      await (_db.update(_db.archivedDocuments)..where((t) => t.id.isIn(ids)))
          .write(const ArchivedDocumentsCompanion(knownByServer: Value(true)));
    }

    for (final a in envoyes.where((a) => ids.contains(a.id))) {
      await (_db.update(_db.archivedDocuments)..where(
            (t) => Expression.and([
              t.id.equals(a.id),
              t.title.equals(a.title),
              a.category == null
                  ? t.category.isNull()
                  : t.category.equals(a.category!),
              a.archivedDate == null
                  ? t.archivedDate.isNull()
                  : t.archivedDate.equals(a.archivedDate!),
              a.expiryDate == null
                  ? t.expiryDate.isNull()
                  : t.expiryDate.equals(a.expiryDate!),
              t.isActive.equals(a.isActive),
              t.syncStatus.equalsValue(SyncStatus.pending),
            ]),
          ))
          .write(ArchivedDocumentsCompanion(syncStatus: Value(statut)));
    }
  }

  /// Acquitte ou refuse des documents administratifs ([envoyes] = ce qui est PARTI, tel quel).
  ///
  /// ⚠️⚠️ **LE STATUT NE CHANGE QUE SI LA LIGNE EST ENCORE CELLE QUI EST PARTIE** (même règle
  /// que [_marquerCourriers] et [_marquerArchives]) : un document corrigé ou retiré pendant
  /// l'envoi reste `pending` et repart. Un document ACCEPTÉ est en revanche toujours « connu
  /// du serveur ».
  Future<void> _marquerDocuments(
    List<AdministrativeDocument> envoyes,
    List<String> ids,
    SyncStatus statut,
  ) async {
    if (statut == SyncStatus.synced) {
      await (_db.update(
        _db.administrativeDocuments,
      )..where((t) => t.id.isIn(ids))).write(
        const AdministrativeDocumentsCompanion(knownByServer: Value(true)),
      );
    }

    for (final d in envoyes.where((d) => ids.contains(d.id))) {
      await (_db.update(_db.administrativeDocuments)..where(
            (t) => Expression.and([
              t.id.equals(d.id),
              t.title.equals(d.title),
              d.type == null ? t.type.isNull() : t.type.equals(d.type!),
              d.beneficiary == null
                  ? t.beneficiary.isNull()
                  : t.beneficiary.equals(d.beneficiary!),
              d.docDate == null
                  ? t.docDate.isNull()
                  : t.docDate.equals(d.docDate!),
              d.status == null ? t.status.isNull() : t.status.equals(d.status!),
              t.isActive.equals(d.isActive),
              t.syncStatus.equalsValue(SyncStatus.pending),
            ]),
          ))
          .write(AdministrativeDocumentsCompanion(syncStatus: Value(statut)));
    }
  }

  /// Marque `synced` les identifiants acceptés, `conflict` les refusés.
  ///
  /// ⚠️ **UN REFUS N'EST NI PERDU NI RÉPUTÉ ENVOYÉ.** L'enregistrement reste
  /// sur le poste et continue de compter comme « en attente » — mais il passe
  /// en `conflict` et sort des envois automatiques.
  ///
  /// ⚠️ **POURQUOI LE SORTIR DES ENVOIS.** Laissé `pending`, il repartait à
  /// chaque synchronisation et se faisait refuser à chaque fois : une boucle
  /// silencieuse, coûteuse en réseau, que personne ne pouvait diagnostiquer
  /// puisque le motif disparaissait avec le bandeau. Il faut une correction —
  /// souvent côté serveur — puis une relance explicite.
  Future<int> _acquitter(
    String table,
    Object? resultat,
    Future<void> Function(List<String> ids, SyncStatus statut) marquer,
    List<String> motifs,
    void Function(int) compterRejets,
  ) async {
    if (resultat is! Map) return 0;

    final acceptes =
        (resultat['accepted'] as List?)?.cast<String>() ?? const [];
    if (acceptes.isNotEmpty) {
      await marquer(acceptes, SyncStatus.synced);

      // ⚠️ F0.79-bis — UN REFUS PÉRIMÉ NE SURVIT PAS À L'ACCEPTATION. Seuls les refus de ces
      // identifiants-là, dans CETTE table, sont purgés (clé `table:id`) : un refus d'un autre
      // enregistrement ne bouge pas. Une ligne n'est envoyée qu'en `pending` ; un refus encore
      // ouvert à ce moment-là est donc celui d'une version antérieure, déjà dépassée. Les rejets
      // du même envoi sont traités PLUS BAS : leur refus tout neuf n'est pas touché.
      await (_db.delete(
            _db.syncConflicts,
          )..where((c) => c.id.isIn([for (final id in acceptes) '$table:$id'])))
          .go();
    }

    final rejets = (resultat['rejected'] as List?) ?? const [];
    compterRejets(rejets.length);

    final refuses = <String>[];

    for (final r in rejets) {
      if (r is! Map) continue;

      final motif = r['reason']?.toString() ?? 'Refus sans motif communiqué.';
      motifs.add(motif);

      final id = r['id']?.toString();
      if (id == null) continue;

      refuses.add(id);

      // Le motif est conservé MOT POUR MOT : c'est le serveur qui sait
      // pourquoi il refuse, et le reformuler ferait perdre l'information dont
      // le responsable a besoin pour corriger.
      await _db
          .into(_db.syncConflicts)
          .insertOnConflictUpdate(
            SyncConflictsCompanion.insert(
              id: '$table:$id',
              sourceTable: table,
              recordId: id,
              reason: motif,
              detectedAt: DateTime.now(),
            ),
          );
    }

    if (refuses.isNotEmpty) {
      await marquer(refuses, SyncStatus.conflict);
    }

    return acceptes.length;
  }

  /// Remet en file un enregistrement refusé, une fois sa cause corrigée.
  ///
  /// ⚠️ RELANCE EXPLICITE, jamais automatique : sans correction, le serveur
  /// refuserait de nouveau et la boucle reprendrait.
  Future<void> relancer(SyncConflict conflit) async {
    final compagnon = switch (conflit.sourceTable) {
      'livestock_daily_entries' =>
        () =>
            (_db.update(
              _db.livestockDailyEntries,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const LivestockDailyEntriesCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'sales' => () => _relancerVente(conflit.recordId),
      'veterinary_records' =>
        () =>
            (_db.update(
              _db.veterinaryRecords,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const VeterinaryRecordsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'stock_adjustments' =>
        () =>
            (_db.update(
              _db.stockAdjustments,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const StockAdjustmentsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'suppliers' =>
        () =>
            (_db.update(
              _db.suppliers,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const SuppliersCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      'customers' =>
        () =>
            (_db.update(
              _db.customers,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const CustomersCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      'mails' =>
        () =>
            (_db.update(
              _db.mails,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const MailsCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      'archived_documents' =>
        () =>
            (_db.update(
              _db.archivedDocuments,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const ArchivedDocumentsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'administrative_documents' =>
        () =>
            (_db.update(
              _db.administrativeDocuments,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const AdministrativeDocumentsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'customer_advances' =>
        () =>
            (_db.update(
              _db.customerAdvances,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const CustomerAdvancesCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'advance_imputations' =>
        () =>
            (_db.update(
              _db.advanceImputations,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const AdvanceImputationsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'supplier_payments' =>
        () =>
            (_db.update(
              _db.supplierPayments,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const SupplierPaymentsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      // ⚠️ F0.77 : sans cette entrée, « Relancer » d'un achat refusé (compte absent du
      // plan, total nul) ne faisait RIEN — le bouton s'affichait, l'achat restait en
      // `conflict` pour toujours.
      'purchases' =>
        () =>
            (_db.update(
              _db.purchases,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const PurchasesCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      'purchase_returns' =>
        () =>
            (_db.update(
              _db.purchaseReturns,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const PurchaseReturnsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'supplier_refunds' =>
        () =>
            (_db.update(
              _db.supplierRefunds,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const SupplierRefundsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'products' =>
        () =>
            (_db.update(
              _db.products,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const ProductsCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      'livestock_reproduction_events' =>
        () =>
            (_db.update(
              _db.livestockReproductionEvents,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const LivestockReproductionEventsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      _ => null,
    };

    if (compagnon == null) return;

    await compagnon();
    await (_db.delete(
      _db.syncConflicts,
    )..where((t) => t.id.equals(conflit.id))).go();
  }

  /// Relance d'une vente refusée : la vente SEULE repart en file.
  ///
  /// 🔴→✅ TICKET F0.90 (défaut D2 de l'audit) — LA FICHE NE REPART PLUS EN ENTIER. F0.89 remettait
  /// en file la fiche `synced` du jour de la vente pour éviter le double comptage (2N), mais
  /// renvoyait ainsi la fiche TELLE QUE LE POSTE LA DÉTIENT : le serveur applique « dernier
  /// écrivain gagne » (`pushDailyEntries`, `fill` de toutes les colonnes reçues), et une correction
  /// faite entre-temps sur le web (2 morts au lieu d'1) était écrasée. Le double comptage est
  /// désormais évité par la FICHE D'IDENTITÉ que [_fichesDIdentite] joint à l'envoi.
  Future<void> _relancerVente(String venteId) async {
    await (_db.update(_db.sales)..where((t) => t.id.equals(venteId))).write(
      const SalesCompanion(syncStatus: Value(SyncStatus.pending)),
    );
  }

  /// 🔴→✅ TICKET F0.90 — FICHES D'IDENTITÉ : `{id, lot_id, entry_date}` et RIEN D'AUTRE.
  ///
  /// ⚠️⚠️ LE PROBLÈME. Le serveur (15.30) n'ajoute pas une vente à une fiche (bande, jour) ACCEPTÉE
  /// dans le MÊME envoi : il la sait déjà portée par la fiche du poste. Une vente REFUSÉE (mois
  /// clôturé…) laisse au serveur une fiche acceptée qui porte déjà ses N têtes ; relancer la vente
  /// seule ferait 2N. Renvoyer la fiche ENTIÈRE (F0.89) l'évitait, mais écrasait toute correction
  /// web de cette fiche.
  ///
  /// ✅ LA MESURE. Pour chaque vente en file, la fiche (bande, JOUR DE LA VENTE) que le poste tient
  /// pour `synced` part réduite à son identité. Lu dans `SyncController` (Laravel, 15.33) :
  ///  - `pushDailyEntries` retrouve la fiche par `id` et fait `fill(except id, effectif_final)` :
  ///    Eloquent n'écrit QUE les clés présentes — achat, nés, morts, vente, dons stockés au
  ///    serveur (donc la correction web) restent intacts ; `effectif_final` est recalculé à partir
  ///    d'eux, jamais repris du poste ;
  ///  - la fiche est ACCEPTÉE : `fichesAcceptees` l'inscrit, et `RecordSaleOnFicheElevageAction`
  ///    n'ajoute pas la vente une seconde fois (sa cascade, elle, tourne quand même).
  ///
  /// ⚠️ POURQUOI C'EST SÛR, ET JUSQU'OÙ. Une fiche `synced` au poste a été ACCEPTÉE par le serveur
  /// avec la vente déjà comptée (la caisse inscrit la vente dans la fiche et la remet en file dans
  /// la même transaction) : la valeur serveur porte donc la vente. Aucune page du serveur ne
  /// SUPPRIME une fiche (lu : seuls des `updateOrCreate` par (bande, jour), qui gardent l'`id`).
  /// Limite connue : si la fiche avait disparu du serveur (restauration, intervention en base),
  /// la fiche d'identité y créerait une fiche vide qui exempterait la vente (0 au lieu de N) —
  /// d'où le ticket serveur proposé (F0.90) : refuser une fiche d'identité inconnue.
  ///
  /// Une fiche `pending` part déjà ENTIÈRE (c'est une modification du poste) ; une fiche en
  /// `conflict` attend sa propre relance (le serveur ajoute alors la vente à SA fiche, ce qui est
  /// juste). Une vente sans bande n'appelle aucune fiche.
  Future<List<LivestockDailyEntry>> _fichesDIdentite(
    List<Sale> ventes,
    Map<String, List<SaleLine>> lignesDeVente,
  ) async {
    final retenues = <String, LivestockDailyEntry>{};

    for (final v in ventes) {
      final jour = DateTime(v.soldAt.year, v.soldAt.month, v.soldAt.day);
      final lots = {
        for (final l in lignesDeVente[v.id] ?? const <SaleLine>[])
          if (l.lotId != null) l.lotId!,
      };

      for (final lot in lots) {
        final fiche =
            await (_db.select(_db.livestockDailyEntries)..where(
                  (t) => Expression.and([
                    t.lotId.equals(lot),
                    t.entryDate.equals(jour),
                    t.syncStatus.equalsValue(SyncStatus.synced),
                  ]),
                ))
                .getSingleOrNull();
        if (fiche != null) retenues[fiche.id] = fiche;
      }
    }

    return retenues.values.toList();
  }

  /// Refus encore ouverts, le plus récent d'abord.
  Future<List<SyncConflict>> conflits() {
    return (_db.select(_db.syncConflicts)..orderBy([
          (t) =>
              OrderingTerm(expression: t.detectedAt, mode: OrderingMode.desc),
        ]))
        .get();
  }

  /// Fiche fournisseur créée, modifiée ou archivée au poste.
  ///
  /// ⚠️ **L'E-MAIL NE PART PAS** : le formulaire n'a pas ce champ, et un poste qui ne
  /// l'envoie pas ne doit pas effacer celui du serveur.
  Map<String, dynamic> _fournisseurEnJson(Supplier f) => {
    'id': f.id,
    'name': f.name,
    'category': f.category,
    'phone': f.phone,
    'address': f.address,
    'is_active': f.isActive,
  };

  /// Fiche client créée, modifiée ou archivée au poste.
  ///
  /// ⚠️ **LE PLAFOND DE CRÉDIT NE PART PAS** : le poste ne le saisit pas, et ne doit pas
  /// pouvoir le relever.
  Map<String, dynamic> _clientEnJson(Customer c) => {
    'id': c.id,
    'name': c.name,
    'phone': c.phone,
    'email': c.email,
    'city': c.city,
    'is_active': c.isActive,
  };

  /// Courrier saisi, modifié ou archivé au poste.
  ///
  /// ⚠️ **ARCHIVER = `{id, is_active: false}` SEULEMENT** (contrat 15.23) : les autres
  /// champs ne sont pas lus. ⚠️ **LA RÉFÉRENCE NE PART JAMAIS** : le serveur l'attribue.
  Map<String, dynamic> _courrierEnJson(Mail m) => m.isActive
      ? {
          'id': m.id,
          'type': m.type,
          'subject': m.subject,
          'party': m.party,
          'mail_date': m.mailDate == null ? null : _jour(m.mailDate!),
          'is_active': true,
        }
      : {'id': m.id, 'is_active': false};

  /// Document archivé saisi, modifié ou retiré au poste.
  ///
  /// ⚠️ **RETIRER = `{id, is_active: false}` SEULEMENT** (contrat 15.24) : les autres champs
  /// ne sont pas lus. ⚠️ **AUCUN STATUT NE PART** : il se déduit de l'échéance, des deux côtés.
  Map<String, dynamic> _archiveEnJson(ArchivedDocument a) => a.isActive
      ? {
          'id': a.id,
          'title': a.title,
          'category': a.category,
          'archived_date': a.archivedDate == null
              ? null
              : _jour(a.archivedDate!),
          'expiry_date': a.expiryDate == null ? null : _jour(a.expiryDate!),
          'is_active': true,
        }
      : {'id': a.id, 'is_active': false};

  /// Document administratif saisi, modifié ou retiré au poste.
  ///
  /// ⚠️ **RETIRER = `{id, is_active: false}` SEULEMENT** (contrat 15.25) : les autres champs
  /// ne sont pas lus. Le statut part tel quel (`signe` | `en_attente`) ; absent, le serveur
  /// conserverait l'existant — le poste ne l'omet donc que si la colonne est vide.
  Map<String, dynamic> _documentEnJson(AdministrativeDocument d) => d.isActive
      ? {
          'id': d.id,
          'title': d.title,
          'type': d.type,
          'beneficiary': d.beneficiary,
          'doc_date': d.docDate == null ? null : _jour(d.docDate!),
          if (d.status != null) 'status': d.status,
          'is_active': true,
        }
      : {'id': d.id, 'is_active': false};

  /// Avance reçue au poste : « tant, de ce client, dans ce compte, ce jour ». Ni solde de
  /// trésorerie ni écriture ne partent — le serveur entre l'argent dans les DEUX livres
  /// et passe D 5xx / C 419. `amount_used` ne part jamais. `device_id` voyage à la racine.
  Map<String, dynamic> _avanceEnJson(CustomerAdvance a) => {
    'id': a.id,
    'customer_id': a.customerId,
    'treasury_account_id': a.treasuryAccountId,
    'amount': a.amount,
    'advance_date': a.advanceDate == null ? null : _jour(a.advanceDate!),
    'payment_mode': a.paymentMode,
    'motif': a.motif,
  };

  /// Imputation : « tant de cette avance sur cette créance ». Ni plafond, ni reste, ni
  /// `amount_paid` : le serveur les recalcule. La créance se désigne par `receivable_id`
  /// OU `sale_id` — la clé absente n'est pas envoyée.
  Map<String, dynamic> _imputationEnJson(ImputationAvance i) => {
    'id': i.id,
    'customer_advance_id': i.customerAdvanceId,
    if (i.receivableId != null) 'receivable_id': i.receivableId,
    if (i.saleId != null) 'sale_id': i.saleId,
    'amount': i.amount,
    'imputation_date': _jour(i.imputationDate),
  };

  /// Règlement fournisseur : ni imputation ni solde ne partent, seulement le fait.
  Map<String, dynamic> _reglementEnJson(ReglementFournisseur r) => {
    'id': r.id,
    'supplier_id': r.supplierId,
    'treasury_account_id': r.treasuryAccountId,
    'amount': r.amount,
    'payment_date': _jour(r.paymentDate),
  };

  /// Retour fournisseur demandé au poste : « cet achat est retourné, pour ce motif, tel
  /// jour ». Ni ligne, ni quantité, ni stock, ni dette : l'annulation est COMPLÈTE et le
  /// serveur choisit les lignes. `device_id` voyage à la racine.
  Map<String, dynamic> _retourEnJson(RetourFournisseur r) => {
    'id': r.id,
    'purchase_id': r.purchaseId,
    'reason': r.reason,
    'return_date': _jour(r.returnDate),
  };

  /// Remboursement reçu d'un fournisseur : « tant, de celui-ci, sur ce compte ». Le plafond
  /// et les deux livres de trésorerie sont l'affaire du serveur.
  Map<String, dynamic> _remboursementEnJson(RemboursementFournisseur r) => {
    'id': r.id,
    'supplier_id': r.supplierId,
    'treasury_account_id': r.treasuryAccountId,
    'amount': r.amount,
    'refund_date': _jour(r.refundDate),
  };

  /// Produit créé ou modifié au poste.
  ///
  /// ⚠️ **LA QUANTITÉ PART TELLE QUELLE ET LE SERVEUR NE L'UTILISE QU'À LA CRÉATION** :
  /// en modification il l'ignore (un stock se corrige par un ajustement). Le SKU
  /// envoyé est provisoire — le serveur engendre le définitif.
  Map<String, dynamic> _produitEnJson(Product p) => {
    'id': p.id,
    'sku': p.sku,
    'name': p.name,
    'description': p.description,
    'category_id': p.categoryId,
    'species_id': p.speciesId,
    'unit': p.unit,
    'pricing_mode': p.pricingMode,
    'price_min': p.priceMin,
    'price_max': p.priceMax,
    'tva_rate': p.tvaRate,
    'stock_qty': p.stockQty,
    'alert_threshold': p.alertThreshold ?? 0,
    'updated_at': p.updatedAt?.toUtc().toIso8601String(),
  };

  /// Fiche modifiée au poste : le FAIT saisi, jamais un dérivé.
  ///
  /// 🔴→✅ TICKET F0.95 (contrat 15.40) :
  ///  - ⚠️⚠️ `effectif_final` et `cat_eff_*` NE PARTENT JAMAIS : ce sont des valeurs DÉRIVÉES que
  ///    le serveur recalcule (il ignore `effectif_final` et neutralise les `cat_eff_*` d'une
  ///    bande à chaîne ; SANS chaîne il les ÉCRIRAIT, et la copie locale, peut-être périmée,
  ///    écraserait une saisie web). `cat_eff_4` non plus ;
  ///  - les mouvements par catégorie (`mort_*`, `don_*`) et le passage partent quand ils sont
  ///    CONNUS ; une valeur inconnue (null) n'est pas envoyée (le serveur traite null comme une
  ///    clé absente : elle n'efface rien) ;
  ///  - `mort` = somme des `mort_*` et `don` = somme des `don_*` quand la ventilation est complète
  ///    (le serveur refuse sinon « ventilation incohérente ») ;
  ///  - `cat_depart_*` seulement sur la fiche TÊTE de chaîne ([tete]) ;
  ///  - `effectif_m/f/sevres/smeres` (SAISIS, QC5) seulement s'ils sont connus.
  Map<String, dynamic> _ficheEnJson(
    LivestockDailyEntry f, {
    required bool tete,
  }) {
    int? somme(int? a, int? b, int? c) =>
        (a == null || b == null || c == null) ? null : a + b + c;
    final connus = <String, int?>{
      'mort_repro': f.mortRepro,
      'mort_sevre': f.mortSevre,
      'mort_jeune': f.mortJeune,
      'don_repro': f.donRepro,
      'don_sevre': f.donSevre,
      'don_jeune': f.donJeune,
      'passage_sevre_jeune': f.passageSevreJeune,
      if (tete) ...{
        'cat_depart_repro': f.catDepartRepro,
        'cat_depart_sevre': f.catDepartSevre,
        'cat_depart_jeune': f.catDepartJeune,
      },
      'effectif_m': f.effectifM,
      'effectif_f': f.effectifF,
      'effectif_sevres': f.effectifSevres,
      'effectif_smeres': f.effectifSmeres,
    };
    return {
      'id': f.id,
      'lot_id': f.lotId,
      'entry_date': _jour(f.entryDate),
      'achat': f.achat,
      'ne': f.ne,
      'mort': somme(f.mortRepro, f.mortSevre, f.mortJeune) ?? f.mort,
      'vente': f.vente,
      'don': somme(f.donRepro, f.donSevre, f.donJeune) ?? f.don,
      'ponte_total': f.ponteTotal,
      'ponte_casses': f.ponteCasses,
      'feed_qty_kg': f.feedQtyKg,
      'weight_sample_avg_g': f.weightSampleAvgG,
      for (final MapEntry(:key, :value) in connus.entries)
        key: ?value,
      'device_id': f.deviceId,
      'updated_at': f.updatedAt.toUtc().toIso8601String(),
    };
  }

  /// F0.90 — fiche réduite à son IDENTITÉ (voir [_fichesDIdentite]). `lot_id` et `entry_date`
  /// sont exigés par le validateur du serveur ; AUCUNE autre clé : chacune écraserait la valeur
  /// serveur (`fill`), et c'est précisément ce qu'on évite.
  Map<String, dynamic> _ficheIdentiteEnJson(LivestockDailyEntry f) => {
    'id': f.id,
    'lot_id': f.lotId,
    'entry_date': _jour(f.entryDate),
  };

  /// ⚠️⚠️ LE POSTE ENVOIE UNE INTENTION, PAS UN RESULTAT. Ni le stock, ni la
  /// caisse, ni la dette, ni l'ecriture ne sont calcules ici : le serveur les
  /// rejoue tous les cinq a la reception (`RecordPurchaseAction`). Recalculer
  /// un PMP localement ferait diverger deux valorisations de stock.
  ///
  /// ⚠️ `purchase_date` VIENT DU POSTE : une livraison recue mardi et
  /// synchronisee jeudi appartient a mardi — meme regle que `sold_at` pour les
  /// ventes (ticket 14.71).
  Map<String, dynamic> _achatEnJson(Purchase a, List<PurchaseLine> lignes) => {
    'id': a.id,
    'supplier_id': a.supplierId,
    'payment_mode': a.paymentMode,
    'treasury_account_id': a.treasuryAccountId,
    'amount_paid': a.amountPaid,
    'purchase_date': _jour(a.purchaseDate),
    'lines': [
      for (final l in lignes)
        {'product_id': l.productId, 'qty': l.qty, 'unit_price': l.unitPrice},
    ],
  };

  /// ⚠️ LE JOUR PART EN 'Y-m-d', jamais en instant : le serveur cherche le
  /// pointage par le couple (employe, JOUR), et un decalage horaire le ferait
  /// porter sur la veille.
  Map<String, dynamic> _pointageEnJson(AttendanceRecord p) => {
    'id': p.id,
    'employee_id': p.employeeId,
    'attendance_date': _jour(p.attendanceDate),
    'check_in': p.checkIn,
    'check_out': p.checkOut,
    'status': p.status,
  };

  Map<String, dynamic> _venteEnJson(Sale v, List<SaleLine> lignes) => {
    'id': v.id,
    'customer_id': v.customerId,
    'payment_mode': v.paymentMode,
    'subtotal': v.subtotal,
    'discount': v.discount,
    'total': v.total,
    'cash_received': v.cashReceived,
    'change_due': v.changeDue,
    'status': v.status,
    // 🔴→✅ TICKET 14.71 / F0.31 — L'HEURE REELLE DU COMPTOIR.
    //
    // ⚠️⚠️ ELLE N'ETAIT PAS ENVOYEE, et le serveur n'avait meme pas de
    // colonne ou la mettre : il datait la vente de sa RECEPTION. Une vente
    // encaissee hors ligne le 28/07 et remontee le 02/08 passait donc son
    // ecriture SYSCOHADA en aout et sortait les tetes de la fiche du 02/08.
    // C'est le defaut le plus couteux qu'un poste hors ligne puisse avoir :
    // il ne se voit que sur les postes qui restent longtemps deconnectes,
    // c'est-a-dire exactement ceux pour lesquels le mode hors ligne existe.
    //
    // ⚠️ ENVOYEE EN HEURE LOCALE, SANS CONVERSION UTC, comme
    // `expense_date` : le serveur tourne desormais en Africa/Porto-Novo
    // (meme ticket). Convertir en UTC decalerait d'une heure et ferait
    // basculer de jour toute vente d'avant 01h00 — le defaut que ce
    // ticket corrige, reintroduit par l'autre bout.
    'sold_at': _instant(v.soldAt),
    'device_id': v.deviceId,
    'updated_at': v.updatedAt.toUtc().toIso8601String(),
    'lines': lignes
        .map(
          (l) => {
            'product_id': l.productId,
            'lot_id': l.lotId,
            'qty': l.qty,
            'unit_price': l.unitPrice,
            'manual_total_amount': l.manualTotalAmount,
          },
        )
        .toList(),
  };

  /// Saillie declaree au poste.
  ///
  /// ⚠️ **SEULS LES CINQ CHAMPS DE LA DECLARATION PARTENT.** Statut, dates
  /// d'echeance et resultats de mise bas sont calcules ou saisis cote serveur :
  /// les envoyer laisserait croire que le poste peut les corriger, alors que
  /// ce canal n'ouvre que la CREATION.
  Map<String, dynamic> _saillieEnJson(LivestockReproductionEvent e) => {
    'id': e.id,
    'lot_id': e.lotId,
    'mother_ref': e.motherRef,
    'sire_ref': e.sireRef,
    'saillie_date': e.saillieDate == null ? null : _jour(e.saillieDate!),
    'device_id': e.deviceId,
  };

  /// ⚠️ LA CATEGORIE PART TELLE QUELLE : le serveur la valide contre sa propre
  /// liste (`Expense::CATEGORIES`) et refuse tout compte inconnu. C'est ce qui
  /// empeche un poste desynchronise d'imputer une charge sur un compte retire.
  Map<String, dynamic> _depenseEnJson(Expense d) => {
    'id': d.id,
    'expense_date': _jour(d.expenseDate),
    'label': d.label,
    'category': d.category,
    'amount': d.amount,
    'treasury_account_id': d.treasuryAccountId,
    'device_id': d.deviceId,
  };

  Map<String, dynamic> _soinEnJson(VeterinaryRecord s) => {
    'id': s.id,
    'lot_id': s.lotId,
    'action_type': s.actionType,
    'product_used': s.productUsed,
    'dose': s.dose,
    'vet_name': s.vetName,
    'symptomes': s.symptomes,
    'cost': s.cost,
    'record_date': _jour(s.recordDate),
    // ⚠️ Le délai part avec le soin : c'est lui qui déclenche la création
    // de la période de rémanence côté serveur. L'omettre laisserait la
    // bande vendable malgré le traitement.
    'withdrawal_days': s.withdrawalDays,
    'device_id': s.deviceId,
    'updated_at': s.updatedAt.toUtc().toIso8601String(),
  };

  /// ⚠️⚠️ **`client_ref` EST LA CLÉ DE L'ACCUSÉ DE RÉCEPTION** (ticket
  /// 14.74). Sans elle, le serveur acquittait avec le `product_id` : le poste
  /// ne se reconnaissait pas dans la réponse, laissait l'ajustement en attente
  /// et le RENVOYAIT à chaque tirage — chaque renvoi rejouant le décrément de
  /// stock et une nouvelle écriture de perte.
  Map<String, dynamic> _ajustementEnJson(StockAdjustment a) => {
    'id': a.id,
    'client_ref': a.id,
    'product_id': a.productId,
    'type': a.type,
    'quantity': a.quantity,
    'reference_type': a.referenceType,
    'reason': a.reason,
    'device_id': a.deviceId,
    'updated_at': a.updatedAt.toUtc().toIso8601String(),
  };

  static List<Map<String, dynamic>> _lignes(Object? brut) =>
      (brut as List?)?.cast<Map<String, dynamic>>() ?? const [];

  static bool _bool(Object? v) => v == true || v == 1 || v == '1';

  static double? _reel(Object? v) =>
      v == null ? null : double.tryParse(v.toString());

  static int? _entier(Object? v) =>
      v == null ? null : int.tryParse(v.toString().split('.').first);

  /// ⚠️⚠️ **RAMENÉE À L'HEURE LOCALE, TOUJOURS.** Une colonne DATE pure
  /// (`entry_date`, `record_date`) arrive en `2026-08-17` et se lit déjà en
  /// local. Mais une date qu'Eloquent sérialise en instant — `due_date` d'une
  /// créance, servie `2026-04-01T23:00:00Z` depuis un serveur en
  /// Africa/Porto-Novo — se lirait **la veille** si on la gardait en UTC. Une
  /// échéance décalée d'un jour, c'est une relance envoyée trop tôt ou une
  /// facture crue encore à terme.
  ///
  /// `toLocal()` est sans effet sur une date déjà locale : la correction ne
  /// coûte rien là où elle ne sert pas.
  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  /// Format `Y-m-d` attendu par le serveur pour une DATE pure.
  ///
  /// ⚠️ Envoyer un ISO complet ferait comparer `2026-08-17T00:00:00` à une
  /// colonne DATE : la comparaison en chaîne échoue selon le pilote, et la
  /// fiche du jour serait dupliquée au lieu d'être mise à jour.
  /// Horodatage LOCAL `Y-m-d H:i:s`, sans fuseau — voir `_venteEnJson`.
  static String _instant(DateTime d) =>
      '${_jour(d)} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';

  static String _jour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
