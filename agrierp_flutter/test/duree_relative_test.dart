import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/duree_relative.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/theme/agri_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coque_poste.dart';
import 'php_laravel.dart';

/// Ticket U13 — LA CLOCHE DIT « IL Y A … » COMME AU WEB (`$notif->created_at->diffForHumans()`, Carbon en français, à
/// l'heure du Bénin), au lieu de « jj/mm/AAAA - HH:mm ».
///
/// 1. Témoins calculés à la main (seuils et formulations relevés en exécutant le PHP du serveur, voir le ticket).
/// 2. **Parité exécutée** : le VRAI Carbon du serveur (application démarrée : locale `fr`, `Africa/Porto-Novo`) rend
///    une série d'écarts — secondes, minutes, heures, jours, semaines, mois, années, fins de mois, 29 février, instants
///    à venir — et [DureeRelative] doit rendre le même texte, mot pour mot.
/// 3. La cloche de la coque du poste l'affiche.
void main() {
  /// Un instant donné par son heure MURALE du Bénin.
  DateTime benin(int a, int m, int j, [int h = 0, int i = 0, int s = 0, int us = 0]) =>
      HeureBenin.versInstant(DateTime(a, m, j, h, i, s, 0, us));

  group('témoins écrits à la main', () {
    final maintenant = benin(2026, 10, 19, 12);
    String il(Duration avant) => DureeRelative.depuis(maintenant.subtract(avant), maintenant: maintenant);

    test('secondes, minutes, heures, jours, semaines : unité la plus grande, tronquée', () {
      expect(il(Duration.zero), 'il y a 0 seconde');
      expect(il(const Duration(seconds: 1)), 'il y a 1 seconde');
      expect(il(const Duration(seconds: 59)), 'il y a 59 secondes');
      expect(il(const Duration(seconds: 60)), 'il y a 1 minute');
      expect(il(const Duration(seconds: 119)), 'il y a 1 minute');
      expect(il(const Duration(minutes: 2)), 'il y a 2 minutes');
      expect(il(const Duration(minutes: 59, seconds: 59)), 'il y a 59 minutes');
      expect(il(const Duration(hours: 1)), 'il y a 1 heure');
      expect(il(const Duration(hours: 23, minutes: 59)), 'il y a 23 heures');
      expect(il(const Duration(days: 1)), 'il y a 1 jour');
      expect(il(const Duration(days: 6)), 'il y a 6 jours');
      expect(il(const Duration(days: 7)), 'il y a 1 semaine');
      expect(il(const Duration(days: 13)), 'il y a 1 semaine');
      expect(il(const Duration(days: 14)), 'il y a 2 semaines');
      expect(il(const Duration(days: 29)), 'il y a 4 semaines');
    });

    test('mois et années CALENDAIRES (19 septembre → 19 octobre = 1 mois ; 31 janvier → 1er mars = 4 semaines)', () {
      expect(il(const Duration(days: 30)), 'il y a 1 mois', reason: '19/09 12 h → 19/10 12 h');
      expect(il(const Duration(days: 59)), 'il y a 1 mois');
      expect(il(const Duration(days: 364)), 'il y a 11 mois');
      expect(il(const Duration(days: 365)), 'il y a 1 an');
      expect(il(const Duration(days: 731)), 'il y a 2 ans');
      expect(
        DureeRelative.depuis(benin(2026, 1, 31), maintenant: benin(2026, 3, 1)),
        'il y a 4 semaines',
        reason: '29 jours : février puis janvier en retenue (timelib)',
      );
      expect(DureeRelative.depuis(benin(2026, 1, 29), maintenant: benin(2026, 3, 1)), 'il y a 1 mois');
      expect(DureeRelative.depuis(benin(2024, 2, 29), maintenant: benin(2025, 2, 28)), 'il y a 11 mois');
      expect(DureeRelative.depuis(benin(2024, 2, 29), maintenant: benin(2025, 3, 1)), 'il y a 1 an');
    });

    test('à venir (horloge du poste en retard) : « dans … », jamais « il y a »', () {
      expect(DureeRelative.depuis(maintenant.add(const Duration(seconds: 1)), maintenant: maintenant), 'dans 1 seconde');
      expect(DureeRelative.depuis(maintenant.add(const Duration(minutes: 5)), maintenant: maintenant), 'dans 5 minutes');
      // Une demi-seconde d'avance : « dans 0 seconde » (la fraction est retenue sur les secondes).
      expect(
        DureeRelative.depuis(benin(2026, 10, 19, 12, 0, 1), maintenant: benin(2026, 10, 19, 12, 0, 0, 500000)),
        'dans 0 seconde',
      );
      expect(DureeRelative.depuis(benin(2026, 3, 1), maintenant: benin(2026, 1, 31)), 'dans 1 mois');
    });

    test("à l'heure du Bénin, quel que soit l'instant transmis (UTC ou local)", () {
      final utc = DateTime.utc(2026, 10, 19, 10, 55);
      expect(DureeRelative.depuis(utc, maintenant: DateTime.utc(2026, 10, 19, 11)), 'il y a 5 minutes');
      expect(DureeRelative.depuis(utc.toLocal(), maintenant: DateTime.utc(2026, 10, 19, 11)), 'il y a 5 minutes');
    });
  });

  test(
    '⚠️ parité exécutée : le texte du poste est celui de Carbon (diffForHumans, fr, Africa/Porto-Novo)',
    () {
      // (maintenant, écart en secondes, sens) : passé (+) ou à venir (−) — et fins de mois, années bissextiles.
      final references = [
        '2026-10-19 12:00:00.000000',
        '2026-03-01 00:00:00.250000',
        '2026-01-31 23:59:59.000000',
        '2028-02-29 06:30:00.999999',
        '2026-12-31 23:00:00.000000',
        '2026-05-01 01:00:00.000000',
      ];
      const ecarts = [
        0, 1, 2, 30, 59, 60, 61, 119, 120, 3599, 3600, 3661, 7199, 7200, 86399, 86400, 86401, 172799, 172800,
        6 * 86400, 7 * 86400, 13 * 86400, 14 * 86400, 27 * 86400, 28 * 86400, 29 * 86400, 30 * 86400, 31 * 86400,
        45 * 86400, 59 * 86400, 60 * 86400, 61 * 86400, 90 * 86400, 180 * 86400, 364 * 86400, 365 * 86400,
        366 * 86400, 400 * 86400, 730 * 86400, 731 * 86400, 1200 * 86400,
      ];
      final cas = [
        for (final r in references)
          for (final e in ecarts) ...[
            {'maintenant': r, 'ecart': e},
            {'maintenant': r, 'ecart': -e},
          ],
      ];

      final php = executerPhp('<?php\n$amorceApplication\n$_script', cas, application: true)! as List;

      final ecartsTrouves = <String>[];
      final unites = <String>{};
      for (var k = 0; k < cas.length; k++) {
        final maintenant = DateTime.parse(cas[k]['maintenant']! as String);
        // Arithmétique en UTC sur les champs de l'heure murale : jamais l'heure d'été de la machine de test.
        final instant = DateTime.utc(
          maintenant.year, maintenant.month, maintenant.day, maintenant.hour, maintenant.minute, maintenant.second,
        ).add(Duration(seconds: -(cas[k]['ecart']! as int)));
        final poste = DureeRelative.depuis(
          HeureBenin.versInstant(instant),
          maintenant: HeureBenin.versInstant(maintenant),
        );
        final web = (php[k] as Map)['texte'] as String;
        if (poste != web) ecartsTrouves.add('${cas[k]} : poste « $poste », web « $web »');
        unites.add(web.replaceAll(RegExp(r'^(il y a|dans) \d+ '), ''));
      }
      expect(ecartsTrouves, isEmpty);
      // La série couvre ce qu'elle prétend couvrir.
      expect(
        unites,
        containsAll(['seconde', 'secondes', 'minute', 'minutes', 'heure', 'heures', 'jour', 'jours', 'semaine',
          'semaines', 'mois', 'an', 'ans']),
      );
      expect([for (final r in php) (r as Map)['texte'] as String].where((t) => t.startsWith('dans ')), isNotEmpty);
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets('U13 — la cloche de la coque affiche « il y a 5 minutes » (et non la date)', (t) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final maintenant = DateTime.utc(2026, 10, 19, 11);
    HeureBenin.horloge = () => maintenant;
    addTearDown(HeureBenin.reinitialiser);
    await t.runAsync(
      () => db
          .into(db.notifications)
          .insert(
            NotificationsCompanion.insert(
              id: 'aaaaaaaa-0000-4000-8000-0000000000c1',
              type: 'stock_low',
              title: 'Stock Provende lapins bas',
              message: 'Autonomie restante : 2,0 jours',
              createdAt: Value(maintenant.subtract(const Duration(minutes: 5))),
            ),
          ),
    );
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: AgriTheme.light, home: coqueDeTest(db)));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('cloche-notifications')));
    await t.pumpAndSettle();

    expect(find.text('il y a 5 minutes'), findsOneWidget);
    expect(find.text('19/10/2026 - 11:55'), findsNothing);
  });
}

/// Le vrai Carbon de l'application (locale et fuseau de la configuration) : `created_at->diffForHumans()` quand
/// `now()` vaut `maintenant` (heure murale du Bénin, microsecondes comprises).
const _script = r'''
$cas = json_decode(file_get_contents($argv[1]), true);
if (config('app.timezone') !== 'Africa/Porto-Novo' && env('APP_TIMEZONE') === null) {
    config(['app.timezone' => 'Africa/Porto-Novo']);
    date_default_timezone_set('Africa/Porto-Novo');
}
$sortie = [];
foreach ($cas as $c) {
    $maintenant = Illuminate\Support\Carbon::parse($c['maintenant'], 'Africa/Porto-Novo');
    Illuminate\Support\Carbon::setTestNow($maintenant);
    $creee = $maintenant->copy()->startOfSecond()->subSeconds($c['ecart']);
    $sortie[] = ['texte' => $creee->diffForHumans(), 'locale' => app()->getLocale(), 'fuseau' => $creee->tzName];
}
echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
''';
