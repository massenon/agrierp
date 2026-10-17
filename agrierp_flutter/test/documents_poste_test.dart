import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/widgets/modale_agri.dart';
import 'package:agrierp/features/administration/administration_repository.dart';
import 'package:agrierp/features/administration/administration_screen.dart';
import 'package:agrierp/features/sync/synchronisation_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  /// Réponse calculée d'après l'envoi : remplace [reponsePush].
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

/// Ticket F0.80 — DOCUMENTS ADMINISTRATIFS SAISIS, MODIFIÉS, RETIRÉS AU POSTE
/// (`documents-administratifs.html`, 2e moitié du ticket 8.3).
///
/// ⚠️⚠️ **LOCAL D'ABORD, SYNCHRONISÉ ENSUITE**, comme les courriers (F0.78) et les archives
/// (F0.79), avec TOUTES leurs leçons dès le premier jet : colonne `known_by_server`, retrait
/// refusé visible avec son motif, accusé comparé à la version envoyée, absorbeur par fusion
/// strict, purge de `sync_conflicts`.
///
/// ⚠️ **AUCUN FICHIER N'EST GÉNÉRÉ** : « Générer un Document » écrit une ligne de registre.
void main() {
  late AppDatabase db;
  late AdministrationRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  DateTime jourLocal() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

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

  Future<void> document(
    String cle, {
    String titre = 'Attestation de stage',
    String? type = 'Attestation',
    String? beneficiaire = 'AGOSSOU Félicité',
    DateTime? date,
    String? statut = 'signe',
    bool actif = true,
    SyncStatus sync = SyncStatus.synced,
    bool connu = true,
  }) => db
      .into(db.administrativeDocuments)
      .insert(
        AdministrativeDocumentsCompanion.insert(
          id: uuid(cle),
          title: titre,
          type: Value(type),
          beneficiary: Value(beneficiaire),
          docDate: Value(date ?? DateTime(2026, 7, 12)),
          status: Value(statut),
          isActive: Value(actif),
          syncStatus: Value(sync),
          knownByServer: Value(connu),
        ),
      );

  Future<List<AdministrativeDocument>> tous() =>
      db.select(db.administrativeDocuments).get();

  final saisie = FormulaireDocument(
    titre: '  Attestation de stage  ',
    type: ' Attestation ',
    beneficiaire: '  AGOSSOU Félicité ',
    date: DateTime(2026, 7, 12, 14, 30),
    statut: 'signe',
  );

  group(
    'règles de saisie (identiques à DocumentAdministratifService, Laravel)',
    () {
      FormulaireDocument f({
        String titre = 'Titre',
        String type = 'Attestation',
        String beneficiaire = 'Kossi',
        DateTime? date,
        String statut = 'en_attente',
      }) => FormulaireDocument(
        titre: titre,
        type: type,
        beneficiaire: beneficiaire,
        date: date ?? DateTime(2026, 7, 12),
        statut: statut,
      );

      test(
        'titre, type, bénéficiaire et date sont obligatoires ; le statut vaut « en attente » par défaut',
        () {
          const vide = FormulaireDocument();
          final e = AdministrationRepository.validerDocument(vide);

          expect(
            e.keys,
            containsAll(['titre', 'type', 'beneficiaire', 'date']),
          );
          expect(e.containsKey('statut'), isFalse);
          expect(vide.statut, 'en_attente');
          expect(e['type'], 'Le champ « Type de document » est obligatoire.');
          expect(
            e['beneficiaire'],
            'Le champ « Bénéficiaire » est obligatoire.',
          );
          expect(e['date'], 'Le champ « Date » est obligatoire.');
        },
      );

      test('titre ≤ 255 : la limite passe, un de plus non', () {
        expect(
          AdministrationRepository.validerDocument(f(titre: 't' * 255)),
          isEmpty,
        );
        expect(
          AdministrationRepository.validerDocument(f(titre: 't' * 256)).keys,
          ['titre'],
        );
      });

      test(
        '⚠️ type ≤ 100 (colonne du serveur, sans max côté validation) : la limite passe, un de plus non',
        () {
          expect(
            AdministrationRepository.validerDocument(f(type: 'c' * 100)),
            isEmpty,
          );
          expect(
            AdministrationRepository.validerDocument(f(type: 'c' * 101)).keys,
            ['type'],
          );
        },
      );

      test('bénéficiaire ≤ 150 : la limite passe, un de plus non', () {
        expect(
          AdministrationRepository.validerDocument(f(beneficiaire: 'b' * 150)),
          isEmpty,
        );
        expect(
          AdministrationRepository.validerDocument(
            f(beneficiaire: 'b' * 151),
          ).keys,
          ['beneficiaire'],
        );
      });

      test('un type libre (hors liste proposée) est accepté', () {
        expect(
          AdministrationRepository.validerDocument(f(type: 'Procès-verbal')),
          isEmpty,
        );
      });

      test('⚠️ le statut est « signe » ou « en_attente », rien d’autre', () {
        expect(
          AdministrationRepository.validerDocument(f(statut: 'signe')),
          isEmpty,
        );
        expect(
          AdministrationRepository.validerDocument(f(statut: 'en_attente')),
          isEmpty,
        );
        expect(
          AdministrationRepository.validerDocument(f(statut: 'brouillon')).keys,
          ['statut'],
        );
        expect(AdministrationRepository.validerDocument(f(statut: '')).keys, [
          'statut',
        ]);
      });

      test('un champ fait d’espaces est vide', () {
        final e = AdministrationRepository.validerDocument(
          f(titre: '   ', type: '  ', beneficiaire: ' '),
        );

        expect(e.keys, containsAll(['titre', 'type', 'beneficiaire']));
      });

      test('créer ou modifier une saisie invalide n’écrit rien', () async {
        await expectLater(
          depot.creerDocument(const FormulaireDocument()),
          throwsArgumentError,
        );
        expect(await tous(), isEmpty);

        await document('d1');
        await expectLater(
          depot.modifierDocument(uuid('d1'), const FormulaireDocument()),
          throwsArgumentError,
        );
        expect((await tous()).single.syncStatus, SyncStatus.synced);
      });
    },
  );

  group('dépôt', () {
    test(
      '⚠️ créé en attente, UUID du poste, jour sans heure, JAMAIS connu du serveur',
      () async {
        final d = await depot.creerDocument(saisie);

        expect(d.id, hasLength(36));
        expect(d.title, 'Attestation de stage');
        expect(d.type, 'Attestation');
        expect(d.beneficiary, 'AGOSSOU Félicité');
        expect(d.docDate, DateTime(2026, 7, 12));
        expect(d.status, 'signe');
        expect(d.isActive, isTrue);
        expect(d.syncStatus, SyncStatus.pending);
        expect(d.knownByServer, isFalse);
      },
    );

    test('le statut par défaut d’une création est « en_attente »', () async {
      final d = await depot.creerDocument(
        FormulaireDocument(
          titre: 'Note',
          type: 'Note interne',
          beneficiaire: 'Tout le personnel',
          date: DateTime(2026, 7, 10),
        ),
      );

      expect(d.status, 'en_attente');
    });

    test(
      '⚠️ modifier repasse en attente, GARDE « connu du serveur » et change le statut',
      () async {
        await document('d1', statut: 'en_attente');

        final d = await depot.modifierDocument(
          uuid('d1'),
          FormulaireDocument(
            titre: 'Attestation signée',
            type: 'Certificat',
            beneficiaire: 'ZINSOU Marc',
            date: DateTime(2026, 8, 1),
            statut: 'signe',
          ),
        );

        expect(d.title, 'Attestation signée');
        expect(d.type, 'Certificat');
        expect(d.beneficiary, 'ZINSOU Marc');
        expect(d.docDate, DateTime(2026, 8, 1));
        expect(d.status, 'signe');
        expect(d.syncStatus, SyncStatus.pending);
        expect(d.knownByServer, isTrue);
      },
    );

    test('⚠️ un document retiré ne se modifie plus', () async {
      await document('d1', actif: false);

      await expectLater(
        depot.modifierDocument(uuid('d1'), saisie),
        throwsStateError,
      );
      expect((await tous()).single.title, 'Attestation de stage');
    });

    test('un document inconnu ne se modifie pas', () async {
      await expectLater(
        depot.modifierDocument(uuid('inconnu'), saisie),
        throwsStateError,
      );
    });

    test('⚠️ corriger une ligne REFUSÉE efface son refus', () async {
      await document('d1', sync: SyncStatus.conflict);
      await db
          .into(db.syncConflicts)
          .insert(
            SyncConflictsCompanion.insert(
              id: 'administrative_documents:${uuid('d1')}',
              sourceTable: 'administrative_documents',
              recordId: uuid('d1'),
              reason: 'Refus.',
              detectedAt: DateTime(2026, 10, 9),
            ),
          );
      await db
          .into(db.syncConflicts)
          .insert(
            SyncConflictsCompanion.insert(
              id: 'administrative_documents:${uuid('autre')}',
              sourceTable: 'administrative_documents',
              recordId: uuid('autre'),
              reason: 'Refus d’un autre document.',
              detectedAt: DateTime(2026, 10, 9),
            ),
          );

      await depot.modifierDocument(uuid('d1'), saisie);

      final restants = await db.select(db.syncConflicts).get();
      expect(restants.map((c) => c.recordId), [uuid('autre')]);
    });

    test(
      '⚠️ retirer ne supprime rien, passe en attente, et est idempotent',
      () async {
        await document('d1');

        expect(await depot.retirerDocument(uuid('d1')), isTrue);
        final d = (await tous()).single;
        expect(d.isActive, isFalse);
        expect(d.syncStatus, SyncStatus.pending);

        expect(
          await depot.retirerDocument(uuid('d1')),
          isFalse,
          reason: 'déjà retiré : rien à faire',
        );
        expect(await depot.retirerDocument(uuid('inconnu')), isFalse);
        expect(await tous(), hasLength(1));
      },
    );

    test(
      '⚠️⚠️ retirer un document REFUSÉ mais connu : son ancien motif ne reste pas orphelin',
      () async {
        await document('d1', sync: SyncStatus.conflict);
        await db
            .into(db.syncConflicts)
            .insert(
              SyncConflictsCompanion.insert(
                id: 'administrative_documents:${uuid('d1')}',
                sourceTable: 'administrative_documents',
                recordId: uuid('d1'),
                reason: 'Refus de modification.',
                detectedAt: DateTime(2026, 10, 9),
              ),
            );
        await db
            .into(db.syncConflicts)
            .insert(
              SyncConflictsCompanion.insert(
                id: 'administrative_documents:${uuid('autre')}',
                sourceTable: 'administrative_documents',
                recordId: uuid('autre'),
                reason: 'Refus d’un autre document.',
                detectedAt: DateTime(2026, 10, 9),
              ),
            );

        await depot.retirerDocument(uuid('d1'));

        expect((await tous()).single.syncStatus, SyncStatus.pending);
        expect(
          (await db.select(db.syncConflicts).get()).map((c) => c.recordId),
          [uuid('autre')],
        );
      },
    );

    test('⚠️ un document retiré quitte la liste et les cartes', () async {
      await document('d1');
      await document('d2', actif: false, sync: SyncStatus.pending);

      final d = await depot.charger();

      expect(d.documents.map((x) => x.id), [uuid('d1')]);
      expect(d.documentsActifs, hasLength(1));
    });

    test(
      'un document en attente compte dans le badge de synchronisation',
      () async {
        await depot.creerDocument(saisie);
        await document('d2');

        expect(await db.pendingCount(), 1);
      },
    );

    test(
      '⚠️⚠️ « Générés (mois) » et « En attente » recalculés INDÉPENDAMMENT (valeurs écrites à la main)',
      () async {
        final n = DateTime.now();
        final a = n.year;
        final m = n.month;
        // (clé, date, statut, actif, synchro)
        final lignes = <(String, DateTime, String, bool, SyncStatus)>[
          ('a', DateTime(a, m, 1), 'en_attente', true, SyncStatus.synced),
          ('b', DateTime(a, m + 1, 0), 'signe', true, SyncStatus.synced),
          ('c', DateTime(a, m, 0), 'signe', true, SyncStatus.synced),
          ('d', DateTime(a, m + 1, 1), 'en_attente', true, SyncStatus.synced),
          ('e', DateTime(a - 1, m, 15), 'en_attente', true, SyncStatus.synced),
          ('f', DateTime(a, m, 10), 'en_attente', false, SyncStatus.pending),
          ('g', DateTime(a, m, 12), 'en_attente', false, SyncStatus.conflict),
          ('h', DateTime(a, m, 15), 'en_attente', true, SyncStatus.conflict),
        ];
        for (final (cle, date, statut, actif, sync) in lignes) {
          await document(
            cle,
            date: date,
            statut: statut,
            actif: actif,
            sync: sync,
          );
        }

        final d = await depot.charger();

        // Actifs : a, b, c, d, e, h (6). Dans le mois courant de l'année courante : a, b, h.
        expect(d.documentsActifs, hasLength(6));
        expect(d.generesDuMois, 3);
        // Actifs en attente de signature : a, d, e, h.
        expect(d.documentsEnAttente, 4);
        expect(
          d.documents.map((x) => x.id),
          isNot(contains(uuid('f'))),
          reason: 'retrait en attente : masqué',
        );
        expect(
          d.documents.map((x) => x.id),
          contains(uuid('g')),
          reason: 'retrait refusé : visible',
        );
      },
    );
  });

  group('synchronisation', () {
    test(
      '⚠️ envoyé avec statut, dates en Y-m-d, acquitté sur réponse',
      () async {
        final d = await depot.creerDocument(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'administrative_documents': {
              'accepted': [d.id],
              'rejected': [],
            },
          },
        );

        await moteur(serveur).synchroniser();

        final envoye =
            (serveur.envois.single['administrative_documents'] as List).single
                as Map;
        expect(envoye, {
          'id': d.id,
          'title': 'Attestation de stage',
          'type': 'Attestation',
          'beneficiary': 'AGOSSOU Félicité',
          'doc_date': '2026-07-12',
          'status': 'signe',
          'is_active': true,
        });
        final apres = (await tous()).single;
        expect(apres.syncStatus, SyncStatus.synced);
        expect(apres.knownByServer, isTrue);
      },
    );

    test('⚠️ RIEN n’est marqué synced sans l’accusé du serveur', () async {
      await depot.creerDocument(saisie);
      final serveur = _ServeurSync(); // le serveur ne répond rien

      await moteur(serveur).synchroniser();

      expect((await tous()).single.syncStatus, SyncStatus.pending);
    });

    test('⚠️ retirer part en {id, is_active: false} seulement', () async {
      await document('d1');
      await depot.retirerDocument(uuid('d1'));
      final serveur = _ServeurSync(
        reponsePush: {
          'administrative_documents': {
            'accepted': [uuid('d1')],
            'rejected': [],
          },
        },
      );

      await moteur(serveur).synchroniser();

      expect(
        (serveur.envois.single['administrative_documents'] as List).single,
        {'id': uuid('d1'), 'is_active': false},
      );
      expect((await tous()).single.syncStatus, SyncStatus.synced);
    });

    test(
      '⚠️ refusé : conflit avec motif mot pour mot, jamais réputé envoyé',
      () async {
        final d = await depot.creerDocument(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'administrative_documents': {
              'accepted': [],
              'rejected': [
                {
                  'id': d.id,
                  'reason':
                      'Votre rôle ne permet pas d\'enregistrer ou modifier un document administratif.',
                },
              ],
            },
          },
        );

        final sortie = await moteur(serveur).synchroniser();

        final apres = (await tous()).single;
        expect(apres.syncStatus, SyncStatus.conflict);
        expect(apres.knownByServer, isFalse);
        expect(sortie.rejete, 1);
        expect(sortie.motifs.join(' '), contains('Votre rôle ne permet pas'));
        final conflit = await db.select(db.syncConflicts).getSingle();
        expect(conflit.sourceTable, 'administrative_documents');
        expect(conflit.recordId, d.id);
      },
    );

    test('⚠️ un conflit se relance : le document repasse en attente', () async {
      final d = await depot.creerDocument(saisie);
      final serveur = _ServeurSync(
        reponsePush: {
          'administrative_documents': {
            'accepted': [],
            'rejected': [
              {'id': d.id, 'reason': 'Refus.'},
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
      '⚠️ TIRAGE DE CONFIRMATION : ce que le serveur a retenu arrive dans la même synchronisation',
      () async {
        final d = await depot.creerDocument(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'administrative_documents': {
              'accepted': [d.id],
              'rejected': [],
            },
          },
          tirages: [
            {'administrative_documents': <dynamic>[]},
            {
              'administrative_documents': [
                {
                  'id': d.id,
                  'title': 'Attestation de stage (serveur)',
                  'type': 'Attestation',
                  'beneficiary': 'AGOSSOU Félicité',
                  'doc_date': '2026-07-12',
                  'status': 'signe',
                  'is_active': true,
                  'updated_at': '2026-10-09T08:00:00+00:00',
                },
              ],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        expect(serveur.nombreDeTirages, 2);
        expect((await tous()).single.title, 'Attestation de stage (serveur)');
      },
    );

    test(
      '⚠️ SEULS les documents en attente partent : ni les synchronisés, ni les refusés',
      () async {
        await document('s1', titre: 'Déjà synchronisé');
        await document(
          'k1',
          titre: 'Refusé, à relancer',
          sync: SyncStatus.conflict,
          connu: false,
        );
        await document(
          'p1',
          titre: 'En attente',
          sync: SyncStatus.pending,
          connu: false,
        );
        final serveur = _ServeurSync();

        await moteur(serveur).synchroniser();

        final partis =
            (serveur.envois.single['administrative_documents'] as List)
                .cast<Map>();
        expect(partis.map((d) => d['id']), [uuid('p1')]);
      },
    );

    test('sans document accepté, pas de second tirage', () async {
      final serveur = _ServeurSync();

      await moteur(serveur).synchroniser();

      expect(serveur.nombreDeTirages, 1);
    });
  });

  group('absorbeur des documents administratifs (fusion stricte)', () {
    Map<String, dynamic> ligne(
      String cle, {
      Object? titre = 'Titre du serveur',
      Object? type = 'Attestation',
      Object? beneficiaire = 'AGOSSOU Félicité',
      Object? date = '2026-07-12',
      Object? statut = 'signe',
      Object? actif = true,
    }) => {
      'id': uuid(cle),
      'title': titre,
      'type': type,
      'beneficiary': beneficiaire,
      'doc_date': date,
      'status': statut,
      'is_active': actif,
      'updated_at': '2026-10-09T08:00:00+00:00',
    };

    test(
      '⚠️ un document du serveur est inséré, puis mis à jour par id',
      () async {
        final serveur = _ServeurSync(
          tirages: [
            {
              'administrative_documents': [
                ligne('d1', titre: 'Première version'),
              ],
            },
            {
              'administrative_documents': [
                ligne(
                  'd1',
                  titre: 'Seconde version',
                  statut: 'en_attente',
                  date: '2026-08-01',
                ),
              ],
            },
          ],
        );
        final m = moteur(serveur);

        await m.synchroniser();
        await m.synchroniser();

        final tout = await tous();
        expect(tout, hasLength(1));
        expect(tout.single.title, 'Seconde version');
        expect(tout.single.status, 'en_attente');
        expect(tout.single.docDate, DateTime(2026, 8, 1));
        expect(tout.single.syncStatus, SyncStatus.synced);
        expect(tout.single.knownByServer, isTrue);
        expect(tout.single.isActive, isTrue);
      },
    );

    test('⚠️ un type libre du serveur est gardé tel quel', () async {
      final serveur = _ServeurSync(
        tirages: [
          {
            'administrative_documents': [ligne('d1', type: 'Procès-verbal')],
          },
        ],
      );

      await moteur(serveur).synchroniser();

      expect((await tous()).single.type, 'Procès-verbal');
    });

    test(
      '⚠️⚠️ le tirage n’efface NI n’écrase un document en attente ou en conflit',
      () async {
        await document(
          'p1',
          titre: 'Saisi au poste',
          sync: SyncStatus.pending,
          connu: false,
        );
        await document(
          'k1',
          titre: 'Refusé au poste',
          sync: SyncStatus.conflict,
          connu: false,
        );
        final serveur = _ServeurSync(
          tirages: [
            {
              // p1 est servi avec un autre contenu ; k1 est absent du tirage.
              'administrative_documents': [
                ligne('p1', titre: 'Version du serveur'),
                ligne('autre', titre: 'Autre'),
              ],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        final parId = {for (final d in await tous()) d.id: d};
        expect(parId[uuid('p1')]!.title, 'Saisi au poste');
        expect(parId[uuid('p1')]!.syncStatus, SyncStatus.pending);
        expect(parId[uuid('k1')]!.title, 'Refusé au poste');
        expect(parId[uuid('k1')]!.syncStatus, SyncStatus.conflict);
        expect(parId[uuid('autre')]!.title, 'Autre');
      },
    );

    test('⚠️ un document retiré côté serveur quitte le poste', () async {
      await document('a1', titre: 'Retiré ailleurs');
      await document('b1', titre: 'Reste');
      final serveur = _ServeurSync(
        tirages: [
          {
            'administrative_documents': [
              ligne('a1', actif: false),
              ligne('b1', titre: 'Reste'),
            ],
          },
        ],
      );

      await moteur(serveur).synchroniser();

      expect((await tous()).map((d) => d.id), [uuid('b1')]);
    });

    test(
      '⚠️ un document synchronisé que le serveur ne sert plus est retiré',
      () async {
        await document('vieux');
        await document('garde');
        final serveur = _ServeurSync(
          tirages: [
            {
              'administrative_documents': [ligne('garde')],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        expect((await tous()).map((d) => d.id), [uuid('garde')]);
      },
    );

    test(
      'un retiré qui descend sans exister au poste n’est pas créé',
      () async {
        final serveur = _ServeurSync(
          tirages: [
            {
              'administrative_documents': [ligne('a1', actif: false)],
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
        final l = ligne('d1')..remove('is_active');
        final serveur = _ServeurSync(
          tirages: [
            {
              'administrative_documents': [l],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        expect((await tous()).single.isActive, isTrue);
      },
    );

    for (final (nom, mauvaise) in <(String, Map<String, dynamic>)>[
      ('titre absent', {'title': null}),
      ('titre vide', {'title': '   '}),
      ('type absent', {'type': null}),
      ('type vide', {'type': ' '}),
      ('bénéficiaire absent', {'beneficiary': null}),
      ('bénéficiaire vide', {'beneficiary': ' '}),
      ('date absente', {'doc_date': null}),
      ('date illisible', {'doc_date': 'pas-une-date'}),
      ('statut absent', {'status': null}),
      ('statut hors liste', {'status': 'brouillon'}),
      ('identifiant invalide', {'id': '1'}),
    ]) {
      test('⚠️ STRICT : $nom est REFUSÉ, rien n’est modifié', () async {
        await document('existant', titre: 'Intact');
        final serveur = _ServeurSync(
          tirages: [
            {
              'administrative_documents': [
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
          tout.map((d) => d.id),
          [uuid('existant')],
          reason: 'la transaction est annulée : ni le bon, ni la suppression',
        );
        expect(tout.single.title, 'Intact');
      });
    }
  });

  group('créer puis retirer HORS LIGNE, retrait refusé, accusé périmé', () {
    /// Serveur réaliste : il connaît les documents qu'il a ACCEPTÉS en entier, et refuse
    /// de retirer un identifiant qu'il ne connaît pas (message de
    /// `pushAdministrativeDocuments`).
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
          for (final m
              in (envoi['administrative_documents'] as List).cast<Map>()) {
            final id = m['id'] as String;
            final retrait = m['is_active'] == false;
            if (refusTout != null) {
              rejetes.add({'id': id, 'reason': refusTout});
            } else if (retrait && !vus.contains(id)) {
              rejetes.add({
                'id': id,
                'reason': 'Document inconnu : impossible de le retirer.',
              });
            } else {
              vus.add(id);
              acceptes.add(id);
            }
          }
          return {
            'administrative_documents': {
              'accepted': acceptes,
              'rejected': rejetes,
            },
          };
        },
      );
    }

    test(
      '⚠️⚠️ créé puis retiré HORS LIGNE : rien d’impossible n’est envoyé, aucun conflit',
      () async {
        final d = await depot.creerDocument(saisie);
        expect(await depot.retirerDocument(d.id), isTrue);
        final serveur = serveurRealiste();

        final sortie = await moteur(serveur).synchroniser();

        expect(
          serveur.envois.expand(
            (e) => (e['administrative_documents'] as List? ?? const []),
          ),
          isEmpty,
          reason: 'le serveur ne connaît pas ce document',
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
      '⚠️ créé, REFUSÉ, puis retiré : la ligne et son conflit disparaissent',
      () async {
        final d = await depot.creerDocument(saisie);
        final m = moteur(serveurRealiste(refusTout: 'Refus de création.'));
        await m.synchroniser();
        expect((await tous()).single.syncStatus, SyncStatus.conflict);

        await depot.retirerDocument(d.id);

        expect(await tous(), isEmpty);
        expect(await m.conflits(), isEmpty, reason: 'plus rien à relancer');
      },
    );

    test(
      '⚠️⚠️ ACQUITTÉ mais tirage de confirmation tombé en panne, puis retiré : le retrait PART',
      () async {
        final d = await depot.creerDocument(saisie);
        final connus = <String>{};
        final premier = serveurRealiste(tiragesEnPanne: {1}, connus: connus);
        await moteur(premier).synchroniser();
        expect((await tous()).single.syncStatus, SyncStatus.synced);

        await depot.retirerDocument(d.id);
        final second = serveurRealiste(connus: connus);
        final sortie = await moteur(second).synchroniser();

        expect(
          (second.envois.single['administrative_documents'] as List).single,
          {'id': d.id, 'is_active': false},
        );
        expect(sortie.rejete, 0);
        expect((await tous()).single.syncStatus, SyncStatus.synced);
      },
    );

    test(
      '⚠️⚠️ un retrait REFUSÉ reste visible : ligne conservée, motif mot pour mot, hors des cartes',
      () async {
        final n = DateTime.now();
        await document('d1', date: DateTime(n.year, n.month, 5));
        await document('d2', date: DateTime(n.year, n.month, 6));
        await depot.retirerDocument(uuid('d1'));
        const motif =
            'Votre rôle ne permet pas d\'enregistrer ou modifier un document administratif.';
        await moteur(serveurRealiste(refusTout: motif)).synchroniser();

        final d = await depot.charger();

        expect(
          d.documents.map((x) => x.id),
          containsAll([uuid('d1'), uuid('d2')]),
        );
        expect(d.refusDocuments[uuid('d1')], motif);
        expect(
          d.documentsActifs.map((x) => x.id),
          [uuid('d2')],
          reason: 'le retrait refusé ne compte pas dans les cartes',
        );
        expect(d.generesDuMois, 1);
      },
    );

    testWidgets(
      '⚠️⚠️ écran : le retrait refusé s’affiche « Archivage refusé » avec son motif, sans boutons ni statut',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        await document('d1');
        await depot.retirerDocument(uuid('d1'));
        await tester.runAsync(
          () => moteur(
            serveurRealiste(refusTout: 'Refus du serveur.'),
          ).synchroniser(),
        );

        await tester.pumpWidget(
          MaterialApp(home: AdministrationScreen(depot: depot)),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const Key('onglet-administration-Documents Administratifs'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(Key('document-refuse-${uuid('d1')}')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(find.byKey(Key('document-motif-${uuid('d1')}')))
              .data,
          'Refus du serveur.',
        );
        expect(
          find.byKey(Key('modifier-document-${uuid('d1')}')),
          findsNothing,
        );
        expect(
          find.byKey(Key('archiver-document-${uuid('d1')}')),
          findsNothing,
        );
        expect(find.byKey(const Key('documents-vide')), findsNothing);
        expect(find.text('Archivage refusé'), findsOneWidget);
        expect(
          find.text('Signé'),
          findsNothing,
          reason: 'un document retiré n’a plus de statut de signature',
        );
      },
    );

    // Une correction d'UN SEUL champ à la fois : un test qui en change plusieurs laisserait
    // survivre la comparaison de chacun des autres.
    FormulaireDocument base({
      String titre = 'Attestation de stage',
      String type = 'Attestation',
      String beneficiaire = 'AGOSSOU Félicité',
      DateTime? date,
      String statut = 'en_attente',
    }) => FormulaireDocument(
      titre: titre,
      type: type,
      beneficiaire: beneficiaire,
      date: date ?? DateTime(2026, 7, 12),
      statut: statut,
    );

    final corrections = <String, FormulaireDocument>{
      'le titre': base(titre: 'Titre corrigé pendant l’envoi'),
      'le type': base(type: 'Certificat'),
      'le bénéficiaire': base(beneficiaire: 'ZINSOU Marc'),
      'la date': base(date: DateTime(2026, 7, 13)),
      'le statut': base(statut: 'signe'),
    };

    for (final MapEntry(key: champ, value: correction) in corrections.entries) {
      test(
        '⚠️ $champ modifié PENDANT l’envoi : l’accusé de l’ancienne version ne rend pas la nouvelle « synced »',
        () async {
          final d = await depot.creerDocument(base());
          final serveur = serveurRealiste(
            pendant: () => depot.modifierDocument(d.id, correction),
          );
          await moteur(serveur).synchroniser();

          final apres = (await tous()).single;
          expect(
            apres.syncStatus,
            SyncStatus.pending,
            reason: 'la correction reste à envoyer',
          );
          expect(apres.knownByServer, isTrue, reason: 'le serveur l’a accepté');

          final suivant = serveurRealiste(connus: {d.id});
          await moteur(suivant).synchroniser();

          final envoye =
              (suivant.envois.single['administrative_documents'] as List).single
                  as Map;
          expect(envoye['title'], correction.titre);
          expect(envoye['type'], correction.type);
          expect(envoye['beneficiary'], correction.beneficiaire);
          expect(
            envoye['doc_date'],
            '2026-07-${correction.date!.day.toString().padLeft(2, '0')}',
          );
          expect(envoye['status'], correction.statut);
          expect((await tous()).single.syncStatus, SyncStatus.synced);
        },
      );
    }

    test(
      '⚠️ retiré PENDANT l’envoi : l’accusé de la version active ne masque pas le retrait',
      () async {
        await document('d1', sync: SyncStatus.pending);
        final serveur = serveurRealiste(
          pendant: () => depot.retirerDocument(uuid('d1')),
        );
        await moteur(serveur).synchroniser();

        final apres = (await tous()).single;
        expect(apres.isActive, isFalse);
        expect(apres.syncStatus, SyncStatus.pending);

        final suivant = serveurRealiste(connus: {uuid('d1')});
        await moteur(suivant).synchroniser();

        expect(
          (suivant.envois.single['administrative_documents'] as List).single,
          {'id': uuid('d1'), 'is_active': false},
        );
        expect((await tous()).single.syncStatus, SyncStatus.synced);
      },
    );

    test(
      '⚠️ refusé → corrigé → accepté : le motif périmé ne reste pas dans Synchronisation',
      () async {
        final d = await depot.creerDocument(saisie);
        final m = moteur(serveurRealiste(refusTout: 'Refus de création.'));
        await m.synchroniser();
        expect(await m.conflits(), hasLength(1));

        await depot.modifierDocument(d.id, saisie);
        expect(await m.conflits(), isEmpty, reason: 'la correction efface');
      },
    );
  });

  group('écran Synchronisation', () {
    testWidgets(
      '⚠️ un document refusé s’y nomme « Document administratif » et offre la remise en file',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        final d = await depot.creerDocument(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'administrative_documents': {
              'accepted': [],
              'rejected': [
                {'id': d.id, 'reason': 'Refus du serveur.'},
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

        expect(find.text('Document administratif'), findsOneWidget);
        expect(find.text('administrative_documents'), findsNothing);
        expect(find.byKey(Key('motif-${d.id}')), findsOneWidget);

        await tester.tap(find.byKey(Key('relancer-${d.id}')));
        await tester.pumpAndSettle();

        expect((await tous()).single.syncStatus, SyncStatus.pending);
      },
    );
  });

  group('migration v35 → v36', () {
    test(
      '⚠️ une base v35 (sans is_active, sync_status, known_by_server) garde ses documents, actifs et connus',
      () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        addTearDown(
          () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
        );
        final dossier = Directory.systemTemp.createTempSync('agrierp_v35_');
        final fichier = File('${dossier.path}${Platform.pathSeparator}v35.db');
        addTearDown(() {
          try {
            dossier.deleteSync(recursive: true);
          } catch (_) {}
        });

        final neuve = AppDatabase.forTesting(NativeDatabase(fichier));
        await neuve
            .into(neuve.administrativeDocuments)
            .insert(
              AdministrativeDocumentsCompanion.insert(
                id: uuid('d1'),
                title: 'Note de service',
                type: const Value('Note interne'),
                beneficiary: const Value('Tout le personnel'),
                status: const Value('en_attente'),
              ),
            );
        await neuve.close();

        var colonnesAvant = <String>[];
        final v35 = AppDatabase.forTesting(
          NativeDatabase(
            fichier,
            setup: (raw) {
              raw.execute(
                'ALTER TABLE administrative_documents DROP COLUMN is_active',
              );
              raw.execute(
                'ALTER TABLE administrative_documents DROP COLUMN sync_status',
              );
              raw.execute(
                'ALTER TABLE administrative_documents DROP COLUMN known_by_server',
              );
              // F0.85 (schéma v37) : une vraie base plus ancienne n'a pas non plus la date de création
              // des écritures.
              raw.execute(
                'ALTER TABLE accounting_entries DROP COLUMN created_at',
              );
              raw.execute('PRAGMA user_version = 35');
              colonnesAvant = [
                for (final l in raw.select(
                  'PRAGMA table_info(administrative_documents)',
                ))
                  l['name'] as String,
              ];
            },
          ),
        );
        final apres = await v35.select(v35.administrativeDocuments).getSingle();
        await v35.close();

        expect(colonnesAvant, isNot(contains('is_active')));
        expect(colonnesAvant, isNot(contains('sync_status')));
        expect(colonnesAvant, isNot(contains('known_by_server')));
        expect(apres.title, 'Note de service');
        expect(apres.status, 'en_attente');
        expect(apres.isActive, isTrue);
        expect(apres.syncStatus, SyncStatus.synced);
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
      await tester.tap(
        find.byKey(const Key('onglet-administration-Documents Administratifs')),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choisir(WidgetTester tester, String cle, String valeur) async {
      await tester.tap(find.byKey(Key(cle)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(valeur).last);
      await tester.pumpAndSettle();
    }

    testWidgets(
      '⚠️ « Générer un Document » : les champs de la maquette + le titre que le serveur exige, rien d’écrit si vide',
      (tester) async {
        await afficher(tester);

        expect(find.text('Générer un Document'), findsOneWidget);
        await tester.tap(find.byKey(const Key('nouveau-document')));
        await tester.pumpAndSettle();
        // ⚠️ Le titre DE LA MODALE (le bouton de l'écran porte le même libellé).
        expect(
          find.descendant(
            of: find.byType(ModaleAgri),
            matching: find.text('Générer un Document'),
          ),
          findsOneWidget,
        );
        for (final libelle in [
          'Titre du document *',
          'Type de document *',
          'Bénéficiaire *',
          'Date *',
          'Statut',
        ]) {
          expect(find.text(libelle), findsOneWidget, reason: libelle);
        }

        await tester.tap(find.byKey(const Key('document-enregistrer')));
        await tester.pumpAndSettle();

        expect(await tous(), isEmpty);
        for (final cle in ['titre', 'type', 'beneficiaire']) {
          expect(
            find.byKey(Key('document-erreur-$cle')),
            findsOneWidget,
            reason: cle,
          );
        }
        expect(
          find.byKey(const Key('document-erreur-date')),
          findsNothing,
          reason: 'préremplie au jour courant',
        );
      },
    );

    testWidgets('⚠️ la liste de types est celle de Laravel', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('nouveau-document')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-type')));
      await tester.pumpAndSettle();

      for (final t in [
        'Attestation',
        'Certificat',
        'Note interne',
        'Correspondance',
      ]) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(
        find.text('Certificat de travail'),
        findsNothing,
        reason: 'valeur de la maquette (qui sert de titre), pas un type',
      );
    });

    testWidgets(
      '⚠️ enregistrer écrit un document en attente d’envoi, daté du jour, statut « en attente »',
      (tester) async {
        await afficher(tester);

        await tester.tap(find.byKey(const Key('nouveau-document')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('document-titre')),
          'Note de service',
        );
        await choisir(tester, 'document-type', 'Note interne');
        await tester.enterText(
          find.byKey(const Key('document-beneficiaire')),
          'Tout le personnel',
        );
        await tester.tap(find.byKey(const Key('document-enregistrer')));
        await tester.pumpAndSettle();

        final d = (await tous()).single;
        expect(d.title, 'Note de service');
        expect(d.type, 'Note interne');
        expect(d.beneficiary, 'Tout le personnel');
        expect(d.docDate, jourLocal());
        expect(d.status, 'en_attente');
        expect(d.syncStatus, SyncStatus.pending);
        expect(d.knownByServer, isFalse);

        expect(find.text('Note de service'), findsOneWidget);
        expect(find.byKey(Key('document-a-envoyer-${d.id}')), findsOneWidget);
      },
    );

    testWidgets('⚠️ le statut « Signé » se choisit et s’enregistre', (
      tester,
    ) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('nouveau-document')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('document-titre')),
        'Contrat',
      );
      await choisir(tester, 'document-type', 'Correspondance');
      await tester.enterText(
        find.byKey(const Key('document-beneficiaire')),
        'PAEB',
      );
      await choisir(tester, 'document-statut', 'Signé');
      await tester.tap(find.byKey(const Key('document-enregistrer')));
      await tester.pumpAndSettle();

      expect((await tous()).single.status, 'signe');
    });

    testWidgets('modifier réécrit le document et le repasse en attente', (
      tester,
    ) async {
      await document('d1', titre: 'Ancien titre');
      await afficher(tester);

      await tester.tap(find.byKey(Key('modifier-document-${uuid('d1')}')));
      await tester.pumpAndSettle();
      expect(find.text('Modifier — Documents Administratifs'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('document-titre')),
        'Nouveau titre',
      );
      await tester.tap(find.byKey(const Key('document-enregistrer')));
      await tester.pumpAndSettle();

      final d = (await tous()).single;
      expect(d.title, 'Nouveau titre');
      expect(d.type, 'Attestation');
      expect(d.status, 'signe');
      expect(d.syncStatus, SyncStatus.pending);
    });

    testWidgets(
      '⚠️ un type reçu du serveur hors liste s’affiche et se conserve à la modification',
      (tester) async {
        await document('d1', type: 'Procès-verbal');
        await afficher(tester);
        expect(find.text('Procès-verbal'), findsOneWidget);

        await tester.tap(find.byKey(Key('modifier-document-${uuid('d1')}')));
        await tester.pumpAndSettle();
        expect(find.text('Procès-verbal'), findsWidgets);
        await tester.tap(find.byKey(const Key('document-enregistrer')));
        await tester.pumpAndSettle();

        expect((await tous()).single.type, 'Procès-verbal');
      },
    );

    testWidgets(
      '⚠️ retirer demande confirmation, nomme le document, ne supprime rien',
      (tester) async {
        await document('d1');
        await document('d2', titre: 'Autre document');
        await afficher(tester);

        await tester.tap(find.byKey(Key('archiver-document-${uuid('d1')}')));
        await tester.pumpAndSettle();
        expect(find.text("Confirmer l'archivage"), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('retrait-document-cible')))
              .data,
          'Attestation de stage',
        );
        expect(
          find.textContaining('Aucune suppression définitive'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('retrait-document-confirmer')));
        await tester.pumpAndSettle();

        final tout = await tous();
        expect(tout, hasLength(2));
        expect(tout.firstWhere((d) => d.id == uuid('d1')).isActive, isFalse);
        expect(find.text('Attestation de stage'), findsNothing);
        expect(find.text('Autre document'), findsOneWidget);
      },
    );

    testWidgets('annuler le retrait ne change rien', (tester) async {
      await document('d1');
      await afficher(tester);

      await tester.tap(find.byKey(Key('archiver-document-${uuid('d1')}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect((await tous()).single.isActive, isTrue);
      expect((await tous()).single.syncStatus, SyncStatus.synced);
    });

    testWidgets(
      '⚠️ état vide de la maquette : son bouton ouvre « Générer un Document »',
      (tester) async {
        await afficher(tester);

        expect(find.text('Aucun résultat trouvé'), findsOneWidget);
        expect(
          find.text('Essayez un autre terme ou un autre filtre.'),
          findsOneWidget,
        );
        expect(find.text('+ Générer un Document'), findsOneWidget);

        await tester.tap(find.byKey(const Key('nouveau-document-vide')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('document-enregistrer')), findsOneWidget);
      },
    );

    testWidgets('l’état vide disparaît dès qu’il y a un document', (
      tester,
    ) async {
      await document('d1');
      await afficher(tester);

      expect(find.byKey(const Key('documents-vide')), findsNothing);
    });

    testWidgets(
      '⚠️ statut et état d’envoi : « Signé » / « En attente » + « À envoyer » tant que non acquitté',
      (tester) async {
        await document('a', titre: 'Doc A', statut: 'signe');
        await document(
          'b',
          titre: 'Doc B',
          statut: 'en_attente',
          sync: SyncStatus.pending,
          connu: false,
        );
        await afficher(tester);

        expect(find.text('Signé'), findsOneWidget);
        expect(
          find.byKey(Key('document-a-envoyer-${uuid('b')}')),
          findsOneWidget,
        );
        expect(
          find.byKey(Key('document-a-envoyer-${uuid('a')}')),
          findsNothing,
        );
      },
    );

    testWidgets(
      '⚠️⚠️ la mention du poste ne promet aucun fichier : « Générer » n’écrit qu’une ligne de registre',
      (tester) async {
        await afficher(tester);

        expect(
          find.textContaining('aucun fichier'),
          findsOneWidget,
          reason: 'risque de promesse trompeuse du libellé de la maquette',
        );
      },
    );

    testWidgets(
      '⚠️⚠️ CARTES : « Modèles disponibles » est un TIRET (jamais 0), « Générés (mois) » et « En attente » recalculés',
      (tester) async {
        final n = DateTime.now();
        await document(
          'a',
          date: DateTime(n.year, n.month, 3),
          statut: 'en_attente',
        );
        await document(
          'b',
          date: DateTime(n.year, n.month, 4),
          statut: 'signe',
        );
        await document(
          'c',
          date: DateTime(n.year, n.month, 0),
          statut: 'en_attente',
        );
        await document(
          'd',
          date: DateTime(n.year, n.month, 5),
          statut: 'en_attente',
          actif: false,
          sync: SyncStatus.pending,
        );
        await afficher(tester);

        final cartes = tester
            .widgetList<CarteKpi>(find.byType(CarteKpi))
            .toList();

        expect(cartes.map((c) => c.libelle), [
          'Modèles disponibles',
          'Générés (mois)',
          'En attente',
        ]);
        expect(cartes[0].valeur, '—');
        expect(
          cartes[0].legende,
          isNotNull,
          reason: 'un tiret sans légende ne dit pas pourquoi',
        );
        expect(cartes[1].valeur, '2', reason: 'a et b ; c = mois précédent');
        expect(cartes[2].valeur, '2', reason: 'a et c ; d est retiré');
        expect(
          cartes.map((c) => c.libelle),
          isNot(contains('Documents')),
          reason: 'carte du poste absente de la maquette, retirée',
        );
        expect(cartes.map((c) => c.libelle), isNot(contains('Signés')));
      },
    );

    testWidgets(
      'sans aucun document, « Générés (mois) » vaut 0 (mesuré) et « En attente » 0',
      (tester) async {
        await afficher(tester);

        final cartes = tester
            .widgetList<CarteKpi>(find.byType(CarteKpi))
            .toList();
        expect(cartes[0].valeur, '—');
        expect(cartes[1].valeur, '0');
        expect(cartes[2].valeur, '0');
      },
    );

    test(
      '⚠️⚠️ les libellés de cartes de l’écran sont ceux de documents-administratifs.html (lus dans la maquette)',
      () {
        final maquette = File(
          'C:/Projects/agrierp_laravel/prototype_html/documents-administratifs.html',
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
          'Modèles disponibles',
          'Générés (mois)',
        ], reason: 'la maquette a changé : revoir les cartes');

        final ecran = File(
          'lib/features/administration/administration_screen.dart',
        ).readAsStringSync();
        final debut = ecran.indexOf('Widget _ongletDocuments');
        final fin = ecran.indexOf('// ── Briques communes');
        expect(debut, isNonNegative);
        expect(fin, greaterThan(debut));
        final onglet = ecran.substring(debut, fin);
        final presentes = [
          for (final m in RegExp(
            r"CarteKpi\(\s*libelle: '([^']+)'",
          ).allMatches(onglet))
            m.group(1)!,
        ];

        // Les deux cartes de la maquette, dans son ordre, puis l'écart assumé.
        expect(presentes.take(2).toList(), attendus);
        expect(presentes, [...attendus, 'En attente']);
      },
    );
  });
}
