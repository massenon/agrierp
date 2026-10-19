import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/export/document_officiel.dart';
import '../../core/export/export_tableur.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/toast_agri.dart';
import '../stocks/pmp_service.dart';
import 'rapports_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// Signature de l'éditeur PDF, injectable — un test ne lance pas d'imprimante.
typedef Editeur =
    Future<String?> Function(DocumentOfficiel document, DateTime maintenant);

/// Ticket U12b — signature de l'éditeur du classeur (le contenu du CSV du web), injectable — un test n'écrit rien.
typedef EditeurClasseur =
    Future<String?> Function(ClasseurRapport classeur, DateTime maintenant);

/// Hub « Rapports & Exports » — `RapportsExportsHub` (web) et ses six composants (`app/Livewire/Rapports/`).
///
/// ⚠️⚠️ **HUB À SIX ONGLETS**, dans l'ordre du hub web : Recettes et Dépenses · État de Trésorerie · Créances
/// Clients · Dettes Fournisseurs · Rapport Élevage · Rapport de Stocks.
///
/// 🔴→✅ **Ticket U12b — LE BLADE FAIT FOI POUR LES SIX ONGLETS** (doctrine, article 5). Comme au web
/// (`rapports-exports-hub.blade.php`), la période (Du … au …) et l'export (« Exporter PDF », « Exporter Excel »)
/// vivent UNIQUEMENT dans la barre du hub, et ciblent l'onglet affiché (`exportPdf()` → `exportReport()` de
/// l'enfant) ; aucun onglet ne porte plus l'en-tête de la maquette (titre, légende, paire « PDF » / « Excel »).
/// Chaque onglet reprend sa vue Blade : mêmes cartes, mêmes tableaux (colonnes, cellules), mêmes états vides,
/// même recherche là où le web en a une (Dettes, Stocks), mêmes calculs (`rapports_parite_test.dart`).
///
/// ⚠️ **DROIT `export-rapports`** : le web masque les deux boutons d'export sans lui (`@can('export-rapports')`) et
/// le refuse dans chaque `exportReport()` (`$this->authorize`). Le poste fait de même ([peutExporter], transposé du
/// seeder par `PermissionsPoste.peut`).
///
/// ⚠️ **CHANGER LA PÉRIODE REMET L'ONGLET À ZÉRO**, comme au web : chaque enfant est clé par la période
/// (`:key="'dt-'.$startDate.$endDate"`), donc recréé — recherche vidée, filtre « Lot / Souche » sur « Tous »,
/// premier tableau d'élevage.
///
/// ⚠️ **QUATRE PAGES `rapport-*.html` NE SONT PAS DANS CE HUB** et ne sont donc pas portées ici :
/// `rapport-bilan.html` et `rapport-mensuel.html` s'ouvrent depuis la comptabilité et le tableau de bord ;
/// `rapport-recettes.html` et `rapport-depenses.html` sont des orphelines de la maquette.
class RapportsExportsScreen extends StatefulWidget {
  const RapportsExportsScreen({
    super.key,
    required this.depot,
    required this.peutExporter,
    this.imprimer,
    this.enregistrer,
    this.maintenant,
  });

  final RapportsRepository depot;

  /// `@can('export-rapports')` du web, pour le rôle de la session (`PermissionsPoste.peut`).
  final bool peutExporter;

  /// Éditeurs injectables. En production ils sont posés par [main]; en test
  /// ils enregistrent l'appel sans toucher au système.
  final Editeur? imprimer;
  final EditeurClasseur? enregistrer;

  /// Horloge injectable — un document daté par `DateTime.now()` ne serait
  /// comparable d'aucune exécution à l'autre.
  final DateTime Function()? maintenant;

  /// Les six onglets du hub web, dans son ordre, avec leur icône (`text-[16px]`).
  static const onglets = <(String, IconData)>[
    ('Recettes et Dépenses', SymbolesAgri.payments),
    ('État de Trésorerie', SymbolesAgri.account_balance_wallet),
    ('Créances Clients', SymbolesAgri.request_quote),
    ('Dettes Fournisseurs', SymbolesAgri.local_shipping),
    ('Rapport Élevage', SymbolesAgri.pets),
    ('Rapport de Stocks', SymbolesAgri.inventory_2),
  ];

  /// Les trois tableaux du rapport d'élevage, dans l'ordre de ses pilules — libellés du BLADE
  /// (`elevage-synth.blade.php`, ticket U10), et non plus ceux de la maquette (« Recensement Hebdomadaire »,
  /// « Suivi Intégral de la Ponte »).
  static const tableauxElevage = <String>[
    'Tableau 1 : Recensement',
    'Tableau 2 : Mouvements, Traitements & Ventes',
    'Tableau 3 : Suivi de la Ponte',
  ];

  /// Info-bulle de « Lecture seule » de l'État de Trésorerie (`title` du Blade).
  static const bulleEcritures =
      'Ce rapport est généré à partir des écritures comptables réelles ; il ne peut pas être modifié ici.';

  /// Info-bulle de « Lecture seule » des Créances, Dettes et Stocks (`title` du Blade).
  static const bulleDonnees =
      'Ce rapport est généré à partir des données réelles ; il ne peut pas être modifié ici.';

  @override
  State<RapportsExportsScreen> createState() => _RapportsExportsScreenState();
}

class _RapportsExportsScreenState extends State<RapportsExportsScreen> {
  String _onglet = RapportsExportsScreen.onglets.first.$1;
  String _tableauElevage = RapportsExportsScreen.tableauxElevage.first;

  /// Recherche des onglets Dettes et Stocks (`$search` de leur composant).
  final _recherche = TextEditingController();

  /// Ticket U10 — filtre « Lot / Souche » du Rapport Élevage (`$lotFilter` du web) : identifiant de bande, vide =
  /// toutes.
  String _lotElevage = '';

  late DateTime _du;
  late DateTime _au;

  DonneesRapports? _donnees;

  DateTime get _maintenant => (widget.maintenant ?? HeureBenin.maintenant)();

  @override
  void initState() {
    super.initState();

    // `RapportsExportsHub::mount()` : du 1er au DERNIER jour du mois en cours (ticket U11), à l'heure du Bénin.
    final aujourdHui = _maintenant;
    _du = DateTime(aujourdHui.year, aujourdHui.month, 1);
    _au = DateTime(aujourdHui.year, aujourdHui.month + 1, 0);

    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger(
      du: _du,
      au: _au,
      lot: _lotElevage,
    );
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  /// La période change : chaque enfant du web est recréé (`:key` porte la période) — recherche, filtre de bande et
  /// tableau d'élevage reviennent à leur état initial.
  void _changerPeriode({DateTime? du, DateTime? au}) {
    setState(() {
      _du = du ?? _du;
      _au = au ?? _au;
      _recherche.clear();
      _lotElevage = '';
      _tableauElevage = RapportsExportsScreen.tableauxElevage.first;
    });
    _charger();
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
                      const SizedBox(height: AgriSpacing.lg),
                      _barreFiltre(),
                      const SizedBox(height: AgriSpacing.lg),
                      _barreOnglets(),
                      const SizedBox(height: AgriSpacing.lg),
                      switch (_onglet) {
                        'État de Trésorerie' => _ongletTresorerie(d),
                        'Créances Clients' => _ongletCreances(d),
                        'Dettes Fournisseurs' => _ongletDettes(d),
                        'Rapport Élevage' => _ongletElevage(d, large),
                        'Rapport de Stocks' => _ongletStocks(d),
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

  /// 🔴→✅ Ticket U11 — en-tête de `rapports-exports-hub.blade.php` : icône `bar_chart`, titre « Rapports & Exports »,
  /// sous-titre du web, filet bas (`border-b pb-md mb-lg`).
  Widget _enteteHub(bool large) => Container(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(SymbolesAgri.bar_chart, size: 26, color: AgriColors.brandEmerald),
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
          'États financiers et opérationnels de la Ferme École OLOUWACHEGOUN.',
          key: Key('hub-sous-titre'),
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    ),
  );

  /// Barre de filtre du hub web (`bg-white border rounded-lg p-md mb-lg`) : « Du » « au » « Au », puis, à droite
  /// (`ml-auto`), « Exporter PDF » et « Exporter Excel » — 🔴→✅ ticket U12b : sous `@can('export-rapports')`.
  Widget _barreFiltre() => Container(
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Wrap(
      spacing: AgriSpacing.sm,
      runSpacing: AgriSpacing.sm,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Wrap(
          spacing: AgriSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _champDate('hub-filter-du', _du, (v) => _changerPeriode(du: v)),
            const Text(
              'au',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
            _champDate('hub-filter-au', _au, (v) => _changerPeriode(au: v)),
          ],
        ),
        if (widget.peutExporter)
          Wrap(
            spacing: AgriSpacing.xs,
            children: [
              _boutonHub(
                cle: 'hub-export-pdf',
                libelle: 'Exporter PDF',
                icone: SymbolesAgri.picture_as_pdf,
                surAppui: _exporterPdf,
              ),
              _boutonHub(
                cle: 'hub-export-excel',
                libelle: 'Exporter Excel',
                icone: SymbolesAgri.table_view,
                surAppui: _exporterTableur,
              ),
            ],
          ),
      ],
    ),
  );

  /// Bouton d'export du hub web : `border border-outline-variant text-brand-forest font-bold text-xs px-md py-sm
  /// rounded-full`, icône 18 px.
  Widget _boutonHub({
    required String cle,
    required String libelle,
    required IconData icone,
    required VoidCallback surAppui,
  }) => OutlinedButton.icon(
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
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.md,
        vertical: AgriSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
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

  /// Barre d'onglets du hub web : `px-md py-2.5 text-xs font-bold border-b-2`, icône 16 px ; actif émeraude.
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
                // Changer d'onglet monte un AUTRE composant au web : sa recherche part vide.
                _recherche.clear();
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
                      size: 16,
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

  /// 🔴→✅ Ticket U12b — `recettes-depenses.blade.php` : trois cartes (`grid-cols-1 sm:grid-cols-3 gap-md mb-lg`,
  /// valeurs `number_format(…, 0, ',', ' ').' F'`, sans couleur de signe), puis les deux tableaux côte à côte
  /// (`grid-cols-1 lg:grid-cols-2 gap-md`), chacun dans sa carte à bandeau titré.
  Widget _ongletRecettesDepenses(DonneesRapports d, bool large) {
    final recettes = _carteMouvements(
      cle: 'tableau-recettes',
      titre: 'Recettes',
      fond: AgriColors.brandEmerald.withValues(alpha: 0.05),
      encre: AgriColors.brandEmerald,
      colonnes: const [('Date', 3), ('Libellé', 7), ('Montant', 4)],
      lignes: [for (final r in d.recettes) RapportsRepository.celluleRecette(r)],
      vide: 'Aucune recette sur la période.',
    );
    final depenses = _carteMouvements(
      cle: 'tableau-depenses',
      titre: 'Dépenses',
      fond: AgriColors.errorBg,
      encre: AgriColors.errorDeep,
      colonnes: const [('Date', 3), ('Libellé', 7), ('Montant', 4)],
      lignes: [for (final m in d.depenses) RapportsRepository.celluleDepense(m)],
      vide: 'Aucune dépense sur la période.',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, contraintes) {
            final colonnes = AgriBreakpoints.petit(context) ? 3 : 1;
            final largeur =
                (contraintes.maxWidth - (colonnes - 1) * AgriSpacing.md) /
                colonnes;
            Widget carte(String libelle, IconData icone, Color couleur, double valeur) => SizedBox(
              width: largeur,
              child: CarteKpi(
                key: Key('kpi-$libelle'),
                libelle: libelle,
                valeur: '${PmpService.francs(valeur)} F',
                couleurLisere: couleur,
                icone: icone,
                couleurIcone: couleur,
              ),
            );
            return Wrap(
              spacing: AgriSpacing.md,
              runSpacing: AgriSpacing.md,
              children: [
                carte('Total Recettes', SymbolesAgri.trending_up, AgriColors.brandEmerald, d.totalRecettes),
                carte('Total Dépenses', SymbolesAgri.trending_down, AgriColors.errorRed, d.totalDepenses),
                carte('Solde Net', SymbolesAgri.account_balance_wallet, AgriColors.infoBlue, d.soldeNet),
              ],
            );
          },
        ),
        const SizedBox(height: AgriSpacing.lg),
        if (large)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: recettes),
              const SizedBox(width: AgriSpacing.md),
              Expanded(child: depenses),
            ],
          )
        else ...[
          recettes,
          const SizedBox(height: AgriSpacing.md),
          depenses,
        ],
        const SizedBox(height: AgriSpacing.md),
        // ⚠️ ÉCART (plateforme) — la paie et les dépenses saisies ailleurs ne descendent pas au poste : le calcul est
        // celui du web, sa matière celle que le poste détient ; le dire vaut mieux qu'un total muet.
        _mentionPoste(
          'Dépenses : ce poste détient les achats de la ferme et les dépenses saisies sur CE poste. La paie et les '
          'dépenses saisies sur le web ou sur un autre poste ne descendent pas encore : le total complet se lit sur '
          'le web.',
        ),
      ],
    );
  }

  /// Carte d'un des deux tableaux : bandeau `px-md py-sm border-b` (titre `text-sm font-bold`), puis le tableau
  /// `w-full text-xs` — en-têtes en gras gris (`text-outline`, sans fond ni capitales), montant aligné à droite, en
  /// gras et coloré ; état vide centré.
  Widget _carteMouvements({
    required String cle,
    required String titre,
    required Color fond,
    required Color encre,
    required List<(String, int)> colonnes,
    required List<List<String>> lignes,
    required String vide,
  }) {
    Widget cellule(String texte, int flex, {bool montant = false}) => Expanded(
      flex: flex,
      child: Text(
        texte,
        textAlign: montant ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: AgriTypography.xs,
          fontWeight: montant ? AgriTypography.gras : AgriTypography.normal,
          color: montant ? encre : AgriColors.onSurface,
        ),
      ),
    );

    return Container(
      key: Key(cle),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AgriSpacing.md,
              vertical: AgriSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: fond,
              border: const Border(
                bottom: BorderSide(color: AgriColors.outlineVariant),
              ),
            ),
            child: Text(
              titre,
              style: TextStyle(
                fontSize: AgriTypography.sm,
                fontWeight: AgriTypography.gras,
                color: encre,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AgriSpacing.md,
              vertical: AgriSpacing.sm,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AgriColors.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                for (var c = 0; c < colonnes.length; c++)
                  Expanded(
                    flex: colonnes[c].$2,
                    child: Text(
                      colonnes[c].$1,
                      textAlign: c == colonnes.length - 1
                          ? TextAlign.right
                          : TextAlign.left,
                      style: const TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: AgriTypography.gras,
                        color: AgriColors.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (lignes.isEmpty)
            _ligneVide(vide)
          else
            for (var i = 0; i < lignes.length; i++)
              Container(
                key: Key('$cle-ligne-$i'),
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: i.isOdd
                      ? AgriColors.surfaceZebra
                      : AgriColors.surfaceCard,
                  border: const Border(
                    bottom: BorderSide(color: AgriColors.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    cellule(lignes[i][0], colonnes[0].$2),
                    cellule(lignes[i][1], colonnes[1].$2),
                    cellule(lignes[i][2], colonnes[2].$2, montant: true),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  // ── Onglet 2 : État de Trésorerie ─────────────────────────────────────────

  /// 🔴→✅ Ticket U12b — `tresorerie.blade.php` : une ligne par jour de la période où la trésorerie a bougé, soldes
  /// CUMULÉS du grand livre (Caisse = 531…, Banque = autres comptes de classe 5), « Solde Total » en gras, « Lecture
  /// seule » ; ni recherche ni carte. Le poste montrait une ligne unique, le solde du dernier tirage.
  Widget _ongletTresorerie(DonneesRapports d) => _carteTableau(
    cle: 'tableau-tresorerie',
    colonnes: const [
      ('Date', 3),
      ('Solde Caisse', 3),
      ('Solde Banque', 3),
      ('Solde Total', 3),
      ('Actions', 2),
    ],
    vide: 'Aucun mouvement de trésorerie sur la période.',
    lignes: [
      for (final s in d.tresorerie)
        () {
          final c = RapportsRepository.celluleTresorerie(s);
          return [
            _texte(c[0]),
            _texte(c[1]),
            _texte(c[2]),
            _texte(c[3], gras: true),
            _lectureSeule(RapportsExportsScreen.bulleEcritures),
          ];
        }(),
    ],
  );

  // ── Onglets 3 et 4 : Créances et Dettes ───────────────────────────────────

  /// 🔴→✅ Ticket U12b — `creances.blade.php` : créances ouvertes dont l'échéance tombe dans la période, reste dû en
  /// gras (`number_format`), sans recherche (le Blade n'en a pas, à la différence des Dettes).
  Widget _ongletCreances(DonneesRapports d) => _carteTableau(
    cle: 'tableau-creances',
    colonnes: const [
      ('Client', 5),
      ('Montant Dû', 3),
      ('Échéance', 3),
      ('Actions', 2),
    ],
    vide: 'Aucune créance sur la période.',
    lignes: [
      for (final e in d.creances) _ligneEcheance(e),
    ],
  );

  /// 🔴→✅ Ticket U12b — `dettes.blade.php` : la même grille, avec la recherche du Blade (nom du fournisseur).
  Widget _ongletDettes(DonneesRapports d) => _carteTableau(
    cle: 'tableau-dettes',
    recherche: 'dettes',
    colonnes: const [
      ('Fournisseur', 5),
      ('Montant Dû', 3),
      ('Échéance', 3),
      ('Actions', 2),
    ],
    vide: 'Aucune dette sur la période.',
    lignes: [
      for (final e in RapportsRepository.filtrerDettes(d.dettes, _recherche.text))
        _ligneEcheance(e),
    ],
  );

  List<Widget> _ligneEcheance(EcheanceRapport e) {
    final c = RapportsRepository.celluleEcheance(e);
    return [
      _texte(c[0]),
      _texte(c[1], gras: true),
      _texte(c[2]),
      _lectureSeule(RapportsExportsScreen.bulleDonnees),
    ];
  }

  // ── Onglet 5 : Rapport Élevage ────────────────────────────────────────────

  /// 🔴→✅ Ticket U11 — l'onglet du BLADE (`elevage-synth.blade.php`), sans l'en-tête de la maquette : ni titre
  /// « Rapport Élevage — Synthèse Détaillée », ni bouton « Filtrer la Période » et sa modale (Du / Au / Format,
  /// « Générer »), ni paire PDF / Excel propre à l'onglet. Au web, la période se règle dans la barre du hub (Du … au …)
  /// et l'export par ses boutons « Exporter PDF » / « Exporter Excel » ; l'onglet commence par son filtre
  /// « Lot / Souche » (`mt-md`, puis `mb-md`).
  Widget _ongletElevage(DonneesRapports d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // 🔴→✅ Ticket U10 — le filtre « Lot / Souche » du Blade, au-dessus des indicateurs : « Lot / Souche : Tous »
      // puis les bandes ACTIVES par code ; il s'applique aux indicateurs et aux trois tableaux.
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: const Key('elevage-lot'),
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: d.bandesElevage.any((b) => b.id == _lotElevage)
                  ? _lotElevage
                  : '',
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.onSurface,
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Lot / Souche : Tous'),
                ),
                for (final b in d.bandesElevage)
                  DropdownMenuItem(value: b.id, child: Text(b.code)),
              ],
              onChanged: (v) {
                setState(() => _lotElevage = v ?? '');
                _charger();
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: AgriSpacing.md),
      // 🔴→✅ Ticket U10 — valeurs du Blade : `number_format(production, 0, ',', ' ')`, `taux.' %'` (flottant PHP)
      // ou « — », `number_format(CA, 0, ',', ' ')` puis « FCFA » (toujours un montant).
      // Ticket U11 — grille du Blade (`grid-cols-2 md:grid-cols-4 gap-md mb-md`) : les quatre cartes se partagent la
      // largeur, sans icône ; « FCFA » en petite unité après le montant, comme le `<span class="text-xs">` du web.
      LayoutBuilder(
        builder: (context, contraintes) {
          final colonnes = AgriBreakpoints.moyen(context) ? 4 : 2;
          final largeur =
              (contraintes.maxWidth - (colonnes - 1) * AgriSpacing.md) /
              colonnes;
          Widget carte(String libelle, Color lisere, String valeur, {String? unite}) => SizedBox(
            width: largeur,
            child: CarteKpi(
              key: Key('kpi-$libelle'),
              libelle: libelle,
              valeur: valeur,
              unite: unite,
              couleurLisere: lisere,
            ),
          );
          return Wrap(
            spacing: AgriSpacing.md,
            runSpacing: AgriSpacing.md,
            children: [
              carte(
                'Production Totale (Œufs)',
                AgriColors.brandEmerald,
                PmpService.francs(d.indicateurs.productionTotale.toDouble()),
              ),
              carte(
                'Taux de Ponte Moyen',
                AgriColors.infoBlue,
                IndicateursElevage.taux(d.indicateurs.tauxPonteMoyen),
              ),
              carte(
                'Taux de Mortalité Hebdo',
                AgriColors.errorRed,
                IndicateursElevage.taux(d.indicateurs.mortaliteHebdo),
              ),
              carte(
                'CA Ventes du Lot',
                AgriColors.accentYellow,
                PmpService.francs(d.indicateurs.chiffreAffaires),
                unite: 'FCFA',
              ),
            ],
          );
        },
      ),
      const SizedBox(height: AgriSpacing.md),
      _pilulesElevage(),
      const SizedBox(height: AgriSpacing.md),
      switch (_tableauElevage) {
        // 🔴→✅ Ticket U10 — le Tableau 2 du Blade : mêmes neuf colonnes, cellules réelles (sexe, montant,
        // traitement, dose, symptômes descendent depuis U10), formule du pied.
        'Tableau 2 : Mouvements, Traitements & Ventes' => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tableau(
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
              vide: 'Aucune fiche journalière sur la période.',
              lignes: d.elevageT2,
            ),
            const Padding(
              padding: EdgeInsets.only(top: AgriSpacing.sm),
              child: Text(
                'Formules : Recette Ventes (FCFA) = Qté Vendue × Prix Unitaire — '
                'Effectif Final = Effectif Début − (Morts + Ventes + Dons)',
                style: TextStyle(fontSize: 10, color: AgriColors.outline),
              ),
            ),
          ],
        ),
        // 🔴→✅ Ticket U9 — le Tableau 3 du web (`elevage-synth.blade.php`) :
        // onze colonnes dont « Lot », soldes de FERME en plateaux.
        'Tableau 3 : Suivi de la Ponte' => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AgriSpacing.sm),
              // Ticket U11 — « <strong>ferme</strong> » du Blade, en gras.
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text:
                          'Les quatre colonnes de stock (SRH / TS / OS / Stock Final) '
                          'sont des soldes de ',
                    ),
                    TextSpan(
                      text: 'ferme',
                      style: TextStyle(fontWeight: AgriTypography.gras),
                    ),
                    TextSpan(
                      text:
                          ', en plateaux : le stock d\'œufs est '
                          'tenu au niveau du produit, rien ne distingue l\'œuf issu '
                          'd\'une bande de celui issu d\'une autre. Deux bandes '
                          'pondeuses le même jour affichent donc le même solde.',
                    ),
                  ],
                ),
                key: Key('legende-elevage-t3'),
                style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
            ),
            _tableau(
              cle: 'tableau-elevage-t3',
              largeur: 1650,
              colonnes: const [
                ('Âge (Sem.)', 3),
                ('Jour', 3),
                ('Lot', 3),
                ('Total Œufs Récoltés (OR)', 4),
                ('Taux Ponte %', 3),
                ('Cassés/Fêlés (OF)', 3),
                ('Commercialisables (OR-OF)', 4),
                ('Stock Restant Hier (SRH)', 4),
                ('Total Stock (TS)', 3),
                ('Sorties Vente OS (Plateaux)', 4),
                ('Stock Final (Plateaux + Vrac)', 5),
              ],
              vide: 'Aucune ponte enregistrée sur la période.',
              lignes: d.elevageT3,
            ),
            const Padding(
              padding: EdgeInsets.only(top: AgriSpacing.sm),
              child: Text(
                'Formules : Taux de Ponte % = (OR × 100) ÷ Effectif Fin — '
                'Total Stock (TS) = (OR−OF) + SRH — Stock Final = TS − OS',
                // Ticket U11 — `text-[10px]` du Blade, comme les pieds des Tableaux 1 et 2.
                style: TextStyle(fontSize: 10, color: AgriColors.outline),
              ),
            ),
          ],
        ),
        // 🔴→✅ Ticket U10 — le Tableau 1 du Blade : dix colonnes réellement portées par la fiche (la maquette en
        // montrait treize, toutes en tiret au poste), la mention en tête et la formule au pied.
        _ => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AgriSpacing.sm),
              child: Text(
                'Colonnes réellement disponibles depuis les fiches journalières — la ventilation détaillée par '
                'rôle de reproduction (Mères Pondeuses/Couveuses/Éleveuses, Géniteurs) n\'existe pas dans un '
                'schéma commun à toutes les espèces et n\'est pas approximée ici.',
                key: Key('legende-elevage-t1'),
                style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
            ),
            _tableau(
              cle: 'tableau-elevage-t1',
              largeur: 1300,
              colonnes: const [
                ('Date', 3),
                ('Lot / Souche', 4),
                ('Effectif M', 3),
                ('Effectif F', 3),
                ('Sous Mères', 3),
                ('Sevrés', 3),
                ('Achats', 3),
                ('Nés', 3),
                ('Morts', 3),
                ('Effectif Final', 3),
              ],
              vide: 'Aucune fiche journalière sur la période.',
              lignes: d.elevageT1,
            ),
            const Padding(
              padding: EdgeInsets.only(top: AgriSpacing.sm),
              child: Text(
                'Formule : Taux Mortalité Hebdo (%) = (Cumul Morts ÷ Effectif Début) × 100',
                style: TextStyle(fontSize: 10, color: AgriColors.outline),
              ),
            ),
          ],
        ),
      },
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

  /// 🔴→✅ Ticket U12b — `stocks-synth.blade.php` : recherche (libellé de catégorie), Catégorie en gras vert forêt,
  /// Valeur Stock « N FCFA » suivie des deux mentions du Blade (produits en stock négatif retenus à zéro, produits
  /// jamais achetés non valorisés), Sous Seuil en pastille rouge (ou « 0 » gris), « Lecture seule ».
  Widget _ongletStocks(DonneesRapports d) => _carteTableau(
    cle: 'tableau-stocks',
    recherche: 'stocks',
    colonnes: const [
      ('Catégorie', 5),
      ('Valeur Stock', 5),
      ('Sous Seuil', 2),
      ('Actions', 2),
    ],
    vide: 'Aucune catégorie active.',
    lignes: [
      for (final l in RapportsRepository.filtrerStocks(d.stocks, _recherche.text))
        [
          Text(
            l.categorie,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _texte('${PmpService.francs(l.valeur)} FCFA'),
              if (l.negatifs > 0)
                Text(
                  RapportsRepository.mentionNegatifs(l.negatifs),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.errorDeep,
                  ),
                ),
              if (l.nonValorises > 0)
                Text(
                  RapportsRepository.mentionNonValorises(l.nonValorises),
                  style: const TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: l.sousSeuil > 0
                ? Container(
                    key: Key('sous-seuil-${l.categorie}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AgriSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AgriColors.errorBg,
                      border: Border.all(
                        color: AgriColors.errorDeep.withValues(alpha: 0.30),
                      ),
                      borderRadius: BorderRadius.circular(AgriRadius.full),
                    ),
                    child: Text(
                      '${l.sousSeuil}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: AgriTypography.gras,
                        color: AgriColors.errorDeep,
                      ),
                    ),
                  )
                : const Text(
                    '0',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.outline,
                    ),
                  ),
          ),
          _lectureSeule(RapportsExportsScreen.bulleDonnees),
        ],
    ],
  );

  // ── Édition ───────────────────────────────────────────────────────────────

  /// Période du web en sous-titre des PDF : `Carbon::parse($startDate)->format('d/m/Y').' au '.…`.
  String get _periode =>
      '${RapportsRepository.date(_du)} au ${RapportsRepository.date(_au)}';

  /// Le PDF de l'onglet actif — 🔴→✅ ticket U12b : celui du WEB (`exportReport('pdf')` de chaque composant, vue
  /// `resources/views/exports/<rapport>.blade.php`) : son titre, la période (ou « État au … ») en sous-titre, ses
  /// colonnes, ses cellules (montants « N FCFA » des créances, dettes et stocks), sa ligne vide. Le poste éditait
  /// encore les titres et sous-titres de la maquette (« Rapport des Créances Clients », « Synthèse des sommes dues
  /// par les clients »…). La colonne « Actions » ne va pas au document, comme au web.
  DocumentOfficiel documentActif() {
    final d = _donnees!;
    List<LigneDocument> ouVide(List<LigneDocument> lignes, String vide) =>
        lignes.isEmpty ? [DonneesDocument([vide])] : lignes;

    return switch (_onglet) {
      'État de Trésorerie' => DocumentOfficiel(
        titre: 'État de Trésorerie',
        fichier: 'tresorerie-{jour}.pdf',
        sousTitre: _periode,
        entetes: const ['Date', 'Solde Caisse', 'Solde Banque', 'Solde Total'],
        lignes: ouVide([
          for (final s in d.tresorerie)
            DonneesDocument(RapportsRepository.celluleTresorerie(s)),
        ], 'Aucun mouvement de trésorerie sur la période.'),
      ),

      'Créances Clients' => DocumentOfficiel(
        titre: 'État des Créances Clients',
        fichier: 'creances-{jour}.pdf',
        sousTitre: _periode,
        entetes: const ['Client', 'Montant Dû', 'Échéance'],
        lignes: ouVide([
          for (final e in d.creances) DonneesDocument(_celluleEcheancePdf(e)),
        ], 'Aucune créance sur la période.'),
      ),

      'Dettes Fournisseurs' => DocumentOfficiel(
        titre: 'État des Dettes Fournisseurs',
        fichier: 'dettes-{jour}.pdf',
        sousTitre: _periode,
        entetes: const ['Fournisseur', 'Montant Dû', 'Échéance'],
        lignes: ouVide([
          for (final e in RapportsRepository.filtrerDettes(d.dettes, _recherche.text))
            DonneesDocument(_celluleEcheancePdf(e)),
        ], 'Aucune dette sur la période.'),
      ),

      // 🔴→✅ Ticket U10 — le PDF du WEB (`ElevageSynth::exportReport()`, vue `exports.elevage-synth`) : titre,
      // période en sous-titre, trois tableaux et leurs colonnes, mêmes cellules qu'à l'écran (lot filtré compris).
      'Rapport Élevage' => DocumentOfficiel(
        titre: 'Rapport Élevage — Synthèse Détaillée',
        fichier: 'rapport-elevage-{jour}.pdf',
        sousTitre:
            '${RapportsRepository.date(d.du)} au ${RapportsRepository.date(d.au)}',
        lignes: [
          const BandeDocument('Tableau 1 — Recensement'),
          const EnteteDocument([
            'Date',
            'Lot',
            'Eff. M',
            'Eff. F',
            'Sous Mères',
            'Sevrés',
            'Achats',
            'Nés',
            'Morts',
            'Eff. Final',
          ]),
          if (d.elevageT1.isEmpty)
            const DonneesDocument(['Aucune fiche sur la période.']),
          for (final l in d.elevageT1) DonneesDocument(l.cellules),
          const BandeDocument('Tableau 2 — Mouvements, Traitements & Ventes'),
          const EnteteDocument([
            'Date',
            'Lot',
            'Sexe Vendu',
            'Qté',
            'Montant',
            'Traitement',
            'Dose',
            'Signes',
          ]),
          if (d.elevageT2.isEmpty)
            const DonneesDocument(['Aucune fiche sur la période.']),
          // Le PDF du web n'a pas la colonne « Effectif Final » de l'écran.
          for (final l in d.elevageT2)
            DonneesDocument([...l.cellules.take(5), ...l.cellules.skip(6)]),
          const BandeDocument('Tableau 3 — Suivi de la Ponte'),
          const EnteteDocument([
            'Jour',
            'Lot',
            'Œufs Récoltés',
            'Taux Ponte %',
            'Cassés',
            'Commercialisables',
          ]),
          if (d.elevageT3Export.isEmpty)
            const DonneesDocument(['Aucune ponte sur la période.']),
          for (final l in d.elevageT3Export) DonneesDocument(l.cellules),
        ],
      ),

      'Rapport de Stocks' => DocumentOfficiel(
        titre: 'Rapport de Stocks — Synthèse',
        fichier: 'rapport-stocks-{jour}.pdf',
        // `'État au '.now()->format('d/m/Y')` : un état, pas une période.
        sousTitre: 'État au ${RapportsRepository.date(_maintenant)}',
        entetes: const ['Catégorie', 'Valeur Stock', 'Sous Seuil'],
        lignes: ouVide([
          for (final l in RapportsRepository.filtrerStocks(d.stocks, _recherche.text))
            DonneesDocument([
              l.categorie,
              '${PmpService.francs(l.valeur)} FCFA',
              '${l.sousSeuil}',
            ]),
        ], 'Aucune catégorie active.'),
      ),

      // `exports/recettes-depenses.blade.php` : les trois totaux en tête, puis « Recettes » et « Dépenses ».
      _ => DocumentOfficiel(
        titre: 'État des Recettes et Dépenses',
        fichier: 'recettes-depenses-{jour}.pdf',
        sousTitre: _periode,
        lignes: [
          const EnteteDocument(['Total Recettes', 'Total Dépenses', 'Solde Net']),
          DonneesDocument([
            '${PmpService.francs(d.totalRecettes)} FCFA',
            '${PmpService.francs(d.totalDepenses)} FCFA',
            '${PmpService.francs(d.soldeNet)} FCFA',
          ]),
          const BandeDocument('Recettes'),
          const EnteteDocument(['Date', 'Libellé', 'Montant']),
          if (d.recettes.isEmpty)
            const DonneesDocument(['Aucune recette sur la période.']),
          for (final r in d.recettes)
            DonneesDocument(RapportsRepository.celluleRecette(r)),
          const BandeDocument('Dépenses'),
          const EnteteDocument(['Date', 'Libellé', 'Montant']),
          if (d.depenses.isEmpty)
            const DonneesDocument(['Aucune dépense sur la période.']),
          for (final m in d.depenses)
            DonneesDocument(RapportsRepository.celluleDepense(m)),
        ],
      ),
    };
  }

  /// Cellules PDF d'une créance ou d'une dette : `$r->customer?->name ?? '—'`, `number_format(balance).' FCFA'`,
  /// échéance.
  static List<String> _celluleEcheancePdf(EcheanceRapport e) => [
    e.nom ?? '—',
    '${PmpService.francs(e.reste)} FCFA',
    RapportsRepository.date(e.echeance),
  ];

  /// 🔴→✅ Ticket U12b — l'export « Excel » de l'onglet actif : les lignes du CSV du web (`exportReport('csv')`), au
  /// nom du web en `.xlsx` (ajout validé par le client, voir `ExportTableur`). Le poste écrivait la copie du PDF,
  /// titre et sous-titre compris, sous un nom horodaté tiré du titre.
  ClasseurRapport classeurActif() {
    final d = _donnees!;
    return switch (_onglet) {
      'État de Trésorerie' => ClasseurRapport(
        fichier: 'tresorerie-{jour}.xlsx',
        onglet: 'État de Trésorerie',
        lignes: RapportsRepository.classeurTresorerie(d),
      ),
      'Créances Clients' => ClasseurRapport(
        fichier: 'creances-{jour}.xlsx',
        onglet: 'État des Créances Clients',
        lignes: RapportsRepository.classeurEcheances('Client', d.creances),
      ),
      'Dettes Fournisseurs' => ClasseurRapport(
        fichier: 'dettes-{jour}.xlsx',
        onglet: 'État des Dettes Fournisseurs',
        lignes: RapportsRepository.classeurEcheances(
          'Fournisseur',
          RapportsRepository.filtrerDettes(d.dettes, _recherche.text),
        ),
      ),
      'Rapport Élevage' => ClasseurRapport(
        fichier: 'rapport-elevage-{jour}.xlsx',
        onglet: 'Rapport Élevage',
        lignes: [
          RapportsRepository.enteteClasseurElevage,
          ...d.elevageClasseur,
        ],
      ),
      'Rapport de Stocks' => ClasseurRapport(
        fichier: 'rapport-stocks-{jour}.xlsx',
        onglet: 'Rapport de Stocks',
        lignes: RapportsRepository.classeurStocks(
          RapportsRepository.filtrerStocks(d.stocks, _recherche.text),
        ),
      ),
      _ => ClasseurRapport(
        fichier: 'recettes-depenses-{jour}.xlsx',
        onglet: 'Recettes et Dépenses',
        lignes: RapportsRepository.classeurRecettesDepenses(d),
      ),
    };
  }

  /// `exportPdf()` du hub → `exportReport('pdf')` de l'onglet actif ; refusé sans `export-rapports`, comme le
  /// `$this->authorize('export-rapports')` du web.
  Future<void> _exporterPdf() async {
    final editeur = widget.imprimer;
    if (!widget.peutExporter || editeur == null) return;

    final message = await editeur(documentActif(), _maintenant);
    if (message != null) _annoncer(message);
  }

  Future<void> _exporterTableur() async {
    final editeur = widget.enregistrer;
    if (!widget.peutExporter || editeur == null) return;

    final chemin = await editeur(classeurActif(), _maintenant);
    // ⚠️ **LE CHEMIN EST ANNONCÉ.** Le web télécharge dans le dossier du navigateur, que l'utilisateur connaît ; un
    // fichier écrit par le poste sans le dire est un fichier introuvable.
    _annoncer(
      chemin == null ? 'Classeur enregistré.' : 'Classeur enregistré : $chemin',
    );
  }

  void _annoncer(String message) {
    if (!mounted) return;
    ToastAgri.afficher(context, message);
  }

  // ── Blocs partagés ────────────────────────────────────────────────────────

  Widget _texte(String texte, {bool gras = false}) => Text(
    texte,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: AgriTypography.xs,
      fontWeight: gras ? AgriTypography.gras : AgriTypography.normal,
      color: AgriColors.onSurface,
    ),
  );

  /// « Lecture seule » de la colonne Actions (`text-outline text-[10px] italic`, `title` en info-bulle), alignée à
  /// droite comme la colonne.
  Widget _lectureSeule(String bulle) => Align(
    alignment: Alignment.centerRight,
    child: Tooltip(
      message: bulle,
      child: const Text(
        'Lecture seule',
        style: TextStyle(
          fontSize: 10,
          fontStyle: FontStyle.italic,
          color: AgriColors.outline,
        ),
      ),
    ),
  );

  /// Ligne vide du Blade : `<td colspan=… class="px-md py-lg text-center text-outline">`.
  Widget _ligneVide(String texte) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.lg,
    ),
    child: Text(
      texte,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        color: AgriColors.outline,
      ),
    ),
  );

  /// Carte-tableau des onglets Trésorerie, Créances, Dettes et Stocks (`bg-white rounded-lg border shadow-sm`) :
  /// recherche facultative (`p-md border-b`, champ `max-w-xs`, icône `search`, « Rechercher... »), en-tête
  /// `bg-surface-zebra` (`text-[10px] font-bold uppercase text-outline`, « Actions » à droite), lignes zébrées, état
  /// vide centré. Le tableau prend toute la largeur de la carte (quatre ou cinq colonnes : l'`overflow-x-auto` du web ne
  /// se déclenche pas aux largeurs du poste ; un texte trop long s'abrège).
  Widget _carteTableau({
    required String cle,
    required List<(String, int)> colonnes,
    required List<List<Widget>> lignes,
    required String vide,
    String? recherche,
  }) => Container(
    key: Key(cle),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recherche != null)
          Container(
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AgriColors.outlineVariant),
              ),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 320,
                child: TextField(
                  key: Key('recherche-$recherche'),
                  controller: _recherche,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(
                      SymbolesAgri.search,
                      size: 18,
                      color: AgriColors.outline,
                    ),
                    hintText: 'Rechercher...',
                    hintStyle: TextStyle(fontSize: AgriTypography.xs),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: AgriTypography.xs),
                  // `wire:model.live.debounce.300ms` : la liste suit la frappe.
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ),
        Builder(
          builder: (context) {
            Widget rangee(List<Widget> cellules) => Row(
              children: [
                for (var c = 0; c < colonnes.length; c++)
                  Expanded(flex: colonnes[c].$2, child: cellules[c]),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AgriSpacing.md,
                    vertical: AgriSpacing.sm,
                  ),
                  decoration: const BoxDecoration(
                    color: AgriColors.surfaceZebra,
                    border: Border(
                      bottom: BorderSide(color: AgriColors.outlineVariant),
                    ),
                  ),
                  child: rangee([
                    for (var c = 0; c < colonnes.length; c++)
                      Text(
                        colonnes[c].$1.toUpperCase(),
                        textAlign: c == colonnes.length - 1
                            ? TextAlign.right
                            : TextAlign.left,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: AgriTypography.gras,
                          color: AgriColors.outline,
                        ),
                      ),
                  ]),
                ),
                if (lignes.isEmpty)
                  _ligneVide(vide)
                else
                  for (var i = 0; i < lignes.length; i++)
                    Container(
                      key: Key('$cle-ligne-$i'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AgriSpacing.md,
                        vertical: AgriSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: i.isOdd
                            ? AgriColors.surfaceZebra
                            : AgriColors.surfaceCard,
                        border: const Border(
                          bottom: BorderSide(
                            color: AgriColors.outlineVariant,
                          ),
                        ),
                      ),
                      child: rangee(lignes[i]),
                    ),
              ],
            );
          },
        ),
      ],
    ),
  );

  /// Tableau des trois tableaux du Rapport Élevage (tickets U9 à U11).
  Widget _tableau({
    required String cle,
    required double largeur,
    required List<(String, int)> colonnes,
    required List<LigneRapport> lignes,
    required String vide,
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
                        child: Text(
                          c < lignes[i].cellules.length
                              ? lignes[i].cellules[c]
                              : '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AgriTypography.xs,
                            color: AgriColors.onSurface,
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

  /// ⚠️ ÉCART — mention propre au poste (absente du web) : dit ce que le poste ne détient pas.
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
/// injecte ses propres éditeurs et contrôle le DOCUMENT produit — titre,
/// sous-titre, colonnes, lignes — sans imprimante, sans disque et sans greffon
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
      // Ticket U11 — le nom du web (`stocks-AAAA-MM-JJ.pdf`…), plus celui du classeur en `.xlsx`.
      name: DocumentOfficiel.nomPdf(document, maintenant),
    );
    return null;
  }

  /// Ticket U12b — le classeur du hub : contenu du CSV du web, nom du web en `.xlsx`.
  static Future<String?> enregistrer(
    ClasseurRapport classeur,
    DateTime maintenant,
  ) => ExportTableur.enregistrerTableau(classeur, maintenant: maintenant);
}
