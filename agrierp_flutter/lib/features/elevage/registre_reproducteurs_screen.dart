import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/champs_date_agri.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'champs_modale_elevage.dart';
import 'reproducteurs_repository.dart';

/// « Registre des Reproducteurs » — `resources/views/livewire/elevage/registre-reproducteurs.blade.php` (maître,
/// article 5).
///
/// Ticket BS3 (décision BS-Q1 du 21/10/2026) — le registre nominatif des reproducteurs s'ÉCRIT au poste (il n'était lu
/// qu'au travers de la fiche d'un sujet). L'écran suit son Blade, section par section :
///   1. en-tête : icône `pets`, « Registre des Reproducteurs », sous-titre du Blade et — avec `manage-elevage` — le
///      bouton « Enregistrer un Reproducteur » ;
///   2. le bandeau d'information bleu (identifier n'ajoute AUCUN animal à l'effectif), avec son lien « Enregistrer des
///      Sujets » ;
///   3. quatre `x-kpi-card` : Reproducteurs Enregistrés · Présents · Femelles · Mâles ;
///   4. la carte du tableau : recherche (300 ms), filtres d'espèce et de statut, puis Identifiant · Espèce · Sexe · Race ·
///      Bande · Cage · Statut · Actions (consulter la fiche ; avec `manage-elevage` : modifier, et enregistrer une sortie
///      pour un sujet présent) ;
///   5. les modales « Enregistrer un Reproducteur » / « Modifier le Reproducteur » et « Enregistrer une Sortie ».
///
/// Toasts du web : « Reproducteur enregistré — l'effectif de la bande est inchangé, ce sujet y était déjà compté. »
/// (succès), « Reproducteur mis à jour. » (succès), « Sortie enregistrée. … » (avertissement).
///
/// ➕ Ajout du poste, gardé : sous l'identifiant d'un sujet de CE poste pas encore reçu par le serveur, « À envoyer » ;
/// « Refusé » suivi du motif du serveur mot pour mot quand l'envoi a été refusé — le web n'a pas de file d'envoi.
///
/// Décisions du client du 21/10/2026 (web d'abord, puis ce poste à l'identique) :
///  - BS-Q11 : le statut d'un sujet sorti s'écrit « Réformé », « Vendu », « Mort » (`Animal::libelleStatut()` du web,
///    [ReproducteursRepository.libelleStatut]) ; la valeur technique reste `reforme` / `vendu` / `mort` ;
///  - BS-Q12 : les espèces proposées sont celles des modules actifs, comme au web et au tirage ;
///  - BS-Q13 : en modification, le champ Identifiant est GRISÉ avec son info-bulle (les saillies s'y rattachent par ce
///    nom) ; à la création il reste libre.
class RegistreReproducteursScreen extends StatefulWidget {
  const RegistreReproducteursScreen({
    super.key,
    required this.depot,
    this.peutGerer = true,
    this.onOuvrirFiche,
    this.onOuvrirSujets,
    this.horloge,
  });

  final ReproducteursRepository depot;

  /// `@can('manage-elevage')` : sans ce droit, ni « Enregistrer un Reproducteur », ni modifier, ni sortie.
  final bool peutGerer;

  /// « Consulter la fiche » : l'identifiant du sujet (`route('elevage.animal-details', $animal)` au web).
  final ValueChanged<String>? onOuvrirFiche;

  /// Lien « Enregistrer des Sujets » du bandeau (`route('elevage.enregistrer-sujets')` au web).
  final VoidCallback? onOuvrirSujets;

  final DateTime Function()? horloge;

  /// `wire:model.live.debounce.300ms` du champ « Rechercher un identifiant, une race... ».
  static const delaiRecherche = Duration(milliseconds: 300);

  /// `<option>` du filtre de statut du Blade : (valeur, libellé).
  static const statuts = <(String, String)>[
    ('', 'Tous les statuts'),
    ('actif', 'Actif'),
    ('reforme', 'Réformé'),
    ('vendu', 'Vendu'),
    ('mort', 'Mort'),
  ];

  @override
  State<RegistreReproducteursScreen> createState() => _RegistreReproducteursScreenState();
}

class _RegistreReproducteursScreenState extends State<RegistreReproducteursScreen> {
  IndicateursReproducteurs? _kpis;
  List<LigneReproducteur> _lignes = const [];
  List<EspeceElevage> _especes = const [];
  final _recherche = TextEditingController();
  String _rechercheAppliquee = '';
  String _espece = '';
  String _statut = '';
  Timer? _attente;

  DateTime _maintenant() => (widget.horloge ?? HeureBenin.maintenant)();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _attente?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final kpis = await widget.depot.indicateurs();
    final especes = await widget.depot.especes();
    final lignes = await widget.depot.reproducteurs(recherche: _rechercheAppliquee, speciesId: _espece, statut: _statut);
    if (!mounted) return;
    setState(() {
      _kpis = kpis;
      _especes = especes;
      _lignes = lignes;
    });
  }

  void _rechercher(String texte) {
    _attente?.cancel();
    _attente = Timer(RegistreReproducteursScreen.delaiRecherche, () {
      _rechercheAppliquee = texte;
      _charger();
    });
  }

  @override
  Widget build(BuildContext context) {
    final k = _kpis;
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: k == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AgriSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _enTete(),
                  const SizedBox(height: AgriSpacing.lg),
                  _bandeau(),
                  _indicateurs(k),
                  const SizedBox(height: AgriSpacing.lg),
                  _carteTableau(),
                ],
              ),
            ),
    );
  }

  /// `flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg`.
  Widget _enTete() {
    final large = AgriBreakpoints.large(context);
    final titre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(SymbolesAgri.pets, size: 26, color: AgriColors.brandEmerald),
            const SizedBox(width: AgriSpacing.xs),
            Flexible(
              child: Text(
                'Registre des Reproducteurs',
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
        Text(
          "Sujets suivis individuellement — identification, race, généalogie. Les bandes d'engraissement restent suivies en quantités.",
          style: TextStyle(fontSize: large ? AgriTypography.sm : AgriTypography.xs, color: AgriColors.outline),
        ),
      ],
    );
    final bouton = widget.peutGerer
        ? ElevatedButton.icon(
            key: const Key('reproducteur-nouveau'),
            onPressed: _nouveau,
            icon: const Icon(SymbolesAgri.add_circle, size: 18),
            label: const Text('Enregistrer un Reproducteur'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              foregroundColor: AgriColors.surfaceCard,
              elevation: 1,
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
              textStyle: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.full)),
            ),
          )
        : null;
    return Container(
      padding: const EdgeInsets.only(bottom: AgriSpacing.md),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AgriColors.outlineVariant))),
      child: large
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Expanded(child: titre), ?bouton],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titre, if (bouton != null) ...[const SizedBox(height: AgriSpacing.sm), bouton]],
            ),
    );
  }

  /// `bg-info-blue/10 border border-info-blue/30 rounded-lg p-md mb-lg flex items-start gap-sm text-xs`.
  Widget _bandeau() {
    const corps = TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface);
    const gras = TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface, fontWeight: FontWeight.bold);
    return Container(
      margin: const EdgeInsets.only(bottom: AgriSpacing.lg),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.infoBlue.withValues(alpha: 0.10),
        border: Border.all(color: AgriColors.infoBlue.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(SymbolesAgri.info, size: 18, color: AgriColors.infoBlue),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: corps,
                children: [
                  const TextSpan(text: 'Enregistrer un reproducteur ici lui donne une '),
                  const TextSpan(text: 'identité', style: gras),
                  const TextSpan(text: ' (boucle, race, généalogie) — cela '),
                  const TextSpan(text: "n'ajoute aucun animal", style: gras),
                  const TextSpan(text: " à l'effectif : le sujet est déjà compté dans sa bande. Les entrées réelles (naissance, achat, don) se saisissent depuis "),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: InkWell(
                      key: const Key('registre-lien-sujets'),
                      onTap: widget.onOuvrirSujets,
                      child: const Text(
                        'Enregistrer des Sujets',
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          color: AgriColors.infoBlue,
                          fontWeight: AgriTypography.demiGras,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg`.
  Widget _indicateurs(IndicateursReproducteurs k) {
    final colonnes = AgriBreakpoints.large(context) ? 4 : 2;
    final cartes = <Widget>[
      CarteKpi(
        key: const Key('kpi-Reproducteurs Enregistrés'),
        libelle: 'Reproducteurs Enregistrés',
        icone: SymbolesAgri.inventory_2,
        couleurLisere: AgriColors.brandEmerald,
        couleurIcone: AgriColors.brandEmerald,
        valeur: '${k.total}',
      ),
      CarteKpi(
        key: const Key('kpi-Présents'),
        libelle: 'Présents',
        icone: SymbolesAgri.check_circle,
        couleurLisere: AgriColors.infoBlue,
        couleurIcone: AgriColors.infoBlue,
        valeur: '${k.presents}',
      ),
      CarteKpi(
        key: const Key('kpi-Femelles'),
        libelle: 'Femelles',
        icone: SymbolesAgri.female,
        couleurLisere: AgriColors.accentYellow,
        couleurIcone: AgriColors.brandForest,
        valeur: '${k.femelles}',
      ),
      CarteKpi(
        key: const Key('kpi-Mâles'),
        libelle: 'Mâles',
        icone: SymbolesAgri.male,
        couleurLisere: AgriColors.brandForest,
        couleurIcone: AgriColors.brandForest,
        valeur: '${k.males}',
      ),
    ];
    final rangees = <Widget>[];
    for (var i = 0; i < cartes.length; i += colonnes) {
      if (i > 0) rangees.add(const SizedBox(height: AgriSpacing.md));
      rangees.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < colonnes; j++) ...[
                if (j > 0) const SizedBox(width: AgriSpacing.md),
                Expanded(child: i + j < cartes.length ? cartes[i + j] : const SizedBox.shrink()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rangees);
  }

  static const _entete = TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgriColors.outline);

  Widget _filtre(Key cle, String valeur, List<(String, String)> options, ValueChanged<String> surChangement) => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        key: cle,
        value: valeur,
        style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.onSurface),
        items: [for (final (v, l) in options) DropdownMenuItem(value: v, child: Text(l))],
        onChanged: (v) => surChangement(v ?? ''),
      ),
    ),
  );

  /// `bg-white rounded-lg border shadow-sm overflow-hidden` : barre d'outils puis tableau.
  Widget _carteTableau() {
    Widget cellule(int flex, String texte, {TextAlign alignement = TextAlign.left}) => Expanded(
      flex: flex,
      child: Text(texte.toUpperCase(), textAlign: alignement, style: _entete),
    );
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
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AgriColors.outlineVariant))),
            child: Wrap(
              spacing: AgriSpacing.sm,
              runSpacing: AgriSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  height: 36,
                  child: TextField(
                    key: const Key('repro-recherche'),
                    controller: _recherche,
                    onChanged: _rechercher,
                    style: const TextStyle(fontSize: AgriTypography.xs),
                    decoration: InputDecoration(
                      hintText: 'Rechercher un identifiant, une race...',
                      hintStyle: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
                      prefixIcon: const Icon(SymbolesAgri.search, size: 18, color: AgriColors.outline),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AgriRadius.lg),
                        borderSide: const BorderSide(color: AgriColors.outlineVariant),
                      ),
                    ),
                  ),
                ),
                _filtre(const Key('repro-filtre-espece'), _espece, [('', 'Toutes les espèces'), for (final e in _especes) (e.id, e.label)], (v) {
                  _espece = v;
                  _charger();
                }),
                _filtre(const Key('repro-filtre-statut'), _statut, RegistreReproducteursScreen.statuts, (v) {
                  _statut = v;
                  _charger();
                }),
              ],
            ),
          ),
          Container(
            color: AgriColors.surfaceZebra,
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
            child: Row(
              children: [
                cellule(3, 'Identifiant'),
                cellule(2, 'Espèce'),
                cellule(2, 'Sexe'),
                cellule(3, 'Race'),
                cellule(2, 'Bande'),
                cellule(1, 'Cage'),
                cellule(2, 'Statut', alignement: TextAlign.center),
                cellule(2, 'Actions', alignement: TextAlign.right),
              ],
            ),
          ),
          if (_lignes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AgriSpacing.lg),
              child: Text(
                'Aucun reproducteur enregistré pour ces critères.',
                key: Key('registre-vide'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AgriTypography.base, color: AgriColors.outline),
              ),
            ),
          for (final (i, l) in _lignes.indexed) _ligne(l, i),
        ],
      ),
    );
  }

  Widget _ligne(LigneReproducteur l, int index) {
    final a = l.animal;
    const corps = TextStyle(fontSize: AgriTypography.xs);
    final present = a.status == 'actif';
    return Container(
      key: Key('reproducteur-ligne-${a.id}'),
      decoration: BoxDecoration(
        color: index.isEven ? AgriColors.surfaceCard : AgriColors.surfaceZebra,
        border: const Border(top: BorderSide(color: AgriColors.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: widget.onOuvrirFiche == null ? null : () => widget.onOuvrirFiche!(a.id),
                  child: Text(
                    a.identifier,
                    style: corps.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: AgriColors.brandEmerald),
                  ),
                ),
                ..._etatEnvoi(l),
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(l.especeLibelle ?? '—', style: corps)),
          Expanded(flex: 2, child: Text(a.sex == 'F' ? 'Femelle' : 'Mâle', style: corps)),
          Expanded(flex: 3, child: Text((a.breed ?? '').isEmpty ? '—' : a.breed!, style: corps)),
          Expanded(flex: 2, child: Text(l.lotCode ?? '—', style: corps)),
          Expanded(flex: 1, child: Text((a.cage ?? '').isEmpty ? '—' : a.cage!, style: corps)),
          Expanded(flex: 2, child: Center(child: _statutBadge(a, present))),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _action('reproducteur-fiche-${a.id}', 'Consulter la fiche', SymbolesAgri.visibility, AgriColors.brandEmerald, () => widget.onOuvrirFiche?.call(a.id)),
                if (widget.peutGerer) ...[
                  _action('reproducteur-modifier-${a.id}', 'Modifier', SymbolesAgri.edit, AgriColors.infoBlue, () => _modifier(a)),
                  if (present)
                    _action('reproducteur-sortie-${a.id}', 'Enregistrer une sortie', SymbolesAgri.logout, AgriColors.errorDeep, () => _sortie(a)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `text-[11px] font-bold px-sm py-0.5 rounded-full` : « Actif » émeraude, sinon le libellé du statut
  /// (`$animal->status_label` : « Réformé », « Vendu », « Mort ») en gris, le motif de sortie en info-bulle.
  Widget _statutBadge(Sujet a, bool present) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: present ? AgriColors.brandEmerald.withValues(alpha: 0.10) : AgriColors.surfaceZebra,
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
      child: Text(
        key: Key('reproducteur-statut-${a.id}'),
        ReproducteursRepository.libelleStatut(a.status),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: present ? AgriColors.brandEmerald : AgriColors.outline),
      ),
    );
    return present || (a.exitReason ?? '').isEmpty ? badge : Tooltip(message: a.exitReason!, child: badge);
  }

  Widget _action(String cle, String infobulle, IconData icone, Color couleur, VoidCallback surAppui) => Tooltip(
    message: infobulle,
    child: InkWell(
      key: Key(cle),
      onTap: surAppui,
      borderRadius: BorderRadius.circular(AgriRadius.full),
      child: Padding(padding: const EdgeInsets.all(4), child: Icon(icone, size: 18, color: couleur)),
    ),
  );

  /// ➕ Ajout du poste : l'état d'envoi d'un sujet de ce poste, sous son identifiant.
  List<Widget> _etatEnvoi(LigneReproducteur l) {
    final a = l.animal;
    if (a.syncStatus == SyncStatus.synced) return const [];
    final refuse = a.syncStatus == SyncStatus.conflict;
    return [
      const SizedBox(height: 2),
      Container(
        key: Key('reproducteur-etat-${a.id}'),
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: refuse ? AgriColors.errorBg : AgriColors.accentYellow.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
        child: Text(
          refuse ? 'Refusé' : 'À envoyer',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: refuse ? AgriColors.errorDeep : AgriColors.brandForest),
        ),
      ),
      if (refuse)
        Text(
          l.motifRefus ?? 'Refus sans motif communiqué.',
          key: Key('reproducteur-motif-${a.id}'),
          style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
        ),
    ];
  }

  // ── Gestes ────────────────────────────────────────────────────────────────────────────────────────────────────────

  /// `newAnimal()` → `modal-reproducteur`.
  Future<void> _nouveau() async {
    final fait = await afficherModale<String>(
      context: context,
      constructeur: (_) => _ModaleReproducteur(depot: widget.depot, aujourdhui: _maintenant()),
    );
    await _apres(fait);
  }

  /// `editAnimal($id)` → `modal-reproducteur`.
  Future<void> _modifier(Sujet a) async {
    final fait = await afficherModale<String>(
      context: context,
      constructeur: (_) => _ModaleReproducteur(depot: widget.depot, aujourdhui: _maintenant(), sujet: a),
    );
    await _apres(fait);
  }

  /// `openExit($id)` → `modal-sortie-reproducteur`.
  Future<void> _sortie(Sujet a) async {
    final fait = await afficherModale<String>(
      context: context,
      constructeur: (_) => _ModaleSortie(depot: widget.depot, sujet: a, aujourdhui: _maintenant()),
    );
    await _apres(fait);
  }

  Future<void> _apres(String? toast) async {
    if (toast == null || !mounted) return;
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(
      context,
      toast,
      type: toast == ReproducteursRepository.toastSortie ? TypeToast.avertissement : TypeToast.succes,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Modale « Enregistrer un Reproducteur » / « Modifier le Reproducteur »
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class _ModaleReproducteur extends StatefulWidget {
  const _ModaleReproducteur({required this.depot, required this.aujourdhui, this.sujet});

  final ReproducteursRepository depot;
  final DateTime aujourdhui;

  /// `null` : création ; sinon `editAnimal`.
  final Sujet? sujet;

  @override
  State<_ModaleReproducteur> createState() => _ModaleReproducteurState();
}

class _ModaleReproducteurState extends State<_ModaleReproducteur> {
  List<EspeceElevage> _especes = const [];
  List<LivestockLot> _bandes = const [];
  late String _espece;
  late String _bande;
  late String _sexe;
  DateTime? _naissance;
  late DateTime? _entree;
  late final TextEditingController _identifiant;
  late final TextEditingController _race;
  late final TextEditingController _cage;
  late final TextEditingController _origine;
  Map<String, String> _erreurs = const {};

  @override
  void initState() {
    super.initState();
    final f = widget.sujet == null
        ? FormulaireReproducteur(entryDate: DateTime(widget.aujourdhui.year, widget.aujourdhui.month, widget.aujourdhui.day))
        : FormulaireReproducteur.depuis(widget.sujet!);
    _espece = f.speciesId;
    _bande = f.lotId;
    _sexe = f.sex;
    _naissance = f.birthDate;
    _entree = f.entryDate;
    _identifiant = TextEditingController(text: f.identifier);
    _race = TextEditingController(text: f.breed);
    _cage = TextEditingController(text: f.cage);
    _origine = TextEditingController(text: f.origin);
    _chargerOptions();
  }

  @override
  void dispose() {
    _identifiant.dispose();
    _race.dispose();
    _cage.dispose();
    _origine.dispose();
    super.dispose();
  }

  Future<void> _chargerOptions() async {
    final especes = await widget.depot.especesDuFormulaire(sujet: widget.sujet);
    final bandes = await widget.depot.bandes(speciesId: _espece);
    if (!mounted) return;
    setState(() {
      _especes = especes;
      _bandes = bandes;
    });
  }

  /// `wire:model.live="species_id"` : les bandes proposées sont celles de l'espèce ; une bande qui n'en est plus n'est pas gardée.
  Future<void> _choisirEspece(String id) async {
    final bandes = await widget.depot.bandes(speciesId: id);
    if (!mounted) return;
    setState(() {
      _espece = id;
      _bandes = bandes;
      if (!bandes.any((b) => b.id == _bande)) _bande = '';
    });
  }

  FormulaireReproducteur _formulaire() => FormulaireReproducteur(
    speciesId: _espece,
    identifier: _identifiant.text,
    lotId: _bande,
    sex: _sexe,
    breed: _race.text,
    birthDate: _naissance,
    entryDate: _entree,
    origin: _origine.text,
    cage: _cage.text,
  );

  Future<void> _enregistrer() async {
    setState(() => _erreurs = const {});
    try {
      if (widget.sujet == null) {
        await widget.depot.enregistrer(_formulaire());
      } else {
        await widget.depot.modifier(widget.sujet!.id, _formulaire());
      }
    } on ReproducteurRefuse catch (e) {
      if (mounted) setState(() => _erreurs = e.erreurs);
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(widget.sujet == null ? ReproducteursRepository.toastEnregistre : ReproducteursRepository.toastMisAJour);
    }
  }

  Future<DateTime?> _choisirDate(DateTime? depart) => showDatePicker(
    context: context,
    initialDate: depart ?? widget.aujourdhui,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  /// `grid grid-cols-1 sm:grid-cols-2 gap-md` : deux colonnes dès 640 px (`sm:`), une seule en dessous.
  Widget _paire(Widget gauche, Widget droite) => AgriBreakpoints.petit(context)
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: gauche),
            const SizedBox(width: AgriSpacing.md),
            Expanded(child: droite),
          ],
        )
      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [gauche, droite]);

  @override
  Widget build(BuildContext context) {
    final edition = widget.sujet != null;
    return ModaleAgri(
      largeur: LargeurModale.lg,
      titre: edition ? 'Modifier le Reproducteur' : 'Enregistrer un Reproducteur',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _paire(
            BlocChampModale(
              libelle: 'Identifiant (boucle) *',
              erreur: _erreurs['identifier'],
              cleErreur: const Key('repro-erreur-identifier'),
              // BS-Q13 : `@if($editingId)` du Blade — `<input disabled title="…">` et son aide.
              aide: edition ? ReproducteursRepository.messageIdentifiantFige : null,
              enfant: KeyedSubtree(
                key: const Key('repro-identifiant'),
                child: edition
                    ? Tooltip(
                        message: ReproducteursRepository.messageIdentifiantFige,
                        child: ChampLectureModale(valeur: _identifiant.text),
                      )
                    : ChampTexteModale(controleur: _identifiant, indice: 'ex : LAP-2026-0143', enErreur: _erreurs.containsKey('identifier')),
              ),
            ),
            BlocChampModale(
              libelle: 'Espèce *',
              erreur: _erreurs['species_id'],
              cleErreur: const Key('repro-erreur-species_id'),
              enfant: KeyedSubtree(
                key: const Key('repro-espece'),
                child: ChampListeModale(
                  valeur: _espece,
                  vide: '-- Sélectionner --',
                  enErreur: _erreurs.containsKey('species_id'),
                  options: [for (final e in _especes) (e.id, e.label)],
                  surChangement: _choisirEspece,
                ),
              ),
            ),
          ),
          _paire(
            BlocChampModale(
              libelle: "Bande d'appartenance",
              erreur: _erreurs['lot_id'],
              cleErreur: const Key('repro-erreur-lot_id'),
              enfant: KeyedSubtree(
                key: const Key('repro-bande'),
                child: ChampListeModale(
                  valeur: _bande,
                  vide: '-- Aucune --',
                  options: [for (final b in _bandes) (b.id, b.code)],
                  surChangement: (v) => setState(() => _bande = v),
                ),
              ),
            ),
            BlocChampModale(
              libelle: 'Sexe *',
              erreur: _erreurs['sex'],
              cleErreur: const Key('repro-erreur-sex'),
              enfant: KeyedSubtree(
                key: const Key('repro-sexe'),
                child: ChampListeModale(
                  valeur: _sexe,
                  options: const [('F', 'Femelle'), ('M', 'Mâle')],
                  surChangement: (v) => setState(() => _sexe = v),
                ),
              ),
            ),
          ),
          _paire(
            BlocChampModale(
              libelle: 'Race',
              erreur: _erreurs['breed'],
              cleErreur: const Key('repro-erreur-breed'),
              enfant: KeyedSubtree(
                key: const Key('repro-race'),
                child: ChampTexteModale(controleur: _race, indice: 'ex : Néo-Zélandais Blanc', enErreur: _erreurs.containsKey('breed')),
              ),
            ),
            BlocChampModale(
              libelle: 'Cage',
              erreur: _erreurs['cage'],
              cleErreur: const Key('repro-erreur-cage'),
              enfant: KeyedSubtree(
                key: const Key('repro-cage'),
                child: ChampTexteModale(controleur: _cage, indice: 'ex : C5', enErreur: _erreurs.containsKey('cage')),
              ),
            ),
          ),
          _paire(
            Padding(
              padding: const EdgeInsets.only(bottom: AgriSpacing.md),
              child: ChampDateFormulaire(
                cle: const Key('repro-naissance'),
                etiquette: 'Date de Naissance',
                valeur: _naissance,
                erreur: _erreurs['birth_date'],
                cleErreur: const Key('repro-erreur-birth_date'),
                onTap: () async {
                  final d = await _choisirDate(_naissance);
                  if (d != null) setState(() => _naissance = d);
                },
                surEffacer: _naissance == null ? null : () => setState(() => _naissance = null),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AgriSpacing.md),
              child: ChampDateFormulaire(
                cle: const Key('repro-entree'),
                etiquette: "Date d'Entrée *",
                valeur: _entree,
                erreur: _erreurs['entry_date'],
                cleErreur: const Key('repro-erreur-entry_date'),
                onTap: () async {
                  final d = await _choisirDate(_entree);
                  if (d != null) setState(() => _entree = d);
                },
              ),
            ),
          ),
          BlocChampModale(
            libelle: 'Origine',
            erreur: _erreurs['origin'],
            cleErreur: const Key('repro-erreur-origin'),
            enfant: KeyedSubtree(
              key: const Key('repro-origine'),
              child: ChampTexteModale(controleur: _origine, indice: 'ex : Naissance interne (Lot LOT-CUNI-2026-002)', enErreur: _erreurs.containsKey('origin')),
            ),
          ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
        BoutonModalePrimaire(key: const Key('repro-enregistrer'), libelle: 'Enregistrer', onPressed: _enregistrer),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Modale « Enregistrer une Sortie »
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class _ModaleSortie extends StatefulWidget {
  const _ModaleSortie({required this.depot, required this.sujet, required this.aujourdhui});

  final ReproducteursRepository depot;
  final Sujet sujet;
  final DateTime aujourdhui;

  @override
  State<_ModaleSortie> createState() => _ModaleSortieState();
}

class _ModaleSortieState extends State<_ModaleSortie> {
  String _statut = 'reforme';
  late DateTime _date = DateTime(widget.aujourdhui.year, widget.aujourdhui.month, widget.aujourdhui.day);
  final _precision = TextEditingController();
  Map<String, String> _erreurs = const {};

  @override
  void dispose() {
    _precision.dispose();
    super.dispose();
  }

  Future<void> _confirmer() async {
    setState(() => _erreurs = const {});
    try {
      await widget.depot.sortir(widget.sujet.id, FormulaireSortie(status: _statut, exitDate: _date, reason: _precision.text));
    } on ReproducteurRefuse catch (e) {
      if (mounted) setState(() => _erreurs = e.erreurs);
      return;
    }
    if (mounted) Navigator.of(context).pop(ReproducteursRepository.toastSortie);
  }

  @override
  Widget build(BuildContext context) {
    const texte = TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline);
    return ModaleAgri(
      largeur: LargeurModale.md,
      titre: 'Enregistrer une Sortie',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: AgriSpacing.md),
            child: Text.rich(
              TextSpan(
                style: texte,
                children: [
                  TextSpan(text: "Le sujet cesse d'être présent et sa fiche le mentionne. "),
                  TextSpan(text: "L'effectif de la bande n'est pas modifié ici", style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: " — c'est la fiche journalière qui fait foi sur les quantités, et le mouvement doit y être saisi."),
                ],
              ),
            ),
          ),
          BlocChampModale(
            libelle: 'Motif de sortie *',
            erreur: _erreurs['exitStatus'],
            cleErreur: const Key('sortie-erreur-exitStatus'),
            enfant: KeyedSubtree(
              key: const Key('sortie-statut'),
              child: ChampListeModale(
                valeur: _statut,
                enErreur: _erreurs.containsKey('exitStatus'),
                options: const [('reforme', 'Réforme'), ('vendu', 'Vente'), ('mort', 'Mortalité')],
                surChangement: (v) => setState(() => _statut = v),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AgriSpacing.md),
            child: ChampDateFormulaire(
              cle: const Key('sortie-date'),
              etiquette: 'Date de sortie *',
              valeur: _date,
              erreur: _erreurs['exit_date'],
              cleErreur: const Key('sortie-erreur-exit_date'),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => _date = d);
              },
            ),
          ),
          BlocChampModale(
            libelle: 'Précision',
            erreur: _erreurs['exit_reason'],
            cleErreur: const Key('sortie-erreur-exit_reason'),
            enfant: KeyedSubtree(
              key: const Key('sortie-precision'),
              child: ChampTexteModale(controleur: _precision, indice: 'ex : Réforme pour âge', enErreur: _erreurs.containsKey('exit_reason')),
            ),
          ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
        BoutonModalePrimaire(key: const Key('sortie-confirmer'), libelle: 'Confirmer la Sortie', couleur: AgriColors.errorRed, onPressed: _confirmer),
      ],
    );
  }
}
