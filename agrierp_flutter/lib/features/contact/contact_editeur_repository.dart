import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

/// Échec d'un envoi à l'éditeur : un message général, et ceux du serveur PAR
/// CHAMP (`objet`, `message`, `module`, `description`, `etapes`) quand il en a
/// rendu.
class EchecContact implements Exception {
  const EchecContact(this.message, {this.champs = const {}});

  final String message;
  final Map<String, String> champs;

  @override
  String toString() => message;
}

/// Envoi à l'éditeur, contre `POST /api/contact` (ticket Laravel 15.11).
///
/// ⚠️⚠️ **L'ENVOI EXIGE LE RÉSEAU ET N'EST PAS MIS EN FILE.** Le serveur envoie
/// un e-mail RÉEL à l'éditeur ; il n'y a ni table ni file côté poste. Hors
/// ligne, l'envoi est refusé par une phrase qui dit de réessayer, et **le texte
/// reste dans le formulaire** ([BrouillonContact]) : rien n'est perdu, rien n'est
/// affirmé envoyé. Une file de synchronisation (envoi différé) reste possible ;
/// elle supposerait un contrat `/sync/push` pour les messages, que le serveur n'a
/// pas.
class ClientContact {
  ClientContact(this._client);

  final Dio _client;

  Future<void> envoyerMessage({
    required String objet,
    required String message,
  }) => _envoyer({'type': 'message', 'subject': objet, 'message': message});

  Future<void> signalerBug({
    required String module,
    required String description,
    required String etapes,
  }) => _envoyer({
    'type': 'bug',
    'module': module,
    'description': description,
    // Facultatif : une chaîne vide n'est pas envoyée.
    if (etapes.trim().isNotEmpty) 'steps': etapes,
  });

  Future<void> _envoyer(Map<String, dynamic> corps) async {
    try {
      await _client.post<dynamic>('/api/contact', data: corps);
    } on DioException catch (e) {
      throw _echec(e);
    }
  }

  static EchecContact _echec(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.receiveTimeout) {
      return const EchecContact(
        'Serveur injoignable. Cet envoi nécessite le réseau : votre texte est '
        'conservé ici, renvoyez-le une fois connecté.',
      );
    }

    final donnees = e.response?.data;
    final champs = <String, String>{};

    if (e.response?.statusCode == 422 &&
        donnees is Map &&
        donnees['errors'] is Map) {
      const correspondance = {
        'subject': 'objet',
        'message': 'message',
        'module': 'module',
        'description': 'description',
        'steps': 'etapes',
      };
      (donnees['errors'] as Map).forEach((cle, messages) {
        final champ = correspondance[cle];
        if (champ != null && messages is List && messages.isNotEmpty) {
          champs[champ] = messages.first.toString();
        }
      });
    }

    return EchecContact(switch (e.response?.statusCode) {
      401 => 'Session expirée : reconnectez-vous.',
      429 => 'Trop d\'envois. Réessayez dans une minute.',
      // 502 : le serveur a refusé d'envoyer l'e-mail et le dit lui-même.
      502 when donnees is Map && donnees['message'] is String =>
        donnees['message'] as String,
      _ => 'Envoi impossible.',
    }, champs: champs);
  }
}

/// Ce que l'utilisateur a saisi, **conservé tant que l'application tourne**.
///
/// ⚠️ **POSSÉDÉ PAR LA COQUE, PAS PAR L'ÉCRAN.** L'écran est reconstruit à chaque
/// changement de page : un texte de dix lignes rédigé hors ligne disparaîtrait
/// si l'utilisateur ouvrait un autre écran pour vérifier une information.
class BrouillonContact {
  final objet = TextEditingController();
  final message = TextEditingController();
  final description = TextEditingController();
  final etapes = TextEditingController();

  /// `''` tant qu'aucun module n'est choisi (« -- Sélectionner -- »).
  String module = '';

  /// Onglet affiché : `message` ou `bug`.
  String onglet = 'message';

  void viderMessage() {
    objet.clear();
    message.clear();
  }

  void viderBug() {
    description.clear();
    etapes.clear();
    module = '';
  }

  void dispose() {
    objet.dispose();
    message.dispose();
    description.dispose();
    etapes.dispose();
  }
}

/// Lectures et règles de `prototype_html/contact-editeur.html`.
class ContactEditeurRepository {
  const ContactEditeurRepository({this.client});

  /// `null` : aucune session — l'envoi répond par une phrase, sans rien tenter.
  final ClientContact? client;

  /// Les six modules du menu « Module concerné », dans l'ordre de la maquette.
  static const modules = [
    'Élevage & Soins',
    'Ventes & POS',
    'Stocks',
    'Comptabilité',
    'Ressources Humaines',
    'Autre',
  ];

  /// ⚠️⚠️ **COORDONNÉES DE LARAVEL, PAS DU PROTOTYPE.** Le prototype donne
  /// « FAGUEZ SARL · support@faguez-sarl.bj · +229 XX XX XX XX » — des
  /// coordonnées de remplissage, et la mauvaise structure : l'éditeur du logiciel
  /// est le Dr MASSENON Rhodes, FAGUEZ SARL étant le cabinet d'accompagnement. La
  /// surface web porte les vraies (ticket 15.8) ; un numéro `XX XX XX XX`
  /// affiché sur un poste de production n'est joignable par personne.
  static const editeurNom = 'Dr MASSENON Rhodes';
  static const editeurTitre = 'Docteur en Génie Logiciel et IA';
  static const editeurEmails = [
    'rarhodes06@gmail.com',
    'contact@massenonrhodes.com',
  ];
  static const editeurTelephones = [
    '+229 01 51 33 50 40',
    '+229 01 97 31 24 37',
  ];
  static const editeurHoraires = 'Lun-Ven, 8h-17h (GMT)';

  /// Règles de saisie du message, à l'identique du serveur. Vide si recevable.
  static Map<String, String> validerMessage({
    required String objet,
    required String message,
  }) => {
    if (objet.trim().isEmpty) 'objet': 'Ce champ est obligatoire.',
    if (message.trim().isEmpty) 'message': 'Ce champ est obligatoire.',
  };

  /// Règles de saisie du signalement. « Étapes » est facultatif.
  static Map<String, String> validerBug({
    required String module,
    required String description,
  }) => {
    if (module.isEmpty) 'module': 'Ce champ est obligatoire.',
    if (description.trim().isEmpty) 'description': 'Ce champ est obligatoire.',
  };

  Future<void> envoyerMessage({
    required String objet,
    required String message,
  }) async => _client().envoyerMessage(objet: objet, message: message);

  Future<void> signalerBug({
    required String module,
    required String description,
    required String etapes,
  }) => _client().signalerBug(
    module: module,
    description: description,
    etapes: etapes,
  );

  ClientContact _client() =>
      client ??
      (throw const EchecContact('Aucune session ouverte : connectez-vous.'));
}
