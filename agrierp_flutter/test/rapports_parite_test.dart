import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/rapports/rapports_exports_screen.dart';
import 'package:agrierp/features/rapports/rapports_repository.dart';
import 'package:agrierp/features/stocks/pmp_service.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket U12b — LES CINQ AUTRES ONGLETS DU HUB « RAPPORTS & EXPORTS » SUR LE BLADE.
///
/// 1. **Lu dans le Blade** (sans PHP) : colonnes de chaque tableau dans leur ordre, états vides, libellés des cartes,
///    présence d'une recherche (Dettes, Stocks) et son absence (Trésorerie, Créances) — et leur présence dans l'écran
///    du poste.
/// 2. **Parité exécutée** : Laravel REND les cinq composants (`Livewire::test`, base SQLite en mémoire) sur un jeu
///    tiré au hasard (graine fixe) et ÉCRIT leurs CSV (`exportReport('csv')`) ; le poste ([RapportsRepository.charger])
///    doit produire les MÊMES cellules, les MÊMES cartes et les MÊMES lignes de classeur, dans le même ordre : ventes
///    validées / annulées, à crédit, sur avance ou non, sans client ; achats à crédit ou non ; dépense archivée ;
///    écritures actives et inactives, comptes 531… et autres comptes de classe 5 ; créances et dettes soldées,
///    partielles, sans échéance, hors période, à échéance égale ; catégories inactives ou sans produit, stocks
///    négatifs, produits jamais achetés, seuils nuls ; recherches.
void main() {
  String vue(String nom) =>
      '$dossierLaravel/resources/views/livewire/rapports/$nom.blade.php';
  final ecran = File('lib/features/rapports/rapports_exports_screen.dart');
  final sautBlade = File(vue('tresorerie')).existsSync()
      ? null
      : 'SAUT : vues Blade absentes ($dossierLaravel)';

  String decoder(String html) => html
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Les `<th>` de chaque `<table>` du Blade, dans l'ordre.
  List<List<String>> tableauxBlade(String nom) {
    final source = File(vue(nom)).readAsStringSync();
    return [
      for (final t in RegExp(
        r'<table.*?</table>',
        dotAll: true,
      ).allMatches(source))
        [
          for (final m in RegExp(
            r'<th[^>]*>(.*?)</th>',
            dotAll: true,
          ).allMatches(t[0]!))
            decoder(m[1]!),
        ],
    ];
  }

  /// Colonnes déclarées par l'écran du poste pour le tableau de clé [cle].
  List<String> colonnesPoste(String cle) {
    final source = ecran.readAsStringSync();
    final debut = source.indexOf("cle: '$cle'");
    final liste = source.indexOf('colonnes: const [', debut);
    final fin = source.indexOf('],', liste);
    return [
      for (final m in RegExp(
        r"\('([^']*)', \d+\)",
      ).allMatches(source.substring(liste, fin)))
        m[1]!,
    ];
  }

  group('lu dans le Blade', () {
    test(
      'U12b — chaque tableau du poste a les colonnes du Blade, dans son ordre',
      () {
        for (final (nom, cles) in [
          ('recettes-depenses', ['tableau-recettes', 'tableau-depenses']),
          ('tresorerie', ['tableau-tresorerie']),
          ('creances', ['tableau-creances']),
          ('dettes', ['tableau-dettes']),
          ('stocks-synth', ['tableau-stocks']),
        ]) {
          final web = tableauxBlade(nom);
          expect(web, hasLength(cles.length), reason: nom);
          for (var i = 0; i < cles.length; i++) {
            expect(colonnesPoste(cles[i]), web[i], reason: '$nom ${cles[i]}');
          }
        }
        // Témoins écrits à la main.
        expect(tableauxBlade('tresorerie').single, [
          'Date',
          'Solde Caisse',
          'Solde Banque',
          'Solde Total',
          'Actions',
        ]);
        expect(tableauxBlade('recettes-depenses').first, [
          'Date',
          'Libellé',
          'Montant',
        ]);
      },
      skip: sautBlade,
    );

    test(
      'U12b — états vides, cartes, info-bulles et recherche : ceux du Blade',
      () {
        final e = ecran.readAsStringSync();
        for (final (nom, libelles) in [
          (
            'recettes-depenses',
            [
              'Total Recettes',
              'Total Dépenses',
              'Solde Net',
              'Aucune recette sur la période.',
              'Aucune dépense sur la période.',
            ],
          ),
          ('tresorerie', ['Aucun mouvement de trésorerie sur la période.']),
          ('creances', ['Aucune créance sur la période.']),
          ('dettes', ['Aucune dette sur la période.', 'Rechercher...']),
          ('stocks-synth', ['Aucune catégorie active.', 'Rechercher...']),
        ]) {
          final b = File(vue(nom)).readAsStringSync();
          for (final l in libelles) {
            expect(b, contains(l), reason: '$nom : $l');
            expect(e, contains("'$l'"), reason: 'poste : $l');
          }
        }
        // Les deux info-bulles de « Lecture seule ».
        expect(
          File(vue('tresorerie')).readAsStringSync(),
          contains(RapportsExportsScreen.bulleEcritures),
        );
        for (final nom in ['creances', 'dettes', 'stocks-synth']) {
          expect(
            File(vue(nom)).readAsStringSync(),
            contains(RapportsExportsScreen.bulleDonnees),
            reason: nom,
          );
        }
        // Recherche : Dettes et Stocks seulement, comme au web.
        for (final (nom, attendue) in [
          ('tresorerie', false),
          ('creances', false),
          ('dettes', true),
          ('stocks-synth', true),
        ]) {
          expect(
            File(vue(nom)).readAsStringSync().contains(
              'wire:model.live.debounce.300ms="search"',
            ),
            attendue,
            reason: nom,
          );
        }
        expect(e, contains("recherche: 'dettes'"));
        expect(e, contains("recherche: 'stocks'"));
        // Les mentions de la cellule « Valeur Stock ».
        final s = File(vue('stocks-synth')).readAsStringSync();
        expect(s, contains('produit(s) en stock négatif, retenus à zéro)'));
        expect(s, contains('produit(s) jamais achetés, non valorisés)'));
        expect(
          RapportsRepository.mentionNegatifs(2),
          '(2 produit(s) en stock négatif, retenus à zéro)',
        );
      },
      skip: sautBlade,
    );

    test(
      'U12b — le hub masque les exports sans export-rapports, comme le web',
      () {
        final hub = File(
          '$dossierLaravel/resources/views/livewire/rapports/rapports-exports-hub.blade.php',
        ).readAsStringSync();
        final debut = hub.indexOf("@can('export-rapports')");
        final fin = hub.indexOf('@endcan', debut);
        expect(debut, greaterThan(0));
        expect(hub.substring(debut, fin), contains('Exporter PDF'));
        expect(hub.substring(debut, fin), contains('Exporter Excel'));
        expect(ecran.readAsStringSync(), contains('if (widget.peutExporter)'));
      },
      skip: sautBlade,
    );
  });

  test(
    'parité exécutée U12b : cellules, cartes et classeurs des cinq onglets = ceux du web, dans le même ordre',
    () async {
      var graine = 4211;
      int hasard(int n) =>
          ((graine = (graine * 1103515245 + 12345) & 0x7fffffff) >> 16) % n;
      String identifiant() => [
        for (final n in [8, 4, 4, 4, 12])
          [for (var k = 0; k < n; k++) '0123456789abcdef'[hasard(16)]].join(),
      ].join('-');
      String deux(int n) => n.toString().padLeft(2, '0');
      String jour(int mois, int j) => '2026-${deux(mois)}-${deux(j)}';
      // Un jour de fin juin à début août : la période est juillet.
      String jourAuHasard() {
        final r = hasard(46);
        return r < 3
            ? jour(6, 28 + r)
            : (r < 34 ? jour(7, r - 2) : jour(8, r - 33));
      }

      double montant() => hasard(4) == 0
          ? (hasard(4000) * 500).toDouble()
          : hasard(50000000) / 100;

      final clients = [
        {'id': identifiant(), 'nom': 'Élodie AHOUNOU', 'actif': true},
        {'id': identifiant(), 'nom': 'Bar Le Palmier', 'actif': true},
        {'id': identifiant(), 'nom': 'Coopérative Agonlin', 'actif': true},
        {'id': identifiant(), 'nom': 'Client Archivé', 'actif': false},
      ];
      final fournisseurs = [
        {'id': identifiant(), 'nom': 'Provenderie du Plateau', 'actif': true},
        {
          'id': identifiant(),
          'nom': 'Pharmacie Vétérinaire Ézéchiel',
          'actif': true,
        },
        {'id': identifiant(), 'nom': 'Quincaillerie PROVENCE', 'actif': true},
        {'id': identifiant(), 'nom': 'Ancien Fournisseur', 'actif': false},
      ];

      final ventes = <Map<String, Object?>>[];
      final minutes = <String>{};
      for (var i = 0; i < 45; i++) {
        final j = jourAuHasard();
        final heure =
            '${deux(6 + hasard(14))}:${deux(hasard(60))}:${deux(hasard(60))}';
        if (!minutes.add('$j $heure')) continue;
        ventes.add({
          'id': identifiant(),
          'client': hasard(3) == 0 ? null : hasard(clients.length),
          'mode': [
            'especes',
            'mobile_money',
            'credit',
            'virement',
            'avance',
          ][hasard(5)],
          'statut': hasard(6) == 0 ? 'annulee' : 'validee',
          'total': montant(),
          // Une vente sans `sold_at` : sa date effective est `created_at` (le poste la reçoit dans `sold_at`).
          'sold_at': i == 7 ? null : '$j $heure',
          'created_at': '$j $heure',
        });
      }

      // Deux ventes de la MÊME seconde (validées, au comptant) : l'identifiant les départage, au web comme au poste.
      final jumelle = ventes.firstWhere(
        (v) => (v['sold_at'] as String?)?.startsWith('2026-07-1') ?? false,
      );
      jumelle
        ..['statut'] = 'validee'
        ..['mode'] = 'especes';
      ventes.add({...jumelle, 'id': identifiant(), 'total': montant()});

      final achats = <Map<String, Object?>>[
        for (var i = 0; i < 24; i++)
          {
            'id': identifiant(),
            'fournisseur': hasard(fournisseurs.length),
            'mode': [
              'especes',
              'credit',
              'mobile_money',
              'virement',
            ][hasard(4)],
            'total': montant(),
            // Peu de jours distincts : plusieurs achats le même jour, et le même jour qu'une dépense.
            'date': jour(7, 1 + hasard(6) * 5),
          },
      ];

      final depenses = <Map<String, Object?>>[
        for (var i = 0; i < 14; i++)
          {
            'id': identifiant(),
            'libelle': [
              'Carburant groupe',
              'Électricité SBEE',
              'Réparation, clôture',
              'Transport œufs',
            ][hasard(4)],
            'montant': montant(),
            'date': i == 0 ? jour(6, 30) : jour(7, 1 + hasard(6) * 5),
            // ⚠️ Une dépense ARCHIVÉE (montant réintégré, charge contre-passée) : le web l'écarte (ticket U12b) ; une
            // dépense du poste n'est jamais archivée au poste.
            'actif': i != 3,
          },
      ];

      final comptes = [
        {'id': identifiant(), 'code': '531', 'classe': 5},
        {'id': identifiant(), 'code': '5312', 'classe': 5},
        {'id': identifiant(), 'code': '521', 'classe': 5},
        {'id': identifiant(), 'code': '5212', 'classe': 5},
        // Classe 5 sans être 531… : côté « Banque » au web (`str_starts_with($code, '531')`).
        {'id': identifiant(), 'code': '532', 'classe': 5},
        {'id': identifiant(), 'code': '552', 'classe': 5},
        {'id': identifiant(), 'code': '701', 'classe': 7},
        {'id': identifiant(), 'code': '601', 'classe': 6},
        {'id': identifiant(), 'code': '411', 'classe': 4},
      ];
      final ecritures = <Map<String, Object?>>[];
      for (var i = 0; i < 36; i++) {
        final r = hasard(60);
        final date = r < 8
            ? jour(6, 10 + r)
            : (r < 52 ? jour(7, 1 + hasard(31)) : jour(8, 1 + hasard(9)));
        final lignes = <Map<String, Object?>>[];
        final n = 2 + hasard(2);
        for (var k = 0; k < n; k++) {
          final m = montant();
          lignes.add({
            'id': identifiant(),
            'compte': hasard(comptes.length),
            'debit': k.isEven ? m : 0.0,
            'credit': k.isOdd ? m : 0.0,
          });
        }
        ecritures.add({
          'id': identifiant(),
          'date': date,
          // ⚠️ Une écriture INACTIVE touchant la caisse en juillet : le web l'ignore, le serveur ne la sert pas.
          'active': i != 5,
          'lignes': lignes,
        });
      }
      ecritures[5]['date'] = jour(7, 14);
      (ecritures[5]['lignes'] as List)[0] = {
        'id': identifiant(),
        'compte': 0,
        'debit': 999999.0,
        'credit': 0.0,
      };

      String? echeance() {
        final r = hasard(10);
        if (r == 0) return null;
        if (r == 1) return jour(6, 20);
        if (r == 2) return jour(8, 12);
        return jour(7, 1 + hasard(4) * 9);
      }

      ({double montant, double regle}) creance() {
        final m = montant() + 1000;
        final r = hasard(4);
        return (
          montant: m,
          regle: r == 0
              ? m
              : (r == 1 ? 0.0 : (m / (2 + hasard(3))).floorToDouble()),
        );
      }

      final creances = <Map<String, Object?>>[
        for (var i = 0; i < 18; i++)
          () {
            final c = creance();
            return {
              'id': identifiant(),
              'client': hasard(clients.length),
              'montant': c.montant,
              'regle': c.regle,
              'echeance': echeance(),
            };
          }(),
      ];
      final dettes = <Map<String, Object?>>[
        for (var i = 0; i < 18; i++)
          () {
            final c = creance();
            return {
              'id': identifiant(),
              'fournisseur': hasard(fournisseurs.length),
              'montant': c.montant,
              'regle': c.regle,
              'echeance': echeance(),
            };
          }(),
      ];

      // ⚠️ Libellés dont l'ordre est le même sous la collation BINAIRE de SQLite (la base de ce test) et sous
      // `utf8mb4_unicode_ci` (MySQL, la production, que le poste suit : `comparerCommeLeServeur`) : une capitale ASCII
      // en tête. « aliments bétail » ou « Œufs » se rangeraient autrement d'une base à l'autre (vu au ticket U12b).
      final categories = [
        {'id': identifiant(), 'libelle': 'Aliments & Provendes', 'actif': true},
        {
          'id': identifiant(),
          'libelle': 'Produits vétérinaires',
          'actif': true,
        },
        {'id': identifiant(), 'libelle': 'Plateaux d’œufs', 'actif': true},
        // Sans produit actif : absente du rapport (et ne décale plus le zébrage, ticket U12b).
        {'id': identifiant(), 'libelle': 'Matériel', 'actif': true},
        {'id': identifiant(), 'libelle': 'Ancienne catégorie', 'actif': false},
        {
          'id': identifiant(),
          'libelle': 'Volaille, aliments bétail',
          'actif': true,
        },
      ];
      final produits = <Map<String, Object?>>[];
      for (var i = 0; i < 18; i++) {
        final cat = [0, 1, 2, 4, 5, 3][hasard(6)];
        produits.add({
          'id': identifiant(),
          'categorie': cat == 3 ? 0 : cat,
          'actif': hasard(6) != 0,
          'stock': [-4.5, 0.0, 12.0, 3.25, 150.0, -1.0, 40.5][hasard(7)],
          'seuil': [0.0, 5.0, 20.0, 3.25][hasard(4)],
        });
      }
      // Témoins : un produit actif en stock négatif (acheté), un produit actif jamais acheté (indice 2) mais en stock.
      produits[0]
        ..['actif'] = true
        ..['stock'] = -4.5;
      produits[2]
        ..['actif'] = true
        ..['stock'] = 12.0
        ..['categorie'] = 0;
      produits.add({
        'id': identifiant(),
        'categorie': 3,
        'actif': false,
        'stock': 10.0,
        'seuil': 0.0,
      });
      final lignesAchat = <Map<String, Object?>>[];
      for (var i = 0; i < produits.length; i++) {
        // Un produit sur trois n'a jamais été acheté (PMP nul).
        if (i % 3 == 2) continue;
        for (var k = 0; k < 1 + hasard(3); k++) {
          lignesAchat.add({
            'id': identifiant(),
            'achat': hasard(achats.length),
            'produit': i,
            'qte': (1 + hasard(40)) / (hasard(2) == 0 ? 1 : 4),
            'prix': (50 + hasard(20000)) / (hasard(3) == 0 ? 100 : 1),
          });
        }
      }

      final recherches = {
        'dettes': ['', 'PROVEN', 'plateau', '0', 'zzz'],
        'stocks': ['', 'ALIMENTS', 'vétérinaires', '0'],
      };

      Object? brutPhp;
      try {
        brutPhp = executerPhp('<?php\n$amorceApplication\n$_script', {
          'clients': clients,
          'fournisseurs': fournisseurs,
          'ventes': ventes,
          'achats': achats,
          'depenses': depenses,
          'comptes': comptes,
          'ecritures': ecritures,
          'creances': creances,
          'dettes': dettes,
          'categories': categories,
          'produits': produits,
          'lignesAchat': lignesAchat,
          'recherches': recherches,
        }, application: true);
      } on FormatException catch (e) {
        // Une exception Laravel s'écrit sur la sortie standard, pas en JSON : la montrer telle quelle.
        // ignore: avoid_print
        print('Sortie du PHP, illisible en JSON :\n${e.source}');
        rethrow;
      }
      final sortie = brutPhp as Map<String, dynamic>;

      // ── Le même jeu au poste, tel que le tirage le dépose ──────────────────
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      DateTime lire(String t) => DateTime.parse(t);
      final instant = DateTime(2026, 8, 1);

      for (final c in clients) {
        await db
            .into(db.customers)
            .insert(
              CustomersCompanion.insert(
                id: c['id']! as String,
                name: c['nom']! as String,
                isActive: Value(c['actif']! as bool),
              ),
            );
      }
      for (final f in fournisseurs) {
        // Le serveur ne sert que les fournisseurs ACTIFS ; une pièce porte le nom du sien.
        if (f['actif'] != true) continue;
        await db
            .into(db.suppliers)
            .insert(
              SuppliersCompanion.insert(
                id: f['id']! as String,
                name: f['nom']! as String,
              ),
            );
      }
      for (final v in ventes) {
        final client = v['client'] as int?;
        await db
            .into(db.sales)
            .insert(
              SalesCompanion.insert(
                id: v['id']! as String,
                deviceId: 'serveur',
                syncStatus: const Value(SyncStatus.synced),
                updatedAt: instant,
                customerId: Value(
                  client == null ? null : clients[client]['id'] as String,
                ),
                customerName: Value(
                  client == null ? null : clients[client]['nom'] as String,
                ),
                paymentMode: v['mode']! as String,
                total: v['total']! as double,
                status: Value(v['statut']! as String),
                soldAt: lire((v['sold_at'] ?? v['created_at'])! as String),
              ),
            );
      }
      for (final a in achats) {
        final f = fournisseurs[a['fournisseur']! as int];
        await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                id: a['id']! as String,
                deviceId: 'serveur',
                syncStatus: const Value(SyncStatus.synced),
                updatedAt: instant,
                supplierId: f['id']! as String,
                supplierName: Value(f['nom']! as String),
                paymentMode: a['mode']! as String,
                total: a['total']! as double,
                purchaseDate: lire(a['date']! as String),
              ),
            );
      }
      for (final e in depenses) {
        if (e['actif'] != true) continue;
        await db
            .into(db.expenses)
            .insert(
              ExpensesCompanion.insert(
                id: e['id']! as String,
                deviceId: 'poste',
                updatedAt: instant,
                expenseDate: lire(e['date']! as String),
                label: e['libelle']! as String,
                category: '628 - Autres charges',
                amount: e['montant']! as double,
                treasuryAccountId: 'caisse-0000000000000000000000000000',
              ),
            );
      }
      for (final c in comptes) {
        await db
            .into(db.chartOfAccounts)
            .insert(
              ChartOfAccountsCompanion.insert(
                id: c['id']! as String,
                code: c['code']! as String,
                label: 'Compte ${c['code']}',
                accountClass: Value(c['classe']! as int),
              ),
            );
      }
      for (final e in ecritures) {
        if (e['active'] != true) continue;
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: e['id']! as String,
                entryDate: lire(e['date']! as String),
              ),
            );
        for (final l in (e['lignes']! as List).cast<Map<String, Object?>>()) {
          await db
              .into(db.accountingEntryLines)
              .insert(
                AccountingEntryLinesCompanion.insert(
                  id: l['id']! as String,
                  entryId: e['id']! as String,
                  accountId: comptes[l['compte']! as int]['id']! as String,
                  debit: Value(l['debit']! as double),
                  credit: Value(l['credit']! as double),
                ),
              );
        }
      }
      for (final c in creances) {
        await db
            .into(db.receivables)
            .insert(
              ReceivablesCompanion.insert(
                id: c['id']! as String,
                customerId: clients[c['client']! as int]['id']! as String,
                amount: c['montant']! as double,
                amountPaid: Value(c['regle']! as double),
                dueDate: Value(
                  c['echeance'] == null ? null : lire(c['echeance']! as String),
                ),
              ),
            );
      }
      for (final d in dettes) {
        final f = fournisseurs[d['fournisseur']! as int];
        await db
            .into(db.payables)
            .insert(
              PayablesCompanion.insert(
                id: d['id']! as String,
                supplierId: f['id']! as String,
                supplierName: Value(f['nom']! as String),
                amount: d['montant']! as double,
                amountPaid: Value(d['regle']! as double),
                dueDate: Value(
                  d['echeance'] == null ? null : lire(d['echeance']! as String),
                ),
              ),
            );
      }
      for (final c in categories) {
        await db
            .into(db.productCategories)
            .insert(
              ProductCategoriesCompanion.insert(
                id: c['id']! as String,
                label: c['libelle']! as String,
                isActive: Value(c['actif']! as bool),
              ),
            );
      }
      for (var i = 0; i < produits.length; i++) {
        final p = produits[i];
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: p['id']! as String,
                sku: 'P$i',
                name: 'Produit $i',
                unit: 'u',
                pricingMode: 'fixe',
                categoryId: Value(
                  categories[p['categorie']! as int]['id']! as String,
                ),
                stockQty: Value(p['stock']! as double),
                alertThreshold: Value(p['seuil']! as double),
                isActive: Value(p['actif']! as bool),
              ),
            );
      }
      for (final l in lignesAchat) {
        await db
            .into(db.purchaseLines)
            .insert(
              PurchaseLinesCompanion.insert(
                id: l['id']! as String,
                purchaseId: achats[l['achat']! as int]['id']! as String,
                productId: produits[l['produit']! as int]['id']! as String,
                qty: (l['qte']! as num).toDouble(),
                unitPrice: (l['prix']! as num).toDouble(),
              ),
            );
      }

      final d = await RapportsRepository(
        database: db,
      ).charger(du: DateTime(2026, 7, 1), au: DateTime(2026, 7, 31));

      List<List<String>> lignes(Object? brut) => [
        for (final l in brut! as List) (l as List).cast<String>(),
      ];

      // Onglet 1 — cartes, tableaux, classeur.
      final rd = (sortie['rd'] as Map).cast<String, dynamic>();
      expect(
        [
          '${PmpService.francs(d.totalRecettes)} F',
          '${PmpService.francs(d.totalDepenses)} F',
          '${PmpService.francs(d.soldeNet)} F',
        ],
        (rd['kpis'] as List).cast<String>(),
        reason: 'cartes',
      );
      expect(
        [for (final r in d.recettes) RapportsRepository.celluleRecette(r)],
        lignes(rd['recettes']),
        reason: 'Recettes',
      );
      expect(
        [for (final m in d.depenses) RapportsRepository.celluleDepense(m)],
        lignes(rd['depenses']),
        reason: 'Dépenses',
      );
      expect(
        RapportsRepository.classeurRecettesDepenses(d),
        lignes(rd['csv']),
        reason: 'classeur Recettes et Dépenses',
      );

      // Onglet 2.
      final tr = (sortie['tresorerie'] as Map).cast<String, dynamic>();
      expect(
        [for (final s in d.tresorerie) RapportsRepository.celluleTresorerie(s)],
        lignes(tr['lignes']),
        reason: 'Trésorerie',
      );
      expect(
        RapportsRepository.classeurTresorerie(d),
        lignes(tr['csv']),
        reason: 'classeur Trésorerie',
      );

      // Onglet 3.
      final cr = (sortie['creances'] as Map).cast<String, dynamic>();
      expect(
        [for (final e in d.creances) RapportsRepository.celluleEcheance(e)],
        lignes(cr['lignes']),
        reason: 'Créances',
      );
      expect(
        RapportsRepository.classeurEcheances('Client', d.creances),
        lignes(cr['csv']),
        reason: 'classeur Créances',
      );

      // Onglet 4, avec et sans recherche.
      final dt = (sortie['dettes'] as Map).cast<String, dynamic>();
      for (final terme in recherches['dettes']!) {
        final web = (dt[terme] as Map).cast<String, dynamic>();
        final filtrees = RapportsRepository.filtrerDettes(d.dettes, terme);
        expect(
          [for (final e in filtrees) RapportsRepository.celluleEcheance(e)],
          lignes(web['lignes']),
          reason: 'Dettes « $terme »',
        );
        expect(
          RapportsRepository.classeurEcheances('Fournisseur', filtrees),
          lignes(web['csv']),
          reason: 'classeur Dettes « $terme »',
        );
      }

      // Onglet 6, avec et sans recherche.
      final st = (sortie['stocks'] as Map).cast<String, dynamic>();
      for (final terme in recherches['stocks']!) {
        final web = (st[terme] as Map).cast<String, dynamic>();
        final filtrees = RapportsRepository.filtrerStocks(d.stocks, terme);
        expect(
          [
            for (final l in filtrees)
              [
                l.categorie,
                RapportsRepository.texteValeurStock(l),
                '${l.sousSeuil}',
              ],
          ],
          lignes(web['lignes']),
          reason: 'Stocks « $terme »',
        );
        expect(
          RapportsRepository.classeurStocks(filtrees),
          lignes(web['csv']),
          reason: 'classeur Stocks « $terme »',
        );
      }

      // La grille couvre ce qu'elle prétend couvrir.
      expect(lignes(rd['recettes']).length, greaterThan(10));
      expect(
        lignes(rd['depenses']).where((l) => l[1].startsWith('Achat — ')),
        isNotEmpty,
      );
      expect(
        lignes(rd['depenses']).where((l) => !l[1].startsWith('Achat — ')),
        isNotEmpty,
      );
      expect(
        lignes(rd['recettes']).where((l) => l[1] == 'Vente — Client comptant'),
        isNotEmpty,
      );
      final jours = [for (final l in lignes(rd['depenses'])) l[0]];
      expect(
        jours.length - jours.toSet().length,
        greaterThan(3),
        reason: 'plusieurs sorties le même jour (ordre du second critère)',
      );
      expect(lignes(tr['lignes']).length, greaterThan(8));
      expect(
        lignes(
          tr['lignes'],
        ).where((l) => l[1].startsWith('-') || l[2].startsWith('-')),
        isNotEmpty,
        reason: 'un solde négatif',
      );
      expect(lignes(cr['lignes']).length, greaterThan(3));
      final echeances = [for (final l in lignes(cr['lignes'])) l[2]];
      expect(
        echeances.length - echeances.toSet().length,
        greaterThan(0),
        reason: 'deux créances de même échéance',
      );
      expect(
        lignes((dt['PROVEN'] as Map)['lignes']).length,
        allOf(
          greaterThan(0),
          lessThan(lignes((dt[''] as Map)['lignes']).length),
        ),
        reason: 'la recherche filtre',
      );
      expect(
        lignes((dt['0'] as Map)['lignes']),
        lignes((dt[''] as Map)['lignes']),
        reason: '« 0 » ne filtre pas (PHP)',
      );
      final valeurs = [for (final l in lignes((st[''] as Map)['lignes'])) l[1]];
      expect(valeurs.where((v) => v.contains('stock négatif')), isNotEmpty);
      expect(valeurs.where((v) => v.contains('jamais achetés')), isNotEmpty);
      expect(
        lignes((st[''] as Map)['lignes']).map((l) => l[0]),
        isNot(contains('Matériel')),
        reason: 'catégorie sans produit actif',
      );
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Crée le jeu dans Laravel (SQLite en mémoire, lignes écrites telles quelles — aucun effet métier), fait rendre les
/// cinq composants par leur vue, et écrire leur CSV par `exportReport('csv')` ; rend chaque cellule (texte, espaces
/// normalisés) et chaque ligne de CSV.
const _script = r'''
$e = json_decode(file_get_contents($argv[1]), true);
Carbon\Carbon::setTestNow('2026-08-25 14:30:00');
Illuminate\Support\Facades\Gate::before(fn ($utilisateur = null) => true);
$t = '2026-08-01 00:00:00';
foreach ($e['clients'] as $c) {
    app('db')->table('customers')->insert(['id' => $c['id'], 'name' => $c['nom'], 'is_active' => $c['actif'], 'created_at' => $t, 'updated_at' => $t]);
}
foreach ($e['fournisseurs'] as $f) {
    app('db')->table('suppliers')->insert(['id' => $f['id'], 'name' => $f['nom'], 'is_active' => $f['actif'], 'created_at' => $t, 'updated_at' => $t]);
}
foreach ($e['ventes'] as $v) {
    app('db')->table('sales')->insert([
        'id' => $v['id'], 'customer_id' => $v['client'] === null ? null : $e['clients'][$v['client']]['id'],
        'payment_mode' => $v['mode'], 'subtotal' => $v['total'], 'total' => $v['total'], 'status' => $v['statut'],
        'sold_at' => $v['sold_at'], 'created_at' => $v['created_at'], 'updated_at' => $t,
    ]);
}
foreach ($e['achats'] as $a) {
    app('db')->table('purchases')->insert([
        'id' => $a['id'], 'supplier_id' => $e['fournisseurs'][$a['fournisseur']]['id'], 'payment_mode' => $a['mode'],
        'total' => $a['total'], 'purchase_date' => $a['date'], 'created_at' => $t, 'updated_at' => $t,
    ]);
}
$caisse = (string) Illuminate\Support\Str::uuid();
app('db')->table('treasury_accounts')->insert(['id' => $caisse, 'type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'created_at' => $t, 'updated_at' => $t]);
foreach ($e['depenses'] as $d) {
    app('db')->table('expenses')->insert([
        'id' => $d['id'], 'expense_date' => $d['date'], 'label' => $d['libelle'], 'category' => '628 - Autres charges',
        'amount' => $d['montant'], 'treasury_account_id' => $caisse, 'is_active' => $d['actif'], 'created_at' => $t, 'updated_at' => $t,
    ]);
}
$exercice = (string) Illuminate\Support\Str::uuid();
app('db')->table('fiscal_years')->insert(['id' => $exercice, 'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert', 'created_at' => $t, 'updated_at' => $t]);
foreach ($e['comptes'] as $c) {
    app('db')->table('chart_of_accounts')->insert(['id' => $c['id'], 'code' => $c['code'], 'label' => 'Compte '.$c['code'], 'class' => $c['classe'], 'created_at' => $t, 'updated_at' => $t]);
}
foreach ($e['ecritures'] as $x) {
    app('db')->table('accounting_entries')->insert(['id' => $x['id'], 'fiscal_year_id' => $exercice, 'entry_date' => $x['date'], 'is_active' => $x['active'], 'created_at' => $t, 'updated_at' => $t]);
    foreach ($x['lignes'] as $l) {
        app('db')->table('accounting_entry_lines')->insert([
            'id' => $l['id'], 'entry_id' => $x['id'], 'account_id' => $e['comptes'][$l['compte']]['id'],
            'debit' => $l['debit'], 'credit' => $l['credit'], 'created_at' => $t, 'updated_at' => $t,
        ]);
    }
}
foreach ($e['creances'] as $c) {
    app('db')->table('receivables')->insert([
        'id' => $c['id'], 'customer_id' => $e['clients'][$c['client']]['id'], 'amount' => $c['montant'],
        'amount_paid' => $c['regle'], 'due_date' => $c['echeance'], 'created_at' => $t, 'updated_at' => $t,
    ]);
}
foreach ($e['dettes'] as $d) {
    app('db')->table('payables')->insert([
        'id' => $d['id'], 'supplier_id' => $e['fournisseurs'][$d['fournisseur']]['id'], 'amount' => $d['montant'],
        'amount_paid' => $d['regle'], 'due_date' => $d['echeance'], 'created_at' => $t, 'updated_at' => $t,
    ]);
}
foreach ($e['categories'] as $c) {
    app('db')->table('product_categories')->insert(['id' => $c['id'], 'label' => $c['libelle'], 'is_active' => $c['actif'], 'created_at' => $t, 'updated_at' => $t]);
}
foreach ($e['produits'] as $i => $p) {
    app('db')->table('products')->insert([
        'id' => $p['id'], 'sku' => 'P'.$i, 'name' => 'Produit '.$i, 'category_id' => $e['categories'][$p['categorie']]['id'],
        'unit' => 'u', 'pricing_mode' => 'fourchette', 'stock_qty' => $p['stock'], 'alert_threshold' => $p['seuil'],
        'is_active' => $p['actif'], 'created_at' => $t, 'updated_at' => $t,
    ]);
}
foreach ($e['lignesAchat'] as $l) {
    app('db')->table('purchase_lines')->insert([
        'id' => $l['id'], 'purchase_id' => $e['achats'][$l['achat']]['id'], 'product_id' => $e['produits'][$l['produit']]['id'],
        'qty' => $l['qte'], 'unit_price' => $l['prix'], 'created_at' => $t, 'updated_at' => $t,
    ]);
}

/** Lignes de chaque `<table>` du rendu : cellules des `<tbody><tr>` qui ont [$colonnes] cellules. */
function tableaux(string $html, int $colonnes): array {
    $doc = new DOMDocument();
    @$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
    $sortie = [];
    foreach ($doc->getElementsByTagName('table') as $table) {
        $lignes = [];
        foreach ($table->getElementsByTagName('tbody') as $tbody) {
            foreach ($tbody->getElementsByTagName('tr') as $tr) {
                $c = [];
                foreach ($tr->getElementsByTagName('td') as $td) {
                    $c[] = trim(preg_replace('/\s+/u', ' ', $td->textContent));
                }
                if (count($c) === $colonnes) {
                    $lignes[] = array_slice($c, 0, $colonnes === 3 ? 3 : $colonnes - 1);
                }
            }
        }
        $sortie[] = $lignes;
    }
    return $sortie;
}
function cartes(string $html): array {
    $doc = new DOMDocument();
    @$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
    $x = new DOMXPath($doc);
    $valeurs = [];
    foreach ($x->query("//span[contains(@class, 'md:text-2xl')]") as $span) {
        $valeurs[] = trim(preg_replace('/\s+/u', ' ', $span->textContent));
    }
    return $valeurs;
}
/** Le CSV écrit par `exportReport('csv')`, ligne par ligne. */
function csv($composant, string $du, string $au): array {
    $reponse = $composant->exportReport('csv', $du, $au);
    ob_start();
    $reponse->sendContent();
    $texte = ob_get_clean();
    return array_map(fn ($l) => str_getcsv($l, ',', '"', ''), explode("\n", rtrim($texte, "\n")));
}
function instance(string $classe, array $proprietes = []) {
    $c = new $classe();
    $c->mount('2026-07-01', '2026-07-31');
    foreach ($proprietes as $k => $v) {
        $c->$k = $v;
    }
    return $c;
}
$du = '2026-07-01';
$au = '2026-07-31';
$params = ['startDate' => $du, 'endDate' => $au];
$sortie = [];

$html = Livewire\Livewire::test(App\Livewire\Rapports\RecettesDepenses::class, $params)->html();
$t = tableaux($html, 3);
$sortie['rd'] = ['kpis' => cartes($html), 'recettes' => $t[0], 'depenses' => $t[1], 'csv' => csv(instance(App\Livewire\Rapports\RecettesDepenses::class), $du, $au)];

$html = Livewire\Livewire::test(App\Livewire\Rapports\Tresorerie::class, $params)->html();
$sortie['tresorerie'] = ['lignes' => tableaux($html, 5)[0], 'csv' => csv(instance(App\Livewire\Rapports\Tresorerie::class), $du, $au)];

$html = Livewire\Livewire::test(App\Livewire\Rapports\Creances::class, $params)->html();
$sortie['creances'] = ['lignes' => tableaux($html, 4)[0], 'csv' => csv(instance(App\Livewire\Rapports\Creances::class), $du, $au)];

foreach ($e['recherches']['dettes'] as $terme) {
    $html = Livewire\Livewire::test(App\Livewire\Rapports\Dettes::class, $params)->set('search', $terme)->html();
    $sortie['dettes'][$terme] = ['lignes' => tableaux($html, 4)[0], 'csv' => csv(instance(App\Livewire\Rapports\Dettes::class, ['search' => $terme]), $du, $au)];
}
foreach ($e['recherches']['stocks'] as $terme) {
    $html = Livewire\Livewire::test(App\Livewire\Rapports\StocksSynth::class, $params)->set('search', $terme)->html();
    $sortie['stocks'][$terme] = ['lignes' => tableaux($html, 4)[0], 'csv' => csv(instance(App\Livewire\Rapports\StocksSynth::class, ['search' => $terme]), $du, $au)];
}
echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
''';
