import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/champs_date_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import '../stocks/pmp_service.dart';
import 'champs_modale_elevage.dart';
import 'sujets_entrees_repository.dart';

/// « Enregistrer des Sujets » — `resources/views/livewire/elevage/enregistrer-sujets.blade.php` (maître, article 5).
///
/// Ticket BS2 — l'écran suit son Blade, section par section :
///   1. en-tête : icône `pets`, « Enregistrer des Sujets », sous-titre du Blade, et — avec le droit `manage-elevage` —
///      « Nouveau Sujet » ;
///   2. trois `x-kpi-card` émeraude : Naissances (mois) · Acquisitions (mois) · Effectif Total ;
///   3. la carte du journal : recherche d'un code de bande (300 ms), filtre « Tous les statuts / Naissance / Achat »,
///      puis le tableau Date · Bande · Espèce · Origine · Quantité · Actions — UNE LIGNE PAR ORIGINE d'une fiche ;
///   4. « Modifier » (`manage-elevage`) et « Archiver » (`archive-elevage`, confirmation) ou « Lecture seule » ;
///   5. les modales « Nouveau Sujet » et « Modifier le Sujet ».
///
/// Toasts du web : « Enregistrement effectué avec succès. » (succès), « Modification enregistrée avec succès. »
/// (succès), « Entrée archivée avec succès. » (avertissement). Un refus (exercice clos, effectif négatif) se lit sous son
/// champ dans la modale, ou en toast d'erreur pour un archivage.
///
/// ➕ Ajout du poste, gardé : sous la date d'une entrée de CE poste pas encore reçue par le serveur, « À envoyer » ;
/// « Refusée » et le motif du serveur mot pour mot quand l'envoi de la fiche a été refusé.
class EnregistrerSujetsScreen extends StatefulWidget {
  const EnregistrerSujetsScreen({
    super.key,
    required this.depot,
    this.peutGerer = true,
    this.peutArchiver = true,
    this.horloge,
  });

  final SujetsEntreesRepository depot;

  /// `@can('manage-elevage')` : « Nouveau Sujet » et « Modifier ».
  final bool peutGerer;

  /// `@can('archive-elevage')` : « Archiver ».
  final bool peutArchiver;

  final DateTime Function()? horloge;

  /// `wire:model.live.debounce.300ms` du champ « Rechercher un code de bande... ».
  static const delaiRecherche = Duration(milliseconds: 300);

  @override
  State<EnregistrerSujetsScreen> createState() => _EnregistrerSujetsScreenState();
}

class _EnregistrerSujetsScreenState extends State<EnregistrerSujetsScreen> {
  IndicateursSujets? _kpis;
  List<LigneSujet> _lignes = const [];
  final _recherche = TextEditingController();
  String _rechercheAppliquee = '';
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
    final lignes = await widget.depot.entrees(recherche: _rechercheAppliquee, statut: _statut);
    if (!mounted) return;
    setState(() {
      _kpis = kpis;
      _lignes = lignes;
    });
  }

  void _rechercher(String texte) {
    _attente?.cancel();
    _attente = Timer(EnregistrerSujetsScreen.delaiRecherche, () {
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
                  _indicateurs(k),
                  const SizedBox(height: AgriSpacing.md),
                  _journal(),
                ],
              ),
            ),
    );
  }

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
                'Enregistrer des Sujets',
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
          "Journal des ENTRÉES (Phase 1 du cycle) : naissances locales et acquisitions externes. Chaque entrée valide alimente ensuite une Bande/Lot pour le suivi continu de l'effectif.",
          style: TextStyle(fontSize: large ? AgriTypography.sm : AgriTypography.xs, color: AgriColors.outline),
        ),
      ],
    );
    final bouton = widget.peutGerer
        ? ElevatedButton.icon(
            key: const Key('sujet-nouveau'),
            onPressed: _nouveau,
            icon: const Icon(SymbolesAgri.add_circle, size: 18),
            label: const Text('Nouveau Sujet'),
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

  /// `x-kpi-accordion` : trois `x-kpi-card` émeraude, sans légende.
  Widget _indicateurs(IndicateursSujets k) {
    final colonnes = AgriBreakpoints.tresLarge(context) ? 4 : 2;
    final cartes = <Widget>[
      CarteKpi(
        key: const Key('kpi-Naissances (mois)'),
        libelle: 'Naissances (mois)',
        icone: SymbolesAgri.child_care,
        couleurLisere: AgriColors.brandEmerald,
        couleurIcone: AgriColors.brandEmerald,
        valeur: '${k.naissancesMois}',
      ),
      CarteKpi(
        key: const Key('kpi-Acquisitions (mois)'),
        libelle: 'Acquisitions (mois)',
        icone: SymbolesAgri.shopping_cart,
        couleurLisere: AgriColors.brandEmerald,
        couleurIcone: AgriColors.brandEmerald,
        valeur: '${k.acquisitionsMois}',
      ),
      CarteKpi(
        key: const Key('kpi-Effectif Total'),
        libelle: 'Effectif Total',
        icone: SymbolesAgri.pets,
        couleurLisere: AgriColors.brandEmerald,
        couleurIcone: AgriColors.brandEmerald,
        valeur: PmpService.francs(k.effectifTotal.toDouble()),
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

  /// `bg-white rounded-lg border shadow-sm overflow-hidden` : barre d'outils puis tableau.
  Widget _journal() {
    Widget cellule(int flex, String texte, {bool droite = false}) => Expanded(
      flex: flex,
      child: Text(texte.toUpperCase(), textAlign: droite ? TextAlign.right : TextAlign.left, style: _entete),
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
                    key: const Key('sujets-recherche'),
                    controller: _recherche,
                    onChanged: _rechercher,
                    style: const TextStyle(fontSize: AgriTypography.xs),
                    decoration: InputDecoration(
                      hintText: 'Rechercher un code de bande...',
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
                      key: const Key('sujets-filtre-statut'),
                      value: _statut,
                      style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Tous les statuts')),
                        DropdownMenuItem(value: 'Naissance', child: Text('Naissance')),
                        DropdownMenuItem(value: 'Achat', child: Text('Achat')),
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
          ),
          Container(
            color: AgriColors.surfaceZebra,
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
            child: Row(
              children: [
                cellule(2, 'Date'),
                cellule(3, 'Bande'),
                cellule(3, 'Espèce'),
                cellule(2, 'Origine'),
                cellule(2, 'Quantité'),
                cellule(2, 'Actions', droite: true),
              ],
            ),
          ),
          if (_lignes.isEmpty) _vide(),
          for (final (i, l) in _lignes.indexed) _ligne(l, i),
        ],
      ),
    );
  }

  /// État vide du Blade : icône `inbox` 44 px, « Aucun résultat trouvé », « + Nouveau Sujet ».
  Widget _vide() => Padding(
    padding: const EdgeInsets.symmetric(vertical: AgriSpacing.xl),
    child: Column(
      key: const Key('sujets-vide'),
      children: [
        const Icon(SymbolesAgri.inbox, size: 44, color: AgriColors.outlineVariant),
        const SizedBox(height: AgriSpacing.sm),
        const Text(
          'Aucun résultat trouvé',
          style: TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.w600, color: AgriColors.onSurface),
        ),
        if (widget.peutGerer)
          TextButton(
            key: const Key('sujets-vide-nouveau'),
            onPressed: _nouveau,
            child: const Text(
              '+ Nouveau Sujet',
              style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: AgriColors.brandEmerald),
            ),
          ),
      ],
    ),
  );

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _ligne(LigneSujet l, int index) {
    const corps = TextStyle(fontSize: AgriTypography.xs);
    final f = l.fiche;
    final naissance = l.origine == 'Naissance';
    final cle = '${f.id}-${l.origine}';
    return Container(
      key: Key('sujet-ligne-$cle'),
      decoration: BoxDecoration(
        color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
        border: const Border(top: BorderSide(color: AgriColors.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(_jour(f.entryDate), style: corps), ..._etatEnvoi(l, cle)],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(l.codeBande ?? '', style: corps.copyWith(fontWeight: FontWeight.bold, color: AgriColors.brandEmerald)),
          ),
          Expanded(flex: 3, child: Text(l.especeLibelle ?? '', style: corps)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: naissance ? AgriColors.brandEmerald.withValues(alpha: 0.10) : const Color(0xFFDBEAFE),
                  border: Border.all(color: naissance ? AgriColors.brandEmerald.withValues(alpha: 0.30) : const Color(0xFF93C5FD)),
                  borderRadius: BorderRadius.circular(AgriRadius.full),
                ),
                child: Text(
                  l.origine,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: naissance ? AgriColors.brandEmerald : AgriColors.infoBlue),
                ),
              ),
            ),
          ),
          Expanded(flex: 2, child: Text('${l.quantite}', key: Key('sujet-quantite-$cle'), style: corps)),
          Expanded(
            flex: 2,
            child: widget.peutGerer
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _action('sujet-modifier-$cle', 'Modifier', SymbolesAgri.edit, AgriColors.infoBlue, () => _modifier(l)),
                      if (widget.peutArchiver)
                        _action('sujet-archiver-$cle', 'Archiver', SymbolesAgri.delete, AgriColors.errorDeep, () => _archiver(l)),
                    ],
                  )
                : const Text(
                    'Lecture seule',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: AgriColors.outline),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _action(String cle, String infobulle, IconData icone, Color couleur, VoidCallback surAppui) => Tooltip(
    message: infobulle,
    child: InkWell(
      key: Key(cle),
      onTap: surAppui,
      borderRadius: BorderRadius.circular(AgriRadius.full),
      child: Padding(padding: const EdgeInsets.all(4), child: Icon(icone, size: 16, color: couleur)),
    ),
  );

  /// ➕ Ajout du poste : l'état d'envoi de la fiche de ce poste, sous la date.
  List<Widget> _etatEnvoi(LigneSujet l, String cle) {
    final f = l.fiche;
    if (f.syncStatus == SyncStatus.synced) return const [];
    final refusee = f.syncStatus == SyncStatus.conflict;
    return [
      const SizedBox(height: 2),
      Container(
        key: Key('sujet-etat-$cle'),
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: refusee ? AgriColors.errorBg : AgriColors.accentYellow.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
        child: Text(
          refusee ? 'Refusée' : 'À envoyer',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: refusee ? AgriColors.errorDeep : AgriColors.brandForest),
        ),
      ),
      if (refusee)
        Text(
          l.motifRefus ?? 'Refus sans motif communiqué.',
          key: Key('sujet-motif-$cle'),
          style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
        ),
    ];
  }

  // ── Gestes ────────────────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> _nouveau() async {
    final ok = await afficherModale<bool>(
      context: context,
      constructeur: (_) => _ModaleSujet(depot: widget.depot, aujourdhui: _maintenant()),
    );
    if (ok != true || !mounted) return;
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(context, SujetsEntreesRepository.toastEnregistree);
  }

  Future<void> _modifier(LigneSujet l) async {
    final ok = await afficherModale<bool>(
      context: context,
      constructeur: (_) => _ModaleSujet(depot: widget.depot, aujourdhui: _maintenant(), existante: l),
    );
    if (ok != true || !mounted) return;
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(context, SujetsEntreesRepository.toastModifiee);
  }

  /// `archiveEntry($id, $origine)` derrière `x-modal-confirm-delete` : « Confirmer l'archivage », le libellé de la
  /// ligne (`CODE — Origine (quantité) du JJ/MM/AAAA`), « Annuler » puis « Archiver ».
  Future<void> _archiver(LigneSujet l) async {
    final confirme = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (contexte) => ModaleConfirmation(
        icone: SymbolesAgri.archive,
        couleurIcone: AgriColors.errorDeep,
        titre: "Confirmer l'archivage",
        message:
            '${l.codeBande} — ${l.origine} (${l.quantite}) du ${_jour(l.fiche.entryDate)} sera marqué(e) comme archivé(e) '
            "(statut inactif). Aucune suppression définitive n'est effectuée.",
        actions: [
          BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(contexte).pop(false)),
          BoutonModalePrimaire(
            key: const Key('archivage-sujet-confirmer'),
            libelle: 'Archiver',
            couleur: AgriColors.errorRed,
            onPressed: () => Navigator.of(contexte).pop(true),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    try {
      await widget.depot.archiver(l.fiche.id, l.origine);
    } on SujetRefuse catch (e) {
      // Pas de modale ouverte : le refus se lit en toast d'erreur.
      if (!mounted) return;
      ToastAgri.afficher(context, e.erreurs.values.first, type: TypeToast.erreur);
      await _charger();
      return;
    } on RefusExercice catch (e) {
      if (!mounted) return;
      ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      return;
    }
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(context, SujetsEntreesRepository.toastArchivee, type: TypeToast.avertissement);
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Modales « Nouveau Sujet » / « Modifier le Sujet »
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class _ModaleSujet extends StatefulWidget {
  const _ModaleSujet({required this.depot, required this.aujourdhui, this.existante});

  final SujetsEntreesRepository depot;
  final DateTime aujourdhui;

  /// La ligne en modification ; `null` : « Nouveau Sujet ».
  final LigneSujet? existante;

  @override
  State<_ModaleSujet> createState() => _ModaleSujetState();
}

class _ModaleSujetState extends State<_ModaleSujet> {
  List<EspeceElevage> _especes = const [];
  List<LivestockLot> _bandes = const [];
  String _espece = '';
  String _bande = '';
  late String _origine = widget.existante?.origine ?? '';
  late DateTime _date = widget.existante?.fiche.entryDate ?? DateTime(widget.aujourdhui.year, widget.aujourdhui.month, widget.aujourdhui.day);
  late final TextEditingController _quantite = TextEditingController(text: '${widget.existante?.quantite ?? 1}');
  Map<String, String> _erreurs = const {};

  bool get _creation => widget.existante == null;

  @override
  void initState() {
    super.initState();
    if (_creation) {
      widget.depot.especes().then((e) {
        if (mounted) setState(() => _especes = e);
      });
    } else {
      _bande = widget.existante!.fiche.lotId;
    }
  }

  @override
  void dispose() {
    _quantite.dispose();
    super.dispose();
  }

  /// `updatedSpeciesId()` : la bande choisie est vidée, la liste est celle de la nouvelle espèce.
  Future<void> _choisirEspece(String id) async {
    final bandes = await widget.depot.bandes(id);
    if (!mounted) return;
    setState(() {
      _espece = id;
      _bande = '';
      _bandes = bandes;
    });
  }

  Future<void> _enregistrer() async {
    setState(() => _erreurs = const {});
    final formulaire = FormulaireSujet(
      speciesId: _espece,
      lotId: _bande,
      origine: _origine,
      quantite: _quantite.text,
      date: _date,
    );
    try {
      if (_creation) {
        await widget.depot.ajouter(formulaire);
      } else {
        await widget.depot.modifier(widget.existante!.fiche.id, widget.existante!.origine, formulaire);
      }
    } on SujetRefuse catch (e) {
      if (!mounted) return;
      if (e.erreurs.containsKey('entry')) {
        // L'entrée n'existe plus : la modale se ferme, le motif du web en toast d'erreur.
        Navigator.of(context).pop(false);
        ToastAgri.afficher(context, e.erreurs['entry']!, type: TypeToast.erreur);
        return;
      }
      setState(() => _erreurs = e.erreurs);
      return;
    } on RefusExercice catch (e) {
      // Exercice clos : le motif R4, sous « Date ».
      if (mounted) setState(() => _erreurs = {'entry_date': e.motif});
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.existante;
    return ModaleAgri(
      largeur: LargeurModale.md,
      titre: _creation ? 'Nouveau Sujet' : 'Modifier le Sujet',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_creation) ...[
            BlocChampModale(
              libelle: 'Espèce *',
              erreur: _erreurs['species_id'],
              cleErreur: const Key('sujet-erreur-species_id'),
              enfant: KeyedSubtree(
                key: const Key('sujet-espece'),
                child: ChampListeModale(
                  valeur: _espece,
                  vide: '-- Sélectionner --',
                  enErreur: _erreurs.containsKey('species_id'),
                  options: [for (final s in _especes) (s.id, s.label)],
                  surChangement: _choisirEspece,
                ),
              ),
            ),
            BlocChampModale(
              libelle: 'Bande / Lot de destination *',
              erreur: _erreurs['lot_id'],
              cleErreur: const Key('sujet-erreur-lot_id'),
              aide:
                  "Champ nécessaire pour rattacher l'entrée à une bande réelle — non présent tel quel dans le formulaire "
                  "d'origine (voir docblock du composant).",
              enfant: KeyedSubtree(
                key: const Key('sujet-bande'),
                child: ChampListeModale(
                  valeur: _bande,
                  vide: _espece.isEmpty ? "Choisir d'abord une espèce" : '-- Sélectionner --',
                  desactive: _espece.isEmpty,
                  enErreur: _erreurs.containsKey('lot_id'),
                  options: [for (final b in _bandes) (b.id, '${b.code} (${b.currentQuantity} têtes)')],
                  surChangement: (v) => setState(() => _bande = v),
                ),
              ),
            ),
          ] else
            BlocChampModale(
              libelle: 'Bande / Lot',
              aide: "La bande d'une entrée n'est jamais modifiable : archivez l'entrée puis saisissez-la sur la bonne bande.",
              enfant: KeyedSubtree(key: const Key('sujet-edit-bande'), child: ChampLectureModale(valeur: e!.codeBande ?? '')),
            ),
          BlocChampModale(
            libelle: 'Origine *',
            erreur: _erreurs['origine'],
            cleErreur: const Key('sujet-erreur-origine'),
            enfant: KeyedSubtree(
              key: const Key('sujet-origine'),
              child: ChampListeModale(
                valeur: _origine,
                vide: _creation ? '-- Sélectionner --' : null,
                enErreur: _erreurs.containsKey('origine'),
                options: [for (final o in SujetsEntreesRepository.origines.keys) (o, o)],
                surChangement: (v) => setState(() => _origine = v),
              ),
            ),
          ),
          BlocChampModale(
            libelle: 'Quantité *',
            erreur: _erreurs['quantite'],
            cleErreur: const Key('sujet-erreur-quantite'),
            enfant: KeyedSubtree(
              key: const Key('sujet-quantite'),
              child: ChampTexteModale(controleur: _quantite, nombre: true, enErreur: _erreurs.containsKey('quantite')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AgriSpacing.md),
            child: ChampDateFormulaire(
              cle: const Key('sujet-date'),
              etiquette: 'Date *',
              valeur: _date,
              erreur: _erreurs['entry_date'],
              cleErreur: const Key('sujet-erreur-entry_date'),
              onTap: () async {
                final choisie = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (choisie != null) setState(() => _date = choisie);
              },
            ),
          ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
        BoutonModalePrimaire(
          key: const Key('sujet-enregistrer'),
          libelle: _creation ? 'Enregistrer' : 'Enregistrer les Modifications',
          onPressed: _enregistrer,
        ),
      ],
    );
  }
}
