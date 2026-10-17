import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/tableau_mensuel.dart';
import 'fiche_journaliere_repository.dart';
import 'soins_repository.dart';

/// `prototype_html/fiche-volailles-reproducteurs.html` → Suivi Reproducteurs
/// & Goliath.
///
/// ⚠️⚠️ **LA MAQUETTE EST LA RÉFÉRENCE DE MISE EN PAGE.** Sections dans SON
/// ordre, libellés au mot près :
///   1. 4 cartes KPI (Effectif Total Vivant · Taux d'Éclosion Couvoir ·
///      Poussins Nés (Éclosion) · Taux de Mortalité) ;
///   2. en-tête de saisie ;
///   3. Bande / Lot Concerné · Achats du jour · Ventes (POS) ;
///   4. **Couvoir** : Œufs Couvés · Poussins Nés · Taux d'Éclosion Calculé ;
///   5. Morts par catégorie — Reproducteur · Poulet · Poussin ;
///   6. (🔁 F0.99) pas de bloc Dons : le web n'en a pas et enregistre `don = 0` ;
///   7. Effectif Final du Jour + Taux de Mortalité du Jour ;
///   8. Rationnement & Provende Servie ;
///   9. Pesée (en grammes, contrairement aux porcs) ;
///  10. Traitements & Vaccins Avicoles Automatiques Prévus ;
///  11. Attribution Bâtiments & Parcs Volailles Traités ;
///  12. Réinitialiser · Enregistrer ce Jour.
///
/// ⚠️ **CORRESPONDANCE DES COLONNES, REPRISE DU SERVEUR** : `ponte_total` porte
/// les **œufs couvés** (mis en incubation) et `ne` les **poussins nés**. Ce
/// n'est pas une ponte d'œufs de table — et c'est bien pourquoi cette fiche
/// n'alimente aucun stock d'œufs (garde-fou du ticket 14.59).
///
/// ⚠️ **LE TAUX D'ÉCLOSION EST NUL, JAMAIS 85 %.** La maquette garde « 85.0 »
/// pour son KPI mensuel de démonstration, mais calcule le taux DU JOUR à partir
/// des seules valeurs saisies. Le serveur avait recopié le 85 % dans les deux —
/// corrigé au ticket 14.61. Ici, rien de couvé donne « — » : un taux inventé se
/// lit comme un couvoir qui fonctionne.
class FicheReproducteursScreen extends StatefulWidget {
  const FicheReproducteursScreen({
    super.key,
    required this.depot,
    required this.soins,
  });

  final FicheJournaliereRepository depot;
  final SoinsRepository soins;

  @override
  State<FicheReproducteursScreen> createState() =>
      _FicheReproducteursScreenState();
}

class _FicheReproducteursScreenState extends State<FicheReproducteursScreen> {
  /// Catégories de la maquette, dans SON ordre.
  /// 🔁 F0.99 — catégories des MORTS du web (`fiche-reproducteurs.blade.php`), libellés et ordre exacts.
  static const _categories = ['Repro', 'Poulet', 'Poussin'];

  List<LivestockLot> _bandes = const [];
  LivestockLot? _bande;
  DateTime _jour = DateTime.now();
  bool _chargement = true;

  int _achat = 0;
  int _vente = 0;

  /// Ticket 15.46 — transferts entre bandes du jour (dérivés, jamais saisis ici) : comptés dans l'effectif.
  int _transfertEntree = 0;
  int _transfertSortie = 0;
  int _effectifPrecedent = 0;

  int _oeufsCouves = 0;
  int _poussinsNes = 0;

  final _morts = <String, int>{for (final c in _categories) c: 0};
  /// 🔁 F0.99 — morts déjà enregistrés pour le jour rechargé (web 15.47 / 15.55) : la répartition n'est pas
  /// stockée, seul le total l'est. Sans lui, ré-enregistrer le jour remettait ses morts à zéro.
  int? _mortEnregistre;

  List<FeedRationStandard> _rations = const [];

  /// Journées du mois pour la bande choisie — le tableau de bas de fiche.
  List<LivestockDailyEntry> _fichesDuMois = const [];
  double _poidsTotalPese = 0;

  ProtocoleDuJour? _protocole;
  final _traitementsCoches = <String>{};
  final _observations = TextEditingController();
  bool _validationEnCours = false;

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  @override
  void dispose() {
    _observations.dispose();
    super.dispose();
  }

  Future<void> _initialiser() async {
    final toutes = await widget.depot.bandesActives();

    // ⚠️⚠️ **AVICULTURE HORS PONTE, PAS SEULEMENT REPRODUCTION.** Le titre de
    // la maquette le dit — « Reproducteurs **& Goliath** », et son bloc
    // d'attribution cite « Bâtiment G2 (Goliath/Chair) » : cette fiche couvre
    // AUSSI les bandes de chair en engraissement. Le serveur applique
    // exactement cette règle (`stage != 'ponte'`).
    //
    // Filtrer sur `stage == 'reproduction'` rendait les bandes de chair
    // INVISIBLES au poste alors que le web les gère : leur saisie journalière
    // serait devenue impossible sur le terrain, sans le moindre message.
    final bandes = toutes
        .where((b) => b.speciesCode == 'aviculture' && b.stage != 'ponte')
        .toList();
    final rations = await widget.depot.rations('aviculture');

    if (!mounted) return;

    setState(() {
      _bandes = bandes;
      _bande = bandes.isEmpty ? null : bandes.first;
      _rations = rations;
    });

    await _chargerJour();
  }

  Future<void> _chargerJour() async {
    final bande = _bande;
    if (bande == null) {
      setState(() => _chargement = false);
      return;
    }

    setState(() => _chargement = true);

    final precedent = await widget.depot.effectifPrecedent(bande.id, _jour);
    final fiche = await widget.depot.chargerJour(bande.id, _jour);
    final protocole = await widget.soins.protocoleDuJour(
      bande: bande,
      codeEspece: 'aviculture',
      quand: _jour,
    );

    final mois = await widget.depot.fichesDuMois(bande.id, quand: _jour);

    if (!mounted) return;

    setState(() {
      _effectifPrecedent = precedent;
      _fichesDuMois = mois;
      _achat = fiche?.achat ?? 0;
      _vente = fiche?.vente ?? 0;
      _transfertEntree = fiche?.transfertEntree ?? 0;
      _transfertSortie = fiche?.transfertSortie ?? 0;
      // ⚠️ `ponte_total` = œufs COUVÉS, `ne` = poussins NÉS (cf. serveur).
      _oeufsCouves = fiche?.ponteTotal ?? 0;
      _poussinsNes = fiche?.ne ?? 0;
      _poidsTotalPese = 0;
      _protocole = protocole;
      _traitementsCoches.clear();
      _observations.clear();
      for (final cle in _categories) {
        _morts[cle] = 0;
      }
      _mortEnregistre = (fiche?.mort ?? 0) > 0 ? fiche!.mort : null;
      _chargement = false;
    });
  }

  // ── Calculs ───────────────────────────────────────────────────────────────

  /// Morts du jour : la répartition saisie, sinon le total déjà enregistré (`mortDuJour` du web).
  int get _totalMorts {
    final saisis = _morts.values.fold(0, (a, b) => a + b);
    return saisis > 0 ? saisis : (_mortEnregistre ?? 0);
  }

  int get _effectifFinal => FicheJournaliereRepository.calculerEffectifFinal(
    effectifPrecedent: _effectifPrecedent,
    achat: _achat,
    // Les poussins nés SONT les entrées de naissance du jour.
    ne: _poussinsNes,
    mort: _totalMorts,
    vente: _vente,
    // F0.99 — aucun don sur cette fiche au web (`'don' => 0`).
      don: 0,
    transfertEntree: _transfertEntree,
    transfertSortie: _transfertSortie,
  ).clamp(0, 1 << 30);

  /// Taux d'éclosion du jour : poussins nés ÷ œufs couvés × 100.
  ///
  /// ⚠️ `null` SANS ŒUF COUVÉ — ni 0 % ni 85 %. « 0 % » se lirait « la couvée
  /// est perdue », ce qui est un fait clinique tout différent de « rien n'a été
  /// mis en incubation ». La distinction se voit d'ailleurs dans les tests.
  double? get _tauxEclosion {
    if (_oeufsCouves <= 0) return null;
    return (_poussinsNes / _oeufsCouves) * 100;
  }

  double? get _tauxMortalite => FicheJournaliereRepository.tauxMortalite(
    effectifPrecedent: _effectifPrecedent,
    mort: _totalMorts,
  );

  double? get _poidsMoyen => FicheJournaliereRepository.poidsMoyen(
    poidsTotalG: _poidsTotalPese,
    tailleEchantillon: _effectifFinal,
  );

  int _effectifDeLaLigne(String libelle) =>
      libelle.toLowerCase().contains('reproducteur') ? _effectifFinal : 0;

  double get _totalProvendeG {
    var total = 0.0;
    for (final ration in _rations) {
      total += FicheJournaliereRepository.provendeGrammes(
        effectif: _effectifDeLaLigne(ration.stageLabel),
        rationGParJour: ration.rationGPerDay,
      );
    }
    return total;
  }

  // ── Rendu ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AgriSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _enTete(),
            const SizedBox(height: AgriSpacing.lg),
            _cartesKpi(),
            const SizedBox(height: AgriSpacing.lg),
            if (_bande == null && !_chargement)
              _messageAucuneBande()
            else
              _carte(
                titre:
                    'Saisie Journalière Reproducteurs & Goliath — ${_libelleJour()}',
                icone: Icons.edit_note,
                enfant: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _bandeEtEntrees(),
                    const SizedBox(height: AgriSpacing.md),
                    _couvoir(),
                    const SizedBox(height: AgriSpacing.md),
                    if (_mortEnregistre != null) ...[
                      Container(
                        key: const Key('morts-enregistres'),
                        padding: const EdgeInsets.all(AgriSpacing.xs),
                        decoration: BoxDecoration(
                          color: AgriColors.accentYellow.withValues(alpha: 0.2),
                          border: Border.all(color: AgriColors.accentYellow),
                          borderRadius: BorderRadius.circular(AgriRadius.lg),
                        ),
                        child: Text(
                          '$_mortEnregistre mort(s) déjà enregistré(s) ce jour, sans répartition par catégorie : '
                          "ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.",
                          style: const TextStyle(fontSize: 11, color: AgriColors.brandForest),
                        ),
                      ),
                      const SizedBox(height: AgriSpacing.xs),
                    ],
                    _blocCategories(
                      titre: 'Morts par catégorie',
                      icone: Icons.dangerous_outlined,
                      couleur: AgriColors.errorDeep,
                      fond: AgriColors.errorBg.withValues(alpha: 0.3),
                      valeurs: _morts,
                    ),
                    const SizedBox(height: AgriSpacing.md),
                    _effectif(),
                    const SizedBox(height: AgriSpacing.md),
                    _rationnement(),
                    const SizedBox(height: AgriSpacing.md),
                    _pesee(),
                    const SizedBox(height: AgriSpacing.md),
                    _traitements(),
                    const SizedBox(height: AgriSpacing.md),
                    _attributionBatiments(),
                    const SizedBox(height: AgriSpacing.md),
                    _boutons(),
                  ],
                ),
              ),
            const SizedBox(height: AgriSpacing.lg),
            _tableauMensuel(),
          ],
        ),
      ),
    );
  }

  String _libelleJour() {
    final j = _jour.day.toString().padLeft(2, '0');
    final m = _jour.month.toString().padLeft(2, '0');
    return 'Jour ${_jour.day} ($j/$m/${_jour.year})';
  }

  Widget _enTete() {
    return const Row(
      children: [
        Icon(Icons.egg_alt, color: AgriColors.brandEmerald, size: 26),
        SizedBox(width: AgriSpacing.xs),
        Expanded(
          child: Text(
            'Fiches Reproducteurs - Aviculture',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cartesKpi() {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final colonnes = AgriBreakpoints.moyen(context) ? 4 : 2;
        final largeur =
            (contraintes.maxWidth - (colonnes - 1) * AgriSpacing.md) / colonnes;

        return Wrap(
          spacing: AgriSpacing.md,
          runSpacing: AgriSpacing.md,
          children: [
            _carteKpi(
              largeur: largeur,
              libelle: 'Effectif Total Vivant',
              valeur: '$_effectifFinal',
              icone: Icons.grid_view,
              couleur: AgriColors.brandEmerald,
            ),
            _carteKpi(
              largeur: largeur,
              libelle: "Taux d'Éclosion Couvoir",
              valeur: _tauxEclosion == null
                  ? '—'
                  : '${_tauxEclosion!.toStringAsFixed(1)}%',
              icone: Icons.egg,
              couleur: AgriColors.infoBlue,
            ),
            _carteKpi(
              largeur: largeur,
              libelle: 'Poussins Nés (Éclosion)',
              valeur: '$_poussinsNes',
              icone: Icons.child_care,
              couleur: AgriColors.accentYellow,
              couleurIcone: AgriColors.brandForest,
            ),
            _carteKpi(
              largeur: largeur,
              libelle: 'Taux de Mortalité',
              valeur: _tauxMortalite == null
                  ? '—'
                  : '${_tauxMortalite!.toStringAsFixed(1)}%',
              icone: Icons.trending_down,
              couleur: AgriColors.errorRed,
            ),
          ],
        );
      },
    );
  }

  /// Filet coloré de 4 px à gauche (`border-l-4`) : un **enfant**, car Flutter
  /// refuse un `borderRadius` sur une bordure aux couleurs non uniformes.
  Widget _carteKpi({
    required double largeur,
    required String libelle,
    required String valeur,
    required IconData icone,
    required Color couleur,
    Color? couleurIcone,
  }) => SizedBox(
    width: largeur,
    child: CarteKpi(
      libelle: libelle,
      valeur: valeur,
      icone: icone,
      couleurLisere: couleur,
      couleurIcone: couleurIcone ?? AgriColors.brandEmerald,
    ),
  );

  /// Tableau mensuel — `fiche-volailles-reproducteurs.html`, bas de page.
  ///
  /// Colonnes de la maquette, dans SON ordre : Date · **Lot / Souche** ·
  /// **Couvoir** (Couvés, Nés) · **Morts par Catégorie** (Repro, Poulet,
  /// Poussin) · Effectif Final · Taux Mort % · Poids Général (g) ·
  /// Traitements & Prophylaxie.
  ///
  /// ⚠️ **« LOT / SOUCHE » SE PLACE AVANT LES GROUPES**, comme dans la
  /// maquette — d'où `colonnesAvant` sur le composant. Le repousser après les
  /// groupes serait un repositionnement.
  ///
  /// 🔁 F0.99 — colonnes du WEB (`fiche-reproducteurs.blade.php`) : Date | Couvoir (Couvés, Nés) | Morts
  /// (total) | Effectif Final | Taux Mort % | Poids Général (g). « Lot / Souche » et « Traitements »
  /// n'existent pas au web ; la ventilation des morts n'est pas stockée, le web montre le total.
  ///
  /// ⚠️ **LE POIDS EST EN GRAMMES ICI** (les porcs pèsent en kilos). La base
  /// stocke la moyenne par sujet ; la maquette annonce le total pesé, d'où la
  /// reconstitution `moyenne × effectif`.
  Widget _tableauMensuel() {
    if (_bande == null) return const SizedBox.shrink();

    int effectifDebut(LivestockDailyEntry f) =>
        f.effectifFinal + f.mort + f.vente + f.don - f.achat - f.ne;

    return TableauMensuel(
      nombreDeJours: _fichesDuMois.length,
      jourActif: _indexDuJourCourant(),
      dateDe: (i) {
        final d = _fichesDuMois[i].entryDate;
        final j = d.day.toString().padLeft(2, '0');
        final m = d.month.toString().padLeft(2, '0');
        return 'Jour ${d.day} ($j/$m)';
      },
      onOuvrirJour: (i) => _ouvrirJour(_fichesDuMois[i].entryDate),
      groupes: [
        GroupeColonnes(
          libelle: 'Couvoir',
          colonnes: [
            // ⚠️ `ponte_total` = œufs COUVÉS, `ne` = poussins NÉS (cf. serveur).
            ColonneMensuelle(
              libelle: 'Couvés',
              valeur: (i) => '${_fichesDuMois[i].ponteTotal ?? 0}',
            ),
            ColonneMensuelle(
              libelle: 'Nés',
              valeur: (i) => '${_fichesDuMois[i].ne}',
            ),
          ],
        ),
        // 🔁 F0.99 — le web affiche le TOTAL des morts (`fiche-reproducteurs.blade.php`), la seule valeur stockée.
        GroupeColonnes(
          libelle: 'Morts (total)',
          colonnes: [
            ColonneMensuelle(
              libelle: 'Repro+Poulet+Poussin',
              largeur: 1.8,
              valeur: (i) => '${_fichesDuMois[i].mort}',
            ),
          ],
        ),
      ],
      colonnesSimples: [
        ColonneMensuelle(
          libelle: 'Effectif Final',
          largeur: 1.3,
          gras: true,
          valeur: (i) => '${_fichesDuMois[i].effectifFinal}',
        ),
        ColonneMensuelle(
          libelle: 'Taux Mort %',
          largeur: 1.2,
          valeur: (i) {
            final depart = effectifDebut(_fichesDuMois[i]);
            if (depart <= 0) return '—';
            return ((_fichesDuMois[i].mort / depart) * 100).toStringAsFixed(1);
          },
        ),
        ColonneMensuelle(
          libelle: 'Poids Général (g)',
          largeur: 1.6,
          valeur: (i) {
            final f = _fichesDuMois[i];
            final moyenne = f.weightSampleAvgG;
            if (moyenne == null || moyenne <= 0 || f.effectifFinal <= 0) {
              return '—';
            }
            // ⚠️ Moyenne (g) → total pesé (g).
            return (moyenne * f.effectifFinal).toStringAsFixed(0);
          },
        ),
      ],
    );
  }


  int? _indexDuJourCourant() {
    for (var i = 0; i < _fichesDuMois.length; i++) {
      final d = _fichesDuMois[i].entryDate;
      if (d.year == _jour.year &&
          d.month == _jour.month &&
          d.day == _jour.day) {
        return i;
      }
    }
    return null;
  }

  /// ⚠️ CHARGE LA JOURNÉE DANS LE FORMULAIRE, comme l'invite de la maquette.
  Future<void> _ouvrirJour(DateTime jour) async {
    setState(() => _jour = jour);
    await _chargerJour();
  }

  Widget _messageAucuneBande() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.lg),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: const Column(
        children: [
          Icon(Icons.sync_problem, size: 32, color: AgriColors.outline),
          SizedBox(height: AgriSpacing.sm),
          Text(
            'Aucune bande avicole hors ponte sur ce poste.',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AgriColors.brandForest,
            ),
          ),
          SizedBox(height: AgriSpacing.xs),
          Text(
            'Lancez une synchronisation pour recevoir les bandes du serveur.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AgriColors.outline),
          ),
        ],
      ),
    );
  }

  Widget _carte({
    required String titre,
    required IconData icone,
    required Widget enfant,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icone, color: AgriColors.brandEmerald, size: 20),
                const SizedBox(width: AgriSpacing.xs),
                Expanded(
                  child: Text(
                    titre,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: AgriSpacing.sm),
            enfant,
          ],
        ),
      ),
    );
  }

  /// « Bande / Lot Concerné » · « Achats du jour » · « Ventes (POS) ».
  Widget _bandeEtEntrees() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BANDE / LOT CONCERNÉ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.brandForest,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AgriColors.outlineVariant),
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('choix-bande'),
                    isExpanded: true,
                    value: _bande?.id,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AgriColors.onSurface,
                    ),
                    items: _bandes
                        .map(
                          (b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(b.code),
                          ),
                        )
                        .toList(),
                    onChanged: (id) async {
                      setState(
                        () => _bande = _bandes.firstWhere((b) => b.id == id),
                      );
                      await _chargerJour();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AgriSpacing.md),
        Expanded(
          child: _champNombre(
            libelle: 'Achats du jour',
            cle: 'achat',
            valeur: _achat,
            surChangement: (v) => setState(() => _achat = v),
          ),
        ),
        const SizedBox(width: AgriSpacing.md),
        Expanded(
          child: _champLecture(
            libelle: 'Ventes',
            suffixe: '(POS)',
            valeur: '$_vente',
          ),
        ),
      ],
    );
  }

  /// Le bloc couvoir de la maquette.
  Widget _couvoir() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.infoBlue.withValues(alpha: 0.06),
        border: Border.all(color: AgriColors.infoBlue.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _champNombre(
              libelle: 'Œufs Couvés (Mis en incubation)',
              cle: 'oeufs-couves',
              valeur: _oeufsCouves,
              surChangement: (v) => setState(() => _oeufsCouves = v),
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: _champNombre(
              libelle: 'Poussins Nés (Éclosion du jour)',
              cle: 'poussins-nes',
              valeur: _poussinsNes,
              surChangement: (v) => setState(() => _poussinsNes = v),
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: _champLecture(
              libelle: "Taux d'Éclosion Calculé (%)",
              valeur: _tauxEclosion == null
                  ? '—'
                  : '${_tauxEclosion!.toStringAsFixed(1)} %',
              cle: 'taux-eclosion',
            ),
          ),
        ],
      ),
    );
  }

  Widget _champNombre({
    required String libelle,
    required String cle,
    required int valeur,
    required ValueChanged<int> surChangement,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          libelle.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AgriColors.brandForest,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: TextFormField(
            key: Key('champ-$cle-$valeur'),
            initialValue: valeur == 0 ? '' : '$valeur',
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              hintText: '0',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(),
            ),
            onChanged: (t) => surChangement(int.tryParse(t) ?? 0),
          ),
        ),
      ],
    );
  }

  Widget _champLecture({
    required String libelle,
    String? suffixe,
    required String valeur,
    String? cle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 3,
          children: [
            Text(
              libelle.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AgriColors.brandForest,
              ),
            ),
            if (suffixe != null)
              Text(
                suffixe,
                style: const TextStyle(fontSize: 9, color: AgriColors.outline),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 40,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AgriColors.surfaceZebra,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Text(
            valeur,
            key: cle == null ? null : Key('lecture-$cle'),
            style: const TextStyle(fontSize: 14, color: AgriColors.outline),
          ),
        ),
      ],
    );
  }

  Widget _blocCategories({
    required String titre,
    required IconData icone,
    required Color couleur,
    required Color fond,
    required Map<String, int> valeurs,
  }) {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: fond,
        border: Border.all(color: couleur.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icone, size: 16, color: couleur),
              const SizedBox(width: AgriSpacing.xs),
              Text(
                titre.toUpperCase(),
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: couleur,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.xs),
          Row(
            children: [
              for (final categorie in _categories) ...[
                Expanded(child: _compteur(categorie, valeurs)),
                if (categorie != _categories.last)
                  const SizedBox(width: AgriSpacing.sm),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _compteur(String categorie, Map<String, int> valeurs) {
    final valeur = valeurs[categorie] ?? 0;
    final prefixe = valeurs == _morts ? 'mort' : 'don';

    return Column(
      children: [
        Text(
          categorie.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: AgriColors.outline,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Row(
            children: [
              _pas(categorie, valeurs, -1, '−', prefixe),
              Expanded(
                child: Center(
                  child: Text(
                    '$valeur',
                    key: Key('compteur-$prefixe-$categorie'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.onSurface,
                    ),
                  ),
                ),
              ),
              _pas(categorie, valeurs, 1, '+', prefixe),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pas(
    String categorie,
    Map<String, int> valeurs,
    int pas,
    String signe,
    String prefixe,
  ) {
    return InkWell(
      key: Key('pas-$prefixe-$categorie-$pas'),
      onTap: () => setState(() {
        final actuel = valeurs[categorie] ?? 0;
        valeurs[categorie] = (actuel + pas).clamp(0, 1 << 30);
      }),
      child: Container(
        width: 30,
        height: 34,
        alignment: Alignment.center,
        color: AgriColors.surfaceZebra,
        child: Text(
          signe,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AgriColors.brandForest,
          ),
        ),
      ),
    );
  }

  Widget _effectif() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.brandEmerald.withValues(alpha: 0.06),
        border: Border.all(
          color: AgriColors.brandEmerald.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EFFECTIF FINAL DU JOUR (CALCULÉ DYNAMIQUE)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const Text(
                  '= Effectif (J-1) + Achats/Poussins Nés − Morts',
                  style: TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_effectifFinal',
                  key: const Key('effectif-final'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AgriColors.brandEmerald,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AgriSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TAUX DE MORTALITÉ DU JOUR (%)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const Text(
                  '= (Morts du Jour ÷ Effectif J-1) × 100',
                  style: TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
                const SizedBox(height: 4),
                Text(
                  _tauxMortalite == null
                      ? '—'
                      : '${_tauxMortalite!.toStringAsFixed(1)} %',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AgriColors.errorDeep,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rationnement() {
    if (_rations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: AgriColors.surfaceZebra,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: const Text(
          "Aucune ration normative reçue pour l'aviculture — synchronisez le "
          'poste avant de servir la provende.',
          style: TextStyle(fontSize: 11, color: AgriColors.outline),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.restaurant, size: 18, color: AgriColors.brandEmerald),
              SizedBox(width: AgriSpacing.xs),
              Expanded(
                child: Text(
                  'RATIONNEMENT & PROVENDE SERVIE PAR STADE (EN GRAMMES G/J)',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          Table(
            border: TableBorder.all(color: AgriColors.outlineVariant),
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.5),
              3: FlexColumnWidth(1.8),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(color: AgriColors.surfaceZebra),
                children: [
                  _CelluleEntete("Stade / Tranche d'Âge"),
                  _CelluleEntete('Effectif'),
                  _CelluleEntete('Ration Normative'),
                  _CelluleEntete('Provende Servie (g)'),
                ],
              ),
              for (final ration in _rations)
                TableRow(
                  children: [
                    _Cellule(ration.stageLabel),
                    _Cellule(
                      '${_effectifDeLaLigne(ration.stageLabel)}',
                      centre: true,
                    ),
                    _Cellule(
                      '${ration.rationGPerDay.round()} g/j',
                      centre: true,
                    ),
                    _Cellule(
                      '${FicheJournaliereRepository.provendeGrammes(effectif: _effectifDeLaLigne(ration.stageLabel), rationGParJour: ration.rationGPerDay).round()} g',
                      centre: true,
                      gras: true,
                    ),
                  ],
                ),
              TableRow(
                decoration: BoxDecoration(
                  color: AgriColors.brandEmerald.withValues(alpha: 0.08),
                ),
                children: [
                  const _Cellule(
                    'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)',
                    gras: true,
                  ),
                  const _Cellule(''),
                  const _Cellule(''),
                  _Cellule(
                    '${_totalProvendeG.round()} g '
                    '(${(_totalProvendeG / 1000).toStringAsFixed(1)} Kg)',
                    centre: true,
                    gras: true,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.xs),
          const Text(
            "L'effectif n'est pas encore ventilé par stade : la fiche du jour "
            "n'en porte que le total. La ligne des reproducteurs le reçoit "
            'entièrement.',
            style: TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
        ],
      ),
    );
  }

  Widget _pesee() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'POIDS GÉNÉRAL PESÉ (G)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const Text(
                  '(Pré-rempli de J-1)',
                  style: TextStyle(fontSize: 9, color: AgriColors.outline),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 40,
                  child: TextFormField(
                    key: Key('champ-pesee-${_poidsTotalPese.round()}'),
                    initialValue: _poidsTotalPese == 0
                        ? ''
                        : '${_poidsTotalPese.round()}',
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'ex : 2400',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (t) => setState(
                      () => _poidsTotalPese = double.tryParse(t) ?? 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AgriSpacing.md),
          Expanded(
            child: _champLecture(
              libelle: 'Taille Échantillon',
              suffixe: '(Auto = Effectif Final)',
              valeur: '$_effectifFinal',
            ),
          ),
          const SizedBox(width: AgriSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'POIDS MOYEN CONSTATÉ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 40,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AgriColors.surfaceZebra,
                    borderRadius: BorderRadius.circular(AgriRadius.lg),
                  ),
                  child: Text(
                    _poidsMoyen == null ? '—' : '${_poidsMoyen!.round()} g',
                    key: const Key('poids-moyen'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandEmerald,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Traitements & Vaccins Avicoles ────────────────────────────────────────

  String _etatProphylaxie(ProtocoleDuJour p) {
    if (!p.determinable) return 'Indéterminé';
    if (p.traitements.isEmpty) return 'Libre';
    return p.enAttente == 0 ? 'Validé / Effectué' : 'Prévus';
  }

  Color _couleurEtat(ProtocoleDuJour p) {
    if (!p.determinable) return AgriColors.outline;
    if (p.traitements.isEmpty) return AgriColors.brandEmerald;
    return p.enAttente == 0 ? AgriColors.brandEmerald : AgriColors.accentYellow;
  }

  Widget _traitements() {
    final protocole = _protocole;

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.infoBlue.withValues(alpha: 0.05),
        border: Border.all(color: AgriColors.infoBlue.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.vaccines, size: 18, color: AgriColors.infoBlue),
              const SizedBox(width: AgriSpacing.xs),
              const Expanded(
                child: Text(
                  'Traitements & Vaccins Avicoles Automatiques Prévus',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AgriTypography.xs,
                    color: AgriColors.brandForest,
                  ),
                ),
              ),
              if (protocole != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _couleurEtat(protocole).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _etatProphylaxie(protocole),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _couleurEtat(protocole) == AgriColors.accentYellow
                          ? AgriColors.brandForest
                          : _couleurEtat(protocole),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          if (protocole == null)
            const Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            // ⚠️ CETTE FICHE EST CELLE OÙ L'INDÉTERMINATION SE PRODUIT LE PLUS :
            // le cycle d'une bande en reproduction se compte depuis la dernière
            // saillie (F0.91 : calculé au poste dès qu'une saillie est connue) ;
            // sans aucune saillie enregistrée, il reste indéterminé.
            if (!protocole.determinable)
              Text(
                'Protocole non calculable au poste — '
                '${protocole.motifIndetermine ?? ''}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AgriColors.errorDeep,
                ),
              )
            else if (protocole.traitements.isEmpty)
              const Text(
                '— Aucun traitement récurrent programmé pour ce jour —',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              )
            else
              ...protocole.traitements.map(_ligneTraitement),
            if (protocole.calendairesNonEvalues > 0)
              Padding(
                padding: const EdgeInsets.only(top: AgriSpacing.xs),
                child: Text(
                  '${protocole.calendairesNonEvalues} entrée(s) du protocole '
                  'suivent le calendrier et ne sont pas évaluées ici.',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            const SizedBox(height: AgriSpacing.sm),
            TextField(
              controller: _observations,
              maxLines: 2,
              style: const TextStyle(fontSize: AgriTypography.xs),
              decoration: const InputDecoration(
                labelText: "Observations Cliniques / Notes de l'Animalier",
                hintText: 'ex : RAS, ponte régulière...',
                hintStyle: TextStyle(fontSize: 11),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AgriSpacing.sm),
            if (protocole.determinable && protocole.enAttente > 0) ...[
              const Text(
                'Valider un traitement rémanent bloque la vente de cette bande '
                "jusqu'à la fin du délai d'attente.",
                style: TextStyle(fontSize: 10, color: AgriColors.errorDeep),
              ),
              const SizedBox(height: AgriSpacing.xs),
              FilledButton.icon(
                key: const Key('bouton-valider-traitements'),
                onPressed: _traitementsCoches.isEmpty || _validationEnCours
                    ? null
                    : _validerTraitements,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text(
                  "Valider l'Administration de tous ces Traitements Aujourd'hui",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: AgriSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    protocole.enAttente > 0
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    size: 13,
                    color: protocole.enAttente > 0
                        ? AgriColors.errorDeep
                        : AgriColors.brandEmerald,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Indice Rouge : ${protocole.enAttente} soin(s) en attente',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: protocole.enAttente > 0
                          ? AgriColors.errorDeep
                          : AgriColors.brandEmerald,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ligneTraitement(TraitementPrevu t) {
    final standard = t.standard;
    final details = [
      if ((standard.productRecommended ?? '').isNotEmpty)
        standard.productRecommended!,
      if ((standard.dosage ?? '').isNotEmpty) standard.dosage!,
    ].join(' — ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 22,
            width: 22,
            child: Checkbox(
              value:
                  t.dejaAdministre || _traitementsCoches.contains(standard.id),
              onChanged: t.dejaAdministre
                  ? null
                  : (coche) => setState(() {
                      if (coche == true) {
                        _traitementsCoches.add(standard.id);
                      } else {
                        _traitementsCoches.remove(standard.id);
                      }
                    }),
            ),
          ),
          const SizedBox(width: AgriSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  standard.treatment,
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                    decoration: t.dejaAdministre
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    '($details)',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AgriColors.outline,
                    ),
                  ),
              ],
            ),
          ),
          if (t.remanenceJours > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AgriColors.errorBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Rémanence ${t.remanenceJours}j',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.errorDeep,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _validerTraitements() async {
    // ⚠️ F0.93 : garde de l'écran (un second appel avant le setState),
    // EN PLUS du dépôt, qui recalcule le protocole sous transaction.
    if (_validationEnCours) return;
    final bande = _bande;
    if (bande == null || _protocole == null) return;

    setState(() => _validationEnCours = true);

    // ⚠️⚠️ F0.93 — PAS de boucle sur l'instantané `_protocole` : le dépôt
    // RECALCULE le protocole à l'instant de l'écriture (comme le serveur,
    // 15.35) ; valider deux fois = un seul soin, une seule rémanence.
    await widget.soins.validerTraitementsDuJour(
      bande: bande,
      codeEspece: 'aviculture',
      quand: _jour,
      idsBareme: Set.of(_traitementsCoches),
      observations: _observations.text,
    );

    if (!mounted) return;
    setState(() => _validationEnCours = false);
    await _chargerJour();
  }

  /// ⚠️⚠️ QUATRIÈME OCCURRENCE DU MÊME MANQUE (cages, bâtiments, logettes,
  /// parcs) : la maquette liste trois emplacements en dur, aucune table ne les
  /// porte, et le Blade Laravel omet la section.
  Widget _attributionBatiments() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.home_work, size: 18, color: AgriColors.brandEmerald),
              SizedBox(width: AgriSpacing.xs),
              Expanded(
                child: Text(
                  'Attribution Bâtiments & Parcs Volailles Traités (Cochés par défaut)',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AgriSpacing.sm),
          Text(
            "Aucun référentiel de bâtiments n'existe encore : ni le serveur ni "
            "le poste n'en tiennent la liste. La section reste à sa place, "
            "vide, en attendant l'arbitrage du client.",
            style: TextStyle(
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
              color: AgriColors.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boutons() {
    return Container(
      padding: const EdgeInsets.only(top: AgriSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            key: const Key('bouton-reinitialiser'),
            onPressed: _bande == null ? null : _reinitialiserJour,
            style: OutlinedButton.styleFrom(
              foregroundColor: AgriColors.outline,
              side: const BorderSide(color: AgriColors.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
            ),
            child: const Text(
              'Réinitialiser',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          FilledButton.icon(
            key: const Key('bouton-enregistrer'),
            onPressed: _bande == null ? null : _enregistrer,
            icon: const Icon(Icons.save, size: 18),
            label: const Text(
              'Enregistrer ce Jour',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _reinitialiserJour() {
    setState(() {
      _achat = 0;
      _oeufsCouves = 0;
      _poussinsNes = 0;
      _poidsTotalPese = 0;
      for (final cle in _categories) {
        _morts[cle] = 0;
      }
    });
  }

  Future<void> _enregistrer() async {
    final bande = _bande;
    if (bande == null) return;

    await widget.depot.enregistrer(
      lotId: bande.id,
      jour: _jour,
      achat: _achat,
      // ⚠️ `ne` PORTE LES POUSSINS NÉS et `ponteTotal` les œufs couvés : c'est
      // la correspondance du serveur, et l'inverser ferait passer une couvée
      // pour des naissances.
      ne: _poussinsNes,
      mort: _totalMorts,
      // F0.99 — aucun don sur cette fiche au web (`'don' => 0`).
      don: 0,
      ponteTotal: _oeufsCouves,
      poidsMoyen: _poidsMoyen,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Jour enregistré.')));

    await _chargerJour();
  }
}

class _CelluleEntete extends StatelessWidget {
  const _CelluleEntete(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(
        texte.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: AgriColors.outline,
        ),
      ),
    );
  }
}

class _Cellule extends StatelessWidget {
  const _Cellule(this.texte, {this.centre = false, this.gras = false});

  final String texte;
  final bool centre;
  final bool gras;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(
        texte,
        textAlign: centre ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: 11,
          fontWeight: gras ? FontWeight.bold : FontWeight.normal,
          color: gras ? AgriColors.brandForest : AgriColors.onSurface,
        ),
      ),
    );
  }
}
