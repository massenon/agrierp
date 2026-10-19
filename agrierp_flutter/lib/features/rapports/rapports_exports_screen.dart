import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/export/document_officiel.dart';
import '../../core/export/export_tableur.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import 'rapports_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// Signature de l'éditeur, injectable — un test ne lance pas d'imprimante.
typedef Editeur =
    Future<String?> Function(DocumentOfficiel document, DateTime maintenant);

/// `prototype_html/rapports-exports.html` → Rapports & Exports.
///
/// ⚠️⚠️ **HUB À SIX ONGLETS**, dans l'ordre du hub : Recettes et Dépenses
/// (`rapport-recettes-depenses.html`) · État de Trésorerie
/// (`rapport-tresorerie.html`) · Créances Clients (`rapport-creances.html`) ·
/// Dettes Fournisseurs (`rapport-dettes.html`) · Rapport Élevage
/// (`rapport-elevage-synth.html`) · Rapport de Stocks
/// (`rapport-stocks-synth.html`).
///
/// ⚠️ **QUATRE PAGES `rapport-*.html` NE SONT PAS DANS CE HUB** et ne sont donc
/// pas portées ici : `rapport-bilan.html` et `rapport-mensuel.html` s'ouvrent
/// depuis la comptabilité et le tableau de bord ; `rapport-recettes.html` et
/// `rapport-depenses.html` ne sont référencées par **aucune** page de la
/// maquette (vérifié par `grep` sur les 103 fichiers) — ce sont des orphelines,
/// à signaler, pas à porter au hasard.
///
/// ⚠️⚠️ **LA BARRE DU HUB ET CELLE DE LA PAGE PORTENT TOUTES DEUX PDF/EXCEL,
/// ET C'EST LA MAQUETTE.** Le hub charge chaque rapport en `<iframe>` : la
/// barre du hub reste visible AU-DESSUS de la barre du rapport, qui n'est pas
/// du chrome et n'est donc pas masquée par le garde d'iframe. Les deux couples
/// de boutons déclenchent le même export — `exportActiveHubTabPDF()` du hub
/// délègue à la fonction du rapport actif. N'en garder qu'un seul serait une
/// perte de structure.
///
/// ⚠️ **NI PAGINATEUR NI SÉLECTEUR DE RÔLE.** Le premier est un artefact de
/// `initDataTable()` que le poste remplace par le défilement, comme sur les
/// écrans déjà portés ; le second est un widget de démonstration, exclu par la
/// règle du projet.
class RapportsExportsScreen extends StatefulWidget {
  const RapportsExportsScreen({
    super.key,
    required this.depot,
    this.imprimer,
    this.enregistrer,
    this.maintenant,
  });

  final RapportsRepository depot;

  /// Éditeurs injectables. En production ils sont posés par [main]; en test
  /// ils enregistrent l'appel sans toucher au système.
  final Editeur? imprimer;
  final Editeur? enregistrer;

  /// Horloge injectable — un document daté par `DateTime.now()` ne serait
  /// comparable d'aucune exécution à l'autre.
  final DateTime Function()? maintenant;

  /// Les six onglets du hub, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Recettes et Dépenses', SymbolesAgri.receipt_long),
    ('État de Trésorerie', SymbolesAgri.account_balance_wallet),
    ('Créances Clients', SymbolesAgri.request_quote),
    ('Dettes Fournisseurs', SymbolesAgri.local_shipping),
    ('Rapport Élevage', SymbolesAgri.pets),
    ('Rapport de Stocks', SymbolesAgri.inventory_2),
  ];

  /// Les trois tableaux du rapport d'élevage, dans l'ordre de ses pilules.
  static const tableauxElevage = <String>[
    'Tableau 1 : Recensement Hebdomadaire',
    'Tableau 2 : Mouvements, Traitements & Ventes',
    'Tableau 3 : Suivi Intégral de la Ponte',
  ];

  @override
  State<RapportsExportsScreen> createState() => _RapportsExportsScreenState();
}

class _RapportsExportsScreenState extends State<RapportsExportsScreen> {
  String _onglet = RapportsExportsScreen.onglets.first.$1;
  String _tableauElevage = RapportsExportsScreen.tableauxElevage.first;
  String _recherche = '';

  late DateTime _du;
  late DateTime _au;

  DonneesRapports? _donnees;

  DateTime get _maintenant => (widget.maintenant ?? DateTime.now)();

  @override
  void initState() {
    super.initState();

    // ⚠️⚠️ **LES DEUX CHAMPS DE DATE DU HUB NE SONT BRANCHÉS SUR RIEN DANS LA
    // MAQUETTE** — `hub-filter-du` et `hub-filter-au` sont déclarés et jamais
    // lus (vérifié : deux occurrences en tout, les deux dans le HTML). Ici ils
    // filtrent réellement : un contrôle décoratif est exactement le mode
    // d'échec que la doctrine de portage interdit.
    //
    // ⚠️ Le mois EN COURS, pas le juillet 2026 figé des pages de démonstration.
    final aujourdHui = _maintenant;
    _du = DateTime(aujourdHui.year, aujourdHui.month, 1);
    _au = aujourdHui;

    _charger();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger(du: _du, au: _au);
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final large = AgriBreakpoints.large(context);

                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    large ? AgriSpacing.lg : AgriSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _enteteHub(large),
                      const SizedBox(height: AgriSpacing.md),
                      _barreFiltre(),
                      const SizedBox(height: AgriSpacing.md),
                      _barreOnglets(),
                      const SizedBox(height: AgriSpacing.lg),
                      switch (_onglet) {
                        'État de Trésorerie' => _ongletTresorerie(d, large),
                        'Créances Clients' => _ongletCreances(d, large),
                        'Dettes Fournisseurs' => _ongletDettes(d, large),
                        'Rapport Élevage' => _ongletElevage(d, large),
                        'Rapport de Stocks' => _ongletStocks(d, large),
                        _ => _ongletRecettesDepenses(d, large),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }

  // ── En-tête et barre de filtre du hub ─────────────────────────────────────

  Widget _enteteHub(bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(SymbolesAgri.summarize, size: 26, color: AgriColors.brandEmerald),
          const SizedBox(width: AgriSpacing.xs),
          Expanded(
            child: Text(
              'Rapports & Exports',
              style: TextStyle(
                fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
                fontWeight: AgriTypography.gras,
                color: AgriColors.onSurface,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: AgriSpacing.xs),
      const Text(
        'Centre de décision stratégique — états comptables, financiers, '
        'zootechniques et commerciaux.',
        style: TextStyle(
          fontSize: AgriTypography.xs,
          color: AgriColors.outline,
        ),
      ),
    ],
  );

  Widget _barreFiltre() => Container(
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.surfaceZebra,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Wrap(
      spacing: AgriSpacing.sm,
      runSpacing: AgriSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(SymbolesAgri.calendar_month, size: 18, color: AgriColors.outline),
        _champDate('hub-filter-du', _du, (v) {
          setState(() => _du = v);
          _charger();
        }),
        const Text(
          'au',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        _champDate('hub-filter-au', _au, (v) {
          setState(() => _au = v);
          _charger();
        }),
        _boutonExport(
          cle: 'hub-export-pdf',
          libelle: 'Exporter PDF',
          icone: SymbolesAgri.picture_as_pdf,
          plein: true,
          surAppui: _exporterPdf,
        ),
        _boutonExport(
          cle: 'hub-export-excel',
          libelle: 'Excel',
          icone: SymbolesAgri.table_view,
          plein: false,
          surAppui: _exporterTableur,
        ),
      ],
    ),
  );

  Widget _champDate(
    String cle,
    DateTime valeur,
    ValueChanged<DateTime> quand,
  ) => OutlinedButton.icon(
    key: Key(cle),
    onPressed: () async {
      final choix = await showDatePicker(
        context: context,
        initialDate: valeur,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        locale: const Locale('fr'),
      );
      if (choix != null) quand(choix);
    },
    icon: const Icon(SymbolesAgri.event, size: 16),
    label: Text(
      RapportsRepository.date(valeur),
      style: const TextStyle(fontSize: AgriTypography.xs),
    ),
    style: OutlinedButton.styleFrom(
      foregroundColor: AgriColors.onSurface,
      backgroundColor: AgriColors.surfaceCard,
      side: const BorderSide(color: AgriColors.outlineVariant),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
    ),
  );

  Widget _boutonExport({
    required String cle,
    required String libelle,
    required IconData icone,
    required bool plein,
    required VoidCallback surAppui,
  }) => plein
      ? ElevatedButton.icon(
          key: Key(cle),
          onPressed: surAppui,
          icon: Icon(icone, size: 18),
          label: Text(
            libelle,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AgriColors.brandEmerald,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
          ),
        )
      : OutlinedButton.icon(
          key: Key(cle),
          onPressed: surAppui,
          icon: Icon(icone, size: 18),
          label: Text(
            libelle,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AgriColors.brandForest,
            backgroundColor: AgriColors.surfaceCard,
            side: const BorderSide(color: AgriColors.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
          ),
        );

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (titre, icone) in RapportsExportsScreen.onglets)
            InkWell(
              key: Key('onglet-rapports-$titre'),
              onTap: () => setState(() {
                _onglet = titre;
                _recherche = '';
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icone,
                      size: 18,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : AgriColors.outline,
                    ),
                    const SizedBox(width: AgriSpacing.xs),
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: AgriTypography.gras,
                        color: _onglet == titre
                            ? AgriColors.brandEmerald
                            : AgriColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  // ── Onglet 1 : Recettes et Dépenses ───────────────────────────────────────

  Widget _ongletRecettesDepenses(DonneesRapports d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _enteteRapport(
        'État des Recettes et Dépenses',
        'Comparatif détaillé des entrées et sorties de trésorerie sur la '
            'période.',
        SymbolesAgri.receipt_long,
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      _grilleKpi(
        large,
        const [
          ('Total Recettes', SymbolesAgri.trending_up, AgriColors.brandEmerald),
          ('Total Dépenses', SymbolesAgri.trending_down, AgriColors.errorRed),
          ('Solde Net', SymbolesAgri.account_balance_wallet, AgriColors.infoBlue),
        ],
        [
          RapportsRepository.montant(d.totalRecettes),
          RapportsRepository.montant(d.totalDepenses),
          RapportsRepository.montant(d.soldeNet),
        ],
        couleurValeur: [
          AgriColors.onSurface,
          AgriColors.onSurface,
          d.soldeNet < 0 ? AgriColors.errorDeep : AgriColors.onSurface,
        ],
      ),
      const SizedBox(height: AgriSpacing.lg),
      _sousTitre('Recettes', AgriColors.brandEmerald),
      const SizedBox(height: AgriSpacing.sm),
      _tableau(
        cle: 'tableau-recettes',
        largeur: 700,
        colonnes: const [('Date', 3), ('Libellé', 7), ('Montant', 3)],
        vide: '— Aucune recette sur la période —',
        lignes: d.recettes,
        couleurDerniere: AgriColors.brandEmerald,
      ),
      const SizedBox(height: AgriSpacing.lg),
      _sousTitre('Dépenses', AgriColors.errorDeep),
      const SizedBox(height: AgriSpacing.sm),
      _tableau(
        cle: 'tableau-depenses',
        largeur: 700,
        colonnes: const [('Date', 3), ('Libellé', 7), ('Montant', 3)],
        vide: '— Aucune dépense sur la période —',
        lignes: d.depenses,
        couleurDerniere: AgriColors.errorDeep,
      ),
      const SizedBox(height: AgriSpacing.md),
      _mentionPoste(
        "Ce comparatif porte les ventes et les dépenses présentes sur CE poste. "
        "Une vente encaissée sur un autre poste et pas encore descendue n'y "
        "figure pas ; une vente annulée y figure sans compter au chiffre "
        "d'affaires.",
      ),
    ],
  );

  // ── Onglet 2 : État de Trésorerie ─────────────────────────────────────────

  Widget _ongletTresorerie(DonneesRapports d, bool large) {
    final t = d.tresorerie;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _enteteRapport(
          'État de Trésorerie',
          'Position de trésorerie consolidée.',
          SymbolesAgri.account_balance_wallet,
          large,
        ),
        const SizedBox(height: AgriSpacing.md),
        _champRecherche('tresorerie', 'Rechercher...'),
        const SizedBox(height: AgriSpacing.sm),
        _tableau(
          cle: 'tableau-tresorerie',
          largeur: 900,
          colonnes: const [
            ('Date', 3),
            ('Solde Caisse', 3),
            ('Solde Banque', 3),
            ('Solde Total', 3),
            ('Actions', 2),
          ],
          vide: '— Aucun solde reçu du serveur —',
          lignes: [
            LigneRapport([
              t.releveLe == null ? '—' : RapportsRepository.date(t.releveLe!),
              t.caisse == null ? '—' : RapportsRepository.montant(t.caisse!),
              t.banque == null ? '—' : RapportsRepository.montant(t.banque!),
              t.total == null ? '—' : RapportsRepository.montant(t.total!),
            ]),
          ],
          lectureSeule: true,
        ),
        const SizedBox(height: AgriSpacing.md),
        // ⚠️⚠️ **UNE PHRASE DATÉE, PAS UNE SÉRIE INVENTÉE.** La maquette
        // dessine une ÉVOLUTION jour par jour ; le poste ne détient qu'un
        // solde, celui du dernier tirage. Il n'affiche donc qu'une ligne — la
        // seule qu'il puisse signer — et dit à quelle date elle se rapporte.
        _mentionPoste(
          t.releveLe == null
              ? "Aucun solde n'est encore descendu sur ce poste : les cellules "
                    "portent un tiret, et non un zéro qui se lirait « la caisse "
                    "est vide ». Synchronisez pour obtenir la position du jour."
              : "Au ${RapportsRepository.date(t.releveLe!)}, dernier tirage. "
                    "⚠️ Le poste ne tient PAS la série journalière des soldes : "
                    "elle se lit sur la surface web, seule à détenir toutes les "
                    "écritures. Le Solde Total inclut le Mobile Money, qui n'a "
                    "pas de colonne propre dans la maquette — il n'est donc pas "
                    "égal à Caisse + Banque.",
        ),
      ],
    );
  }

  // ── Onglets 3 et 4 : Créances et Dettes ───────────────────────────────────

  Widget _ongletCreances(DonneesRapports d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _enteteRapport(
        'État des Créances Clients',
        'Suivi des sommes dues par les clients.',
        SymbolesAgri.request_quote,
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      _champRecherche('creances', 'Rechercher...'),
      const SizedBox(height: AgriSpacing.sm),
      _tableau(
        cle: 'tableau-creances',
        largeur: 800,
        colonnes: const [
          ('Client', 5),
          ('Montant Dû', 3),
          ('Échéance', 3),
          ('Actions', 2),
        ],
        vide: '— Aucune créance ouverte —',
        lignes: _filtrees(d.creances),
        lectureSeule: true,
      ),
      const SizedBox(height: AgriSpacing.md),
      _mentionPoste(
        "Le montant affiché est le RESTE DÛ (montant − déjà réglé), jamais le "
        "montant facturé. Le serveur ne descend que les créances non soldées.",
      ),
    ],
  );

  Widget _ongletDettes(DonneesRapports d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _enteteRapport(
        'État des Dettes Fournisseurs',
        'Suivi des sommes dues aux fournisseurs.',
        SymbolesAgri.local_shipping,
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      _champRecherche('dettes', 'Rechercher...'),
      const SizedBox(height: AgriSpacing.sm),
      _tableau(
        cle: 'tableau-dettes',
        largeur: 800,
        colonnes: const [
          ('Fournisseur', 5),
          ('Montant Dû', 3),
          ('Échéance', 3),
          ('Actions', 2),
        ],
        vide: '— Aucune dette ouverte —',
        lignes: _filtrees(d.dettes),
        lectureSeule: true,
      ),
      const SizedBox(height: AgriSpacing.md),
      _mentionPoste(
        "Le montant affiché est le RESTE DÛ. Un fournisseur archivé reste "
        "nommé sur l'ardoise qu'il a laissée.",
      ),
    ],
  );

  // ── Onglet 5 : Rapport Élevage ────────────────────────────────────────────

  Widget _ongletElevage(DonneesRapports d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _enteteRapport(
        'Rapport Élevage — Synthèse Détaillée',
        'Restitution fidèle des registres manuscrits — recensement, mouvements '
            "et suivi de ponte, alimentée automatiquement depuis les fiches "
            "d'élevage.",
        SymbolesAgri.pets,
        large,
        actionSupplementaire: OutlinedButton.icon(
          key: const Key('elevage-filtrer-periode'),
          onPressed: _ouvrirFiltrePeriode,
          icon: const Icon(SymbolesAgri.tune, size: 18),
          label: const Text(
            'Filtrer la Période',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AgriColors.brandForest,
            side: const BorderSide(color: AgriColors.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AgriRadius.full),
            ),
          ),
        ),
      ),
      const SizedBox(height: AgriSpacing.md),
      _grilleKpi(
        large,
        const [
          ('Production Totale (Œufs)', null, AgriColors.brandEmerald),
          ('Taux de Ponte Moyen', null, AgriColors.infoBlue),
          ('Taux de Mortalité Hebdo', null, AgriColors.errorRed),
          ('CA Ventes du Lot', null, AgriColors.accentYellow),
        ],
        [
          '${d.indicateurs.productionTotale} œufs',
          d.indicateurs.tauxPonteMoyen == null
              ? '—'
              : '${d.indicateurs.tauxPonteMoyen!.toStringAsFixed(1)} %',
          d.indicateurs.mortaliteHebdo == null
              ? '—'
              : '${d.indicateurs.mortaliteHebdo!.toStringAsFixed(1)} %',
          d.indicateurs.chiffreAffaires == null
              ? '—'
              : '${RapportsRepository.montant(d.indicateurs.chiffreAffaires!)} FCFA',
        ],
      ),
      const SizedBox(height: AgriSpacing.lg),
      _pilulesElevage(),
      const SizedBox(height: AgriSpacing.md),
      switch (_tableauElevage) {
        'Tableau 2 : Mouvements, Traitements & Ventes' => _tableau(
          cle: 'tableau-elevage-t2',
          largeur: 1400,
          colonnes: const [
            ('Date', 3),
            ('Lot', 4),
            ('Sexe Vendu', 3),
            ('Qté Vendue', 3),
            ('Montant Vente (FCFA)', 4),
            ('Effectif Final', 3),
            ('Traitement Administré', 4),
            ('Dose', 3),
            ('Signes de Maladie Observés', 5),
          ],
          vide: '— Aucune journée saisie sur la période —',
          lignes: d.elevageT2,
        ),
        'Tableau 3 : Suivi Intégral de la Ponte' => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tableau(
              cle: 'tableau-elevage-t3',
              largeur: 1500,
              colonnes: const [
                ('Âge (Sem.)', 3),
                ('Jour', 3),
                ('Total Œufs Récoltés (OR)', 4),
                ('Taux Ponte %', 3),
                ('Cassés/Fêlés (OF)', 3),
                ('Commercialisables (OR-OF)', 4),
                ('Stock Restant Hier (SRH)', 4),
                ('Total Stock (TS)', 3),
                ('Sorties Vente OS (Plateaux)', 4),
                ('Stock Final (Plateaux + Vrac)', 5),
              ],
              vide: '— Aucune journée de ponte saisie sur la période —',
              lignes: d.elevageT3,
            ),
            const Padding(
              padding: EdgeInsets.only(top: AgriSpacing.sm),
              child: Text(
                'Formules : Taux de Ponte % = (OR × 100) ÷ Effectif Fin — '
                'Total Stock (TS) = (OR−OF) + SRH — Stock Final = TS − OS',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ),
          ],
        ),
        _ => _tableau(
          cle: 'tableau-elevage-t1',
          largeur: 1700,
          colonnes: const [
            ('Date', 3),
            ('Lot / Souche', 4),
            ('Mères Pondeuses', 3),
            ('Mères Couveuses', 3),
            ('Mères Éleveuses', 3),
            ('Poussins S/Mères', 3),
            ('Sevrés M', 2),
            ('Sevrés F', 2),
            ('Morts M', 2),
            ('Morts F', 2),
            ('Morts SM', 2),
            ('Géniteurs', 2),
            ('Effectif Malade', 3),
          ],
          vide: '— Aucune journée saisie sur la période —',
          lignes: d.elevageT1,
        ),
      },
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ Les deux limites du rapport d'élevage, dites à l'écran. Un
      // rapport muet sur ce qu'il ne couvre pas se lit comme un rapport
      // complet — et une colonne de tirets passerait pour une ferme sans
      // mortalité.
      _mentionPoste(
        "Ce rapport porte les journées saisies SUR CE POSTE : les fiches "
        "d'élevage ne descendent jamais du serveur, elles n'y montent que. "
        "⚠️ Les colonnes en tiret (ventilation par sexe et par stade, "
        "traitement, dose, symptômes, montant de vente) ne quittent pas le "
        "poste à l'envoi : il ne les a jamais eues. Elles restent affichées "
        "parce que la maquette les demande — les retirer laisserait croire le "
        "contraire. Le Tableau 3, lui, est intégralement calculé ici.",
      ),
    ],
  );

  Widget _pilulesElevage() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final titre in RapportsExportsScreen.tableauxElevage)
          Padding(
            padding: const EdgeInsets.only(right: AgriSpacing.xs),
            child: InkWell(
              key: Key('pilule-$titre'),
              onTap: () => setState(() => _tableauElevage = titre),
              borderRadius: BorderRadius.circular(AgriRadius.full),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: _tableauElevage == titre
                      ? AgriColors.brandEmerald
                      : Colors.transparent,
                  border: Border.all(
                    color: _tableauElevage == titre
                        ? AgriColors.brandEmerald
                        : AgriColors.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(AgriRadius.full),
                ),
                child: Text(
                  titre,
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                    color: _tableauElevage == titre
                        ? Colors.white
                        : AgriColors.outline,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  // ── Onglet 6 : Rapport de Stocks ──────────────────────────────────────────

  Widget _ongletStocks(DonneesRapports d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _enteteRapport(
        'Rapport de Stocks — Synthèse',
        'État consolidé des stocks et alertes.',
        SymbolesAgri.inventory_2,
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      _champRecherche('stocks', 'Rechercher...'),
      const SizedBox(height: AgriSpacing.sm),
      _tableau(
        cle: 'tableau-stocks',
        largeur: 800,
        colonnes: const [
          ('Catégorie', 5),
          ('Valeur Stock', 3),
          ('Sous Seuil', 3),
          ('Actions', 2),
        ],
        vide: '— Aucun produit au catalogue —',
        lignes: _filtrees(d.stocks),
        lectureSeule: true,
      ),
      const SizedBox(height: AgriSpacing.md),
      _mentionPoste(
        "La valorisation retient le prix minimum et ignore les quantités "
        "négatives — celles-ci signalent une entrée non saisie, pas une dette "
        "de marchandise.",
      ),
    ],
  );

  // ── Édition ───────────────────────────────────────────────────────────────

  /// Le document de l'onglet actif.
  ///
  /// ⚠️ **CHAQUE RAPPORT A SON PROPRE TITRE ET SON PROPRE SOUS-TITRE**, repris
  /// mot pour mot des six fonctions d'export de la maquette. Un titre générique
  /// « Rapport AgriERP » ferait six documents indiscernables dans un classeur.
  ///
  /// ⚠️ **LA COLONNE « ACTIONS » NE VA PAS AU DOCUMENT**, comme dans la
  /// maquette (`slice(0, 3)` / `slice(0, 4)`) : « Lecture seule » imprimé sur
  /// un état officiel n'a aucun sens.
  DocumentOfficiel documentActif() {
    final d = _donnees!;

    return switch (_onglet) {
      'État de Trésorerie' => DocumentOfficiel(
        titre: 'État de Trésorerie',
        sousTitre: 'Évolution des soldes Caisse et Banque',
        entetes: const ['Date', 'Solde Caisse', 'Solde Banque', 'Solde Total'],
        lignes: [
          DonneesDocument([
            d.tresorerie.releveLe == null
                ? '—'
                : RapportsRepository.date(d.tresorerie.releveLe!),
            d.tresorerie.caisse == null
                ? '—'
                : RapportsRepository.montant(d.tresorerie.caisse!),
            d.tresorerie.banque == null
                ? '—'
                : RapportsRepository.montant(d.tresorerie.banque!),
            d.tresorerie.total == null
                ? '—'
                : RapportsRepository.montant(d.tresorerie.total!),
          ]),
        ],
        noteDePied:
            'Position au dernier tirage. La série journalière des soldes est '
            'tenue sur la surface web, seule à détenir toutes les écritures.',
      ),

      'Créances Clients' => DocumentOfficiel(
        titre: 'Rapport des Créances Clients',
        sousTitre: 'Synthèse des sommes dues par les clients',
        entetes: const ['Client', 'Montant Dû', 'Échéance'],
        lignes: [
          for (final l in _filtrees(d.creances)) DonneesDocument(l.cellules),
        ],
      ),

      'Dettes Fournisseurs' => DocumentOfficiel(
        titre: 'Rapport des Dettes Fournisseurs',
        sousTitre: 'Synthèse des sommes dues aux fournisseurs',
        entetes: const ['Fournisseur', 'Montant Dû', 'Échéance'],
        lignes: [
          for (final l in _filtrees(d.dettes)) DonneesDocument(l.cellules),
        ],
      ),

      'Rapport Élevage' => DocumentOfficiel(
        titre: 'Rapport Élevage — Synthèse Détaillée',
        sousTitre: 'Recensement, mouvements et suivi de ponte',
        lignes: [
          const BandeDocument('TABLEAU 1 — RECENSEMENT HEBDOMADAIRE'),
          const EnteteDocument([
            'Date',
            'Lot',
            'M.Pond.',
            'M.Couv.',
            'M.Élev.',
            'Pouss.SM',
            'Sevrés M',
            'Sevrés F',
            'Morts M',
            'Morts F',
            'Morts SM',
            'Génit.',
            'Malades',
          ]),
          for (final l in d.elevageT1) DonneesDocument(l.cellules),
          const BandeDocument('TABLEAU 2 — MOUVEMENTS, TRAITEMENTS & VENTES'),
          const EnteteDocument([
            'Date',
            'Lot',
            'Sexe',
            'Qté',
            'Montant',
            'Eff.Final',
            'Traitement',
            'Dose',
            'Signes Maladie',
          ]),
          for (final l in d.elevageT2) DonneesDocument(l.cellules),
          const BandeDocument(
            "TABLEAU 3 — SUIVI INTÉGRAL DE LA PONTE & STOCK D'ŒUFS",
          ),
          const EnteteDocument([
            'Âge',
            'Jour',
            'OR',
            'Ponte%',
            'OF',
            'Comm.',
            'SRH',
            'TS',
            'OS',
            'Stock Final',
          ]),
          for (final l in d.elevageT3) DonneesDocument(l.cellules),
        ],
        noteDePied:
            "Journées saisies sur ce poste. Les colonnes en tiret ne font pas "
            "partie de la charge utile d'envoi des fiches.",
      ),

      'Rapport de Stocks' => DocumentOfficiel(
        titre: 'Rapport de Synthèse des Stocks',
        sousTitre: 'Valorisation et alertes de seuil par catégorie',
        entetes: const ['Catégorie', 'Valeur Stock', 'Sous Seuil'],
        lignes: [
          for (final l in _filtrees(d.stocks)) DonneesDocument(l.cellules),
        ],
      ),

      _ => DocumentOfficiel(
        titre: 'État des Recettes et Dépenses',
        sousTitre: 'Synthèse financière de la période',
        lignes: [
          const BandeDocument('RECETTES'),
          const EnteteDocument(['Date', 'Libellé', 'Montant']),
          for (final l in d.recettes) DonneesDocument(l.cellules),
          const BandeDocument('DÉPENSES'),
          const EnteteDocument(['Date', 'Libellé', 'Montant']),
          for (final l in d.depenses) DonneesDocument(l.cellules),
          TotalDocument([
            'Total Recettes',
            '',
            RapportsRepository.montant(d.totalRecettes),
          ], premiere: true),
          TotalDocument([
            'Total Dépenses',
            '',
            RapportsRepository.montant(d.totalDepenses),
          ]),
          TotalDocument([
            'Solde Net',
            '',
            RapportsRepository.montant(d.soldeNet),
          ]),
        ],
      ),
    };
  }

  Future<void> _exporterPdf() async {
    final editeur = widget.imprimer;
    if (editeur == null) return;

    final message = await editeur(documentActif(), _maintenant);
    _annoncer(message ?? 'Rapport envoyé à l’impression.');
  }

  Future<void> _exporterTableur() async {
    final editeur = widget.enregistrer;
    if (editeur == null) return;

    final chemin = await editeur(documentActif(), _maintenant);
    // ⚠️ **LE CHEMIN EST ANNONCÉ.** Un fichier écrit sans le dire est un
    // fichier introuvable, et l'utilisateur conclut que le bouton ne marche
    // pas.
    _annoncer(
      chemin == null ? 'Classeur enregistré.' : 'Classeur enregistré : $chemin',
    );
  }

  void _annoncer(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: AgriTypography.xs),
        ),
        backgroundColor: AgriColors.brandEmerald,
      ),
    );
  }

  // ── Modale « Filtrer la Période » ─────────────────────────────────────────

  /// ⚠️ **LE FORMAT EST UN CHOIX DE LA MAQUETTE, PAS UN DÉCOR.** Son formulaire
  /// impose « Du », « Au » et « Format » ; « Générer » édite en PDF ou en
  /// classeur selon ce choix. Le champ « Lot / Souche » y est facultatif.
  Future<void> _ouvrirFiltrePeriode() async {
    var du = _du;
    var au = _au;
    String? format;
    String? erreur;

    // ⚠️ `modal-create-rapport-elevage-synth` de `rapport-elevage-synth.html`
    // l.348 : panneau `max-w-lg`, barre de titre avec ✕, pied séparé par un
    // filet, boutons « Annuler » puis « Générer ».
    final choix = await afficherModale<String>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: 'Filtrer la Période',
          largeur: LargeurModale.lg,
          contenu: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _etiquette('Période — Du *'),
              _champDate('exp-elevage-du', du, (v) => rafraichir(() => du = v)),
              const SizedBox(height: AgriSpacing.md),
              _etiquette('Période — Au *'),
              _champDate('exp-elevage-au', au, (v) => rafraichir(() => au = v)),
              const SizedBox(height: AgriSpacing.md),
              // ⚠️ « Lot / Souche » de la maquette n'est PAS repris : ses deux
              // options sont figées sur les bandes de démonstration, et le
              // rapport porte déjà toutes les bandes du poste avec leur code
              // en colonne. Un filtre à options inventées vaudrait moins que
              // pas de filtre du tout.
              _etiquette('Format *'),
              DropdownButtonFormField<String>(
                key: const Key('exp-elevage-format'),
                initialValue: format,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '-- Sélectionner --',
                ),
                style: const TextStyle(
                  fontSize: AgriTypography.sm,
                  color: AgriColors.onSurface,
                ),
                items: const [
                  DropdownMenuItem(value: 'PDF', child: Text('PDF')),
                  DropdownMenuItem(
                    value: 'Excel (CSV)',
                    child: Text('Excel (CSV)'),
                  ),
                ],
                onChanged: (v) => rafraichir(() => format = v),
              ),
              if (erreur != null)
                Padding(
                  padding: const EdgeInsets.only(top: AgriSpacing.sm),
                  child: Text(
                    erreur!,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.errorDeep,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(),
            ),
            BoutonModalePrimaire(
              key: const Key('exp-elevage-generer'),
              libelle: 'Générer',
              onPressed: () {
                if (format == null) {
                  rafraichir(
                    () => erreur = 'Le champ « Format » est obligatoire.',
                  );
                  return;
                }
                Navigator.of(context).pop(format);
              },
            ),
          ],
        ),
      ),
    );

    if (choix == null || !mounted) return;

    setState(() {
      _du = du;
      _au = au;
      _onglet = 'Rapport Élevage';
    });
    await _charger();

    if (choix == 'PDF') {
      await _exporterPdf();
    } else {
      await _exporterTableur();
    }
  }

  Widget _etiquette(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
    child: Text(
      texte,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: AgriTypography.gras,
        letterSpacing: 0.8,
        color: AgriColors.brandForest,
      ),
    ),
  );

  // ── Blocs partagés ────────────────────────────────────────────────────────

  /// En-tête d'un rapport : son titre, sa légende, et SA PROPRE paire de
  /// boutons — celle que la maquette montre à l'intérieur de l'iframe.
  Widget _enteteRapport(
    String titre,
    String legende,
    IconData icone,
    bool large, {
    Widget? actionSupplementaire,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 26, color: AgriColors.brandEmerald),
          const SizedBox(width: AgriSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre,
                  style: TextStyle(
                    fontSize: large ? AgriTypography.xl : AgriTypography.lg,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.onSurface,
                  ),
                ),
                const SizedBox(height: AgriSpacing.xs),
                Text(
                  legende,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    color: AgriColors.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: AgriSpacing.sm),
      Wrap(
        spacing: AgriSpacing.xs,
        runSpacing: AgriSpacing.xs,
        children: [
          ?actionSupplementaire,
          _boutonExport(
            cle: 'rapport-export-pdf',
            libelle: 'PDF',
            icone: SymbolesAgri.picture_as_pdf,
            plein: false,
            surAppui: _exporterPdf,
          ),
          _boutonExport(
            cle: 'rapport-export-excel',
            libelle: 'Excel',
            icone: SymbolesAgri.upload,
            plein: true,
            surAppui: _exporterTableur,
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(top: AgriSpacing.sm),
        child: Divider(height: 1, color: AgriColors.outlineVariant),
      ),
    ],
  );

  Widget _sousTitre(String texte, Color couleur) => Text(
    texte,
    style: TextStyle(
      fontSize: AgriTypography.sm,
      fontWeight: AgriTypography.gras,
      color: couleur,
    ),
  );

  Widget _grilleKpi(
    bool large,
    List<(String, IconData?, Color)> definitions,
    List<String> valeurs, {
    List<Color>? couleurValeur,
  }) => Wrap(
    spacing: AgriSpacing.md,
    runSpacing: AgriSpacing.md,
    children: [
      for (var i = 0; i < definitions.length; i++)
        SizedBox(
          width: large ? 260 : 200,
          child: CarteKpi(
            key: Key('kpi-${definitions[i].$1}'),
            libelle: definitions[i].$1,
            valeur: valeurs[i],
            couleurLisere: definitions[i].$3,
            icone: definitions[i].$2,
            couleurIcone: definitions[i].$3,
            couleurValeur: couleurValeur?[i] ?? AgriColors.onSurface,
          ),
        ),
    ],
  );

  Widget _champRecherche(String cle, String invite) => SizedBox(
    width: 320,
    child: TextField(
      key: Key('recherche-$cle'),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(SymbolesAgri.search, size: 18),
        hintText: invite,
        hintStyle: const TextStyle(fontSize: AgriTypography.xs),
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: AgriTypography.xs),
      onChanged: (v) => setState(() => _recherche = v),
    ),
  );

  List<LigneRapport> _filtrees(List<LigneRapport> lignes) {
    final terme = _recherche.trim().toLowerCase();
    if (terme.isEmpty) return lignes;

    return lignes
        .where((l) => l.cellules.any((c) => c.toLowerCase().contains(terme)))
        .toList();
  }

  Widget _tableau({
    required String cle,
    required double largeur,
    required List<(String, int)> colonnes,
    required List<LigneRapport> lignes,
    required String vide,
    bool lectureSeule = false,
    Color? couleurDerniere,
  }) => Container(
    key: Key(cle),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: largeur,
        child: Column(
          children: [
            Container(
              color: AgriColors.surfaceZebra,
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
              child: Row(
                children: [
                  for (final (libelle, flex) in colonnes)
                    Expanded(
                      flex: flex,
                      child: Text(
                        libelle.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: AgriTypography.gras,
                          letterSpacing: 0.8,
                          color: AgriColors.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  vide,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            for (var i = 0; i < lignes.length; i++)
              Container(
                key: Key('$cle-ligne-$i'),
                color: i.isOdd
                    ? AgriColors.surfaceZebra
                    : AgriColors.surfaceCard,
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                child: Row(
                  children: [
                    for (var c = 0; c < colonnes.length; c++)
                      Expanded(
                        flex: colonnes[c].$2,
                        child: _cellule(
                          lignes[i].cellules,
                          c,
                          colonnes.length,
                          lectureSeule,
                          couleurDerniere,
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

  /// ⚠️ **« Lecture seule » EST LE CONTENU DE LA COLONNE ACTIONS**, exactement
  /// comme dans la maquette — et non un bouton grisé. Ces états sont produits
  /// à partir de données réelles ; il n'y a rien à y modifier, ici ou ailleurs.
  Widget _cellule(
    List<String> cellules,
    int index,
    int nombreDeColonnes,
    bool lectureSeule,
    Color? couleurDerniere,
  ) {
    if (lectureSeule && index == nombreDeColonnes - 1) {
      return const Text(
        'Lecture seule',
        style: TextStyle(
          fontSize: 10,
          fontStyle: FontStyle.italic,
          color: AgriColors.outline,
        ),
      );
    }

    final texte = index < cellules.length ? cellules[index] : '';
    final derniere = couleurDerniere != null && index == cellules.length - 1;

    return Text(
      texte,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: derniere ? AgriTypography.gras : AgriTypography.normal,
        color: derniere ? couleurDerniere : AgriColors.onSurface,
      ),
    );
  }

  Widget _mentionPoste(String texte) => Container(
    key: const Key('mention-poste'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.accentYellow.withValues(alpha: 0.10),
      border: Border.all(
        color: AgriColors.accentYellow.withValues(alpha: 0.30),
      ),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(SymbolesAgri.info, size: 18, color: AgriColors.brandForest),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Text(
            texte,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Éditeurs réels, posés par [main].
///
/// ⚠️ **ISOLÉS DE L'ÉCRAN, ET C'EST CE QUI REND L'ÉCRAN VÉRIFIABLE.** Un test
/// injecte ses propres [Editeur] et contrôle le DOCUMENT produit — titre,
/// sous-titre, colonnes, totaux — sans imprimante, sans disque et sans greffon
/// natif.
class EditeursRapports {
  const EditeursRapports._();

  /// ⚠️ **LA BOÎTE D'IMPRESSION DE WINDOWS, PAS UN FICHIER ÉCRIT D'AUTORITÉ.**
  /// Elle offre aussi « Enregistrer au format PDF » : l'utilisateur choisit
  /// son imprimante ou son dossier. Écrire nous-mêmes déciderait à sa place,
  /// et un rapport doit souvent partir directement sur papier.
  static Future<String?> imprimer(
    DocumentOfficiel document,
    DateTime maintenant,
  ) async {
    final logo = await ExportOfficiel.chargerLogo();
    final polices = await ExportOfficiel.chargerPolices();
    final octets = await ExportOfficiel.construire(
      document,
      maintenant: maintenant,
      logo: logo,
      polices: polices,
    );

    await Printing.layoutPdf(
      onLayout: (_) => octets,
      name: ExportTableur.nomFichier(document.titre, maintenant),
    );
    return null;
  }

  static Future<String?> enregistrer(
    DocumentOfficiel document,
    DateTime maintenant,
  ) => ExportTableur.enregistrer(document, maintenant: maintenant);
}
