import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import 'bilan_technico_economique_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/bilan-technico-economique.html` → onglet « Bilan
/// Technico-Économique » du Dashboard Élevage.
///
/// ⚠️⚠️ **COÛTS CALCULÉS AU POSTE, REVENUS REÇUS DU SERVEUR.** Les règles de
/// calcul sont celles de Laravel (voir [BilanTechnicoEconomiqueRepository]). Le
/// revenu, lui, ne peut pas être recalculé ici : les ventes serveur ne
/// descendent qu'en en-tête, sans lignes. Il porte donc la date du dernier
/// tirage, et une vente faite sur ce poste depuis n'y figure qu'après la
/// synchronisation suivante — la légende le dit.
///
/// ⚠️ **PAS DE VERDICT « RENTABLE / DÉFICITAIRE »**, comme Laravel : sur des coûts
/// partiels il pourrait déclarer rentable un lot qui perd de l'argent.
///
/// ⚠️ **ÉCARTS AVEC LE PROTOTYPE, TOUS DE LARAVEL** : « Coût Total CONNU du Lot »
/// (la main d'œuvre est hors calcul — un « Coût Total » sans réserve serait un
/// chiffre faux présenté comme complet), « Total connu » au lieu de « TOTAL
/// COÛTS », et l'encart d'information à la place du verdict.
class BilanTechnicoEconomiqueVue extends StatefulWidget {
  const BilanTechnicoEconomiqueVue({super.key, required this.depot});

  final BilanTechnicoEconomiqueRepository depot;

  @override
  State<BilanTechnicoEconomiqueVue> createState() =>
      _BilanTechnicoEconomiqueVueState();
}

class _BilanTechnicoEconomiqueVueState
    extends State<BilanTechnicoEconomiqueVue> {
  List<BandeBilan>? _bandes;
  String _lotId = '';
  BilanLot? _bilan;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final bandes = await widget.depot.bandes();
    final id = bandes.any((b) => b.id == _lotId)
        ? _lotId
        : (bandes.firstOrNull?.id ?? '');
    final bilan = id.isEmpty ? null : await widget.depot.charger(id);
    if (!mounted) return;
    setState(() {
      _bandes = bandes;
      _lotId = id;
      _bilan = bilan;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bandes = _bandes;
    if (bandes == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final large = AgriBreakpoints.large(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(bandes, large),
        const SizedBox(height: AgriSpacing.md),
        if (_bilan == null)
          _vide()
        else ...[
          _cartes(_bilan!, large),
          const SizedBox(height: AgriSpacing.lg),
          _details(_bilan!, large),
          const SizedBox(height: AgriSpacing.lg),
          _encart(
            const Key('bilan-marge-info'),
            "Marge Nette calculée sur revenus et coûts connus. La main d'œuvre "
            "reste hors du calcul tant qu'aucune clé d'imputation aux bandes "
            "n'est arbitrée.",
            gras: true,
          ),
          if (_bilan!.ventesEnAttente > 0) ...[
            const SizedBox(height: AgriSpacing.md),
            _encart(
              const Key('bilan-ventes-en-attente'),
              '${_bilan!.ventesEnAttente} vente(s) de ce poste imputée(s) à '
              "cette bande attendent d'être envoyées : leur revenu n'est pas "
              'encore compté.',
              gras: true,
            ),
          ],
          const SizedBox(height: AgriSpacing.md),
          _encart(
            const Key('bilan-methode'),
            "Ce bilan agrège automatiquement : le coût d'acquisition initial "
            'de la bande, les provendes servies (valorisées au prix indicatif '
            'du catalogue Types de Provende), les frais vétérinaires imputés '
            'au lot, et les ventes enregistrées via le POS — sujets vifs, œufs '
            'et produits transformés compris, imputés à la bande désignée à '
            'la caisse, jamais répartis par une heuristique. Les revenus sont '
            'ceux du dernier tirage du serveur : une vente faite sur ce poste '
            "depuis n'y figure qu'après la prochaine synchronisation.",
          ),
        ],
      ],
    );
  }

  // ── En-tête et sélecteur de bande ─────────────────────────────────────────

  Widget _entete(List<BandeBilan> bandes, bool large) {
    final titre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              SymbolesAgri.account_balance_wallet,
              size: 24,
              color: AgriColors.brandEmerald,
            ),
            SizedBox(width: AgriSpacing.xs),
            Flexible(
              child: Text(
                'Rentabilité de Lot',
                style: TextStyle(
                  fontSize: AgriTypography.lg,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Coûts, revenus et rentabilité réelle par bande — alimenté '
          'automatiquement par les achats, ventes et charges imputés à '
          'chaque lot.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    );

    final selecteur = bandes.isEmpty
        ? const SizedBox.shrink()
        : Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('bilan-lot'),
                value: _lotId,
                // ⚠️ Le menu déroulant ne reprend pas le style du thème : sans
                // cette base il retombe sur la police par défaut du moteur.
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: AgriTypography.sm,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.onSurface,
                ),
                items: [
                  for (final b in bandes)
                    DropdownMenuItem(value: b.id, child: Text(b.libelle)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _lotId = v);
                  _charger();
                },
              ),
            ),
          );

    return large
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titre),
              selecteur,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titre,
              const SizedBox(height: AgriSpacing.sm),
              selecteur,
            ],
          );
  }

  Widget _vide() => Container(
    key: const Key('bilan-vide'),
    padding: const EdgeInsets.all(AgriSpacing.lg),
    decoration: _carte(),
    child: const Column(
      children: [
        Icon(SymbolesAgri.inbox, size: 44, color: AgriColors.outlineVariant),
        SizedBox(height: AgriSpacing.sm),
        Text(
          'Aucune bande pour le moment.',
          style: TextStyle(
            fontSize: AgriTypography.sm,
            fontWeight: FontWeight.w600,
            color: AgriColors.onSurface,
          ),
        ),
        SizedBox(height: AgriSpacing.xs),
        // ⚠️ Laravel renvoie vers « Bandes & Sujets » ; le poste n'a pas cet
        // écran — une bande se crée sur le web et descend à la synchronisation.
        Text(
          "Les bandes se créent sur l'application web et descendent ici à la "
          'synchronisation.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    ),
  );

  BoxDecoration _carte() => BoxDecoration(
    color: AgriColors.surfaceCard,
    border: Border.all(color: AgriColors.outlineVariant),
    borderRadius: BorderRadius.circular(AgriRadius.lg),
  );

  // ── Les quatre cartes ─────────────────────────────────────────────────────

  Widget _cartes(BilanLot b, bool large) {
    final revenu = b.revenuTotalConnu;
    final marge = b.margeNette;
    final parSujet = b.coutParSujet;

    return GrilleKpi(colonnes: large ? 4 : 2, children: [
        CarteKpi(
          libelle: 'Coût Total Connu du Lot',
          valeur: _montant(b.coutTotalConnu),
          unite: 'FCFA',
          couleurLisere: AgriColors.infoBlue,
          legende: "Hors main d'œuvre (clé d'imputation à arbitrer)",
        ),
        CarteKpi(
          libelle: 'Revenu Total du Lot',
          valeur: revenu == null ? '—' : _montant(revenu),
          unite: revenu == null ? null : 'FCFA',
          couleurLisere: AgriColors.brandEmerald,
          legende: revenu == null
              ? 'Revenus pas encore reçus du serveur — synchronisez'
              : 'Ventes validées, nettes des avoirs traités',
        ),
        CarteKpi(
          libelle: 'Marge Nette',
          valeur: marge == null ? '—' : _montant(marge),
          unite: marge == null ? null : 'FCFA',
          couleurLisere: AgriColors.accentYellow,
          couleurValeur: marge == null
              ? AgriColors.onSurface
              : (marge >= 0 ? AgriColors.brandEmerald : AgriColors.errorDeep),
          legende: marge == null
              ? 'Sans revenus reçus, la marge ne se calcule pas'
              : 'Sur revenus et coûts connus',
        ),
        CarteKpi(
          libelle: 'Coût de Revient / Sujet',
          valeur: parSujet == null ? '—' : _montant(parSujet),
          unite: parSujet == null ? null : 'FCFA',
          couleurLisere: AgriColors.errorRed,
          // Ticket H6 : le Blade fait foi — même légende, que la valeur soit connue ou « — ».
          legende: 'Sur coûts connus ÷ effectif initial',
        ),
      ],
    );
  }

  // ── Détail des coûts et des revenus ───────────────────────────────────────

  Widget _details(BilanLot b, bool large) {
    final couts = _carteDetail(
      titre: 'Détail des Coûts',
      icone: SymbolesAgri.trending_down,
      couleurIcone: AgriColors.errorDeep,
      lignes: b.couts,
      vide: '',
      total: _montant(b.coutTotalConnu),
      couleurTotal: AgriColors.brandForest,
      cle: 'bilan-couts',
    );

    final revenus = _carteDetail(
      titre: 'Détail des Revenus',
      icone: SymbolesAgri.trending_up,
      couleurIcone: AgriColors.brandEmerald,
      lignes: b.revenus,
      vide: b.revenusRecus
          ? 'Aucune vente encore enregistrée sur cette bande.'
          : 'Revenus pas encore reçus du serveur — synchronisez.',
      total: b.revenuTotalConnu == null ? '—' : _montant(b.revenuTotalConnu!),
      couleurTotal: AgriColors.brandEmerald,
      cle: 'bilan-revenus',
    );

    return large
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: couts),
              const SizedBox(width: AgriSpacing.md),
              Expanded(child: revenus),
            ],
          )
        : Column(
            children: [
              couts,
              const SizedBox(height: AgriSpacing.md),
              revenus,
            ],
          );
  }

  Widget _carteDetail({
    required String titre,
    required IconData icone,
    required Color couleurIcone,
    required List<LigneBilan> lignes,
    required String vide,
    required String total,
    required Color couleurTotal,
    required String cle,
  }) => Container(
    key: Key(cle),
    padding: const EdgeInsets.all(AgriSpacing.lg),
    decoration: _carte(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icone, size: 18, color: couleurIcone),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              titre,
              style: const TextStyle(
                fontSize: AgriTypography.sm,
                fontWeight: AgriTypography.gras,
                color: AgriColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        if (lignes.isEmpty)
          Text(
            vide,
            key: Key('$cle-vide'),
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontStyle: FontStyle.italic,
              color: AgriColors.outline,
            ),
          ),
        for (final (i, l) in lignes.indexed)
          Container(
            key: Key('$cle-ligne-$i'),
            margin: const EdgeInsets.only(bottom: AgriSpacing.sm),
            padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AgriColors.outlineVariant),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    l.libelle,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.outline,
                    ),
                  ),
                ),
                const SizedBox(width: AgriSpacing.sm),
                Expanded(
                  flex: 6,
                  child: l.montant != null
                      ? Text(
                          '${_montant(l.montant!)} FCFA',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: AgriTypography.xs,
                            fontWeight: AgriTypography.gras,
                            color: AgriColors.brandForest,
                          ),
                        )
                      : Text(
                          l.motif ?? 'En attente',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: AgriColors.outline,
                          ),
                        ),
                ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total connu',
              style: TextStyle(
                fontSize: AgriTypography.sm,
                fontWeight: AgriTypography.gras,
                color: couleurTotal,
              ),
            ),
            Text(
              total == '—' ? '—' : '$total FCFA',
              key: Key('$cle-total'),
              style: TextStyle(
                fontSize: AgriTypography.sm,
                fontWeight: AgriTypography.gras,
                color: couleurTotal,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _encart(Key cle, String texte, {bool gras = false}) => Container(
    key: cle,
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.infoBlue.withValues(alpha: 0.10),
      border: Border.all(color: AgriColors.infoBlue.withValues(alpha: 0.20)),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(SymbolesAgri.info, size: 16, color: AgriColors.brandForest),
        const SizedBox(width: AgriSpacing.xs),
        Expanded(
          child: Text(
            texte,
            style: TextStyle(
              fontSize: gras ? AgriTypography.sm : AgriTypography.xs,
              fontWeight: gras ? FontWeight.w600 : null,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
    ),
  );

  /// « 135 000 » — espaces de milliers, comme `number_format(…, 0, ',', ' ')`.
  static String _montant(double valeur) {
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }
}
