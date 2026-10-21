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
import '../rapports/rapports_exports_screen.dart' show Editeur;
import '../stocks/pmp_service.dart';
import 'devis_repository.dart';

/// Onglet « Devis Prestations » du hub « Ventes & Devis » — `resources/views/livewire/ventes/devis.blade.php` (maître,
/// article 5) et `app/Livewire/Ventes/Devis.php`.
///
/// 🔴→✅ Ticket DEV — l'onglet n'était qu'une carte « non embarqué » ; la demande du client du 21/10/2026 est « la saisie
/// Devis & Proforma avec son tab panel et son CRUD doit être faite dans le poste », identique au web. Le « tab panel » est
/// le hub lui-même (`ventes-devis-hub.blade.php` : Enregistrer Vente · Devis Prestations · Historique des Ventes · Retours
/// et Avoirs) : l'onglet Devis n'a pas de sous-onglet au web, il n'en a pas ici. L'écran suit son Blade, section par
/// section :
///   1. en-tête : icône `request_quote`, « Devis & Proforma », sous-titre ; « Exporter » (`picture_as_pdf`, droit
///      `export-ventes`) et « Nouveau Devis » (`manage-ventes`) ;
///   2. quatre `x-kpi-card` : « Devis Actifs », « Valeur Totale », « Taux de Conversion », « En Attente de Relance » ;
///   3. la barre « N° devis, client... », « Statut : Tous », « Client : Tous » ;
///   4. le tableau N° Devis · Client · Date · Validité · Montant · Statut · Actions, badge du Blade, « Aucun devis pour le
///      moment. » ;
///   5. la modale « Nouveau Devis » / « Modifier le Devis » (`modal-create-devis`, `max-width="md"`) et l'archivage
///      derrière `x-modal-confirm-delete`.
///
/// Toasts du web : « Devis créé avec succès. », « Devis modifié avec succès. », « Devis marqué comme envoyé / accepté /
/// refusé. », « Devis archivé avec succès. » (avertissement), « La conversion en facture réelle arrive avec le module
/// Facturation (Sprint 7). » (avertissement : la conversion n'existe pas encore au web).
///
/// ➕ Ajouts du poste, gardés : sous le numéro, l'état d'envoi d'une saisie de ce poste (« À envoyer » ; « Refusé » ou
/// « Archivage refusé » suivi du motif du serveur mot pour mot) — le web n'a pas de file d'envoi ; et « — » en N° Devis
/// tant que le serveur n'a pas attribué le numéro.
class DevisOnglet extends StatefulWidget {
  const DevisOnglet({
    super.key,
    required this.depot,
    this.peutGerer = true,
    this.peutExporter = true,
    this.imprimer,
  });

  final DevisRepository depot;

  /// `manage-ventes` : « Nouveau Devis » et les icônes d'écriture (le web les montre à tous et refuse au serveur ; le
  /// poste, qui ne peut pas refuser « au serveur » avant d'écrire, ne les montre pas à qui n'a pas le droit).
  final bool peutGerer;

  /// `export-ventes` : « Exporter » (`exportDevisPdf()` : `$this->authorize('export-ventes')`).
  final bool peutExporter;

  /// Éditeur injecté — `EditeursRapports.imprimer` en production, un espion en test. `null` : « Exporter » inerte.
  final Editeur? imprimer;

  /// `wire:model.live.debounce.300ms` du champ de recherche.
  static const delaiRecherche = Duration(milliseconds: 300);

  /// Texte de l'état vide du Blade.
  static const etatVide = 'Aucun devis pour le moment.';

  @override
  State<DevisOnglet> createState() => _DevisOngletState();
}

class _DevisOngletState extends State<DevisOnglet> {
  DonneesDevis? _donnees;

  final _recherche = TextEditingController();
  String _rechercheAppliquee = '';
  String _statut = '';
  String _client = '';
  Timer? _attenteRecherche;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _attenteRecherche?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger(
      recherche: _rechercheAppliquee,
      statut: _statut,
      clientId: _client,
    );
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AgriSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _enTete(d),
          const SizedBox(height: AgriSpacing.md),
          _indicateurs(d?.kpis),
          const SizedBox(height: AgriSpacing.md),
          _barreFiltres(d?.clients ?? const []),
          const SizedBox(height: AgriSpacing.md),
          _tableau(d?.lignes ?? const []),
        ],
      ),
    );
  }

  // ── 1. En-tête ───────────────────────────────────────────────────────────────────────────────────────────────────

  /// `flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm` : titre (`text-xl lg:text-2xl font-bold`,
  /// icône `request_quote` 26 px émeraude) et sous-titre `text-xs text-outline mt-xs` ; boutons à droite.
  Widget _enTete(DonneesDevis? d) {
    final large = AgriBreakpoints.large(context);
    final titre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(SymbolesAgri.request_quote, size: 26, color: AgriColors.brandEmerald),
            const SizedBox(width: AgriSpacing.xs),
            Flexible(
              child: Text(
                'Devis & Proforma',
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
          'Cycle de vie complet des devis : brouillon, envoi, acceptation et conversion en facture.',
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
      ],
    );

    final boutons = Wrap(
      spacing: AgriSpacing.xs,
      runSpacing: AgriSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.peutExporter)
          OutlinedButton.icon(
            key: const Key('devis-exporter'),
            onPressed: widget.imprimer == null || d == null ? null : () => _exporter(d),
            icon: const Icon(SymbolesAgri.picture_as_pdf, size: 18),
            label: const Text(
              'Exporter',
              style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AgriColors.brandForest,
              backgroundColor: AgriColors.surfaceCard,
              side: const BorderSide(color: AgriColors.outlineVariant),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
            ),
          ),
        if (widget.peutGerer)
          FilledButton.icon(
            key: const Key('devis-nouveau'),
            onPressed: () => _ouvrirFormulaire(null),
            icon: const Icon(SymbolesAgri.add_circle, size: 18),
            label: const Text(
              'Nouveau Devis',
              style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
            ),
          ),
      ],
    );

    return large
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Expanded(child: titre), boutons],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titre, const SizedBox(height: AgriSpacing.sm), boutons],
          );
  }

  /// « Exporter » — `exportDevisPdf()` : les devis tels qu'ils sont filtrés à l'écran.
  Future<void> _exporter(DonneesDevis d) async {
    final editeur = widget.imprimer;
    if (editeur == null) return;
    final maintenant = HeureBenin.maintenant();
    final message = await editeur(DevisRepository.documentPdf(d.lignes, maintenant), maintenant);
    // Le web ne dit rien après un export réussi : seul un échec de l'éditeur s'affiche.
    if (message != null && mounted) {
      ToastAgri.afficher(context, message, type: TypeToast.erreur);
    }
  }

  // ── 2. Indicateurs ───────────────────────────────────────────────────────────────────────────────────────────────

  /// `grid grid-cols-2 xl:grid-cols-4 gap-md` — les quatre `x-kpi-card` du Blade, dans son ordre et ses couleurs
  /// (émeraude, bleu, maïs, rouge). Rien n'est lu : « — », jamais 0.
  Widget _indicateurs(KpisDevis? k) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final colonnes = AgriBreakpoints.tresLarge(context) ? 4 : 2;
        final largeur = (contraintes.maxWidth - (colonnes - 1) * AgriSpacing.md) / colonnes;
        Widget carte(String libelle, String valeur, Color couleur, IconData icone, {Color? couleurIcone}) => SizedBox(
          width: largeur,
          child: CarteKpi(
            key: Key('kpi-$libelle'),
            libelle: libelle,
            valeur: valeur,
            icone: icone,
            couleurLisere: couleur,
            couleurIcone: couleurIcone ?? couleur,
          ),
        );

        return Wrap(
          spacing: AgriSpacing.md,
          runSpacing: AgriSpacing.md,
          children: [
            carte('Devis Actifs', k == null ? '—' : '${k.devisActifs}', AgriColors.brandEmerald, SymbolesAgri.request_quote),
            carte(
              'Valeur Totale',
              // `number_format($kpis['valeur_totale'], 0, ',', ' ').' FCFA'`.
              k == null ? '—' : '${PmpService.francs(k.valeurTotale)} FCFA',
              AgriColors.infoBlue,
              SymbolesAgri.payments,
            ),
            carte(
              'Taux de Conversion',
              k == null ? '—' : '${k.tauxConversion} %',
              AgriColors.accentYellow,
              SymbolesAgri.trending_up,
              couleurIcone: AgriColors.brandForest,
            ),
            carte(
              'En Attente de Relance',
              k == null ? '—' : '${k.enAttenteDeRelance}',
              AgriColors.errorRed,
              SymbolesAgri.pending_actions,
            ),
          ],
        );
      },
    );
  }

  // ── 3. Filtres ───────────────────────────────────────────────────────────────────────────────────────────────────

  /// `bg-white border rounded-lg p-md flex flex-wrap items-center gap-sm` : recherche `flex-1 min-w-[180px]` (icône
  /// `search`), « Statut : Tous », « Client : Tous ».
  Widget _barreFiltres(List<Customer> clients) {
    Widget liste({
      required String cle,
      required String valeur,
      required List<(String, String)> options,
      required ValueChanged<String> surChangement,
    }) {
      final presente = options.any((o) => o.$1 == valeur);
      return Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
        decoration: BoxDecoration(
          color: AgriColors.surfaceCard,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: Key(cle),
            value: presente ? valeur : '',
            style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
            items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
            onChanged: (v) => surChangement(v ?? ''),
          ),
        ),
      );
    }

    return Container(
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
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 180, maxWidth: 420),
            child: SizedBox(
              width: 420,
              height: 36,
              child: TextField(
                key: const Key('devis-recherche'),
                controller: _recherche,
                onChanged: _rechercher,
                style: const TextStyle(fontSize: AgriTypography.xs),
                decoration: InputDecoration(
                  hintText: 'N° devis, client...',
                  isDense: true,
                  prefixIcon: const Icon(SymbolesAgri.search, size: 18, color: AgriColors.outline),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AgriRadius.lg),
                    borderSide: const BorderSide(color: AgriColors.outlineVariant),
                  ),
                ),
              ),
            ),
          ),
          liste(
            cle: 'devis-filtre-statut',
            valeur: _statut,
            options: [
              ('', 'Statut : Tous'),
              for (final e in DevisRepository.statuts.entries) (e.key, e.value),
            ],
            surChangement: (v) {
              _statut = v;
              _charger();
            },
          ),
          liste(
            cle: 'devis-filtre-client',
            valeur: _client,
            options: [
              ('', 'Client : Tous'),
              for (final c in clients) (c.id, c.name),
            ],
            surChangement: (v) {
              _client = v;
              _charger();
            },
          ),
        ],
      ),
    );
  }

  void _rechercher(String texte) {
    _attenteRecherche?.cancel();
    _attenteRecherche = Timer(DevisOnglet.delaiRecherche, () {
      _rechercheAppliquee = texte;
      _charger();
    });
  }

  // ── 4. Tableau ───────────────────────────────────────────────────────────────────────────────────────────────────

  static const _enteteColonne = TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgriColors.outline);

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Le tableau du Blade (`table.rtable`) : en-tête `bg-surface-zebra`, sept colonnes, zébrage une ligne sur deux.
  Widget _tableau(List<LigneDevis> lignes) {
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
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('N° DEVIS', style: _enteteColonne)),
                Expanded(flex: 3, child: Text('CLIENT', style: _enteteColonne)),
                Expanded(flex: 2, child: Text('DATE', style: _enteteColonne)),
                Expanded(flex: 2, child: Text('VALIDITÉ', style: _enteteColonne)),
                Expanded(flex: 3, child: Text('MONTANT', textAlign: TextAlign.right, style: _enteteColonne)),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: EdgeInsets.only(left: AgriSpacing.md),
                    child: Text('STATUT', style: _enteteColonne),
                  ),
                ),
                Expanded(flex: 3, child: Text('ACTIONS', textAlign: TextAlign.right, style: _enteteColonne)),
              ],
            ),
          ),
          if (lignes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AgriSpacing.lg),
              child: Text(
                DevisOnglet.etatVide,
                key: Key('devis-vide'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AgriTypography.base, color: AgriColors.outline),
              ),
            ),
          for (final (i, l) in lignes.indexed) _ligne(l, i),
        ],
      ),
    );
  }

  Widget _ligne(LigneDevis l, int index) {
    final d = l.devis;
    const corps = TextStyle(fontSize: AgriTypography.xs);
    return Container(
      key: Key('devis-ligne-$index'),
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
                Text(
                  d.quoteNumber ?? '—',
                  key: Key('devis-numero-$index'),
                  style: corps.copyWith(fontWeight: FontWeight.bold, color: AgriColors.brandEmerald),
                ),
                ..._etatEnvoi(l),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              l.client ?? '—',
              key: Key('devis-client-$index'),
              style: corps.copyWith(fontWeight: FontWeight.bold, color: AgriColors.brandForest),
            ),
          ),
          Expanded(flex: 2, child: Text(_jour(d.quoteDate), style: corps)),
          Expanded(
            flex: 2,
            child: Text(_jour(l.valideJusqua), key: Key('devis-validite-$index'), style: corps),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${PmpService.francs(d.amount)} FCFA',
              key: Key('devis-montant-$index'),
              textAlign: TextAlign.right,
              style: corps.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(left: AgriSpacing.md),
              child: Align(alignment: Alignment.centerLeft, child: _badgeStatut(d)),
            ),
          ),
          Expanded(flex: 3, child: _actions(d)),
        ],
      ),
    );
  }

  /// `inline-flex px-sm py-[2px] rounded-full text-[11px] font-bold border` — les cinq styles du Blade
  /// (`$statusStyles`) : brouillon et facturé gris, envoyé bleu, accepté émeraude, refusé rouge.
  Widget _badgeStatut(Quote d) {
    final (fond, texte, bord) = switch (d.status) {
      'envoye' => (
        AgriColors.infoBlue.withValues(alpha: 0.10),
        AgriColors.infoBlue,
        AgriColors.infoBlue.withValues(alpha: 0.30),
      ),
      'accepte' => (
        AgriColors.brandEmerald.withValues(alpha: 0.10),
        AgriColors.brandEmerald,
        AgriColors.brandEmerald.withValues(alpha: 0.30),
      ),
      'refuse' => (
        AgriColors.errorBg,
        AgriColors.errorDeep,
        AgriColors.errorDeep.withValues(alpha: 0.30),
      ),
      _ => (AgriColors.surfaceZebra, AgriColors.outline, AgriColors.outlineVariant),
    };
    return Container(
      key: Key('devis-statut-${d.id}'),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: fond,
        border: Border.all(color: bord),
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
      child: Text(
        DevisRepository.statuts[d.status] ?? d.status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: texte),
      ),
    );
  }

  /// ➕ Ajout du poste : l'état d'envoi d'une saisie de ce poste, sous son numéro.
  List<Widget> _etatEnvoi(LigneDevis l) {
    final d = l.devis;
    if (d.syncStatus == SyncStatus.synced) return const [];
    final refuse = d.syncStatus == SyncStatus.conflict;
    return [
      const SizedBox(height: 2),
      Container(
        key: Key('devis-etat-${d.id}'),
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: refuse ? AgriColors.errorBg : AgriColors.accentYellow.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
        child: Text(
          !refuse
              ? 'À envoyer'
              : d.isActive
              ? 'Refusé'
              : 'Archivage refusé',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: refuse ? AgriColors.errorDeep : AgriColors.brandForest,
          ),
        ),
      ),
      if (refuse)
        Text(
          l.motifRefus ?? 'Refus sans motif communiqué.',
          key: Key('devis-motif-${d.id}'),
          style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
        ),
    ];
  }

  /// Les icônes d'action du Blade, dans son ordre et aux mêmes conditions : brouillon → « Marquer comme envoyé » ;
  /// envoyé → « Marquer comme accepté » et « Marquer comme refusé » ; accepté → « Convertir en Facture » ; puis
  /// « Modifier » et « Archiver ».
  Widget _actions(Quote d) {
    Widget action({
      required String cle,
      required String infobulle,
      required IconData icone,
      required Color couleur,
      required VoidCallback surAppui,
    }) => Tooltip(
      message: infobulle,
      child: InkWell(
        key: Key(cle),
        onTap: surAppui,
        borderRadius: BorderRadius.circular(AgriRadius.full),
        child: Padding(padding: const EdgeInsets.all(4), child: Icon(icone, size: 18, color: couleur)),
      ),
    );

    return Wrap(
      alignment: WrapAlignment.end,
      children: [
        if (widget.peutGerer && d.status == 'brouillon')
          action(
            cle: 'devis-envoyer-${d.id}',
            infobulle: 'Marquer comme envoyé',
            icone: SymbolesAgri.send,
            couleur: AgriColors.infoBlue,
            surAppui: () => _changerStatut(d, 'envoye', DevisRepository.toastEnvoye, TypeToast.succes),
          ),
        if (widget.peutGerer && d.status == 'envoye') ...[
          action(
            cle: 'devis-accepter-${d.id}',
            infobulle: 'Marquer comme accepté',
            icone: SymbolesAgri.check_circle,
            couleur: AgriColors.brandEmerald,
            surAppui: () => _changerStatut(d, 'accepte', DevisRepository.toastAccepte, TypeToast.succes),
          ),
          action(
            cle: 'devis-refuser-${d.id}',
            infobulle: 'Marquer comme refusé',
            icone: SymbolesAgri.cancel,
            couleur: AgriColors.errorDeep,
            surAppui: () => _changerStatut(d, 'refuse', DevisRepository.toastRefuse, TypeToast.avertissement),
          ),
        ],
        // `convertToInvoice()` n'a pas d'`authorize()` au web : le bouton est montré à tous.
        if (d.status == 'accepte')
          action(
            cle: 'devis-convertir-${d.id}',
            infobulle: 'Convertir en Facture',
            icone: SymbolesAgri.receipt_long,
            couleur: AgriColors.brandEmerald,
            surAppui: () => ToastAgri.afficher(context, DevisRepository.toastConversion, type: TypeToast.avertissement),
          ),
        if (widget.peutGerer) ...[
          action(
            cle: 'devis-modifier-${d.id}',
            infobulle: 'Modifier',
            icone: SymbolesAgri.edit,
            couleur: AgriColors.brandEmerald,
            surAppui: () => _ouvrirFormulaire(d),
          ),
          action(
            cle: 'devis-archiver-${d.id}',
            infobulle: 'Archiver',
            icone: SymbolesAgri.delete,
            couleur: AgriColors.outline,
            surAppui: () => _archiver(d),
          ),
        ],
      ],
    );
  }

  /// `markAsSent` / `markAsAccepted` / `markAsRefused` : toast du web en cas de succès ; un refus (pas interdit,
  /// devis archivé ou d'un exercice clos) est un toast d'erreur, comme au web.
  Future<void> _changerStatut(Quote d, String statut, String message, TypeToast type) async {
    try {
      await widget.depot.changerStatut(d.id, statut);
    } on DevisRefuse catch (e) {
      if (!mounted) return;
      ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      return;
    }
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(context, message, type: type);
  }

  /// `archiveQuote($id)` derrière `x-modal-confirm-delete` : icône `archive` `text-error-deep`, « Confirmer
  /// l'archivage », le numéro du devis, « Annuler » puis « Archiver » (`bg-error-red`).
  Future<void> _archiver(Quote d) async {
    final confirme = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (contexte) => ModaleConfirmation(
        icone: SymbolesAgri.archive,
        couleurIcone: AgriColors.errorDeep,
        titre: "Confirmer l'archivage",
        message:
            '${d.quoteNumber ?? 'Ce devis'} sera marqué(e) comme archivé(e) (statut inactif). '
            "Aucune suppression définitive n'est effectuée.",
        actions: [
          BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(contexte).pop(false)),
          BoutonModalePrimaire(
            key: const Key('archivage-devis-confirmer'),
            libelle: 'Archiver',
            couleur: AgriColors.errorRed,
            onPressed: () => Navigator.of(contexte).pop(true),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    bool archive;
    try {
      archive = await widget.depot.archiver(d.id);
    } on DevisRefuse catch (e) {
      if (!mounted) return;
      ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      return;
    }
    await _charger();
    // Un second archivage ne fait rien, et ne dit rien (le web non plus).
    if (!mounted || !archive) return;
    ToastAgri.afficher(context, DevisRepository.toastArchive, type: TypeToast.avertissement);
  }

  // ── 5. Modale « Nouveau Devis » / « Modifier le Devis » ─────────────────────────────────────────────────────────

  Future<void> _ouvrirFormulaire(Quote? existant) async {
    final clients = _donnees?.clients ?? await widget.depot.clients();
    if (!mounted) return;
    final message = await afficherModale<String>(
      context: context,
      constructeur: (_) => _ModaleDevis(depot: widget.depot, clients: clients, existant: existant),
    );
    if (message == null) return;
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(context, message);
  }
}

/// `modal-create-devis` (`max-width="md"`), champ pour champ : « Client * », « Articles / Prestations * », « Montant HT
/// (FCFA) * », « TVA (%) », « Validité (jours) », « Date du Devis », « Note (optionnel) » ; erreurs sous leur champ
/// (`@error` du Blade) ; « Annuler » / « Enregistrer ». Rend le toast de succès (`null` : fermée sans enregistrer).
class _ModaleDevis extends StatefulWidget {
  const _ModaleDevis({required this.depot, required this.clients, required this.existant});

  final DevisRepository depot;
  final List<Customer> clients;
  final Quote? existant;

  @override
  State<_ModaleDevis> createState() => _ModaleDevisState();
}

class _ModaleDevisState extends State<_ModaleDevis> {
  late String? _client = widget.existant?.customerId;
  late final _articles = TextEditingController(text: widget.existant?.articlesDescription ?? '');
  late final _montant = TextEditingController(
    text: widget.existant == null ? '' : PmpService.flottant(widget.existant!.amount),
  );
  late String _tva = PmpService.flottant(widget.existant?.tvaRate ?? DevisRepository.tvaParDefaut.toDouble());
  late final _validite = TextEditingController(
    text: '${widget.existant?.validityDays ?? DevisRepository.validiteParDefaut}',
  );
  late DateTime _date = widget.existant?.quoteDate ?? HeureBenin.aujourdhui();
  late final _note = TextEditingController(text: widget.existant?.note ?? '');

  Map<String, String> _erreurs = const {};
  bool _enregistrement = false;

  bool get _creation => widget.existant == null;

  @override
  void dispose() {
    _articles.dispose();
    _montant.dispose();
    _validite.dispose();
    _note.dispose();
    super.dispose();
  }

  /// `saveQuote()` : erreurs sous leur champ ; un refus qui n'est celui d'aucun champ (devis archivé, facturé) est un
  /// toast d'erreur et la modale reste ouverte ; sinon la modale se ferme et rend le toast de succès.
  Future<void> _enregistrer() async {
    setState(() {
      _enregistrement = true;
      _erreurs = const {};
    });
    try {
      await widget.depot.enregistrer(
        clientId: _client,
        articles: _articles.text,
        montant: _montant.text,
        tva: _tva,
        validite: _validite.text,
        date: _date,
        note: _note.text,
        idEnModification: widget.existant?.id,
      );
    } on DevisRefuse catch (e) {
      if (!mounted) return;
      final aucunChamp = e.erreurs.keys.every((c) => c == 'devis');
      if (aucunChamp) ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      setState(() {
        _erreurs = aucunChamp ? const {} : e.erreurs;
        _enregistrement = false;
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(_creation ? DevisRepository.toastCree : DevisRepository.toastModifie);
  }

  /// `block text-[10px] text-brand-forest font-bold uppercase mb-xs`.
  Widget _etiquette(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
    child: Text(
      texte.toUpperCase(),
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgriColors.brandForest),
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
        key: Key('devis-erreur-$cle'),
        style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
      ),
    );
  }

  OutlineInputBorder _bord(String cle) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AgriRadius.lg),
    borderSide: BorderSide(color: _erreurs.containsKey(cle) ? AgriColors.errorDeep : AgriColors.outlineVariant),
  );

  Widget _champTexte({
    required String libelle,
    required String cle,
    required TextEditingController controleur,
    String? exemple,
    bool nombre = false,
    int lignes = 1,
    bool gras = false,
  }) {
    final enErreur = _erreurs.containsKey(cle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette(libelle),
        SizedBox(
          height: lignes == 1 ? 44 : null,
          child: TextField(
            key: Key('devis-$cle'),
            controller: controleur,
            minLines: lignes,
            maxLines: lignes,
            keyboardType: nombre ? TextInputType.number : TextInputType.multiline,
            style: TextStyle(fontSize: AgriTypography.sm, fontWeight: gras ? FontWeight.bold : FontWeight.normal),
            decoration: InputDecoration(
              hintText: exemple,
              isDense: true,
              filled: enErreur,
              fillColor: const Color(0xFFFFF5F5),
              contentPadding: EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: lignes == 1 ? 12 : AgriSpacing.sm),
              border: _bord(cle),
              enabledBorder: _bord(cle),
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
    String? vide,
  }) {
    final presente = options.any((o) => o.$1 == valeur);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette(libelle),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
          decoration: BoxDecoration(
            color: _erreurs.containsKey(cle) ? const Color(0xFFFFF5F5) : AgriColors.surfaceCard,
            border: Border.all(color: _erreurs.containsKey(cle) ? AgriColors.errorDeep : AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: Key('devis-liste-$cle'),
              isExpanded: true,
              value: presente ? valeur : null,
              hint: vide == null
                  ? null
                  : Text(vide, style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface)),
              style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
              items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
              onChanged: surChangement,
            ),
          ),
        ),
        _erreur(cle),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Le `<select>` « TVA (%) » du Blade n'offre que 0 % et 18 % ; un devis déjà saisi avec un autre taux le garde.
    final taux = {for (final t in DevisRepository.tauxTva) '$t', _tva}.toList()
      ..sort((a, b) => double.parse(a).compareTo(double.parse(b)));

    return ModaleAgri(
      titre: _creation ? 'Nouveau Devis' : 'Modifier le Devis',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _champListe(
            libelle: 'Client *',
            cle: 'client',
            valeur: _client,
            vide: '-- Sélectionner --',
            options: [for (final c in widget.clients) (c.id, c.name)],
            surChangement: (v) => setState(() => _client = v),
          ),
          const SizedBox(height: AgriSpacing.md),
          _champTexte(
            libelle: 'Articles / Prestations *',
            cle: 'articles',
            controleur: _articles,
            exemple: 'ex : 2 cages galvanisées 6 compartiments sur mesure',
            lignes: 3,
          ),
          const SizedBox(height: AgriSpacing.md),
          // `grid grid-cols-3 gap-sm`.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _champTexte(
                  libelle: 'Montant HT (FCFA) *',
                  cle: 'montant',
                  controleur: _montant,
                  nombre: true,
                  gras: true,
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _champListe(
                  libelle: 'TVA (%)',
                  cle: 'tva',
                  valeur: _tva,
                  options: [for (final t in taux) (t, '$t %')],
                  surChangement: (v) => setState(() => _tva = v ?? _tva),
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _champTexte(
                  libelle: 'Validité (jours)',
                  cle: 'validite',
                  controleur: _validite,
                  nombre: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          ChampDateFormulaire(
            cle: const Key('devis-date'),
            etiquette: 'Date du Devis',
            valeur: _date,
            erreur: _erreurs['date'],
            cleErreur: const Key('devis-erreur-date'),
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
          const SizedBox(height: AgriSpacing.md),
          _champTexte(libelle: 'Note (optionnel)', cle: 'note', controleur: _note, lignes: 2),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
        BoutonModalePrimaire(
          key: const Key('devis-enregistrer'),
          libelle: 'Enregistrer',
          onPressed: _enregistrement ? null : _enregistrer,
        ),
      ],
    );
  }
}
