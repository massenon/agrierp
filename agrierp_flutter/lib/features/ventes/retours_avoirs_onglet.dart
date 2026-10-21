import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/grille_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'avoirs_repository.dart';
import 'elements_ventes.dart';

/// Onglet « Retours et Avoirs » du hub Ventes & Devis — `resources/views/livewire/ventes/retours-avoirs.blade.php` et
/// `Livewire\Ventes\RetoursAvoirs` (ticket AV1). La vue Blade est le maître : même structure, mêmes libellés, mêmes
/// colonnes, mêmes statuts, mêmes messages.
///
///  1. en-tête : icône `assignment_return`, « Retours et Avoirs », sous-titre, bouton « Nouveau Retour » ;
///  2. quatre cartes : Retours du mois, Montant Avoirs, Produits Retournés, Taux de Retour ;
///  3. tableau : Avoir · Facture · Client · Date · Motif · Décision · Montant · Statut · Actions (« Aucun retour pour le
///     moment. » quand il est vide) ;
///  4. modale « Nouveau Retour » en cinq sections (1. Facture Source · 2. Article Retourné · Quantité / Montant ·
///     3. Motif du Retour · 4. Inspection Sanitaire · 5. Décision), « Annuler » / « Enregistrer le Retour ».
///
/// ⚠️⚠️ **LE POSTE ENREGISTRE LA DEMANDE, LE SERVEUR FAIT LES EFFETS** (voir [AvoirsRepository]) : numéro `AV-AAAA-NNN`,
/// stock réintégré, écriture inverse 701 / 443 / 411 arrivent à la synchronisation. D'où trois ÉCARTS ASSUMÉS, dits à
/// l'écran plutôt que cachés :
///  - le numéro d'un avoir encore non reçu est « — » ;
///  - sous le statut, « Non envoyé » (ou le motif de refus du serveur, mot pour mot) : la pastille « En attente » du web
///    dit « pas encore traité », pas « pas encore reçu par la ferme » ;
///  - le toast de succès ne promet pas un effet qui n'a pas eu lieu (voir [AvoirsRepository.toastDemande]).
///
/// ⚠️ DROITS COMME AU WEB : « Nouveau Retour » et l'icône « Marquer comme traité » sont visibles de tout compte qui voit
/// l'écran (`view-ventes`) ; sans `manage-ventes`, l'enregistrement est refusé par « Votre rôle ne permet pas cette
/// action. » (le `authorize()` de `saveReturn()` / `markAsTreated()`), jamais écrit.
class RetoursAvoirsOnglet extends StatefulWidget {
  const RetoursAvoirsOnglet({super.key, required this.depot, this.peutGerer = true});

  final AvoirsRepository depot;

  /// `manage-ventes` du rôle de la session.
  final bool peutGerer;

  /// Le refus du `authorize()` du web, traduit (`lang/fr.json`).
  static const refusDroit = 'Votre rôle ne permet pas cette action.';

  /// Sous le statut d'une demande pas encore reçue par le serveur.
  static const nonEnvoye = 'Non envoyé';

  @override
  State<RetoursAvoirsOnglet> createState() => _RetoursAvoirsOngletState();
}

class _RetoursAvoirsOngletState extends State<RetoursAvoirsOnglet> {
  DonneesAvoirs? _donnees;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;
    if (d == null) return const Center(child: CircularProgressIndicator());

    final large = AgriBreakpoints.large(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _entete(large),
          const SizedBox(height: AgriSpacing.md),
          _kpis(d.kpis),
          const SizedBox(height: AgriSpacing.md),
          _tableau(d),
        ],
      ),
    );
  }

  // ── 1. En-tête ─────────────────────────────────────────────────────────────────────────────────────────────────────────

  Widget _entete(bool large) {
    const titre = TitreOnglet(
      icone: SymbolesAgri.assignment_return,
      titre: 'Retours et Avoirs',
      sousTitre: 'Gestion des retours produits, avoirs clients et inspection sanitaire du cheptel retourné.',
    );
    final bouton = BoutonEntete(
      key: const Key('nouveau-retour'),
      icone: SymbolesAgri.add_circle,
      libelle: 'Nouveau Retour',
      onPressed: _nouveauRetour,
    );

    // `flex-col lg:flex-row lg:items-center lg:justify-between gap-sm`.
    return EnteteOnglet(
      enfant: large
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [const Flexible(child: titre), bouton],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titre, const SizedBox(height: AgriSpacing.sm), bouton],
            ),
    );
  }

  // ── 2. Cartes ──────────────────────────────────────────────────────────────────────────────────────────────────────────

  Widget _kpis(KpisAvoirs k) => GrilleKpiAdaptative(
    cartes: [
      CarteKpi(
        key: const Key('kpi-Retours du mois'),
        libelle: 'Retours du mois',
        valeur: '${k.retoursDuMois}',
        couleurLisere: AgriColors.infoBlue,
        icone: SymbolesAgri.assignment_return,
        couleurIcone: AgriColors.infoBlue,
      ),
      CarteKpi(
        key: const Key('kpi-Montant Avoirs'),
        libelle: 'Montant Avoirs',
        valeur: AvoirsRepository.montantFr(k.montantAvoirs),
        unite: 'FCFA',
        couleurLisere: AgriColors.accentYellow,
        icone: SymbolesAgri.payments,
        couleurIcone: AgriColors.brandForest,
      ),
      CarteKpi(
        key: const Key('kpi-Produits Retournés'),
        libelle: 'Produits Retournés',
        valeur: '${k.produitsRetournes}',
        couleurLisere: AgriColors.brandEmerald,
        icone: SymbolesAgri.inventory_2,
        couleurIcone: AgriColors.brandEmerald,
      ),
      CarteKpi(
        key: const Key('kpi-Taux de Retour'),
        libelle: 'Taux de Retour',
        // `number_format($taux, 1, ',', ' ').'%'`.
        valeur: '${k.tauxRetour.toStringAsFixed(1).replaceAll('.', ',')}%',
        couleurLisere: AgriColors.errorRed,
        icone: SymbolesAgri.percent,
        couleurIcone: AgriColors.errorRed,
      ),
    ],
  );

  // ── 3. Tableau ─────────────────────────────────────────────────────────────────────────────────────────────────────────

  static const _colonnes = [
    ColonneTableau('Avoir', 2),
    ColonneTableau('Facture', 2),
    ColonneTableau('Client', 3),
    ColonneTableau('Date', 2),
    ColonneTableau('Motif', 3),
    ColonneTableau('Décision', 3),
    ColonneTableau('Montant', 2, droite: true),
    ColonneTableau('Statut', 3),
    ColonneTableau('Actions', 2, droite: true),
  ];

  Widget _tableau(DonneesAvoirs d) => TableauAgri(
    colonnes: _colonnes,
    largeur: 1260,
    clePrefixe: 'avoir',
    videTexte: 'Aucun retour pour le moment.',
    lignes: [for (final l in d.lignes) _cellules(l)],
  );

  List<Widget> _cellules(LigneAvoir l) {
    final a = l.avoir;
    return [
      Text(
        l.numero,
        style: styleCellule.copyWith(fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
      ),
      Text(l.facture, style: styleCellule.copyWith(fontFamily: 'monospace')),
      Text(l.client, style: styleCellule, overflow: TextOverflow.ellipsis),
      // `$note->created_at->format('d/m/Y')`.
      Text(_jour(a.createdAt), style: styleCellule),
      Text(a.reason ?? '', style: styleCellule),
      _decision(a.decision),
      Text(
        AvoirsRepository.montantFr(a.amount),
        style: styleCellule.copyWith(fontWeight: AgriTypography.gras),
      ),
      _statut(l),
      a.status == 'en_attente'
          ? boutonIconeTableau(
              cle: Key('avoir-traite-${a.id}'),
              infobulle: 'Marquer comme traité',
              icone: SymbolesAgri.check_circle,
              couleur: AgriColors.brandEmerald,
              onPressed: () => _marquerTraite(a.id),
            )
          : const SizedBox.shrink(),
    ];
  }

  Widget _decision(String? decision) {
    if (decision == 'reintegre') {
      return const _DecisionAvoir(SymbolesAgri.restart_alt, 'Réintégré', AgriColors.brandEmerald);
    }
    if (decision == 'reforme') {
      return const _DecisionAvoir(SymbolesAgri.heart_broken, 'Réforme', AgriColors.errorDeep);
    }
    return const Text('—', style: styleCellule);
  }

  Widget _statut(LigneAvoir l) {
    final pastille = l.avoir.status == 'traite'
        ? const PastilleStatut.succes('Traité')
        : const PastilleStatut.attente('En attente');
    // ⚠️ ÉCART ASSUMÉ (hors ligne) : le web n'a pas cette ligne. Une demande saisie ici n'existe pas encore côté ferme.
    final precision = l.refusee
        ? 'Refusé par le serveur : ${l.motifRefus ?? 'motif non communiqué'}'
        : (l.enAttenteDEnvoi ? RetoursAvoirsOnglet.nonEnvoye : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        pastille,
        if (precision != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              precision,
              key: Key('avoir-envoi-${l.avoir.id}'),
              style: TextStyle(
                fontSize: 10,
                color: l.refusee ? AgriColors.errorDeep : AgriColors.outline,
              ),
            ),
          ),
      ],
    );
  }

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ── Actions ────────────────────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> _marquerTraite(String id) async {
    if (!widget.peutGerer) {
      ToastAgri.afficher(context, RetoursAvoirsOnglet.refusDroit, type: TypeToast.erreur);
      return;
    }
    await widget.depot.marquerTraite(id);
    if (!mounted) return;
    ToastAgri.afficher(context, AvoirsRepository.toastTraite);
    await _charger();
  }

  Future<void> _nouveauRetour() async {
    final sortie = await afficherModale<_SortieRetour>(
      context: context,
      constructeur: (_) => _ModaleNouveauRetour(depot: widget.depot, peutGerer: widget.peutGerer),
    );
    if (sortie == null || !mounted) return;

    switch (sortie) {
      case _RetourEnregistre(:final avoir):
        ToastAgri.afficher(
          context,
          AvoirsRepository.toastDemande(avoir.decision ?? 'reintegre', montantNul: avoir.amount <= 0),
          duree: const Duration(seconds: 6),
        );
      case _RetourRefuse(:final motif):
        ToastAgri.afficher(context, 'Retour refusé : $motif', type: TypeToast.erreur, duree: const Duration(seconds: 6));
      case _RetourSansDroit():
        ToastAgri.afficher(context, RetoursAvoirsOnglet.refusDroit, type: TypeToast.erreur);
    }
    await _charger();
  }
}

/// `inline-flex items-center gap-1 font-bold` : icône 14 px + libellé, dans la couleur de la décision.
class _DecisionAvoir extends StatelessWidget {
  const _DecisionAvoir(this.icone, this.libelle, this.couleur);

  final IconData icone;
  final String libelle;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icone, size: 14, color: couleur),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          libelle,
          overflow: TextOverflow.ellipsis,
          style: styleCellule.copyWith(fontWeight: AgriTypography.gras, color: couleur),
        ),
      ),
    ],
  );
}

sealed class _SortieRetour {
  const _SortieRetour();
}

class _RetourEnregistre extends _SortieRetour {
  const _RetourEnregistre(this.avoir);

  final AvoirClient avoir;
}

class _RetourRefuse extends _SortieRetour {
  const _RetourRefuse(this.motif);

  final String motif;
}

class _RetourSansDroit extends _SortieRetour {
  const _RetourSansDroit();
}

/// `<x-modal name="modal-nouveau-retour" max-width="md">` : le formulaire « Nouveau Retour ».
class _ModaleNouveauRetour extends StatefulWidget {
  const _ModaleNouveauRetour({required this.depot, required this.peutGerer});

  final AvoirsRepository depot;
  final bool peutGerer;

  @override
  State<_ModaleNouveauRetour> createState() => _ModaleNouveauRetourState();
}

class _ModaleNouveauRetourState extends State<_ModaleNouveauRetour> {
  List<VenteRetournable> _ventes = const [];
  List<ArticleRetournable> _articles = const [];

  String _venteId = '';
  String _produitId = '';
  String _decision = 'reintegre';
  final _quantite = TextEditingController();
  final _montant = TextEditingController();
  final _motif = TextEditingController();
  final _notes = TextEditingController();

  Map<String, String> _erreurs = {};

  @override
  void initState() {
    super.initState();
    _chargerVentes();
  }

  @override
  void dispose() {
    _quantite.dispose();
    _montant.dispose();
    _motif.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _chargerVentes() async {
    final ventes = await widget.depot.ventesRecentes();
    if (!mounted) return;
    setState(() => _ventes = ventes);
  }

  /// `updatedSaleId()` : le produit, la quantité et le montant repartent à zéro.
  Future<void> _choisirVente(String id) async {
    final articles = id.isEmpty ? <ArticleRetournable>[] : await widget.depot.articlesDe(id);
    if (!mounted) return;
    setState(() {
      _venteId = id;
      _articles = articles;
      _produitId = '';
      _quantite.clear();
      _montant.clear();
    });
  }

  /// `updatedProductId()` : quantité et montant pré-remplis avec la PREMIÈRE ligne de ce produit (retour total).
  void _choisirProduit(String id) {
    setState(() {
      _produitId = id;
      final ligne = _articles.where((a) => a.produitId == id).firstOrNull;
      if (ligne != null) {
        _quantite.text = _nombre(ligne.quantite);
        _montant.text = _nombre(ligne.montant);
      }
    });
  }

  static String _nombre(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static double? _lire(String texte) {
    final net = texte.trim().replaceAll(' ', '').replaceAll(',', '.');
    return net.isEmpty ? null : double.tryParse(net);
  }

  Future<void> _valider() async {
    if (!widget.peutGerer) {
      Navigator.of(context).pop<_SortieRetour>(const _RetourSansDroit());
      return;
    }
    final resultat = await widget.depot.enregistrer(
      venteId: _venteId,
      produitId: _produitId,
      quantite: _lire(_quantite.text),
      montant: _lire(_montant.text),
      motif: _motif.text,
      decision: _decision,
      notes: _notes.text,
    );
    if (!mounted) return;
    if (resultat.refus != null) {
      Navigator.of(context).pop<_SortieRetour>(_RetourRefuse(resultat.refus!));
    } else if (resultat.avoir != null) {
      Navigator.of(context).pop<_SortieRetour>(_RetourEnregistre(resultat.avoir!));
    } else {
      setState(() => _erreurs = resultat.erreurs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vente = _venteId.isEmpty ? null : _ventes.where((v) => v.vente.id == _venteId).firstOrNull;

    return ModaleAgri(
      titre: 'Nouveau Retour',
      largeur: LargeurModale.md,
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(
            '1. Facture Source',
            'saleId',
            ListeAgri(
              cle: const Key('retour-vente'),
              valeur: _venteId,
              invalide: _erreurs.containsKey('saleId'),
              options: [
                const ('', '-- Sélectionner une vente --'),
                for (final v in _ventes)
                  (
                    v.vente.id,
                    '${v.reference} — ${v.client} — ${AvoirsRepository.montantFr(v.vente.total)} FCFA',
                  ),
              ],
              onChanged: _choisirVente,
            ),
          ),
          // `@if($this->selectedSale)` : les quatre autres sections n'apparaissent qu'avec une vente choisie.
          if (vente != null) ...[
            _section(
              '2. Article Retourné',
              'productId',
              ListeAgri(
                cle: const Key('retour-produit'),
                valeur: _produitId,
                invalide: _erreurs.containsKey('productId'),
                options: [
                  const ('', '-- Sélectionner --'),
                  for (final a in _articles)
                    (a.produitId, '${a.nom} (${AvoirsRepository.quantiteFr(a.quantite)} ${a.unite})'),
                ],
                onChanged: _choisirProduit,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _champ(
                    'Quantité Retournée *',
                    'qty',
                    ChampSaisieAgri(
                      cle: const Key('retour-quantite'),
                      controleur: _quantite,
                      invalide: _erreurs.containsKey('qty'),
                      numerique: true,
                    ),
                  ),
                ),
                const SizedBox(width: AgriSpacing.sm),
                Expanded(
                  child: _champ(
                    "Montant de l'Avoir (FCFA) *",
                    'amount',
                    ChampSaisieAgri(
                      cle: const Key('retour-montant'),
                      controleur: _montant,
                      invalide: _erreurs.containsKey('amount'),
                      numerique: true,
                      gras: true,
                    ),
                  ),
                ),
              ],
            ),
            _section(
              '3. Motif du Retour',
              'reason',
              ChampSaisieAgri(
                cle: const Key('retour-motif'),
                controleur: _motif,
                invalide: _erreurs.containsKey('reason'),
                indice: 'ex : Produit détérioré, erreur de quantité, mortalité...',
              ),
            ),
            _section(
              '4. Inspection Sanitaire (si sujet vivant)',
              null,
              ChampSaisieAgri(
                cle: const Key('retour-notes'),
                controleur: _notes,
                indice: 'ex : Contrôle visuel effectué, RAS',
                lignes: 2,
              ),
            ),
            _decisionSection(),
          ],
        ],
      ),
      actions: [
        BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
        BoutonModalePrimaire(key: const Key('retour-enregistrer'), libelle: 'Enregistrer le Retour', onPressed: _valider),
      ],
    );
  }

  /// `<p class="text-[10px] text-brand-forest font-bold uppercase mb-xs">` + champ + `.invalid-feedback`.
  Widget _section(String titre, String? cleErreur, Widget champ) =>
      _bloc(titre, cleErreur, champ);

  Widget _champ(String libelle, String cleErreur, Widget champ) => _bloc(libelle, cleErreur, champ);

  Widget _bloc(String libelle, String? cleErreur, Widget champ) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
          child: Text(
            libelle.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
        ),
        champ,
        if (cleErreur != null && _erreurs[cleErreur] != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _erreurs[cleErreur]!,
              key: Key('retour-erreur-$cleErreur'),
              style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
            ),
          ),
      ],
    ),
  );

  Widget _decisionSection() => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: AgriSpacing.xs),
          child: Text(
            '5. DÉCISION',
            style: TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
          ),
        ),
        RadioGroup<String>(
          groupValue: _decision,
          onChanged: (v) => setState(() => _decision = v ?? _decision),
          child: Wrap(
            spacing: AgriSpacing.md,
            children: [
              _radio('reintegre', SymbolesAgri.restart_alt, AgriColors.brandEmerald, 'Réintégrer au stock'),
              _radio('reforme', SymbolesAgri.heart_broken, AgriColors.errorDeep, 'Réformer (détruire)'),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: AgriSpacing.xs),
          child: Text(
            "Réintégrer ajoute réellement la quantité au stock du produit. Réformer n'a aucun impact sur le stock (traçabilité seule).",
            style: TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
        ),
      ],
    ),
  );

  Widget _radio(String valeur, IconData icone, Color couleur, String libelle) => InkWell(
    key: Key('retour-decision-$valeur'),
    onTap: () => setState(() => _decision = valeur),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(value: valeur, activeColor: couleur, visualDensity: VisualDensity.compact),
        Icon(icone, size: 16, color: couleur),
        const SizedBox(width: 4),
        Text(libelle, style: const TextStyle(fontSize: AgriTypography.sm)),
      ],
    ),
  );
}

/// `<select class="w-full h-11 px-md border rounded-lg text-sm bg-white">` (`is-invalid` : bord `#BA1A1A`, fond `#FFF5F5`).
class ListeAgri extends StatelessWidget {
  const ListeAgri({
    super.key,
    required this.cle,
    required this.valeur,
    required this.options,
    required this.onChanged,
    this.invalide = false,
    this.cleListe,
  });

  final Key cle;
  final Key? cleListe;
  final String valeur;

  /// (valeur, libellé) ; la première option, de valeur vide, est l'invite « -- Sélectionner -- ».
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  final bool invalide;

  @override
  Widget build(BuildContext context) => Container(
    key: cle,
    height: AgriChamps.hauteurFormulaire,
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
    decoration: BoxDecoration(
      color: invalide ? const Color(0xFFFFF5F5) : AgriColors.surfaceCard,
      border: Border.all(color: invalide ? AgriColors.errorDeep : AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        key: cleListe,
        value: options.any((o) => o.$1 == valeur) ? valeur : '',
        isExpanded: true,
        style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
        items: [
          for (final (v, libelle) in options)
            DropdownMenuItem(value: v, child: Text(libelle, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => onChanged(v ?? ''),
      ),
    ),
  );
}

/// `<input class="w-full h-11 px-md border rounded-lg text-sm">` — [lignes] > 1 : le `<textarea rows="2" px-md py-sm>`.
class ChampSaisieAgri extends StatelessWidget {
  const ChampSaisieAgri({
    super.key,
    required this.cle,
    required this.controleur,
    this.invalide = false,
    this.indice,
    this.numerique = false,
    this.gras = false,
    this.lignes = 1,
  });

  final Key cle;
  final TextEditingController controleur;
  final bool invalide;
  final String? indice;
  final bool numerique;
  final bool gras;
  final int lignes;

  @override
  Widget build(BuildContext context) {
    final bord = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      borderSide: BorderSide(color: invalide ? AgriColors.errorDeep : AgriColors.outlineVariant),
    );
    final champ = TextField(
      key: cle,
      controller: controleur,
      keyboardType: numerique ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      minLines: lignes,
      maxLines: lignes,
      style: TextStyle(
        fontSize: AgriTypography.sm,
        fontWeight: gras ? AgriTypography.gras : AgriTypography.normal,
        color: AgriColors.onSurface,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: invalide ? const Color(0xFFFFF5F5) : AgriColors.surfaceCard,
        hintText: indice,
        hintStyle: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.outline),
        contentPadding: EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: lignes > 1 ? AgriSpacing.sm : 12),
        border: bord,
        enabledBorder: bord,
        focusedBorder: bord,
      ),
    );
    return lignes > 1 ? champ : SizedBox(height: AgriChamps.hauteurFormulaire, child: champ);
  }
}
