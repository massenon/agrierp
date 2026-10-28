import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/champs_date_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'champs_modale_elevage.dart';
import 'transformation_repository.dart';

/// Ticket EL-1 — ÉCRAN « BON D'ABATTAGE & TRANSFORMATION », portage de `transformation-form.blade.php`
/// (`Livewire\Elevage\TransformationForm`, route `/transformation`, entrée « Transformation » du menu).
///
/// Même structure que le Blade : en-tête, trois cartes (« Transformations (mois) », « Sujets Transformés », « Valeur Stock
/// Produit Fini » en attente), formulaire « 1. Sélection de la Bande Source » à 55 % et « Impact Automatique Prévisualisé » à
/// 45 % (de `lg` à `1fr`), puis « Historique des Transformations » (20 dernières).
///
/// ⚠️ Le poste n'écrit que le fait : l'effectif de la bande et le stock du produit fini bougent quand le serveur a rejoué la
/// transformation (voir [TransformationRepository]). Les refus s'affichent sous le champ concerné, comme `@error`.
class TransformationScreen extends StatefulWidget {
  const TransformationScreen({super.key, required this.depot, this.nomOperateur = '', this.maintenant});

  final TransformationRepository depot;

  /// `auth()->user()->name`, dans le champ grisé « Opérateur ».
  final String nomOperateur;

  /// Horloge (mois des cartes, date initiale) ; par défaut l'heure du Bénin.
  final DateTime Function()? maintenant;

  @override
  State<TransformationScreen> createState() => _TransformationScreenState();
}

class _TransformationScreenState extends State<TransformationScreen> {
  List<LotTransformable> _lots = const [];
  List<Product> _produits = const [];
  KpisTransformation _kpis = const KpisTransformation(transformationsDuMois: 0, sujetsTransformes: 0);
  List<LigneTransformation> _historique = const [];
  bool _charge = false;
  bool _enCours = false;

  String _lotId = '';
  String _productId = '';
  late DateTime _date = _jourSeul(_maintenant());
  final _sujets = TextEditingController(text: '1');
  final _produite = TextEditingController();
  Map<String, String> _erreurs = const {};

  DateTime _maintenant() => (widget.maintenant ?? HeureBenin.maintenant)();

  static DateTime _jourSeul(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _sujets.dispose();
    _produite.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final lots = await widget.depot.lots();
    final produits = _lotId.isEmpty ? <Product>[] : await widget.depot.produits(_lotId);
    final kpis = await widget.depot.kpis(_maintenant());
    final historique = await widget.depot.historique();
    if (!mounted) return;
    setState(() {
      _lots = lots;
      _produits = produits;
      _kpis = kpis;
      _historique = historique;
      _charge = true;
    });
  }

  /// `updatedLotId()` : la bande change, le produit est remis à zéro.
  Future<void> _choisirLot(String id) async {
    final produits = id.isEmpty ? <Product>[] : await widget.depot.produits(id);
    if (!mounted) return;
    setState(() {
      _lotId = id;
      _productId = '';
      _produits = produits;
    });
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreurs = const {};
    });
    try {
      final r = await widget.depot.enregistrer(
        lotId: _lotId,
        qtyAnimals: _sujets.text,
        productId: _productId,
        qtyProduced: _produite.text,
        date: _date,
      );
      if (!mounted) return;
      ToastAgri.afficher(context, TransformationRepository.toast(r.transformation.qtyAnimals, r.produitNom));
      // `reset(['lotId', 'qtyAnimals', 'productId', 'qtyProduced'])`, 1 sujet, date du jour.
      _lotId = '';
      _productId = '';
      _sujets.text = '1';
      _produite.clear();
      _date = _jourSeul(_maintenant());
      _produits = const [];
      await _charger();
    } on TransformationRefusee catch (e) {
      if (!mounted) return;
      setState(() => _erreurs = e.erreurs);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_charge) {
      return const Scaffold(backgroundColor: AgriColors.surfaceBg, body: Center(child: CircularProgressIndicator()));
    }
    final large = AgriBreakpoints.large(context);

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AgriSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _enTete(large),
            const SizedBox(height: AgriSpacing.lg),
            GrilleKpi(
              colonnes: large ? 3 : 2,
              children: [
                CarteKpi(
                  key: const Key('kpi-transformations-mois'),
                  libelle: 'Transformations (mois)',
                  valeur: '${_kpis.transformationsDuMois}',
                  couleurLisere: AgriColors.brandEmerald,
                  icone: SymbolesAgri.restaurant,
                ),
                CarteKpi(
                  key: const Key('kpi-sujets-transformes'),
                  libelle: 'Sujets Transformés',
                  valeur: '${_kpis.sujetsTransformes}',
                  couleurLisere: AgriColors.infoBlue,
                  couleurIcone: AgriColors.infoBlue,
                  icone: SymbolesAgri.pets,
                ),
                // `x-kpi-card :pending` : tiret estompé et sablier devant « Disponible après … ».
                CarteKpi(
                  key: const Key('kpi-valeur-stock-produit-fini'),
                  libelle: 'Valeur Stock Produit Fini',
                  valeur: '—',
                  couleurValeur: AgriColors.outline.withValues(alpha: 0.5),
                  couleurLisere: AgriColors.accentYellow,
                  couleurIcone: AgriColors.brandForest,
                  icone: SymbolesAgri.inventory_2,
                  iconeLegende: SymbolesAgri.hourglass_empty,
                  legende: 'Disponible après Sprint 6 (Stocks) — valorisation de stock réelle',
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.lg),
            if (large)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 55, child: _formulaire()),
                  const SizedBox(width: AgriSpacing.md),
                  Expanded(flex: 45, child: _impact()),
                ],
              )
            else ...[
              _formulaire(),
              const SizedBox(height: AgriSpacing.md),
              _impact(),
            ],
            const SizedBox(height: AgriSpacing.xl),
            _tableau(),
          ],
        ),
      ),
    );
  }

  Widget _enTete(bool large) => Container(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AgriColors.outlineVariant))),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(SymbolesAgri.restaurant, size: 26, color: AgriColors.brandEmerald),
            const SizedBox(width: AgriSpacing.xs),
            Expanded(
              child: Text(
                "Bon d'Abattage & Transformation",
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
          'Convertit des sujets vivants en produits finis vendables au POS — impact automatique sur le cheptel et le stock.',
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
      ],
    ),
  );

  BoxDecoration get _cadre => BoxDecoration(
    color: AgriColors.surfaceCard,
    border: Border.all(color: AgriColors.outlineVariant),
    borderRadius: BorderRadius.circular(AgriRadius.lg),
  );

  LotTransformable? get _lotChoisi => _lots.where((l) => l.lot.id == _lotId).firstOrNull;

  Widget _formulaire() {
    final lot = _lotChoisi;
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: _cadre,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: AgriSpacing.md),
            child: Text(
              '1. SÉLECTION DE LA BANDE SOURCE',
              style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
            ),
          ),
          BlocChampModale(
            libelle: "Lot / Bande d'Élevage *",
            cleErreur: const Key('transformation-erreur-lot'),
            erreur: _erreurs['lotId'],
            enfant: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeyedSubtree(
                  key: const Key('transformation-lot'),
                  child: ChampListeModale(
                    valeur: _lotId,
                    vide: '-- Sélectionner --',
                    enErreur: _erreurs.containsKey('lotId'),
                    options: [for (final l in _lots) (l.lot.id, l.libelle)],
                    surChangement: _choisirLot,
                  ),
                ),
                const SizedBox(height: AgriSpacing.xs),
                lot == null
                    ? const Text(
                        key: Key('transformation-effectif'),
                        'Sélectionnez une bande pour voir son effectif disponible.',
                        style: TextStyle(fontSize: 10, color: AgriColors.outline),
                      )
                    : Text.rich(
                        key: const Key('transformation-effectif'),
                        TextSpan(
                          style: const TextStyle(fontSize: 10, color: AgriColors.outline),
                          children: [
                            const TextSpan(text: 'Effectif disponible : '),
                            TextSpan(
                              text: '${lot.disponible}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AgriColors.brandEmerald),
                            ),
                            const TextSpan(text: ' sujets.'),
                          ],
                        ),
                      ),
              ],
            ),
          ),
          BlocChampModale(
            libelle: 'Nombre de Sujets à Abattre *',
            cleErreur: const Key('transformation-erreur-sujets'),
            erreur: _erreurs['qtyAnimals'],
            enfant: KeyedSubtree(
              key: const Key('transformation-sujets'),
              child: ChampTexteModale(controleur: _sujets, nombre: true, enErreur: _erreurs.containsKey('qtyAnimals')),
            ),
          ),
          BlocChampModale(
            libelle: 'Produit Fini Cible *',
            cleErreur: const Key('transformation-erreur-produit'),
            erreur: _erreurs['productId'],
            enfant: KeyedSubtree(
              key: const Key('transformation-produit'),
              child: ChampListeModale(
                valeur: _productId,
                vide: '-- Choisir un produit --',
                enErreur: _erreurs.containsKey('productId'),
                desactive: _lotId.isEmpty,
                options: [for (final p in _produits) (p.id, p.name)],
                surChangement: (v) => setState(() => _productId = v),
              ),
            ),
          ),
          BlocChampModale(
            libelle: 'Quantité Produite (Unités / Kg)',
            cleErreur: const Key('transformation-erreur-produite'),
            erreur: _erreurs['qtyProduced'],
            enfant: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeyedSubtree(
                  key: const Key('transformation-produite'),
                  child: ChampTexteModale(
                    controleur: _produite,
                    nombre: true,
                    indice: 'ex : 10',
                    enErreur: _erreurs.containsKey('qtyProduced'),
                  ),
                ),
                const SizedBox(height: AgriSpacing.xs),
                const Text(
                  'Rendement libre — saisie manuelle sans calcul automatique (poids variable selon transformation).',
                  style: TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AgriSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ChampDateFormulaire(
                        cle: const Key('transformation-date'),
                        etiquette: 'Date de Transaction',
                        valeur: _date,
                        erreur: _erreurs['transformationDate'],
                        cleErreur: const Key('transformation-erreur-date'),
                        onTap: () async {
                          final choisie = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (choisie != null) setState(() => _date = choisie);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AgriSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: AgriSpacing.xs),
                        child: Text(
                          'OPÉRATEUR',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgriColors.brandForest),
                        ),
                      ),
                      KeyedSubtree(
                        key: const Key('transformation-operateur'),
                        child: ChampLectureModale(valeur: widget.nomOperateur),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Opacity(
            opacity: _enCours ? 0.5 : 1,
            child: ElevatedButton.icon(
              key: const Key('transformation-valider'),
              onPressed: _enCours ? null : _valider,
              icon: const Icon(SymbolesAgri.check_circle, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
              ),
              label: const Text('Valider la Transformation', style: TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _impact() => Container(
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: _cadre,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: AgriSpacing.md),
          child: Text(
            'IMPACT AUTOMATIQUE PRÉVISUALISÉ',
            style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
          ),
        ),
        _impactTuile(
          fond: AgriColors.errorBg,
          bord: AgriColors.errorDeep.withValues(alpha: 0.20),
          icone: SymbolesAgri.trending_down,
          couleur: AgriColors.errorDeep,
          titre: 'Élevage — Décrémentation',
          texte: "L'effectif vivant de la bande sera réduit du nombre de sujets abattus.",
        ),
        const SizedBox(height: AgriSpacing.sm),
        _impactTuile(
          fond: AgriColors.brandEmerald.withValues(alpha: 0.10),
          bord: AgriColors.brandEmerald.withValues(alpha: 0.20),
          icone: SymbolesAgri.trending_up,
          couleur: AgriColors.brandEmerald,
          titre: 'Stock Produits Finis — Incrémentation',
          texte: 'Le stock du produit fini choisi sera augmenté de la quantité produite saisie.',
        ),
        const SizedBox(height: AgriSpacing.sm),
        _impactTuile(
          fond: AgriColors.surfaceZebra,
          bord: AgriColors.outlineVariant,
          icone: SymbolesAgri.account_balance,
          couleur: AgriColors.outline,
          titre: 'Comptabilité — Variation de Stock',
          texte: 'Écriture automatique (Débit 313 / Crédit 73) en attente du Sprint 10 (journal comptable) — non générée pour le moment.',
        ),
        const SizedBox(height: AgriSpacing.sm),
        _impactTuile(
          fond: AgriColors.accentYellow.withValues(alpha: 0.10),
          bord: AgriColors.accentYellow.withValues(alpha: 0.30),
          icone: SymbolesAgri.point_of_sale,
          couleur: AgriColors.brandForest,
          titre: 'Vente au POS',
          texte:
              "Le produit est immédiatement disponible au catalogue (stock déjà incrémenté). L'imputation au centre analytique arrive avec la comptabilité (Sprint 10).",
        ),
      ],
    ),
  );

  Widget _impactTuile({
    required Color fond,
    required Color bord,
    required IconData icone,
    required Color couleur,
    required String titre,
    required String texte,
  }) => Container(
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(color: fond, border: Border.all(color: bord), borderRadius: BorderRadius.circular(AgriRadius.lg)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 18, color: couleur),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titre, style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: couleur)),
              Text(texte, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
            ],
          ),
        ),
      ],
    ),
  );

  static const _entete = TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.outline);
  static const _cellule = TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface);

  Widget _tableau() => Container(
    key: const Key('transformation-historique'),
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
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AgriColors.outlineVariant))),
          child: const Text(
            'Historique des Transformations',
            style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
          ),
        ),
        LayoutBuilder(
          builder: (_, c) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: c.maxWidth),
              child: SizedBox(
                width: max(760, c.maxWidth),
                child: Column(
                  children: [
                    Container(
                      color: AgriColors.surfaceZebra,
                      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
                      child: const Row(
                        children: [
                          Expanded(flex: 2, child: Text('DATE', style: _entete)),
                          Expanded(flex: 3, child: Text('BANDE SOURCE', style: _entete)),
                          Expanded(flex: 2, child: Text('SUJETS ABATTUS', textAlign: TextAlign.right, style: _entete)),
                          Expanded(flex: 4, child: Padding(padding: EdgeInsets.only(left: AgriSpacing.md), child: Text('PRODUIT FINI', style: _entete))),
                          Expanded(flex: 2, child: Text('QTÉ PRODUITE', textAlign: TextAlign.right, style: _entete)),
                          Expanded(flex: 3, child: Padding(padding: EdgeInsets.only(left: AgriSpacing.md), child: Text('STATUT', style: _entete))),
                        ],
                      ),
                    ),
                    if (_historique.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.lg),
                        child: Center(
                          child: Text(
                            'Aucune transformation enregistrée pour le moment.',
                            style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
                          ),
                        ),
                      ),
                    for (var i = 0; i < _historique.length; i++) _ligne(i, _historique[i]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _ligne(int i, LigneTransformation l) {
    final t = l.transformation;
    return Container(
      key: Key('transformation-ligne-${t.id}'),
      color: i.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 2, child: Text(TransformationRepository.jourFr(t.transformationDate), style: _cellule)),
          Expanded(
            flex: 3,
            child: Text(l.codeBande ?? '', style: _cellule.copyWith(fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
          ),
          Expanded(flex: 2, child: Text('${t.qtyAnimals}', textAlign: TextAlign.right, style: _cellule)),
          Expanded(
            flex: 4,
            child: Padding(padding: const EdgeInsets.only(left: AgriSpacing.md), child: Text(l.produit ?? '', style: _cellule)),
          ),
          Expanded(flex: 2, child: Text(TransformationRepository.quantite(t.qtyProduced), textAlign: TextAlign.right, style: _cellule)),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: AgriSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: AgriColors.surfaceZebra,
                      border: Border.all(color: AgriColors.outlineVariant),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Non comptabilisé',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgriColors.outline),
                    ),
                  ),
                  // Ajout du poste : où en est l'envoi (le web n'a qu'une ligne déjà écrite sur le serveur).
                  if (t.syncStatus != SyncStatus.synced)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        key: Key('transformation-attente-${t.id}'),
                        t.syncStatus == SyncStatus.conflict
                            ? 'Refusée par le serveur : ${l.motifRefus ?? 'motif non communiqué'}'
                            : "En attente d'envoi",
                        style: TextStyle(
                          fontSize: 10,
                          color: t.syncStatus == SyncStatus.conflict ? AgriColors.errorDeep : AgriColors.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
