import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/comptabilite/exercice_choisi.dart';
import '../../core/erreurs/message_erreur.dart';
import '../../core/export/pdf_recu.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/champs_date_agri.dart';
import '../../core/widgets/grille_kpi.dart';
import '../../core/widgets/lecture_seule.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/pagination_agri.dart';
import '../../core/widgets/toast_agri.dart';
import '../../core/temps/heure_benin.dart';
import 'avoirs_repository.dart';
import 'elements_ventes.dart';
import 'historique_ventes_repository.dart';

/// Onglet « Historique des Ventes » du hub Ventes & Devis — `resources/views/livewire/ventes/historique-ventes.blade.php`
/// et `Livewire\Ventes\HistoriqueVentes` (ticket AV2). La vue Blade est le maître : audit ligne à ligne dans
/// `docs/AUDIT_FIDELITE_ECRANS.md` § 11, verrouillé par `test/historique_ventes_blade_test.dart`.
///
///  1. en-tête : icône `receipt_long`, « Historique des Ventes », « Toutes les ventes enregistrées de l'entreprise. »,
///     bouton « Nouvelle Vente » (le hub, sur son premier onglet) et la période (deux champs Date bornés à l'exercice) ;
///  2. quatre cartes sur la PÉRIODE : Chiffre d'Affaires, Transactions, Panier Moyen, Encours Créances ;
///  3. filtres : recherche « Facture, client... », Statut, Mode, Client, « Réinitialiser » ;
///  4. tableau de onze colonnes, 25 ventes par page DANS L'EXERCICE AFFICHÉ (la période n'y filtre rien : c'est la règle du
///     web, `getSalesProperty()` ne lit pas `dateFrom` / `dateTo`) ; actions Voir et Annuler ;
///  5. modale « Annuler cette vente ? » et tiroir de détail (articles, sous-total, remise, total, « Télécharger PDF »).
///
/// ⚠️⚠️ **« ANNULER » EST UNE DEMANDE** : la vente passe à « Annulée » ici et repart ; le serveur réintègre le stock
/// (voir [HistoriqueVentesRepository.annuler]). Le toast du web, « Vente annulée — stock réintégré. », dit un effet qui n'a
/// pas encore eu lieu au poste : l'écran l'écrit « … — le stock sera réintégré à la synchronisation. » (ÉCART ASSUMÉ).
///
/// ⚠️ ÉCARTS ASSUMÉS (hors ligne) : « Télécharger PDF » exige le réseau (le ticket est produit par le serveur) et ENREGISTRE
/// le fichier dans Documents\AgriERP au lieu de le télécharger dans un navigateur ; sous la pastille d'une vente pas encore
/// reçue du serveur, la mention « Non envoyée » ; le bouton « Annuler » est grisé sans `manage-ventes` (le web 403 à
/// l'envoi), comme `@lectureSeule` le grise quand l'exercice affiché est clos.
class HistoriqueVentesOnglet extends StatefulWidget {
  const HistoriqueVentesOnglet({
    super.key,
    required this.depot,
    this.peutGerer = true,
    this.peutExporter = true,
    this.onNouvelleVente,
    this.enregistrer,
  });

  final HistoriqueVentesRepository depot;

  /// `manage-ventes` : sans lui, « Annuler » est refusé (« Votre rôle ne permet pas cette action. »).
  final bool peutGerer;

  /// `export-ventes` : sans lui, « Télécharger PDF » est refusé.
  final bool peutExporter;

  /// `<a href="{{ route('ventes.devis-hub') }}">` : le hub, sur son premier onglet (Enregistrer Vente).
  final VoidCallback? onNouvelleVente;

  /// Écrit le PDF reçu ; `LivraisonPdf.enregistrer` en production, un espion en test.
  final Future<String> Function(PdfRecu pdf)? enregistrer;

  /// `wire:model.live.debounce.300ms` du champ de recherche.
  static const delaiRecherche = Duration(milliseconds: 300);

  /// Le toast du web, `cancelSale()` : « Vente annulée — stock réintégré. ».
  static const toastAnnulee = 'Vente annulée — stock réintégré.';

  /// ⚠️ ÉCART ASSUMÉ : au poste, le stock n'est réintégré qu'à la synchronisation.
  static const toastAnnuleeAuPoste = 'Vente annulée — le stock sera réintégré à la synchronisation.';

  static const refusDroit = 'Votre rôle ne permet pas cette action.';

  @override
  State<HistoriqueVentesOnglet> createState() => _HistoriqueVentesOngletState();
}

class _HistoriqueVentesOngletState extends State<HistoriqueVentesOnglet> {
  InstantaneHistorique? _donnees;

  // Filtres (`#[Url] public string $search, $statusFilter, $modeFilter, $customerFilter`).
  final _recherche = TextEditingController();
  Timer? _minuterie;
  String _recherchee = '';
  String _statut = '';
  String _mode = '';
  String _clientId = '';

  /// `$dateFrom` / `$dateTo` : la période des cartes. Posée au premier affichage, puis à chaque changement d'exercice.
  DateTime? _du;
  DateTime? _au;
  int? _anneePeriode;

  /// Ticket EX7 (EF9) — page de 25 ventes, dans l'exercice affiché.
  int _page = 1;

  /// `$viewingSaleId` : le tiroir de détail.
  String? _voirId;
  bool _pdfEnCours = false;

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
    final donnees = await widget.depot.charger();
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  /// `mount()` : `ExerciceChoisi::periodeParDefaut(début du mois, aujourd'hui)` — dans l'exercice affiché quand il contient
  /// le jour, l'exercice entier sinon (2026 consulté en 2027).
  void _initialiserPeriode(EtatExercice? etat) {
    final annee = etat?.annee;
    if (_du != null && _anneePeriode == annee) return;
    final aujourdhui = HeureBenin.aujourdhui();
    final debutMois = DateTime(aujourdhui.year, aujourdhui.month);
    if (etat == null) {
      _du = debutMois;
      _au = aujourdhui;
    } else {
      final p = etat.periodeParDefaut(debutMois, aujourdhui);
      _du = p.debut;
      _au = p.fin;
    }
    _anneePeriode = annee;
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;
    if (d == null) return const Center(child: CircularProgressIndicator());

    final etat = PorteeExerciceChoisi.lire(context);
    _initialiserPeriode(etat);
    final large = AgriBreakpoints.large(context);
    final detail = _voirId == null ? null : d.detail(_voirId!);

    final contenu = SingleChildScrollView(
      padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _entete(large, etat),
          const SizedBox(height: AgriSpacing.md),
          _kpis(d),
          const SizedBox(height: AgriSpacing.md),
          _filtres(d),
          const SizedBox(height: AgriSpacing.md),
          _tableau(d, etat),
        ],
      ),
    );

    if (detail == null) return contenu;

    // `x-on:keydown.escape.window="$wire.closeDrawer()"`, voile `fixed inset-0 bg-black/40`, tiroir `w-full sm:w-96`.
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _fermerTiroir},
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            contenu,
            Positioned.fill(
              child: GestureDetector(
                key: const Key('tiroir-voile'),
                behavior: HitTestBehavior.opaque,
                onTap: _fermerTiroir,
                child: const ColoredBox(color: Color(0x66000000)),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: AgriBreakpoints.petit(context) ? 384 : MediaQuery.sizeOf(context).width,
              child: _tiroir(detail),
            ),
          ],
        ),
      ),
    );
  }

  // ── 1. En-tête ─────────────────────────────────────────────────────────────────────────────────────────────────────────

  Widget _entete(bool large, EtatExercice? etat) {
    const titre = TitreOnglet(
      icone: SymbolesAgri.receipt_long,
      titre: 'Historique des Ventes',
      sousTitre: "Toutes les ventes enregistrées de l'entreprise.",
    );
    final bouton = BoutonEntete(
      key: const Key('nouvelle-vente'),
      icone: SymbolesAgri.add_circle,
      libelle: 'Nouvelle Vente',
      onPressed: widget.onNouvelleVente,
    );

    return EnteteOnglet(
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          large
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [const Flexible(child: titre), bouton],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [titre, const SizedBox(height: AgriSpacing.sm), bouton],
                ),
          const SizedBox(height: AgriSpacing.md),
          _periode(etat),
        ],
      ),
    );
  }

  /// `flex items-center gap-xs bg-white border border-outline-variant rounded-lg p-sm w-fit` : icône, début, « au », fin.
  Widget _periode(EtatExercice? etat) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      key: const Key('periode'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Wrap(
        spacing: AgriSpacing.xs,
        runSpacing: AgriSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(SymbolesAgri.calendar_month, size: AgriChamps.iconePeriode, color: AgriColors.outline),
          ChampDateFiltre(
            cle: const Key('date-debut'),
            valeur: _du!,
            compact: true,
            onTap: () => _choisirDate(_du!, etat, debut: true),
          ),
          const Text('au', style: StylesChampsAgri.motPeriode),
          ChampDateFiltre(
            cle: const Key('date-fin'),
            valeur: _au!,
            compact: true,
            onTap: () => _choisirDate(_au!, etat, debut: false),
          ),
        ],
      ),
    ),
  );

  Future<void> _choisirDate(DateTime valeur, EtatExercice? etat, {required bool debut}) async {
    // `min` / `max` du web : le calendrier est borné à l'exercice affiché.
    final choix = await showDatePicker(
      context: context,
      initialDate: etat?.borner(valeur) ?? valeur,
      firstDate: etat?.bornes.debut ?? DateTime(2020),
      lastDate: etat?.bornes.fin ?? DateTime(2100),
      locale: const Locale('fr'),
    );
    if (choix == null || !mounted) return;
    setState(() {
      final nouveauDu = debut ? choix : _du!;
      final nouveauAu = debut ? _au! : choix;
      // `updatedDateFrom()` : une date saisie hors de l'exercice est ramenée à sa borne, début ≤ fin.
      final p = etat?.bornerPeriode(nouveauDu, nouveauAu) ??
          (nouveauAu.isBefore(nouveauDu)
              ? (debut: nouveauDu, fin: nouveauDu)
              : (debut: nouveauDu, fin: nouveauAu));
      _du = p.debut;
      _au = p.fin;
    });
  }

  // ── 2. Cartes ──────────────────────────────────────────────────────────────────────────────────────────────────────────

  Widget _kpis(InstantaneHistorique d) {
    final k = d.kpis(_du!, _au!);
    return GrilleKpi(
      cartes: [
        CarteKpi(
          key: const Key("kpi-Chiffre d'Affaires"),
          libelle: "Chiffre d'Affaires",
          valeur: AvoirsRepository.montantFr(k.chiffreAffaires),
          unite: 'FCFA',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.payments,
          couleurIcone: AgriColors.brandEmerald,
        ),
        CarteKpi(
          key: const Key('kpi-Transactions'),
          libelle: 'Transactions',
          valeur: '${k.transactions}',
          couleurLisere: AgriColors.infoBlue,
          icone: SymbolesAgri.receipt,
          couleurIcone: AgriColors.infoBlue,
        ),
        CarteKpi(
          key: const Key('kpi-Panier Moyen'),
          libelle: 'Panier Moyen',
          valeur: AvoirsRepository.montantFr(k.panierMoyen),
          unite: 'FCFA',
          couleurLisere: AgriColors.accentYellow,
          icone: SymbolesAgri.shopping_cart,
          couleurIcone: AgriColors.brandForest,
        ),
        CarteKpi(
          key: const Key('kpi-Encours Créances'),
          libelle: 'Encours Créances',
          valeur: AvoirsRepository.montantFr(k.encoursCreances),
          unite: 'FCFA',
          couleurLisere: AgriColors.errorRed,
          icone: SymbolesAgri.request_quote,
          couleurIcone: AgriColors.errorRed,
        ),
      ],
    );
  }

  // ── 3. Filtres ─────────────────────────────────────────────────────────────────────────────────────────────────────────

  Widget _filtres(InstantaneHistorique d) => Container(
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
        // `relative flex-1 min-w-[180px]` : le champ prend la place restante de la ligne.
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 180, maxWidth: 420),
          child: SizedBox(width: 320, child: _champRecherche()),
        ),
        _menu(
          cle: 'filtre-statut',
          valeur: _statut,
          defaut: 'Statut : Toutes',
          options: [for (final (v, l) in HistoriqueVentesRepository.statuts) (v, l)],
          surChangement: (v) => setState(() {
            _statut = v;
            _page = 1;
          }),
        ),
        _menu(
          cle: 'filtre-mode',
          valeur: _mode,
          defaut: 'Mode : Tous',
          options: [for (final e in HistoriqueVentesRepository.libellesModes.entries) (e.key, e.value)],
          surChangement: (v) => setState(() {
            _mode = v;
            _page = 1;
          }),
        ),
        _menu(
          cle: 'filtre-client',
          valeur: _clientId,
          defaut: 'Client : Tous',
          options: [for (final c in d.clientsActifs) (c.id, c.name)],
          surChangement: (v) => setState(() {
            _clientId = v;
            _page = 1;
          }),
        ),
        TextButton.icon(
          key: const Key('reinitialiser'),
          onPressed: _reinitialiser,
          icon: const Icon(SymbolesAgri.restart_alt, size: 16),
          label: const Text('Réinitialiser', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
          style: TextButton.styleFrom(
            foregroundColor: AgriColors.outline,
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: AgriSpacing.sm),
          ),
        ),
      ],
    ),
  );

  /// `pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white` + icône `search` 18 px à gauche.
  Widget _champRecherche() {
    final bord = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      borderSide: const BorderSide(color: AgriColors.outlineVariant),
    );
    return TextField(
      key: const Key('recherche-ventes'),
      controller: _recherche,
      style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
      onChanged: (v) {
        _minuterie?.cancel();
        _minuterie = Timer(HistoriqueVentesOnglet.delaiRecherche, () {
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
        hintText: 'Facture, client...',
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

  /// `<select class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">`.
  Widget _menu({
    required String cle,
    required String valeur,
    required String defaut,
    required List<(String, String)> options,
    required void Function(String) surChangement,
  }) => Container(
    key: Key(cle),
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: options.any((o) => o.$1 == valeur) ? valeur : '',
        style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
        items: [
          DropdownMenuItem(value: '', child: Text(defaut)),
          for (final (v, libelle) in options) DropdownMenuItem(value: v, child: Text(libelle)),
        ],
        onChanged: (v) => surChangement(v ?? ''),
      ),
    ),
  );

  /// `resetFilters()` : la recherche et les trois listes — jamais la période.
  void _reinitialiser() {
    _minuterie?.cancel();
    _recherche.clear();
    setState(() {
      _recherchee = '';
      _statut = '';
      _mode = '';
      _clientId = '';
      _page = 1;
    });
  }

  // ── 4. Tableau ─────────────────────────────────────────────────────────────────────────────────────────────────────────

  static const _colonnes = [
    ColonneTableau('Facture', 2),
    ColonneTableau('Client', 3),
    ColonneTableau('Date', 3),
    ColonneTableau('Articles', 2, droite: true),
    ColonneTableau('Remise', 2, droite: true),
    ColonneTableau('Total TTC', 3, droite: true),
    ColonneTableau('Payé', 2, droite: true),
    ColonneTableau('Reste', 2, droite: true),
    ColonneTableau('Mode', 3),
    ColonneTableau('Statut', 3),
    ColonneTableau('Actions', 2, droite: true),
  ];

  Widget _tableau(InstantaneHistorique d, EtatExercice? etat) {
    // Ticket EX7 (EF9) — les ventes de l'exercice AFFICHÉ, 25 par page (`soldBetween` de l'exercice puis `paginate(25)`).
    final toutes = d.filtrer(
      recherche: _recherchee,
      statut: _statut,
      mode: _mode,
      clientId: _clientId,
      dansExercice: etat?.contient,
    );
    final lignes = etat == null ? toutes : PaginationAgri.tranche(toutes, _page);
    final motifLecture = LectureSeule.motif(context);

    return TableauAgri(
      colonnes: _colonnes,
      largeur: 1180,
      clePrefixe: 'vente',
      videTexte: 'Aucune vente pour le moment.',
      opaciteLigne: (i) => lignes[i].annulee ? 0.5 : 1,
      lignes: [for (final l in lignes) _cellules(l, motifLecture)],
      pied: etat == null
          ? null
          : PaginationAgri(
              nom: 'ventes',
              total: toutes.length,
              page: _page,
              annee: etat.annee,
              onPage: (p) => setState(() => _page = p),
            ),
    );
  }

  List<Widget> _cellules(LigneVente l, String? motifLecture) {
    final v = l.vente;
    return [
      // `text-brand-emerald hover:underline font-bold font-mono` : la facture ouvre le détail.
      InkWell(
        key: Key('vente-ref-${v.id}'),
        onTap: () => setState(() => _voirId = v.id),
        child: Text(
          l.facture,
          style: styleCellule.copyWith(
            color: AgriColors.brandEmerald,
            fontWeight: AgriTypography.gras,
            fontFamily: 'monospace',
          ),
        ),
      ),
      Text(
        l.client,
        style: styleCellule.copyWith(fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
        overflow: TextOverflow.ellipsis,
      ),
      Text(_horodatage(v.soldAt), style: styleCellule),
      Text('${l.articles}', style: styleCellule),
      Text(AvoirsRepository.montantFr(v.discount), style: styleCellule),
      Text(
        '${AvoirsRepository.montantFr(v.total)} FCFA',
        style: styleCellule.copyWith(fontWeight: AgriTypography.gras),
      ),
      Text(AvoirsRepository.montantFr(l.paye), style: styleCellule.copyWith(color: AgriColors.brandEmerald)),
      Text(
        AvoirsRepository.montantFr(l.reste),
        style: l.reste > 0
            ? styleCellule.copyWith(color: AgriColors.errorDeep, fontWeight: AgriTypography.gras)
            : styleCellule,
      ),
      Text(l.mode, style: styleCellule),
      _pastilleStatut(l),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          boutonIconeTableau(
            cle: Key('vente-voir-${v.id}'),
            infobulle: 'Voir',
            icone: SymbolesAgri.visibility,
            couleur: AgriColors.infoBlue,
            onPressed: () => setState(() => _voirId = v.id),
          ),
          if (!l.annulee)
            LectureSeule.infobulle(
              motifLecture,
              boutonIconeTableau(
                cle: Key('vente-annuler-${v.id}'),
                infobulle: motifLecture == null ? 'Annuler' : null,
                icone: SymbolesAgri.delete,
                couleur: motifLecture == null ? AgriColors.errorDeep : AgriColors.outlineVariant,
                onPressed: motifLecture == null ? () => _confirmerAnnulation(v.id) : null,
              ),
            ),
        ],
      ),
    ];
  }

  Widget _pastilleStatut(LigneVente l) {
    final pastille = switch (l.statut) {
      'Annulée' => const PastilleStatut.erreur('Annulée'),
      'En attente' => const PastilleStatut.attente('En attente'),
      _ => const PastilleStatut.succes('Payée'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        pastille,
        // ⚠️ ÉCART ASSUMÉ (hors ligne) : le web n'a pas cette ligne. Une vente saisie ici n'existe pas encore côté ferme.
        if (!l.envoyee)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Non envoyée',
              key: Key('vente-envoi-${l.vente.id}'),
              style: const TextStyle(fontSize: 10, color: AgriColors.outline),
            ),
          ),
      ],
    );
  }

  /// `$sale->date_effective->format('d/m/Y H:i')`.
  static String _horodatage(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ── 5. Annulation et tiroir ────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> _confirmerAnnulation(String id) async {
    final motifLecture = LectureSeule.motif(context);
    final confirme = await afficherModale<bool>(
      context: context,
      constructeur: (_) => _ModaleAnnulation(motifLecture: motifLecture),
    );
    if (confirme != true || !mounted) return;
    if (!widget.peutGerer) {
      ToastAgri.afficher(context, HistoriqueVentesOnglet.refusDroit, type: TypeToast.erreur);
      return;
    }
    final annulee = await widget.depot.annuler(id);
    if (!mounted) return;
    if (annulee) {
      ToastAgri.afficher(context, HistoriqueVentesOnglet.toastAnnuleeAuPoste, type: TypeToast.avertissement);
    }
    await _charger();
  }

  void _fermerTiroir() => setState(() => _voirId = null);

  Widget _tiroir(DetailVente detail) {
    final l = detail.ligne;
    final v = l.vente;
    return Material(
      key: const Key('tiroir-detail'),
      color: AgriColors.surfaceCard,
      elevation: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `px-lg py-md border-b bg-brand-forest` : la référence en `font-mono` blanche et le ✕.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.lg, vertical: AgriSpacing.md),
            decoration: const BoxDecoration(
              color: AgriColors.brandForest,
              border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.facture,
                    key: const Key('tiroir-reference'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: AgriTypography.gras,
                      fontSize: AgriTypography.sm,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                InkWell(
                  key: const Key('tiroir-fermer-x'),
                  onTap: _fermerTiroir,
                  child: const Icon(SymbolesAgri.close, size: 24, color: Color(0xCCFFFFFF)),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _donnee('Client', l.client)),
                      Expanded(child: _donnee('Date', _horodatage(v.soldAt))),
                    ],
                  ),
                  const SizedBox(height: AgriSpacing.md),
                  Container(
                    padding: const EdgeInsets.only(top: AgriSpacing.md),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: AgriColors.outlineVariant))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ARTICLES',
                          style: TextStyle(
                            fontSize: AgriTypography.xs,
                            fontWeight: AgriTypography.gras,
                            color: AgriColors.brandForest,
                          ),
                        ),
                        const SizedBox(height: AgriSpacing.sm),
                        for (var i = 0; i < detail.articles.length; i++)
                          Container(
                            key: Key('tiroir-article-$i'),
                            padding: const EdgeInsets.only(bottom: 4),
                            margin: const EdgeInsets.only(bottom: AgriSpacing.xs),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0x80BEC9C2))),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    '${detail.articles[i].nom} × ${AvoirsRepository.quantiteFr(detail.articles[i].quantite)}',
                                    style: styleCellule,
                                  ),
                                ),
                                Text(
                                  '${AvoirsRepository.montantFr(detail.articles[i].montant)} FCFA',
                                  style: styleCellule.copyWith(fontWeight: AgriTypography.gras),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.md),
                  Container(
                    padding: const EdgeInsets.only(top: AgriSpacing.md),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: AgriColors.outlineVariant))),
                    child: Column(
                      children: [
                        _ligneTotal('Sous-total', '${AvoirsRepository.montantFr(v.subtotal)} FCFA'),
                        const SizedBox(height: 4),
                        _ligneTotal('Remise', '${AvoirsRepository.montantFr(v.discount)} FCFA'),
                        const SizedBox(height: 4),
                        _ligneTotal('Total', '${AvoirsRepository.montantFr(v.total)} FCFA', fort: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AgriSpacing.lg),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AgriColors.outlineVariant))),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: AgriSpacing.sm,
              runSpacing: AgriSpacing.sm,
              children: [
                ElevatedButton.icon(
                  key: const Key('tiroir-pdf'),
                  onPressed: _pdfEnCours ? null : () => _telechargerPdf(v.id),
                  icon: const Icon(SymbolesAgri.download, size: 16),
                  label: const Text(
                    'Télécharger PDF',
                    style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AgriColors.brandEmerald,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
                  ),
                ),
                OutlinedButton(
                  key: const Key('tiroir-fermer'),
                  onPressed: _fermerTiroir,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AgriColors.outline,
                    side: const BorderSide(color: AgriColors.outlineVariant),
                    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
                  ),
                  child: const Text(
                    'Fermer',
                    style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _donnee(String libelle, String valeur) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(libelle, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
      Text(valeur, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
    ],
  );

  Widget _ligneTotal(String libelle, String valeur, {bool fort = false}) {
    final style = fort
        ? const TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandEmerald)
        : const TextStyle(fontSize: AgriTypography.xs);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          libelle,
          style: fort ? style : style.copyWith(color: AgriColors.outline),
        ),
        Text(valeur, style: style),
      ],
    );
  }

  /// `exportSaleTicketPdf()` : le ticket de la vente, produit par le serveur, enregistré dans Documents\AgriERP.
  Future<void> _telechargerPdf(String id) async {
    if (!widget.peutExporter) {
      ToastAgri.afficher(context, 'Votre rôle ne permet pas d\'exporter le ticket d\'une vente.', type: TypeToast.erreur);
      return;
    }
    setState(() => _pdfEnCours = true);
    try {
      final pdf = await widget.depot.ticketPdf(id);
      final chemin = await (widget.enregistrer ?? LivraisonPdf.enregistrer)(pdf);
      if (!mounted) return;
      ToastAgri.afficher(context, 'Ticket enregistré : $chemin');
    } on EchecTicketVente catch (e) {
      if (!mounted) return;
      ToastAgri.afficher(context, e.message, type: TypeToast.erreur);
    } on Object catch (e) {
      if (!mounted) return;
      ToastAgri.afficher(context, messageEcritureFichier(e), type: TypeToast.erreur);
    } finally {
      if (mounted) setState(() => _pdfEnCours = false);
    }
  }
}

/// `<x-modal name="modal-cancel-sale" max-width="sm">` : « Annuler cette vente ? » — pastille `w-12 h-12 bg-error-bg
/// rounded-full` à l'icône `warning` de 28 px, titre, mise en garde, puis « Annuler » et « Oui, Annuler la Vente »
/// (`@lectureSeule` : grisé, avec son motif, quand l'exercice affiché est clos).
///
/// ⚠️ Ce n'est ni [ModaleAgri] (le web n'a ici ni titre ni ✕) ni [ModaleConfirmation] (pastille ronde, boutons en ligne et
/// centrés, voile `bg-black/50`) : le gabarit est celui de `x-modal`, contenu centré.
class _ModaleAnnulation extends StatelessWidget {
  const _ModaleAnnulation({required this.motifLecture});

  final String? motifLecture;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(AgriSpacing.md),
    backgroundColor: Colors.transparent,
    elevation: 0,
    child: Container(
      width: LargeurModale.sm.pixels,
      constraints: BoxConstraints(
        maxWidth: LargeurModale.sm.pixels,
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AgriRadius.lg), boxShadow: AgriShadows.xl),
      child: Material(
        color: AgriColors.surfaceCard,
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AgriSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(color: AgriColors.errorBg, shape: BoxShape.circle),
                  child: const Icon(SymbolesAgri.warning, size: 28, color: AgriColors.errorDeep),
                ),
                const SizedBox(height: AgriSpacing.md),
                const Text(
                  'Annuler cette vente ?',
                  style: TextStyle(
                    fontSize: AgriTypography.lg,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandForest,
                  ),
                ),
                const SizedBox(height: AgriSpacing.xs),
                const Text(
                  'Le stock des produits vendus sera automatiquement réintégré. '
                  'Cette action est réversible uniquement en recréant une nouvelle vente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
                ),
                const SizedBox(height: AgriSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AgriSpacing.sm,
                  runSpacing: AgriSpacing.sm,
                  children: [
                    BoutonModaleSecondaire(
                      libelle: 'Annuler',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    LectureSeule.infobulle(
                      motifLecture,
                      BoutonModalePrimaire(
                        key: const Key('annulation-confirmer'),
                        libelle: 'Oui, Annuler la Vente',
                        couleur: AgriColors.errorDeep,
                        onPressed: motifLecture == null ? () => Navigator.of(context).pop(true) : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
