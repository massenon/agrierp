import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/theme/agri_theme.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/elevage/transformation_repository.dart';
import 'package:agrierp/features/elevage/transformation_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket EL-1 — « BON D'ABATTAGE & TRANSFORMATION » AU POSTE (`Livewire\Elevage\TransformationForm`).
///
/// Le poste écrit le FAIT (`pending`, UUID du poste) ; le serveur (`SaisieTransformationAction`) sort les sujets comme une
/// vente de la fiche du jour, entre le stock du produit fini et le rend au tirage. Les libellés sont LUS dans le Blade.
class _Serveur extends Interceptor {
  final List<Map<String, dynamic>> envois = [];
  int tirages = 0;
  final refus = <String, String>{};
  Map<String, dynamic> tirage = {'server_time': '2026-10-28T12:00:00Z'};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [for (final e in value) if (e is Map && !refus.containsKey(e['id'])) e['id']],
                  'rejected': [for (final e in value) if (e is Map && refus.containsKey(e['id'])) {'id': e['id'], 'reason': refus[e['id']]}],
                },
          },
        ),
      );
      return;
    }
    tirages++;
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

String? _lire(String relatif) {
  final f = File('$dossierLaravel/$relatif');
  return f.existsSync() ? f.readAsStringSync() : null;
}

String _norme(String s) => s.replaceAll('&amp;', '&').replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late TransformationRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);
  final lotA = uuid('a1');
  final lotB = uuid('a2');
  final poulet = uuid('p1');
  final lapin = uuid('p2');
  final universel = uuid('p3');
  final especeAvi = uuid('e1');
  final especeLap = uuid('e2');

  Future<void> bande(String id, String code, int effectif, String espece, {String statut = 'actif', bool active = true}) =>
      db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(id: id, code: code, speciesId: espece, status: Value(statut), isActive: Value(active), currentQuantity: Value(effectif)),
      );

  Future<void> produit(String id, String nom, String? espece, {bool actif = true}) => db.into(db.products).insert(
    ProductsCompanion.insert(id: id, sku: 'SKU-$nom', name: nom, unit: 'pièce', pricingMode: 'fixe', speciesId: Value(espece), isActive: Value(actif)),
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 28, 14),
    );
    depot = TransformationRepository(database: db, deviceId: 'poste-test');
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: especeAvi, code: 'aviculture', label: 'Aviculture'));
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: especeLap, code: 'cuniculture', label: 'Cuniculture'));
    await bande(lotA, 'AVI-ENG-1', 40, especeAvi);
    await bande(lotB, 'LAP-ENG-1', 12, especeLap);
    await produit(poulet, 'Poulet fumé', especeAvi);
    await produit(lapin, 'Lapin fumé', especeLap);
    await produit(universel, 'Fumier', null);
  });
  tearDown(() async => db.close());

  Future<Transformation> ecrire({String lot = '', String sujets = '5', String prod = '', String produite = '5', DateTime? date}) async {
    final r = await depot.enregistrer(
      lotId: lot.isEmpty ? lotA : lot,
      qtyAnimals: sujets,
      productId: prod.isEmpty ? poulet : prod,
      qtyProduced: produite,
      date: date ?? DateTime(2026, 10, 10),
    );
    return r.transformation;
  }

  Future<Map<String, String>> refus(Future<void> Function() geste) async {
    try {
      await geste();
    } on TransformationRefusee catch (e) {
      return e.erreurs;
    }
    return {};
  }

  group('dépôt', () {
    test('⚠️⚠️ le poste n\'écrit QUE le fait : ni l\'effectif de la bande, ni le stock du produit, ni la fiche du jour', () async {
      final t = await ecrire(sujets: '5', produite: '12,5');

      expect((t.lotId, t.productId, t.qtyAnimals, t.qtyProduced, t.syncStatus, t.deviceId), (lotA, poulet, 5, 12.5, SyncStatus.pending, 'poste-test'));
      expect(t.id.length, 36);
      expect(t.transformationDate, DateTime(2026, 10, 10));
      expect((await (db.select(db.livestockLots)..where((l) => l.id.equals(lotA))).getSingle()).currentQuantity, 40);
      expect((await (db.select(db.products)..where((p) => p.id.equals(poulet))).getSingle()).stockQty, 0);
      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
    });

    test('⚠️ les champs vides, mots pour mots ceux du web', () async {
      final e = await refus(() => depot.enregistrer(lotId: '', qtyAnimals: '', productId: '', qtyProduced: '', date: null));

      expect(e, {
        'lotId': 'Le champ bande est obligatoire.',
        'qtyAnimals': "Le champ nombre d'animaux est obligatoire.",
        'productId': 'Le champ produit est obligatoire.',
        'qtyProduced': 'Le champ quantité produite est obligatoire.',
        'transformationDate': 'Le champ date de transformation est obligatoire.',
      });
      expect(await db.select(db.transformations).get(), isEmpty);
    });

    test('l\'effectif disponible tient compte des sujets déjà engagés par ce poste (rien n\'est transformé deux fois)', () async {
      await ecrire(sujets: '30');

      expect((await depot.lots()).firstWhere((l) => l.lot.id == lotA).disponible, 10);
      final e = await refus(() => ecrire(sujets: '11'));
      expect(e, {'qtyAnimals': "La quantité ne peut pas dépasser l'effectif disponible du lot (10)."});
      await ecrire(sujets: '10');
      expect((await depot.lots()).map((l) => l.lot.id), [lotB], reason: 'la bande vidée n\'est plus proposée (effectif > 0 du web)');
    });

    test('exercice clos : refusé sous la date, avec le motif R4 du jour saisi', () async {
      await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(id: uuid('x26'), year: 2026, startDate: Value(DateTime(2026, 1, 1)), endDate: Value(DateTime(2026, 12, 31)), status: const Value('cloture')),
      );

      expect(
        await refus(() => ecrire()),
        {'transformationDate': "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 10/10/2026."},
      );
      expect(await db.select(db.transformations).get(), isEmpty);
    });

    test('la liste des bandes : actives, « actif », effectif > 0, avec l\'espèce ; les produits : ceux de l\'espèce ou sans espèce, actifs, par nom', () async {
      await bande(uuid('a3'), 'AVI-VIDE', 0, especeAvi);
      await bande(uuid('a4'), 'AVI-VENDUE', 9, especeAvi, statut: 'vendu');
      await bande(uuid('a5'), 'AVI-ARCH', 9, especeAvi, active: false);
      await produit(uuid('p4'), 'Archivé', especeAvi, actif: false);

      final lots = await depot.lots();
      expect(lots.map((l) => l.libelle), ['AVI-ENG-1 — 40 sujets (Aviculture)', 'LAP-ENG-1 — 12 sujets (Cuniculture)']);
      expect((await depot.produits(lotA)).map((p) => p.name), ['Fumier', 'Poulet fumé']);
      expect((await depot.produits(lotB)).map((p) => p.name), ['Fumier', 'Lapin fumé']);
      expect(await depot.produits(''), isEmpty);
    });

    test('cartes du mois : transformations et sujets du mois en cours, hors refusées ; historique : 20 dernières, la plus récente d\'abord', () async {
      await ecrire(sujets: '2', date: DateTime(2026, 10, 3));
      final refusee = await ecrire(sujets: '3', date: DateTime(2026, 10, 4));
      await ecrire(sujets: '1', date: DateTime(2026, 9, 28));
      await (db.update(db.transformations)..where((t) => t.id.equals(refusee.id))).write(const TransformationsCompanion(syncStatus: Value(SyncStatus.conflict)));

      final k = await depot.kpis(DateTime(2026, 10, 28));
      expect((k.transformationsDuMois, k.sujetsTransformes), (1, 2));

      for (var i = 0; i < 25; i++) {
        await db.into(db.transformations).insert(
          TransformationsCompanion.insert(
            id: uuid('h${i.toString().padLeft(2, '0')}'), deviceId: 'serveur', syncStatus: const Value(SyncStatus.synced), updatedAt: DateTime(2026, 1, 1),
            lotId: lotA, productId: poulet, qtyAnimals: 1, qtyProduced: 1, transformationDate: DateTime(2025, 1, 1 + i),
          ),
        );
      }
      final h = await depot.historique();
      expect(h, hasLength(20));
      expect(h.first.transformation.transformationDate, DateTime(2026, 10, 4));
      expect(TransformationRepository.quantite(12.5), '12.5');
      expect(TransformationRepository.quantite(5), '5');
      expect(TransformationRepository.quantite(10), '10');
      expect(TransformationRepository.quantite(0.1), '0.1');
    });
  });

  group('moteur', () {
    test('⚠️⚠️ l\'envoi porte le fait seul (UUID du poste), puis le tirage de confirmation rapporte effectif et stock', () async {
      final t = await ecrire(sujets: '5', produite: '12.5');

      await moteur.synchroniser();

      expect(serveur.envois.single['transformations'], [
        {'id': t.id, 'lot_id': lotA, 'product_id': poulet, 'qty_animals': 5, 'qty_produced': 12.5, 'transformation_date': '2026-10-10'},
      ]);
      expect((await (db.select(db.transformations)..where((x) => x.id.equals(t.id))).getSingle()).syncStatus, SyncStatus.synced);
      expect(serveur.tirages, 2, reason: 'tirage, envoi, puis tirage de confirmation (effectif de la bande et stock changés par le serveur)');
    });

    test('rien à envoyer : aucune requête d\'envoi, un seul tirage', () async {
      await moteur.synchroniser();

      expect(serveur.envois, isEmpty);
      expect(serveur.tirages, 1);
    });

    test('un refus du serveur devient conflict avec son motif, visible à l\'historique, et se relance', () async {
      final t = await ecrire();
      serveur.refus[t.id] = "La quantité ne peut pas dépasser l'effectif disponible du lot (3).";

      await moteur.synchroniser();

      expect((await (db.select(db.transformations)..where((x) => x.id.equals(t.id))).getSingle()).syncStatus, SyncStatus.conflict);
      final conflit = (await db.select(db.syncConflicts).get()).firstWhere((x) => x.sourceTable == 'transformations');
      expect(conflit.reason, contains('effectif disponible'));
      expect((await depot.historique()).single.motifRefus, contains('effectif disponible'));
      await moteur.relancer(conflit);
      expect((await (db.select(db.transformations)..where((x) => x.id.equals(t.id))).getSingle()).syncStatus, SyncStatus.pending);
    });

    test('⚠️ l\'absorbeur est STRICT : une saisie en attente ou refusée n\'est jamais écrasée, une acquittée est remplacée', () async {
      final enAttente = await ecrire(sujets: '5');
      final refusee = await ecrire(sujets: '6');
      await (db.update(db.transformations)..where((x) => x.id.equals(refusee.id))).write(const TransformationsCompanion(syncStatus: Value(SyncStatus.conflict)));
      serveur.refus.addAll({}); // rien n'est refusé à l'envoi : le tirage de ce test est le seul sujet
      Map<String, dynamic> ligne(String id, int sujets, {String? lot}) => {
        'id': id, 'lot_id': lot ?? lotA, 'product_id': poulet, 'qty_animals': sujets, 'qty_produced': 7.5,
        'operator_id': uuid('u1'), 'transformation_date': '2026-10-10', 'updated_at': '2026-10-28T12:00:00Z',
      };
      serveur.tirage = {
        'server_time': '2026-10-28T13:00:00Z',
        'transformations': [ligne(enAttente.id, 99), ligne(refusee.id, 98), ligne(uuid('s1'), 4), ligne(uuid('s2'), 2, lot: uuid('inconnue'))],
      };

      // Un envoi sans rien à envoyer : seul le tirage compte (les deux saisies sont gardées hors de l'envoi).
      await (db.update(db.transformations)..where((x) => x.id.equals(enAttente.id))).write(const TransformationsCompanion(syncStatus: Value(SyncStatus.conflict)));
      await moteur.synchroniser();

      final lignes = {for (final t in await db.select(db.transformations).get()) t.id: t};
      expect(lignes[enAttente.id]!.qtyAnimals, 5);
      expect(lignes[refusee.id]!.qtyAnimals, 6);
      expect((lignes[uuid('s1')]!.qtyAnimals, lignes[uuid('s1')]!.syncStatus, lignes[uuid('s1')]!.deviceId, lignes[uuid('s1')]!.operatorId), (4, SyncStatus.synced, 'serveur', uuid('u1')));
      expect(lignes[uuid('s2')], isNotNull, reason: 'une bande inconnue du poste n\'est pas un refus : c\'est un historique');
    });

    test('⚠️ un identifiant servi deux fois, ou une ligne illisible, refuse tout le tirage', () async {
      serveur.tirage = {
        'server_time': '2026-10-28T13:00:00Z',
        'transformations': [
          {'id': uuid('s1'), 'lot_id': lotA, 'product_id': poulet, 'qty_animals': 4, 'qty_produced': 1, 'transformation_date': '2026-10-10'},
          {'id': uuid('s1'), 'lot_id': lotA, 'product_id': poulet, 'qty_animals': 4, 'qty_produced': 1, 'transformation_date': '2026-10-10'},
        ],
      };
      await expectLater(moteur.synchroniser(), throwsA(anything));
      expect(await db.select(db.transformations).get(), isEmpty);
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      await tester.pumpWidget(
        MaterialApp(
          theme: AgriTheme.light,
          home: TransformationScreen(depot: depot, nomOperateur: 'M. Olouchègoun', maintenant: () => DateTime(2026, 10, 28, 10)),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Un `Text` qui porte [t], tel quel ou en capitales (`uppercase` du Blade).
    Finder texte(String t) => find.byWidgetPredicate((w) => w is Text && (w.data == t || w.data == t.toUpperCase()));

    Future<void> choisir(WidgetTester tester, String cle, String libelle) async {
      await tester.tap(find.byKey(Key(cle)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(libelle).last);
      await tester.pumpAndSettle();
    }

    Future<void> saisir(WidgetTester tester, String cle, String valeur) async {
      await tester.enterText(find.descendant(of: find.byKey(Key(cle)), matching: find.byType(TextField)), valeur);
      await tester.pump();
    }

    testWidgets('⚠️ l\'écran porte les libellés du Blade, lus dans le Blade', (tester) async {
      final blade = _lire('resources/views/livewire/elevage/transformation-form.blade.php');
      if (blade == null) {
        markTestSkipped('SAUT : dépôt Laravel absent ($dossierLaravel)');
        return;
      }
      await afficher(tester);
      final corps = _norme(blade);

      for (final t in [
        "Bon d'Abattage & Transformation",
        'Convertit des sujets vivants en produits finis vendables au POS — impact automatique sur le cheptel et le stock.',
        'Transformations (mois)',
        'Sujets Transformés',
        'Valeur Stock Produit Fini',
        '1. Sélection de la Bande Source',
        "Lot / Bande d'Élevage *",
        'Sélectionnez une bande pour voir son effectif disponible.',
        'Nombre de Sujets à Abattre *',
        'Produit Fini Cible *',
        'Quantité Produite (Unités / Kg)',
        'Rendement libre — saisie manuelle sans calcul automatique (poids variable selon transformation).',
        'Date de Transaction',
        'Opérateur',
        'Valider la Transformation',
        'Impact Automatique Prévisualisé',
        'Élevage — Décrémentation',
        "L'effectif vivant de la bande sera réduit du nombre de sujets abattus.",
        'Stock Produits Finis — Incrémentation',
        'Le stock du produit fini choisi sera augmenté de la quantité produite saisie.',
        'Comptabilité — Variation de Stock',
        'Écriture automatique (Débit 313 / Crédit 73) en attente du Sprint 10 (journal comptable) — non générée pour le moment.',
        'Vente au POS',
        "Le produit est immédiatement disponible au catalogue (stock déjà incrémenté). L'imputation au centre analytique arrive avec la comptabilité (Sprint 10).",
        'Historique des Transformations',
        'Aucune transformation enregistrée pour le moment.',
      ]) {
        expect(corps, contains(t), reason: 'le Blade ne porte plus « $t » : mettre l\'écran à jour');
        expect(texte(t), findsWidgets, reason: '« $t » absent de l\'écran');
      }
      for (final c in ['Date', 'Bande Source', 'Sujets Abattus', 'Produit Fini', 'Qté Produite', 'Statut']) {
        expect(corps, contains('>$c</th>'), reason: c);
        expect(find.text(c.toUpperCase()), findsWidgets, reason: c);
      }
      // `x-kpi-card :pending` : la légende est « Disponible après {pending-since} » (composant `kpi-card`).
      expect(corps, contains('pending-since="Sprint 6 (Stocks) — valorisation de stock réelle"'));
      expect(_lire('resources/views/components/kpi-card.blade.php'), contains(r'Disponible après {{ $pendingSince'));
      expect(texte('Disponible après Sprint 6 (Stocks) — valorisation de stock réelle'), findsOneWidget);
      expect(corps, contains('Non comptabilisé'));
      expect(corps, contains('-- Sélectionner --'));
      expect(corps, contains('-- Choisir un produit --'));
      expect(corps, contains('ex : 10'));
      expect(find.text('M. Olouchègoun'), findsOneWidget);
      expect(find.text('-- Sélectionner --'), findsOneWidget);
      expect(find.text('-- Choisir un produit --'), findsOneWidget);
      expect(find.text('ex : 10'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('kpi-valeur-stock-produit-fini')), matching: find.text('—')), findsOneWidget);
    });

    testWidgets('⚠️ « Valider la Transformation » : refus sous les champs (messages du web), puis le fait est écrit et l\'écran remis à zéro', (tester) async {
      await afficher(tester);

      // Produit désactivé tant qu'aucune bande n'est choisie (`@if(!$lotId) disabled`).
      expect(tester.widget<DropdownButton<String>>(find.descendant(of: find.byKey(const Key('transformation-produit')), matching: find.byType(DropdownButton<String>))).onChanged, isNull);

      await tester.tap(find.byKey(const Key('transformation-valider')));
      await tester.pumpAndSettle();
      expect(find.text('Le champ bande est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ produit est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ quantité produite est obligatoire.'), findsOneWidget);
      expect(await db.select(db.transformations).get(), isEmpty);

      await choisir(tester, 'transformation-lot', 'AVI-ENG-1 — 40 sujets (Aviculture)');
      expect(find.textContaining('Effectif disponible : 40 sujets.', findRichText: true), findsOneWidget);
      await choisir(tester, 'transformation-produit', 'Poulet fumé');
      await saisir(tester, 'transformation-sujets', '41');
      await saisir(tester, 'transformation-produite', '12.5');
      await tester.tap(find.byKey(const Key('transformation-valider')));
      await tester.pumpAndSettle();
      expect(find.text("La quantité ne peut pas dépasser l'effectif disponible du lot (40)."), findsOneWidget);

      await saisir(tester, 'transformation-sujets', '5');
      await tester.tap(find.byKey(const Key('transformation-valider')));
      await tester.pumpAndSettle();

      final t = (await db.select(db.transformations).get()).single;
      expect((t.lotId, t.productId, t.qtyAnimals, t.qtyProduced, t.syncStatus), (lotA, poulet, 5, 12.5, SyncStatus.pending));
      expect(find.text('Transformation validée — 5 sujet(s) transformé(s) en Poulet fumé.'), findsOneWidget);
      // Remise à zéro (`reset`) : bande et produit vides, 1 sujet, quantité vide.
      expect(find.text('-- Sélectionner --'), findsOneWidget);
      expect(find.text('-- Choisir un produit --'), findsOneWidget);
      expect(tester.widget<TextField>(find.descendant(of: find.byKey(const Key('transformation-sujets')), matching: find.byType(TextField))).controller!.text, '1');
      // Historique : la ligne, son statut du web et l'état d'envoi du poste ; cartes du mois.
      expect(find.byKey(Key('transformation-ligne-${t.id}')), findsOneWidget);
      expect(find.descendant(of: find.byKey(Key('transformation-ligne-${t.id}')), matching: find.text('AVI-ENG-1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(Key('transformation-ligne-${t.id}')), matching: find.text('Poulet fumé')), findsOneWidget);
      expect(find.descendant(of: find.byKey(Key('transformation-ligne-${t.id}')), matching: find.text('12.5')), findsOneWidget);
      expect(find.descendant(of: find.byKey(Key('transformation-ligne-${t.id}')), matching: find.text('Non comptabilisé')), findsOneWidget);
      expect(find.byKey(Key('transformation-attente-${t.id}')), findsOneWidget);
      expect(find.text("En attente d'envoi"), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('kpi-transformations-mois')), matching: find.text('1')), findsOneWidget, reason: 'le fait est daté du 10/10 : le mois courant l\'inclut');
      expect(find.descendant(of: find.byKey(const Key('kpi-sujets-transformes')), matching: find.text('5')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
