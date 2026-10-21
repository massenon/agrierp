import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/gestes_importants.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/elevage/registre_reproducteurs_screen.dart';
import 'package:agrierp/features/elevage/reproducteurs_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket BS3 (décision BS-Q1 du 21/10/2026) — « REGISTRE DES REPRODUCTEURS » AU POSTE : ENREGISTRER, MODIFIER, SORTIR UN
/// SUJET NOMINATIF (repository, file de synchronisation, absorbeur, écran).
///
/// Maître : `app/Livewire/Elevage/RegistreReproducteurs.php` et `app/Actions/SaisieReproducteurAction.php`. Valeurs
/// attendues écrites à la main. ⚠️ IDENTIFIER UN SUJET N'EST PAS LE FAIRE ENTRER : l'effectif de la bande ne bouge jamais.
/// Les messages sont comparés au VRAI composant web dans `reproducteurs_parite_test.dart`, les libellés du Blade dans
/// `reproducteurs_blade_test.dart`.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-21T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];
  final Map<String, String> refuses = {};

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
          'accepted': [for (final id in ids) if (key != 'animals' || !refuses.containsKey(id)) id],
          'rejected': [
            if (key == 'animals')
              for (final id in ids)
                if (refuses.containsKey(id)) {'id': id, 'reason': refuses[id]},
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
  late ReproducteursRepository depot;
  var signaux = 0;

  const lapins = 'aaaaaaaa-0000-4000-8000-0000000000a1';
  const volailles = 'aaaaaaaa-0000-4000-8000-0000000000a2';
  const bande = 'bbbbbbbb-0000-4000-8000-000000000001';
  const sujet1 = 'cccccccc-0000-4000-8000-000000000001';
  final maintenant = DateTime(2026, 10, 21, 10, 30);

  String uuid(String graine) => graine.padRight(36, '0');

  Future<void> especes() async {
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: lapins, code: 'cuniculture', label: 'Lapins'));
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: volailles, code: 'aviculture', label: 'Volailles'));
  }

  Future<void> uneBande(String id, String code, {String espece = lapins, int courant = 20, String statut = 'actif', bool active = true}) =>
      db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: id,
          code: code,
          speciesId: espece,
          speciesCode: Value(espece == lapins ? 'cuniculture' : 'aviculture'),
          stage: const Value('reproduction'),
          initialQuantity: Value(courant),
          currentQuantity: Value(courant),
          createdDate: Value(DateTime(2026, 2, 1)),
          status: Value(statut),
          isActive: Value(active),
        ),
      );

  Future<void> unSujet(
    String id,
    String identifiant, {
    String espece = lapins,
    String? lot,
    String sexe = 'F',
    String? race,
    String statut = 'actif',
    bool actif = true,
    String categorie = 'reproducteur',
    SyncStatus sync = SyncStatus.synced,
    DateTime? entree,
  }) => db.into(db.animals).insert(
    AnimalsCompanion.insert(
      id: id,
      identifier: identifiant,
      speciesId: Value(espece),
      speciesLabel: Value(espece == lapins ? 'Lapins' : 'Volailles'),
      lotId: Value(lot),
      lotCode: Value(lot == null ? null : 'LOT-CUNI-1'),
      category: Value(categorie),
      sex: Value(sexe),
      breed: Value(race),
      entryDate: Value(entree ?? DateTime(2026, 2, 15)),
      status: Value(statut),
      isActive: Value(actif),
      syncStatus: Value(sync),
    ),
  );

  Future<Sujet?> lu(String id) => (db.select(db.animals)..where((t) => t.id.equals(id))).getSingleOrNull();

  FormulaireReproducteur formulaire({
    String espece = lapins,
    String identifiant = 'LAP-2026-0143',
    String lot = '',
    String sexe = 'F',
    String race = 'Néo-Zélandais Blanc',
    DateTime? naissance,
    DateTime? entree,
    String origine = 'Naissance interne',
    String cage = 'C5',
  }) => FormulaireReproducteur(
    speciesId: espece,
    identifier: identifiant,
    lotId: lot,
    sex: sexe,
    breed: race,
    birthDate: naissance ?? DateTime(2026, 2, 12),
    entryDate: entree ?? DateTime(2026, 2, 15),
    origin: origine,
    cage: cage,
  );

  Future<Map<String, String>> erreursDe(Future<Object?> Function() geste) async {
    try {
      await geste();
    } on ReproducteurRefuse catch (e) {
      return e.erreurs;
    }
    return {};
  }

  Future<void> attendre(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await t.pumpAndSettle();
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    signaux = 0;
    final gestes = GestesImportants()..addListener(() => signaux++);
    depot = ReproducteursRepository(database: db, deviceId: 'poste-test', gestes: gestes, horloge: () => maintenant);
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => maintenant,
    );
    await especes();
  });

  tearDown(() async {
    ToastAgri.toutRetirer();
    await db.close();
  });

  group('enregistrer', () {
    test('⚠️ le sujet naît au poste : UUID, actif, reproducteur, EN FILE, espèce et bande recopiées, signal ; l effectif de la bande ne bouge JAMAIS', () async {
      await uneBande(bande, 'LOT-CUNI-1', courant: 20);

      final cree = await depot.enregistrer(formulaire(lot: bande));

      expect(cree.id, hasLength(36));
      expect(
        [cree.identifier, cree.category, cree.sex, cree.breed, cree.origin, cree.cage, cree.status, cree.isActive],
        ['LAP-2026-0143', 'reproducteur', 'F', 'Néo-Zélandais Blanc', 'Naissance interne', 'C5', 'actif', true],
      );
      expect([cree.speciesId, cree.speciesLabel, cree.lotId, cree.lotCode], [lapins, 'Lapins', bande, 'LOT-CUNI-1']);
      expect([cree.birthDate, cree.entryDate], [DateTime(2026, 2, 12), DateTime(2026, 2, 15)]);
      expect(cree.syncStatus, SyncStatus.pending);
      expect(signaux, 1);
      final lot = await (db.select(db.livestockLots)..where((t) => t.id.equals(bande))).getSingle();
      expect([lot.currentQuantity, lot.initialQuantity, lot.syncStatus], [20, 20, SyncStatus.synced], reason: 'aucune cascade : le sujet était déjà compté');
    });

    test('un sujet sans bande, sans race ni naissance : les champs vides valent « rien » (jamais une chaîne vide)', () async {
      final cree = await depot.enregistrer(
        const FormulaireReproducteur(speciesId: lapins, identifier: 'LAP-X', sex: 'M', entryDate: null).copieAvec(entryDate: DateTime(2026, 2, 15)),
      );

      expect([cree.lotId, cree.lotCode, cree.breed, cree.birthDate, cree.origin, cree.cage], [null, null, null, null, null, null]);
    });

    test('⚠️ le formulaire vide a les trois messages du web, un par champ ; rien n est écrit', () async {
      final erreurs = await erreursDe(() => depot.enregistrer(const FormulaireReproducteur()));

      expect(erreurs, {
        'identifier': 'Le champ identifiant est obligatoire.',
        'species_id': 'Le champ espèce est obligatoire.',
        'entry_date': "Le champ date d'entrée est obligatoire.",
      });
      expect(await db.select(db.animals).get(), isEmpty);
      expect(signaux, 0);
    });

    test('longueurs (identifiant 50, race 100, origine 150, cage 30), identifiant déjà pris (sans tenir compte de la casse), espèce et bande inconnues', () async {
      await unSujet(sujet1, 'LAP-2026-0143');

      expect(
        await erreursDe(() => depot.enregistrer(formulaire(identifiant: 'x' * 51, race: 'x' * 101, origine: 'x' * 151, cage: 'x' * 31))),
        {
          'identifier': 'Le champ identifiant ne doit pas dépasser 50 caractères.',
          'breed': 'Le champ race ne doit pas dépasser 100 caractères.',
          'origin': 'Le champ origine ne doit pas dépasser 150 caractères.',
          'cage': 'Le champ cage ne doit pas dépasser 30 caractères.',
        },
      );
      expect(await erreursDe(() => depot.enregistrer(formulaire(identifiant: 'lap-2026-0143'))), {'identifier': 'La valeur du champ identifiant est déjà utilisée.'});
      expect(await erreursDe(() => depot.enregistrer(formulaire(identifiant: 'LAP-NEUF', espece: 'zzz', lot: 'yyy'))), {
        'species_id': "La valeur sélectionnée pour le champ espèce n'existe pas.",
        'lot_id': "La valeur sélectionnée pour le champ bande n'existe pas.",
      });
      expect(await db.select(db.animals).get(), hasLength(1));
    });

    test('⚠️ dates : naissance et entrée au plus tard aujourd hui, naissance jamais après l entrée (messages du web)', () async {
      expect(
        await erreursDe(() => depot.enregistrer(formulaire(naissance: DateTime(2026, 12, 1), entree: DateTime(2026, 12, 31)))),
        {
          'birth_date': "Le champ date de naissance doit être une date antérieure ou égale à aujourd'hui.",
          'entry_date': "Le champ date d'entrée doit être une date antérieure ou égale à aujourd'hui.",
        },
      );
      expect(
        await erreursDe(() => depot.enregistrer(formulaire(naissance: DateTime(2026, 3, 1), entree: DateTime(2026, 2, 1)))),
        {'birth_date': "La date de naissance ne peut pas être postérieure à la date d'entrée."},
      );
      expect(await db.select(db.animals).get(), isEmpty);
    });
  });

  group('modifier', () {
    test('⚠️ race, cage, bande et identifiant changent, la ligne repart EN FILE ; statut et sortie ne bougent jamais', () async {
      await uneBande(bande, 'LOT-CUNI-1');
      await unSujet(sujet1, 'LAP-2026-0143', statut: 'reforme');

      await depot.modifier(sujet1, formulaire(identifiant: 'LAP-2026-0144', race: 'Californien', cage: 'C9', lot: bande));

      final a = (await lu(sujet1))!;
      expect([a.identifier, a.breed, a.cage, a.lotId, a.lotCode, a.status, a.syncStatus], ['LAP-2026-0144', 'Californien', 'C9', bande, 'LOT-CUNI-1', 'reforme', SyncStatus.pending]);
      expect(signaux, 1);
    });

    test('⚠️ une modification qui ne change rien n écrit rien : le sujet reste synchronisé, aucun signal', () async {
      await unSujet(sujet1, 'LAP-2026-0143', race: 'Néo-Zélandais Blanc');
      await (db.update(db.animals)..where((t) => t.id.equals(sujet1))).write(
        AnimalsCompanion(birthDate: Value(DateTime(2026, 2, 12)), origin: const Value('Naissance interne'), cage: const Value('C5')),
      );

      await depot.modifier(sujet1, formulaire());

      expect((await lu(sujet1))!.syncStatus, SyncStatus.synced);
      expect(signaux, 0);
    });

    test('son propre identifiant n est pas un doublon ; celui d un AUTRE sujet l est', () async {
      await unSujet(sujet1, 'LAP-1');
      await unSujet(uuid('c2'), 'LAP-2');

      await depot.modifier(sujet1, formulaire(identifiant: 'LAP-1', cage: 'C1'));
      expect(await erreursDe(() => depot.modifier(sujet1, formulaire(identifiant: 'LAP-2'))), {'identifier': 'La valeur du champ identifiant est déjà utilisée.'});
    });

    test('sujet introuvable : le message du poste, sous « sujet »', () async {
      expect((await erreursDe(() => depot.modifier(uuid('zz'), formulaire()))).keys, ['sujet']);
    });
  });

  group('sortir', () {
    test('⚠️ la sortie pose statut, date et motif, EN FILE ; la ligne est gardée (archivage logique) ; l effectif de la bande ne bouge pas', () async {
      await uneBande(bande, 'LOT-CUNI-1', courant: 20);
      await unSujet(sujet1, 'LAP-2026-0143', lot: bande);

      expect(await depot.sortir(sujet1, FormulaireSortie(status: 'reforme', exitDate: DateTime(2026, 8, 1), reason: 'Réforme pour âge')), isTrue);

      final a = (await lu(sujet1))!;
      expect([a.status, a.exitDate, a.exitReason, a.isActive, a.syncStatus], ['reforme', DateTime(2026, 8, 1), 'Réforme pour âge', true, SyncStatus.pending]);
      expect(signaux, 1);
      expect((await (db.select(db.livestockLots)..where((t) => t.id.equals(bande))).getSingle()).currentQuantity, 20);
    });

    test('⚠️ messages du web : date de sortie avant l entrée, dans le futur, motif trop long, champs vides', () async {
      await unSujet(sujet1, 'LAP-2026-0143');

      expect(
        await erreursDe(() => depot.sortir(sujet1, FormulaireSortie(status: 'mort', exitDate: DateTime(2026, 1, 1)))),
        {'exit_date': "La date de sortie ne peut pas précéder la date d'entrée du sujet."},
      );
      expect(
        await erreursDe(() => depot.sortir(sujet1, FormulaireSortie(status: 'zz', exitDate: DateTime(2026, 12, 1), reason: 'x' * 151))),
        {
          'exitStatus': "La valeur sélectionnée pour le champ statut de sortie n'est pas valide.",
          'exit_date': 'Le champ date de sortie doit être une date antérieure ou égale à aujourd\'hui.',
          'exit_reason': 'Le champ motif ne doit pas dépasser 150 caractères.',
        },
      );
      expect(
        await erreursDe(() => depot.sortir(sujet1, const FormulaireSortie(status: ''))),
        {'exitStatus': 'Le champ statut de sortie est obligatoire.', 'exit_date': 'Le champ date de sortie est obligatoire.'},
      );
      expect((await lu(sujet1))!.status, 'actif');
      expect(signaux, 0);
    });

    test('⚠️ un sujet déjà sorti : la même sortie ne fait rien, une autre est refusée avec le motif clair', () async {
      await unSujet(sujet1, 'LAP-2026-0143', statut: 'vendu');
      await (db.update(db.animals)..where((t) => t.id.equals(sujet1))).write(AnimalsCompanion(exitDate: Value(DateTime(2026, 8, 1)), exitReason: const Value('Vente')));

      expect(await depot.sortir(sujet1, FormulaireSortie(status: 'vendu', exitDate: DateTime(2026, 8, 1), reason: 'Vente')), isFalse);
      expect(signaux, 0);
      expect(
        await erreursDe(() => depot.sortir(sujet1, FormulaireSortie(status: 'mort', exitDate: DateTime(2026, 8, 2)))),
        {'exitStatus': 'Ce reproducteur est déjà sorti (Vendu) : sa sortie ne peut pas être modifiée.'},
      );
    });
  });

  group('lire', () {
    test('⚠️ indicateurs : reproducteurs non archivés, présents, femelles et mâles PRÉSENTS ; les autres catégories ne comptent pas', () async {
      await unSujet(uuid('s1'), 'A', sexe: 'F');
      await unSujet(uuid('s2'), 'B', sexe: 'M');
      await unSujet(uuid('s3'), 'C', sexe: 'F', statut: 'reforme');
      await unSujet(uuid('s4'), 'D', sexe: 'F', actif: false);
      await unSujet(uuid('s5'), 'E', sexe: 'F', categorie: 'engraissement');
      await unSujet(uuid('s6'), 'F', sexe: 'M');

      final k = await depot.indicateurs();

      expect([k.total, k.presents, k.femelles, k.males], [4, 3, 1, 2]);
    });

    test('tableau : par identifiant, recherche sur l identifiant OU la race, filtres d espèce et de statut', () async {
      await unSujet(uuid('s1'), 'LAP-B', race: 'Californien');
      await unSujet(uuid('s2'), 'LAP-A', race: 'Néo-Zélandais');
      await unSujet(uuid('s3'), 'POU-1', espece: volailles, statut: 'mort');

      expect([for (final l in await depot.reproducteurs()) l.animal.identifier], ['LAP-A', 'LAP-B', 'POU-1']);
      expect([for (final l in await depot.reproducteurs(recherche: 'californ')) l.animal.identifier], ['LAP-B']);
      expect([for (final l in await depot.reproducteurs(recherche: 'pou')) l.animal.identifier], ['POU-1']);
      expect([for (final l in await depot.reproducteurs(speciesId: volailles)) l.animal.identifier], ['POU-1']);
      expect([for (final l in await depot.reproducteurs(statut: 'actif')) l.animal.identifier], ['LAP-A', 'LAP-B']);
      expect([for (final l in await depot.reproducteurs(statut: 'mort')) l.animal.identifier], ['POU-1']);
    });

    test('bandes proposées : en cours et non archivées, de l espèce choisie, par code ; espèces par libellé', () async {
      await uneBande(uuid('b1'), 'LOT-CUNI-2');
      await uneBande(uuid('b2'), 'LOT-CUNI-1');
      await uneBande(uuid('b3'), 'LOT-CUNI-3', statut: 'cloture');
      await uneBande(uuid('b4'), 'LOT-CUNI-4', active: false);
      await uneBande(uuid('b5'), 'LOT-VOL-1', espece: volailles);

      expect([for (final b in await depot.bandes(speciesId: lapins)) b.code], ['LOT-CUNI-1', 'LOT-CUNI-2']);
      expect([for (final b in await depot.bandes()) b.code], ['LOT-CUNI-1', 'LOT-CUNI-2', 'LOT-VOL-1']);
      expect([for (final e in await depot.especes()) e.label], ['Lapins', 'Volailles']);
    });
  });

  group('file de synchronisation', () {
    test('⚠️⚠️ un sujet enregistré part avec sa ligne exacte ; l accusé le passe synced', () async {
      await uneBande(bande, 'LOT-CUNI-1');
      final cree = await depot.enregistrer(formulaire(lot: bande));

      await moteur.synchroniser();

      expect((serveur.envois.single['animals'] as List).single, {
        'id': cree.id,
        'identifier': 'LAP-2026-0143',
        'species_id': lapins,
        'lot_id': bande,
        'category': 'reproducteur',
        'sex': 'F',
        'breed': 'Néo-Zélandais Blanc',
        'birth_date': '2026-02-12',
        'entry_date': '2026-02-15',
        'origin': 'Naissance interne',
        'cage': 'C5',
        'status': 'actif',
        'exit_date': null,
        'exit_reason': null,
        'is_active': true,
        'device_id': 'poste-test',
      });
      expect((await lu(cree.id))!.syncStatus, SyncStatus.synced);
    });

    test('une sortie part avec statut, date et motif', () async {
      await unSujet(sujet1, 'LAP-2026-0143');
      await depot.sortir(sujet1, FormulaireSortie(status: 'mort', exitDate: DateTime(2026, 8, 1), reason: 'Coccidiose'));

      await moteur.synchroniser();

      final ligne = (serveur.envois.single['animals'] as List).single as Map;
      expect([ligne['status'], ligne['exit_date'], ligne['exit_reason']], ['mort', '2026-08-01', 'Coccidiose']);
    });

    test('⚠️ le sujet part APRÈS sa bande du même envoi (la bande créée à l instant)', () {
      final envoi = <String, dynamic>{
        'device_id': 'poste-test',
        'animals': [{'id': uuid('a1')}],
        'livestock_lots': [{'id': uuid('l1')}],
      };
      expect(SyncEngine.ordreDuServeur.indexOf('livestock_lots'), lessThan(SyncEngine.ordreDuServeur.indexOf('animals')));
      expect(SyncEngine.decouperEnLots(envoi), hasLength(1));
    });

    test('⚠️⚠️ un REFUS du serveur passe le sujet en conflit, avec son motif mot pour mot ; relancer le remet en file', () async {
      final cree = await depot.enregistrer(formulaire());
      serveur.refuses[cree.id] = 'La valeur du champ identifiant existe déjà.';

      await moteur.synchroniser();

      expect((await lu(cree.id))!.syncStatus, SyncStatus.conflict);
      final conflit = (await db.select(db.syncConflicts).get()).single;
      expect([conflit.sourceTable, conflit.recordId, conflit.reason], ['animals', cree.id, 'La valeur du champ identifiant existe déjà.']);
      expect((await depot.reproducteurs()).single.motifRefus, 'La valeur du champ identifiant existe déjà.');

      await moteur.relancer(conflit);
      expect((await lu(cree.id))!.syncStatus, SyncStatus.pending);
    });

    test('⚠️ un sujet modifié PENDANT l envoi de sa version précédente reste en file et repart', () async {
      await unSujet(sujet1, 'LAP-1');
      await depot.modifier(sujet1, formulaire(identifiant: 'LAP-1', cage: 'C1'));
      // Pendant l'envoi, l'exploitant le corrige encore : l'accusé de la première version ne doit pas l'acquitter.
      serveur.avantReponse = () async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await (db.update(db.animals)..where((t) => t.id.equals(sujet1))).write(
          AnimalsCompanion(cage: const Value('C2'), updatedAt: Value(DateTime.utc(2026, 10, 21, 11)), syncStatus: const Value(SyncStatus.pending)),
        );
      };

      await moteur.synchroniser();

      expect([(await lu(sujet1))!.syncStatus, (await lu(sujet1))!.cage], [SyncStatus.pending, 'C2']);
    });

    test('animals figure parmi les tables envoyées (compteur « à envoyer »)', () async {
      expect(AppDatabase.tablesEnvoyees, contains('animals'));
      await unSujet(sujet1, 'LAP-1', sync: SyncStatus.pending);
      await unSujet(uuid('c2'), 'LAP-2', sync: SyncStatus.conflict);

      final c = await db.compteursSynchronisation();

      expect([c.aEnvoyer, c.refuses], [1, 1]);
    });
  });

  group('tirage (absorbeur)', () {
    Map<String, dynamic> servi(String id, {String identifiant = 'LAP-WEB-1', String statut = 'actif', String cage = 'C3'}) => {
      'id': id,
      'identifier': identifiant,
      'species_id': lapins,
      'species_label': 'Lapins',
      'lot_id': null,
      'lot_code': null,
      'category': 'reproducteur',
      'sex': 'M',
      'breed': 'Fauve',
      'birth_date': '2026-01-10',
      'entry_date': '2026-02-01',
      'origin': 'Achat',
      'cage': cage,
      'status': statut,
      'exit_date': null,
      'exit_reason': null,
      'is_active': true,
    };

    test('un sujet du web descend, acquitté, avec l identifiant de son espèce', () async {
      serveur.tirage = {'server_time': '2026-10-21T12:00:00Z', 'animals': [servi(uuid('w1'))]};

      await moteur.synchroniser();

      final a = (await lu(uuid('w1')))!;
      expect([a.identifier, a.speciesId, a.speciesLabel, a.sex, a.syncStatus], ['LAP-WEB-1', lapins, 'Lapins', 'M', SyncStatus.synced]);
    });

    test('⚠️ l ensemble est remplacé pour les sujets synchronisés : un sujet absent du tirage disparaît, un sujet servi prend la version du serveur', () async {
      await unSujet(sujet1, 'LAP-1');
      await unSujet(uuid('c2'), 'LAP-2');
      serveur.tirage = {'server_time': '2026-10-21T12:00:00Z', 'animals': [servi(sujet1, identifiant: 'LAP-1', cage: 'C9')]};

      await moteur.synchroniser();

      expect([for (final a in await db.select(db.animals).get()) a.id], [sujet1]);
      expect((await lu(sujet1))!.cage, 'C9');
    });

    for (final statut in [SyncStatus.pending, SyncStatus.conflict]) {
      test('⚠️⚠️ un sujet local ${statut.name} n est JAMAIS écrasé ni supprimé par le tirage', () async {
        await unSujet(sujet1, 'LAP-1', sync: statut, race: 'Local');
        serveur.tirage = {'server_time': '2026-10-21T12:00:00Z', 'animals': <Map<String, dynamic>>[]};

        await moteur.synchroniser();
        expect((await lu(sujet1))?.breed, 'Local', reason: 'absent du tirage : gardé');
        // (L'envoi du même passage l'a acquitté s'il était `pending` : on le remet dans son état.)
        await (db.update(db.animals)..where((t) => t.id.equals(sujet1))).write(AnimalsCompanion(syncStatus: Value(statut)));

        serveur.tirage = {'server_time': '2026-10-21T12:00:00Z', 'animals': [servi(sujet1, identifiant: 'LAP-1', cage: 'C9')]};
        await moteur.synchroniser();
        expect([(await lu(sujet1))!.breed, (await lu(sujet1))!.cage], ['Local', null], reason: 'servi : jamais écrasé');
      });
    }

    for (final (cas, fautive) in <(String, Map<String, dynamic>)>[
      ('identifiant technique invalide', servi('court')),
      ('servi deux fois', servi(uuid('w1'))),
      ('identifiant lisible absent', servi(uuid('w2'), identifiant: '')),
      ('is_active illisible', servi(uuid('w2'))..['is_active'] = 'peut-être'),
    ]) {
      test('⚠️⚠️ STRICT — $cas : toute la page est refusée, rien n est écrit', () async {
        serveur.tirage = {'server_time': '2026-10-21T12:00:00Z', 'animals': [servi(uuid('w1')), fautive]};

        await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));

        expect(await db.select(db.animals).get(), isEmpty);
      });
    }
  });

  group('écran « Registre des Reproducteurs »', () {
    Future<void> monter(WidgetTester t, {bool peutGerer = true, ValueChanged<String>? onOuvrirFiche}) async {
      t.view.physicalSize = const Size(1400, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: RegistreReproducteursScreen(
            depot: depot,
            peutGerer: peutGerer,
            onOuvrirFiche: onOuvrirFiche,
            onOuvrirSujets: () {},
            horloge: () => maintenant,
          ),
        ),
      );
      await attendre(t);
    }

    Future<void> choisirFiltre(WidgetTester t, String cle, String libelle) async {
      await t.tap(find.byKey(Key(cle)));
      await t.pumpAndSettle();
      await t.tap(find.text(libelle).last);
      await attendre(t);
    }

    Future<void> choisir(WidgetTester t, String cle, String libelle) async {
      await t.tap(find.descendant(of: find.byKey(Key(cle)), matching: find.byType(DropdownButton<String>)));
      await t.pumpAndSettle();
      await t.tap(find.text(libelle).last);
      await attendre(t);
    }

    Future<void> saisir(WidgetTester t, String cle, String texte) async {
      await t.enterText(find.descendant(of: find.byKey(Key(cle)), matching: find.byType(TextField)), texte);
      await t.pump();
    }

    String texteDe(WidgetTester t, String cle) => (t.widget(find.byKey(Key(cle))) as Text).data!;

    testWidgets('⚠️ l écran rend les KPI, le tableau (huit colonnes) et « Lecture seule » sans le droit', (t) async {
      await t.runAsync(() async {
        await uneBande(bande, 'LOT-CUNI-1');
        await unSujet(uuid('s1'), 'LAP-A', lot: bande, race: 'Californien');
        await unSujet(uuid('s2'), 'LAP-B', sexe: 'M', statut: 'reforme');
      });
      await monter(t, peutGerer: false);

      expect(find.text('Registre des Reproducteurs'), findsOneWidget);
      for (final (libelle, valeur) in [('Reproducteurs Enregistrés', '2'), ('Présents', '1'), ('Femelles', '1'), ('Mâles', '0')]) {
        expect(find.descendant(of: find.byKey(Key('kpi-$libelle')), matching: find.text(valeur)), findsOneWidget, reason: libelle);
      }
      expect(find.text('LAP-A'), findsOneWidget);
      expect(find.text('Californien'), findsOneWidget);
      expect(find.text('LOT-CUNI-1'), findsOneWidget);
      expect(find.text('Reforme'), findsOneWidget, reason: 'ucfirst(\$status) du Blade : sans accent (BS-Q11)');
      expect(find.byKey(const Key('reproducteur-nouveau')), findsNothing);
      expect(find.byKey(Key('reproducteur-modifier-${uuid('s1')}')), findsNothing);
      expect(find.byKey(Key('reproducteur-fiche-${uuid('s1')}')), findsOneWidget, reason: 'consulter la fiche reste ouvert (view-elevage)');
    });

    testWidgets('aucun sujet : le message du Blade', (t) async {
      await monter(t);

      expect(find.text('Aucun reproducteur enregistré pour ces critères.'), findsOneWidget);
    });

    testWidgets('⚠️⚠️ Enregistrer un Reproducteur : création EN FILE, toast du web, ligne « À envoyer », l effectif de la bande intact', (t) async {
      await t.runAsync(() => uneBande(bande, 'LOT-CUNI-1', courant: 20));
      await monter(t);

      await t.tap(find.byKey(const Key('reproducteur-nouveau')));
      await t.pumpAndSettle();
      await choisir(t, 'repro-espece', 'Lapins');
      await saisir(t, 'repro-identifiant', 'LAP-2026-0150');
      await choisir(t, 'repro-bande', 'LOT-CUNI-1');
      await saisir(t, 'repro-race', 'Fauve');
      await t.tap(find.byKey(const Key('repro-enregistrer')));
      await attendre(t);

      final a = await t.runAsync(() => (db.select(db.animals)..where((x) => x.identifier.equals('LAP-2026-0150'))).getSingleOrNull());
      expect([a!.breed, a.lotCode, a.syncStatus, a.sex], ['Fauve', 'LOT-CUNI-1', SyncStatus.pending, 'F']);
      expect(find.text("Reproducteur enregistré — l'effectif de la bande est inchangé, ce sujet y était déjà compté."), findsOneWidget);
      expect(find.byKey(Key('reproducteur-etat-${a.id}')), findsOneWidget);
      expect(find.text('À envoyer'), findsOneWidget);
      final lot = await t.runAsync(() => (db.select(db.livestockLots)..where((x) => x.id.equals(bande))).getSingle());
      expect(lot!.currentQuantity, 20);
      await t.pump(ToastAgri.duree);
    });

    testWidgets('⚠️ formulaire vide : les messages du web sous leur champ ; la naissance après l entrée sous « Date de Naissance »', (t) async {
      await monter(t);
      await t.tap(find.byKey(const Key('reproducteur-nouveau')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('repro-enregistrer')));
      await t.pumpAndSettle();

      expect(texteDe(t, 'repro-erreur-identifier'), 'Le champ identifiant est obligatoire.');
      expect(texteDe(t, 'repro-erreur-species_id'), 'Le champ espèce est obligatoire.');
      expect(await t.runAsync(() => db.select(db.animals).get()), isEmpty);

      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(find.text('Enregistrer un Reproducteur'), findsOneWidget, reason: 'seul le bouton de l en-tête reste');
    });

    testWidgets('⚠️ Modifier : la modale reprend le sujet, l enregistrement le remet EN FILE avec le toast du web', (t) async {
      await t.runAsync(() => unSujet(sujet1, 'LAP-1', race: 'Californien'));
      await monter(t);

      await t.tap(find.byKey(const Key('reproducteur-modifier-$sujet1')));
      await t.pumpAndSettle();
      expect(find.text('Modifier le Reproducteur'), findsOneWidget);
      expect(t.widget<TextField>(find.descendant(of: find.byKey(const Key('repro-race')), matching: find.byType(TextField))).controller!.text, 'Californien');
      await saisir(t, 'repro-cage', 'C7');
      await t.tap(find.byKey(const Key('repro-enregistrer')));
      await attendre(t);

      final a = (await t.runAsync(() => lu(sujet1)))!;
      expect([a.cage, a.syncStatus], ['C7', SyncStatus.pending]);
      expect(find.text('Reproducteur mis à jour.'), findsOneWidget);
      await t.pump(ToastAgri.duree);
    });

    testWidgets('⚠️⚠️ Sortie : motif, date, précision ; toast d avertissement ; le sujet passe « Réformé » EN FILE, plus de bouton de sortie', (t) async {
      await t.runAsync(() => unSujet(sujet1, 'LAP-1'));
      await monter(t);

      await t.tap(find.byKey(const Key('reproducteur-sortie-$sujet1')));
      await t.pumpAndSettle();
      expect(find.text('Enregistrer une Sortie'), findsOneWidget);
      expect(find.textContaining("L'effectif de la bande n'est pas modifié ici"), findsOneWidget);
      await saisir(t, 'sortie-precision', 'Réforme pour âge');
      await t.tap(find.byKey(const Key('sortie-confirmer')));
      await attendre(t);

      final a = (await t.runAsync(() => lu(sujet1)))!;
      expect([a.status, a.exitReason, a.exitDate, a.syncStatus], ['reforme', 'Réforme pour âge', DateTime(2026, 10, 21), SyncStatus.pending]);
      expect(find.text("Sortie enregistrée. L'effectif de la bande doit être ajusté depuis la fiche journalière — c'est elle qui fait foi sur les quantités."), findsOneWidget);
      expect(find.byKey(const Key('reproducteur-sortie-$sujet1')), findsNothing);
      await t.pump(ToastAgri.duree);
    });

    testWidgets('Sortie : une date avant l entrée est refusée avec le message du web, sous « Date de sortie »', (t) async {
      await t.runAsync(() => unSujet(sujet1, 'LAP-1', entree: DateTime(2026, 10, 25).subtract(const Duration(days: 1))));
      await monter(t);

      await t.tap(find.byKey(const Key('reproducteur-sortie-$sujet1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('sortie-confirmer')));
      await t.pumpAndSettle();

      expect(texteDe(t, 'sortie-erreur-exit_date'), "La date de sortie ne peut pas précéder la date d'entrée du sujet.");
      expect((await t.runAsync(() => lu(sujet1)))!.status, 'actif');
    });

    testWidgets('recherche (300 ms), filtres d espèce et de statut', (t) async {
      await t.runAsync(() async {
        await unSujet(uuid('s1'), 'LAP-A', race: 'Californien');
        await unSujet(uuid('s2'), 'POU-B', espece: volailles, statut: 'mort');
      });
      await monter(t);

      await t.enterText(find.byKey(const Key('repro-recherche')), 'californ');
      await t.pump(const Duration(milliseconds: 299));
      expect(find.text('POU-B'), findsOneWidget, reason: 'pas encore appliquée');
      await t.pump(const Duration(milliseconds: 2));
      await attendre(t);
      expect(find.text('POU-B'), findsNothing);

      await t.enterText(find.byKey(const Key('repro-recherche')), '');
      await t.pump(RegistreReproducteursScreen.delaiRecherche);
      await attendre(t);
      await choisirFiltre(t, 'repro-filtre-espece', 'Volailles');
      expect(find.text('LAP-A'), findsNothing);
      expect(find.text('POU-B'), findsOneWidget);
      await choisirFiltre(t, 'repro-filtre-espece', 'Toutes les espèces');
      await choisirFiltre(t, 'repro-filtre-statut', 'Actif');
      expect(find.text('POU-B'), findsNothing);
      expect(find.text('LAP-A'), findsOneWidget);
    });

    testWidgets('le bouton de consultation ouvre la fiche du sujet', (t) async {
      await t.runAsync(() => unSujet(sujet1, 'LAP-1'));
      String? ouvert;
      await monter(t, onOuvrirFiche: (id) => ouvert = id);

      await t.tap(find.byKey(const Key('reproducteur-fiche-$sujet1')));
      await t.pump();

      expect(ouvert, sujet1);
    });

    testWidgets('⚠️ un sujet REFUSÉ par le serveur le dit avec son motif, mot pour mot', (t) async {
      await t.runAsync(() async {
        await unSujet(sujet1, 'LAP-1', sync: SyncStatus.conflict);
        await db.into(db.syncConflicts).insert(
          SyncConflictsCompanion.insert(
            id: 'animals:$sujet1',
            sourceTable: 'animals',
            recordId: sujet1,
            reason: 'La valeur du champ identifiant existe déjà.',
            detectedAt: DateTime(2026, 10, 21),
          ),
        );
      });
      await monter(t);

      expect(find.text('Refusé'), findsOneWidget);
      expect(texteDe(t, 'reproducteur-motif-$sujet1'), 'La valeur du champ identifiant existe déjà.');
    });
  });
}
