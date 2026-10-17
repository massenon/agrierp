import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/tableau_mensuel.dart';
import 'fiche_journaliere_repository.dart';
import 'soins_repository.dart';

/// `prototype_html/fiche-escargots.html` → Suivi du Cheptel Hélicicole.
///
/// ⚠️⚠️ **LA MAQUETTE EST LA RÉFÉRENCE DE MISE EN PAGE.** Sections dans SON
/// ordre, libellés au mot près :
///   1. 4 cartes KPI (Effectif Escargots Total · Naissains Nés (mois) ·
///      Taux d'Éclosion Naissains · Taux de Mortalité) ;
///   2. en-tête de saisie ;
///   3. Achats du jour · Naissains Nés (Éclosion) · Ventes (POS) ;
///   4. **Pondoirs** : Œufs Récoltés (Pondoirs terre) · Naissains Nés
///      (Éclosion jour) · Taux d'Éclosion Naissains (%) ;
///   5. Morts par catégorie — Bordé · Engraissement · Naissain ;
///   6. Dons par catégorie — les mêmes trois ;
///   7. Effectif Final du Jour + Taux de Mortalité du Jour ;
///   8. Rationnement ;
///   9. Pesée (en grammes) ;
///  10. Soins, Hygrométrie & Entretien du Substrat ;
///  11. Attribution Parcs & Fosses en Terre Traités ;
///  12. Réinitialiser · Enregistrer ce Jour.
///
/// ⚠️ **CORRESPONDANCE DES COLONNES, REPRISE DU SERVEUR** : `ponte_total` porte
/// les **œufs récoltés aux pondoirs**, `ne` les **naissains nés**. Comme pour
/// les reproducteurs, ce ne sont pas des œufs de table : cette fiche
/// n'alimente aucun stock d'œufs (garde-fou du ticket 14.59).
///
/// ⚠️⚠️ **AUCUN BARÈME DE RATION N'EXISTE POUR L'HÉLICICULTURE.** La maquette
/// demande un « Rationnement Farine Calcique & Fourrage » propre aux escargots,
/// mais `feed_ration_standards` ne couvre que cuniculture, aviculture et
/// porciculture — la filière hélicicole est désactivée par défaut (Document 00
/// §5.1) et aucun grammage n'a été fourni. La section reste **en bandeau
/// d'attente**, exactement comme côté serveur : inventer un grammage non
/// documenté ferait servir une provende au jugé.
///
/// ⚠️⚠️ **ÉCART DE LA MAQUETTE, SIGNALÉ ET NON RECOPIÉ.** Le prototype porte
/// **deux champs** « Naissains Nés » — `day-ne` dans la ligne des entrées et
/// `day-naissains-nes` dans le bloc pondoirs — stockés comme deux valeurs
/// distinctes (`day.ne` et `day.naissainsNes`). Or **seul le second alimente
/// l'effectif final** (`computeEffectifAndFeedLive`, l. 774 et 877) : un
/// animalier qui remplit le premier ne voit rien bouger, et sa saisie se perd.
///
/// Les deux champs restent **à leur place et dans leur forme**, mais portent la
/// même valeur : saisir dans l'un met l'autre à jour. Aucune saisie ne peut
/// donc être ignorée en silence. Le serveur, lui, avait résolu l'ambiguïté sans
/// la dire, en ne gardant qu'un champ. **À arbitrer par le client** : deux
/// notions réellement distinctes, ou une redondance de la maquette ?
class FicheEscargotsScreen extends StatefulWidget {
  const FicheEscargotsScreen({
    super.key,
    required this.depot,
    required this.soins,
  });

  final FicheJournaliereRepository depot;
  final SoinsRepository soins;

  @override
  State<FicheEscargotsScreen> createState() => _FicheEscargotsScreenState();
}

class _FicheEscargotsScreenState extends State<FicheEscargotsScreen> {
  /// Catégories de la maquette, dans SON ordre.
  static const _categories = ['Bordé', 'Engraissement', 'Naissain'];

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

  int _oeufsTerre = 0;
  int _naissainsNes = 0;

  final _morts = <String, int>{for (final c in _categories) c: 0};
  final _dons = <String, int>{for (final c in _categories) c: 0};

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
    final bandes = toutes.where((b) => b.speciesCode == 'helico').toList();
    final rations = await widget.depot.rations('helico');

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
      codeEspece: 'helico',
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
      _oeufsTerre = fiche?.ponteTotal ?? 0;
      _naissainsNes = fiche?.ne ?? 0;
      _poidsTotalPese = 0;
      _protocole = protocole;
      _traitementsCoches.clear();
      _observations.clear();
      for (final cle in _categories) {
        _morts[cle] = 0;
        _dons[cle] = 0;
      }
      _chargement = false;
    });
  }

  // ── Calculs ───────────────────────────────────────────────────────────────

  int get _totalMorts => _morts.values.fold(0, (a, b) => a + b);
  int get _totalDons => _dons.values.fold(0, (a, b) => a + b);

  int get _effectifFinal => FicheJournaliereRepository.calculerEffectifFinal(
    effectifPrecedent: _effectifPrecedent,
    achat: _achat,
    ne: _naissainsNes,
    mort: _totalMorts,
    vente: _vente,
    don: _totalDons,
    transfertEntree: _transfertEntree,
    transfertSortie: _transfertSortie,
  ).clamp(0, 1 << 30);

  /// Taux d'éclosion : naissains nés ÷ œufs récoltés × 100.
  ///
  /// ⚠️ `null` SANS ŒUF RÉCOLTÉ — la même distinction que sur la fiche
  /// Reproducteurs : « rien n'a été récolté » n'est pas « la ponte a échoué »,
  /// qui vaut bien 0 %.
  double? get _tauxEclosion {
    if (_oeufsTerre <= 0) return null;
    return (_naissainsNes / _oeufsTerre) * 100;
  }

  double? get _tauxMortalite => FicheJournaliereRepository.tauxMortalite(
    effectifPrecedent: _effectifPrecedent,
    mort: _totalMorts,
  );

  double? get _poidsMoyen => FicheJournaliereRepository.poidsMoyen(
    poidsTotalG: _poidsTotalPese,
    tailleEchantillon: _effectifFinal,
  );

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
                    'Saisie Journalière du Cheptel Hélicicole — ${_libelleJour()}',
                icone: Icons.edit_note,
                enfant: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _entreesEtVentes(),
                    const SizedBox(height: AgriSpacing.md),
                    _pondoirs(),
                    const SizedBox(height: AgriSpacing.md),
                    _blocCategories(
                      titre: 'Morts par catégorie',
                      icone: Icons.dangerous_outlined,
                      couleur: AgriColors.errorDeep,
                      fond: AgriColors.errorBg.withValues(alpha: 0.3),
                      valeurs: _morts,
                    ),
                    const SizedBox(height: AgriSpacing.md),
                    _blocCategories(
                      titre: 'Dons par catégorie',
                      icone: Icons.card_giftcard,
                      couleur: AgriColors.brandEmerald,
                      fond: AgriColors.brandEmerald.withValues(alpha: 0.05),
                      valeurs: _dons,
                    ),
                    const SizedBox(height: AgriSpacing.md),
                    _effectif(),
                    const SizedBox(height: AgriSpacing.md),
                    _rationnement(),
                    const SizedBox(height: AgriSpacing.md),
                    _pesee(),
                    const SizedBox(height: AgriSpacing.md),
                    _soinsEtHygrometrie(),
                    const SizedBox(height: AgriSpacing.md),
                    _attributionParcs(),
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
    return Row(
      children: [
        const Icon(Icons.bug_report, color: AgriColors.brandEmerald, size: 26),
        const SizedBox(width: AgriSpacing.xs),
        const Expanded(
          child: Text(
            'Fiches Escargots - Héliciculture',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AgriColors.brandForest,
            ),
          ),
        ),
        if (_bandes.length > 1)
          DropdownButton<String>(
            value: _bande?.id,
            underline: const SizedBox.shrink(),
            items: _bandes
                .map((b) => DropdownMenuItem(value: b.id, child: Text(b.code)))
                .toList(),
            onChanged: (id) async {
              setState(() => _bande = _bandes.firstWhere((b) => b.id == id));
              await _chargerJour();
            },
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
              libelle: 'Effectif Escargots Total',
              valeur: '$_effectifFinal',
              icone: Icons.bug_report,
              couleur: AgriColors.brandEmerald,
            ),
            _carteKpi(
              largeur: largeur,
              libelle: 'Naissains Nés (mois)',
              valeur: '$_naissainsNes',
              icone: Icons.child_care,
              couleur: AgriColors.infoBlue,
            ),
            _carteKpi(
              largeur: largeur,
              libelle: "Taux d'Éclosion Naissains",
              valeur: _tauxEclosion == null
                  ? '—'
                  : '${_tauxEclosion!.toStringAsFixed(1)}%',
              icone: Icons.egg_alt,
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

  /// Tableau mensuel — `fiche-escargots.html`, bas de page.
  ///
  /// Colonnes de la maquette, dans SON ordre : Date · **Entrées** (Achat,
  /// Naissain Né) · **Sorties** (Mort, Vente, Don) · **Effectif Final du Jour**
  /// (Naissains, Engraiss., Bordés, Total) · Taux Mort % · Poids Général (g) ·
  /// Entretien & Hygrométrie.
  ///
  /// ⚠️ **« NAISSAIN NÉ » AU SINGULIER EN ENTRÉE, « NAISSAINS » AU PLURIEL EN
  /// EFFECTIF** : ce sont bien deux libellés distincts dans la maquette, et
  /// l'un des points d'arbitrage client encore ouverts. Recopiés tels quels.
  ///
  /// ⚠️⚠️ **NAISSAINS / ENGRAISS. / BORDÉS AFFICHENT UN TIRET** : la
  /// ventilation par stade n'existe qu'à la saisie ;
  /// `livestock_daily_entries` ne porte que l'effectif total.
  ///
  /// ⚠️ **LE POIDS EST EN GRAMMES** (les porcs sont la seule fiche en kilos).
  /// La base stocke la moyenne par sujet, la maquette annonce le total pesé :
  /// d'où la reconstitution `moyenne × effectif`.
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
          libelle: 'Entrées',
          colonnes: [
            ColonneMensuelle(
              libelle: 'Achat',
              valeur: (i) => '${_fichesDuMois[i].achat}',
            ),
            ColonneMensuelle(
              libelle: 'Naissain Né',
              largeur: 1.4,
              valeur: (i) => '${_fichesDuMois[i].ne}',
            ),
          ],
        ),
        GroupeColonnes(
          libelle: 'Sorties',
          colonnes: [
            ColonneMensuelle(
              libelle: 'Mort',
              valeur: (i) => '${_fichesDuMois[i].mort}',
            ),
            ColonneMensuelle(
              libelle: 'Vente',
              valeur: (i) => '${_fichesDuMois[i].vente}',
            ),
            ColonneMensuelle(
              libelle: 'Don',
              valeur: (i) => '${_fichesDuMois[i].don}',
            ),
          ],
        ),
        GroupeColonnes(
          libelle: 'Effectif Final du Jour',
          colonnes: [
            // ⚠️ Trois colonnes non synchronisées — voir le docblock.
            const ColonneMensuelle(
              libelle: 'Naissains',
              largeur: 1.3,
              valeur: _nonSynchronise,
            ),
            const ColonneMensuelle(
              libelle: 'Engraiss.',
              largeur: 1.2,
              valeur: _nonSynchronise,
            ),
            const ColonneMensuelle(libelle: 'Bordés', valeur: _nonSynchronise),
            ColonneMensuelle(
              libelle: 'Total',
              gras: true,
              valeur: (i) => '${_fichesDuMois[i].effectifFinal}',
            ),
          ],
        ),
      ],
      colonnesSimples: [
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
        const ColonneMensuelle(
          libelle: 'Entretien & Hygrométrie',
          largeur: 2.4,
          // ⚠️ Le relevé d'entretien vit dans une autre table : le rattacher
          // jour par jour demanderait une requête par ligne. Signalé.
          valeur: _nonSynchronise,
        ),
      ],
    );
  }

  static String _nonSynchronise(int _) => '—';

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
            'Aucune bande hélicicole active sur ce poste.',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AgriColors.brandForest,
            ),
          ),
          SizedBox(height: AgriSpacing.xs),
          Text(
            "L'héliciculture est un module désactivé par défaut : vérifiez "
            "qu'il est actif côté serveur, puis synchronisez.",
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

  Widget _entreesEtVentes() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          child: _champNombre(
            libelle: 'Naissains Nés (Éclosion)',
            cle: 'naissains-entree',
            valeur: _naissainsNes,
            surChangement: (v) => setState(() => _naissainsNes = v),
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

  /// Le bloc pondoirs de la maquette.
  Widget _pondoirs() {
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
              libelle: 'Œufs Récoltés (Pondoirs terre)',
              cle: 'oeufs-terre',
              valeur: _oeufsTerre,
              surChangement: (v) => setState(() => _oeufsTerre = v),
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: _champNombre(
              libelle: 'Naissains Nés (Éclosion jour)',
              cle: 'naissains-nes',
              valeur: _naissainsNes,
              surChangement: (v) => setState(() => _naissainsNes = v),
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: _champLecture(
              libelle: "Taux d'Éclosion Naissains (%)",
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
                  '= Effectif (J-1) + Achats/Nés − (Morts + Ventes + Dons)',
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

  /// ⚠️⚠️ **BANDEAU D'ATTENTE, PAS UN TABLEAU VIDE.** Aucun barème de ration
  /// n'existe pour l'héliciculture : `feed_ration_standards` ne couvre que
  /// cuniculture, aviculture et porciculture. Un tableau à zéro se lirait
  /// « aucune provende à servir » ; le bandeau dit que le barème manque.
  Widget _rationnement() {
    if (_rations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: AgriColors.accentYellow.withValues(alpha: 0.12),
          border: Border.all(
            color: AgriColors.accentYellow.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: AgriColors.brandForest),
            SizedBox(width: AgriSpacing.xs),
            Expanded(
              child: Text(
                'RATIONNEMENT FARINE CALCIQUE & FOURRAGE — barème non fourni. '
                "Aucune ration normative n'existe pour l'héliciculture : la "
                'provende ne peut pas être calculée sans un grammage validé '
                'par le client.',
                style: TextStyle(fontSize: 10.5, color: AgriColors.brandForest),
              ),
            ),
          ],
        ),
      );
    }

    // Si un barème hélicicole est un jour fourni, il s'affiche comme ailleurs.
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
                  'RATIONNEMENT FARINE CALCIQUE & FOURRAGE (EN GRAMMES G/J)',
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
            children: [
              const TableRow(
                decoration: BoxDecoration(color: AgriColors.surfaceZebra),
                children: [
                  _CelluleEntete('Stade'),
                  _CelluleEntete('Effectif'),
                  _CelluleEntete('Ration Normative'),
                  _CelluleEntete('Provende Servie (g)'),
                ],
              ),
              for (final ration in _rations)
                TableRow(
                  children: [
                    _Cellule(ration.stageLabel),
                    _Cellule('$_effectifFinal', centre: true),
                    _Cellule(
                      '${ration.rationGPerDay.round()} g/j',
                      centre: true,
                    ),
                    _Cellule(
                      '${FicheJournaliereRepository.provendeGrammes(effectif: _effectifFinal, rationGParJour: ration.rationGPerDay).round()} g',
                      centre: true,
                      gras: true,
                    ),
                  ],
                ),
            ],
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
                      hintText: 'ex : 5000',
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

  // ── Soins, Hygrométrie & Entretien du Substrat ────────────────────────────

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

  /// ⚠️ ICÔNE `water_drop`, PAS `vaccines` : chez les escargots l'entretien du
  /// substrat et l'hygrométrie priment sur la vaccination. La maquette le dit
  /// par son icône comme par son titre.
  Widget _soinsEtHygrometrie() {
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
              const Icon(
                Icons.water_drop,
                size: 18,
                color: AgriColors.infoBlue,
              ),
              const SizedBox(width: AgriSpacing.xs),
              const Expanded(
                child: Text(
                  'Soins, Hygrométrie & Entretien du Substrat Prévus pour ce Jour',
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
                labelText: "Observations / Taux d'Humidité Relevé (%)",
                hintText:
                    "ex : Humidité du sol 85%, arrosage du soir effectué...",
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
                  "Valider l'Entretien & Soins Aujourd'hui",
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
      codeEspece: 'helico',
      quand: _jour,
      idsBareme: Set.of(_traitementsCoches),
      observations: _observations.text,
    );

    if (!mounted) return;
    setState(() => _validationEnCours = false);
    await _chargerJour();
  }

  /// ⚠️⚠️ CINQUIÈME OCCURRENCE DU MÊME MANQUE (cages, bâtiments, logettes,
  /// parcs, fosses) : la maquette liste trois emplacements en dur, aucune table
  /// ne les porte, et le Blade Laravel omet la section.
  Widget _attributionParcs() {
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
                  'Attribution Parcs & Fosses en Terre Traités (Cochés par défaut)',
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
            "Aucun référentiel de parcs et fosses n'existe encore : ni le "
            "serveur ni le poste n'en tiennent la liste. La section reste à sa "
            "place, vide, en attendant l'arbitrage du client.",
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
      _oeufsTerre = 0;
      _naissainsNes = 0;
      _poidsTotalPese = 0;
      for (final cle in _categories) {
        _morts[cle] = 0;
        _dons[cle] = 0;
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
      // ⚠️ `ne` PORTE LES NAISSAINS NÉS et `ponteTotal` les œufs récoltés aux
      // pondoirs : correspondance du serveur, inversée elle ferait passer une
      // récolte d'œufs pour des naissances.
      ne: _naissainsNes,
      mort: _totalMorts,
      don: _totalDons,
      ponteTotal: _oeufsTerre,
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
