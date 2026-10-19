import '../../core/auth/auth_service.dart';
import '../../core/config/environnement.dart';
import '../../core/config/parametres_poste.dart';

/// État du jeton de session de ce poste, tel que l'onglet « Appairage » l'annonce.
enum EtatJeton {
  /// Jeton au coffre, et rien n'indique que le serveur le refuse.
  present('Présent', 'Jeton de session présent : ce poste est appairé au serveur.'),

  /// Le serveur a répondu 401 / 403 : la synchronisation automatique est suspendue (S-T1) — appairage révoqué au
  /// web, jeton expiré ou compte désactivé.
  refuse(
    'Session refusée',
    "Session refusée par le serveur : appairage révoqué, jeton expiré ou compte désactivé. La synchronisation "
        "automatique est arrêtée jusqu'à une nouvelle connexion — réappairez ce poste.",
  ),

  /// Aucun jeton au coffre.
  absent('Absent', "Aucun jeton de session : ce poste n'est pas appairé. Connectez-vous pour l'appairer."),

  /// Coffre du système illisible : le poste ne sait pas (« — », jamais une affirmation).
  inconnu('—', 'Coffre du système illisible : état du jeton inconnu.');

  const EtatJeton(this.libelle, this.explication);

  final String libelle;
  final String explication;
}

/// Ticket CFG-2 (décision client du 19/10/2026) — CE QUE L'ONGLET « APPAIRAGE » DE PARAMÈTRES LIT ET FAIT.
///
/// Remplace l'écran isolé « Paramètres du poste » : identifiant du poste (jamais régénéré), environnement de
/// construction (S-T8), adresse du serveur (réglable, normalisée, effective au redémarrage), intervalle de la
/// synchronisation automatique (H13 / S-T3) — tout cela dans [parametres] — plus la SESSION : compte connecté,
/// état du jeton, test de connexion (`GET /api/auth/me`) et réappairage.
///
/// ⚠️ RÉAPPAIRER = DÉCONNEXION PROPRE PUIS ÉCRAN DE CONNEXION ([reappairer], le « Déconnexion » du menu du compte,
/// ticket H1). Les saisies en attente RESTENT dans la base locale : elles partiront après la reconnexion. Une
/// nouvelle connexion délivre un jeton neuf nommé d'après [identifiant] — c'est ce qui rétablit un poste dont le
/// web a révoqué l'appairage.
class AppairagePoste {
  AppairagePoste({
    required this.parametres,
    required this.identifiant,
    required this.auth,
    Environnement? environnement,
    bool Function()? sessionSuspendue,
    this.reappairer,
  }) : environnement = environnement ?? Environnement.courant,
       _sessionSuspendue = sessionSuspendue ?? _jamais;

  static bool _jamais() => false;

  final ParametresPoste parametres;
  final String identifiant;
  final AuthService auth;
  final Environnement environnement;
  final bool Function() _sessionSuspendue;

  /// Déconnexion propre et retour à l'écran de connexion ; `null` : geste non proposé (premier démarrage, tests).
  final Future<void> Function()? reappairer;

  SessionUtilisateur? get session => auth.utilisateur;

  /// Adresse en usage par le client HTTP (celle du démarrage).
  String get adresseEnUsage => auth.adresseServeur;

  /// Ticket S-T1 — la synchronisation automatique de cette session s'est arrêtée sur un 401 / 403.
  bool get sessionSuspendue => _sessionSuspendue();

  Future<EtatJeton> etatDuJeton() async {
    final present = await auth.jetonPresent();
    if (present == null) return EtatJeton.inconnu;
    if (!present) return EtatJeton.absent;
    return sessionSuspendue ? EtatJeton.refuse : EtatJeton.present;
  }
}
