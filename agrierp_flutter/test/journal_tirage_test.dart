import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.84 — LE JOURNAL DU POSTE SE CORRIGE (item 9, ticket T1 ; serveur : 15.28).
///
/// ⚠️⚠️ Avant ce ticket, la fusion des écritures ne supprimait jamais rien : une écriture ARCHIVÉE sur
/// le web restait au poste pour toujours, et une écriture MODIFIÉE (lignes supprimées puis recréées
/// avec de nouveaux identifiants côté serveur) gardait ses ANCIENNES lignes en plus des nouvelles.
/// Journal, Grand Livre et Balance du poste comptaient alors ce que le web ne compte plus — sans
/// aucune erreur.
///
/// Contrat testé : le tirage sert `accounting_entry_ids` (TOUTES les écritures actives, sans filtre
/// `since`) ; une écriture servie arrive avec TOUTES ses lignes courantes. Le serveur ci-dessous est
/// un MODÈLE écrit dans le test, indépendant du poste : ses totaux servent de vérité, jamais ceux du
/// dépôt de l'écran.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Un VRAI UUID (8-4-4-4-12 hexadécimal) déduit d'une graine lisible (jusqu'à 16 caractères).
/// ⚠️ F0.84-bis : l'ancienne version rendait une chaîne de 36 caractères SANS tirets — que
/// l'absorbeur acceptait parce qu'il ne contrôlait que la longueur.
String _uuid(String graine) {
  final hex = graine.codeUnits
      .map((c) => c.toRadixString(16).padLeft(2, '0'))
      .join()
      .padRight(32, '0')
      .substring(0, 32);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class _Ligne {
  _Ligne(this.id, this.compte, this.debit, this.credit);
  final String id;
  final String compte;
  final double debit;
  final double credit;
}

class _Ecriture {
  _Ecriture(this.id, this.date, this.reference, this.lignes);
  final String id;
  String date;
  String reference;
  bool active = true;
  bool verrouillee = false;
  int tic = 0;

  /// Instant de CRÉATION (ticket 15.29) : posé à l'ajout, jamais modifié ensuite.
  String creeLe = '';
  List<_Ligne> lignes;
}

/// Serveur MODÈLE : applique le contrat du ticket 15.28 et garde sa propre vérité.
class _ServeurJournal extends Interceptor {
  final ecritures = <String, _Ecriture>{};
  int horloge = 0;
  final demandes = <String?>[];

  /// Personnalisation d'un tirage (cas d'un serveur défaillant ou ancien).
  void Function(Map<String, dynamic> corps)? deformation;

  static final _origine = DateTime.utc(2026, 10, 10, 12);

  String get _heure =>
      _origine.add(Duration(seconds: horloge)).toIso8601String();

  /// Faux = serveur ANTÉRIEUR au ticket 15.29 : la clé `created_at` n'est pas servie.
  bool servirDateCreation = true;

  void ajouter(_Ecriture e) {
    e.tic = ++horloge;
    e.creeLe = _heure;
    ecritures[e.id] = e;
  }

  /// `updateManual` : lignes recréées (nouveaux ids), l'écriture change.
  void modifier(String id, List<_Ligne> nouvelles) {
    final e = ecritures[id]!;
    e.lignes = nouvelles;
    e.tic = ++horloge;
  }

  void archiver(String id) {
    final e = ecritures[id]!;
    e.active = false;
    e.tic = ++horloge;
  }

  void restaurer(String id) {
    final e = ecritures[id]!;
    e.active = true;
    e.tic = ++horloge;
  }

  void supprimerPhysiquement(String id) => ecritures.remove(id);

  /// Vérité INDÉPENDANTE : somme (débit, crédit) par compte des écritures actives.
  Map<String, (double, double)> verite() {
    final t = <String, (double, double)>{};
    for (final e in ecritures.values.where((e) => e.active)) {
      for (final l in e.lignes) {
        final avant = t[l.compte] ?? (0.0, 0.0);
        t[l.compte] = (avant.$1 + l.debit, avant.$2 + l.credit);
      }
    }
    return t;
  }

  Set<String> get identifiantsActifs => {
    for (final e in ecritures.values.where((e) => e.active)) e.id,
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{},
        ),
      );
      return;
    }

    final since = options.queryParameters['since'] as String?;
    demandes.add(since);
    final seuil = since == null
        ? -1
        : DateTime.parse(since).difference(_origine).inSeconds;

    final servies = ecritures.values
        .where((e) => e.active && e.tic > seuil)
        .toList();

    final corps = <String, dynamic>{
      'server_time': _heure,
      'accounting_entries': <Map<String, dynamic>>[
        for (final e in servies)
          {
            'id': e.id,
            'fiscal_year_id': _uuid('exercice'),
            'entry_date': e.date,
            'reference': e.reference,
            'source_type': 'manual',
            'is_locked': e.verrouillee,
            if (servirDateCreation) 'created_at': e.creeLe,
          },
      ],
      'accounting_entry_lines': <Map<String, dynamic>>[
        for (final e in servies)
          for (final l in e.lignes)
            {
              'id': l.id,
              'entry_id': e.id,
              'account_id': l.compte,
              'cost_center_id': null,
              // Le serveur sert les décimaux en CHAÎNES ('10000.00').
              'debit': l.debit.toStringAsFixed(2),
              'credit': l.credit.toStringAsFixed(2),
            },
      ],
      'accounting_entry_ids': (identifiantsActifs.toList()..sort()),
    };
    deformation?.call(corps);

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: corps,
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late _ServeurJournal serveur;
  late ComptabiliteRepository depot;

  final caisse = _uuid('c531');
  final ventes = _uuid('c701');
  final banque = _uuid('c521');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _ServeurJournal();
    depot = ComptabiliteRepository(database: db);

    for (final (cle, code, libelle, classe) in [
      ('c531', '531', 'Caisse', 5),
      ('c701', '701', 'Ventes', 7),
      ('c521', '521', 'Banque', 5),
    ]) {
      await db
          .into(db.chartOfAccounts)
          .insert(
            ChartOfAccountsCompanion.insert(
              id: _uuid(cle),
              code: code,
              label: libelle,
              accountClass: Value(classe),
            ),
          );
    }
  });

  tearDown(() async => db.close());

  SyncEngine moteur({Connectivity? connectivite}) {
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'));
    client.interceptors.add(serveur);
    return SyncEngine(
      database: db,
      client: client,
      deviceId: 'poste-test',
      connectivity: connectivite ?? _Connectivite(),
    );
  }

  _Ecriture od(String cle, double montant, {String? debit, String? credit}) =>
      _Ecriture(_uuid(cle), '2026-10-05', 'OD-$cle', [
        _Ligne(_uuid('${cle}ld'), debit ?? caisse, montant, 0),
        _Ligne(_uuid('${cle}lc'), credit ?? ventes, 0, montant),
      ]);

  /// Ce que le poste affiche, recalculé par un chemin différent du dépôt de l'écran :
  /// lecture directe des tables, sans passer par `ComptabiliteRepository`.
  Future<Map<String, (double, double)>> totauxDuPoste() async {
    final actives = {
      for (final e in await db.select(db.accountingEntries).get()) e.id,
    };
    final t = <String, (double, double)>{};
    for (final l in await db.select(db.accountingEntryLines).get()) {
      // Une ligne dont l'écriture n'existe plus ne compterait pour personne dans le Journal :
      // on la compte QUAND MÊME ici, pour qu'une ligne orpheline soit visible comme un écart.
      final avant = t[l.accountId] ?? (0.0, 0.0);
      t[l.accountId] = (avant.$1 + l.debit, avant.$2 + l.credit);
      if (!actives.contains(l.entryId)) {
        t['orpheline'] = (1.0, 0.0);
      }
    }
    return t;
  }

  void egalite(
    Map<String, (double, double)> poste,
    Map<String, (double, double)> verite,
  ) {
    expect(poste.keys.toSet(), verite.keys.toSet());
    for (final k in verite.keys) {
      expect(poste[k]!.$1, closeTo(verite[k]!.$1, 0.001), reason: 'débit $k');
      expect(poste[k]!.$2, closeTo(verite[k]!.$2, 0.001), reason: 'crédit $k');
    }
  }

  group('écriture archivée sur le web', () {
    test('⚠️⚠️ le poste retire l écriture archivée et ses lignes', () async {
      serveur.ajouter(od('a', 1000));
      serveur.ajouter(od('b', 2000));
      await moteur().synchroniser();
      expect(await db.select(db.accountingEntries).get(), hasLength(2));

      serveur.archiver(_uuid('b'));
      await moteur().synchroniser();

      final restantes = await db.select(db.accountingEntries).get();
      expect(restantes.map((e) => e.id), [_uuid('a')]);
      expect(await db.select(db.accountingEntryLines).get(), hasLength(2));
      egalite(await totauxDuPoste(), serveur.verite());
    });

    test(
      'Journal, Grand Livre et Balance suivent le serveur après archivage',
      () async {
        serveur.ajouter(od('a', 1000));
        serveur.ajouter(od('b', 2000, debit: banque));
        await moteur().synchroniser();
        serveur.archiver(_uuid('b'));
        await moteur().synchroniser();

        final d = await depot.charger();
        final verite = serveur.verite();

        // Journal : une seule pièce, 1 000 de chaque côté.
        expect(d.journal, hasLength(1));
        expect(d.totalDebit, 1000);
        expect(d.totalCredit, 1000);
        // Grand Livre : la banque n'a plus aucun mouvement ; la caisse un seul.
        expect(d.grandLivre(banque), isEmpty);
        expect(d.grandLivre(caisse).single.soldeProgressif, 1000);
        // Balance : exactement les comptes et totaux du serveur.
        // Ticket F0.86 : la balance a une période ; une période qui englobe tout le journal met
        // chaque montant en MOUVEMENTS (ouverture vide), comparables aux cumuls du serveur.
        final balance = {
          for (final l
              in d
                  .balanceGenerale(
                    debut: DateTime(2000, 1, 1),
                    fin: DateTime(2100, 12, 31),
                  )
                  .lignes)
            l.compteId: (l.mouvementsDebit, l.mouvementsCredit),
        };
        egalite(balance, verite);
        expect(d.ecrituresIncompletes, 0);
      },
    );

    test(
      '⚠️ sans écriture active, le poste se vide (réinitialisation)',
      () async {
        serveur.ajouter(od('a', 1000));
        await moteur().synchroniser();

        serveur.supprimerPhysiquement(_uuid('a'));
        await moteur()
            .synchroniser(); // 1re annonce vide : repoussée (F0.84-bis)
        await moteur()
            .synchroniser(); // 2e annonce vide : confirmée, le journal se vide

        expect(await db.select(db.accountingEntries).get(), isEmpty);
        expect(await db.select(db.accountingEntryLines).get(), isEmpty);
        // Le plan comptable, lui, n'est pas touché.
        expect(await db.select(db.chartOfAccounts).get(), hasLength(3));
      },
    );

    test('une écriture restaurée redescend avec ses lignes', () async {
      serveur.ajouter(od('a', 1000));
      serveur.ajouter(od('b', 2000));
      await moteur().synchroniser();
      serveur.archiver(_uuid('b'));
      await moteur().synchroniser();
      expect(await db.select(db.accountingEntries).get(), hasLength(1));

      serveur.restaurer(_uuid('b'));
      await moteur().synchroniser();

      expect(await db.select(db.accountingEntries).get(), hasLength(2));
      egalite(await totauxDuPoste(), serveur.verite());
    });
  });

  group('écriture modifiée sur le web (lignes recréées)', () {
    test(
      '⚠️⚠️ les anciennes lignes disparaissent et les montants ne se doublent pas',
      () async {
        serveur.ajouter(od('a', 10000));
        await moteur().synchroniser();

        // Même date, même référence ; autres comptes et autre montant, nouvelles lignes.
        serveur.modifier(_uuid('a'), [
          _Ligne(_uuid('n1'), banque, 4000, 0),
          _Ligne(_uuid('n2'), ventes, 0, 4000),
        ]);
        await moteur().synchroniser();

        final lignes = await db.select(db.accountingEntryLines).get();
        expect(lignes.map((l) => l.id).toSet(), {_uuid('n1'), _uuid('n2')});
        egalite(await totauxDuPoste(), serveur.verite());

        final d = await depot.charger();
        expect(d.totalDebit, 4000, reason: 'pas 14 000 : montants non doublés');
        expect(d.totalCredit, 4000);
        expect(d.grandLivre(caisse), isEmpty);
        expect(d.grandLivre(banque).single.soldeProgressif, 4000);
        expect(d.ecrituresIncompletes, 0);
      },
    );

    test(
      'la modification d une écriture ne touche pas les lignes des autres',
      () async {
        serveur.ajouter(od('a', 10000));
        serveur.ajouter(od('b', 500));
        await moteur().synchroniser();

        serveur.modifier(_uuid('a'), [
          _Ligne(_uuid('n1'), caisse, 7000, 0),
          _Ligne(_uuid('n2'), ventes, 0, 7000),
        ]);
        await moteur().synchroniser();

        egalite(await totauxDuPoste(), serveur.verite());
        final d = await depot.charger();
        expect(d.totalDebit, 7500);
      },
    );

    test('un tirage incrémental vide ne change rien', () async {
      serveur.ajouter(od('a', 10000));
      await moteur().synchroniser();
      final avant = await totauxDuPoste();

      await moteur().synchroniser();

      egalite(await totauxDuPoste(), avant);
      expect(await db.select(db.accountingEntries).get(), hasLength(1));
    });
  });

  group('tirage incrémental (since)', () {
    test(
      '⚠️ le second tirage envoie since, le premier n en envoie pas',
      () async {
        serveur.ajouter(od('a', 1000));
        await moteur().synchroniser();
        await moteur().synchroniser();

        expect(serveur.demandes.first, isNull);
        expect(serveur.demandes.last, isNotNull);
      },
    );

    test(
      '⚠️ l archivage est pris en compte sur un tirage incrémental (sans dépendre d un tirage complet)',
      () async {
        serveur.ajouter(od('a', 1000));
        serveur.ajouter(od('b', 2000));
        await moteur().synchroniser();

        serveur.archiver(_uuid('a'));
        await moteur().synchroniser();

        expect(serveur.demandes.last, isNotNull);
        final e = await db.select(db.accountingEntries).get();
        expect(e.map((x) => x.id), [_uuid('b')]);
      },
    );
  });

  group('serveur sans la liste des écritures actives (ancien serveur)', () {
    test(
      '⚠️ pas de purge, pas d erreur ; le remplacement des lignes reste appliqué',
      () async {
        serveur.ajouter(od('a', 1000));
        serveur.ajouter(od('b', 2000));
        await moteur().synchroniser();

        serveur.deformation = (c) => c.remove('accounting_entry_ids');
        serveur.archiver(_uuid('b'));
        serveur.modifier(_uuid('a'), [
          _Ligne(_uuid('n1'), caisse, 300, 0),
          _Ligne(_uuid('n2'), ventes, 0, 300),
        ]);
        await moteur().synchroniser();

        // Sans la liste, rien ne permet de savoir que `b` est archivée : elle reste (limite documentée).
        expect(await db.select(db.accountingEntries).get(), hasLength(2));
        // Mais les lignes de `a` sont bien remplacées, pas doublées.
        final lignesA = await (db.select(
          db.accountingEntryLines,
        )..where((l) => l.entryId.equals(_uuid('a')))).get();
        expect(lignesA.map((l) => l.id).toSet(), {_uuid('n1'), _uuid('n2')});
      },
    );
  });

  group('absorbeur strict', () {
    Future<void> refus(
      String raison,
      void Function(Map<String, dynamic> corps) casse,
    ) async {
      serveur.ajouter(od('a', 1000));
      await moteur().synchroniser();
      final avant = await totauxDuPoste();
      final curseurAvant = (await db.etatDeSynchronisation())?.lastPulledAt;

      serveur.ajouter(od('b', 2000));
      serveur.deformation = casse;
      await expectLater(
        moteur().synchroniser(),
        throwsA(isA<FormatException>()),
        reason: raison,
      );

      // Rien n'est appliqué, pas même la partie valide du tirage, et le curseur n'avance pas.
      egalite(await totauxDuPoste(), avant);
      expect(await db.select(db.accountingEntries).get(), hasLength(1));
      expect((await db.etatDeSynchronisation())?.lastPulledAt, curseurAvant);
    }

    test(
      '⚠️ liste des actives qui n est pas une liste d identifiants',
      () async {
        await refus('ids invalides', (c) => c['accounting_entry_ids'] = [1, 2]);
      },
    );

    test('⚠️ liste des actives qui n est pas une liste', () async {
      await refus('ids non liste', (c) => c['accounting_entry_ids'] = 'oups');
    });

    test('⚠️ écriture servie mais absente de la liste des actives', () async {
      await refus('incohérence', (c) {
        c['accounting_entry_ids'] = [_uuid('a')];
      });
    });

    test(
      '⚠️ date d écriture illisible : refusée, jamais remplacée par aujourd hui',
      () async {
        await refus('date', (c) {
          (c['accounting_entries'] as List).last['entry_date'] = 'pas-une-date';
        });
      },
    );

    test('⚠️ identifiant d écriture invalide', () async {
      await refus('id', (c) {
        // Payload COHÉRENT par ailleurs (lignes et liste des actives suivent) : seul l'identifiant
        // n'est pas un UUID de 36 caractères.
        final b = _uuid('b');
        (c['accounting_entries'] as List).last['id'] = 'court';
        for (final l in c['accounting_entry_lines'] as List) {
          if (l['entry_id'] == b) l['entry_id'] = 'court';
        }
        c['accounting_entry_ids'] = [
          for (final i in c['accounting_entry_ids'] as List)
            i == b ? 'court' : i,
        ];
      });
    });

    test('⚠️ même écriture servie deux fois', () async {
      await refus('doublon', (c) {
        final l = c['accounting_entries'] as List;
        l.add(Map<String, dynamic>.from(l.last as Map));
      });
    });

    test(
      '⚠️ ligne rattachée à une écriture que le tirage ne sert pas',
      () async {
        await refus('orpheline', (c) {
          (c['accounting_entry_lines'] as List).add({
            'id': _uuid('orph'),
            'entry_id': _uuid('inconnue'),
            'account_id': caisse,
            'cost_center_id': null,
            'debit': '1.00',
            'credit': '0.00',
          });
        });
      },
    );

    test('⚠️ montant illisible : refusé, jamais lu comme 0', () async {
      await refus('montant', (c) {
        (c['accounting_entry_lines'] as List).last['debit'] = 'abc';
      });
    });

    test('⚠️ montant absent : refusé, jamais lu comme 0', () async {
      await refus('montant absent', (c) {
        (c['accounting_entry_lines'] as List).last['credit'] = null;
      });
    });

    test('⚠️ ligne dont l identifiant est en double', () async {
      await refus('ligne doublon', (c) {
        final l = c['accounting_entry_lines'] as List;
        l.add(Map<String, dynamic>.from(l.last as Map));
      });
    });
  });

  group('un tirage réellement incomplet reste détecté', () {
    test(
      '⚠️⚠️ une écriture servie avec une seule de ses lignes est dite incomplète',
      () async {
        serveur.ajouter(od('a', 1000));
        serveur.deformation = (c) {
          (c['accounting_entry_lines'] as List).removeLast();
        };
        await moteur().synchroniser();

        final d = await depot.charger();
        expect(d.ecrituresIncompletes, 1);
        expect(d.journal.single.equilibree, isFalse);
      },
    );
  });

  group('volume et lignes orphelines', () {
    test(
      '⚠️ 1 200 écritures dont 700 archivées : 500 restent (découpage des suppressions)',
      () async {
        for (var i = 0; i < 1200; i++) {
          serveur.ajouter(od('e${i.toString().padLeft(4, '0')}', 10.0 + i));
        }
        await moteur().synchroniser();
        expect(await db.select(db.accountingEntries).get(), hasLength(1200));

        for (var i = 0; i < 700; i++) {
          serveur.archiver(_uuid('e${i.toString().padLeft(4, '0')}'));
        }
        await moteur().synchroniser();

        expect(await db.select(db.accountingEntries).get(), hasLength(500));
        expect(await db.select(db.accountingEntryLines).get(), hasLength(1000));
        egalite(await totauxDuPoste(), serveur.verite());
      },
    );

    test(
      '⚠️ une ligne orpheline déjà au poste est retirée par un tirage complet des actives',
      () async {
        serveur.ajouter(od('a', 1000));
        await moteur().synchroniser();
        await db
            .into(db.accountingEntryLines)
            .insert(
              AccountingEntryLinesCompanion.insert(
                id: _uuid('orph'),
                entryId: _uuid('disparue'),
                accountId: caisse,
                debit: const Value(999),
              ),
            );

        await moteur().synchroniser();

        final lignes = await db.select(db.accountingEntryLines).get();
        expect(lignes.map((l) => l.id), isNot(contains(_uuid('orph'))));
        egalite(await totauxDuPoste(), serveur.verite());
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  TICKET F0.84-bis — suites de l'audit indépendant de F0.84 / 15.28
  // ═══════════════════════════════════════════════════════════════════════════

  group('F0.84-bis — l en-tête d une écriture suit le serveur', () {
    test(
      '⚠️ date, référence et verrouillage sont mis à jour au poste',
      () async {
        serveur.ajouter(od('a', 1000));
        await moteur().synchroniser();

        final e = serveur.ecritures[_uuid('a')]!;
        e.date = '2026-11-15';
        e.reference = 'OD-2026-0042 corrigée';
        e.verrouillee = true;
        e.tic = ++serveur.horloge;
        await moteur().synchroniser();

        final l = (await db.select(db.accountingEntries).get()).single;
        expect(l.reference, 'OD-2026-0042 corrigée');
        expect(l.isLocked, isTrue);
        expect(l.entryDate.month, 11);
        expect(l.entryDate.day, 15);
      },
    );
  });

  group('F0.84-bis — le tirage est atomique', () {
    test(
      '⚠️⚠️ un tirage qui échoue à mi-chemin ne laisse aucun état partiel',
      () async {
        serveur.ajouter(od('a', 10));
        await moteur().synchroniser();
        final curseur = (await db.etatDeSynchronisation())?.lastPulledAt;

        // `z` est servie avec une ligne dont l'identifiant est DÉJÀ celui d'une ligne de `a` : rien
        // ne le trahit avant l'écriture (le poste ne connaît pas sa base à la validation).
        serveur.ajouter(
          _Ecriture(_uuid('z'), '2026-10-02', 'OD-z', [
            _Ligne(_uuid('ald'), caisse, 99, 0),
            _Ligne(_uuid('zlc'), ventes, 0, 99),
          ]),
        );
        await expectLater(moteur().synchroniser(), throwsA(anything));

        expect(
          (await db.select(db.accountingEntries).get()).map((e) => e.id),
          [_uuid('a')],
          reason: 'l en-tête de `z`, inséré avant l échec, doit être annulé',
        );
        expect(await db.select(db.accountingEntryLines).get(), hasLength(2));
        expect((await db.etatDeSynchronisation())?.lastPulledAt, curseur);
      },
    );
  });

  group(
    'F0.84-bis — volume : plus de variables qu une requête SQLite n en accepte',
    () {
      test(
        '⚠️⚠️ purge de 33 000 écritures (limite de variables ~32 766)',
        () async {
          String id(int i) =>
              '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}';
          await db.batch((b) {
            b.insertAll(db.accountingEntries, [
              for (var i = 0; i < 33000; i++)
                AccountingEntriesCompanion.insert(
                  id: id(i),
                  entryDate: DateTime(2026, 1, 1),
                ),
            ]);
            b.insertAll(db.accountingEntryLines, [
              for (var i = 0; i < 33000; i++)
                AccountingEntryLinesCompanion.insert(
                  id: '11111111-1111-4111-8111-${i.toRadixString(16).padLeft(12, '0')}',
                  entryId: id(i),
                  accountId: caisse,
                  debit: const Value(1),
                ),
            ]);
          });
          // Le serveur ne connaît qu'une écriture active : les 33 000 autres doivent partir.
          serveur.ajouter(od('a', 1000));

          await moteur().synchroniser();

          expect(
            (await db.select(db.accountingEntries).get()).map((e) => e.id),
            [_uuid('a')],
          );
          expect(await db.select(db.accountingEntryLines).get(), hasLength(2));
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    },
  );

  group('F0.84-bis — le poste exploite accounting_entry_ids', () {
    test(
      '⚠️⚠️ une écriture active absente du poste (créée entre la requête et server_time) est redemandée UNE fois, sans since',
      () async {
        serveur.ajouter(od('a', 1000));
        await moteur().synchroniser();
        // `r` est active mais son horodatage précède le curseur : le tirage incrémental ne la sert jamais.
        final retardataire = od('r', 500);
        serveur.ajouter(retardataire);
        retardataire.tic = 0;
        serveur.demandes.clear();

        final r = await moteur().synchroniser();

        expect(serveur.demandes, hasLength(2), reason: 'une seule relance');
        expect(serveur.demandes.first, isNotNull);
        expect(serveur.demandes.last, isNull, reason: 'relance SANS since');
        expect(r.avertissements, isEmpty);
        egalite(await totauxDuPoste(), serveur.verite());
        expect((await depot.charger()).ecrituresIncompletes, 0);

        // Réparé : le tirage suivant est de nouveau un tirage simple.
        serveur.demandes.clear();
        await moteur().synchroniser();
        expect(serveur.demandes, hasLength(1));
        expect(serveur.demandes.single, isNotNull);
      },
    );

    test(
      '⚠️⚠️ une écriture annoncée mais jamais servie : relance bornée, journal dit INCOMPLET, curseur avancé',
      () async {
        serveur.ajouter(od('a', 1000));
        await moteur().synchroniser();
        final curseurAvant = (await db.etatDeSynchronisation())?.lastPulledAt;
        serveur.deformation = (c) => c['accounting_entry_ids'] = [
          ...(c['accounting_entry_ids'] as List),
          _uuid('fantome'),
        ];
        serveur.demandes.clear();
        serveur.horloge += 5; // le temps passe sur le serveur

        final r = await moteur().synchroniser();

        expect(serveur.demandes, hasLength(2), reason: 'jamais de boucle');
        expect(
          r.avertissements.join(' '),
          allOf(contains('incomplet'), contains('1')),
        );
        expect(await db.select(db.accountingEntries).get(), hasLength(1));
        final curseur = (await db.etatDeSynchronisation())?.lastPulledAt;
        expect(curseur, isNot(curseurAvant), reason: 'le curseur avance');

        // Tant que le fantôme persiste, chaque synchronisation redemande tout le journal — deux
        // requêtes, jamais plus — puis, le serveur redevenu cohérent, tout rentre dans l'ordre.
        serveur.demandes.clear();
        final r2 = await moteur().synchroniser();
        expect(serveur.demandes, hasLength(2));
        expect(serveur.demandes.first, isNull);
        expect(r2.avertissements, isNotEmpty);

        serveur.deformation = null;
        serveur.demandes.clear();
        final r3 = await moteur().synchroniser();
        expect(serveur.demandes, hasLength(1));
        expect(
          serveur.demandes.single,
          isNull,
          reason: 'dernier tirage complet',
        );
        expect(r3.avertissements, isEmpty);

        serveur.demandes.clear();
        await moteur().synchroniser();
        expect(
          serveur.demandes.single,
          isNotNull,
          reason: 'retour au tirage simple',
        );
      },
    );
  });

  group('F0.84-bis — liste des actives vide : jamais purgée sur un seul tirage', () {
    Future<void> annoncerVide() async {
      serveur.deformation = (c) {
        c['accounting_entry_ids'] = <String>[];
        c['accounting_entries'] = <Map<String, dynamic>>[];
        c['accounting_entry_lines'] = <Map<String, dynamic>>[];
      };
    }

    test(
      '⚠️⚠️ erreur serveur (base vide) : le journal local survit et se retrouve ensuite',
      () async {
        serveur.ajouter(od('a', 1000));
        serveur.ajouter(od('b', 2000));
        await moteur().synchroniser();

        await annoncerVide();
        final r = await moteur().synchroniser();
        expect(await db.select(db.accountingEntries).get(), hasLength(2));
        expect(await db.select(db.accountingEntryLines).get(), hasLength(4));
        expect(r.avertissements.join(' '), contains('vide'));

        // Le serveur redevient normal : rien n'a été perdu, aucun avertissement.
        serveur.deformation = null;
        final r2 = await moteur().synchroniser();
        expect(await db.select(db.accountingEntries).get(), hasLength(2));
        expect(r2.avertissements, isEmpty);
        egalite(await totauxDuPoste(), serveur.verite());

        // L'annonce a été OUBLIÉE : une nouvelle annonce vide doit de nouveau être confirmée.
        await annoncerVide();
        final r3 = await moteur().synchroniser();
        expect(await db.select(db.accountingEntries).get(), hasLength(2));
        expect(r3.avertissements, isNotEmpty);
      },
    );

    test(
      '⚠️⚠️ vraie réinitialisation : confirmée par le tirage suivant, puis le journal est vidé',
      () async {
        serveur.ajouter(od('a', 1000));
        serveur.ajouter(od('b', 2000));
        await moteur().synchroniser();
        serveur.supprimerPhysiquement(_uuid('a'));
        serveur.supprimerPhysiquement(_uuid('b'));

        final r1 = await moteur().synchroniser();
        expect(await db.select(db.accountingEntries).get(), hasLength(2));
        expect(r1.avertissements, isNotEmpty);

        final r2 = await moteur().synchroniser();
        expect(await db.select(db.accountingEntries).get(), isEmpty);
        expect(await db.select(db.accountingEntryLines).get(), isEmpty);
        expect(r2.avertissements, isEmpty);
        expect(await db.select(db.chartOfAccounts).get(), hasLength(3));
      },
    );

    test(
      'un poste sans écriture n a rien à purger : aucun avertissement',
      () async {
        final r = await moteur().synchroniser();
        expect(r.avertissements, isEmpty);
        final r2 = await moteur().synchroniser();
        expect(r2.avertissements, isEmpty);
      },
    );
  });

  group('F0.84-bis — poste déjà corrompu avant la mise à jour', () {
    Future<void> poserPosteDouble() async {
      // `e1` ancienne, non retouchée depuis : ses lignes sont DOUBLÉES (restes d'avant F0.84), et le
      // curseur est déjà avancé — le tirage incrémental ne la servira jamais.
      await db
          .into(db.accountingEntries)
          .insert(
            AccountingEntriesCompanion.insert(
              id: _uuid('e1'),
              entryDate: DateTime(2026, 10, 1),
            ),
          );
      for (final (i, d, c) in [
        ('a', 10.0, 0.0),
        ('b', 0.0, 10.0),
        ('c', 10.0, 0.0),
        ('d', 0.0, 10.0),
      ]) {
        await db
            .into(db.accountingEntryLines)
            .insert(
              AccountingEntryLinesCompanion.insert(
                id: _uuid('l$i'),
                entryId: _uuid('e1'),
                accountId: caisse,
                debit: Value(d),
                credit: Value(c),
              ),
            );
      }
      serveur.ajouter(
        _Ecriture(_uuid('e1'), '2026-10-01', 'R1', [
          _Ligne(_uuid('n1'), caisse, 10, 0),
          _Ligne(_uuid('n2'), ventes, 0, 10),
        ]),
      );
      await db.noterEtatDeSynchronisation(
        tire: DateTime.utc(2026, 10, 10, 12, 0, 30),
      );
    }

    test(
      '⚠️⚠️ le premier tirage après la mise à jour redemande tout le journal et guérit les lignes doublées',
      () async {
        await poserPosteDouble();

        await moteur().synchroniser();

        expect(
          serveur.demandes.first,
          isNull,
          reason: 'sans since, malgré le curseur',
        );
        final lignes = await db.select(db.accountingEntryLines).get();
        expect(lignes.map((l) => l.id).toSet(), {_uuid('n1'), _uuid('n2')});
        egalite(await totauxDuPoste(), serveur.verite());
      },
    );

    test('⚠️ la resynchronisation ne se rejoue pas', () async {
      await poserPosteDouble();
      await moteur().synchroniser();
      serveur.demandes.clear();

      // Un nouveau défaut introduit après coup n'est PAS « guéri » par un second tirage complet.
      await db
          .into(db.accountingEntryLines)
          .insert(
            AccountingEntryLinesCompanion.insert(
              id: _uuid('extra'),
              entryId: _uuid('e1'),
              accountId: caisse,
              debit: const Value(1),
            ),
          );
      await moteur().synchroniser();

      expect(
        serveur.demandes.single,
        isNotNull,
        reason: 'tirage simple, avec since',
      );
      expect(await db.select(db.accountingEntryLines).get(), hasLength(3));
    });
  });

  group('F0.84-bis — rigueur de l absorbeur', () {
    Future<void> refus(void Function(Map<String, dynamic> corps) casse) async {
      serveur.ajouter(od('a', 1000));
      await moteur().synchroniser();
      final avant = await totauxDuPoste();
      serveur.ajouter(od('b', 2000));
      serveur.deformation = casse;
      await expectLater(
        moteur().synchroniser(),
        throwsA(isA<FormatException>()),
      );
      egalite(await totauxDuPoste(), avant);
      expect(await db.select(db.accountingEntries).get(), hasLength(1));
    }

    for (final valeur in ['NaN', 'Infinity', '-Infinity']) {
      test('⚠️ débit « $valeur » refusé', () async {
        await refus(
          (c) => (c['accounting_entry_lines'] as List).last['debit'] = valeur,
        );
      });
      test('⚠️ crédit « $valeur » refusé', () async {
        await refus(
          (c) => (c['accounting_entry_lines'] as List).last['credit'] = valeur,
        );
      });
    }

    final faux = 'x' * 36; // 36 caractères, mais pas un UUID
    test(
      '⚠️ identifiant d écriture de 36 caractères non UUID refusé',
      () async {
        await refus((c) {
          final b = _uuid('b');
          (c['accounting_entries'] as List).last['id'] = faux;
          for (final l in c['accounting_entry_lines'] as List) {
            if (l['entry_id'] == b) l['entry_id'] = faux;
          }
          c['accounting_entry_ids'] = [
            for (final i in c['accounting_entry_ids'] as List)
              i == b ? faux : i,
          ];
        });
      },
    );
    test('⚠️ identifiant de ligne non UUID refusé', () async {
      await refus(
        (c) => (c['accounting_entry_lines'] as List).last['id'] = faux,
      );
    });
    test('⚠️ identifiant de compte non UUID refusé', () async {
      await refus(
        (c) => (c['accounting_entry_lines'] as List).last['account_id'] = faux,
      );
    });
    test('⚠️ identifiant actif non UUID refusé', () async {
      await refus(
        (c) => c['accounting_entry_ids'] = [
          ...(c['accounting_entry_ids'] as List),
          faux,
        ],
      );
    });
  });

  group('aucune saisie locale détruite', () {
    test('⚠️⚠️ une saisie pending survit à la purge du journal', () async {
      await db
          .into(db.livestockLots)
          .insert(
            LivestockLotsCompanion.insert(
              id: '11111111-1111-4111-8111-111111111111',
              code: 'AVI-2026-01',
              speciesId: '22222222-2222-4222-8222-222222222222',
            ),
          );
      await db
          .into(db.livestockDailyEntries)
          .insert(
            LivestockDailyEntriesCompanion.insert(
              id: '33333333-3333-4333-8333-333333333333',
              deviceId: 'poste-test',
              updatedAt: DateTime(2026, 10, 9),
              lotId: '11111111-1111-4111-8111-111111111111',
              entryDate: DateTime(2026, 10, 9),
            ),
          );
      expect(await db.pendingCount(), 1);

      serveur.ajouter(od('a', 1000));
      await moteur().synchroniser();
      serveur.supprimerPhysiquement(_uuid('a'));

      // Hors ligne : aucune absorption, la saisie reste en file.
      await moteur(connectivite: _ConnectiviteHorsLigne()).synchroniser();
      expect(await db.pendingCount(), 1);

      // En ligne : le journal se vide, la saisie `pending` n'est ni détruite ni marquée envoyée à tort
      // (le faux serveur répond {} à l'envoi, sans acquittement).
      await moteur()
          .synchroniser(); // 1re annonce vide : confirmée au tirage suivant (F0.84-bis)
      await moteur().synchroniser();
      expect(await db.select(db.accountingEntries).get(), isEmpty);
      expect(await db.pendingCount(), 1);
    });

    /// Preuve par construction que les écritures sont en LECTURE SEULE au poste : aucune écriture
    /// locale n'existe (pas de colonne `sync_status`), donc aucune ligne `pending`/`conflict` à
    /// protéger. Si un jour un dépôt les écrit, ce test casse et oblige à ajouter la protection.
    test(
      '⚠️⚠️ seul le moteur de synchronisation écrit dans les tables du journal',
      () {
        final ecrivains = <String>[];
        final motif = RegExp(
          r'\b(into|insert|insertAll|update|delete|replace)\(\s*[\w.]*accountingEntr(ies|yLines)\b',
        );
        final brut = RegExp(
          r'custom(Statement|Update|Insert)[^;]*accounting_entr',
        );
        for (final f in Directory('lib').listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          if (f.path.endsWith('.g.dart')) continue;
          final source = f.readAsStringSync();
          if (motif.hasMatch(source) || brut.hasMatch(source)) {
            ecrivains.add(f.path.replaceAll('\\', '/'));
          }
        }
        expect(ecrivains, ['lib/core/sync/sync_engine.dart']);

        final colonnes = RegExp(
          r'class AccountingEntr(ies|yLines) extends Table \{[^}]*\}',
        );
        final schema = File(
          'lib/core/database/app_database.dart',
        ).readAsStringSync();
        for (final m in colonnes.allMatches(schema)) {
          expect(m.group(0), isNot(contains('syncStatus')));
        }
      },
    );
  });

  // ── Ticket F0.85 — l'instant de CRÉATION des écritures (serveur : 15.29) ─────
  //
  // ⚠️⚠️ Le Grand Livre du serveur départage deux pièces du MÊME JOUR par `created_at`. Le poste ne le
  // recevait pas : il ne pouvait pas reproduire l'ordre, donc le solde progressif de chaque ligne.
  group('F0.85 — l instant de création des écritures', () {
    Future<Map<String, DateTime?>> creations() async => {
      for (final e in await db.select(db.accountingEntries).get())
        e.id: e.createdAt,
    };

    test(
      '⚠️⚠️ la date de création servie est rangée, à l instant près',
      () async {
        serveur.ajouter(od('a', 1000));
        serveur.ajouter(od('b', 2000));
        await moteur().synchroniser();

        final c = await creations();
        expect(
          c[_uuid('a')]!.toUtc(),
          DateTime.parse(serveur.ecritures[_uuid('a')]!.creeLe).toUtc(),
        );
        expect(
          c[_uuid('b')]!.toUtc(),
          DateTime.parse(serveur.ecritures[_uuid('b')]!.creeLe).toUtc(),
        );
        expect(c[_uuid('b')]!.isAfter(c[_uuid('a')]!), isTrue);
      },
    );

    test(
      '⚠️⚠️ deux pièces du même jour : l ordre de création, pas celui des identifiants',
      () async {
        // « zz » est créée AVANT « aa », mais son identifiant est plus grand.
        serveur.ajouter(od('zz', 1000));
        serveur.ajouter(od('aa', 500));
        await moteur().synchroniser();

        final d = await depot.charger();
        final livre = d.grandLivreCompte(caisse);

        expect(livre.mouvements.map((m) => m.ecriture.id), [
          _uuid('zz'),
          _uuid('aa'),
        ]);
        // Caisse débitrice : 1 000 puis 1 500.
        expect(livre.mouvements.map((m) => m.soldeProgressif), [1000, 1500]);
      },
    );

    test(
      '⚠️⚠️ un poste DÉJÀ à jour sans la date la rapporte à la mise à jour, une seule fois',
      () async {
        // Poste d'avant F0.85 : tirages faits (resynchronisation F0.84-bis écrite), dates inconnues.
        serveur.servirDateCreation = false;
        serveur.ajouter(od('a', 1000));
        await moteur().synchroniser();
        expect((await creations())[_uuid('a')], isNull);

        // Le serveur est mis à jour (15.29) : le prochain tirage est COMPLET malgré le curseur.
        serveur.servirDateCreation = true;
        serveur.demandes.clear();
        await moteur().synchroniser();

        expect(serveur.demandes.single, isNull, reason: 'sans since');
        expect((await creations())[_uuid('a')], isNotNull);

        // Et ensuite, de nouveau incrémental.
        serveur.demandes.clear();
        await moteur().synchroniser();
        expect(serveur.demandes.single, isNotNull);
      },
    );

    test(
      '⚠️ face à un serveur qui ne la sert pas, le tirage reste complet (la date serait perdue sinon)',
      () async {
        serveur.servirDateCreation = false;
        serveur.ajouter(od('a', 1000));
        await moteur().synchroniser();
        serveur.demandes.clear();

        await moteur().synchroniser();
        await moteur().synchroniser();

        expect(serveur.demandes, [null, null]);
        // Le journal, lui, reste juste.
        egalite(await totauxDuPoste(), serveur.verite());
        expect(await _reglage(db, SyncEngine.cleJournalResyncCreation), isNull);
      },
    );

    test(
      'une date de création déjà connue n est jamais effacée par un serveur qui ne la sert plus',
      () async {
        serveur.ajouter(od('a', 1000));
        await moteur().synchroniser();
        final connue = (await creations())[_uuid('a')];
        expect(connue, isNotNull);

        serveur.servirDateCreation = false;
        serveur.modifier(_uuid('a'), [
          _Ligne(_uuid('n1'), caisse, 1500, 0),
          _Ligne(_uuid('n2'), ventes, 0, 1500),
        ]);
        await moteur().synchroniser();

        expect((await creations())[_uuid('a')], connue);
      },
    );

    test('une modification ne change pas la date de création', () async {
      serveur.ajouter(od('a', 1000));
      await moteur().synchroniser();
      final avant = (await creations())[_uuid('a')];

      serveur.modifier(_uuid('a'), [
        _Ligne(_uuid('n1'), caisse, 1500, 0),
        _Ligne(_uuid('n2'), ventes, 0, 1500),
      ]);
      await moteur().synchroniser();

      expect((await creations())[_uuid('a')], avant);
    });

    test(
      '⚠️ une date de création illisible est refusée, rien n est appliqué',
      () async {
        serveur.ajouter(od('a', 1000));
        await moteur().synchroniser();
        serveur.ajouter(od('b', 2000));
        serveur.deformation = (c) =>
            (c['accounting_entries'] as List).last['created_at'] = 'hier soir';

        await expectLater(
          moteur().synchroniser(),
          throwsA(isA<FormatException>()),
        );
        expect(await db.select(db.accountingEntries).get(), hasLength(1));
      },
    );

    test(
      'une date de création explicitement nulle est admise (inconnue, pas refusée)',
      () async {
        serveur.ajouter(od('a', 1000));
        serveur.deformation = (c) =>
            (c['accounting_entries'] as List).single['created_at'] = null;

        await moteur().synchroniser();

        expect(await db.select(db.accountingEntries).get(), hasLength(1));
        expect((await creations())[_uuid('a')], isNull);
      },
    );

    test(
      '⚠️⚠️ une base v36 (sans created_at) est migrée : écritures gardées, date inconnue',
      () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        addTearDown(
          () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
        );
        final dossier = Directory.systemTemp.createTempSync('agrierp_v36_');
        final fichier = File('${dossier.path}${Platform.pathSeparator}v36.db');
        addTearDown(() {
          try {
            dossier.deleteSync(recursive: true);
          } catch (_) {}
        });

        final neuve = AppDatabase.forTesting(NativeDatabase(fichier));
        await neuve
            .into(neuve.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: _uuid('v36'),
                entryDate: DateTime(2026, 3, 1),
                reference: const Value('OD-2026-0001 — Ancienne'),
              ),
            );
        await neuve.close();

        var colonnesAvant = <String>[];
        final v36 = AppDatabase.forTesting(
          NativeDatabase(
            fichier,
            setup: (raw) {
              raw.execute(
                'ALTER TABLE accounting_entries DROP COLUMN created_at',
              );
              raw.execute('PRAGMA user_version = 36');
              colonnesAvant = [
                for (final l in raw.select(
                  'PRAGMA table_info(accounting_entries)',
                ))
                  l['name'] as String,
              ];
            },
          ),
        );
        final apres = await v36.select(v36.accountingEntries).getSingle();

        // ⚠️ `select()` de Drift lit par `SELECT *` : une colonne absente se lit « null » SANS erreur.
        // Seule une ÉCRITURE de la colonne prouve qu'elle existe après la migration.
        final instant = DateTime(2026, 3, 2, 10, 0, 5);
        await v36
            .into(v36.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: _uuid('v37'),
                entryDate: DateTime(2026, 3, 2),
                createdAt: Value(instant),
              ),
            );
        final nouvelle = await (v36.select(
          v36.accountingEntries,
        )..where((e) => e.id.equals(_uuid('v37')))).getSingle();
        await v36.close();

        expect(colonnesAvant, isNot(contains('created_at')));
        expect(apres.id, _uuid('v36'));
        expect(apres.reference, 'OD-2026-0001 — Ancienne');
        // Jamais « maintenant » : la date est rapportée par la resynchronisation unique.
        expect(apres.createdAt, isNull);
        expect(nouvelle.createdAt, instant);
      },
    );

    test(
      'le schéma est au moins en version 37 (colonne created_at ajoutée par la migration)',
      () async {
        // F0.95 : v38 (effectif par catégorie). La colonne date de la v37 ; le palier lui-même est
        // couvert par `migration_toutes_versions_test.dart` (historique version par version).
        expect(db.schemaVersion, greaterThanOrEqualTo(37));
        // La colonne existe et accepte NULL.
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: _uuid('s'),
                entryDate: DateTime(2026, 3, 1),
              ),
            );
        expect((await creations())[_uuid('s')], isNull);
      },
    );
  });
}

class _ConnectiviteHorsLigne implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.none,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Valeur d'un réglage du poste (table `app_settings`), ou `null`.
Future<String?> _reglage(AppDatabase db, String cle) async {
  final ligne = await (db.select(
    db.appSettings,
  )..where((t) => t.key.equals(cle))).getSingleOrNull();
  return ligne?.value;
}
