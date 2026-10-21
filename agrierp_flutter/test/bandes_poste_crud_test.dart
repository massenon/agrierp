import 'package:agrierp/core/comptabilite/exercice_de_saisie.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/gestes_importants.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/elevage/bandes_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket BS1 — « BANDES & SUJETS » AU POSTE : CRÉER, MODIFIER, ARCHIVER UNE BANDE (repository et file de synchronisation).
///
/// Maître : `app/Livewire/Elevage/GestionBandes.php` et `app/Actions/SaisieBandeAction.php`. Valeurs attendues écrites
/// à la main (jamais relues du code testé). L'écran est vérifié dans `bandes_ecran_poste_test.dart`, les libellés du
/// Blade dans `bandes_blade_test.dart`, les messages contre le PHP exécuté dans `bandes_parite_test.dart`.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Serveur feint : sert [tirage], garde chaque envoi, accepte tout sauf les bandes de [refusees].
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-21T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];
  final Map<String, String> refusees = {};

  /// Ce que l'exploitant fait PENDANT l'envoi, avant la réponse du serveur.
  Future<void> Function()? avantReponse;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      await avantReponse?.call();
      final reponse = <String, dynamic>{};
      for (final MapEntry(:key, :value) in corps.entries) {
        if (value is! List) continue;
        final ids = [for (final e in value) if (e is Map && e['id'] is String) e['id'] as String];
        reponse[key] = {
          'accepted': [for (final id in ids) if (key != 'livestock_lots' || !refusees.containsKey(id)) id],
          'rejected': [
            if (key == 'livestock_lots')
              for (final id in ids)
                if (refusees.containsKey(id)) {'id': id, 'reason': refusees[id]},
          ],
        };
      }
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: reponse));
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late BandesRepository depot;
  var signaux = 0;

  const lapins = 'aaaaaaaa-0000-4000-8000-0000000000a1';
  const volailles = 'aaaaaaaa-0000-4000-8000-0000000000a2';
  const mere = 'bbbbbbbb-0000-4000-8000-000000000001';
  final maintenant = DateTime(2026, 10, 21, 10, 30);

  String uuid(String graine) => graine.padRight(36, '0');

  Future<void> especes() async {
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: lapins, code: 'cuniculture', label: 'Cuniculture'));
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: volailles, code: 'aviculture', label: 'Aviculture'));
    for (final code in ['cuniculture', 'aviculture']) {
      await db.into(db.modulesConfig).insert(ModulesConfigCompanion.insert(id: uuid('mod-$code'), speciesCode: code));
    }
  }

  Future<void> bande(
    String id,
    String code, {
    String espece = lapins,
    String stade = 'reproduction',
    int initial = 10,
    int courant = 10,
    String statut = 'actif',
    bool active = true,
    SyncStatus sync = SyncStatus.synced,
    DateTime? creee,
  }) => db.into(db.livestockLots).insert(
    LivestockLotsCompanion.insert(
      id: id,
      code: code,
      speciesId: espece,
      speciesCode: Value(espece == lapins ? 'cuniculture' : 'aviculture'),
      stage: Value(stade),
      initialQuantity: Value(initial),
      currentQuantity: Value(courant),
      createdDate: Value(creee ?? DateTime(2026, 9, 1)),
      status: Value(statut),
      isActive: Value(active),
      syncStatus: Value(sync),
    ),
  );

  Future<LivestockLot?> lue(String id) => (db.select(db.livestockLots)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> exercice(int annee, String statut) => db.into(db.fiscalYears).insert(
    FiscalYearsCompanion.insert(
      id: uuid('ex$annee'),
      year: annee,
      startDate: Value(DateTime(annee)),
      endDate: Value(DateTime(annee, 12, 31)),
      status: Value(statut),
    ),
  );

  FormulaireBande formulaire({
    String espece = lapins,
    String code = 'LOT-LAP-9',
    String stade = 'reproduction',
    DateTime? date,
    String quantite = '12',
    String cout = '',
    String produit = '',
    String origine = '',
  }) => FormulaireBande(
    speciesId: espece,
    code: code,
    stage: stade,
    createdDate: date ?? DateTime(2026, 10, 20),
    quantite: quantite,
    coutAcquisition: cout,
    productId: produit,
    lotOrigineId: origine,
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    signaux = 0;
    final gestes = GestesImportants()..addListener(() => signaux++);
    depot = BandesRepository(database: db, deviceId: 'poste-test', gestes: gestes, horloge: () => maintenant);
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => maintenant,
    );
    await especes();
  });

  tearDown(() async => db.close());

  group('créer', () {
    test('⚠️ la bande naît au poste : UUID, effectif initial = courant, actif, EN FILE (pending), signal de synchronisation', () async {
      final creee = await depot.creer(formulaire(cout: '135000'));

      expect(creee.id, hasLength(36));
      expect(
        [creee.code, creee.stage, creee.initialQuantity, creee.currentQuantity, creee.status, creee.isActive, creee.speciesCode],
        ['LOT-LAP-9', 'reproduction', 12, 12, 'actif', true, 'cuniculture'],
      );
      expect(creee.createdDate, DateTime(2026, 10, 20));
      expect(creee.acquisitionCost, 135000);
      expect(creee.syncStatus, SyncStatus.pending);
      expect(creee.effectifCorrige, isNull);
      expect(signaux, 1);
    });

    test('⚠️ le formulaire vide a les quatre messages du web, un par champ', () async {
      await expectLater(
        depot.creer(const FormulaireBande()),
        throwsA(
          isA<BandeRefusee>().having((e) => e.erreurs, 'erreurs', {
            'species_id': 'Le champ espèce est obligatoire.',
            'code': 'Le champ code est obligatoire.',
            'created_date': 'Le champ date de création est obligatoire.',
            'quantity': 'Le champ quantité doit être au moins égal à 1.',
          }),
        ),
      );
      expect(await db.select(db.livestockLots).get(), isEmpty);
    });

    test('code déjà pris (même en majuscules, même archivé), code de plus de 50 caractères, quantité nulle ou négative', () async {
      await bande(mere, 'LOT-LAP-1', active: false);

      Future<Map<String, String>> erreurs(FormulaireBande f) async {
        try {
          await depot.creer(f);
        } on BandeRefusee catch (e) {
          return e.erreurs;
        }
        return {};
      }

      expect(await erreurs(formulaire(code: 'lot-lap-1')), {'code': 'La valeur du champ code est déjà utilisée.'});
      expect(await erreurs(formulaire(code: 'x' * 51)), {'code': 'Le champ code ne doit pas dépasser 50 caractères.'});
      expect(await erreurs(formulaire(quantite: '0')), {'quantity': 'Le champ quantité doit être au moins égal à 1.'});
      expect(await erreurs(formulaire(quantite: '-4')), {'quantity': 'Le champ quantité doit être au moins égal à 1.'});
      expect(await erreurs(formulaire(stade: 'ponte')), {'stage': "La valeur sélectionnée pour le champ stade n'est pas valide."});
      expect(await db.select(db.livestockLots).get(), hasLength(1));
    });

    test('⚠️⚠️ une bande datée dans un exercice CLOS est refusée avant d écrire, avec le motif R4 du serveur', () async {
      await exercice(2025, 'cloture');
      await exercice(2026, 'ouvert');

      await expectLater(
        depot.creer(formulaire(date: DateTime(2025, 12, 20))),
        throwsA(
          isA<RefusExercice>().having((e) => e.motif, 'motif', "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025."),
        ),
      );
      expect(await db.select(db.livestockLots).get(), isEmpty);
      expect(signaux, 0);

      await depot.creer(formulaire(date: DateTime(2026, 1, 5)));
      expect(await db.select(db.livestockLots).get(), hasLength(1));
    });

    test('⚠️ la constitution (bande d origine) est un transfert EN FILE et sort les sujets de la bande mère : un seul comptage', () async {
      await bande(mere, 'LOT-LAP-MERE', initial: 10, courant: 10, creee: DateTime(2026, 9, 1));
      await db.into(db.livestockDailyEntries).insert(
        LivestockDailyEntriesCompanion.insert(
          id: uuid('f1'),
          deviceId: 'serveur',
          updatedAt: DateTime(2026, 9, 1),
          lotId: mere,
          entryDate: DateTime(2026, 9, 1),
          effectifFinal: const Value(10),
          syncStatus: const Value(SyncStatus.synced),
          catDepartRepro: const Value(10),
          catDepartSevre: const Value(0),
          catDepartJeune: const Value(0),
        ),
      );

      final creee = await depot.creer(
        formulaire(code: 'LOT-LAP-PORTEE', stade: 'croissance', quantite: '4', date: DateTime(2026, 9, 10), origine: mere),
      );

      final transferts = await db.select(db.livestockTransfers).get();
      expect(transferts, hasLength(1));
      expect(
        [transferts.single.sourceLotId, transferts.single.targetLotId, transferts.single.quantity, transferts.single.constitution, transferts.single.categorie, transferts.single.motif, transferts.single.syncStatus],
        [mere, creee.id, 4, true, 'sevre', 'Constitution de la bande LOT-LAP-PORTEE', SyncStatus.pending],
      );
      expect((await lue(mere))!.currentQuantity, 6, reason: '10 - 4 sortis de la bande mère');
      expect((await lue(creee.id))!.currentQuantity, 4, reason: 'aucune entrée dans la bande constituée');
    });

    test('⚠️ une constitution impossible refuse la bande entière (rien n est écrit) avec le motif du transfert', () async {
      await bande(mere, 'LOT-LAP-MERE', initial: 3, courant: 3);

      await expectLater(
        depot.creer(formulaire(code: 'LOT-LAP-PORTEE', stade: 'croissance', quantite: '9', date: DateTime(2026, 9, 10), origine: mere)),
        throwsA(isA<BandeRefusee>().having((e) => e.erreurs.keys, 'champs', ['lot_origine_id'])),
      );

      expect(await db.select(db.livestockLots).get(), hasLength(1), reason: 'seule la bande mère');
      expect(await db.select(db.livestockTransfers).get(), isEmpty);
    });
  });

  group('modifier', () {
    test('⚠️ stade et statut changent, la ligne repart EN FILE ; l effectif n est PAS envoyé sans correction explicite', () async {
      await bande(mere, 'LOT-LAP-1', courant: 10);

      await depot.modifier(mere, stage: 'engraissement', quantite: '10', status: 'cloture');

      final b = (await lue(mere))!;
      expect([b.stage, b.status, b.currentQuantity, b.syncStatus, b.effectifCorrige], ['engraissement', 'cloture', 10, SyncStatus.pending, null]);
      expect(b.initialQuantity, 10);
      expect(b.code, 'LOT-LAP-1');
      expect(signaux, 1);
    });

    test('⚠️ une correction de l effectif actuel est écrite et marquée à envoyer (effectifCorrige)', () async {
      await bande(mere, 'LOT-LAP-1', courant: 10);

      await depot.modifier(mere, stage: 'reproduction', quantite: '7', status: 'actif');

      final b = (await lue(mere))!;
      expect([b.currentQuantity, b.effectifCorrige, b.syncStatus], [7, 7, SyncStatus.pending]);
    });

    test('⚠️ une modification qui ne change rien n écrit rien : la bande reste synchronisée, aucun signal', () async {
      await bande(mere, 'LOT-LAP-1', courant: 10);

      await depot.modifier(mere, stage: 'reproduction', quantite: '10', status: 'actif');

      expect((await lue(mere))!.syncStatus, SyncStatus.synced);
      expect(signaux, 0);
    });

    test('les messages du web : stade, effectif (au moins 0), statut', () async {
      await bande(mere, 'LOT-LAP-1');

      Future<Map<String, String>> erreurs(String stade, String quantite, String statut) async {
        try {
          await depot.modifier(mere, stage: stade, quantite: quantite, status: statut);
        } on BandeRefusee catch (e) {
          return e.erreurs;
        }
        return {};
      }

      expect(await erreurs('reproduction', '-1', 'actif'), {'quantity': 'Le champ quantité doit être au moins égal à 0.'});
      expect(await erreurs('ponte', '3', 'actif'), {'stage': "La valeur sélectionnée pour le champ stade n'est pas valide."});
      expect(await erreurs('reproduction', '3', 'vendu'), {'status': "La valeur sélectionnée pour le champ statut n'est pas valide."});
      expect((await lue(mere))!.currentQuantity, 10);
    });

    test('⚠️ une bande ARCHIVÉE n est plus modifiable (le motif du web)', () async {
      await bande(mere, 'LOT-LAP-1', active: false);

      await expectLater(
        depot.modifier(mere, stage: 'engraissement', quantite: '10', status: 'actif'),
        throwsA(isA<BandeRefusee>().having((e) => e.erreurs, 'erreurs', {'bande': 'Cette bande est archivée : elle ne peut plus être modifiée.'})),
      );
      expect((await lue(mere))!.stage, 'reproduction');
    });
  });

  group('archiver', () {
    test('⚠️ archiver est LOGIQUE : is_active = false, la ligne et son effectif sont gardés, EN FILE', () async {
      await bande(mere, 'LOT-LAP-1', courant: 8);

      expect(await depot.archiver(mere), isTrue);

      final b = (await lue(mere))!;
      expect([b.isActive, b.status, b.currentQuantity, b.syncStatus], [false, 'actif', 8, SyncStatus.pending]);
      expect(signaux, 1);
    });

    test('⚠️ un second archivage ne fait rien : ni mise en file, ni signal', () async {
      await bande(mere, 'LOT-LAP-1', active: false);

      expect(await depot.archiver(mere), isFalse);

      expect((await lue(mere))!.syncStatus, SyncStatus.synced);
      expect(signaux, 0);
    });

    test('une bande archivée quitte la liste et les indicateurs', () async {
      await bande(mere, 'LOT-LAP-1', courant: 8);
      await bande(uuid('b2'), 'LOT-LAP-2', courant: 5);

      await depot.archiver(mere);

      expect([for (final l in await depot.bandes()) l.bande.code], ['LOT-LAP-2']);
      final k = await depot.indicateurs();
      expect([k.bandesActives, k.effectifTotal], [1, 5]);
    });
  });

  group('lire', () {
    test('⚠️ indicateurs : bandes VIVANTES seulement (statut actif ET non archivée), reproduction, effectif, alertes par bande', () async {
      await bande(uuid('b1'), 'A', stade: 'reproduction', courant: 10);
      await bande(uuid('b2'), 'B', stade: 'croissance', courant: 20);
      await bande(uuid('b3'), 'C', stade: 'reproduction', courant: 40, statut: 'cloture');
      await bande(uuid('b4'), 'D', stade: 'reproduction', courant: 80, active: false);
      for (final (id, lot, fin) in [
        ('p1', uuid('b1'), DateTime(2026, 10, 21)),
        ('p2', uuid('b1'), DateTime(2026, 10, 25)),
        ('p3', uuid('b2'), DateTime(2026, 10, 20)),
        ('p4', uuid('b3'), DateTime(2026, 10, 30)),
      ]) {
        await db.into(db.veterinaryWithdrawalPeriods).insert(
          VeterinaryWithdrawalPeriodsCompanion.insert(id: uuid(id), lotId: lot, endDate: fin),
        );
      }

      final k = await depot.indicateurs();

      expect([k.bandesActives, k.enReproduction, k.effectifTotal], [2, 1, 30]);
      expect(k.alertesSanitaires, 1, reason: 'bande A (deux délais en cours = une alerte) ; B expiré hier ; C clôturée');
    });

    test('tableau : les plus récentes d abord, recherche sur le code, filtre d espèce, mortalité arrondie au dixième', () async {
      await bande(uuid('b1'), 'LOT-LAP-1', initial: 8, courant: 7, creee: DateTime(2026, 9, 1));
      await bande(uuid('b2'), 'LOT-VOL-1', espece: volailles, stade: 'ponte', initial: 3, courant: 3, creee: DateTime(2026, 10, 1));
      await bande(uuid('b3'), 'LOT-LAP-2', initial: 0, courant: 0, creee: DateTime(2026, 8, 1));

      final toutes = await depot.bandes();
      expect([for (final l in toutes) l.bande.code], ['LOT-VOL-1', 'LOT-LAP-1', 'LOT-LAP-2']);
      expect([for (final l in toutes) l.mortalite], [0.0, 12.5, null]);
      expect([for (final l in toutes) BandesRepository.formaterMortalite(l.mortalite)], ['0%', '12.5%', '—']);
      expect([for (final l in toutes) l.libelleStade], ['Ponte', 'Reproducteur', 'Reproducteur']);
      expect([for (final l in await depot.bandes(recherche: 'lap')) l.bande.code], ['LOT-LAP-1', 'LOT-LAP-2']);
      expect([for (final l in await depot.bandes(filiere: 'aviculture')) l.bande.code], ['LOT-VOL-1']);
    });

    test('le prochain code continue la séquence de l espèce (préfixes par défaut de la migration du web)', () async {
      await bande(uuid('b1'), 'LOT-LAP-3');
      await bande(uuid('b2'), 'LOT-LAP-12');
      await bande(uuid('b3'), 'LOT-VOL-4', espece: volailles);

      expect(await depot.codeSuggere(lapins), 'LOT-LAP-13');
      expect(await depot.codeSuggere(volailles), 'LOT-VOL-5');
    });

    test('les espèces proposées sont celles dont le module est actif, par libellé', () async {
      await db.update(db.modulesConfig).write(const ModulesConfigCompanion(isEnabled: Value(false)));
      await (db.update(db.modulesConfig)..where((t) => t.speciesCode.equals('aviculture'))).write(const ModulesConfigCompanion(isEnabled: Value(true)));

      expect([for (final e in await depot.especes()) e.code], ['aviculture']);
    });
  });

  group('file de synchronisation', () {
    test('⚠️⚠️ une bande créée part avec sa ligne exacte, AVANT les fiches ; l accusé la passe synced et ne vide que ce qui est parti', () async {
      final creee = await depot.creer(formulaire(cout: '135000'));

      await moteur.synchroniser();

      final envoi = serveur.envois.single;
      expect(envoi['livestock_lots'], [
        {
          'id': creee.id,
          'code': 'LOT-LAP-9',
          'species_id': lapins,
          'stage': 'reproduction',
          'created_date': '2026-10-20',
          'initial_quantity': 12,
          'acquisition_cost': 135000.0,
          'product_id': null,
          'status': 'actif',
          'is_active': true,
          'device_id': 'poste-test',
        },
      ]);
      expect((await lue(creee.id))!.syncStatus, SyncStatus.synced);
    });

    test('⚠️ une correction d effectif part avec la ligne (effectif_corrige), puis est vidée à l accusé', () async {
      await bande(mere, 'LOT-LAP-1', courant: 10);
      await depot.modifier(mere, stage: 'reproduction', quantite: '7', status: 'actif');

      await moteur.synchroniser();

      expect((serveur.envois.single['livestock_lots'] as List).single['effectif_corrige'], 7);
      final b = (await lue(mere))!;
      expect([b.syncStatus, b.effectifCorrige], [SyncStatus.synced, null]);
    });

    test('⚠️ SANS correction, la ligne ne porte PAS d effectif : il appartient aux fiches', () async {
      await bande(mere, 'LOT-LAP-1', courant: 10);
      await depot.modifier(mere, stage: 'engraissement', quantite: '10', status: 'actif');

      await moteur.synchroniser();

      final ligne = (serveur.envois.single['livestock_lots'] as List).single as Map;
      expect(ligne.containsKey('effectif_corrige'), isFalse);
      expect(ligne.containsKey('current_quantity'), isFalse);
      expect(ligne['stage'], 'engraissement');
    });

    test('un archivage part avec is_active = false', () async {
      await bande(mere, 'LOT-LAP-1');
      await depot.archiver(mere);

      await moteur.synchroniser();

      expect((serveur.envois.single['livestock_lots'] as List).single['is_active'], false);
      expect((await lue(mere))!.syncStatus, SyncStatus.synced);
    });

    test('⚠️⚠️ un REFUS du serveur passe la bande en conflit, avec son motif mot pour mot (jamais retour silencieux en pending)', () async {
      final creee = await depot.creer(formulaire());
      serveur.refusees[creee.id] = 'La valeur du champ code existe déjà.';

      await moteur.synchroniser();

      expect((await lue(creee.id))!.syncStatus, SyncStatus.conflict);
      final conflits = await db.select(db.syncConflicts).get();
      expect([conflits.single.sourceTable, conflits.single.recordId, conflits.single.reason], ['livestock_lots', creee.id, 'La valeur du champ code existe déjà.']);
      expect((await depot.bandes()).single.motifRefus, 'La valeur du champ code existe déjà.');

      // Elle n est pas renvoyée tant qu elle n est pas relancée.
      serveur.envois.clear();
      await moteur.synchroniser();
      expect(serveur.envois.where((e) => e.containsKey('livestock_lots')), isEmpty);
    });

    test('⚠️ une bande corrigée PENDANT l envoi de sa version précédente reste en file et repart', () async {
      await bande(mere, 'LOT-LAP-1');
      await depot.modifier(mere, stage: 'croissance', quantite: '10', status: 'actif');
      // Pendant l envoi, l exploitant la corrige encore : l accusé de la première version ne doit pas l acquitter.
      serveur.avantReponse = () async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await (db.update(db.livestockLots)..where((t) => t.id.equals(mere))).write(
          LivestockLotsCompanion(stage: const Value('engraissement'), updatedAt: Value(DateTime.utc(2026, 10, 21, 11)), syncStatus: const Value(SyncStatus.pending)),
        );
      };

      await moteur.synchroniser();

      expect((await lue(mere))!.syncStatus, SyncStatus.pending);
    });

    test('⚠️ relancer remet une bande refusée en file', () async {
      final creee = await depot.creer(formulaire());
      serveur.refusees[creee.id] = 'Refus.';
      await moteur.synchroniser();
      final conflit = (await db.select(db.syncConflicts).get()).single;

      await moteur.relancer(conflit);

      expect((await lue(creee.id))!.syncStatus, SyncStatus.pending);
    });

    test('la bande figure parmi les tables envoyées (compteur « à envoyer » de la barre) et les tables perdues à la réinitialisation', () async {
      expect(AppDatabase.tablesEnvoyees, contains('livestock_lots'));
      await bande(mere, 'LOT-LAP-1', sync: SyncStatus.pending);
      await bande(uuid('b2'), 'LOT-LAP-2', sync: SyncStatus.conflict);

      final c = await db.compteursSynchronisation();

      expect([c.aEnvoyer, c.refuses], [1, 1]);
    });
  });

  group('tirage (absorbeur)', () {
    Map<String, dynamic> servie(String id, {String code = 'LOT-WEB-1', int courant = 30, bool actif = true}) => {
      'id': id,
      'code': code,
      'species_id': lapins,
      'species_code': 'cuniculture',
      'stage': 'croissance',
      'initial_quantity': 30,
      'current_quantity': courant,
      'created_date': '2026-09-01',
      'status': 'actif',
      'is_active': actif,
      'updated_at': '2026-10-21T10:00:00+01:00',
    };

    test('une bande du web descend, acquittée (synced)', () async {
      serveur.tirage = {'server_time': '2026-10-21T12:00:00Z', 'livestock_lots': [servie(uuid('w1'))]};

      await moteur.synchroniser();

      final b = (await lue(uuid('w1')))!;
      expect([b.code, b.currentQuantity, b.syncStatus, b.isActive], ['LOT-WEB-1', 30, SyncStatus.synced, true]);
    });

    test('⚠️ une bande synchronisée prend la dernière version du serveur, archivage compris', () async {
      await bande(mere, 'LOT-LAP-1', courant: 10);
      serveur.tirage = {'server_time': '2026-10-21T12:00:00Z', 'livestock_lots': [servie(mere, code: 'LOT-LAP-1', courant: 44, actif: false)]};

      await moteur.synchroniser();

      final b = (await lue(mere))!;
      expect([b.currentQuantity, b.isActive], [44, false]);
    });

    for (final statut in [SyncStatus.pending, SyncStatus.conflict]) {
      test('⚠️⚠️ une bande locale ${statut.name} n est JAMAIS écrasée par le tirage', () async {
        await bande(mere, 'LOT-LAP-1', courant: 10, stade: 'engraissement', sync: statut);
        serveur.tirage = {'server_time': '2026-10-21T12:00:00Z', 'livestock_lots': [servie(mere, code: 'LOT-LAP-1', courant: 44, actif: false)]};

        await moteur.synchroniser();

        final b = (await lue(mere))!;
        expect([b.stage, b.currentQuantity, b.isActive], ['engraissement', 10, true]);
        if (statut == SyncStatus.conflict) expect(b.syncStatus, SyncStatus.conflict);
      });
    }

    for (final (cas, fautive) in <(String, Map<String, dynamic>)>[
      ('identifiant invalide', servie('court')),
      ('servie deux fois', servie(uuid('w1'))),
      ('code absent', servie(uuid('w2'), code: '')..remove('code')),
      ('effectif illisible', servie(uuid('w2'))..['current_quantity'] = 'beaucoup'),
      ('effectif négatif', servie(uuid('w2'), courant: -3)),
      ('date de création illisible', servie(uuid('w2'))..['created_date'] = 'hier'),
      ('archivage illisible', servie(uuid('w2'))..['is_active'] = 'peut-être'),
    ]) {
      test('⚠️⚠️ STRICT — $cas : toute la page est refusée, rien n est écrit, le curseur ne bouge pas', () async {
        await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
        final curseur = (await db.etatDeSynchronisation())?.lastPulledAt;
        serveur.tirage = {'server_time': '2026-10-21T12:00:00Z', 'livestock_lots': [servie(uuid('w1')), fautive]};

        await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));

        expect(await db.select(db.livestockLots).get(), isEmpty);
        expect((await db.etatDeSynchronisation())?.lastPulledAt, curseur);
      });
    }
  });
}
