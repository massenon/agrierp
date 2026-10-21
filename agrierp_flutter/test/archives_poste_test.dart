import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
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

/// Ticket F0.79 — DOCUMENTS ARCHIVÉS SAISIS, MODIFIÉS, RETIRÉS AU POSTE
/// (`archivage-documents.html`, 2e moitié du ticket 8.2).
///
/// ⚠️⚠️ **LOCAL D'ABORD, SYNCHRONISÉ ENSUITE**, comme les courriers (F0.78) : le document est
/// écrit `pending`, le serveur le valide. Le STATUT (Valide / Bientôt expiré / Expiré) n'est
/// ni stocké ni envoyé : il se déduit de l'échéance, avec la règle du serveur (15.24).
///
/// ⚠️⚠️ **ET LE TIRAGE FUSIONNE** : l'ancien absorbeur effaçait toute la table avant de
/// réinsérer, ce qui aurait fait disparaître un document saisi et pas encore acquitté.
void main() {
  late AppDatabase db;
  late AdministrationRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  DateTime jourLocal() {
    final n = HeureBenin.maintenant();
    return DateTime(n.year, n.month, n.day);
  }

  /// Le jour de l'essai, décalé d'un nombre de jours CALENDAIRES (sans passer par une
  /// durée de 24 h, que le changement d'heure fausserait).
  DateTime dans(int jours) {
    final j = jourLocal();
    return DateTime(j.year, j.month, j.day + jours);
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
    String titre = 'Registre du Commerce (RCCM)',
    String? categorie = 'Juridique',
    DateTime? archive,
    DateTime? echeance,
    bool actif = true,
    SyncStatus statut = SyncStatus.synced,
    bool connu = true,
  }) => db
      .into(db.archivedDocuments)
      .insert(
        ArchivedDocumentsCompanion.insert(
          id: uuid(cle),
          title: titre,
          category: Value(categorie),
          archivedDate: Value(archive ?? DateTime(2026, 1, 2)),
          expiryDate: Value(echeance),
          isActive: Value(actif),
          syncStatus: Value(statut),
          knownByServer: Value(connu),
        ),
      );

  Future<List<ArchivedDocument>> tous() =>
      db.select(db.archivedDocuments).get();

  final saisie = FormulaireArchive(
    titre: '  Attestation Fiscale  ',
    categorie: ' Fiscal ',
    dateArchivage: DateTime(2026, 3, 15, 14, 30),
    echeance: DateTime(2026, 9, 15, 8),
  );

  group('statut d’échéance (règle du serveur, 15.24)', () {
    // ⚠️ RECALCUL INDÉPENDANT : les résultats attendus sont écrits À LA MAIN, par date
    // calendaire, jamais recalculés par la même arithmétique que le code.
    // Aujourd'hui = 9 octobre 2026.
    final aujourdhui = DateTime(2026, 10, 9);

    final attendus = <(String, DateTime?, StatutArchive)>[
      ('sans échéance', null, StatutArchive.valide),
      ('passée depuis longtemps', DateTime(2025, 1, 1), StatutArchive.expire),
      ('hier (-1)', DateTime(2026, 10, 8), StatutArchive.expire),
      ('aujourd’hui (0)', DateTime(2026, 10, 9), StatutArchive.expire),
      ('demain (+1)', DateTime(2026, 10, 10), StatutArchive.bientotExpire),
      ('+29 jours', DateTime(2026, 11, 7), StatutArchive.bientotExpire),
      ('+30 jours', DateTime(2026, 11, 8), StatutArchive.bientotExpire),
      ('+31 jours', DateTime(2026, 11, 9), StatutArchive.valide),
      ('+32 jours', DateTime(2026, 11, 10), StatutArchive.valide),
      ('+200 jours', DateTime(2027, 4, 27), StatutArchive.valide),
    ];

    for (final (nom, echeance, statut) in attendus) {
      test('⚠️ $nom → ${statut.libelle}', () {
        expect(
          AdministrationRepository.statutArchive(echeance, aujourdhui),
          statut,
        );
      });
    }

    test(
      '⚠️⚠️ les HEURES sont ignorées, des deux côtés (jours calendaires)',
      () {
        for (final heureDuPoste in [
          DateTime(2026, 10, 9, 0, 0, 1),
          DateTime(2026, 10, 9, 12),
          DateTime(2026, 10, 9, 23, 59, 59),
        ]) {
          for (final (nom, echeance, statut) in attendus) {
            if (echeance == null) continue;
            for (final heureEcheance in [0, 13, 23]) {
              final e = DateTime(
                echeance.year,
                echeance.month,
                echeance.day,
                heureEcheance,
                heureEcheance == 0 ? 0 : 59,
              );
              expect(
                AdministrationRepository.statutArchive(e, heureDuPoste),
                statut,
                reason: '$nom, poste à $heureDuPoste, échéance à $e',
              );
            }
          }
        }
      },
    );

    test('⚠️ le seuil franchit un changement de mois et d’année', () {
      // 15/12/2026 + 30 jours = 14/01/2027 (bientôt) ; + 31 = 15/01/2027 (valide).
      final jour = DateTime(2026, 12, 15);
      expect(
        AdministrationRepository.statutArchive(DateTime(2027, 1, 14), jour),
        StatutArchive.bientotExpire,
      );
      expect(
        AdministrationRepository.statutArchive(DateTime(2027, 1, 15), jour),
        StatutArchive.valide,
      );
    });

    test('les libellés sont ceux du serveur', () {
      expect(StatutArchive.valide.libelle, 'Valide');
      expect(StatutArchive.bientotExpire.libelle, 'Bientôt expiré');
      expect(StatutArchive.expire.libelle, 'Expiré');
    });
  });

  group('règles de saisie (identiques à ArchiveDocumentService, Laravel)', () {
    FormulaireArchive f({
      String titre = 'Titre',
      String categorie = 'Fiscal',
      DateTime? archive,
      DateTime? echeance,
    }) => FormulaireArchive(
      titre: titre,
      categorie: categorie,
      dateArchivage: archive ?? DateTime(2026, 3, 15),
      echeance: echeance,
    );

    test('titre, catégorie et date d’archivage sont obligatoires', () {
      final e = AdministrationRepository.validerArchive(
        const FormulaireArchive(),
      );

      expect(e.keys, containsAll(['titre', 'categorie', 'dateArchivage']));
      expect(e.containsKey('echeance'), isFalse);
      expect(e['titre'], 'Le champ « Nom du document » est obligatoire.');
      expect(e['categorie'], 'Le champ « Catégorie » est obligatoire.');
    });

    test('titre ≤ 255 : la limite passe, un de plus non', () {
      expect(
        AdministrationRepository.validerArchive(f(titre: 't' * 255)),
        isEmpty,
      );
      expect(
        AdministrationRepository.validerArchive(f(titre: 't' * 256)).keys,
        ['titre'],
      );
    });

    test(
      'catégorie ≤ 100 (colonne du serveur) : la limite passe, un de plus non',
      () {
        expect(
          AdministrationRepository.validerArchive(f(categorie: 'c' * 100)),
          isEmpty,
        );
        expect(
          AdministrationRepository.validerArchive(f(categorie: 'c' * 101)).keys,
          ['categorie'],
        );
      },
    );

    test('une catégorie libre (hors liste proposée) est acceptée', () {
      expect(
        AdministrationRepository.validerArchive(f(categorie: 'Agréments')),
        isEmpty,
      );
    });

    test('un champ fait d’espaces est vide', () {
      final e = AdministrationRepository.validerArchive(
        f(titre: '   ', categorie: '   '),
      );

      expect(e.keys, containsAll(['titre', 'categorie']));
    });

    test(
      '⚠️ l’échéance ne précède jamais la date d’archivage (égale : permis)',
      () {
        final archive = DateTime(2026, 3, 15);

        expect(
          AdministrationRepository.validerArchive(
            f(archive: archive, echeance: DateTime(2026, 3, 15)),
          ),
          isEmpty,
          reason: 'après_ou_égale',
        );
        expect(
          AdministrationRepository.validerArchive(
            f(archive: archive, echeance: DateTime(2026, 3, 14)),
          ).keys,
          ['echeance'],
        );
        expect(
          AdministrationRepository.validerArchive(
            f(archive: archive, echeance: DateTime(2026, 3, 16)),
          ),
          isEmpty,
        );
      },
    );

    test(
      '⚠️ la comparaison ignore l’heure (même jour, heure antérieure : permis)',
      () {
        expect(
          AdministrationRepository.validerArchive(
            f(
              archive: DateTime(2026, 3, 15, 18),
              echeance: DateTime(2026, 3, 15, 8),
            ),
          ),
          isEmpty,
        );
      },
    );

    test('créer ou modifier une saisie invalide n’écrit rien', () async {
      await expectLater(
        depot.creerArchive(const FormulaireArchive()),
        throwsArgumentError,
      );
      expect(await tous(), isEmpty);

      await document('d1');
      await expectLater(
        depot.modifierArchive(uuid('d1'), const FormulaireArchive()),
        throwsArgumentError,
      );
      expect((await tous()).single.syncStatus, SyncStatus.synced);
    });
  });

  group('dépôt', () {
    test(
      '⚠️ créé en attente, UUID du poste, jours sans heure, JAMAIS connu du serveur',
      () async {
        final a = await depot.creerArchive(saisie);

        expect(a.id, hasLength(36));
        expect(a.title, 'Attestation Fiscale');
        expect(a.category, 'Fiscal');
        expect(a.archivedDate, DateTime(2026, 3, 15));
        expect(a.expiryDate, DateTime(2026, 9, 15));
        expect(a.isActive, isTrue);
        expect(a.syncStatus, SyncStatus.pending);
        expect(a.knownByServer, isFalse);
      },
    );

    test(
      'une échéance absente reste absente (jamais une date inventée)',
      () async {
        final a = await depot.creerArchive(
          FormulaireArchive(
            titre: 'RCCM',
            categorie: 'Juridique',
            dateArchivage: DateTime(2026, 1, 2),
          ),
        );

        expect(a.expiryDate, isNull);
      },
    );

    test(
      '⚠️ modifier repasse en attente et GARDE « connu du serveur »',
      () async {
        await document('d1');

        final a = await depot.modifierArchive(
          uuid('d1'),
          FormulaireArchive(
            titre: 'RCCM 2026',
            categorie: 'Autre',
            dateArchivage: DateTime(2026, 1, 2),
            echeance: DateTime(2027, 1, 2),
          ),
        );

        expect(a.title, 'RCCM 2026');
        expect(a.category, 'Autre');
        expect(a.expiryDate, DateTime(2027, 1, 2));
        expect(a.syncStatus, SyncStatus.pending);
        expect(a.knownByServer, isTrue);
      },
    );

    test('⚠️ modifier peut EFFACER l’échéance', () async {
      await document('d1', echeance: DateTime(2027, 1, 2));

      final a = await depot.modifierArchive(
        uuid('d1'),
        FormulaireArchive(
          titre: 'RCCM',
          categorie: 'Juridique',
          dateArchivage: DateTime(2026, 1, 2),
        ),
      );

      expect(a.expiryDate, isNull);
    });

    test('⚠️ un document retiré ne se modifie plus', () async {
      await document('d1', actif: false);

      await expectLater(
        depot.modifierArchive(uuid('d1'), saisie),
        throwsStateError,
      );
      expect((await tous()).single.title, 'Registre du Commerce (RCCM)');
    });

    test('⚠️ corriger une ligne REFUSÉE efface son refus', () async {
      await document('d1', statut: SyncStatus.conflict);
      await db
          .into(db.syncConflicts)
          .insert(
            SyncConflictsCompanion.insert(
              id: 'archived_documents:${uuid('d1')}',
              sourceTable: 'archived_documents',
              recordId: uuid('d1'),
              reason: 'Refus.',
              detectedAt: DateTime(2026, 10, 9),
            ),
          );

      await depot.modifierArchive(uuid('d1'), saisie);

      expect(await db.select(db.syncConflicts).get(), isEmpty);
    });

    test(
      '⚠️ retirer ne supprime rien, passe en attente, et est idempotent',
      () async {
        await document('d1');

        expect(await depot.retirerArchive(uuid('d1')), isTrue);
        final a = (await tous()).single;
        expect(a.isActive, isFalse);
        expect(a.syncStatus, SyncStatus.pending);

        expect(
          await depot.retirerArchive(uuid('d1')),
          isFalse,
          reason: 'déjà retiré : rien à faire',
        );
        expect(await depot.retirerArchive(uuid('inconnu')), isFalse);
        expect(await tous(), hasLength(1));
      },
    );

    test('⚠️ un document retiré quitte la liste et les cartes', () async {
      await document('d1', echeance: dans(10));
      await document('d2', echeance: dans(10), actif: false);

      final d = await depot.charger();

      expect(d.archives.map((a) => a.id), [uuid('d1')]);
      expect(d.archivesActives, hasLength(1));
      expect(d.bientotExpirees(jourLocal()), hasLength(1));
    });

    test(
      'un document en attente compte dans le badge de synchronisation',
      () async {
        await depot.creerArchive(saisie);
        await document('d2');

        expect(await db.pendingCount(), 1);
      },
    );

    test(
      '⚠️ les trois compteurs recalculés INDÉPENDAMMENT (valeurs écrites à la main)',
      () async {
        // (décalage en jours, actif)
        final lignes = <(String, int?, bool, SyncStatus)>[
          ('a', -5, true, SyncStatus.synced), // expiré
          ('b', 0, true, SyncStatus.synced), // expiré (aujourd'hui)
          ('c', 1, true, SyncStatus.synced), // bientôt
          ('d', 30, true, SyncStatus.synced), // bientôt
          ('e', 31, true, SyncStatus.synced), // valide
          ('f', 400, true, SyncStatus.synced), // valide
          ('g', null, true, SyncStatus.synced), // valide, sans échéance
          ('h', 10, false, SyncStatus.pending), // retiré : ne compte pas
          (
            'i',
            5,
            false,
            SyncStatus.conflict,
          ), // retrait refusé : ne compte pas
          ('j', -3, false, SyncStatus.pending), // retiré expiré : ne compte pas
        ];
        for (final (cle, decalage, actif, statut) in lignes) {
          await document(
            cle,
            echeance: decalage == null ? null : dans(decalage),
            actif: actif,
            statut: statut,
          );
        }

        final d = await depot.charger();

        // 7 actifs ; bientôt expirés : c, d ; expirés : a, b.
        expect(d.archivesActives, hasLength(7));
        expect(d.bientotExpirees(jourLocal()), hasLength(2));
        expect(d.expirees(jourLocal()), hasLength(2));
        expect(
          d.archives.map((a) => a.id),
          isNot(contains(uuid('h'))),
          reason: 'retrait en attente : masqué',
        );
        expect(
          d.archives.map((a) => a.id),
          contains(uuid('i')),
          reason: 'retrait refusé : visible',
        );
      },
    );
  });

  group('synchronisation', () {
    test(
      '⚠️ envoyé SANS statut, dates en Y-m-d, acquitté sur réponse',
      () async {
        final a = await depot.creerArchive(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'archived_documents': {
              'accepted': [a.id],
              'rejected': [],
            },
          },
        );

        await moteur(serveur).synchroniser();

        final envoye =
            (serveur.envois.single['archived_documents'] as List).single as Map;
        expect(envoye, {
          'id': a.id,
          'title': 'Attestation Fiscale',
          'category': 'Fiscal',
          'archived_date': '2026-03-15',
          'expiry_date': '2026-09-15',
          'is_active': true,
        });
        expect(envoye.containsKey('status'), isFalse);
        final apres = (await tous()).single;
        expect(apres.syncStatus, SyncStatus.synced);
        expect(apres.knownByServer, isTrue);
      },
    );

    test('⚠️ une échéance absente part en null', () async {
      await depot.creerArchive(
        FormulaireArchive(
          titre: 'RCCM',
          categorie: 'Juridique',
          dateArchivage: DateTime(2026, 1, 2),
        ),
      );
      final serveur = _ServeurSync();

      await moteur(serveur).synchroniser();

      final envoye =
          (serveur.envois.single['archived_documents'] as List).single as Map;
      expect(envoye['expiry_date'], isNull);
      expect(envoye.containsKey('expiry_date'), isTrue);
    });

    test('⚠️ RIEN n’est marqué synced sans l’accusé du serveur', () async {
      await depot.creerArchive(saisie);
      final serveur = _ServeurSync(); // le serveur ne répond rien

      await moteur(serveur).synchroniser();

      expect((await tous()).single.syncStatus, SyncStatus.pending);
    });

    test('⚠️ retirer part en {id, is_active: false} seulement', () async {
      await document('d1');
      await depot.retirerArchive(uuid('d1'));
      final serveur = _ServeurSync(
        reponsePush: {
          'archived_documents': {
            'accepted': [uuid('d1')],
            'rejected': [],
          },
        },
      );

      await moteur(serveur).synchroniser();

      expect((serveur.envois.single['archived_documents'] as List).single, {
        'id': uuid('d1'),
        'is_active': false,
      });
      expect((await tous()).single.syncStatus, SyncStatus.synced);
    });

    test(
      '⚠️ refusé : conflit avec motif mot pour mot, jamais réputé envoyé',
      () async {
        final a = await depot.creerArchive(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'archived_documents': {
              'accepted': [],
              'rejected': [
                {
                  'id': a.id,
                  'reason':
                      'Votre rôle ne permet pas d\'archiver ou modifier un document.',
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
        expect(conflit.sourceTable, 'archived_documents');
        expect(conflit.recordId, a.id);
      },
    );

    test('⚠️ un conflit se relance : le document repasse en attente', () async {
      final a = await depot.creerArchive(saisie);
      final serveur = _ServeurSync(
        reponsePush: {
          'archived_documents': {
            'accepted': [],
            'rejected': [
              {'id': a.id, 'reason': 'Refus.'},
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
        final a = await depot.creerArchive(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'archived_documents': {
              'accepted': [a.id],
              'rejected': [],
            },
          },
          tirages: [
            {'archived_documents': <dynamic>[]},
            {
              'archived_documents': [
                {
                  'id': a.id,
                  'title': 'Attestation Fiscale (serveur)',
                  'category': 'Fiscal',
                  'archived_date': '2026-03-15',
                  'expiry_date': '2026-09-15',
                  'is_active': true,
                  'updated_at': '2026-10-09T08:00:00+00:00',
                },
              ],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        expect(serveur.nombreDeTirages, 2);
        expect((await tous()).single.title, 'Attestation Fiscale (serveur)');
      },
    );

    test('sans document accepté, pas de second tirage', () async {
      final serveur = _ServeurSync();

      await moteur(serveur).synchroniser();

      expect(serveur.nombreDeTirages, 1);
    });
  });

  group('absorbeur des archives (fusion stricte)', () {
    Map<String, dynamic> ligne(
      String cle, {
      Object? titre = 'Titre du serveur',
      Object? categorie = 'Juridique',
      Object? archive = '2026-01-02',
      Object? echeance,
      Object? actif = true,
    }) => {
      'id': uuid(cle),
      'title': titre,
      'category': categorie,
      'archived_date': archive,
      'expiry_date': echeance,
      'is_active': actif,
      'updated_at': '2026-10-09T08:00:00+00:00',
    };

    test(
      '⚠️ un document du serveur est inséré, puis mis à jour par id',
      () async {
        final serveur = _ServeurSync(
          tirages: [
            {
              'archived_documents': [ligne('d1', titre: 'Première version')],
            },
            {
              'archived_documents': [
                ligne('d1', titre: 'Seconde version', echeance: '2027-05-01'),
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
        expect(tout.single.expiryDate, DateTime(2027, 5, 1));
        expect(tout.single.syncStatus, SyncStatus.synced);
        expect(tout.single.knownByServer, isTrue);
      },
    );

    test('⚠️ une catégorie libre du serveur est gardée telle quelle', () async {
      final serveur = _ServeurSync(
        tirages: [
          {
            'archived_documents': [ligne('d1', categorie: 'Agréments')],
          },
        ],
      );

      await moteur(serveur).synchroniser();

      expect((await tous()).single.category, 'Agréments');
    });

    test(
      '⚠️⚠️ le tirage n’efface NI n’écrase un document en attente ou en conflit',
      () async {
        await document(
          'p1',
          titre: 'Saisi au poste',
          statut: SyncStatus.pending,
          connu: false,
        );
        await document(
          'k1',
          titre: 'Refusé au poste',
          statut: SyncStatus.conflict,
          connu: false,
        );
        final serveur = _ServeurSync(
          tirages: [
            {
              // p1 est servi avec un autre contenu ; k1 est absent du tirage.
              'archived_documents': [
                ligne('p1', titre: 'Version du serveur'),
                ligne('autre', titre: 'Autre'),
              ],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        final parId = {for (final a in await tous()) a.id: a};
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
            'archived_documents': [
              ligne('a1', actif: false),
              ligne('b1', titre: 'Reste'),
            ],
          },
        ],
      );

      await moteur(serveur).synchroniser();

      expect((await tous()).map((a) => a.id), [uuid('b1')]);
    });

    test(
      '⚠️ un document synchronisé que le serveur ne sert plus est retiré',
      () async {
        await document('vieux');
        await document('garde');
        final serveur = _ServeurSync(
          tirages: [
            {
              'archived_documents': [ligne('garde')],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        expect((await tous()).map((a) => a.id), [uuid('garde')]);
      },
    );

    test(
      'un retiré qui descend sans exister au poste n’est pas créé',
      () async {
        final serveur = _ServeurSync(
          tirages: [
            {
              'archived_documents': [ligne('a1', actif: false)],
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
              'archived_documents': [l],
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
      ('catégorie absente', {'category': null}),
      ('catégorie vide', {'category': ' '}),
      ('date d’archivage absente', {'archived_date': null}),
      ('date d’archivage illisible', {'archived_date': 'pas-une-date'}),
      ('échéance illisible', {'expiry_date': 'pas-une-date'}),
      ('identifiant invalide', {'id': '1'}),
    ]) {
      test('⚠️ STRICT : $nom est REFUSÉ, rien n’est modifié', () async {
        await document('existant', titre: 'Intact');
        final serveur = _ServeurSync(
          tirages: [
            {
              'archived_documents': [
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
          tout.map((a) => a.id),
          [uuid('existant')],
          reason: 'la transaction est annulée : ni le bon, ni la suppression',
        );
        expect(tout.single.title, 'Intact');
      });
    }
  });

  group('créer puis retirer HORS LIGNE, retrait refusé, accusé périmé', () {
    /// Serveur réaliste : il connaît les documents qu'il a ACCEPTÉS en entier, et refuse
    /// de retirer un identifiant qu'il ne connaît pas (message de `pushArchivedDocuments`).
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
          for (final m in (envoi['archived_documents'] as List).cast<Map>()) {
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
            'archived_documents': {'accepted': acceptes, 'rejected': rejetes},
          };
        },
      );
    }

    test(
      '⚠️⚠️ créé puis retiré HORS LIGNE : rien d’impossible n’est envoyé, aucun conflit',
      () async {
        final a = await depot.creerArchive(saisie);
        expect(await depot.retirerArchive(a.id), isTrue);
        final serveur = serveurRealiste();

        final sortie = await moteur(serveur).synchroniser();

        expect(
          serveur.envois.expand(
            (e) => (e['archived_documents'] as List? ?? const []),
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
        final a = await depot.creerArchive(saisie);
        final m = moteur(serveurRealiste(refusTout: 'Refus de création.'));
        await m.synchroniser();
        expect((await tous()).single.syncStatus, SyncStatus.conflict);

        await depot.retirerArchive(a.id);

        expect(await tous(), isEmpty);
        expect(await m.conflits(), isEmpty, reason: 'plus rien à relancer');
      },
    );

    test(
      '⚠️⚠️ ACQUITTÉ mais tirage de confirmation tombé en panne, puis retiré : le retrait PART',
      () async {
        final a = await depot.creerArchive(saisie);
        final connus = <String>{};
        final premier = serveurRealiste(tiragesEnPanne: {1}, connus: connus);
        await moteur(premier).synchroniser();
        expect((await tous()).single.syncStatus, SyncStatus.synced);

        await depot.retirerArchive(a.id);
        final second = serveurRealiste(connus: connus);
        final sortie = await moteur(second).synchroniser();

        expect((second.envois.single['archived_documents'] as List).single, {
          'id': a.id,
          'is_active': false,
        });
        expect(sortie.rejete, 0);
        expect((await tous()).single.syncStatus, SyncStatus.synced);
      },
    );

    test(
      '⚠️⚠️ un retrait REFUSÉ reste visible : ligne conservée, motif mot pour mot, hors des cartes',
      () async {
        await document('d1', echeance: dans(10));
        await document('d2', echeance: dans(10));
        await depot.retirerArchive(uuid('d1'));
        const motif =
            'Votre rôle ne permet pas d\'archiver ou modifier un document.';
        await moteur(serveurRealiste(refusTout: motif)).synchroniser();

        final d = await depot.charger();

        expect(
          d.archives.map((a) => a.id),
          containsAll([uuid('d1'), uuid('d2')]),
        );
        expect(d.refusArchives[uuid('d1')], motif);
        expect(
          d.archivesActives.map((a) => a.id),
          [uuid('d2')],
          reason: 'le retrait refusé ne compte pas dans les cartes',
        );
        expect(d.bientotExpirees(jourLocal()), hasLength(1));
      },
    );

    testWidgets(
      '⚠️⚠️ écran : le retrait refusé s’affiche « Archivage refusé » avec son motif, sans boutons',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        await document('d1');
        await depot.retirerArchive(uuid('d1'));
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
            const Key('onglet-administration-Archivage des Documents'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(Key('archive-refuse-${uuid('d1')}')), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(Key('archive-motif-${uuid('d1')}')))
              .data,
          'Refus du serveur.',
        );
        expect(find.byKey(Key('modifier-archive-${uuid('d1')}')), findsNothing);
        expect(find.byKey(Key('archiver-archive-${uuid('d1')}')), findsNothing);
        expect(find.byKey(const Key('archives-vide')), findsNothing);
        expect(find.text('Archivage refusé'), findsOneWidget);
        expect(
          find.text('Valide'),
          findsNothing,
          reason: 'un document retiré n’a plus de statut d’échéance',
        );
      },
    );

    // Une correction d'UN SEUL champ à la fois : un test qui en change plusieurs laisserait
    // survivre la comparaison de chacun des autres.
    final corrections = <String, FormulaireArchive>{
      'le titre': FormulaireArchive(
        titre: 'Titre corrigé pendant l’envoi',
        categorie: 'Fiscal',
        dateArchivage: DateTime(2026, 3, 15),
        echeance: DateTime(2026, 9, 15),
      ),
      'la catégorie': FormulaireArchive(
        titre: 'Attestation Fiscale',
        categorie: 'Autre',
        dateArchivage: DateTime(2026, 3, 15),
        echeance: DateTime(2026, 9, 15),
      ),
      'la date d’archivage': FormulaireArchive(
        titre: 'Attestation Fiscale',
        categorie: 'Fiscal',
        dateArchivage: DateTime(2026, 3, 16),
        echeance: DateTime(2026, 9, 15),
      ),
      'l’échéance (changée)': FormulaireArchive(
        titre: 'Attestation Fiscale',
        categorie: 'Fiscal',
        dateArchivage: DateTime(2026, 3, 15),
        echeance: DateTime(2026, 9, 20),
      ),
      'l’échéance (effacée)': FormulaireArchive(
        titre: 'Attestation Fiscale',
        categorie: 'Fiscal',
        dateArchivage: DateTime(2026, 3, 15),
      ),
    };

    for (final MapEntry(key: champ, value: correction) in corrections.entries) {
      test(
        '⚠️ $champ modifié PENDANT l’envoi : l’accusé de l’ancienne version ne rend pas la nouvelle « synced »',
        () async {
          final a = await depot.creerArchive(
            FormulaireArchive(
              titre: 'Attestation Fiscale',
              categorie: 'Fiscal',
              dateArchivage: DateTime(2026, 3, 15),
              echeance: DateTime(2026, 9, 15),
            ),
          );
          final serveur = serveurRealiste(
            pendant: () => depot.modifierArchive(a.id, correction),
          );
          await moteur(serveur).synchroniser();

          final apres = (await tous()).single;
          expect(
            apres.syncStatus,
            SyncStatus.pending,
            reason: 'la correction reste à envoyer',
          );
          expect(apres.knownByServer, isTrue, reason: 'le serveur l’a accepté');

          final suivant = serveurRealiste(connus: {a.id});
          await moteur(suivant).synchroniser();

          final envoye =
              (suivant.envois.single['archived_documents'] as List).single
                  as Map;
          expect(envoye['title'], correction.titre);
          expect(envoye['category'], correction.categorie);
          expect(
            envoye['archived_date'],
            '2026-03-${correction.dateArchivage!.day}',
          );
          expect(
            envoye['expiry_date'],
            correction.echeance == null
                ? isNull
                : '2026-09-${correction.echeance!.day}',
          );
          expect((await tous()).single.syncStatus, SyncStatus.synced);
        },
      );
    }

    test(
      '⚠️ retiré PENDANT l’envoi : l’accusé de la version active ne masque pas le retrait',
      () async {
        await document('d1', statut: SyncStatus.pending);
        final serveur = serveurRealiste(
          pendant: () => depot.retirerArchive(uuid('d1')),
        );
        await moteur(serveur).synchroniser();

        final apres = (await tous()).single;
        expect(apres.isActive, isFalse);
        expect(apres.syncStatus, SyncStatus.pending);

        final suivant = serveurRealiste(connus: {uuid('d1')});
        await moteur(suivant).synchroniser();

        expect((suivant.envois.single['archived_documents'] as List).single, {
          'id': uuid('d1'),
          'is_active': false,
        });
        expect((await tous()).single.syncStatus, SyncStatus.synced);
      },
    );
  });

  group('écran Synchronisation', () {
    testWidgets(
      '⚠️ un document refusé s’y nomme « Document archivé » et offre la remise en file',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        final a = await depot.creerArchive(saisie);
        final serveur = _ServeurSync(
          reponsePush: {
            'archived_documents': {
              'accepted': [],
              'rejected': [
                {'id': a.id, 'reason': 'Refus du serveur.'},
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

        expect(find.text('Document archivé'), findsOneWidget);
        expect(find.text('archived_documents'), findsNothing);
        expect(find.byKey(Key('motif-${a.id}')), findsOneWidget);

        await tester.tap(find.byKey(Key('relancer-${a.id}')));
        await tester.pumpAndSettle();

        expect((await tous()).single.syncStatus, SyncStatus.pending);
      },
    );
  });

  group('migration v34 → v35', () {
    test(
      '⚠️ une base v34 (sans is_active, sync_status, known_by_server) garde ses documents, actifs et connus',
      () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        addTearDown(
          () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
        );
        final dossier = Directory.systemTemp.createTempSync('agrierp_v34_');
        final fichier = File('${dossier.path}${Platform.pathSeparator}v34.db');
        addTearDown(() {
          try {
            dossier.deleteSync(recursive: true);
          } catch (_) {}
        });

        final neuve = AppDatabase.forTesting(NativeDatabase(fichier));
        await neuve
            .into(neuve.archivedDocuments)
            .insert(
              ArchivedDocumentsCompanion.insert(
                id: uuid('d1'),
                title: 'Agrément vétérinaire',
                category: const Value('Agréments'),
                expiryDate: Value(DateTime(2027, 1, 2)),
              ),
            );
        await neuve.close();

        var colonnesAvant = <String>[];
        final v34 = AppDatabase.forTesting(
          NativeDatabase(
            fichier,
            setup: (raw) {
              raw.execute(
                'ALTER TABLE archived_documents DROP COLUMN is_active',
              );
              raw.execute(
                'ALTER TABLE archived_documents DROP COLUMN sync_status',
              );
              raw.execute(
                'ALTER TABLE archived_documents DROP COLUMN known_by_server',
              );
              // F0.80 : une vraie base v34 n'a pas non plus les colonnes des documents
              // administratifs (schéma v36).
              for (final c in ['is_active', 'sync_status', 'known_by_server']) {
                raw.execute(
                  'ALTER TABLE administrative_documents DROP COLUMN $c',
                );
              }
              // F0.85 (schéma v37) : une vraie base plus ancienne n'a pas non plus la date de création
              // des écritures.
              raw.execute(
                'ALTER TABLE accounting_entries DROP COLUMN created_at',
              );
              raw.execute('PRAGMA user_version = 34');
              colonnesAvant = [
                for (final l in raw.select(
                  'PRAGMA table_info(archived_documents)',
                ))
                  l['name'] as String,
              ];
            },
          ),
        );
        final apres = await v34.select(v34.archivedDocuments).getSingle();
        await v34.close();

        expect(colonnesAvant, isNot(contains('is_active')));
        expect(colonnesAvant, isNot(contains('sync_status')));
        expect(colonnesAvant, isNot(contains('known_by_server')));
        expect(apres.title, 'Agrément vétérinaire');
        expect(apres.category, 'Agréments');
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
        find.byKey(const Key('onglet-administration-Archivage des Documents')),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choisirCategorie(WidgetTester tester, String categorie) async {
      await tester.tap(find.byKey(const Key('archive-categorie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(categorie).last);
      await tester.pumpAndSettle();
    }

    testWidgets(
      '⚠️ « Archiver un Document » : quatre champs de la maquette + date d’archivage, rien d’écrit si vide',
      (tester) async {
        await afficher(tester);

        await tester.tap(find.byKey(const Key('nouveau-archive')));
        await tester.pumpAndSettle();
        expect(find.text('Archiver un Document'), findsWidgets);
        for (final libelle in [
          'Nom du document *',
          'Catégorie *',
          // Ticket MP1 : le libellé d'un champ Date est celui du Blade, `uppercase` compris (`ChampDateFormulaire`).
          "DATE D'ARCHIVAGE *",
          "DATE D'EXPIRATION",
        ]) {
          expect(find.text(libelle), findsOneWidget, reason: libelle);
        }

        await tester.tap(find.byKey(const Key('archive-enregistrer')));
        await tester.pumpAndSettle();

        expect(await tous(), isEmpty);
        expect(find.byKey(const Key('archive-erreur-titre')), findsOneWidget);
        expect(
          find.byKey(const Key('archive-erreur-categorie')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('archive-erreur-dateArchivage')),
          findsNothing,
          reason: 'préremplie au jour courant',
        );
      },
    );

    testWidgets('⚠️ la liste de catégories est celle de Laravel', (
      tester,
    ) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('nouveau-archive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('archive-categorie')));
      await tester.pumpAndSettle();

      for (final c in [
        'Juridique',
        'Fiscal',
        'Sanitaire',
        'Foncier',
        'Autre',
      ]) {
        expect(find.text(c), findsWidgets, reason: c);
      }
      expect(
        find.text('RH'),
        findsNothing,
        reason: 'catégorie de la maquette, pas du serveur',
      );
    });

    testWidgets(
      '⚠️ enregistrer écrit un document en attente, date d’archivage du jour',
      (tester) async {
        await afficher(tester);

        await tester.tap(find.byKey(const Key('nouveau-archive')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('archive-titre')),
          'Attestation Fiscale',
        );
        await choisirCategorie(tester, 'Fiscal');
        await tester.tap(find.byKey(const Key('archive-enregistrer')));
        await tester.pumpAndSettle();

        final a = (await tous()).single;
        expect(a.title, 'Attestation Fiscale');
        expect(a.category, 'Fiscal');
        expect(a.archivedDate, jourLocal());
        expect(a.expiryDate, isNull);
        expect(a.syncStatus, SyncStatus.pending);
        expect(a.knownByServer, isFalse);

        expect(find.text('Attestation Fiscale'), findsOneWidget);
        expect(find.byKey(Key('archive-a-envoyer-${a.id}')), findsOneWidget);
      },
    );

    testWidgets('⚠️ une échéance choisie est enregistrée, et effaçable', (
      tester,
    ) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('nouveau-archive')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('archive-titre')), 'Bail');
      await choisirCategorie(tester, 'Foncier');
      await tester.tap(find.byKey(const Key('archive-echeance')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('archive-echeance-effacer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('archive-echeance-effacer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('archive-echeance-effacer')), findsNothing);
      await tester.tap(find.byKey(const Key('archive-enregistrer')));
      await tester.pumpAndSettle();

      expect((await tous()).single.expiryDate, isNull);
    });

    testWidgets('⚠️ échéance antérieure à l’archivage : refusée à l’écran', (
      tester,
    ) async {
      // Archivé dans 10 jours, sans échéance : le sélecteur d'échéance propose « aujourd'hui »
      // (valeur initiale), donc ANTÉRIEURE à l'archivage.
      await document('d1', archive: dans(10));
      await afficher(tester);

      await tester.tap(find.byKey(Key('modifier-archive-${uuid('d1')}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('archive-echeance')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('archive-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('archive-erreur-echeance')), findsOneWidget);
      expect((await tous()).single.syncStatus, SyncStatus.synced);
    });

    testWidgets('modifier réécrit le document et le repasse en attente', (
      tester,
    ) async {
      await document('d1', titre: 'Ancien titre');
      await afficher(tester);

      await tester.tap(find.byKey(Key('modifier-archive-${uuid('d1')}')));
      await tester.pumpAndSettle();
      expect(find.text('Modifier — Archivage des Documents'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('archive-titre')),
        'Nouveau titre',
      );
      await tester.tap(find.byKey(const Key('archive-enregistrer')));
      await tester.pumpAndSettle();

      final a = (await tous()).single;
      expect(a.title, 'Nouveau titre');
      expect(a.category, 'Juridique');
      expect(a.syncStatus, SyncStatus.pending);
    });

    testWidgets(
      '⚠️ une catégorie reçue du serveur hors liste s’affiche et se conserve à la modification',
      (tester) async {
        await document('d1', categorie: 'Agréments');
        await afficher(tester);
        expect(find.text('Agréments'), findsOneWidget);

        await tester.tap(find.byKey(Key('modifier-archive-${uuid('d1')}')));
        await tester.pumpAndSettle();
        expect(find.text('Agréments'), findsWidgets);
        await tester.tap(find.byKey(const Key('archive-enregistrer')));
        await tester.pumpAndSettle();

        expect((await tous()).single.category, 'Agréments');
      },
    );

    testWidgets(
      '⚠️ retirer demande confirmation, nomme le document, ne supprime rien',
      (tester) async {
        await document('d1');
        await document('d2', titre: 'Autre document');
        await afficher(tester);

        await tester.tap(find.byKey(Key('archiver-archive-${uuid('d1')}')));
        await tester.pumpAndSettle();
        expect(find.text("Confirmer l'archivage"), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('retrait-archive-cible')))
              .data,
          'Registre du Commerce (RCCM)',
        );
        expect(
          find.textContaining('Aucune suppression définitive'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('retrait-archive-confirmer')));
        await tester.pumpAndSettle();

        final tout = await tous();
        expect(tout, hasLength(2));
        expect(tout.firstWhere((a) => a.id == uuid('d1')).isActive, isFalse);
        expect(find.text('Registre du Commerce (RCCM)'), findsNothing);
        expect(find.text('Autre document'), findsOneWidget);
      },
    );

    testWidgets('annuler le retrait ne change rien', (tester) async {
      await document('d1');
      await afficher(tester);

      await tester.tap(find.byKey(Key('archiver-archive-${uuid('d1')}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect((await tous()).single.isActive, isTrue);
      expect((await tous()).single.syncStatus, SyncStatus.synced);
    });

    testWidgets(
      '⚠️ état vide de la maquette : son bouton ouvre « Archiver un Document »',
      (tester) async {
        await afficher(tester);

        expect(find.text('Aucun résultat trouvé'), findsOneWidget);
        expect(
          find.text('Essayez un autre terme ou un autre filtre.'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('nouveau-archive-vide')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('archive-enregistrer')), findsOneWidget);
      },
    );

    testWidgets('l’état vide disparaît dès qu’il y a un document', (
      tester,
    ) async {
      await document('d1');
      await afficher(tester);

      expect(find.byKey(const Key('archives-vide')), findsNothing);
    });

    testWidgets(
      '⚠️⚠️ les pastilles de statut suivent la règle du serveur, une par ligne',
      (tester) async {
        await document('a', titre: 'Doc A', echeance: dans(-1));
        await document('b', titre: 'Doc B', echeance: dans(0));
        await document('c', titre: 'Doc C', echeance: dans(1));
        await document('d', titre: 'Doc D', echeance: dans(30));
        await document('e', titre: 'Doc E', echeance: dans(31));
        await document('f', titre: 'Doc F');
        await afficher(tester);

        // 2 expirés (A, B), 2 bientôt expirés (C, D), 2 valides (E, F).
        expect(find.text('Expiré'), findsNWidgets(2));
        expect(find.text('Bientôt expiré'), findsNWidgets(2));
        expect(find.text('Valide'), findsNWidgets(2));
        expect(find.text('À renouveler'), findsNothing);
        expect(find.text('Sans échéance'), findsNothing);
      },
    );

    testWidgets(
      '⚠️⚠️ LIBELLÉS ET VALEURS DES CARTES : celles de la maquette, plus l’alerte « Expirés »',
      (tester) async {
        await document('a', echeance: dans(-5));
        await document('b', echeance: dans(0));
        await document('c', echeance: dans(1));
        await document('d', echeance: dans(30));
        await document('e', echeance: dans(31));
        await document('f');
        await document(
          'h',
          echeance: dans(-40),
        ); // 3e expiré : « Expirés » ≠ « bientôt »
        await document('g', echeance: dans(10), actif: false);
        // Un retrait REFUSÉ reste dans la liste, mais ne compte dans aucune carte.
        await document(
          'i',
          echeance: dans(5),
          actif: false,
          statut: SyncStatus.conflict,
        );
        await afficher(tester);

        final cartes = tester
            .widgetList<CarteKpi>(find.byType(CarteKpi))
            .toList();

        expect(cartes.map((c) => c.libelle), [
          'Documents archivés',
          'Expirant sous 30j',
          'Expirés',
        ]);
        expect(
          cartes[0].valeur,
          '7',
          reason: 'les actifs seulement (a à f et h)',
        );
        expect(cartes[1].valeur, '2', reason: 'jours 1 et 30');
        expect(cartes[2].valeur, '3', reason: 'jours -5, 0 et -40');
        expect(
          cartes.map((c) => c.libelle),
          isNot(contains('À renouveler')),
          reason:
              'seuil de 60 j retiré : ni la maquette ni le serveur ne l’ont',
        );
      },
    );

    test(
      '⚠️⚠️ les libellés de cartes de l’écran sont ceux de archivage-documents.html (lus dans la maquette)',
      () {
        final maquette = File(
          '$dossierPrototype/archivage-documents.html',
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
          'Documents archivés',
          'Expirant sous 30j',
        ], reason: 'la maquette a changé : revoir les cartes');

        final ecran = File(
          'lib/features/administration/administration_screen.dart',
        ).readAsStringSync();
        final debut = ecran.indexOf('Widget _ongletArchives');
        final fin = ecran.indexOf('Widget _celluleArchive');
        final onglet = ecran.substring(debut, fin);
        final presentes = [
          for (final m in RegExp(
            r"CarteKpi\(\s*libelle: '([^']+)'",
          ).allMatches(onglet))
            m.group(1)!,
        ];

        // Les deux cartes de la maquette, dans son ordre, puis l'écart assumé.
        expect(presentes.take(2).toList(), attendus);
        expect(presentes, [...attendus, 'Expirés']);
      },
    );
  });
}
