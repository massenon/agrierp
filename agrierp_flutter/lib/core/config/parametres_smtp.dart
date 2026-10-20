import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../database/app_database.dart';

/// Sécurité de la connexion SMTP — les trois choix du web (`EmailSmtp::SECURITES` : `tls`, `ssl`, `''`).
enum SecuriteSmtp {
  tls('tls', 'TLS'),
  ssl('ssl', 'SSL'),
  aucune('', 'Aucune');

  const SecuriteSmtp(this.code, this.libelle);

  /// Valeur enregistrée, celle du web.
  final String code;

  /// Libellé de la liste, celui du web.
  final String libelle;

  static SecuriteSmtp depuisCode(String? code) {
    final propre = (code ?? 'tls').trim().toLowerCase();
    for (final s in values) {
      if (s.code == propre) return s;
    }
    return tls;
  }
}

/// Réglages SMTP de CE poste, tels que l'onglet « Email (SMTP) » les affiche.
///
/// ⚠️ Le mot de passe n'y figure PAS : seulement s'il en existe un ([motDePasseEnregistre]). Il ne se relit
/// qu'au moment d'envoyer ([ParametresSmtp.motDePassePourEnvoi]).
class ConfigurationSmtp {
  const ConfigurationSmtp({
    this.hote = '',
    this.port = 587,
    this.securite = SecuriteSmtp.tls,
    this.utilisateur = '',
    this.expediteur = '',
    this.motDePasseEnregistre = false,
    this.emailDeContact,
  });

  final String hote;
  final int port;
  final SecuriteSmtp securite;
  final String utilisateur;

  /// Adresse d'expédition saisie ; vide : [adresseExpedition] retombe sur l'e-mail de contact, comme au web.
  final String expediteur;
  final bool motDePasseEnregistre;

  /// E-mail de contact de la ferme (`company_settings.email`, descendu du serveur — ticket 14.84).
  final String? emailDeContact;

  /// Expéditeur réel : l'adresse d'expédition, sinon l'e-mail de contact, sinon l'utilisateur SMTP
  /// (`CompanySetting::adresseExpedition()` du web, plus ce dernier recours propre au poste).
  String? get adresseExpedition {
    for (final a in [expediteur, emailDeContact ?? '', utilisateur]) {
      if (a.trim().isNotEmpty) return a.trim();
    }
    return null;
  }
}

/// Tickets CFG-2 (décision client du 19/10/2026, D-CFG-2) — RÉGLAGES SMTP DU POSTE.
///
/// Hôte, port, sécurité, utilisateur et adresse d'expédition sont des réglages LOCAUX (`app_settings`, comme
/// [ParametresPoste]) ; ils ne se synchronisent pas : chaque poste a les siens.
///
/// ⚠️⚠️ **LE MOT DE PASSE VA AU COFFRE DU SYSTÈME, JAMAIS EN BASE.** `flutter_secure_storage` (le gestionnaire
/// d'identifiants de Windows), comme le jeton de session (`AuthService`) — l'équivalent sûr du `poste.json` de
/// TATACORA. Ni Drift, ni la file de synchronisation, ni un journal : une copie de `agrierp.sqlite` emportée sur
/// une clé ne doit pas ouvrir la boîte mail de la ferme. Un garde-fou lit ce fichier
/// (`test/parametres_smtp_test.dart`) : seules les clés de [clesReglages] s'écrivent dans `app_settings`.
///
/// ⚠️ **CHAMP VIDE = MOT DE PASSE INCHANGÉ**, comme au web : l'écran ne le réaffiche jamais ; l'effacer est un
/// geste explicite ([effacerMotDePasse]).
class ParametresSmtp {
  ParametresSmtp({required AppDatabase database, FlutterSecureStorage? coffre})
    : _db = database,
      _coffre = coffre ?? const FlutterSecureStorage();

  static const cleHote = 'smtp.hote';
  static const clePort = 'smtp.port';
  static const cleSecurite = 'smtp.securite';
  static const cleUtilisateur = 'smtp.utilisateur';
  static const cleExpediteur = 'smtp.expediteur';

  /// Les SEULES clés que ce service écrit dans `app_settings`.
  static const clesReglages = [
    cleHote,
    clePort,
    cleSecurite,
    cleUtilisateur,
    cleExpediteur,
  ];

  /// Clé du mot de passe AU COFFRE (jamais une clé de `app_settings`).
  static const cleCoffreMotDePasse = 'agrierp.smtp.mot_de_passe';

  static const portParDefaut = 587;

  final AppDatabase _db;
  final FlutterSecureStorage _coffre;

  Future<ConfigurationSmtp> charger() async {
    final reglages = {
      for (final ligne in await (_db.select(
        _db.appSettings,
      )..where((t) => t.key.isIn(clesReglages))).get())
        ligne.key: ligne.value,
    };
    final entreprise = await (_db.select(
      _db.companySettings,
    )..limit(1)).getSingleOrNull();

    return ConfigurationSmtp(
      hote: reglages[cleHote] ?? '',
      port: int.tryParse(reglages[clePort] ?? '') ?? portParDefaut,
      securite: SecuriteSmtp.depuisCode(reglages[cleSecurite]),
      utilisateur: reglages[cleUtilisateur] ?? '',
      expediteur: reglages[cleExpediteur] ?? '',
      motDePasseEnregistre: await motDePasseEnregistre(),
      emailDeContact: entreprise?.email,
    );
  }

  /// Règles de `EmailSmtp::save()` du web, messages de `lang/fr/validation.php` : rend les erreurs par champ
  /// (`hote`, `port`, `utilisateur`, `expediteur`), vide si la saisie est valable.
  static Map<String, String> erreursDeSaisie({
    required String hote,
    required String port,
    String utilisateur = '',
    String expediteur = '',
  }) {
    final erreurs = <String, String>{};
    final h = hote.trim();
    if (h.isEmpty) {
      erreurs['hote'] = 'Le champ hôte SMTP est obligatoire.';
    } else if (h.length > 150) {
      erreurs['hote'] = 'Le champ hôte SMTP ne doit pas dépasser 150 caractères.';
    }
    final p = port.trim();
    final n = int.tryParse(p);
    if (p.isEmpty) {
      erreurs['port'] = 'Le champ port est obligatoire.';
    } else if (n == null) {
      erreurs['port'] = 'Le champ port doit être un nombre entier.';
    } else if (n < 1) {
      erreurs['port'] = 'Le champ port doit être au moins égal à 1.';
    } else if (n > 65535) {
      erreurs['port'] = 'Le champ port ne doit pas dépasser 65535.';
    }
    if (utilisateur.trim().length > 150) {
      erreurs['utilisateur'] =
          'Le champ utilisateur SMTP ne doit pas dépasser 150 caractères.';
    }
    final e = expediteur.trim();
    if (e.isNotEmpty && !estAdresseEmail(e)) {
      erreurs['expediteur'] =
          "Le champ adresse d'expédition doit être une adresse e-mail valide.";
    }
    return erreurs;
  }

  static bool estAdresseEmail(String valeur) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(valeur.trim());

  /// Enregistre les réglages. [motDePasse] vide : le mot de passe au coffre est CONSERVÉ.
  ///
  /// Lève [ArgumentError] (message français) si la saisie n'est pas valable — l'écran valide avant.
  Future<void> enregistrer({
    required String hote,
    required int port,
    required SecuriteSmtp securite,
    String utilisateur = '',
    String expediteur = '',
    String motDePasse = '',
  }) async {
    final erreurs = erreursDeSaisie(
      hote: hote,
      port: '$port',
      utilisateur: utilisateur,
      expediteur: expediteur,
    );
    if (erreurs.isNotEmpty) throw ArgumentError(erreurs.values.first);

    await _db.transaction(() async {
      await _ecrireReglage(cleHote, hote.trim());
      await _ecrireReglage(clePort, '$port');
      await _ecrireReglage(cleSecurite, securite.code);
      await _ecrireReglage(cleUtilisateur, utilisateur.trim());
      await _ecrireReglage(cleExpediteur, expediteur.trim());
    });

    // ⚠️⚠️ Au COFFRE, et seulement s'il a été saisi : un champ vide ne l'efface pas.
    if (motDePasse.isNotEmpty) {
      await _coffre.write(key: cleCoffreMotDePasse, value: motDePasse);
    }
  }

  /// Effacement EXPLICITE (bouton « Effacer le mot de passe », confirmé).
  Future<void> effacerMotDePasse() => _coffre.delete(key: cleCoffreMotDePasse);

  /// Un mot de passe est-il au coffre ? Coffre illisible : `false` (rien d'utilisable n'y est).
  Future<bool> motDePasseEnregistre() async {
    try {
      final valeur = await _coffre.read(key: cleCoffreMotDePasse);
      return valeur != null && valeur.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Le mot de passe, relu au coffre AU MOMENT D'ENVOYER — jamais affiché, jamais journalisé.
  Future<String?> motDePassePourEnvoi() async {
    final valeur = await _coffre.read(key: cleCoffreMotDePasse);
    return valeur == null || valeur.isEmpty ? null : valeur;
  }

  /// ⚠️ L'unique écriture de `app_settings` de ce service : une clé de [clesReglages], jamais le mot de passe.
  Future<void> _ecrireReglage(String cle, String valeur) {
    assert(clesReglages.contains(cle), 'clé SMTP inconnue : $cle');
    return _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: cle, value: valeur),
        );
  }
}
