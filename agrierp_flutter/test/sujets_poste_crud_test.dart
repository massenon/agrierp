import 'package:agrierp/core/comptabilite/exercice_de_saisie.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/elevage/enregistrer_sujets_screen.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:flutter/material.dart';
import 'package:agrierp/features/elevage/sujets_entrees_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket BS2 — « ENREGISTRER DES SUJETS » AU POSTE : NOUVEAU, MODIFIER, ARCHIVER UNE ENTRÉE (repository et file de
/// synchronisation).
///
/// Maître : `app/Livewire/Elevage/EnregistrerSujets.php` et `app/Actions/SaisieSujetAction.php`. Une ligne du journal est
/// UNE ORIGINE d'une fiche du jour (Naissance → `ne`, Achat → `achat`, Don → `don`). Les effectifs attendus sont écrits à
/// la main : bande de 200 têtes au 01/06/2026, puis 200 + entrées − sorties.
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
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List) key: {'accepted': [for (final e in value) if (e is Map && e['id'] is String) e['id']], 'rejected': []},
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {'server_time': '2026-10-21T12:00:00Z'}));
  }
}

void main() {
  late AppDatabase db;
  late SujetsEntreesRepository depot;
  late FicheJournaliereRepository fiches;
  late _Serveur serveur;
  late SyncEngine moteur;

  const lapins = 'aaaaaaaa-0000-4000-8000-0000000000a1';
  const bande = 'bbbbbbbb-0000-4000-8000-000000000001';
  final maintenant = DateTime(2026, 10, 21, 10, 30);

  String uuid(String graine) => graine.padRight(36, '0');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fiches = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    depot = SujetsEntreesRepository(database: db, fiches: fiches, horloge: () => maintenant);
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => maintenant,
    );
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: lapins, code: 'aviculture', label: 'Aviculture'));
    await db.into(db.modulesConfig).insert(ModulesConfigCompanion.insert(id: uuid('mod'), speciesCode: 'aviculture'));
    await db.into(db.livestockLots).insert(
      LivestockLotsCompanion.insert(
        id: bande,
        code: 'PON-2026-01',
        speciesId: lapins,
        speciesCode: const Value('aviculture'),
        stage: const Value('ponte'),
        initialQuantity: const Value(200),
        currentQuantity: const Value(200),
        createdDate: Value(DateTime(2026, 6, 1)),
        status: const Value('actif'),
      ),
    );
  });

  tearDown(() async {
    ToastAgri.toutRetirer();
    await db.close();
  });

  FormulaireSujet saisie(String origine, int quantite, DateTime jour) =>
      FormulaireSujet(speciesId: lapins, lotId: bande, origine: origine, quantite: '$quantite', date: jour);

  Future<LivestockDailyEntry?> fiche(DateTime jour) => fiches.chargerJour(bande, jour);
  Future<int?> effectif(DateTime jour) async => (await fiche(jour))?.effectifFinal;
  Future<int> bandeActuelle() async => (await (db.select(db.livestockLots)..where((t) => t.id.equals(bande))).getSingle()).currentQuantity;

  final dix = DateTime(2026, 10, 10);
  final quinze = DateTime(2026, 10, 15);
  final douze = DateTime(2026, 10, 12);
  final vingt = DateTime(2026, 10, 20);

  /// 10 naissances le 10/10 (210), 5 achats le 15/10 (215).
  Future<void> journal() async {
    await depot.ajouter(saisie('Naissance', 10, dix));
    await depot.ajouter(saisie('Achat', 5, quinze));
    expect([await effectif(dix), await effectif(quinze), await bandeActuelle()], [210, 215, 215]);
  }

  group('nouveau', () {
    test('⚠️ AJOUTE la quantité à la colonne de l origine ; la fiche et la bande suivent ; EN FILE (pending)', () async {
      await depot.ajouter(saisie('Naissance', 10, dix));
      await depot.ajouter(saisie('Naissance', 3, dix));

      final f = (await fiche(dix))!;
      expect([f.ne, f.achat, f.don, f.effectifFinal, f.syncStatus], [13, 0, 0, 213, SyncStatus.pending]);
      expect(await bandeActuelle(), 213);
    });

    test('⚠️ un don est une SORTIE (décision A3) : la formule le soustrait', () async {
      await depot.ajouter(saisie('Achat', 10, dix));
      await depot.ajouter(saisie('Don', 4, dix));

      expect([await effectif(dix), await bandeActuelle()], [206, 206]);
    });

    test('⚠️ les AUTRES colonnes de la fiche sont gardées (morts, ponte, aliment) : le journal ne les efface pas', () async {
      await fiches.enregistrer(lotId: bande, jour: dix, achat: 0, ne: 0, mort: 2, don: 0, ponteTotal: 90, ponteCasses: 3, aliment: 25.5, poidsMoyen: 1800);

      await depot.ajouter(saisie('Naissance', 10, dix));

      final f = (await fiche(dix))!;
      expect([f.mort, f.ponteTotal, f.ponteCasses, f.feedQtyKg, f.weightSampleAvgG, f.ne, f.effectifFinal], [2, 90, 3, 25.5, 1800, 10, 208]);
    });

    test('⚠️ les messages du web, un par champ, quand tout est vide', () async {
      await expectLater(
        depot.ajouter(const FormulaireSujet(quantite: '0')),
        throwsA(
          isA<SujetRefuse>().having((e) => e.erreurs, 'erreurs', {
            'species_id': 'Le champ espèce est obligatoire.',
            'lot_id': 'Le champ bande est obligatoire.',
            'origine': 'Le champ origine est obligatoire.',
            'quantite': 'Le champ quantité doit être au moins égal à 1.',
            'entry_date': "Le champ date d'entrée est obligatoire.",
          }),
        ),
      );
      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
    });

    test('⚠️⚠️ une date dans un exercice CLOS est refusée avant d écrire, avec le motif R4 du serveur', () async {
      await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(id: uuid('ex25'), year: 2025, startDate: Value(DateTime(2025)), endDate: Value(DateTime(2025, 12, 31)), status: const Value('cloture')),
      );

      await expectLater(
        depot.ajouter(saisie('Achat', 5, DateTime(2025, 12, 20))),
        throwsA(isA<RefusExercice>().having((e) => e.motif, 'motif', "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.")),
      );
      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
    });
  });

  group('modifier', () {
    test('⚠️ la quantité REMPLACE l ancienne : fiche, jours suivants et bande recalculés par la cascade unique', () async {
      await journal();
      final f = (await fiche(dix))!;

      await depot.modifier(f.id, 'Naissance', saisie('Naissance', 4, dix));

      // 200 + 4 = 204 ; 204 + 5 = 209.
      expect([(await fiche(dix))!.ne, await effectif(dix), await effectif(quinze), await bandeActuelle()], [4, 204, 209, 209]);
    });

    test('changer l origine déplace la quantité de colonne', () async {
      await journal();
      final f = (await fiche(dix))!;

      await depot.modifier(f.id, 'Naissance', saisie('Achat', 10, dix));

      final apres = (await fiche(dix))!;
      expect([apres.ne, apres.achat, await effectif(dix), await bandeActuelle()], [0, 10, 210, 215]);
    });

    test('⚠️ changer le jour retire l entrée du premier jour et la pose sur le second', () async {
      await journal();
      final f = (await fiche(dix))!;

      await depot.modifier(f.id, 'Naissance', saisie('Naissance', 10, vingt));

      // 10/10 : plus rien (200) ; 15/10 : 205 ; 20/10 : 215 ; la bande suit la DERNIÈRE fiche.
      expect([(await fiche(dix))!.ne, await effectif(dix), await effectif(quinze), await effectif(vingt), await bandeActuelle()], [0, 200, 205, 215, 215]);
    });

    test('⚠️ la ligne modifiée repart EN FILE (pending), à l instant de la saisie', () async {
      await journal();
      await (db.update(db.livestockDailyEntries)).write(const LivestockDailyEntriesCompanion(syncStatus: Value(SyncStatus.synced)));
      final f = (await fiche(dix))!;

      await depot.modifier(f.id, 'Naissance', saisie('Naissance', 4, dix));

      expect((await fiche(dix))!.syncStatus, SyncStatus.pending);
    });
  });

  group('archiver', () {
    test('⚠️ archiver remet la colonne à 0, la cascade suit, la ligne quitte le journal ; la FICHE est gardée', () async {
      await journal();
      final f = (await fiche(quinze))!;

      await depot.archiver(f.id, 'Achat');

      expect([(await fiche(quinze))!.achat, await effectif(quinze), await bandeActuelle()], [0, 210, 210]);
      expect([for (final l in await depot.entrees()) '${l.origine}${l.quantite}'], ['Naissance10']);
      expect(await fiche(quinze), isNotNull);
    });

    test('⚠️ une entrée déjà archivée est signalée, rien n est écrit', () async {
      await journal();
      final f = (await fiche(quinze))!;
      await depot.archiver(f.id, 'Achat');
      await (db.update(db.livestockDailyEntries)).write(const LivestockDailyEntriesCompanion(syncStatus: Value(SyncStatus.synced)));

      await expectLater(
        depot.archiver(f.id, 'Achat'),
        throwsA(isA<SujetRefuse>().having((e) => e.erreurs, 'erreurs', {'entry': "Cette entrée n'existe plus : elle a déjà été modifiée ou archivée."})),
      );
      expect((await fiche(quinze))!.syncStatus, SyncStatus.synced);
    });
  });

  group('effectif négatif', () {
    /// 12/10 : vente de 205 sujets → 210 − 205 = 5 ; 15/10 : 5 + 5 = 10.
    Future<void> venteDuDouze() async {
      await journal();
      await db.into(db.livestockDailyEntries).insert(
        LivestockDailyEntriesCompanion.insert(
          id: uuid('vente'),
          deviceId: 'poste-test',
          updatedAt: DateTime(2026, 10, 12),
          lotId: bande,
          entryDate: douze,
          vente: const Value(205),
          effectifFinal: const Value(5),
        ),
      );
      await fiches.recalculerEnCascade(bande, dix);
      expect([await effectif(douze), await effectif(quinze), await bandeActuelle()], [5, 10, 10]);
    }

    test('⚠️ archiver ou réduire une entrée qui rendrait un effectif négatif un jour suivant est refusé, rien n est écrit', () async {
      await venteDuDouze();
      final f = (await fiche(dix))!;

      await expectLater(
        depot.archiver(f.id, 'Naissance'),
        throwsA(isA<SujetRefuse>().having((e) => e.erreurs['quantite'], 'message', "Saisie refusée : l'effectif de la bande PON-2026-01 deviendrait négatif le 12/10/2026 (-5).")),
      );
      await expectLater(
        depot.modifier(f.id, 'Naissance', saisie('Naissance', 4, dix)),
        throwsA(isA<SujetRefuse>().having((e) => e.erreurs['quantite'], 'message', "Saisie refusée : l'effectif de la bande PON-2026-01 deviendrait négatif le 12/10/2026 (-1).")),
      );

      expect([(await fiche(dix))!.ne, await effectif(dix), await effectif(douze), await effectif(quinze), await bandeActuelle()], [10, 210, 5, 10, 10]);
    });

    test('un don plus grand que l effectif de la bande est refusé', () async {
      await expectLater(
        depot.ajouter(saisie('Don', 201, dix)),
        throwsA(isA<SujetRefuse>().having((e) => e.erreurs['quantite'], 'message', "Saisie refusée : l'effectif de la bande PON-2026-01 deviendrait négatif le 10/10/2026 (-1).")),
      );
      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
    });
  });

  group('journal', () {
    test('une fiche avec naissance ET achat donne DEUX lignes, la plus récente d abord, 50 fiches au plus', () async {
      await depot.ajouter(saisie('Naissance', 3, douze));
      await depot.ajouter(saisie('Achat', 2, douze));
      await depot.ajouter(saisie('Don', 1, dix));

      final lignes = await depot.entrees();

      expect([for (final l in lignes) '${l.origine}${l.quantite}'], ['Naissance3', 'Achat2', 'Don1']);
      expect([for (final l in await depot.entrees(statut: 'Achat')) l.origine], ['Achat']);
      expect([for (final l in await depot.entrees(statut: 'Naissance')) l.origine], ['Naissance']);
      expect(lignes.first.codeBande, 'PON-2026-01');
      expect(lignes.first.especeLibelle, 'Aviculture');
      expect(await depot.entrees(recherche: 'zzz'), isEmpty);
    });

    test('indicateurs : naissances et achats DU MOIS, effectif des bandes vivantes', () async {
      await depot.ajouter(saisie('Naissance', 3, dix));
      await depot.ajouter(saisie('Achat', 2, DateTime(2026, 9, 30)));
      await depot.ajouter(saisie('Achat', 4, quinze));

      final k = await depot.indicateurs();

      expect([k.naissancesMois, k.acquisitionsMois, k.effectifTotal], [3, 4, 209]);
    });

    test('les bandes proposées sont celles de l espèce, actives et non archivées, par code', () async {
      await db.into(db.livestockLots).insert(LivestockLotsCompanion.insert(id: uuid('b2'), code: 'A-ARCHIVEE', speciesId: lapins, isActive: const Value(false)));
      await db.into(db.livestockLots).insert(LivestockLotsCompanion.insert(id: uuid('b3'), code: 'A-CLOTUREE', speciesId: lapins, status: const Value('cloture')));
      await db.into(db.livestockLots).insert(LivestockLotsCompanion.insert(id: uuid('b4'), code: 'A-AUTRE', speciesId: 'autre', status: const Value('actif')));

      expect([for (final b in await depot.bandes(lapins)) b.code], ['PON-2026-01']);
    });
  });

  group('file de synchronisation', () {
    test('⚠️⚠️ de bout en bout : création, modification et archivage partent comme la fiche du jour (colonnes achat, ne, don)', () async {
      await depot.ajouter(saisie('Naissance', 10, dix));
      await moteur.synchroniser();
      Map<String, dynamic> derniere() => (serveur.envois.last['livestock_daily_entries'] as List).single as Map<String, dynamic>;
      expect([derniere()['ne'], derniere()['achat'], derniere()['don'], derniere()['entry_date']], [10, 0, 0, '2026-10-10']);

      final f = (await fiche(dix))!;
      await depot.modifier(f.id, 'Naissance', saisie('Naissance', 4, dix));
      await moteur.synchroniser();
      expect(derniere()['ne'], 4);
      expect(derniere()['id'], f.id, reason: 'la même fiche, jamais une seconde');

      await depot.archiver(f.id, 'Naissance');
      await moteur.synchroniser();
      expect([derniere()['ne'], derniere()['achat'], derniere()['don']], [0, 0, 0]);
      expect((await fiche(dix))!.syncStatus, SyncStatus.synced);
    });
  });

  group('écran « Enregistrer des Sujets »', () {
    Future<void> attendre(WidgetTester t) async {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await t.pumpAndSettle();
    }

    Future<void> monter(WidgetTester t, {bool peutGerer = true, bool peutArchiver = true}) async {
      t.view.physicalSize = const Size(1400, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: EnregistrerSujetsScreen(depot: depot, peutGerer: peutGerer, peutArchiver: peutArchiver, horloge: () => maintenant),
        ),
      );
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

    Future<void> journalDuDecor(WidgetTester t) => t.runAsync(() async {
      await depot.ajouter(saisie('Naissance', 10, dix));
      await depot.ajouter(saisie('Achat', 5, quinze));
    });

    testWidgets('⚠️ l écran rend les KPI, le journal (une ligne par origine) et « Lecture seule » sans le droit', (t) async {
      await journalDuDecor(t);
      await monter(t, peutGerer: false);

      expect(find.text('Enregistrer des Sujets'), findsOneWidget);
      expect(find.textContaining('Journal des ENTRÉES (Phase 1 du cycle)'), findsOneWidget);
      for (final (libelle, valeur) in [('Naissances (mois)', '10'), ('Acquisitions (mois)', '5'), ('Effectif Total', '215')]) {
        expect(find.descendant(of: find.byKey(Key('kpi-$libelle')), matching: find.text(valeur)), findsOneWidget, reason: libelle);
      }
      expect(find.text('PON-2026-01'), findsNWidgets(2));
      expect(find.text('15/10/2026'), findsOneWidget);
      expect(find.text('Lecture seule'), findsNWidgets(2));
      expect(find.byKey(const Key('sujet-nouveau')), findsNothing);
    });

    testWidgets('journal vide : « Aucun résultat trouvé » et « + Nouveau Sujet »', (t) async {
      await monter(t);

      expect(find.text('Aucun résultat trouvé'), findsOneWidget);
      expect(find.text('+ Nouveau Sujet'), findsOneWidget);
    });

    testWidgets('⚠️⚠️ Nouveau Sujet : espèce puis bande, EN FILE, toast du web, effectif de la bande à jour', (t) async {
      await monter(t);
      await t.tap(find.byKey(const Key('sujet-nouveau')));
      await t.pumpAndSettle();
      expect(find.text('Nouveau Sujet'), findsWidgets);
      expect(find.text("Choisir d'abord une espèce"), findsOneWidget);

      await choisir(t, 'sujet-espece', 'Aviculture');
      await choisir(t, 'sujet-bande', 'PON-2026-01 (200 têtes)');
      await choisir(t, 'sujet-origine', 'Naissance');
      await saisir(t, 'sujet-quantite', '10');
      await t.tap(find.byKey(const Key('sujet-enregistrer')));
      await attendre(t);

      final f = (await t.runAsync(() => fiche(DateTime(2026, 10, 21))))!;
      expect([f.ne, f.effectifFinal, f.syncStatus], [10, 210, SyncStatus.pending]);
      expect(find.text('Enregistrement effectué avec succès.'), findsOneWidget);
      expect(find.text('À envoyer'), findsOneWidget);
      await t.pump(ToastAgri.duree);
    });

    testWidgets('⚠️ formulaire vide : les messages du web sous leur champ ; un exercice clos : le motif R4 sous « Date »', (t) async {
      await t.runAsync(
        () => db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(id: uuid('ex26'), year: 2026, startDate: Value(DateTime(2026)), endDate: Value(DateTime(2026, 12, 31)), status: const Value('cloture')),
        ),
      );
      await monter(t);
      await t.tap(find.byKey(const Key('sujet-nouveau')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('sujet-enregistrer')));
      await t.pumpAndSettle();
      expect(texteDe(t, 'sujet-erreur-species_id'), 'Le champ espèce est obligatoire.');
      expect(texteDe(t, 'sujet-erreur-lot_id'), 'Le champ bande est obligatoire.');
      expect(texteDe(t, 'sujet-erreur-origine'), 'Le champ origine est obligatoire.');

      await choisir(t, 'sujet-espece', 'Aviculture');
      await choisir(t, 'sujet-bande', 'PON-2026-01 (200 têtes)');
      await choisir(t, 'sujet-origine', 'Achat');
      await t.tap(find.byKey(const Key('sujet-enregistrer')));
      await attendre(t);
      expect(texteDe(t, 'sujet-erreur-entry_date'), "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 21/10/2026.");
      expect(await t.runAsync(() => db.select(db.livestockDailyEntries).get()), isEmpty);
    });

    testWidgets('⚠️⚠️ Modifier le Sujet : la quantité REMPLACE, la cascade suit ; toast du web ; la fiche repart EN FILE', (t) async {
      await journalDuDecor(t);
      await t.runAsync(() => db.update(db.livestockDailyEntries).write(const LivestockDailyEntriesCompanion(syncStatus: Value(SyncStatus.synced))));
      final f = (await t.runAsync(() => fiche(dix)))!;
      await monter(t);

      await t.tap(find.byKey(Key('sujet-modifier-${f.id}-Naissance')));
      await t.pumpAndSettle();
      expect(find.text('Modifier le Sujet'), findsOneWidget);
      expect(find.text('PON-2026-01'), findsWidgets);
      await saisir(t, 'sujet-quantite', '4');
      await t.tap(find.byKey(const Key('sujet-enregistrer')));
      await attendre(t);

      final apres = (await t.runAsync(() => fiche(dix)))!;
      expect([apres.ne, apres.effectifFinal, apres.syncStatus], [4, 204, SyncStatus.pending]);
      expect((await t.runAsync(bandeActuelle)), 209);
      expect(find.text('Modification enregistrée avec succès.'), findsOneWidget);
      expect(texteDe(t, 'sujet-quantite-${f.id}-Naissance'), '4');
      await t.pump(ToastAgri.duree);
    });

    testWidgets('⚠️⚠️ Archiver : confirmation, l entrée quitte le journal, la fiche est gardée, toast d avertissement', (t) async {
      await journalDuDecor(t);
      final f = (await t.runAsync(() => fiche(quinze)))!;
      await monter(t);

      await t.tap(find.byKey(Key('sujet-archiver-${f.id}-Achat')));
      await t.pumpAndSettle();
      expect(find.text("Confirmer l'archivage"), findsOneWidget);
      expect(
        find.text("PON-2026-01 — Achat (5) du 15/10/2026 sera marqué(e) comme archivé(e) (statut inactif). Aucune suppression définitive n'est effectuée."),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('archivage-sujet-confirmer')));
      await attendre(t);

      expect((await t.runAsync(() => fiche(quinze)))!.achat, 0);
      expect(find.byKey(Key('sujet-ligne-${f.id}-Achat')), findsNothing);
      expect(find.text('Entrée archivée avec succès.'), findsOneWidget);
      await t.pump(ToastAgri.duree);
    });

    testWidgets('⚠️ archiver une entrée qui rendrait un effectif négatif : toast d erreur avec le motif, rien n est écrit', (t) async {
      await t.runAsync(() async {
        await depot.ajouter(saisie('Naissance', 10, dix));
        await db.into(db.livestockDailyEntries).insert(
          LivestockDailyEntriesCompanion.insert(id: uuid('vente'), deviceId: 'poste-test', updatedAt: DateTime(2026, 10, 12), lotId: bande, entryDate: douze, vente: const Value(205), effectifFinal: const Value(5)),
        );
        await fiches.recalculerEnCascade(bande, dix);
      });
      final f = (await t.runAsync(() => fiche(dix)))!;
      await monter(t);

      await t.tap(find.byKey(Key('sujet-archiver-${f.id}-Naissance')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('archivage-sujet-confirmer')));
      await attendre(t);

      expect(find.text("Saisie refusée : l'effectif de la bande PON-2026-01 deviendrait négatif le 12/10/2026 (-5)."), findsOneWidget);
      expect((await t.runAsync(() => fiche(dix)))!.ne, 10);
      await t.pump(ToastAgri.duree);
    });

    testWidgets('sans archive-elevage : Modifier reste, Archiver disparaît', (t) async {
      await journalDuDecor(t);
      final f = (await t.runAsync(() => fiche(dix)))!;
      await monter(t, peutArchiver: false);

      expect(find.byKey(Key('sujet-modifier-${f.id}-Naissance')), findsOneWidget);
      expect(find.byKey(Key('sujet-archiver-${f.id}-Naissance')), findsNothing);
    });

    testWidgets('filtre « Naissance » / « Achat » et recherche d un code de bande', (t) async {
      await journalDuDecor(t);
      await monter(t);

      await t.tap(find.byKey(const Key('sujets-filtre-statut')));
      await t.pumpAndSettle();
      await t.tap(find.text('Achat').last);
      await attendre(t);
      expect(find.text('15/10/2026'), findsOneWidget);
      expect(find.text('10/10/2026'), findsNothing);

      await t.enterText(find.byKey(const Key('sujets-recherche')), 'zzz');
      await t.pump(EnregistrerSujetsScreen.delaiRecherche);
      await attendre(t);
      expect(find.text('Aucun résultat trouvé'), findsOneWidget);
    });

    testWidgets('⚠️ une fiche REFUSÉE par le serveur le dit avec son motif, mot pour mot', (t) async {
      await journalDuDecor(t);
      final f = (await t.runAsync(() => fiche(dix)))!;
      await t.runAsync(() async {
        await (db.update(db.livestockDailyEntries)..where((x) => x.id.equals(f.id))).write(const LivestockDailyEntriesCompanion(syncStatus: Value(SyncStatus.conflict)));
        await db.into(db.syncConflicts).insert(
          SyncConflictsCompanion.insert(id: 'livestock_daily_entries:${f.id}', sourceTable: 'livestock_daily_entries', recordId: f.id, reason: "L'exercice 2025 est clôturé.", detectedAt: DateTime(2026, 10, 21)),
        );
      });
      await monter(t);

      expect(find.text('Refusée'), findsOneWidget);
      expect(texteDe(t, 'sujet-motif-${f.id}-Naissance'), "L'exercice 2025 est clôturé.");
    });
  });
}
