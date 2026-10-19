import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import 'transferts_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// Ticket 15.46 — ÉCRAN « TRANSFERTS ENTRE BANDES », portage de `transferts-bandes.blade.php`.
///
/// ⚠️ Absent du prototype : écran construit d'abord sur le web (Doctrine, article 0) et porté ici à
/// l'identique (mêmes sections, mêmes libellés, mêmes refus). Il fonctionne hors ligne : le transfert
/// part au serveur à la prochaine synchronisation, qui le rejoue avec ses propres contrôles.
class TransfertsBandesScreen extends StatefulWidget {
  const TransfertsBandesScreen({super.key, required this.depot});

  final TransfertsRepository depot;

  @override
  State<TransfertsBandesScreen> createState() => _TransfertsBandesScreenState();
}

class _TransfertsBandesScreenState extends State<TransfertsBandesScreen> {
  List<LivestockLot>? _bandes;
  List<LivestockTransfer> _transferts = const [];
  List<LivestockLot> _aRattacher = const [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final bandes = await widget.depot.bandes();
    final transferts = await widget.depot.transferts();
    final aRattacher = await widget.depot.bandesARattacher();
    if (!mounted) return;
    setState(() {
      _bandes = bandes;
      _transferts = transferts;
      _aRattacher = aRattacher;
    });
  }

  String _code(String id) =>
      _bandes?.where((b) => b.id == id).firstOrNull?.code ?? '—';

  static String _fr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _ouvrirFormulaire({LivestockLot? aRattacher}) async {
    final bandes = _bandes ?? const <LivestockLot>[];
    final enregistre = await afficherModale<bool>(
      context: context,
      constructeur: (_) => _FormulaireTransfert(
        depot: widget.depot,
        bandes: bandes,
        aRattacher: aRattacher,
      ),
    );
    if (enregistre == true) {
      await _charger();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AgriColors.brandEmerald,
          content: Text(
            aRattacher != null
                ? 'Bande rattachée à sa bande d\'origine : les sujets ne sont plus comptés deux fois.'
                : 'Transfert enregistré : les deux bandes sont recalculées.',
          ),
        ),
      );
    }
  }

  Future<void> _annuler(LivestockTransfer t) async {
    final confirme = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (ctx) => ModaleConfirmation(
        icone: SymbolesAgri.swap_horiz,
        couleurIcone: AgriColors.errorDeep,
        titre: 'Annuler ce transfert ?',
        message: 'Les deux bandes seront recalculées. Le transfert reste tracé.',
        actions: [
          BoutonModaleSecondaire(
            libelle: 'Retour',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          BoutonModalePrimaire(
            libelle: 'Annuler le transfert',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    try {
      await widget.depot.annuler(t.id);
      await _charger();
    } on TransfertRefuse catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AgriColors.errorDeep, content: Text(e.motif)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bandes = _bandes;
    if (bandes == null) {
      return const Scaffold(
        backgroundColor: AgriColors.surfaceBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final maintenant = DateTime.now();
    final duMois = _transferts.where(
      (t) =>
          t.isActive &&
          t.transferDate.year == maintenant.year &&
          t.transferDate.month == maintenant.month,
    );

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AgriSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(SymbolesAgri.swap_horiz, color: AgriColors.brandEmerald, size: 26),
                const SizedBox(width: AgriSpacing.xs),
                const Expanded(
                  child: Text(
                    'Transferts entre Bandes',
                    style: TextStyle(
                      fontSize: AgriTypography.xl,
                      fontWeight: FontWeight.w900,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ),
                FilledButton.icon(
                  key: const Key('transfert-nouveau'),
                  style: FilledButton.styleFrom(backgroundColor: AgriColors.brandEmerald),
                  onPressed: () => _ouvrirFormulaire(),
                  icon: const Icon(SymbolesAgri.add_circle, size: 18),
                  label: const Text('Nouveau Transfert'),
                ),
              ],
            ),
            const Text(
              "Sujets passés d'une bande à une autre le même jour : sortie de la bande source, entrée dans la bande cible, effectifs recalculés.",
              style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
            const SizedBox(height: AgriSpacing.lg),
            Wrap(
              spacing: AgriSpacing.md,
              runSpacing: AgriSpacing.md,
              children: [
                SizedBox(
                  width: 240,
                  child: CarteKpi(
                    libelle: 'Transferts du Mois',
                    valeur: '${duMois.length}',
                    couleurLisere: AgriColors.brandEmerald,
                    icone: SymbolesAgri.swap_horiz,
                    legende: 'Transferts actifs datés de ce mois',
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: CarteKpi(
                    libelle: 'Sujets Transférés',
                    valeur: '${duMois.fold(0, (s, t) => s + t.quantity)}',
                    couleurLisere: AgriColors.infoBlue,
                    icone: SymbolesAgri.pets,
                    legende: 'Cumul des sujets transférés ce mois',
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: CarteKpi(
                    libelle: 'Bandes Rattachées',
                    valeur: '${bandes.where((b) => b.lotSourceId != null).length}',
                    couleurLisere: AgriColors.accentYellow,
                    icone: SymbolesAgri.link,
                    legende: "Bandes reliées à leur bande d'origine",
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: CarteKpi(
                    libelle: 'Bandes à Vérifier',
                    valeur: '${_aRattacher.length}',
                    couleurLisere: AgriColors.errorRed,
                    icone: SymbolesAgri.warning,
                    legende: "Bandes peut-être issues d'une autre, sans origine renseignée",
                  ),
                ),
              ],
            ),
            if (_aRattacher.isNotEmpty) ...[
              const SizedBox(height: AgriSpacing.lg),
              _panneau(
                titre: 'Bandes à vérifier : double comptage possible',
                explication:
                    "Une bande créée pour accueillir une portée a un effectif initial qui compte déjà ces sujets ; s'ils sont aussi nés dans la bande mère, ils y sont encore comptés. Rattachez chaque bande concernée à sa bande d'origine : la sortie est inscrite dans la bande mère au jour de création, rien n'est ajouté à la bande rattachée. Une bande achetée ou constituée d'animaux extérieurs ne se rattache pas.",
                lignes: [
                  for (final b in _aRattacher)
                    _ligne(
                      cle: 'ligne-rattacher-${b.id}',
                      cellules: [
                        b.code,
                        b.createdDate == null ? '—' : _fr(b.createdDate!),
                        '${b.initialQuantity} sujet(s)',
                      ],
                      action: TextButton(
                        key: Key('rattacher-${b.id}'),
                        onPressed: () => _ouvrirFormulaire(aRattacher: b),
                        child: const Text("Rattacher à sa bande d'origine"),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AgriSpacing.lg),
            _panneau(
              titre: 'Historique des transferts',
              lignes: _transferts.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.all(AgriSpacing.md),
                        child: Text(
                          'Aucun transfert enregistré.',
                          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
                        ),
                      ),
                    ]
                  : [
                      for (final t in _transferts)
                        _ligne(
                          cle: 'ligne-transfert-${t.id}',
                          attenue: !t.isActive,
                          cellules: [
                            _fr(t.transferDate),
                            '${_code(t.sourceLotId)} → ${_code(t.targetLotId)}',
                            '${t.quantity} sujet(s)',
                            t.constitution ? 'Constitution de bande' : 'Transfert',
                            t.motif ?? '—',
                            !t.isActive
                                ? 'Annulé'
                                : t.syncStatus == SyncStatus.synced
                                ? 'Actif'
                                : t.syncStatus == SyncStatus.conflict
                                ? 'Refusé par le serveur'
                                : 'En attente d\'envoi',
                          ],
                          action: t.isActive
                              ? TextButton(
                                  key: Key('annuler-${t.id}'),
                                  onPressed: () => _annuler(t),
                                  child: const Text(
                                    'Annuler',
                                    style: TextStyle(color: AgriColors.errorDeep),
                                  ),
                                )
                              : null,
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _panneau({required String titre, String? explication, required List<Widget> lignes}) {
    return Container(
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      padding: const EdgeInsets.all(AgriSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titre.toUpperCase(),
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
          if (explication != null) ...[
            const SizedBox(height: AgriSpacing.xs),
            Text(
              explication,
              style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
          ],
          const SizedBox(height: AgriSpacing.sm),
          ...lignes,
        ],
      ),
    );
  }

  Widget _ligne({
    required String cle,
    required List<String> cellules,
    Widget? action,
    bool attenue = false,
  }) {
    return Container(
      key: Key(cle),
      padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Opacity(
        opacity: attenue ? 0.6 : 1,
        child: Row(
          children: [
            for (final c in cellules)
              Expanded(
                child: Text(
                  c,
                  style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface),
                ),
              ),
            SizedBox(width: 200, child: Align(alignment: Alignment.centerRight, child: action)),
          ],
        ),
      ),
    );
  }
}

/// Formulaire du transfert (ou du rattachement d'une bande à sa bande d'origine).
class _FormulaireTransfert extends StatefulWidget {
  const _FormulaireTransfert({required this.depot, required this.bandes, this.aRattacher});

  final TransfertsRepository depot;
  final List<LivestockLot> bandes;
  final LivestockLot? aRattacher;

  @override
  State<_FormulaireTransfert> createState() => _FormulaireTransfertState();
}

class _FormulaireTransfertState extends State<_FormulaireTransfert> {
  String? _source;
  String? _cible;
  late DateTime _jour;
  late final TextEditingController _quantite;
  final _motif = TextEditingController();
  String? _categorie;
  String? _erreur;
  bool _enCours = false;

  LivestockLot? get _rattachee => widget.aRattacher;
  bool get _constitution => _rattachee != null;

  @override
  void initState() {
    super.initState();
    final r = _rattachee;
    _cible = r?.id;
    _jour = r?.createdDate ?? DateTime.now();
    _quantite = TextEditingController(text: '${r?.initialQuantity ?? 1}');
    _categorie = r == null ? null : TransfertsRepository.categorieDuStade(r.stage);
  }

  @override
  void dispose() {
    _quantite.dispose();
    _motif.dispose();
    super.dispose();
  }

  LivestockLot? _bande(String? id) => widget.bandes.where((b) => b.id == id).firstOrNull;

  List<LivestockLot> get _sources {
    final r = _rattachee;
    if (r == null) return widget.bandes;
    return widget.bandes
        .where(
          (b) =>
              b.id != r.id &&
              b.speciesId == r.speciesId &&
              b.createdDate != null &&
              r.createdDate != null &&
              !b.createdDate!.isAfter(r.createdDate!),
        )
        .toList();
  }

  List<LivestockLot> get _cibles {
    final s = _bande(_source);
    if (s == null) return const [];
    return widget.bandes.where((b) => b.speciesId == s.speciesId && b.id != s.id).toList();
  }

  Future<void> _enregistrer() async {
    final quantite = int.tryParse(_quantite.text.trim());
    if (_source == null || _cible == null || quantite == null) {
      setState(() => _erreur = 'Choisissez la bande source, la bande cible et le nombre de sujets.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.depot.creer(
        sourceLotId: _source!,
        targetLotId: _cible!,
        jour: _jour,
        quantite: quantite,
        categorie: _categorie,
        constitution: _constitution,
        motif: _motif.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on TransfertRefuse catch (e) {
      setState(() {
        _erreur = e.motif;
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _bande(_source);
    final libelles = TransfertsRepository.libellesCategories(
      source?.speciesCode ?? _rattachee?.speciesCode,
    );

    return ModaleAgri(
      titre: _constitution ? "Rattacher une Bande à sa Bande d'Origine" : 'Nouveau Transfert',
      contenu: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_erreur != null)
            Container(
              key: const Key('transfert-erreur'),
              padding: const EdgeInsets.all(AgriSpacing.sm),
              margin: const EdgeInsets.only(bottom: AgriSpacing.sm),
              decoration: BoxDecoration(
                color: AgriColors.errorBg,
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
              child: Text(
                _erreur!,
                style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
              ),
            ),
          if (_constitution)
            Padding(
              padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
              child: Text(
                "Les sujets de la bande rattachée sont retirés de la bande d'origine au jour de création (${_TransfertsBandesScreenState._fr(_jour)}). L'effectif de la bande rattachée ne change pas : il les comptait déjà.",
                style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
              ),
            ),
          DropdownButtonFormField<String>(
            key: const Key('transfert-source'),
            initialValue: _source,
            decoration: InputDecoration(
              labelText: _constitution ? "Bande d'Origine *" : 'Bande Source *',
            ),
            items: [
              for (final b in _sources)
                DropdownMenuItem(value: b.id, child: Text('${b.code} (${b.currentQuantity})')),
            ],
            onChanged: (v) => setState(() {
              _source = v;
              if (!_constitution) {
                _cible = null;
                _categorie = null;
              }
            }),
          ),
          const SizedBox(height: AgriSpacing.sm),
          if (_constitution)
            TextFormField(
              initialValue: _rattachee!.code,
              enabled: false,
              decoration: const InputDecoration(labelText: 'Bande Rattachée'),
            )
          else
            DropdownButtonFormField<String>(
              key: const Key('transfert-cible'),
              initialValue: _cible,
              decoration: const InputDecoration(labelText: 'Bande Cible *'),
              items: [
                for (final b in _cibles)
                  DropdownMenuItem(value: b.id, child: Text('${b.code} (${b.currentQuantity})')),
              ],
              onChanged: (v) => setState(() => _cible = v),
            ),
          const SizedBox(height: AgriSpacing.sm),
          InkWell(
            key: const Key('transfert-date'),
            onTap: _constitution
                ? null
                : () async {
                    final choisi = await showDatePicker(
                      context: context,
                      initialDate: _jour,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (choisi != null) setState(() => _jour = choisi);
                  },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date du Transfert *'),
              child: Text(_TransfertsBandesScreenState._fr(_jour)),
            ),
          ),
          const SizedBox(height: AgriSpacing.sm),
          TextField(
            key: const Key('transfert-quantite'),
            controller: _quantite,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Nombre de Sujets *'),
          ),
          if (libelles.isNotEmpty) ...[
            const SizedBox(height: AgriSpacing.sm),
            DropdownButtonFormField<String>(
              key: const Key('transfert-categorie'),
              initialValue: _categorie,
              decoration: const InputDecoration(labelText: 'Catégorie des Sujets *'),
              items: [
                for (final e in libelles.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _categorie = v),
            ),
            const Text(
              "Les sujets gardent leur catégorie dans la bande cible : un changement de bande n'est pas un changement de stade.",
              style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
          ],
          const SizedBox(height: AgriSpacing.sm),
          TextField(
            key: const Key('transfert-motif'),
            controller: _motif,
            maxLength: 255,
            decoration: const InputDecoration(
              labelText: 'Motif',
              hintText: 'Ex. : sevrage de la portée de la lapine L-12',
            ),
          ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BoutonModalePrimaire(
          libelle: _constitution ? 'Rattacher' : 'Enregistrer le Transfert',
          onPressed: _enCours ? null : _enregistrer,
        ),
      ],
    );
  }
}
