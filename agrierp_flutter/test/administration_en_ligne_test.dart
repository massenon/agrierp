import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/parametres/administration_en_ligne.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tickets PA-1, PA-5, PA-6, PA-8 — gestes d'administration EN LIGNE : routes du serveur par le client partagé, jamais en base
/// locale ; hors ligne, le poste le dit ; le message du serveur est repris tel quel.
class _Reseau implements Connectivity {
  _Reseau(this.enLigne);

  bool enLigne;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [enLigne ? ConnectivityResult.wifi : ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  final List<String> appels = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    appels.add('${options.method} ${options.path}');
    Response<dynamic> ok(dynamic donnees, [int code = 200]) => Response(requestOptions: options, statusCode: code, data: donnees);
    switch (options.path) {
      case '/api/parametres/sessions/vider':
        handler.resolve(ok({'sessions': 2, 'jetons': 1, 'message': '2 session(s) web fermée(s), 1 poste(s) déconnecté(s). Votre session est conservée.'}));
      case '/api/parametres/postes':
        handler.resolve(ok({'postes': [{'poste': 'comptoir-1', 'utilisateur': 'Caisse', 'libelle_etat': 'À jour', 'dernier_contact': null, 'dernier_envoi': null}]}));
      case '/api/parametres/postes/revoquer':
        handler.reject(DioException(requestOptions: options, response: ok({'message': 'Poste inconnu du serveur : aucun appairage révoqué.'}, 422)));
      case '/api/parametres/sauvegardes':
        handler.resolve(ok({'fichiers': [{'fichier': 'sauvegarde-1.sql', 'date': '2026-10-28T02:00:00Z', 'portee': 'complète', 'taille': 2048}], 'modules': {'ventes': 'Ventes & Clients'}}));
      case '/api/parametres/sauvegardes/telecharger/sauvegarde-1.sql':
        handler.resolve(ok(<int>[1, 2, 3]));
      case '/api/parametres/sms/tester':
        handler.resolve(ok({'type': 'error', 'message': 'Aucun fournisseur SMS configuré.'}));
      default:
        handler.resolve(ok({'message': 'ok'}));
    }
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late _Reseau reseau;
  late AdministrationEnLigne admin;
  late Directory dossier;
  var role = 'admin';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    reseau = _Reseau(true);
    dossier = Directory.systemTemp.createTempSync('agrierp_telechargements_');
    final client = Dio()..interceptors.add(serveur);
    admin = AdministrationEnLigne(
      client: client,
      engine: SyncEngine(database: db, client: client, deviceId: 'poste-test', connectivity: reseau),
      role: () => role,
      dossierTelechargement: () async => dossier,
    );
    role = 'admin';
  });
  tearDown(() async {
    await db.close();
    dossier.deleteSync(recursive: true);
  });

  test('le droit est celui du rôle : admin tout, caissier rien', () {
    expect(admin.peut('manage-users'), isTrue);
    role = 'caissier';
    expect(admin.peut('manage-users'), isFalse);
    expect(admin.peut('manage-parametres'), isFalse);
  });

  test('⚠️ hors ligne, chaque geste le dit et n\'appelle rien', () async {
    reseau.enLigne = false;

    for (final geste in [admin.viderSessions, admin.postes, admin.sauvegardes, () => admin.testerSms('+229')]) {
      await expectLater(geste(), throwsA(isA<RefusAdministration>().having((e) => e.message, 'message', AdministrationEnLigne.refusHorsLigne)));
    }
    expect(serveur.appels, isEmpty);
  });

  test('en ligne : le message du serveur est repris tel quel, un refus remonte avec son motif', () async {
    expect(await admin.viderSessions(), '2 session(s) web fermée(s), 1 poste(s) déconnecté(s). Votre session est conservée.');
    expect((await admin.postes()).single.poste, 'comptoir-1');
    await expectLater(admin.revoquer('inconnu'), throwsA(isA<RefusAdministration>().having((e) => e.message, 'motif', 'Poste inconnu du serveur : aucun appairage révoqué.')));
    final s = await admin.sauvegardes();
    expect((s.fichiers.single.fichier, s.modules['ventes']), ('sauvegarde-1.sql', 'Ventes & Clients'));
    final test = await admin.testerSms('+22996456789');
    expect((test.succes, test.message), (false, 'Aucun fournisseur SMS configuré.'));
  });

  test('⚠️ le téléchargement écrit le fichier dans le dossier du poste', () async {
    final chemin = await admin.telecharger('sauvegarde-1.sql');

    expect(File(chemin).readAsBytesSync(), [1, 2, 3]);
    expect(chemin, startsWith(dossier.path));
  });
}
