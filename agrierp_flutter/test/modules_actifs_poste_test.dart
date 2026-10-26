import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/theme/symboles_agri.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket MOD1 — MODULES ACTIFS : ACTIVER / DÉSACTIVER AU POSTE (« En poste, je n'arrive pas à activer / désactiver les
/// Modules Actifs », signalé par le client).
///
/// 🔴 CAUSE RACINE (trois défauts qui se cumulaient) :
///  1. l'interrupteur n'était qu'une `Icon` (`toggle_on` / `toggle_off`), sans aucun gestionnaire de clic, et la mention
///     de l'écran disait « le réglage lui-même se fait sur la surface web » ;
///  2. `modules_config` n'était qu'un référentiel descendant : aucune colonne `sync_status`, aucune clé d'envoi, et le
///     serveur comptait tout envoi dans `referentiels_ignored` ;
///  3. l'absorbeur REMPLAÇAIT toute la table à chaque tirage : même avec (1) et (2), une bascule non acquittée serait
///     revenue toute seule à l'ancienne valeur au cycle suivant.
///
/// Ce fichier : l'écran (clic, icônes, toast, persistance), le dépôt (`pending`, valeur explicite), le moteur (envoi,
/// acquittement, refus, absorbeur protecteur), la parité Blade ↔ Dart, et l'ALLER-RETOUR contre le vrai SyncController.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Serveur feint : sert [tirage] ; répond à `modules_config` par [reponse] (défaut : tout accepté).
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-21T09:00:00Z'};
  final List<Map<String, dynamic>> envois = [];
  Map<String, dynamic> Function(List<dynamic> lignes)? reponse;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      final lignes = corps['modules_config'] as List? ?? const [];
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            if (corps.containsKey('modules_config'))
              'modules_config': reponse != null
                  ? reponse!(lignes)
                  : {
                      'accepted': [for (final l in lignes) (l as Map)['id']],
                      'rejected': <Object>[],
                    },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

Map<String, dynamic> _ligneServeur(String code, bool actif) => {
  'id': 'cccccccc-0000-4000-8000-${code.hashCode.abs().toString().padLeft(12, '0').substring(0, 12)}',
  'species_code': code,
  'is_enabled': actif,
};

Map<String, dynamic> _tirage(Map<String, bool> etat) => {
  'server_time': '2026-10-21T09:00:00Z',
  'modules_config': [for (final e in etat.entries) _ligneServeur(e.key, e.value)],
};

void main() {
  late AppDatabase db;
  late ParametresGenerauxRepository depot;
  late _Serveur serveur;
  late SyncEngine moteur;
  var horloge = DateTime(2026, 10, 21, 10);

  const ferme = {'cuniculture': true, 'aviculture': true, 'porciculture': true, 'helico': false};

  setUp(() async {
    horloge = DateTime(2026, 10, 21, 10);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ParametresGenerauxRepository(database: db, maintenant: () => horloge);
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
    );
  });

  tearDown(() async {
    ToastAgri.toutRetirer();
    await db.close();
  });

  /// État local : espèce → (valeur, statut).
  Future<Map<String, (bool, SyncStatus)>> etat() async => {
    for (final m in await db.select(db.modulesConfig).get()) m.speciesCode: (m.isEnabled, m.syncStatus),
  };

  /// Sème l'état d'un tirage directement (les tests de widget ne passent pas par le réseau feint).
  Future<void> semer(Map<String, bool> etatServeur) async {
    for (final e in etatServeur.entries) {
      await db.into(db.modulesConfig).insert(
        ModulesConfigCompanion.insert(
          id: _ligneServeur(e.key, e.value)['id'] as String,
          speciesCode: e.key,
          isEnabled: Value(e.value),
        ),
      );
    }
  }

  /// Pose l'état du serveur au poste par un vrai tirage.
  Future<void> tirer(Map<String, bool> etatServeur) async {
    serveur.tirage = _tirage(etatServeur);
    await moteur.synchroniser();
  }

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ParametresGenerauxScreen(depot: depot)));
    await tester.pumpAndSettle();
    final cible = find.byKey(const Key('onglet-parametres-generaux-Modules Actifs'));
    await tester.ensureVisible(cible);
    await tester.pumpAndSettle();
    await tester.tap(cible);
    await tester.pumpAndSettle();
  }

  group('écran — l\'interrupteur répond au clic', () {
    testWidgets('⚠️⚠️ éteindre un module : écrit localement, icône et toast comme le web', (tester) async {
      await semer(ferme);
      await afficher(tester);
      expect(find.byIcon(SymbolesAgri.toggle_on), findsNWidgets(3));

      await tester.tap(find.byKey(const Key('bascule-module-porciculture')));
      await tester.pumpAndSettle();

      expect((await etat())['porciculture'], (false, SyncStatus.pending));
      expect((await etat())['cuniculture'], (true, SyncStatus.synced), reason: 'indépendamment des autres espèces');
      expect(find.byIcon(SymbolesAgri.toggle_on), findsNWidgets(2));
      expect(find.byIcon(SymbolesAgri.toggle_off), findsNWidgets(2));
      expect(find.text('Modification appliquée avec succès.'), findsOne);
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));
    });

    testWidgets('⚠️ rallumer (l\'héliciculture éteinte par défaut), puis rééteindre', (tester) async {
      await semer(ferme);
      await afficher(tester);

      await tester.tap(find.byKey(const Key('bascule-module-helico')));
      await tester.pumpAndSettle();
      expect((await etat())['helico'], (true, SyncStatus.pending));
      expect(find.byIcon(SymbolesAgri.toggle_on), findsNWidgets(4));
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('bascule-module-helico')));
      await tester.pumpAndSettle();
      expect((await etat())['helico'], (false, SyncStatus.pending));
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));
    });

    testWidgets('⚠️ poste jamais tiré (aucune ligne) : la bascule crée la ligne, actif par défaut → éteint', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('bascule-module-aviculture')));
      await tester.pumpAndSettle();

      expect((await etat())['aviculture'], (false, SyncStatus.pending));
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));
    });

    testWidgets('la mention ne renvoie plus au web et porte le texte du Blade', (tester) async {
      await semer(ferme);
      await afficher(tester);
      expect(find.textContaining('surface web'), findsNothing);
      expect(find.textContaining('réapparaissent dès la réactivation du module.'), findsOne);
    });
  });

  group('effet immédiat sur ce que le poste montre', () {
    test('⚠️ une espèce éteinte disparaît des espèces actives, rallumée elle revient (aucune donnée touchée)', () async {
      await tirer(ferme);
      expect(await depot.especesActives(), {'cuniculture', 'aviculture', 'porciculture'});

      await depot.definirModule(ModuleEspece.porciculture, actif: false);
      expect(await depot.especesActives(), {'cuniculture', 'aviculture'});

      await depot.definirModule(ModuleEspece.helico, actif: true);
      await depot.definirModule(ModuleEspece.porciculture, actif: true);
      expect(await depot.especesActives(), {'cuniculture', 'aviculture', 'porciculture', 'helico'});
    });

    test('⚠️ aucun « au moins un module » : le web n\'impose rien, le poste non plus', () async {
      await tirer(ferme);
      for (final m in ModuleEspece.values) {
        await depot.definirModule(m, actif: false);
      }
      expect(await depot.especesActives(), isEmpty);
    });

    test('⚠️ la comptabilité n\'est jamais touchée par une bascule', () async {
      await tirer(ferme);
      await db.into(db.treasuryAccounts).insert(
        TreasuryAccountsCompanion.insert(id: 'tttttttt-0000-4000-8000-000000000001', label: 'Caisse', accountCode: const Value('531'), type: const Value('caisse')),
      );
      final avant = [(await db.select(db.treasuryAccounts).get()).length, (await db.select(db.accountingEntries).get()).length];
      for (final m in ModuleEspece.values) {
        await depot.definirModule(m, actif: false);
        await depot.definirModule(m, actif: true);
      }
      expect([(await db.select(db.treasuryAccounts).get()).length, (await db.select(db.accountingEntries).get()).length], avant);
    });
  });

  group('moteur — envoi, acquittement, refus', () {
    test('⚠️⚠️ la valeur choisie part au serveur (valeur explicite, id = code de l\'espèce) puis passe synced', () async {
      await tirer(ferme);
      await depot.definirModule(ModuleEspece.porciculture, actif: false);
      expect(await db.pendingCount(), 1, reason: 'le badge de synchronisation compte la bascule');

      serveur.tirage = _tirage({...ferme, 'porciculture': false});
      await moteur.synchroniser();

      final envoi = serveur.envois.singleWhere((e) => e.containsKey('modules_config'));
      expect(envoi['modules_config'], [
        {'id': 'porciculture', 'species_code': 'porciculture', 'is_enabled': false},
      ]);
      expect((await etat())['porciculture'], (false, SyncStatus.synced));
      expect(await db.pendingCount(), 0);
    });

    test('rien n\'est envoyé tant qu\'aucun module n\'a été basculé', () async {
      await tirer(ferme);
      await moteur.synchroniser();
      expect(serveur.envois.any((e) => e.containsKey('modules_config')), isFalse);
    });

    test('⚠️ un refus du serveur (droit manage-modules) met la ligne en conflit AVEC son motif, sans la perdre', () async {
      await tirer(ferme);
      await depot.definirModule(ModuleEspece.aviculture, actif: false);
      serveur.reponse = (lignes) => {
        'accepted': <String>[],
        'rejected': [
          for (final l in lignes) {'id': (l as Map)['id'], 'reason': 'Refusé : votre rôle ne permet pas d\'activer ou désactiver un module.'},
        ],
      };

      await moteur.synchroniser();

      expect((await etat())['aviculture'], (false, SyncStatus.conflict));
      final refus = await db.select(db.syncConflicts).get();
      expect(refus.single.reason, contains('activer ou désactiver un module'));
    });

    test('⚠️ une bascule refaite PENDANT l\'envoi n\'est pas marquée synced sur l\'accusé de l\'ancienne', () async {
      await tirer(ferme);
      await depot.definirModule(ModuleEspece.aviculture, actif: false);
      serveur.reponse = (lignes) {
        horloge = horloge.add(const Duration(minutes: 1));
        // rallumée entre l'envoi et l'accusé
        db.update(db.modulesConfig).write(ModulesConfigCompanion(
          isEnabled: const Value(true),
          updatedAt: Value(horloge.toUtc()),
        ));
        return {'accepted': [for (final l in lignes) (l as Map)['id']], 'rejected': <Object>[]};
      };
      serveur.tirage = _tirage({...ferme, 'aviculture': false});
      await moteur.synchroniser();
      await Future<void>.delayed(Duration.zero);

      expect((await etat())['aviculture']!.$2, SyncStatus.pending, reason: 'la nouvelle valeur repartira');
    });
  });

  group('moteur — tirage : la bascule ne « revient » pas toute seule', () {
    test('⚠️⚠️ un tirage qui renvoie l\'ANCIENNE valeur n\'écrase pas une bascule non acquittée', () async {
      await tirer(ferme);
      await depot.definirModule(ModuleEspece.porciculture, actif: false);
      // Le serveur n'a pas encore reçu la bascule : il sert toujours « porciculture actif ». On coupe l'envoi.
      serveur.reponse = (lignes) => {'accepted': <String>[], 'rejected': <Object>[]};
      serveur.tirage = _tirage(ferme);

      await moteur.synchroniser();
      await moteur.synchroniser();

      expect((await etat())['porciculture'], (false, SyncStatus.pending));
      expect((await depot.charger()).moduleActif(ModuleEspece.porciculture), isFalse);
    });

    test('⚠️ un module éteint AU WEB s\'éteint au poste au tirage suivant, et rallumé au web il se rallume', () async {
      await tirer(ferme);
      expect((await depot.charger()).moduleActif(ModuleEspece.aviculture), isTrue);

      await tirer({...ferme, 'aviculture': false});
      expect((await etat())['aviculture'], (false, SyncStatus.synced));
      expect((await depot.charger()).moduleActif(ModuleEspece.aviculture), isFalse);

      await tirer(ferme);
      expect((await etat())['aviculture'], (true, SyncStatus.synced));
    });

    test('⚠️ une bascule en attente pour une espèce que le tirage ne liste pas n\'est pas perdue', () async {
      await depot.definirModule(ModuleEspece.helico, actif: true);
      serveur.reponse = (lignes) => {'accepted': <String>[], 'rejected': <Object>[]};
      serveur.tirage = _tirage({'cuniculture': true});

      await moteur.synchroniser();

      expect((await etat())['helico'], (true, SyncStatus.pending));
      expect((await etat())['cuniculture'], (true, SyncStatus.synced));
    });
  });

  group('parité Blade ↔ Dart (le web est le maître)', () {
    final blade = File('$dossierLaravel/resources/views/livewire/parametres/modules-actifs.blade.php');
    final composant = File('$dossierLaravel/app/Livewire/Parametres/ModulesActifs.php');
    final graines = File('$dossierLaravel/database/seeders/LivestockSpeciesSeeder.php');
    final ecran = File('lib/features/parametres/parametres_generaux_screen.dart');
    final saute = !blade.existsSync() ? 'SAUT : Blade absent (${blade.path})' : null;

    String lire(File f) => f.readAsStringSync().replaceAll('\r\n', '\n');

    test('titre, sous-titre et carte d\'information : mot pour mot', () {
      final b = lire(blade).replaceAll('&#039;', "'");
      final d = lire(ecran);
      expect(b, contains('Modules Actifs'));
      const sousTitre = "Activez ou désactivez indépendamment chaque espèce d'élevage. La désactivation masque les menus et "
          'onglets concernés, sans jamais toucher à la comptabilité générale.';
      expect(b, contains(sousTitre));
      expect(d.replaceAll(RegExp(r"""['"]\s*\n\s*['"]"""), ''), contains(sousTitre.substring(0, 40)));
      for (final morceau in [
        'Ces réglages sont appliqués immédiatement sur tous les onglets de',
        'Gestion Élevage',
        'Dashboard Élevage',
        'Les données déjà enregistrées d\'une espèce désactivée restent conservées et réapparaissent dès la réactivation du module.',
      ]) {
        expect(b.replaceAll(RegExp(r'</?strong>'), ''), contains(morceau));
      }
    }, skip: saute);

    test('descriptions, pastille FUTUR et message de retour identiques au Blade et au composant', () {
      final b = lire(blade);
      expect(b, contains('Fiches, VMS, catalogue POS liés à cette filière'));
      expect(b, contains('Module en préparation — désactivé par défaut'));
      expect(b, contains('FUTUR'));
      expect(b, contains('info-blue'), reason: 'la pastille FUTUR et la carte sont bleues au web');
      final d = lire(ecran);
      expect(d, contains('Fiches, VMS, catalogue POS liés à cette filière'));
      expect(d, contains('Module en préparation — désactivé par défaut'));
      expect(d, contains("_pastille('FUTUR', couleur: AgriColors.infoBlue)"));
      expect(d, contains('couleur: AgriColors.infoBlue'));
      expect(d, isNot(contains('liés aux lapins')));

      final php = lire(composant);
      expect(php, contains("message: '${ParametresGenerauxScreenAccesTest.message}'"));
      expect(php, contains("authorize('manage-modules')"));
      expect(php, contains('ModuleConfig::definir'));
    }, skip: saute);

    test('les espèces, libellés et icônes de l\'onglet sont ceux du référentiel serveur', () {
      final php = lire(graines);
      final lignes = RegExp(r"\['code' => '(\w+)', 'label' => '([^']+)', 'is_enabled' => (true|false), 'icon' => '(\w+)'\]")
          .allMatches(php)
          .toList();
      expect(lignes.length, ModuleEspece.values.length, reason: 'une espèce de plus au serveur = une ligne de plus au poste');
      for (final (i, m) in lignes.indexed) {
        expect(ModuleEspece.values[i].code, m.group(1));
        expect(ModuleEspece.values[i].libelle, m.group(2));
        // « FUTUR » = espèce non exploitée au référentiel (`livestock_species.is_enabled = false`).
        expect(m.group(3) == 'false', ModuleEspece.values[i] == ModuleEspece.helico);
        expect(lire(ecran), contains('ModuleEspece.${ModuleEspece.values[i].name}: SymbolesAgri.${m.group(4)}'), reason: 'icône du Blade');
      }
    }, skip: !graines.existsSync() ? 'SAUT : seeder absent' : null);
  });

  group('⚠️⚠️ ALLER-RETOUR contre le VRAI serveur PHP (SyncController, absorbeur, tirage)', () {
    final saut = sautSansPhp();

    const script = r'''<?php
use Illuminate\Http\Request;
use Laravel\Sanctum\Sanctum;
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
Artisan::call('db:seed', ['--class' => 'Database\\Seeders\\RolesAndPermissionsSeeder', '--force' => true]);
Artisan::call('db:seed', ['--class' => 'Database\\Seeders\\LivestockSpeciesSeeder', '--force' => true]);
Artisan::call('db:seed', ['--class' => 'Database\\Seeders\\ModulesConfigSeeder', '--force' => true]);
App\Models\CompanySetting::current();
$u = App\Models\User::create(['name' => 'Admin', 'username' => 'admin', 'email' => 'admin@fermeolouwachegoun.com', 'password' => bcrypt('x'), 'is_active' => true]);
$u->assignRole($in['role']);
Sanctum::actingAs($u, ['*']);
$noyau = $app->make(Illuminate\Contracts\Http\Kernel::class);
$tirer = fn () => json_decode($noyau->handle(Request::create('/api/sync/pull?page=1', 'GET', [], [], [], ['HTTP_ACCEPT' => 'application/json']))->getContent(), true);
$sortie = ['avant' => $tirer()];
if (isset($in['envoi'])) {
    $r = $noyau->handle(Request::create('/api/sync/push', 'POST', [], [], [], ['CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json'], json_encode($in['envoi'])));
    $sortie['statut'] = $r->getStatusCode();
    $sortie['push'] = json_decode($r->getContent(), true);
    // Pendant ce temps, au WEB : l'aviculture est éteinte par le vrai composant Livewire.
    Livewire\Livewire::actingAs($u)->test(App\Livewire\Parametres\ModulesActifs::class)->call('toggleModule', 'aviculture');
    $sortie['apres'] = $tirer();
}
echo json_encode($sortie);
''';

    test('⚠️⚠️ poste → serveur → web → poste : rien n\'est écrasé, tout converge', () async {
      // 1. L'état du serveur au démarrage, tiré par le poste.
      final depart = executerPhp(script, {'role': 'admin'}, application: true) as Map<String, dynamic>;
      serveur.tirage = depart['avant'] as Map<String, dynamic>;
      await moteur.synchroniser();
      expect((await etat())['porciculture'], (true, SyncStatus.synced));
      expect((await etat())['helico'], (false, SyncStatus.synced));

      // 2. Au poste : on éteint les porcs, on allume l'héliciculture. Le serveur n'a encore rien reçu : il sert
      //    l'ancien état, que le poste absorbe SANS le laisser écraser ses bascules.
      await depot.definirModule(ModuleEspece.porciculture, actif: false);
      await depot.definirModule(ModuleEspece.helico, actif: true);
      serveur.reponse = (lignes) => {'accepted': <String>[], 'rejected': <Object>[]};
      await moteur.synchroniser();
      expect((await etat())['porciculture'], (false, SyncStatus.pending), reason: 'tirage périmé : la bascule reste');
      expect((await etat())['helico'], (true, SyncStatus.pending));
      final envoi = serveur.envois.lastWhere((e) => e.containsKey('modules_config'));

      // 3. Le VRAI serveur reçoit l'envoi du poste, puis l'administrateur éteint l'aviculture AU WEB.
      final r = executerPhp(script, {'role': 'admin', 'envoi': envoi}, application: true) as Map<String, dynamic>;
      expect(r['statut'], 200);
      final acquittement = (r['push'] as Map)['modules_config'] as Map;
      expect(acquittement['rejected'], isEmpty, reason: 'le serveur réel accepte le format du poste');
      expect((acquittement['accepted'] as List).toSet(), {'porciculture', 'helico'});
      final serveurApres = {
        for (final m in (r['apres'] as Map)['modules_config'] as List) (m as Map)['species_code'] as String: m['is_enabled'] == true || m['is_enabled'] == 1,
      };
      expect(serveurApres, {'cuniculture': true, 'aviculture': false, 'porciculture': false, 'helico': true});

      // 4. Le poste reçoit l'accusé du vrai serveur puis son vrai tirage : il converge, rien n'est en attente.
      serveur.reponse = (_) => Map<String, dynamic>.from(acquittement);
      serveur.tirage = r['apres'] as Map<String, dynamic>;
      await moteur.synchroniser();

      expect(await etat(), {
        'cuniculture': (true, SyncStatus.synced),
        'aviculture': (false, SyncStatus.synced),
        'porciculture': (false, SyncStatus.synced),
        'helico': (true, SyncStatus.synced),
      });
      expect(await db.pendingCount(), 0);
    }, skip: saut);

    test('⚠️ un compte sans manage-modules est refusé par le vrai serveur : conflit avec motif au poste', () async {
      final depart = executerPhp(script, {'role': 'caissier'}, application: true) as Map<String, dynamic>;
      serveur.tirage = depart['avant'] as Map<String, dynamic>;
      await moteur.synchroniser();
      await depot.definirModule(ModuleEspece.cuniculture, actif: false);
      serveur.reponse = (lignes) => {'accepted': <String>[], 'rejected': <Object>[]};
      await moteur.synchroniser();
      final envoi = serveur.envois.lastWhere((e) => e.containsKey('modules_config'));

      final r = executerPhp(script, {'role': 'caissier', 'envoi': envoi}, application: true) as Map<String, dynamic>;
      final acquittement = (r['push'] as Map)['modules_config'] as Map;
      expect(acquittement['accepted'], isEmpty);

      serveur.reponse = (_) => Map<String, dynamic>.from(acquittement);
      await moteur.synchroniser();

      expect((await etat())['cuniculture'], (false, SyncStatus.conflict));
      expect((await db.select(db.syncConflicts).get()).single.reason, contains('activer ou désactiver un module'));
    }, skip: saut);
  });
}

/// Constantes partagées avec le Blade (un seul endroit où le message du web est répété dans ce fichier).
abstract final class ParametresGenerauxScreenAccesTest {
  static const message = 'Modification appliquée avec succès.';
}
