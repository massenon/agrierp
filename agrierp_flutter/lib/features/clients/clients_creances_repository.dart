import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/export/document_officiel.dart';
import '../../core/temps/heure_benin.dart';

/// Une ligne de « Liste des Clients ».
class LigneClient {
  const LigneClient({
    required this.client,
    required this.totalAchats,
    required this.soldeDu,
  });

  final Customer client;

  /// ⚠️ **CE QUE CE POSTE A ENCAISSÉ POUR CE CLIENT**, pas le total de la
  /// ferme : le tirage ne descend pas `sales`. Un gérant qui compare deux
  /// postes doit le lire, pas le deviner.
  final double totalAchats;

  final double soldeDu;

  /// ⚠️ **MÊME DÉRIVATION QUE LE WEB** (`ListeClients::getCustomersWithBalanceProperty`) :
  /// « Créance en retard » dès qu'un solde reste dû, sinon « Actif ». Le web ne suit aucune
  /// « dernière activité » : il n'y a donc pas de statut « Inactif » (une fiche archivée
  /// quitte la liste) — la maquette en propose un, le poste ne l'invente pas.
  String get statut => soldeDu > 0 ? 'Créance en retard' : 'Actif';

  /// Écrite au poste, pas encore acquittée par le serveur.
  bool get enAttente => client.syncStatus != SyncStatus.synced;
}

/// Ce que l'utilisateur saisit dans « Nouveau Client » / « Modifier le Client ».
class FormulaireClient {
  const FormulaireClient({
    required this.nom,
    this.telephone = '',
    this.ville = '',
    this.email = '',
  });

  final String nom;
  final String telephone;
  final String ville;
  final String email;
}

/// Une ligne de « Suivi des Dettes Clients ».
class LigneCreance {
  const LigneCreance({
    required this.creance,
    required this.nomClient,
    this.imputeEnAttente = 0,
  });

  final Receivable creance;
  final String nomClient;

  /// Imputations d'acompte saisies sur CE poste, pas encore acquittées (ticket F0.73).
  final double imputeEnAttente;

  /// ⚠️⚠️ **LE RESTE DÛ SE CALCULE**, il n'est stocké nulle part : `amount −
  /// amount_paid`. Afficher `amount` comme encours compterait deux fois ce qui
  /// a déjà été réglé.
  ///
  /// ⚠️ **NET DES IMPUTATIONS EN ATTENTE** (F0.73) : le poste ne modifie jamais
  /// `amount_paid` (le serveur seul l'applique), mais afficher le solde brut après une
  /// imputation saisie inviterait à la saisir deux fois.
  double get resteDu {
    final net = creance.amount - creance.amountPaid - imputeEnAttente;
    return net < 0 ? 0 : net;
  }

  /// Jours écoulés depuis l'échéance — négatif si elle n'est pas atteinte.
  ///
  /// ⚠️ **DEPUIS L'ÉCHÉANCE, PAS DEPUIS L'ÉMISSION.** Une facture émise il y a
  /// 90 jours mais payable à 120 n'est pas en retard. C'est la règle que
  /// `AgedBalanceService` applique côté serveur ; la reprendre autrement
  /// donnerait deux balances âgées différentes pour la même créance.
  int? retard(DateTime jour) {
    final echeance = creance.dueDate;
    if (echeance == null) return null;
    return jour
        .difference(DateTime(echeance.year, echeance.month, echeance.day))
        .inDays;
  }

  bool echue(DateTime jour) => (retard(jour) ?? -1) > 0;
}

/// Une ligne de « Historique des Avances ».
class LigneAvance {
  const LigneAvance({
    required this.avance,
    required this.nomClient,
    this.imputeEnAttente = 0,
    this.motifRefus,
  });

  final CustomerAdvance avance;
  final String nomClient;

  /// Imputations de cette avance saisies sur CE poste, pas encore acquittées.
  final double imputeEnAttente;

  /// Motif du refus du serveur, conservé mot pour mot (avance en `conflict`).
  final String? motifRefus;

  /// ⚠️⚠️ **SOLDE NET DES IMPUTATIONS EN ATTENTE** (F0.73). `amount_used` ne bouge qu'au
  /// tirage : le poste ne le décrémente jamais, il ne fait que déduire à l'affichage ce
  /// qu'il a lui-même saisi et que le serveur n'a pas encore appliqué.
  double get soldeRestant {
    final net = avance.amount - avance.amountUsed - imputeEnAttente;
    return net < 0 ? 0 : net;
  }

  bool get soldee => soldeRestant <= 0;

  /// Saisie au poste, pas encore acquittée (l'argent n'est pas encore entré côté ferme).
  bool get enAttente => avance.syncStatus == SyncStatus.pending;

  /// Refusée par le serveur : elle n'existe pas côté ferme, elle attend une décision.
  bool get refusee => avance.syncStatus == SyncStatus.conflict;

  bool get imputationEnAttente => imputeEnAttente > 0;
}

/// Une relance déjà envoyée — ligne de « File de Relance Active ».
class LigneRelance {
  const LigneRelance({required this.relance, required this.nomClient});

  final CustomerReminder relance;
  final String nomClient;
}

class DonneesClients {
  const DonneesClients({
    required this.clients,
    required this.creances,
    required this.avances,
    required this.relances,
    required this.nouveauxDuMois,
    this.comptes = const [],
  });

  final List<LigneClient> clients;
  final List<LigneCreance> creances;
  final List<LigneAvance> avances;
  final List<LigneRelance> relances;

  /// Comptes de trésorerie servis par le serveur (choix de « Nouvel Acompte »).
  final List<TreasuryAccount> comptes;

  /// ⚠️ **TOUJOURS `null`** : `customers` descend sans sa date de création —
  /// le tirage ne sert que ce dont le poste a besoin pour vendre. Compter
  /// « 0 nouveau ce mois-ci » affirmerait qu'aucun client n'a été créé.
  final int? nouveauxDuMois;

  int get clientsActifs => clients.where((c) => c.client.isActive).length;

  double get encoursGlobal => creances.fold<double>(0, (t, c) => t + c.resteDu);

  double echusAuDela(DateTime jour, int jours) => creances
      .where((c) => (c.retard(jour) ?? 0) > jours)
      .fold<double>(0, (t, c) => t + c.resteDu);

  double get avancesEnCours => avances
      .where((a) => !a.soldee)
      .fold<double>(0, (t, a) => t + a.soldeRestant);

  int get clientsAvecAvance => avances
      .where((a) => !a.soldee)
      .map((a) => a.avance.customerId)
      .toSet()
      .length;

  /// File de relance active — les créances échues, la plus vieille d'abord.
  ///
  /// ⚠️ **MÊME RÈGLE QUE LE WEB** (`app/Livewire/Ventes/RelancesClients.php`
  /// l.117-125) : échéance dépassée, solde restant strictement positif, tri
  /// par ancienneté décroissante. Deux règles différentes donneraient deux
  /// files différentes pour la même ferme.
  List<LigneCreance> fileDeRelance(DateTime jour) =>
      creances.where((c) => c.echue(jour) && c.resteDu > 0).toList()
        ..sort((a, b) => (b.retard(jour) ?? 0).compareTo(a.retard(jour) ?? 0));

  /// Relances envoyées dans le mois de [jour].
  ///
  /// ⚠️ **LE MOIS EN COURS, PAS LE TOTAL.** La maquette ne dit pas la période
  /// (`relances-clients.html` l.118) ; le web la fixe au mois calendaire
  /// (`RelancesClients.php` l.92). Compter tout l'historique afficherait un
  /// nombre qui ne baisse jamais, et qui ne dirait plus rien du mois courant.
  int relancesDuMois(DateTime jour) => relances.where((r) {
    final date = r.relance.reminderDate;
    return date != null && date.year == jour.year && date.month == jour.month;
  }).length;
}

/// Lectures du hub `prototype_html/creances-clients.html`.
///
/// ⚠️⚠️ **TROIS TABLES RÉELLES, AUCUNE NE DESCENDAIT.** `customers` (10
/// lignes), `receivables` (51) et `customer_advances` (4) existent depuis les
/// premiers sprints ; le tirage ne les servait pas (ticket 14.75). Le hub
/// était donc impossible à bâtir — et trois écrans déjà livrés portaient un
/// tiret à cause de cette seule absence : « Encours Créances » du Tableau de
/// Bord et de l'historique des ventes, et le nom du client dans cet
/// historique.
///
/// ⚠️ Les CRÉANCES (`receivables`) et les RELANCES se lisent seulement : une créance se solde par un
/// encaissement, geste encore réservé au web (ticket VC-1 de `docs/INVENTAIRE_LECTURE_SEULE_POSTE.md`).
/// Les clients et les avances, eux, s'écrivent ici depuis F0.55 (`creerClient`, `enregistrerAvance`…).
class ClientsCreancesRepository {
  ClientsCreancesRepository({
    required this.database,
    required this.deviceId,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final AppDatabase database;

  /// Identifiant du poste, posé sur chaque avance et imputation (`SyncColumns`).
  final String deviceId;
  final Uuid _uuid;

  /// Règles de saisie, identiques à `CustomerCatalogService` (Laravel) : seul le nom est
  /// obligatoire. ⚠️ La maquette marque « Téléphone * » ; le web ne l'exige pas (règle
  /// métier : Laravel l'emporte). Vide si recevable.
  static Map<String, String> validerFiche(FormulaireClient f) {
    final e = <String, String>{};

    if (f.nom.trim().isEmpty) {
      e['nom'] = 'Ce champ est obligatoire.';
    } else if (f.nom.trim().length > 150) {
      e['nom'] = '150 caractères au plus.';
    }
    if (f.telephone.trim().length > 30) {
      e['telephone'] = '30 caractères au plus.';
    }
    if (f.ville.trim().length > 100) e['ville'] = '100 caractères au plus.';
    final mail = f.email.trim();
    if (mail.isNotEmpty) {
      if (mail.length > 150) {
        e['email'] = '150 caractères au plus.';
      } else if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
        e['email'] = "Adresse e-mail invalide.";
      }
    }

    return e;
  }

  String? _ouNul(String v) => v.trim().isEmpty ? null : v.trim();

  /// Crée une fiche, EN ATTENTE d'envoi. Le serveur la valide à la synchronisation.
  Future<Customer> creerClient(FormulaireClient f) async {
    final id = _uuid.v4();

    await database
        .into(database.customers)
        .insert(
          CustomersCompanion.insert(
            id: id,
            name: f.nom.trim(),
            phone: Value(_ouNul(f.telephone)),
            city: Value(_ouNul(f.ville)),
            email: Value(_ouNul(f.email)),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );

    return (await _fiche(id))!;
  }

  /// ⚠️ Le plafond de crédit n'est pas touché : le formulaire n'a pas ce champ.
  Future<Customer> modifierClient(String id, FormulaireClient f) async {
    await (database.update(
      database.customers,
    )..where((c) => c.id.equals(id))).write(
      CustomersCompanion(
        name: Value(f.nom.trim()),
        phone: Value(_ouNul(f.telephone)),
        city: Value(_ouNul(f.ville)),
        email: Value(_ouNul(f.email)),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );

    return (await _fiche(id))!;
  }

  /// Archive la fiche : `is_active = false`, rien n'est supprimé. Ses ventes, créances
  /// et avances restent lisibles.
  Future<void> archiverClient(String id) => archiverClients([id]);

  /// Archivage en masse. Retourne le nombre de fiches réellement archivées (une fiche
  /// déjà archivée n'est pas comptée), comme le web.
  Future<int> archiverClients(List<String> ids) async {
    final actifs =
        await (database.select(database.customers)..where(
              (c) => Expression.and([c.id.isIn(ids), c.isActive.equals(true)]),
            ))
            .get();

    await (database.update(
      database.customers,
    )..where((c) => c.id.isIn(ids))).write(
      const CustomersCompanion(
        isActive: Value(false),
        syncStatus: Value(SyncStatus.pending),
      ),
    );

    return actifs.length;
  }

  Future<Customer?> _fiche(String id) => (database.select(
    database.customers,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Seuil d'ancienneté du KPI « Échus > 30 jours ».
  static const int seuilEchu = 30;

  /// ⚠️ Le jour de référence n'est pas retenu ici : l'âge d'une créance se
  /// calcule **à l'affichage** (`LigneCreance.retard`), pas au chargement.
  /// Le figer au tirage ferait vieillir l'encours d'un poste resté allumé.
  Future<DonneesClients> charger() async {
    final clients = await database.select(database.customers).get();
    final creances = await database.select(database.receivables).get();
    final avances = await database.select(database.customerAdvances).get();
    final relances = await database.select(database.customerReminders).get();
    final ventes = await database.select(database.sales).get();
    final comptes = await (database.select(
      database.treasuryAccounts,
    )..orderBy([(t) => OrderingTerm(expression: t.label)])).get();

    final nomDe = {for (final c in clients) c.id: c.name};

    // ⚠️ Imputations EN ATTENTE seulement : une imputation acquittée est déjà dans
    // `amount_used` / `amount_paid` (tirage de confirmation du moteur) ; une refusée
    // (`conflict`) n'a rien appliqué.
    final enAttente = await (database.select(
      database.advanceImputations,
    )..where((i) => i.syncStatus.equalsValue(SyncStatus.pending))).get();
    final parAvance = <String, double>{};
    final parCreance = <String, double>{};
    for (final i in enAttente) {
      parAvance[i.customerAdvanceId] =
          (parAvance[i.customerAdvanceId] ?? 0) + i.amount;
      final cible = i.receivableId;
      if (cible != null) {
        parCreance[cible] = (parCreance[cible] ?? 0) + i.amount;
      }
    }

    // Ticket VC-1 — les ENCAISSEMENTS en attente réduisent aussi le solde de leur créance (le poste ne modifie jamais
    // `amount_paid` : le serveur l'applique et le tirage de confirmation le rend).
    for (final e in await (database.select(
      database.receivablePayments,
    )..where((p) => p.syncStatus.equalsValue(SyncStatus.pending))).get()) {
      final cible = e.receivableId;
      if (cible != null) parCreance[cible] = (parCreance[cible] ?? 0) + e.amount;
    }
    // Ticket VC-3 — les encaissements GLOBAUX (sans créance visée) pèsent sur les plus anciennes d'abord.
    await _repartirGlobaux(creances, parCreance);

    final refus = {
      for (final c in await (database.select(
        database.syncConflicts,
      )..where((c) => c.sourceTable.equals('customer_advances'))).get())
        c.recordId: c.reason,
    };

    // ⚠️⚠️ F0.77 — SOLDE NET, COMME LES CRÉANCES, LES KPI ET LES AVANCES. Le solde de la
    // liste des clients était BRUT (`amount − amount_paid`) : après une imputation saisie
    // et pas encore acquittée, la liste disait « solde dû 50 000 » là où « Suivi des Dettes
    // Clients » disait 30 000. Même formule que `LigneCreance.resteDu` (plancher à zéro PAR
    // créance) : on passe par elle, pour ne pas en écrire une troisième copie.
    final duParClient = <String, double>{};
    for (final c in creances) {
      final reste = LigneCreance(
        creance: c,
        nomClient: '',
        imputeEnAttente: parCreance[c.id] ?? 0,
      ).resteDu;
      duParClient[c.customerId] = (duParClient[c.customerId] ?? 0) + reste;
    }

    final achatsParClient = <String, double>{};
    for (final v in ventes.where((v) => v.status != 'annulee')) {
      final id = v.customerId;
      if (id == null) continue;
      achatsParClient[id] = (achatsParClient[id] ?? 0) + v.total;
    }

    return DonneesClients(
      clients:
          (clients.where((c) => c.isActive).toList()
                ..sort((a, b) => a.name.compareTo(b.name)))
              .map(
                (c) => LigneClient(
                  client: c,
                  totalAchats: achatsParClient[c.id] ?? 0,
                  soldeDu: duParClient[c.id] ?? 0,
                ),
              )
              .toList(),
      creances:
          (creances.toList()..sort(
                (a, b) => (a.dueDate ?? DateTime(2100)).compareTo(
                  b.dueDate ?? DateTime(2100),
                ),
              ))
              .map(
                (c) => LigneCreance(
                  creance: c,
                  nomClient: nomDe[c.customerId] ?? 'Client inconnu',
                  imputeEnAttente: parCreance[c.id] ?? 0,
                ),
              )
              .toList(),
      avances:
          (avances.toList()..sort(
                (a, b) => (b.advanceDate ?? DateTime(1970)).compareTo(
                  a.advanceDate ?? DateTime(1970),
                ),
              ))
              .map(
                (a) => LigneAvance(
                  avance: a,
                  nomClient: nomDe[a.customerId] ?? 'Client inconnu',
                  imputeEnAttente: parAvance[a.id] ?? 0,
                  motifRefus: refus[a.id],
                ),
              )
              .toList(),
      relances:
          (relances.toList()..sort(
                (a, b) => (b.reminderDate ?? DateTime(1970)).compareTo(
                  a.reminderDate ?? DateTime(1970),
                ),
              ))
              .map(
                (r) => LigneRelance(
                  relance: r,
                  nomClient: nomDe[r.customerId] ?? 'Client inconnu',
                ),
              )
              .toList(),
      // ⚠️ Voir le champ : la date de création ne descend pas.
      nouveauxDuMois: null,
      comptes: comptes,
    );
  }

  // ── Avances et imputations saisies au poste (ticket F0.73) ────────────────

  /// Modes de la maquette (`adv-new-mode`) → code du contrat serveur.
  ///
  /// ⚠️ MTN et Moov se CONFONDENT en `mobile_money` : le contrat 15.19 n'a pas
  /// d'opérateur. Le reçu garde le libellé choisi, la ferme ne le retient pas.
  static const modesPaiement = <String, String>{
    'Espèces': 'especes',
    'MTN Mobile Money': 'mobile_money',
    'Moov Money': 'mobile_money',
    'Chèque': 'cheque',
  };

  /// Reste d'une avance, imputations EN ATTENTE déduites.
  Future<double> resteAvance(CustomerAdvance a) async {
    final net = a.amount - a.amountUsed - await _enAttenteDe(avanceId: a.id);
    return net < 0 ? 0 : net;
  }

  /// Solde d'une créance, imputations EN ATTENTE déduites.
  Future<double> soldeCreance(Receivable c) async {
    final net = c.amount - c.amountPaid - ((await _enAttenteParCreance())[c.id] ?? 0);
    return net < 0 ? 0 : net;
  }

  /// Ce qui pèse DÉJÀ sur chaque créance, en attente d'envoi : imputations d'acompte, encaissements visant la créance
  /// (VC-1) et encaissements globaux répartis (VC-3).
  Future<Map<String, double>> _enAttenteParCreance() async {
    final creances = await database.select(database.receivables).get();
    final parCreance = <String, double>{};
    for (final i in await (database.select(database.advanceImputations)
          ..where((i) => i.syncStatus.equalsValue(SyncStatus.pending)))
        .get()) {
      final cible = i.receivableId;
      if (cible != null) parCreance[cible] = (parCreance[cible] ?? 0) + i.amount;
    }
    for (final e in await (database.select(database.receivablePayments)
          ..where((p) => p.syncStatus.equalsValue(SyncStatus.pending)))
        .get()) {
      final cible = e.receivableId;
      if (cible != null) parCreance[cible] = (parCreance[cible] ?? 0) + e.amount;
    }
    await _repartirGlobaux(creances, parCreance);
    return parCreance;
  }

  /// Répartit les encaissements GLOBAUX en attente (`receivable_id` nul) sur les créances de leur client, les plus
  /// anciennes d'abord (échéance croissante, la règle de `CustomerSettlementService`), dans la limite de ce qui reste
  /// dû après tout ce qui pèse déjà sur chaque créance.
  Future<void> _repartirGlobaux(List<Receivable> creances, Map<String, double> parCreance) async {
    final globaux = await (database.select(database.receivablePayments)
          ..where((p) => Expression.and([p.syncStatus.equalsValue(SyncStatus.pending), p.receivableId.isNull()]))
          ..orderBy([(p) => OrderingTerm(expression: p.updatedAt)]))
        .get();
    for (final p in globaux) {
      var reste = p.amount;
      final siennes = creances.where((c) => c.customerId == p.customerId).toList()
        ..sort((a, b) => (a.dueDate ?? DateTime(2100)).compareTo(b.dueDate ?? DateTime(2100)));
      for (final c in siennes) {
        if (reste <= 0) break;
        final libre = c.amount - c.amountPaid - (parCreance[c.id] ?? 0);
        if (libre <= 0) continue;
        final part = reste < libre ? reste : libre;
        parCreance[c.id] = (parCreance[c.id] ?? 0) + part;
        reste -= part;
      }
    }
  }

  /// Ticket VC-3 — « Enregistrer un règlement » de la fiche client (solde global, FIFO) : un encaissement SANS créance
  /// visée, EN ATTENTE d'envoi. Refus reproduits avant d'écrire : montant ≥ 1, client et compte connus, solde du client
  /// non nul, jamais plus que ce solde (net de tout ce qui est en attente), exercice ouvert.
  Future<EncaissementCreance> encaisserSolde({
    required String clientId,
    required double montant,
    required String compteId,
    DateTime? date,
  }) async {
    if (montant.isNaN || montant.isInfinite || montant <= 0) {
      throw const SaisieRefusee('Le montant du règlement doit être supérieur à zéro.');
    }
    if (montant < 1) throw const SaisieRefusee("Le montant du règlement doit être d'au moins 1 FCFA.");

    final client = await clientDe(clientId);
    if (client == null) throw const SaisieRefusee('Client inconnu — synchronisez le poste.');
    final compte = await (database.select(database.treasuryAccounts)..where((c) => c.id.equals(compteId))).getSingleOrNull();
    if (compte == null) throw const SaisieRefusee('Compte de trésorerie inconnu — synchronisez le poste avant de saisir.');

    final charges = await _enAttenteParCreance();
    final solde = (await (database.select(database.receivables)..where((c) => c.customerId.equals(clientId))).get())
        .fold<double>(0, (t, c) {
      final net = c.amount - c.amountPaid - (charges[c.id] ?? 0);
      return t + (net > 0 ? net : 0);
    });
    if (solde <= 0) throw const SaisieRefusee("Ce client n'a aucune créance ouverte.");
    if (montant > solde + 0.005) {
      throw SaisieRefusee(
        'Le montant dépasse le solde du client (${solde.toStringAsFixed(0)} F), '
        'encaissements et imputations en attente déduits.',
      );
    }

    final jour = date ?? HeureBenin.maintenant();
    await ExerciceDeSaisie(database).refuser(jour);

    final id = _uuid.v4();
    await database.into(database.receivablePayments).insert(
      ReceivablePaymentsCompanion.insert(
        id: id,
        deviceId: deviceId,
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: DateTime.now(),
        customerId: clientId,
        treasuryAccountId: compteId,
        amount: montant,
        paymentDate: DateTime(jour.year, jour.month, jour.day),
      ),
    );
    return (database.select(database.receivablePayments)..where((p) => p.id.equals(id))).getSingle();
  }

  /// Ticket VC-3 — le contenu de « Profil Client » (`ProfileClient`) : ce que le poste sait de ce client.
  Future<ProfilClient?> profil(String clientId) async {
    final client = await clientDe(clientId);
    if (client == null) return null;

    final donnees = await charger();
    final creances = donnees.creances.where((l) => l.creance.customerId == clientId && l.resteDu > 0).toList()
      ..sort((a, b) => (a.creance.dueDate ?? DateTime(2100)).compareTo(b.creance.dueDate ?? DateTime(2100)));

    final ventes = await (database.select(database.sales)
          ..where((v) => v.customerId.equals(clientId))
          ..orderBy([(v) => OrderingTerm.desc(v.soldAt)])
          ..limit(20))
        .get();
    final lignes = ventes.isEmpty
        ? <SaleLine>[]
        : await (database.select(database.saleLines)..where((l) => l.saleId.isIn([for (final v in ventes) v.id]))).get();
    final produits = {for (final p in await database.select(database.products).get()) p.id: p.name};

    return ProfilClient(
      client: client,
      soldeGlobal: creances.fold<double>(0, (t, l) => t + l.resteDu),
      ventes: [
        for (final v in ventes)
          VenteDuClient(
            vente: v,
            articles: [
              for (final l in lignes)
                if (l.saleId == v.id && produits[l.productId] != null) produits[l.productId]!,
            ].join(', '),
          ),
      ],
      creances: creances,
      avances: donnees.avances.where((a) => a.avance.customerId == clientId && !a.soldee && a.avance.isActive).toList(),
      relances: (await (database.select(database.customerReminders)
                ..where((r) => r.customerId.equals(clientId))
                ..orderBy([(r) => OrderingTerm.desc(r.reminderDate)]))
              .get()),
      comptes: donnees.comptes,
    );
  }

  Future<double> _enAttenteDe({String? avanceId, String? creanceId}) async {
    var encaisse = 0.0;
    if (creanceId != null) {
      // Ticket VC-1 — encaissements en attente sur cette créance.
      encaisse = (await (database.select(database.receivablePayments)..where(
                (p) => Expression.and([
                  p.syncStatus.equalsValue(SyncStatus.pending),
                  p.receivableId.equals(creanceId),
                ]),
              ))
              .get())
          .fold<double>(0, (t, p) => t + p.amount);
    }
    final lignes =
        await (database.select(database.advanceImputations)..where(
              (i) => Expression.and([
                i.syncStatus.equalsValue(SyncStatus.pending),
                if (avanceId != null) i.customerAdvanceId.equals(avanceId),
                if (creanceId != null) i.receivableId.equals(creanceId),
              ]),
            ))
            .get();
    return encaisse + lignes.fold<double>(0, (t, i) => t + i.amount);
  }

  /// Enregistre un acompte reçu, EN ATTENTE d'envoi.
  ///
  /// ⚠️⚠️ **LE POSTE N'ÉCRIT QUE LE FAIT.** Aucun solde de trésorerie n'est modifié,
  /// aucune écriture n'est passée : le serveur fait entrer l'argent dans les DEUX livres
  /// (solde du compte et classe 5) et passe D 5xx / C 419, dans une transaction.
  ///
  /// ⚠️ **REFUSER AVANT D'ÉCRIRE.** Montant d'au moins 1 FCFA (le serveur refuse en
  /// dessous), client actif et compte de trésorerie connus, motif renseigné.
  /// ⚠️ Le MOTIF est obligatoire ici parce que la maquette le marque `*` ; le serveur,
  /// lui, le laisse facultatif (constat 6 du ticket 15.19) — le poste est plus strict,
  /// décision client à confirmer.
  Future<CustomerAdvance> enregistrerAvance({
    required String clientId,
    required double montant,
    required String compteId,
    required String motif,
    String modePaiement = 'Espèces',
    DateTime? date,
  }) async {
    // ⚠️ `Infinity` (saisie « 1e999 ») n'est ni NaN ni <= 0 : accepté, il ferait échouer
    // l'encodage JSON de l'envoi à chaque synchronisation et bloquerait toute la file.
    if (montant.isNaN || montant.isInfinite || montant <= 0) {
      throw const SaisieRefusee(
        "Le montant de l'acompte doit être supérieur à zéro.",
      );
    }
    if (montant < 1) {
      throw const SaisieRefusee(
        "Le montant de l'acompte doit être d'au moins 1 FCFA.",
      );
    }

    final client = await (database.select(
      database.customers,
    )..where((c) => c.id.equals(clientId))).getSingleOrNull();
    if (client == null || !client.isActive) {
      throw const SaisieRefusee('Client inconnu — synchronisez le poste.');
    }

    final compte = await (database.select(
      database.treasuryAccounts,
    )..where((c) => c.id.equals(compteId))).getSingleOrNull();
    if (compte == null) {
      throw const SaisieRefusee(
        'Compte de trésorerie inconnu — synchronisez le poste avant de saisir.',
      );
    }

    final motifNet = motif.trim();
    if (motifNet.isEmpty) {
      throw const SaisieRefusee(
        'Le motif / la commande réservée est obligatoire.',
      );
    }
    if (motifNet.length > 255) {
      throw const SaisieRefusee('Le motif tient en 255 caractères au plus.');
    }

    final code = modesPaiement[modePaiement];
    if (code == null) {
      throw const SaisieRefusee('Mode de paiement inconnu.');
    }

    final jour = date ?? HeureBenin.maintenant();

    // 🔴→✅ Ticket EX6 (EF7) — l'écriture D 5xx / C 419 est datée de l'avance (`CustomerAdvanceService::recevoir`) :
    // exercice absent (sans filet R2) ou clos → refusé AVANT d'écrire, motif R4 du serveur ([RefusExercice]).
    await ExerciceDeSaisie(database).refuser(jour);

    final id = _uuid.v4();

    await database
        .into(database.customerAdvances)
        .insert(
          CustomerAdvancesCompanion.insert(
            id: id,
            customerId: clientId,
            amount: montant,
            amountUsed: const Value(0),
            advanceDate: Value(DateTime(jour.year, jour.month, jour.day)),
            isActive: const Value(true),
            treasuryAccountId: Value(compteId),
            paymentMode: Value(code),
            motif: Value(motifNet),
            deviceId: Value(deviceId),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );

    return (database.select(
      database.customerAdvances,
    )..where((a) => a.id.equals(id))).getSingle();
  }

  /// Impute un acompte sur une créance, EN ATTENTE d'envoi.
  ///
  /// ⚠️⚠️ **NI `amount_used` NI `amount_paid` NE BOUGENT AU POSTE.** Le serveur applique
  /// `min(montant, reste de l'avance, solde de la créance)`, met à jour les deux et passe
  /// D 419 / C 411. Ici on refuse AVANT d'écrire ce que le serveur refuserait ou
  /// plafonnerait en silence : au-delà du reste de l'avance, au-delà du solde de la
  /// créance, tous deux NETS des imputations déjà en attente, ou créance d'un autre client.
  Future<ImputationAvance> imputerAvance({
    required String avanceId,
    required String creanceId,
    required double montant,
    DateTime? date,
  }) async {
    if (montant.isNaN || montant.isInfinite || montant <= 0) {
      throw const SaisieRefusee(
        'Le montant à imputer doit être supérieur à zéro.',
      );
    }
    if (montant < 1) {
      throw const SaisieRefusee(
        "Le montant à imputer doit être d'au moins 1 FCFA.",
      );
    }

    final avance = await (database.select(
      database.customerAdvances,
    )..where((a) => a.id.equals(avanceId))).getSingleOrNull();
    if (avance == null || !avance.isActive) {
      throw const SaisieRefusee('Avance introuvable ou archivée.');
    }
    if (avance.syncStatus == SyncStatus.conflict) {
      throw const SaisieRefusee(
        "Cette avance a été refusée par le serveur : elle n'existe pas côté "
        "ferme. Relancez-la depuis la synchronisation avant de l'imputer.",
      );
    }

    final creance = await (database.select(
      database.receivables,
    )..where((c) => c.id.equals(creanceId))).getSingleOrNull();
    if (creance == null) {
      throw const SaisieRefusee('Créance introuvable — synchronisez le poste.');
    }
    if (creance.customerId != avance.customerId) {
      throw const SaisieRefusee(
        "Cette créance n'appartient pas au client de l'avance.",
      );
    }

    final reste = await resteAvance(avance);
    if (reste <= 0) {
      throw const SaisieRefusee(
        'Cette avance est déjà entièrement imputée : rien à imputer.',
      );
    }
    final solde = await soldeCreance(creance);
    if (solde <= 0) {
      throw const SaisieRefusee(
        'Cette créance est déjà soldée : rien à imputer.',
      );
    }
    if (montant > reste + 0.005) {
      throw SaisieRefusee(
        "Le montant dépasse le reste de l'avance (${reste.toStringAsFixed(0)} F), "
        'imputations en attente déduites.',
      );
    }
    if (montant > solde + 0.005) {
      throw SaisieRefusee(
        'Le montant dépasse le solde de la créance (${solde.toStringAsFixed(0)} F), '
        'imputations en attente déduites.',
      );
    }

    final jour = date ?? HeureBenin.maintenant();

    // 🔴→✅ Ticket EX6 (EF7) — l'écriture D 419 / C 411 est datée de l'imputation (`CustomerAdvanceService::imputer`) :
    // exercice absent (sans filet R2) ou clos → refusé AVANT d'écrire, motif R4 du serveur ([RefusExercice]).
    await ExerciceDeSaisie(database).refuser(jour);

    final id = _uuid.v4();

    await database
        .into(database.advanceImputations)
        .insert(
          AdvanceImputationsCompanion.insert(
            id: id,
            deviceId: deviceId,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: DateTime.now(),
            customerAdvanceId: avanceId,
            receivableId: Value(creanceId),
            amount: montant,
            imputationDate: DateTime(jour.year, jour.month, jour.day),
          ),
        );

    return (database.select(
      database.advanceImputations,
    )..where((i) => i.id.equals(id))).getSingle();
  }

  /// Ticket VC-1 — « Enregistrer un Recouvrement » (`suivi-dettes.blade.php`, `modal-add-payment`) : encaisse une
  /// créance, EN ATTENTE d'envoi.
  ///
  /// ⚠️⚠️ **LE POSTE N'ÉCRIT QUE LE FAIT.** Ni `amount_paid` de la créance, ni solde de compte, ni écriture : le
  /// serveur (`CustomerSettlementService`) solde la créance, fait entrer l'argent dans les DEUX livres de trésorerie et
  /// passe D 5xx / C 411, dans une transaction. Le poste AFFICHE le solde net de ce qu'il a saisi (`soldeCreance`).
  ///
  /// ⚠️ **REFUSER AVANT D'ÉCRIRE**, avec les messages du serveur : montant d'au moins 1 FCFA, créance et compte connus,
  /// créance non soldée, jamais plus que son solde (le web plafonne en silence ; le poste le dit, comme pour les
  /// avances), exercice de la date ouvert (EX6).
  Future<EncaissementCreance> encaisserCreance({
    required String creanceId,
    required double montant,
    required String compteId,
    DateTime? date,
  }) async {
    if (montant.isNaN || montant.isInfinite || montant <= 0) {
      throw const SaisieRefusee('Le montant du règlement doit être supérieur à zéro.');
    }
    if (montant < 1) {
      throw const SaisieRefusee("Le montant du règlement doit être d'au moins 1 FCFA.");
    }

    final creance = await (database.select(
      database.receivables,
    )..where((c) => c.id.equals(creanceId))).getSingleOrNull();
    if (creance == null) {
      throw const SaisieRefusee('Créance introuvable — synchronisez le poste.');
    }

    final compte = await (database.select(
      database.treasuryAccounts,
    )..where((c) => c.id.equals(compteId))).getSingleOrNull();
    if (compte == null) {
      throw const SaisieRefusee('Compte de trésorerie inconnu — synchronisez le poste avant de saisir.');
    }

    final solde = await soldeCreance(creance);
    if (solde <= 0) {
      throw const SaisieRefusee('Cette créance est déjà soldée : rien à encaisser.');
    }
    if (montant > solde + 0.005) {
      throw SaisieRefusee(
        'Le montant dépasse le solde de la créance (${solde.toStringAsFixed(0)} F), '
        'encaissements et imputations en attente déduits.',
      );
    }

    final jour = date ?? HeureBenin.maintenant();

    // L'écriture D 5xx / C 411 est datée du règlement : exercice absent (sans filet R2) ou clos → refusé AVANT d'écrire.
    await ExerciceDeSaisie(database).refuser(jour);

    final id = _uuid.v4();

    await database
        .into(database.receivablePayments)
        .insert(
          ReceivablePaymentsCompanion.insert(
            id: id,
            deviceId: deviceId,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: DateTime.now(),
            customerId: creance.customerId,
            receivableId: Value(creanceId),
            treasuryAccountId: compteId,
            amount: montant,
            paymentDate: DateTime(jour.year, jour.month, jour.day),
          ),
        );

    return (database.select(
      database.receivablePayments,
    )..where((p) => p.id.equals(id))).getSingle();
  }

  // ── Ticket VC-2 — relances de clients ────────────────────────────────────────

  /// Téléphone d'un client (lien WhatsApp), `null` s'il est inconnu.
  Future<String?> telephoneDe(String clientId) async => (await clientDe(clientId))?.phone;

  Future<Customer?> clientDe(String clientId) => (database.select(database.customers)..where((c) => c.id.equals(clientId))).getSingleOrNull();

  /// Les quatre canaux (`RelanceClientService::CANAUX`).
  static const canauxRelance = ['whatsapp', 'email', 'sms', 'courrier'];

  /// Les trois modèles du WEB (`RelancesClients::defaultTemplates`) — le web est le maître, au caractère près.
  static const modelesRelance = <String, String>{
    '1':
        "Bonjour [NOM],\n\nNous vous rappelons amicalement que la facture [FACTURE] d'un montant de [MONTANT_DU] FCFA est arrivée à échéance le [DATE_ECHEANCE]. Merci de bien vouloir régulariser votre situation.\n\nCordialement,\nFerme École OLOUWACHEGOUN",
    '2':
        "Bonjour [NOM],\n\nMalgré notre précédent rappel, la facture [FACTURE] d'un montant de [MONTANT_DU] FCFA reste impayée depuis le [DATE_ECHEANCE]. Merci de régulariser rapidement votre situation.\n\nCordialement,\nFerme École OLOUWACHEGOUN",
    '3':
        "Mise en demeure — [NOM],\n\nSauf erreur de notre part, la facture [FACTURE] d'un montant de [MONTANT_DU] FCFA demeure impayée malgré nos relances. À défaut de règlement sous 8 jours, nous nous verrons contraints d'engager les démarches de recouvrement nécessaires.\n\nFerme École OLOUWACHEGOUN",
  };

  /// `RelancesClients::renderTemplate` : [NOM], [FACTURE] (8 premiers caractères en majuscules), [MONTANT_DU] (solde,
  /// milliers séparés par une espace) et [DATE_ECHEANCE] (jj/mm/aaaa).
  static String rendreModele(String modele, LigneCreance ligne) {
    final identifiant = ligne.creance.saleId ?? ligne.creance.id;
    final echeance = ligne.creance.dueDate;
    return modele
        .replaceAll('[NOM]', ligne.nomClient)
        .replaceAll('[FACTURE]', identifiant.substring(0, identifiant.length < 8 ? identifiant.length : 8).toUpperCase())
        .replaceAll('[MONTANT_DU]', DocumentsAvances.formaterMontant(ligne.resteDu))
        .replaceAll('[DATE_ECHEANCE]', echeance == null ? '' : DocumentsAvances.formaterJour(echeance));
  }

  /// Le lien `wa.me` du web : numéro réduit à ses chiffres, message encodé.
  static String lienWhatsapp(String telephone, String message) =>
      'https://wa.me/${telephone.replaceAll(RegExp(r'[^0-9]'), '')}?text=${Uri.encodeComponent(message)}';

  /// Lettre de relance (`exports.courrier-relance`) : destinataire, ville, date, puis le message.
  static DocumentOfficiel lettreRelance({required String client, String? ville, required DateTime date, required String message}) {
    return DocumentOfficiel(
      titre: 'Lettre de Relance',
      sousTitre: client,
      entetes: const ['Champ', 'Valeur'],
      lignes: [
        DonneesDocument(['Destinataire', client]),
        if (ville != null && ville.isNotEmpty) DonneesDocument(['Ville', ville]),
        DonneesDocument(['Date', DocumentsAvances.formaterJour(date)]),
        DonneesDocument(['Message', message]),
      ],
    );
  }

  /// « Relancer WhatsApp » / « par Mail » / « par SMS » / « Exporter Courrier » : écrit la relance, EN ATTENTE d'envoi.
  ///
  /// ⚠️⚠️ **LE POSTE FAIT CE QUE L'APPAREIL PEUT FAIRE, ET DEMANDE LE RESTE.** WhatsApp (lien `wa.me`) et le courrier
  /// (PDF) se font ICI — l'écran les déclenche APRÈS cette écriture ; l'e-mail et le SMS partent du SERVEUR (SMTP et
  /// fournisseur SMS de l'entreprise) : la demande attend la synchronisation, qui l'acquitte ou la refuse avec son motif.
  /// Les refus du serveur sont reproduits AVANT d'écrire, mêmes messages : numéro (WhatsApp, SMS), adresse (e-mail),
  /// message obligatoire.
  Future<CustomerReminder> relancer({
    String? creanceId,
    String? clientId,
    required String canal,
    required String message,
    DateTime? date,
  }) async {
    if (!canauxRelance.contains(canal)) throw const SaisieRefusee('Canal de relance inconnu.');
    if (message.trim().isEmpty) throw const SaisieRefusee('Le champ message est obligatoire.');

    // Ticket VC-3 — « relance rapide » de la fiche client : sans créance visée, `clientId` seul.
    Receivable? creance;
    if (creanceId != null) {
      creance = await (database.select(database.receivables)..where((c) => c.id.equals(creanceId))).getSingleOrNull();
      if (creance == null) throw const SaisieRefusee('Créance introuvable — synchronisez le poste.');
    }
    final idClient = creance?.customerId ?? clientId;
    if (idClient == null) throw const SaisieRefusee('Client inconnu — synchronisez le poste.');
    final client = await clientDe(idClient);
    if (client == null) throw const SaisieRefusee('Client inconnu — synchronisez le poste.');

    final telephone = (client.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if ((canal == 'whatsapp' || canal == 'sms') && telephone.isEmpty) {
      throw const SaisieRefusee("Ce client n'a pas de numéro de téléphone enregistré.");
    }
    if (canal == 'email' && (client.email ?? '').trim().isEmpty) {
      throw const SaisieRefusee("Ce client n'a pas d'adresse email enregistrée.");
    }

    final jour = date ?? HeureBenin.maintenant();
    final id = _uuid.v4();

    await database
        .into(database.customerReminders)
        .insert(
          CustomerRemindersCompanion.insert(
            id: id,
            deviceId: deviceId,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: DateTime.now(),
            customerId: client.id,
            receivableId: Value(creanceId),
            channel: canal,
            reminderDate: Value(DateTime(jour.year, jour.month, jour.day)),
            message: Value(message),
          ),
        );

    return (database.select(database.customerReminders)..where((r) => r.id.equals(id))).getSingle();
  }
}

/// Une vente de la fiche client (« Ventes ») et la liste de ses articles.
class VenteDuClient {
  const VenteDuClient({required this.vente, required this.articles});

  final Sale vente;
  final String articles;
}

/// Ticket VC-3 — ce que « Profil Client » affiche d'un client (`ProfileClient` du web).
class ProfilClient {
  const ProfilClient({
    required this.client,
    required this.soldeGlobal,
    required this.ventes,
    required this.creances,
    required this.avances,
    required this.relances,
    required this.comptes,
  });

  final Customer client;

  /// « Solde Global Dû » : somme des soldes NETS des créances encore dues.
  final double soldeGlobal;
  final List<VenteDuClient> ventes;
  final List<LigneCreance> creances;
  final List<LigneAvance> avances;
  final List<CustomerReminder> relances;
  final List<TreasuryAccount> comptes;

  /// Part du crédit autorisé utilisée, 0–100 (`null` : pas de plafond).
  int? get pourcentageCredit =>
      client.creditLimit > 0 ? (soldeGlobal / client.creditLimit * 100).round().clamp(0, 100) : null;
}

/// Saisie d'avance ou d'imputation refusée AVANT d'être écrite — le motif est montré
/// tel quel.
class SaisieRefusee implements Exception {
  const SaisieRefusee(this.motif);

  final String motif;

  @override
  String toString() => motif;
}

/// Documents éditables de « Historique des Avances » (`historique-avances.html`, F0.73).
///
/// ⚠️ **CONSTRUCTEURS PURS, SANS IMPRIMANTE NI DISQUE** : l'effet (boîte d'impression)
/// est injecté par l'écran — `EditeursRapports`, le SEUL exportateur du poste.
class DocumentsAvances {
  const DocumentsAvances._();

  /// `exportRecuAcomptePDF` de la maquette (l.533-551), mot pour mot, plus la mention du
  /// poste.
  ///
  /// ⚠️⚠️ **REÇU DU POSTE, NON NUMÉROTÉ** (D12) : aucune numérotation de reçus n'existe
  /// ni au poste ni au serveur. Le document le dit, plutôt que d'inventer un numéro que
  /// la ferme ne retrouverait nulle part. Il est émis APRÈS l'écriture locale et dit
  /// que l'acompte n'est pas encore reçu par la ferme.
  static DocumentOfficiel recu({
    required String client,
    required String motif,
    required double montant,
    required String mode,
    required DateTime date,
  }) {
    return DocumentOfficiel(
      titre: "Reçu d'Acompte",
      sousTitre: 'Justificatif de versement — à conserver',
      entetes: const ['Champ', 'Valeur'],
      lignes: [
        DonneesDocument(['Client', client]),
        DonneesDocument(['Motif / Commande réservée', motif]),
        DonneesDocument([
          "Montant de l'acompte",
          '${formaterMontant(montant)} FCFA',
        ]),
        DonneesDocument(['Mode de paiement', mode]),
        DonneesDocument(['Date', formaterJour(date)]),
        const DonneesDocument(['Numéro', 'Reçu du poste — non numéroté']),
      ],
      noteDePied:
          "Ce reçu fait foi du versement de l'acompte ci-dessus, imputable sur la "
          'facture finale de la commande concernée. Reçu du poste : acompte '
          'enregistré sur ce poste, pas encore reçu par la ferme (en attente de '
          'synchronisation).',
    );
  }

  /// `exportAvancesPDF` de la maquette (l.554-568) : titre, sous-titre et cinq colonnes.
  ///
  /// ⚠️ Le document sort de la ferme : une avance non encore acquittée y est SIGNALÉE, et
  /// les soldes sont dits nets des imputations en attente.
  static DocumentOfficiel liste(List<LigneAvance> avances) {
    final enAttente = avances.where((a) => a.enAttente).length;
    final imputees = avances.where((a) => a.imputationEnAttente).length;

    return DocumentOfficiel(
      titre: 'Historique des Avances Clients',
      fichier: 'avances-{jour}.pdf',
      sousTitre: 'Acomptes et réservations de commandes',
      entetes: const [
        'Client',
        'Montant Avance',
        'Solde Restant',
        'Date',
        'Statut',
      ],
      lignes: [
        for (final a in avances)
          DonneesDocument([
            a.nomClient,
            '${formaterMontant(a.avance.amount)} FCFA',
            '${formaterMontant(a.soldeRestant)} FCFA',
            a.avance.advanceDate == null
                ? '—'
                : formaterJour(a.avance.advanceDate!),
            [
              if (a.refusee)
                'Refusée par le serveur'
              else
                a.soldee ? 'Soldée' : 'En cours',
              if (a.enAttente) 'en attente de synchronisation',
            ].join(' — '),
          ]),
      ],
      noteDePied: [
        'Soldes nets des imputations saisies sur ce poste et pas encore '
            'envoyées.',
        if (enAttente > 0)
          '$enAttente avance(s) saisie(s) sur ce poste, pas encore reçue(s) '
              'par la ferme.',
        if (imputees > 0)
          '$imputees avance(s) avec une imputation en attente de '
              'synchronisation.',
      ].join(' '),
    );
  }

  static String formaterMontant(double valeur) {
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  static String formaterJour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
