import '../../core/audit/libelles_audit.dart';
import '../../core/auth/auth_service.dart';
import '../../core/database/app_database.dart';

/// Une ligne du journal d'audit personnel.
class LigneJournalProfil {
  const LigneJournalProfil({
    required this.date,
    required this.action,
    required this.module,
    required this.ip,
  });

  /// `null` quand le serveur n'a pas daté l'entrée : l'écran écrit « — ».
  final DateTime? date;

  /// Libellé français, jamais la clé technique (sauf clé inconnue).
  final String action;
  final String? module;
  final String? ip;
}

/// Ce que lit `prototype_html/mon-profil.html`.
class DonneesProfil {
  const DonneesProfil({
    required this.nom,
    required this.initiales,
    required this.email,
    required this.roleLibelle,
    required this.derniereConnexion,
    required this.adresseIp,
    required this.actif,
    required this.journal,
  });

  final String nom;
  final String initiales;
  final String email;

  /// `null` quand le serveur n'a pas qualifié le rôle : l'écran omet le badge,
  /// comme la vue Blade (`@if(role_label)`).
  final String? roleLibelle;

  final DateTime? derniereConnexion;
  final String? adresseIp;

  /// `null` = le poste ne détient pas la ligne de cet utilisateur. L'écran
  /// écrit « — » : ni « Actif » ni « Inactif » ne s'affirme sans la donnée.
  final bool? actif;

  /// Au plus dix lignes, la plus récente d'abord.
  final List<LigneJournalProfil> journal;
}

/// Lectures de `mon-profil.html`.
///
/// ⚠️⚠️ **LE POSTE NE DÉTIENT QUE LES CENT DERNIÈRES ACTIONS DE LA FERME**, pas
/// l'historique de chacun : `SyncController` borne le tirage à 100 lignes toutes
/// personnes confondues. Le « journal des 10 dernières actions » d'un utilisateur
/// peu actif peut donc en compter moins de dix, voire aucune, alors que le
/// serveur en détient davantage. L'écran le dit ; il ne présente pas un journal
/// court comme un journal complet.
///
/// ⚠️ **L'IDENTITÉ DE LA LIGNE D'AUDIT EST UN NOM, PAS UN IDENTIFIANT.** Le
/// tirage sert `user_name` et non `user_id` : deux utilisateurs homonymes
/// verraient leurs actions confondues. Limite du contrat de synchronisation,
/// non corrigeable côté poste — signalée dans le ticket F0.57.
///
/// ⚠️ **« DERNIÈRE CONNEXION » RETIENT `login` ET `api.login`.** La vue web ne
/// lit que `login` (connexion navigateur) ; une connexion de ce poste est
/// journalisée `api.login`. Ne lire que la première ferait afficher, au poste,
/// la dernière fois que la personne a ouvert un navigateur.
class MonProfilRepository {
  MonProfilRepository({required this.database});

  final AppDatabase database;

  static const _actionsDeConnexion = {'login', 'api.login'};

  Future<DonneesProfil> charger(SessionUtilisateur? session) async {
    // Le nom du journal est celui de la fiche utilisateur tirée du serveur
    // quand elle existe ; sinon celui de la session.
    Utilisateur? fiche;
    if (session != null && session.id.isNotEmpty) {
      fiche = await (database.select(
        database.utilisateurs,
      )..where((u) => u.id.equals(session.id))).getSingleOrNull();
    }

    final nom = fiche?.name ?? session?.nom ?? '';

    final lignes = nom.isEmpty
        ? <AuditLog>[]
        : await (database.select(
            database.auditLogs,
          )..where((l) => l.userName.equals(nom))).get();
    lignes.sort(
      (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );

    final connexion = lignes
        .where((l) => _actionsDeConnexion.contains(l.action))
        .firstOrNull;

    final roleLibelle = session?.roleLibelle;

    return DonneesProfil(
      nom: nom,
      initiales: initialesDe(nom),
      email: session?.email ?? '',
      roleLibelle: (roleLibelle == null || roleLibelle.isEmpty)
          ? null
          : roleLibelle,
      derniereConnexion: connexion?.createdAt,
      adresseIp: connexion?.ipAddress,
      actif: fiche?.isActive,
      journal: [
        for (final l in lignes.take(10))
          LigneJournalProfil(
            date: l.createdAt,
            action: LibellesAudit.action(l.action),
            module: LibellesAudit.module(l.module),
            ip: l.ipAddress,
          ),
      ],
    );
  }

  /// Deux premières initiales du nom, en majuscules — l'accesseur `initials` de
  /// `User` côté serveur. `?` quand le nom est vide.
  static String initialesDe(String nom) {
    final mots = nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty);
    final initiales = mots
        .take(2)
        .map((m) => String.fromCharCode(m.runes.first).toUpperCase())
        .join();
    return initiales.isEmpty ? '?' : initiales;
  }

  /// Règles de saisie du changement de mot de passe, à l'identique du serveur
  /// (`PolitiqueMotDePasse`, ticket Laravel 15.9) : 8 caractères, une majuscule,
  /// un chiffre — décision du commanditaire. Le serveur revérifie de toute
  /// façon ; ce contrôle évite seulement un aller-retour réseau. Retourne les messages par champ, vide si la
  /// saisie est recevable.
  static Map<String, String> validerMotDePasse({
    required String ancien,
    required String nouveau,
    required String confirmation,
  }) {
    final erreurs = <String, String>{};

    if (ancien.trim().isEmpty) {
      erreurs['ancien'] = 'Ce champ est obligatoire.';
    }
    if (nouveau.trim().isEmpty) {
      erreurs['nouveau'] = 'Ce champ est obligatoire.';
    } else if (nouveau.length < 8) {
      erreurs['nouveau'] =
          'Le mot de passe doit contenir au moins 8 caractères.';
    } else if (!RegExp('[A-Z]').hasMatch(nouveau) ||
        !RegExp('[0-9]').hasMatch(nouveau)) {
      erreurs['nouveau'] =
          'Le mot de passe doit contenir au moins une majuscule et un chiffre.';
    }
    if (confirmation.trim().isEmpty) {
      erreurs['confirmation'] = 'Ce champ est obligatoire.';
    } else if (nouveau.isNotEmpty && nouveau != confirmation) {
      erreurs['confirmation'] = 'Les mots de passe ne correspondent pas.';
    }

    return erreurs;
  }
}
