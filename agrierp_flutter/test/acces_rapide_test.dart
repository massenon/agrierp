import 'dart:io';

import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_theme.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/widgets/acces_rapide.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'coque_poste.dart';
import 'package:agrierp/core/theme/symboles_agri.dart';

/// Ticket H1 — BOUTON FLOTTANT ET PANNEAU « ACCÈS RAPIDE » (`layouts/app.blade.php:219-247`).
///
/// 🔴 Absents au poste (audit du 19/10/2026) : les fiches d'espèce n'y étaient atteignables que par Gestion
/// Élevage. Les libellés sont LUS DANS LE BLADE (le maître), pas recopiés : un renommage au web fait rougir ce test.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('les 13 entrées et leurs 3 groupes sont ceux du Blade, dans l ordre', () {
    final blade = File('$dossierLaravel/resources/views/layouts/app.blade.php').readAsStringSync();
    final debut = blade.indexOf('Accès Rapide</span>');
    final fin = blade.indexOf('Ticket AIDE-1', debut);
    expect(debut, greaterThan(0), reason: 'panneau « Accès Rapide » introuvable dans le Blade');
    final panneau = blade.substring(debut, fin);

    // Une entrée = `<a …><span class="… text-<couleur> …">icone</span><span …>Libellé</span></a>` ; un séparateur =
    // `<div class="border-t …">`.
    final groupesBlade = <List<String>>[[]];
    final couleursBlade = <String>[];
    final motif = RegExp(
      r'<a [^>]*><span class="material-symbols-outlined text-([\w-]+) [^"]*">(\w+)</span><span[^>]*>([^<]+)</span></a>'
      r'|<div class="border-t',
    );
    for (final m in motif.allMatches(panneau)) {
      if (m.group(2) == null) {
        groupesBlade.add([]);
      } else {
        if (groupesBlade.last.isEmpty) couleursBlade.add(m.group(1)!);
        groupesBlade.last.add('${m.group(2)}|${m.group(3)!.replaceAll('&amp;', '&').trim()}');
      }
    }

    String nomIcone(IconData i) => switch (i) {
      SymbolesAgri.cruelty_free => 'cruelty_free',
      SymbolesAgri.egg => 'egg',
      SymbolesAgri.egg_alt => 'egg_alt',
      SymbolesAgri.pets => 'pets',
      SymbolesAgri.bug_report => 'bug_report',
      SymbolesAgri.favorite => 'favorite',
      SymbolesAgri.vaccines => 'vaccines',
      SymbolesAgri.point_of_sale => 'point_of_sale',
      SymbolesAgri.inventory_2 => 'inventory_2',
      SymbolesAgri.dashboard => 'dashboard',
      SymbolesAgri.receipt => 'receipt',
      SymbolesAgri.account_balance => 'account_balance',
      SymbolesAgri.picture_as_pdf => 'picture_as_pdf',
      _ => '?',
    };
    final groupesPoste = [
      for (final (_, entrees) in AccesRapide.groupes) [for (final (i, l, _) in entrees) '${nomIcone(i)}|$l'],
    ];

    expect(groupesPoste, groupesBlade);
    expect(groupesPoste.expand((g) => g), hasLength(13));
    // Couleur des icônes par groupe : émeraude, bleu, forêt.
    expect(couleursBlade, ['brand-emerald', 'info-blue', 'brand-forest']);
    expect([for (final (c, _) in AccesRapide.groupes) c], [AgriColors.brandEmerald, AgriColors.infoBlue, AgriColors.brandForest]);
  });

  testWidgets('le bouton ouvre le tiroir ; une entrée y mène à l écran et ferme le tiroir', (t) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: AgriTheme.light, home: coqueDeTest(db)));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('bouton-acces-rapide')), findsOneWidget);
    await t.tap(find.byKey(const Key('bouton-acces-rapide')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('panneau-acces-rapide')), findsOneWidget);
    expect(find.text('Accès Rapide'), findsOneWidget);
    expect(find.text('Fiche Volailles Reproducteurs'), findsOneWidget);

    await t.tap(find.byKey(Key('acces-rapide-${EcranPoste.fichePorcs.name}')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('panneau-acces-rapide')), findsNothing);
    expect(t.widget<Text>(find.byKey(const Key('fil-ariane'))).data, contains('Porcs'));
  });

  testWidgets('la croix ferme le tiroir sans naviguer', (t) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: AgriTheme.light, home: coqueDeTest(db)));
    await t.pumpAndSettle();
    final avant = t.widget<Text>(find.byKey(const Key('fil-ariane'))).data;

    await t.tap(find.byKey(const Key('bouton-acces-rapide')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('acces-rapide-fermer')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('panneau-acces-rapide')), findsNothing);
    expect(t.widget<Text>(find.byKey(const Key('fil-ariane'))).data, avant);
  });
}
