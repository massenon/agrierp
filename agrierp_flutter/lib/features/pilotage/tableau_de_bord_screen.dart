import 'package:flutter/material.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/comptabilite/exercice_choisi.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import 'tableau_de_bord_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// Tableau de Bord — ticket H5 : **la vue Blade `livewire/dashboard/index.blade.php` fait foi** (article 5).
///
/// Sections dans SON ordre, libellés au mot près (verrouillés par `test/tableau_de_bord_blade_test.dart`, qui
/// les lit dans le Blade) :
///   1. en-tête « Bienvenue… » + deux actions (Enregistrer une Vente · Élevage) ;
///   2. période « Du / au » DÉSACTIVÉE (mois courant) + sélecteur d'état (8 options) + bouton PDF ;
///   3. huit cartes KPI ;
///   4. « CA vs Dépenses — 6 derniers mois » (8/12) + « Alertes Critiques » (4/12) ;
///   5. trois cartes espèces — Lapins · Volailles · Porcs ;
///   6. « Statistiques de Ventes » + « Transactions Récentes » (cinq onglets : Vente · Achat · Devis ·
///      Dépenses · Factures) ;
///   7. « Activités du Jour » + « Top 5 Produits du Mois ».
///
/// Ajouts du poste absents du web, GARDÉS par décision client du 19/10/2026 : « · Exercice {année} actif »
/// dans l'en-tête, les sous-textes Caisse / Banque de la Trésorerie, les noms des produits du Stock Critique,
/// « Au dernier tirage » sous l'Effectif.
class TableauDeBordScreen extends StatefulWidget {
  const TableauDeBordScreen({
    super.key,
    required this.depot,
    this.onEnregistrerVente,
    this.onElevage,
    this.onOuvrir,
    this.nomUtilisateur = 'Manager Olouwachegoun',
  });

  final TableauDeBordRepository depot;
  final VoidCallback? onEnregistrerVente;
  final VoidCallback? onElevage;

  /// Ouvre un écran du poste : alerte cliquée, état choisi (bouton PDF), « Voir tout ». `null` : rien ne
  /// navigue (tests, aperçu).
  final ValueChanged<EcranPoste>? onOuvrir;
  final String nomUtilisateur;

  /// Le `<select>` du Blade : `(libellé, adresse web)`, dans son ordre. Deux options pointent la même adresse
  /// (Recettes / Dépenses) : la valeur retenue à l'écran est donc le LIBELLÉ.
  static const etats = <(String, String)>[
    ('État des Recettes', '/rapports-exports?tab=recettes-depenses'),
    ('État des Dépenses', '/rapports-exports?tab=recettes-depenses'),
    ('État de Trésorerie', '/rapports-exports?tab=tresorerie'),
    ('Bilan Simplifié', '/rapport-bilan'),
    ('État des Créances', '/rapports-exports?tab=creances'),
    ('État des Dettes', '/rapports-exports?tab=dettes'),
    ('Rapport Élevage', '/rapports-exports?tab=elevage-synth'),
    ('Rapport de Stocks', '/rapports-exports?tab=stocks-synth'),
  ];

  @override
  State<TableauDeBordScreen> createState() => _TableauDeBordScreenState();
}

class _TableauDeBordScreenState extends State<TableauDeBordScreen> {
  DonneesTableauDeBord? _donnees;
  bool _chargement = true;

  /// Onglet actif de « Transactions Récentes ».
  String _ongletTx = 'Vente';

  /// État choisi dans le sélecteur (libellé), `null` : « -- Choisir un état / rapport -- ».
  String? _etat;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    final donnees = await widget.depot.charger();
    if (!mounted) return;
    setState(() {
      _donnees = donnees;
      _chargement = false;
    });
  }

  static String _nombre(double v) => TableauDeBordRepository.nombre(v, 0);

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
                // ⚠️ MÊMES POINTS DE RUPTURE QUE LE WEB : `md:` à 768,
                // `lg:` à 1024.
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
    // Ticket EX7 — l'exercice AFFICHÉ et son statut (`ExerciceChoisi::exercice()` du web : « Exercice 2026 actif » ou
    // « Exercice 2026 clôturé ») ; hors du socle, l'exercice ouvert le plus récent, comme avant.
    final affiche = PorteeExerciceChoisi.lire(context)?.exercice;
    final exercice = affiche?.year ?? _donnees?.exerciceOuvert;
    final etatExercice = affiche?.status == 'cloture' ? 'clôturé' : 'actif';
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
          'Rapport généré le ${_dateCourte(HeureBenin.maintenant())} '
          'à ${_heure(HeureBenin.maintenant())} · '
          '${exercice == null ? 'Aucun exercice ouvert' : 'Exercice $exercice $etatExercice'}',
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
          icone: SymbolesAgri.point_of_sale,
          libelle: 'Enregistrer une Vente',
          onPressed: widget.onEnregistrerVente,
        ),
        _boutonClair(
          key: const Key('action-elevage'),
          icone: SymbolesAgri.pets,
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

  // ── 2. Période + sélecteur d'état ─────────────────────────────────────────

  /// Écran du poste ouvert par l'état choisi, `null` si aucun état ou si le poste n'a pas la page
  /// (`/rapport-bilan`) : aucune cible inventée, le bouton PDF reste alors désactivé.
  EcranPoste? get _cibleEtat {
    final choisi = _etat;
    if (choisi == null) return null;
    final adresse = TableauDeBordScreen.etats
        .firstWhere((e) => e.$1 == choisi)
        .$2;
    return TableauDeBordRepository.ecranDuLien(adresse);
  }

  /// ⚠️ **PÉRIODE DÉSACTIVÉE, COMME LE WEB** (`<input type="date" … disabled>`) : le tableau de bord est calé
  /// sur le mois courant. Le sélecteur d'état navigue, comme `window.location.href = report`.
  Widget _filtreEtExport(bool large) {
    final d = _donnees!;
    final dates = Row(
      children: [
        const Icon(SymbolesAgri.calendar_month, size: 18, color: AgriColors.outline),
        const SizedBox(width: AgriSpacing.xs),
        Expanded(child: _champDate(const Key('date-du'), d.debutPeriode)),
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
        Expanded(child: _champDate(const Key('date-au'), d.finPeriode)),
      ],
    );

    final cible = _cibleEtat;
    final exports = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: large ? 224 : 180,
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const Key('choix-etat'),
              value: _etat,
              isExpanded: true,
              isDense: true,
              hint: const Text(
                '-- Choisir un état / rapport --',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.onSurface,
              ),
              items: [
                for (final (libelle, _) in TableauDeBordScreen.etats)
                  DropdownMenuItem(
                    value: libelle,
                    child: Text(libelle, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _etat = v),
            ),
          ),
        ),
        const SizedBox(width: AgriSpacing.xs),
        _boutonPlein(
          key: const Key('export-pdf'),
          icone: SymbolesAgri.picture_as_pdf,
          libelle: 'PDF',
          onPressed: cible == null || widget.onOuvrir == null
              ? null
              : () => widget.onOuvrir!(cible),
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

  /// Champ de date DÉSACTIVÉ : aucun sélecteur ne s'ouvre, fond grisé.
  Widget _champDate(Key cle, DateTime valeur) {
    return Container(
      key: cle,
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Text(
        _dateCourte(valeur),
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          color: AgriColors.outline,
        ),
      ),
    );
  }

  // ── 3. Les huit KPI ───────────────────────────────────────────────────────

  Widget _kpis(bool moyen) {
    final d = _donnees!;
    final caisse = d.tresorerieParType['caisse'] ?? 0;
    final banque = d.tresorerieParType['banque'] ?? 0;
    final mobileMoney = d.tresorerieParType['mobile_money'] ?? 0;

    final cartes = <Widget>[
      _carteKpi(
        libelle: "Chiffre d'Affaires",
        mesure: d.chiffreAffaires,
        unite: 'FCFA',
        detail: d.legendeChiffreAffaires ?? '',
        icone: SymbolesAgri.trending_up,
        barre: AgriColors.brandEmerald,
      ),
      _carteKpi(
        libelle: 'Trésorerie',
        mesure: d.tresorerie,
        unite: 'FCFA',
        // Ajout du poste, construit au web (H11) ; Mobile Money en troisième ligne (D-U8). Même texte que la
        // légende du web (`dashboard/index.blade.php`), « F » compris.
        detail: 'Caisse : ${_nombre(caisse)} F · Banque : ${_nombre(banque)} F · '
            'Mobile Money : ${_nombre(mobileMoney)} F',
        icone: SymbolesAgri.account_balance_wallet,
        barre: AgriColors.infoBlue,
        couleurIcone: AgriColors.infoBlue,
      ),
      _carteKpi(
        libelle: 'Dépenses',
        mesure: d.depenses,
        unite: 'FCFA',
        detail: d.legendeDepenses ?? '',
        icone: SymbolesAgri.shopping_cart,
        barre: AgriColors.accentYellow,
        couleurIcone: AgriColors.brandForest,
      ),
      _carteKpi(
        libelle: 'Résultat Net',
        mesure: d.resultatNet,
        unite: 'FCFA',
        detail: d.legendeResultatNet ?? '',
        icone: SymbolesAgri.savings,
        barre: AgriColors.brandEmerald,
      ),
      _carteKpi(
        libelle: 'Créances Clients',
        mesure: d.creances,
        unite: 'FCFA',
        detail: '',
        icone: SymbolesAgri.request_quote,
        barre: AgriColors.errorRed,
        couleurIcone: AgriColors.errorRed,
      ),
      _carteKpi(
        libelle: 'Dettes Fournisseurs',
        mesure: d.dettes,
        unite: 'FCFA',
        detail: '',
        icone: SymbolesAgri.local_shipping,
        barre: AgriColors.accentYellow,
        couleurIcone: AgriColors.brandForest,
      ),
      _carteKpi(
        libelle: 'Stock Critique',
        mesure: Mesure.chiffre(d.produitsSousSeuil.length.toDouble()),
        unite: 'produits',
        // Ajout du poste, gardé (décision client du 19/10/2026).
        detail: d.produitsSousSeuil.isEmpty
            ? 'Aucun produit sous son seuil'
            : d.produitsSousSeuil.take(3).map((p) => p.name).join(', '),
        icone: SymbolesAgri.warning,
        barre: AgriColors.errorRed,
        couleurIcone: AgriColors.errorRed,
      ),
      _carteKpi(
        libelle: 'Effectif Animaux',
        mesure: d.effectifAnimaux,
        unite: 'têtes',
        // Ajout du poste, gardé (décision client du 19/10/2026).
        detail: 'Au dernier tirage',
        icone: SymbolesAgri.pets,
        barre: AgriColors.brandEmerald,
      ),
    ];

    // ⚠️ HAUTEUR FIXE, PAS UN RAPPORT LARGEUR / HAUTEUR. Une carte KPI garde la hauteur de son contenu quelle que
    // soit sa largeur (la grille web n'impose aucun rapport) : avec `childAspectRatio`, la barre latérale passée à
    // 288 px comme au web (ticket H1) rétrécissait les cartes en 1280 px et leur contenu débordait.
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: moyen ? 4 : 2,
        mainAxisSpacing: AgriSpacing.md,
        crossAxisSpacing: AgriSpacing.md,
        mainAxisExtent: 160,
      ),
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
    valeur: mesure.disponible ? _nombre(mesure.valeur!) : '—',
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
        ],
      ),
    );

    final alertes = _bloc(
      titre: 'Alertes Critiques',
      enfant: _donnees!.alertes.isEmpty
          ? _messageVide('Aucune alerte critique pour le moment.', centre: true)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _donnees!.alertes.length; i++) ...[
                  if (i > 0) const SizedBox(height: AgriSpacing.sm),
                  _alerte(i, _donnees!.alertes[i]),
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

    // ⚠️ RAPPORT 8/12 – 4/12 DU WEB, pas une demi-largeur chacun.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 8, child: courbe),
        const SizedBox(width: AgriSpacing.md),
        Expanded(flex: 4, child: alertes),
      ],
    );
  }

  /// Une alerte : icône `warning`, fond rouge (critique) ou jaune (moyen), et lien vers l'écran du poste quand
  /// il existe (`<a href="{{ $alert['link'] }}">`). `/gestion-bandes` n'a pas d'écran au poste : pas de lien.
  Widget _alerte(int i, AlerteCritique a) {
    final ecran = TableauDeBordRepository.ecranDuLien(a.lien);
    final couleur = a.grave ? AgriColors.errorDeep : AgriColors.brandForest;
    final rayon = BorderRadius.circular(AgriRadius.lg);

    return Material(
      color: a.grave
          ? AgriColors.errorBg
          : AgriColors.accentYellow.withValues(alpha: 0.20),
      shape: RoundedRectangleBorder(
        borderRadius: rayon,
        side: a.grave
            ? BorderSide(color: AgriColors.errorDeep.withValues(alpha: 0.20))
            : BorderSide.none,
      ),
      child: InkWell(
        key: Key('alerte-$i'),
        borderRadius: rayon,
        onTap: ecran == null || widget.onOuvrir == null
            ? null
            : () => widget.onOuvrir!(ecran),
        child: Padding(
          padding: const EdgeInsets.all(AgriSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(SymbolesAgri.warning, size: 18, color: couleur),
              const SizedBox(width: AgriSpacing.xs),
              Expanded(
                child: Text(
                  a.message,
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.w600,
                    color: couleur,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

  // ── 5. Cartes espèces ─────────────────────────────────────────────────────

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
    'Lapins': SymbolesAgri.cruelty_free,
    'Volailles': SymbolesAgri.egg,
    'Porcs': SymbolesAgri.pets,
  };

  Widget _carteEspece(CarteEspece carte) {
    // ⚠️ `$x['mortalite'] > 5` dans le Blade : STRICTEMENT au-dessus de 5 (5,0 % reste vert).
    final critique =
        carte.mortalite > TableauDeBordRepository.seuilMortaliteCarte;

    final mesures = [
      ...carte.mesures,
      (
        'Mortalité',
        '${TableauDeBordRepository.nombre(carte.mortalite, 1)}%',
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
                _iconesEspeces[carte.titre] ?? SymbolesAgri.pets,
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
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Hauteur fixe, même raison que la grille des KPI.
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AgriSpacing.sm,
              crossAxisSpacing: AgriSpacing.sm,
              mainAxisExtent: 68,
            ),
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

  /// Tuiles « Revenu » / « Dépenses » du mois courant (dernier point de la série, achats en dépenses) et
  /// histogramme des SIX mois de la courbe, comme le web.
  Widget _statistiquesDeVentes() {
    final serie = _donnees!.serie;
    final courant = serie.last;
    final (suffixeCa, suffixeDep) =
        TableauDeBordRepository.variationStatistique(serie);

    return _bloc(
      titre: 'Statistiques de Ventes',
      icone: SymbolesAgri.bar_chart,
      apresTitre: Text(
        '${HeureBenin.maintenant().year}',
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
                  '${_nombre(courant.chiffreAffaires)} F',
                  'Revenu$suffixeCa',
                  AgriColors.brandEmerald,
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _tuile(
                  '${_nombre(courant.depenses)} F',
                  'Dépenses$suffixeDep',
                  AgriColors.errorRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          SizedBox(
            height: 128,
            child: CustomPaint(
              painter: _HistogrammePainter(serie),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final m in serie)
                Text(
                  m.libelle,
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

  /// Les cinq onglets du web, dans son ordre, avec leurs messages vides exacts.
  ///
  /// ⚠️ ÉCART (donnée absente) : l'onglet Devis n'a pas de table au poste (`quotes` ne descend pas). Il reste
  /// à sa place et affiche le message vide du web plutôt que de disparaître.
  static const _ongletsTx = <(String, String)>[
    ('Vente', 'Aucune vente récente.'),
    ('Achat', 'Aucun achat récent.'),
    ('Devis', 'Aucun devis récent.'),
    ('Dépenses', 'Aucune dépense récente.'),
    ('Factures', 'Aucune facture récente.'),
  ];

  static Color _couleurTon(TonMontant ton) => switch (ton) {
    TonMontant.emeraude => AgriColors.brandEmerald,
    TonMontant.foret => AgriColors.brandForest,
    TonMontant.jaune => AgriColors.accentYellow,
    TonMontant.bleu => AgriColors.infoBlue,
    TonMontant.rouge => AgriColors.errorRed,
  };

  Widget _transactionsRecentes() {
    final d = _donnees!;

    final lignes = switch (_ongletTx) {
      'Vente' => d.ventesRecentes,
      'Achat' => d.achatsRecents,
      'Dépenses' => d.depensesRecentes,
      'Factures' => d.facturesRecentes,
      _ => const <LigneTransaction>[],
    };
    final messageVide = _ongletsTx.firstWhere((o) => o.$1 == _ongletTx).$2;

    return _bloc(
      titre: 'Transactions Récentes',
      icone: SymbolesAgri.receipt_long,
      // `<a href="/ventes-devis">Voir tout</a>`.
      apresTitre: InkWell(
        key: const Key('tx-voir-tout'),
        onTap: widget.onOuvrir == null
            ? null
            : () => widget.onOuvrir!(EcranPoste.ventesEtDevis),
        child: const Text(
          'Voir tout',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AgriColors.brandEmerald,
          ),
        ),
      ),
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (onglet, _) in _ongletsTx)
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
          if (lignes.isEmpty)
            _messageVide(messageVide, centre: true)
          else
            for (var i = 0; i < lignes.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  border: i < lignes.length - 1
                      ? const Border(
                          bottom: BorderSide(color: AgriColors.outlineVariant),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        lignes[i].libelle,
                        style: const TextStyle(fontSize: AgriTypography.xs),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${_nombre(lignes[i].montant)} F',
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                        color: _couleurTon(lignes[i].ton),
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
          ? _messageVide(
              "Aucune activité enregistrée aujourd'hui pour le moment.",
              centre: true,
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
                              a.detail,
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

    final top = _donnees!.topProduits;
    final droite = _bloc(
      titre: 'Top 5 Produits du Mois',
      enfant: top.isEmpty
          ? _messageVide('Aucune vente ce mois-ci.', centre: true)
          : SingleChildScrollView(
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
                      padding: const EdgeInsets.symmetric(
                        vertical: AgriSpacing.xs,
                      ),
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
                    for (var i = 0; i < top.length; i++)
                      Container(
                        // `$i % 2 === 1 ? 'bg-surface-zebra'` : la DEUXIÈME ligne est zébrée.
                        decoration: BoxDecoration(
                          color: i.isOdd
                              ? AgriColors.surfaceZebra
                              : Colors.transparent,
                          border: const Border(
                            bottom: BorderSide(
                              color: AgriColors.outlineVariant,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: AgriSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                top[i].produit,
                                style: const TextStyle(
                                  fontSize: AgriTypography.xs,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                TableauDeBordRepository.quantiteTop(
                                  top[i].quantite,
                                ),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: AgriTypography.xs,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _nombre(top[i].chiffreAffaires),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: AgriTypography.xs,
                                ),
                              ),
                            ),
                            // Marge en émeraude, « — » en gris sans PMP (voir le dépôt).
                            Expanded(
                              child: Text(
                                top[i].margePct == null
                                    ? '—'
                                    : '${top[i].margePct}%',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: AgriTypography.xs,
                                  color: top[i].margePct == null
                                      ? AgriColors.outline
                                      : AgriColors.brandEmerald,
                                ),
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

  /// Message vide du web : `text-xs text-outline text-center`.
  Widget _messageVide(String message, {bool centre = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AgriSpacing.md),
    child: Text(
      message,
      textAlign: centre ? TextAlign.center : TextAlign.start,
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        color: AgriColors.outline,
      ),
    ),
  );

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
      // `disabled:bg-surface-zebra disabled:text-outline`.
      disabledBackgroundColor: AgriColors.surfaceZebra,
      disabledForegroundColor: AgriColors.outline,
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
