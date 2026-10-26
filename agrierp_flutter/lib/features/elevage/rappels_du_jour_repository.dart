import '../../core/auth/permissions_poste.dart';
import '../../core/database/app_database.dart';
import '../../core/temps/heure_benin.dart';
import 'dashboard_elevage_repository.dart' show DashboardElevageRepository;
import 'soins_repository.dart';

/// Urgence d'un rappel — l'ordre de l'énumération EST l'ordre d'affichage (retard, aujourd'hui, à venir).
enum UrgenceRappel { retard, aujourdhui, avenir }

/// Source d'un rappel — l'ordre de l'énumération est celui du tri à égalité (soin, barème, délai d'attente).
enum TypeRappel { soin, prophylaxie, remanence }

/// Une ligne de la fenêtre « Rappels du jour » (`livewire/shared/rappels-du-jour.blade.php`).
class LigneRappel {
  const LigneRappel({
    required this.urgence,
    required this.type,
    required this.bande,
    required this.espece,
    required this.libelle,
    required this.produit,
    required this.date,
    required this.jours,
    required this.echeance,
  });

  final UrgenceRappel urgence;
  final TypeRappel type;
  final String bande;
  final String espece;
  final String libelle;

  /// « — » quand le produit est inconnu (jamais « 0 » ni vide).
  final String produit;

  /// Jour prévu (minuit, heure du Bénin).
  final DateTime date;

  /// Écart en jours calendaires avec aujourd'hui : négatif = en retard.
  final int jours;
  final String echeance;

  /// « Soin planifié » / « Barème prophylactique » / « Délai d'attente » (libellés du Blade).
  String get typeLibelle => switch (type) {
    TypeRappel.soin => 'Soin planifié',
    TypeRappel.prophylaxie => 'Barème prophylactique',
    TypeRappel.remanence => "Délai d'attente",
  };

  /// « 12/10/2026 ».
  String get dateTexte =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';

  /// « AAAA-MM-JJ » (clé de tri et d'échange avec le serveur).
  String get cleJour => HeureBenin.cleJour(date);
}

/// Le résultat du calcul : les lignes triées et l'horizon N utilisé.
class RappelsDuJour {
  const RappelsDuJour({required this.lignes, required this.joursRappel});

  static const vides = RappelsDuJour(lignes: [], joursRappel: RappelsDuJourRepository.joursParDefaut);

  final List<LigneRappel> lignes;
  final int joursRappel;

  bool get vide => lignes.isEmpty;

  List<LigneRappel> de(UrgenceRappel urgence) => [
    for (final l in lignes)
      if (l.urgence == urgence) l,
  ];
}

/// Tickets POP2 — la fenêtre « Rappels du jour », CALCULÉE EN LOCAL (hors ligne) à partir des tables déjà
/// synchronisées. Contrepartie exacte de `App\Services\RappelsDuJourService` (le web est le maître, Doctrine art. 5).
///
/// ═══ RÈGLE R-RAPPELS-01 (PRD `docs/prd/popup-rappels.md` § 5) ═══
/// Horizon N = délai de rappel des soins (`company_settings.rappel_soins_jours`, 3 par défaut tant qu'il n'a jamais
/// été tiré). Aucun seuil nouveau, trois sources :
///  1. soin planifié (`veterinary_calendar_events`, `planned`) : date dépassée = En retard, du jour = Aujourd'hui,
///     jusqu'à aujourd'hui + N = À venir ;
///  2. traitement du barème prophylactique dû et non encore administré — le cycle vient de
///     [SoinsRepository.protocoleDuJour], PAS recopié ici — pour chacun des jours J à J+N : Aujourd'hui ou À venir ;
///  3. fin de délai d'attente (`veterinary_withdrawal_periods`) entre aujourd'hui et aujourd'hui + N.
/// Bandes vivantes (`status = 'actif'` ET `is_active`) ; une espèce désactivée dans Modules Actifs ne génère rien.
/// Tri : urgence, date croissante, code de bande, type, libellé.
///
/// ⚠️ Modules Actifs : tant qu'AUCUNE ligne `modules_config` n'est tirée, toutes les espèces comptent (même convention
/// que le Dashboard Élevage du poste) ; le web, lui, lit la table telle quelle.
/// ⚠️ Droit : [pourRole] ne rend rien sans `view-elevage` (même permission que la route Soins et vaccins du web).
class RappelsDuJourRepository {
  RappelsDuJourRepository({required AppDatabase database, required SoinsRepository soins})
    : _db = database,
      // ignore: prefer_initializing_formals
      _soins = soins;

  final AppDatabase _db;
  final SoinsRepository _soins;

  /// Délai par défaut de R-SOINS-01 (`AlertesElevageService::JOURS_RAPPEL_SOINS`).
  static const joursParDefaut = 3;

  /// Permission du web qui ouvre Soins et vaccins.
  static const permission = 'view-elevage';

  /// Rappels que ce rôle doit voir : rien sans le droit.
  Future<RappelsDuJour> pourRole(String? role, {DateTime? quand}) async {
    if (role == null || !PermissionsPoste.peut(role, permission)) return RappelsDuJour.vides;
    return calculer(quand: quand);
  }

  Future<RappelsDuJour> calculer({DateTime? quand}) async {
    final aujourdhui = HeureBenin.jour(quand ?? HeureBenin.maintenant());

    final reglage = await _db.select(_db.companySettings).get();
    final horizon = (reglage.isEmpty ? null : reglage.first.rappelSoinsJours) ?? joursParDefaut;

    final modules = await _db.select(_db.modulesConfig).get();
    final actifs = modules.isEmpty
        ? null
        : {
            for (final m in modules)
              if (m.isEnabled) m.speciesCode,
          };
    final libellesEspece = {
      for (final e in await _db.select(_db.livestockSpecies).get()) e.code: e.label,
    };

    final bandes = <String, LivestockLot>{
      for (final b in await _db.select(_db.livestockLots).get())
        if (b.isActive && b.status == 'actif' && b.speciesCode != null && (actifs == null || actifs.contains(b.speciesCode)))
          b.id: b,
    };

    LigneRappel ligne(TypeRappel type, LivestockLot bande, String libelle, String? produit, DateTime date) {
      final jour = HeureBenin.jour(date);
      final jours = SoinsRepository.joursCalendairesEntre(aujourdhui, jour);
      String pluriel(int n) => '$n jour${n > 1 ? 's' : ''}';
      final code = bande.speciesCode!;
      return LigneRappel(
        urgence: jours < 0 ? UrgenceRappel.retard : (jours == 0 ? UrgenceRappel.aujourdhui : UrgenceRappel.avenir),
        type: type,
        bande: bande.code,
        espece: libellesEspece[code] ?? DashboardElevageRepository.libellesEspeces[code] ?? code,
        libelle: libelle,
        produit: produit != null && produit.trim().isNotEmpty ? produit : '—',
        date: jour,
        jours: jours,
        echeance: jours < 0 ? 'En retard de ${pluriel(-jours)}' : (jours == 0 ? "Aujourd'hui" : 'Dans ${pluriel(jours)}'),
      );
    }

    final lignes = <LigneRappel>[];

    // 1. Soins planifiés (R-SOINS-01 telle quelle) : tout ce qui est en retard, puis jusqu'à aujourd'hui + N.
    for (final e in await (_db.select(_db.veterinaryCalendarEvents)..where((t) => t.status.equals('planned'))).get()) {
      final bande = bandes[e.lotId];
      if (bande == null) continue;
      final jour = HeureBenin.jour(e.scheduledDate);
      if (SoinsRepository.joursCalendairesEntre(aujourdhui, jour) > horizon) continue;
      lignes.add(ligne(TypeRappel.soin, bande, e.taskType, null, jour));
    }

    // 2. Barème prophylactique : le moteur unique du poste, jour par jour.
    final parCode = bandes.values.toList()..sort((a, b) => a.code.compareTo(b.code));
    for (final bande in parCode) {
      for (var d = 0; d <= horizon; d++) {
        final jour = HeureBenin.plusJours(aujourdhui, d);
        final protocole = await _soins.protocoleDuJour(bande: bande, codeEspece: bande.speciesCode!, quand: jour);
        // Un traitement déjà administré n'est plus un rappel : l'afficher ferait redoser la bande.
        for (final t in protocole.traitements.where((t) => !t.dejaAdministre)) {
          lignes.add(ligne(TypeRappel.prophylaxie, bande, t.standard.treatment, t.standard.productRecommended, jour));
        }
      }
    }

    // 3. Fins de délai d'attente dans la fenêtre.
    for (final r in await _db.select(_db.veterinaryWithdrawalPeriods).get()) {
      final bande = bandes[r.lotId];
      if (bande == null) continue;
      final fin = HeureBenin.jour(r.endDate);
      final jours = SoinsRepository.joursCalendairesEntre(aujourdhui, fin);
      if (jours < 0 || jours > horizon) continue;
      lignes.add(ligne(TypeRappel.remanence, bande, "Fin du délai d'attente", r.productUsed, fin));
    }

    lignes.sort((a, b) {
      final c = a.urgence.index.compareTo(b.urgence.index);
      if (c != 0) return c;
      final d = a.cleJour.compareTo(b.cleJour);
      if (d != 0) return d;
      final e = a.bande.compareTo(b.bande);
      if (e != 0) return e;
      final f = a.type.index.compareTo(b.type.index);
      if (f != 0) return f;
      return a.libelle.compareTo(b.libelle);
    });

    return RappelsDuJour(lignes: lignes, joursRappel: horizon);
  }
}
