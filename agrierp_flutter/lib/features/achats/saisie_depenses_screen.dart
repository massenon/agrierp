import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/comptabilite/exercice_choisi.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/lecture_seule.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/pagination_agri.dart';
import '../../core/widgets/toast_agri.dart';
import '../../core/comptabilite/exercice_de_saisie.dart';
import '../stocks/pmp_service.dart';
import 'depenses_repository.dart';

/// « Saisie des Dépenses » — `resources/views/livewire/achats/saisie-depenses.blade.php` (maître, article 5).
///
/// 🔴→✅ Ticket U14 — l'écran suit son Blade, section par section :
///   1. en-tête : icône `request_page`, « Saisie des Dépenses », sous-titre du Blade (plus de « Indicateurs de
///      performance », que le Blade n'a pas) ;
///   2. trois `x-kpi-card` : « Dépenses du mois » (`… FCFA`, émeraude), « Charges Fixes » (maïs) et « Charges
///      Variables » (bleu), ces deux-là « en attente » comme au web (tiret estompé, sablier, « Disponible après Aucun
///      champ Fixe/Variable dans le formulaire source ») — le poste avait inversé leurs couleurs ;
///   3. le formulaire « Nouvelle Dépense » / « Modifier la Dépense » sur deux colonnes (`md:grid-cols-2`), les
///      erreurs sous leur champ avec les messages du web, le bouton « Enregistrer la Dépense » à droite ;
///   4. la barre « Rechercher... » (300 ms, comme `wire:model.live.debounce.300ms`) et « Tous les statuts » /
///      « Payée » / « En attente » ;
///   5. le tableau Date · Libellé · Catégorie · Montant · Statut · Actions, badge du Blade (« Payée » / « En
///      attente »), « Modifier » et « Archiver » (modale `x-modal-confirm-delete`), « Aucune dépense pour le moment. ».
///
/// Toasts du web : « Dépense enregistrée avec succès. » (succès), « Dépense archivée — trésorerie réintégrée et
/// charge annulée. » (avertissement). Comme au web, après un enregistrement le compte de trésorerie choisi reste
/// sélectionné (`reset()` ne le vide pas) et la date revient à aujourd'hui.
///
/// ➕ Ajout du poste, gardé : sous la date, l'état d'envoi d'une saisie de ce poste (« À envoyer » ; « Refusée » ou
/// « Archivage refusé » suivi du motif du serveur mot pour mot) — le web n'a pas de file d'envoi.
///
/// ⚠️ ÉCART (plateforme) : « Reçu / Facture (Photo) ». La synchronisation ne transporte aucun fichier : le champ est
/// à sa place et dit sa limite, au lieu d'accepter une photo qui ne partirait jamais.
///
/// ⚠️ « Charges Fixes / Variables » : arbitrage client en attente (aucun champ Fixe/Variable, ni au web ni ici).
class SaisieDepensesScreen extends StatefulWidget {
  const SaisieDepensesScreen({super.key, required this.depot});

  final DepensesRepository depot;

  /// `wire:model.live.debounce.300ms` du champ « Rechercher... ».
  static const delaiRecherche = Duration(milliseconds: 300);

  /// `pending-since` des deux cartes en attente du Blade.
  static const legendeEnAttente =
      'Disponible après Aucun champ Fixe/Variable dans le formulaire source';

  /// Ticket EX7 (réponse à EX-Q5, décision D-U14-1) — info-bulle du champ « Date » GRISÉ d'une dépense comptabilisée :
  /// `SaisieDepenseAction::MOTIF_DATE_VERROUILLEE` du web, mot pour mot. Le refus à l'enregistrement reste la garantie.
  static const motifDateVerrouillee = 'Dépense déjà comptabilisée : sa date ne peut plus être modifiée.';

  @override
  State<SaisieDepensesScreen> createState() => _SaisieDepensesScreenState();
}

class _SaisieDepensesScreenState extends State<SaisieDepensesScreen> {
  List<ExpenseCategory> _categories = const [];
  List<TreasuryAccount> _comptes = const [];
  List<LigneDepense> _depenses = const [];
  double? _totalDuMois;

  /// `editingExpenseId` du composant : `null` = « Nouvelle Dépense ».
  String? _enModification;

  /// Ticket EX7 (EX-Q5) — la dépense en modification est comptabilisée (`accounting_entry_id`) : sa date est grisée.
  bool _dateVerrouillee = false;

  /// Ticket EX7 (EF9) — page affichée (25 dépenses), dans l'exercice affiché.
  int _page = 1;

  DateTime _date = HeureBenin.aujourdhui();
  final _libelle = TextEditingController();
  String? _categorie;
  final _montant = TextEditingController();
  String? _compteId;

  final _recherche = TextEditingController();
  String _rechercheAppliquee = '';
  String _statut = '';
  Timer? _attenteRecherche;

  bool _enregistrement = false;
  Map<String, String> _erreurs = const {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _attenteRecherche?.cancel();
    _libelle.dispose();
    _montant.dispose();
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    // Ticket EX7 (EF9) — les dépenses de l'exercice AFFICHÉ ; « Dépenses du mois » sur son mois de référence.
    final etat = PorteeExerciceChoisi.lire(context);
    final categories = await widget.depot.categories();
    final comptes = await widget.depot.comptesTresorerie();
    final depenses = await widget.depot.depenses(
      recherche: _rechercheAppliquee,
      statut: _statut,
      bornes: etat?.bornes,
    );
    final total = await widget.depot.totalDuMois(etat?.moisDeReference ?? HeureBenin.maintenant());

    if (!mounted) return;

    setState(() {
      _categories = categories;
      _comptes = comptes;
      _depenses = depenses;
      _totalDuMois = total;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AgriSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _enTete(),
            const SizedBox(height: AgriSpacing.lg),
            _indicateurs(),
            const SizedBox(height: AgriSpacing.lg),
            _formulaire(),
            const SizedBox(height: AgriSpacing.lg),
            _barreFiltres(),
            const SizedBox(height: AgriSpacing.md),
            _tableau(),
          ],
        ),
      ),
    );
  }

  /// `border-b border-outline-variant pb-md mb-lg` : icône `request_page` 26 px émeraude dans le titre
  /// (`text-xl lg:text-2xl font-bold text-on-surface`), sous-titre `text-xs text-outline`.
  Widget _enTete() {
    final large = AgriBreakpoints.large(context);
    return Container(
      padding: const EdgeInsets.only(bottom: AgriSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                SymbolesAgri.request_page,
                size: 26,
                color: AgriColors.brandEmerald,
              ),
              const SizedBox(width: AgriSpacing.xs),
              Flexible(
                child: Text(
                  'Saisie des Dépenses',
                  style: TextStyle(
                    fontSize: large ? 24 : 20,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.xs),
          const Text(
            "Enregistrement des charges d'exploitation courantes de la ferme (SYSCOHADA Classe 6).",
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// `grid grid-cols-1 sm:grid-cols-3 gap-md` — les trois `x-kpi-card` du Blade, dans son ordre et ses couleurs.
  Widget _indicateurs() {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final colonnes = AgriBreakpoints.petit(context) ? 3 : 1;
        final largeur =
            (contraintes.maxWidth - (colonnes - 1) * AgriSpacing.md) / colonnes;
        final total = _totalDuMois;

        return Wrap(
          spacing: AgriSpacing.md,
          runSpacing: AgriSpacing.md,
          children: [
            _carteKpi(
              largeur,
              'Dépenses du mois',
              // `number_format($kpis['depenses_mois'], 0, ',', ' ').' FCFA'` ; « — » tant que rien n'est lu.
              total == null ? '—' : '${PmpService.francs(total)} FCFA',
              AgriColors.brandEmerald,
              SymbolesAgri.payments,
            ),
            _carteKpi(
              largeur,
              'Charges Fixes',
              '—',
              AgriColors.accentYellow,
              SymbolesAgri.event_repeat,
              couleurIcone: AgriColors.brandForest,
              enAttente: true,
            ),
            _carteKpi(
              largeur,
              'Charges Variables',
              '—',
              AgriColors.infoBlue,
              SymbolesAgri.trending_down,
              enAttente: true,
            ),
          ],
        );
      },
    );
  }

  /// `x-kpi-card` : liseré et icône de la variante (`text-brand-forest` pour `maize`) ; `:pending` → tiret estompé
  /// (`text-outline/50`) et sablier `hourglass_empty` devant « Disponible après … ».
  Widget _carteKpi(
    double largeur,
    String libelle,
    String valeur,
    Color couleur,
    IconData icone, {
    Color? couleurIcone,
    bool enAttente = false,
  }) => SizedBox(
    width: largeur,
    child: CarteKpi(
      key: Key('kpi-$libelle'),
      libelle: libelle,
      valeur: valeur,
      icone: icone,
      couleurLisere: couleur,
      couleurIcone: couleurIcone ?? couleur,
      couleurValeur: enAttente
          ? AgriColors.outline.withValues(alpha: 0.5)
          : AgriColors.onSurface,
      legende: enAttente ? SaisieDepensesScreen.legendeEnAttente : null,
      iconeLegende: enAttente ? SymbolesAgri.hourglass_empty : null,
    ),
  );

  /// Le formulaire du Blade : `bg-white rounded-lg border shadow-sm p-lg`, titre `font-bold text-lg
  /// text-brand-forest` (« Nouvelle Dépense » ou « Modifier la Dépense »), aide, puis la grille `md:grid-cols-2`.
  Widget _formulaire() {
    final deuxColonnes = AgriBreakpoints.moyen(context);
    final champs = <Widget>[
      _champDate(),
      _champTexte(
        libelle: 'Libellé de la Dépense *',
        cle: 'libelle',
        controleur: _libelle,
        exemple: 'ex : Carburant livraison ou Achat provende Lot 3',
      ),
      _champListe(
        libelle: 'Catégorie de Charges (SYSCOHADA) *',
        cle: 'categorie',
        valeur: _categorie,
        options: [for (final c in _categories) (c.label, c.label)],
        surChangement: (v) => setState(() => _categorie = v),
      ),
      _champTexte(
        libelle: 'Montant Décaissé (FCFA) *',
        cle: 'montant',
        controleur: _montant,
        exemple: 'ex : 25000',
        nombre: true,
      ),
      _champListe(
        libelle: 'Compte de Trésorerie Débité *',
        cle: 'compte',
        valeur: _compteId,
        // `{{ $account->label }} ({{ number_format($account->balance, 0, ',', ' ') }} FCFA)`.
        options: [
          for (final c in _comptes)
            (c.id, '${c.label} (${PmpService.francs(c.balance)} FCFA)'),
        ],
        surChangement: (v) => setState(() => _compteId = v),
      ),
      _recu(),
    ];

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.lg),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        boxShadow: AgriShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                SymbolesAgri.add_circle,
                size: 20,
                color: AgriColors.brandForest,
              ),
              const SizedBox(width: AgriSpacing.xs),
              Expanded(
                child: Text(
                  _enModification == null
                      ? 'Nouvelle Dépense'
                      : 'Modifier la Dépense',
                  key: const Key('depense-titre-formulaire'),
                  style: const TextStyle(
                    fontSize: AgriTypography.lg,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          const Text(
            "Enregistrez une charge d'exploitation de trésorerie directe.",
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          for (var i = 0; i < champs.length; i += deuxColonnes ? 2 : 1) ...[
            if (i > 0) const SizedBox(height: AgriSpacing.md),
            if (deuxColonnes)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: champs[i]),
                  const SizedBox(width: AgriSpacing.md),
                  Expanded(child: champs[i + 1]),
                ],
              )
            else
              champs[i],
          ],
          const SizedBox(height: AgriSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            // Ticket EX7 (EF10) — exercice affiché clos : grisé, motif en info-bulle (`@lectureSeule` du web).
            child: LectureSeule.infobulle(
              LectureSeule.motif(context),
              FilledButton.icon(
              key: const Key('bouton-enregistrer-depense'),
              onPressed: _enregistrement || LectureSeule.motif(context) != null ? null : _enregistrer,
              icon: const Icon(SymbolesAgri.save, size: 18),
              label: const Text('Enregistrer la Dépense'),
              style: FilledButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontSize: AgriTypography.sm,
                  fontWeight: FontWeight.bold,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.lg,
                  vertical: AgriSpacing.sm,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }

  /// `block text-[10px] text-brand-forest font-bold uppercase mb-xs`.
  Widget _etiquette(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
    child: Text(
      texte.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: AgriColors.brandForest,
      ),
    ),
  );

  /// `<p class="invalid-feedback">` du Blade (11 px, `#BA1A1A`).
  Widget _erreur(String cle) {
    final texte = _erreurs[cle];
    if (texte == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        texte,
        key: Key('erreur-$cle'),
        style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
      ),
    );
  }

  /// Cadre `h-11 px-md border rounded-lg text-sm`, rouge et teinté si le champ est en erreur (`is-invalid`).
  BoxDecoration _cadre(String cle) => BoxDecoration(
    color: _erreurs.containsKey(cle)
        ? const Color(0xFFFFF5F5)
        : AgriColors.surfaceCard,
    border: Border.all(
      color: _erreurs.containsKey(cle)
          ? AgriColors.errorDeep
          : AgriColors.outlineVariant,
    ),
    borderRadius: BorderRadius.circular(AgriRadius.lg),
  );

  /// « Date de la Transaction * » — `type="date"` du web, borné (ticket EX6) au plus ancien exercice OUVERT connu
  /// (`min` du web, `AccountingEntryService::premierJourSaisissable`).
  Widget _champDate() {
    String deux(int n) => n.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette('Date de la Transaction *'),
        // Ticket EX7 (EX-Q5) — dépense comptabilisée en modification : date grisée, motif du web en info-bulle.
        LectureSeule.infobulle(
          _dateVerrouillee ? SaisieDepensesScreen.motifDateVerrouillee : null,
          InkWell(
          key: const Key('champ-date'),
          onTap: _dateVerrouillee ? null : () async {
            final premier = await widget.depot.premierJourSaisissable();
            if (!mounted) return;
            final bornes = ExerciceDeSaisie.calendrier(
              premier: premier,
              repli: DateTime(2000),
              dernier: DateTime(2100),
              initial: _date,
            );
            final choisie = await showDatePicker(
              context: context,
              initialDate: bornes.initial,
              firstDate: bornes.premier,
              lastDate: DateTime(2100),
            );
            if (choisie != null) setState(() => _date = choisie);
          },
          child: Container(
            height: 44,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
            decoration: _cadre('date'),
            child: Text(
              '${deux(_date.day)}/${deux(_date.month)}/${_date.year}',
              style: TextStyle(
                fontSize: AgriTypography.sm,
                color: _dateVerrouillee ? AgriColors.outline : null,
              ),
            ),
          ),
        ),
        ),
        _erreur('date'),
      ],
    );
  }

  Widget _champTexte({
    required String libelle,
    required String cle,
    required TextEditingController controleur,
    required String exemple,
    bool nombre = false,
  }) {
    final enErreur = _erreurs.containsKey(cle);
    final bord = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      borderSide: BorderSide(
        color: enErreur ? AgriColors.errorDeep : AgriColors.outlineVariant,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette(libelle),
        SizedBox(
          height: 44,
          child: TextField(
            key: Key('champ-$cle'),
            controller: controleur,
            keyboardType: nombre ? TextInputType.number : TextInputType.text,
            style: const TextStyle(fontSize: AgriTypography.sm),
            decoration: InputDecoration(
              hintText: exemple,
              isDense: true,
              filled: enErreur,
              fillColor: const Color(0xFFFFF5F5),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: 12,
              ),
              border: bord,
              enabledBorder: bord,
            ),
          ),
        ),
        _erreur(cle),
      ],
    );
  }

  Widget _champListe({
    required String libelle,
    required String cle,
    required String? valeur,
    required List<(String, String)> options,
    required ValueChanged<String?> surChangement,
  }) {
    // Une valeur hors de la liste (compte désactivé depuis la saisie) : le web garde la valeur et montre
    // « -- Sélectionner -- » ; une liste Flutter refuse une valeur absente de ses entrées.
    final presente = options.any((o) => o.$1 == valeur);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette(libelle),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
          decoration: _cadre(cle),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: Key('liste-$cle'),
              isExpanded: true,
              value: presente ? valeur : null,
              hint: const Text(
                '-- Sélectionner --',
                style: TextStyle(
                  fontSize: AgriTypography.sm,
                  color: AgriColors.onSurface,
                ),
              ),
              style: const TextStyle(
                fontSize: AgriTypography.sm,
                color: AgriColors.onSurface,
              ),
              items: [
                for (final o in options)
                  DropdownMenuItem(value: o.$1, child: Text(o.$2)),
              ],
              onChanged: surChangement,
            ),
          ),
        ),
        _erreur(cle),
      ],
    );
  }

  /// « Reçu / Facture (Photo) » — cadre pointillé du Blade (`border-2 border-dashed … h-11`).
  ///
  /// ⚠️ ÉCART (plateforme) : la synchronisation ne transporte aucun fichier. Le champ est à sa place et dit sa limite,
  /// au lieu d'accepter une photo qui ne partirait jamais (l'utilisateur croirait le justificatif transmis).
  Widget _recu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette('Reçu / Facture (Photo)'),
        Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.md,
            vertical: AgriSpacing.xs,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AgriColors.outlineVariant, width: 2),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                SymbolesAgri.add_a_photo,
                size: 18,
                color: AgriColors.outlineVariant,
              ),
              SizedBox(width: AgriSpacing.xs),
              Flexible(
                child: Text(
                  'Le justificatif ne peut pas encore être transmis depuis le poste : la synchronisation ne '
                  "transporte aucun fichier. Joignez-le depuis l'application web.",
                  key: Key('depense-recu-limite'),
                  style: TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// `bg-white border rounded-lg p-md flex flex-wrap items-center gap-sm` : « Rechercher... » (icône `search`,
  /// `flex-1 min-w-[180px]`) puis la liste des statuts.
  Widget _barreFiltres() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                key: const Key('depenses-recherche'),
                controller: _recherche,
                onChanged: _rechercher,
                style: const TextStyle(fontSize: AgriTypography.xs),
                decoration: InputDecoration(
                  hintText: 'Rechercher...',
                  isDense: true,
                  prefixIcon: const Icon(
                    SymbolesAgri.search,
                    size: 18,
                    color: AgriColors.outline,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AgriRadius.lg),
                    borderSide: const BorderSide(
                      color: AgriColors.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
            decoration: BoxDecoration(
              color: AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('depenses-filtre-statut'),
                value: _statut,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.onSurface,
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Tous les statuts'),
                  ),
                  for (final s in DepensesRepository.statuts)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) {
                  _statut = v ?? '';
                  _charger();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _rechercher(String texte) {
    _attenteRecherche?.cancel();
    _attenteRecherche = Timer(SaisieDepensesScreen.delaiRecherche, () {
      _rechercheAppliquee = texte;
      _charger();
    });
  }

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AgriColors.outline,
  );

  /// Le tableau du Blade (`table.rtable`) : en-tête `bg-surface-zebra`, six colonnes, zébrage une ligne sur deux.
  Widget _tableau() {
    return Container(
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        boxShadow: AgriShadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AgriColors.surfaceZebra,
            padding: const EdgeInsets.symmetric(
              horizontal: AgriSpacing.md,
              vertical: AgriSpacing.sm,
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('DATE', style: _enteteColonne)),
                Expanded(
                  flex: 4,
                  child: Text('LIBELLÉ', style: _enteteColonne),
                ),
                Expanded(
                  flex: 3,
                  child: Text('CATÉGORIE', style: _enteteColonne),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'MONTANT',
                    textAlign: TextAlign.right,
                    style: _enteteColonne,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: EdgeInsets.only(left: AgriSpacing.md),
                    child: Text('STATUT', style: _enteteColonne),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'ACTIONS',
                    textAlign: TextAlign.right,
                    style: _enteteColonne,
                  ),
                ),
              ],
            ),
          ),
          if (_depenses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AgriSpacing.lg),
              child: Text(
                'Aucune dépense pour le moment.',
                key: Key('depenses-vide'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AgriTypography.base,
                  color: AgriColors.outline,
                ),
              ),
            ),
          for (final (i, l) in (PorteeExerciceChoisi.lire(context) == null ? _depenses : PaginationAgri.tranche(_depenses, _page)).indexed)
            _ligne(l, i),
          // Ticket EX7 (EF9) — `<x-pagination>` du web, sous le tableau.
          if (PorteeExerciceChoisi.lire(context) case final etat?)
            PaginationAgri(
              nom: 'depenses',
              total: _depenses.length,
              page: _page,
              annee: etat.annee,
              onPage: (p) => setState(() => _page = p),
            ),
        ],
      ),
    );
  }

  Widget _ligne(LigneDepense l, int index) {
    final d = l.depense;
    String deux(int n) => n.toString().padLeft(2, '0');
    const corps = TextStyle(fontSize: AgriTypography.xs);
    return Container(
      key: Key('depense-ligne-$index'),
      decoration: BoxDecoration(
        color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
        border: const Border(
          top: BorderSide(color: AgriColors.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.md,
        vertical: AgriSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${deux(d.expenseDate.day)}/${deux(d.expenseDate.month)}/${d.expenseDate.year}',
                  style: corps,
                ),
                ..._etatEnvoi(l),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              d.label,
              key: Key('depense-libelle-$index'),
              style: corps.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(flex: 3, child: Text(d.category, style: corps)),
          Expanded(
            flex: 2,
            child: Text(
              '${PmpService.francs(d.amount)} FCFA',
              key: Key('depense-montant-$index'),
              textAlign: TextAlign.right,
              style: corps.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(left: AgriSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _badgeStatut(d),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _action(
                  cle: 'depense-modifier-${d.id}',
                  infobulle: 'Modifier',
                  icone: SymbolesAgri.edit,
                  couleur: AgriColors.brandEmerald,
                  surAppui: () => _modifier(d),
                  verrou: LectureSeule.motif(context),
                ),
                _action(
                  cle: 'depense-archiver-${d.id}',
                  infobulle: 'Archiver',
                  icone: SymbolesAgri.delete,
                  couleur: AgriColors.outline,
                  surAppui: () => _archiver(d),
                  verrou: LectureSeule.motif(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `inline-flex px-sm py-[2px] rounded-full text-[11px] font-bold border` : « Payée » émeraude (`payee`), sinon
  /// « En attente » maïs.
  Widget _badgeStatut(Expense d) {
    final payee = d.status == 'payee';
    return Container(
      key: Key('depense-statut-${d.id}'),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: payee
            ? AgriColors.brandEmerald.withValues(alpha: 0.10)
            : AgriColors.accentYellow.withValues(alpha: 0.20),
        border: Border.all(
          color: payee
              ? AgriColors.brandEmerald.withValues(alpha: 0.30)
              : AgriColors.accentYellow,
        ),
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
      child: Text(
        payee ? 'Payée' : 'En attente',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: payee ? AgriColors.brandEmerald : AgriColors.brandForest,
        ),
      ),
    );
  }

  /// ➕ Ajout du poste : l'état d'envoi d'une saisie de ce poste, sous sa date.
  List<Widget> _etatEnvoi(LigneDepense l) {
    final d = l.depense;
    if (d.syncStatus == SyncStatus.synced) return const [];
    final refusee = d.syncStatus == SyncStatus.conflict;
    return [
      const SizedBox(height: 2),
      Container(
        key: Key('depense-etat-${d.id}'),
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: refusee
              ? AgriColors.errorBg
              : AgriColors.accentYellow.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
        child: Text(
          !refusee
              ? 'À envoyer'
              : d.isActive
              ? 'Refusée'
              : 'Archivage refusé',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: refusee ? AgriColors.errorDeep : AgriColors.brandForest,
          ),
        ),
      ),
      if (refusee)
        Text(
          l.motifRefus ?? 'Refus sans motif communiqué.',
          key: Key('depense-motif-${d.id}'),
          style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
        ),
    ];
  }

  Widget _action({
    required String cle,
    required String infobulle,
    required IconData icone,
    required Color couleur,
    required VoidCallback surAppui,
    String? verrou,
  }) => Tooltip(
    // Ticket EX7 (EF10) — exercice affiché clos : grisé, le motif remplace l'info-bulle.
    message: verrou ?? infobulle,
    child: InkWell(
      key: Key(cle),
      onTap: verrou == null ? surAppui : null,
      borderRadius: BorderRadius.circular(AgriRadius.full),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icone, size: 18, color: verrou == null ? couleur : AgriColors.outlineVariant),
      ),
    ),
  );

  /// `editExpense($id)` : le formulaire passe en « Modifier la Dépense », rempli avec la dépense (`(float) amount`).
  void _modifier(Expense d) {
    setState(() {
      _enModification = d.id;
      _dateVerrouillee = d.accountingEntryId != null;
      _date = d.expenseDate;
      _libelle.text = d.label;
      _categorie = d.category;
      _montant.text = PmpService.flottant(d.amount);
      _compteId = d.treasuryAccountId;
    });
  }

  /// `archiveExpense($id)` derrière `x-modal-confirm-delete` : icône `archive` `text-error-deep`, « Confirmer
  /// l'archivage », le libellé de la dépense, « Annuler » puis « Archiver » (`bg-error-red`).
  Future<void> _archiver(Expense d) async {
    final confirme = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (contexte) => ModaleConfirmation(
        icone: SymbolesAgri.archive,
        couleurIcone: AgriColors.errorDeep,
        titre: "Confirmer l'archivage",
        message:
            '${d.label} sera marqué(e) comme archivé(e) (statut inactif). '
            "Aucune suppression définitive n'est effectuée.",
        actions: [
          BoutonModaleSecondaire(
            libelle: 'Annuler',
            onPressed: () => Navigator.of(contexte).pop(false),
          ),
          BoutonModalePrimaire(
            key: const Key('archivage-depense-confirmer'),
            libelle: 'Archiver',
            couleur: AgriColors.errorRed,
            onPressed: () => Navigator.of(contexte).pop(true),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    try {
      await widget.depot.archiver(d.id);
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7) — `archiveExpense()` : dépense d'un exercice clos, motif R4 en toast d'erreur.
      if (!mounted) return;
      ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      return;
    }
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(
      context,
      DepensesRepository.toastArchivee,
      type: TypeToast.avertissement,
    );
  }

  /// `submitExpense()` : erreurs sous leur champ ; sinon toast du web, formulaire remis à « Nouvelle Dépense »
  /// (libellé, catégorie, montant vidés, date du jour ; le compte de trésorerie reste choisi, comme au web).
  Future<void> _enregistrer() async {
    setState(() {
      _enregistrement = true;
      _erreurs = const {};
    });

    try {
      await widget.depot.enregistrerSaisie(
        date: _date,
        libelle: _libelle.text,
        categorie: _categorie,
        montant: _montant.text,
        compteTresorerieId: _compteId,
        idEnModification: _enModification,
      );
    } on DepenseRefusee catch (e) {
      if (!mounted) return;
      setState(() {
        _erreurs = e.erreurs;
        _enregistrement = false;
      });
      return;
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7) — `submitExpense()` : exercice clos ou absent, le motif R4 sous « Date ».
      if (!mounted) return;
      setState(() {
        _erreurs = {'date': e.motif};
        _enregistrement = false;
      });
      return;
    }

    if (!mounted) return;
    _libelle.clear();
    _montant.clear();
    setState(() {
      _enModification = null;
      _dateVerrouillee = false;
      _categorie = null;
      _date = HeureBenin.aujourdhui();
      _enregistrement = false;
    });
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(context, DepensesRepository.toastEnregistree);
  }
}
