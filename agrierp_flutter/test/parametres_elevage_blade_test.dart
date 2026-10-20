import 'dart:io';

import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/modale_agri.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/elevage/parametres_elevage_repository.dart';
import 'package:agrierp/features/elevage/parametres_elevage_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Tickets H9, H9b et H10 (poste) — GARDE-FOU : PARAMÈTRES ÉLEVAGE CONFRONTÉ AU BLADE MAÎTRE.
///
/// ⚠️⚠️ **LE BLADE FAIT FOI** (doctrine, article 5). Onglets, titres, sous-titres, boutons, colonnes (dans
/// l'ordre et leur alignement), messages « vide », modales (titres « Saisir / Modifier … », champs, exemples,
/// options, pied « Annuler » / « Enregistrer »), confirmation de suppression, bloc « Rappel des soins
/// planifiés », formulaire de numérotation et messages des toasts sont LUS dans
/// `parametres-elevage.blade.php`, `modal-confirm-permanent-delete.blade.php` et `ParametresElevage.php`,
/// jamais recopiés ici : une retouche du web fait rougir le poste au lieu de diverger en silence.
///
/// Deux confrontations de plus, au code du serveur : les clés envoyées par le moteur sont exactement celles
/// que valide `RecordParametresElevageFromDeviceAction`, et le droit d'écrire (`manage-elevage`) est celui
/// que donne `RolesAndPermissionsSeeder`.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Serveur feint qui garde le corps de l'envoi et accepte tout.
class _Serveur extends Interceptor {
  Map<String, dynamic>? envoi;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      envoi = options.data as Map<String, dynamic>;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {'server_time': '2026-10-19T12:00:00Z'},
      ),
    );
  }
}

// ── Lecture du web (maître) ───────────────────────────────────────────────────────────────────────────

String? _lireLaravel(String relatif) {
  final f = File('$dossierLaravel/$relatif');
  return f.existsSync() ? f.readAsStringSync() : null;
}

final String? _blade = _lireLaravel(
  'resources/views/livewire/elevage/parametres-elevage.blade.php',
);
final String? _confirmation = _lireLaravel(
  'resources/views/components/modal-confirm-permanent-delete.blade.php',
);
final String? _livewire = _lireLaravel(
  'app/Livewire/Elevage/ParametresElevage.php',
);
final String? _action = _lireLaravel(
  'app/Actions/RecordParametresElevageFromDeviceAction.php',
);
final String? _seeder = _lireLaravel(
  'database/seeders/RolesAndPermissionsSeeder.php',
);

/// Sans `agrierp_laravel/`, le web ne peut pas être lu : les tests qui le lisent se sautent.
final bool _sautWeb = [
  _blade,
  _confirmation,
  _livewire,
  _action,
  _seeder,
].contains(null);

String _decoder(String html) => html
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&gt;', '>')
    .replaceAll('&lt;', '<')
    .replaceAll('&#039;', "'")
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<String> _tous(String source, String motif) => RegExp(
  motif,
  dotAll: true,
).allMatches(source).map((m) => _decoder(m.group(1)!)).toList();

/// Section d'un onglet (`@if($tab === '…')` jusqu'à l'onglet suivant).
String _section(String onglet) {
  final b = _blade!;
  final debut = b.indexOf("@if(\$tab === '$onglet')");
  expect(debut, greaterThan(-1), reason: 'onglet $onglet absent du Blade');
  final suivant = b.indexOf("@if(\$tab === '", debut + 1);
  return b.substring(debut, suivant < 0 ? b.length : suivant);
}

/// Partie « page » (avant la modale) et partie « modale » d'une section.
(String, String) _pageEtModale(String section) {
  final i = section.indexOf('<x-modal name=');
  return i < 0
      ? (section, '')
      : (section.substring(0, i), section.substring(i));
}

/// Colonnes `<th>` d'une section : (libellé, aligné à droite).
List<(String, bool)> _colonnes(String section) => [
  for (final m in RegExp(
    r'<th class="([^"]*)">([^<]*)</th>',
  ).allMatches(section))
    (_decoder(m.group(2)!), m.group(1)!.contains('text-right')),
];

/// Titre de la modale : `{{ $editing… ? 'Modifier …' : 'Saisir …' }}` → (modifier, créer).
(String, String) _titresModale(String modale) {
  final m = RegExp(
    r'''<h3[^>]*>\{\{ \$\w+ \? (["'])(.+?)\1 : (["'])(.+?)\3 \}\}</h3>''',
  ).firstMatch(modale)!;
  return (m.group(2)!, m.group(4)!);
}

/// Messages des toasts du composant (`dispatch('toast', message: '…')`).
List<String> _messagesPhp() => _tous(_livewire!, r"message: '([^']+)'");

/// Clés validées par une méthode de l'Action serveur (`$this->valider($ligne, [ 'cle' => … ])`).
Set<String> _clesValidees(String methode) {
  final a = _action!;
  final debut = a.indexOf('private function $methode(');
  expect(debut, greaterThan(-1), reason: methode);
  final fin = a.indexOf(']);', debut);
  return {
    for (final m in RegExp(
      r"'(\w+)' => \[",
    ).allMatches(a.substring(debut, fin)))
      m.group(1)!,
  };
}

void main() {
  late AppDatabase db;
  late ParametresElevageRepository depot;

  const especeLapins = 'eeeeeeee-0000-4000-8000-000000000001';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ParametresElevageRepository(
      database: db,
      maintenant: () => DateTime(2026, 10, 19, 10),
    );
    await db
        .into(db.livestockSpecies)
        .insert(
          LivestockSpeciesCompanion.insert(
            id: especeLapins,
            code: 'cuniculture',
            label: 'Cuniculture (Lapins)',
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ParametresElevageScreen(depot: depot, peutModifier: true),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> onglet(WidgetTester tester, String libelle) async {
    await tester.tap(find.byKey(Key('onglet-parametres-$libelle')));
    await tester.pumpAndSettle();
  }

  Future<void> nettoyer(WidgetTester tester) async {
    ToastAgri.toutRetirer();
    await tester.pumpWidget(const SizedBox());
  }

  /// Les en-têtes, lus dans le Blade, sont rendus dans CET ORDRE et avec le même alignement.
  void colonnesConformes(WidgetTester tester, List<(String, bool)> colonnes) {
    final abscisses = <double>[];
    for (final (libelle, droite) in colonnes) {
      final texte = find.text(libelle.toUpperCase());
      expect(texte, findsOneWidget, reason: libelle);
      abscisses.add(tester.getTopLeft(texte).dx);
      expect(
        tester.widget<Text>(texte).textAlign,
        droite ? TextAlign.right : TextAlign.left,
        reason: '$libelle : alignement du Blade',
      );
    }
    for (var i = 1; i < abscisses.length; i++) {
      expect(
        abscisses[i],
        greaterThan(abscisses[i - 1]),
        reason: '${colonnes[i].$1} après ${colonnes[i - 1].$1}',
      );
    }
  }

  /// Exemples (`placeholder`) portés par les champs de la modale ouverte.
  List<String?> exemples(WidgetTester tester) => [
    for (final c in tester.widgetList<TextField>(
      find.descendant(
        of: find.byType(ModaleAgri),
        matching: find.byType(TextField),
      ),
    ))
      c.decoration?.hintText,
  ];

  /// Modale ouverte : libellés (en capitales, classe `uppercase`), exemples et pied du Blade.
  void modaleConforme(WidgetTester tester, String modale) {
    final m = find.byType(ModaleAgri);
    expect(tester.widget<ModaleAgri>(m).largeur, LargeurModale.sm);
    for (final l in _tous(modale, r'<label[^>]*>([^<]*)</label>')) {
      expect(
        find.descendant(of: m, matching: find.text(l.toUpperCase())),
        findsOneWidget,
        reason: 'libellé « $l »',
      );
    }
    final ex = exemples(tester);
    for (final p in _tous(modale, r'placeholder="([^"]*)"')) {
      expect(ex, contains(p), reason: 'exemple « $p »');
    }
    final pied = _tous(
      modale,
      r'<button type="(?:button|submit)"[^>]*class="px-md py-sm rounded-lg[^"]*">([^<]+)</button>',
    );
    expect(pied, ['Annuler', 'Enregistrer']);
    for (final b in pied) {
      expect(
        find.descendant(of: m, matching: find.text(b)),
        findsOneWidget,
        reason: b,
      );
    }
  }

  group('H9 — structure du Blade', () {
    testWidgets('les quatre onglets du Blade, dans son ordre', (tester) async {
      final onglets = _tous(_blade!, r"'label' => '([^']+)'");
      expect(onglets, hasLength(4));
      await afficher(tester);

      final abscisses = [
        for (final o in onglets) tester.getTopLeft(find.text(o)).dx,
      ];
      expect([...abscisses]..sort(), abscisses);
      await nettoyer(tester);
    }, skip: _sautWeb);

    testWidgets(
      'chaque onglet : titre, sous-titre, bouton, colonnes et message vide du Blade',
      (tester) async {
        await afficher(tester);
        for (final (cle, libelle) in [
          ('rationnement', 'Fiche de Rationnement (g/j)'),
          ('prophylaxie', 'Calendriers de Prophylaxie'),
          ('provende', 'Types de Provende'),
        ]) {
          final (page, _) = _pageEtModale(_section(cle));
          await onglet(tester, libelle);

          expect(
            find.text(_tous(page, r'</span>([^<]+)</h2>').single),
            findsOneWidget,
            reason: '$cle : titre',
          );
          expect(
            find.text(
              _tous(
                page,
                r'<p class="text-xs text-outline mt-xs">(.*?)</p>',
              ).single,
            ),
            findsOneWidget,
            reason: '$cle : sous-titre',
          );
          expect(
            find.text(_tous(page, r'add_circle</span>([^<]+)</button>').single),
            findsOneWidget,
            reason: '$cle : bouton',
          );
          colonnesConformes(tester, _colonnes(page));
          // Rationnement : `@foreach` sans `@empty`, aucun message.
          final vides = _tous(page, r'text-center text-outline">([^<]+)</td>');
          if (vides.isEmpty) {
            expect(find.byKey(const Key('tableau-vide')), findsNothing);
          } else {
            expect(find.text(vides.single), findsOneWidget, reason: cle);
          }
        }
        await nettoyer(tester);
      },
      skip: _sautWeb,
    );

    test('prophylaxie : sous-onglets d espèce du Blade, dans son ordre', () {
      final (page, _) = _pageEtModale(_section('prophylaxie'));
      final especes = _tous(page, r'\]\)>([^<]+)</button>');
      expect(especes, EspeceProphylaxie.values.map((e) => e.libelle).toList());
      final codes = RegExp(
        r"\$set\('prophySpecies', '(\w+)'\)",
      ).allMatches(page).map((m) => m.group(1)).toList();
      expect(codes, EspeceProphylaxie.values.map((e) => e.code).toList());
    }, skip: _sautWeb);

    testWidgets(
      '« Rappel des soins planifiés » : libellé, aide et bouton du Blade',
      (tester) async {
        final (page, _) = _pageEtModale(_section('prophylaxie'));
        final bloc = page.substring(page.indexOf('saveRappelSoins'));
        await afficher(tester);
        await onglet(tester, 'Calendriers de Prophylaxie');

        final libelle = _tous(bloc, r'<label[^>]*>([^<]*)</label>').first;
        expect(find.text(libelle.toUpperCase()), findsOneWidget);
        expect(
          find.text(
            _tous(bloc, r'<p class="text-xs text-outline">([^<]+)</p>').first,
          ),
          findsOneWidget,
        );
        final bouton = _tous(
          bloc,
          r'<button type="submit"[^>]*>([^<]+)</button>',
        ).first;
        expect(
          find.descendant(
            of: find.byKey(const Key('rappel-soins-enregistrer')),
            matching: find.text(bouton),
          ),
          findsOneWidget,
        );
        // `min="0" max="30"` du champ = `min:0|max:30` du composant.
        expect(bloc, contains('min="0" max="30"'));
        expect(_livewire, contains("'min:0', 'max:30'"));
        await nettoyer(tester);
      },
      skip: _sautWeb,
    );

    testWidgets(
      'numérotation : titre, libellés et groupes dans l ordre du Blade, bouton',
      (tester) async {
        final section = _section('numerotation');
        await afficher(tester);
        await onglet(tester, 'Numérotation Bandes & Sujets');

        expect(
          find.text(_tous(section, r'</span>([^<]+)</h2>').single),
          findsOneWidget,
        );
        expect(
          find.text(
            _tous(
              section,
              r'<p class="text-xs text-outline mt-xs">(.*?)</p>',
            ).single,
          ),
          findsOneWidget,
        );
        final libelles = _tous(section, r'<label[^>]*>([^<]*)</label>');
        expect(libelles, hasLength(9));
        final ordonnees = [
          for (final l in libelles)
            tester.getTopLeft(find.text(l.toUpperCase())),
        ];
        for (var i = 1; i < ordonnees.length; i++) {
          final avant = ordonnees[i - 1];
          final apres = ordonnees[i];
          expect(
            apres.dy > avant.dy ||
                (apres.dy == avant.dy && apres.dx > avant.dx),
            isTrue,
            reason: '${libelles[i]} après ${libelles[i - 1]}',
          );
        }
        // Les clés des champs (`wire:model="numbering.…"`) sont celles du serveur, dans le même ordre.
        expect(
          RegExp(
            r'wire:model="numbering\.(\w+)"',
          ).allMatches(section).map((m) => m.group(1)).toList(),
          ParametresElevageRepository.longueursNumerotation.keys.toList(),
        );
        for (final g in _tous(
          section,
          r'tracking-wider[^>]*>\s*<span[^>]*>[^<]*</span>([^<]+)</p>',
        )) {
          expect(find.text(g.toUpperCase()), findsOneWidget, reason: g);
        }
        expect(
          find.text(_tous(section, r'save</span>([^<]+)</button>').single),
          findsOneWidget,
        );
        // `maxlength="4"` : les mêmes champs sont limités au poste.
        for (final m in RegExp(
          r'wire:model="numbering\.(\w+)" type="text" maxlength="4"',
        ).allMatches(section)) {
          await tester.enterText(
            find.byKey(Key('format-${m.group(1)}')),
            'ABCDE',
          );
          expect(find.text('ABCD'), findsOneWidget, reason: m.group(1));
          await tester.enterText(find.byKey(Key('format-${m.group(1)}')), '');
        }
        await nettoyer(tester);
      },
      skip: _sautWeb,
    );
  });

  group('H9b — modales et messages du Blade', () {
    testWidgets(
      'ration : titres, champs, exemples, options du Blade ; message du composant',
      (tester) async {
        final (_, modale) = _pageEtModale(_section('rationnement'));
        final (modifier, saisir) = _titresModale(modale);
        final options = [
          for (final m in RegExp(
            r'<option value="(\w+)">([^<]+)</option>',
          ).allMatches(modale))
            (m.group(1)!, m.group(2)!),
        ];
        expect(options, ParametresElevageRepository.especesRation);
        await afficher(tester);

        await tester.tap(find.byKey(const Key('ajouter-ration')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ModaleAgri>(find.byType(ModaleAgri)).titre,
          saisir,
        );
        modaleConforme(tester, modale);
        // `newRation()` : `$this->ration_species_code = 'aviculture';` — la première option.
        expect(find.text(options.first.$2), findsOneWidget);

        await tester.enterText(find.byKey(const Key('ration-stade')), 'Ponte');
        await tester.enterText(find.byKey(const Key('ration-grammes')), '110');
        await tester.tap(find.byKey(const Key('ration-enregistrer')));
        await tester.pumpAndSettle();
        expect(
          find.text(_messagesPhp().singleWhere((m) => m.startsWith('Ration'))),
          findsOneWidget,
        );
        ToastAgri.toutRetirer();
        await tester.pumpAndSettle();

        final id = (await db.select(db.feedRationStandards).getSingle()).id;
        await tester.tap(find.byKey(Key('modifier-ration-$id')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ModaleAgri>(find.byType(ModaleAgri)).titre,
          modifier,
        );
        await nettoyer(tester);
      },
      skip: _sautWeb,
    );

    testWidgets(
      'échéance : titres, champs, exemples du Blade ; message du composant',
      (tester) async {
        final (_, modale) = _pageEtModale(_section('prophylaxie'));
        final (modifier, saisir) = _titresModale(modale);
        await afficher(tester);
        await onglet(tester, 'Calendriers de Prophylaxie');

        await tester.tap(find.byKey(const Key('ajouter-echeance')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ModaleAgri>(find.byType(ModaleAgri)).titre,
          saisir,
        );
        modaleConforme(tester, modale);

        await tester.enterText(
          find.byKey(const Key('echeance-periode')),
          'J+14',
        );
        await tester.enterText(
          find.byKey(const Key('echeance-traitement')),
          'Vaccin',
        );
        await tester.enterText(
          find.byKey(const Key('echeance-produit')),
          'HB1',
        );
        await tester.enterText(
          find.byKey(const Key('echeance-dose')),
          '1 goutte',
        );
        await tester.tap(find.byKey(const Key('echeance-enregistrer')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            _messagesPhp().singleWhere((m) => m.startsWith('Échéance')),
          ),
          findsOneWidget,
        );
        ToastAgri.toutRetirer();
        await tester.pumpAndSettle();

        final id =
            (await db.select(db.prophylaxisScheduleStandards).getSingle()).id;
        await tester.tap(find.byKey(Key('modifier-echeance-$id')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ModaleAgri>(find.byType(ModaleAgri)).titre,
          modifier,
        );
        await nettoyer(tester);
      },
      skip: _sautWeb,
    );

    testWidgets(
      'type de provende : titres, champs, exemples, « -- Sélectionner -- » ; message du composant',
      (tester) async {
        final (_, modale) = _pageEtModale(_section('provende'));
        final (modifier, saisir) = _titresModale(modale);
        await afficher(tester);
        await onglet(tester, 'Types de Provende');

        await tester.tap(find.byKey(const Key('ajouter-provende')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ModaleAgri>(find.byType(ModaleAgri)).titre,
          saisir,
        );
        modaleConforme(tester, modale);
        expect(
          find.text(_tous(modale, r'<option value="">([^<]+)</option>').single),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('provende-nom')),
          'Aliment lapin',
        );
        await tester.tap(find.byKey(const Key('provende-espece')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cuniculture (Lapins)').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('provende-enregistrer')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            _messagesPhp().singleWhere((m) => m.startsWith('Type de provende')),
          ),
          findsOneWidget,
        );
        ToastAgri.toutRetirer();
        await tester.pumpAndSettle();

        final id = (await db.select(db.feedTypes).getSingle()).id;
        await tester.tap(find.byKey(Key('modifier-provende-$id')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ModaleAgri>(find.byType(ModaleAgri)).titre,
          modifier,
        );
        await nettoyer(tester);
      },
      skip: _sautWeb,
    );

    testWidgets(
      'suppression : confirmation du composant Blade, puis message d archivage',
      (tester) async {
        final c = _confirmation!;
        final titre = _tous(c, r'<h3[^>]*>([^<]+)</h3>').single;
        final debutMessage = _tous(
          c,
          r'<p class="text-xs text-outline mb-md">\s*([^<@]+?)\s*@if',
        ).single;
        final attention = _tous(c, r'<span>(Attention[^<]+)</span>').single;
        final boutons = _tous(
          c,
          r'<button type="button"[^>]*>([^<]+)</button>',
        );
        expect(boutons, ['Annuler', 'Oui, Supprimer définitivement']);
        await db
            .into(db.feedRationStandards)
            .insert(
              FeedRationStandardsCompanion.insert(
                id: 'aaaaaaaa-0000-4000-8000-000000000001',
                speciesCode: 'aviculture',
                stageLabel: 'Ponte',
                rationGPerDay: 110,
              ),
            );
        await afficher(tester);

        await tester.tap(
          find.byKey(
            const Key('supprimer-ration-aaaaaaaa-0000-4000-8000-000000000001'),
          ),
        );
        await tester.pumpAndSettle();
        final m = find.byType(ModaleConfirmation);
        expect(tester.widget<ModaleConfirmation>(m).titre, titre);
        expect(
          tester.widget<ModaleConfirmation>(m).message,
          '$debutMessage Ponte.',
        );
        expect(
          find.descendant(of: m, matching: find.text(attention)),
          findsOneWidget,
        );
        for (final b in boutons) {
          expect(
            find.descendant(of: m, matching: find.text(b)),
            findsOneWidget,
            reason: b,
          );
        }

        await tester.tap(find.text(boutons.last));
        await tester.pumpAndSettle();
        final archive = _messagesPhp()
            .where((x) => x.startsWith('Paramètre archivé'))
            .toSet()
            .single;
        expect(find.text(archive), findsOneWidget);
        expect(find.byKey(const Key('toast-avertissement')), findsOneWidget);
        await nettoyer(tester);
      },
      skip: _sautWeb,
    );

    testWidgets('numérotation et délai de rappel : messages du composant', (
      tester,
    ) async {
      await afficher(tester);
      await onglet(tester, 'Calendriers de Prophylaxie');
      await tester.enterText(find.byKey(const Key('rappel-soins')), '4');
      await tester.tap(find.byKey(const Key('rappel-soins-enregistrer')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          _messagesPhp().singleWhere((m) => m.startsWith('Délai de rappel')),
        ),
        findsOneWidget,
      );
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle();

      await onglet(tester, 'Numérotation Bandes & Sujets');
      for (final cle
          in ParametresElevageRepository.longueursNumerotation.keys) {
        await tester.enterText(find.byKey(Key('format-$cle')), 'X');
      }
      await tester.tap(find.byKey(const Key('numerotation-enregistrer')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          _messagesPhp().singleWhere(
            (m) => m.startsWith('Formats de numérotation'),
          ),
        ),
        findsOneWidget,
      );
      await nettoyer(tester);
    }, skip: _sautWeb);

    test('chaque message du composant web est porté par l écran', () {
      final ecran = File(
        'lib/features/elevage/parametres_elevage_screen.dart',
      ).readAsStringSync();
      for (final m in _messagesPhp().toSet()) {
        expect(ecran, contains("'$m'"), reason: m);
      }
    }, skip: _sautWeb);
  });

  group('H9b — contrat avec le serveur', () {
    test(
      'les clés envoyées sont exactement celles que valide RecordParametresElevageFromDeviceAction',
      () async {
        final serveur = _Serveur();
        final moteur = SyncEngine(
          database: db,
          client: Dio()..interceptors.add(serveur),
          deviceId: 'poste-test',
          connectivity: _Connectivite(),
        );
        await depot.enregistrerRation(
          espece: 'aviculture',
          stade: 'Ponte',
          grammes: 110,
        );
        await depot.enregistrerEcheance(
          espece: 'aviculture',
          periode: 'J+14',
          traitement: 'Vaccin',
          produit: 'HB1',
          dose: '1 goutte',
          remanence: 0,
        );
        await depot.enregistrerProvende(
          nom: 'Aliment',
          espece: (await depot.charger()).especesProvende.single,
          sacKg: 25,
          prixKg: 250,
        );
        await depot.enregistrerNumerotation({
          for (final c
              in ParametresElevageRepository.longueursNumerotation.keys)
            c: 'X',
        });
        await depot.enregistrerRappelSoins(3);

        await moteur.synchroniser();

        final envoi = serveur.envoi!;
        // `TABLES` de l'Action : les cinq clés d'envoi.
        final tables = RegExp(r"'(\w+)'")
            .allMatches(
              RegExp(
                r'public const TABLES = \[(.*?)\];',
                dotAll: true,
              ).firstMatch(_action!)!.group(1)!,
            )
            .map((m) => m.group(1)!)
            .toSet();
        expect(tables, {
          'feed_ration_standards',
          'prophylaxis_schedule_standards',
          'feed_types',
          'elevage_numbering',
          'company_settings',
        });
        for (final (cle, methode) in [
          ('feed_ration_standards', 'ration'),
          ('prophylaxis_schedule_standards', 'prophylaxie'),
          ('feed_types', 'provende'),
          ('elevage_numbering', 'numerotation'),
          ('company_settings', 'rappelSoins'),
        ]) {
          final envoyees = ((envoi[cle] as List).single as Map).keys.toSet();
          final validees = _clesValidees(methode);
          // ⚠️ `id` part TOUJOURS (il nomme la ligne dans un refus), même là où l'Action ne le valide pas.
          expect(envoyees, {...validees, 'id'}, reason: '$cle ↔ $methode()');
        }
        expect(
          _action,
          contains("'elevage_numbering' => \$this->numerotation(\$ligne)"),
        );
        expect(
          _action,
          contains("return '${ParametresElevageCles.numerotation}';"),
        );
        expect(
          _action,
          contains("return '${ParametresElevageCles.rappelSoins}';"),
        );
      },
      skip: _sautWeb,
    );

    test('le droit d écrire est celui du seeder web (manage-elevage)', () {
      final s = _seeder!;
      final roles = RegExp(r"\$roles = \[(.*?)\];").firstMatch(s)!.group(1)!;
      for (final role in RegExp(
        r"'(\w+)'",
      ).allMatches(roles).map((m) => m.group(1)!)) {
        if (role == 'admin') {
          expect(
            s,
            contains(
              "Role::findByName('admin')->givePermissionTo(Permission::all());",
            ),
          );
          expect(PermissionsPoste.peut('admin', 'manage-elevage'), isTrue);
          continue;
        }
        final bloc = RegExp(
          "Role::findByName\\('$role'\\)->givePermissionTo\\(\\[(.*?)\\]\\);",
          dotAll: true,
        ).firstMatch(s)!.group(1)!;
        final permissions = RegExp(
          r"'([\w-]+)'",
        ).allMatches(bloc).map((m) => m.group(1)!).toSet();
        expect(
          PermissionsPoste.permissionsDuRole[role],
          permissions,
          reason: role,
        );
      }
      expect(PermissionsPoste.peut('animalier', 'manage-elevage'), isTrue);
      expect(PermissionsPoste.peut('caissier', 'manage-elevage'), isFalse);
      expect(PermissionsPoste.peut('comptable', 'manage-elevage'), isFalse);
      expect(PermissionsPoste.peut('inconnu', 'manage-elevage'), isFalse);
    }, skip: _sautWeb);

    test('le composant web et le point d envoi exigent manage-elevage', () {
      // Les huit écritures du composant : rappel, ration ×2, échéance ×2, provende ×2, numérotation.
      expect(
        RegExp(r"authorize\('manage-elevage'\)").allMatches(_livewire!).length,
        8,
      );
      final controleur = _lireLaravel(
        'app/Http/Controllers/Api/SyncController.php',
      )!;
      final bloc = controleur.substring(
        controleur.indexOf('RecordParametresElevageFromDeviceAction::TABLES'),
      );
      expect(
        bloc.substring(0, bloc.indexOf('->execute(')),
        contains("can('manage-elevage')"),
      );
    }, skip: _sautWeb);
  });
}
