import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';

/// Les indicateurs du hub « Gestion Élevage », calculés comme `App\Livewire\Elevage\GestionElevage`.
class IndicateursGestionElevage {
  const IndicateursGestionElevage({
    required this.effectifTotal,
    required this.bandesActives,
    required this.tauxMortaliteMois,
    required this.helicoActif,
  });

  /// `getEffectifTotalProperty()` : Σ `current_quantity` des bandes VIVANTES.
  final int effectifTotal;

  /// `getBandesActivesProperty()` : nombre de bandes VIVANTES.
  final int bandesActives;

  /// `getTauxMortaliteMoisProperty()` : `null` (« — ») sans bande vivante, sans fiche du mois ou sans effectif de
  /// départ — jamais 0.
  final double? tauxMortaliteMois;

  /// `ModuleConfig::isEnabled('helico')` : la carte « Fiches Escargots » est grisée quand il est faux.
  final bool helicoActif;
}

/// Ticket H4 — calculs du hub « Gestion Élevage », hors du widget.
///
/// Maître : `app/Livewire/Elevage/GestionElevage.php`. Chaque calcul en reprend la requête, au filtre près.
class GestionElevageRepository {
  GestionElevageRepository({required AppDatabase database, DateTime Function()? horloge})
    : _db = database,
      _horloge = horloge ?? DateTime.now;

  final AppDatabase _db;

  /// `now()` du web : le mois du taux de mortalité est celui de ce jour.
  final DateTime Function() _horloge;

  /// Statut d'une bande en cours (`livestock_lots.status`, enum `actif` | `cloture`).
  static const statutActif = 'actif';

  /// ⚠️⚠️ `LivestockLot::vivantes()` AU FILTRE PRÈS : `where('status', 'actif')->where('is_active', true)`.
  ///
  /// Les DEUX conditions, toujours. Archiver une bande pose `is_active = false` sans toucher au statut, et clôturer
  /// une bande pose `status = cloture` sans toucher à `is_active` : un seul des deux filtres compte encore l'une ou
  /// l'autre dans « Effectif Total Vivant » (correctif « ARCHIVAGE » du web).
  Future<List<LivestockLot>> _bandesVivantes() =>
      (_db.select(_db.livestockLots)
            ..where((t) => t.status.equals(statutActif) & t.isActive.equals(true)))
          .get();

  Future<IndicateursGestionElevage> charger() async {
    final bandes = await _bandesVivantes();
    return IndicateursGestionElevage(
      effectifTotal: bandes.fold<int>(0, (s, b) => s + b.currentQuantity),
      bandesActives: bandes.length,
      tauxMortaliteMois: await _tauxMortaliteMois(bandes),
      helicoActif: await _helicoActif(),
    );
  }

  /// `getTauxMortaliteMoisProperty()` : Σ morts / Σ `previousEffectif()` des fiches du mois des bandes vivantes,
  /// × 100, arrondi à 2 décimales (`round(…, 2)`).
  Future<double?> _tauxMortaliteMois(List<LivestockLot> bandes) async {
    if (bandes.isEmpty) return null;

    final maintenant = _horloge();
    // `whereBetween('entry_date', [startOfMonth, endOfMonth])` : du 1er au dernier jour du mois, bornes comprises.
    final debut = DateTime(maintenant.year, maintenant.month);
    final finExclue = DateTime(maintenant.year, maintenant.month + 1);
    final ids = [for (final b in bandes) b.id];

    // Toutes les fiches des bandes vivantes jusqu'à la fin du mois : celles d'avant le mois servent à
    // `previousEffectif()` de la première fiche du mois.
    final fiches =
        await (_db.select(_db.livestockDailyEntries)
              ..where((t) => t.lotId.isIn(ids) & t.entryDate.isSmallerThanValue(finExclue)))
            .get();
    final duMois = [for (final f in fiches) if (!f.entryDate.isBefore(debut)) f];
    if (duMois.isEmpty) return null;

    final initiales = {for (final b in bandes) b.id: b.initialQuantity};
    final totalMorts = duMois.fold<int>(0, (s, f) => s + f.mort);
    final totalEffectifDepart = duMois.fold<int>(
      0,
      (s, f) => s + effectifPrecedent(f, fiches, initiales[f.lotId] ?? 0),
    );
    if (totalEffectifDepart <= 0) return null;

    return arrondi2(totalMorts / totalEffectifDepart * 100);
  }

  /// `LivestockDailyEntry::previousEffectif()` : `effectif_final` de la fiche la plus récente de la MÊME bande dont
  /// la date est STRICTEMENT antérieure (`whereDate('entry_date', '<', …)`, fiche courante exclue), sinon
  /// `initial_quantity` de la bande.
  ///
  /// ⚠️ Comparaison sur le JOUR, jamais sur l'horodatage : le défaut du ticket 14.4 faisait de la fiche elle-même sa
  /// propre « veille ».
  static int effectifPrecedent(LivestockDailyEntry fiche, List<LivestockDailyEntry> fichesDeLaBase, int effectifInitial) {
    final jour = _jour(fiche.entryDate);
    LivestockDailyEntry? veille;
    for (final f in fichesDeLaBase) {
      if (f.lotId != fiche.lotId || f.id == fiche.id || !_jour(f.entryDate).isBefore(jour)) continue;
      if (veille == null || f.entryDate.isAfter(veille.entryDate)) veille = f;
    }
    return veille?.effectifFinal ?? effectifInitial;
  }

  /// `ModuleConfig::isEnabled('helico')` : `(bool) value('is_enabled')` — une ligne ABSENTE vaut `false`, comme au
  /// web (la carte est alors grisée, jamais masquée).
  Future<bool> _helicoActif() async {
    final ligne = await (_db.select(_db.modulesConfig)
          ..where((t) => t.speciesCode.equals('helico'))
          ..limit(1))
        .getSingleOrNull();
    return ligne?.isEnabled ?? false;
  }

  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

  /// `round($x, 2)` de PHP : demi-unité arrondie en s'éloignant de zéro.
  static double arrondi2(double x) => (x * 100).round() / 100;

  /// `number_format($n, 0, ',', ' ')` — « 1 234 ».
  static String formaterEntier(int n) {
    final chiffres = n.abs().toString();
    final groupes = <String>[];
    for (var i = chiffres.length; i > 0; i -= 3) {
      groupes.insert(0, chiffres.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${n < 0 ? '-' : ''}${groupes.join(' ')}';
  }

  /// Valeur du KPI « Taux Mortalité (mois) » : `number_format($taux, 2, ',', ' ').' %'`, ou « — » sans donnée.
  static String formaterTaux(double? taux) {
    if (taux == null) return '—';
    final centiemes = (taux * 100).round();
    final entier = centiemes.abs() ~/ 100;
    final decimales = (centiemes.abs() % 100).toString().padLeft(2, '0');
    return '${centiemes < 0 ? '-' : ''}${formaterEntier(entier)},$decimales %';
  }
}
