import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/caisse_screen.dart';
import 'package:agrierp/features/ventes/choix_facture.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MECEF-3 — LE CHOIX « Facture simple » / « Facture normalisée » à la caisse du POSTE (demande du client, 07/11/2026), mêmes
/// libellés, même ordre et même comportement que la caisse du web (`PosInterface`) :
///  - le choix n'est proposé que si le module MeCeF est actif (`mecef.actif`) ; défaut : facture simple (AUCUNE transmission) ;
///  - « Facture normalisée » ouvre la fenêtre « Facture Normalisée » (ModaleAgri) : IFU du client (vide = client sans IFU), nom
///    et prénom *, taux AIB (5 % par défaut), préremplie d'après la fiche du client ;
///  - refus motivés AVANT tout effet (mêmes mots que le serveur) ; le poste ÉCRIT le choix et l'envoie avec la vente.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          for (final MapEntry(:key, :value) in corps.entries)
            if (value is List) key: {'accepted': [for (final e in value) if (e is Map && e['id'] is String) e['id']], 'rejected': <Object>[]},
        },
      ));
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {'server_time': '2026-11-07T09:00:00Z'}));
  }
}

void main() {
  late AppDatabase db;
  late CaisseRepository depot;

  const client = 'cccccccc-1111-4111-8111-cccccccccccc';
  late Product oeufs;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = CaisseRepository(database: db, deviceId: 'poste-test', maintenant: () => DateTime(2026, 11, 7, 10));
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb', sku: 'OEU-001', name: 'Oeufs', unit: 'u', pricingMode: 'fourchette',
        priceMin: const Value(1000), priceMax: const Value(8000), stockQty: const Value(50),
      ),
    );
    oeufs = await db.select(db.products).getSingle();
  });

  tearDown(() async => db.close());

  Future<void> activerMecef([bool actif = true]) => db.into(db.appSettings).insertOnConflictUpdate(
    AppSettingsCompanion.insert(key: 'mecef.actif', value: actif ? '1' : '0'),
  );

  Future<void> poserClient({String? ifu, String nom = 'GBAGUIDI Solange'}) =>
      db.into(db.customers).insert(CustomersCompanion.insert(id: client, name: nom, ifu: Value(ifu)));

  List<LignePanier> panier() => [LignePanier(produit: oeufs, quantite: 2, montant: 6000)];

  group('dépôt', () {
    test('par défaut : facture simple, aucune identité fiscale', () async {
      final v = await depot.enregistrerVente(panier: panier(), modePaiement: 'especes');

      expect([v.factureType, v.clientIfu, v.clientNomFacture, v.aibTaux], ['simple', null, null, null]);
    });

    test('une facture simple n\'emporte jamais l\'identité fiscale saisie par erreur', () async {
      final v = await depot.enregistrerVente(
        panier: panier(), modePaiement: 'especes', clientIfu: 'zz', clientNomFacture: 'A', aibTaux: '9%',
      );

      expect([v.factureType, v.clientIfu, v.clientNomFacture, v.aibTaux], ['simple', null, null, null]);
    });

    test('⚠️ une facture normalisée écrit le choix à la saisie (IFU vide = client sans IFU)', () async {
      final avec = await depot.enregistrerVente(
        panier: panier(), modePaiement: 'especes', factureType: 'normalisee',
        clientIfu: '123 456 789 0123', clientNomFacture: ' KPOGNON Séraphin ', aibTaux: '1%',
      );
      expect([avec.factureType, avec.clientIfu, avec.clientNomFacture, avec.aibTaux], ['normalisee', '1234567890123', 'KPOGNON Séraphin', '1%']);

      final sans = await depot.enregistrerVente(
        panier: panier(), modePaiement: 'especes', factureType: 'normalisee', clientIfu: '', clientNomFacture: 'Particulier', aibTaux: 'N/A',
      );
      expect([sans.clientIfu, sans.aibTaux], [null, 'N/A']);
    });

    test('⚠️ refus motivés (mêmes mots que le serveur), avant tout effet : aucune vente, stock intact', () async {
      for (final (ifu, nom, aib, motif) in [
        ('12345', 'A', '5%', ChoixFacture.motifIfu),
        ('', '   ', '5%', ChoixFacture.motifNom),
        ('', 'A', '9%', ChoixFacture.motifAib),
        ('', 'A', null, ChoixFacture.motifAib),
      ]) {
        await expectLater(
          depot.enregistrerVente(panier: panier(), modePaiement: 'especes', factureType: 'normalisee', clientIfu: ifu, clientNomFacture: nom, aibTaux: aib),
          throwsA(isA<VenteRefusee>().having((e) => e.message, 'message', motif)),
        );
      }
      await expectLater(
        depot.enregistrerVente(panier: panier(), modePaiement: 'especes', factureType: 'speciale'),
        throwsA(isA<VenteRefusee>().having((e) => e.message, 'message', ChoixFacture.motifType)),
      );

      expect(await db.select(db.sales).get(), isEmpty);
      expect(await db.select(db.saleLines).get(), isEmpty);
      expect((await db.select(db.products).getSingle()).stockQty, 50);
    });

    test('mecefActif suit le tirage (`mecef.actif`) ; inconnu : désactivé comme au serveur', () async {
      expect(await depot.mecefActif(), isFalse);
      await activerMecef();
      expect(await depot.mecefActif(), isTrue);
      await activerMecef(false);
      expect(await depot.mecefActif(), isFalse);
    });
  });

  group('envoi', () {
    test('⚠️ le choix part AVEC la vente (jamais l\'AIB calculé ni ce que renvoie la DGI)', () async {
      await depot.enregistrerVente(
        panier: panier(), modePaiement: 'especes', factureType: 'normalisee', clientIfu: '1234567890123', clientNomFacture: 'KPOGNON Séraphin', aibTaux: '5%',
      );
      await depot.enregistrerVente(panier: panier(), modePaiement: 'especes');
      final serveur = _Serveur();
      final moteur = SyncEngine(
        database: db, client: Dio()..interceptors.add(serveur), deviceId: 'poste-test', connectivity: _Connectivite(),
        maintenant: () => DateTime.utc(2026, 11, 7, 9),
      );

      await moteur.synchroniser();

      final ventes = (serveur.envois.expand((e) => (e['sales'] as List?) ?? const []).cast<Map<String, dynamic>>()).toList();
      expect(ventes, hasLength(2));
      final normalisee = ventes.firstWhere((v) => v['facture_type'] == 'normalisee');
      expect([normalisee['client_ifu'], normalisee['client_nom_facture'], normalisee['aib_taux']], ['1234567890123', 'KPOGNON Séraphin', '5%']);
      final simple = ventes.firstWhere((v) => v['facture_type'] == 'simple');
      expect([simple['client_ifu'], simple['client_nom_facture'], simple['aib_taux']], [null, null, null]);
      for (final v in ventes) {
        expect(v.keys.where((k) => k.startsWith('mecef')), isEmpty);
      }
    });

    test('le tirage rend le choix, l\'AIB de la DGI et la livraison incluse ; le client rend son IFU', () async {
      final serveur = _Serveur();
      final moteur = SyncEngine(
        database: db, client: Dio()..interceptors.add(serveur), deviceId: 'poste-test', connectivity: _Connectivite(),
        maintenant: () => DateTime.utc(2026, 11, 7, 9),
      );
      // Un tirage qui sert une vente normalisée et un client avec IFU.
      final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        h.resolve(Response<Map<String, dynamic>>(requestOptions: o, statusCode: 200, data: {
          'server_time': '2026-11-07T09:00:00Z',
          'customers': [{'id': client, 'name': 'SODJI Béatrice', 'ifu': '9876543210123', 'is_active': true}],
          'sales': [{
            'id': 'dddddddd-1111-4111-8111-dddddddddddd', 'customer_id': client, 'payment_mode': 'especes', 'subtotal': 11800, 'discount': 0,
            'total': 14300, 'status': 'validee', 'mecef_status': 'transmise', 'mecef_qr_ref': 'F;X', 'facture_type': 'normalisee',
            'client_ifu': '9876543210123', 'client_nom_facture': 'SODJI Béatrice', 'aib_taux': '5%', 'mecef_aib_montant': 590,
            'delivery_fee': 2500, 'delivery_in_total': true, 'sold_at': '2026-11-07T09:30:00+01:00',
          }],
        }));
      }));
      await SyncEngine(database: db, client: dio, deviceId: 'poste-test', connectivity: _Connectivite(), maintenant: () => DateTime.utc(2026, 11, 7, 9)).synchroniser();
      expect(moteur, isNotNull);

      final c = await (db.select(db.customers)..where((t) => t.id.equals(client))).getSingle();
      expect(c.ifu, '9876543210123');
      final v = await (db.select(db.sales)..where((t) => t.id.equals('dddddddd-1111-4111-8111-dddddddddddd'))).getSingle();
      expect([v.factureType, v.clientIfu, v.clientNomFacture, v.aibTaux, v.mecefAibMontant, v.deliveryFee, v.deliveryInTotal], ['normalisee', '9876543210123', 'SODJI Béatrice', '5%', 590, 2500, true]);
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: CaisseScreen(depot: depot)));
      await tester.pumpAndSettle();
    }

    Future<void> mettreAuPanier(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('produit-OEU-001')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('saisie-quantite')), '2');
      await tester.enterText(find.byKey(const Key('saisie-montant')), '6000');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmer-ligne')));
      await tester.pumpAndSettle();
    }

    Future<void> choisirNormalisee(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('type-facture')));
      await tester.tap(find.byKey(const Key('type-facture')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Facture normalisée').last);
      await tester.pumpAndSettle();
    }

    Future<void> valider(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('valider-vente')));
      await tester.tap(find.byKey(const Key('valider-vente')));
      await tester.pumpAndSettle();
    }

    testWidgets('module inactif : aucun « Type de Facture », la vente est une facture simple', (tester) async {
      await afficher(tester);
      await mettreAuPanier(tester);

      expect(find.byKey(const Key('type-facture')), findsNothing);
      await valider(tester);

      expect((await db.select(db.sales).getSingle()).factureType, 'simple');
      expect(find.byKey(const Key('facture-demandee')), findsNothing);
    });

    testWidgets('module actif : « Facture simple » par défaut, libellés et ordre du web', (tester) async {
      await activerMecef();
      await afficher(tester);
      await mettreAuPanier(tester);

      expect(find.byKey(const Key('type-facture')), findsOneWidget);
      expect(find.text('Facture simple'), findsOneWidget);
      expect(find.byKey(const Key('facture-infos')), findsNothing);

      await valider(tester);
      expect((await db.select(db.sales).getSingle()).factureType, 'simple', reason: 'jamais transmise : le défaut');
      expect(find.byKey(const Key('facture-demandee')), findsNothing);
    });

    testWidgets('⚠️ « Facture normalisée » ouvre la fenêtre, préremplie d\'après le client (nom et IFU) ; Valider ; la vente porte le choix', (tester) async {
      await activerMecef();
      await poserClient(ifu: '9876543210123');
      await afficher(tester);
      await mettreAuPanier(tester);

      await tester.tap(find.byKey(const Key('client-vente')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GBAGUIDI Solange').last);
      await tester.pumpAndSettle();
      await choisirNormalisee(tester);

      expect(find.text('Facture Normalisée'), findsOneWidget);
      // Libellés et ordre : IFU du client, Nom et prénom du client *, Taux AIB.
      final ordre = ['IFU du client', 'Nom et prénom du client *', 'Taux AIB'].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
      expect(ordre, [...ordre]..sort());
      expect(tester.widget<TextField>(find.byKey(const Key('facture-ifu'))).controller!.text, '9876543210123');
      expect(tester.widget<TextField>(find.byKey(const Key('facture-nom'))).controller!.text, 'GBAGUIDI Solange');
      expect(find.text('5 %'), findsOneWidget, reason: '5 % par défaut : le cas général');
      expect(find.text('Laissez vide pour un client sans IFU (client particulier).'), findsOneWidget);

      await tester.tap(find.byKey(const Key('facture-valider')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('facture-infos')), findsOneWidget, reason: '« Modifier les informations de facturation »');

      await valider(tester);

      final v = await db.select(db.sales).getSingle();
      expect([v.factureType, v.clientIfu, v.clientNomFacture, v.aibTaux], ['normalisee', '9876543210123', 'GBAGUIDI Solange', '5%']);
      expect(find.byKey(const Key('facture-demandee')), findsOneWidget);
      expect(find.text('Facture normalisée demandée — en attente'), findsOneWidget);
    });

    testWidgets('⚠️ la fenêtre refuse avec les motifs du serveur : nom, IFU, puis passe ; IFU vide accepté', (tester) async {
      await activerMecef();
      await afficher(tester);
      await mettreAuPanier(tester);
      await choisirNormalisee(tester);

      await tester.tap(find.byKey(const Key('facture-valider')));
      await tester.pumpAndSettle();
      expect(find.text(ChoixFacture.motifNom), findsOneWidget);
      expect(find.text('Facture Normalisée'), findsOneWidget, reason: 'la fenêtre reste ouverte');

      await tester.enterText(find.byKey(const Key('facture-nom')), 'Madame ADJOVI');
      await tester.enterText(find.byKey(const Key('facture-ifu')), '12345');
      await tester.tap(find.byKey(const Key('facture-valider')));
      await tester.pumpAndSettle();
      expect(find.text(ChoixFacture.motifIfu), findsOneWidget);

      await tester.enterText(find.byKey(const Key('facture-ifu')), '');
      await tester.tap(find.byKey(const Key('facture-valider')));
      await tester.pumpAndSettle();
      expect(find.text('Facture Normalisée'), findsNothing);

      await valider(tester);
      final v = await db.select(db.sales).getSingle();
      expect([v.factureType, v.clientIfu, v.clientNomFacture], ['normalisee', null, 'Madame ADJOVI']);
    });

    testWidgets('« Annuler » ramène à la facture simple', (tester) async {
      await activerMecef();
      await afficher(tester);
      await mettreAuPanier(tester);
      await choisirNormalisee(tester);

      await tester.tap(find.byKey(const Key('facture-annuler')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('facture-infos')), findsNothing);
      expect(tester.widget<DropdownButton<String>>(find.byKey(const Key('type-facture'))).value, 'simple');
      await valider(tester);
      expect((await db.select(db.sales).getSingle()).factureType, 'simple');
    });

    testWidgets('la vente suivante repart en facture simple (le choix ne se reporte jamais)', (tester) async {
      await activerMecef();
      await afficher(tester);
      await mettreAuPanier(tester);
      await choisirNormalisee(tester);
      await tester.enterText(find.byKey(const Key('facture-nom')), 'Madame ADJOVI');
      await tester.tap(find.byKey(const Key('facture-valider')));
      await tester.pumpAndSettle();
      await valider(tester);
      await tester.tap(find.byKey(const Key('bouton-nouvelle-vente')));
      await tester.pumpAndSettle();

      expect(tester.widget<DropdownButton<String>>(find.byKey(const Key('type-facture'))).value, 'simple');
      expect(find.byKey(const Key('facture-infos')), findsNothing);
    });
  });

  test('garde de source : la fenêtre est une ModaleAgri ouverte par afficherModale, jamais conditionnée par un `if` d\'écran', () {
    final source = File('lib/features/ventes/caisse_screen.dart').readAsStringSync();
    expect(source, contains('class _DialogueFactureNormalisee'));
    expect(source, contains('ModaleAgri('));
    expect(source, contains('afficherModale<ChoixValide>'));
    // Les libellés de la fenêtre sont ceux du Blade du POS web.
    final blade = File('${Directory.current.parent.path}/agrierp_laravel/resources/views/livewire/ventes/pos-interface.blade.php');
    if (blade.existsSync()) {
      final b = blade.readAsStringSync();
      for (final libelle in ['Facture Normalisée', 'IFU du client', 'Nom et prénom du client *', 'Taux AIB', 'Type de Facture', 'Modifier les informations de facturation']) {
        expect(b, contains(libelle), reason: libelle);
        expect(source, contains(libelle), reason: libelle);
      }
      expect(b, contains("Laissez vide pour un client sans IFU (client particulier)."));
      expect(source, contains('Laissez vide pour un client sans IFU (client particulier).'));
    }
    expect(jsonEncode(ChoixFacture.libellesAib), contains('Aucun (N/A)'));
  });
}
