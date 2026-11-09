import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../../core/database/app_database.dart' show ChartOfAccount, FixedAsset;
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/champs_date_agri.dart';
import '../../core/widgets/modale_agri.dart';
import 'documents_comptabilite.dart';
import 'immobilisations_repository.dart';

/// Ticket CP-3 — `Livewire\Comptabilite\Immobilisations` (route `/immobilisations`, carte « Immobilisations » du hub web).
///
/// Même structure que le Blade : en-tête, filtres (date d'arrêté, nature, statut), quatre cartes, mention « hors comptabilité »,
/// bandeau « Dotation aux amortissements en attente », ventilation par nature, registre détaillé à onze colonnes, modales
/// « Nouvelle Immobilisation » / « Modifier l'Immobilisation » et « Sortie d'Immobilisation ».
///
/// ⚠️ Le poste ne calcule aucune écriture : « Passer la Dotation » écrit une DEMANDE, le serveur recalcule l'écart contre le
/// grand livre. Les montants affichés sont ceux de `CalculAmortissement`, transposition du modèle web prouvée par une
/// parité exécutée.
class ImmobilisationsPage extends StatefulWidget {
  const ImmobilisationsPage({
    super.key,
    required this.depot,
    required this.maintenant,
    this.peutEcrire = true,
  });

  final ImmobilisationsRepository depot;
  final DateTime Function() maintenant;

  /// `manage-comptabilite` : sans lui, ni « Nouvelle Immobilisation », ni modifier, ni sortie, ni dotation (le Blade les masque).
  final bool peutEcrire;

  @override
  State<ImmobilisationsPage> createState() => _ImmobilisationsPageState();
}

class _ImmobilisationsPageState extends State<ImmobilisationsPage> {
  DonneesImmobilisations? _donnees;
  late DateTime _arrete = _jourSeul(widget.maintenant());
  String _filtreNature = 'tous';
  String _filtreStatut = 'en_service';
  String? _message;

  static DateTime _jourSeul(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final d = await widget.depot.charger();
    if (mounted) setState(() => _donnees = d);
  }

  static String _montant(double v) => DocumentsComptabilite.montant(v);

  @override
  Widget build(BuildContext context) {
    final d = _donnees;
    if (d == null) return const Padding(padding: EdgeInsets.all(AgriSpacing.lg), child: Center(child: CircularProgressIndicator()));

    final large = AgriBreakpoints.large(context);
    final kpis = ImmobilisationsRepository.kpis(d, _arrete);
    final ventilation = ImmobilisationsRepository.ventilation(d, _arrete);
    final biens = [
      for (final b in d.biens)
        if ((_filtreNature == 'tous' || b.accountCode == _filtreNature) && (_filtreStatut == 'tous' || b.status == _filtreStatut)) b,
    ];
    final aDoter = kpis.aDoter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _enTete(large),
        const SizedBox(height: AgriSpacing.md),
        if (_message != null) ...[
          Container(
            key: const Key('immo-message'),
            padding: const EdgeInsets.all(AgriSpacing.sm),
            decoration: BoxDecoration(
              color: AgriColors.brandEmerald.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
              border: Border.all(color: AgriColors.brandEmerald.withValues(alpha: 0.30)),
            ),
            child: Text(_message!, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.brandForest)),
          ),
          const SizedBox(height: AgriSpacing.md),
        ],
        _filtres(d),
        const SizedBox(height: AgriSpacing.md),
        GrilleKpi(
          colonnes: large ? 4 : 2,
          children: [
            CarteKpi(
              key: const Key('kpi-immo-brut'),
              libelle: 'Valeur Brute',
              valeur: '${_montant(kpis.brut)} F',
              couleurLisere: AgriColors.brandEmerald,
            ),
            CarteKpi(
              key: const Key('kpi-immo-amortissement'),
              libelle: 'Amortissements Cumulés',
              valeur: '−${_montant(kpis.amortissement)} F',
              couleurLisere: AgriColors.errorRed,
              couleurValeur: AgriColors.errorDeep,
            ),
            CarteKpi(
              key: const Key('kpi-immo-net'),
              libelle: 'Valeur Nette Comptable',
              valeur: '${_montant(kpis.net)} F',
              couleurLisere: AgriColors.brandForest,
              couleurValeur: AgriColors.brandForest,
            ),
            // ⚠️ Un tiret quand le poste ne connaît pas le solde de 281 (aucune écriture reçue) : jamais « 0 F ».
            CarteKpi(
              key: const Key('kpi-immo-a-doter'),
              libelle: 'Dotation à Comptabiliser',
              valeur: aDoter == null ? '—' : '${_montant(aDoter)} F',
              legende: aDoter == null ? 'Écritures non reçues : le poste ne connaît pas encore le solde de 281.' : null,
              couleurLisere: aDoter != null && aDoter > 0 ? AgriColors.accentYellow : AgriColors.outlineVariant,
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        if (kpis.horsCompta > 0) ...[_horsCompta(kpis.horsCompta), const SizedBox(height: AgriSpacing.md)],
        if (widget.peutEcrire && aDoter != null && aDoter > 0) ...[_bandeauDotation(d, aDoter), const SizedBox(height: AgriSpacing.md)],
        if (ventilation.isNotEmpty) ...[_ventilation(ventilation, kpis), const SizedBox(height: AgriSpacing.md)],
        _registre(d, biens),
      ],
    );
  }

  Widget _enTete(bool large) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(SymbolesAgri.domain, size: 26, color: AgriColors.brandEmerald),
                const SizedBox(width: AgriSpacing.xs),
                Text(
                  'Immobilisations',
                  style: TextStyle(
                    fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.xs),
            const Text(
              'Registre des biens durables, amortissement linéaire et dotation comptable — source de la Note 2 des États Financiers.',
              style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
          ],
        ),
      ),
      if (widget.peutEcrire) ...[
        const SizedBox(width: AgriSpacing.sm),
        ElevatedButton.icon(
          key: const Key('immo-nouvelle'),
          onPressed: () => _ouvrirBien(null),
          icon: const Icon(SymbolesAgri.add, size: 18),
          style: ElevatedButton.styleFrom(backgroundColor: AgriColors.brandEmerald, foregroundColor: Colors.white, shape: const StadiumBorder()),
          label: const Text('Nouvelle Immobilisation', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
        ),
      ],
    ],
  );

  Widget _etiquette(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
    child: Text(texte.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
  );

  Widget _liste(Key cle, String valeur, List<(String, String)> options, ValueChanged<String> onChanged) => SizedBox(
    width: 240,
    child: DropdownButtonFormField<String>(
      key: cle,
      initialValue: valeur,
      isDense: true,
      isExpanded: true,
      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
      style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.onSurface),
      items: [for (final (v, l) in options) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
      onChanged: (v) => setState(() => onChanged(v ?? valeur)),
    ),
  );

  Widget _filtres(DonneesImmobilisations d) => Container(
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Wrap(
      spacing: AgriSpacing.md,
      runSpacing: AgriSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: 200,
          child: ChampDateFormulaire(
            cle: const Key('immo-date-arrete'),
            etiquette: "Date d'arrêté",
            valeur: _arrete,
            onTap: () async {
              final choisie = await showDatePicker(
                context: context,
                initialDate: _arrete,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (choisie != null) setState(() => _arrete = choisie);
            },
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _etiquette('Nature'),
            _liste(
              const Key('immo-filtre-nature'),
              _filtreNature,
              [('tous', 'Toutes les natures'), for (final n in d.natures) (n.code, '${n.code} — ${n.label}')],
              (v) => _filtreNature = v,
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _etiquette('Statut'),
            _liste(
              const Key('immo-filtre-statut'),
              _filtreStatut,
              const [('en_service', 'En service'), ('cede', 'Cédées'), ('reforme', 'Réformées'), ('tous', 'Tous statuts')],
              (v) => _filtreStatut = v,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _horsCompta(double montant) => Container(
    key: const Key('immo-hors-compta'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(SymbolesAgri.info, size: 20, color: AgriColors.outline),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_montant(montant)} FCFA hors comptabilité', style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
              const SizedBox(height: AgriSpacing.xs),
              const Text(
                "Des biens saisis en reprise d'antériorité figurent à ce registre sans écriture de classe 2 : ils n'apparaissent donc pas à l'Actif Immobilisé du Bilan et ne sont pas amortis au grand livre. Leur valeur relève d'un bilan d'ouverture que l'application n'importe pas encore.",
                style: TextStyle(fontSize: 11, color: AgriColors.outline),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _bandeauDotation(DonneesImmobilisations d, double aDoter) {
    final enAttente = d.dotations.where((x) => !x.refusee).firstOrNull;
    final refusee = d.dotations.where((x) => x.refusee).firstOrNull;

    return Container(
      key: const Key('immo-bandeau-dotation'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.accentYellow.withValues(alpha: 0.10),
        border: Border.all(color: AgriColors.accentYellow.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(SymbolesAgri.calculate, size: 20, color: AgriColors.brandForest),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dotation aux amortissements en attente', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
                const SizedBox(height: AgriSpacing.xs),
                Text(
                  "${_montant(aDoter)} FCFA d'amortissement calculé au ${DocumentsComptabilite.jour(_arrete)} ne sont pas encore comptabilisés. L'écriture débitera 681 et créditera 281.",
                  style: const TextStyle(fontSize: 11, color: AgriColors.outline),
                ),
                if (enAttente != null)
                  const Padding(
                    padding: EdgeInsets.only(top: AgriSpacing.xs),
                    child: Text(
                      'Demande envoyée au serveur : elle sera comptabilisée à la prochaine synchronisation.',
                      key: Key('immo-dotation-demandee'),
                      style: TextStyle(fontSize: 11, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
                    ),
                  ),
                if (refusee != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AgriSpacing.xs),
                    child: Text(
                      'Demande refusée par le serveur : ${refusee.motifRefus ?? 'motif non communiqué'}',
                      key: const Key('immo-dotation-refusee'),
                      style: const TextStyle(fontSize: 11, fontWeight: AgriTypography.gras, color: AgriColors.errorDeep),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          ElevatedButton.icon(
            key: const Key('immo-passer-dotation'),
            onPressed: enAttente != null ? null : _passerDotation,
            icon: const Icon(SymbolesAgri.post_add, size: 18),
            style: ElevatedButton.styleFrom(backgroundColor: AgriColors.brandForest, foregroundColor: Colors.white, shape: const StadiumBorder()),
            label: const Text('Passer la Dotation', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _passerDotation() async {
    try {
      await widget.depot.passerDotation(_arrete);
      _message = 'Dotation demandée au serveur : elle sera comptabilisée (débit 681 / crédit 281) à la prochaine synchronisation.';
    } on SaisieImmobilisationRefusee catch (e) {
      _message = e.toString();
    }
    await _charger();
  }

  static const _entete = TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.outline);
  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  Widget _carte(Widget titre, Widget corps) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AgriColors.surfaceZebra,
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
          child: titre,
        ),
        corps,
      ],
    ),
  );

  Widget _table(double largeur, List<(String, int, TextAlign)> colonnes, List<Widget> lignes, {Widget? pied}) => LayoutBuilder(
    builder: (_, c) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: max(largeur, c.maxWidth),
        child: Column(
          children: [
            Container(
              color: AgriColors.surfaceZebra,
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
              child: Row(
                children: [
                  for (final (l, f, a) in colonnes) Expanded(flex: f, child: Text(l.toUpperCase(), textAlign: a, style: _entete)),
                ],
              ),
            ),
            ...lignes,
            ?pied,
          ],
        ),
      ),
    ),
  );

  Widget _ligne(int i, List<(Widget, int)> cellules, {Key? cle}) => Container(
    key: cle,
    color: i.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [for (final (w, f) in cellules) Expanded(flex: f, child: w)]),
  );

  Widget _ventilation(List<LigneVentilation> lignes, KpisImmobilisations kpis) => _carte(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Ventilation par Nature d'Actif", style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
        Text(
          'Alimente la Note 2 des États Financiers — au ${DocumentsComptabilite.jour(_arrete)}, biens en service uniquement.',
          style: const TextStyle(fontSize: 11, color: AgriColors.outline),
        ),
      ],
    ),
    _table(
      700,
      const [
        ('Compte', 2, TextAlign.left),
        ('Nature', 4, TextAlign.left),
        ('Nb', 1, TextAlign.right),
        ('Valeur Brute', 3, TextAlign.right),
        ('Amortissement', 3, TextAlign.right),
        ('Valeur Nette', 3, TextAlign.right),
      ],
      [
        for (var i = 0; i < lignes.length; i++)
          _ligne(i, [
            (Text(lignes[i].code, style: _cellule.copyWith(fontFamily: 'monospace', fontWeight: AgriTypography.gras)), 2),
            (Text(lignes[i].libelle, style: _cellule), 4),
            (Text('${lignes[i].nombre}', textAlign: TextAlign.right, style: _cellule), 1),
            (Text(_montant(lignes[i].brut), textAlign: TextAlign.right, style: _cellule), 3),
            (
              Text(
                lignes[i].amortissement > 0 ? '−${_montant(lignes[i].amortissement)}' : '—',
                textAlign: TextAlign.right,
                style: _cellule.copyWith(color: AgriColors.errorDeep),
              ),
              3,
            ),
            (Text(_montant(lignes[i].net), textAlign: TextAlign.right, style: _cellule.copyWith(fontWeight: AgriTypography.gras, color: AgriColors.brandForest)), 3),
          ], cle: Key('immo-ventilation-$i')),
      ],
      pied: Container(
        key: const Key('immo-ventilation-total'),
        color: AgriColors.brandForest,
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
        child: Row(
          children: [
            const Expanded(flex: 7, child: Text('TOTAL IMMOBILISATIONS', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: Colors.white))),
            Expanded(flex: 3, child: Text(_montant(kpis.brut), textAlign: TextAlign.right, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: Colors.white))),
            Expanded(flex: 3, child: Text('−${_montant(kpis.amortissement)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: Colors.white))),
            Expanded(flex: 3, child: Text(_montant(kpis.net), textAlign: TextAlign.right, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: Colors.white))),
          ],
        ),
      ),
    ),
  );

  Widget _statut(FixedAsset b) {
    final (texte, fond, couleur) = switch (b.status) {
      'en_service' => ('En service', AgriColors.brandEmerald, AgriColors.brandEmerald),
      'cede' => ('Cédée ${b.disposalDate == null ? '' : DocumentsComptabilite.jour(b.disposalDate!)}'.trim(), AgriColors.outline, AgriColors.outline),
      _ => ('Réformée ${b.disposalDate == null ? '' : DocumentsComptabilite.jour(b.disposalDate!)}'.trim(), AgriColors.errorRed, AgriColors.errorDeep),
    };
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
        decoration: BoxDecoration(color: fond.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)),
        child: Text(texte, style: TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: couleur)),
      ),
    );
  }

  Widget _registre(DonneesImmobilisations d, List<FixedAsset> biens) => _carte(
    const Text('Registre Détaillé', style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
    _table(
      1180,
      const [
        ('Code', 2, TextAlign.left),
        ('Désignation', 4, TextAlign.left),
        ('Acquisition', 2, TextAlign.left),
        ('Valeur Brute', 3, TextAlign.right),
        ('Durée', 2, TextAlign.center),
        ('Annuité', 3, TextAlign.right),
        ('Cumul Amort.', 3, TextAlign.right),
        ('V.N.C.', 3, TextAlign.right),
        ('Comptabilisé', 2, TextAlign.center),
        ('Statut', 3, TextAlign.center),
        ('Actions', 2, TextAlign.right),
      ],
      [
        if (biens.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AgriSpacing.lg),
            child: Center(child: Text('Aucune immobilisation enregistrée pour ce filtre.', style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline))),
          ),
        for (var i = 0; i < biens.length; i++) _ligneBien(d, i, biens[i]),
      ],
    ),
  );

  Widget _ligneBien(DonneesImmobilisations d, int i, FixedAsset b) {
    final amorti = CalculAmortissement.totalementAmorti(b, _arrete);
    final refus = d.refus['fixed_assets:${b.id}'];
    final attente = b.syncStatus.name != 'synced';

    return _ligne(
      i,
      [
        (Text(b.code, style: _cellule.copyWith(fontFamily: 'monospace', fontWeight: AgriTypography.gras)), 2),
        (
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.label, style: _cellule.copyWith(fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
              Text('Compte ${b.accountCode}', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AgriColors.outline)),
              if (attente)
                Text(
                  refus == null ? 'En attente de synchronisation' : 'Refusé : $refus',
                  key: Key('immo-attente-${b.id}'),
                  style: TextStyle(fontSize: 10, color: refus == null ? AgriColors.outline : AgriColors.errorDeep),
                ),
            ],
          ),
          4,
        ),
        (Text(DocumentsComptabilite.jour(b.acquisitionDate), style: _cellule), 2),
        (Text(_montant(b.acquisitionValue), textAlign: TextAlign.right, style: _cellule), 3),
        (Text('${b.durationYears} ans', textAlign: TextAlign.center, style: _cellule), 2),
        (Text(_montant(CalculAmortissement.annuite(b)), textAlign: TextAlign.right, style: _cellule), 3),
        (
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_montant(CalculAmortissement.cumul(b, _arrete)), style: _cellule.copyWith(color: AgriColors.errorDeep)),
              if (amorti) const Text('AMORTI', style: TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.outline)),
            ],
          ),
          3,
        ),
        (Text(_montant(CalculAmortissement.valeurNette(b, _arrete)), textAlign: TextAlign.right, style: _cellule.copyWith(fontWeight: AgriTypography.gras, color: AgriColors.brandForest)), 3),
        (
          Center(
            child: Tooltip(
              message: b.isCapitalized ? "Porté à l'actif" : "Reprise d'antériorité — hors comptabilité",
              child: Icon(
                b.isCapitalized ? SymbolesAgri.check_circle : SymbolesAgri.remove_circle_outline,
                size: 18,
                color: b.isCapitalized ? AgriColors.brandEmerald : AgriColors.outline,
              ),
            ),
          ),
          2,
        ),
        (_statut(b), 3),
        (
          widget.peutEcrire
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      key: Key('immo-modifier-${b.id}'),
                      tooltip: 'Modifier',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _ouvrirBien(b),
                      icon: const Icon(SymbolesAgri.edit, size: 18, color: AgriColors.brandEmerald),
                    ),
                    if (b.status == 'en_service')
                      IconButton(
                        key: Key('immo-sortie-${b.id}'),
                        tooltip: 'Cession / réforme',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _ouvrirSortie(b),
                        icon: const Icon(SymbolesAgri.logout, size: 18, color: AgriColors.outline),
                      ),
                  ],
                )
              : const Text('—', textAlign: TextAlign.right, style: TextStyle(color: AgriColors.outline)),
          2,
        ),
      ],
      cle: Key('immo-ligne-${b.id}'),
    );
  }

  Future<void> _ouvrirBien(FixedAsset? existant) async {
    final d = _donnees!;
    final ok = await afficherModale<bool>(
      context: context,
      constructeur: (_) => _ModaleBien(depot: widget.depot, donnees: d, existant: existant, aujourdhui: widget.maintenant()),
    );
    if (ok == true) {
      _message = existant == null ? 'Immobilisation enregistrée.' : 'Immobilisation modifiée.';
      await _charger();
    }
  }

  Future<void> _ouvrirSortie(FixedAsset bien) async {
    final ok = await afficherModale<bool>(
      context: context,
      constructeur: (_) => _ModaleSortie(depot: widget.depot, bien: bien, aujourdhui: widget.maintenant()),
    );
    if (ok == true) {
      _message = "Sortie enregistrée — le bien cesse de s'amortir à cette date.";
      await _charger();
    }
  }
}

Widget _champ(String etiquette, Widget champ, String? erreur, Key cleErreur, {String? aide}) => Padding(
  padding: const EdgeInsets.only(bottom: AgriSpacing.md),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
        child: Text(etiquette.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
      ),
      champ,
      if (aide != null)
        Padding(
          padding: const EdgeInsets.only(top: AgriSpacing.xs),
          child: Text(aide, style: const TextStyle(fontSize: 11, color: AgriColors.outline)),
        ),
      if (erreur != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(erreur, key: cleErreur, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
        ),
    ],
  ),
);

/// « Nouvelle Immobilisation » / « Modifier l'Immobilisation » (`showForm` du composant web).
class _ModaleBien extends StatefulWidget {
  const _ModaleBien({required this.depot, required this.donnees, required this.existant, required this.aujourdhui});

  final ImmobilisationsRepository depot;
  final DonneesImmobilisations donnees;
  final FixedAsset? existant;
  final DateTime aujourdhui;

  @override
  State<_ModaleBien> createState() => _ModaleBienState();
}

class _ModaleBienState extends State<_ModaleBien> {
  late final TextEditingController _code = TextEditingController(text: widget.existant?.code ?? '');
  late final TextEditingController _libelle = TextEditingController(text: widget.existant?.label ?? '');
  late final TextEditingController _valeur = TextEditingController(text: widget.existant == null ? '' : widget.existant!.acquisitionValue.round().toString());
  late final TextEditingController _residuelle = TextEditingController(text: widget.existant == null ? '0' : widget.existant!.residualValue.round().toString());
  late final TextEditingController _duree = TextEditingController(text: widget.existant?.durationYears.toString() ?? '');
  late String _nature = widget.existant?.accountCode ?? '';
  late DateTime? _date = widget.existant?.acquisitionDate ?? widget.aujourdhui;
  String _contrepartie = '';
  Map<String, String> _erreurs = const {};

  @override
  void dispose() {
    for (final c in [_code, _libelle, _valeur, _residuelle, _duree]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _enregistrer() async {
    try {
      if (widget.existant == null) {
        await widget.depot.creer(
          code: _code.text, libelle: _libelle.text, nature: _nature, dateAcquisition: _date,
          valeur: _valeur.text, residuelle: _residuelle.text, duree: _duree.text, contrepartie: _contrepartie,
        );
      } else {
        await widget.depot.modifier(
          widget.existant!.id,
          code: _code.text, libelle: _libelle.text, nature: _nature, dateAcquisition: _date,
          valeur: _valeur.text, residuelle: _residuelle.text, duree: _duree.text,
        );
      }
    } on SaisieImmobilisationRefusee catch (e) {
      setState(() => _erreurs = e.erreurs);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _texte(String cle, TextEditingController c, String indice, {bool nombre = false}) => TextField(
    key: Key(cle),
    controller: c,
    keyboardType: nombre ? TextInputType.number : null,
    decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: indice),
  );

  @override
  Widget build(BuildContext context) {
    final d = widget.donnees;

    return ModaleAgri(
      titre: widget.existant == null ? 'Nouvelle Immobilisation' : "Modifier l'Immobilisation",
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_erreurs['formulaire'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AgriSpacing.md),
              child: Text(_erreurs['formulaire']!, key: const Key('immo-erreur-formulaire'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
            ),
          _champ('Code *', _texte('immo-code', _code, 'IMM-001'), _erreurs['code'], const Key('immo-erreur-code')),
          _champ('Désignation *', _texte('immo-libelle', _libelle, 'Broyeur à provende'), _erreurs['label'], const Key('immo-erreur-label')),
          _champ(
            'Nature (compte de classe 2) *',
            DropdownButtonFormField<String>(
              key: const Key('immo-nature'),
              initialValue: _nature,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
              items: [
                const DropdownMenuItem(value: '', child: Text('— Choisir —')),
                for (final ChartOfAccount n in d.natures) DropdownMenuItem(value: n.code, child: Text('${n.code} — ${n.label}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _nature = v ?? ''),
            ),
            _erreurs['accountCode'],
            const Key('immo-erreur-accountCode'),
          ),
          ChampDateFormulaire(
            cle: const Key('immo-date-acquisition'),
            etiquette: "Date d'acquisition *",
            valeur: _date,
            erreur: _erreurs['acquisitionDate'],
            cleErreur: const Key('immo-erreur-acquisitionDate'),
            onTap: () async {
              final choisie = await showDatePicker(
                context: context,
                initialDate: _date ?? widget.aujourdhui,
                firstDate: DateTime(1990),
                lastDate: DateTime(2100),
              );
              if (choisie != null) setState(() => _date = choisie);
            },
          ),
          const SizedBox(height: AgriSpacing.md),
          _champ("Valeur d'acquisition (FCFA) *", _texte('immo-valeur', _valeur, '', nombre: true), _erreurs['acquisitionValue'], const Key('immo-erreur-acquisitionValue')),
          _champ('Valeur résiduelle (FCFA)', _texte('immo-residuelle', _residuelle, '', nombre: true), _erreurs['residualValue'], const Key('immo-erreur-residualValue')),
          _champ("Durée d'amortissement (ans) *", _texte('immo-duree', _duree, '', nombre: true), _erreurs['durationYears'], const Key('immo-erreur-durationYears')),
          // Le Blade ne propose la contrepartie qu'à la CRÉATION (@unless($editingId)).
          if (widget.existant == null)
            _champ(
              "Comptabilisation de l'acquisition",
              DropdownButtonFormField<String>(
                key: const Key('immo-contrepartie'),
                initialValue: _contrepartie,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
                items: [
                  const DropdownMenuItem(value: '', child: Text("Reprise d'antériorité — aucune écriture")),
                  for (final t in d.comptesTresorerie) DropdownMenuItem(value: t.id, child: Text('Payé par ${t.label} (${t.accountCode ?? '—'})', overflow: TextOverflow.ellipsis)),
                  const DropdownMenuItem(value: 'credit', child: Text('À crédit — dette fournisseur (401)')),
                ],
                onChanged: (v) => setState(() => _contrepartie = v ?? ''),
              ),
              _erreurs['contrepartie'],
              const Key('immo-erreur-contrepartie'),
              aide:
                  "Une acquisition comptabilisée débite le compte de classe 2 choisi et crédite la contrepartie. Sans écriture, le bien alimente ce registre mais reste absent du Bilan.",
            ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
        BoutonModalePrimaire(key: const Key('immo-enregistrer'), libelle: 'Enregistrer', onPressed: _enregistrer),
      ],
    );
  }
}

/// « Sortie d'Immobilisation » (`showCession` du composant web).
class _ModaleSortie extends StatefulWidget {
  const _ModaleSortie({required this.depot, required this.bien, required this.aujourdhui});

  final ImmobilisationsRepository depot;
  final FixedAsset bien;
  final DateTime aujourdhui;

  @override
  State<_ModaleSortie> createState() => _ModaleSortieState();
}

class _ModaleSortieState extends State<_ModaleSortie> {
  String _statut = 'cede';
  late DateTime? _date = widget.aujourdhui;
  final _motif = TextEditingController();
  Map<String, String> _erreurs = const {};

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  Future<void> _confirmer() async {
    try {
      await widget.depot.sortir(widget.bien.id, date: _date, statut: _statut, motif: _motif.text);
    } on SaisieImmobilisationRefusee catch (e) {
      setState(() => _erreurs = e.erreurs);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => ModaleAgri(
    titre: "Sortie d'Immobilisation",
    contenu: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: AgriSpacing.md),
          child: Text(
            "Le bien n'est jamais supprimé : il change de statut et cesse de s'amortir à la date de sortie, son historique comptable restant consultable.",
            style: TextStyle(fontSize: 11, color: AgriColors.outline),
          ),
        ),
        if (_erreurs['formulaire'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AgriSpacing.md),
            child: Text(_erreurs['formulaire']!, key: const Key('sortie-erreur-formulaire'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
          ),
        _champ(
          'Type de sortie *',
          DropdownButtonFormField<String>(
            key: const Key('sortie-statut'),
            initialValue: _statut,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
            items: const [
              DropdownMenuItem(value: 'cede', child: Text('Cession (vente)')),
              DropdownMenuItem(value: 'reforme', child: Text('Réforme (mise au rebut)')),
            ],
            onChanged: (v) => setState(() => _statut = v ?? 'cede'),
          ),
          _erreurs['cessionStatus'],
          const Key('sortie-erreur-cessionStatus'),
        ),
        ChampDateFormulaire(
          cle: const Key('sortie-date'),
          etiquette: 'Date de sortie *',
          valeur: _date,
          erreur: _erreurs['cessionDate'],
          cleErreur: const Key('sortie-erreur-cessionDate'),
          onTap: () async {
            final choisie = await showDatePicker(
              context: context,
              initialDate: _date ?? widget.aujourdhui,
              firstDate: DateTime(1990),
              lastDate: DateTime(2100),
            );
            if (choisie != null) setState(() => _date = choisie);
          },
        ),
        const SizedBox(height: AgriSpacing.md),
        _champ(
          'Motif *',
          TextField(
            key: const Key('sortie-motif'),
            controller: _motif,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'Vendu à un éleveur voisin'),
          ),
          _erreurs['cessionReason'],
          const Key('sortie-erreur-cessionReason'),
        ),
      ],
    ),
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
      BoutonModalePrimaire(key: const Key('sortie-confirmer'), libelle: 'Confirmer la Sortie', onPressed: _confirmer, couleur: AgriColors.brandForest),
    ],
  );
}
