import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.12 — SECTION « TRAITEMENTS & PROPHYLAXIE » DE LA FICHE LAPINS.
///
/// 🔁 Ticket U12a — la section est celle du Blade (`fiche-lapins.blade.php` + `x-prophylaxie-du-jour`) : titre
/// « Traitements & Prophylaxie », badge « N Prévu(s) », « Protocole non calculable — … », bouton actif sans case
/// cochée (le web n'a pas de garde ; le dépôt n'écrit alors rien et le toast le dit).
///
/// ⚠️⚠️ Le test qui compte est le dernier : valider un traitement rémanent
/// doit **écrire un vrai soin et une vraie période de rémanence**. Une case
/// qui ne ferait que changer de couleur laisserait vendre une bande traitée —
/// c'est exactement le défaut que la maquette ne peut pas, elle, révéler.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  // La bande est mise en lot le jour même du test : le protocole borné à J1
  // est donc dû aujourd'hui, sans dépendre de la date réelle d'exécution.
  final aujourdHui = HeureBenin.maintenant();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'CUN-2026-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            speciesCode: const Value('cuniculture'),
            createdDate: Value(
              DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day),
            ),
            initialQuantity: const Value(40),
            currentQuantity: const Value(40),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> protocole({
    required String traitement,
    int? debut = 1,
    int? fin = 1,
    int remanence = 0,
  }) async {
    await db
        .into(db.prophylaxisScheduleStandards)
        .insert(
          ProphylaxisScheduleStandardsCompanion.insert(
            id: '11111111-1111-4111-8111-111111111111',
            speciesCode: 'cuniculture',
            periodLabel: 'Le 1er jour',
            cycleDayStart: Value(debut),
            cycleDayEnd: Value(fin),
            treatment: traitement,
            productRecommended: const Value('Ivermectine'),
            dosage: const Value('0,2 ml / kg'),
            withdrawalDays: Value(remanence),
          ),
        );
  }

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FicheLapinsScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('la section porte le titre du Blade', (tester) async {
    await afficher(tester);

    expect(
      find.text('TRAITEMENTS & PROPHYLAXIE'),
      findsOneWidget,
    );
  });

  testWidgets('sans traitement du jour, le Blade affiche « Libre »', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Libre'), findsOneWidget);
    expect(
      find.text('— Aucun traitement récurrent programmé pour ce jour —'),
      findsOneWidget,
    );
  });

  testWidgets('un traitement dû est affiché avec son produit et sa posologie', (
    tester,
  ) async {
    await protocole(traitement: 'Anticoccidien', remanence: 7);
    await afficher(tester);

    // Une seule ligne du Blade : traitement en gras, puis « (produit — posologie) ».
    expect(find.text('Anticoccidien (Ivermectine — 0,2 ml / kg)', findRichText: true), findsOneWidget);
    expect(find.text('Rémanence 7j'), findsOneWidget);
    expect(find.text('1 Prévu(s)'), findsOneWidget);
    expect(find.text('Indice Rouge : 1 soin(s) en attente'), findsOneWidget);
  });

  testWidgets(
    "⚠️ une bande en reproduction SANS saillie connue affiche l'indétermination, jamais « Libre »",
    (tester) async {
      await (db.update(db.livestockLots)..where((t) => t.id.equals(bandeId)))
          .write(const LivestockLotsCompanion(stage: Value('reproduction')));
      await protocole(traitement: 'Vitamines', debut: 1, fin: 60);
      await afficher(tester);

      expect(find.text('Indéterminé'), findsOneWidget);
      expect(
        find.text('Libre'),
        findsNothing,
        reason: 'une inconnue ne doit pas se lire comme une absence de soin',
      );
      expect(find.textContaining('Protocole non calculable —'), findsOneWidget);
      expect(find.textContaining('aucune saillie'), findsOneWidget);
      expect(find.textContaining('hors ligne'), findsNothing);
    },
  );

  testWidgets(
    "⚠️ F0.91 : une bande en reproduction AVEC saillie voit son protocole calculé depuis la saillie",
    (tester) async {
      // Mise en lot il y a 40 jours (le traitement J1 n'est pas dû selon elle),
      // saillie aujourd'hui : J1 depuis la saillie, le traitement J1 est dû.
      final jour = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day);
      await (db.update(
        db.livestockLots,
      )..where((t) => t.id.equals(bandeId))).write(
        LivestockLotsCompanion(
          stage: const Value('reproduction'),
          createdDate: Value(DateTime(jour.year, jour.month, jour.day - 40)),
        ),
      );
      await db
          .into(db.livestockReproductionEvents)
          .insert(
            LivestockReproductionEventsCompanion.insert(
              id: 'cccccccc-1111-4111-8111-cccccccccccc',
              deviceId: 'serveur',
              syncStatus: const Value(SyncStatus.synced),
              updatedAt: jour,
              lotId: bandeId,
              motherRef: 'R1',
              saillieDate: Value(jour),
            ),
          );
      await protocole(traitement: 'Vitamines', debut: 1, fin: 1);
      await afficher(tester);

      expect(find.text('Indéterminé'), findsNothing);
      expect(find.textContaining('Protocole non calculable'), findsNothing);
      expect(find.textContaining('Vitamines', findRichText: true), findsOneWidget);
      expect(find.text('1 Prévu(s)'), findsOneWidget);
    },
  );

  testWidgets(
    '⚠️ les entrées calendaires non évaluées sont annoncées, pas masquées',
    (tester) async {
      await protocole(traitement: 'Désinfection', debut: null, fin: null);
      await afficher(tester);

      expect(find.textContaining('sans jour de cycle (calendaires, ex. « Le 1er du mois ») ne sont pas évaluées ici.'), findsOneWidget);
    },
  );

  testWidgets(
    '⚠️⚠️ valider écrit un vrai soin ET la rémanence qui bloque la caisse',
    (tester) async {
      await protocole(traitement: 'Anticoccidien', remanence: 7);
      await afficher(tester);

      // Le bouton est actif sans case cochée, comme au web.
      final bouton = find.byKey(const Key('bouton-valider-traitements'));
      expect(tester.widget<ElevatedButton>(bouton).onPressed, isNotNull);

      await tester.ensureVisible(find.byType(Checkbox).last);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox).last).value, isTrue);

      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();

      final registre = await soins.historique(bandeId);
      expect(registre, hasLength(1));
      expect(registre.single.actionType, 'Anticoccidien');
      expect(registre.single.productUsed, 'Ivermectine');

      final remanences = await db.select(db.veterinaryWithdrawalPeriods).get();
      expect(
        remanences,
        hasLength(1),
        reason: 'sans elle, la caisse du poste vendrait une bande traitée',
      );
      expect(remanences.single.lotId, bandeId);
      expect(find.text('1 traitement(s) enregistré(s) au registre vétérinaire.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('après validation, la section passe à « Validé / Effectué »', (
    tester,
  ) async {
    await protocole(traitement: 'Anticoccidien', remanence: 7);
    await afficher(tester);

    // ⚠️ `ensureVisible` AVANT LE TAP : la case est sous la ligne de
    // flottaison en 800x600, et un tap hors champ frappe silencieusement ce
    // qui se trouve a ces coordonnees — le test passerait sans rien valider.
    await tester.ensureVisible(find.byType(Checkbox).last);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();

    final bouton = find.byKey(const Key('bouton-valider-traitements'));
    await tester.ensureVisible(bouton);
    await tester.tap(bouton);
    await tester.pumpAndSettle();

    expect(find.text('Validé / Effectué'), findsOneWidget);
    expect(find.text('Indice Rouge : 0 soin(s) en attente'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
