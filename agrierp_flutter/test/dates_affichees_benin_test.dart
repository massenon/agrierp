import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_repository.dart';
import 'package:agrierp/features/notifications/notifications_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:agrierp/features/profil/mon_profil_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket U12b — RESTE DE S-T11 : LES DATES ET HEURES AFFICHÉES SONT CELLES DU BÉNIN.
///
/// S-T11 a mis le JOUR MÉTIER à l'heure du Bénin ; les INSTANTS servis par le serveur (`created_at` du journal d'audit
/// et des notifications, `updated_at`) s'affichaient encore à l'heure de Windows. Le web les affiche à l'heure du
/// serveur (`Africa/Porto-Novo`, UTC+1). Chaque cas ci-dessous écrit un instant UTC — 23 h 30 le 27 juillet, soit
/// 00 h 30 le 28 au Bénin — et attend l'heure du Bénin, quel que soit le fuseau du processus : la suite passe aussi
/// sous `TZ=America/New_York` et `TZ=Asia/Tokyo` (`flutter test` respecte `TZ`). Sous l'ancien code, un poste réglé en
/// UTC affichait « 27/07/2026 23:30 », à New York « 27/07/2026 19:30 », à Tokyo « 28/07/2026 08:30 ».
void main() {
  /// 00 h 30 le 28 juillet 2026 au Bénin.
  final instant = DateTime.utc(2026, 7, 27, 23, 30);

  test(
    'U12b — Centre de notifications et cloche : la date est celle du Bénin',
    () {
      final ligne = LigneNotification(
        id: 'n',
        message: 'Stock bas',
        categorie: 'Stocks',
        gravite: 'info',
        lue: false,
        date: instant,
        lien: null,
      );

      // `$notif->created_at->format('d/m/Y - H:i')` du web.
      expect(ligne.dateTexte, '28/07/2026 - 00:30');
      // Le même instant, reçu en heure locale de Windows, se lit pareil.
      expect(
        LigneNotification(
          id: 'n',
          message: 'Stock bas',
          categorie: 'Stocks',
          gravite: 'info',
          lue: false,
          date: instant.toLocal(),
          lien: null,
        ).dateTexte,
        '28/07/2026 - 00:30',
      );
    },
  );

  test(
    'U12b — Mon Profil : dernière connexion et journal à l heure du Bénin',
    () {
      // `->created_at->format('d/m/Y H:i')` du web.
      expect(MonProfilScreen.dateHeure(instant), '28/07/2026 00:30');
      expect(MonProfilScreen.dateHeure(instant.toLocal()), '28/07/2026 00:30');
    },
  );

  testWidgets('U12b — Paramètres, Audit Logs : l horodatage est celui du Bénin', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            id: 'a'.padRight(36, '0'),
            userName: const Value('Manager Olouwachegoun'),
            action: 'login',
            module: const Value('auth'),
            createdAt: Value(instant),
          ),
        );

    tester.view.physicalSize = const Size(1700, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ParametresGenerauxScreen(
          depot: ParametresGenerauxRepository(database: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final onglet = find.byKey(
      const Key('onglet-parametres-generaux-Audit Logs'),
    );
    await tester.ensureVisible(onglet);
    await tester.pumpAndSettle();
    await tester.tap(onglet);
    await tester.pumpAndSettle();

    expect(find.text('28/07/2026 00:30'), findsOneWidget);
    // Démontage AVANT la fermeture de la base : les flux Drift de l'écran se ferment proprement.
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'U12b — Suivi de la reproduction : un échec se range dans le mois du Bénin',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      // `updated_at` : 23 h 30 UTC le 31 juillet, soit 00 h 30 le 1er AOÛT au Bénin.
      await db
          .into(db.livestockReproductionEvents)
          .insert(
            LivestockReproductionEventsCompanion.insert(
              id: 'e'.padRight(36, '0'),
              deviceId: 'serveur',
              syncStatus: const Value(SyncStatus.synced),
              updatedAt: DateTime.utc(2026, 7, 31, 23, 30),
              lotId: 'l'.padRight(36, '0'),
              motherRef: 'R1',
              status: const Value('echec'),
            ),
          );
      final depot = SuiviReproductionRepository(database: db);

      // `whereMonth('updated_at', now()->month)` au serveur : août.
      expect((await depot.charger(quand: DateTime(2026, 8, 10))).echecs, 1);
      expect((await depot.charger(quand: DateTime(2026, 7, 20))).echecs, 0);
    },
  );
}
