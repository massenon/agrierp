import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/agregats_coherence.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/sync/coherence_repository.dart';
import 'package:agrierp/features/sync/synchronisation_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket S-T6 (méthode TATACORA) — CONTRÔLE DE COHÉRENCE : nombre de lignes et total par table et par jour, au poste
/// et au serveur, comparés dans l'écran Synchronisation.
///
/// Les attendus sont des LITTÉRAUX calculés à la main (jeu ci-dessous), jamais produits par le code testé.
class _Connexion implements Connectivity {
  _Connexion(this.enLigne);

  bool enLigne;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [enLigne ? ConnectivityResult.wifi : ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

void main() {
  const poste = 'poste-test';
  const bande = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const autre = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';
  var n = 0;
  String uuid() => '00000000-0000-4000-8000-${(++n).toString().padLeft(12, '0')}';

  group('S-T6 — parité de la table de correspondance (PHP ↔ Dart)', () {
    final php = File('$dossierLaravel/app/Services/CoherenceSynchronisationService.php');

    test('chaque entrée de AGREGATS du serveur est celle du poste, dans le même ordre', () {
      if (!php.existsSync()) {
        markTestSkipped('agrierp_laravel introuvable (${php.path})');
        return;
      }
      final source = php.readAsStringSync();
      final bloc = RegExp(r'public const AGREGATS = \[\n(.*?)\n\s*\];', dotAll: true).firstMatch(source);
      expect(bloc, isNotNull, reason: 'AGREGATS introuvable dans le PHP');

      final ligne = RegExp(
        r"^\s*'(\w+)' => \['libelle' => '([^']*)', 'jour' => \[([^\]]*)\], "
        r"'montant' => '(\w+)', 'filtre' => (null|\[([^\]]*)\])\],$",
      );
      String sansGuillemets(String s) => s.trim().replaceAll("'", '');

      final cotePhp = <String>[];
      for (final brute in bloc!.group(1)!.split('\n')) {
        if (brute.trim().isEmpty) continue;
        final m = ligne.firstMatch(brute);
        expect(m, isNotNull, reason: 'ligne de AGREGATS hors format (le test la lit au texte) : $brute');
        final filtre = m!.group(6) == null
            ? 'null'
            : m.group(6)!.split(',').map(sansGuillemets).join('|');
        cotePhp.add(
          '${m.group(1)} ; ${m.group(2)} ; ${m.group(3)!.split(',').map(sansGuillemets).join('|')} ; '
          '${m.group(4)} ; $filtre',
        );
      }

      final coteDart = [
        for (final a in AgregatsCoherence.tables)
          '${a.table} ; ${a.libelle} ; ${a.jour.join('|')} ; ${a.montant} ; '
              '${a.filtre == null ? 'null' : '${a.filtre!.$1}|${a.filtre!.$2}|${a.filtre!.$3}'}',
      ];

      expect(coteDart, cotePhp);
      expect(cotePhp, hasLength(8), reason: "ticket U13 : les dépenses y entrent");
    });

    test('chaque table et chaque colonne de la correspondance existe au poste', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      for (final a in AgregatsCoherence.tables) {
        final table = db.allTables.where((t) => t.actualTableName == a.table);
        expect(table, hasLength(1), reason: 'table ${a.table} absente du poste');
        final colonnes = table.single.columnsByName;
        for (final c in [a.jour.first, a.montant, ?a.filtre?.$1]) {
          expect(colonnes.containsKey(c), isTrue, reason: '${a.table}.$c absente du poste');
        }
      }
    });
  });

  group('S-T6 — comptes du poste', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      final saisie = DateTime(2026, 10, 19, 12);

      Future<void> vente(DateTime le, double total, {SyncStatus statut = SyncStatus.synced, String etat = 'validee'}) =>
          db.into(db.sales).insert(
            SalesCompanion.insert(
              id: uuid(), deviceId: poste, updatedAt: saisie, paymentMode: 'especes', total: total, soldAt: le,
              status: Value(etat), syncStatus: Value(statut),
            ),
          );
      await vente(DateTime(2026, 10, 18, 9), 1000);
      await vente(DateTime(2026, 10, 18, 17, 30), 2500.5);
      await vente(DateTime(2026, 10, 19, 11), 700);
      await vente(DateTime(2026, 10, 19, 12), 9999, etat: 'annulee'); // annulée : exclue
      await vente(DateTime(2026, 10, 19, 13), 300, statut: SyncStatus.pending); // pas encore au serveur
      await vente(DateTime(2026, 10, 19, 14), 400, statut: SyncStatus.conflict); // refusée : pas au serveur
      await vente(DateTime(2026, 10, 17, 23, 59), 5000); // avant `depuis`

      await db.into(db.purchases).insert(
        PurchasesCompanion.insert(
          id: uuid(), deviceId: poste, updatedAt: saisie, supplierId: autre, paymentMode: 'especes', total: 15000,
          purchaseDate: DateTime(2026, 10, 18), syncStatus: const Value(SyncStatus.synced),
        ),
      );
      await db.into(db.purchases).insert(
        PurchasesCompanion.insert(
          id: uuid(), deviceId: poste, updatedAt: saisie, supplierId: autre, paymentMode: 'credit', total: 4000.25,
          purchaseDate: DateTime(2026, 10, 18), syncStatus: const Value(SyncStatus.synced),
        ),
      );

      Future<void> fiche(String lot, DateTime jour, int mort) => db.into(db.livestockDailyEntries).insert(
        LivestockDailyEntriesCompanion.insert(
          id: uuid(), deviceId: poste, updatedAt: saisie, lotId: lot, entryDate: jour, mort: Value(mort),
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
      await fiche(bande, DateTime(2026, 10, 18), 2);
      await fiche(bande, DateTime(2026, 10, 19), 0);
      await fiche(autre, DateTime(2026, 10, 19), 3);

      Future<void> soin(double cout, bool actif) => db.into(db.veterinaryRecords).insert(
        VeterinaryRecordsCompanion.insert(
          id: uuid(), deviceId: poste, updatedAt: saisie, lotId: bande, actionType: 'vaccin',
          recordDate: DateTime(2026, 10, 19), cost: Value(cout), isActive: Value(actif),
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
      await soin(1200, true);
      await soin(800, false); // archivé : exclu

      await db.into(db.customerAdvances).insert(
        CustomerAdvancesCompanion.insert(
          id: uuid(), customerId: autre, amount: 5000, advanceDate: Value(DateTime(2026, 10, 19)),
          syncStatus: const Value(SyncStatus.synced),
        ),
      );

      await db.into(db.livestockTransfers).insert(
        LivestockTransfersCompanion.insert(
          id: uuid(), deviceId: poste, updatedAt: saisie, sourceLotId: bande, targetLotId: autre,
          transferDate: DateTime(2026, 10, 18), quantity: 12, syncStatus: const Value(SyncStatus.synced),
        ),
      );

      // Grand livre des stocks : tiré en lecture seule, sans statut — toutes ses lignes comptent.
      Future<void> mouvement(double q, DateTime le) => db.into(db.stockMovements).insert(
        StockMovementsCompanion.insert(
          id: uuid(), productId: autre, type: 'sortie', quantity: q, referenceType: 'vente', movementDate: le,
        ),
      );
      await mouvement(3, DateTime(2026, 10, 19, 8, 15));
      await mouvement(1.5, DateTime(2026, 10, 19, 18));
    });
    tearDown(() => db.close());

    ControleCoherenceRepository depot(Map<String, dynamic> serveur) => ControleCoherenceRepository(
      database: db,
      serveur: (_) async => serveur,
      maintenant: () => DateTime(2026, 10, 19, 15),
    );

    test('nombre et total par table et par jour, lignes `synced` seulement — jeu calculé à la main', () async {
      final local = await depot(const {}).calculerLocal(DateTime(2026, 10, 18));

      expect(local['sales'], {
        '2026-10-18': const TotauxJour(nombre: 2, total: 3500.5),
        '2026-10-19': const TotauxJour(nombre: 1, total: 700),
      });
      expect(local['purchases'], {'2026-10-18': const TotauxJour(nombre: 2, total: 19000.25)});
      expect(local['livestock_daily_entries'], {
        '2026-10-18': const TotauxJour(nombre: 1, total: 2),
        '2026-10-19': const TotauxJour(nombre: 2, total: 3),
      });
      expect(local['veterinary_records'], {'2026-10-19': const TotauxJour(nombre: 1, total: 1200)});
      expect(local['customer_advances'], {'2026-10-19': const TotauxJour(nombre: 1, total: 5000)});
      expect(local['livestock_transfers'], {'2026-10-18': const TotauxJour(nombre: 1, total: 12)});
      expect(local['stock_movements'], {'2026-10-19': const TotauxJour(nombre: 2, total: 4.5)});
    });

    test(
      'EX1 — sans « anouveaux » servi (compte sans la comptabilité), le poste ne contrôle pas les à-nouveaux',
      () async {
        final sans = await depot(const {'tables': {}}).verifier();
        expect(sans.anouveauxServeur, isNull);
        expect(sans.anouveauxPoste, isNull, reason: 'le journal ne descend pas à ce compte : rien à relire');
        expect(sans.nombreEcartsAnouveaux, 0);

        final avec = await depot(const {'tables': {}, 'anouveaux': []}).verifier();
        expect(avec.anouveauxServeur, isEmpty);
        expect(avec.anouveauxPoste, isEmpty, reason: 'aucun exercice au poste : rien à comparer');
      },
    );

    test('lecture de la réponse du serveur : un tableau PHP vide (`[]`) est une table sans ligne', () {
      final lu = ControleCoherenceRepository.lireServeur({
        'tables': {
          'sales': {
            'libelle': 'Ventes',
            'jours': {'2026-10-18': {'nombre': 2, 'total': 3500.5}},
          },
          'purchases': {'libelle': 'Achats', 'jours': <Object>[]},
        },
      });
      expect(lu['sales'], {'2026-10-18': const TotauxJour(nombre: 2, total: 3500.5)});
      expect(lu['purchases'], isEmpty);
    });

    test('comparaison : jours conformes, écarts de nombre ou de total, jour connu d\'un seul côté', () async {
      final resultat = await depot({
        'depuis': '2026-09-20',
        'tables': {
          'sales': {
            'jours': {
              '2026-10-18': {'nombre': 2, 'total': 3500.5}, // conforme
              '2026-10-17': {'nombre': 1, 'total': 5000}, // conforme
              '2026-10-19': {'nombre': 2, 'total': 1000}, // une vente de 300 manque au poste
            },
          },
          'purchases': {'jours': {'2026-10-18': {'nombre': 2, 'total': 19000}}}, // 0,25 d'écart
          'livestock_daily_entries': {
            'jours': {
              '2026-10-18': {'nombre': 1, 'total': 2},
              '2026-10-19': {'nombre': 2, 'total': 3},
            },
          },
          'veterinary_records': {'jours': {'2026-10-19': {'nombre': 1, 'total': 1200}}},
          'customer_advances': {'jours': <Object>[]}, // l'avance du poste n'est pas au serveur
          'livestock_transfers': {'jours': {'2026-10-18': {'nombre': 1, 'total': 12}}},
          'stock_movements': {
            'jours': {
              '2026-10-19': {'nombre': 2, 'total': 4.5},
              '2026-10-01': {'nombre': 1, 'total': 10}, // mouvement du serveur jamais descendu
            },
          },
        },
      }).verifier();

      expect(resultat.depuis, DateTime(2026, 9, 20), reason: '30 jours, aujourd\'hui compris');
      final parTable = {for (final t in resultat.tables) t.table: t};
      expect(parTable.keys.toList(), AgregatsCoherence.tables.map((a) => a.table).toList());

      final ventes = parTable['sales']!;
      expect(ventes.conformes.map((l) => l.jour), ['2026-10-18', '2026-10-17']);
      expect(ventes.ecarts.single.jour, '2026-10-19');
      expect((ventes.ecarts.single.ecartNombre, ventes.ecarts.single.ecartTotal), (-1, -300.0));

      expect(parTable['purchases']!.ecarts.single.ecartTotal, 0.25);
      expect(parTable['purchases']!.ecarts.single.ecartNombre, 0);
      expect(parTable['livestock_daily_entries']!.ecarts, isEmpty);
      expect(parTable['livestock_daily_entries']!.conformes.map((l) => l.jour), ['2026-10-19', '2026-10-18'],
          reason: 'du plus récent au plus ancien');

      final avance = parTable['customer_advances']!.ecarts.single;
      expect((avance.poste, avance.serveur), (const TotauxJour(nombre: 1, total: 5000), null));

      final mouvements = parTable['stock_movements']!;
      expect(mouvements.ecarts.single.jour, '2026-10-01');
      expect(mouvements.ecarts.single.poste, isNull);
      expect(mouvements.conformes.single.jour, '2026-10-19');

      expect(resultat.nombreEcarts, 4);
    });

    test('un bruit d\'arrondi sous le centime n\'est pas un écart', () {
      const l = LigneCoherence(
        jour: '2026-10-19',
        poste: TotauxJour(nombre: 3, total: 0.1 + 0.2),
        serveur: TotauxJour(nombre: 3, total: 0.3),
      );
      expect(l.conforme, isTrue);
    });
  });

  group('S-T6 — écran Synchronisation, « Contrôle de cohérence »', () {
    late AppDatabase db;
    late _Connexion connexion;
    late SyncEngine engine;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      connexion = _Connexion(true);
      engine = SyncEngine(
        database: db,
        client: Dio(BaseOptions(baseUrl: 'http://serveur-feint')),
        deviceId: poste,
        connectivity: connexion,
      );
      await db.into(db.sales).insert(
        SalesCompanion.insert(
          id: uuid(), deviceId: poste, updatedAt: DateTime(2026, 10, 19), paymentMode: 'especes', total: 1000,
          soldAt: DateTime(2026, 10, 18, 9), syncStatus: const Value(SyncStatus.synced),
        ),
      );
      await db.into(db.sales).insert(
        SalesCompanion.insert(
          id: uuid(), deviceId: poste, updatedAt: DateTime(2026, 10, 19), paymentMode: 'especes', total: 700,
          soldAt: DateTime(2026, 10, 19, 9), syncStatus: const Value(SyncStatus.synced),
        ),
      );
    });
    tearDown(() => db.close());

    Future<void> afficher(WidgetTester t, Future<Map<String, dynamic>> Function(String) serveur) async {
      t.view.physicalSize = const Size(1280, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: SynchronisationScreen(
            database: db,
            engine: engine,
            coherence: ControleCoherenceRepository(
              database: db,
              serveur: serveur,
              maintenant: () => DateTime(2026, 10, 19, 15),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('titre, bouton, puis tableau Poste / Serveur / Écart ; jours conformes repliés', (t) async {
      String? demande;
      await afficher(t, (depuis) async {
        demande = depuis;
        return {
          'tables': {
            'sales': {
              'jours': {
                '2026-10-18': {'nombre': 1, 'total': 1000},
                '2026-10-19': {'nombre': 2, 'total': 1500},
              },
            },
          },
        };
      });

      expect(find.text('Contrôle de cohérence'), findsOneWidget);
      expect(find.byKey(const Key('coherence-aucun-controle')), findsOneWidget);

      await t.ensureVisible(find.byKey(const Key('bouton-verifier-coherence')));
      await t.tap(find.text('Vérifier la cohérence'));
      await t.pumpAndSettle();

      expect(demande, '2026-09-20');
      expect(find.text('Depuis le 20/09/2026 : 1 jour(s) en écart.'), findsOneWidget);
      expect(find.text('Poste'), findsOneWidget);
      expect(find.text('Serveur'), findsOneWidget);
      expect(find.text('Écart'), findsOneWidget);

      final ecart = find.byKey(const Key('coherence-sales-2026-10-19'));
      expect(find.descendant(of: ecart, matching: find.text('19/10/2026')), findsOneWidget);
      expect(find.descendant(of: ecart, matching: find.text('1 · 700')), findsOneWidget);
      expect(find.descendant(of: ecart, matching: find.text('2 · 1500')), findsOneWidget);
      expect(find.descendant(of: ecart, matching: find.text('-1 ligne(s) · -800')), findsOneWidget);

      // Le jour conforme est replié ; « 1 jour(s) conforme(s) » le déplie.
      expect(find.byKey(const Key('coherence-sales-2026-10-18')), findsNothing);
      await t.tap(find.byKey(const Key('coherence-deplier-sales')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('coherence-sales-2026-10-18')), findsOneWidget);

      // Les autres tables, sans aucune ligne d'aucun côté, le disent.
      expect(find.text('Aucune ligne sur la période, ni au poste ni au serveur.'), findsNWidgets(7));
      await t.pump(const Duration(seconds: 4)); // toast retiré
    });

    testWidgets('⚠️ hors ligne : un avertissement, le serveur n\'est pas appelé', (t) async {
      connexion.enLigne = false;
      var appels = 0;
      await afficher(t, (_) async {
        appels++;
        return {};
      });

      await t.ensureVisible(find.byKey(const Key('bouton-verifier-coherence')));
      await t.tap(find.text('Vérifier la cohérence'));
      await t.pump();

      expect(appels, 0);
      expect(find.text('Hors ligne — le contrôle de cohérence demande le serveur.'), findsOneWidget);
      expect(find.byKey(const Key('coherence-aucun-controle')), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('serveur injoignable : un avertissement, jamais une erreur rouge', (t) async {
      await afficher(t, (_) async => throw DioException(
        requestOptions: RequestOptions(path: '/api/sync/coherence'),
        type: DioExceptionType.connectionError,
      ));

      await t.ensureVisible(find.byKey(const Key('bouton-verifier-coherence')));
      await t.tap(find.text('Vérifier la cohérence'));
      await t.pumpAndSettle();

      expect(find.text('Serveur injoignable — contrôle impossible pour le moment.'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });
  });
}
