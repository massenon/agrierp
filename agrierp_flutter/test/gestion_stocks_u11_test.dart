import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/stocks/gestion_stocks_screen.dart';
import 'package:agrierp/features/stocks/pmp_service.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket U11 — GESTION DES STOCKS, ONGLET « AJUSTEMENT / CORRECTION » : LES RÈGLES ET LES RETOURS DU WEB.
///
/// Le poste exigeait un motif (le web non), présélectionnait le premier produit (le web : « -- Sélectionner -- »),
/// répondait par une `SnackBar` à lui (le web : trois toasts selon le sens et la valorisation de l'écart, un
/// avertissement pour un écart nul), affichait son aide à lui et nommait son PDF comme un classeur. Ici :
///   1. **Lu dans le Blade / le composant** : règles validées, messages, option vide, groupes de motifs, texte
///      d'aide, en-têtes du journal, noms des PDF de toutes les éditions du poste face à ceux du web.
///   2. **Parité exécutée** : le VRAI `GestionStocks::validateAdjustment()` sur dix cas (erreurs de validation, écart
///      nul, excédent, pertes chiffrées ou non, comptes absents) ; le poste rend les mêmes messages.
///   3. **Écran** : présélection, erreurs sous les champs, toasts, remise à vide, rien d'écrit sur un refus.
void main() {
  final composant = File('$dossierLaravel/app/Livewire/Stocks/GestionStocks.php');
  final blade = File(
    '$dossierLaravel/resources/views/livewire/stocks/gestion-stocks.blade.php',
  );
  final ecran = File('lib/features/stocks/gestion_stocks_screen.dart');
  final depotSource = File('lib/features/stocks/stocks_repository.dart');
  final sautSansWeb = blade.existsSync() && composant.existsSync()
      ? null
      : 'SAUT : dépôt Laravel absent ($dossierLaravel)';

  /// Bloc `@if($tab === 'ajustements')` du Blade.
  String blocAjustement() {
    final b = blade.readAsStringSync();
    final debut = b.indexOf("@if(\$tab === 'ajustements')");
    return b.substring(debut, b.indexOf('@endif', b.indexOf('</button>', debut)));
  }

  String texte(String html) => html
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  group('lu dans le Blade et le composant', () {
    test(
      'U11 — le web ne valide que le produit et le stock physique : le motif est facultatif des deux côtés',
      () {
        final c = composant.readAsStringSync();
        final debut = c.indexOf('public function validateAdjustment()');
        final regles = c.substring(debut, c.indexOf(']);', debut));
        final cles = {
          for (final m in RegExp(r"'(\w+)' => \[").allMatches(regles)) m[1]!,
        };
        expect(cles, {'adjProductId', 'adjPhysical'});
        expect(regles, contains("'adjPhysical' => ['required', 'numeric', 'min:0']"));
        expect(
          StocksRepository.validerAjustement(productId: 'p', physique: '12'),
          isEmpty,
          reason: 'aucun motif exigé',
        );
        // Noms de champ du web (`lang/fr/validation.php`).
        final lang = File(
          '$dossierLaravel/lang/fr/validation.php',
        ).readAsStringSync();
        expect(lang, contains("'adjPhysical' => 'stock physique constaté'"));
        expect(lang, contains("'adjProductId' => 'produit'"));
      },
      skip: sautSansWeb,
    );

    test(
      'U11 — les messages du composant sont ceux du poste, mot pour mot',
      () {
        final c = composant.readAsStringSync();
        // Littéraux adjacents recollés (`'…' "…"` sur deux lignes).
        final d = depotSource.readAsStringSync().replaceAll(
          RegExp(r'''["']\s*\n\s*["']'''),
          '',
        );
        expect(c, contains("'Aucun écart détecté — rien à ajuster.'"));
        expect(d, contains("'Aucun écart détecté — rien à ajuster.'"));
        for (final morceau in [
          'Ajustement enregistré — écart positif de ',
          'Aucune écriture : un excédent signale une entrée non saisie, jamais un gain.',
          'Ajustement enregistré — perte de ',
          ' FCFA portée en charge exceptionnelle (débit 657 / crédit 601).',
          "Ajustement enregistré — ATTENTION : perte non comptabilisée (aucun coût d'achat connu pour ce produit, ou "
              'compte manquant). À régulariser au Journal Comptable.',
        ]) {
          expect(c.replaceAll('"', "'"), contains(morceau), reason: morceau);
          expect(d.replaceAll('"', "'"), contains(morceau), reason: morceau);
        }
      },
      skip: sautSansWeb,
    );

    test(
      'U11 — option vide, groupes de motifs, texte d aide et bouton : ceux du Blade',
      () {
        final bloc = blocAjustement();
        final e = ecran.readAsStringSync();
        expect(bloc, contains('<option value="">-- Sélectionner --</option>'));
        expect(e, contains("'-- Sélectionner --'"));
        expect(
          e,
          isNot(contains('donnees.lignes.first.produit.id')),
          reason: 'aucune présélection du premier produit',
        );

        // Les deux `<optgroup>` et leurs options, dans l'ordre.
        final groupes = [
          for (final m in RegExp(
            r'<optgroup label="([^"]+)">(.*?)</optgroup>',
            dotAll: true,
          ).allMatches(bloc))
            (
              m[1]!,
              [
                for (final o in RegExp(
                  r'<option>(.*?)</option>',
                ).allMatches(m[2]!))
                  o[1]!,
              ],
            ),
        ];
        expect(
          [
            for (final (libelle, options) in groupes) [libelle, ...options],
          ],
          [
            ['Écart négatif (perte)', ...StocksRepository.motifsPerte],
            ['Écart positif (surplus)', ...StocksRepository.motifsSurplus],
          ],
        );
        for (final (libelle, _) in groupes) {
          expect(e, contains("'$libelle'"), reason: libelle);
        }

        // Texte d'aide sous le bouton (dernier `<p class="text-[10px] text-outline">` du bloc).
        final aides = RegExp(
          r'<p class="text-\[10px\] text-outline">(.*?)</p>',
          dotAll: true,
        ).allMatches(bloc).toList();
        final aide = texte(aides.last[1]!);
        expect(aide, isNot(contains('pas encore active')));
        // Littéraux adjacents recollés (`"…" '…'` sur deux lignes).
        final ecranSansCoupure = e.replaceAll(
          RegExp(r'''["']\s*\n\s*["']'''),
          '',
        );
        expect(ecranSansCoupure, contains(aide));
        expect(bloc, contains("Valider l'ajustement"));
        expect(e, contains('"Valider l\'ajustement"'));
      },
      skip: sautSansWeb,
    );

    test(
      'U11 — en-têtes du Journal des Mouvements : ceux du Blade, accentués',
      () {
        final b = blade.readAsStringSync();
        final debut = b.indexOf("@if(\$tab === 'mouvements')");
        final bloc = b.substring(debut, b.indexOf('</thead>', debut));
        final web = [
          for (final m in RegExp(
            r'<th[^>]*>(.*?)</th>',
          ).allMatches(bloc))
            texte(m[1]!).toUpperCase(),
        ];
        expect(web, [
          'DATE / HEURE',
          'RÉFÉRENCE',
          'PRODUIT',
          'TYPE',
          'MOTIF',
          'QUANTITÉ',
          'VALEUR',
        ]);
        final e = ecran.readAsStringSync();
        for (final entete in web) {
          expect(e, contains("'$entete'"), reason: entete);
        }
      },
      skip: sautSansWeb,
    );

    /// 🔴→✅ Ticket U11 — le NOM DU PDF est celui du web, pour chaque édition du poste que le web édite aussi : lu
    /// dans le composant Livewire (`'stocks-'.now()->format('Y-m-d').'.pdf'`), comparé au modèle déclaré au poste.
    test(
      'U11 — chaque PDF du poste porte le nom que le web donne au même export',
      () {
        // (composant web, préfixe du web, source du poste, modèle du poste)
        const paires = [
          ('Stocks/GestionStocks.php', 'stocks-', 'lib/features/stocks/stocks_repository.dart', 'stocks-{jour}.pdf'),
          ('Rapports/RecettesDepenses.php', 'recettes-depenses-', 'lib/features/rapports/rapports_exports_screen.dart', 'recettes-depenses-{jour}.pdf'),
          ('Rapports/Tresorerie.php', 'tresorerie-', 'lib/features/rapports/rapports_exports_screen.dart', 'tresorerie-{jour}.pdf'),
          ('Rapports/Creances.php', 'creances-', 'lib/features/rapports/rapports_exports_screen.dart', 'creances-{jour}.pdf'),
          ('Rapports/Dettes.php', 'dettes-', 'lib/features/rapports/rapports_exports_screen.dart', 'dettes-{jour}.pdf'),
          ('Rapports/ElevageSynth.php', 'rapport-elevage-', 'lib/features/rapports/rapports_exports_screen.dart', 'rapport-elevage-{jour}.pdf'),
          ('Rapports/StocksSynth.php', 'rapport-stocks-', 'lib/features/rapports/rapports_exports_screen.dart', 'rapport-stocks-{jour}.pdf'),
          ('Comptabilite/PlanComptable.php', 'plan-comptable-', 'lib/features/comptabilite/documents_comptabilite.dart', 'plan-comptable-{jour}.pdf'),
          ('Comptabilite/JournalComptable.php', 'journal-comptable-', 'lib/features/comptabilite/documents_comptabilite.dart', 'journal-comptable-{jour}.pdf'),
          ('Comptabilite/BalanceGenerale.php', 'balance-generale-', 'lib/features/comptabilite/documents_comptabilite.dart', 'balance-generale-{jour}.pdf'),
          ('Achats/ListeAchats.php', 'achats-', 'lib/features/achats/achats_repository.dart', 'achats-{jour}.pdf'),
          ('Ventes/HistoriqueAvances.php', 'avances-', 'lib/features/clients/clients_creances_repository.dart', 'avances-{jour}.pdf'),
        ];
        for (final (php, prefixe, dart, modele) in paires) {
          final web = File('$dossierLaravel/app/Livewire/$php').readAsStringSync();
          expect(
            web,
            contains("'$prefixe'.now()->format('Y-m-d').'.pdf'"),
            reason: php,
          );
          expect(
            File(dart).readAsStringSync(),
            contains("fichier: '$modele'"),
            reason: dart,
          );
        }
        // Le Grand Livre : `'grand-livre-'.($account?->code ?? 'compte').'-'.now()->format('Y-m-d').'.pdf'`.
        expect(
          File('$dossierLaravel/app/Livewire/Comptabilite/GrandLivre.php').readAsStringSync(),
          contains("'grand-livre-'.(\$account?->code ?? 'compte').'-'.now()->format('Y-m-d').'.pdf'"),
        );
        expect(
          File('lib/features/comptabilite/documents_comptabilite.dart').readAsStringSync(),
          contains(r"fichier: 'grand-livre-${c?.code ?? 'compte'}-{jour}.pdf'"),
        );
        // La fiche Pondeuses : `'fiche-'.now()->format('Y-m').'.pdf'`.
        expect(
          File('$dossierLaravel/app/Livewire/Elevage/FichePondeuses.php').readAsStringSync(),
          contains("'fiche-'.now()->format('Y-m').'.pdf'"),
        );
      },
      skip: sautSansWeb,
    );
  });

  test('U11 — le nom du PDF : modèle daté, sinon le titre horodaté, toujours en .pdf', () {
    final quand = DateTime(2026, 10, 9, 7, 5);
    expect(
      DocumentOfficiel.nomPdf(
        StocksRepository.documentTableau(const [], quand),
        quand,
      ),
      'stocks-2026-10-09.pdf',
    );
    expect(
      DocumentOfficiel.nomPdf(
        const DocumentOfficiel(
          titre: 'Fiche',
          sousTitre: '',
          lignes: [],
          fichier: 'fiche-{mois}.pdf',
        ),
        quand,
      ),
      'fiche-2026-10.pdf',
    );
    // Un document que le web n'édite pas : le titre, horodaté à la minute — et une extension de PDF (le poste
    // proposait `….xlsx` pour TOUS ses PDF).
    expect(
      DocumentOfficiel.nomPdf(
        const DocumentOfficiel(
          titre: "Reçu d'Acompte",
          sousTitre: '',
          lignes: [],
        ),
        quand,
      ),
      'Reçu-d-Acompte-20261009-0705.pdf',
    );
  });

  test('U11 — les toasts de l ajustement, calculés à la main', () {
    expect(
      StocksRepository.messageAjustement(ecart: 7, pmp: 250, comptesDePerte: true),
      (
        message:
            'Ajustement enregistré — écart positif de 7. Aucune écriture : un excédent signale une entrée non '
            'saisie, jamais un gain.',
        avertissement: false,
      ),
    );
    // 5 × 6 500 = 32 500.
    expect(
      StocksRepository.messageAjustement(ecart: -5, pmp: 6500, comptesDePerte: true).message,
      'Ajustement enregistré — perte de 32 500 FCFA portée en charge exceptionnelle (débit 657 / crédit 601).',
    );
    // Sans PMP, ou sans les comptes 657 / 601 au plan du poste : la perte n'est pas comptabilisée.
    for (final (pmp, comptes) in [(null, true), (6500.0, false), (0.0, true)]) {
      final r = StocksRepository.messageAjustement(
        ecart: -5,
        pmp: pmp,
        comptesDePerte: comptes,
      );
      expect(r.message, contains('ATTENTION : perte non comptabilisée'), reason: '$pmp $comptes');
      expect(r.avertissement, isTrue);
    }
    // Plan comptable jamais tiré : les comptes du plan SYSCOHADA du serveur sont présumés (documenté).
    expect(
      StocksRepository.messageAjustement(ecart: -1, pmp: 10, comptesDePerte: null).message,
      contains('perte de 10 FCFA'),
    );
  });

  test(
    'parité exécutée U11 : validateAdjustment() du web et l onglet Ajustement du poste rendent les mêmes messages',
    () {
      // (stock théorique, stock physique saisi, lignes d'achat (qté, prix), comptes 657/601 présents)
      final cas = <Map<String, Object?>>[
        {'produit': false, 'stock': 40, 'physique': null, 'achats': <List<num>>[], 'comptes': true},
        {'produit': true, 'stock': 40, 'physique': -3, 'achats': <List<num>>[], 'comptes': true},
        {'produit': true, 'stock': 40, 'physique': 40, 'achats': <List<num>>[], 'comptes': true},
        {'produit': true, 'stock': 40, 'physique': 40.004, 'achats': <List<num>>[], 'comptes': true},
        {'produit': true, 'stock': 40, 'physique': 47, 'achats': <List<num>>[], 'comptes': true},
        {'produit': true, 'stock': 40, 'physique': 42.5, 'achats': <List<num>>[], 'comptes': true},
        {'produit': true, 'stock': 40, 'physique': 35, 'achats': [[40, 6500]], 'comptes': true},
        {'produit': true, 'stock': 10.5, 'physique': 7.25, 'achats': [[3, 1234.56], [7, 999.99]], 'comptes': true},
        {'produit': true, 'stock': 12, 'physique': 4, 'achats': <List<num>>[], 'comptes': true},
        {'produit': true, 'stock': 12, 'physique': 4, 'achats': [[5, 800]], 'comptes': false},
      ];

      final sortie =
          executerPhp('<?php\n$amorceApplication\n$_script', cas, application: true)
              as List;

      for (var i = 0; i < cas.length; i++) {
        final c = cas[i];
        final web = (sortie[i] as Map).cast<String, dynamic>();
        final physique = c['physique'] == null ? '' : '${c['physique']}';
        final erreurs = StocksRepository.validerAjustement(
          productId: c['produit'] == true ? 'p' : '',
          physique: physique,
        );
        expect(
          [erreurs['produit'], erreurs['physique']],
          [web['erreur_produit'], web['erreur_physique']],
          reason: 'cas $i — erreurs',
        );
        if (erreurs.isNotEmpty) {
          expect(web['toast'], isNull, reason: 'cas $i — rien d écrit');
          continue;
        }
        final ecart = StocksRepository.ecartCalcule(
          theorique: (c['stock']! as num).toDouble(),
          physique: double.parse(physique),
        );
        final lignes = [
          for (final l in c['achats']! as List)
            PurchaseLine(
              id: 'l',
              purchaseId: 'a',
              productId: 'p',
              qty: ((l as List)[0] as num).toDouble(),
              unitPrice: (l[1] as num).toDouble(),
            ),
        ];
        final attendu = ecart == 0
            ? (message: StocksRepository.messageEcartNul, avertissement: true)
            : StocksRepository.messageAjustement(
                ecart: ecart,
                pmp: PmpService.pmp('p', lignes),
                comptesDePerte: c['comptes'] == true,
              );
        expect(
          [attendu.message, attendu.avertissement ? 'warning' : 'success'],
          [web['toast'], web['type']],
          reason: 'cas $i',
        );
      }

      // La grille couvre ce qu'elle prétend couvrir : chaque branche du web.
      final toasts = [for (final s in sortie) (s as Map)['toast'] as String?];
      for (final morceau in [
        'rien à ajuster',
        'écart positif de 7.',
        'écart positif de 2.5.',
        'perte de 32 500 FCFA',
        'perte de 3 479 FCFA',
        'ATTENTION',
      ]) {
        expect(toasts.whereType<String>().where((t) => t.contains(morceau)), isNotEmpty, reason: morceau);
      }
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );

  group('écran', () {
    late AppDatabase db;
    late StocksRepository depot;
    const provende = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
    const oeufs = 'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb';

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      depot = StocksRepository(database: db, deviceId: 'poste-test');
      for (final (id, sku, nom, stock) in [
        (provende, 'ALI-001', 'Aliment ponte 25kg', 45.0),
        (oeufs, 'AVI-002', 'Œufs de table (plateau)', 8.0),
      ]) {
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: id,
                sku: sku,
                name: nom,
                unit: 'sac',
                pricingMode: 'fixe',
                stockQty: Value(stock),
              ),
            );
      }
      // PMP de la provende : 40 sacs à 6 500 F.
      await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: 'cccccccc-0000-4000-8000-cccccccccccc',
              deviceId: 'serveur',
              updatedAt: DateTime(2026, 10, 1),
              syncStatus: const Value(SyncStatus.synced),
              supplierId: 'dddddddd-0000-4000-8000-dddddddddddd',
              paymentMode: 'especes',
              total: 260000,
              purchaseDate: DateTime(2026, 10, 1),
            ),
          );
      await db
          .into(db.purchaseLines)
          .insert(
            PurchaseLinesCompanion.insert(
              id: 'eeeeeeee-0000-4000-8000-eeeeeeeeeeee',
              purchaseId: 'cccccccc-0000-4000-8000-cccccccccccc',
              productId: provende,
              qty: 40,
              unitPrice: 6500,
            ),
          );
      for (final (code, libelle) in [
        ('601', 'Achats de marchandises'),
        ('657', 'Charges exceptionnelles'),
      ]) {
        await db
            .into(db.chartOfAccounts)
            .insert(
              ChartOfAccountsCompanion.insert(
                id: 'ffffffff-0000-4000-8000-000000000$code',
                code: code,
                label: libelle,
              ),
            );
      }
    });

    tearDown(() async {
      ToastAgri.toutRetirer();
      await db.close();
    });

    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: GestionStocksScreen(depot: depot)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onglet-stocks-Ajustement / Correction')));
      await tester.pumpAndSettle();
    }

    Future<void> choisir(WidgetTester tester, String libelle) async {
      await tester.tap(find.byKey(const Key('adj-produit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(libelle).last);
      await tester.pumpAndSettle();
    }

    Future<void> valider(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('adj-valider')));
      await tester.pumpAndSettle();
    }

    String valeur(WidgetTester tester, String cle) => tester
        .widget<Text>(
          find.descendant(of: find.byKey(Key(cle)), matching: find.byType(Text)).first,
        )
        .data!;

    testWidgets('⚠️ U11 — l onglet s ouvre sur « -- Sélectionner -- », théorique « — », écart « 0 »', (
      tester,
    ) async {
      await afficher(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('adj-produit')),
          matching: find.text('-- Sélectionner --'),
        ),
        findsOneWidget,
      );
      expect(valeur(tester, 'adj-theorique'), '—');
      expect(tester.widget<Text>(find.byKey(const Key('adj-ecart'))).data, '0');
      expect(
        find.text(
          "Si l'écart est négatif, une écriture de charge exceptionnelle (compte 657) est générée automatiquement, "
          'valorisée au PMP.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('⚠️ U11 — sans produit ni stock physique : les deux erreurs du web, sous leur champ, rien d écrit', (
      tester,
    ) async {
      await afficher(tester);
      await valider(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('adj-erreur-produit'))).data,
        'Le champ produit est obligatoire.',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('adj-erreur-physique'))).data,
        'Le champ stock physique constaté est obligatoire.',
      );
      expect(await db.select(db.stockAdjustments).get(), isEmpty);
    });

    testWidgets('U11 — un stock physique négatif est refusé comme au web', (tester) async {
      await afficher(tester);
      await choisir(tester, 'Aliment ponte 25kg (Théorique : 45)');
      await tester.enterText(find.byKey(const Key('adj-physique')), '-2');
      await valider(tester);

      expect(find.byKey(const Key('adj-erreur-produit')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('adj-erreur-physique'))).data,
        'Le champ stock physique constaté doit être au moins égal à 0.',
      );
      expect(await db.select(db.stockAdjustments).get(), isEmpty);
    });

    testWidgets('⚠️ U11 — un écart nul : avertissement du web, rien d écrit, le formulaire reste', (
      tester,
    ) async {
      await afficher(tester);
      await choisir(tester, 'Aliment ponte 25kg (Théorique : 45)');
      await tester.enterText(find.byKey(const Key('adj-physique')), '45');
      await valider(tester);

      expect(find.text('Aucun écart détecté — rien à ajuster.'), findsOneWidget);
      expect(await db.select(db.stockAdjustments).get(), isEmpty);
      expect(valeur(tester, 'adj-theorique'), '45');
      // Le toast se retire seul après 3,5 s, comme au web.
      await tester.pump(ToastAgri.duree);
    });

    testWidgets('⚠️ U11 — une perte : le toast du web chiffré au PMP, puis le formulaire remis à vide', (
      tester,
    ) async {
      await afficher(tester);
      await choisir(tester, 'Aliment ponte 25kg (Théorique : 45)');
      await tester.enterText(find.byKey(const Key('adj-physique')), '40');
      await tester.pumpAndSettle();
      await valider(tester);

      // 5 sacs × 6 500 F = 32 500 F.
      expect(
        find.text(
          'Ajustement enregistré — perte de 32 500 FCFA portée en charge exceptionnelle (débit 657 / crédit 601).',
        ),
        findsOneWidget,
      );
      final ecrit = await db.select(db.stockAdjustments).getSingle();
      expect([ecrit.type, ecrit.quantity], ['sortie', 5]);
      // `reset(['adjProductId', 'adjPhysical', 'adjReason'])`.
      expect(
        find.descendant(
          of: find.byKey(const Key('adj-produit')),
          matching: find.text('-- Sélectionner --'),
        ),
        findsOneWidget,
      );
      expect(valeur(tester, 'adj-theorique'), '—');
      expect(
        tester.widget<TextField>(find.byKey(const Key('adj-physique'))).controller!.text,
        '',
      );
      // Le toast se retire seul après 3,5 s, comme au web.
      await tester.pump(ToastAgri.duree);
    });

    testWidgets('U11 — un excédent : le toast de succès du web', (tester) async {
      await afficher(tester);
      await choisir(tester, 'Aliment ponte 25kg (Théorique : 45)');
      await tester.enterText(find.byKey(const Key('adj-physique')), '52');
      await valider(tester);

      expect(
        find.text(
          'Ajustement enregistré — écart positif de 7. Aucune écriture : un excédent signale une entrée non '
          'saisie, jamais un gain.',
        ),
        findsOneWidget,
      );
      // Le toast se retire seul après 3,5 s, comme au web.
      await tester.pump(ToastAgri.duree);
    });

    testWidgets('U11 — une perte sans coût d achat connu : l avertissement du web', (tester) async {
      await afficher(tester);
      await choisir(tester, 'Œufs de table (plateau) (Théorique : 8)');
      await tester.enterText(find.byKey(const Key('adj-physique')), '6');
      await valider(tester);

      expect(
        find.textContaining('ATTENTION : perte non comptabilisée'),
        findsOneWidget,
      );
      // Le toast se retire seul après 3,5 s, comme au web.
      await tester.pump(ToastAgri.duree);
    });

    testWidgets('U11 — les motifs se présentent dans les deux groupes du Blade', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('adj-motif')));
      await tester.pumpAndSettle();

      final perte = tester.getTopLeft(find.text('Écart négatif (perte)').last).dy;
      final surplus = tester.getTopLeft(find.text('Écart positif (surplus)').last).dy;
      expect(perte, lessThan(tester.getTopLeft(find.text('Casse de matériel').last).dy));
      expect(
        tester.getTopLeft(find.text('Péremption dépassée').last).dy,
        lessThan(surplus),
      );
      expect(surplus, lessThan(tester.getTopLeft(find.text('Naissance non répertoriée').last).dy));
    });
  });
}

/// Rejoue chaque cas dans le VRAI composant (`GestionStocks::validateAdjustment()`), base SQLite en mémoire : un
/// produit par cas, ses lignes d'achat, exercice ouvert, comptes 601 / 657 (retirés pour les cas qui le disent).
/// Rend la première erreur de chaque champ et le dernier toast (message, type).
const _script = r'''
$cas = json_decode(file_get_contents($argv[1]), true);
Carbon\Carbon::setTestNow('2026-10-19 10:00:00');
foreach (['view-stocks', 'manage-stocks'] as $nom) {
    App\Models\Permission::findOrCreate($nom, 'web');
}
$role = App\Models\Role::findOrCreate('admin', 'web');
$role->givePermissionTo(['view-stocks', 'manage-stocks']);
$admin = App\Models\User::create(['name' => 'DG', 'email' => 'dg@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
$admin->assignRole($role);
App\Models\FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
$categorie = App\Models\ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
$fournisseur = App\Models\Supplier::create(['name' => 'Provenderie', 'phone' => '+22997000000', 'is_active' => true]);
$sortie = [];
// Les cas SANS comptes d'abord : un compte qui porte déjà des écritures ne se supprime pas (clé étrangère).
$ordre = array_keys($cas);
usort($ordre, fn ($a, $b) => [$cas[$a]['comptes'], $a] <=> [$cas[$b]['comptes'], $b]);
$comptesCrees = false;
foreach ($ordre as $i) {
    $c = $cas[$i];
    if ($c['comptes'] && ! $comptesCrees) {
        foreach ([['601', 'Achats de marchandises'], ['657', 'Charges exceptionnelles']] as [$code, $libelle]) {
            App\Models\ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => 6, 'is_active' => true]);
        }
        $comptesCrees = true;
    }
    $produit = App\Models\Product::create([
        'sku' => 'P'.$i, 'name' => 'Produit '.$i, 'category_id' => $categorie->id, 'unit' => 'sac',
        'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 100000, 'tva_rate' => 0,
        'stock_qty' => $c['stock'], 'is_active' => true,
    ]);
    foreach ($c['achats'] as [$qte, $prix]) {
        $achat = App\Models\Purchase::create(['supplier_id' => $fournisseur->id, 'payment_mode' => 'especes', 'total' => $qte * $prix, 'purchase_date' => '2026-10-01']);
        App\Models\PurchaseLine::create(['purchase_id' => $achat->id, 'product_id' => $produit->id, 'qty' => $qte, 'unit_price' => $prix]);
    }
    $composant = Livewire\Livewire::actingAs($admin)->test(App\Livewire\Stocks\GestionStocks::class)
        ->set('tab', 'ajustements');
    if ($c['produit']) {
        $composant->set('adjProductId', $produit->id);
    }
    if ($c['physique'] !== null) {
        $composant->set('adjPhysical', $c['physique']);
    }
    $composant->call('validateAdjustment');
    $erreurs = $composant->errors();
    $toast = collect($composant->effects['dispatches'] ?? [])->where('name', 'toast')->last();
    $sortie[$i] = [
        'erreur_produit' => $erreurs->first('adjProductId') ?: null,
        'erreur_physique' => $erreurs->first('adjPhysical') ?: null,
        'toast' => $toast['params']['message'] ?? null,
        'type' => $toast['params']['type'] ?? null,
    ];
}
ksort($sortie);
echo json_encode(array_values($sortie), JSON_UNESCAPED_UNICODE);
''';
