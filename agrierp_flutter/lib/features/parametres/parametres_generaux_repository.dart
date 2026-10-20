import '../../core/database/app_database.dart';
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
class ParametresGenerauxRepository {
  ParametresGenerauxRepository({required this.database});

  final AppDatabase database;

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
