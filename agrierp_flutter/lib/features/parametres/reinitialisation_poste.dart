import 'package:dio/dio.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/database/app_database.dart';
import '../../core/sync/sync_engine.dart';

/// Refus NOMMÉ de la réinitialisation : hors ligne, droit, verrou du serveur (mode démonstration, mot de
/// confirmation). Son message est déjà la phrase française à afficher (celle du serveur quand il en donne une).
class RefusReinitialisation implements Exception {
  const RefusReinitialisation(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Saisies de ce poste qui ne sont pas arrivées au serveur, pour une table que la réinitialisation efface.
class SaisiesNonEnvoyees {
  const SaisiesNonEnvoyees({required this.table, required this.enAttente, required this.refusees});

  final String table;

  /// `pending` : jamais envoyées (ou sans accusé du serveur).
  final int enAttente;

  /// `conflict` : refusées par le serveur, jamais arrivées.
  final int refusees;

  int get total => enAttente + refusees;

  String get libelle => ReinitialisationPoste.libellesTables[table] ?? table;
}

/// Compte rendu d'une réinitialisation réussie.
class ResultatReinitialisation {
  const ResultatReinitialisation({
    required this.message,
    required this.perdues,
    this.synchronisation,
    this.echecSynchronisation,
  });

  /// Message du serveur — celui du toast web (`ReinitialisationDonneesService::messageResultat()`).
  final String message;

  /// Saisies non envoyées effacées par la purge de ce poste.
  final int perdues;

  /// Tirage complet qui a suivi la purge ; `null` s'il a échoué ([echecSynchronisation]).
  final SyncOutcome? synchronisation;
  final Object? echecSynchronisation;
}

/// Ticket R-1 (demande du client : « sur le web et le poste ») — CE QUE L'ONGLET « RÉINITIALISATION » DU POSTE
/// LIT ET FAIT. Le pendant de `Livewire\Parametres\ReinitialisationDonnees`, par les routes
/// `/api/parametres/reinitialisation` qui appellent le MÊME service (même droit, mêmes verrous, même journal,
/// même marque `data_reset_at`).
///
/// ⚠️⚠️ **EN LIGNE SEULEMENT.** Réinitialiser, c'est vider la base du SERVEUR : hors ligne, rien n'est tenté.
///
/// ⚠️⚠️ **PURGE IMMÉDIATE APRÈS SUCCÈS, RIEN SUR UN ÉCHEC.** La purge locale suit le mécanisme de 15.50
/// ([SyncEngine.appliquerReinitialisation]) dès que le serveur a répondu, puis un tirage complet ; le poste
/// n'attend pas la synchronisation suivante pour cesser d'afficher des données effacées.
///
/// ⚠️ **LES SAISIES NON ENVOYÉES SONT PERDUES** (`pending` et `conflict` des tables effacées) : la
/// réinitialisation les rend caduques, et le serveur refuserait leur envoi (409). L'onglet les compte, table
/// par table, et exige une confirmation explicite ([saisiesNonEnvoyees]).
class ReinitialisationPoste {
  ReinitialisationPoste({
    required AppDatabase database,
    required Dio client,
    required SyncEngine engine,
    required String Function() role,
  }) : _db = database,
       // `prefer_initializing_formals` : Dart interdit `this._x` sur un paramètre NOMMÉ privé (voir `SyncEngine`).
       // ignore: prefer_initializing_formals
       _client = client,
       // ignore: prefer_initializing_formals
       _engine = engine,
       // ignore: prefer_initializing_formals
       _role = role;

  final AppDatabase _db;
  final Dio _client;
  final SyncEngine _engine;

  /// Rôle de la session ouverte : le droit est celui du web (`manage-parametres`, [PermissionsPoste.peut]).
  final String Function() _role;

  /// Mot à recopier — `ReinitialisationDonneesService::MOT_DE_CONFIRMATION` du web.
  static const motDeConfirmation = 'REINITIALISER';

  /// Message sous le champ quand le mot n'est pas recopié — `messageConfirmation()` du web.
  /// ⚠️ Écrit en toutes lettres (pas d'interpolation) : le garde-fou compare les littéraux au Blade.
  static const messageConfirmation = 'Saisissez REINITIALISER pour confirmer.';

  /// Refus 403 du serveur pour un autre rôle (`ReinitialisationDonneesController::REFUS_ROLE`).
  static const refusRole = 'Votre rôle ne permet pas de réinitialiser les données.';

  static const refusHorsLigne =
      'Hors ligne : la réinitialisation vide les données du serveur, que ce poste ne peut pas joindre. '
      'Reconnectez le poste au réseau pour y accéder.';

  static const _route = '/api/parametres/reinitialisation';

  /// Droit du web sur l'onglet : `manage-parametres` (`authorize()` du composant), administrateur seulement.
  bool get autorise => PermissionsPoste.peut(_role(), 'manage-parametres');

  Future<bool> estEnLigne() => _engine.estEnLigne();

  /// État de la bascule « Mode démonstration » sur le serveur.
  Future<bool> modeDemoActif() async {
    final reponse = await _appeler(() => _client.get<Map<String, dynamic>>(_route));
    return reponse['mode_demo_actif'] == true;
  }

  /// Bouton « Activé / Désactivé » du web : rend le nouvel état et le message du toast web.
  Future<({bool actif, String message, bool avertissement})> basculerModeDemo() async {
    await _exigerEnLigne();
    final reponse = await _appeler(() => _client.post<Map<String, dynamic>>('$_route/mode-demo'));
    return (
      actif: reponse['mode_demo_actif'] == true,
      message: '${reponse['message'] ?? ''}',
      avertissement: reponse['type'] == 'warning',
    );
  }

  /// Ticket R-1 — enregistrements de ce poste jamais arrivés au serveur (`pending`, `conflict`) dans les tables
  /// que la réinitialisation EFFACE ([AppDatabase.tablesDActivite]). Celles des référentiels conservés (un barème
  /// d'élevage, un produit) survivent à la purge et repartiront : les compter annoncerait une perte qui n'a pas
  /// lieu (règle H9b de [AppDatabase.purgerDonneesDActivite]).
  Future<List<SaisiesNonEnvoyees>> saisiesNonEnvoyees() async {
    final resultat = <SaisiesNonEnvoyees>[];
    for (final table in tablesPerdues) {
      final ligne = await _db
          .customSelect(
            "SELECT COALESCE(SUM(CASE WHEN sync_status = 'pending' THEN 1 ELSE 0 END), 0) AS en_attente, "
            "COALESCE(SUM(CASE WHEN sync_status = 'conflict' THEN 1 ELSE 0 END), 0) AS refusees "
            'FROM $table',
          )
          .getSingle();
      final enAttente = ligne.read<int>('en_attente');
      final refusees = ligne.read<int>('refusees');
      if (enAttente + refusees > 0) {
        resultat.add(SaisiesNonEnvoyees(table: table, enAttente: enAttente, refusees: refusees));
      }
    }
    return resultat;
  }

  /// Tables envoyées par le poste ET effacées par la réinitialisation, dans l'ordre de l'envoi.
  static List<String> get tablesPerdues =>
      AppDatabase.tablesEnvoyees.where(AppDatabase.tablesDActivite.contains).toList();

  /// Libellé de chaque table de [tablesPerdues] (un test exige qu'aucune n'en manque).
  static const libellesTables = <String, String>{
    'livestock_daily_entries': "Fiches journalières d'élevage",
    'sales': 'Ventes',
    'stock_adjustments': 'Ajustements de stock',
    'veterinary_records': 'Soins vétérinaires',
    'expenses': 'Dépenses',
    'quotes': 'Devis',
    'purchase_orders': 'Bons de commande',
    'livestock_reproduction_events': 'Saillies et mises bas',
    'purchases': 'Achats',
    'attendance_records': 'Pointages',
    // Tickets RH-1, RH-2, RH-4.
    'employees': 'Employés',
    'internships': 'Stagiaires',
    'internship_absences': 'Absences de stagiaires',
    'payslip_requests': 'Demandes de règlement de paie',
    'utilisateurs': 'Comptes utilisateurs',
    'receivable_payments': 'Encaissements de créances',
    'manual_entry_requests': "Demandes d'écriture manuelle",
    'depreciation_requests': 'Demandes de dotation aux amortissements',
    'customer_reminders': 'Relances de clients',
    'suppliers': 'Fournisseurs',
    'supplier_payments': 'Règlements fournisseurs',
    'customers': 'Clients',
    'mails': 'Courriers',
    'archived_documents': 'Documents archivés',
    'administrative_documents': 'Documents administratifs',
    'customer_advances': 'Avances clients',
    'advance_imputations': 'Imputations d\'avances',
    'purchase_returns': 'Retours fournisseurs',
    'supplier_refunds': 'Remboursements fournisseurs',
    'credit_notes': 'Retours et avoirs clients',
    'corbeille_demandes': 'Demandes de la corbeille',
    'livestock_transfers': 'Transferts entre bandes',
    'livestock_lots': 'Bandes',
    'animals': 'Reproducteurs (registre nominatif)',
    'infirmary_records': 'Infirmerie',
    'veterinary_calendar_events': 'Calendrier vétérinaire',
  };

  /// « Confirmer la réinitialisation » : le serveur réinitialise (verrous et service du web), puis ce poste
  /// purge AUSSITÔT ses données d'activité et tire tout. Lève [RefusReinitialisation] (hors ligne, droit, verrou)
  /// ou l'erreur réseau — et alors RIEN n'est purgé.
  Future<ResultatReinitialisation> reinitialiser(String confirmation) async {
    if (!autorise) throw const RefusReinitialisation(refusRole);
    // Même verrou que le web, vérifié avant tout appel : le serveur le revérifie de toute façon.
    if (confirmation != motDeConfirmation) throw const RefusReinitialisation(messageConfirmation);
    await _exigerEnLigne();

    var message = '';
    final perdues = await _engine.reinitialiserDepuisCePoste(() async {
      final reponse = await _appeler(
        () => _client.post<Map<String, dynamic>>(_route, data: {'confirmation': confirmation}),
      );
      final marque = reponse['data_reset_at'];
      if (marque is! String || marque.isEmpty) {
        // Serveur sans la marque (antérieur à 15.50) : sans elle, les envois suivants ne seraient pas reconnus.
        throw const RefusReinitialisation(
          "Réponse du serveur incomplète (marque de réinitialisation absente) : le serveur n'est peut-être pas "
          'à la même version que le poste.',
        );
      }
      message = '${reponse['message'] ?? ''}';
      return marque;
    });

    try {
      final synchronisation = await _engine.synchroniser();
      return ResultatReinitialisation(message: message, perdues: perdues, synchronisation: synchronisation);
    } catch (e) {
      return ResultatReinitialisation(message: message, perdues: perdues, echecSynchronisation: e);
    }
  }

  Future<void> _exigerEnLigne() async {
    if (!await estEnLigne()) throw const RefusReinitialisation(refusHorsLigne);
  }

  /// Un refus du serveur (403 droit, 409 mode démonstration, 422 confirmation) devient un [RefusReinitialisation]
  /// portant SON message, mot pour mot (parité des refus, doctrine 5.4). Le reste remonte tel quel
  /// (`messageErreur()` le dit en français).
  Future<Map<String, dynamic>> _appeler(Future<Response<Map<String, dynamic>>> Function() requete) async {
    try {
      return (await requete()).data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      final statut = e.response?.statusCode;
      final corps = e.response?.data;
      final message = corps is Map && corps['message'] is String ? corps['message'] as String : null;
      if (message != null && message.isNotEmpty && (statut == 403 || statut == 409 || statut == 422)) {
        throw RefusReinitialisation(message);
      }
      rethrow;
    }
  }
}
