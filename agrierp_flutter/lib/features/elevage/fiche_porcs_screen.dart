import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/tableau_mensuel.dart';
import 'categorie_ration_porc.dart';
import 'effectif_par_categorie.dart';
import 'fiche_journaliere_repository.dart';
import 'soins_repository.dart';

/// `prototype_html/fiche-porcs.html` → Saisie Journalière du Cheptel Porcin.
///
/// ⚠️⚠️ **LA MAQUETTE EST LA RÉFÉRENCE DE MISE EN PAGE.** Sections dans SON
/// ordre, libellés au mot près :
///   1. 4 cartes KPI (Effectif Porcins Vivants · Truies Gestantes / Verrats ·
///      Porcelets sous Mère · Taux de Mortalité) ;
///   2. en-tête de saisie ;
///   3. Entrées & Ventes (Achats du jour · Nés (Mise bas porcelets) ·
///      Ventes (POS)) ;
///   4. Morts par catégorie — Reproducteur · Porc Marchand · Porcelet ;
///   5. Dons par catégorie — les mêmes trois ;
///   6. Effectif Final du Jour + Taux de Mortalité du Jour ;
///   7. Rationnement & Provende Servie par Espèces ;
///   8. Pesée ;
///   9. Traitements & Soins Porcins ;
///  10. Attribution Logettes & Porcheries Traitées ;
///  11. Réinitialiser · Enregistrer ce Jour.
///
/// ⚠️⚠️ **SEULE FICHE À PESER EN KILOS.** Lapins et volailles pèsent en
/// grammes ; « Poids Général Pesé (**Kg**) » est propre aux porcs. La colonne
/// de stockage reste `weight_sample_avg_g` — le poids **moyen par sujet, en
/// grammes** — pour rester cohérente entre fiches. La conversion se fait donc
/// ici, dans les DEUX sens, et c'est exactement là que le serveur se trompait :
/// il rechargeait la moyenne dans le champ du total (corrigé au ticket 14.60).
///
/// ⚠️ **« VENTES » EST EN LECTURE SEULE**, comme dans la maquette : la valeur
/// vient de la CAISSE.
class FichePorcsScreen extends StatefulWidget {
  const FichePorcsScreen({super.key, required this.depot, required this.soins});

  final FicheJournaliereRepository depot;
  final SoinsRepository soins;

  @override
  State<FichePorcsScreen> createState() => _FichePorcsScreenState();
}

class _FichePorcsScreenState extends State<FichePorcsScreen> {
  /// Catégories de la maquette, dans SON ordre — Morts et Dons les partagent.
  static const _categories = ['Reproducteur', 'Porc Marchand', 'Porcelet'];

  /// F0.99 — libellés du bloc « Morts » du web (`fiche-porcs.blade.php`), différents de ceux des dons.
  static const _libellesMorts = {
    'Reproducteur': 'Reproducteur (Truie/Verrat)',
    'Porc Marchand': 'Porc marchand / Engraiss.',
  };

  List<LivestockLot> _bandes = const [];
  LivestockLot? _bande;
  DateTime _jour = DateTime.now();
  bool _chargement = true;

  int _achat = 0;
  int _ne = 0;
  int _vente = 0;

  /// Ticket 15.46 — transferts entre bandes du jour (dérivés, jamais saisis ici) : comptés dans l'effectif.
  int _transfertEntree = 0;
  int _transfertSortie = 0;
  int _effectifPrecedent = 0;

  /// F0.99 — veille par catégorie (chaîne, ou départ déduit du stade) ; `null` = inconnue (« — »).
  EffectifCategories? _veilleCategories;

  /// F0.99 — fiche chargée du jour : ses transferts PAR CATÉGORIE entrent dans le calcul, comme au web.
  LivestockDailyEntry? _ficheDuJour;

  /// 🔁 15.57 — état de la chaîne (mode, départ, date) : section « Effectif de départ par catégorie » du web.
  EtatJour? _etatCategories;

  /// 🔁 15.57 — départ par catégorie pré-rempli depuis le stade, corrigeable tant que la bande n'a pas de chaîne.
  int? _departRepro;
  int? _departSevre;
  int? _departJeune;

  /// 🔁 15.57 — effectifs saisis du web (QC5) : `effectif_m` Verrats, `effectif_f` Truies gestantes,
  /// `effectif_sevres` Porcelets, `effectif_smeres` Engraissement.
  int _effectifVerrats = 0;
  int _effectifTruies = 0;
  int _effectifPorcelets = 0;
  int _effectifEngraissement = 0;

  final _morts = <String, int>{for (final c in _categories) c: 0};
  final _dons = <String, int>{for (final c in _categories) c: 0};

  /// F0.97 — passage de stade du jour (Porcelet → Porc Marchand), `passage_sevre_jeune`.
  final _passage = <String, int>{'Porcelet → Porc Marchand': 0};

  /// Totaux d'une fiche ANCIENNE non ventilée rechargée : la catégorie ne se devine pas (web 15.42).
  int? _mortAncien;
  int? _donAncien;

  List<FeedRationStandard> _rations = const [];

  /// Journées du mois pour la bande choisie — le tableau de bas de fiche.
  List<LivestockDailyEntry> _fichesDuMois = const [];

  /// Poids TOTAL pesé, en kilos — l'unité de la maquette porcine.
  double _poidsTotalKg = 0;

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
    final bandes = toutes
        .where((b) => b.speciesCode == 'porciculture')
        .toList();
    final rations = await widget.depot.rations('porciculture');

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
    final veilleCategories = await widget.depot.veilleParCategorie(
      bande.id,
      _jour,
    );
    final etatCategories = await widget.depot.etatCategories(bande.id, _jour);
    final fiche = await widget.depot.chargerJour(bande.id, _jour);
    final protocole = await widget.soins.protocoleDuJour(
      bande: bande,
      codeEspece: 'porciculture',
      quand: _jour,
    );

    final mois = await widget.depot.fichesDuMois(bande.id, quand: _jour);

    if (!mounted) return;

    setState(() {
      _effectifPrecedent = precedent;
      _veilleCategories = veilleCategories;
      _ficheDuJour = fiche;
      _etatCategories = etatCategories;
      // Sans chaîne : le départ est pré-rempli depuis le stade (`departDepuisStade`), comme au web.
      final sansChaine = etatCategories?.mode == 'sans_chaine';
      _departRepro = sansChaine ? veilleCategories?.repro : null;
      _departSevre = sansChaine ? veilleCategories?.sevre : null;
      _departJeune = sansChaine ? veilleCategories?.jeune : null;
      _effectifVerrats = fiche?.effectifM ?? 0;
      _effectifTruies = fiche?.effectifF ?? 0;
      _effectifPorcelets = fiche?.effectifSevres ?? 0;
      _effectifEngraissement = fiche?.effectifSmeres ?? 0;
      _fichesDuMois = mois;
      _achat = fiche?.achat ?? 0;
      _ne = fiche?.ne ?? 0;
      _vente = fiche?.vente ?? 0;
      _transfertEntree = fiche?.transfertEntree ?? 0;
      _transfertSortie = fiche?.transfertSortie ?? 0;
      // ⚠️ LE TOTAL SE RECONSTITUE : moyenne (g) × effectif ÷ 1000. Reprendre
      // la moyenne telle quelle afficherait 5 Kg là où 500 ont été pesés —
      // le défaut corrigé côté serveur au ticket 14.60.
      final moyenneG = fiche?.weightSampleAvgG ?? 0;
      final effectifFiche = fiche?.effectifFinal ?? 0;
      _poidsTotalKg = moyenneG > 0 && effectifFiche > 0
          ? (moyenneG * effectifFiche) / 1000
          : 0;
      _protocole = protocole;
      _traitementsCoches.clear();
      _observations.clear();
      // 🔴→✅ F0.97 — LES MORTS ET DONS DU JOUR SONT RELUS PAR CATÉGORIE. Ils étaient remis à zéro au
      // rechargement : ré-enregistrer le jour effaçait ses morts. Emplacements : Reproducteur = `repro`,
      // Porcelet = `sevre`, Porc Marchand = `jeune`.
      for (final cle in _categories) {
        _morts[cle] = 0;
        _dons[cle] = 0;
      }
      _mortAncien = null;
      _donAncien = null;
      if (fiche != null) {
        if (fiche.mortRepro != null &&
            fiche.mortSevre != null &&
            fiche.mortJeune != null) {
          _morts['Reproducteur'] = fiche.mortRepro!;
          _morts['Porcelet'] = fiche.mortSevre!;
          _morts['Porc Marchand'] = fiche.mortJeune!;
        } else if (fiche.mort > 0) {
          _mortAncien = fiche.mort;
        }
        if (fiche.donRepro != null &&
            fiche.donSevre != null &&
            fiche.donJeune != null) {
          _dons['Reproducteur'] = fiche.donRepro!;
          _dons['Porcelet'] = fiche.donSevre!;
          _dons['Porc Marchand'] = fiche.donJeune!;
        } else if (fiche.don > 0) {
          _donAncien = fiche.don;
        }
      }
      _passage.updateAll((_, _) => fiche?.passageSevreJeune ?? 0);
      _chargement = false;
    });
  }

  // ── Calculs ───────────────────────────────────────────────────────────────

  int get _totalMorts => _morts.values.fold(0, (a, b) => a + b);
  int get _totalDons => _dons.values.fold(0, (a, b) => a + b);

  int get _effectifFinal => FicheJournaliereRepository.calculerEffectifFinal(
    effectifPrecedent: _effectifPrecedent,
    achat: _achat,
    ne: _ne,
    mort: _totalMorts,
    vente: _vente,
    don: _totalDons,
    transfertEntree: _transfertEntree,
    transfertSortie: _transfertSortie,
  ).clamp(0, 1 << 30);

  double? get _tauxMortalite => FicheJournaliereRepository.tauxMortalite(
    effectifPrecedent: _effectifPrecedent,
    mort: _totalMorts,
  );

  /// Poids moyen constaté, en **kilos** — l'unité affichée par cette fiche.
  ///
  /// ⚠️ Le dépôt raisonne en grammes (colonne commune aux fiches) : la pesée
  /// est donc convertie à l'entrée, et le résultat ramené en kilos.
  double? get _poidsMoyenKg {
    final moyenneG = FicheJournaliereRepository.poidsMoyen(
      poidsTotalG: _poidsTotalKg * 1000,
      tailleEchantillon: _effectifFinal,
    );
    return moyenneG == null ? null : moyenneG / 1000;
  }

  /// 🔁 F0.99 — effectifs PAR CATÉGORIE du jour, calculés comme le web (`categoriesJour`, 15.42) : veille de
  /// la chaîne (ou départ déduit du stade) + mouvements saisis + transferts du jour. `null` = inconnus.
  /// Sans chaîne, le départ SAISI (corrigé) remplace la veille déduite, comme `categoriesJour` du web.
  bool get _departModifiable =>
      _etatCategories?.mode == 'sans_chaine' && _veilleCategories != null;

  EffectifCategoriesJour? get _categoriesDuJour {
    final veille = _departModifiable
        ? EffectifCategories(
            repro: _departRepro,
            sevre: _departSevre,
            jeune: _departJeune,
          )
        : _veilleCategories;
    if (veille == null) return null;
    final f = _ficheDuJour;
    return EffectifParCategorie.calculerJour(
      EffectifParCategorie.porcs,
      veille,
      MouvementsJour(
        achat: _achat,
        ne: _ne,
        vente: _vente,
        mortRepro: _morts['Reproducteur'],
        mortSevre: _morts['Porcelet'],
        mortJeune: _morts['Porc Marchand'],
        donRepro: _dons['Reproducteur'],
        donSevre: _dons['Porcelet'],
        donJeune: _dons['Porc Marchand'],
        passage: _passage.values.single,
        transfertEntreeRepro: f?.transfertEntreeRepro ?? 0,
        transfertEntreeSevre: f?.transfertEntreeSevre ?? 0,
        transfertEntreeJeune: f?.transfertEntreeJeune ?? 0,
        transfertSortieRepro: f?.transfertSortieRepro ?? 0,
        transfertSortieSevre: f?.transfertSortieSevre ?? 0,
        transfertSortieJeune: f?.transfertSortieJeune ?? 0,
      ),
    );
  }

  /// Effectif d'une catégorie du rationnement (`sevre` = Porcelet, `jeune` = Porc Marchand).
  int? _effectifDeCategorie(EffectifCategoriesJour? jour, String cle) =>
      switch (cle) {
        CategorieRationPorc.reproducteur => jour?.repro,
        CategorieRationPorc.porcelet => jour?.sevre,
        _ => jour?.jeune,
      };

  /// `number_format($n, 0, ',', ' ')` de PHP (séparateur de milliers : espace).
  static String _milliers(num n) {
    final t = n.round().abs().toString();
    final sb = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      if (i > 0 && (t.length - i) % 3 == 0) sb.write(' ');
      sb.write(t[i]);
    }
    return '${n.round() < 0 ? '-' : ''}$sb';
  }

  /// `round($g / 1000, 2)` affiché par PHP : 2 décimales au plus, sans zéro final (« 2.8 », « 3 »).
  static String _kgCommePhp(double g) {
    final t = (g / 1000).toStringAsFixed(2);
    return t.replaceFirst(RegExp(r'\.?0+$'), '');
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
                    'Saisie Journalière du Cheptel Porcin — ${_libelleJour()}',
                icone: Icons.edit_note,
                enfant: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _entreesEtVentes(),
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
                    if (_mortAncien != null || _donAncien != null) ...[
                      const SizedBox(height: AgriSpacing.sm),
                      Container(
                        key: const Key('porcs-non-ventilee'),
                        padding: const EdgeInsets.all(AgriSpacing.sm),
                        decoration: BoxDecoration(
                          color: AgriColors.accentYellow.withValues(alpha: 0.2),
                          border: Border.all(color: AgriColors.accentYellow),
                          borderRadius: BorderRadius.circular(AgriRadius.lg),
                        ),
                        child: Text(
                          'Fiche ancienne non ventilée par catégorie : ${_mortAncien ?? 0} mort(s) et '
                          '${_donAncien ?? 0} don(s) non ventilé(s) y sont enregistrés. Ventilez-les '
                          "ci-dessus avant d'enregistrer.",
                          style: const TextStyle(
                            fontSize: AgriTypography.xs,
                            color: AgriColors.brandForest,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AgriSpacing.md),
                    _blocCategories(
                      titre: 'Passage de stade (Porcelet → Porc Marchand)',
                      icone: Icons.trending_up,
                      couleur: AgriColors.brandForest,
                      fond: AgriColors.surfaceZebra,
                      valeurs: _passage,
                    ),
                    ..._departParCategorie(),
                    const SizedBox(height: AgriSpacing.md),
                    _effectifsSaisis(),
                    const SizedBox(height: AgriSpacing.md),
                    _effectif(),
                    const SizedBox(height: AgriSpacing.md),
                    _rationnement(),
                    const SizedBox(height: AgriSpacing.md),
                    _pesee(),
                    const SizedBox(height: AgriSpacing.md),
                    _traitements(),
                    const SizedBox(height: AgriSpacing.md),
                    _attributionLogettes(),
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
        const Icon(Icons.pets, color: AgriColors.brandEmerald, size: 26),
        const SizedBox(width: AgriSpacing.xs),
        const Expanded(
          child: Text(
            'Fiches Porcs - Porciculture',
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
              libelle: 'Effectif Porcins Vivants',
              valeur: '$_effectifFinal',
              icone: Icons.pets,
              couleur: AgriColors.brandEmerald,
            ),
            // ⚠️ TIRET, PAS UN CHIFFRE. La ventilation truies / verrats /
            // porcelets sous mère n'est pas portée par le contrat de
            // synchronisation : un zéro se lirait « plus aucune truie ».
            _carteKpi(
              largeur: largeur,
              libelle: 'Truies Gestantes / Verrats',
              valeur: '—',
              icone: Icons.favorite,
              couleur: AgriColors.infoBlue,
            ),
            _carteKpi(
              largeur: largeur,
              libelle: 'Porcelets sous Mère',
              valeur: '—',
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

  /// Tableau mensuel — `fiche-porcs.html`, bas de page.
  ///
  /// Colonnes de la maquette : Date · **Entrées** (Achat, Né) · **Sorties**
  /// (Mort, Vente, Don) · **Effectif Final du Jour** (Truies Gest., Verrats,
  /// Porcelets, Engraiss., Total) · Taux Mort % · **Poids Général (Kg)** ·
  /// Traitements & Prophylaxie.
  ///
  /// ⚠️⚠️ **LA PESÉE EST EN KILOS, seule fiche à cette échelle.** La colonne
  /// annonce le TOTAL pesé ; la base stocke la MOYENNE par sujet en grammes.
  /// La reconstitution est `moyenne × effectif ÷ 1000` — c'est l'aller-retour
  /// corrigé au ticket 14.60, appliqué ici à la lecture.
  ///
  /// ⚠️ **TRUIES GEST. / VERRATS / PORCELETS / ENGRAISS. AFFICHENT UN TIRET** :
  /// le serveur les tient dans `effectif_f`, `effectif_m`, `effectif_sevres` et
  /// `effectif_smeres`, que le contrat de synchronisation ne descend pas.
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
              libelle: 'Né',
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
            // 🔁 15.57 — effectifs SAISIS synchronisés, ordre du web : Truies (`effectif_f`), Verrats (`effectif_m`),
            // Porcelets (`effectif_sevres`), Engraissement (`effectif_smeres`) ; « — » si non saisis.
            ColonneMensuelle(
              libelle: 'Truies Gest.',
              largeur: 1.3,
              valeur: (i) => _fichesDuMois[i].effectifF?.toString() ?? '—',
            ),
            ColonneMensuelle(libelle: 'Verrats', valeur: (i) => _fichesDuMois[i].effectifM?.toString() ?? '—'),
            ColonneMensuelle(
              libelle: 'Porcelets',
              largeur: 1.2,
              valeur: (i) => _fichesDuMois[i].effectifSevres?.toString() ?? '—',
            ),
            ColonneMensuelle(
              libelle: 'Engraiss.',
              largeur: 1.2,
              valeur: (i) => _fichesDuMois[i].effectifSmeres?.toString() ?? '—',
            ),
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
          libelle: 'Poids Général (Kg)',
          largeur: 1.6,
          valeur: (i) {
            final f = _fichesDuMois[i];
            final moyenne = f.weightSampleAvgG;
            if (moyenne == null || moyenne <= 0 || f.effectifFinal <= 0) {
              return '—';
            }
            // ⚠️ Moyenne (g) → total pesé (Kg).
            return ((moyenne * f.effectifFinal) / 1000).toStringAsFixed(1);
          },
        ),
        const ColonneMensuelle(
          // F0.99 — en-tête du web (`fiche-porcs.blade.php`).
          libelle: 'Traitements & Prophylaxie',
          largeur: 2.4,
          // ⚠️ Registre vétérinaire : autre table, une requête par ligne
          // serait nécessaire. Signalé plutôt qu'approximé.
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
            'Aucune bande porcine active sur ce poste.',
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
            libelle: 'Nés (Mise bas porcelets)',
            cle: 'ne',
            valeur: _ne,
            surChangement: (v) => setState(() => _ne = v),
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

  /// 🔁 15.57 — section « Effectif de départ par catégorie » du web (`fiche-porcs.blade.php`) : modifiable tant
  /// que la bande n'a pas de chaîne (pré-remplie depuis le stade), verrouillée ensuite, motif du refus affiché.
  List<Widget> _departParCategorie() {
    final etat = _etatCategories;
    if (etat == null) return const [];
    String date(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    Widget cadre({required Widget enfant, required bool modifiable}) => Container(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: modifiable
            ? AgriColors.brandEmerald.withValues(alpha: 0.05)
            : AgriColors.surfaceZebra,
        border: Border.all(
          color: modifiable
              ? AgriColors.brandEmerald.withValues(alpha: 0.2)
              : AgriColors.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: enfant,
    );

    final motif = etat.refus ?? _motifDepart;
    final widgets = <Widget>[];
    if (_departModifiable) {
      widgets.add(
        cadre(
          modifiable: true,
          enfant: Column(
            key: const Key('porcs-depart-modifiable'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EFFECTIF DE DÉPART PAR CATÉGORIE (DÉDUIT DU STADE DE LA BANDE)',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.brandEmerald,
                ),
              ),
              Text(
                "Effectif au DÉBUT du jour, avant les mouvements du jour, pré-rempli automatiquement depuis le stade "
                'de la bande. La somme des trois catégories doit égaler l\'effectif total au début du jour '
                '($_effectifPrecedent). Corrigez-le seulement pour une bande mixte ; il est verrouillé au premier '
                'enregistrement.',
                style: const TextStyle(fontSize: 10, color: AgriColors.outline),
              ),
              const SizedBox(height: AgriSpacing.xs),
              Row(
                children: [
                  for (final (libelle, cle, valeur, maj) in [
                    ('Reproducteur', 'depart-repro', _departRepro, (int v) => _departRepro = v),
                    ('Porcelet', 'depart-sevre', _departSevre, (int v) => _departSevre = v),
                    ('Porc Marchand', 'depart-jeune', _departJeune, (int v) => _departJeune = v),
                  ]) ...[
                    Expanded(
                      child: _champNombre(
                        libelle: libelle,
                        cle: cle,
                        valeur: valeur ?? 0,
                        surChangement: (v) => setState(() => maj(v)),
                      ),
                    ),
                    if (cle != 'depart-jeune') const SizedBox(width: AgriSpacing.sm),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    } else if (etat.depart != null && etat.departDate != null) {
      final d = etat.depart!;
      widgets.add(
        cadre(
          modifiable: false,
          enfant: Column(
            key: const Key('porcs-depart-verrouille'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EFFECTIF DE DÉPART PAR CATÉGORIE (VERROUILLÉ)',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.brandForest,
                ),
              ),
              Text(
                'Effectif de départ fixé le ${date(etat.departDate!)} (au début de ce jour).',
                style: const TextStyle(fontSize: 10, color: AgriColors.outline),
              ),
              const SizedBox(height: AgriSpacing.xs),
              Row(
                children: [
                  for (final (libelle, valeur) in [
                    ('Reproducteur', d.repro),
                    ('Porcelet', d.sevre),
                    ('Porc Marchand', d.jeune),
                  ]) ...[
                    Expanded(
                      child: _champLecture(
                        libelle: libelle,
                        valeur: valeur == null ? '—' : '$valeur',
                      ),
                    ),
                    if (libelle != 'Porc Marchand') const SizedBox(width: AgriSpacing.sm),
                  ],
                ],
              ),
              if (etat.mode == 'avant_depart')
                Text(
                  "Jour antérieur à l'effectif de départ fixé le ${date(etat.departDate!)} : les effectifs par "
                  'catégorie ne sont pas calculés (—).',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.errorDeep,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    if (motif != null) {
      widgets.add(
        Container(
          key: const Key('porcs-depart-motif'),
          margin: const EdgeInsets.only(top: AgriSpacing.xs),
          padding: const EdgeInsets.all(AgriSpacing.sm),
          decoration: BoxDecoration(
            color: AgriColors.errorBg,
            border: Border.all(color: AgriColors.errorDeep.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Text(
            motif,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
              color: AgriColors.errorDeep,
            ),
          ),
        ),
      );
    }
    return [if (widgets.isNotEmpty) const SizedBox(height: AgriSpacing.md), ...widgets];
  }

  /// Motif D4 du départ saisi (`verifierDepart` du web), affiché en direct.
  String? get _motifDepart => _departModifiable
      ? EffectifParCategorie.verifierDepart(
          EffectifCategories(
            repro: _departRepro,
            sevre: _departSevre,
            jeune: _departJeune,
          ),
          _effectifPrecedent,
        )
      : null;

  /// 🔁 15.57 — saisie Verrats / Truies Gestantes / Porcelets / Engraissement du web (QC5).
  Widget _effectifsSaisis() {
    return Row(
      key: const Key('porcs-effectifs-saisis'),
      children: [
        for (final (libelle, cle, valeur, maj) in [
          ('Verrats', 'effectif-verrats', _effectifVerrats, (int v) => _effectifVerrats = v),
          ('Truies Gestantes', 'effectif-truies', _effectifTruies, (int v) => _effectifTruies = v),
          ('Porcelets', 'effectif-porcelets', _effectifPorcelets, (int v) => _effectifPorcelets = v),
          ('Engraissement', 'effectif-engraissement', _effectifEngraissement, (int v) => _effectifEngraissement = v),
        ]) ...[
          Expanded(
            child: _champNombre(
              libelle: libelle,
              cle: cle,
              valeur: valeur,
              surChangement: (v) => setState(() => maj(v)),
            ),
          ),
          if (cle != 'effectif-engraissement') const SizedBox(width: AgriSpacing.sm),
        ],
      ],
    );
  }

  Widget _champLecture({
    required String libelle,
    String? suffixe,
    required String valeur,
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
              // Les clés du bloc, pas `_categories` : le bloc de passage n'a qu'un compteur.
              for (final categorie in valeurs.keys) ...[
                Expanded(child: _compteur(categorie, valeurs)),
                if (categorie != valeurs.keys.last)
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
    final prefixe = identical(valeurs, _morts)
        ? 'mort'
        : identical(valeurs, _dons)
        ? 'don'
        : 'passage';

    return Column(
      children: [
        Text(
          (identical(valeurs, _morts)
                  ? (_libellesMorts[categorie] ?? categorie)
                  : categorie)
              .toUpperCase(),
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

  /// « Rationnement & Provende Servie par Espèces (en Grammes g/j) ».
  ///
  /// ⚠️ LES GRAMMAGES ET LES LIBELLÉS VIENNENT DU RÉFÉRENTIEL SYNCHRONISÉ.
  /// 🔁 F0.99 — le tableau du web (`fiche-porcs.blade.php`) : trois lignes fixes Porcelet / Porc Marchand /
  /// Reproducteur, effectifs CALCULÉS par catégorie, ration du barème par clé stable (secours sinon). Une
  /// catégorie inconnue donne « — » et un total « — » : jamais une provende partielle présentée comme complète.
  Widget _rationnement() {
    final jour = _categoriesDuJour;
    double? total = 0;
    final lignes = <TableRow>[];

    for (final cle in CategorieRationPorc.ordre) {
      final ration = CategorieRationPorc.ration(_rations, cle);
      final effectif = _effectifDeCategorie(jour, cle);
      final grammes = effectif == null ? null : effectif * ration;
      total = (grammes == null || total == null) ? null : total + grammes;

      lignes.add(
        TableRow(
          decoration: cle == CategorieRationPorc.marchand
              ? const BoxDecoration(color: AgriColors.surfaceZebra)
              : null,
          children: [
            _Cellule(CategorieRationPorc.libelles[cle]!, cle: 'ration-libelle-$cle', gras: true),
            _Cellule(effectif == null ? '—' : '$effectif', cle: 'ration-effectif-$cle', centre: true),
            // Le web double l'unité sur la seule ligne Reproducteur : « 2 000 g/j (2.0 Kg) ».
            _Cellule(
              cle == CategorieRationPorc.reproducteur
                  ? '${_milliers(ration)} g/j (${(ration / 1000).toStringAsFixed(1)} Kg)'
                  : '${ration.round()} g/j',
              cle: 'ration-g-$cle',
              centre: true,
            ),
            _Cellule(
              grammes == null ? '—' : '${grammes.round()} g',
              cle: 'ration-grammes-$cle',
              droite: true,
              gras: true,
            ),
          ],
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
                  'RATIONNEMENT & PROVENDE SERVIE PAR STADE PORCIN (EN GRAMMES G/J)',
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
              2: FlexColumnWidth(1.8),
              3: FlexColumnWidth(1.8),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(color: AgriColors.surfaceZebra),
                children: [
                  _CelluleEntete('Stade Physiologique'),
                  _CelluleEntete('Effectif'),
                  _CelluleEntete('Ration Normative'),
                  _CelluleEntete('Provende Servie (g)'),
                ],
              ),
              ...lignes,
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
                    total == null
                        ? '—'
                        : '${total.round()} g (${_kgCommePhp(total)} Kg)',
                    cle: 'total-provende',
                    droite: true,
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

  /// ⚠️ **EN KILOS** — seule fiche à cette échelle.
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
                  'POIDS GÉNÉRAL PESÉ (KG)',
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
                    key: Key('champ-pesee-${_poidsTotalKg.round()}'),
                    initialValue: _poidsTotalKg == 0
                        ? ''
                        : '${_poidsTotalKg.round()}',
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'ex : 850',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (t) =>
                        setState(() => _poidsTotalKg = double.tryParse(t) ?? 0),
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
                    _poidsMoyenKg == null
                        ? '—'
                        : '${_poidsMoyenKg!.toStringAsFixed(1)} Kg',
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

  // ── Traitements & Soins Porcins ───────────────────────────────────────────

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
                  'Traitements & Soins Porcins Automatiques Prévus pour ce Jour',
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
                labelText: "Observations Cliniques / Notes de l'Animalier",
                hintText: "ex : Consommation d'eau normale, RAS...",
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
      codeEspece: 'porciculture',
      quand: _jour,
      idsBareme: Set.of(_traitementsCoches),
      observations: _observations.text,
    );

    if (!mounted) return;
    setState(() => _validationEnCours = false);
    await _chargerJour();
  }

  /// ⚠️⚠️ MÊME CONSTAT QUE LES CAGES ET LES BÂTIMENTS : la maquette liste trois
  /// logettes **en dur**, aucune table ne les porte — ni serveur ni poste — et
  /// le Blade Laravel omet la section.
  Widget _attributionLogettes() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.home_work, size: 18, color: AgriColors.brandEmerald),
              SizedBox(width: AgriSpacing.xs),
              Expanded(
                child: Text(
                  'Attribution Logettes & Porcheries Traitées (Cochées par défaut)',
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
            "Aucun référentiel de logettes n'existe encore : ni le serveur ni "
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
      _ne = 0;
      _poidsTotalKg = 0;
      for (final cle in _categories) {
        _morts[cle] = 0;
        _dons[cle] = 0;
      }
      _passage.updateAll((_, _) => 0);
    });
  }

  void _signalerRefus(String motif) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: AgriColors.errorDeep, content: Text(motif)),
    );
  }

  Future<void> _enregistrer() async {
    final bande = _bande;
    if (bande == null) return;

    // ⚠️ LE POIDS MOYEN EST STOCKÉ EN GRAMMES, comme sur les autres fiches :
    // la colonne est commune. Y déposer des kilos ferait une erreur d'un
    // facteur mille, invisible jusqu'au suivi de croissance.
    final moyenneG = FicheJournaliereRepository.poidsMoyen(
      poidsTotalG: _poidsTotalKg * 1000,
      tailleEchantillon: _effectifFinal,
    );

    // Fiche ancienne non ventilée rechargée : ne pas remettre ses morts / dons à zéro en silence.
    if ((_mortAncien != null && _totalMorts == 0) ||
        (_donAncien != null && _totalDons == 0)) {
      _signalerRefus(
        "Cette fiche porte des morts ou des dons non ventilés par catégorie : ventilez-les "
        "(Reproducteur / Porc Marchand / Porcelet) avant d'enregistrer.",
      );
      return;
    }

    try {
      await widget.depot.enregistrer(
        lotId: bande.id,
        jour: _jour,
        achat: _achat,
        ne: _ne,
        mort: _totalMorts,
        don: _totalDons,
        poidsMoyen: moyenneG,
        ventilation: VentilationJour(
          mortRepro: _morts['Reproducteur']!,
          mortSevre: _morts['Porcelet']!,
          mortJeune: _morts['Porc Marchand']!,
          donRepro: _dons['Reproducteur']!,
          donSevre: _dons['Porcelet']!,
          donJeune: _dons['Porc Marchand']!,
          passage: _passage.values.single,
          departSaisi: _departModifiable
              ? EffectifCategories(
                  repro: _departRepro,
                  sevre: _departSevre,
                  jeune: _departJeune,
                )
              : null,
        ),
        effectifs: EffectifsSaisis(
          m: _effectifVerrats,
          f: _effectifTruies,
          sevres: _effectifPorcelets,
          smeres: _effectifEngraissement,
        ),
      );
    } on FicheRefusee catch (e) {
      _signalerRefus(e.motif);
      return;
    }

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
  const _Cellule(
    this.texte, {
    this.centre = false,
    this.droite = false,
    this.gras = false,
    this.cle,
  });

  final String texte;
  final bool centre;
  final bool droite;
  final bool gras;

  /// Clé du texte (tests du rationnement, F0.99).
  final String? cle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(
        texte,
        key: cle == null ? null : Key(cle!),
        textAlign: centre
            ? TextAlign.center
            : (droite ? TextAlign.end : TextAlign.start),
        style: TextStyle(
          fontSize: 11,
          fontWeight: gras ? FontWeight.bold : FontWeight.normal,
          color: gras ? AgriColors.brandForest : AgriColors.onSurface,
        ),
      ),
    );
  }
}
