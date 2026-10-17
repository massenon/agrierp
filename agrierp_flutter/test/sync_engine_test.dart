import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 0 Flutter — MOTEUR DE SYNCHRONISATION.
///
/// Les invariants testés ici sont ceux dont la violation ne lève AUCUNE erreur
/// et se voit seulement des semaines plus tard, quand des saisies manquent.
class _ConnectiviteFeinte implements Connectivity {
  _ConnectiviteFeinte(this.enLigne);

  final bool enLigne;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      enLigne ? [ConnectivityResult.wifi] : [ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Intercepte les appels HTTP pour rendre la réponse serveur voulue.
class _ServeurFeint extends Interceptor {
  _ServeurFeint({this.pull = const {}, this.push = const {}});

  final Map<String, dynamic> pull;
  final Map<String, dynamic> push;

  final List<Map<String, dynamic>> corpsRecus = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final estPush = options.path.contains('push');

    if (estPush && options.data is Map<String, dynamic>) {
      corpsRecus.add(options.data as Map<String, dynamic>);
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: estPush ? push : pull,
      ),
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  SyncEngine moteur(_ServeurFeint serveur, {bool enLigne = true}) {
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'));
    client.interceptors.add(serveur);

    return SyncEngine(
      database: db,
      client: client,
      deviceId: 'poste-test',
      connectivity: _ConnectiviteFeinte(enLigne),
    );
  }

  Future<void> ficheEnAttente(String id) async {
    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: 'lot-0000-0000-0000-0000-00000000000$id'.substring(0, 36),
            code: 'AVI-2026-01',
            speciesId: 'esp-0000-0000-0000-0000-000000000001',
          ),
        );

    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: id,
            deviceId: 'poste-test',
            updatedAt: DateTime(2026, 8, 17),
            lotId: 'lot-0000-0000-0000-0000-00000000000$id'.substring(0, 36),
            entryDate: DateTime(2026, 8, 17),
          ),
        );
  }

  /// ⚠️ HORS LIGNE N'EST PAS UNE ERREUR — c'est le mode normal de cette ferme.
  test('hors ligne : rien n\'est envoye et rien n\'est perdu', () async {
    await ficheEnAttente('11111111-1111-4111-8111-111111111111');

    final serveur = _ServeurFeint();
    final resultat = await moteur(serveur, enLigne: false).synchroniser();

    expect(resultat.horsLigne, isTrue);
    expect(serveur.corpsRecus, isEmpty, reason: 'aucun appel reseau');
    expect(await db.pendingCount(), 1, reason: 'la saisie reste en file');
  });

  /// LE FLUX NOMINAL : accusé du serveur, puis acquittement local.
  test('une fiche acceptee par le serveur quitte la file', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ficheEnAttente(id);

    final serveur = _ServeurFeint(
      push: {
        'livestock_daily_entries': {
          'accepted': [id],
          'rejected': [],
        },
      },
    );

    final resultat = await moteur(serveur).synchroniser();

    expect(resultat.accepte, 1);
    expect(await db.pendingCount(), 0);
  });

  /// ⚠️ L'INVARIANT LE PLUS IMPORTANT. Un enregistrement REFUSÉ reste dans la
  /// file : le marquer synchronisé le ferait disparaître de l'appareil sans
  /// qu'il existe nulle part ailleurs.
  test('une fiche refusee reste dans la file, avec son motif', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ficheEnAttente(id);

    final serveur = _ServeurFeint(
      push: {
        'livestock_daily_entries': {
          'accepted': <String>[],
          'rejected': [
            {'id': id, 'reason': 'lot_id inconnu du serveur'},
          ],
        },
      },
    );

    final resultat = await moteur(serveur).synchroniser();

    expect(resultat.accepte, 0);
    expect(resultat.rejete, 1);
    expect(resultat.motifs.first, contains('lot_id'));
    expect(
      await db.pendingCount(),
      1,
      reason: 'un refus ne doit jamais vider la file',
    );
  });

  /// ⚠️ UN REFUS SORT DES ENVOIS AUTOMATIQUES. Laissé `pending`, il repartait
  /// à chaque synchronisation et se faisait refuser à chaque fois : une boucle
  /// silencieuse que personne ne pouvait diagnostiquer.
  test('un refus n est plus renvoye automatiquement', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ficheEnAttente(id);

    final refus = _ServeurFeint(
      push: {
        'livestock_daily_entries': {
          'accepted': <String>[],
          'rejected': [
            {'id': id, 'reason': 'lot_id inconnu du serveur'},
          ],
        },
      },
    );

    await moteur(refus).synchroniser();

    // Seconde tentative : le serveur ne doit plus rien recevoir.
    final second = _ServeurFeint(push: {});
    await moteur(second).synchroniser();

    final envoye = second.corpsRecus.isEmpty
        ? null
        : second.corpsRecus.single['livestock_daily_entries'] as List?;

    expect(
      envoye ?? const [],
      isEmpty,
      reason: 'un refus attend une correction, pas un renvoi en boucle',
    );
  });

  /// Le motif est conservé, consultable après coup.
  test('le motif du refus est conserve', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ficheEnAttente(id);

    final serveur = _ServeurFeint(
      push: {
        'livestock_daily_entries': {
          'accepted': <String>[],
          'rejected': [
            {'id': id, 'reason': 'lot_id inconnu du serveur'},
          ],
        },
      },
    );

    final m = moteur(serveur);
    await m.synchroniser();

    final conflits = await m.conflits();

    expect(conflits, hasLength(1));
    expect(conflits.single.recordId, id);
    expect(conflits.single.sourceTable, 'livestock_daily_entries');
    expect(conflits.single.reason, 'lot_id inconnu du serveur');
  });

  /// ⚠️ Un refus RÉPÉTÉ met à jour le motif au lieu d'empiler des doublons.
  test('un refus repete n empile pas les conflits', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ficheEnAttente(id);

    Future<void> refuser(String motif) async {
      final m = moteur(
        _ServeurFeint(
          push: {
            'livestock_daily_entries': {
              'accepted': <String>[],
              'rejected': [
                {'id': id, 'reason': motif},
              ],
            },
          },
        ),
      );
      // On relance pour que la fiche reparte en file avant le second refus.
      for (final c in await m.conflits()) {
        await m.relancer(c);
      }
      await m.synchroniser();
    }

    await refuser('premier motif');
    await refuser('second motif');

    final m = moteur(_ServeurFeint());
    final conflits = await m.conflits();

    expect(conflits, hasLength(1));
    expect(conflits.single.reason, 'second motif');
  });

  /// La relance remet l'enregistrement en file et referme le conflit.
  test('la relance remet en file et referme le conflit', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ficheEnAttente(id);

    final refus = moteur(
      _ServeurFeint(
        push: {
          'livestock_daily_entries': {
            'accepted': <String>[],
            'rejected': [
              {'id': id, 'reason': 'lot_id inconnu du serveur'},
            ],
          },
        },
      ),
    );
    await refus.synchroniser();

    final conflits = await refus.conflits();
    await refus.relancer(conflits.single);

    expect(await refus.conflits(), isEmpty);

    // La fiche repart réellement.
    final second = _ServeurFeint(
      push: {
        'livestock_daily_entries': {
          'accepted': [id],
          'rejected': [],
        },
      },
    );
    final resultat = await moteur(second).synchroniser();

    expect(resultat.accepte, 1);
    expect(await db.pendingCount(), 0);
  });

  /// ⚠️ Une réponse serveur muette ne vaut pas acquittement.
  test('une reponse sans accuse laisse la file intacte', () async {
    await ficheEnAttente('11111111-1111-4111-8111-111111111111');

    final resultat = await moteur(_ServeurFeint(push: {})).synchroniser();

    expect(resultat.accepte, 0);
    expect(await db.pendingCount(), 1);
  });

  /// Le tirage précède l'envoi : les référentiels arrivent d'abord.
  test('le tirage precede l envoi', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ficheEnAttente(id);

    final serveur = _ServeurFeint(
      pull: {
        'server_time': '2026-08-17T12:00:00+00:00',
        'product_categories': [
          {
            'id': 'cat-1111-1111-1111-1111-111111111111',
            'label': 'Volailles',
            'is_active': true,
          },
        ],
        'products': <dynamic>[],
        'livestock_lots': <dynamic>[],
      },
      push: {
        'livestock_daily_entries': {
          'accepted': [id],
          'rejected': [],
        },
      },
    );

    final resultat = await moteur(serveur).synchroniser();

    expect(resultat.tire, 1, reason: 'la categorie tiree est absorbee');
    expect(await db.select(db.productCategories).get(), hasLength(1));
  });

  /// ⚠️ L'HORODATAGE DU TIRAGE VIENT DU SERVEUR, jamais de l'appareil : une
  /// horloge locale décalée ferait sauter ou rejouer des changements.
  test('l horodatage retenu est celui du serveur', () async {
    final serveur = _ServeurFeint(
      pull: {
        'server_time': '2026-08-17T12:00:00.000Z',
        'product_categories': <dynamic>[],
        'products': <dynamic>[],
        'livestock_lots': <dynamic>[],
      },
    );

    await moteur(serveur).synchroniser();

    final etat = await db.select(db.syncState).getSingle();
    expect(etat.lastPulledAt!.toUtc(), DateTime.utc(2026, 8, 17, 12));
  });

  /// ⚠️ UNE ACTION D'AUDIT ARRIVE EN INSTANT AVEC DÉCALAGE (`+01:00`, serveur en
  /// Africa/Porto-Novo) ET SE LIT EN HEURE LOCALE DU POSTE — c'est ce que
  /// « Mon Profil » affiche (ticket F0.57). Le même instant, deux écritures.
  test('une action d audit tiree est ramenee a l heure locale', () async {
    final serveur = _ServeurFeint(
      pull: {
        'server_time': '2026-08-17T12:00:00.000Z',
        'product_categories': <dynamic>[],
        'products': <dynamic>[],
        'livestock_lots': <dynamic>[],
        'audit_logs': [
          {
            'id': '22222222-2222-4222-8222-222222222222',
            'user_name': 'Manager Olouwachegoun',
            'action': 'login',
            'module': 'auth',
            'ip_address': '192.168.1.42',
            'created_at': '2026-07-28T06:14:00+01:00',
          },
        ],
      },
    );

    await moteur(serveur).synchroniser();

    final ligne = await db.select(db.auditLogs).getSingle();
    expect(ligne.createdAt!.toUtc(), DateTime.utc(2026, 7, 28, 5, 14));
    expect(ligne.createdAt!.isUtc, isFalse);
  });

  /// ⚠️ LES NOTIFICATIONS SONT REMPLACÉES EN BLOC À CHAQUE TIRAGE (ticket F0.59) :
  /// « lue » et « supprimée » ne touchent pas `created_at`, un tirage
  /// incrémental ne les verrait jamais. Une notification supprimée ailleurs doit
  /// donc DISPARAÎTRE d'ici, et la catégorie est celle du serveur.
  test('les notifications tirées remplacent les anciennes', () async {
    Map<String, dynamic> ligne(String id, String categorie, bool lue) => {
      'id': id,
      'type': 'stock_low',
      'category': categorie,
      'severity': 'critique',
      'title': 'Seuil',
      'message': 'Vaccin Newcastle (2 boîtes)',
      'link_url': '/gestion-stocks',
      'is_read': lue,
      'created_at': '2026-07-28T06:12:00+01:00',
    };

    Map<String, dynamic> tirage(List<Map<String, dynamic>> notifications) => {
      'server_time': '2026-08-17T12:00:00.000Z',
      'product_categories': <dynamic>[],
      'products': <dynamic>[],
      'livestock_lots': <dynamic>[],
      'notifications': notifications,
    };

    const a = '33333333-3333-4333-8333-333333333333';
    const b = '44444444-4444-4444-8444-444444444444';

    await moteur(
      _ServeurFeint(
        pull: tirage([ligne(a, 'Stocks', false), ligne(b, 'RH', true)]),
      ),
    ).synchroniser();

    var lignes = await db.select(db.notifications).get();
    expect(lignes, hasLength(2));
    expect(lignes.firstWhere((l) => l.id == b).category, 'RH');
    expect(lignes.firstWhere((l) => l.id == b).isRead, isTrue);

    // Deuxième tirage : `b` a été supprimée côté serveur, `a` est devenue lue.
    await moteur(
      _ServeurFeint(pull: tirage([ligne(a, 'Stocks', true)])),
    ).synchroniser();

    lignes = await db.select(db.notifications).get();
    expect(lignes.map((l) => l.id), [a]);
    expect(lignes.single.isRead, isTrue);
  });

  /// 🔴 ⚠️⚠️ **LA TROISIÈME SYNCHRONISATION D'UNE MÊME BASE ÉCHOUAIT POUR
  /// TOUJOURS** (découvert au ticket F0.63). Chaque tirage insérait une ligne
  /// `sync_state` SANS identifiant : SQLite en attribuait un nouveau au lieu de
  /// mettre à jour la ligne 1, et `getSingleOrNull()` levait « Too many elements »
  /// dès le troisième passage. Aucun test ne synchronisait trois fois ; l'échec ne
  /// se voyait qu'en usage réel — une ferme qui synchronise chaque jour y arrive
  /// le troisième jour.
  test("⚠️⚠️ dix synchronisations de suite, une seule ligne d'état", () async {
    final tirage = {
      'server_time': '2026-08-17T12:00:00.000Z',
      'product_categories': <dynamic>[],
      'products': <dynamic>[],
      'livestock_lots': <dynamic>[],
    };

    for (var i = 1; i <= 10; i++) {
      await moteur(_ServeurFeint(pull: tirage)).synchroniser();
    }

    final lignes = await db.select(db.syncState).get();
    expect(lignes, hasLength(1));
    expect(lignes.single.id, 1);
    expect(lignes.single.lastPulledAt, isNotNull);
  });

  test(
    "un tirage ne retire pas la date du dernier envoi, ni l'inverse",
    () async {
      await db.noterEtatDeSynchronisation(
        tire: DateTime.utc(2026, 8, 1),
        envoye: DateTime.utc(2026, 8, 2),
      );
      await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 8, 3));

      final e = (await db.etatDeSynchronisation())!;
      expect(e.lastPulledAt!.toUtc(), DateTime.utc(2026, 8, 3));
      expect(e.lastPushedAt!.toUtc(), DateTime.utc(2026, 8, 2));

      await db.noterEtatDeSynchronisation(envoye: DateTime.utc(2026, 8, 4));

      final f = (await db.etatDeSynchronisation())!;
      expect(f.lastPulledAt!.toUtc(), DateTime.utc(2026, 8, 3));
      expect(f.lastPushedAt!.toUtc(), DateTime.utc(2026, 8, 4));
    },
  );

  test('⚠️ une base DÉJÀ abîmée (deux lignes) se lit puis se répare', () async {
    // L'état laissé par l'ancien défaut sur un poste réel.
    await db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            id: const Value(1),
            lastPulledAt: Value(DateTime.utc(2026, 8, 1)),
          ),
        );
    await db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            id: const Value(2),
            lastPulledAt: Value(DateTime.utc(2026, 8, 5)),
            lastPushedAt: Value(DateTime.utc(2026, 8, 6)),
          ),
        );

    // La lecture ne lève pas, et retient les dates LES PLUS RÉCENTES.
    final e = (await db.etatDeSynchronisation())!;
    expect(e.lastPulledAt!.toUtc(), DateTime.utc(2026, 8, 5));
    expect(e.lastPushedAt!.toUtc(), DateTime.utc(2026, 8, 6));

    // Une synchronisation sur cette base fonctionne et la ramène à une ligne.
    await moteur(
      _ServeurFeint(
        pull: {
          'server_time': '2026-08-17T12:00:00.000Z',
          'product_categories': <dynamic>[],
          'products': <dynamic>[],
          'livestock_lots': <dynamic>[],
        },
      ),
    ).synchroniser();

    final lignes = await db.select(db.syncState).get();
    expect(lignes, hasLength(1));
    expect(lignes.single.lastPulledAt!.toUtc(), DateTime.utc(2026, 8, 17, 12));
    expect(lignes.single.lastPushedAt!.toUtc(), DateTime.utc(2026, 8, 6));
  });

  /// ⚠️ LES REVENUS PAR BANDE SONT REMPLACÉS EN BLOC, ET LEUR DATE EST GARDÉE À
  /// PART (ticket F0.63). Trois cas : un tirage qui les apporte, un tirage qui les
  /// apporte VIDES (« aucune vente » est une réponse), un tirage qui ne les envoie
  /// pas (un serveur plus ancien : on n'efface rien).
  test('les revenus par bande sont remplacés et datés', () async {
    Map<String, dynamic> tirage(Object? revenus) => {
      'server_time': '2026-08-17T12:00:00.000Z',
      'product_categories': <dynamic>[],
      'products': <dynamic>[],
      'livestock_lots': <dynamic>[],
      'lot_revenues': ?revenus,
    };

    const lot = '55555555-5555-4555-8555-555555555555';
    const produitA = '66666666-6666-4666-8666-666666666666';
    const produitB = '77777777-7777-4777-8777-777777777777';

    Map<String, dynamic> ligne(String produit, double montant) => {
      'lot_id': lot,
      'product_id': produit,
      'label': 'Ventes — $produit',
      'amount': montant,
    };

    Future<String?> date() async =>
        (await (db.select(db.appSettings)
                  ..where((s) => s.key.equals(SyncEngine.cleRevenusTires)))
                .getSingleOrNull())
            ?.value;

    // 1. Jamais reçus : aucune date.
    expect(await date(), isNull);

    // 2. Un tirage qui les apporte.
    await moteur(
      _ServeurFeint(
        pull: tirage([ligne(produitA, 45000), ligne(produitB, 15000)]),
      ),
    ).synchroniser();
    expect(await db.select(db.lotRevenues).get(), hasLength(2));
    final premiere = await date();
    expect(premiere, isNotNull);

    // 3. Un tirage qui NE les envoie PAS : rien n'est effacé.
    await moteur(_ServeurFeint(pull: tirage(null))).synchroniser();
    expect(await db.select(db.lotRevenues).get(), hasLength(2));

    // 4. Un tirage qui les apporte VIDES : tout est remplacé, la date avance.
    await moteur(_ServeurFeint(pull: tirage(<dynamic>[]))).synchroniser();
    expect(await db.select(db.lotRevenues).get(), isEmpty);
    expect(await date(), isNotNull);
  });

  /// La date d'une fiche part au format `Y-m-d`, jamais en ISO complet : le
  /// serveur compare à une colonne DATE, et un ISO ferait dupliquer la fiche.
  test('la date de fiche part au format jour', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ficheEnAttente(id);

    final serveur = _ServeurFeint(
      push: {
        'livestock_daily_entries': {
          'accepted': [id],
          'rejected': [],
        },
      },
    );

    await moteur(serveur).synchroniser();

    final envoye = serveur.corpsRecus.single['livestock_daily_entries'] as List;
    expect((envoye.single as Map)['entry_date'], '2026-08-17');
  });

  /// 🔴→✅ TICKET 14.71 / F0.31 — L'HEURE REELLE DE LA VENTE PART AVEC ELLE.
  ///
  /// ⚠️⚠️ ELLE NE PARTAIT PAS. Le poste tenait `sales.sold_at` depuis toujours
  /// et ne l'envoyait jamais ; le serveur, faute de colonne, datait la vente de
  /// sa RECEPTION. Une vente encaissee hors ligne le 12 et remontee le 20
  /// passait donc son ecriture SYSCOHADA au 20 et sortait les tetes de la fiche
  /// d'elevage du 20. Le defaut ne se manifeste que sur un poste reste
  /// longtemps deconnecte — la situation meme pour laquelle ce mode existe.
  ///
  /// ⚠️ FORMAT LOCAL `Y-m-d H:i:s`, SANS CONVERSION UTC : le serveur tourne en
  /// Africa/Porto-Novo. Un `toUtc()` reculerait d'une heure et ferait basculer
  /// de jour toute vente d'avant 01h00 — le defaut corrige, reintroduit par
  /// l'autre bout.
  test('l heure reelle de la vente part avec la vente', () async {
    const id = '22222222-2222-4222-8222-222222222222';
    const produit = '33333333-3333-4333-8333-333333333333';

    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: id,
            deviceId: 'poste-test',
            updatedAt: DateTime(2026, 8, 20, 9, 5),
            paymentMode: 'especes',
            total: 21000,
            soldAt: DateTime(2026, 8, 12, 14, 30, 5),
          ),
        );

    await db
        .into(db.saleLines)
        .insert(
          SaleLinesCompanion.insert(
            id: '44444444-4444-4444-8444-444444444444',
            saleId: id,
            productId: produit,
            qty: 6,
            unitPrice: 3500,
            manualTotalAmount: 21000,
          ),
        );

    final serveur = _ServeurFeint(
      push: {
        'sales': {
          'accepted': [id],
          'rejected': [],
        },
      },
    );

    await moteur(serveur).synchroniser();

    final envoye = serveur.corpsRecus.single['sales'] as List;
    expect((envoye.single as Map)['sold_at'], '2026-08-12 14:30:05');
  });

  /// ⚠️⚠️ TICKET F0.35 — LA SAILLIE DÉCLARÉE AU CLAPIER PART AU TIRAGE.
  ///
  /// ⚠️ **SEULS LES CINQ CHAMPS DE LA DÉCLARATION SONT ENVOYÉS.** Statut,
  /// échéances et résultats de mise bas sont calculés ou saisis côté serveur :
  /// les joindre laisserait croire que le poste peut les corriger, alors que
  /// ce canal n'ouvre que la CRÉATION.
  test('la saillie declaree part avec ses cinq champs', () async {
    const id = '55555555-5555-4555-8555-555555555555';
    const lot = 'lot-cuni-0000-0000-0000-000000000001';

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: lot.padRight(36, '0').substring(0, 36),
            code: 'LOT-LAP-2026-06',
            speciesId: 'esp-cuniculture',
          ),
        );

    await db
        .into(db.livestockReproductionEvents)
        .insert(
          LivestockReproductionEventsCompanion.insert(
            id: id,
            deviceId: 'poste-test',
            updatedAt: DateTime(2026, 8, 20, 9),
            lotId: lot.padRight(36, '0').substring(0, 36),
            motherRef: 'R8',
            sireRef: const Value('M2'),
            saillieDate: Value(DateTime(2026, 8, 12)),
          ),
        );

    final serveur = _ServeurFeint(
      push: {
        'livestock_reproduction_events': {
          'accepted': [id],
          'rejected': [],
        },
      },
    );

    await moteur(serveur).synchroniser();

    final envoye =
        serveur.corpsRecus.single['livestock_reproduction_events'] as List;
    final saillie = envoye.single as Map;

    expect(saillie['mother_ref'], 'R8');
    expect(saillie['sire_ref'], 'M2');
    expect(saillie['saillie_date'], '2026-08-12');
    expect(saillie.containsKey('status'), isFalse);
    expect(saillie.containsKey('mise_bas_date_actual'), isFalse);
  });

  /// ⚠️⚠️ **UNE DÉCLARATION EN ATTENTE SURVIT AU TIRAGE.** Elle n'existe pas
  /// encore côté serveur : la remplacer par la charge du tirage l'effacerait
  /// purement et simplement, et l'animalier n'aurait aucun moyen de le savoir.
  test('une saillie en attente n est pas ecrasee par le tirage', () async {
    const id = '66666666-6666-4666-8666-666666666666';
    const lot = 'lot-cuni-0000-0000-0000-000000000002';

    await db
        .into(db.livestockReproductionEvents)
        .insert(
          LivestockReproductionEventsCompanion.insert(
            id: id,
            deviceId: 'poste-test',
            updatedAt: DateTime(2026, 8, 20, 9),
            lotId: lot.padRight(36, '0').substring(0, 36),
            motherRef: 'R8',
            saillieDate: Value(DateTime(2026, 8, 12)),
          ),
        );

    // Le serveur ne la connait pas encore et ne renvoie qu'un autre cycle.
    final serveur = _ServeurFeint(
      pull: {
        'server_time': '2026-08-20T10:00:00Z',
        'livestock_reproduction_events': [
          {
            'id': '77777777-7777-4777-8777-777777777777',
            'lot_id': lot.padRight(36, '0').substring(0, 36),
            'mother_ref': 'R1',
            'status': 'en_cours',
            'updated_at': '2026-08-19T10:00:00Z',
          },
        ],
      },
    );

    await moteur(serveur).synchroniser();

    final restante = await (db.select(
      db.livestockReproductionEvents,
    )..where((t) => t.id.equals(id))).getSingleOrNull();

    expect(restante, isNotNull, reason: 'la declaration locale a survecu');
    expect(restante!.syncStatus, SyncStatus.pending);
  });

  /// 🔴→✅ TICKET 14.74 — L'AJUSTEMENT PART AVEC SA RÉFÉRENCE CLIENTE.
  ///
  /// ⚠️⚠️ Le poste envoyait `id` ; le serveur cherchait `client_ref` et, ne le
  /// trouvant pas, acquittait avec le `product_id`. Le poste ne se
  /// reconnaissait donc jamais dans la réponse : l'ajustement restait EN
  /// ATTENTE et repartait à chaque tirage, rejouant à chaque fois le décrément
  /// de stock et une nouvelle écriture de perte.
  test('l ajustement de stock part avec sa reference cliente', () async {
    const id = '88888888-8888-4888-8888-888888888888';

    await db
        .into(db.stockAdjustments)
        .insert(
          StockAdjustmentsCompanion.insert(
            id: id,
            deviceId: 'poste-test',
            updatedAt: DateTime(2026, 8, 20, 9),
            productId: '99999999-9999-4999-8999-999999999999',
            type: 'sortie',
            quantity: 5,
            referenceType: 'inventaire',
            reason: const Value('Vol / Disparition'),
            movementDate: DateTime(2026, 8, 20),
          ),
        );

    final serveur = _ServeurFeint(
      push: {
        'stock_adjustments': {
          'accepted': [id],
          'rejected': [],
        },
      },
    );

    await moteur(serveur).synchroniser();

    final envoye = serveur.corpsRecus.single['stock_adjustments'] as List;
    expect((envoye.single as Map)['client_ref'], id);

    // ⚠️ ET IL QUITTE LA FILE : c'est tout l'objet de la référence.
    final restant = await (db.select(
      db.stockAdjustments,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(restant.syncStatus, SyncStatus.synced);
  });
}
