import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/tableau_mensuel.dart';
import 'categorie_ration_lapin.dart';
import 'effectif_par_categorie.dart';
import 'fiche_journaliere_repository.dart';
import 'soins_repository.dart';

/// `prototype_html/fiche-lapins.html` → Saisie Journalière du Cheptel.
///
/// SECTIONS REPRISES DE LA MAQUETTE, dans l'ordre :
///   1. en-tête « Fiches Lapins - Cuniculture » + sélecteur de date ;
///   2. « Saisie Journalière du Cheptel — Jour N (jj/mm/aaaa) » ;
///   3. Entrées & Ventes (Achats du jour, Nés (Mise bas), Ventes (POS)) ;
///   4. « Morts par catégorie » — Reproducteur / Jeune / Sous-mères (glossaire du 17/10/2026, F0.96) ;
///   5. « Dons par catégorie » — mêmes trois catégories ; puis le sevrage du jour (Sous-mères → Jeune) ;
///   6. Effectif Final du Jour, calculé, avec sa formule affichée.
///
/// ⚠️ **« VENTES » EST EN LECTURE SEULE**, exactement comme dans la maquette :
/// la valeur vient de la CAISSE, pas de cette fiche. La rendre saisissable
/// ouvrirait deux sources pour un même chiffre — et la caisse écraserait la
/// saisie manuelle au passage suivant, sans prévenir.
///
/// ⚠️ **LES COMPTEURS ± NE DESCENDENT PAS SOUS ZÉRO.** La maquette pose
/// `min="0"` sur chaque champ : un nombre de morts négatif n'a pas de sens et
/// gonflerait l'effectif final au lieu de le réduire.
///
/// SECTIONS AJOUTÉES APRÈS LE PREMIER PORTAGE (ce docblock disait, jusqu'au
/// ticket F0.91, qu'elles n'étaient « pas converties » : c'était faux depuis
/// F0.12) :
///   • « Traitements & Prophylaxie Automatiques Prévus pour ce Jour » (F0.12) —
///     protocole calculé par `SoinsRepository.protocoleDuJour`, même règle que
///     `ProtocoleDuJourService` côté serveur (15.35, parité vérifiée en F0.91) :
///     J1 = mise en lot, ou DERNIÈRE SAILLIE pour une bande en reproduction ;
///     « Indéterminé » (écart assumé, quatrième état) quand aucune saillie
///     n'est connue ; valider écrit un vrai soin et sa rémanence ;
///   • « Attribution Cages & Bandes Traitées » — rendue à sa place, mais SANS
///     référentiel (aucune table `cages` nulle part) : voir `_attributionCages`.
///
/// ÉCART ASSUMÉ — la maquette détaille morts et dons en TROIS catégories
/// (reproducteur, chair, lapereau) alors que le schéma de synchronisation ne
/// porte qu'un total `mort` et un total `don` : c'est le contrat que le
/// serveur accepte. La saisie par catégorie est conservée à l'écran (elle aide
/// l'éleveur à ne rien oublier) et sommée à l'enregistrement. La ventilation
/// n'est donc PAS persistée — signalé, car la restituer demanderait des
/// colonnes qui n'existent ni localement ni côté serveur.
class FicheLapinsScreen extends StatefulWidget {
  const FicheLapinsScreen({
    super.key,
    required this.depot,
    required this.soins,
  });

  final FicheJournaliereRepository depot;

  /// ⚠️ REQUIS, PAS OPTIONNEL. Sans lui la section « Traitements &
  /// Prophylaxie » serait masquee en silence — un protocole invisible se
  /// lit comme un protocole vide.
  final SoinsRepository soins;

  @override
  State<FicheLapinsScreen> createState() => _FicheLapinsScreenState();
}

class _FicheLapinsScreenState extends State<FicheLapinsScreen> {
  List<LivestockLot> _bandes = const [];
  LivestockLot? _bande;
  DateTime _jour = DateTime.now();

  /// Indicateurs du mois, en tete de fiche comme dans la maquette.
  ({int effectif, int naissances, double? tauxMortalite})? _indicateurs;

  /// Journées du mois pour la bande choisie — le tableau de bas de fiche.
  List<LivestockDailyEntry> _fichesDuMois = const [];

  /// Protocole du jour pour la bande selectionnee — `null` tant qu'il charge.
  ProtocoleDuJour? _protocole;

  /// Identifiants des traitements coches, en attente de validation.
  final _traitementsCoches = <String>{};
  final _observationsTraitements = TextEditingController();
  bool _validationEnCours = false;

  int _achat = 0;
  int _ne = 0;
  int _vente = 0;

  /// Ticket 15.46 — transferts entre bandes du jour (dérivés, jamais saisis ici) : comptés dans l'effectif.
  int _transfertEntree = 0;
  int _transfertSortie = 0;

  /// F0.96 — libellés et ordre de la fiche web (17/10/2026). Emplacements : Reproducteur = `repro`,
  /// Jeune = `jeune`, Sous-mères = `sevre` (colonnes `mort_*` / `don_*` du serveur).
  static const _repro = 'Reproducteur';
  static const _jeune = 'Jeune';
  static const _sousMeres = 'Sous-mères';
  final _morts = <String, int>{_repro: 0, _jeune: 0, _sousMeres: 0};
  final _dons = <String, int>{_repro: 0, _jeune: 0, _sousMeres: 0};

  /// Sevrage du jour (Sous-mères → Jeune), `passage_sevre_jeune` : seul mouvement qui fait passer les
  /// nés dans la catégorie vendue (Jeune).
  final _sevrage = <String, int>{'Sous-mères → Jeune': 0};

  /// F0.96 — catégories au début du jour (chaîne ou départ déduit du stade) ; null = inconnues.
  EffectifCategories? _veilleCategories;

  /// F0.99 — fiche chargée du jour : ses transferts PAR CATÉGORIE entrent dans le calcul, comme au web
  /// (`calculerJour` du serveur). Ils manquaient à F0.96 : la provende ignorait les transferts du jour.
  LivestockDailyEntry? _ficheDuJour;

  /// Totaux d'une fiche ANCIENNE non ventilée rechargée : la catégorie ne se devine pas (web 15.41).
  int? _mortAncien;
  int? _donAncien;

  int _effectifPrecedent = 0;
  double _poidsTotalPese = 0;
  bool _chargement = true;

  /// Rations normatives descendues du serveur, par stade.
  List<FeedRationStandard> _rations = const [];

  int get _totalMorts => _morts.values.fold(0, (a, b) => a + b);
  int get _totalDons => _dons.values.fold(0, (a, b) => a + b);

  /// Effectif recalculé à chaque frappe, comme le fait la maquette
  /// (`computeEffectifAndFeedLive`) — et par le MÊME point de vérité que
  /// l'enregistrement, pour que l'aperçu ne puisse pas mentir.
  /// Poids moyen constaté, recalculé à chaque frappe comme dans la maquette.
  double? get _poidsMoyen => FicheJournaliereRepository.poidsMoyen(
    poidsTotalG: _poidsTotalPese,
    tailleEchantillon: _effectifFinal,
  );

  int get _effectifFinal => FicheJournaliereRepository.calculerEffectifFinal(
    effectifPrecedent: _effectifPrecedent,
    achat: _achat,
    ne: _ne,
    mort: _totalMorts,
    vente: _vente,
    don: _totalDons,
    transfertEntree: _transfertEntree,
    transfertSortie: _transfertSortie,
  );

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  Future<void> _initialiser() async {
    final toutes = await widget.depot.bandesActives();

    // ⚠️⚠️ **FILTRER SUR L'ESPECE, comme le serveur.** Sans ce filtre, la fiche
    // Lapins listait TOUTES les bandes actives du poste — porcines, avicoles,
    // escargots comprises. L'animalier pouvait alors saisir des morts
    // « Lapereau » sur une bande de porcs : la fiche du jour partait avec le
    // bon `lot_id` et les bonnes quantites, sur la mauvaise espece, sans
    // qu'aucune erreur ne soit levee.
    //
    // ⚠️ AUCUN FILTRE DE STADE ICI : le serveur retient toutes les bandes
    // cunicoles, quel que soit leur stade (`FicheLapins`).
    final bandes = toutes.where((b) => b.speciesCode == 'cuniculture').toList();
    final rations = await widget.depot.rations('cuniculture');
    final indicateurs = await widget.depot.indicateursDuMois(bandes: bandes);
    if (!mounted) return;

    setState(() {
      _bandes = bandes;
      _bande = bandes.isEmpty ? null : bandes.first;
      _rations = rations;
      _indicateurs = indicateurs;
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
    final fiche = await widget.depot.chargerJour(bande.id, _jour);
    final protocole = await widget.soins.protocoleDuJour(
      bande: bande,
      codeEspece: 'cuniculture',
      quand: _jour,
    );
    final mois = await widget.depot.fichesDuMois(bande.id, quand: _jour);
    if (!mounted) return;

    _protocole = protocole;
    // ⚠️ Les cases repartent VIDES a chaque changement de jour ou de bande :
    // conserver un cochage d'un autre jour ferait valider un soin qui n'a pas
    // ete administre.
    _traitementsCoches.clear();
    _observationsTraitements.clear();

    setState(() {
      _effectifPrecedent = precedent;
      _veilleCategories = veilleCategories;
      _ficheDuJour = fiche;
      _fichesDuMois = mois;
      _achat = fiche?.achat ?? 0;
      _ne = fiche?.ne ?? 0;
      _vente = fiche?.vente ?? 0;
      _transfertEntree = fiche?.transfertEntree ?? 0;
      _transfertSortie = fiche?.transfertSortie ?? 0;

      // 🔴→✅ F0.96 — LA VENTILATION EST RELUE DES COLONNES PAR CATÉGORIE. Le poste portait le total
      // relu sur « Reproducteur » : une répartition FABRIQUÉE, renvoyée telle quelle au serveur au
      // prochain enregistrement. Une fiche ancienne non ventilée ne se devine pas : son total est
      // gardé à part et l'enregistrement exige sa ventilation (règle de la fiche web).
      for (final k in _morts.keys) {
        _morts[k] = 0;
      }
      for (final k in _dons.keys) {
        _dons[k] = 0;
      }
      _mortAncien = null;
      _donAncien = null;
      if (fiche != null) {
        if (fiche.mortRepro != null &&
            fiche.mortSevre != null &&
            fiche.mortJeune != null) {
          _morts[_repro] = fiche.mortRepro!;
          _morts[_sousMeres] = fiche.mortSevre!;
          _morts[_jeune] = fiche.mortJeune!;
        } else if (fiche.mort > 0) {
          _mortAncien = fiche.mort;
        }
        if (fiche.donRepro != null &&
            fiche.donSevre != null &&
            fiche.donJeune != null) {
          _dons[_repro] = fiche.donRepro!;
          _dons[_sousMeres] = fiche.donSevre!;
          _dons[_jeune] = fiche.donJeune!;
        } else if (fiche.don > 0) {
          _donAncien = fiche.don;
        }
      }
      _sevrage.updateAll((_, _) => fiche?.passageSevreJeune ?? 0);

      // Le poids TOTAL n'est pas conservé : seul le poids MOYEN l'est
      // (`weight_sample_avg_g` du contrat). On le reconstitue pour que la
      // saisie relue affiche la même chose qu'à l'enregistrement.
      final moyen = fiche?.weightSampleAvgG;
      _poidsTotalPese = moyen == null ? 0 : moyen * (fiche?.effectifFinal ?? 0);

      _chargement = false;
    });
  }

  Future<void> _enregistrer() async {
    final bande = _bande;
    if (bande == null) return;

    // Fiche ancienne non ventilée rechargée : ne pas remettre ses morts / dons à zéro en silence.
    if ((_mortAncien != null && _totalMorts == 0) ||
        (_donAncien != null && _totalDons == 0)) {
      _signalerRefus(
        "Cette fiche porte des morts ou des dons non ventilés par catégorie : ventilez-les "
        "(Reproducteur / Jeune / Sous-mères) avant d'enregistrer.",
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
        poidsMoyen: _poidsMoyen,
        ventilation: VentilationJour(
          mortRepro: _morts[_repro]!,
          mortSevre: _morts[_sousMeres]!,
          mortJeune: _morts[_jeune]!,
          donRepro: _dons[_repro]!,
          donSevre: _dons[_sousMeres]!,
          donJeune: _dons[_jeune]!,
          passage: _sevrage.values.single,
        ),
      );
    } on FicheRefusee catch (e) {
      _signalerRefus(e.motif);
      return;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AgriColors.brandEmerald,
        content: Text(
          'Journée enregistrée sur ce poste — en attente de synchronisation.',
        ),
      ),
    );

    await _chargerJour();
  }

  void _signalerRefus(String motif) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: AgriColors.errorDeep, content: Text(motif)),
    );
  }

  Future<void> _choisirDate() async {
    final choisi = await showDatePicker(
      context: context,
      initialDate: _jour,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (choisi == null) return;
    setState(() => _jour = choisi);
    await _chargerJour();
  }

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
                titre: 'Saisie Journalière du Cheptel — ${_libelleJour()}',
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
                        key: const Key('lapins-non-ventilee'),
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
                      titre: 'Sevrage du jour (Sous-mères → Jeune)',
                      icone: Icons.trending_up,
                      couleur: AgriColors.brandForest,
                      fond: AgriColors.surfaceZebra,
                      valeurs: _sevrage,
                    ),
                    const SizedBox(height: AgriSpacing.md),
                    // ⚠️ ORDRE DE LA MAQUETTE, NON NEGOCIABLE : l'Effectif
                    // Final precede le Rationnement (`fiche-lapins.html`,
                    // l. 272 puis 289). L'inverse deplacait un element
                    // existant — la maquette est la reference de mise en page.
                    _effectif(),
                    const SizedBox(height: AgriSpacing.md),
                    _rationnement(),
                    const SizedBox(height: AgriSpacing.md),
                    _pesee(),
                    const SizedBox(height: AgriSpacing.md),
                    _traitements(),
                    const SizedBox(height: AgriSpacing.md),
                    _attributionCages(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.cruelty_free,
              color: AgriColors.brandEmerald,
              size: 26,
            ),
            const SizedBox(width: AgriSpacing.xs),
            const Expanded(
              child: Text(
                'Fiches Lapins - Cuniculture',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.onSurface,
                ),
              ),
            ),
            if (_bandes.length > 1)
              DropdownButton<String>(
                value: _bande?.id,
                underline: const SizedBox.shrink(),
                items: [
                  for (final b in _bandes)
                    DropdownMenuItem(value: b.id, child: Text(b.code)),
                ],
                onChanged: (id) async {
                  setState(
                    () => _bande = _bandes.firstWhere((b) => b.id == id),
                  );
                  await _chargerJour();
                },
              ),
            const SizedBox(width: AgriSpacing.sm),
            OutlinedButton.icon(
              key: const Key('selecteur-date'),
              onPressed: _choisirDate,
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text(
                '${_jour.day.toString().padLeft(2, '0')}/'
                '${_jour.month.toString().padLeft(2, '0')}/${_jour.year}',
                style: const TextStyle(fontSize: AgriTypography.xs),
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Fiche de suivi mensuel du cheptel — transcription fidèle du registre de la ferme.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    );
  }

  /// « 2. CARTES KPI DYNAMIQUES DU MOIS » — quatre cartes, dans l'ordre et avec
  /// les intitulés de `fiche-lapins.html`.
  ///
  /// ⚠️⚠️ **CE BLOC MANQUAIT ENTIÈREMENT.** La maquette ouvre la fiche par
  /// quatre indicateurs ; cet écran — le premier construit, avant que la règle
  /// de conformité ne soit posée — passait directement au formulaire. Les
  /// quatre fiches suivantes les ont ; celle-ci ne les avait pas.
  ///
  /// ⚠️ **« GÉNITEURS (M/F) » AFFICHE UN TIRET.** Le serveur le tire de
  /// `effectif_m` / `effectif_f`, deux colonnes que le contrat de
  /// synchronisation ne descend pas. Un zéro se lirait « plus aucun géniteur » —
  /// sur une bande de reproduction, c'est un contresens.
  Widget _cartesKpi() {
    final i = _indicateurs;

    return LayoutBuilder(
      builder: (context, contraintes) {
        // Maquette : `grid grid-cols-2 md:grid-cols-4 gap-md`.
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
              valeur: i == null ? '—' : '${i.effectif}',
              icone: Icons.pets,
              couleur: AgriColors.brandEmerald,
            ),
            _carteKpi(
              largeur: largeur,
              libelle: 'Géniteurs (M/F)',
              valeur: '—',
              icone: Icons.favorite,
              couleur: AgriColors.infoBlue,
              note: 'non synchronisé',
            ),
            _carteKpi(
              largeur: largeur,
              libelle: 'Naissances du Mois',
              valeur: i == null ? '—' : '${i.naissances}',
              icone: Icons.child_care,
              couleur: AgriColors.accentYellow,
              couleurIcone: AgriColors.brandForest,
            ),
            _carteKpi(
              largeur: largeur,
              libelle: 'Taux de Mortalité',
              valeur: i?.tauxMortalite == null
                  ? '—'
                  : '${i!.tauxMortalite!.toStringAsFixed(1)}%',
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
    String? note,
  }) => SizedBox(
    width: largeur,
    child: CarteKpi(
      libelle: libelle,
      valeur: valeur,
      legende: note,
      icone: icone,
      couleurLisere: couleur,
      couleurIcone: couleurIcone ?? AgriColors.brandEmerald,
    ),
  );

  /// Tableau mensuel — `fiche-lapins.html`, bas de page.
  ///
  /// Colonnes de la maquette, dans son ordre : Date · **Entrées** (Achat, Né) ·
  /// **Sorties** (Mort, Vente, Don) · **Effectif Final du Jour** (M, F, Jeunes,
  /// S/Mères, Total) · Taux Mort % · Poids Général (g) · Traitements &
  /// Prophylaxie.
  ///
  /// 🔁 TICKET F0.92 — « Sevrés » devient « Jeunes » (décision client du
  /// 14/10/2026, serveur 15.36), distinct de « S/Mères ». ÉCART ASSUMÉ : la
  /// maquette dit encore « Sevrés ». La colonne serveur reste
  /// `effectif_sevres` (contrat de synchronisation, jamais renommé).
  ///
  /// ⚠️⚠️ **M / F / JEUNES / S/MÈRES AFFICHENT UN TIRET.** Le serveur les tient
  /// dans `effectif_m`, `effectif_f`, `effectif_sevres` et `effectif_smeres` ;
  /// le contrat de synchronisation ne descend aucune de ces quatre colonnes.
  /// Un zéro se lirait « plus aucun reproducteur » — les colonnes restent à leur
  /// place, vides et honnêtes.
  Widget _tableauMensuel() {
    if (_bande == null) return const SizedBox.shrink();

    String? valeur(int i, int? Function(LivestockDailyEntry f) lecture) {
      final v = lecture(_fichesDuMois[i]);
      return v?.toString();
    }

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
              valeur: (i) => valeur(i, (f) => f.achat) ?? '—',
            ),
            ColonneMensuelle(
              libelle: 'Né',
              valeur: (i) => valeur(i, (f) => f.ne) ?? '—',
            ),
          ],
        ),
        GroupeColonnes(
          libelle: 'Sorties',
          colonnes: [
            ColonneMensuelle(
              libelle: 'Mort',
              valeur: (i) => valeur(i, (f) => f.mort) ?? '—',
            ),
            ColonneMensuelle(
              libelle: 'Vente',
              valeur: (i) => valeur(i, (f) => f.vente) ?? '—',
            ),
            ColonneMensuelle(
              libelle: 'Don',
              valeur: (i) => valeur(i, (f) => f.don) ?? '—',
            ),
          ],
        ),
        GroupeColonnes(
          libelle: 'Effectif Final du Jour',
          colonnes:
              [
                // 🔁 15.57 — colonnes synchronisées (`effectif_m/f/sevres/smeres`), comme le web.
                ColonneMensuelle(libelle: 'M', valeur: (i) => _fichesDuMois[i].effectifM?.toString() ?? '—'),
                ColonneMensuelle(libelle: 'F', valeur: (i) => _fichesDuMois[i].effectifF?.toString() ?? '—'),
                ColonneMensuelle(libelle: 'Jeunes', valeur: (i) => _fichesDuMois[i].effectifSevres?.toString() ?? '—'),
                ColonneMensuelle(libelle: 'S/Mères', valeur: (i) => _fichesDuMois[i].effectifSmeres?.toString() ?? '—'),
              ] +
              [
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
          valeur: (i) {
            final f = _fichesDuMois[i];
            final depart =
                f.effectifFinal + f.mort + f.vente + f.don - f.achat - f.ne;
            if (depart <= 0) return '—';
            return '${((f.mort / depart) * 100).toStringAsFixed(1)} %';
          },
        ),
        ColonneMensuelle(
          libelle: 'Poids Général (g)',
          largeur: 1.4,
          valeur: (i) {
            final moyenne = _fichesDuMois[i].weightSampleAvgG;
            final effectif = _fichesDuMois[i].effectifFinal;
            // ⚠️ La colonne annonce un TOTAL pesé ; la base porte la MOYENNE.
            if (moyenne == null || moyenne <= 0 || effectif <= 0) return '—';
            return '${(moyenne * effectif).round()}';
          },
        ),
        ColonneMensuelle(
          libelle: 'Traitements & Prophylaxie',
          largeur: 2.2,
          // ⚠️ Le registre vétérinaire est une AUTRE table : le rattacher jour
          // par jour ici demanderait une requête par ligne. Signalé plutôt
          // qu'approximé.
          valeur: (_) => '—',
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
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(AgriSpacing.lg),
        child: Column(
          children: [
            Icon(Icons.inbox, size: 44, color: AgriColors.outlineVariant),
            SizedBox(height: AgriSpacing.sm),
            Text(
              'Aucune bande sur ce poste.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: AgriSpacing.xs),
            // Les bandes sont un RÉFÉRENTIEL : elles descendent du serveur et
            // ne se créent pas ici. Le dire évite de chercher un bouton
            // « Nouvelle bande » qui n'existera jamais sur cet écran.
            Text(
              'Les bandes proviennent du serveur : lancez une synchronisation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
          ],
        ),
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
      children: [
        Expanded(
          child: _champNombre(
            libelle: 'Achats du jour',
            valeur: _achat,
            cle: 'achat',
            onChange: (v) => setState(() => _achat = v),
          ),
        ),
        const SizedBox(width: AgriSpacing.md),
        Expanded(
          child: _champNombre(
            libelle: 'Nés (Mise bas)',
            valeur: _ne,
            cle: 'ne',
            onChange: (v) => setState(() => _ne = v),
          ),
        ),
        const SizedBox(width: AgriSpacing.md),
        Expanded(
          child: _champNombre(
            libelle: 'Ventes (POS)',
            valeur: _vente,
            cle: 'vente',
            // ⚠️ Lecture seule : la valeur vient de la caisse.
            onChange: null,
          ),
        ),
      ],
    );
  }

  Widget _champNombre({
    required String libelle,
    required int valeur,
    required String cle,
    required void Function(int)? onChange,
  }) {
    final lectureSeule = onChange == null;

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
        const SizedBox(height: AgriSpacing.xs),
        TextFormField(
          key: Key('champ-$cle-$valeur'),
          initialValue: valeur.toString(),
          readOnly: lectureSeule,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: lectureSeule
                ? AgriColors.surfaceZebra
                : AgriColors.surfaceCard,
            helperText: lectureSeule ? 'Alimenté par la caisse' : null,
            helperStyle: const TextStyle(fontSize: 9),
          ),
          onChanged: (v) => onChange?.call(int.tryParse(v) ?? 0),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: AgriSpacing.sm),
          Row(
            children: [
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
        const SizedBox(height: AgriSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _pas(categorie, valeurs, -1, '−'),
              Text(
                '${valeurs[categorie]}',
                key: Key('valeur-${categorie.hashCode}'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _pas(categorie, valeurs, 1, '+'),
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
  ) {
    return InkWell(
      key: Key('pas-${categorie.hashCode}-$pas'),
      onTap: () => setState(() {
        // ⚠️ Plancher à zéro : un nombre de morts négatif gonflerait
        // l'effectif final au lieu de le réduire.
        valeurs[categorie] = (valeurs[categorie]! + pas).clamp(0, 999999);
      }),
      child: Container(
        width: 32,
        height: 36,
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

  /// « Rationnement & Provende Servie par Catégorie (en Grammes g/j) ».
  ///
  /// 🔁 TICKET F0.96 — GLOSSAIRE du 17/10/2026 (serveur 15.44) : trois lignes FIXES, dans l'ordre du
  /// web — Reproducteur · Jeune (60 g) · Sous-mères (30 g) — et colonne « Catégorie ». ÉCART ASSUMÉ vis-à-vis de la maquette, qui dit
  /// encore « Espèce », « Lapereau » et « par Espèces » (verrouillé par
  /// `test/fiche_lapins_glossaire_test.dart`).
  ///
  /// ⚠️⚠️ **RAPPROCHEMENT PAR CLÉ STABLE** (`CategorieRationLapin`), jamais
  /// par sous-chaîne du libellé : le barème peut porter les anciens OU les
  /// nouveaux libellés ; renommer une ligne ne change ni la ration ni le
  /// total affichés. Une catégorie absente du barème prend la valeur de
  /// secours du serveur (120 / 30 / 60), exactement comme le web.
  ///
  /// ⚠️ LES GRAMMAGES VIENNENT DU RÉFÉRENTIEL SYNCHRONISÉ : un barème
  /// entièrement absent (poste jamais synchronisé) affiche « Rationnement
  /// indisponible » plutôt que trois valeurs de secours.
  ///
  /// 🔁 F0.96 — L'EFFECTIF PAR CATÉGORIE EST CALCULÉ comme sur le web : veille de la chaîne (ou départ
  /// déduit du stade) + mouvements saisis. Une catégorie inconnue affiche « — » (effectif ET provende),
  /// JAMAIS « 0 » : un zéro se lirait « aucun reproducteur nourri ».
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
          "Rationnement indisponible : les rations normatives descendent du "
          "serveur. Lancez une synchronisation.",
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      );
    }

    // F0.96 — effectifs PAR CATÉGORIE du jour, calculés comme sur le web (`categoriesJour`) : veille de
    // la chaîne (ou départ déduit du stade) + mouvements saisis à l'écran. Inconnue = « — », jamais 0.
    final veille = _veilleCategories;
    final jourCalcule = veille == null
        ? null
        : EffectifParCategorie.calculerJour(
            EffectifParCategorie.lapins,
            veille,
            MouvementsJour(
              achat: _achat,
              ne: _ne,
              vente: _vente,
              mortRepro: _morts[_repro],
              mortSevre: _morts[_sousMeres],
              mortJeune: _morts[_jeune],
              donRepro: _dons[_repro],
              donSevre: _dons[_sousMeres],
              donJeune: _dons[_jeune],
              passage: _sevrage.values.single,
              transfertEntreeRepro: _ficheDuJour?.transfertEntreeRepro ?? 0,
              transfertEntreeSevre: _ficheDuJour?.transfertEntreeSevre ?? 0,
              transfertEntreeJeune: _ficheDuJour?.transfertEntreeJeune ?? 0,
              transfertSortieRepro: _ficheDuJour?.transfertSortieRepro ?? 0,
              transfertSortieSevre: _ficheDuJour?.transfertSortieSevre ?? 0,
              transfertSortieJeune: _ficheDuJour?.transfertSortieJeune ?? 0,
            ),
          );
    int? effectifDe(String cle) => switch (cle) {
      CategorieRationLapin.reproducteur => jourCalcule?.repro,
      CategorieRationLapin.sousMeres => jourCalcule?.sevre,
      _ => jourCalcule?.jeune,
    };
    double? totalGrammes;

    final lignes = <TableRow>[];

    for (final cle in CategorieRationLapin.ordre) {
      final ration = CategorieRationLapin.ration(_rations, cle);
      final effectif = effectifDe(cle);
      final connue = effectif != null;

      final grammes = connue
          ? FicheJournaliereRepository.provendeGrammes(
              effectif: effectif,
              rationGParJour: ration,
            )
          : null;
      if (grammes != null) totalGrammes = (totalGrammes ?? 0) + grammes;

      lignes.add(
        TableRow(
          children: [
            _celluleTexte(
              CategorieRationLapin.libelles[cle]!,
              gras: true,
              cle: 'ration-libelle-$cle',
            ),
            _celluleTexte(
              connue ? '$effectif' : '—',
              centre: true,
              cle: 'ration-effectif-$cle',
            ),
            _celluleTexte(
              '${_sansDecimaleInutile(ration)} g/j',
              centre: true,
              cle: 'ration-g-$cle',
            ),
            _celluleTexte(
              grammes == null ? '—' : '${_sansDecimaleInutile(grammes)} g',
              droite: true,
              couleur: AgriColors.brandEmerald,
              gras: true,
              cle: 'ration-grammes-$cle',
            ),
          ],
        ),
      );
    }
    final total = totalGrammes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.restaurant, size: 16, color: AgriColors.brandEmerald),
            SizedBox(width: AgriSpacing.xs),
            Expanded(
              child: Text(
                'RATIONNEMENT & PROVENDE SERVIE PAR CATÉGORIE (EN GRAMMES G/J)',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.brandForest,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Column(
            children: [
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1.4),
                  3: FlexColumnWidth(1.6),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(
                      color: AgriColors.surfaceZebra,
                    ),
                    children: [
                      _celluleTexte('Catégorie', entete: true),
                      _celluleTexte('Effectif', entete: true, centre: true),
                      _celluleTexte(
                        'Ration Normative',
                        entete: true,
                        centre: true,
                      ),
                      _celluleTexte(
                        'Provende Servie (g)',
                        entete: true,
                        droite: true,
                      ),
                    ],
                  ),
                  ...lignes,
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AgriColors.brandEmerald.withValues(alpha: 0.1),
                  border: const Border(
                    top: BorderSide(color: AgriColors.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AgriColors.brandForest,
                        ),
                      ),
                    ),
                    Text(
                      // Le total est converti UNE SEULE FOIS, à la fin :
                      // convertir chaque ligne accumulerait les arrondis.
                      // « — » quand aucune ligne ne porte l'effectif : le
                      // poste ne sait pas, ce n'est pas « 0 g servi ».
                      total == null
                          ? '—'
                          : '${_sansDecimaleInutile(total)} g '
                                '(${(total / 1000).toStringAsFixed(1)} Kg)',
                      key: const Key('total-provende'),
                      style: const TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                        color: AgriColors.brandEmerald,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _celluleTexte(
    String valeur, {
    bool entete = false,
    bool centre = false,
    bool droite = false,
    bool gras = false,
    Color? couleur,
    String? cle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.md,
        vertical: AgriSpacing.xs,
      ),
      child: Text(
        valeur,
        key: cle == null ? null : Key(cle),
        textAlign: droite
            ? TextAlign.right
            : (centre ? TextAlign.center : TextAlign.left),
        style: TextStyle(
          fontSize: entete ? 10 : 12,
          fontWeight: (entete || gras) ? FontWeight.bold : FontWeight.normal,
          color:
              couleur ?? (entete ? AgriColors.outline : AgriColors.brandForest),
        ),
      ),
    );
  }

  /// « 120 » plutôt que « 120.0 » : la maquette affiche des grammages entiers.
  static String _sansDecimaleInutile(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// « PESÉE & POIDS MOYEN CONSTATÉ » — trois champs de la maquette :
  /// poids général pesé (saisi), taille d'échantillon (verrouillée, « Auto =
  /// Effectif Final ») et poids moyen constaté (calculé).
  ///
  /// ⚠️ LA TAILLE D'ÉCHANTILLON SUIT L'EFFECTIF FINAL EN DIRECT : saisir un
  /// mort change le diviseur, donc le poids moyen. Le figer ferait diverger
  /// l'affichage du calcul réellement enregistré.
  Widget _pesee() {
    final moyen = _poidsMoyen;

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AgriColors.outlineVariant)),
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
                const SizedBox(height: AgriSpacing.xs),
                TextFormField(
                  key: Key('champ-pesee-${_poidsTotalPese.round()}'),
                  initialValue: _poidsTotalPese > 0
                      ? _poidsTotalPese.round().toString()
                      : '',
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(hintText: 'ex : 3500'),
                  onChanged: (v) =>
                      setState(() => _poidsTotalPese = double.tryParse(v) ?? 0),
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
                  "TAILLE ÉCHANTILLON",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const SizedBox(height: AgriSpacing.xs),
                Container(
                  height: 48,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AgriSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: AgriColors.surfaceZebra,
                    border: Border.all(color: AgriColors.outlineVariant),
                    borderRadius: BorderRadius.circular(AgriRadius.lg),
                  ),
                  child: Text(
                    '$_effectifFinal',
                    key: const Key('taille-echantillon'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ),
                const Text(
                  'Auto = Effectif Final',
                  style: TextStyle(fontSize: 9, color: AgriColors.outline),
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
                  'POIDS MOYEN CONSTATÉ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const SizedBox(height: AgriSpacing.xs),
                Container(
                  height: 48,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AgriSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: AgriColors.surfaceZebra,
                    border: Border.all(color: AgriColors.outlineVariant),
                    borderRadius: BorderRadius.circular(AgriRadius.lg),
                  ),
                  child: Text(
                    // ⚠️ « — » et non « 0 g » quand rien n'est pesé : un zéro
                    // se lirait comme un cheptel sans poids alors qu'il s'agit
                    // d'une absence de mesure.
                    moyen == null ? '—' : '${moyen.round()} g',
                    key: const Key('poids-moyen'),
                    style: const TextStyle(
                      fontSize: 14,
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

  Widget _effectif() {
    final taux = FicheJournaliereRepository.tauxMortalite(
      effectifPrecedent: _effectifPrecedent,
      mort: _totalMorts,
    );

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
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
          const SizedBox(height: AgriSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$_effectifFinal',
                key: const Key('effectif-final'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AgriColors.brandEmerald,
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Text(
                'départ $_effectifPrecedent'
                '${taux == null ? '' : ' · mortalité ${taux.toStringAsFixed(1)} %'}',
                style: const TextStyle(fontSize: 11, color: AgriColors.outline),
              ),
            ],
          ),
          if (_effectifFinal < 0) ...[
            const SizedBox(height: AgriSpacing.xs),
            // ⚠️ Signalé, jamais bloqué ni corrigé en douce : un effectif
            // négatif révèle une saisie incohérente que seul l'éleveur peut
            // trancher — le forcer à zéro masquerait l'erreur.
            const Text(
              'Effectif négatif : vérifiez les sorties saisies.',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AgriColors.errorDeep,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  Traitements & Prophylaxie — `fiche-lapins.html`, lignes 363-378 et
  //  `renderProphylaxieMultiList()`.
  // ══════════════════════════════════════════════════════════════════════

  /// Libelle de l'etat, tel que la maquette le formule.
  ///
  /// ⚠️ TROIS ETATS DANS LA MAQUETTE, UN QUATRIEME ICI. « Libre », « Prevus »
  /// et « Valide / Effectue » supposent tous que le jour du cycle est connu.
  /// Le poste peut aussi etre dans l'incapacite de le calculer — le presenter
  /// comme « Libre » ferait passer une inconnue pour une absence de soin.
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
        borderRadius: BorderRadius.circular(8),
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
                  'Traitements & Prophylaxie Automatiques Prévus pour ce Jour',
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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AgriSpacing.sm),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            if (!protocole.determinable)
              _avertissementIndetermine(protocole)
            else if (protocole.traitements.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AgriSpacing.sm),
                child: Text(
                  '— Aucun traitement récurrent programmé pour ce jour —',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
              )
            else
              ...protocole.traitements.map(_ligneTraitement),
            if (protocole.calendairesNonEvalues > 0)
              _noteCalendaires(protocole),
            const SizedBox(height: AgriSpacing.sm),
            _observations(),
            const SizedBox(height: AgriSpacing.sm),
            if (protocole.determinable && protocole.enAttente > 0)
              _boutonValiderTraitements(),
            _indicateurEnAttente(protocole),
          ],
        ],
      ),
    );
  }

  /// ⚠️ LE MOTIF EST AFFICHE TEL QUEL, pas remplace par une liste vide.
  Widget _avertissementIndetermine(ProtocoleDuJour protocole) {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.errorBg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.help_outline, size: 15, color: AgriColors.errorDeep),
          const SizedBox(width: AgriSpacing.xs),
          Expanded(
            child: Text(
              'Protocole non calculable au poste — '
              '${protocole.motifIndetermine ?? ''} '
              'Consultez le serveur avant toute administration.',
              style: const TextStyle(
                fontSize: 10.5,
                color: AgriColors.errorDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ⚠️ COMPTEES ET DITES, JAMAIS MASQUEES : les taire laisserait croire a un
  /// protocole integralement couvert par l'ecran.
  Widget _noteCalendaires(ProtocoleDuJour protocole) {
    final n = protocole.calendairesNonEvalues;

    return Padding(
      padding: const EdgeInsets.only(top: AgriSpacing.xs),
      child: Text(
        '$n entrée(s) du protocole suivent le calendrier (ex. « le 1er du '
        'mois ») et ne sont pas évaluées ici.',
        style: const TextStyle(fontSize: 10, color: AgriColors.outline),
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
              // ⚠️ UN SOIN DEJA ENREGISTRE NE SE DECOCHE PAS : la case reflete
              // le registre, elle ne le commande pas a rebours.
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

  Widget _observations() {
    return TextField(
      controller: _observationsTraitements,
      maxLines: 2,
      style: const TextStyle(fontSize: AgriTypography.xs),
      decoration: const InputDecoration(
        labelText: 'Observations / Notes Additionnelles de l\'Animalier',
        hintText: 'ex : RAS, légère perte d\'appétit cage C3...',
        hintStyle: TextStyle(fontSize: 11),
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _boutonValiderTraitements() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ⚠️ LA CONSEQUENCE EST DITE AVANT LE CLIC, pas apres : valider un
        // traitement remanent BLOQUE la vente de cette bande, y compris a la
        // caisse de ce poste, jusqu'a la fin du delai d'attente.
        const Text(
          'Valider un traitement rémanent bloque la vente de cette bande '
          'jusqu\'à la fin du délai d\'attente.',
          style: TextStyle(fontSize: 10, color: AgriColors.errorDeep),
        ),
        const SizedBox(height: AgriSpacing.xs),
        FilledButton.icon(
          onPressed: _traitementsCoches.isEmpty || _validationEnCours
              ? null
              : _validerTraitements,
          icon: const Icon(Icons.check_circle_outline, size: 16),
          label: const Text(
            'Valider l\'Administration de tous ces Traitements Aujourd\'hui',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  /// « Indice Rouge » de la maquette : le compte des soins non administres.
  Widget _indicateurEnAttente(ProtocoleDuJour protocole) {
    final n = protocole.enAttente;

    return Padding(
      padding: const EdgeInsets.only(top: AgriSpacing.xs),
      child: Row(
        children: [
          Icon(
            n > 0 ? Icons.error_outline : Icons.check_circle_outline,
            size: 13,
            color: n > 0 ? AgriColors.errorDeep : AgriColors.brandEmerald,
          ),
          const SizedBox(width: 4),
          Text(
            'Indice Rouge : $n soin(s) en attente',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: n > 0 ? AgriColors.errorDeep : AgriColors.brandEmerald,
            ),
          ),
        ],
      ),
    );
  }

  /// Enregistre un soin reel par traitement coche.
  ///
  /// ⚠️ **CE N'EST PAS UNE CASE A COCHER DECORATIVE.** Chaque validation ecrit
  /// un enregistrement au registre veterinaire ET, si le traitement porte un
  /// delai d'attente, la periode de remanence qui bloque la caisse. Une case
  /// qui ne ferait que changer de couleur laisserait vendre une bande traitee.
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
      codeEspece: 'cuniculture',
      quand: _jour,
      idsBareme: Set.of(_traitementsCoches),
      observations: _observationsTraitements.text,
    );

    if (!mounted) return;
    setState(() => _validationEnCours = false);

    // Rechargement : l'etat affiche vient du registre, jamais d'une supposition
    // locale sur ce qui vient d'etre ecrit.
    await _chargerJour();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Traitements enregistrés au registre.')),
    );
  }

  /// « Attribution Cages & Bandes Traitées (Cochées par défaut) » —
  /// `fiche-lapins.html`, l. 396-420.
  ///
  /// ⚠️⚠️ **LA SECTION EXISTE, SON RÉFÉRENTIEL N'EXISTE NULLE PART.** La
  /// maquette liste quatre cages en dur (« Cage C1 (Bande B1) »…) ; il n'y a
  /// **aucune table `cages`** côté serveur, et le Blade Laravel omet la section
  /// entièrement — omission silencieuse jamais signalée jusqu'ici.
  ///
  /// Le conteneur est donc rendu **à sa place et dans sa forme**, et son
  /// contenu dit la vérité. Recopier les quatre cages de la maquette
  /// inventerait un référentiel : l'animalier cocherait des cages qui
  /// n'existent pas, et rien ne serait enregistré.
  Widget _attributionCages() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.grid_view,
                size: 18,
                color: AgriColors.brandEmerald,
              ),
              const SizedBox(width: AgriSpacing.xs),
              const Expanded(
                child: Text(
                  'Attribution Cages & Bandes Traitées (Cochées par défaut)',
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
          const Text(
            "Aucun référentiel de cages n'existe encore : ni le serveur ni le "
            "poste n'en tiennent la liste. La section reste à sa place, vide, "
            "en attendant l'arbitrage du client.",
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

  /// « Réinitialiser » + « Enregistrer ce Jour », alignés à droite —
  /// `fiche-lapins.html`, l. 422-427.
  ///
  /// ⚠️ LIBELLÉS REPRIS MOT POUR MOT. « Enregistrer la journée » était une
  /// reformulation : la maquette écrit « Enregistrer ce Jour ».
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

  /// `resetCurrentDayForm()` de la maquette : remet le FORMULAIRE à zéro.
  ///
  /// ⚠️ NE SUPPRIME RIEN EN BASE. La maquette vide les champs saisis ; effacer
  /// la fiche déjà enregistrée serait une suppression physique — interdite sur
  /// un enregistrement zootechnique.
  void _reinitialiserJour() {
    setState(() {
      _achat = 0;
      _ne = 0;
      for (final cle in _morts.keys) {
        _morts[cle] = 0;
      }
      for (final cle in _dons.keys) {
        _dons[cle] = 0;
      }
      _sevrage.updateAll((_, _) => 0);
    });
  }
}
