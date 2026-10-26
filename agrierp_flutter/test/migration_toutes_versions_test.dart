// Ticket F0.85-bis — la migration Drift doit réussir depuis TOUTE version de départ.
//
// ⚠️ Défaut d'origine : les paliers `createTable` créent la table avec le schéma COURANT
// (toutes ses colonnes), puis un palier `addColumn` postérieur rajoute une colonne que
// cette création vient déjà de poser. Depuis une base en v19, `accounting_entries` est
// créée au palier v20 AVEC `created_at`, et le palier v37 la rajoute : « duplicate column
// name: created_at », le poste ne s'ouvre plus. Les tests de migration existants ne
// partaient que de la version précédente (N-1 → N) et ne voyaient pas ce cas.
//
// Méthode : pour chaque version de départ N (1 à schemaVersion-1), une base neuve est
// ramenée à la forme vN en retirant les tables créées et les colonnes ajoutées APRÈS N
// (historique ci-dessous, relu du `onUpgrade`), `user_version` est posé à N, puis la base
// est rouverte : la migration réelle s'exécute. Son schéma final est comparé à celui
// d'une base neuve (tables, colonnes, types, nullabilité, défauts, clés étrangères, index).
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Version à laquelle chaque table a été créée par un palier `createTable`. Une table
/// absente de cette liste existe depuis la v1 (`createAll` d'origine).
Map<int, List<TableInfo>> _tablesCreees(AppDatabase d) => {
  2: [d.feedRationStandards],
  3: [d.veterinaryWithdrawalPeriods],
  4: [d.syncConflicts],
  5: [d.appSettings],
  6: [d.prophylaxisScheduleStandards, d.veterinaryRecords],
  9: [d.treasuryAccounts, d.expenseCategories, d.expenses],
  10: [d.livestockReproductionEvents],
  12: [d.customers, d.receivables, d.customerAdvances],
  13: [d.customerReminders],
  14: [d.feedTypes, d.elevageNumberingSettings],
  15: [d.suppliers, d.purchaseOrders, d.purchases, d.purchaseLines],
  16: [d.payables],
  18: [d.employees, d.internships, d.attendanceRecords],
  19: [d.mails, d.administrativeDocuments, d.archivedDocuments],
  20: [
    d.chartOfAccounts,
    d.fiscalYears,
    d.accountingEntries,
    d.accountingEntryLines,
  ],
  21: [
    d.companySettings,
    d.modulesConfig,
    d.rolesApplicatifs,
    d.utilisateurs,
    d.auditLogs,
  ],
  22: [d.notifications],
  23: [d.lotRevenues],
  24: [d.attestationTemplates],
  25: [d.animals],
  26: [d.livestockSpecies],
  28: [d.supplierPayments],
  31: [d.advanceImputations],
  32: [d.purchaseReturns, d.supplierRefunds, d.supplierCredits],
  // Ticket 15.46 — transferts entre bandes.
  39: [d.livestockTransfers],
  // Ticket H8b (D-H8) — infirmerie et calendrier vétérinaire planifié.
  41: [d.infirmaryRecords, d.veterinaryCalendarEvents],
  // Ticket U2 (D-U2) — objectifs de GMQ tirés du serveur.
  43: [d.growthStandards],
  // Ticket U9 — grand livre des stocks du serveur, en lecture seule.
  44: [d.stockMovements],
  // Ticket U13 — paie réglée du serveur, en lecture seule (Recettes et Dépenses).
  47: [d.payslips],
  // Ticket DEV — « Devis & Proforma » au poste.
  53: [d.quotes],
  // Tickets AV1 / AV2 — retours et avoirs clients (table mixte). ⚠️ Le palier 53 est celui de la branche « Devis Prestations ».
  54: [d.creditNotes],
  // Ticket DEP4 — lignes de dépense et centres de coût. ⚠️ Chaîne 52 → 53 (devis) → 54 (avoirs) → 56 (dépenses) : le palier
  // 55 est inutilisé (aucune table ni colonne), la migration passe de 54 à 56 sans trou.
  56: [d.expenseLines, d.costCenters],
  // Ticket ARC3 — la Corbeille : instantané du serveur et demandes. ⚠️ 57, 59 et 60 sont réservés à d'autres branches.
  58: [d.corbeilleElements, d.corbeilleDemandes],
};

/// Version à laquelle chaque colonne a été ajoutée à une table existante (palier
/// `addColumn`, ou reconstruction v11 de `livestock_reproduction_events`).
Map<int, List<(TableInfo, GeneratedColumn)>> _colonnesAjoutees(
  AppDatabase d,
) => {
  7: [
    (
      d.prophylaxisScheduleStandards,
      d.prophylaxisScheduleStandards.cycleDayStart,
    ),
    (
      d.prophylaxisScheduleStandards,
      d.prophylaxisScheduleStandards.cycleDayEnd,
    ),
  ],
  8: [(d.livestockLots, d.livestockLots.speciesCode)],
  11: [
    (d.livestockReproductionEvents, d.livestockReproductionEvents.deviceId),
    (d.livestockReproductionEvents, d.livestockReproductionEvents.syncStatus),
  ],
  17: [
    (d.sales, d.sales.customerName),
    (d.sales, d.sales.mecefStatus),
    (d.sales, d.sales.mecefQrRef),
  ],
  26: [(d.products, d.products.description)],
  27: [(d.products, d.products.syncStatus)],
  29: [
    (d.suppliers, d.suppliers.syncStatus),
    (d.suppliers, d.suppliers.isActive),
  ],
  30: [(d.customers, d.customers.email), (d.customers, d.customers.syncStatus)],
  31: [
    (d.customerAdvances, d.customerAdvances.treasuryAccountId),
    (d.customerAdvances, d.customerAdvances.paymentMode),
    (d.customerAdvances, d.customerAdvances.motif),
    (d.customerAdvances, d.customerAdvances.deviceId),
    (d.customerAdvances, d.customerAdvances.syncStatus),
  ],
  32: [
    (d.purchases, d.purchases.returnedAt),
    (d.purchases, d.purchases.supplierCredit),
  ],
  33: [(d.mails, d.mails.isActive), (d.mails, d.mails.syncStatus)],
  34: [(d.mails, d.mails.knownByServer)],
  35: [
    (d.archivedDocuments, d.archivedDocuments.isActive),
    (d.archivedDocuments, d.archivedDocuments.syncStatus),
    (d.archivedDocuments, d.archivedDocuments.knownByServer),
  ],
  36: [
    (d.administrativeDocuments, d.administrativeDocuments.isActive),
    (d.administrativeDocuments, d.administrativeDocuments.syncStatus),
    (d.administrativeDocuments, d.administrativeDocuments.knownByServer),
  ],
  37: [(d.accountingEntries, d.accountingEntries.createdAt)],
  // F0.95 — effectif par catégorie (lapins et porcs) et ventilation par sexe des fiches.
  38: [
    for (final c in [
      d.livestockDailyEntries.mortRepro,
      d.livestockDailyEntries.mortSevre,
      d.livestockDailyEntries.mortJeune,
      d.livestockDailyEntries.donRepro,
      d.livestockDailyEntries.donSevre,
      d.livestockDailyEntries.donJeune,
      d.livestockDailyEntries.passageSevreJeune,
      d.livestockDailyEntries.catDepartRepro,
      d.livestockDailyEntries.catDepartSevre,
      d.livestockDailyEntries.catDepartJeune,
      d.livestockDailyEntries.catEffRepro,
      d.livestockDailyEntries.catEffSevre,
      d.livestockDailyEntries.catEffJeune,
      d.livestockDailyEntries.catEff4,
      d.livestockDailyEntries.effectifM,
      d.livestockDailyEntries.effectifF,
      d.livestockDailyEntries.effectifSevres,
      d.livestockDailyEntries.effectifSmeres,
    ])
      (d.livestockDailyEntries, c),
  ],
  // Ticket 15.46 — transferts entre bandes : colonnes dérivées des fiches, bande d'origine.
  39: [
    for (final c in [
      d.livestockDailyEntries.transfertEntree,
      d.livestockDailyEntries.transfertSortie,
      d.livestockDailyEntries.transfertEntreeRepro,
      d.livestockDailyEntries.transfertEntreeSevre,
      d.livestockDailyEntries.transfertEntreeJeune,
      d.livestockDailyEntries.transfertSortieRepro,
      d.livestockDailyEntries.transfertSortieSevre,
      d.livestockDailyEntries.transfertSortieJeune,
    ])
      (d.livestockDailyEntries, c),
    (d.livestockLots, d.livestockLots.lotSourceId),
  ],
  // Ticket H2 — instant de la dernière synchronisation aboutie.
  40: [(d.syncState, d.syncState.lastSucceededAt)],
  // Ticket H9b (D-H9) — Paramètres Élevage modifiables au poste : archivage logique, statut d'envoi, instant
  // de saisie ; délai du rappel des soins ; instant de création de la prophylaxie (tri du web, H9).
  42: [
    (d.feedRationStandards, d.feedRationStandards.isActive),
    (d.feedRationStandards, d.feedRationStandards.syncStatus),
    (d.feedRationStandards, d.feedRationStandards.updatedAt),
    (d.prophylaxisScheduleStandards, d.prophylaxisScheduleStandards.isActive),
    (
      d.prophylaxisScheduleStandards,
      d.prophylaxisScheduleStandards.syncStatus,
    ),
    (d.prophylaxisScheduleStandards, d.prophylaxisScheduleStandards.updatedAt),
    (d.prophylaxisScheduleStandards, d.prophylaxisScheduleStandards.createdAt),
    (d.feedTypes, d.feedTypes.isActive),
    (d.feedTypes, d.feedTypes.syncStatus),
    (d.feedTypes, d.feedTypes.updatedAt),
    (d.elevageNumberingSettings, d.elevageNumberingSettings.syncStatus),
    (d.elevageNumberingSettings, d.elevageNumberingSettings.updatedAt),
    (d.companySettings, d.companySettings.rappelSoinsJours),
    (d.companySettings, d.companySettings.syncStatus),
    (d.companySettings, d.companySettings.updatedAt),
  ],
  // Ticket U3 (D-U3) — archivage logique des soins au poste comme au web.
  43: [(d.veterinaryRecords, d.veterinaryRecords.isActive)],
  // Ticket U10 — colonnes de la fiche reçues pour le Rapport Élevage (Tableau 2, CA Ventes du Lot).
  45: [
    (d.livestockDailyEntries, d.livestockDailyEntries.venteSexe),
    (d.livestockDailyEntries, d.livestockDailyEntries.venteMontant),
    (d.livestockDailyEntries, d.livestockDailyEntries.treatmentProductId),
    (d.livestockDailyEntries, d.livestockDailyEntries.treatmentDose),
    (d.livestockDailyEntries, d.livestockDailyEntries.symptomes),
  ],
  // Ticket S-T10 — quantité comptée d'un inventaire.
  46: [(d.stockAdjustments, d.stockAdjustments.countedQuantity)],
  // Ticket U13 — archivage des dépenses, descendu du serveur.
  47: [(d.expenses, d.expenses.isActive)],
  // Ticket U14 — statut et écriture comptable des dépenses (badge, filtre, règle de modification du web).
  48: [
    (d.expenses, d.expenses.status),
    (d.expenses, d.expenses.accountingEntryId),
  ],
  // Ticket BS1 — bandes saisies au poste : statut d'envoi et correction d'effectif.
  49: [
    (d.livestockLots, d.livestockLots.syncStatus),
    (d.livestockLots, d.livestockLots.effectifCorrige),
  ],
  // Ticket BS-Q7 — restauration d'une bande archivée, à envoyer.
  50: [(d.livestockLots, d.livestockLots.restauree)],
  // Ticket BS3 — reproducteurs nominatifs saisis au poste : identifiant d'espèce, statut d'envoi, instant de saisie.
  51: [
    (d.animals, d.animals.speciesId),
    (d.animals, d.animals.syncStatus),
    (d.animals, d.animals.updatedAt),
  ],
  // Ticket MAIL1 — palier de DONNÉES (adresses e-mail du nouveau domaine) : aucune table ni colonne ajoutée.
  52: [],
  // Ticket DEV — table `quotes` créée (aucune colonne ajoutée à une table existante).
  53: [],
  // Tickets AV1 / AV2 — table `credit_notes` créée (aucune colonne ajoutée à une table existante).
  54: [],
  // Ticket DEP4 — l'en-tête d'une dépense à plusieurs lignes (mode, centre de coût, fournisseur, bénéficiaire, auteur,
  // refus de la pièce) ; la transformation 1 en-tête = 1 ligne est vérifiée par `depenses_multilignes_test.dart`.
  56: [
    (d.expenses, d.expenses.paymentMode),
    (d.expenses, d.expenses.costCenterId),
    (d.expenses, d.expenses.supplierId),
    (d.expenses, d.expenses.beneficiary),
    (d.expenses, d.expenses.createdBy),
    (d.expenses, d.expenses.ecritureRefus),
  ],
  // Ticket ARC3 — deux tables créées (aucune colonne ajoutée à une table existante).
  58: [],
};

/// Description du schéma réel lue dans SQLite, indépendante de l'ordre des colonnes
/// (un `addColumn` ajoute en fin de table, une création neuve dans l'ordre déclaré).
Future<Map<String, Object>> _schemaReel(AppDatabase d) async {
  Future<List<Map<String, Object?>>> lire(String requete) async => [
    for (final l in await d.customSelect(requete).get()) l.data,
  ];

  final tables = [
    for (final l in await lire(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      l['name'] as String,
  ];
  final index = [
    for (final l in await lire(
      "SELECT name, tbl_name FROM sqlite_master WHERE type = 'index' "
      'ORDER BY name',
    ))
      '${l['tbl_name']}.${l['name']}',
  ];
  final colonnes = <String, Object>{};
  for (final t in tables) {
    final cols = [
      for (final c in await lire('PRAGMA table_info("$t")'))
        '${c['name']}|${c['type']}|notnull=${c['notnull']}'
            '|defaut=${c['dflt_value']}|pk=${c['pk']}',
    ]..sort();
    final cles = [
      for (final f in await lire('PRAGMA foreign_key_list("$t")'))
        '${f['from']}->${f['table']}.${f['to']}',
    ]..sort();
    colonnes[t] = {'colonnes': cols, 'cles': cles};
  }
  return {'tables': tables, 'index': index, 'detail': colonnes};
}

/// Construit, dans [fichier], une base en forme vN et l'ouvre avec l'application :
/// la migration N → courante s'exécute au premier accès.
Future<AppDatabase> _baseMigreeDepuis(int n, File fichier) async {
  final neuve = AppDatabase.forTesting(NativeDatabase(fichier));
  final aRetirerTables = <String>[];
  final aRetirerColonnes = <(String, String)>[];
  _tablesCreees(neuve).forEach((version, tables) {
    if (version > n) {
      aRetirerTables.addAll(tables.map((t) => t.actualTableName));
    }
  });
  _colonnesAjoutees(neuve).forEach((version, paires) {
    if (version > n) {
      for (final (table, colonne) in paires) {
        aRetirerColonnes.add((table.actualTableName, colonne.name));
      }
    }
  });
  // Forcer la création du schéma courant.
  await neuve.customSelect('SELECT 1').get();
  await neuve.close();

  return AppDatabase.forTesting(
    NativeDatabase(
      fichier,
      setup: (raw) {
        for (final t in aRetirerTables) {
          raw.execute('DROP TABLE "$t"');
        }
        for (final (t, c) in aRetirerColonnes) {
          // Table déjà retirée (créée après N) : sa colonne part avec elle.
          if (aRetirerTables.contains(t)) continue;
          raw.execute('ALTER TABLE "$t" DROP COLUMN "$c"');
        }
        raw.execute('PRAGMA user_version = $n');
      },
    ),
  );
}

void main() {
  late Directory dossier;

  setUpAll(() {
    // Plusieurs instances successives sur des fichiers distincts : VOULU.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dossier = Directory.systemTemp.createTempSync('agrierp_migr_');
  });
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    try {
      dossier.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('⚠️ la chaîne 52 → 53 (quotes, DEV) → 54 (credit_notes, AV) → 56 (dépenses, DEP4) est complète ; le 55 est inutilisé', () {
    final d = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(d.close);
    expect(d.schemaVersion, 58, reason: 'le 55 (unicité) n\'a pas pris de palier Drift : 54 → 56 sans trou ; ARC3 : 56 → 58');
    expect(_tablesCreees(d)[58], [d.corbeilleElements, d.corbeilleDemandes]);
    expect(_tablesCreees(d)[56], [d.expenseLines, d.costCenters]);
    expect(_tablesCreees(d).containsKey(55) || _colonnesAjoutees(d).containsKey(55), isFalse);
    expect(_tablesCreees(d)[53], [d.quotes]);
    expect(_tablesCreees(d)[54], [d.creditNotes]);
    final source = File('lib/core/database/app_database.dart').readAsStringSync();
    expect(source, contains('if (from < 53) {'));
    expect(source, contains('if (from < 54) {'));
    expect(source, contains('if (from < 56) {'));
    expect(source, contains('if (from < 58) {'));
    expect(source, isNot(contains('if (from < 55) {')));
  });

  test('l’historique du test couvre le palier le plus récent du schéma', () {
    final d = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(d.close);
    final derniere = [
      ..._tablesCreees(d).keys,
      ..._colonnesAjoutees(d).keys,
    ].reduce((a, b) => a > b ? a : b);
    // Un nouveau palier non reporté ici rendrait les bases « vN » fausses.
    expect(derniere, d.schemaVersion);
  });


  group('migration vers la version courante depuis chaque version', () {
    late Map<String, Object> reference;

    setUpAll(() async {
      final d = AppDatabase.forTesting(NativeDatabase.memory());
      reference = await _schemaReel(d);
      await d.close();
    });

    // Toutes les versions de départ possibles, pas seulement N-1.
    final courante = AppDatabase.forTesting(NativeDatabase.memory());
    final versionCourante = courante.schemaVersion;
    courante.close();

    for (var n = 1; n < versionCourante; n++) {
      test('⚠️ une base v$n migre jusqu’à v$versionCourante sans erreur et '
          'obtient exactement le schéma d’une base neuve', () async {
        final fichier = File('${dossier.path}${Platform.pathSeparator}v$n.db');
        final db = await _baseMigreeDepuis(n, fichier);
        try {
          final obtenu = await _schemaReel(db);
          expect(obtenu['tables'], reference['tables']);
          expect(obtenu['index'], reference['index']);
          expect(obtenu['detail'], reference['detail']);
          final version = await db
              .customSelect('PRAGMA user_version')
              .getSingle();
          expect(version.read<int>('user_version'), versionCourante);
        } finally {
          await db.close();
        }
      });
    }
  });

  test('⚠️ aucun palier n’appelle `m.addColumn` en direct : un `createTable` '
      'antérieur a pu poser la colonne (garde-fou de source)', () {
    final source = File(
      'lib/core/database/app_database.dart',
    ).readAsStringSync();
    final appels = RegExp(r'\bm\.addColumn\(').allMatches(source).length;
    // Une seule occurrence : celle de l'aide `_ajouterColonneSiAbsente`.
    expect(appels, 1);
  });
}
