import 'package:agrierp/core/auth/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 0 Flutter — AUTHENTIFICATION contre `POST /api/auth/login`.
///
/// Le contrat serveur a été aligné au même moment (ticket 14.51 côté Laravel) :
/// l'API n'acceptait que l'adresse e-mail, alors que le champ de la maquette
/// annonce « NOM D'UTILISATEUR OU EMAIL ». Sans cet alignement, cet écran
/// aurait promis ce que le serveur refusait.

/// Coffre en mémoire — évite la dépendance à la plateforme dans les tests.
class _CoffreMemoire extends FlutterSecureStorage {
  const _CoffreMemoire(this._contenu);

  final Map<String, String> _contenu;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _contenu[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _contenu.remove(key);
    } else {
      _contenu[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _contenu.remove(key);
  }
}

/// Sert la réponse voulue et retient ce qui a été envoyé.
class _ServeurFeint extends Interceptor {
  _ServeurFeint({this.reponse, this.erreur});

  final Map<String, dynamic>? reponse;
  final Response<dynamic>? erreur;

  Map<String, dynamic>? corpsRecu;
  String? cheminRecu;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    cheminRecu = options.path;
    if (options.data is Map<String, dynamic>) {
      corpsRecu = options.data as Map<String, dynamic>;
    }

    if (erreur != null) {
      handler.reject(
        DioException(
          requestOptions: options,
          response: erreur!..requestOptions = options,
          type: DioExceptionType.badResponse,
        ),
      );
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: reponse ?? const {},
      ),
    );
  }
}

void main() {
  const reponseValide = {
    'token': 'jeton-sanctum-123',
    'user': {
      'id': 'uuid-utilisateur',
      'name': 'Comptable Ferme École',
      'username': 'compta',
      'email': 'compta@fermeolouwachegoun.com',
      'role': 'comptable',
      'role_label': 'Comptable',
    },
  };

  (AuthService, _ServeurFeint, Map<String, String>) monter({
    Map<String, dynamic>? reponse,
    Response<dynamic>? erreur,
    Map<String, String>? coffreInitial,
  }) {
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'));
    final serveur = _ServeurFeint(reponse: reponse, erreur: erreur);
    client.interceptors.add(serveur);

    final contenu = coffreInitial ?? <String, String>{};

    return (
      AuthService(
        client: client,
        deviceName: 'poste-test',
        coffre: _CoffreMemoire(contenu),
      ),
      serveur,
      contenu,
    );
  }

  /// LE FLUX DEMANDÉ : « compta » ouvre la session.
  test('l identifiant court est envoye tel quel au serveur', () async {
    final (auth, serveur, _) = monter(reponse: reponseValide);

    final utilisateur = await auth.connecter(
      identifiant: 'compta',
      motDePasse: 'AgriERP@2026',
    );

    expect(serveur.corpsRecu!['identifiant'], 'compta');
    expect(serveur.corpsRecu!['device_name'], 'poste-test');
    expect(utilisateur.identifiant, 'compta');
    expect(utilisateur.roleLibelle, 'Comptable');
  });

  /// ⚠️ LE MOT DE PASSE N'EST JAMAIS CONSERVÉ — ni en clair ni en empreinte.
  test('le mot de passe n est jamais stocke', () async {
    final (auth, _, coffre) = monter(reponse: reponseValide);

    await auth.connecter(
      identifiant: 'compta',
      motDePasse: 'AgriERP@2026-reconnaissable',
    );

    for (final valeur in coffre.values) {
      expect(valeur, isNot(contains('reconnaissable')));
    }
  });

  /// Le jeton part ensuite sur chaque appel : sans cela, la synchronisation
  /// se verrait refuser en 401 alors que la connexion a réussi.
  test('le jeton arme le client pour les appels suivants', () async {
    final (auth, serveur, _) = monter(reponse: reponseValide);

    await auth.connecter(identifiant: 'compta', motDePasse: 'x');

    expect(auth.utilisateur, isNotNull);
    expect(serveur.corpsRecu, isNotNull);
  });

  /// ⚠️ REPRISE DE SESSION HORS LIGNE : aucun appel réseau au démarrage.
  test('la session se reprend sans reseau', () async {
    final (auth, serveur, _) = monter(
      coffreInitial: {
        'agrierp.token': 'jeton-conserve',
        'agrierp.user':
            '{"id":"u1","name":"DG","username":"admin",'
            '"email":"dg@fermeolouwachegoun.com","role":"admin","role_label":"Admin"}',
      },
    );

    expect(await auth.reprendreSession(), isTrue);
    expect(auth.utilisateur!.identifiant, 'admin');
    expect(serveur.corpsRecu, isNull, reason: 'aucun aller-retour serveur');
  });

  /// Sans jeton conservé, il n'y a pas de session à reprendre.
  test('sans jeton, aucune session n est reprise', () async {
    final (auth, _, _) = monter();

    expect(await auth.reprendreSession(), isFalse);
    expect(auth.utilisateur, isNull);
  });

  /// ⚠️ Le message du serveur est rendu tel quel : « Identifiants
  /// incorrects. » demande un geste différent d'un serveur injoignable.
  test('le motif de refus vient du serveur', () async {
    final (auth, _, _) = monter(
      erreur: Response<dynamic>(
        requestOptions: RequestOptions(),
        statusCode: 422,
        data: {
          'errors': {
            'identifiant': ['Identifiants incorrects.'],
          },
        },
      ),
    );

    expect(
      () => auth.connecter(identifiant: 'compta', motDePasse: 'faux'),
      throwsA(
        isA<EchecConnexion>().having(
          (e) => e.message,
          'message',
          'Identifiants incorrects.',
        ),
      ),
    );
  });

  /// Un compte désactivé porte son propre message, distinct d'un mot de passe
  /// erroné : l'utilisateur doit savoir qu'il faut appeler un administrateur.
  test('un compte desactive porte son propre message', () async {
    final (auth, _, _) = monter(
      erreur: Response<dynamic>(
        requestOptions: RequestOptions(),
        statusCode: 422,
        data: {
          'errors': {
            'identifiant': [
              'Ce compte a été désactivé. Contactez un administrateur.',
            ],
          },
        },
      ),
    );

    expect(
      () => auth.connecter(identifiant: 'compta', motDePasse: 'x'),
      throwsA(
        isA<EchecConnexion>().having(
          (e) => e.message,
          'message',
          contains('désactivé'),
        ),
      ),
    );
  });

  /// La déconnexion vide le coffre même si le serveur ne répond pas : hors
  /// ligne, on doit pouvoir fermer sa session sur le poste.
  test('la deconnexion vide le coffre meme sans serveur', () async {
    final (auth, _, coffre) = monter(reponse: reponseValide);

    await auth.connecter(identifiant: 'compta', motDePasse: 'x');
    expect(coffre, isNotEmpty);

    await auth.deconnecter();

    expect(coffre, isEmpty);
    expect(auth.utilisateur, isNull);
  });

  // ── Changement de mot de passe (ticket F0.57 / Laravel 15.9) ────────────

  group('changement de mot de passe', () {
    Response<dynamic> refus(int code, [Object? donnees]) => Response<dynamic>(
      requestOptions: RequestOptions(),
      statusCode: code,
      data: donnees,
    );

    test(
      'part vers /api/auth/password avec les trois clés du serveur',
      () async {
        final (auth, serveur, _) = monter(reponse: const {'message': 'ok'});

        await auth.changerMotDePasse(
          ancien: 'Ancien1',
          nouveau: 'Nouveau12',
          confirmation: 'Nouveau12',
        );

        expect(serveur.cheminRecu, '/api/auth/password');
        expect(serveur.corpsRecu, {
          'current_password': 'Ancien1',
          'new_password': 'Nouveau12',
          'new_password_confirmation': 'Nouveau12',
        });
      },
    );

    test(
      "un 422 est rendu PAR CHAMP, sous le nom que l'écran emploie",
      () async {
        final (auth, _, _) = monter(
          erreur: refus(422, {
            'message': 'invalide',
            'errors': {
              'current_password': ['Ancien faux.'],
              'new_password': ['Trop court.'],
            },
          }),
        );

        await expectLater(
          auth.changerMotDePasse(ancien: 'x', nouveau: 'y', confirmation: 'y'),
          throwsA(
            isA<EchecChangementMotDePasse>().having((e) => e.champs, 'champs', {
              'ancien': 'Ancien faux.',
              'nouveau': 'Trop court.',
            }),
          ),
        );
      },
    );

    test('un 401 dit que la session a expiré', () async {
      final (auth, _, _) = monter(
        erreur: refus(401, {'message': 'Unauthenticated.'}),
      );

      await expectLater(
        auth.changerMotDePasse(ancien: 'a', nouveau: 'b', confirmation: 'b'),
        throwsA(
          isA<EchecChangementMotDePasse>().having(
            (e) => e.message,
            'message',
            contains('Session expirée'),
          ),
        ),
      );
    });

    test("un 429 demande d'attendre", () async {
      final (auth, _, _) = monter(erreur: refus(429));

      await expectLater(
        auth.changerMotDePasse(ancien: 'a', nouveau: 'b', confirmation: 'b'),
        throwsA(
          isA<EchecChangementMotDePasse>().having(
            (e) => e.message,
            'message',
            contains('Trop de tentatives'),
          ),
        ),
      );
    });
  });
}
