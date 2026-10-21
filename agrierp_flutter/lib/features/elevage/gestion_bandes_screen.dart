import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/export/document_officiel.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import '../stocks/pmp_service.dart';
import 'autonomie_alimentaire_carte.dart';
import 'bandes_repository.dart';
import 'champs_modale_elevage.dart';

/// « Bandes & Sujets » — `resources/views/livewire/elevage/gestion-bandes.blade.php` (maître, article 5).
///
/// Ticket BS1 — l'écran suit son Blade, section par section :
///   1. en-tête : icône `layers`, « Bandes & Sujets », sous-titre du Blade, et — avec le droit `manage-elevage` — le
///      bouton « Nouvelle Bande » (pilule émeraude) ;
///   2. quatre `x-kpi-card` : Bandes Actives · En Reproduction · Effectif Total Vivant · Alertes Sanitaires ;
///   3. « Exporter PDF » à droite ;
///   4. la barre de recherche (300 ms) et le filtre d'espèce ;
///   5. le tableau Code Bande · Espèce · Stade · Date Création · Effectif Initial · Effectif Actuel · Mortalité ·
///      Statut · Actions, « Modifier » et « Archiver » (confirmation) ou « Lecture seule », ligne cliquable : tiroir ;
///   6. les modales « Nouvelle Bande » et « Modifier la Bande », le tiroir de détail.
///
/// Toasts du web : « Bande créée avec succès. » (succès), « Bande modifiée avec succès. » (succès), « Bande archivée
/// avec succès. » (avertissement).
///
/// ➕ Ajout du poste, gardé : sous le code d'une bande de CE poste pas encore reçue par le serveur, « À envoyer » ;
/// « Refusée » suivi du motif du serveur mot pour mot quand l'envoi a été refusé — le web n'a pas de file d'envoi.
///
/// ⚠️ ÉCART (plateforme) : « Mortalité » d'une bande dont l'effectif initial est 0 s'affiche « — » (inconnue) ; le Blade
/// d'origine disait « 0% » — corrigé au web d'abord (BS1) puis ici.
class GestionBandesScreen extends StatefulWidget {
  const GestionBandesScreen({
    super.key,
    required this.depot,
    this.peutGerer = true,
    this.imprimer,
    this.onCommanderStock,
    this.onOuvrirSujets,
    this.horloge,
  });

  final BandesRepository depot;

  /// `@can('manage-elevage')` : sans ce droit, ni « Nouvelle Bande », ni Modifier, ni Archiver (« Lecture seule »).
  final bool peutGerer;

  /// « Exporter PDF » — `EditeursRapports.imprimer` en production, un espion en test ; `null` : bouton inerte.
  final Future<String?> Function(DocumentOfficiel document, DateTime maintenant)? imprimer;

  /// « Commander Stock » de l'alerte d'autonomie du tiroir (`/achats-commandes` au web).
  final VoidCallback? onCommanderStock;

  /// Bouton « Enregistrer des Sujets » de l'en-tête (`route('elevage.enregistrer-sujets')` au web).
  final VoidCallback? onOuvrirSujets;

  final DateTime Function()? horloge;

  /// `wire:model.live.debounce.300ms` du champ « Rechercher un code de bande... ».
  static const delaiRecherche = Duration(milliseconds: 300);

  /// `<option>` du filtre d'espèce du Blade : (valeur, libellé).
  static const filieres = <(String, String)>[
    ('', 'Espèce : Toutes'),
    ('cuniculture', 'Cuniculture'),
    ('aviculture', 'Aviculture'),
    ('porciculture', 'Porciculture'),
    ('helico', 'Héliciculture'),
  ];

  @override
  State<GestionBandesScreen> createState() => _GestionBandesScreenState();
}

class _GestionBandesScreenState extends State<GestionBandesScreen> {
  IndicateursBandes? _kpis;
  List<LigneBande> _lignes = const [];
  final _recherche = TextEditingController();
  String _rechercheAppliquee = '';
  String _filiere = '';
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
    final lignes = await widget.depot.bandes(recherche: _rechercheAppliquee, filiere: _filiere);
    if (!mounted) return;
    setState(() {
      _kpis = kpis;
      _lignes = lignes;
    });
  }

  void _rechercher(String texte) {
    _attente?.cancel();
    _attente = Timer(GestionBandesScreen.delaiRecherche, () {
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
                  _exporter(),
                  _barreFiltres(),
                  _tableau(),
                ],
              ),
            ),
    );
  }

  /// `flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md mb-lg`.
  Widget _enTete() {
    final large = AgriBreakpoints.large(context);
    final titre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(SymbolesAgri.layers, size: 26, color: AgriColors.brandEmerald),
            const SizedBox(width: AgriSpacing.xs),
            Flexible(
              child: Text(
                'Bandes & Sujets',
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
          'Effectif vivant en temps réel, stade physiologique et statut, par bande.',
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
      ],
    );
    // `<a href="/enregistrer-sujets">` : bouton à bordure, puis — avec `manage-elevage` — « Nouvelle Bande ».
    final boutons = Wrap(
      spacing: AgriSpacing.sm,
      runSpacing: AgriSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          key: const Key('bandes-enregistrer-sujets'),
          onPressed: widget.onOuvrirSujets,
          icon: const Icon(SymbolesAgri.pets, size: 18),
          label: const Text('Enregistrer des Sujets'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AgriColors.brandForest,
            side: const BorderSide(color: AgriColors.outlineVariant),
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
            textStyle: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.full)),
          ),
        ),
        if (widget.peutGerer)
          ElevatedButton.icon(
            key: const Key('bande-nouvelle'),
            onPressed: _nouvelle,
            icon: const Icon(SymbolesAgri.add_circle, size: 18),
            label: const Text('Nouvelle Bande'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              foregroundColor: AgriColors.surfaceCard,
              elevation: 1,
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
              textStyle: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.full)),
            ),
          ),
      ],
    );
    return Container(
      padding: const EdgeInsets.only(bottom: AgriSpacing.md),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AgriColors.outlineVariant))),
      child: large
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Expanded(child: titre), boutons],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titre, const SizedBox(height: AgriSpacing.sm), boutons],
            ),
    );
  }

  /// `x-kpi-accordion` : `grid grid-cols-2 xl:grid-cols-4 gap-md`.
  Widget _indicateurs(IndicateursBandes k) {
    final colonnes = AgriBreakpoints.tresLarge(context) ? 4 : 2;
    final cartes = <Widget>[
      CarteKpi(
        key: const Key('kpi-Bandes Actives'),
        libelle: 'Bandes Actives',
        icone: SymbolesAgri.layers,
        couleurLisere: AgriColors.brandEmerald,
        couleurIcone: AgriColors.brandEmerald,
        valeur: '${k.bandesActives}',
        legende: 'Lots au statut « Actif », toutes espèces',
      ),
      CarteKpi(
        key: const Key('kpi-En Reproduction'),
        libelle: 'En Reproduction',
        icone: SymbolesAgri.favorite,
        couleurLisere: AgriColors.infoBlue,
        couleurIcone: AgriColors.infoBlue,
        valeur: '${k.enReproduction}',
        legende: 'Bandes au stade Reproduction',
      ),
      CarteKpi(
        key: const Key('kpi-Effectif Total Vivant'),
        libelle: 'Effectif Total Vivant',
        icone: SymbolesAgri.pets,
        couleurLisere: AgriColors.accentYellow,
        couleurIcone: AgriColors.brandForest,
        valeur: PmpService.francs(k.effectifTotal.toDouble()),
        legende: 'Cumul de toutes les bandes actives',
      ),
      CarteKpi(
        key: const Key('kpi-Alertes Sanitaires'),
        libelle: 'Alertes Sanitaires',
        icone: SymbolesAgri.warning,
        couleurLisere: AgriColors.errorRed,
        couleurIcone: AgriColors.errorRed,
        valeur: '${k.alertesSanitaires}',
        legende: 'Bandes sous rémanence ou soin actif',
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

  /// `flex justify-end mb-sm` : bouton « Exporter PDF » (bordure, `text-brand-forest`).
  Widget _exporter() => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
    child: Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        key: const Key('bandes-exporter-pdf'),
        onPressed: widget.imprimer == null ? null : _exporterPdf,
        icon: const Icon(SymbolesAgri.picture_as_pdf, size: 18),
        label: const Text('Exporter PDF'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AgriColors.brandForest,
          side: const BorderSide(color: AgriColors.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
          textStyle: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.full)),
        ),
      ),
    ),
  );

  /// `exports/gestion-bandes.blade.php` : le tableau filtré, titre « Gestion des Bandes », « État au JJ/MM/AAAA ».
  /// Le statut est `Actif` ou `ucfirst($status)` (« Cloture », sans accent, comme le PDF du web).
  Future<void> _exporterPdf() async {
    final maintenant = _maintenant();
    String deux(int n) => n.toString().padLeft(2, '0');
    final document = DocumentOfficiel(
      titre: 'Gestion des Bandes',
      sousTitre: 'État au ${deux(maintenant.day)}/${deux(maintenant.month)}/${maintenant.year}',
      entetes: const [
        'Code Bande',
        'Espèce',
        'Stade',
        'Date Création',
        'Effectif Initial',
        'Effectif Actuel',
        'Mortalité',
        'Statut',
      ],
      lignes: [
        if (_lignes.isEmpty) const BandeDocument('Aucune bande active.'),
        for (final l in _lignes)
          DonneesDocument([
            l.bande.code,
            l.especeLibelle ?? '',
            l.libelleStade,
            _jour(l.bande.createdDate),
            '${l.bande.initialQuantity}',
            '${l.bande.currentQuantity}',
            BandesRepository.formaterMortalite(l.mortalite),
            l.bande.status == 'actif' ? 'Actif' : _ucfirst(l.bande.status ?? ''),
          ]),
      ],
      fichier: 'bandes-{jour}.pdf',
    );
    await widget.imprimer!(document, maintenant);
  }

  static String _ucfirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _jour(DateTime? d) =>
      d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// `bg-white border rounded-lg p-md mb-md flex flex-wrap items-center gap-sm` : recherche et filtre d'espèce.
  Widget _barreFiltres() {
    return Container(
      margin: const EdgeInsets.only(bottom: AgriSpacing.md),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Wrap(
        spacing: AgriSpacing.sm,
        runSpacing: AgriSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            height: 36,
            child: TextField(
              key: const Key('bandes-recherche'),
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
                key: const Key('bandes-filtre-filiere'),
                value: _filiere,
                style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
                items: [
                  for (final (valeur, libelle) in GestionBandesScreen.filieres)
                    DropdownMenuItem(value: valeur, child: Text(libelle)),
                ],
                onChanged: (v) {
                  _filiere = v ?? '';
                  _charger();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _entete = TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgriColors.outline);

  Widget _tableau() {
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
            color: AgriColors.surfaceZebra,
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
            child: Row(
              children: [
                cellule(3, 'Code Bande'),
                cellule(3, 'Espèce'),
                cellule(3, 'Stade'),
                cellule(2, 'Date Création'),
                cellule(2, 'Effectif Initial', droite: true),
                cellule(2, 'Effectif Actuel', droite: true),
                cellule(2, 'Mortalité', droite: true),
                cellule(2, 'Statut'),
                cellule(2, 'Actions', droite: true),
              ],
            ),
          ),
          if (_lignes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AgriSpacing.xl),
              child: Text(
                'Aucune bande pour le moment. Cliquez sur « Nouvelle Bande » pour commencer.',
                key: Key('bandes-vide'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AgriTypography.base, color: AgriColors.outline),
              ),
            ),
          for (final (i, l) in _lignes.indexed) _ligne(l, i),
        ],
      ),
    );
  }

  Widget _ligne(LigneBande l, int index) {
    final b = l.bande;
    const corps = TextStyle(fontSize: AgriTypography.xs);
    final actif = b.status == 'actif';
    return InkWell(
      key: Key('bande-ligne-${b.id}'),
      onTap: () => _voir(b.id),
      child: Container(
        decoration: BoxDecoration(
          color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
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
                  Text(b.code, style: corps.copyWith(fontWeight: FontWeight.bold, color: AgriColors.brandEmerald)),
                  ..._etatEnvoi(l),
                ],
              ),
            ),
            Expanded(flex: 3, child: Text(l.especeLibelle ?? '', style: corps)),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _badge(
                  l.libelleStade,
                  AgriColors.accentYellow.withValues(alpha: 0.2),
                  AgriColors.brandForest,
                  AgriColors.accentYellow,
                ),
              ),
            ),
            Expanded(flex: 2, child: Text(_jour(b.createdDate), style: corps)),
            Expanded(flex: 2, child: Text('${b.initialQuantity}', textAlign: TextAlign.right, style: corps)),
            Expanded(
              flex: 2,
              child: Text(
                '${b.currentQuantity}',
                key: Key('bande-effectif-${b.id}'),
                textAlign: TextAlign.right,
                style: corps.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                BandesRepository.formaterMortalite(l.mortalite),
                key: Key('bande-mortalite-${b.id}'),
                textAlign: TextAlign.right,
                style: corps.copyWith(
                  color: (l.mortalite ?? 0) > 0 ? AgriColors.errorDeep : AgriColors.outline,
                  fontWeight: (l.mortalite ?? 0) > 0 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: actif
                    ? _badge(
                        'Actif',
                        AgriColors.brandEmerald.withValues(alpha: 0.10),
                        AgriColors.brandEmerald,
                        AgriColors.brandEmerald.withValues(alpha: 0.30),
                      )
                    : _badge('Clôturé', AgriColors.surfaceZebra, AgriColors.outline, AgriColors.outlineVariant),
              ),
            ),
            Expanded(
              flex: 2,
              child: widget.peutGerer
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _action('bande-modifier-${b.id}', 'Modifier', SymbolesAgri.edit, AgriColors.infoBlue, () => _modifier(b)),
                        _action('bande-archiver-${b.id}', 'Archiver', SymbolesAgri.delete, AgriColors.errorDeep, () => _archiver(b)),
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
      ),
    );
  }

  /// `inline-flex px-sm py-[2px] rounded-full text-[11px] font-bold border`.
  Widget _badge(String texte, Color fond, Color texteCouleur, Color bord) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
    decoration: BoxDecoration(
      color: fond,
      border: Border.all(color: bord),
      borderRadius: BorderRadius.circular(AgriRadius.full),
    ),
    child: Text(texte, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: texteCouleur)),
  );

  Widget _action(String cle, String infobulle, IconData icone, Color couleur, VoidCallback surAppui) => Tooltip(
    message: infobulle,
    child: InkWell(
      key: Key(cle),
      onTap: surAppui,
      borderRadius: BorderRadius.circular(AgriRadius.full),
      child: Padding(padding: const EdgeInsets.all(4), child: Icon(icone, size: 16, color: couleur)),
    ),
  );

  /// ➕ Ajout du poste : l'état d'envoi d'une bande de ce poste, sous son code.
  List<Widget> _etatEnvoi(LigneBande l) {
    final b = l.bande;
    if (b.syncStatus == SyncStatus.synced) return const [];
    final refusee = b.syncStatus == SyncStatus.conflict;
    return [
      const SizedBox(height: 2),
      Container(
        key: Key('bande-etat-${b.id}'),
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
          key: Key('bande-motif-${b.id}'),
          style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
        ),
    ];
  }

  // ── Gestes ────────────────────────────────────────────────────────────────────────────────────────────────────────

  /// `newLot()` → `modal-create-bande`.
  Future<void> _nouvelle() async {
    final cree = await afficherModale<bool>(
      context: context,
      constructeur: (_) => _ModaleNouvelleBande(depot: widget.depot, aujourdhui: _maintenant()),
    );
    if (cree != true || !mounted) return;
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(context, BandesRepository.toastCreee);
  }

  /// `editLot($id)` → `modal-edit-bande`.
  Future<void> _modifier(LivestockLot b) async {
    final resultat = await afficherModale<String>(
      context: context,
      constructeur: (_) => _ModaleModifierBande(depot: widget.depot, bande: b),
    );
    if (resultat == null || !mounted) return;
    await _charger();
    if (!mounted) return;
    if (resultat == 'modifiee') {
      ToastAgri.afficher(context, BandesRepository.toastModifiee);
    } else {
      // Bande archivée depuis l'ouverture de la modale : le motif du web, en toast d'erreur.
      ToastAgri.afficher(context, resultat, type: TypeToast.erreur);
    }
  }

  /// `archiveLot($id)` derrière `x-modal-confirm-delete` : icône `archive` `text-error-deep`, « Confirmer
  /// l'archivage », le code de la bande, « Annuler » puis « Archiver » (`bg-error-red`).
  Future<void> _archiver(LivestockLot b) async {
    final confirme = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (contexte) => ModaleConfirmation(
        icone: SymbolesAgri.archive,
        couleurIcone: AgriColors.errorDeep,
        titre: "Confirmer l'archivage",
        message:
            '${b.code} sera marqué(e) comme archivé(e) (statut inactif). '
            "Aucune suppression définitive n'est effectuée.",
        actions: [
          BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(contexte).pop(false)),
          BoutonModalePrimaire(
            key: const Key('archivage-bande-confirmer'),
            libelle: 'Archiver',
            couleur: AgriColors.errorRed,
            onPressed: () => Navigator.of(contexte).pop(true),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    await widget.depot.archiver(b.id);
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(context, BandesRepository.toastArchivee, type: TypeToast.avertissement);
  }

  /// `view($id)` : le tiroir de détail, à droite (`sm:w-96`), sous un voile `bg-black/40`.
  Future<void> _voir(String id) async {
    final detail = await widget.depot.detail(id);
    if (detail == null || !mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer',
      barrierColor: const Color(0x66000000),
      pageBuilder: (contexte, _, _) => Align(
        alignment: Alignment.centerRight,
        child: _TiroirBande(detail: detail, onCommanderStock: widget.onCommanderStock),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Modale « Nouvelle Bande »
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class _ModaleNouvelleBande extends StatefulWidget {
  const _ModaleNouvelleBande({required this.depot, required this.aujourdhui});

  final BandesRepository depot;
  final DateTime aujourdhui;

  @override
  State<_ModaleNouvelleBande> createState() => _ModaleNouvelleBandeState();
}

class _ModaleNouvelleBandeState extends State<_ModaleNouvelleBande> {
  List<EspeceElevage> _especes = const [];
  List<Product> _produits = const [];
  List<LivestockLot> _origines = const [];
  String _espece = '';
  String? _codeEspece;
  String _stade = 'reproduction';
  String _produit = '';
  String _origine = '';
  late DateTime _date = DateTime(widget.aujourdhui.year, widget.aujourdhui.month, widget.aujourdhui.day);
  final _code = TextEditingController();
  // `public int $quantity = 0` : le champ s'ouvre sur 0.
  final _quantite = TextEditingController(text: '0');
  final _cout = TextEditingController();
  Map<String, String> _erreurs = const {};

  @override
  void initState() {
    super.initState();
    widget.depot.especes().then((e) {
      if (mounted) setState(() => _especes = e);
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _quantite.dispose();
    _cout.dispose();
    super.dispose();
  }

  /// `updatedSpeciesId()` : le code suggéré (numérotation continue), un stade qui existe pour l'espèce ; les produits
  /// et les bandes d'origine sont ceux de l'espèce.
  Future<void> _choisirEspece(String id) async {
    final espece = _especes.where((e) => e.id == id).firstOrNull;
    final code = await widget.depot.codeSuggere(id);
    final produits = await widget.depot.produitsCandidats(id);
    final origines = await widget.depot.bandesOrigine(id);
    if (!mounted) return;
    setState(() {
      _espece = id;
      _codeEspece = espece?.code;
      if (espece != null) _code.text = code;
      final stades = BandesRepository.stadesPourEspece(_codeEspece);
      if (!stades.containsKey(_stade)) _stade = stades.keys.first;
      _produits = produits;
      _origines = origines;
      _produit = '';
      _origine = '';
    });
  }

  Future<void> _creer() async {
    setState(() => _erreurs = const {});
    try {
      await widget.depot.creer(
        FormulaireBande(
          speciesId: _espece,
          code: _code.text,
          stage: _stade,
          createdDate: _date,
          quantite: _quantite.text,
          coutAcquisition: _cout.text,
          productId: _produit,
          lotOrigineId: _origine,
        ),
      );
    } on BandeRefusee catch (e) {
      if (mounted) setState(() => _erreurs = e.erreurs);
      return;
    } on RefusExercice catch (e) {
      // `SaisieBandeAction::creer` — exercice clos : le motif R4, sous « Date de Création ».
      if (mounted) setState(() => _erreurs = {'created_date': e.motif});
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final stades = BandesRepository.stadesPourEspece(_codeEspece);
    return ModaleAgri(
      largeur: LargeurModale.sm,
      titre: 'Nouvelle Bande',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlocChampModale(
            libelle: 'Espèce *',
            erreur: _erreurs['species_id'],
            cleErreur: const Key('bande-erreur-species_id'),
            enfant: KeyedSubtree(
              key: const Key('bande-espece'),
              child: ChampListeModale(
                valeur: _espece,
                vide: '-- Sélectionner --',
                enErreur: _erreurs.containsKey('species_id'),
                options: [for (final e in _especes) (e.id, e.label)],
                surChangement: _choisirEspece,
              ),
            ),
          ),
          BlocChampModale(
            libelle: 'Code Unique de la Bande *',
            erreur: _erreurs['code'],
            cleErreur: const Key('bande-erreur-code'),
            aide: 'Numérotation continue suggérée automatiquement — modifiable si besoin.',
            enfant: KeyedSubtree(
              key: const Key('bande-code'),
              child: ChampTexteModale(controleur: _code, indice: 'ex : LOT-LAP-7', enErreur: _erreurs.containsKey('code')),
            ),
          ),
          BlocChampModale(
            libelle: 'Stade Initial',
            erreur: _erreurs['stage'],
            cleErreur: const Key('bande-erreur-stage'),
            enfant: KeyedSubtree(
              key: const Key('bande-stade'),
              child: ChampListeModale(
                valeur: _stade,
                options: [for (final MapEntry(:key, :value) in stades.entries) (key, value)],
                surChangement: (v) => setState(() => _stade = v),
              ),
            ),
          ),
          BlocChampModale(
            libelle: 'Date de Création',
            erreur: _erreurs['created_date'],
            cleErreur: const Key('bande-erreur-created_date'),
            enfant: KeyedSubtree(
              key: const Key('bande-date'),
              child: ChampDateModale(
                date: _date,
                enErreur: _erreurs.containsKey('created_date'),
                surChangement: (d) => setState(() => _date = d),
              ),
            ),
          ),
          BlocChampModale(
            libelle: 'Quantité Initiale (Effectif) *',
            erreur: _erreurs['quantity'],
            cleErreur: const Key('bande-erreur-quantity'),
            enfant: KeyedSubtree(
              key: const Key('bande-quantite'),
              child: ChampTexteModale(controleur: _quantite, nombre: true, indice: 'ex : 27', enErreur: _erreurs.containsKey('quantity')),
            ),
          ),
          BlocChampModale(
            libelle: "Coût d'Acquisition (FCFA)",
            erreur: _erreurs['acquisition_cost'],
            cleErreur: const Key('bande-erreur-acquisition_cost'),
            enfant: KeyedSubtree(
              key: const Key('bande-cout'),
              child: ChampTexteModale(controleur: _cout, nombre: true, indice: 'ex : 135000'),
            ),
          ),
          BlocChampModale(
            libelle: 'Produit issu de cette bande',
            erreur: _erreurs['product_id'],
            cleErreur: const Key('bande-erreur-product_id'),
            aide:
                "Les naissances entreront en stock sur ce produit ; mortalité et dons l'en retireront. "
                "Sélectionnez d'abord la filière.",
            enfant: KeyedSubtree(
              key: const Key('bande-produit'),
              child: ChampListeModale(
                valeur: _produit,
                vide: '-- Aucun (pas de mouvement de stock) --',
                options: [for (final p in _produits) (p.id, '${p.sku} — ${p.name}')],
                surChangement: (v) => setState(() => _produit = v),
              ),
            ),
          ),
          BlocChampModale(
            libelle: "Bande d'Origine",
            erreur: _erreurs['lot_origine_id'],
            cleErreur: const Key('bande-erreur-lot_origine_id'),
            aide:
                "Portée ou sevrés déjà comptés dans une autre bande : ils en sortent le jour de création, pour "
                "n'être comptés qu'une fois.",
            enfant: KeyedSubtree(
              key: const Key('bande-origine'),
              child: ChampListeModale(
                valeur: _origine,
                vide: "-- Aucune (achat, animaux extérieurs) --",
                enErreur: _erreurs.containsKey('lot_origine_id'),
                options: [for (final o in _origines) (o.id, '${o.code} (${PmpService.francs(o.currentQuantity.toDouble())})')],
                surChangement: (v) => setState(() => _origine = v),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AgriSpacing.sm),
            margin: const EdgeInsets.only(bottom: AgriSpacing.md),
            decoration: BoxDecoration(color: AgriColors.surfaceZebra, borderRadius: BorderRadius.circular(AgriRadius.lg)),
            child: const Text(
              'Le suivi individuel par sujet (N° Lapine, etc.) se paramètre depuis Enregistrer Sujets, une fois la bande créée.',
              style: TextStyle(fontSize: 10, color: AgriColors.outline),
            ),
          ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
        BoutonModalePrimaire(key: const Key('bande-creer'), libelle: 'Créer la Bande', onPressed: _creer),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Modale « Modifier la Bande »
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class _ModaleModifierBande extends StatefulWidget {
  const _ModaleModifierBande({required this.depot, required this.bande});

  final BandesRepository depot;
  final LivestockLot bande;

  @override
  State<_ModaleModifierBande> createState() => _ModaleModifierBandeState();
}

class _ModaleModifierBandeState extends State<_ModaleModifierBande> {
  late String _stade = widget.bande.stage ?? 'reproduction';
  late String _statut = widget.bande.status ?? 'actif';
  late final TextEditingController _quantite = TextEditingController(text: '${widget.bande.currentQuantity}');
  Map<String, String> _erreurs = const {};

  @override
  void dispose() {
    _quantite.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    setState(() => _erreurs = const {});
    try {
      await widget.depot.modifier(widget.bande.id, stage: _stade, quantite: _quantite.text, status: _statut);
    } on BandeRefusee catch (e) {
      if (e.erreurs.containsKey('bande')) {
        // Bande archivée depuis l'ouverture de la modale : fermée, le motif en toast d'erreur (comme le web).
        if (mounted) Navigator.of(context).pop(e.erreurs['bande']);
        return;
      }
      if (mounted) setState(() => _erreurs = e.erreurs);
      return;
    }
    if (mounted) Navigator.of(context).pop('modifiee');
  }

  @override
  Widget build(BuildContext context) {
    final stades = BandesRepository.stadesPourEspece(widget.bande.speciesCode);
    return ModaleAgri(
      largeur: LargeurModale.sm,
      titre: 'Modifier la Bande',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlocChampModale(
            libelle: 'Code Unique de la Bande',
            aide: "L'identifiant technique unique n'est jamais modifiable après création.",
            enfant: KeyedSubtree(key: const Key('bande-edit-code'), child: ChampLectureModale(valeur: widget.bande.code)),
          ),
          BlocChampModale(
            libelle: 'Stade *',
            erreur: _erreurs['stage'],
            cleErreur: const Key('bande-erreur-stage'),
            enfant: KeyedSubtree(
              key: const Key('bande-edit-stade'),
              child: ChampListeModale(
                valeur: _stade,
                enErreur: _erreurs.containsKey('stage'),
                options: [for (final MapEntry(:key, :value) in stades.entries) (key, value)],
                surChangement: (v) => setState(() => _stade = v),
              ),
            ),
          ),
          BlocChampModale(
            libelle: 'Effectif Actuel *',
            erreur: _erreurs['quantity'],
            cleErreur: const Key('bande-erreur-quantity'),
            enfant: KeyedSubtree(
              key: const Key('bande-edit-quantite'),
              child: ChampTexteModale(controleur: _quantite, nombre: true, enErreur: _erreurs.containsKey('quantity')),
            ),
          ),
          BlocChampModale(
            libelle: 'Statut *',
            erreur: _erreurs['status'],
            cleErreur: const Key('bande-erreur-status'),
            enfant: KeyedSubtree(
              key: const Key('bande-edit-statut'),
              child: ChampListeModale(
                valeur: _statut,
                options: const [('actif', 'Actif'), ('cloture', 'Clôturé')],
                surChangement: (v) => setState(() => _statut = v),
              ),
            ),
          ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
        BoutonModalePrimaire(key: const Key('bande-enregistrer'), libelle: 'Enregistrer les Modifications', onPressed: _enregistrer),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Tiroir de détail
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// `viewingLot` : en-tête `bg-brand-forest` (code en blanc, ✕), grille Espèce · Stade · Date Création · Statut ·
/// Effectif Initial · Effectif Actuel, puis « Autonomie Alimentaire » et « Suivi Sanitaire » (données réelles de la bande).
class _TiroirBande extends StatelessWidget {
  const _TiroirBande({required this.detail, this.onCommanderStock});

  final DetailBande detail;
  final VoidCallback? onCommanderStock;

  static const _etiquette = TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline);
  static const _valeur = TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: AgriColors.onSurface);
  static const _titre = TextStyle(
    fontSize: AgriTypography.xs,
    fontWeight: FontWeight.bold,
    color: AgriColors.brandForest,
  );

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _case(String etiquette, String valeur) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(etiquette, style: _etiquette), Text(valeur, style: _valeur)],
  );

  @override
  Widget build(BuildContext context) {
    final b = detail.bande;
    final sanitaire = detail.remanence;
    final largeur = MediaQuery.sizeOf(context).width;
    return Material(
      key: const Key('bande-tiroir'),
      color: AgriColors.surfaceCard,
      elevation: 16,
      child: SizedBox(
        width: largeur >= AgriBreakpoints.sm ? 384 : largeur,
        height: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AgriColors.brandForest,
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.lg, vertical: AgriSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      b.code,
                      style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  InkWell(
                    key: const Key('bande-tiroir-fermer'),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(SymbolesAgri.close, color: Color(0xCCFFFFFF)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AgriSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      runSpacing: AgriSpacing.sm,
                      children: [
                        for (final (e, v) in [
                          ('Espèce', detail.especeLibelle ?? ''),
                          ('Stade', detail.libelleStade),
                          ('Date Création', b.createdDate == null ? '—' : _jour(b.createdDate!)),
                          ('Statut', b.status == 'actif' ? 'Actif' : 'Clôturé'),
                          ('Effectif Initial', '${b.initialQuantity}'),
                          ('Effectif Actuel', '${b.currentQuantity}'),
                        ])
                          FractionallySizedBox(widthFactor: 0.5, child: _case(e, v)),
                      ],
                    ),
                    const SizedBox(height: AgriSpacing.md),
                    const Divider(height: 1, color: AgriColors.outlineVariant),
                    const SizedBox(height: AgriSpacing.md),
                    const Text('AUTONOMIE ALIMENTAIRE', style: _titre),
                    const SizedBox(height: AgriSpacing.xs),
                    CarteAutonomieAlimentaire(
                      autonomie: detail.autonomie,
                      filiere: 'de la filière ${detail.especeLibelle ?? ''}',
                      onCommanderStock: onCommanderStock,
                    ),
                    const SizedBox(height: AgriSpacing.xs),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 11, color: AgriColors.outline),
                        children: [
                          const TextSpan(text: 'Provende servie à cette bande : '),
                          TextSpan(
                            text: detail.provendeBandeKg == null
                                ? '—'
                                : '${PmpService.nombre(detail.provendeBandeKg!, 2)} Kg/j',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AgriColors.brandForest),
                          ),
                          if (detail.dateDerniereFiche != null) TextSpan(text: ' (fiche du ${_jour(detail.dateDerniereFiche!)})'),
                        ],
                      ),
                      key: const Key('bande-provende-servie'),
                    ),
                    const SizedBox(height: AgriSpacing.md),
                    const Divider(height: 1, color: AgriColors.outlineVariant),
                    const SizedBox(height: AgriSpacing.md),
                    const Text('SUIVI SANITAIRE', style: _titre),
                    const SizedBox(height: AgriSpacing.xs),
                    if (sanitaire != null)
                      Container(
                        key: const Key('bande-remanence'),
                        padding: const EdgeInsets.all(AgriSpacing.sm),
                        decoration: BoxDecoration(
                          color: AgriColors.errorBg,
                          border: Border.all(color: AgriColors.errorDeep.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(AgriRadius.lg),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(SymbolesAgri.block, size: 16, color: AgriColors.errorDeep),
                                SizedBox(width: AgriSpacing.xs),
                                Expanded(
                                  child: Text(
                                    "Délai d'attente en cours",
                                    style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: AgriColors.errorDeep),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${sanitaire.productUsed ?? ''} — vente interdite jusqu\'au ${_jour(sanitaire.endDate)}.',
                              style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
                            ),
                          ],
                        ),
                      )
                    else
                      const Text(
                        "Aucun délai d'attente en cours : vente autorisée.",
                        key: Key('bande-vente-autorisee'),
                        style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.w600, color: AgriColors.brandEmerald),
                      ),
                    const SizedBox(height: AgriSpacing.sm),
                    Wrap(
                      runSpacing: AgriSpacing.sm,
                      children: [
                        FractionallySizedBox(widthFactor: 0.5, child: _case('En infirmerie', '${detail.infirmerie} sujet(s)')),
                        FractionallySizedBox(
                          widthFactor: 0.5,
                          child: _case(
                            'Mortalité 7 jours',
                            '${detail.mortsSurSeptJours} mort(s)'
                            '${detail.mortaliteSurSeptJours == null ? '' : ' — ${PmpService.nombre(detail.mortaliteSurSeptJours!, 1)} %'}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AgriSpacing.sm),
                    const Text('Derniers soins', style: _etiquette),
                    if (detail.derniersSoins.isEmpty)
                      const Text('—', style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline))
                    else
                      for (final s in detail.derniersSoins)
                        Text(
                          '${_jour(s.recordDate)} — ${s.actionType}${s.productUsed == null || s.productUsed!.isEmpty ? '' : ' (${s.productUsed})'}',
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
