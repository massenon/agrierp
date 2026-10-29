import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../stocks/pmp_service.dart';

/// Les quatre modules d'espèce, tels que la maquette les nomme.
enum ModuleEspece {
  cuniculture('cuniculture', 'Cuniculture (Lapins)'),
  aviculture('aviculture', 'Aviculture (Volailles)'),
  porciculture('porciculture', 'Porciculture (Porcs)'),
  helico('helico', 'Héliciculture (Escargots)');

  const ModuleEspece(this.code, this.libelle);

  final String code;
  final String libelle;
}

class DonneesParametresGeneraux {
  const DonneesParametresGeneraux({
    required this.entreprise,
    required this.modules,
    required this.roles,
    required this.utilisateurs,
    required this.comptes,
    required this.audit,
  });

  /// ⚠️ `null` tant qu'aucun tirage n'a eu lieu : l'identité de la ferme n'est
  /// pas devinable, et un écran qui afficherait « — » partout sans le dire
  /// laisserait croire à une fiche vide côté serveur.
  final CompanySetting? entreprise;

  final List<ModulesConfigData> modules;
  final List<RolesApplicatif> roles;
  final List<Utilisateur> utilisateurs;
  final List<TreasuryAccount> comptes;
  final List<AuditLog> audit;

  bool moduleActif(ModuleEspece module) =>
      modules
          .where((m) => m.speciesCode == module.code)
          .map((m) => m.isEnabled)
          .firstOrNull ??
      // ⚠️⚠️ **ACTIF PAR DÉFAUT, ET C'EST DÉLIBÉRÉ.** Tant que le poste n'a
      // rien tiré, il ne sait rien : masquer une espèce sur cette ignorance
      // ferait disparaître le cheptel réel de la ferme. On ne cache qu'un
      // module que le serveur a explicitement éteint.
      true;

  /// Module « Assistant de démarrage » : ÉTEINT par défaut (contrairement aux espèces) — sans ligne, il n'est pas actif.
  bool get assistantActif =>
      modules.where((m) => m.speciesCode == 'assistant_demarrage').map((m) => m.isEnabled).firstOrNull ?? false;

  /// Codes des espèces que la ferme exploite réellement.
  Set<String> get especesActives => {
    for (final module in ModuleEspece.values)
      if (moduleActif(module)) module.code,
  };

  int get modulesActifs => ModuleEspece.values.where(moduleActif).length;

  int get utilisateursActifs => utilisateurs.where((u) => u.isActive).length;

  double get tresorerieTotale =>
      comptes.fold<double>(0, (t, c) => t + c.balance);

  List<TreasuryAccount> comptesDe(String type) =>
      comptes.where((c) => c.type == type).toList();

  /// Solde cumulé d'une famille de comptes — `caisse`, `banque`,
  /// `mobile_money`.
  ///
  /// ⚠️ **LA FERME A PLUSIEURS BANQUES ET PLUSIEURS OPÉRATEURS.** La maquette
  /// affiche « Solde Banques (521) » au singulier de la carte mais au pluriel
  /// des comptes : BOA et Ecobank d'un côté, MTN et Moov de l'autre. Prendre
  /// le premier compte trouvé afficherait la moitié de la trésorerie réelle.
  double soldeDe(String type) =>
      comptesDe(type).fold<double>(0, (t, c) => t + c.balance);

  /// ⚠️⚠️ **UNE TRACE D'AUDIT VIEILLIT PENDANT QUE LE POSTE EST HORS LIGNE.**
  /// Le compteur « Événements (24h) » de la maquette se lit depuis MAINTENANT.
  /// Si le dernier tirage remonte à plus de 24 h, il vaut structurellement
  /// zéro — et « 0 » dirait « rien ne s'est passé sur la ferme » quand le
  /// poste ne sait simplement rien. D'où le drapeau, et le tiret qu'il
  /// commande à l'écran.
  bool get auditRecent =>
      audit.any((l) => l.createdAt != null && _dansLes24h(l.createdAt!));

  int get evenements24h => audit
      .where((l) => l.createdAt != null && _dansLes24h(l.createdAt!))
      .length;

  /// ⚠️ `login.failed` est le nom que le serveur donne à une tentative
  /// refusée. Compter sur le libellé affiché ferait dépendre une alerte de
  /// sécurité d'une traduction.
  ///
  /// 🔴→✅ Ticket U14 — sur les dernières 24 h, comme le web (`AuditLogs::getKpisProperty()`) : le poste comptait toutes
  /// les tentatives reçues, quelle que soit leur date.
  int get connexionsEchouees => audit
      .where((l) => l.action == 'login.failed' && l.createdAt != null && _dansLes24h(l.createdAt!))
      .length;

  /// 🔴→✅ Ticket U14 — « Rechercher... » de l'onglet du web (`AuditLogs::getLogsProperty()`) : `action LIKE '%…%'` OU
  /// `module LIKE '%…%'`, sur les CLÉS techniques (`sale.created`, `ventes`) et non sur les libellés, sous la collation
  /// du serveur (ni casse ni accents ; `%` et `_` sont des jokers) ; « 0 » ne filtre pas (`when()` le lit faux).
  static List<AuditLog> filtrerAudit(List<AuditLog> lignes, String recherche) {
    if (recherche.isEmpty || recherche == '0') return lignes;
    final motif = StringBuffer();
    for (final c in cleCommeLeServeur(recherche).split('')) {
      motif.write(switch (c) {
        '%' => '.*',
        '_' => '.',
        _ => RegExp.escape(c),
      });
    }
    final like = RegExp(motif.toString(), dotAll: true);
    return [
      for (final l in lignes)
        if (like.hasMatch(cleCommeLeServeur(l.action)) || like.hasMatch(cleCommeLeServeur(l.module ?? ''))) l,
    ];
  }

  static bool _dansLes24h(DateTime instant) =>
      DateTime.now().difference(instant).inHours.abs() < 24;
}

/// Lectures de `prototype_html/parametres-hub.html`.
///
/// ⚠️⚠️ **AUCUN SECRET NE DESCEND AU POSTE.** `company_settings` porte côté
/// serveur les mots de passe SMTP et les jetons SMS (Twilio, Vonage) : un poste
/// volé donnerait accès au compte SMS et à la boîte mail de la ferme. Seuls
/// l'identité de l'entreprise et ses taux sont servis — et le poste n'a même
/// pas de colonne où ranger un secret.
///
/// ⚠️⚠️ **`modules_config` DÉCIDE DES ESPÈCES VISIBLES.** L'héliciculture est
/// éteinte sur cette ferme, et le poste proposait pourtant la fiche Escargots :
/// la maquette, elle, masque les blocs `data-module="helico"`. Le poste lit
/// désormais cette table.
/// Ticket UT-1 — refus d'une saisie de compte, champ par champ (`nom`, `identifiant`, `email`, `role`, `motDePasse`,
/// `''` pour le compte entier) ; les messages sont ceux de `lang/fr/validation.php` du web.
class RefusSaisieUtilisateur implements Exception {
  const RefusSaisieUtilisateur(this.champs);

  final Map<String, String> champs;

  @override
  String toString() => champs.values.join(' ');
}

class ParametresGenerauxRepository {
  ParametresGenerauxRepository({
    required this.database,
    DateTime Function()? maintenant,
    Uuid? uuid,
    this.identifiantPoste = 'poste',
    FlutterSecureStorage? coffre,
  }) : _maintenant = maintenant ?? HeureBenin.maintenant,
       _uuid = uuid ?? const Uuid(),
       _coffre = coffre ?? const FlutterSecureStorage();

  final AppDatabase database;
  final DateTime Function() _maintenant;
  final Uuid _uuid;

  /// `device_id` des lignes écrites ici (ticket UT-1).
  final String identifiantPoste;

  /// Ticket UT-1 — le coffre du système : un mot de passe saisi y attend son envoi, jamais en base.
  final FlutterSecureStorage _coffre;

  /// Ticket UT-1 — message du web quand on archive son propre compte.
  static const messagePropreCompte = 'Vous ne pouvez pas archiver votre propre compte.';

  /// Ticket MDP-1 — messages du web (`SaisieUtilisateurAction::MESSAGE_PROPRE_REINITIALISATION` / `…_COMPTE_ARCHIVE_…`),
  /// lus dans le PHP par `test/reinitialisation_mot_de_passe_test.dart`.
  static const messagePropreReinitialisation = 'Vous ne pouvez pas réinitialiser votre propre mot de passe : utilisez Mon Profil.';
  static const messageCompteArchiveReinitialisation = 'Ce compte est archivé : réactivez-le avant de réinitialiser son mot de passe.';

  /// Clé du coffre du mot de passe en attente d'un compte (la même que celle lue par le moteur à l'envoi).
  static String cleMotDePasse(String idUtilisateur) => 'agrierp.utilisateur.mdp.$idUtilisateur';

  /// Ticket UT-1 — crée ou modifie un compte LOCALEMENT (`pending`), avec les règles de
  /// `SaisieUtilisateurAction::regles()` : nom ≤ 150 ; identifiant 3–50, lettres/chiffres/`.`/`-`/`_` (JAMAIS
  /// d'arobase : la connexion choisit sa colonne selon « @ »), unique ; e-mail valide ≤ 150, unique ; rôle parmi
  /// ceux reçus ; mot de passe obligatoire à la création, facultatif ensuite (vide = conservé), politique 14.65
  /// (8 caractères, une lettre, un chiffre, un symbole). Le mot de passe va au COFFRE, jamais en base. Rend l'identifiant.
  Future<String> enregistrerUtilisateur({
    String? id,
    required String nom,
    required String identifiant,
    required String email,
    required String role,
    required String motDePasse,
  }) async {
    final erreurs = <String, String>{};
    final nomNet = nom.trim();
    final identifiantNet = identifiant.trim();
    final emailNet = email.trim();

    if (nomNet.isEmpty) erreurs['nom'] = 'Le champ nom est obligatoire.';
    if (nomNet.length > 150) erreurs['nom'] = 'Le champ nom ne doit pas dépasser 150 caractères.';

    if (identifiantNet.isEmpty) {
      erreurs['identifiant'] = "Le champ nom d'utilisateur est obligatoire.";
    } else if (identifiantNet.length < 3) {
      erreurs['identifiant'] = "Le champ nom d'utilisateur doit contenir au moins 3 caractères.";
    } else if (identifiantNet.length > 50) {
      erreurs['identifiant'] = "Le champ nom d'utilisateur ne doit pas dépasser 50 caractères.";
    } else if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(identifiantNet)) {
      erreurs['identifiant'] = "Le format du champ nom d'utilisateur n'est pas valide.";
    }

    if (emailNet.isEmpty) {
      erreurs['email'] = 'Le champ courriel est obligatoire.';
    } else if (emailNet.length > 150) {
      erreurs['email'] = 'Le champ courriel ne doit pas dépasser 150 caractères.';
    } else if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(emailNet)) {
      erreurs['email'] = 'Le champ courriel doit être une adresse courriel valide.';
    }

    final roles = (await database.select(database.rolesApplicatifs).get()).map((r) => r.name).toSet();
    if (role.trim().isEmpty) {
      erreurs['role'] = 'Le champ rôle est obligatoire.';
    } else if (!roles.contains(role)) {
      erreurs['role'] = "La valeur sélectionnée pour le champ rôle n'existe pas.";
    }

    if (motDePasse.isEmpty) {
      if (id == null) erreurs['motDePasse'] = 'Le champ mot de passe est obligatoire.';
    } else {
      final defaut = motDePasseRefuse(motDePasse);
      if (defaut != null) erreurs['motDePasse'] = defaut;
    }

    // Unicité LOCALE (le serveur la garantit à son tour, pour toute la ferme).
    final autres = (await database.select(database.utilisateurs).get()).where((u) => u.id != id);
    if (!erreurs.containsKey('identifiant') && autres.any((u) => u.username?.toLowerCase() == identifiantNet.toLowerCase())) {
      erreurs['identifiant'] = "La valeur du champ nom d'utilisateur est déjà utilisée.";
    }
    if (!erreurs.containsKey('email') && autres.any((u) => u.email?.toLowerCase() == emailNet.toLowerCase())) {
      erreurs['email'] = 'La valeur du champ courriel est déjà utilisée.';
    }
    if (erreurs.isNotEmpty) throw RefusSaisieUtilisateur(erreurs);

    final identifiantLigne = id ?? _uuid.v4();
    final existant = id == null ? null : await (database.select(database.utilisateurs)..where((t) => t.id.equals(id))).getSingleOrNull();
    final ligne = UtilisateursCompanion.insert(
      id: identifiantLigne,
      deviceId: identifiantPoste,
      syncStatus: const Value(SyncStatus.pending),
      updatedAt: HeureBenin.versInstant(_maintenant()),
      name: nomNet,
      username: Value(identifiantNet),
      email: Value(emailNet),
      role: Value(role),
      isActive: Value(existant?.isActive ?? true),
    );
    await database.transaction(() async {
      await database.into(database.utilisateurs).insert(ligne, onConflict: DoUpdate((_) => ligne));
    });
    if (motDePasse.isNotEmpty) {
      await _coffre.write(key: cleMotDePasse(identifiantLigne), value: motDePasse);
      // MDP-1 : un mot de passe saisi par la modification ordinaire n'est pas un temporaire — il remplace une
      // réinitialisation encore en attente, qui ne doit pas le marquer à tort.
      await _coffre.delete(key: cleMotDePasseTemporaire(identifiantLigne));
    }
    return identifiantLigne;
  }

  /// Ticket MDP-1 — clé du coffre qui marque le mot de passe en attente comme TEMPORAIRE (la même que celle lue par le moteur).
  static String cleMotDePasseTemporaire(String idUtilisateur) => 'agrierp.utilisateur.reinit.$idUtilisateur';

  /// Ticket MDP-1 — RÉINITIALISATION PAR UN ADMINISTRATEUR, mêmes règles que `SaisieUtilisateurAction::
  /// reinitialiserMotDePasse` : jamais son propre compte, jamais un compte archivé, mot de passe temporaire selon
  /// `Password::defaults()` (obligatoire). Le temporaire attend au COFFRE (comme UT-1, jamais en base) avec le marqueur
  /// de réinitialisation ; la ligne repasse `pending` et porte le drapeau `must_change_password` (affichage immédiat de
  /// la liste, confirmé au prochain tirage). Le serveur ferme jetons et sessions, trace `user.password_reset` et
  /// rejette (`conflict`, motif du web) ce que le poste n'aurait pas su refuser.
  Future<void> reinitialiserMotDePasseUtilisateur(String id, String motDePasseTemporaire, {required String? idConnecte}) async {
    if (idConnecte != null && id == idConnecte) throw const RefusSaisieUtilisateur({'': messagePropreReinitialisation});

    final u = await (database.select(database.utilisateurs)..where((t) => t.id.equals(id))).getSingle();
    if (!u.isActive) throw const RefusSaisieUtilisateur({'': messageCompteArchiveReinitialisation});

    final defaut = motDePasseTemporaire.isEmpty ? 'Le champ mot de passe temporaire est obligatoire.' : motDePasseRefuse(motDePasseTemporaire)?.replaceFirst('champ mot de passe', 'champ mot de passe temporaire');
    if (defaut != null) throw RefusSaisieUtilisateur({'motDePasse': defaut});

    await _coffre.write(key: cleMotDePasse(id), value: motDePasseTemporaire);
    await _coffre.write(key: cleMotDePasseTemporaire(id), value: '1');
    await (database.update(database.utilisateurs)..where((t) => t.id.equals(id))).write(
      UtilisateursCompanion(
        mustChangePassword: const Value(true),
        deviceId: Value(identifiantPoste),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(HeureBenin.versInstant(_maintenant())),
      ),
    );
  }

  /// `Password::defaults()` du web (14.65) : `min(8)->letters()->numbers()->symbols()`, messages de `lang/fr`.
  /// `null` : accepté.
  static String? motDePasseRefuse(String motDePasse) {
    if (motDePasse.length < 8) return 'Le champ mot de passe doit contenir au moins 8 caractères.';
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(motDePasse)) return 'Le champ mot de passe doit contenir au moins une lettre.';
    if (!RegExp(r'\p{N}', unicode: true).hasMatch(motDePasse)) return 'Le champ mot de passe doit contenir au moins un chiffre.';
    if (!RegExp(r'[\p{Z}\p{S}\p{P}]', unicode: true).hasMatch(motDePasse)) return 'Le champ mot de passe doit contenir au moins un symbole.';
    return null;
  }

  /// Ticket UT-1 — archive un compte (`is_active` faux, `pending`) ; jamais le sien (message du web) ; un compte déjà
  /// archivé n'est pas réécrit. Le serveur révoque ses jetons au rejeu.
  Future<void> archiverUtilisateur(String id, {required String? idConnecte}) async {
    if (idConnecte != null && id == idConnecte) throw const RefusSaisieUtilisateur({'': messagePropreCompte});
    await _basculerActif(id, actif: false);
  }

  /// Ticket UT-1 — réactive un compte archivé (`pending`) ; un compte déjà actif n'est pas réécrit.
  Future<void> reactiverUtilisateur(String id) => _basculerActif(id, actif: true);

  Future<void> _basculerActif(String id, {required bool actif}) async {
    final u = await (database.select(database.utilisateurs)..where((t) => t.id.equals(id))).getSingle();
    if (u.isActive == actif) return;
    await (database.update(database.utilisateurs)..where((t) => t.id.equals(id))).write(
      UtilisateursCompanion(
        isActive: Value(actif),
        deviceId: Value(identifiantPoste),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(HeureBenin.versInstant(_maintenant())),
      ),
    );
  }

  /// `ModulesActifs::toggleModule()` — active ou désactive UNE espèce, indépendamment des autres.
  ///
  /// 🔴 Avant le ticket MOD1, le poste n'avait AUCUN interrupteur (le réglage « se faisait sur le web ») : le client ne
  /// pouvait ni activer ni désactiver un module. La valeur choisie est écrite localement (`pending`, effet immédiat sur
  /// les écrans d'élevage, qui relisent cette table à l'ouverture) puis envoyée au serveur (`modules_config`, droit
  /// `manage-modules`) ; le tirage ne l'écrase pas tant qu'elle n'est pas acquittée (`_absorberModules`).
  ///
  /// ⚠️ Ne touche QUE `modules_config` : ni les données déjà saisies de l'espèce, ni la comptabilité. Aucun « au moins un
  /// module » : le web n'impose rien, le poste non plus.
  Future<void> definirModule(ModuleEspece module, {required bool actif}) => _definirCode(module.code, actif);

  /// Ticket AIDE-1 — le module « Assistant de démarrage » est-il allumé ? Lu dans la copie locale de `modules_config` (tirée
  /// du serveur), ÉTEINT par défaut : sans ligne, pas de bouton d'aide. Même règle que
  /// [DonneesParametresGeneraux.assistantActif] et `PremierDemarrageRepository.moduleActif`.
  Future<bool> assistantActif() async {
    final ligne = await (database.select(database.modulesConfig)..where((t) => t.speciesCode.equals('assistant_demarrage'))).getSingleOrNull();
    return ligne?.isEnabled ?? false;
  }

  /// `ModulesActifs::toggleAssistant()` — même écriture (`modules_config`, `pending`), même envoi au serveur.
  Future<void> definirAssistant({required bool actif}) => _definirCode('assistant_demarrage', actif);

  Future<void> _definirCode(String code, bool actif) async {
    final instant = HeureBenin.versInstant(_maintenant());
    final existante = await (database.select(
      database.modulesConfig,
    )..where((t) => t.speciesCode.equals(code))).getSingleOrNull();

    if (existante == null) {
      await database
          .into(database.modulesConfig)
          .insert(
            ModulesConfigCompanion.insert(
              id: _uuid.v4(),
              speciesCode: code,
              isEnabled: Value(actif),
              syncStatus: const Value(SyncStatus.pending),
              updatedAt: Value(instant),
            ),
          );
      return;
    }

    await (database.update(
      database.modulesConfig,
    )..where((t) => t.id.equals(existante.id))).write(
      ModulesConfigCompanion(
        isEnabled: Value(actif),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(instant),
      ),
    );
  }

  Future<DonneesParametresGeneraux> charger() async {
    final entreprise = await database
        .select(database.companySettings)
        .getSingleOrNull();
    final modules = await database.select(database.modulesConfig).get();
    final roles = await database.select(database.rolesApplicatifs).get();
    final utilisateurs = await database.select(database.utilisateurs).get();
    final comptes = await database.select(database.treasuryAccounts).get();
    final audit = await database.select(database.auditLogs).get();

    return DonneesParametresGeneraux(
      entreprise: entreprise,
      modules: modules,
      roles: roles.toList()..sort((a, b) => a.name.compareTo(b.name)),
      utilisateurs: utilisateurs.toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
      comptes: comptes.toList()..sort((a, b) => a.label.compareTo(b.label)),
      audit: audit.toList()
        ..sort(
          (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
            a.createdAt ?? DateTime(1970),
          ),
        ),
    );
  }

  /// Les espèces que la ferme exploite — lues par les écrans d'élevage.
  ///
  /// ⚠️ **UNE SEULE SOURCE POUR TOUS LES ÉCRANS.** Recopier la règle « helico
  /// est éteint » dans chaque écran garantirait qu'un jour l'un d'eux
  /// l'oublie.
  Future<Set<String>> especesActives() async =>
      (await charger()).especesActives;
}
