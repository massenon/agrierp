import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/administration/administration_repository.dart';
import 'package:agrierp/features/administration/administration_screen.dart';
import 'package:agrierp/features/sync/synchronisation_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chemins_depot.dart';

/// Serveur de synchronisation feint : sert, tirage après tirage, les blocs [tirages]
/// (le dernier se répète), répond [reponsePush] à l'envoi et note ce qui est envoyé.
class _ServeurSync extends Interceptor {
  _ServeurSync({
    this.reponsePush = const {},
    this.tirages = const [{}],
    this.repondre,
    this.tiragesEnPanne = const {},
    this.pendant,
  });

  final Map<String, dynamic> reponsePush;
  final List<Map<String, dynamic>> tirages;

  /// Réponse calculée d'après l'envoi (F0.78-bis) : remplace [reponsePush].
  final Map<String, dynamic> Function(Map<String, dynamic> envoi)? repondre;

  /// Rangs (0, 1, …) des tirages qui échouent sur le réseau.
  final Set<int> tiragesEnPanne;

  /// Exécuté PENDANT l'envoi, avant la réponse : le poste est modifié en plein push.
  final Future<void> Function()? pendant;
  final List<Map<String, dynamic>> envois = [];
  var nombreDeTirages = 0;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final push = options.path.contains('push');
    if (push) envois.add(Map<String, dynamic>.from(options.data as Map));
    if (push && pendant != null) await pendant!();

    if (!push && tiragesEnPanne.contains(nombreDeTirages)) {
      nombreDeTirages++;
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }

    Map<String, dynamic> corps;
    if (push) {
      corps = repondre != null ? repondre!(envois.last) : reponsePush;
    } else {
      final bloc =
          tirages[nombreDeTirages < tirages.length
              ? nombreDeTirages
              : tirages.length - 1];
      nombreDeTirages++;
      corps = {
        'server_time': '2026-10-09T12:0$nombreDeTirages:00.000Z',
        'product_categories': <dynamic>[],
        'products': <dynamic>[],
        'livestock_lots': <dynamic>[],
        ...bloc,
      };
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: corps,
      ),
    );
  }
}

class _ConnectiviteFeinte implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Ticket F0.78 — COURRIERS SAISIS, MODIFIÉS, ARCHIVÉS AU POSTE (`gestion-courriers.html`).
///
/// ⚠️⚠️ **LOCAL D'ABORD, SYNCHRONISÉ ENSUITE**, comme les clients (F0.72) : le courrier est
/// écrit `pending`, le serveur le valide et lui attribue SA référence. Le poste n'invente
/// JAMAIS `CR-AAAA-NNN` : « — » jusqu'à l'acquittement.
///
/// ⚠️⚠️ **ET LE TIRAGE FUSIONNE** : l'ancien absorbeur effaçait toute la table avant de
/// réinsérer, ce qui aurait fait disparaître un courrier saisi et pas encore acquitté.
void main() {
  late AppDatabase db;
  late AdministrationRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final aujourdhui = DateTime.now();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = AdministrationRepository(database: db);
  });

  tearDown(() async => db.close());

  SyncEngine moteur(_ServeurSync serveur) => SyncEngine(
    database: db,
    client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
      ..interceptors.add(serveur),
    deviceId: 'poste-test',
    connectivity: _ConnectiviteFeinte(),
  );

  Future<void> courrier(
    String cle, {
    String type = 'entrant',
    String objet = 'Convocation réunion PAEB',
    String? partie = 'FAGUEZ SARL',
    String? reference = 'CR-2026-054',
    DateTime? date,
    bool actif = true,
    SyncStatus statut = SyncStatus.synced,
  }) => db
      .into(db.mails)
      .insert(
        MailsCompanion.insert(
          id: uuid(cle),
          reference: Value(reference),
          type: type,
          subject: objet,
          party: Value(partie),
          mailDate: Value(date ?? DateTime(2026, 7, 14)),
          isActive: Value(actif),
          syncStatus: Value(statut),
        ),
      );

  Future<List<Mail>> tous() => db.select(db.mails).get();

  final saisie = FormulaireCourrier(
    type: 'entrant',
    objet: '  Convocation réunion PAEB  ',
    partie: ' FAGUEZ SARL ',
    date: DateTime(2026, 7, 14, 15, 30),
  );

  group('règles de saisie (identiques à CourrierService, Laravel)', () {
    test('les quatre champs sont obligatoires', () {
      final e = AdministrationRepository.validerCourrier(
        const FormulaireCourrier(),
      );

      expect(e.keys, containsAll(['type', 'objet', 'partie', 'date']));
      expect(e['type'], 'Le champ « Type » est obligatoire.');
      expect(e['objet'], 'Le champ « Objet » est obligatoire.');
      expect(
        e['partie'],
        'Le champ « Expéditeur / Destinataire » est obligatoire.',
      );
      expect(e['date'], 'Le champ « Date » est obligatoire.');
    });

    test('un type hors entrant/sortant est refusé', () {
      final e = AdministrationRepository.validerCourrier(
        FormulaireCourrier(
          type: 'interne',
          objet: 'x',
          partie: 'y',
          date: DateTime(2026, 7, 14),
        ),
      );

      expect(e.keys, ['type']);
    });

    test('objet ≤ 255 et partie ≤ 150 : la limite passe, un de plus non', () {
      FormulaireCourrier f(int objet, int partie) => FormulaireCourrier(
        type: 'sortant',
        objet: 'o' * objet,
        partie: 'p' * partie,
        date: DateTime(2026, 7, 14),
      );

      expect(AdministrationRepository.validerCourrier(f(255, 150)), isEmpty);
      expect(AdministrationRepository.validerCourrier(f(256, 150)).keys, [
        'objet',
      ]);
      expect(AdministrationRepository.validerCourrier(f(255, 151)).keys, [
        'partie',
      ]);
    });

    test('un champ fait d’espaces est vide', () {
      final e = AdministrationRepository.validerCourrier(
        FormulaireCourrier(
          type: 'entrant',
          objet: '   ',
          partie: '   ',
          date: DateTime(2026, 7, 14),
        ),
      );

      expect(e.keys, containsAll(['objet', 'partie']));
    });

    test('créer ou modifier une saisie invalide n’écrit rien', () async {
      await expectLater(
        depot.creerCourrier(const FormulaireCourrier()),
        throwsArgumentError,
      );
      expect(await tous(), isEmpty);

      await courrier('c1');
      await expectLater(
        depot.modifierCourrier(uuid('c1'), const FormulaireCourrier()),
        throwsArgumentError,
      );
      expect((await tous()).single.syncStatus, SyncStatus.synced);
    });
  });

  group('dépôt', () {
    test(
      '⚠️ créé en attente, UUID du poste, RÉFÉRENCE VIDE (jamais inventée)',
      () async {
        final c = await depot.creerCourrier(saisie);

        expect(c.id, hasLength(36));
        expect(c.reference, isNull, reason: 'le serveur l’attribue');
        expect(c.type, 'entrant');
        expect(c.subject, 'Convocation réunion PAEB');
        expect(c.party, 'FAGUEZ SARL');
        expect(
          c.mailDate,
          DateTime(2026, 7, 14),
          reason: 'un courrier a un JOUR, pas une heure',
        );
        expect(c.syncStatus, SyncStatus.pending);
        expect(c.isActive, isTrue);
      },
    );

    test('⚠️ modifier repasse en attente et GARDE la référence', () async {
      await courrier('c1', reference: 'CR-2026-054');

      final m = await depot.modifierCourrier(
        uuid('c1'),
        FormulaireCourrier(
          type: 'sortant',
          objet: 'Rapport trimestriel',
          partie: 'Coordination PAEB',
          date: DateTime(2026, 7, 10),
        ),
      );

      expect(m.subject, 'Rapport trimestriel');
      expect(m.type, 'sortant');
      expect(m.reference, 'CR-2026-054');
      expect(m.syncStatus, SyncStatus.pending);
    });

    test('⚠️ un courrier archivé ne se modifie plus', () async {
      await courrier('c1', actif: false);

      await expectLater(
        depot.modifierCourrier(uuid('c1'), saisie),
        throwsStateError,
      );
      expect((await tous()).single.subject, 'Convocation réunion PAEB');
    });

    test(
      '⚠️ archiver ne supprime rien, passe en attente, et est idempotent',
      () async {
        await courrier('c1');

        expect(await depot.archiverCourrier(uuid('c1')), isTrue);
        final c = (await tous()).single;
        expect(c.isActive, isFalse);
        expect(c.syncStatus, SyncStatus.pending);

        expect(
          await depot.archiverCourrier(uuid('c1')),
          isFalse,
          reason: 'déjà archivé : rien à faire',
        );
        expect(await depot.archiverCourrier(uuid('inconnu')), isFalse);
        expect(await tous(), hasLength(1));
      },
    );

    test('⚠️ un courrier archivé quitte la liste et les cartes', () async {
      await courrier('c1', date: aujourdhui);
      await courrier('c2', date: aujourdhui, actif: false);

      final d = await depot.charger();

      expect(d.courriers.map((c) => c.id), [uuid('c1')]);
      expect(d.recus, 1);
    });

    test(
      '⚠️ cartes recalculées indépendamment du dépôt (mois courant, par sens)',
      () async {
        final lignes = <(String, String, DateTime, bool)>[
          ('a', 'entrant', aujourdhui, true),
          ('b', 'entrant', aujourdhui, true),
          ('c', 'entrant', aujourdhui, true),
          ('d', 'sortant', aujourdhui, true),
          ('e', 'sortant', aujourdhui, true),
          ('f', 'entrant', DateTime(aujourdhui.year - 1, 3, 2), true),
          ('g', 'sortant', DateTime(aujourdhui.year - 1, 3, 2), true),
          ('h', 'entrant', aujourdhui, false),
          ('i', 'sortant', aujourdhui, false),
        ];
        for (final (cle, type, date, actif) in lignes) {
          await courrier(cle, type: type, date: date, actif: actif);
        }

        // Recomptage indépendant, sur la liste brute — sans passer par le dépôt.
        int compter(String type) => lignes
            .where(
              (l) =>
                  l.$2 == type &&
                  l.$4 &&
                  l.$3.year == aujourdhui.year &&
                  l.$3.month == aujourdhui.month,
            )
            .length;

        final d = await depot.charger();

        expect(d.recus, compter('entrant'));
        expect(d.recus, 3);
        expect(d.envoyes, compter('sortant'));
        expect(d.envoyes, 2);
        expect(d.enAttente, isNull, reason: 'aucun statut de courrier en base');
      },
    );

    test(
      'un courrier en attente compte dans le badge de synchronisation',
      () async {
        await depot.creerCourrier(saisie);
        await courrier('c2');

        expect(await db.pendingCount(), 1);
      },
    );
  });

  group('synchronisation', () {
    test(
      '⚠️ envoyé SANS référence, date en Y-m-d, acquitté sur réponse',
      () async {
        final c = await depot.creerCourrier(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'mails': {
              'accepted': [c.id],
              'rejected': [],
            },
          },
        );

        await moteur(serveur).synchroniser();

        final envoye = (serveur.envois.single['mails'] as List).single as Map;
        expect(envoye, {
          'id': c.id,
          'type': 'entrant',
          'subject': 'Convocation réunion PAEB',
          'party': 'FAGUEZ SARL',
          'mail_date': '2026-07-14',
          'is_active': true,
        });
        expect(envoye.containsKey('reference'), isFalse);
        expect((await tous()).single.syncStatus, SyncStatus.synced);
      },
    );

    test('⚠️ RIEN n’est marqué synced sans l’accusé du serveur', () async {
      await depot.creerCourrier(saisie);
      final serveur = _ServeurSync(); // le serveur ne répond rien pour `mails`

      await moteur(serveur).synchroniser();

      expect((await tous()).single.syncStatus, SyncStatus.pending);
    });

    test('⚠️ archiver part en {id, is_active: false} seulement', () async {
      await courrier('c1');
      await depot.archiverCourrier(uuid('c1'));
      final serveur = _ServeurSync(
        reponsePush: {
          'mails': {
            'accepted': [uuid('c1')],
            'rejected': [],
          },
        },
      );

      await moteur(serveur).synchroniser();

      expect((serveur.envois.single['mails'] as List).single, {
        'id': uuid('c1'),
        'is_active': false,
      });
      expect((await tous()).single.syncStatus, SyncStatus.synced);
    });

    test(
      '⚠️ refusé : conflit avec motif mot pour mot, jamais réputé envoyé',
      () async {
        final c = await depot.creerCourrier(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'mails': {
              'accepted': [],
              'rejected': [
                {
                  'id': c.id,
                  'reason':
                      'Votre rôle ne permet pas de créer ou modifier un courrier.',
                },
              ],
            },
          },
        );

        final sortie = await moteur(serveur).synchroniser();

        expect((await tous()).single.syncStatus, SyncStatus.conflict);
        expect(sortie.rejete, 1);
        expect(sortie.motifs.join(' '), contains('Votre rôle ne permet pas'));
        final conflit = await db.select(db.syncConflicts).getSingle();
        expect(conflit.sourceTable, 'mails');
        expect(conflit.recordId, c.id);
      },
    );

    test('⚠️ un conflit se relance : le courrier repasse en attente', () async {
      final c = await depot.creerCourrier(saisie);
      final serveur = _ServeurSync(
        reponsePush: {
          'mails': {
            'accepted': [],
            'rejected': [
              {'id': c.id, 'reason': 'Refus.'},
            ],
          },
        },
      );
      final m = moteur(serveur);
      await m.synchroniser();

      await m.relancer((await m.conflits()).single);

      expect((await tous()).single.syncStatus, SyncStatus.pending);
      expect(await m.conflits(), isEmpty);
    });

    test(
      '⚠️ TIRAGE DE CONFIRMATION : la référence attribuée arrive dans la même synchronisation',
      () async {
        final c = await depot.creerCourrier(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'mails': {
              'accepted': [c.id],
              'rejected': [],
            },
          },
          tirages: [
            {'mails': <dynamic>[]},
            {
              'mails': [
                {
                  'id': c.id,
                  'reference': 'CR-2026-055',
                  'type': 'entrant',
                  'subject': 'Convocation réunion PAEB',
                  'party': 'FAGUEZ SARL',
                  'mail_date': '2026-07-14',
                  'is_active': true,
                },
              ],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        expect(serveur.nombreDeTirages, 2);
        final m = (await tous()).single;
        expect(m.reference, 'CR-2026-055');
        expect(m.syncStatus, SyncStatus.synced);
      },
    );

    test('sans courrier accepté, pas de second tirage', () async {
      final serveur = _ServeurSync();

      await moteur(serveur).synchroniser();

      expect(serveur.nombreDeTirages, 1);
    });
  });

  group('absorbeur des courriers (fusion stricte)', () {
    Map<String, dynamic> ligne(
      String cle, {
      String type = 'entrant',
      String objet = 'Objet du serveur',
      Object? date = '2026-07-14',
      Object? actif = true,
      String? reference = 'CR-2026-001',
    }) => {
      'id': uuid(cle),
      'reference': reference,
      'type': type,
      'subject': objet,
      'party': 'Partie',
      'mail_date': date,
      'is_active': actif,
      'updated_at': '2026-10-09T08:00:00+00:00',
    };

    test(
      '⚠️ un courrier du serveur est inséré, puis mis à jour par id',
      () async {
        final serveur = _ServeurSync(
          tirages: [
            {
              'mails': [ligne('c1', objet: 'Première version')],
            },
            {
              'mails': [ligne('c1', objet: 'Seconde version')],
            },
          ],
        );
        final m = moteur(serveur);

        await m.synchroniser();
        await m.synchroniser();

        final tout = await tous();
        expect(tout, hasLength(1));
        expect(tout.single.subject, 'Seconde version');
        expect(tout.single.reference, 'CR-2026-001');
        expect(tout.single.syncStatus, SyncStatus.synced);
      },
    );

    test(
      '⚠️⚠️ le tirage n’efface NI n’écrase un courrier en attente ou en conflit',
      () async {
        await courrier(
          'p1',
          objet: 'Saisi au poste',
          reference: null,
          statut: SyncStatus.pending,
        );
        await courrier(
          'k1',
          objet: 'Refusé au poste',
          reference: null,
          statut: SyncStatus.conflict,
        );
        final serveur = _ServeurSync(
          tirages: [
            {
              // p1 est servi avec un autre contenu ; k1 est absent du tirage.
              'mails': [
                ligne('p1', objet: 'Version du serveur'),
                ligne('autre', objet: 'Autre'),
              ],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        final parId = {for (final c in await tous()) c.id: c};
        expect(parId[uuid('p1')]!.subject, 'Saisi au poste');
        expect(parId[uuid('p1')]!.syncStatus, SyncStatus.pending);
        expect(parId[uuid('k1')]!.subject, 'Refusé au poste');
        expect(parId[uuid('k1')]!.syncStatus, SyncStatus.conflict);
        expect(parId[uuid('autre')]!.subject, 'Autre');
      },
    );

    test('⚠️ un courrier archivé côté serveur quitte le poste', () async {
      await courrier('a1', objet: 'Archivé ailleurs');
      await courrier('b1', objet: 'Reste');
      final serveur = _ServeurSync(
        tirages: [
          {
            'mails': [ligne('a1', actif: false), ligne('b1', objet: 'Reste')],
          },
        ],
      );

      await moteur(serveur).synchroniser();

      expect((await tous()).map((c) => c.id), [uuid('b1')]);
    });

    test(
      '⚠️ un courrier synchronisé que le serveur ne sert plus est retiré',
      () async {
        await courrier('vieux');
        await courrier('garde');
        final serveur = _ServeurSync(
          tirages: [
            {
              'mails': [ligne('garde')],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        expect((await tous()).map((c) => c.id), [uuid('garde')]);
      },
    );

    test(
      'un archivé qui descend sans exister au poste n’est pas créé',
      () async {
        final serveur = _ServeurSync(
          tirages: [
            {
              'mails': [ligne('a1', actif: false)],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        expect(await tous(), isEmpty);
      },
    );

    test(
      '⚠️ une ligne sans `is_active` (ancien serveur) reste active',
      () async {
        final l = ligne('c1')..remove('is_active');
        final serveur = _ServeurSync(
          tirages: [
            {
              'mails': [l],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        expect((await tous()).single.isActive, isTrue);
      },
    );

    for (final (nom, mauvaise) in <(String, Map<String, dynamic>)>[
      ('type inconnu', {'type': 'interne'}),
      ('objet absent', {'subject': null}),
      ('objet vide', {'subject': '   '}),
      ('date illisible', {'mail_date': 'pas-une-date'}),
      ('identifiant invalide', {'id': '1'}),
    ]) {
      test('⚠️ STRICT : $nom est REFUSÉ, rien n’est modifié', () async {
        await courrier('existant', objet: 'Intact');
        final serveur = _ServeurSync(
          tirages: [
            {
              'mails': [
                ligne('bon'),
                {...ligne('mauvais'), ...mauvaise},
              ],
            },
          ],
        );

        await expectLater(
          moteur(serveur).synchroniser(),
          throwsA(isA<FormatException>()),
        );

        final tout = await tous();
        expect(
          tout.map((c) => c.id),
          [uuid('existant')],
          reason: 'la transaction est annulée : ni le bon, ni la suppression',
        );
        expect(tout.single.subject, 'Intact');
      });
    }
  });

  group('F0.78-bis : archivage d’un courrier inconnu du serveur', () {
    /// Serveur réaliste : il connaît les courriers qu'il a ACCEPTÉS en entier, et refuse
    /// d'archiver un identifiant qu'il ne connaît pas (message de `pushMails`, 15.23).
    _ServeurSync serveurRealiste({
      Set<int> tiragesEnPanne = const {},
      Future<void> Function()? pendant,
      Set<String>? connus,
      String? refusTout,
    }) {
      final vus = connus ?? <String>{};
      return _ServeurSync(
        tiragesEnPanne: tiragesEnPanne,
        pendant: pendant,
        repondre: (envoi) {
          final acceptes = <String>[];
          final rejetes = <Map<String, String>>[];
          for (final m in (envoi['mails'] as List).cast<Map>()) {
            final id = m['id'] as String;
            final archivage = m['is_active'] == false;
            if (refusTout != null) {
              rejetes.add({'id': id, 'reason': refusTout});
            } else if (archivage && !vus.contains(id)) {
              rejetes.add({
                'id': id,
                'reason': 'Courrier inconnu : impossible de l’archiver.',
              });
            } else {
              vus.add(id);
              acceptes.add(id);
            }
          }
          return {
            'mails': {'accepted': acceptes, 'rejected': rejetes},
          };
        },
      );
    }

    test(
      '⚠️⚠️ créé puis archivé HORS LIGNE : rien d’impossible n’est envoyé, aucun conflit',
      () async {
        final c = await depot.creerCourrier(saisie);
        expect(await depot.archiverCourrier(c.id), isTrue);
        final serveur = serveurRealiste();

        final sortie = await moteur(serveur).synchroniser();

        expect(
          serveur.envois.expand((e) => (e['mails'] as List? ?? const [])),
          isEmpty,
          reason: 'le serveur ne connaît pas ce courrier',
        );
        expect(sortie.rejete, 0);
        expect(await db.select(db.syncConflicts).get(), isEmpty);
        expect(
          await tous(),
          isEmpty,
          reason: 'jamais acquitté : retiré du poste',
        );
        expect(await db.pendingCount(), 0);
      },
    );

    test(
      '⚠️ créé, REFUSÉ, puis archivé : la ligne et son conflit disparaissent',
      () async {
        final c = await depot.creerCourrier(saisie);
        final m = moteur(serveurRealiste(refusTout: 'Refus de création.'));
        await m.synchroniser();
        expect((await tous()).single.syncStatus, SyncStatus.conflict);

        await depot.archiverCourrier(c.id);

        expect(await tous(), isEmpty);
        expect(await m.conflits(), isEmpty, reason: 'plus rien à relancer');
      },
    );

    test(
      '⚠️⚠️ ACQUITTÉ mais référence pas encore descendue, puis archivé : l’archivage PART',
      () async {
        final c = await depot.creerCourrier(saisie);
        final connus = <String>{};
        // Le tirage de confirmation échoue : le courrier est connu du serveur, sa
        // référence n'est pas descendue. `reference == null` ne dit donc PAS « inconnu ».
        final premier = serveurRealiste(tiragesEnPanne: {1}, connus: connus);
        await moteur(premier).synchroniser();
        final apres = (await tous()).single;
        expect(apres.syncStatus, SyncStatus.synced);
        expect(apres.reference, isNull);

        await depot.archiverCourrier(c.id);
        final second = serveurRealiste(connus: connus);
        final sortie = await moteur(second).synchroniser();

        expect((second.envois.single['mails'] as List).single, {
          'id': c.id,
          'is_active': false,
        });
        expect(sortie.rejete, 0);
        expect((await tous()).single.syncStatus, SyncStatus.synced);
      },
    );

    test(
      '⚠️⚠️ un archivage REFUSÉ reste visible : ligne « Refusé » et motif, hors des cartes',
      () async {
        await courrier('c1', date: aujourdhui);
        await courrier('c2', date: aujourdhui);
        await depot.archiverCourrier(uuid('c1'));
        const motif =
            'Votre rôle ne permet pas de créer ou modifier un courrier.';
        await moteur(serveurRealiste(refusTout: motif)).synchroniser();

        final d = await depot.charger();

        expect(
          d.courriers.map((c) => c.id),
          containsAll([uuid('c1'), uuid('c2')]),
        );
        expect(d.refusCourriers[uuid('c1')], motif);
        expect(
          d.recus,
          1,
          reason: 'l’archivé refusé ne compte pas dans les cartes',
        );
      },
    );

    testWidgets(
      '⚠️⚠️ écran : l’archivage refusé s’affiche « Refusé » avec son motif, sans boutons d’édition',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        await courrier('c1');
        await depot.archiverCourrier(uuid('c1'));
        await tester.runAsync(
          () => moteur(
            serveurRealiste(refusTout: 'Refus du serveur.'),
          ).synchroniser(),
        );

        await tester.pumpWidget(
          MaterialApp(home: AdministrationScreen(depot: depot)),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(Key('courrier-refuse-${uuid('c1')}')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(find.byKey(Key('courrier-motif-${uuid('c1')}')))
              .data,
          'Refus du serveur.',
        );
        expect(
          find.byKey(Key('modifier-courrier-${uuid('c1')}')),
          findsNothing,
        );
        expect(
          find.byKey(Key('archiver-courrier-${uuid('c1')}')),
          findsNothing,
        );
        expect(find.byKey(const Key('courriers-vide')), findsNothing);
        expect(find.text('Archivage refusé'), findsOneWidget);
      },
    );

    // Une correction d'UN SEUL champ à la fois : un test qui en change plusieurs laisserait
    // survivre la comparaison de chacun des autres.
    final corrections = <String, FormulaireCourrier>{
      'le type': FormulaireCourrier(
        type: 'sortant',
        objet: 'Convocation réunion PAEB',
        partie: 'FAGUEZ SARL',
        date: DateTime(2026, 7, 14),
      ),
      'l’objet': FormulaireCourrier(
        type: 'entrant',
        objet: 'Objet corrigé pendant l’envoi',
        partie: 'FAGUEZ SARL',
        date: DateTime(2026, 7, 14),
      ),
      'la partie': FormulaireCourrier(
        type: 'entrant',
        objet: 'Convocation réunion PAEB',
        partie: 'Autre partie',
        date: DateTime(2026, 7, 14),
      ),
      'la date': FormulaireCourrier(
        type: 'entrant',
        objet: 'Convocation réunion PAEB',
        partie: 'FAGUEZ SARL',
        date: DateTime(2026, 7, 20),
      ),
    };

    for (final MapEntry(key: champ, value: correction) in corrections.entries) {
      test(
        '⚠️ $champ modifié PENDANT l’envoi : l’accusé de l’ancienne version ne rend pas la nouvelle « synced »',
        () async {
          final c = await depot.creerCourrier(saisie);
          final serveur = serveurRealiste(
            pendant: () => depot.modifierCourrier(c.id, correction),
          );
          await moteur(serveur).synchroniser();

          final apres = (await tous()).single;
          expect(
            apres.syncStatus,
            SyncStatus.pending,
            reason: 'la correction reste à envoyer',
          );
          expect(apres.knownByServer, isTrue, reason: 'le serveur l’a accepté');

          final suivant = serveurRealiste(connus: {c.id});
          await moteur(suivant).synchroniser();

          final envoye = (suivant.envois.single['mails'] as List).single as Map;
          expect(envoye['type'], correction.type);
          expect(envoye['subject'], correction.objet);
          expect(envoye['party'], correction.partie);
          expect(envoye['mail_date'], '2026-07-${correction.date!.day}');
          expect((await tous()).single.syncStatus, SyncStatus.synced);
        },
      );
    }

    test(
      '⚠️ archivé PENDANT l’envoi : l’accusé de la version active ne masque pas l’archivage',
      () async {
        await courrier('c1', statut: SyncStatus.pending);
        final serveur = serveurRealiste(
          pendant: () => depot.archiverCourrier(uuid('c1')),
        );
        await moteur(serveur).synchroniser();

        final apres = (await tous()).single;
        expect(apres.isActive, isFalse);
        expect(apres.syncStatus, SyncStatus.pending);

        final suivant = serveurRealiste(connus: {uuid('c1')});
        await moteur(suivant).synchroniser();

        expect((suivant.envois.single['mails'] as List).single, {
          'id': uuid('c1'),
          'is_active': false,
        });
        expect((await tous()).single.syncStatus, SyncStatus.synced);
      },
    );
  });

  group('écran Synchronisation', () {
    testWidgets(
      '⚠️ un courrier refusé s’y nomme « Courrier » et offre la remise en file',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        final c = await depot.creerCourrier(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'mails': {
              'accepted': [],
              'rejected': [
                {'id': c.id, 'reason': 'Refus du serveur.'},
              ],
            },
          },
        );
        final m = moteur(serveur);
        await tester.runAsync(m.synchroniser);

        await tester.pumpWidget(
          MaterialApp(
            home: SynchronisationScreen(database: db, engine: m),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Courrier'), findsOneWidget);
        expect(find.text('mails'), findsNothing);
        expect(find.byKey(Key('motif-${c.id}')), findsOneWidget);

        await tester.tap(find.byKey(Key('relancer-${c.id}')));
        await tester.pumpAndSettle();

        expect((await tous()).single.syncStatus, SyncStatus.pending);
      },
    );
  });

  group('migration v32 → v33', () {
    test(
      '⚠️ une base v32 (sans is_active ni sync_status) garde ses courriers',
      () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        addTearDown(
          () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
        );
        final dossier = Directory.systemTemp.createTempSync('agrierp_v32_');
        final fichier = File('${dossier.path}${Platform.pathSeparator}v32.db');
        addTearDown(() {
          try {
            dossier.deleteSync(recursive: true);
          } catch (_) {}
        });

        final neuve = AppDatabase.forTesting(NativeDatabase(fichier));
        await neuve
            .into(neuve.mails)
            .insert(
              MailsCompanion.insert(
                id: uuid('c1'),
                reference: const Value('CR-2026-054'),
                type: 'entrant',
                subject: 'Convocation',
              ),
            );
        await neuve.close();

        var colonnesAvant = <String>[];
        final v32 = AppDatabase.forTesting(
          NativeDatabase(
            fichier,
            setup: (raw) {
              raw.execute('ALTER TABLE mails DROP COLUMN is_active');
              raw.execute('ALTER TABLE mails DROP COLUMN sync_status');
              raw.execute('ALTER TABLE mails DROP COLUMN known_by_server');
              // F0.79 : une vraie base v32 n'a pas non plus les colonnes des archives.
              for (final c in ['is_active', 'sync_status', 'known_by_server']) {
                raw.execute('ALTER TABLE archived_documents DROP COLUMN $c');
                // F0.80 : ni celles des documents administratifs (schéma v36).
                raw.execute(
                  'ALTER TABLE administrative_documents DROP COLUMN $c',
                );
              }
              // F0.85 (schéma v37) : une vraie base plus ancienne n'a pas non plus la date de création
              // des écritures.
              raw.execute(
                'ALTER TABLE accounting_entries DROP COLUMN created_at',
              );
              raw.execute('PRAGMA user_version = 32');
              colonnesAvant = [
                for (final l in raw.select('PRAGMA table_info(mails)'))
                  l['name'] as String,
              ];
            },
          ),
        );
        final apres = await v32.select(v32.mails).getSingle();
        await v32.close();

        expect(colonnesAvant, isNot(contains('is_active')));
        expect(colonnesAvant, isNot(contains('sync_status')));
        expect(apres.id, uuid('c1'));
        expect(apres.reference, 'CR-2026-054');
        expect(apres.isActive, isTrue);
        expect(apres.syncStatus, SyncStatus.synced);
      },
    );
  });

  group('migration v33 → v34', () {
    test(
      '⚠️ une base v33 (sans known_by_server) garde ses courriers, tous réputés connus',
      () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        addTearDown(
          () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
        );
        final dossier = Directory.systemTemp.createTempSync('agrierp_v33_');
        final fichier = File('${dossier.path}${Platform.pathSeparator}v33.db');
        addTearDown(() {
          try {
            dossier.deleteSync(recursive: true);
          } catch (_) {}
        });

        final neuve = AppDatabase.forTesting(NativeDatabase(fichier));
        await neuve
            .into(neuve.mails)
            .insert(
              MailsCompanion.insert(
                id: uuid('c1'),
                reference: const Value('CR-2026-054'),
                type: 'entrant',
                subject: 'Convocation',
              ),
            );
        await neuve.close();

        var colonnesAvant = <String>[];
        final v33 = AppDatabase.forTesting(
          NativeDatabase(
            fichier,
            setup: (raw) {
              raw.execute('ALTER TABLE mails DROP COLUMN known_by_server');
              // F0.79 : une vraie base v33 n'a pas non plus les colonnes des archives.
              for (final c in ['is_active', 'sync_status', 'known_by_server']) {
                raw.execute('ALTER TABLE archived_documents DROP COLUMN $c');
                // F0.80 : ni celles des documents administratifs (schéma v36).
                raw.execute(
                  'ALTER TABLE administrative_documents DROP COLUMN $c',
                );
              }
              // F0.85 (schéma v37) : une vraie base plus ancienne n'a pas non plus la date de création
              // des écritures.
              raw.execute(
                'ALTER TABLE accounting_entries DROP COLUMN created_at',
              );
              raw.execute('PRAGMA user_version = 33');
              colonnesAvant = [
                for (final l in raw.select('PRAGMA table_info(mails)'))
                  l['name'] as String,
              ];
            },
          ),
        );
        final apres = await v33.select(v33.mails).getSingle();
        await v33.close();

        expect(colonnesAvant, isNot(contains('known_by_server')));
        expect(apres.reference, 'CR-2026-054');
        expect(apres.knownByServer, isTrue);
      },
    );
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(home: AdministrationScreen(depot: depot)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> remplir(
      WidgetTester tester, {
      String? type = 'Entrant',
      String objet = 'Convocation réunion PAEB',
      String partie = 'FAGUEZ SARL',
      bool date = true,
    }) async {
      if (type != null) {
        await tester.tap(find.byKey(const Key('courrier-type')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(type).last);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byKey(const Key('courrier-objet')), objet);
      await tester.enterText(find.byKey(const Key('courrier-partie')), partie);
      if (date) {
        await tester.tap(find.byKey(const Key('courrier-date')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets(
      '⚠️ « Nouveau Courrier » : quatre champs, rien d’écrit si vide',
      (tester) async {
        await afficher(tester);

        await tester.tap(find.byKey(const Key('nouveau-courrier')));
        await tester.pumpAndSettle();
        expect(find.text('Nouveau Courrier'), findsWidgets);
        for (final libelle in [
          'Type *',
          'Objet *',
          'Expéditeur / Destinataire *',
          // Ticket MP1 : le libellé d'un champ Date est celui du Blade, `uppercase` compris (`ChampDateFormulaire`).
          'DATE *',
        ]) {
          expect(find.text(libelle), findsOneWidget, reason: libelle);
        }

        await tester.tap(find.byKey(const Key('courrier-enregistrer')));
        await tester.pumpAndSettle();

        expect(await tous(), isEmpty);
        for (final cle in ['type', 'objet', 'partie', 'date']) {
          expect(
            find.byKey(Key('courrier-erreur-$cle')),
            findsOneWidget,
            reason: cle,
          );
        }
      },
    );

    testWidgets(
      '⚠️ enregistrer écrit un courrier en attente, référence « — » à l’écran',
      (tester) async {
        await afficher(tester);

        await tester.tap(find.byKey(const Key('nouveau-courrier')));
        await tester.pumpAndSettle();
        await remplir(tester);
        await tester.tap(find.byKey(const Key('courrier-enregistrer')));
        await tester.pumpAndSettle();

        final c = (await tous()).single;
        expect(c.subject, 'Convocation réunion PAEB');
        expect(c.type, 'entrant');
        expect(c.reference, isNull);
        expect(c.syncStatus, SyncStatus.pending);
        expect(c.mailDate, isNotNull);

        expect(
          tester
              .widget<Text>(find.byKey(Key('courrier-reference-${c.id}')))
              .data,
          '—',
        );
        expect(find.byKey(Key('courrier-a-envoyer-${c.id}')), findsOneWidget);
        expect(find.text('Convocation réunion PAEB'), findsOneWidget);
      },
    );

    testWidgets('modifier réécrit le courrier et le repasse en attente', (
      tester,
    ) async {
      await courrier('c1', objet: 'Ancien objet');
      await afficher(tester);

      await tester.tap(find.byKey(Key('modifier-courrier-${uuid('c1')}')));
      await tester.pumpAndSettle();
      expect(find.text('Modifier — Gestion des Courriers'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('courrier-objet')),
        'Nouvel objet',
      );
      await tester.tap(find.byKey(const Key('courrier-enregistrer')));
      await tester.pumpAndSettle();

      final c = (await tous()).single;
      expect(c.subject, 'Nouvel objet');
      expect(c.reference, 'CR-2026-054');
      expect(c.syncStatus, SyncStatus.pending);
    });

    testWidgets(
      '⚠️ archiver demande confirmation, nomme la référence, ne supprime rien',
      (tester) async {
        await courrier('c1');
        await courrier('c2', objet: 'Autre', reference: 'CR-2026-053');
        await afficher(tester);

        await tester.tap(find.byKey(Key('archiver-courrier-${uuid('c1')}')));
        await tester.pumpAndSettle();
        expect(find.text("Confirmer l'archivage"), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('archivage-courrier-cible')))
              .data,
          'CR-2026-054',
        );
        expect(
          find.textContaining('Aucune suppression définitive'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('archivage-courrier-confirmer')));
        await tester.pumpAndSettle();

        final tout = await tous();
        expect(tout, hasLength(2));
        expect(tout.firstWhere((c) => c.id == uuid('c1')).isActive, isFalse);
        expect(find.text('Convocation réunion PAEB'), findsNothing);
        expect(find.text('Autre'), findsOneWidget);
      },
    );

    testWidgets('annuler l’archivage ne change rien', (tester) async {
      await courrier('c1');
      await afficher(tester);

      await tester.tap(find.byKey(Key('archiver-courrier-${uuid('c1')}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect((await tous()).single.isActive, isTrue);
      expect((await tous()).single.syncStatus, SyncStatus.synced);
    });

    testWidgets(
      'sans référence, la confirmation nomme l’objet (jamais une référence inventée)',
      (tester) async {
        await courrier('c1', reference: null, statut: SyncStatus.pending);
        await afficher(tester);

        await tester.tap(find.byKey(Key('archiver-courrier-${uuid('c1')}')));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<Text>(find.byKey(const Key('archivage-courrier-cible')))
              .data,
          'Convocation réunion PAEB',
        );
      },
    );

    testWidgets(
      '⚠️ un courrier refusé montre « Refusé » et le motif du serveur',
      (tester) async {
        await courrier('c1', reference: null, statut: SyncStatus.conflict);
        await db
            .into(db.syncConflicts)
            .insert(
              SyncConflictsCompanion.insert(
                id: 'mails:${uuid('c1')}',
                sourceTable: 'mails',
                recordId: uuid('c1'),
                reason:
                    'Ce courrier est archivé : il ne peut plus être modifié.',
                detectedAt: DateTime(2026, 10, 9),
              ),
            );
        await afficher(tester);

        expect(
          find.byKey(Key('courrier-refuse-${uuid('c1')}')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(find.byKey(Key('courrier-motif-${uuid('c1')}')))
              .data,
          'Ce courrier est archivé : il ne peut plus être modifié.',
        );
      },
    );

    testWidgets(
      '⚠️ état vide de la maquette : son bouton ouvre « Nouveau Courrier »',
      (tester) async {
        await afficher(tester);

        expect(find.text('Aucun résultat trouvé'), findsOneWidget);
        expect(
          find.text('Essayez un autre terme ou un autre filtre.'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('nouveau-courrier-vide')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('courrier-enregistrer')), findsOneWidget);
      },
    );

    testWidgets('l’état vide disparaît dès qu’il y a un courrier', (
      tester,
    ) async {
      await courrier('c1');
      await afficher(tester);

      expect(find.byKey(const Key('courriers-vide')), findsNothing);
    });

    testWidgets(
      '⚠️⚠️ LIBELLÉS DES CARTES de la maquette (pas seulement leur nombre) ; « En attente » = « — »',
      (tester) async {
        await courrier('c1', date: aujourdhui);
        await courrier('c2', type: 'sortant', date: aujourdhui);
        await afficher(tester);

        final cartes = tester
            .widgetList<CarteKpi>(find.byType(CarteKpi))
            .toList();

        expect(cartes.map((c) => c.libelle), [
          'Reçus (mois)',
          'Envoyés (mois)',
          'En attente',
        ]);
        expect(cartes[0].valeur, '1');
        expect(cartes[1].valeur, '1');
        expect(
          cartes[2].valeur,
          '—',
          reason: 'jamais 0 : le poste ne le sait pas',
        );
        expect(cartes[2].legende, isNotNull);
        expect(
          cartes.map((c) => c.libelle),
          isNot(contains('Courriers (mois)')),
          reason: 'carte absente de gestion-courriers.html',
        );
      },
    );

    test(
      '⚠️⚠️ les libellés de cartes de l’écran sont ceux de gestion-courriers.html (lus dans la maquette)',
      () {
        final maquette = File(
          '$dossierPrototype/gestion-courriers.html',
        );
        if (!maquette.existsSync()) {
          markTestSkipped('maquette absente de ce poste de travail');
          return;
        }

        // Les libellés de carte sont des <span> `uppercase` SANS `tracking-wider`
        // (celui des <th>) : l'extracteur de vocabulaire ne les voit pas.
        final html = maquette.readAsStringSync();
        final attendus = [
          for (final m in RegExp(
            r'<span class="text-\[10px\] text-outline font-bold uppercase">([^<]+)</span>',
          ).allMatches(html))
            m.group(1)!.trim(),
        ];

        expect(attendus, [
          'Reçus (mois)',
          'Envoyés (mois)',
          'En attente',
        ], reason: 'la maquette a changé : revoir les cartes');

        final ecran = File(
          'lib/features/administration/administration_screen.dart',
        ).readAsStringSync();
        final debut = ecran.indexOf('Widget _ongletCourriers');
        final fin = ecran.indexOf('Widget _typeCourrier');
        final onglet = ecran.substring(debut, fin);
        final presentes = [
          for (final m in RegExp(
            r"CarteKpi\(\s*libelle: '([^']+)'",
          ).allMatches(onglet))
            m.group(1)!,
        ];

        expect(presentes, attendus);
      },
    );
  });
}
