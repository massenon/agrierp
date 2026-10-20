import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Utilisateur connecté, tel que le serveur le décrit.
class SessionUtilisateur {
  const SessionUtilisateur({
    required this.id,
    required this.nom,
    required this.identifiant,
    required this.email,
    required this.role,
    required this.roleLibelle,
  });

  factory SessionUtilisateur.depuisJson(Map<String, dynamic> j) =>
      SessionUtilisateur(
        id: (j['id'] ?? '') as String,
        nom: (j['name'] ?? '') as String,
        identifiant: (j['username'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        role: (j['role'] ?? '') as String,
        roleLibelle: (j['role_label'] ?? '') as String,
      );

  final String id;
  final String nom;
  final String identifiant;
  final String email;
  final String role;
  final String roleLibelle;

  Map<String, dynamic> versJson() => {
    'id': id,
    'name': nom,
    'username': identifiant,
    'email': email,
    'role': role,
    'role_label': roleLibelle,
  };
}

/// Échec d'authentification porteur du message du serveur.
class EchecConnexion implements Exception {
  const EchecConnexion(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Échec du changement de mot de passe : un message général, et les messages du
/// serveur PAR CHAMP (`ancien`, `nouveau`, `confirmation`) quand il en a rendu.
class EchecChangementMotDePasse implements Exception {
  const EchecChangementMotDePasse(this.message, {this.champs = const {}});

  final String message;
  final Map<String, String> champs;

  @override
  String toString() => message;
}

/// Authentification du client Desktop contre `POST /api/auth/login`.
///
/// ⚠️ **NOM D'UTILISATEUR OU E-MAIL**, comme l'annonce le libellé du champ
/// depuis la maquette. Le serveur choisit sa colonne selon la présence d'un
/// « @ » ; le client n'a donc rien à deviner et n'impose aucune règle de
/// format qui rejetterait « admin » avant l'envoi.
///
/// ⚠️ **LE MOT DE PASSE N'EST JAMAIS CONSERVÉ**, ni en clair ni sous forme
/// d'empreinte. Seuls le jeton Sanctum et l'identité de l'utilisateur sont
/// stockés, dans le coffre du système. Garder de quoi revérifier un mot de
/// passe hors ligne ferait de chaque poste de la ferme un dépôt de secrets.
class AuthService {
  AuthService({
    required Dio client,
    required String deviceName,
    FlutterSecureStorage? coffre,
  }) : // `prefer_initializing_formals` suggère `this._client` : Dart
       // l'interdit sur un paramètre NOMMÉ privé.
       // ignore: prefer_initializing_formals
       _client = client,
       // ignore: prefer_initializing_formals
       _deviceName = deviceName,
       _coffre = coffre ?? const FlutterSecureStorage();

  static const _cleJeton = 'agrierp.token';
  static const _cleUtilisateur = 'agrierp.user';

  final Dio _client;
  final String _deviceName;
  final FlutterSecureStorage _coffre;

  SessionUtilisateur? _utilisateur;
  SessionUtilisateur? get utilisateur => _utilisateur;

  /// Reprend la session d'un lancement précédent.
  ///
  /// ⚠️ **CE CHEMIN DOIT FONCTIONNER HORS LIGNE.** À Ikpinlè le réseau est
  /// intermittent : exiger un aller-retour serveur au démarrage rendrait
  /// l'application inutilisable les jours de coupure — précisément ceux où
  /// l'offline-first doit tenir. On fait donc confiance au jeton conservé,
  /// sans le revalider.
  Future<bool> reprendreSession() async {
    final jeton = await _coffre.read(key: _cleJeton);
    final brut = await _coffre.read(key: _cleUtilisateur);

    if (jeton == null || brut == null) return false;

    _utilisateur = SessionUtilisateur.depuisJson(
      jsonDecode(brut) as Map<String, dynamic>,
    );
    _appliquerJeton(jeton);

    return true;
  }

  /// Connexion réelle contre le serveur.
  ///
  /// ⚠️ **LA PREMIÈRE CONNEXION EXIGE LE RÉSEAU**, et il faut le dire
  /// clairement plutôt que d'échouer sur un message technique : sans jeton, un
  /// poste neuf n'a rien à quoi faire confiance. Un déverrouillage hors ligne
  /// supposerait de conserver de quoi vérifier le mot de passe localement —
  /// décision de sécurité qui appartient au client, pas au développeur.
  Future<SessionUtilisateur> connecter({
    required String identifiant,
    required String motDePasse,
  }) async {
    try {
      final reponse = await _client.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {
          'identifiant': identifiant,
          'password': motDePasse,
          'device_name': _deviceName,
        },
      );

      final corps = reponse.data ?? const <String, dynamic>{};
      final jeton = corps['token'] as String?;
      final utilisateur = corps['user'];

      if (jeton == null || utilisateur is! Map<String, dynamic>) {
        throw const EchecConnexion('Réponse inattendue du serveur.');
      }

      _utilisateur = SessionUtilisateur.depuisJson(utilisateur);
      _appliquerJeton(jeton);

      await _coffre.write(key: _cleJeton, value: jeton);
      await _coffre.write(
        key: _cleUtilisateur,
        value: jsonEncode(_utilisateur!.versJson()),
      );

      return _utilisateur!;
    } on DioException catch (e) {
      throw EchecConnexion(_messageLisible(e));
    }
  }

  /// Changement du mot de passe de l'utilisateur connecté, contre
  /// `POST /api/auth/password` (ticket Laravel 15.9).
  ///
  /// ⚠️ **CE GESTE EXIGE LE RÉSEAU, ET IL LE DIT.** Le serveur vérifie
  /// l'ancien mot de passe contre son hachage ; le poste n'en garde aucun (voir
  /// l'en-tête de la classe) et ne peut donc rien valider seul. Hors ligne,
  /// l'échec est une phrase qui demande de réessayer, pas un « erreur ».
  ///
  /// ⚠️ **LE JETON COURANT RESTE VALIDE** : le serveur ne révoque rien. Le poste
  /// n'a donc pas à se reconnecter, ce qui l'obligerait à retrouver le réseau.
  ///
  /// Lève [EchecChangementMotDePasse], porteuse des messages PAR CHAMP quand le
  /// serveur en a rendu (422), pour que l'écran les place sous le bon champ.
  Future<void> changerMotDePasse({
    required String ancien,
    required String nouveau,
    required String confirmation,
  }) async {
    try {
      await _client.post<Map<String, dynamic>>(
        '/api/auth/password',
        data: {
          'current_password': ancien,
          'new_password': nouveau,
          'new_password_confirmation': confirmation,
        },
      );
    } on DioException catch (e) {
      final donnees = e.response?.data;
      final champs = <String, String>{};

      if (e.response?.statusCode == 422 &&
          donnees is Map &&
          donnees['errors'] is Map) {
        const correspondance = {
          'current_password': 'ancien',
          'new_password': 'nouveau',
          'new_password_confirmation': 'confirmation',
        };
        (donnees['errors'] as Map).forEach((cle, messages) {
          final champ = correspondance[cle];
          if (champ != null && messages is List && messages.isNotEmpty) {
            champs[champ] = messages.first.toString();
          }
        });
      }

      throw EchecChangementMotDePasse(
        e.response?.statusCode == 401
            ? 'Session expirée : reconnectez-vous.'
            : e.response?.statusCode == 429
            ? 'Trop de tentatives. Réessayez dans une minute.'
            : _messageLisible(e, parDefaut: 'Changement impossible.'),
        champs: champs,
      );
    }
  }

  /// Ticket CFG-2 — adresse du serveur EN USAGE (celle du client HTTP, construit au démarrage) : l'onglet
  /// « Appairage » la distingue de l'adresse enregistrée, qui n'agit qu'après redémarrage.
  String get adresseServeur => _client.options.baseUrl;

  /// Ticket CFG-2 — un jeton est-il conservé au coffre ? `null` : coffre illisible (aucun coffre du système,
  /// comme dans un test de rendu) — l'écran dit alors qu'il ne sait pas, au lieu d'affirmer une absence.
  Future<bool?> jetonPresent() async {
    try {
      final jeton = await _coffre.read(key: _cleJeton);
      return jeton != null && jeton.isNotEmpty;
    } catch (_) {
      return null;
    }
  }

  /// Ticket CFG-2 — « Tester la connexion » de l'onglet Appairage : `GET /api/auth/me` avec le jeton de la
  /// session. Rend le compte tel que le serveur le décrit ; lève l'erreur du client HTTP sinon (hors ligne,
  /// 401 d'un appairage révoqué, 403 d'un compte désactivé…), que l'écran traduit par `messageErreur`.
  ///
  /// ⚠️ La session locale n'est PAS remplacée : un test n'a pas à changer le rôle sous lequel l'écran tourne.
  Future<SessionUtilisateur> verifierSession() async {
    final reponse = await _client.get<Map<String, dynamic>>('/api/auth/me');
    return SessionUtilisateur.depuisJson(
      reponse.data ?? const <String, dynamic>{},
    );
  }

  Future<void> deconnecter() async {
    // La révocation serveur est tentée, mais son échec ne doit pas empêcher la
    // déconnexion locale : hors ligne, l'utilisateur doit pouvoir fermer sa
    // session sur le poste malgré tout.
    try {
      await _client.post('/api/auth/logout');
    } on DioException {
      // Ignoré volontairement — voir ci-dessus.
    }

    _utilisateur = null;
    _client.options.headers.remove('Authorization');
    await _coffre.delete(key: _cleJeton);
    await _coffre.delete(key: _cleUtilisateur);
  }

  void _appliquerJeton(String jeton) {
    _client.options.headers['Authorization'] = 'Bearer $jeton';
    _client.options.headers['Accept'] = 'application/json';
  }

  /// Traduit l'échec réseau en phrase utile.
  ///
  /// ⚠️ Une absence de réseau et un mot de passe erroné demandent deux
  /// gestes DIFFÉRENTS : réessayer plus tard, ou corriger sa saisie. Les
  /// confondre sous « Erreur de connexion » ferait chercher au mauvais
  /// endroit.
  String _messageLisible(
    DioException e, {
    String parDefaut = 'Connexion impossible.',
  }) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.receiveTimeout) {
      return parDefaut == 'Connexion impossible.'
          ? 'Serveur injoignable. La première connexion sur ce poste '
                'nécessite le réseau.'
          : 'Serveur injoignable. Ce changement nécessite le réseau : '
                'réessayez une fois connecté.';
    }

    final donnees = e.response?.data;

    if (donnees is Map && donnees['errors'] is Map) {
      final erreurs = (donnees['errors'] as Map).values;
      if (erreurs.isNotEmpty && erreurs.first is List) {
        final premiere = (erreurs.first as List).first;
        return premiere.toString();
      }
    }

    if (donnees is Map && donnees['message'] is String) {
      return donnees['message'] as String;
    }

    return parDefaut;
  }
}
