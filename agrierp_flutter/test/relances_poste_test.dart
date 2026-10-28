import 'package:agrierp/core/config/envoi_email_test.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/clients/clients_creances_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket VC-2 — LES RELANCES DE CLIENTS SE FONT (ET SE DEMANDENT) AU POSTE (`relances-clients.blade.php`).
///
/// WhatsApp (lien `wa.me`) et le courrier (PDF) se font sur l'appareil ; l'appel se compose par `tel:` et l'e-mail part du SMTP du
/// poste (AUT-3, remplace le SMS) ; sans envoyeur, c'est une DEMANDE que le serveur exécute à la synchronisation. Dans tous les cas la relance est écrite `pending` (UUID
/// du poste) : le client n'est pas rappelé deux fois, et un refus du serveur est lu à l'écran Synchronisation.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-28T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];
  final refus = <String, Map<String, String>>{};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [
                    for (final e in value)
                      if (e is Map && e['id'] is String && !(refus[key]?.containsKey(e['id']) ?? false)) e['id'],
                  ],
                  'rejected': [
                    for (final e in value)
                      if (e is Map && e['id'] is String && (refus[key]?.containsKey(e['id']) ?? false))
                        {'id': e['id'], 'reason': refus[key]![e['id']]},
                  ],
                },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late ClientsCreancesRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 28, 14),
    );
    depot = ClientsCreancesRepository(database: db, deviceId: 'poste-test');
    await db.into(db.customers).insert(
      CustomersCompanion.insert(id: uuid('c1'), name: 'AMOUSSOU Régis', phone: const Value('+229 97 20 20 20'), email: const Value('regis@exemple.bj'), city: const Value('Ikpinlè')),
    );
    await db.into(db.customers).insert(CustomersCompanion.insert(id: uuid('c2'), name: 'Sans Coordonnées'));
    await db.into(db.receivables).insert(
      ReceivablesCompanion.insert(id: uuid('abcd1234r1'), customerId: uuid('c1'), amount: 100000, dueDate: Value(DateTime(2025, 1, 10))),
    );
    await db.into(db.receivables).insert(
      ReceivablesCompanion.insert(id: uuid('r2'), customerId: uuid('c2'), amount: 5000, dueDate: Value(DateTime(2025, 1, 10))),
    );
  });
  tearDown(() async => db.close());

  Future<List<CustomerReminder>> relances() => db.select(db.customerReminders).get();

  group('modèles', () {
    test('⚠️ les trois modèles sont ceux du WEB, balises rendues comme `renderTemplate`', () async {
      final d = await depot.charger();
      final l = d.creances.firstWhere((c) => c.creance.id == uuid('abcd1234r1'));

      final texte = ClientsCreancesRepository.rendreModele(ClientsCreancesRepository.modelesRelance['2']!, l);

      expect(texte, startsWith('Bonjour AMOUSSOU Régis,\n\nMalgré notre précédent rappel, la facture ABCD1234 d\'un montant de 100 000 FCFA reste impayée depuis le 10/01/2025.'));
      expect(texte, endsWith('Cordialement,\nFerme École OLOUWACHEGOUN'));
      expect(texte, isNot(contains('[')));
      expect(ClientsCreancesRepository.modelesRelance.keys, ['1', '2', '3']);
    });

    test('le lien WhatsApp réduit le numéro à ses chiffres et encode le message', () {
      expect(
        ClientsCreancesRepository.lienWhatsapp('+229 97 20 20 20', 'Bonjour & merci'),
        'https://wa.me/22997202020?text=Bonjour%20%26%20merci',
      );
    });
  });

  group('dépôt', () {
    test('⚠️⚠️ une relance est pending, porte l\'UUID du poste, canal, message et jour', () async {
      final r = await depot.relancer(creanceId: uuid('abcd1234r1'), canal: 'email', message: 'Bonjour', date: DateTime(2026, 10, 28));

      expect(r.syncStatus, SyncStatus.pending);
      expect(r.deviceId, 'poste-test');
      expect(r.customerId, uuid('c1'));
      expect(r.receivableId, uuid('abcd1234r1'));
      expect(r.channel, 'email');
      expect(r.reminderDate, DateTime(2026, 10, 28));
    });

    test('les refus du serveur sont reproduits AVANT d\'écrire, mêmes messages', () async {
      Future<String> refuse(String creance, String canal, {String message = 'Bonjour'}) async {
        try {
          await depot.relancer(creanceId: creance, canal: canal, message: message);
        } on SaisieRefusee catch (e) {
          return e.motif;
        }
        fail('accepté');
      }

      expect(await refuse(uuid('r2'), 'whatsapp'), "Ce client n'a pas de numéro de téléphone enregistré.");
      expect(await refuse(uuid('r2'), 'appel'), "Ce client n'a pas de numéro de téléphone enregistré.");
      expect(await refuse(uuid('r2'), 'email'), "Ce client n'a pas d'adresse email enregistrée.");
      expect(await refuse(uuid('abcd1234r1'), 'pigeon'), 'Canal de relance inconnu.');
      expect(await refuse(uuid('abcd1234r1'), 'appel', message: '  '), 'Le champ message est obligatoire.');
      expect(await refuse(uuid('inconnue'), 'courrier'), 'Créance introuvable — synchronisez le poste.');
      expect(await relances(), isEmpty);

      // Le courrier n'exige aucune coordonnée (la lettre se remet en main propre).
      await depot.relancer(creanceId: uuid('r2'), canal: 'courrier', message: 'Lettre');
      expect((await relances()).length, 1);
    });

    test('la lettre de relance porte destinataire, ville, date et message', () {
      final doc = ClientsCreancesRepository.lettreRelance(client: 'AMOUSSOU Régis', ville: 'Ikpinlè', date: DateTime(2026, 10, 28), message: 'Bonjour');
      expect(doc.titre, 'Lettre de Relance');
      final lignes = [for (final l in doc.lignes.whereType<DonneesDocument>()) l.cellules];
      expect(lignes, [
        ['Destinataire', 'AMOUSSOU Régis'],
        ['Ville', 'Ikpinlè'],
        ['Date', '28/10/2026'],
        ['Message', 'Bonjour'],
      ]);
    });
  });

  group('AUT-3 · e-mail par le SMTP du poste', () {
    test('⚠️ l\'e-mail PART D\'ABORD (objet du web), puis la relance est écrite « déjà envoyée » et part avec already_sent', () async {
      final envoyes = <Map<String, String>>[];
      final direct = ClientsCreancesRepository(
        database: db, deviceId: 'poste-test',
        envoyerEmail: ({required destinataire, required sujet, required corps}) async => envoyes.add({'a': destinataire, 'objet': sujet, 'corps': corps}),
      );

      final r = await direct.relancer(creanceId: uuid('abcd1234r1'), canal: 'email', message: 'Bonjour');

      expect(envoyes.single['objet'], 'Ferme École OLOUWACHEGOUN — Rappel de règlement');
      expect(envoyes.single['corps'], 'Bonjour');
      expect(r.alreadySent, isTrue);
      await moteur.synchroniser();
      expect(((serveur.envois.single['customer_reminders'] as List).single as Map)['already_sent'], true);
    });

    test('⚠️ un envoi refusé (hors ligne, SMTP) lève le motif du SMTP et n\'écrit AUCUNE relance', () async {
      final direct = ClientsCreancesRepository(
        database: db, deviceId: 'poste-test',
        envoyerEmail: ({required destinataire, required sujet, required corps}) async => throw const EchecEnvoiEmail("Poste hors ligne : l'e-mail exige le réseau. Réessayez une fois le poste connecté."),
      );

      await expectLater(
        direct.relancer(creanceId: uuid('abcd1234r1'), canal: 'email', message: 'Bonjour'),
        throwsA(isA<SaisieRefusee>().having((e) => e.motif, 'motif', contains('hors ligne'))),
      );
      expect(await relances(), isEmpty);
    });

    test('le lien d\'appel garde chiffres et plus', () {
      expect(ClientsCreancesRepository.lienAppel('+229 97 20-20.20'), '+229972020' '20');
    });
  });

  group('moteur', () {
    test('⚠️⚠️ l\'envoi ne porte que le fait, sous les clés de `pushCustomerReminders`, et est acquitté', () async {
      final r = await depot.relancer(creanceId: uuid('abcd1234r1'), canal: 'appel', message: 'Bonjour', date: DateTime(2026, 10, 28));

      await moteur.synchroniser();

      final envoye = (serveur.envois.single['customer_reminders'] as List).single as Map;
      expect(envoye, {
        'id': r.id, 'customer_id': uuid('c1'), 'receivable_id': uuid('abcd1234r1'), 'channel': 'appel',
        'message': 'Bonjour', 'reminder_date': '2026-10-28', 'already_sent': false,
      });
      expect((await relances()).single.syncStatus, SyncStatus.synced);
    });

    test('un refus du serveur devient conflict avec son motif et se relance', () async {
      final r = await depot.relancer(creanceId: uuid('abcd1234r1'), canal: 'appel', message: 'Bonjour');
      serveur.refus['customer_reminders'] = {r.id: "Ce client n'a pas de numéro de téléphone enregistré."};

      await moteur.synchroniser();

      expect((await relances()).single.syncStatus, SyncStatus.conflict);
      final conflit = (await db.select(db.syncConflicts).get()).firstWhere((c) => c.sourceTable == 'customer_reminders');
      expect(conflit.reason, contains('pas de numéro'));
      await moteur.relancer(conflit);
      expect((await relances()).single.syncStatus, SyncStatus.pending);
    });

    test('⚠️⚠️ le tirage n\'écrase pas une relance pending et ajoute celles du web', () async {
      final locale = await depot.relancer(creanceId: uuid('abcd1234r1'), canal: 'email', message: 'Locale');
      serveur.refus['customer_reminders'] = {locale.id: 'non'};
      serveur.tirage = {
        'server_time': '2026-10-28T13:00:00Z',
        'customer_reminders': [
          {'id': locale.id, 'customer_id': uuid('c1'), 'receivable_id': null, 'channel': 'appel', 'reminder_date': '2026-10-01', 'message': 'ÉCRASÉE'},
          {'id': uuid('web1'), 'customer_id': uuid('c1'), 'receivable_id': uuid('abcd1234r1'), 'channel': 'whatsapp', 'reminder_date': '2026-10-02', 'message': 'Du web'},
        ],
      };

      await moteur.synchroniser();

      final toutes = {for (final r in await relances()) r.id: r};
      expect(toutes[locale.id]!.message, 'Locale');
      expect(toutes[uuid('web1')]!.syncStatus, SyncStatus.synced);
      expect(toutes[uuid('web1')]!.deviceId, 'serveur');
    });
  });

  group('écran', () {
    final urls = <String>[];
    final documents = <DocumentOfficiel>[];

    Future<void> afficher(WidgetTester tester) async {
      urls.clear();
      documents.clear();
      tester.view.physicalSize = const Size(1700, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      await tester.pumpWidget(
        MaterialApp(
          home: ClientsCreancesScreen(
            depot: depot,
            maintenant: () => DateTime(2026, 10, 28, 10),
            ouvrirUrl: (u) async => urls.add(u),
            imprimer: (doc, _) async {
              documents.add(doc);
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onglet-clients-Relances Clients')));
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️⚠️ « Relancer WhatsApp » écrit la relance PUIS ouvre wa.me avec le message du modèle', (tester) async {
      await afficher(tester);

      await tester.ensureVisible(find.byKey(Key('relancer-whatsapp-${uuid('abcd1234r1')}')));
      await tester.tap(find.byKey(Key('relancer-whatsapp-${uuid('abcd1234r1')}')));
      await tester.pumpAndSettle();

      final r = (await relances()).single;
      expect(r.channel, 'whatsapp');
      expect(r.syncStatus, SyncStatus.pending);
      expect(r.message, contains('la facture ABCD1234 d\'un montant de 100 000 FCFA'));
      expect(urls.single, startsWith('https://wa.me/22997202020?text='));
    });

    testWidgets('« Exporter Courrier » édite la lettre et tient la trace', (tester) async {
      await afficher(tester);

      await tester.ensureVisible(find.byKey(Key('exporter-courrier-${uuid('abcd1234r1')}')));
      await tester.tap(find.byKey(Key('exporter-courrier-${uuid('abcd1234r1')}')));
      await tester.pumpAndSettle();

      expect((await relances()).single.channel, 'courrier');
      expect(documents.single.titre, 'Lettre de Relance');
    });

    testWidgets('sans envoyeur, l\'e-mail est une DEMANDE (rien ouvert) ; un appel sans numéro est refusé sans trace', (tester) async {
      await afficher(tester);

      await tester.ensureVisible(find.byKey(Key('relancer-email-${uuid('abcd1234r1')}')));
      await tester.tap(find.byKey(Key('relancer-email-${uuid('abcd1234r1')}')));
      await tester.pumpAndSettle();
      expect((await relances()).single.channel, 'email');
      expect(urls, isEmpty);

      await tester.ensureVisible(find.byKey(Key('relancer-appel-${uuid('r2')}')));
      await tester.tap(find.byKey(Key('relancer-appel-${uuid('r2')}')));
      await tester.pumpAndSettle();
      expect(find.text("Ce client n'a pas de numéro de téléphone enregistré."), findsOneWidget);
      expect((await relances()).length, 1, reason: 'refus : aucune relance écrite');
    });

    testWidgets('« Appeler » tient la trace puis compose le numéro par tel: (chiffres et +)', (tester) async {
      await afficher(tester);

      await tester.ensureVisible(find.byKey(Key('relancer-appel-${uuid('abcd1234r1')}')));
      await tester.tap(find.byKey(Key('relancer-appel-${uuid('abcd1234r1')}')));
      await tester.pumpAndSettle();

      expect((await relances()).single.channel, 'appel');
      expect(urls.single, startsWith('tel:'));
      expect(urls.single, isNot(contains(' ')));
    });

    testWidgets('le modèle est MODIFIABLE : balise ajoutée, niveau changé = texte du niveau rechargé', (tester) async {
      await afficher(tester);

      await tester.ensureVisible(find.byKey(const Key('balise-[NOM]')));
      await tester.tap(find.byKey(const Key('balise-[NOM]')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('modele-texte'))).controller!.text, endsWith('[NOM]'));

      await tester.tap(find.byKey(const Key('niveau-relance')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Niveau 3 : Mise en demeure').last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('modele-texte'))).controller!.text, startsWith('Mise en demeure — [NOM]'));
    });

    testWidgets('« Relancer » de Suivi des Dettes tient la trace WhatsApp du solde dû', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('onglet-clients-Suivi des Dettes')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('creance-relancer-0')));
      await tester.pumpAndSettle();

      final r = (await relances()).single;
      expect(r.channel, 'whatsapp');
      expect(r.message, 'Relance — solde dû 100 000 FCFA.');
    });
  });
}
