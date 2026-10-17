import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import 'tableau_de_bord_repository.dart';

/// `prototype_html/dashboard.html` → Tableau de Bord.
///
/// ⚠️⚠️ **LA MAQUETTE EST LA RÉFÉRENCE DE MISE EN PAGE.** Sections dans SON
/// ordre, libellés au mot près :
///   1. en-tête « Bienvenue… » + deux actions (Enregistrer une Vente ·
///      Élevage) ;
///   2. filtre de dates (du · au) + sélecteur d'état + bouton PDF ;
///   3. huit cartes KPI ;
///   4. « CA vs Dépenses — 6 derniers mois » (8/12) + « Alertes Critiques »
///      (4/12) ;
///   5. trois cartes espèces — Lapins · Volailles · Porcs ;
///   6. « Statistiques de Ventes » + « Transactions Récentes » (cinq
///      onglets : Vente · Achat · Devis · Dépenses · Factures) ;
///   7. « Activités du Jour » + « Top 5 Produits du Mois ».
///
/// ⚠️⚠️ **CINQ BLOCS NE PEUVENT PAS PARLER DE LA FERME ENTIÈRE.** Le tirage ne
/// descend ni `sales` ni `expenses` : le CA, les dépenses, les deux courbes,
/// les transactions et le top produits ne portent QUE ce que ce poste a saisi.
/// La mention est portée à l'écran, sous chaque bloc concerné — un gérant qui
/// compare deux postes doit le lire, pas le deviner.
class TableauDeBordScreen extends StatefulWidget {
  const TableauDeBordScreen({
    super.key,
    required this.depot,
    this.onEnregistrerVente,
    this.onElevage,
    this.nomUtilisateur = 'Manager Olouwachegoun',
  });

  final TableauDeBordRepository depot;
  final VoidCallback? onEnregistrerVente;
  final VoidCallback? onElevage;
  final String nomUtilisateur;

  @override
  State<TableauDeBordScreen> createState() => _TableauDeBordScreenState();
}

class _TableauDeBordScreenState extends State<TableauDeBordScreen> {
  late DateTime _du;
  late DateTime _au;

  DonneesTableauDeBord? _donnees;
  bool _chargement = true;

  /// Onglet actif de « Transactions Récentes ».
  String _ongletTx = 'Vente';

  @override
  void initState() {
    super.initState();
    final maintenant = DateTime.now();
    _du = DateTime(maintenant.year, maintenant.month, 1);
    _au = maintenant;
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    final donnees = await widget.depot.charger(du: _du, au: _au);
    if (!mounted) return;
    setState(() {
      _donnees = donnees;
      _chargement = false;
    });
  }

  // ── Rendu ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: _chargement || _donnees == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              // ⚠️ `Builder` ET NON `LayoutBuilder` : la mise en page se
              // décide sur la largeur de l'ÉCRAN (MediaQuery), jamais sur
              // celle du contenu. Retirer les contraintes de la portée
              // interdit la rechute.
              builder: (context) {
                // ⚠️ MÊMES POINTS DE RUPTURE QUE LA MAQUETTE : `md:` à 768,
                // `lg:` à 1024. Les inventer ferait diverger la mise en page
                // du navigateur et du poste sur les mêmes largeurs.
                final large = AgriBreakpoints.large(context);
                final moyen = AgriBreakpoints.moyen(context);

                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    large ? AgriSpacing.lg : AgriSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _entete(large),
                      const SizedBox(height: AgriSpacing.md),
                      _filtreEtExport(large),
                      const SizedBox(height: AgriSpacing.lg),
                      _kpis(moyen),
                      const SizedBox(height: AgriSpacing.lg),
                      _pilotage(large),
                      const SizedBox(height: AgriSpacing.lg),
                      _cartesEspeces(moyen),
                      const SizedBox(height: AgriSpacing.lg),
                      _statistiquesEtTransactions(large),
                      const SizedBox(height: AgriSpacing.lg),
                      _activitesEtTop(large),
                    ],
                  ),
                );
              },
            ),
    );
  }

  // ── 1. En-tête ────────────────────────────────────────────────────────────

  Widget _entete(bool large) {
    final titre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bienvenue, ${widget.nomUtilisateur} 👋',
          style: TextStyle(
            fontSize: large ? 24 : 20,
            fontWeight: FontWeight.bold,
            color: AgriColors.onSurface,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        Text(
          'Rapport généré le ${_dateCourte(DateTime.now())} '
          'à ${_heure(DateTime.now())} · Exercice ${DateTime.now().year} actif',
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    );

    final actions = Wrap(
      spacing: AgriSpacing.xs,
      runSpacing: AgriSpacing.xs,
      children: [
        _boutonPlein(
          key: const Key('action-vente'),
          icone: Icons.point_of_sale,
          libelle: 'Enregistrer une Vente',
          onPressed: widget.onEnregistrerVente,
        ),
        _boutonClair(
          key: const Key('action-elevage'),
          icone: Icons.pets,
          libelle: 'Élevage',
          onPressed: widget.onElevage,
        ),
      ],
    );

    final contenu = large
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titre),
              actions,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titre,
              const SizedBox(height: AgriSpacing.sm),
              actions,
            ],
          );

    return Container(
      padding: const EdgeInsets.only(bottom: AgriSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: contenu,
    );
  }

  // ── 2. Filtre de dates + export ───────────────────────────────────────────

  /// ⚠️ **LE SÉLECTEUR D'ÉTAT ET LE BOUTON PDF SONT INERTES**, et visiblement.
  /// Les neuf états de la maquette (Recettes, Dépenses, Trésorerie, Bilan
  /// Simplifié…) se lisent au grand livre, que le poste ne tient pas. Même
  /// traitement que le champ de recherche de la barre supérieure : présents,
  /// désactivés — plutôt qu'absents de la maquette, ou faussement actifs.
  Widget _filtreEtExport(bool large) {
    final dates = Row(
      children: [
        const Icon(Icons.calendar_month, size: 18, color: AgriColors.outline),
        const SizedBox(width: AgriSpacing.xs),
        Expanded(child: _champDate(const Key('date-du'), _du, (d) => _du = d)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AgriSpacing.xs),
          child: Text(
            'au',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
        ),
        Expanded(child: _champDate(const Key('date-au'), _au, (d) => _au = d)),
      ],
    );

    final exports = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: large ? 224 : 180,
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.sm,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: AgriColors.surfaceZebra,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: const Text(
            '-- Choisir un état / rapport --',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AgriSpacing.xs),
        Opacity(
          opacity: 0.5,
          child: _boutonPlein(
            key: const Key('export-pdf'),
            icone: Icons.picture_as_pdf,
            libelle: 'PDF',
            onPressed: null,
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: large
          ? Row(
              children: [
                Expanded(child: dates),
                const SizedBox(width: AgriSpacing.sm),
                exports,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                dates,
                const SizedBox(height: AgriSpacing.sm),
                exports,
              ],
            ),
    );
  }

  Widget _champDate(
    Key cle,
    DateTime valeur,
    void Function(DateTime) affecter,
  ) {
    return InkWell(
      key: cle,
      onTap: () async {
        final choisi = await showDatePicker(
          context: context,
          initialDate: valeur,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (choisi == null) return;
        setState(() => affecter(choisi));
        await _charger();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Text(
          _dateCourte(valeur),
          style: const TextStyle(fontSize: AgriTypography.xs),
        ),
      ),
    );
  }

  // ── 3. Les huit KPI ───────────────────────────────────────────────────────

  Widget _kpis(bool moyen) {
    final d = _donnees!;
    final caisse = d.tresorerieParType['caisse'] ?? 0;
    final banque = d.tresorerieParType['banque'] ?? 0;

    final cartes = <Widget>[
      _carteKpi(
        libelle: "Chiffre d'Affaires",
        mesure: d.chiffreAffaires,
        unite: 'FCFA',
        // ⚠️ LA MAQUETTE COMPARE AU MOIS PRÉCÉDENT. Le poste ne peut pas :
        // il ne détient que ses propres ventes, et seulement depuis sa
        // dernière remise à zéro. Dire d'où vient le chiffre vaut mieux
        // qu'une variation calculée sur une base incomplète.
        detail: 'Ce poste uniquement · ${d.nombreDeVentes} vente(s)',
        icone: Icons.trending_up,
        barre: AgriColors.brandEmerald,
      ),
      _carteKpi(
        libelle: 'Trésorerie',
        mesure: d.tresorerie,
        unite: 'FCFA',
        detail: 'Caisse : ${_montant(caisse)} · Banque : ${_montant(banque)}',
        icone: Icons.account_balance_wallet,
        barre: AgriColors.infoBlue,
        couleurIcone: AgriColors.infoBlue,
      ),
      _carteKpi(
        libelle: 'Dépenses',
        mesure: d.depenses,
        unite: 'FCFA',
        detail: 'Ce poste uniquement',
        icone: Icons.shopping_cart,
        barre: AgriColors.accentYellow,
        couleurIcone: AgriColors.brandForest,
      ),
      _carteKpi(
        libelle: 'Résultat Net',
        mesure: d.resultatNet,
        unite: 'FCFA',
        detail: '',
        icone: Icons.savings,
        barre: AgriColors.brandEmerald,
      ),
      _carteKpi(
        libelle: 'Créances Clients',
        mesure: d.creances,
        unite: 'FCFA',
        detail: '',
        icone: Icons.request_quote,
        barre: AgriColors.errorRed,
        couleurIcone: AgriColors.errorRed,
      ),
      _carteKpi(
        libelle: 'Dettes Fournisseurs',
        mesure: d.dettes,
        unite: 'FCFA',
        detail: '',
        icone: Icons.local_shipping,
        barre: AgriColors.accentYellow,
        couleurIcone: AgriColors.brandForest,
      ),
      _carteKpi(
        libelle: 'Stock Critique',
        mesure: Mesure.chiffre(d.produitsSousSeuil.length.toDouble()),
        unite: 'produits',
        detail: d.produitsSousSeuil.isEmpty
            ? 'Aucun produit sous son seuil'
            : d.produitsSousSeuil.take(3).map((p) => p.name).join(', '),
        icone: Icons.warning,
        barre: AgriColors.errorRed,
        couleurIcone: AgriColors.errorRed,
      ),
      _carteKpi(
        libelle: 'Effectif Animaux',
        mesure: d.effectifAnimaux,
        unite: 'têtes',
        // ⚠️ Pas de comparaison au mois précédent : l'effectif d'un mois
        // révolu ne se reconstitue pas depuis le seul solde courant des
        // bandes — c'est la même erreur que le « stock reporté » du grand
        // livre d'œufs (ticket 14.13).
        detail: 'Au dernier tirage',
        icone: Icons.pets,
        barre: AgriColors.brandEmerald,
      ),
    ];

    return GridView.count(
      crossAxisCount: moyen ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AgriSpacing.md,
      crossAxisSpacing: AgriSpacing.md,
      childAspectRatio: moyen ? 1.9 : 1.5,
      children: cartes,
    );
  }

  Widget _carteKpi({
    required String libelle,
    required Mesure mesure,
    required String unite,
    required String detail,
    required IconData icone,
    required Color barre,
    Color couleurIcone = AgriColors.brandEmerald,
  }) => CarteKpi(
    libelle: libelle,
    // ⚠️ TIRET, JAMAIS ZÉRO : « — » dit « le poste ne sait pas », « 0 »
    // dirait « la ferme n'en a pas ».
    valeur: mesure.disponible ? _montant(mesure.valeur!) : '—',
    unite: mesure.disponible ? unite : null,
    legende: mesure.disponible ? detail : mesure.motifAbsence,
    icone: icone,
    couleurLisere: barre,
    couleurIcone: couleurIcone,
  );

  // ── 4. Centre de pilotage : courbe 8/12 + alertes 4/12 ────────────────────

  Widget _pilotage(bool large) {
    final courbe = _bloc(
      titre: 'CA vs Dépenses — 6 derniers mois',
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 208,
            child: CustomPaint(
              painter: _CourbePainter(_donnees!.serie),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: AgriSpacing.sm),
          Row(
            children: [
              _legende(AgriColors.brandEmerald, "Chiffre d'affaires"),
              const SizedBox(width: AgriSpacing.lg),
              _legende(AgriColors.errorRed, 'Dépenses'),
            ],
          ),
          const SizedBox(height: AgriSpacing.xs),
          const Text(
            'Ventes et dépenses saisies sur ce poste',
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: AgriColors.outline,
            ),
          ),
        ],
      ),
    );

    final alertes = _bloc(
      titre: 'Alertes Critiques',
      enfant: _donnees!.alertes.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: AgriSpacing.sm),
              child: Text(
                '— Aucune alerte sur les données du poste —',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final a in _donnees!.alertes) ...[
                  Container(
                    padding: const EdgeInsets.all(AgriSpacing.sm),
                    decoration: BoxDecoration(
                      color: a.grave
                          ? AgriColors.errorBg
                          : AgriColors.accentYellow.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(AgriRadius.lg),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          a.grave ? Icons.inventory_2 : Icons.request_quote,
                          size: 18,
                          color: a.grave
                              ? AgriColors.errorDeep
                              : AgriColors.brandForest,
                        ),
                        const SizedBox(width: AgriSpacing.sm),
                        Expanded(
                          child: Text(
                            a.message,
                            style: TextStyle(
                              fontSize: AgriTypography.xs,
                              color: a.grave
                                  ? AgriColors.errorDeep
                                  : AgriColors.brandForest,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.sm),
                ],
              ],
            ),
    );

    if (!large) {
      return Column(
        children: [
          courbe,
          const SizedBox(height: AgriSpacing.md),
          alertes,
        ],
      );
    }

    // ⚠️ RAPPORT 8/12 – 4/12 DE LA MAQUETTE, pas une demi-largeur chacun.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 8, child: courbe),
        const SizedBox(width: AgriSpacing.md),
        Expanded(flex: 4, child: alertes),
      ],
    );
  }

  Widget _legende(Color couleur, String libelle) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
      ),
      const SizedBox(width: AgriSpacing.xs),
      Text(
        libelle,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          color: AgriColors.outline,
        ),
      ),
    ],
  );

  // ── 5. Élevage en temps réel ──────────────────────────────────────────────

  Widget _cartesEspeces(bool moyen) {
    final cartes = _donnees!.especes.map(_carteEspece).toList();

    if (!moyen) {
      return Column(
        children: [
          for (final c in cartes) ...[
            c,
            const SizedBox(height: AgriSpacing.md),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cartes.length; i++) ...[
          if (i > 0) const SizedBox(width: AgriSpacing.md),
          Expanded(child: cartes[i]),
        ],
      ],
    );
  }

  static const _iconesEspeces = {
    'Lapins': Icons.cruelty_free,
    'Volailles': Icons.egg,
    'Porcs': Icons.pets,
  };

  Widget _carteEspece(CarteEspece carte) {
    // ⚠️ SEUIL DE 5 %, ET IL VIENT DU PROTOTYPE : `gestion-elevage.html` écrit
    // « Seuil normal < 5% » et bascule en rouge à partir de 5. La maquette du
    // tableau de bord, elle, colore 3,2 % en rouge — chiffre de démonstration
    // codé en dur, incohérent avec sa propre page sœur. C'est la RÈGLE qui est
    // reprise, pas la couleur d'un exemple.
    final critique =
        (carte.mortalite ?? 0) >= TableauDeBordRepository.seuilMortalite;

    final mesures = [
      ...carte.mesures,
      (
        'Mortalité',
        carte.mortalite == null
            ? '—'
            : '${carte.mortalite!.toStringAsFixed(1)}%',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                _iconesEspeces[carte.titre] ?? Icons.pets,
                size: 20,
                color: AgriColors.brandEmerald,
              ),
              const SizedBox(width: AgriSpacing.xs),
              Text(
                carte.titre,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AgriSpacing.sm,
            crossAxisSpacing: AgriSpacing.sm,
            childAspectRatio: 2.6,
            children: [
              for (var i = 0; i < mesures.length; i++)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      mesures[i].$1,
                      style: const TextStyle(
                        fontSize: AgriTypography.xs,
                        color: AgriColors.outline,
                      ),
                    ),
                    Text(
                      mesures[i].$2,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: i == mesures.length - 1
                            ? (critique
                                  ? AgriColors.errorRed
                                  : AgriColors.brandEmerald)
                            : AgriColors.onSurface,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 6. Statistiques de Ventes + Transactions Récentes ─────────────────────

  Widget _statistiquesEtTransactions(bool large) {
    final gauche = _statistiquesDeVentes();
    final droite = _transactionsRecentes();

    if (!large) {
      return Column(
        children: [
          gauche,
          const SizedBox(height: AgriSpacing.md),
          droite,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: gauche),
        const SizedBox(width: AgriSpacing.md),
        Expanded(child: droite),
      ],
    );
  }

  Widget _statistiquesDeVentes() {
    final d = _donnees!;

    return _bloc(
      titre: 'Statistiques de Ventes',
      icone: Icons.bar_chart,
      apresTitre: Text(
        '${DateTime.now().year}',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: AgriColors.outline,
        ),
      ),
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _tuile(
                  '${_montant(d.chiffreAffaires.valeur ?? 0)} F',
                  'Revenu',
                  AgriColors.brandEmerald,
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _tuile(
                  '${_montant(d.depenses.valeur ?? 0)} F',
                  'Dépenses',
                  AgriColors.errorRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          SizedBox(
            height: 128,
            child: CustomPaint(
              painter: _HistogrammePainter(d.serieAnnuelle),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final m in ['Jan', 'Mar', 'Mai', 'Jul', 'Sep', 'Nov'])
                Text(
                  m,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AgriColors.outline,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tuile(String valeur, String libelle, Color couleur) => Container(
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.surfaceZebra,
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            valeur,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: couleur,
            ),
          ),
        ),
        Text(
          libelle,
          style: const TextStyle(fontSize: 10, color: AgriColors.outline),
        ),
      ],
    ),
  );

  /// ⚠️ **LES CINQ ONGLETS DE LA MAQUETTE SONT LÀ**, dans son ordre. Trois
  /// n'ont aucun module embarqué au poste (Achat, Devis, Factures) : ils le
  /// disent au lieu de disparaître, sans quoi la structure de l'écran
  /// divergerait de la maquette selon ce qui est construit.
  static const _ongletsTx = ['Vente', 'Achat', 'Devis', 'Dépenses', 'Factures'];

  Widget _transactionsRecentes() {
    final d = _donnees!;

    final lignes = switch (_ongletTx) {
      'Vente' => d.ventesRecentes,
      'Dépenses' => d.depensesRecentes,
      _ => const <LigneTransaction>[],
    };

    final embarque = _ongletTx == 'Vente' || _ongletTx == 'Dépenses';

    return _bloc(
      titre: 'Transactions Récentes',
      icone: Icons.receipt_long,
      apresTitre: const Text(
        'Voir tout',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: AgriColors.brandEmerald,
        ),
      ),
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final onglet in _ongletsTx)
                  InkWell(
                    key: Key('onglet-tx-$onglet'),
                    onTap: () => setState(() => _ongletTx = onglet),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AgriSpacing.sm,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 2,
                            color: _ongletTx == onglet
                                ? AgriColors.brandEmerald
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Text(
                        onglet,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _ongletTx == onglet
                              ? AgriColors.brandEmerald
                              : AgriColors.outline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AgriColors.outlineVariant),
          const SizedBox(height: AgriSpacing.sm),
          if (!embarque)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AgriSpacing.sm),
              child: Text(
                '— Module non embarqué au poste —',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
            )
          else if (lignes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AgriSpacing.sm),
              child: Text(
                '— Aucune écriture sur la période —',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
            )
          else
            for (final l in lignes)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AgriColors.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.libelle,
                        style: const TextStyle(fontSize: AgriTypography.xs),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${_montant(l.montant ?? 0)} F',
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                        color: _ongletTx == 'Dépenses'
                            ? AgriColors.errorRed
                            : AgriColors.brandEmerald,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  // ── 7. Activités du Jour + Top 5 Produits ─────────────────────────────────

  Widget _activitesEtTop(bool large) {
    final gauche = _bloc(
      titre: 'Activités du Jour',
      enfant: _donnees!.activitesDuJour.isEmpty
          ? const Text(
              '— Aucune écriture aujourd\'hui sur ce poste —',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontStyle: FontStyle.italic,
                color: AgriColors.outline,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final a in _donnees!.activitesDuJour) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: AgriColors.brandEmerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AgriSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.libelle,
                              style: const TextStyle(
                                fontSize: AgriTypography.xs,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              a.horodatage ?? '',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AgriColors.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AgriSpacing.md),
                ],
              ],
            ),
    );

    final droite = _bloc(
      titre: 'Top 5 Produits du Mois',
      enfant: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 420,
          child: Column(
            children: [
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AgriColors.outlineVariant),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: AgriSpacing.xs),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text('Produit', style: _enteteTop),
                    ),
                    Expanded(
                      child: Text(
                        'Qté',
                        textAlign: TextAlign.right,
                        style: _enteteTop,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'CA',
                        textAlign: TextAlign.right,
                        style: _enteteTop,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Marge',
                        textAlign: TextAlign.right,
                        style: _enteteTop,
                      ),
                    ),
                  ],
                ),
              ),
              if (_donnees!.topProduits.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AgriSpacing.sm),
                  child: Text(
                    '— Aucune vente sur la période —',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontStyle: FontStyle.italic,
                      color: AgriColors.outline,
                    ),
                  ),
                ),
              for (var i = 0; i < _donnees!.topProduits.length; i++)
                Container(
                  color: i.isEven
                      ? AgriColors.surfaceZebra
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: AgriSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          _donnees!.topProduits[i].produit,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _montant(_donnees!.topProduits[i].quantite),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _montant(_donnees!.topProduits[i].chiffreAffaires),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      // ⚠️ MARGE VIDE : elle suppose un prix de revient, que le
                      // poste ne reçoit pas. Un pourcentage calculé sur le prix
                      // de vente ne serait pas une marge.
                      const Expanded(
                        child: Text(
                          '—',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (!large) {
      return Column(
        children: [
          gauche,
          const SizedBox(height: AgriSpacing.md),
          droite,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: gauche),
        const SizedBox(width: AgriSpacing.md),
        Expanded(child: droite),
      ],
    );
  }

  static const _enteteTop = TextStyle(
    fontSize: AgriTypography.xs,
    color: AgriColors.outline,
  );

  // ── Briques communes ──────────────────────────────────────────────────────

  Widget _bloc({
    required String titre,
    required Widget enfant,
    IconData? icone,
    Widget? apresTitre,
  }) {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icone != null) ...[
                Icon(icone, size: 18, color: AgriColors.brandEmerald),
                const SizedBox(width: AgriSpacing.xs),
              ],
              Expanded(
                child: Text(
                  titre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.onSurface,
                  ),
                ),
              ),
              ?apresTitre,
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          enfant,
        ],
      ),
    );
  }

  Widget _boutonPlein({
    required Key key,
    required IconData icone,
    required String libelle,
    required VoidCallback? onPressed,
  }) => ElevatedButton.icon(
    key: key,
    onPressed: onPressed,
    icon: Icon(icone, size: 18),
    label: Text(
      libelle,
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: FontWeight.bold,
      ),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: AgriColors.brandEmerald,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.md,
        vertical: AgriSpacing.sm,
      ),
    ),
  );

  Widget _boutonClair({
    required Key key,
    required IconData icone,
    required String libelle,
    required VoidCallback? onPressed,
  }) => OutlinedButton.icon(
    key: key,
    onPressed: onPressed,
    icon: Icon(icone, size: 18),
    label: Text(
      libelle,
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: FontWeight.bold,
      ),
    ),
    style: OutlinedButton.styleFrom(
      backgroundColor: AgriColors.surfaceCard,
      foregroundColor: AgriColors.brandForest,
      side: const BorderSide(color: AgriColors.outlineVariant),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.md,
        vertical: AgriSpacing.sm,
      ),
    ),
  );

  // ── Formats ───────────────────────────────────────────────────────────────

  /// Milliers séparés par une espace, comme la maquette : « 850 000 ».
  static String _montant(double valeur) {
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  static String _dateCourte(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _heure(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Courbe « CA vs Dépenses » — trait plein émeraude, tirets rouges, exactement
/// comme le `<svg>` de la maquette.
class _CourbePainter extends CustomPainter {
  _CourbePainter(this.points);

  final List<PointMensuel> points;

  @override
  void paint(Canvas canvas, Size size) {
    final axe = Paint()
      ..color = AgriColors.outlineVariant
      ..strokeWidth = 1;

    const margeGauche = 40.0;
    const margeBas = 30.0;
    final hauteur = size.height - margeBas;

    canvas.drawLine(
      const Offset(margeGauche, 10),
      Offset(margeGauche, hauteur),
      axe,
    );
    canvas.drawLine(
      Offset(margeGauche, hauteur),
      Offset(size.width, hauteur),
      axe,
    );

    if (points.isEmpty) return;

    final maximum = points
        .expand((p) => [p.chiffreAffaires, p.depenses])
        .fold<double>(0, (a, b) => a > b ? a : b);

    final pas =
        (size.width - margeGauche - 20) /
        (points.length == 1 ? 1 : points.length - 1);

    Offset position(int i, double valeur) {
      final y = maximum <= 0
          ? hauteur - 10
          : hauteur - (valeur / maximum) * (hauteur - 20);
      return Offset(margeGauche + 10 + pas * i, y);
    }

    void tracer(
      double Function(PointMensuel) mesure,
      Color couleur,
      bool tirets,
    ) {
      final trait = Paint()
        ..color = couleur
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;

      for (var i = 0; i < points.length - 1; i++) {
        final a = position(i, mesure(points[i]));
        final b = position(i + 1, mesure(points[i + 1]));

        if (!tirets) {
          canvas.drawLine(a, b, trait);
          continue;
        }

        // Tirets 5/4, comme `stroke-dasharray="5,4"`.
        final distance = (b - a).distance;
        final direction = distance == 0 ? Offset.zero : (b - a) / distance;
        var parcouru = 0.0;
        while (parcouru < distance) {
          final fin = (parcouru + 5).clamp(0.0, distance);
          canvas.drawLine(a + direction * parcouru, a + direction * fin, trait);
          parcouru += 9;
        }
      }
    }

    tracer((p) => p.chiffreAffaires, AgriColors.brandEmerald, false);
    tracer((p) => p.depenses, AgriColors.errorRed, true);

    for (var i = 0; i < points.length; i++) {
      final texte = TextPainter(
        text: TextSpan(
          text: points[i].libelle,
          style: const TextStyle(fontSize: 10, color: AgriColors.outline),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      texte.paint(
        canvas,
        Offset(margeGauche + 10 + pas * i - texte.width / 2, hauteur + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CourbePainter ancien) =>
      ancien.points != points;
}

/// Histogramme annuel de « Statistiques de Ventes » : une paire de barres par
/// mois, émeraude puis rouge, comme les `<rect>` de la maquette.
class _HistogrammePainter extends CustomPainter {
  _HistogrammePainter(this.points);

  final List<PointMensuel> points;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height - 20;

    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = AgriColors.outlineVariant
        ..strokeWidth = 1,
    );

    if (points.isEmpty) return;

    final maximum = points
        .expand((p) => [p.chiffreAffaires, p.depenses])
        .fold<double>(0, (a, b) => a > b ? a : b);
    if (maximum <= 0) return;

    final largeurGroupe = size.width / points.length;
    final largeurBarre = (largeurGroupe / 3).clamp(3.0, 14.0);

    void barre(double x, double valeur, Color couleur) {
      final hauteur = (valeur / maximum) * (base - 10);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, base - hauteur, largeurBarre, hauteur),
          const Radius.circular(3),
        ),
        Paint()..color = couleur,
      );
    }

    for (var i = 0; i < points.length; i++) {
      final x = largeurGroupe * i + largeurGroupe * 0.1;
      barre(x, points[i].chiffreAffaires, AgriColors.brandEmerald);
      barre(x + largeurBarre + 2, points[i].depenses, AgriColors.errorRed);
    }
  }

  @override
  bool shouldRepaint(covariant _HistogrammePainter ancien) =>
      ancien.points != points;
}
