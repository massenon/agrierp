
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/systeme/justificatif_local.dart';
import 'package:agrierp/core/systeme/justificatifs_navigateur.dart';
import 'package:agrierp/core/systeme/ouvreur_url.dart';
import 'package:agrierp/core/systeme/plateforme_poste.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// PWA-2b — JUSTIFICATIFS AU NAVIGATEUR : les octets (≤ 2 Mo) sont rangés dans un magasin local (IndexedDB ; ici le REPLI en
/// mémoire), sans changer le schéma Drift ; la colonne porte une référence `navigateur:<clé>/<nom>` ; le moteur les envoie
/// par `POST /api/sync/receipts` comme le natif ; l'écran les rouvre (téléchargement).
class _Serveur extends Interceptor {
  final List<FormData> recus = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('/sync/receipts')) {
      recus.add(options.data as FormData);
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {'stored': true}));
      return;
    }
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {'accepted': [for (final e in value) if (e is Map && e['id'] is String) e['id']], 'rejected': <dynamic>[]},
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {'server_time': '2026-11-09T12:00:00Z'}));
  }
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late MagasinJustificatifs ancienMagasin;
  late Future<String> Function(String, List<int>) ancienLivreur;
  final livraisons = <({String nom, List<int> octets})>[];

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    PlateformePoste.forcerNavigateur(true);
    ancienMagasin = JustificatifsNavigateur.magasin;
    JustificatifsNavigateur.magasin = MagasinJustificatifsMemoire();
    ancienLivreur = PlateformePoste.livreurNavigateur;
    livraisons.clear();
    PlateformePoste.livreurNavigateur = (nom, octets) async {
      livraisons.add((nom: nom, octets: octets));
      return nom;
    };
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-web',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 11, 9, 14),
    );
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: uuid('f1'), name: 'Provenderie du Plateau', category: const Value('Aliments')));
    await db.into(db.products).insert(ProductsCompanion.insert(id: uuid('p1'), sku: 'ALI-25', name: 'Aliment ponte 25kg', unit: 'sac', pricingMode: 'fourchette'));
    await db.into(db.treasuryAccounts).insert(TreasuryAccountsCompanion.insert(id: uuid('t1'), label: 'Caisse principale', balance: const Value(100000)));
  });
  tearDown(() async {
    PlateformePoste.forcerNavigateur(null);
    JustificatifsNavigateur.magasin = ancienMagasin;
    PlateformePoste.livreurNavigateur = ancienLivreur;
    await db.close();
  });

  Future<String> achatAvecRecu(String chemin) async => AchatsRepository(database: db, identifiantPoste: 'poste-web').enregistrer(
    fournisseurId: uuid('f1'),
    lignes: [LigneSaisieAchat(produit: (await db.select(db.products).get()).single, quantite: 2, prixUnitaire: 5900)],
    modePaiement: 'especes',
    compteId: uuid('t1'),
    montantPaye: 11800,
    receiptLocalPath: chemin,
  );

  test('ranger : référence navigateur:<clé>/<nom>, octets relus, refus au-delà de 2 Mo ou si vide', () async {
    final octets = Uint8List.fromList([1, 2, 3, 4]);
    final ref = await rangerJustificatifNavigateur('facture mars.pdf', octets);
    expect(ref, isNotNull);
    expect(JustificatifsNavigateur.estReference(ref!), isTrue);
    final d = JustificatifsNavigateur.decoder(ref)!;
    expect(d.nom, 'facture mars.pdf');
    expect(await JustificatifsNavigateur.magasin.lire(d.cle), octets);
    expect(dernierRefusJustificatif, isNull);

    expect(await rangerJustificatifNavigateur('gros.pdf', Uint8List(JustificatifsNavigateur.tailleMaxOctets + 1)), isNull);
    expect(dernierRefusJustificatif, contains('2 Mo'));
    expect(await rangerJustificatifNavigateur('vide.pdf', Uint8List(0)), isNull);
    expect(dernierRefusJustificatif, contains('vide'));
    expect(JustificatifsNavigateur.decoder(r'C:\Users\x\recu.pdf'), isNull);
    expect(JustificatifsNavigateur.reference('k', r'a/b\c.pdf'), 'navigateur:k/a_b_c.pdf');
  });

  test('⚠️ le justificatif d\'un achat part par POST /api/sync/receipts avec ses octets, une seule fois', () async {
    final ref = (await rangerJustificatifNavigateur('recu.png', Uint8List.fromList([9, 8, 7])))!;
    final id = await achatAvecRecu(ref);

    await moteur.synchroniser();

    expect(serveur.recus, hasLength(1));
    final envoi = serveur.recus.single;
    expect({for (final f in envoi.fields) f.key: f.value}, {'table': 'purchases', 'id': id});
    expect(envoi.files.single.value.filename, 'recu.png');
    final recu = <int>[await for (final b in envoi.files.single.value.finalize()) ...b];
    expect(recu, [9, 8, 7]);
    final achat = await db.select(db.purchases).getSingle();
    expect(achat.syncStatus, SyncStatus.synced);
    expect(achat.receiptSent, isTrue);

    await moteur.synchroniser();
    expect(serveur.recus, hasLength(1), reason: 'jamais deux fois');
  });

  test('octets disparus du magasin : signalé, marqué envoyé, rien n\'est posté', () async {
    await achatAvecRecu('navigateur:inconnue/recu.pdf');
    final resultat = await moteur.synchroniser();
    expect(serveur.recus, isEmpty);
    expect(resultat.avertissements.join(' '), contains('introuvable'));
    expect((await db.select(db.purchases).getSingle()).receiptSent, isTrue);
  });

  test('rouvrir depuis l\'écran : le justificatif est téléchargé sous son nom', () async {
    final ref = (await rangerJustificatifNavigateur('recu.jpg', Uint8List.fromList([5, 5])))!;
    await ouvrirUrlSysteme(ref);
    expect(livraisons.single.nom, 'recu.jpg');
    expect(livraisons.single.octets, [5, 5]);
  });
}
