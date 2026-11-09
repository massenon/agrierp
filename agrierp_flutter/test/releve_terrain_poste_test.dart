import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/elevage/dashboard_elevage_repository.dart';
import 'package:agrierp/features/elevage/dashboard_elevage_screen.dart';
import 'package:agrierp/features/elevage/parametres_elevage_repository.dart';
import 'package:agrierp/features/elevage/parametres_elevage_screen.dart';
import 'package:agrierp/features/elevage/releve_terrain.dart';
import 'package:agrierp/features/elevage/releve_terrain_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket RELEVES-1 (poste) — onglet « Relevés de terrain » de Paramètres Élevage : dépôt (UN écrivain), règle
/// « À valider → Validé », moteur de synchronisation (absorbeur STRICT, envoi, acquittement, refus) et écran
/// (modale « Valider »). Les calculs et les refus sont comparés au vrai PHP par `releve_terrain_parite_php_test.dart`,
/// les libellés au Blade par `releve_terrain_blade_test.dart`.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-11-08T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];
  String? refus;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      final ids = [for (final e in corps['field_survey_entries'] as List? ?? const []) (e as Map)['id'] as String];
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            if (corps.containsKey('field_survey_entries'))
              'field_survey_entries': refus == null
                  ? {'accepted': ids, 'rejected': <Object>[]}
                  : {
                      'accepted': <String>[],
                      'rejected': [for (final id in ids) {'id': id, 'reason': refus}],
                    },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

const _idRegle = 'a1000000-0000-4000-8000-000000000001';
const _idGoliath = 'a1000000-0000-4000-8000-000000000002';
const _idDelai = 'a1000000-0000-4000-8000-000000000003';
const _idDensite = 'a1000000-0000-4000-8000-000000000004';

Map<String, dynamic> _ligneServeur(String id, String type, String label, Map<String, dynamic> data, {String? espece, String statut = 'a_valider', bool actif = true}) => {
  'id': id,
  'type': type,
  'label': label,
  'species_code': espece,
  'data': data,
  'status': statut,
  'validated_by': null,
  'validated_by_name': null,
  'validated_at': null,
  'is_active': actif,
  'updated_at': '2026-11-08T08:00:00Z',
};

final _donneesPintade = {'duree_jours': 28, 'eclosion_min': 26, 'eclosion_max': 28, 'mode': 'couveuse_artificielle', 'mirages': [7, 14], 'transfert_jour': 25, 'conservation_max_jours': 10};
final _donneesDelai = {'mode': 'constate', 'marge_jours': 4, 'critique_jours': 3, 'alerte_jours': 7};

Map<String, dynamic> _propositions() => {
  'server_time': '2026-11-08T12:00:00Z',
  'field_survey_entries': [
    _ligneServeur(_idRegle, 'incubation_regle', 'Pintade', _donneesPintade, espece: 'pintade'),
    _ligneServeur(_idGoliath, 'incubation_regle', 'Goliath', {..._donneesPintade, 'duree_jours': 21, 'eclosion_min': 19, 'eclosion_max': 23, 'transfert_jour': null}, espece: 'goliath'),
    _ligneServeur(_idDelai, 'delai_regle', 'Délai fournisseur de provende', _donneesDelai),
    _ligneServeur(_idDensite, 'poisson_densite', "Densité d'empoissonnement", {'densite': null, 'unite': null}, espece: 'poisson_chat'),
  ],
};

void main() {
  late AppDatabase db;
  late ReleveTerrainRepository depot;
  late _Serveur serveur;
  late SyncEngine moteur;
  final horloge = DateTime(2026, 11, 8, 10);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ReleveTerrainRepository(database: db, maintenant: () => horloge);
    serveur = _Serveur();
    moteur = SyncEngine(database: db, client: Dio()..interceptors.add(serveur), deviceId: 'poste-test', connectivity: _Connectivite());
  });

  tearDown(() async => db.close());

  Future<FieldSurveyEntry> ligne(String id) => (db.select(db.fieldSurveyEntries)..where((t) => t.id.equals(id))).getSingle();

  group('dépôt — règle « À valider → Validé »', () {
    test('le tirage sème les propositions « À valider », synced, rien en attente', () async {
      serveur.tirage = _propositions();
      await moteur.synchroniser();

      expect(await depot.nombreAValider(), 4);
      final p = await ligne(_idRegle);
      expect([p.status, p.syncStatus, p.isActive, p.speciesCode], ['a_valider', SyncStatus.synced, true, 'pintade']);
      expect(ReleveTerrainRepository.donnees(p)['duree_jours'], 28);
      expect(await db.pendingCount(), 0);
    });

    test('⚠️⚠️ aucun chemin d enregistrement ne laisse « À valider » : modifier, valider (avec ou sans correction), créer', () async {
      serveur.tirage = _propositions();
      await moteur.synchroniser();

      // Modifier puis enregistrer.
      await depot.modifier(_idRegle, label: 'Pintade', especeCode: 'pintade', data: {..._donneesPintade, 'mirages': '7, 14', 'duree_jours': 27});
      var p = await ligne(_idRegle);
      expect([p.status, p.syncStatus, p.validatedAt != null], ['valide', SyncStatus.pending, true]);
      expect(ReleveTerrainRepository.donnees(p)['duree_jours'], 27);

      // Valider sans rien corriger, puis en corrigeant.
      await depot.valider(_idGoliath);
      expect((await ligne(_idGoliath)).status, 'valide');
      expect(ReleveTerrainRepository.donnees(await ligne(_idGoliath))['duree_jours'], 21);
      await depot.valider(_idDensite, data: {'densite': '50', 'unite': 'poissons/m³'});
      p = await ligne(_idDensite);
      expect([p.status, ReleveTerrainRepository.donnees(p)['densite']], ['valide', 50]);
      await depot.valider(_idDelai);
      expect((await ligne(_idDelai)).status, 'valide');
      expect(await depot.nombreAValider(), 0);

      // Création humaine.
      final id = await depot.creer(ReleveTerrain.incubationLot, label: 'LOT-1', especeCode: 'pintade', data: {'mise_date': '2026-10-01', 'mode': 'couveuse_artificielle', 'oeufs_mis': '100'});
      expect((await ligne(id)).status, 'valide');

      // Seul le serveur sème « À valider » : le dépôt ne l'écrit nulle part (gardé par les sources).
      final source = File('lib/features/elevage/releve_terrain_repository.dart').readAsStringSync();
      expect(source.contains('status: const Value(ReleveTerrain.valide)'), isTrue);
      expect(source.contains("Value('a_valider')"), isFalse);
      expect(source.contains('Value(ReleveTerrain.aValider)'), isFalse);
    });

    test('refus avant écriture, avec les messages du web ; un relevé de lot exige la règle de son espèce', () async {
      serveur.tirage = _propositions();
      await moteur.synchroniser();

      await expectLater(
        depot.creer(ReleveTerrain.incubationLot, label: 'LOT-X', especeCode: 'dinde', data: {'mode': 'couveuse_artificielle', 'oeufs_mis': '10', 'oeufs_fertiles': '12'}),
        throwsA(
          isA<ReleveRefuse>().having((e) => e.erreurs, 'erreurs', {
            'species_code': "Aucune règle d'incubation n'existe pour cette espèce : créez-la d'abord.",
            'data.mise_date': 'Le champ date de mise en incubation est obligatoire.',
            'data.oeufs_fertiles': 'Les œufs fertiles ne peuvent pas dépasser les œufs mis.',
          }),
        ),
      );
      await expectLater(
        depot.creer(ReleveTerrain.incubationRegle, label: 'Pintade bis', especeCode: 'pintade', data: {..._donneesPintade, 'mirages': '7, 14'}),
        throwsA(isA<ReleveRefuse>().having((e) => e.erreurs['species_code'], 'doublon', "Une règle d'incubation existe déjà pour cette espèce.")),
      );
      expect((await db.select(db.fieldSurveyEntries).get()).length, 4);   // rien d'écrit
    });

    test('archiver : logique, en attente d envoi, le statut n est pas touché', () async {
      serveur.tirage = _propositions();
      await moteur.synchroniser();
      await depot.archiver(_idDensite);
      final p = await ligne(_idDensite);
      expect([p.isActive, p.syncStatus, p.status], [false, SyncStatus.pending, 'a_valider']);
      expect(await depot.nombreAValider(), 3);
    });
  });

  group('moteur', () {
    test('⚠️⚠️ STRICT : une ligne pending (validée hors ligne) n est jamais écrasée par un tirage « À valider »', () async {
      serveur.tirage = _propositions();
      await moteur.synchroniser();
      await depot.valider(_idRegle);

      // Le serveur refuse l'envoi : la ligne reste en attente (« conflict »), le tirage « À valider » ne l'écrase pas.
      serveur.refus = 'Refus de test.';
      serveur.tirage = _propositions();
      await moteur.synchroniser();

      final p = await ligne(_idRegle);
      expect([p.status, p.syncStatus], ['valide', SyncStatus.conflict]);
    });

    test('⚠️⚠️ STRICT : type inconnu, statut illisible, identifiant servi deux fois, valeurs illisibles refusent TOUT le tirage', () async {
      final cas = <String, List<Map<String, dynamic>>>{
        'type': [_ligneServeur(_idRegle, 'inconnu', 'x', {})],
        'statut': [_ligneServeur(_idRegle, 'incubation_regle', 'x', {}, statut: 'brouillon')],
        'doublon': [_ligneServeur(_idRegle, 'incubation_regle', 'x', {}), _ligneServeur(_idRegle, 'incubation_regle', 'y', {})],
        'valeurs': [
          {..._ligneServeur(_idRegle, 'incubation_regle', 'x', {}), 'data': 'oups'},
        ],
        'libelle': [_ligneServeur(_idRegle, 'incubation_regle', '', {})],
        'actif': [
          {..._ligneServeur(_idRegle, 'incubation_regle', 'x', {}), 'is_active': 'peut-être'},
        ],
      };
      for (final e in cas.entries) {
        serveur.tirage = {'server_time': '2026-11-08T12:00:00Z', 'field_survey_entries': [..._propositions()['field_survey_entries'] as List, ...e.value]};
        await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()), reason: e.key);
        expect(await db.select(db.fieldSurveyEntries).get(), isEmpty, reason: '${e.key} : rien n\'est écrit');
      }
    });

    test('l envoi : une règle d incubation part AVANT les relevés de lots qui la visent', () async {
      serveur.tirage = _propositions();
      await moteur.synchroniser();
      await depot.creer(ReleveTerrain.incubationLot, label: 'LOT-1', especeCode: 'pintade', data: {'mise_date': '2026-10-01', 'mode': 'couveuse_artificielle', 'oeufs_mis': '100'});
      await depot.valider(_idRegle);

      await moteur.synchroniser();

      final envoyes = (serveur.envois.last['field_survey_entries'] as List).cast<Map<String, dynamic>>();
      expect([for (final e in envoyes) e['type']], ['incubation_regle', 'incubation_lot']);
      expect(await db.pendingCount(), 0);
    });

    test('la ligne envoyée porte type, libellé, espèce, valeurs et is_active — jamais le statut', () async {
      serveur.tirage = _propositions();
      await moteur.synchroniser();
      await depot.valider(_idDensite, data: {'densite': '50', 'unite': 'poissons/m³'});
      await moteur.synchroniser();

      final e = (serveur.envois.last['field_survey_entries'] as List).single as Map<String, dynamic>;
      expect(e, {
        'id': _idDensite,
        'type': 'poisson_densite',
        'label': "Densité d'empoissonnement",
        'species_code': 'poisson_chat',
        'data': {'densite': 50, 'unite': 'poissons/m³'},
        'is_active': true,
        'device_id': 'poste-test',
      });
      expect(e.containsKey('status'), isFalse);
      expect((await ligne(_idDensite)).syncStatus, SyncStatus.synced);
      expect(await db.pendingCount(), 0);
    });

    test('un refus du serveur passe la ligne en conflict avec son motif mot pour mot', () async {
      serveur.tirage = _propositions();
      await moteur.synchroniser();
      await depot.valider(_idDensite, data: {'densite': '50', 'unite': 'x'});
      serveur.refus = 'Votre rôle ne permet pas d\'enregistrer un relevé de terrain.';
      await moteur.synchroniser();

      expect((await ligne(_idDensite)).syncStatus, SyncStatus.conflict);
      final lignes = await depot.lignes('technicien');
      expect(lignes.single.etat.motifRefus, serveur.refus);
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester, {bool droit = true}) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: ParametresElevageScreen(depot: ParametresElevageRepository(database: db, maintenant: () => horloge), peutModifier: droit)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('onglet-parametres-Relevés de terrain')));
      await tester.tap(find.byKey(const Key('onglet-parametres-Relevés de terrain')), warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    Future<void> nettoyer(WidgetTester tester) async {
      ToastAgri.toutRetirer();
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('l onglet liste les propositions « À valider » avec leurs valeurs et un bouton « Valider »', (tester) async {
      await tester.runAsync(() async {
        serveur.tirage = _propositions();
        await moteur.synchroniser();
      });
      await afficher(tester);

      expect(find.text('4 référentiel(s) à valider — Dashboard Élevage'), findsOneWidget);
      expect(find.text('À valider'), findsNWidgets(2));   // deux règles d'incubation (la famille ouverte)
      expect(find.byKey(Key('valider-releve-$_idRegle')), findsOneWidget);
      expect(
        find.text("28 j · éclosion J26 à J28 · Couveuse artificielle · mirages J7, J14 · éclosoir J25 · œufs conservés ≤ 10 j"),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('releves-famille-provende')));
      await tester.pumpAndSettle();
      expect(find.textContaining('critique 3 j · alerte 7 j · marge 4 j'), findsOneWidget);
      expect(find.byKey(const Key('releves-regle-retenue')), findsOneWidget);
      await nettoyer(tester);
    });

    testWidgets('⚠️⚠️ le bouton « Valider » ouvre la modale de mise à jour ; « Valider » passe la ligne à « Validé »', (tester) async {
      await tester.runAsync(() async {
        serveur.tirage = _propositions();
        await moteur.synchroniser();
      });
      await afficher(tester);

      await tester.tap(find.byKey(Key('valider-releve-$_idRegle')));
      await tester.pumpAndSettle();
      expect(find.text('Valider le relevé — Règle d\'incubation'), findsOneWidget);
      expect(find.text('Relisez les valeurs proposées, corrigez-les si besoin, puis validez.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('releve-duree_jours')), '27');
      await tester.tap(find.byKey(const Key('releve-valider')));
      await tester.pumpAndSettle();

      final p = await tester.runAsync(() => ligne(_idRegle));
      expect([p!.status, p.syncStatus, ReleveTerrainRepository.donnees(p)['duree_jours']], ['valide', SyncStatus.pending, 27]);
      expect(find.byKey(Key('valider-releve-$_idRegle')), findsNothing);   // plus de bouton : la ligne est « Validé »
      await nettoyer(tester);
    });

    testWidgets('modifier puis enregistrer passe à « Validé » ; un refus s affiche sous le champ sans rien écrire', (tester) async {
      await tester.runAsync(() async {
        serveur.tirage = _propositions();
        await moteur.synchroniser();
      });
      await afficher(tester);

      await tester.tap(find.byKey(Key('modifier-releve-$_idGoliath')));
      await tester.pumpAndSettle();
      expect(find.text("Modifier le relevé — Règle d'incubation"), findsOneWidget);
      await tester.enterText(find.byKey(const Key('releve-duree_jours')), '70');
      await tester.tap(find.byKey(const Key('releve-enregistrer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('releve-erreur-duree_jours')), findsOneWidget);
      expect(find.text("Le champ durée d'incubation doit être un nombre entier compris entre 1 et 60."), findsOneWidget);
      expect((await tester.runAsync(() => ligne(_idGoliath)))!.status, 'a_valider');

      await tester.enterText(find.byKey(const Key('releve-duree_jours')), '22');
      await tester.tap(find.byKey(const Key('releve-enregistrer')));
      await tester.pumpAndSettle();
      final g = await tester.runAsync(() => ligne(_idGoliath));
      expect([g!.status, ReleveTerrainRepository.donnees(g)['duree_jours']], ['valide', 22]);
      await nettoyer(tester);
    });

    testWidgets('sans le droit manage-elevage : ni « Valider », ni modifier, ni ajouter', (tester) async {
      await tester.runAsync(() async {
        serveur.tirage = _propositions();
        await moteur.synchroniser();
      });
      await afficher(tester, droit: false);

      expect(find.byKey(Key('valider-releve-$_idRegle')), findsNothing);
      expect(find.byKey(Key('modifier-releve-$_idRegle')), findsNothing);
      expect(find.byKey(const Key('ajouter-incubation_regle')), findsNothing);
      expect(find.text('À valider'), findsNWidgets(2));
      await nettoyer(tester);
    });
  });

  group('Dashboard Élevage', () {
    testWidgets('le bloc « Relevés de terrain » : cinq cartes, tirets sans lot, puis les moyennes des lots relevés', (tester) async {
      await tester.runAsync(() async {
        serveur.tirage = _propositions();
        await moteur.synchroniser();
      });
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tableau = DashboardElevageRepository(database: db, soins: SoinsRepository(database: db, deviceId: 'poste-test'));

      Future<void> montrer() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(home: DashboardElevageScreen(depot: tableau)));
        await tester.pumpAndSettle();
      }

      await montrer();
      expect(find.byKey(const Key('cartes-releves')), findsOneWidget);
      expect(find.text('RÉFÉRENTIELS À VALIDER'), findsOneWidget);
      expect(find.text('Aucun lot relevé'), findsNWidgets(2));
      expect(find.text('3 j / 7 j'), findsOneWidget);
      expect(find.text('Règle : —'), findsOneWidget);

      await tester.runAsync(() async {
        await depot.creer(ReleveTerrain.incubationLot, label: 'L1', especeCode: 'pintade', data: {'mise_date': '2026-10-01', 'mode': 'couveuse_artificielle', 'oeufs_mis': '100', 'oeufs_fertiles': '80', 'oeufs_eclos': '60', 'premier_eclos_date': '2026-10-29'});
        await depot.creer(ReleveTerrain.incubationLot, label: 'L2', especeCode: 'pintade', data: {'mise_date': '2026-10-01', 'mode': 'couveuse_artificielle', 'oeufs_mis': '90', 'oeufs_fertiles': '70', 'oeufs_eclos': '50', 'premier_eclos_date': '2026-10-27'});
      });
      await montrer();
      expect(find.text('78,9 %'), findsOneWidget);
      expect(find.text('73,2 %'), findsOneWidget);
      expect(find.text('27 j'), findsOneWidget);
      expect(find.text('Règle : 28 j'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('jsonEncode des valeurs : les entiers restent des entiers (contrat avec le serveur)', () {
    expect(jsonEncode({'a': 28, 'b': 2.5}), '{"a":28,"b":2.5}');
  });
}
