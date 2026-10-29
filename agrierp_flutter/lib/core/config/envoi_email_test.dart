import 'dart:async';
import 'dart:io' show HandshakeException, SocketException;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../erreurs/message_erreur.dart';
import 'parametres_smtp.dart';

/// Envoi réel d'un message par un serveur SMTP — `send` du paquet `mailer` hors des tests, injecté dans les tests
/// (aucun réseau).
typedef EnvoyeurSmtp = Future<void> Function(Message message, SmtpServer serveur);

/// Échec de l'e-mail de test, porteur d'une phrase française prête à afficher.
class EchecEnvoiEmail implements Exception {
  const EchecEnvoiEmail(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Ticket CFG-2 — « ENVOYER UN E-MAIL DE TEST » DU POSTE, RÉEL, comme `EmailSmtp::sendTestEmail()` du web.
///
/// Les réglages ENREGISTRÉS sont relus (ceux du formulaire ne comptent qu'une fois enregistrés, comme au web) et
/// le mot de passe est repris au coffre au moment d'envoyer. Messages du web : « E-mail de test envoyé à … »,
/// « Enregistrez d'abord l'hôte SMTP… », « Échec de l'envoi — vérifiez la configuration SMTP (…) ».
///
/// ⚠️ HORS LIGNE, ON LE DIT au lieu de laisser le délai de connexion s'écouler : c'est le mode normal de la ferme.
class EnvoiEmailTest {
  EnvoiEmailTest({
    required ParametresSmtp parametres,
    EnvoyeurSmtp? envoyeur,
    Future<bool> Function()? enLigne,
  }) : // `prefer_initializing_formals` suggère `this._parametres` : Dart l'interdit sur un paramètre NOMMÉ privé.
       // ignore: prefer_initializing_formals
       _parametres = parametres,
       _envoyeur = envoyeur ?? envoyerReellement,
       _enLigne = enLigne ?? connectiviteDuSysteme;

  final ParametresSmtp _parametres;
  final EnvoyeurSmtp _envoyeur;
  final Future<bool> Function() _enLigne;

  /// Délai d'un envoi : au-delà, l'échec est annoncé plutôt que d'attendre indéfiniment.
  static const delai = Duration(seconds: 30);

  static const sujet = 'LogiAgriERP — Test de configuration SMTP';
  static const corps =
      'Ceci est un e-mail de test envoyé depuis un poste LogiAgriERP (Paramètres > Email (SMTP)) — configuration '
      'SMTP validée avec succès.';

  static Future<void> envoyerReellement(Message message, SmtpServer serveur) =>
      send(message, serveur, timeout: delai);

  static Future<bool> connectiviteDuSysteme() async {
    try {
      final liens = await Connectivity().checkConnectivity();
      return liens.any((l) => l != ConnectivityResult.none);
    } catch (_) {
      // Plateforme sans canal de connectivité : on tente l'envoi, son échec dira la suite.
      return true;
    }
  }

  /// Serveur SMTP du `mailer` pour [c] : `ssl` = connexion chiffrée d'emblée ; `tls` = STARTTLS exigé ;
  /// `aucune` = connexion non chiffrée permise (choix « Aucune » du web).
  static SmtpServer serveurPour(ConfigurationSmtp c, String? motDePasse) => SmtpServer(
    c.hote,
    port: c.port,
    ssl: c.securite == SecuriteSmtp.ssl,
    allowInsecure: c.securite == SecuriteSmtp.aucune,
    username: c.utilisateur.isEmpty ? null : c.utilisateur,
    password: motDePasse,
  );

  /// Envoie l'e-mail de test à [destinataire] ; rend le message de succès du web. Lève [EchecEnvoiEmail].
  Future<String> envoyer(String destinataire) async {
    final dest = destinataire.trim();
    if (dest.isEmpty) {
      throw const EchecEnvoiEmail('Le champ destinataire du test est obligatoire.');
    }
    if (!ParametresSmtp.estAdresseEmail(dest)) {
      throw const EchecEnvoiEmail(
        'Le champ destinataire du test doit être une adresse e-mail valide.',
      );
    }

    final c = await _parametres.charger();
    if (c.hote.isEmpty) {
      throw const EchecEnvoiEmail(
        "Enregistrez d'abord l'hôte SMTP avant d'envoyer un e-mail de test.",
      );
    }
    final expediteur = c.adresseExpedition;
    if (expediteur == null) {
      throw const EchecEnvoiEmail(
        "Renseignez l'adresse d'expédition (ou l'utilisateur SMTP) avant d'envoyer un e-mail de test.",
      );
    }

    if (!await _enLigne()) {
      throw const EchecEnvoiEmail(
        "Poste hors ligne : l'e-mail de test exige le réseau. Réessayez une fois le poste connecté.",
      );
    }

    final message = Message()
      ..from = Address(expediteur, 'LogiAgriERP')
      ..recipients.add(dest)
      ..subject = sujet
      ..text = corps;

    try {
      await _envoyeur(message, serveurPour(c, await _parametres.motDePassePourEnvoi()));
    } catch (e) {
      throw EchecEnvoiEmail(
        "Échec de l'envoi — vérifiez la configuration SMTP (${messageErreurSmtp(e)}).",
      );
    }

    return 'E-mail de test envoyé à $dest.';
  }
}

/// Motif FRANÇAIS d'un échec d'envoi SMTP (ticket U5 : jamais l'exception brute à l'écran). Les erreurs que le
/// `mailer` ne connaît pas passent par [messageErreur].
///
/// ⚠️ Le détail technique (réponse du serveur, en anglais) n'est PAS affiché ; il ne contient jamais le mot de
/// passe, qui n'est ni journalisé ni repris ici.
String messageErreurSmtp(Object erreur) => switch (erreur) {
  SmtpClientAuthenticationException() =>
    'identifiant ou mot de passe refusé par le serveur SMTP',
  SmtpUnsecureException() =>
    "le serveur n'accepte pas de connexion chiffrée : choisissez SSL, ou « Aucune » si votre fournisseur l'exige",
  SmtpNoGreetingException() =>
    "le serveur ne répond pas comme un serveur SMTP : vérifiez l'hôte, le port et la sécurité",
  SmtpMessageValidationException() =>
    "adresse d'expédition ou de destination refusée",
  SmtpClientCommunicationException() =>
    "le serveur SMTP a refusé l'envoi",
  MailerException() => "le serveur SMTP a refusé l'envoi",
  SocketException() =>
    "serveur SMTP injoignable : vérifiez l'hôte, le port et la connexion du poste",
  HandshakeException() =>
    'échec de la connexion chiffrée : vérifiez la sécurité (TLS ou SSL) et le port',
  TimeoutException() => 'le serveur SMTP ne répond pas (délai dépassé)',
  _ => messageErreur(erreur),
};
