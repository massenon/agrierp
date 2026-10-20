import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/sync_engine.dart';

/// Une ligne du détail des coûts ou des revenus.
class LigneBilan {
  const LigneBilan({required this.libelle, this.montant, this.motif});

  final String libelle;

  /// `null` : le poste ne sait pas — l'écran écrit le [motif], jamais `0`.
  final double? montant;
  final String? motif;
}

/// Bande proposée au sélecteur.
class BandeBilan {
  const BandeBilan({
    required this.id,
    required this.code,
    required this.espece,
    required this.effectifInitial,
  });

  final String id;
  final String code;

  /// Libellé de l'espèce (« Aviculture »), ou son code faute de libellé.
  final String espece;
  final int effectifInitial;

  String get libelle => '$code ($espece)';
}

/// Le bilan d'une bande.
class BilanLot {
  const BilanLot({
    required this.bande,
    required this.couts,
    required this.revenus,
    required this.revenusRecus,
    required this.ventesEnAttente,
  });

  final BandeBilan bande;
  final List<LigneBilan> couts;
  final List<LigneBilan> revenus;

  /// Le poste a-t-il déjà reçu les revenus par bande ? `false` : aucun tirage
  /// depuis la mise à jour — « pas de revenu » serait un faux.
  final bool revenusRecus;

  /// Ventes de CE poste, imputées à la bande et pas encore parties.
  final int ventesEnAttente;

  /// ⚠️ « CONNU » : la main d'œuvre manque toujours (aucune clé d'imputation) et
  /// un coût sans montant ne compte pas. Le total n'est jamais présenté comme
  /// complet.
  double get coutTotalConnu =>
      couts.fold<double>(0, (t, c) => t + (c.montant ?? 0));

  /// `null` tant que les revenus n'ont pas été reçus.
  double? get revenuTotalConnu => revenusRecus
      ? revenus.fold<double>(0, (t, r) => t + (r.montant ?? 0))
      : null;

  double? get margeNette {
    final revenu = revenuTotalConnu;
    return revenu == null ? null : _arrondi2(revenu - coutTotalConnu);
  }

  /// Coûts connus ÷ effectif INITIAL, arrondi à l'entier — `null` si l'effectif
  /// initial n'est pas positif.
  double? get coutParSujet => bande.effectifInitial > 0
      ? (coutTotalConnu / bande.effectifInitial).roundToDouble()
      : null;

  static double _arrondi2(double v) => (v * 100).roundToDouble() / 100;
}

/// Lectures de `prototype_html/bilan-technico-economique.html`.
///
/// ⚠️⚠️ **LES RÈGLES SONT CELLES DE `Livewire\Elevage\BilanTechnicoEconomique`**
/// (tickets 3.14 et 14.44), recopiées ici sans rien inventer :
///  * **Acquisition initiale** : `acquisition_cost` de la bande ; absent → « En attente » (Blade).
///  * **Provende servie** : Σ `feed_qty_kg` des fiches de la bande × PRIX MOYEN
///    INDICATIF des types de provende de l'espèce. Ce n'est PAS le prix d'achat —
///    le prix du catalogue.
///  * **Frais vétérinaires** : Σ `cost` des soins de la bande.
///  * **Main d'œuvre imputée** : TOUJOURS en attente. Ce n'est pas la paie qui
///    manque, c'est une CLÉ D'IMPUTATION : rien ne rattache un employé à une
///    bande, et chaque clé possible (temps, effectif, poids vif) donne un coût de
///    revient différent. Arbitrage du client.
///  * **Revenus** : ceux du SERVEUR (`lot_revenues`) — ventes validées, nettes des
///    avoirs traités.
///
/// ⚠️ **PAS DE VERDICT « RENTABLE / DÉFICITAIRE »** : le prototype en affiche un,
/// Laravel l'a retiré — sur des coûts partiels il pourrait annoncer « rentable »
/// un lot qui perd de l'argent. Un encart l'explique à la place.
///
/// ⚠️ **ÉCART ASSUMÉ AVEC LARAVEL : « — », JAMAIS « 0 »** quand le poste ne peut
/// pas chiffrer. Laravel écrit 0 FCFA de provende quand aucun type de provende de
/// l'espèce n'a de prix (`?? 0`) — un coût nul présenté comme un coût réel. Le
/// poste écrit « — » et dit pourquoi.
class BilanTechnicoEconomiqueRepository {
  BilanTechnicoEconomiqueRepository({required this.database});

  final AppDatabase database;

  static const _libellesEspece = {
    'cuniculture': 'Cuniculture',
    'aviculture': 'Aviculture',
    'porciculture': 'Porciculture',
    'helico': 'Héliciculture',
  };

  static const motifMainDoeuvre =
      "Aucune clé d'imputation définie — un employé n'est rattaché ni à une "
      'bande ni à un centre de coût. Arbitrage client requis.';

  /// Bandes actives, les plus récentes d'abord.
  Future<List<BandeBilan>> bandes() async {
    final lots =
        await (database.select(database.livestockLots)
              ..where((l) => l.isActive.equals(true))
              ..orderBy([
                (l) => OrderingTerm(
                  expression: l.createdDate,
                  mode: OrderingMode.desc,
                  nulls: NullsOrder.last,
                ),
                (l) => OrderingTerm(expression: l.code),
              ]))
            .get();
    final provendes = await database.select(database.feedTypes).get();

    String espece(LivestockLot l) {
      final libelle = provendes
          .where((p) => p.speciesId != null && p.speciesId == l.speciesId)
          .map((p) => p.speciesLabel)
          .whereType<String>()
          .firstOrNull;
      return libelle ??
          _libellesEspece[l.speciesCode] ??
          l.speciesCode ??
          'Espèce inconnue';
    }

    return [
      for (final l in lots)
        BandeBilan(
          id: l.id,
          code: l.code,
          espece: espece(l),
          effectifInitial: l.initialQuantity,
        ),
    ];
  }

  Future<BilanLot?> charger(String lotId) async {
    final lot = await (database.select(
      database.livestockLots,
    )..where((l) => l.id.equals(lotId))).getSingleOrNull();
    if (lot == null) return null;

    final bande = (await bandes()).firstWhere(
      (b) => b.id == lotId,
      orElse: () => BandeBilan(
        id: lot.id,
        code: lot.code,
        espece: lot.speciesCode ?? 'Espèce inconnue',
        effectifInitial: lot.initialQuantity,
      ),
    );

    // ── Coûts ──────────────────────────────────────────────────────────────
    final fiches = await (database.select(
      database.livestockDailyEntries,
    )..where((f) => f.lotId.equals(lotId))).get();
    final provendeKg = fiches.fold<double>(0, (t, f) => t + (f.feedQtyKg ?? 0));

    // ⚠️ Ticket H9b — types ACTIFS seulement, comme avant H9b (le tirage effaçait alors les archivés) : un
    // type archivé au poste reste en base pour son libellé, il ne pèse pas sur le prix moyen.
    final prix = (await database.select(database.feedTypes).get())
        .where((p) => p.isActive && p.speciesId == lot.speciesId)
        .map((p) => p.pricePerKg)
        .whereType<double>()
        .toList();
    final prixMoyenKg = prix.isEmpty
        ? null
        : prix.fold<double>(0, (t, p) => t + p) / prix.length;

    // Le web ne somme que les soins ACTIFS (`is_active = true`, soin archivé = supprimé). Ticket U3 : le poste
    // porte `is_active` (tiré, et archivé ici comme au web) — même filtre.
    final soins = await (database.select(database.veterinaryRecords)..where(
          (s) => Expression.and([s.lotId.equals(lotId), s.isActive.equals(true)]),
        ))
        .get();
    final coutVeterinaire = soins.fold<double>(0, (t, s) => t + (s.cost ?? 0));

    final couts = [
      // Ticket H6 : le Blade fait foi — sans coût d'acquisition, le web écrit « En attente »
      // (`$cout['motif'] ?? 'En attente'`, aucun motif pour cette ligne) : pas de motif ici non plus.
      LigneBilan(libelle: 'Acquisition initiale', montant: lot.acquisitionCost),
      LigneBilan(
        libelle: 'Provende servie (cumul, prix indicatif)',
        // ⚠️ Pas de prix de provende → « — », pas 0 (voir l'en-tête de classe).
        montant: prixMoyenKg == null
            ? null
            : (provendeKg * prixMoyenKg).roundToDouble(),
        motif: prixMoyenKg == null
            ? "Aucun type de provende de l'espèce n'a de prix : la provende "
                  'servie ne peut pas être valorisée.'
            : null,
      ),
      LigneBilan(libelle: 'Frais vétérinaires', montant: coutVeterinaire),
      const LigneBilan(
        libelle: "Main d'œuvre imputée",
        motif: motifMainDoeuvre,
      ),
    ];

    // ── Revenus ────────────────────────────────────────────────────────────
    final tires =
        await (database.select(database.appSettings)
              ..where((s) => s.key.equals(SyncEngine.cleRevenusTires)))
            .getSingleOrNull();
    final revenus = await (database.select(
      database.lotRevenues,
    )..where((r) => r.lotId.equals(lotId))).get();
    revenus.sort((a, b) => a.label.compareTo(b.label));

    // Ventes de CE poste, imputées à la bande, qui n'ont pas encore quitté le
    // poste : leur revenu n'est pas dans le chiffre du serveur.
    final enAttente = await database
        .customSelect(
          'SELECT COUNT(DISTINCT s.id) AS n FROM sales s '
          'JOIN sale_lines l ON l.sale_id = s.id '
          "WHERE l.lot_id = ? AND s.sync_status <> 'synced' "
          "AND s.status <> 'annulee'",
          variables: [Variable.withString(lotId)],
        )
        .getSingle();

    return BilanLot(
      bande: bande,
      couts: couts,
      revenus: [
        for (final r in revenus)
          LigneBilan(libelle: r.label, montant: r.amount),
      ],
      revenusRecus: tires != null,
      ventesEnAttente: enAttente.read<int>('n'),
    );
  }
}
