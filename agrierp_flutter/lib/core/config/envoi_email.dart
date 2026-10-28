import 'package:mailer/mailer.dart';

import 'envoi_email_test.dart';
import 'parametres_smtp.dart';

/// Ticket AUT-3 — ENVOI D'UN E-MAIL PAR LE SMTP DU POSTE (Paramètres > Email (SMTP)), sans passer par le serveur.
///
/// Remplace le SMS : la relance par e-mail part du poste lui-même. Même configuration, mêmes refus et mêmes messages que
/// l'e-mail de test ([EnvoiEmailTest]) ; seul le contenu change. ⚠️ Hors ligne, l'envoi est refusé en le disant (aucune
/// attente d'un délai de connexion) : la trace d'une relance n'est écrite QU'APRÈS un envoi réussi, comme au web.
class EnvoiEmail {
  EnvoiEmail({required this.parametres, this.envoyeur, this.enLigne});

  final ParametresSmtp parametres;

  /// Envoi réel du `mailer` par défaut ; injecté dans les tests (aucun réseau).
  final EnvoyeurSmtp? envoyeur;
  final Future<bool> Function()? enLigne;

  /// Envoie [corps] à [destinataire]. Lève [EchecEnvoiEmail] (phrase française prête à afficher).
  Future<void> envoyer({required String destinataire, required String sujet, required String corps}) async {
    final dest = destinataire.trim();
    if (!ParametresSmtp.estAdresseEmail(dest)) {
      throw const EchecEnvoiEmail("L'adresse e-mail du destinataire n'est pas valide.");
    }

    final c = await parametres.charger();
    if (c.hote.isEmpty) throw const EchecEnvoiEmail("Enregistrez d'abord l'hôte SMTP (Paramètres > Email (SMTP)) avant d'envoyer un e-mail.");
    final expediteur = c.adresseExpedition;
    if (expediteur == null) throw const EchecEnvoiEmail("Renseignez l'adresse d'expédition (ou l'utilisateur SMTP) avant d'envoyer un e-mail.");
    if (!await (enLigne ?? EnvoiEmailTest.connectiviteDuSysteme)()) {
      throw const EchecEnvoiEmail("Poste hors ligne : l'e-mail exige le réseau. Réessayez une fois le poste connecté.");
    }

    final message = Message()
      ..from = Address(expediteur, 'AgriERP')
      ..recipients.add(dest)
      ..subject = sujet
      ..text = corps;

    try {
      await (envoyeur ?? EnvoiEmailTest.envoyerReellement)(message, EnvoiEmailTest.serveurPour(c, await parametres.motDePassePourEnvoi()));
    } catch (e) {
      throw EchecEnvoiEmail("Échec de l'envoi — vérifiez la configuration SMTP (${messageErreurSmtp(e)}).");
    }
  }
}
