import 'dart:io';

import 'package:agrierp/core/comptabilite/exercice_de_saisie.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket EX6 (EF7 du PRD `docs/prd/exercices-comptables.md`) — REFUS LOCAL AU POSTE, SUR TOUS LES ÉCRANS DE SAISIE,
/// de ce que le serveur refuse pour cause d'exercice (ticket EX5).
///
/// Décor commun, AUJOURD'HUI = mardi 20/10/2026 :
///  - exercice 2024 CLÔTURÉ (01/01/2024 → 31/12/2024) ;
///  - exercice 2025 OUVERT (01/01/2025 → 31/12/2025) — l'exercice ouvert le plus récent ;
///  - 2026 n'existe pas encore au poste (poste resté hors ligne depuis le 1er janvier) ;
///  - 2023 n'existe pas, et 2022 non plus.
///
/// Quatre jours par écran :
///  - 20/12/2024, dans l'exercice CLOS → refus, motif R4 « L'exercice 2024 est clôturé : … » ;
///  - 15/06/2023, qu'AUCUN exercice ne couvre (2022 n'existe pas : pas de filet) → refus « Aucun exercice comptable ne
///    couvre … » pour une saisie qui produit une écriture, ACCEPTÉ pour une saisie « exercice clos seulement »
///    (`refusExerciceClos` du serveur : ajout de stock, inventaire en excédent, fiche d'élevage, modification et
///    archivage d'une dépense) ;
///  - 10/01/2026, FILET R2 (2025 est l'exercice ouvert le plus récent, seul ouvert) → accepté : le serveur créera 2026 ;
///  - 15/03/2025, dans l'exercice OUVERT → accepté.
/// Plus : aucun exercice connu au poste → accepté (le serveur jugera).
///
/// ⚠️ Les motifs attendus sont des LITTÉRAUX écrits à la main, jamais produits par le code testé. Un refus doit venir
/// AVANT toute écriture : chaque refus vérifie que la table visée n'a pas bougé.
///
/// ⚠️ Épreuve de mutation : retirer l'appel à `ExerciceDeSaisie` d'un dépôt fait rougir ses cas « clos » et « aucun ».
const _clos = 'L\'exercice 2024 est clôturé : aucune saisie ne peut être datée du 20/12/2024.';
const _aucun =
    'Aucun exercice comptable ne couvre le 15/06/2023. '
    'Ouvrez l\'exercice 2023 (Comptabilité › Clôture d\'exercice).';

final _jourClos = DateTime(2024, 12, 20);
final _jourAucun = DateTime(2023, 6, 15);
final _jourFilet = DateTime(2026, 1, 10);
final _jourOuvert = DateTime(2025, 3, 15);
final _aujourdhui = DateTime(2026, 10, 20, 10, 15);

String _uuid(String cle) {
  final hex = cle.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  final h = hex.padRight(32, '0').substring(0, 32);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-8${h.substring(17, 20)}-${h.substring(20, 32)}';
}

Future<void> _exercice(AppDatabase db, int annee, String statut) => db
    .into(db.fiscalYears)
    .insert(
      FiscalYearsCompanion.insert(
        id: _uuid('ex$annee'),
        year: annee,
        startDate: Value(DateTime(annee)),
        endDate: Value(DateTime(annee, 12, 31)),
        status: Value(statut),
      ),
    );

Future<void> _exercicesDuDecor(AppDatabase db) async {
  await _exercice(db, 2024, 'cloture');
  await _exercice(db, 2025, 'ouvert');
}

/// Données de base que tous les écrans peuvent viser.
Future<void> _referentiels(AppDatabase db) async {
  await db
      .into(db.suppliers)
      .insert(SuppliersCompanion.insert(id: _uuid('f1'), name: 'Provenderie du Plateau'));
  await db
      .into(db.treasuryAccounts)
      .insert(TreasuryAccountsCompanion.insert(id: _uuid('t1'), label: 'Caisse principale', balance: const Value(500000)));
  await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: _uuid('p1'),
          sku: 'ALI-001',
          name: 'Provende ponte',
          unit: 'sac',
          pricingMode: 'fixe',
          stockQty: const Value(30),
        ),
      );
  // Un achat du serveur (PMP connu : 18 500 F le sac), ancien, pour le retour et l'inventaire.
  await db
      .into(db.purchases)
      .insert(
        PurchasesCompanion.insert(
          id: _uuid('a1'),
          deviceId: 'serveur',
          updatedAt: DateTime(2023, 6, 1),
          syncStatus: const Value(SyncStatus.synced),
          supplierId: _uuid('f1'),
          paymentMode: 'especes',
          total: 185000,
          purchaseDate: DateTime(2023, 6, 1),
        ),
      );
  await db
      .into(db.purchaseLines)
      .insert(
        PurchaseLinesCompanion.insert(
          id: _uuid('l1'),
          purchaseId: _uuid('a1'),
          productId: _uuid('p1'),
          qty: 10,
          unitPrice: 18500,
        ),
      );
  await db
      .into(db.supplierCredits)
      .insert(SupplierCreditsCompanion.insert(supplierId: _uuid('f1'), openCredit: 40000));
  await db
      .into(db.payables)
      .insert(PayablesCompanion.insert(id: _uuid('d1'), supplierId: _uuid('f1'), amount: 90000));
  await db.into(db.customers).insert(CustomersCompanion.insert(id: _uuid('c1'), name: 'Restaurant Le Baobab'));
  await db
      .into(db.receivables)
      .insert(ReceivablesCompanion.insert(id: _uuid('r1'), customerId: _uuid('c1'), amount: 60000));
  await db
      .into(db.customerAdvances)
      .insert(
        CustomerAdvancesCompanion.insert(
          id: _uuid('v1'),
          customerId: _uuid('c1'),
          amount: 50000,
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
  await db.into(db.expenseCategories).insert(ExpenseCategoriesCompanion.insert(label: 'Énergie'));
  await db
      .into(db.livestockLots)
      .insert(LivestockLotsCompanion.insert(id: _uuid('b1'), code: 'PON-01', speciesId: _uuid('esp')));
}

/// Une dépense déjà au poste, datée de [jour], pour la modification et l'archivage.
Future<void> _depenseExistante(AppDatabase db, DateTime jour) => db
    .into(db.expenses)
    .insert(
      ExpensesCompanion.insert(
        id: _uuid('e1'),
        deviceId: 'serveur',
        syncStatus: const Value(SyncStatus.synced),
        updatedAt: jour,
        expenseDate: jour,
        label: 'Facture SBEE',
        category: 'Énergie',
        amount: 25000,
        treasuryAccountId: _uuid('t1'),
      ),
    );

/// Un écran de saisie : sa règle, la table qu'il écrit (refus = rien d'écrit), et le geste de saisie daté de [jour].
class _Ecran {
  const _Ecran(
    this.nom,
    this.regle,
    this.compter,
    this.saisir, {
    this.preparer,
  });

  final String nom;
  final RegleExercice regle;
  final Future<int> Function(AppDatabase db) compter;
  final Future<void> Function(AppDatabase db, DateTime jour) saisir;
  final Future<void> Function(AppDatabase db, DateTime jour)? preparer;
}

Future<int> _lignes<T extends Table, R>(AppDatabase db, TableInfo<T, R> table) async =>
    (await db.select(table).get()).length;

Future<int> _enAttente(AppDatabase db) async => (await (db.select(
  db.expenses,
)..where((e) => e.syncStatus.equalsValue(SyncStatus.pending))).get()).length;

final _ecrans = <_Ecran>[
  _Ecran(
    'Achats & Commandes — achat',
    RegleExercice.ecriture,
    (db) => _lignes(db, db.purchases),
    (db, jour) async {
      final produit = await (db.select(db.products)..where((p) => p.id.equals(_uuid('p1')))).getSingle();
      await AchatsRepository(database: db, identifiantPoste: 'poste-test', horloge: () => _aujourdhui).enregistrer(
        fournisseurId: _uuid('f1'),
        lignes: [LigneSaisieAchat(produit: produit, quantite: 2, prixUnitaire: 18500)],
        modePaiement: 'especes',
        compteId: _uuid('t1'),
        montantPaye: 37000,
        date: jour,
      );
    },
  ),
  _Ecran(
    'Liste d’Achats — retour fournisseur',
    RegleExercice.ecriture,
    (db) => _lignes(db, db.purchaseReturns),
    (db, jour) => AchatsRepository(
      database: db,
      identifiantPoste: 'poste-test',
      horloge: () => _aujourdhui,
    ).enregistrerRetour(achatId: _uuid('a1'), motif: 'Marchandise avariée', date: jour),
  ),
  _Ecran(
    'Liste d’Achats — remboursement fournisseur',
    RegleExercice.ecriture,
    (db) => _lignes(db, db.supplierRefunds),
    (db, jour) => AchatsRepository(
      database: db,
      identifiantPoste: 'poste-test',
      horloge: () => _aujourdhui,
    ).enregistrerRemboursement(fournisseurId: _uuid('f1'), montant: 10000, date: jour, compteId: _uuid('t1')),
  ),
  _Ecran(
    'Fournisseurs — règlement fournisseur',
    RegleExercice.ecriture,
    (db) => _lignes(db, db.supplierPayments),
    (db, jour) => FournisseursRepository(
      database: db,
      deviceId: 'poste-test',
    ).enregistrerReglement(fournisseurId: _uuid('f1'), montant: 20000, compteId: _uuid('t1'), date: jour),
  ),
  _Ecran(
    'Clients & Créances — avance client',
    RegleExercice.ecriture,
    (db) => _lignes(db, db.customerAdvances),
    (db, jour) => ClientsCreancesRepository(database: db, deviceId: 'poste-test').enregistrerAvance(
      clientId: _uuid('c1'),
      montant: 15000,
      compteId: _uuid('t1'),
      motif: 'Commande de poulets',
      date: jour,
    ),
  ),
  _Ecran(
    'Clients & Créances — imputation d’avance',
    RegleExercice.ecriture,
    (db) => _lignes(db, db.advanceImputations),
    (db, jour) => ClientsCreancesRepository(
      database: db,
      deviceId: 'poste-test',
    ).imputerAvance(avanceId: _uuid('v1'), creanceId: _uuid('r1'), montant: 10000, date: jour),
  ),
  _Ecran(
    'Saisie des Dépenses — nouvelle dépense',
    RegleExercice.ecriture,
    (db) => _lignes(db, db.expenses),
    (db, jour) => DepensesRepository(database: db, deviceId: 'poste-test').enregistrer(
      date: jour,
      libelle: 'Carburant groupe',
      categorie: 'Énergie',
      montant: 12000,
      compteTresorerieId: _uuid('t1'),
    ),
  ),
  _Ecran(
    'Saisie des Dépenses — modification (nouvelle date)',
    RegleExercice.closSeulement,
    _enAttente,
    (db, jour) => DepensesRepository(database: db, deviceId: 'poste-test').enregistrer(
      date: jour,
      libelle: 'Facture SBEE',
      categorie: 'Énergie',
      montant: 25000,
      compteTresorerieId: _uuid('t1'),
      idEnModification: _uuid('e1'),
    ),
    preparer: (db, _) => _depenseExistante(db, DateTime(2025, 2, 10)),
  ),
  _Ecran(
    'Saisie des Dépenses — archivage',
    RegleExercice.closSeulement,
    _enAttente,
    (db, jour) => DepensesRepository(database: db, deviceId: 'poste-test').archiver(_uuid('e1')),
    preparer: _depenseExistante,
  ),
  _Ecran(
    'Gestion des Stocks — ajout de stock',
    RegleExercice.closSeulement,
    (db) => _lignes(db, db.stockAdjustments),
    (db, jour) => StocksRepository(
      database: db,
      deviceId: 'poste-test',
      horloge: () => _aujourdhui,
    ).ajouterStock(date: jour, productId: _uuid('p1'), quantite: '5'),
  ),
  _Ecran(
    'Gestion des Stocks — inventaire, manquant (perte comptabilisée)',
    RegleExercice.ecriture,
    (db) => _lignes(db, db.stockAdjustments),
    (db, jour) => StocksRepository(database: db, deviceId: 'poste-test', horloge: () => _aujourdhui).enregistrerEcart(
      productId: _uuid('p1'),
      stockPhysique: 25,
      motif: 'Sacs éventrés',
      quand: DateTime(jour.year, jour.month, jour.day, 10),
    ),
  ),
  _Ecran(
    'Gestion des Stocks — inventaire, excédent (aucune écriture)',
    RegleExercice.closSeulement,
    (db) => _lignes(db, db.stockAdjustments),
    (db, jour) => StocksRepository(database: db, deviceId: 'poste-test', horloge: () => _aujourdhui).enregistrerEcart(
      productId: _uuid('p1'),
      stockPhysique: 33,
      motif: 'Recomptage',
      quand: DateTime(jour.year, jour.month, jour.day, 10),
    ),
  ),
  _Ecran(
    'Fiches d’élevage — fiche du jour (Q3)',
    RegleExercice.closSeulement,
    (db) => _lignes(db, db.livestockDailyEntries),
    (db, jour) => FicheJournaliereRepository(
      database: db,
      deviceId: 'poste-test',
    ).enregistrer(lotId: _uuid('b1'), jour: jour, achat: 0, ne: 0, mort: 1, don: 0),
  ),
];

Matcher _refuse(String motif) => throwsA(isA<RefusExercice>().having((e) => e.motif, 'motif', motif));

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await _referentiels(db);
  });

  tearDown(() => db.close());

  for (final ecran in _ecrans) {
    group(ecran.nom, () {
      Future<void> preparer(DateTime jour, {bool exercices = true}) async {
        if (exercices) await _exercicesDuDecor(db);
        await ecran.preparer?.call(db, jour);
      }

      test('exercice CLOS → refusé avec le motif exact du serveur, rien n’est écrit', () async {
        await preparer(_jourClos);
        final avant = await ecran.compter(db);
        await expectLater(ecran.saisir(db, _jourClos), _refuse(_clos));
        expect(await ecran.compter(db), avant);
      });

      if (ecran.regle == RegleExercice.ecriture) {
        test('aucun exercice ne couvre le jour → refusé (« Aucun exercice comptable ne couvre … »)', () async {
          await preparer(_jourAucun);
          final avant = await ecran.compter(db);
          await expectLater(ecran.saisir(db, _jourAucun), _refuse(_aucun));
          expect(await ecran.compter(db), avant);
        });
      } else {
        test('aucun exercice ne couvre le jour → ACCEPTÉ, comme `refusExerciceClos` du serveur', () async {
          await preparer(_jourAucun);
          await ecran.saisir(db, _jourAucun);
        });
      }

      test('filet R2 : jour de N+1 alors que N est l’exercice ouvert le plus récent → accepté', () async {
        await preparer(_jourFilet);
        await ecran.saisir(db, _jourFilet);
      });

      test('jour dans un exercice OUVERT → accepté', () async {
        await preparer(_jourOuvert);
        await ecran.saisir(db, _jourOuvert);
      });

      test('aucun exercice connu au poste → accepté (le serveur jugera à l’envoi)', () async {
        await preparer(_jourClos, exercices: false);
        await ecran.saisir(db, _jourClos);
      });
    });
  }

  group('Saisie des Dépenses — l’exercice de la date D’ORIGINE compte aussi (`SaisieDepenseAction::modifier`)', () {
    test('une dépense d’un exercice clos ne se modifie pas, même vers un exercice ouvert', () async {
      await _exercicesDuDecor(db);
      await _depenseExistante(db, _jourClos);
      await expectLater(
        DepensesRepository(database: db, deviceId: 'poste-test').enregistrer(
          date: _jourOuvert,
          libelle: 'Facture SBEE corrigée',
          categorie: 'Énergie',
          montant: 25000,
          compteTresorerieId: _uuid('t1'),
          idEnModification: _uuid('e1'),
        ),
        _refuse(_clos),
      );
      expect(await _enAttente(db), 0);
    });
  });

  group('Caisse — vente datée (point de passage commun)', () {
    CaisseRepository caisse() => CaisseRepository(database: db, deviceId: 'poste-test', maintenant: () => _aujourdhui);

    test('exercice clos → « Vente refusée : » + le motif R4, première lettre en minuscule', () async {
      await _exercicesDuDecor(db);
      expect(
        await caisse().refusDeDate(_jourClos),
        'Vente refusée : l\'exercice 2024 est clôturé : aucune saisie ne peut être datée du 20/12/2024.',
      );
    });

    test('aucun exercice → « Vente refusée : aucun exercice comptable ne couvre … »', () async {
      await _exercicesDuDecor(db);
      expect(
        await caisse().refusDeDate(_jourAucun),
        'Vente refusée : aucun exercice comptable ne couvre le 15/06/2023. '
        'Ouvrez l\'exercice 2023 (Comptabilité › Clôture d\'exercice).',
      );
    });

    test('filet R2 et exercice ouvert → acceptés ; aucun exercice connu → accepté', () async {
      await _exercicesDuDecor(db);
      expect(await caisse().refusDeDate(_jourFilet), isNull);
      expect(await caisse().refusDeDate(_jourOuvert), isNull);
      await db.delete(db.fiscalYears).go();
      expect(await caisse().refusDeDate(_jourClos), isNull);
    });
  });

  group('ExerciceDeSaisie — la règle (sans écran)', () {
    FiscalYear ex(int annee, String statut) => FiscalYear(
      id: _uuid('ex$annee'),
      year: annee,
      startDate: DateTime(annee),
      endDate: DateTime(annee, 12, 31),
      status: statut,
    );

    test('le filet R2 ne joue pas avant le 1er janvier de N+1 (comme `refusOuverture`)', () {
      final exercices = [ex(2025, 'ouvert')];
      // Saisie d'un jour FUTUR de 2026 faite le 31/12/2025 : le serveur refuserait (« ne peut s'ouvrir qu'à partir du
      // 01/01/2026 »), puis refus R4.
      expect(
        ExerciceDeSaisie.juger(
          exercices,
          DateTime(2026, 1, 2),
          regle: RegleExercice.ecriture,
          aujourdhui: DateTime(2025, 12, 31, 23),
        ),
        'Aucun exercice comptable ne couvre le 02/01/2026. '
        'Ouvrez l\'exercice 2026 (Comptabilité › Clôture d\'exercice).',
      );
      expect(
        ExerciceDeSaisie.juger(
          exercices,
          DateTime(2026, 1, 2),
          regle: RegleExercice.ecriture,
          aujourdhui: DateTime(2026, 1, 1),
        ),
        isNull,
      );
    });

    test('le filet R2 ne joue pas si N est clos, ni si deux exercices sont déjà ouverts, ni pour N+2', () {
      expect(
        ExerciceDeSaisie.filetOuvrirait(2026, [ex(2025, 'cloture')], _aujourdhui),
        isFalse,
      );
      expect(
        ExerciceDeSaisie.filetOuvrirait(2026, [ex(2024, 'ouvert'), ex(2025, 'ouvert')], _aujourdhui),
        isFalse,
      );
      expect(ExerciceDeSaisie.filetOuvrirait(2027, [ex(2025, 'ouvert')], DateTime(2027, 2, 1)), isFalse);
      expect(ExerciceDeSaisie.filetOuvrirait(2026, [ex(2025, 'ouvert')], _aujourdhui), isTrue);
    });

    test('bornes du calendrier : début du plus ancien exercice OUVERT, lendemain du dernier exercice CLOS', () {
      final exercices = [ex(2023, 'cloture'), ex(2024, 'cloture'), ex(2025, 'ouvert'), ex(2026, 'ouvert')];
      expect(ExerciceDeSaisie.premierJourDe(exercices), DateTime(2025));
      expect(ExerciceDeSaisie.premierJourDe(exercices, regle: RegleExercice.closSeulement), DateTime(2025));
      expect(ExerciceDeSaisie.premierJourDe(const []), isNull);
      expect(ExerciceDeSaisie.premierJourDe([ex(2025, 'ouvert')], regle: RegleExercice.closSeulement), isNull);
    });
  });

  group('parité avec le serveur', () {
    test('les deux motifs R4 sont écrits dans le PHP exactement comme au poste', () {
      final aucun = File('$dossierLaravel/app/Exceptions/NoOpenFiscalYearException.php');
      final clos = File('$dossierLaravel/app/Exceptions/ClosedFiscalYearException.php');
      final vente = File('$dossierLaravel/app/Actions/VerifySaleDateAction.php');
      if (!aucun.existsSync() || !clos.existsSync() || !vente.existsSync()) {
        markTestSkipped('SAUT : dépôt Laravel absent ($dossierLaravel)');
        return;
      }

      // Le gabarit de `message()` de chaque exception, variables PHP remplacées par celles du poste.
      String gabarit(File f) {
        final m = RegExp(r'function message\([^)]*\): string\s*\{\s*return "([^"]+)";').firstMatch(f.readAsStringSync());
        expect(m, isNotNull, reason: '${f.path} : `message()` introuvable — le garde-fou doit être mis à jour');
        return m!.group(1)!;
      }

      expect(
        gabarit(aucun).replaceAll(r'{$jourFr}', '10/01/2027').replaceAll(r'{$annee}', '2027'),
        ExerciceDeSaisie.messageAucunExercice(DateTime(2027, 1, 10)),
      );
      expect(
        gabarit(clos).replaceAll(r'{$annee}', '2026').replaceAll(r'{$jourFr}', '20/12/2026'),
        ExerciceDeSaisie.messageExerciceClos(2026, DateTime(2026, 12, 20)),
      );
      expect(vente.readAsStringSync(), contains("return 'Vente refusée : '.mb_strtolower(mb_substr(\$motif, 0, 1))"));
    });

    test('les écrans du web préfixent l’achat refusé comme le poste (« Achat refusé : »)', () {
      final achat = File('$dossierLaravel/app/Livewire/Achats/EnregistrerAchat.php');
      if (!achat.existsSync()) {
        markTestSkipped('SAUT : dépôt Laravel absent ($dossierLaravel)');
        return;
      }
      expect(achat.readAsStringSync(), contains("message: 'Achat refusé : '.\$e->getMessage()"));
    });

    test('PARITÉ EXÉCUTÉE : `exerciceOuvertPour` et `refusExerciceClos` du PHP rendent le verdict du poste', () {
      final saut = sautSansPhp();
      if (saut != null) {
        markTestSkipped(saut);
        return;
      }

      // Décors d'exercices (jamais vide : « aucun exercice connu » est un écart VOULU, vérifié plus haut).
      const decors = <List<List<Object>>>[
        [
          [2024, 'cloture'],
          [2025, 'ouvert'],
        ],
        [
          [2024, 'ouvert'],
          [2025, 'ouvert'],
        ],
        [
          [2025, 'cloture'],
        ],
        [
          [2025, 'ouvert'],
        ],
        [
          [2024, 'cloture'],
          [2025, 'cloture'],
          [2026, 'ouvert'],
        ],
        [
          [2023, 'cloture'],
          [2025, 'ouvert'],
        ],
      ];
      const jours = [
        '2023-06-15',
        '2024-01-01',
        '2024-12-20',
        '2024-12-31',
        '2025-01-01',
        '2025-03-15',
        '2025-12-31',
        '2026-01-01',
        '2026-01-10',
        '2027-02-05',
      ];
      const aujourdhuis = ['2025-12-31', '2026-01-01', '2026-10-20', '2027-03-01'];

      final cas = <Map<String, Object>>[];
      for (final (i, decor) in decors.indexed) {
        for (final jour in jours) {
          for (final auj in aujourdhuis) {
            cas.add({'decor': i, 'jour': jour, 'aujourdhui': auj});
          }
        }
      }

      final verdicts =
          executerPhp(
                '<?php\n$amorceApplication\n'
                r'''
$entree = json_decode(file_get_contents($argv[1]), true);
$service = app(App\Services\AccountingEntryService::class);
$sortie = [];
foreach ($entree['cas'] as $cas) {
    Illuminate\Support\Facades\DB::beginTransaction();
    foreach ($entree['decors'][$cas['decor']] as [$annee, $statut]) {
        App\Models\FiscalYear::create(['year' => $annee, 'start_date' => "$annee-01-01", 'end_date' => "$annee-12-31", 'status' => $statut]);
    }
    Carbon\Carbon::setTestNow(Carbon\Carbon::parse($cas['aujourdhui'].' 12:00:00', 'Africa/Porto-Novo'));
    try {
        $service->exerciceOuvertPour($cas['jour']);
        $ecriture = null;
    } catch (App\Exceptions\NoOpenFiscalYearException|App\Exceptions\ClosedFiscalYearException $e) {
        $ecriture = $e->getMessage();
    }
    Illuminate\Support\Facades\DB::rollBack();

    Illuminate\Support\Facades\DB::beginTransaction();
    foreach ($entree['decors'][$cas['decor']] as [$annee, $statut]) {
        App\Models\FiscalYear::create(['year' => $annee, 'start_date' => "$annee-01-01", 'end_date' => "$annee-12-31", 'status' => $statut]);
    }
    $clos = $service->refusExerciceClos($cas['jour']);
    Illuminate\Support\Facades\DB::rollBack();

    $sortie[] = ['ecriture' => $ecriture, 'clos' => $clos];
}
echo json_encode($sortie);
''',
                {'decors': decors, 'cas': cas},
                application: true,
              )!
              as List;

      expect(verdicts, hasLength(cas.length));
      var compares = 0;
      for (final (i, c) in cas.indexed) {
        final exercices = [
          for (final e in decors[c['decor']! as int])
            FiscalYear(
              id: _uuid('ex${e[0]}'),
              year: e[0] as int,
              startDate: DateTime(e[0] as int),
              endDate: DateTime(e[0] as int, 12, 31),
              status: e[1] as String,
            ),
        ];
        final jour = DateTime.parse(c['jour']! as String);
        final auj = DateTime.parse('${c['aujourdhui']} 12:00:00');
        final php = verdicts[i] as Map;
        final contexte = 'décor ${c['decor']}, jour ${c['jour']}, aujourd’hui ${c['aujourdhui']}';
        expect(
          ExerciceDeSaisie.juger(exercices, jour, regle: RegleExercice.ecriture, aujourdhui: auj),
          php['ecriture'],
          reason: 'exerciceOuvertPour — $contexte',
        );
        expect(
          ExerciceDeSaisie.juger(exercices, jour, regle: RegleExercice.closSeulement, aujourdhui: auj),
          php['clos'],
          reason: 'refusExerciceClos — $contexte',
        );
        compares += 2;
      }
      // 6 décors × 10 jours × 4 « aujourd'hui » × 2 règles.
      expect(compares, 480);
    });
  });

  group('garde-fou : chaque dépôt de saisie passe par le point de passage commun', () {
    // Chaque fichier qui ÉCRIT une saisie que le serveur juge par exercice, et l'appel attendu. Un dépôt nouveau qui
    // écrirait l'une de ces tables sans passer par `ExerciceDeSaisie` rougirait ici.
    const depots = {
      'lib/features/ventes/caisse_repository.dart': 'ExerciceDeSaisie',
      'lib/features/achats/achats_repository.dart': 'ExerciceDeSaisie',
      'lib/features/achats/fournisseurs_repository.dart': 'ExerciceDeSaisie',
      'lib/features/achats/depenses_repository.dart': 'ExerciceDeSaisie',
      'lib/features/clients/clients_creances_repository.dart': 'ExerciceDeSaisie',
      'lib/features/stocks/stocks_repository.dart': 'ExerciceDeSaisie',
      'lib/features/elevage/fiche_journaliere_repository.dart': 'ExerciceDeSaisie',
    };
    const tables = [
      'db.sales)',
      'database.purchases)',
      'database.purchaseReturns)',
      'database.supplierRefunds)',
      'database.supplierPayments)',
      'database.customerAdvances)',
      'database.advanceImputations)',
      '_db.expenses)',
      'database.stockAdjustments)',
      '_db.livestockDailyEntries)',
    ];

    test('les dépôts connus appellent `ExerciceDeSaisie`', () {
      for (final MapEntry(key: chemin, value: appel) in depots.entries) {
        expect(File(chemin).readAsStringSync(), contains(appel), reason: chemin);
      }
    });

    test('aucun autre fichier de lib/features n’insère dans une table de saisie jugée par exercice', () {
      final fautifs = <String>[];
      for (final f in Directory('lib/features').listSync(recursive: true).whereType<File>()) {
        final chemin = f.path.replaceAll(r'\', '/');
        if (!chemin.endsWith('.dart') || depots.containsKey(chemin)) continue;
        final source = f.readAsStringSync();
        for (final t in tables) {
          if (source.contains('.into($t') || source.contains('.into(${t.replaceFirst('database.', 'db.')}')) {
            fautifs.add('$chemin → $t');
          }
        }
      }
      expect(fautifs, isEmpty);
    });
  });
}
