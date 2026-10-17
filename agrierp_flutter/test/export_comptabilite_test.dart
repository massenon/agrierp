import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:agrierp/features/comptabilite/documents_comptabilite.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chemins_depot.dart';

/// Ticket F0.87 (item 9, T4) — « Exporter PDF » des quatre pages comptables du poste
/// (`plan-comptable.html`, `journal-comptable.html`, `grand-livre.html`, `balance-generale.html`).
///
/// ⚠️⚠️ **TITRES, SOUS-TITRES ET COLONNES SONT CEUX DU WEB DEPUIS F0.88** (arbitrage client du
/// 13/10/2026 ; `resources/views/exports/*.blade.php` et composants Livewire relus par un test). Les
/// fonctions d'export de la MAQUETTE (`exportPlanComptablePDF`…) restent relues par un second test
/// qui énumère chaque écart. ⚠️⚠️ **LES CHIFFRES EXPORTÉS SONT CEUX DE L'ÉCRAN** : un test compare
/// chaque cellule du document à la cellule affichée ; un autre les compare à des valeurs CALCULÉES À
/// LA MAIN (détail en commentaire), jamais obtenues en appelant le code testé.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ComptabiliteRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  /// Horloge du poste : 20 mars 2026. Grand Livre par défaut : 01/03/2026 → 20/03/2026 ;
  /// Balance par défaut : mars 2026 entier.
  final maintenantFixe = DateTime(2026, 3, 20, 10, 30);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ComptabiliteRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> compte(String code, String libelle, int? classe) => db
      .into(db.chartOfAccounts)
      .insert(
        ChartOfAccountsCompanion.insert(
          id: uuid('c$code'),
          code: code,
          label: libelle,
          accountClass: Value(classe),
        ),
      );

  Future<void> ligne(
    String cle,
    String cleEcriture,
    String code, {
    double debit = 0,
    double credit = 0,
  }) => db
      .into(db.accountingEntryLines)
      .insert(
        AccountingEntryLinesCompanion.insert(
          id: uuid(cle),
          entryId: uuid(cleEcriture),
          accountId: uuid('c$code'),
          debit: Value(debit),
          credit: Value(credit),
        ),
      );

  Future<void> entete(
    String cle,
    DateTime date,
    String reference, {
    String source = 'manual',
  }) => db
      .into(db.accountingEntries)
      .insert(
        AccountingEntriesCompanion.insert(
          id: uuid(cle),
          entryDate: date,
          reference: Value(reference),
          sourceType: Value(source),
        ),
      );

  /// Écriture à deux lignes, équilibrée.
  Future<void> ecriture(
    String cle,
    DateTime date,
    String reference,
    String debit,
    String credit,
    double montant, {
    String source = 'manual',
  }) async {
    await entete(cle, date, reference, source: source);
    await ligne('${cle}d', cle, debit, debit: montant);
    await ligne('${cle}c', cle, credit, credit: montant);
  }

  /// Le jeu, ÉCRIT À LA MAIN, inséré dans le désordre.
  ///
  /// | clé | date       | débit | crédit | montant  | référence                                  |
  /// | E1  | 2026-01-10 | 531   | 101    | 100 000  | OD-2026-0001 — Apport du capital           |
  /// | E2  | 2026-02-15 | 601   | 401    |  40 000  | OD-2026-0002 — Achat provende              |
  /// | E3  | 2026-03-02 | 531   | 701    |  25 000  | OD-2026-0003 — Vente comptant              |
  /// | E4  | 2026-03-05 | 401   | 531    |  15 000  | OD-2026-0004 — Règlement fournisseur       |
  /// | E8  | 2026-03-10 | 531   | 701    |     500  | VTE-0042 (sans « — » : pas de libellé)     |
  /// | E5  | 2026-03-18 | 531   | 701    | 1 234,60 | OD-2026-0005 — Vente d’œufs                |
  /// | E6  | 2026-03-25 | 531   | 701    |   3 000  | OD-2026-0006 — Vente fin de mois           |
  /// | E7  | 2026-04-02 | 601   | 531    |     600  | OD-2026-0007 — Avril                       |
  Future<void> jeu() async {
    await compte('531', 'Caisse', 5);
    await compte('101', 'Capital', 1);
    await compte('701', 'Ventes', 7);
    await compte('601', 'Achats', 6);
    await compte('401', 'Fournisseurs', 4);
    await compte('47', 'Compte d’attente', null);
    await db
        .into(db.fiscalYears)
        .insert(
          FiscalYearsCompanion.insert(
            id: uuid('ex2026'),
            year: 2026,
            startDate: Value(DateTime(2026, 1, 1)),
            endDate: Value(DateTime(2026, 12, 31)),
            status: const Value('ouvert'),
          ),
        );

    await ecriture(
      'e6',
      DateTime(2026, 3, 25),
      'OD-2026-0006 — Vente fin de mois',
      '531',
      '701',
      3000,
    );
    await ecriture(
      'e1',
      DateTime(2026, 1, 10),
      'OD-2026-0001 — Apport du capital',
      '531',
      '101',
      100000,
    );
    await ecriture(
      'e5',
      DateTime(2026, 3, 18),
      'OD-2026-0005 — Vente d’œufs',
      '531',
      '701',
      1234.60,
    );
    await ecriture(
      'e8',
      DateTime(2026, 3, 10),
      'VTE-0042',
      '531',
      '701',
      500,
      source: 'sale',
    );
    await ecriture(
      'e3',
      DateTime(2026, 3, 2),
      'OD-2026-0003 — Vente comptant',
      '531',
      '701',
      25000,
      source: 'sale',
    );
    await ecriture(
      'e7',
      DateTime(2026, 4, 2),
      'OD-2026-0007 — Avril',
      '601',
      '531',
      600,
    );
    await ecriture(
      'e2',
      DateTime(2026, 2, 15),
      'OD-2026-0002 — Achat provende',
      '601',
      '401',
      40000,
      source: 'purchase',
    );
    await ecriture(
      'e4',
      DateTime(2026, 3, 5),
      'OD-2026-0004 — Règlement fournisseur',
      '401',
      '531',
      15000,
    );
  }

  /// Écriture INCOMPLÈTE (une seule ligne reçue) : 531 débité de 700 le 19/03/2026.
  Future<void> ecritureIncomplete() async {
    await entete('e9', DateTime(2026, 3, 19), 'OD-2026-0009 — Ligne manquante');
    await ligne('e9d', 'e9', '531', debit: 700);
  }

  /// SECONDE écriture incomplète (F0.87-bis) : 601 débité de 250 le 12/03/2026, seule ligne reçue.
  Future<void> secondeEcritureIncomplete() async {
    await entete(
      'e11',
      DateTime(2026, 3, 12),
      'OD-2026-0011 — Seconde ligne manquante',
    );
    await ligne('e11d', 'e11', '601', debit: 250);
  }

  /// Jeu « CENTIMES » (F0.87-bis), ÉCRIT À LA MAIN : trois écritures de 0,40 F, montant dans
  /// ]0 ; 0,5[. `number_format(0.4, 0)` du serveur écrit « 0 » et la vue teste `> 0` : la cellule
  /// est « 0 », JAMAIS « — » (un « — » dirait « aucun mouvement » alors qu'il y en a un).
  ///
  /// | clé | date       | débit | crédit | montant | référence                           |
  /// | E20 | 2026-02-15 | 531   | 701    | 0,40    | OD-2026-0020 — Centimes reçus       |
  /// | E21 | 2026-03-06 | 701   | 531    | 0,40    | OD-2026-0021 — Centimes rendus      |
  /// | E22 | 2026-03-10 | 531   | 701    | 0,40    | OD-2026-0022 — Centimes encaissés   |
  Future<void> jeuCentimes() async {
    await compte('531', 'Caisse', 5);
    await compte('701', 'Ventes', 7);
    await db
        .into(db.fiscalYears)
        .insert(
          FiscalYearsCompanion.insert(
            id: uuid('ex2026'),
            year: 2026,
            startDate: Value(DateTime(2026, 1, 1)),
            endDate: Value(DateTime(2026, 12, 31)),
            status: const Value('ouvert'),
          ),
        );
    await ecriture(
      'e22',
      DateTime(2026, 3, 10),
      'OD-2026-0022 — Centimes encaissés',
      '531',
      '701',
      0.4,
    );
    await ecriture(
      'e20',
      DateTime(2026, 2, 15),
      'OD-2026-0020 — Centimes reçus',
      '531',
      '701',
      0.4,
    );
    await ecriture(
      'e21',
      DateTime(2026, 3, 6),
      'OD-2026-0021 — Centimes rendus',
      '701',
      '531',
      0.4,
    );
  }

  /// Cellules des lignes de données d'un document.
  List<List<String>> donnees(DocumentOfficiel d) => [
    for (final l in d.lignes.whereType<DonneesDocument>()) l.cellules,
  ];

  List<List<String>> totaux(DocumentOfficiel d) => [
    for (final l in d.lignes.whereType<TotalDocument>()) l.cellules,
  ];

  /// Glyphes manquants dessinés en carré barré (même lecture que F0.75 / F0.82).
  int glyphesManquants(List<int> pdf) {
    final brut = latin1.decode(pdf);
    final signature = RegExp(
      r'0 0 m [\d.]+ [\d.]+ l 0 [\d.]+ m [\d.]+ 0 l 0 0 [\d.]+ [\d.]+ re',
    );
    var total = 0;
    for (final debut in RegExp(r'(?<!end)stream\r?\n').allMatches(brut)) {
      final fin = brut.indexOf('endstream', debut.end);
      if (fin < 0) continue;
      try {
        final flux = latin1.decode(
          ZLibDecoder().convert(pdf.sublist(debut.end, fin)),
          allowInvalid: true,
        );
        total += signature.allMatches(flux).length;
      } catch (_) {}
    }
    return total;
  }

  /// Relit le TEXTE d'un PDF produit par le paquet `pdf` (ticket F0.87-bis), SANS dépendance :
  /// zlib de `dart:io` et la table `ToUnicode` de chaque police.
  ///
  /// Le moteur écrit chaque mot par un opérateur `/Fn t Tf … [<codes>]TJ` ; un code est l'INDEX
  /// du caractère dans la table de SA police (la police grasse et la normale ont deux tables
  /// différentes : « 0001 » n'est pas la même lettre). Les espaces ne sont pas écrites : un mot =
  /// un `TJ`, rendu ici séparé par une espace.
  ///
  /// ⚠️ STRICT : un flux illisible, une police sans table, un code absent de sa table, un `TJ`
  /// d'une autre forme ou un `Tj` font ÉCHOUER le test — une lecture qui saute ce qu'elle ne
  /// comprend pas passerait sur un PDF vide.
  List<String> motsDuPdf(List<int> pdf) {
    final brut = latin1.decode(pdf);
    final objets = <int, ({String dict, String? flux})>{};
    final enTeteObjet = RegExp(r'(\d+) 0 obj');
    var position = 0;
    while (true) {
      final m = enTeteObjet.firstMatch(brut.substring(position));
      if (m == null) break;
      final debutObjet = position + m.end;
      final numero = int.parse(m.group(1)!);
      final finDict = brut.indexOf('stream', debutObjet);
      final finObjet = brut.indexOf('endobj', debutObjet);
      if (finDict < 0 || finDict > finObjet) {
        objets[numero] = (
          dict: brut.substring(debutObjet, finObjet),
          flux: null,
        );
        position = finObjet + 'endobj'.length;
        continue;
      }
      final dict = brut.substring(debutObjet, finDict);
      var debutFlux = finDict + 'stream'.length;
      if (brut[debutFlux] == '\r') debutFlux++;
      if (brut[debutFlux] == '\n') debutFlux++;
      // La longueur DÉCLARÉE borne le flux : un « endstream » peut figurer dans des octets compressés.
      final longueur = int.parse(
        RegExp(r'/Length (\d+)').firstMatch(dict)!.group(1)!,
      );
      final octets = pdf.sublist(debutFlux, debutFlux + longueur);
      objets[numero] = (
        dict: dict,
        flux: dict.contains('/FlateDecode')
            ? latin1.decode(ZLibDecoder().convert(octets))
            : null,
      );
      position = brut.indexOf('endobj', debutFlux + longueur) + 'endobj'.length;
    }

    // Police (/F6, /F11…) → table code → caractère.
    final tables = <String, Map<int, String>>{};
    for (final o in objets.values) {
      if (!o.dict.contains('/Subtype/Type0')) continue;
      final nom = RegExp(r'/Name/(F\d+)').firstMatch(o.dict)!.group(1)!;
      final ref = int.parse(
        RegExp(r'/ToUnicode (\d+) 0 R').firstMatch(o.dict)!.group(1)!,
      );
      final cmap = objets[ref]!.flux!;
      final paires = cmap.substring(
        cmap.indexOf('beginbfchar'),
        cmap.indexOf('endbfchar'),
      );
      tables[nom] = {
        for (final p in RegExp(
          r'<([0-9A-Fa-f]{4})> <([0-9A-Fa-f]+)>',
        ).allMatches(paires))
          int.parse(p.group(1)!, radix: 16): String.fromCharCode(
            int.parse(p.group(2)!, radix: 16),
          ),
      };
    }
    expect(tables, isNotEmpty, reason: 'aucune police Type0 avec ToUnicode');

    // Pages dans l'ordre de /Kids, puis leurs flux de contenu.
    final racine = objets.values.firstWhere(
      (o) => o.dict.contains('/Type/Pages'),
    );
    final kids = RegExp(
      r'/Kids\[([^\]]*)\]',
    ).firstMatch(racine.dict)!.group(1)!;
    final mots = <String>[];
    final operateur = RegExp(r'/(F\d+) [\d.]+ Tf|\[<([0-9A-Fa-f]*)>\]TJ');
    for (final page in RegExp(r'(\d+) 0 R').allMatches(kids)) {
      final dictPage = objets[int.parse(page.group(1)!)]!.dict;
      final contenus = RegExp(
        r'/Contents\s*(\[[^\]]*\]|\d+ 0 R)',
      ).firstMatch(dictPage)!.group(1)!;
      for (final c in RegExp(r'(\d+) 0 R').allMatches(contenus)) {
        final flux = objets[int.parse(c.group(1)!)]!.flux!;
        expect(flux.contains(' Tj'), isFalse, reason: 'opérateur Tj non lu');
        String? police;
        var lus = 0;
        for (final o in operateur.allMatches(flux)) {
          if (o.group(1) != null) {
            police = o.group(1);
            continue;
          }
          lus++;
          final table = tables[police]!;
          final hex = o.group(2)!;
          final mot = StringBuffer();
          for (var i = 0; i < hex.length; i += 4) {
            final code = int.parse(hex.substring(i, i + 4), radix: 16);
            mot.write(
              table[code] ??
                  (throw StateError(
                    'code $code absent de la table de $police',
                  )),
            );
          }
          if (mot.isNotEmpty) mots.add(mot.toString());
        }
        expect(
          lus,
          ']TJ'.allMatches(flux).length,
          reason: 'un TJ d’une autre forme n’a pas été lu',
        );
      }
    }
    return mots;
  }

  /// Vérifie que chaque [attendus] se lit dans le texte du PDF, MOT POUR MOT et DANS L'ORDRE
  /// (bornes de mots : « 0 » ne se trouve pas dans « 2026 »).
  void lireDansLOrdre(List<String> mots, List<String> attendus) {
    final texte = ' ${mots.join(' ')} ';
    var curseur = 0;
    for (final a in attendus) {
      final i = texte.indexOf(' $a ', curseur);
      expect(
        i,
        greaterThanOrEqualTo(0),
        reason: 'absent du PDF (ou hors de l’ordre attendu) : « $a »',
      );
      curseur = i + a.length + 1;
    }
  }

  /// Une ligne du document telle qu'elle se lit dans le PDF : cellules non vides, séparées par une
  /// espace (le moteur écrit mot par mot, cellule après cellule).
  String enLigne(List<String> cellules) =>
      cellules.where((c) => c.isNotEmpty).join(' ');

  // ── Valeurs CALCULÉES À LA MAIN ─────────────────────────────────────────────

  /// Plan, trié par code en CHAÎNES : « 401 » < « 47 » (« 0 » < « 7 »). Classe absente : « — ».
  const planAttendu = [
    ['101', 'Capital', '1'],
    ['401', 'Fournisseurs', '4'],
    ['47', 'Compte d’attente', '—'],
    ['531', 'Caisse', '5'],
    ['601', 'Achats', '6'],
    ['701', 'Ventes', '7'],
  ];

  /// Journal : date DÉCROISSANTE ; N° Pièce = avant le premier « — », Libellé = après (« — » s'il
  /// n'y en a pas) ; Montant = total débit arrondi au franc (1 234,60 → « 1 235 »).
  const journalAttendu = [
    ['OD-2026-0007', '02/04/2026', 'Avril', '601', '531', '600'],
    ['OD-2026-0006', '25/03/2026', 'Vente fin de mois', '531', '701', '3 000'],
    ['OD-2026-0005', '18/03/2026', 'Vente d’œufs', '531', '701', '1 235'],
    ['VTE-0042', '10/03/2026', '—', '531', '701', '500'],
    [
      'OD-2026-0004',
      '05/03/2026',
      'Règlement fournisseur',
      '401',
      '531',
      '15 000',
    ],
    ['OD-2026-0003', '02/03/2026', 'Vente comptant', '531', '701', '25 000'],
    ['OD-2026-0002', '15/02/2026', 'Achat provende', '601', '401', '40 000'],
    [
      'OD-2026-0001',
      '10/01/2026',
      'Apport du capital',
      '531',
      '101',
      '100 000',
    ],
  ];

  /// Grand Livre 531 (débiteur), 01/03 → 20/03 : ouverture = E1 = 100 000 ;
  /// E3 +25 000 = 125 000 ; E4 −15 000 = 110 000 ; E8 +500 = 110 500 ; E5 +1 234,60 = 111 734,60.
  /// Débits 26 734,60 (« 26 735 »), crédits 15 000, final 111 734,60 (« 111 735 »).
  const livre531 = [
    ['02/03/2026', 'OD-2026-0003', 'Vente comptant', '25 000', '—', '125 000'],
    [
      '05/03/2026',
      'OD-2026-0004',
      'Règlement fournisseur',
      '—',
      '15 000',
      '110 000',
    ],
    ['10/03/2026', 'VTE-0042', '—', '500', '—', '110 500'],
    ['18/03/2026', 'OD-2026-0005', 'Vente d’œufs', '1 235', '—', '111 735'],
  ];

  /// Balance de MARS 2026. Ouverture (avant le 01/03) : 531 D 100 000 ; 101 C 100 000 ;
  /// 601 D 40 000 ; 401 C 40 000. Mouvements : 531 D 25 000 + 500 + 1 234,60 + 3 000 = 29 734,60,
  /// C 15 000 ; 401 D 15 000 ; 701 C 29 734,60. Finals : 531 D 114 734,60 ; 101 C 100 000 ;
  /// 401 C 25 000 ; 601 D 40 000 ; 701 C 29 734,60. « 47 » n'a aucune ligne : absent.
  const balanceMars = [
    ['101', 'Capital', '—', '100 000', '—', '—', '—', '100 000'],
    ['401', 'Fournisseurs', '—', '40 000', '15 000', '—', '—', '25 000'],
    ['531', 'Caisse', '100 000', '—', '29 735', '15 000', '114 735', '—'],
    ['601', 'Achats', '40 000', '—', '—', '—', '40 000', '—'],
    ['701', 'Ventes', '—', '—', '—', '29 735', '—', '29 735'],
  ];

  /// Totaux : ouverture 140 000 / 140 000 ; mouvements 44 734,60 / 44 734,60 ;
  /// finals 154 734,60 / 154 734,60 (écart nul).
  const totauxMars = [
    'TOTAUX',
    '',
    '140 000',
    '140 000',
    '44 735',
    '44 735',
    '154 735',
    '154 735',
  ];

  /// Jeu « centimes », Grand Livre 531 (débiteur), 01/03 → 20/03 — À LA MAIN : ouverture = E20 =
  /// 0,40 (« 0 ») ; E21 crédit 0,40 → solde 0,00 ; E22 débit 0,40 → solde 0,40. Débit et crédit
  /// de 0,40 s'écrivent « 0 » (jamais « — ») ; totaux 0,40 / 0,40, final 0,40 : « 0 ».
  const centimes531 = [
    ['06/03/2026', 'OD-2026-0021', 'Centimes rendus', '—', '0', '0'],
    ['10/03/2026', 'OD-2026-0022', 'Centimes encaissés', '0', '—', '0'],
  ];
  const totauxCentimes531 = [
    ["Solde d'ouverture", '', '', '', '', '0'],
    ['Totaux de la période', '', '', '0', '0', '0'],
  ];

  /// Jeu « centimes », Balance de MARS 2026 — À LA MAIN. 531 : ouverture D 0,40 ; mouvements
  /// D 0,40 (E22) et C 0,40 (E21) ; final net 0,40 + 0,40 − 0,40 = D 0,40. 701 : ouverture C 0,40 ;
  /// mouvements D 0,40 (E21) et C 0,40 (E22) ; final C 0,40. Toute cellule non nulle vaut « 0 ».
  /// Totaux : ouverture 0,40 / 0,40 → « 0 » ; mouvements 0,80 / 0,80 → « 1 » ; finals 0,40 / 0,40
  /// → « 0 » ; écart nul : aucune mention.
  const centimesMars = [
    ['531', 'Caisse', '0', '—', '0', '0', '0', '—'],
    ['701', 'Ventes', '—', '0', '0', '0', '—', '0'],
  ];
  const totauxCentimesMars = ['TOTAUX', '', '0', '0', '1', '1', '0', '0'];

  /// Mention de pied du journal pour DEUX écritures incomplètes. Le code écrit « (s) » : le texte
  /// ne varie pas entre singulier et pluriel, seul le nombre change.
  const noteDeuxIncompletes =
      '2 écriture(s) marquée(s) « incomplète » : lignes non encore reçues au poste '
      '(tirage incomplet) ; le montant affiché est le total des débits reçus.';

  /// Lecture d'une fonction d'export de la maquette.
  ({String titre, String? sousTitre, List<String> colonnes}) maquette(
    String fichier,
    String fonction,
  ) {
    final html = File(
      '$dossierPrototype/$fichier',
    ).readAsStringSync();
    final debut = html.indexOf('function $fonction(');
    final corps = html.substring(debut, html.indexOf('\n}', debut));
    final titre = RegExp(r"title: '([^']*)'").firstMatch(corps)!.group(1)!;
    final sous = RegExp(r"subtitle: '([^']*)'").firstMatch(corps)?.group(1);
    final tete = RegExp(r"tableHeadHtml: '([^']*)'").firstMatch(corps)!;
    final colonnes = [
      for (final m in RegExp(r'<th>([^<]*)</th>').allMatches(tete.group(1)!))
        m.group(1)!,
    ];
    return (titre: titre, sousTitre: sous, colonnes: colonnes);
  }

  /// Lecture d'un gabarit d'export du WEB (ticket F0.88, arbitrage client du 13/10/2026 : les
  /// libellés des PDF comptables suivent le web, plus la maquette). [colonnes] = les `<th>` du
  /// `<thead>` de `resources/views/exports/<vue>.blade.php` ; [appel] = les arguments passés par le
  /// composant Livewire à `PdfExportService::render` (titre, puis sous-titre) ; [corps] = la vue.
  ({List<String> colonnes, String appel, String corps}) web(
    String vue,
    String composant,
  ) {
    final corps = File(
      '$dossierLaravel/resources/views/exports/$vue.blade.php',
    ).readAsStringSync();
    final thead = RegExp(
      r'<thead>([\s\S]*?)</thead>',
    ).firstMatch(corps)!.group(1)!;
    final colonnes = [
      for (final m in RegExp(r'<th[^>]*>([^<]*)</th>').allMatches(thead))
        m.group(1)!.trim(),
    ];
    final php = File(
      '$dossierLaravel/app/Livewire/Comptabilite/$composant.php',
    ).readAsStringSync();
    final debut = php.indexOf("'exports.$vue',");
    expect(debut, greaterThan(0), reason: '$composant : appel introuvable');
    final appel = php.substring(debut, php.indexOf(');', debut));
    return (colonnes: colonnes, appel: appel, corps: corps);
  }

  /// Mention de déséquilibre de la vue web, espaces réduits, montant remplacé par « § ».
  String mentionWeb() {
    final corps = web('balance-generale', 'BalanceGenerale').corps;
    final debut = corps.indexOf("@unless(\$balance['is_balanced'])");
    final bloc = corps.substring(debut, corps.indexOf('@endunless', debut));
    return bloc
        .substring(bloc.indexOf('>') + 1, bloc.indexOf('</p>'))
        .replaceAll(RegExp(r'\{\{[^}]*\}\}'), '§')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Balance construite À LA MAIN (F0.88) : un compte débiteur de 4 500, un compte créditeur de
  /// 4 500,40 ; écart = débits − crédits = −0,40 (crédits plus forts).
  const balanceMoinsQuarante = BalanceGenerale(
    lignes: [
      LigneBalance(
        compteId: 'x',
        compte: null,
        ouvertureDebit: 0,
        ouvertureCredit: 0,
        mouvementsDebit: 4500,
        mouvementsCredit: 0,
        finalDebit: 4500,
        finalCredit: 0,
      ),
      LigneBalance(
        compteId: 'y',
        compte: null,
        ouvertureDebit: 0,
        ouvertureCredit: 0,
        mouvementsDebit: 0,
        mouvementsCredit: 4500.40,
        finalDebit: 0,
        finalCredit: 4500.40,
      ),
    ],
    totalOuvertureDebit: 0,
    totalOuvertureCredit: 0,
    totalMouvementsDebit: 4500,
    totalMouvementsCredit: 4500.40,
    totalFinalDebit: 4500,
    totalFinalCredit: 4500.40,
    ecart: -0.40,
    journalVide: false,
    journalIncomplet: false,
  );

  Future<DonneesComptabilite> charger() => depot.charger();

  group('constructeurs purs — valeurs calculées À LA MAIN', () {
    /// Les quatre documents du jeu, pour les deux tests de libellés.
    Future<
      ({
        DocumentOfficiel plan,
        DocumentOfficiel journal,
        DocumentOfficiel livre,
        DocumentOfficiel balance,
      })
    >
    quatreDocuments() async {
      await jeu();
      final d = await charger();
      return (
        plan: DocumentsComptabilite.plan(d, le: maintenantFixe),
        journal: DocumentsComptabilite.journal(d, le: maintenantFixe),
        livre: DocumentsComptabilite.grandLivre(
          d.grandLivreCompte(
            uuid('c531'),
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 20),
          ),
          debut: DateTime(2026, 3, 1),
          fin: DateTime(2026, 3, 20),
        ),
        balance: DocumentsComptabilite.balance(
          d.balanceGenerale(
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 31),
          ),
          periode: 'Mars 2026 (période courante)',
        ),
      );
    }

    test(
      '⚠️⚠️ F0.88 : titres, sous-titres et colonnes des PDF = gabarits du WEB',
      () async {
        final docs = await quatreDocuments();

        // Plan : `exports/plan-comptable.blade.php`, `PlanComptable::exportPlanComptablePdf`.
        final plan = web('plan-comptable', 'PlanComptable');
        expect(plan.appel, contains("'Plan Comptable SYSCOHADA',"));
        expect(plan.appel, contains("'État au '.now()->format('d/m/Y')"));
        expect(docs.plan.titre, 'Plan Comptable SYSCOHADA');
        // Horloge du poste (injectée) : 20/03/2026, jamais l'horloge réelle.
        expect(docs.plan.sousTitre, 'État au 20/03/2026');
        expect(docs.plan.entetes, plan.colonnes);
        expect(plan.colonnes, ['N° Compte', 'Intitulé', 'Classe']);

        // Journal : `exports/journal-comptable.blade.php`.
        final journal = web('journal-comptable', 'JournalComptable');
        expect(journal.appel, contains("'Journal Comptable',"));
        expect(journal.appel, contains("'État au '.now()->format('d/m/Y')"));
        expect(docs.journal.titre, 'Journal Comptable');
        expect(docs.journal.sousTitre, 'État au 20/03/2026');
        expect(docs.journal.entetes, journal.colonnes);
        expect(journal.colonnes, [
          'N° Pièce',
          'Date',
          'Libellé',
          'Débit',
          'Crédit',
          'Montant',
        ]);

        // Grand Livre : `exports/grand-livre.blade.php` ; titre et période du composant.
        final livre = web('grand-livre', 'GrandLivre');
        expect(
          File(
            '$dossierLaravel/app/Livewire/Comptabilite/GrandLivre.php',
          ).readAsStringSync(),
          contains(
            "'Grand Livre — Compte '.\$account->code.' — '.\$account->label",
          ),
        );
        expect(livre.appel, contains("'Période du '."));
        expect(docs.livre.titre, 'Grand Livre — Compte 531 — Caisse');
        expect(docs.livre.sousTitre, 'Période du 01/03/2026 au 20/03/2026');
        expect(docs.livre.entetes, livre.colonnes);
        expect(livre.colonnes.last, 'Solde Progressif');

        // Balance : `exports/balance-generale.blade.php` ; sous-titre = `periodLabel`.
        final balance = web('balance-generale', 'BalanceGenerale');
        expect(balance.appel, contains("'Balance Générale',"));
        expect(balance.appel, contains(r'$this->periodLabel'));
        expect(docs.balance.titre, 'Balance Générale');
        expect(docs.balance.sousTitre, 'Mars 2026 (période courante)');
        expect(docs.balance.entetes, balance.colonnes);
        expect(balance.colonnes, [
          'N° Compte',
          'Libellé',
          'Ouv. Débit',
          'Ouv. Crédit',
          'Mvt Débit',
          'Mvt Crédit',
          'Final Débit',
          'Final Crédit',
        ]);

        // Mention de déséquilibre : texte de la vue web.
        expect(
          mentionWeb(),
          'Balance déséquilibrée — écart de § FCFA. Une anomalie de saisie doit être '
          'corrigée avant toute clôture.',
        );
      },
    );

    test(
      '⚠️⚠️ F0.88 : la maquette reste relue — le PDF ne s’en écarte QUE là où le web diffère',
      () async {
        // Couverture conservée : les fonctions d'export de la maquette sont toujours lues, et
        // chaque écart du PDF par rapport à elles est ÉNUMÉRÉ (un écart non listé fait échouer).
        // A7 : sans la maquette (absente du monorepo, plan A8), saut AVEC sa raison, jamais rouge.
        if (!File('$dossierPrototype/plan-comptable.html').existsSync()) {
          markTestSkipped('maquette absente ($dossierPrototype) : comparaison impossible');
          return;
        }
        final docs = await quatreDocuments();

        List<int> ecarts(List<String> a, List<String> b) {
          expect(a.length, b.length);
          return [
            for (var i = 0; i < a.length; i++)
              if (a[i] != b[i]) i,
          ];
        }

        final plan = maquette('plan-comptable.html', 'exportPlanComptablePDF');
        expect(plan.titre, docs.plan.titre);
        expect(plan.sousTitre, 'Liste des comptes actifs');
        expect(docs.plan.sousTitre, isNot(plan.sousTitre));
        expect(ecarts(plan.colonnes, docs.plan.entetes), isEmpty);

        final journal = maquette('journal-comptable.html', 'exportJournalPDF');
        expect(journal.titre, docs.journal.titre);
        expect(journal.sousTitre, 'Écritures comptables SYSCOHADA');
        expect(docs.journal.sousTitre, isNot(journal.sousTitre));
        expect(ecarts(journal.colonnes, docs.journal.entetes), isEmpty);

        final livre = maquette('grand-livre.html', 'exportGrandLivrePDF');
        expect(livre.titre, 'Grand Livre — Compte ');
        expect(docs.livre.titre, startsWith(livre.titre));
        expect(livre.colonnes.last, 'Solde');
        expect(ecarts(livre.colonnes, docs.livre.entetes), [5]);

        final balance = maquette('balance-generale.html', 'exportBalancePDF');
        expect(balance.titre, docs.balance.titre);
        expect(balance.colonnes, [
          'N° Compte',
          'Libellé',
          'Ouv. D',
          'Ouv. C',
          'Mvt D',
          'Mvt C',
          'Final D',
          'Final C',
        ]);
        expect(ecarts(balance.colonnes, docs.balance.entetes), [
          2,
          3,
          4,
          5,
          6,
          7,
        ]);
      },
    );

    test(
      '⚠️⚠️ F0.88 : écart de balance — centimes si non nul, « 0 » si nul, signe sur les centimes',
      () {
        // Valeurs ÉCRITES À LA MAIN. Virgule décimale, espace des milliers (celle de `montant`, et
        // de `number_format($x, …, ',', ' ')` du web). Écart = débits − crédits : négatif = crédits
        // plus forts ; le signe est lu sur les CENTIMES arrondis (F0.86-bis : jamais « -0 »).
        // Liste (et non table) : 0.0 et -0.0 sont des clés égales en Dart.
        const cas = <(double, String)>[
          (0.0, '0'),
          (-0.0, '0'),
          (0.004, '0'),
          (-0.004, '0'),
          (0.01, '0,01'),
          (-0.01, '-0,01'),
          (0.4, '0,40'),
          (-0.4, '-0,40'),
          (-0.41, '-0,41'),
          (-0.6, '-0,60'),
          (1, '1,00'),
          (1500, '1 500,00'),
          (-1234.5, '-1 234,50'),
          (1234567.89, '1 234 567,89'),
          (-999999.99, '-999 999,99'),
        ];
        for (final (v, attendu) in cas) {
          expect(DocumentsComptabilite.montantEcart(v), attendu, reason: '$v');
        }
      },
    );

    test(
      'plan : tous les comptes, triés par code, classe absente « — »',
      () async {
        await jeu();
        final doc = DocumentsComptabilite.plan(
          await charger(),
          le: maintenantFixe,
        );

        expect(donnees(doc), planAttendu);
        expect(doc.noteDePied, isNull);
      },
    );

    test(
      '⚠️⚠️ journal : pièce et libellé coupés au premier « — », montant au franc',
      () async {
        await jeu();
        final doc = DocumentsComptabilite.journal(
          await charger(),
          le: maintenantFixe,
        );

        expect(donnees(doc), journalAttendu);
        expect(doc.noteDePied, isNull);
      },
    );

    test(
      '⚠️ journal : un libellé qui contient lui-même « — » reste entier (coupe au PREMIER)',
      () async {
        // Trou relevé par la mutation M28 (coupe au dernier « — ») : aucune référence du jeu
        // n'avait deux tirets. `explode('—', $reference, 2)` du serveur coupe au premier.
        await compte('531', 'Caisse', 5);
        await compte('701', 'Ventes', 7);
        await ecriture(
          'e10',
          DateTime(2026, 3, 3),
          'OD-2026-0010 — Vente — lot 3',
          '531',
          '701',
          900,
        );
        final doc = DocumentsComptabilite.journal(
          await charger(),
          le: maintenantFixe,
        );

        expect(donnees(doc), [
          ['OD-2026-0010', '03/03/2026', 'Vente — lot 3', '531', '701', '900'],
        ]);
      },
    );

    test(
      '⚠️⚠️ journal incomplet : montant marqué « (incomplète) » et mention en pied',
      () async {
        await jeu();
        await ecritureIncomplete();
        final doc = DocumentsComptabilite.journal(
          await charger(),
          le: maintenantFixe,
        );

        // Ordre décroissant : E7 (02/04), E6 (25/03), E9 (19/03), E5 (18/03)…
        expect(donnees(doc)[2], [
          'OD-2026-0009',
          '19/03/2026',
          'Ligne manquante',
          '531',
          '—',
          '700 (incomplète)',
        ]);
        expect(
          doc.noteDePied,
          '1 écriture(s) marquée(s) « incomplète » : lignes non encore reçues au poste '
          '(tirage incomplet) ; le montant affiché est le total des débits reçus.',
        );
      },
    );

    test(
      '⚠️⚠️ grand livre 531 : ouverture, solde progressif, totaux de la période',
      () async {
        await jeu();
        final d = await charger();
        final doc = DocumentsComptabilite.grandLivre(
          d.grandLivreCompte(
            uuid('c531'),
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 20),
          ),
          debut: DateTime(2026, 3, 1),
          fin: DateTime(2026, 3, 20),
        );

        expect(donnees(doc), livre531);
        expect(totaux(doc), [
          ["Solde d'ouverture", '', '', '', '', '100 000'],
          ['Totaux de la période', '', '', '26 735', '15 000', '111 735'],
        ]);
        // L'ouverture ouvre le document, les totaux le ferment.
        expect(doc.lignes.first, isA<TotalDocument>());
        expect(doc.lignes.last, isA<TotalDocument>());
        expect((doc.lignes.last as TotalDocument).premiere, isTrue);
        expect(doc.noteDePied, isNull);
      },
    );

    test(
      '⚠️⚠️ grand livre 701 (créditeur) : le solde monte avec les CRÉDITS',
      () async {
        await jeu();
        final d = await charger();
        final doc = DocumentsComptabilite.grandLivre(
          d.grandLivreCompte(
            uuid('c701'),
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 20),
          ),
          debut: DateTime(2026, 3, 1),
          fin: DateTime(2026, 3, 20),
        );

        expect(doc.titre, 'Grand Livre — Compte 701 — Ventes');
        // Ouverture 0 (aucune vente avant mars, mais le compte a des écritures : connue) ;
        // 25 000 → 25 500 → 26 734,60.
        expect(donnees(doc), [
          [
            '02/03/2026',
            'OD-2026-0003',
            'Vente comptant',
            '—',
            '25 000',
            '25 000',
          ],
          ['10/03/2026', 'VTE-0042', '—', '—', '500', '25 500'],
          [
            '18/03/2026',
            'OD-2026-0005',
            'Vente d’œufs',
            '—',
            '1 235',
            '26 735',
          ],
        ]);
        expect(totaux(doc), [
          ["Solde d'ouverture", '', '', '', '', '0'],
          ['Totaux de la période', '', '', '0', '26 735', '26 735'],
        ]);
      },
    );

    test(
      '⚠️⚠️ grand livre, journal incomplet : ouverture et final « — », raison en pied',
      () async {
        await jeu();
        await ecritureIncomplete();
        final d = await charger();
        final doc = DocumentsComptabilite.grandLivre(
          d.grandLivreCompte(
            uuid('c531'),
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 20),
          ),
          debut: DateTime(2026, 3, 1),
          fin: DateTime(2026, 3, 20),
        );

        expect(totaux(doc), [
          ["Solde d'ouverture", '', '', '', '', '—'],
          ['Totaux de la période', '', '', '27 435', '15 000', '—'],
        ]);
        expect(
          doc.noteDePied,
          '${DocumentsComptabilite.motifJournalIncomplet}.',
        );
      },
    );

    test(
      'grand livre : un compte sans écriture sur la période ne produit aucune ligne',
      () async {
        await jeu();
        final d = await charger();
        final doc = DocumentsComptabilite.grandLivre(
          d.grandLivreCompte(
            uuid('c47'),
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 20),
          ),
          debut: DateTime(2026, 3, 1),
          fin: DateTime(2026, 3, 20),
        );

        expect(doc.lignes, isEmpty);
      },
    );

    test(
      '⚠️⚠️ balance de mars : lignes, ligne TOTAUX, aucun bandeau (équilibrée)',
      () async {
        await jeu();
        final d = await charger();
        final doc = DocumentsComptabilite.balance(
          d.balanceGenerale(
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 31),
          ),
          periode: 'Mars 2026 (période courante)',
        );

        expect(donnees(doc), balanceMars);
        expect(totaux(doc), [totauxMars]);
        expect((doc.lignes.last as TotalDocument).premiere, isTrue);
        expect(doc.noteDePied, isNull);
      },
    );

    test(
      '⚠️⚠️ balance, journal incomplet : soldes « — », mouvements montrés, mention de l’écran',
      () async {
        await jeu();
        await ecritureIncomplete();
        final d = await charger();
        final doc = DocumentsComptabilite.balance(
          d.balanceGenerale(
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 31),
          ),
          periode: 'Mars 2026 (période courante)',
        );

        expect(donnees(doc), [
          ['101', 'Capital', '—', '—', '—', '—', '—', '—'],
          ['401', 'Fournisseurs', '—', '—', '15 000', '—', '—', '—'],
          ['531', 'Caisse', '—', '—', '30 435', '15 000', '—', '—'],
          ['601', 'Achats', '—', '—', '—', '—', '—', '—'],
          ['701', 'Ventes', '—', '—', '—', '29 735', '—', '—'],
        ]);
        expect(totaux(doc), [
          ['TOTAUX', '', '—', '—', '45 435', '44 735', '—', '—'],
        ]);
        expect(
          doc.noteDePied,
          "${DocumentsComptabilite.motifJournalIncomplet}. Soldes d'ouverture et finaux "
          'portent un tiret ; les mouvements de la période sont ceux du journal reçu.',
        );
      },
    );

    test(
      '⚠️⚠️ balance déséquilibrée : la mention de l’écran et l’écart en pied',
      () {
        const b = BalanceGenerale(
          lignes: [
            LigneBalance(
              compteId: 'x',
              compte: null,
              ouvertureDebit: 0,
              ouvertureCredit: 0,
              mouvementsDebit: 1500,
              mouvementsCredit: 0,
              finalDebit: 1500,
              finalCredit: 0,
            ),
          ],
          totalOuvertureDebit: 0,
          totalOuvertureCredit: 0,
          totalMouvementsDebit: 1500,
          totalMouvementsCredit: 0,
          totalFinalDebit: 1500,
          totalFinalCredit: 0,
          ecart: 1500,
          journalVide: false,
          journalIncomplet: false,
        );
        final doc = DocumentsComptabilite.balance(b, periode: 'P');

        expect(donnees(doc), [
          [
            '—',
            'Compte absent du plan reçu au poste',
            '—',
            '—',
            '1 500',
            '—',
            '1 500',
            '—',
          ],
        ]);
        // F0.88 : texte de la vue WEB (`exports/balance-generale.blade.php`), écart en centimes.
        expect(
          doc.noteDePied,
          'Balance déséquilibrée — écart de 1 500,00 FCFA. Une anomalie de saisie doit être '
          'corrigée avant toute clôture.',
        );
        expect(doc.noteDePied, mentionWeb().replaceAll('§', '1 500,00'));
      },
    );

    test(
      '⚠️⚠️ F0.88 : écart de -0,40 → « -0,40 FCFA » en pied (jamais « 0 », jamais « -0 »)',
      () {
        final doc = DocumentsComptabilite.balance(
          balanceMoinsQuarante,
          periode: 'P',
        );

        expect(
          doc.noteDePied,
          'Balance déséquilibrée — écart de -0,40 FCFA. Une anomalie de saisie doit être '
          'corrigée avant toute clôture.',
        );
        // Les autres montants gardent leur arrondi au franc.
        expect(totaux(doc), [
          ['TOTAUX', '', '0', '0', '4 500', '4 500', '4 500', '4 500'],
        ]);
      },
    );

    test(
      'balance sans compte mouvementé : aucune ligne (rien à éditer)',
      () async {
        await compte('531', 'Caisse', 5);
        final d = await charger();
        final doc = DocumentsComptabilite.balance(
          d.balanceGenerale(
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 31),
          ),
          periode: 'Mars 2026 (période courante)',
        );

        expect(doc.lignes, isEmpty);
      },
    );

    test(
      '⚠️⚠️ aucun « — », « ’ » ni « œ » n’est dessiné en carré barré (polices passées)',
      () async {
        await jeu();
        await ecritureIncomplete();
        final d = await charger();
        final polices = await ExportOfficiel.chargerPolices();

        for (final doc in [
          DocumentsComptabilite.plan(d, le: maintenantFixe),
          DocumentsComptabilite.journal(d, le: maintenantFixe),
          DocumentsComptabilite.grandLivre(
            d.grandLivreCompte(
              uuid('c531'),
              debut: DateTime(2026, 3, 1),
              fin: DateTime(2026, 3, 20),
            ),
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 20),
          ),
          DocumentsComptabilite.balance(
            d.balanceGenerale(
              debut: DateTime(2026, 3, 1),
              fin: DateTime(2026, 3, 31),
            ),
            periode: 'Mars 2026 (période courante)',
          ),
        ]) {
          final octets = await ExportOfficiel.construire(
            doc,
            maintenant: maintenantFixe,
            polices: polices,
          );
          expect(octets.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
          expect(glyphesManquants(octets), 0, reason: doc.titre);
        }
      },
    );

    test(
      '⚠️ le « ⚠ » de l’écran n’est PAS dans la police : il sortirait en carré barré',
      () async {
        // Pourquoi le document écrit « (incomplète) » au lieu du signe de l'écran.
        final polices = await ExportOfficiel.chargerPolices();
        final octets = await ExportOfficiel.construire(
          const DocumentOfficiel(
            titre: 'Sonde',
            sousTitre: '',
            entetes: ['Montant'],
            lignes: [
              DonneesDocument(['700 ⚠']),
            ],
          ),
          maintenant: maintenantFixe,
          polices: polices,
        );
        expect(glyphesManquants(octets), greaterThan(0));
      },
    );

    test(
      '⚠️⚠️ P1 grand livre : un débit et un crédit de 0,40 F s’écrivent « 0 », jamais « — »',
      () async {
        // Trou relevé par l'audit de F0.87 : `montantOuTiret` passé de `> 0` à `>= 0.5` survivait
        // (aucun montant du jeu n'était dans ]0 ; 0,5[). La vue du serveur teste `> 0`.
        await jeuCentimes();
        final d = await charger();
        final doc = DocumentsComptabilite.grandLivre(
          d.grandLivreCompte(
            uuid('c531'),
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 20),
          ),
          debut: DateTime(2026, 3, 1),
          fin: DateTime(2026, 3, 20),
        );

        expect(donnees(doc), centimes531);
        expect(totaux(doc), totauxCentimes531);
        expect(doc.noteDePied, isNull);
      },
    );

    test(
      '⚠️⚠️ P1 balance : ouverture, mouvements et final de 0,40 F s’écrivent « 0 », jamais « — »',
      () async {
        await jeuCentimes();
        final d = await charger();
        final doc = DocumentsComptabilite.balance(
          d.balanceGenerale(
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 31),
          ),
          periode: 'Mars 2026 (période courante)',
        );

        expect(donnees(doc), centimesMars);
        expect(totaux(doc), [totauxCentimesMars]);
        expect(doc.noteDePied, isNull);
      },
    );

    test(
      '⚠️⚠️ P2 journal : DEUX écritures incomplètes — les deux marquées, « 2 » en pied',
      () async {
        // Trou relevé par l'audit de F0.87 : le nombre figé à « 1 » dans la mention survivait
        // (le jeu n'avait qu'une écriture incomplète).
        await jeu();
        await ecritureIncomplete();
        await secondeEcritureIncomplete();
        final doc = DocumentsComptabilite.journal(
          await charger(),
          le: maintenantFixe,
        );
        final lignes = donnees(doc);

        // Ordre décroissant : E7 (02/04), E6 (25/03), E9 (19/03), E5 (18/03), E11 (12/03)…
        expect(lignes[2], [
          'OD-2026-0009',
          '19/03/2026',
          'Ligne manquante',
          '531',
          '—',
          '700 (incomplète)',
        ]);
        expect(lignes[4], [
          'OD-2026-0011',
          '12/03/2026',
          'Seconde ligne manquante',
          '601',
          '—',
          '250 (incomplète)',
        ]);
        expect(
          lignes.where((l) => l.last.endsWith('(incomplète)')),
          hasLength(2),
        );
        expect(lignes, hasLength(10));
        expect(doc.noteDePied, noteDeuxIncompletes);
      },
    );
  });

  group('texte RELU dans le PDF produit (F0.87-bis)', () {
    Future<List<String>> motsDe(DocumentOfficiel doc) async => motsDuPdf(
      await ExportOfficiel.construire(
        doc,
        maintenant: maintenantFixe,
        polices: await ExportOfficiel.chargerPolices(),
      ),
    );

    /// Ce qu'un lecteur doit lire dans le PDF : titre (en capitales), sous-titre, colonnes (en
    /// capitales), chaque ligne dans l'ordre, puis la mention de pied.
    List<String> attendusDe(DocumentOfficiel doc) => [
      doc.titre.toUpperCase(),
      if (doc.sousTitre.isNotEmpty) doc.sousTitre,
      enLigne([for (final e in doc.entetes) e.toUpperCase()]),
      for (final l in doc.lignes)
        switch (l) {
          DonneesDocument(:final cellules) => enLigne(cellules),
          TotalDocument(:final cellules) => enLigne(cellules),
          _ => throw StateError('ligne inattendue'),
        },
      if (doc.noteDePied != null) doc.noteDePied!,
    ];

    test('le lecteur relit un document connu, et rien de plus', () async {
      const sonde = DocumentOfficiel(
        titre: 'Sonde — lecture',
        sousTitre: 'Période du 01/03/2026 au 20/03/2026',
        entetes: ['Libellé', 'Montant'],
        lignes: [
          DonneesDocument(['Vente d’œufs', '1 235']),
          TotalDocument(['Totaux', '0'], premiere: true),
        ],
        noteDePied: 'Mention « de pied ».',
      );
      final mots = await motsDe(sonde);

      lireDansLOrdre(mots, [
        'SONDE — LECTURE',
        'Période du 01/03/2026 au 20/03/2026',
        'LIBELLÉ MONTANT',
        'Vente d’œufs 1 235',
        'Totaux 0',
        'Mention « de pied ».',
      ]);
      // Une valeur absente du document n'est pas « lue ».
      expect(mots.join(' '), isNot(contains('9 999')));
    });

    test(
      '⚠️⚠️ (a) les quatre documents se relisent dans le PDF : titre, colonnes, CHAQUE ligne, mention',
      () async {
        await jeu();
        await ecritureIncomplete();
        await secondeEcritureIncomplete();
        final d = await charger();

        final documents = [
          DocumentsComptabilite.plan(d, le: maintenantFixe),
          DocumentsComptabilite.journal(d, le: maintenantFixe),
          DocumentsComptabilite.grandLivre(
            d.grandLivreCompte(
              uuid('c531'),
              debut: DateTime(2026, 3, 1),
              fin: DateTime(2026, 3, 20),
            ),
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 20),
          ),
          DocumentsComptabilite.balance(
            d.balanceGenerale(
              debut: DateTime(2026, 3, 1),
              fin: DateTime(2026, 3, 31),
            ),
            periode: 'Mars 2026 (période courante)',
          ),
        ];
        for (final doc in documents) {
          expect(doc.lignes, isNotEmpty, reason: doc.titre);
          lireDansLOrdre(await motsDe(doc), attendusDe(doc));
        }
        // Le journal, le grand livre et la balance portent une mention : elle est bien imprimée.
        expect(documents.where((d) => d.noteDePied != null), hasLength(3));
      },
    );

    test(
      '⚠️⚠️ F0.88 dans le PDF : les libellés du WEB sont imprimés (un par document)',
      () async {
        await jeu();
        final d = await charger();

        // Libellés écrits À LA MAIN (pas relus du code) : ce que le lecteur doit voir.
        lireDansLOrdre(
          await motsDe(DocumentsComptabilite.plan(d, le: maintenantFixe)),
          ['PLAN COMPTABLE SYSCOHADA', 'État au 20/03/2026'],
        );
        lireDansLOrdre(
          await motsDe(DocumentsComptabilite.journal(d, le: maintenantFixe)),
          ['JOURNAL COMPTABLE', 'État au 20/03/2026'],
        );
        lireDansLOrdre(
          await motsDe(
            DocumentsComptabilite.grandLivre(
              d.grandLivreCompte(
                uuid('c531'),
                debut: DateTime(2026, 3, 1),
                fin: DateTime(2026, 3, 20),
              ),
              debut: DateTime(2026, 3, 1),
              fin: DateTime(2026, 3, 20),
            ),
          ),
          ['DATE N° PIÈCE LIBELLÉ DÉBIT CRÉDIT SOLDE PROGRESSIF'],
        );
        lireDansLOrdre(
          await motsDe(
            DocumentsComptabilite.balance(
              d.balanceGenerale(
                debut: DateTime(2026, 3, 1),
                fin: DateTime(2026, 3, 31),
              ),
              periode: 'Mars 2026 (période courante)',
            ),
          ),
          [
            'N° COMPTE LIBELLÉ OUV. DÉBIT OUV. CRÉDIT MVT DÉBIT MVT CRÉDIT '
                'FINAL DÉBIT FINAL CRÉDIT',
          ],
        );
      },
    );

    test(
      '⚠️⚠️ F0.88 dans le PDF : l’écart de -0,40 est imprimé avec ses centimes',
      () async {
        final mots = await motsDe(
          DocumentsComptabilite.balance(balanceMoinsQuarante, periode: 'P'),
        );

        lireDansLOrdre(mots, [
          'TOTAUX 0 0 4 500 4 500 4 500 4 500',
          'Balance déséquilibrée — écart de -0,40 FCFA. Une anomalie de saisie doit être '
              'corrigée avant toute clôture.',
        ]);
        expect(mots, isNot(contains('-0')));
      },
    );

    test(
      '⚠️⚠️ P1 dans le PDF : les cellules de 0,40 F sont imprimées « 0 », pas « — »',
      () async {
        await jeuCentimes();
        final d = await charger();
        final livre = await motsDe(
          DocumentsComptabilite.grandLivre(
            d.grandLivreCompte(
              uuid('c531'),
              debut: DateTime(2026, 3, 1),
              fin: DateTime(2026, 3, 20),
            ),
            debut: DateTime(2026, 3, 1),
            fin: DateTime(2026, 3, 20),
          ),
        );
        lireDansLOrdre(livre, [
          for (final l in totauxCentimes531.take(1)) enLigne(l),
          for (final l in centimes531) enLigne(l),
          enLigne(totauxCentimes531.last),
        ]);

        final balance = await motsDe(
          DocumentsComptabilite.balance(
            d.balanceGenerale(
              debut: DateTime(2026, 3, 1),
              fin: DateTime(2026, 3, 31),
            ),
            periode: 'Mars 2026 (période courante)',
          ),
        );
        lireDansLOrdre(balance, [
          for (final l in centimesMars) enLigne(l),
          enLigne(totauxCentimesMars),
        ]);
      },
    );

    test(
      '⚠️⚠️ P2 dans le PDF : deux lignes « (incomplète) » et « 2 écriture(s) » imprimés',
      () async {
        await jeu();
        await ecritureIncomplete();
        await secondeEcritureIncomplete();
        final mots = await motsDe(
          DocumentsComptabilite.journal(await charger(), le: maintenantFixe),
        );

        lireDansLOrdre(mots, [
          'OD-2026-0009 19/03/2026 Ligne manquante 531 — 700 (incomplète)',
          'OD-2026-0011 12/03/2026 Seconde ligne manquante 601 — 250 (incomplète)',
          noteDeuxIncompletes,
        ]);
        expect(mots.where((m) => m == '(incomplète)'), hasLength(2));
      },
    );
  });

  group('câblage (lecture du code source : invisible au rendu)', () {
    test(
      '⚠️ main.dart branche l’éditeur de production sur la Comptabilité',
      () {
        final src = File('lib/main.dart').readAsStringSync();
        final debut = src.indexOf('EcranPoste.comptabilite =>');
        final fin = src.indexOf('EcranPoste.parametresGeneraux =>');

        expect(debut, greaterThan(0));
        expect(
          src.substring(debut, fin),
          contains('imprimer: EditeursRapports.imprimer'),
        );
      },
    );
  });

  group('écran', () {
    late List<(DocumentOfficiel, DateTime)> editions;

    Future<void> afficher(
      WidgetTester tester,
      PageComptable page, {
      Future<String?> Function(DocumentOfficiel, DateTime)? editeur,
      bool sansEditeur = false,
    }) async {
      editions = [];
      tester.view.physicalSize = const Size(1700, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ComptabiliteScreen(
            depot: depot,
            maintenant: () => maintenantFixe,
            imprimer: sansEditeur
                ? null
                : editeur ??
                      (document, quand) async {
                        editions.add((document, quand));
                        return null;
                      },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('carte-${page.name}')));
      await tester.pumpAndSettle();
    }

    /// Les textes affichés d'une ligne du tableau de l'écran.
    List<String> celluleEcran(WidgetTester tester, int i) => [
      for (final t in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(Key('ligne-$i')),
          matching: find.byType(Text),
        ),
      ))
        t.data!,
    ];

    List<List<String>> tableauEcran(WidgetTester tester) => [
      for (var i = 0; find.byKey(Key('ligne-$i')).evaluate().isNotEmpty; i++)
        celluleEcran(tester, i),
    ];

    Future<void> exporter(WidgetTester tester, String cle) async {
      await tester.ensureVisible(find.byKey(Key(cle)));
      await tester.tap(find.byKey(Key(cle)));
      await tester.pumpAndSettle();
    }

    const boutons = {
      PageComptable.planComptable: 'exporter-pdf-plan',
      PageComptable.journal: 'exporter-pdf-journal',
      PageComptable.grandLivre: 'exporter-pdf-grand-livre',
      PageComptable.balance: 'exporter-pdf-balance',
    };

    for (final MapEntry(key: page, value: cle) in boutons.entries) {
      testWidgets('⚠️ ${page.libelle} : bouton « Exporter PDF » de la maquette', (
        tester,
      ) async {
        await jeu();
        await afficher(tester, page);

        expect(
          find.descendant(
            of: find.byKey(Key(cle)),
            matching: find.text('Exporter PDF'),
          ),
          findsOneWidget,
        );
        await exporter(tester, cle);
        expect(editions, hasLength(1));
        // L'horloge passée à l'éditeur est celle du poste (injectée), pas l'horloge réelle.
        expect(editions.single.$2, maintenantFixe);
        expect(find.text('Document envoyé à l’impression.'), findsOneWidget);
      });
    }

    testWidgets('⚠️⚠️ plan : document = lignes affichées', (tester) async {
      await jeu();
      await afficher(tester, PageComptable.planComptable);
      await exporter(tester, 'exporter-pdf-plan');

      final doc = editions.single.$1;
      expect(donnees(doc), tableauEcran(tester));
      expect(donnees(doc), planAttendu);
    });

    testWidgets(
      '⚠️⚠️ journal : l’écran montre le N° de pièce, pas le type de source, et le PDF aussi',
      (tester) async {
        await jeu();
        await afficher(tester, PageComptable.journal);

        expect(tableauEcran(tester), journalAttendu);
        expect(find.text('sale'), findsNothing);

        await exporter(tester, 'exporter-pdf-journal');
        expect(donnees(editions.single.$1), tableauEcran(tester));
      },
    );

    testWidgets(
      '⚠️⚠️ grand livre : document = lignes et cartes affichées (531 par défaut, 01/03 → 20/03)',
      (tester) async {
        await jeu();
        await afficher(tester, PageComptable.grandLivre);
        await exporter(tester, 'exporter-pdf-grand-livre');

        final doc = editions.single.$1;
        expect(doc.titre, 'Grand Livre — Compte 531 — Caisse');
        expect(doc.sousTitre, 'Période du 01/03/2026 au 20/03/2026');
        expect(donnees(doc), tableauEcran(tester));
        expect(donnees(doc), livre531);

        // Ouverture, totaux et final = les cartes de l'écran.
        String carte(String cle, String valeur) {
          expect(
            find.descendant(
              of: find.byKey(Key(cle)),
              matching: find.text(valeur),
            ),
            findsOneWidget,
            reason: cle,
          );
          return valeur;
        }

        expect(totaux(doc), [
          [
            "Solde d'ouverture",
            '',
            '',
            '',
            '',
            carte('kpi-livre-ouverture', '100 000'),
          ],
          [
            'Totaux de la période',
            '',
            '',
            carte('kpi-livre-debit', '26 735'),
            carte('kpi-livre-credit', '15 000'),
            carte('kpi-livre-final', '111 735'),
          ],
        ]);
      },
    );

    testWidgets(
      '⚠️⚠️ grand livre : compte, période et recherche exportés = ceux affichés',
      (tester) async {
        await jeu();
        await afficher(tester, PageComptable.grandLivre);

        // Début de période porté au 03/03/2026 : E3 (02/03) passe dans l'ouverture.
        await tester.tap(find.byKey(const Key('gl-date-debut')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('3').last);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        await exporter(tester, 'exporter-pdf-grand-livre');
        var doc = editions.last.$1;
        expect(doc.sousTitre, 'Période du 03/03/2026 au 20/03/2026');
        // Ouverture 100 000 + 25 000 = 125 000 ; 110 000 ; 110 500 ; 111 734,60.
        expect(donnees(doc), livre531.sublist(1));
        expect(totaux(doc).first.last, '125 000');
        expect(donnees(doc), tableauEcran(tester));

        // Recherche « vente » : seules E5 et (déjà hors période) E3 portent « Vente » → E5.
        await tester.enterText(find.byKey(const Key('gl-recherche')), 'vente');
        await tester.pumpAndSettle();
        await exporter(tester, 'exporter-pdf-grand-livre');
        doc = editions.last.$1;
        expect(donnees(doc), [
          [
            '18/03/2026',
            'OD-2026-0005',
            'Vente d’œufs',
            '1 235',
            '—',
            '126 235',
          ],
        ]);
        expect(donnees(doc), tableauEcran(tester));

        // Compte 701 choisi dans la liste.
        await tester.enterText(find.byKey(const Key('gl-recherche')), '');
        await tester.tap(find.byKey(const Key('compte-grand-livre')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('701 — Ventes').last);
        await tester.pumpAndSettle();
        await exporter(tester, 'exporter-pdf-grand-livre');
        doc = editions.last.$1;
        expect(doc.titre, 'Grand Livre — Compte 701 — Ventes');
        expect(donnees(doc), tableauEcran(tester));
      },
    );

    testWidgets(
      '⚠️⚠️ balance : document = lignes et TOTAUX affichés, période du sélecteur',
      (tester) async {
        await jeu();
        await afficher(tester, PageComptable.balance);
        await exporter(tester, 'exporter-pdf-balance');

        var doc = editions.single.$1;
        expect(doc.sousTitre, 'Mars 2026 (période courante)');
        expect(donnees(doc), tableauEcran(tester));
        expect(donnees(doc), balanceMars);
        final totauxEcran = [
          'TOTAUX',
          '',
          for (var c = 0; c < 6; c++)
            tester.widget<Text>(find.byKey(Key('bal-total-$c'))).data!,
        ];
        expect(totaux(doc), [totauxEcran]);
        expect(totaux(doc), [totauxMars]);

        // Exercice complet 2026 : ouverture nulle, tout le journal de l'exercice.
        await tester.tap(find.byKey(const Key('balance-periode')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Exercice complet — 2026').last);
        await tester.pumpAndSettle();
        await exporter(tester, 'exporter-pdf-balance');
        doc = editions.last.$1;
        expect(doc.sousTitre, 'Exercice complet — 2026');
        expect(donnees(doc), tableauEcran(tester));
        // 531 : D 100 000 + 25 000 + 500 + 1 234,60 + 3 000 = 129 734,60 ; C 15 000 + 600 = 15 600 ;
        // final 114 134,60. Mouvements totaux 185 334,60 ; finals 154 734,60 des deux côtés.
        expect(donnees(doc)[2], [
          '531',
          'Caisse',
          '—',
          '—',
          '129 735',
          '15 600',
          '114 135',
          '—',
        ]);
        expect(totaux(doc), [
          ['TOTAUX', '', '0', '0', '185 335', '185 335', '154 735', '154 735'],
        ]);
      },
    );

    testWidgets(
      '⚠️⚠️ journal incomplet : même tiret et même mention qu’à l’écran',
      (tester) async {
        await jeu();
        await ecritureIncomplete();
        await afficher(tester, PageComptable.balance);
        await exporter(tester, 'exporter-pdf-balance');

        final doc = editions.single.$1;
        expect(donnees(doc), tableauEcran(tester));
        expect(
          find.textContaining(DocumentsComptabilite.motifJournalIncomplet),
          findsWidgets,
        );
        expect(
          doc.noteDePied,
          startsWith(DocumentsComptabilite.motifJournalIncomplet),
        );
      },
    );

    const vides = {
      PageComptable.planComptable: 'Aucun compte à exporter.',
      PageComptable.journal: 'Aucune écriture à exporter.',
      PageComptable.grandLivre:
          'Aucune écriture à exporter pour ce compte sur cette période.',
      PageComptable.balance:
          'Aucun compte mouvementé à exporter sur cette période.',
    };

    for (final MapEntry(key: page, value: message) in vides.entries) {
      testWidgets(
        '⚠️ ${page.libelle} sans ligne : rien n’est édité, l’écran le dit',
        (tester) async {
          if (page != PageComptable.planComptable) {
            await compte('531', 'Caisse', 5);
          }
          await afficher(tester, page);
          await exporter(tester, boutons[page]!);

          expect(editions, isEmpty);
          expect(find.text(message), findsOneWidget);
        },
      );
    }

    testWidgets('⚠️ le message rendu par l’éditeur est celui qui s’affiche', (
      tester,
    ) async {
      await jeu();
      await afficher(
        tester,
        PageComptable.balance,
        editeur: (document, quand) async => 'Balance enregistrée.',
      );
      await exporter(tester, 'exporter-pdf-balance');

      expect(find.text('Balance enregistrée.'), findsOneWidget);
      expect(find.text('Document envoyé à l’impression.'), findsNothing);
    });

    testWidgets(
      '⚠️⚠️ un éditeur qui lève : l’erreur est capturée et l’écran le dit',
      (tester) async {
        await jeu();
        await afficher(
          tester,
          PageComptable.journal,
          editeur: (document, quand) async =>
              throw StateError('imprimante absente'),
        );
        await exporter(tester, 'exporter-pdf-journal');

        expect(tester.takeException(), isNull);
        expect(
          find.text(
            'L’édition du document a échoué. Réessayez ou vérifiez l’imprimante.',
          ),
          findsOneWidget,
        );
        expect(find.text('Document envoyé à l’impression.'), findsNothing);
      },
    );

    testWidgets('sans éditeur injecté, le bouton ne fait rien (pas d’erreur)', (
      tester,
    ) async {
      await jeu();
      await afficher(tester, PageComptable.planComptable, sansEditeur: true);
      await exporter(tester, 'exporter-pdf-plan');

      expect(tester.takeException(), isNull);
      expect(find.text('Document envoyé à l’impression.'), findsNothing);
    });

    /// Mots du PDF construit À PARTIR DU DOCUMENT QUE L'ÉCRAN A ENVOYÉ à l'éditeur.
    Future<List<String>> motsImprimes(
      WidgetTester tester,
      DocumentOfficiel doc,
    ) async => (await tester.runAsync(
      () async => motsDuPdf(
        await ExportOfficiel.construire(
          doc,
          maintenant: maintenantFixe,
          polices: await ExportOfficiel.chargerPolices(),
        ),
      ),
    ))!;

    String valeurCarte(WidgetTester tester, String cle) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(Key(cle)),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .whereType<String>()
        .firstWhere((t) => RegExp(r'^[\d —-]+$').hasMatch(t));

    testWidgets(
      '⚠️⚠️ P1 grand livre 0,40 F : « 0 » à l’écran, dans le document et dans le PDF',
      (tester) async {
        await jeuCentimes();
        await afficher(tester, PageComptable.grandLivre);

        expect(tableauEcran(tester), centimes531);
        expect(valeurCarte(tester, 'kpi-livre-ouverture'), '0');
        expect(valeurCarte(tester, 'kpi-livre-debit'), '0');
        expect(valeurCarte(tester, 'kpi-livre-credit'), '0');
        expect(valeurCarte(tester, 'kpi-livre-final'), '0');

        await exporter(tester, 'exporter-pdf-grand-livre');
        final doc = editions.single.$1;
        expect(donnees(doc), centimes531);
        expect(totaux(doc), totauxCentimes531);

        lireDansLOrdre(await motsImprimes(tester, doc), [
          for (final l in centimes531) enLigne(l),
          enLigne(totauxCentimes531.last),
        ]);
      },
    );

    testWidgets(
      '⚠️⚠️ P1 balance 0,40 F : « 0 » à l’écran, dans le document et dans le PDF',
      (tester) async {
        await jeuCentimes();
        await afficher(tester, PageComptable.balance);

        expect(tableauEcran(tester), centimesMars);
        expect([
          'TOTAUX',
          '',
          for (var c = 0; c < 6; c++)
            tester.widget<Text>(find.byKey(Key('bal-total-$c'))).data!,
        ], totauxCentimesMars);

        await exporter(tester, 'exporter-pdf-balance');
        final doc = editions.single.$1;
        expect(donnees(doc), centimesMars);
        expect(totaux(doc), [totauxCentimesMars]);

        lireDansLOrdre(await motsImprimes(tester, doc), [
          for (final l in centimesMars) enLigne(l),
          enLigne(totauxCentimesMars),
        ]);
      },
    );

    for (final (page, cle, titre) in [
      (
        PageComptable.planComptable,
        'exporter-pdf-plan',
        'Plan Comptable SYSCOHADA',
      ),
      (PageComptable.journal, 'exporter-pdf-journal', 'Journal Comptable'),
    ]) {
      testWidgets(
        '⚠️⚠️ F0.88 : ${page.libelle} exporté « État au » la date du POSTE (horloge injectée)',
        (tester) async {
          await jeu();
          await afficher(tester, page);
          await exporter(tester, cle);

          expect(editions.single.$1.titre, titre);
          // `maintenantFixe` = 20/03/2026 ; l'horloge réelle donnerait une autre date.
          expect(editions.single.$1.sousTitre, 'État au 20/03/2026');
        },
      );
    }

    testWidgets(
      '⚠️⚠️ F0.88 : écart de -0,40 — « -0,40 » rouge à l’écran, bandeau, même écart au PDF',
      (tester) async {
        // 44 écritures « 531 D 100 / 701 C 100,009 » le 05/03/2026 : chacune déséquilibrée de
        // 0,009 (< 0,01 : PAS « incomplète »). À LA MAIN, en millièmes : 44 × 100 009 = 4 400 396
        // → 440 039,6 centimes → 440 040 (4 400,40) au crédit ; 440 000 (4 400) au débit.
        // Écart = débits − crédits = −40 centimes → « -0,40 ».
        await compte('531', 'Caisse', 5);
        await compte('701', 'Ventes', 7);
        for (var i = 101; i <= 144; i++) {
          await entete('x$i', DateTime(2026, 3, 5), 'OD-X$i — Arrondi');
          await ligne('x${i}d', 'x$i', '531', debit: 100);
          await ligne('x${i}c', 'x$i', '701', credit: 100.009);
        }
        expect((44 * 100009 + 5) ~/ 10, 440040);
        await afficher(tester, PageComptable.balance);

        Finder carte(String texte) => find.descendant(
          of: find.byKey(const Key('kpi-balance-ecart')),
          matching: find.text(texte),
        );
        expect(carte('-0,40'), findsOneWidget);
        expect(carte('0'), findsNothing);
        expect(carte('-0'), findsNothing);
        expect(
          tester
              .widget<CarteKpi>(find.byKey(const Key('kpi-balance-ecart')))
              .couleurValeur,
          AgriColors.errorDeep,
        );
        expect(
          find.byKey(const Key('bal-alerte-desequilibre')),
          findsOneWidget,
        );
        // Les autres montants gardent l'arrondi au franc.
        expect(
          find.descendant(
            of: find.byKey(const Key('kpi-balance-credits')),
            matching: find.text('4 400'),
          ),
          findsOneWidget,
        );

        await exporter(tester, 'exporter-pdf-balance');
        final doc = editions.single.$1;
        expect(
          doc.noteDePied,
          'Balance déséquilibrée — écart de -0,40 FCFA. Une anomalie de saisie doit être '
          'corrigée avant toute clôture.',
        );
        lireDansLOrdre(await motsImprimes(tester, doc), [
          'écart de -0,40 FCFA.',
        ]);
      },
    );

    testWidgets(
      '⚠️⚠️ P2 journal exporté depuis l’écran : deux incomplètes, « 2 écriture(s) » imprimé',
      (tester) async {
        await jeu();
        await ecritureIncomplete();
        await secondeEcritureIncomplete();
        await afficher(tester, PageComptable.journal);
        await exporter(tester, 'exporter-pdf-journal');

        final doc = editions.single.$1;
        expect(doc.noteDePied, noteDeuxIncompletes);
        lireDansLOrdre(await motsImprimes(tester, doc), [noteDeuxIncompletes]);
      },
    );
  });
}
