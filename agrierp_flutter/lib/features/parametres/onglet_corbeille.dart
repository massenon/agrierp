import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/champs_date_agri.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import '../ventes/elements_ventes.dart';
import 'corbeille_repository.dart';

/// Ticket ARC4 (PRD `docs/prd/archives.md`) — onglet « Corbeille » du hub Paramètres, AU POSTE. Transposé de
/// `resources/views/livewire/parametres/corbeille.blade.php` et `Livewire\Parametres\Corbeille` (MAÎTRES, lus par
/// `test/corbeille_blade_test.dart` : libellés, colonnes, actions, messages, icônes).
///
///  1. en-tête : icône `restore_from_trash`, « Corbeille » et son sous-titre ;
///  2. trois cartes : Éléments archivés, Restaurables, Suppression définitive possible ;
///  3. l'encadré : ce qui n'entre pas dans la Corbeille et ce qui s'y consulte sans se restaurer ;
///  4. filtres : recherche, Type, « Archivé du », « Au », « Réinitialiser » (visible quand un filtre est posé) ;
///  5. tableau de six colonnes, 25 éléments par page ; « Restaurer » ou la phrase de refus ; « Supprimer définitivement »
///     ou la phrase de refus ;
///  6. modale « Supprimer définitivement ? » : le mot SUPPRIMER saisi à la main (le bouton reste grisé tant qu'il n'est
///     pas exact).
///
/// ⚠️⚠️ **RESTAURER ET SUPPRIMER SONT DES DEMANDES** (voir [CorbeilleRepository]) : la page l'écrit (toasts
/// « … demandée : elle sera faite par le serveur à la prochaine synchronisation. » — ÉCART ASSUMÉ, le web agit à l'instant)
/// et chaque ligne dit où en est sa demande : « Demande en attente d'envoi », « Demande traitée par le serveur »,
/// « Refusée par le serveur : » suivi du motif, mot pour mot.
///
/// ⚠️ ÉCARTS ASSUMÉS (hors ligne) : la mention « Archivé sur ce poste — pas encore synchronisé » sous une entité que ce poste
/// vient d'archiver ; les règles de cette ligne sont celles de son type, le serveur juge à l'envoi.
class OngletCorbeille extends StatefulWidget {
  const OngletCorbeille({super.key, required this.depot});

  final CorbeilleRepository depot;

  /// `wire:model.live.debounce.300ms` du champ de recherche.
  static const delaiRecherche = Duration(milliseconds: 300);

  static const parPage = 25;

  @override
  State<OngletCorbeille> createState() => _OngletCorbeilleState();
}

class _OngletCorbeilleState extends State<OngletCorbeille> {
  List<LigneCorbeille>? _lignes;

  final _recherche = TextEditingController();
  Timer? _minuterie;
  String _recherchee = '';
  String _type = '';
  DateTime? _du;
  DateTime? _au;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final lignes = await widget.depot.lignes();
    if (!mounted) return;
    setState(() => _lignes = lignes);
  }

  bool get _filtre => _recherchee != '' || _type != '' || _du != null || _au != null;

  @override
  Widget build(BuildContext context) {
    final toutes = _lignes;
    if (toutes == null) return const Center(child: CircularProgressIndicator());

    final large = AgriBreakpoints.large(context);
    final filtrees = CorbeilleRepository.filtrer(toutes, type: _type, recherche: _recherchee, du: _du, au: _au);

    return SingleChildScrollView(
      padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _entete(),
          const SizedBox(height: AgriSpacing.md),
          _cartes(toutes, context),
          const SizedBox(height: AgriSpacing.md),
          _encadre(),
          const SizedBox(height: AgriSpacing.md),
          _filtres(),
          const SizedBox(height: AgriSpacing.md),
          _tableau(filtrees, vide: toutes.isEmpty),
        ],
      ),
    );
  }

  // ── 1. En-tête ─────────────────────────────────────────────────────────────────────────────────────────────────────────

  Widget _entete() => const EnteteOnglet(
    enfant: TitreOnglet(
      icone: SymbolesAgri.restore_from_trash,
      titre: 'Corbeille',
      sousTitre:
          "Rien n'est effacé par erreur : tout enregistrement retiré d'un module est archivé ici. "
          'Restaurez-le, ou supprimez-le définitivement quand il n\'a aucune conséquence.',
    ),
  );

  // ── 2. Cartes ──────────────────────────────────────────────────────────────────────────────────────────────────────────

  Widget _cartes(List<LigneCorbeille> toutes, BuildContext context) {
    final c = CorbeilleRepository.cartes(toutes);

    return GrilleKpi(
      colonnes: AgriBreakpoints.petit(context) ? 3 : 1,
      children: [
        CarteKpi(
          key: const Key('kpi-Éléments archivés'),
          libelle: 'Éléments archivés',
          valeur: '${c.archives}',
          couleurLisere: AgriColors.brandForest,
          icone: SymbolesAgri.inventory_2,
          couleurIcone: AgriColors.brandForest,
        ),
        CarteKpi(
          key: const Key('kpi-Restaurables'),
          libelle: 'Restaurables',
          valeur: '${c.restaurables}',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.restore,
          couleurIcone: AgriColors.brandEmerald,
        ),
        CarteKpi(
          key: const Key('kpi-Suppression définitive possible'),
          libelle: 'Suppression définitive possible',
          valeur: '${c.supprimables}',
          couleurLisere: AgriColors.errorRed,
          icone: SymbolesAgri.delete,
          couleurIcone: AgriColors.errorRed,
        ),
      ],
    );
  }

  // ── 3. Encadré ─────────────────────────────────────────────────────────────────────────────────────────────────────────

  /// `bg-info-blue/10 border border-info-blue/20 rounded-lg p-md text-xs text-brand-forest`.
  Widget _encadre() {
    const gras = TextStyle(fontWeight: AgriTypography.gras);

    return Container(
      key: const Key('corbeille-encadre'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.infoBlue.withValues(alpha: 0.1),
        border: Border.all(color: AgriColors.infoBlue.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Text.rich(
        const TextSpan(
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.brandForest),
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.only(right: AgriSpacing.xs),
                child: Icon(SymbolesAgri.info, size: 16, color: AgriColors.brandForest),
              ),
            ),
            TextSpan(text: 'Les '),
            TextSpan(text: 'écritures comptables', style: gras),
            TextSpan(text: " n'apparaissent pas ici : une écriture ne se supprime pas, elle se contre-passe. Les "),
            TextSpan(text: 'comptes utilisateurs', style: gras),
            TextSpan(text: ' non plus : leur réactivation se fait depuis Gestion Utilisateurs. Une '),
            TextSpan(text: 'dépense', style: gras),
            TextSpan(text: ', une '),
            TextSpan(text: 'vente annulée', style: gras),
            TextSpan(text: ' ou un '),
            TextSpan(text: 'transfert annulé', style: gras),
            TextSpan(text: ' se consulte ici mais ne se restaure pas : sa contre-passation ou son mouvement ne seraient pas rejoués.'),
          ],
        ),
      ),
    );
  }

  // ── 4. Filtres ─────────────────────────────────────────────────────────────────────────────────────────────────────────

  Widget _filtres() {
    final etiquette = StylesChampsAgri.etiquetteFormulaire;

    Widget champ(String libelle, Widget enfant, {double largeur = 220}) => SizedBox(
      width: largeur,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.only(bottom: AgriSpacing.xs), child: Text(libelle.toUpperCase(), style: etiquette)),
          enfant,
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        boxShadow: AgriShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AgriSpacing.sm,
            runSpacing: AgriSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              champ('Recherche', _champRecherche(), largeur: 320),
              champ('Type', _menuType()),
              SizedBox(
                width: 200,
                child: ChampDateFormulaire(
                  cle: const Key('corbeille-du'),
                  etiquette: 'Archivé du',
                  valeur: _du,
                  onTap: () => _choisirDate(_du, debut: true),
                  surEffacer: _du == null ? null : () => setState(() {
                    _du = null;
                    _page = 1;
                  }),
                  cleEffacer: const Key('corbeille-du-effacer'),
                ),
              ),
              SizedBox(
                width: 200,
                child: ChampDateFormulaire(
                  cle: const Key('corbeille-au'),
                  etiquette: 'Au',
                  valeur: _au,
                  onTap: () => _choisirDate(_au, debut: false),
                  surEffacer: _au == null ? null : () => setState(() {
                    _au = null;
                    _page = 1;
                  }),
                  cleEffacer: const Key('corbeille-au-effacer'),
                ),
              ),
            ],
          ),
          if (_filtre)
            Padding(
              padding: const EdgeInsets.only(top: AgriSpacing.sm),
              child: TextButton(
                key: const Key('corbeille-reinitialiser'),
                onPressed: _reinitialiser,
                style: TextButton.styleFrom(foregroundColor: AgriColors.brandEmerald, padding: EdgeInsets.zero, minimumSize: Size.zero),
                child: const Text('Réinitialiser', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
              ),
            ),
        ],
      ),
    );
  }

  /// `h-10 pl-10 pr-md border border-outline-variant rounded-lg text-xs bg-white` + icône `search` 18 px à gauche.
  Widget _champRecherche() {
    final bord = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      borderSide: const BorderSide(color: AgriColors.outlineVariant),
    );

    return TextField(
      key: const Key('corbeille-recherche'),
      controller: _recherche,
      style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
      onChanged: (v) {
        _minuterie?.cancel();
        _minuterie = Timer(OngletCorbeille.delaiRecherche, () {
          if (!mounted) return;
          setState(() {
            _recherchee = v;
            _page = 1;
          });
        });
      },
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AgriColors.surfaceCard,
        hintText: 'Rechercher un élément archivé…',
        hintStyle: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        prefixIcon: const Icon(SymbolesAgri.search, size: 18, color: AgriColors.outline),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        contentPadding: const EdgeInsets.fromLTRB(0, AgriSpacing.sm, AgriSpacing.md, AgriSpacing.sm),
        border: bord,
        enabledBorder: bord,
        focusedBorder: bord,
      ),
    );
  }

  /// `<select class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">`.
  Widget _menuType() => Container(
    key: const Key('corbeille-type'),
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        isExpanded: true,
        value: _type,
        style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
        items: [
          const DropdownMenuItem(value: '', child: Text('Tous les types')),
          for (final t in TypesCorbeille.tous) DropdownMenuItem(value: t.cle, child: Text(t.libelle)),
        ],
        onChanged: (v) => setState(() {
          _type = v ?? '';
          _page = 1;
        }),
      ),
    ),
  );

  Future<void> _choisirDate(DateTime? valeur, {required bool debut}) async {
    final choix = await showDatePicker(
      context: context,
      initialDate: valeur ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('fr'),
    );
    if (choix == null || !mounted) return;
    setState(() {
      if (debut) {
        _du = choix;
      } else {
        _au = choix;
      }
      _page = 1;
    });
  }

  void _reinitialiser() {
    _minuterie?.cancel();
    _recherche.clear();
    setState(() {
      _recherchee = '';
      _type = '';
      _du = null;
      _au = null;
      _page = 1;
    });
  }

  // ── 5. Tableau ─────────────────────────────────────────────────────────────────────────────────────────────────────────

  static const _colonnes = [
    ColonneTableau('Type', 3),
    ColonneTableau('Élément', 4),
    ColonneTableau('Détail', 4),
    ColonneTableau('Module', 3),
    ColonneTableau('Archivé le', 3),
    ColonneTableau('Archivé par', 3),
    ColonneTableau('Actions', 6, droite: true),
  ];

  /// `ucfirst($element['module'])`.
  static String _majuscule(String texte) => texte.isEmpty ? texte : texte[0].toUpperCase() + texte.substring(1);

  /// `format('d/m/Y à H:i')`.
  static String _horodatage(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à '
            '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// « {total} élément(s) — page X sur Y » : le pied du Blade.
  static String texteDuPied({required int total, required int page, required int pages}) =>
      "$total ${total > 1 ? 'éléments' : 'élément'} — page $page sur $pages";

  Widget _tableau(List<LigneCorbeille> filtrees, {required bool vide}) {
    final pages = (filtrees.length / OngletCorbeille.parPage).ceil().clamp(1, 1 << 30);
    final courante = _page.clamp(1, pages);
    final visibles = filtrees.skip((courante - 1) * OngletCorbeille.parPage).take(OngletCorbeille.parPage).toList();

    return TableauAgri(
      colonnes: _colonnes,
      largeur: 1330,
      clePrefixe: 'corbeille',
      videTexte: vide
          ? 'La corbeille est vide — aucun élément archivé.'
          : 'Aucun élément archivé ne correspond à cette recherche.',
      lignes: [for (final l in visibles) _cellules(l)],
      pied: _pied(total: filtrees.length, page: courante, pages: pages),
    );
  }

  List<Widget> _cellules(LigneCorbeille l) => [
    Text(l.libelleType, style: styleCellule.copyWith(fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
    Text(l.titre, style: styleCellule),
    Text(l.detail != '' ? l.detail : '—', style: styleCellule.copyWith(color: AgriColors.outline)),
    Text(_majuscule(l.module), style: styleCellule.copyWith(color: AgriColors.outline)),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_horodatage(l.archiveLe), style: styleCellule.copyWith(color: AgriColors.outline)),
        // ⚠️ ÉCART ASSUMÉ (hors ligne) : le web n'a pas cette ligne.
        if (l.locale)
          Text(
            'Archivé sur ce poste — pas encore synchronisé',
            key: Key('corbeille-locale-${l.type}-${l.elementId}'),
            style: const TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
      ],
    ),
    // Ticket ARC-Q2 : `{{ $element['archive_par'] ?? '—' }}`.
    Text(l.archivePar ?? '—', style: styleCellule.copyWith(color: AgriColors.outline)),
    _actions(l),
  ];

  Widget _actions(LigneCorbeille l) {
    final bloque = l.enAttente || l.traitee;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ⚠️ ÉCART ASSUMÉ : où en est la demande de CETTE ligne (le web agit à l'instant, il n'a pas de demande).
        if (l.enAttente)
          Text("Demande en attente d'envoi", key: Key('corbeille-demande-${l.type}-${l.elementId}'), style: _petit(AgriColors.brandForest)),
        if (l.traitee)
          Text('Demande traitée par le serveur', key: Key('corbeille-demande-${l.type}-${l.elementId}'), style: _petit(AgriColors.brandEmerald)),
        if (l.refusee)
          Text(
            'Refusée par le serveur : ${l.refus ?? 'motif non communiqué'}',
            key: Key('corbeille-demande-${l.type}-${l.elementId}'),
            textAlign: TextAlign.right,
            style: _petit(AgriColors.errorDeep),
          ),
        if (l.restaurable)
          _bouton(
            cle: Key('corbeille-restaurer-${l.type}-${l.elementId}'),
            icone: SymbolesAgri.restore,
            libelle: 'Restaurer',
            couleur: AgriColors.brandEmerald,
            onPressed: bloque ? null : () => _restaurer(l),
          )
        else
          _phrase(Key('corbeille-refus-restauration-${l.type}-${l.elementId}'), SymbolesAgri.block, 'Non restaurable : ${l.motifRestauration}'),
        if (l.supprimable)
          _bouton(
            cle: Key('corbeille-supprimer-${l.type}-${l.elementId}'),
            icone: SymbolesAgri.delete,
            libelle: 'Supprimer définitivement',
            couleur: AgriColors.errorDeep,
            onPressed: bloque ? null : () => _supprimer(l),
          )
        else
          _phrase(
            Key('corbeille-refus-suppression-${l.type}-${l.elementId}'),
            SymbolesAgri.lock,
            'Suppression définitive impossible : ${l.motifSuppression}',
          ),
      ],
    );
  }

  static TextStyle _petit(Color couleur) => TextStyle(fontSize: 11, fontWeight: AgriTypography.gras, color: couleur);

  /// `inline-flex items-start gap-xs text-[11px] text-outline max-w-xs text-right` : la phrase d'un refus.
  Widget _phrase(Key cle, IconData icone, String texte) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 320),
    child: Row(
      key: cle,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 14, color: AgriColors.outline),
        const SizedBox(width: AgriSpacing.xs),
        Flexible(child: Text(texte, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: AgriColors.outline))),
      ],
    ),
  );

  Widget _bouton({
    required Key cle,
    required IconData icone,
    required String libelle,
    required Color couleur,
    required VoidCallback? onPressed,
  }) => TextButton.icon(
    key: cle,
    onPressed: onPressed,
    icon: Icon(icone, size: 16),
    label: Text(libelle, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
    style: TextButton.styleFrom(
      foregroundColor: couleur,
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.xs),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );

  /// Le pied du Blade : `<p class="text-[11px] text-outline">` et « Précédent » / « Suivant » quand il y a plus d'une page.
  Widget _pied({required int total, required int page, required int pages}) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: AgriColors.brandForest,
      side: const BorderSide(color: AgriColors.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: AgriSpacing.xs),
      textStyle: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
    );

    return Container(
      key: const Key('pagination-corbeille'),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
      decoration: const BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border(top: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AgriSpacing.sm,
        runSpacing: AgriSpacing.sm,
        children: [
          Text(texteDuPied(total: total, page: page, pages: pages), style: const TextStyle(fontSize: 11, color: AgriColors.outline)),
          if (pages > 1)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  key: const Key('pagination-corbeille-precedent'),
                  style: style,
                  onPressed: page > 1 ? () => setState(() => _page = page - 1) : null,
                  icon: const Icon(SymbolesAgri.chevron_left, size: 16),
                  label: const Text('Précédent'),
                ),
                const SizedBox(width: AgriSpacing.xs),
                OutlinedButton(
                  key: const Key('pagination-corbeille-suivant'),
                  style: style,
                  onPressed: page < pages ? () => setState(() => _page = page + 1) : null,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Suivant'), Icon(SymbolesAgri.chevron_right, size: 16)]),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── 6. Gestes ──────────────────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> _restaurer(LigneCorbeille l) async {
    final r = await widget.depot.demanderRestauration(l);
    if (!mounted) return;
    ToastAgri.afficher(context, r.message, type: r.ok ? TypeToast.succes : TypeToast.erreur);
    await _charger();
  }

  /// Premier temps : la modale ne s'ouvre que si la suppression est possible (la ligne le dit, sinon c'est un refus).
  Future<void> _supprimer(LigneCorbeille l) async {
    if (!l.supprimable) {
      ToastAgri.afficher(context, l.motifSuppression ?? CorbeilleRepository.messageIntrouvable, type: TypeToast.erreur);
      return;
    }
    final mot = await afficherModale<String>(
      context: context,
      confirmation: true,
      constructeur: (_) => ModaleSuppressionDefinitive(titre: l.titre, libelleType: l.libelleType),
    );
    if (mot == null || !mounted) return;
    final r = await widget.depot.demanderSuppression(l, mot);
    if (!mounted) return;
    ToastAgri.afficher(context, r.message, type: r.ok ? TypeToast.succes : TypeToast.erreur);
    await _charger();
  }
}

/// Second temps de la suppression définitive — `modal-confirm-suppression-definitive` du Blade : icône d'avertissement,
/// « Supprimer définitivement ? », le texte, le champ « Pour confirmer, saisissez le mot SUPPRIMER », « Annuler » et
/// « Supprimer définitivement » (grisé tant que le mot n'est pas EXACT : casse et espaces compris).
class ModaleSuppressionDefinitive extends StatefulWidget {
  const ModaleSuppressionDefinitive({super.key, required this.titre, required this.libelleType});

  final String titre;
  final String libelleType;

  @override
  State<ModaleSuppressionDefinitive> createState() => _ModaleSuppressionDefinitiveState();
}

class _ModaleSuppressionDefinitiveState extends State<ModaleSuppressionDefinitive> {
  final _mot = TextEditingController();

  @override
  void dispose() {
    _mot.dispose();
    super.dispose();
  }

  bool get _exact => _mot.text == CorbeilleRepository.motConfirmation;

  @override
  Widget build(BuildContext context) => ModaleConfirmation(
    icone: SymbolesAgri.warning,
    couleurIcone: AgriColors.errorDeep,
    titre: 'Supprimer définitivement ?',
    message:
        '${widget.titre} (${widget.libelleType}) sera supprimé définitivement. '
        "Cette action est irréversible : l'élément ne pourra plus être restauré.",
    detail: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AgriSpacing.md),
        const Text(
          'Pour confirmer, saisissez le mot SUPPRIMER',
          style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.onSurface),
        ),
        const SizedBox(height: AgriSpacing.xs),
        TextField(
          key: const Key('corbeille-confirmation'),
          controller: _mot,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: AgriTypography.sm),
          decoration: const InputDecoration(hintText: CorbeilleRepository.motConfirmation),
        ),
      ],
    ),
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
      BoutonModalePrimaire(
        key: const Key('corbeille-confirmer-suppression'),
        libelle: 'Supprimer définitivement',
        couleur: AgriColors.errorRed,
        onPressed: _exact ? () => Navigator.of(context).pop(_mot.text) : null,
      ),
    ],
  );
}
