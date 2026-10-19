import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/fusion_referentiels.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serveur feint : sert un tirage vide, répond [reponses] aux envois successifs (la dernière se répète) et note ce
/// qui est envoyé.
class _ServeurSync extends Interceptor {
  _ServeurSync({required this.reponses});

  final List<Map<String, dynamic>> reponses;
  final List<Map<String, dynamic>> envois = [];
  var _tirage = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final push = options.path.contains('push');
    Map<String, dynamic> corps;
    if (push) {
      envois.add(Map<String, dynamic>.from(options.data as Map));
      corps = reponses[envois.length - 1 < reponses.length ? envois.length - 1 : reponses.length - 1];
    } else {
      _tirage++;
      corps = {
        'server_time': '2026-10-19T12:0$_tirage:00.000Z',
        'product_categories': <dynamic>[],
        'products': <dynamic>[],
        'livestock_lots': <dynamic>[],
      };
    }
    handler.resolve(
      Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: corps),
    );
  }
}

class _ConnectiviteFeinte implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Ticket S-T5 (méthode TATACORA) — « le poste apprend l'identifiant du serveur ». À la réception d'un `merged`, le
/// poste remplace son identifiant de client, fournisseur ou produit par celui du serveur, dans la fiche ET dans toutes
/// ses références, en une transaction ; ses saisies en attente partent ensuite avec le bon identifiant.
void main() {
  late AppDatabase db;

  const idPoste = 'b0000000-0000-4000-8000-00000000000b';
  const idServeur = 'a0000000-0000-4000-8000-00000000000a';

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  SyncEngine moteur(_ServeurSync serveur) => SyncEngine(
    database: db,
    client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur),
    deviceId: 'poste-test',
    connectivity: _ConnectiviteFeinte(),
  );

  /// Colonnes (nom SQL) d'une table du schéma.
  Future<List<({String nom, String type, bool requis, bool cle})>> colonnes(String table) async => [
    for (final l in await db.customSelect('PRAGMA table_info("$table")').get())
      (
        nom: l.read<String>('name'),
        type: l.read<String>('type').toUpperCase(),
        requis: l.read<int>('notnull') == 1 && l.readNullable<String>('dflt_value') == null,
        cle: l.read<int>('pk') > 0,
      ),
  ];

  /// Insère, en SQL brut, une ligne minimale de [table] dont [colonne] vaut [valeur] : chaque autre colonne requise
  /// reçoit une valeur neutre (texte unique, 0 pour un nombre, une date ou un booléen).
  var compteur = 0;
  Future<void> ligne(String table, String colonne, String valeur, {Map<String, Object> autres = const {}}) async {
    final valeurs = <String, Object>{colonne: valeur, ...autres};
    for (final c in await colonnes(table)) {
      if (valeurs.containsKey(c.nom) || !(c.requis || c.cle)) continue;
      compteur++;
      valeurs[c.nom] = c.type.contains('TEXT') ? 'v$compteur-'.padRight(36, '0') : 0;
    }
    await db.customStatement(
      'INSERT INTO $table (${valeurs.keys.join(', ')}) VALUES (${List.filled(valeurs.length, '?').join(', ')})',
      valeurs.values.toList(),
    );
  }

  Future<int> nombre(String table, String colonne, String valeur) async => (await db
          .customSelect('SELECT COUNT(*) AS n FROM $table WHERE $colonne = ?', variables: [Variable.withString(valeur)])
          .getSingle())
      .read<int>('n');

  Future<void> clientLocal(String id, String nom, {SyncStatus statut = SyncStatus.pending}) => db
      .into(db.customers)
      .insert(CustomersCompanion.insert(id: id, name: nom, phone: const Value('+229 97 12 34 56'), syncStatus: Value(statut)));

  Future<void> venteEnAttente(String id, String clientId) => db.into(db.sales).insert(
    SalesCompanion.insert(
      id: id,
      deviceId: 'poste-test',
      updatedAt: DateTime.utc(2026, 10, 19, 8),
      customerId: Value(clientId),
      paymentMode: 'credit',
      total: 7000,
      soldAt: DateTime.utc(2026, 10, 19, 8),
    ),
  );

  group('garde-fou du schéma', () {
    test('⚠️⚠️ chaque colonne customer_id, supplier_id et …product_id du schéma Drift est couverte par le remplacement', () async {
      final trouvees = <String, Set<(String, String)>>{for (final t in FusionReferentiels.tables) t: {}};
      for (final table in db.allTables) {
        for (final c in table.$columns) {
          final nom = c.name;
          final cible = nom == 'customer_id' || nom.endsWith('_customer_id')
              ? 'customers'
              : nom == 'supplier_id' || nom.endsWith('_supplier_id')
              ? 'suppliers'
              : nom == 'product_id' || nom.endsWith('_product_id')
              ? 'products'
              : null;
          if (cible != null) trouvees[cible]!.add((table.actualTableName, nom));
        }
      }

      expect(trouvees.values.expand((e) => e), isNotEmpty, reason: 'le relevé doit voir des références');
      for (final t in FusionReferentiels.tables) {
        expect(
          FusionReferentiels.references[t]!.toSet(),
          trouvees[t],
          reason: 'références vers « $t » : le schéma et FusionReferentiels.references doivent coïncider',
        );
      }
    });

    test('les miroirs à clé sont exactement les tables dont la référence fait partie de la clé primaire', () async {
      final aCle = <String>{};
      for (final refs in FusionReferentiels.references.values) {
        for (final (table, colonne) in refs) {
          if ((await colonnes(table)).any((c) => c.nom == colonne && c.cle)) aCle.add(table);
        }
      }
      expect(aCle, FusionReferentiels.miroirsACle);
    });
  });

  group('remplacement', () {
    for (final referentiel in FusionReferentiels.tables) {
      test('⚠️⚠️ $referentiel : la fiche et TOUTES ses références passent à l\'identifiant du serveur', () async {
        await ligne(referentiel, 'id', idPoste, autres: {'name': 'Fiche du poste', 'sync_status': 'pending'});
        for (final (table, colonne) in FusionReferentiels.references[referentiel]!) {
          await ligne(table, colonne, idPoste);
        }

        await FusionReferentiels(db).appliquer(referentiel, idPoste, idServeur);

        for (final (table, colonne) in FusionReferentiels.references[referentiel]!) {
          expect(await nombre(table, colonne, idPoste), 0, reason: '$table.$colonne garde l\'identifiant du poste');
          expect(await nombre(table, colonne, idServeur), 1, reason: '$table.$colonne');
        }
        expect(await nombre(referentiel, 'id', idPoste), 0, reason: 'la fiche du poste est retirée');
        final copie = await db
            .customSelect('SELECT name, sync_status FROM $referentiel WHERE id = ?', variables: [Variable.withString(idServeur)])
            .getSingle();
        expect(copie.read<String>('name'), 'Fiche du poste', reason: 'copiée sous l\'identifiant du serveur');
        expect(copie.read<String>('sync_status'), 'synced', reason: 'le serveur l\'a : le tirage y écrira sa version');
      });
    }

    test('la fiche du serveur déjà au poste est gardée telle quelle ; le doublon local disparaît', () async {
      await clientLocal(idServeur, 'Version du serveur', statut: SyncStatus.synced);
      await clientLocal(idPoste, 'Saisie au poste');

      await FusionReferentiels(db).appliquer('customers', idPoste, idServeur);

      final tous = await db.select(db.customers).get();
      expect(tous.map((c) => (c.id, c.name)), [(idServeur, 'Version du serveur')]);
    });

    test('miroir à clé : la ligne du serveur fait foi, celle du poste qui la doublerait est retirée', () async {
      await ligne('supplier_credits', 'supplier_id', idServeur, autres: {'open_credit': 5000});
      await ligne('supplier_credits', 'supplier_id', idPoste, autres: {'open_credit': 99});

      await FusionReferentiels(db).appliquer('suppliers', idPoste, idServeur);

      final restes = await db.select(db.supplierCredits).get();
      expect(restes.map((c) => (c.supplierId, c.openCredit)), [(idServeur, 5000.0)]);
    });

    test('une saisie en attente le RESTE, avec le même instant de saisie ; le refus ouvert du poste est retiré', () async {
      await clientLocal(idPoste, 'Saisie au poste', statut: SyncStatus.conflict);
      await venteEnAttente('c0000000-0000-4000-8000-00000000000c', idPoste);
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'customers:$idPoste',
          sourceTable: 'customers',
          recordId: idPoste,
          reason: 'Refus.',
          detectedAt: DateTime.utc(2026, 10, 19),
        ),
      );

      await FusionReferentiels(db).appliquer('customers', idPoste, idServeur);

      final vente = await db.select(db.sales).getSingle();
      expect(vente.customerId, idServeur);
      expect(vente.syncStatus, SyncStatus.pending);
      expect(vente.updatedAt.toUtc(), DateTime.utc(2026, 10, 19, 8));
      expect(await db.select(db.syncConflicts).get(), isEmpty);
    });

    test('⚠️ TRANSACTIONNEL : un échec en cours de route ne laisse AUCUN remplacement partiel', () async {
      await clientLocal(idPoste, 'Saisie au poste');
      await venteEnAttente('c0000000-0000-4000-8000-00000000000c', idPoste);
      // La dernière étape (retrait de la fiche du poste) échoue.
      await db.customStatement(
        "CREATE TEMP TRIGGER bloque BEFORE DELETE ON customers BEGIN SELECT RAISE(ABORT, 'refus'); END;",
      );

      await expectLater(FusionReferentiels(db).appliquer('customers', idPoste, idServeur), throwsA(anything));

      expect((await db.select(db.sales).getSingle()).customerId, idPoste, reason: 'la vente n\'a pas bougé');
      expect((await db.select(db.customers).get()).map((c) => c.id), [idPoste], reason: 'aucune copie laissée');
    });

    test('idempotent : rejouer la même fusion ne change rien et n\'échoue pas', () async {
      await clientLocal(idPoste, 'Saisie au poste');
      await venteEnAttente('c0000000-0000-4000-8000-00000000000c', idPoste);
      final fusion = FusionReferentiels(db);

      await fusion.appliquer('customers', idPoste, idServeur);
      await fusion.appliquer('customers', idPoste, idServeur);

      expect((await db.select(db.customers).get()).map((c) => c.id), [idServeur]);
      expect((await db.select(db.sales).getSingle()).customerId, idServeur);
    });

    test('une entrée `merged` illisible est ignorée', () {
      expect(
        FusionReferentiels.fusionsDe({
          'merged': [
            {'id': idPoste, 'id_serveur': idServeur},
            {'id': idPoste},
            {'id': '', 'id_serveur': idServeur},
            'x',
          ],
        }),
        [(idPoste, idServeur)],
      );
      expect(FusionReferentiels.fusionsDe({'accepted': <Object?>[]}), isEmpty, reason: 'serveur ancien : pas de merged');
    });
  });

  group('synchronisation', () {
    Map<String, dynamic> fusionne(String table) => {
      table: {
        'accepted': [idPoste],
        'rejected': <Object?>[],
        'merged': [
          {'id': idPoste, 'id_serveur': idServeur, 'motif': 'Existe déjà.'},
        ],
      },
    };

    test('⚠️⚠️ un client fusionné : la vente en attente repart avec l\'identifiant du serveur', () async {
      await clientLocal(idPoste, 'AMOUSSOU Régis');
      await venteEnAttente('c0000000-0000-4000-8000-00000000000c', idPoste);
      final serveur = _ServeurSync(
        reponses: [
          // 1er envoi : le client est fusionné ; la vente n'est pas encore acquittée (elle reste en attente).
          fusionne('customers'),
          // 2e envoi : la vente est acceptée.
          {
            'sales': {
              'accepted': ['c0000000-0000-4000-8000-00000000000c'],
              'rejected': <Object?>[],
            },
          },
        ],
      );
      final m = moteur(serveur);

      await m.synchroniser();

      expect((await db.select(db.customers).get()).map((c) => c.id), [idServeur]);
      final vente = await db.select(db.sales).getSingle();
      expect(vente.customerId, idServeur);
      expect(vente.syncStatus, SyncStatus.pending);

      await m.synchroniser();

      final envoyee = (serveur.envois[1]['sales'] as List).single as Map;
      expect(envoyee['customer_id'], idServeur, reason: 'la saisie en attente part avec le bon identifiant');
      expect(serveur.envois[1]['customers'], isEmpty, reason: 'le client fusionné ne repart pas');
      expect((await db.select(db.sales).getSingle()).syncStatus, SyncStatus.synced);
    });

    test('un renvoi après fusion (même `merged` reçu de nouveau) ne change rien', () async {
      await clientLocal(idServeur, 'Version du serveur', statut: SyncStatus.synced);
      await clientLocal(idPoste, 'Saisie au poste');
      await venteEnAttente('c0000000-0000-4000-8000-00000000000c', idPoste);
      final serveur = _ServeurSync(reponses: [fusionne('customers')]);
      final m = moteur(serveur);

      await m.synchroniser();
      await m.synchroniser(); // la vente repart, le serveur rejoue la même réponse

      expect((await db.select(db.customers).get()).map((c) => (c.id, c.name)), [(idServeur, 'Version du serveur')]);
      expect((await db.select(db.sales).getSingle()).customerId, idServeur);
    });

    test('un fournisseur et un produit fusionnés sont remplacés comme un client ; un serveur ancien ne change rien', () async {
      await db.into(db.suppliers).insert(
        SuppliersCompanion.insert(id: idPoste, name: 'Provenderie', syncStatus: const Value(SyncStatus.pending)),
      );
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'p0000000-0000-4000-8000-00000000000b',
          sku: 'LOC-1',
          name: 'Poulet',
          unit: 'u',
          pricingMode: 'fourchette',
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      final serveur = _ServeurSync(
        reponses: [
          {
            ...fusionne('suppliers'),
            // Serveur ANCIEN pour les produits : acquitté, sans `merged`.
            'products': {
              'accepted': ['p0000000-0000-4000-8000-00000000000b'],
              'rejected': <Object?>[],
            },
          },
        ],
      );

      await moteur(serveur).synchroniser();

      expect((await db.select(db.suppliers).get()).map((f) => (f.id, f.syncStatus)), [(idServeur, SyncStatus.synced)]);
      expect(
        (await db.select(db.products).get()).map((p) => (p.id, p.syncStatus)),
        [('p0000000-0000-4000-8000-00000000000b', SyncStatus.synced)],
      );
    });

    test('les `merged` de plusieurs lots sont mis bout à bout', () {
      final fusion = <String, dynamic>{};
      SyncEngine.fusionnerReponse(fusion, {
        'customers': {
          'accepted': ['x'],
          'rejected': <Object?>[],
          'merged': [
            {'id': 'x', 'id_serveur': 'a'},
          ],
        },
      });
      SyncEngine.fusionnerReponse(fusion, {
        'customers': {'accepted': ['y'], 'rejected': <Object?>[]},
      });
      SyncEngine.fusionnerReponse(fusion, {
        'customers': {
          'accepted': ['z'],
          'rejected': <Object?>[],
          'merged': [
            {'id': 'z', 'id_serveur': 'a'},
          ],
        },
      });

      expect(fusion['customers']['accepted'], ['x', 'y', 'z']);
      expect(FusionReferentiels.fusionsDe(fusion['customers']), [('x', 'a'), ('z', 'a')]);
    });
  });
}
