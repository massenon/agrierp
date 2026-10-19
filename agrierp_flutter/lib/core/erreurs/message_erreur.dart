import 'dart:io' show FileSystemException;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../sync/sync_engine.dart' show EchecSynchronisation;

/// Ticket U5 (décision D-U5 du 19/10/2026) — UN ÉCHEC TECHNIQUE S'ANNONCE EN
/// FRANÇAIS.
///
/// Trois écrans de synchronisation et deux exports affichaient l'exception
/// telle quelle (`'Synchronisation impossible — $e'`) : l'utilisateur lisait
/// « DioException [connection error]: The connection errored… »,
/// « FormatException: Unexpected character » ou « FileSystemException: Cannot
/// open file … (OS Error: Access is denied) ».
///
/// [messageErreur] rend une phrase française :
///   - le refus nommé du serveur ([EchecSynchronisation]) tel quel ;
///   - une erreur réseau ([DioException]) selon sa nature (injoignable, délai,
///     session expirée, droits, serveur en erreur) ;
///   - un fichier impossible à écrire ([FileSystemException],
///     [messageEcritureFichier]) ;
///   - le motif d'une erreur levée par NOTRE code (absorbeurs stricts, dépôts),
///     qui est déjà une phrase française — reconnue à ses caractères français ;
///   - sinon une phrase générique. Le détail technique part au journal
///     (`debugPrint`), jamais à l'écran.
///
/// ⚠️ Les MOTIFS de refus du serveur restent affichés mot pour mot (règle du
/// projet) : ils ne passent pas par ici, et sont français depuis `lang/fr` côté
/// web.
String messageErreur(Object erreur) {
  if (erreur is EchecSynchronisation) return erreur.message;

  if (erreur is DioException) return _messageReseau(erreur);

  if (erreur is FileSystemException) return messageEcritureFichier(erreur);

  final motif = switch (erreur) {
    FormatException(:final message) => message,
    ArgumentError(:final message) => message is String ? message : null,
    StateError(:final message) => message,
    _ => null,
  };
  if (motif != null && estPhraseFrancaise(motif)) return motif;

  debugPrint('Erreur inattendue (détail technique, non affiché) : $erreur');
  return messageGenerique;
}

/// Échec d'écriture d'un document (PDF, classeur) sur le disque du poste. Le
/// chemin est repris quand le système le donne ; le motif du système
/// (« Access is denied », « The process cannot access the file… »), anglais,
/// part au journal.
String messageEcritureFichier(Object erreur) {
  debugPrint('Écriture de fichier impossible (détail technique) : $erreur');
  final chemin = erreur is FileSystemException ? erreur.path : null;
  return "Impossible d'écrire le fichier"
      '${chemin == null || chemin.isEmpty ? '' : ' « $chemin »'} : '
      'vérifiez que le dossier existe, que vous avez le droit d’y écrire et '
      'que le fichier n’est pas ouvert dans un autre logiciel.';
}

/// Phrase affichée pour un échec technique sans explication exploitable.
const String messageGenerique =
    'Une erreur inattendue est survenue. Réessayez ; si le problème persiste, '
    "contactez l'administrateur.";

/// Vrai si le texte porte une marque du français écrit : accent, cédille,
/// guillemets « », ou un mot-outil français (« Le champ nom du poste est
/// obligatoire. » n'a aucun accent). Les messages techniques de Dart et du
/// framework (« Unexpected character », « Invalid radix-10 number », « Server
/// Error ») n'en portent aucun.
bool estPhraseFrancaise(String texte) => _marquesDuFrancais.hasMatch(texte);

final RegExp _marquesDuFrancais = RegExp(
  r'[éèêàâçùûîôœÉÈÀÇ«»]|\b(le|la|les|du|des|est|une|vous|votre|pas|au|aux)\b',
  caseSensitive: false,
);

String _messageReseau(DioException e) {
  final nomme = EchecSynchronisation.motifHttp(
    e.response?.statusCode,
    e.response?.data,
  );
  if (nomme != null) return nomme;

  return switch (e.type) {
    DioExceptionType.connectionError =>
      'Serveur injoignable : vérifiez la connexion du poste et l’adresse du '
          'serveur, puis réessayez.',
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      'Le serveur ne répond pas (délai dépassé) : réessayez dans un instant.',
    DioExceptionType.badCertificate =>
      'Le certificat de sécurité du serveur est refusé : vérifiez l’adresse '
          'du serveur.',
    DioExceptionType.cancel => 'Opération annulée.',
    DioExceptionType.badResponse => _messageStatut(e),
    // `unknown`, `transformTimeout` et tout type ajouté par une future version de Dio.
    _ =>
      'Échec de la communication avec le serveur : réessayez dans un instant.',
  };
}

String _messageStatut(DioException e) {
  final corps = e.response?.data;
  final serveur = corps is Map && corps['message'] is String
      ? corps['message'] as String
      : null;
  final statut = e.response?.statusCode ?? 0;

  // Le serveur répond en français depuis le ticket U5 : son message est repris
  // quand il en donne un (motif d'un 422, d'un 403 posé par l'application…).
  if (serveur != null && serveur.isNotEmpty && estPhraseFrancaise(serveur)) {
    return serveur;
  }
  return switch (statut) {
    404 =>
      'Adresse introuvable sur le serveur : le poste et le serveur ne '
          'sont peut-être pas à la même version.',
    422 => 'Le serveur a refusé les données envoyées.',
    >= 500 =>
      'Le serveur a rencontré une erreur. Réessayez dans un instant ; '
          "si le problème persiste, contactez l'administrateur.",
    _ => 'Le serveur a refusé la demande (code $statut).',
  };
}
