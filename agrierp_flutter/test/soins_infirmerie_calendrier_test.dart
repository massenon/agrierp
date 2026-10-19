import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/widgets/modale_agri.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/elevage/soins_vaccins_repository.dart';
import 'package:agrierp/features/elevage/soins_vaccins_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Tickets H8 et H8b (poste) — SOINS ET VACCINS ALIGNÉ SUR LE BLADE ; INFIRMERIE ET CALENDRIER PLANIFIÉ SAISIS
/// AU POSTE (décision client D-H8 du 19/10/2026).
///
/// ⚠️⚠️ **LE BLADE FAIT FOI** (doctrine, article 5). Les libellés, colonnes, options, exemples et messages
/// attendus sont LUS dans `soins-vaccins-hub.blade.php` et `SoinsVaccinsHub.php`, jamais recopiés ici : une
/// retouche du web fait rougir le poste au lieu de diverger en silence.
///
/// Ce que le poste GARDE en plus (décisions client) : la colonne « Statut » du registre (après les six du Blade),
/// les filtres, la recherche et les boutons Importer / Exporter, le protocole calculé et les rémanences dans le
/// calendrier — avec une légende qui distingue « planifié » (web) et « calculé (protocole) » (poste).
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Serveur feint : sert [tirage] au tirage, accepte (ou refuse avec [refus]) tout envoi.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-19T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];
  String? refus;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      Map<String, dynamic> reponse(String cle) {
        final ids = [for (final e in corps[cle] as List? ?? const []) (e as Map)['id'] as String];
        return refus == null
            ? {'accepted': ids, 'rejected': <Object>[]}
            : {
                'accepted': <String>[],
                'rejected': [
                  for (final id in ids) {'id': id, 'reason': refus},
                ],
              };
      }

      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'infirmary_records': reponse('infirmary_records'),
            'veterinary_calendar_events': reponse('veterinary_calendar_events'),
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

// ── Lecture du web (maître) ─────────────────────────────────────────────────────────────────────────────

String? _lireLaravel(String relatif) {
  final f = File('$dossierLaravel/$relatif');
  return f.existsSync() ? f.readAsStringSync() : null;
}

final String? _blade = _lireLaravel('resources/views/livewire/elevage/soins-vaccins-hub.blade.php');
final String? _livewire = _lireLaravel('app/Livewire/Elevage/SoinsVaccinsHub.php');
/// Sans `agrierp_laravel/`, le Blade maître ne peut pas être lu : les tests qui le lisent se sautent.
final bool _sautWeb = _blade == null || _livewire == null;

String _decoder(String html) => html
    .replaceAll('&gt;', '>')
    .replaceAll('&lt;', '<')
    .replaceAll('&#039;', "'")
    .replaceAll('&amp;', '&')
    .trim();

/// Les trois sections du hub, dans l'ordre du Blade.
String _section(String onglet) {
  final b = _blade!;
  final debut = b.indexOf("@if(\$tab === '$onglet')");
  final suivants = ["@if(\$tab === 'calendrier')", "@if(\$tab === 'suivi')"]
      .map(b.indexOf)
      .where((i) => i > debut)
      .toList();
  return b.substring(debut, suivants.isEmpty ? b.length : suivants.first);
}

List<String> _tous(String source, String motif) =>
    RegExp(motif).allMatches(source).map((m) => _decoder(m.group(1)!)).toList();

/// Colonnes `<th>` d'une section, sans les en-têtes datés (`{{ … }}`) du Gantt.
List<String> _colonnes(String section) =>
    _tous(section, r'<th[^>]*>([^<]*)</th>').where((c) => !c.contains('{{')).toList();

/// Messages des toasts du composant (`dispatch('toast', message: '…')`).
List<String> _messagesPhp() => _tous(_livewire!, r"message: '([^']+)'");

void main() {
  late AppDatabase db;
  late SoinsRepository soins;
  late SoinsVaccinsRepository depot;
  late _Serveur serveur;
  late SyncEngine moteur;

  const lapins = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
  const volailles = 'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb';
  const archivee = 'cccccccc-0000-4000-8000-cccccccccccc';
  const especeLapins = 'eeeeeeee-0000-4000-8000-000000000001';
  const especeVolailles = 'eeeeeeee-0000-4000-8000-000000000002';

  final maintenant = DateTime.now();
  final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
  DateTime jourDe(int decalage) => DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + decalage);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
    depot = SoinsVaccinsRepository(database: db, soins: soins);
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
    );

    for (final (id, code, label) in [
      (especeLapins, 'cuniculture', 'Lapins'),
      (especeVolailles, 'aviculture', 'Volailles'),
    ]) {
      await db
          .into(db.livestockSpecies)
          .insert(LivestockSpeciesCompanion.insert(id: id, code: code, label: label));
    }
    for (final (id, code, espece, codeEspece, statut) in [
      (lapins, 'LOT-LAP-01', especeLapins, 'cuniculture', 'actif'),
      (volailles, 'LOT-VOL-01', especeVolailles, 'aviculture', 'actif'),
      // Bande clôturée : jamais proposée (`status = actif` ET `is_active`, `getActiveLotsProperty`).
      (archivee, 'LOT-ANC-01', especeLapins, 'cuniculture', 'cloture'),
    ]) {
      await db
          .into(db.livestockLots)
          .insert(
            LivestockLotsCompanion.insert(
              id: id,
              code: code,
              speciesId: espece,
              speciesCode: Value(codeEspece),
              stage: const Value('engraissement'),
              status: Value(statut),
              createdDate: Value(jourDe(-10)),
              currentQuantity: const Value(40),
            ),
          );
    }
  });

  tearDown(() async => db.close());

  Future<void> entree(
    String id,
    String lot,
    DateTime jour,
    String statut, {
    SyncStatus sync = SyncStatus.synced,
    String? sujet,
  }) => db
      .into(db.infirmaryRecords)
      .insert(
        InfirmaryRecordsCompanion.insert(
          id: id,
          deviceId: 'serveur',
          syncStatus: Value(sync),
          updatedAt: jour,
          lotId: lot,
          sujetRef: Value(sujet),
          motif: 'Motif $id',
          isolationLevel: const Value('Infirmerie'),
          entryDate: jour,
          status: Value(statut),
        ),
      );

  Future<void> evenement(String id, String lot, DateTime jour, String statut, {String tache = 'Rappel'}) => db
      .into(db.veterinaryCalendarEvents)
      .insert(
        VeterinaryCalendarEventsCompanion.insert(
          id: id,
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: jour,
          lotId: lot,
          taskType: tache,
          scheduledDate: jour,
          status: Value(statut),
        ),
      );

  String uuid(int n) => '11111111-0000-4000-8000-${n.toString().padLeft(12, '0')}';

  // ══ 1. Le moteur : tirage (absorbeurs stricts) et envoi ═════════════════════════════════════════════════

  group('H8b — tirage', () {
    test('le tirage absorbe l infirmerie et le calendrier planifié du web', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'infirmary_records': [
          {
            'id': uuid(1), 'lot_id': lapins, 'sujet_ref': '#A-204', 'motif': 'Suspicion Newcastle',
            'isolation_level': 'Quarantaine stricte', 'entry_date': '2026-10-18T00:00:00.000000Z',
            'status': 'en_cours', 'updated_at': '2026-10-18T09:00:00.000000Z',
          },
        ],
        'veterinary_calendar_events': [
          {
            'id': uuid(2), 'lot_id': volailles, 'task_type': 'Rappel Newcastle',
            'scheduled_date': '2026-10-25T00:00:00.000000Z', 'status': 'planned',
            'updated_at': '2026-10-18T09:00:00.000000Z',
          },
        ],
      };

      await moteur.synchroniser();

      final e = await db.select(db.infirmaryRecords).getSingle();
      expect(
        [e.id, e.lotId, e.sujetRef, e.motif, e.isolationLevel, e.status, e.syncStatus],
        [uuid(1), lapins, '#A-204', 'Suspicion Newcastle', 'Quarantaine stricte', 'en_cours', SyncStatus.synced],
      );
      final v = await db.select(db.veterinaryCalendarEvents).getSingle();
      expect([v.id, v.lotId, v.taskType, v.status, v.syncStatus],
          [uuid(2), volailles, 'Rappel Newcastle', 'planned', SyncStatus.synced]);
      // Une ligne tirée n'a été écrite par aucun poste : elle ne repart jamais.
      expect(await db.pendingCount(), 0);
    });

    test('⚠️⚠️ STRICT : une saisie locale pending n est jamais écrasée par le tirage', () async {
      await entree(uuid(3), lapins, jourDe(-1), 'reintegre', sync: SyncStatus.pending);
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'infirmary_records': [
          {
            'id': uuid(3), 'lot_id': lapins, 'motif': 'Motif serveur', 'isolation_level': 'Infirmerie',
            'entry_date': '2026-10-18', 'status': 'en_cours', 'updated_at': '2026-10-18T09:00:00Z',
          },
        ],
      };

      await moteur.synchroniser();

      final e = await db.select(db.infirmaryRecords).getSingle();
      expect(e.status, 'reintegre', reason: 'la réintégration saisie au poste part à l envoi, elle n est pas écrasée');
      expect(e.motif, 'Motif ${uuid(3)}');
    });

    test('⚠️⚠️ STRICT : une bande inconnue ou un statut inconnu refuse tout le lot', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'veterinary_calendar_events': [
          {
            'id': uuid(4), 'lot_id': lapins, 'task_type': 'Rappel', 'scheduled_date': '2026-10-25',
            'status': 'planned',
          },
          {
            'id': uuid(5), 'lot_id': 'dddddddd-0000-4000-8000-dddddddddddd', 'task_type': 'Rappel',
            'scheduled_date': '2026-10-25', 'status': 'planned',
          },
        ],
      };
      await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));
      expect(await db.select(db.veterinaryCalendarEvents).get(), isEmpty);

      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'infirmary_records': [
          {
            'id': uuid(6), 'lot_id': lapins, 'motif': 'X', 'entry_date': '2026-10-18', 'status': 'gueri',
          },
        ],
      };
      await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));
      expect(await db.select(db.infirmaryRecords).get(), isEmpty);
    });
  });

  group('H8b — envoi', () {
    test('une entrée d infirmerie part en snake_case, puis sa réintégration repart en pending', () async {
      final id = await depot.enregistrerEntreeInfirmerie(
        lotId: lapins,
        sujetRef: '#A-204',
        motif: 'Suspicion Newcastle',
        niveauIsolement: 'Quarantaine stricte',
        dateEntree: DateTime(2026, 10, 18),
      );
      final creee = await (db.select(db.infirmaryRecords)..where((t) => t.id.equals(id))).getSingle();
      expect([creee.status, creee.syncStatus, creee.deviceId], ['en_cours', SyncStatus.pending, 'poste-test']);
      expect(await db.pendingCount(), 1, reason: 'le compteur « en attente » couvre la nouvelle table');

      await moteur.synchroniser();

      final parti = (serveur.envois.single['infirmary_records'] as List).single as Map;
      expect(parti, containsPair('id', id));
      expect(parti, containsPair('lot_id', lapins));
      expect(parti, containsPair('sujet_ref', '#A-204'));
      expect(parti, containsPair('motif', 'Suspicion Newcastle'));
      expect(parti, containsPair('isolation_level', 'Quarantaine stricte'));
      expect(parti, containsPair('entry_date', '2026-10-18'));
      expect(parti, containsPair('status', 'en_cours'));
      expect((await (db.select(db.infirmaryRecords)..where((t) => t.id.equals(id))).getSingle()).syncStatus,
          SyncStatus.synced);

      await depot.reintegrer(id);
      final reintegree = await (db.select(db.infirmaryRecords)..where((t) => t.id.equals(id))).getSingle();
      expect([reintegree.status, reintegree.syncStatus], ['reintegre', SyncStatus.pending]);

      await moteur.synchroniser();
      final second = (serveur.envois.last['infirmary_records'] as List).single as Map;
      expect(second, containsPair('status', 'reintegre'));
      expect(await db.pendingCount(), 0);
    });

    test('une intervention planifiée puis confirmée part avec son statut', () async {
      final id = await depot.planifierIntervention(
        lotId: volailles,
        intervention: 'Rappel Myxomatose',
        datePrevue: DateTime(2026, 10, 25),
      );
      await moteur.synchroniser();
      final parti = (serveur.envois.single['veterinary_calendar_events'] as List).single as Map;
      expect(parti, containsPair('id', id));
      expect(parti, containsPair('lot_id', volailles));
      expect(parti, containsPair('task_type', 'Rappel Myxomatose'));
      expect(parti, containsPair('scheduled_date', '2026-10-25'));
      expect(parti, containsPair('status', 'planned'));

      await depot.confirmerAdministration(id);
      expect((await db.select(db.veterinaryCalendarEvents).getSingle()).syncStatus, SyncStatus.pending);
      await moteur.synchroniser();
      expect((serveur.envois.last['veterinary_calendar_events'] as List).single, containsPair('status', 'done'));
      expect((await db.select(db.veterinaryCalendarEvents).getSingle()).syncStatus, SyncStatus.synced);
    });

    test('un refus du serveur passe l entrée en conflit avec son motif', () async {
      serveur.refus = "La date du champ entry date ne peut pas être postérieure à aujourd'hui.";
      await depot.enregistrerEntreeInfirmerie(
        lotId: lapins,
        motif: 'Boiterie',
        niveauIsolement: 'Infirmerie',
        dateEntree: DateTime(2026, 10, 18),
      );

      final resultat = await moteur.synchroniser();

      expect(resultat.motifs.join(' '), contains('postérieure'));
      expect((await db.select(db.infirmaryRecords).getSingle()).syncStatus, SyncStatus.conflict);
      expect(await db.pendingCount(), 1, reason: 'un refus reste compté');
    });
  });

  // ══ 2. Le dépôt : indicateurs recalculés à la main ══════════════════════════════════════════════════════

  group('H8b — indicateurs', () {
    test('les quatre KPI de l infirmerie suivent getKpisInfirmerieProperty', () async {
      final debutMois = DateTime(aujourdhui.year, aujourdhui.month, 1);
      final moisDernier = DateTime(aujourdhui.year, aujourdhui.month - 1, 15);
      // En cours : 2 (dont une du mois dernier — « en cours » ne dépend pas du mois).
      await entree(uuid(10), lapins, debutMois, 'en_cours');
      await entree(uuid(11), volailles, moisDernier, 'en_cours');
      // Réintégrés : 1 du mois (compte), 1 du mois dernier (ne compte pas).
      await entree(uuid(12), lapins, debutMois, 'reintegre');
      await entree(uuid(13), lapins, moisDernier, 'reintegre');
      // Décès : 2 du mois, 1 du mois dernier.
      await entree(uuid(14), lapins, debutMois, 'deces');
      await entree(uuid(15), volailles, debutMois, 'deces');
      await entree(uuid(16), volailles, moisDernier, 'deces');

      final d = await depot.charger();

      expect(d.kpisInfirmerie.enQuarantaine, 2);
      expect(d.kpisInfirmerie.guerisMois, 1);
      expect(d.kpisInfirmerie.sousTraitement, 2);
      expect(d.kpisInfirmerie.decesMois, 2);
      // Registre : « Animaux en quarantaine » lit l'infirmerie (`InfirmaryRecord::where('status','en_cours')`).
      expect(d.enQuarantaine, 2);
      expect(d.infirmerie, hasLength(7));
      // Plus récente d'abord (`orderByDesc('entry_date')`).
      expect(d.infirmerie.first.entree.entryDate.isBefore(d.infirmerie.last.entree.entryDate), isFalse);
    });

    test('« Vaccinations planifiées » compte les événements planned, toutes dates', () async {
      await evenement(uuid(20), lapins, jourDe(2), 'planned');
      await evenement(uuid(21), lapins, jourDe(40), 'planned');
      await evenement(uuid(22), volailles, jourDe(-30), 'planned');
      await evenement(uuid(23), volailles, jourDe(1), 'done');

      final d = await depot.charger();

      expect(d.vaccinationsPlanifiees, 3);
    });

    test('calendrier : fenêtre J → J+13, « En retard » = planned et date passée, à l affichage seulement', () async {
      await evenement(uuid(30), lapins, jourDe(-1), 'planned');
      await evenement(uuid(31), lapins, jourDe(3), 'planned');
      await evenement(uuid(32), lapins, jourDe(5), 'done');
      await evenement(uuid(33), lapins, jourDe(14), 'planned');

      final d = await depot.charger(quand: DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day, 10));

      expect(d.fenetre.first, aujourdhui);
      expect(d.fenetre.last, jourDe(13));
      expect(d.fenetre, hasLength(14));
      final ligne = d.calendrier.singleWhere((l) => l.codeBande == 'LOT-LAP-01');
      expect(ligne.evenements.map((e) => e.id).toSet(), {uuid(31), uuid(32)},
          reason: 'J−1 et J+14 sont hors de la fenêtre du web');
      expect(ligne.evenements.singleWhere((e) => e.id == uuid(32)).etat, EtatIntervention.effectue);
      expect(ligne.evenements.singleWhere((e) => e.id == uuid(31)).etat, EtatIntervention.planifie);
      // Lignes : bandes actives seulement (`status = actif` ET `is_active`).
      expect(d.calendrier.map((l) => l.codeBande), isNot(contains('LOT-ANC-01')));

      // Le statut stocké ne change pas : « En retard » n'est jamais écrit (`display_status`).
      await evenement(uuid(34), volailles, aujourdhui, 'planned');
      final tard = await depot.charger(quand: DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day, 10));
      expect(
        tard.calendrier.singleWhere((l) => l.codeBande == 'LOT-VOL-01').evenements.single.etat,
        EtatIntervention.enRetard,
        reason: 'Carbon::isPast() sur une date à minuit : le jour même, passé minuit, est « En retard » au web',
      );
      final stocke = await (db.select(db.veterinaryCalendarEvents)..where((t) => t.id.equals(uuid(34)))).getSingle();
      expect(stocke.status, 'planned');
    });

    test('les bandes proposées sont actives (status actif ET is_active)', () async {
      await (db.update(db.livestockLots)..where((t) => t.id.equals(volailles)))
          .write(const LivestockLotsCompanion(isActive: Value(false)));

      final bandes = await depot.bandesActives();

      expect(bandes.map((b) => b.code), ['LOT-LAP-01']);
      expect(bandes.single.libelleAvecEspece, 'LOT-LAP-01 (Lapins)');
    });

    test('le coût sanitaire est formaté comme number_format(…, 0, \',\', \' \') . \' FCFA\'', () {
      expect(SoinsVaccinsRepository.fcfa(12500), '12 500 FCFA');
      expect(SoinsVaccinsRepository.fcfa(0), '0 FCFA');
      expect(SoinsVaccinsRepository.fcfa(1234567.5), '1 234 568 FCFA');
    });
  });

  // ══ 3. L'écran, confronté au Blade ═════════════════════════════════════════════════════════════════════

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(home: SoinsVaccinsScreen(depot: depot, soins: soins)));
    await tester.pumpAndSettle();
  }

  Future<void> onglet(WidgetTester tester, String titre) async {
    await tester.tap(find.byKey(Key('onglet-vms-$titre')));
    await tester.pumpAndSettle();
  }

  Future<void> nettoyer(WidgetTester tester) async {
    ToastAgri.toutRetirer();
    await tester.pumpWidget(const SizedBox());
  }

  /// Exemples (`placeholder` du Blade) portés par les champs d'une modale.
  List<String?> exemplesDe(WidgetTester tester, Finder modale) => [
    for (final c in tester.widgetList<TextField>(find.descendant(of: modale, matching: find.byType(TextField))))
      c.decoration?.hintText,
  ];

  /// Les en-têtes d'un tableau, lus dans le Blade, sont rendus dans CET ORDRE (de gauche à droite).
  void colonnesDansLOrdre(WidgetTester tester, List<String> colonnes) {
    final abscisses = [
      for (final c in colonnes) tester.getTopLeft(find.text(c.toUpperCase()).first).dx,
    ];
    for (var i = 1; i < abscisses.length; i++) {
      expect(abscisses[i], greaterThan(abscisses[i - 1]), reason: '${colonnes[i]} après ${colonnes[i - 1]}');
    }
  }

  group('H8 — registre', () {
    testWidgets('les six colonnes du Blade, dans son ordre, puis « Statut » (ajout du poste)', (tester) async {
      final colonnes = _colonnes(_section('registre'));
      expect(colonnes, hasLength(6), reason: 'Blade : $colonnes');
      await soins.enregistrer(lotId: lapins, typeAction: 'Vaccination', produit: 'Alfamec', cout: 12500);

      await afficher(tester);

      colonnesDansLOrdre(tester, [...colonnes, 'Statut']);
      // Cellule « CODE (Libellé espèce) » et coût « 12 500 FCFA ».
      expect(find.text('LOT-LAP-01 (Lapins)'), findsOneWidget);
      expect(find.text('12 500 FCFA'), findsOneWidget);
      await nettoyer(tester);
    }, skip: _sautWeb);

    testWidgets('registre vide : le message exact du Blade', (tester) async {
      final vides = _tous(_section('registre'), r'text-center text-outline">([^<]+)</td>');
      await afficher(tester);
      expect(find.text(vides.single), findsOneWidget);
      await nettoyer(tester);
    }, skip: _sautWeb);

    testWidgets('« Animaux en quarantaine » lit l infirmerie', (tester) async {
      await entree(uuid(40), lapins, aujourdhui, 'en_cours');
      await entree(uuid(41), lapins, aujourdhui, 'en_cours');
      await entree(uuid(42), lapins, aujourdhui, 'reintegre');
      await afficher(tester);
      final carte = tester.widget<CarteKpi>(
        find.byWidgetPredicate((w) => w is CarteKpi && w.libelle == 'Animaux en quarantaine'),
      );
      expect(carte.valeur, '2');
      await nettoyer(tester);
    });

    testWidgets('la modale Nouveau Soin : libellés, exemples, options et aide du Blade ; largeur sm', (tester) async {
      final section = _section('registre');
      await afficher(tester);
      await tester.tap(find.byKey(const Key('nouveau-soin')));
      await tester.pumpAndSettle();
      final modale = find.byType(ModaleAgri);

      expect(tester.widget<ModaleAgri>(modale).largeur, LargeurModale.sm);
      for (final l in _tous(section, r'<label[^>]*>([^<]*)</label>')) {
        expect(find.descendant(of: modale, matching: find.text(l.toUpperCase())), findsOneWidget, reason: l);
      }
      final exemples = exemplesDe(tester, modale);
      for (final p in _tous(section, r'placeholder="([^"]*)"')) {
        expect(exemples, contains(p), reason: 'exemple « $p »');
      }
      final aides = _tous(section, r'<p class="text-\[9px\] text-outline mt-xs">([^<]+)</p>');
      expect(find.descendant(of: modale, matching: find.text(aides.single)), findsOneWidget);
      // Libellé ROUGE de la rémanence (`text-error-deep`).
      final remanence = tester.widget<Text>(
        find.descendant(of: modale, matching: find.text("DÉLAI D'ATTENTE / RÉMANENCE (JOURS)")),
      );
      expect(remanence.style?.color, const Color(0xFFBA1A1A));
      // Symptômes : zone de texte (`<textarea rows="2">`).
      expect(tester.widget<TextField>(find.byKey(const Key('soin-symptomes'))).maxLines, 2);
      // « -- Sélectionner -- » en tête des deux listes.
      expect(find.descendant(of: modale, matching: find.text('-- Sélectionner --')), findsNWidgets(2));
      await nettoyer(tester);
    }, skip: _sautWeb);

    testWidgets('soin enregistré : message du PHP, avec et sans rémanence ; bandes actives seulement',
        (tester) async {
      final avec = RegExp(r'"(Soin enregistré[^"]*)"').firstMatch(_livewire!)!.group(1)!;
      final sans = RegExp(r": '(Soin enregistré[^']*)'").firstMatch(_livewire!)!.group(1)!;
      await afficher(tester);

      Future<void> saisir({required String produit, String? delai}) async {
        await tester.tap(find.byKey(const Key('nouveau-soin')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('soin-bande')));
        await tester.pumpAndSettle();
        expect(find.text('LOT-ANC-01 (Lapins)'), findsNothing, reason: 'bande clôturée non proposée');
        await tester.tap(find.text('LOT-LAP-01 (Lapins)').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('soin-type')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vermifuge').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('soin-produit')), produit);
        if (delai != null) await tester.enterText(find.byKey(const Key('soin-remanence')), delai);
        await tester.tap(find.byKey(const Key('soin-enregistrer')));
        await tester.pumpAndSettle();
      }

      await saisir(produit: 'Levalap', delai: '7');
      expect(find.text(avec.replaceAll(r'{$this->soinRemanence}', '7')), findsOneWidget);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle();

      await saisir(produit: 'Vitamine AD3E');
      expect(find.text(sans), findsOneWidget);
      expect(await db.select(db.veterinaryRecords).get(), hasLength(2));
      await nettoyer(tester);
    }, skip: _sautWeb);
  });

  group('H8b — Suivi Sanitaire', () {
    testWidgets('titre, sous-titre, bouton, KPI, colonnes et message vide du Blade', (tester) async {
      final section = _section('suivi');
      await afficher(tester);
      await onglet(tester, 'Suivi Sanitaire');

      expect(find.text(_tous(section, r'</span>([^<]+)</h2>').single), findsWidgets);
      expect(find.text(_tous(section, r'<p class="text-xs text-outline mt-xs">([^<]+)</p>').single), findsOneWidget);
      final bouton = _tous(section, r'wire:click="newInfirmaryEntry"[^>]*>\s*<span[^>]*>[^<]*</span>([^<]+)</button>');
      expect(find.text(bouton.single), findsOneWidget);
      final kpi = _tous(section, r'x-kpi-card label="([^"]+)"');
      expect(kpi, hasLength(4));
      expect(find.byType(CarteKpi), findsNWidgets(4));
      for (final l in kpi) {
        expect(find.byWidgetPredicate((w) => w is CarteKpi && w.libelle == l), findsOneWidget, reason: l);
      }
      final colonnes = _colonnes(section);
      expect(colonnes, hasLength(6));
      colonnesDansLOrdre(tester, colonnes);
      expect(find.text(_tous(section, r'text-center text-outline">([^<]+)</td>').single), findsOneWidget);
      await nettoyer(tester);
    }, skip: _sautWeb);

    testWidgets('lignes : « CODE — sujet », statuts du Blade, « Clôturé » sans action', (tester) async {
      final section = _section('suivi');
      final statuts = _tous(section, r'rounded-full text-\[11px\] font-bold border [^"]*">([^<]+)</span>');
      expect(statuts, ['En cours', 'Réintégré', 'Décès']);
      final cloture = _tous(section, r'<span class="text-outline text-\[11px\]">([^<]+)</span>').single;

      await entree(uuid(50), lapins, jourDe(-1), 'en_cours', sujet: '#A-204');
      await entree(uuid(51), volailles, jourDe(-2), 'reintegre');
      await entree(uuid(52), volailles, jourDe(-3), 'deces');
      await afficher(tester);
      await onglet(tester, 'Suivi Sanitaire');

      expect(find.text('LOT-LAP-01 — #A-204'), findsOneWidget);
      expect(find.text('LOT-VOL-01'), findsNWidgets(2));
      for (final s in statuts) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.text(cloture), findsNWidgets(2));
      expect(find.byKey(Key('reintegrer-${uuid(50)}')), findsOneWidget);
      expect(find.byKey(Key('deces-${uuid(50)}')), findsOneWidget);
      expect(find.byKey(Key('reintegrer-${uuid(51)}')), findsNothing);
      await nettoyer(tester);
    }, skip: _sautWeb);

    testWidgets('Réintégrer et Décès écrivent localement en pending, avec les toasts du PHP', (tester) async {
      final messages = _messagesPhp();
      await entree(uuid(60), lapins, jourDe(-1), 'en_cours');
      await entree(uuid(61), volailles, jourDe(-1), 'en_cours');
      await afficher(tester);
      await onglet(tester, 'Suivi Sanitaire');

      await tester.tap(find.byKey(Key('reintegrer-${uuid(60)}')));
      await tester.pumpAndSettle();
      expect(find.text(messages.singleWhere((m) => m.startsWith('Sujet réintégré'))), findsOneWidget);
      expect(find.byKey(const Key('toast-succes')), findsOneWidget);

      await tester.tap(find.byKey(Key('deces-${uuid(61)}')));
      await tester.pumpAndSettle();
      expect(find.text(messages.singleWhere((m) => m.startsWith('Décès'))), findsOneWidget);
      expect(find.byKey(const Key('toast-avertissement')), findsOneWidget);

      final lignes = {for (final e in await db.select(db.infirmaryRecords).get()) e.id: e};
      expect([lignes[uuid(60)]!.status, lignes[uuid(60)]!.syncStatus], ['reintegre', SyncStatus.pending]);
      expect([lignes[uuid(61)]!.status, lignes[uuid(61)]!.syncStatus], ['deces', SyncStatus.pending]);
      await nettoyer(tester);
    }, skip: _sautWeb);

    testWidgets('la modale Nouvelle Entrée Infirmerie : champs, options du Blade, enregistrement', (tester) async {
      final section = _section('suivi');
      final titreModale = _tous(section, r'<h3[^>]*>([^<]*)</h3>').single;
      final options = _tous(section, r'<option>([^<]*)</option>');
      expect(options, ['Quarantaine stricte', 'Infirmerie', 'Simple surveillance']);
      final succes = _messagesPhp().singleWhere((m) => m.startsWith('Entrée infirmerie'));

      await afficher(tester);
      await onglet(tester, 'Suivi Sanitaire');
      await tester.tap(find.byKey(const Key('nouvelle-entree-infirmerie')));
      await tester.pumpAndSettle();
      final modale = find.byType(ModaleAgri);
      expect(tester.widget<ModaleAgri>(modale).titre, titreModale);
      expect(tester.widget<ModaleAgri>(modale).largeur, LargeurModale.sm);
      for (final l in _tous(section, r'<label[^>]*>([^<]*)</label>')) {
        expect(find.descendant(of: modale, matching: find.text(l.toUpperCase())), findsOneWidget, reason: l);
      }
      final exemples = exemplesDe(tester, modale);
      for (final p in _tous(section, r'placeholder="([^"]*)"')) {
        expect(exemples, contains(p), reason: p);
      }

      // Champs obligatoires vides : rien n'est écrit.
      await tester.tap(find.byKey(const Key('infirmerie-enregistrer')));
      await tester.pumpAndSettle();
      expect(await db.select(db.infirmaryRecords).get(), isEmpty);

      await tester.tap(find.byKey(const Key('infirmerie-bande')));
      await tester.pumpAndSettle();
      expect(find.text('LOT-ANC-01'), findsNothing);
      await tester.tap(find.text('LOT-VOL-01').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('infirmerie-sujet')), '#B-12');
      await tester.enterText(find.byKey(const Key('infirmerie-motif')), 'Suspicion Newcastle');
      await tester.tap(find.byKey(const Key('infirmerie-isolement')));
      await tester.pumpAndSettle();
      for (final o in options) {
        expect(find.text(o), findsWidgets, reason: o);
      }
      await tester.tap(find.text('Simple surveillance').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('infirmerie-enregistrer')));
      await tester.pumpAndSettle();

      final e = await db.select(db.infirmaryRecords).getSingle();
      expect([e.lotId, e.sujetRef, e.motif, e.isolationLevel, e.status, e.syncStatus],
          [volailles, '#B-12', 'Suspicion Newcastle', 'Simple surveillance', 'en_cours', SyncStatus.pending]);
      expect(e.entryDate, aujourdhui);
      expect(find.text(succes), findsOneWidget);
      expect(find.text('LOT-VOL-01 — #B-12'), findsOneWidget);
      await nettoyer(tester);
    }, skip: _sautWeb);
  });

  group('H8b — Calendrier', () {
    testWidgets('sous-titre, bouton, légende du Blade, plus la légende des sources du poste', (tester) async {
      final section = _section('calendrier');
      await afficher(tester);
      await onglet(tester, 'Calendrier Vétérinaire');

      expect(find.text(_tous(section, r'<p class="text-xs text-outline mt-xs">([^<]+)</p>').single), findsOneWidget);
      final bouton = _tous(section, r'wire:click="newIntervention"[^>]*>\s*<span[^>]*>[^<]*</span>([^<]+)</button>');
      expect(find.text(bouton.single), findsOneWidget);
      for (final l in _tous(section, r'inline-block bg-[\w-]+"></span>([^<]+)</span>')) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(find.byKey(const Key('legende-source-planifie')), findsOneWidget);
      expect(find.byKey(const Key('legende-source-calcule')), findsOneWidget);
      await nettoyer(tester);
    }, skip: _sautWeb);

    testWidgets('sans bande active : le message exact du Blade', (tester) async {
      final vide = _tous(_section('calendrier'), r'<p class="text-sm text-outline">([^<]+)</p>').single;
      await db.update(db.livestockLots).write(const LivestockLotsCompanion(status: Value('cloture')));
      await afficher(tester);
      await onglet(tester, 'Calendrier Vétérinaire');
      expect(find.text(vide), findsOneWidget);
      await nettoyer(tester);
    }, skip: _sautWeb);

    testWidgets('planifier une intervention : modale du Blade, écriture pending, message du PHP', (tester) async {
      final section = _section('calendrier');
      final succes = _messagesPhp().singleWhere((m) => m.startsWith('Intervention planifiée'));
      await afficher(tester);
      await onglet(tester, 'Calendrier Vétérinaire');
      await tester.tap(find.byKey(const Key('planifier-intervention')));
      await tester.pumpAndSettle();
      final modale = find.byType(ModaleAgri);
      expect(tester.widget<ModaleAgri>(modale).titre, _tous(section, r'<h3[^>]*>([^<]*)</h3>').single);
      for (final l in _tous(section, r'<label[^>]*>([^<]*)</label>')) {
        expect(find.descendant(of: modale, matching: find.text(l.toUpperCase())), findsOneWidget, reason: l);
      }
      expect(exemplesDe(tester, modale), contains(_tous(section, r'placeholder="([^"]*)"').single));
      for (final b in _tous(section, r'<button type="(?:submit|button)" (?:x-on:click="[^"]*" )?class="px-md[^"]*">([^<]+)</button>')) {
        expect(find.descendant(of: modale, matching: find.text(b)), findsOneWidget, reason: b);
      }

      await tester.tap(find.byKey(const Key('plan-bande')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LOT-LAP-01').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('plan-intervention')), 'Rappel Myxomatose');
      await tester.tap(find.byKey(const Key('plan-planifier')));
      await tester.pumpAndSettle();

      final v = await db.select(db.veterinaryCalendarEvents).getSingle();
      expect([v.lotId, v.taskType, v.status, v.syncStatus, v.scheduledDate],
          [lapins, 'Rappel Myxomatose', 'planned', SyncStatus.pending, aujourdhui]);
      expect(find.text(succes), findsOneWidget);
      await nettoyer(tester);
    }, skip: _sautWeb);

    testWidgets('clic sur une case planifiée = confirmation d administration (done), message du PHP', (tester) async {
      final succes = _messagesPhp().singleWhere((m) => m.startsWith('Administration confirmée'));
      await evenement(uuid(70), lapins, jourDe(2), 'planned', tache: 'Rappel Myxomatose');
      await afficher(tester);
      await onglet(tester, 'Calendrier Vétérinaire');
      expect(find.byKey(Key('planifie-${uuid(70)}')), findsOneWidget);

      await tester.tap(find.byKey(Key('planifie-${uuid(70)}')));
      await tester.pumpAndSettle();

      final v = await db.select(db.veterinaryCalendarEvents).getSingle();
      expect([v.status, v.syncStatus], ['done', SyncStatus.pending]);
      expect(find.text(succes), findsOneWidget);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle();

      // Une case « done » ne se confirme plus (`@if($event->status !== 'done')`).
      await tester.tap(find.byKey(Key('planifie-${uuid(70)}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('toast-succes')), findsNothing);
      await nettoyer(tester);
    });

    testWidgets('« Vaccinations planifiées » au registre = événements planned', (tester) async {
      await evenement(uuid(80), lapins, jourDe(2), 'planned');
      await evenement(uuid(81), volailles, jourDe(3), 'planned');
      await evenement(uuid(82), volailles, jourDe(4), 'done');
      await afficher(tester);
      final carte = tester.widget<CarteKpi>(
        find.byWidgetPredicate((w) => w is CarteKpi && w.libelle == 'Vaccinations planifiées'),
      );
      expect(carte.valeur, '2');
      await nettoyer(tester);
    });
  });
}
