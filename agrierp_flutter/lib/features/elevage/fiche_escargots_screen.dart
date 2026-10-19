import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/export/document_officiel.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/tableau_mensuel.dart';
import '../../core/widgets/toast_agri.dart';
import '../stocks/journal_stocks.dart';
import '../stocks/pmp_service.dart';
import 'elements_fiche.dart';
import 'fiche_journaliere_repository.dart';
import 'mois_fiche.dart';
import 'soins_repository.dart';

/// `fiche-escargots.blade.php` (web, `FicheEscargots`) → Fiches Escargots - Héliciculture.
///
/// 🔴→✅ **TICKET U12a — LE BLADE EST LA RÉFÉRENCE DE MISE EN PAGE** (doctrine, article 5), et non plus la maquette
/// `fiche-escargots.html`. Sections du Blade, dans son ordre, libellés au mot près :
///   0. module Héliciculture éteint (`modules_config`) : la carte « Module Héliciculture non activé » seule ;
///   1. en-tête, sous-titre, « Exporter PDF » ; 2. quatre cartes du MOIS (`getKpisProperty()`) ;
///   3. sans bande : « Aucune bande active en héliciculture pour le moment. » ;
///   4. carte « Saisie Journalière du Cheptel » (« Bande : », « Date : ») : transferts du jour ; Achats du jour ·
///      Ventes (POS, réel) ; **Workflow Ponte en Terre & Éclosion des Naissains** ; Morts par catégorie ; Dons par
///      catégorie ; Naissains · Engraissement · Bordés ; effectif final et taux de mortalité ; « Rationnement Farine
///      Calcique & Fourrage » (en attente : aucun barème) ; pesée ; « Entretien & Hygrométrie » (en attente) et
///      « Observations » ; « Enregistrer ce Jour » ;
///   5. le tableau du mois (TOUS les jours, « Traitements & Prophylaxie » du registre).
///
/// Retirés avec la maquette : le second champ « Naissains Nés » de la ligne des entrées, « Soins, Hygrométrie &
/// Entretien du Substrat » et son protocole du jour (le Blade n'a pas `x-prophylaxie-du-jour` ici), « Attribution
/// Parcs & Fosses en Terre Traités », « Réinitialiser », le « Jour N » du titre et des lignes du tableau.
///
/// ⚠️ **CORRESPONDANCE DES COLONNES, REPRISE DU SERVEUR** : `ponte_total` porte les œufs pondus en terre, `ne` les
/// naissains nés ; `effectif_m` Naissains, `effectif_f` Engraissement, `effectif_sevres` Bordés. Cette fiche
/// n'alimente aucun stock d'œufs (ticket 14.59).
class FicheEscargotsScreen extends StatefulWidget {
  const FicheEscargotsScreen({
    super.key,
    required this.depot,
    required this.soins,
    this.imprimer,
    this.onOuvrirTransferts,
    this.onRetourGestion,
    this.maintenant,
  });

  final FicheJournaliereRepository depot;

  /// Gardé pour la signature commune des fiches : le Blade des escargots n'a pas de protocole du jour.
  final SoinsRepository soins;

  /// « Exporter PDF » — `EditeursRapports.imprimer` en production, un espion en test ; `null` : bouton inerte.
  final Future<String?> Function(DocumentOfficiel document, DateTime maintenant)? imprimer;
  final VoidCallback? onOuvrirTransferts;

  /// « ← Retour à Gestion Élevage » de la carte « Module Héliciculture non activé ».
  final VoidCallback? onRetourGestion;

  /// Horloge injectable : le mois du tableau et des cartes est celui de MAINTENANT (`now()` du web).
  final DateTime Function()? maintenant;

  @override
  State<FicheEscargotsScreen> createState() => _FicheEscargotsScreenState();
}

class _FicheEscargotsScreenState extends State<FicheEscargotsScreen> {
  /// Catégories des morts et des dons du Blade (15.56), dans son ordre.
  static const _categories = [
    ('borde', 'Reproducteur (Bordé)'),
    ('engraissement', 'Engraissement'),
    ('naissain', 'Naissain'),
  ];

  bool? _moduleActif;
  List<LivestockLot> _bandes = const [];
  LivestockLot? _bande;
  late DateTime _jour;
  bool _chargement = true;
  DonneesMoisFiche? _mois;

  int _precedent = 0;
  LivestockDailyEntry? _fiche;
  int _achat = 0;
  int _oeufsTerre = 0;
  int _naissainsNes = 0;
  final _morts = <String, int>{for (final (c, _) in _categories) c: 0};
  final _dons = <String, int>{for (final (c, _) in _categories) c: 0};
  int? _mortEnregistre;
  int? _donEnregistre;
  int _effectifNaissains = 0;
  int _effectifEngraissement = 0;
  int _effectifBordes = 0;
  double? _pesee;
  final _observations = TextEditingController();

  // S-T11 : le jour métier est celui du Bénin, quel que soit le réglage de Windows.
  DateTime get _maintenant => (widget.maintenant ?? HeureBenin.maintenant)();

  @override
  void initState() {
    super.initState();
    final m = _maintenant;
    _jour = DateTime(m.year, m.month, m.day);
    _initialiser();
  }

  @override
  void dispose() {
    _observations.dispose();
    super.dispose();
  }

  Future<void> _initialiser() async {
    final db = widget.depot.database;
    // `ModuleConfig::isEnabled('helico')` : une ligne ABSENTE vaut « éteint », comme au web.
    final module = await (db.select(db.modulesConfig)
          ..where((t) => t.speciesCode.equals('helico'))
          ..limit(1))
        .getSingleOrNull();
    final actif = module?.isEnabled ?? false;
    final bandes = MoisFiche.bandesDe(EspeceFiche.escargots, await widget.depot.bandesActives(), helicoActif: actif);
    if (!mounted) return;
    setState(() {
      _moduleActif = actif;
      _bandes = bandes;
      _bande = bandes.isEmpty ? null : bandes.first;
    });
    await _chargerJour();
  }

  /// `loadDay()` : la fiche de LA bande à CETTE date, quel que soit le mois (🔴→✅ U12a, corrigé aussi au web) ; les
  /// morts et dons enregistrés, dont la répartition n'est pas stockée, gardés en total.
  Future<void> _chargerJour() async {
    final bande = _bande;
    final mois = await MoisFiche.charger(
      widget.depot.database,
      espece: EspeceFiche.escargots,
      bandes: _bandes,
      bande: bande,
      maintenant: _maintenant,
    );
    final precedent = bande == null ? 0 : await widget.depot.effectifPrecedent(bande.id, _jour);
    final fiche = bande == null ? null : await widget.depot.chargerJour(bande.id, _jour);
    if (!mounted) return;
    setState(() {
      _mois = mois;
      _precedent = precedent;
      _fiche = fiche;
      _morts.updateAll((_, _) => 0);
      _dons.updateAll((_, _) => 0);
      _mortEnregistre = (fiche?.mort ?? 0) > 0 ? fiche!.mort : null;
      _donEnregistre = (fiche?.don ?? 0) > 0 ? fiche!.don : null;
      _achat = fiche?.achat ?? 0;
      _oeufsTerre = fiche?.ponteTotal ?? 0;
      _naissainsNes = fiche?.ne ?? 0;
      _effectifNaissains = fiche?.effectifM ?? 0;
      _effectifEngraissement = fiche?.effectifF ?? 0;
      _effectifBordes = fiche?.effectifSevres ?? 0;
      // Le TOTAL pesé se reconstitue depuis la moyenne stockée.
      final moyenne = fiche?.weightSampleAvgG;
      _pesee = fiche == null || moyenne == null || moyenne == 0 || fiche.effectifFinal <= 0
          ? null
          : (moyenne * fiche.effectifFinal).roundToDouble();
      _chargement = false;
    });
  }

  // ── Calculs, ceux du composant web ────────────────────────────────────────

  int get _vente => _fiche?.vente ?? 0;

  /// `mortDuJour()` : la répartition saisie, sinon le total déjà enregistré.
  int get _totalMorts {
    final saisis = _morts.values.fold(0, (a, b) => a + b);
    return saisis > 0 ? saisis : (_mortEnregistre ?? 0);
  }

  /// `donDuJour()` (15.56) : la répartition saisie, sinon le total déjà enregistré.
  int get _totalDons {
    final saisis = _dons.values.fold(0, (a, b) => a + b);
    return saisis > 0 ? saisis : (_donEnregistre ?? 0);
  }

  int get _effectifFinal => FicheJournaliereRepository.calculerEffectifFinal(
    effectifPrecedent: _precedent,
    achat: _achat,
    ne: _naissainsNes,
    mort: _totalMorts,
    vente: _vente,
    don: _totalDons,
    transfertEntree: _fiche?.transfertEntree ?? 0,
    transfertSortie: _fiche?.transfertSortie ?? 0,
  ).clamp(0, 1 << 30);

  double get _tauxMortalite => _precedent > 0 ? PmpService.arrondi(_totalMorts / _precedent * 100, 1) : 0;

  /// `getEclosionRateCalcProperty()` : 0,0 % sans œuf pondu (règle du taux DU JOUR, 14.61).
  double get _tauxEclosion => _oeufsTerre > 0 ? PmpService.arrondi(_naissainsNes / _oeufsTerre * 100, 1) : 0;

  static String _pourcent(double x) => '${PmpService.nombre(x, 1)} %';

  // ── Rendu ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);
    final k = _mois?.indicateurs;
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
        child: _moduleActif == false
            ? _moduleNonActive()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EnTeteFiche(
                    icone: SymbolesAgri.bug_report,
                    titre: 'Fiches Escargots - Héliciculture',
                    sousTitre:
                        "Suivi mensuel du cheptel d'escargots — ponte en terre, éclosion des naissains et engraissement.",
                    onExporter: widget.imprimer == null || _mois == null ? null : _exporter,
                  ),
                  const SizedBox(height: AgriSpacing.lg),
                  CartesFiche(
                    cartes: [
                      CarteFiche('Effectif Total Vivant', k?[0] ?? '—', SymbolesAgri.bug_report, CarteFiche.emerald),
                      CarteFiche('Naissains Nés (mois)', k?[1] ?? '—', SymbolesAgri.child_care, CarteFiche.blue),
                      CarteFiche("Taux d'Éclosion Naissains", k?[2] ?? '—', SymbolesAgri.egg_alt, CarteFiche.maize),
                      CarteFiche('Taux de Mortalité', k?[3] ?? '—', SymbolesAgri.trending_down, CarteFiche.red),
                    ],
                  ),
                  const SizedBox(height: AgriSpacing.lg),
                  if (_bande == null && !_chargement)
                    const AucuneBandeFiche(message: 'Aucune bande active en héliciculture pour le moment.')
                  else if (_bande != null) ...[
                    _carteSaisie(),
                    const SizedBox(height: AgriSpacing.lg),
                    // `hidden lg:block` : le tableau du mois n'existe qu'à partir de 1 024 px, comme au web.
                    if (large) _tableauMensuel(),
                  ],
                ],
              ),
      ),
    );
  }

  /// `@if(!$moduleEnabled)` : la carte du Blade (cadenas, titre, texte, lien de retour).
  Widget _moduleNonActive() => Center(
    child: Container(
      key: const Key('module-helico-inactif'),
      constraints: const BoxConstraints(maxWidth: 512),
      margin: const EdgeInsets.only(top: AgriSpacing.xl),
      padding: const EdgeInsets.all(AgriSpacing.xl),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        children: [
          const Icon(SymbolesAgri.lock, size: 56, color: AgriColors.outlineVariant),
          const SizedBox(height: AgriSpacing.md),
          const Text(
            'Module Héliciculture non activé',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AgriTypography.lg, fontWeight: AgriTypography.gras, color: AgriColors.onSurface),
          ),
          const SizedBox(height: AgriSpacing.xs),
          const Text(
            "Ce module est disponible mais désactivé par défaut. Un administrateur peut l'activer depuis Paramètres "
            '> Modules Actifs.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AgriTypography.sm, color: AgriColors.outline),
          ),
          const SizedBox(height: AgriSpacing.md),
          InkWell(
            key: const Key('retour-gestion-elevage'),
            onTap: widget.onRetourGestion,
            child: const Text(
              '← Retour à Gestion Élevage',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
                color: AgriColors.brandEmerald,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// `exportFichePdf()` — le PDF du mois de la bande (`fiche-AAAA-MM.pdf`).
  Future<void> _exporter() async {
    final editeur = widget.imprimer;
    final mois = _mois;
    if (editeur == null || mois == null) return;
    final message = await editeur(mois.document, _maintenant);
    if (message != null && mounted) {
      ToastAgri.afficher(context, message, type: TypeToast.erreur);
    }
  }

  Widget _carteSaisie() {
    final moyen = _pesee == null || _pesee == 0 || _effectifFinal <= 0 ? '—' : '${(_pesee! / _effectifFinal).round()} g';
    return CarteSaisieFiche(
      enTete: EnTeteSaisieFiche(
        titre: 'Saisie Journalière du Cheptel',
        jour: _jour,
        onJour: _ouvrirJour,
        bandes: [for (final b in _bandes) (b.id, b.code)],
        bandeId: _bande?.id,
        onBande: (id) async {
          setState(() => _bande = _bandes.firstWhere((b) => b.id == id));
          await _chargerJour();
        },
      ),
      blocs: [
        if ((_fiche?.transfertEntree ?? 0) > 0 || (_fiche?.transfertSortie ?? 0) > 0)
          TransfertsDuJourFiche(
            entree: _fiche!.transfertEntree,
            sortie: _fiche!.transfertSortie,
            onOuvrir: widget.onOuvrirTransferts,
          ),
        GrilleFiche(
          enfants: [
            ChampSaisieFiche(
              libelle: 'Achats du jour',
              cle: 'achat',
              valeur: _achat,
              onChange: (v) => setState(() => _achat = (v ?? 0).toInt()),
            ),
            ChampLectureFiche(libelle: 'Ventes', suffixe: '(POS, réel)', valeur: '$_vente', cle: 'champ-ventes'),
          ],
        ),
        _workflowPonte(),
        BlocCategoriesFiche.morts(
          categories: _categories,
          valeurs: _morts,
          dejaEnregistres: _mortEnregistre,
          onChange: (c, v) => setState(() => _morts[c] = v),
        ),
        BlocCategoriesFiche.dons(
          categories: _categories,
          valeurs: _dons,
          dejaEnregistres: _donEnregistre,
          onChange: (c, v) => setState(() => _dons[c] = v),
        ),
        GrilleFiche(
          ecart: AgriSpacing.sm,
          enfants: [
            ChampSaisieFiche(
              libelle: 'Naissains',
              cle: 'effectif-naissains',
              valeur: _effectifNaissains,
              petite: true,
              onChange: (v) => setState(() => _effectifNaissains = (v ?? 0).toInt()),
            ),
            ChampSaisieFiche(
              libelle: 'Engraissement',
              cle: 'effectif-engraissement',
              valeur: _effectifEngraissement,
              petite: true,
              onChange: (v) => setState(() => _effectifEngraissement = (v ?? 0).toInt()),
            ),
            ChampSaisieFiche(
              libelle: 'Bordés',
              cle: 'effectif-bordes',
              valeur: _effectifBordes,
              petite: true,
              onChange: (v) => setState(() => _effectifBordes = (v ?? 0).toInt()),
            ),
          ],
        ),
        BlocEffectifFiche(
          titreEffectif: 'Effectif Final du Jour',
          formuleEffectif: '= Effectif (J-1) + Achats/Naissains − (Morts + Ventes + Dons)',
          effectif: '$_effectifFinal',
          tauxMortalite: _pourcent(_tauxMortalite),
        ),
        const FiletFiche(
          enfants: [
            TitreSectionFiche('Rationnement Farine Calcique & Fourrage', icone: SymbolesAgri.restaurant),
            SizedBox(height: AgriSpacing.xs),
            ModuleEnAttenteFiche(
              key: Key('rationnement-en-attente'),
              libelle: 'Le calcul du rationnement',
              prevu:
                  "qu'un barème officiel soit fourni pour l'héliciculture (absent de FeedRationStandards, ticket 2.7)",
            ),
          ],
        ),
        GrilleFiche(
          enfants: [
            ChampSaisieFiche(
              libelle: 'Poids Général Pesé (g)',
              cle: 'pesee',
              valeur: _pesee,
              gras: true,
              indice: 'ex : 4500',
              onChange: (v) => setState(() => _pesee = v?.toDouble()),
            ),
            ChampLectureFiche(
              libelle: 'Poids Moyen Constaté',
              suffixe: '(Poids Général ÷ Effectif Final)',
              valeur: moyen,
              cle: 'champ-poids-moyen',
              couleur: AgriColors.brandEmerald,
              gras: true,
            ),
          ],
        ),
        FiletFiche(
          enfants: [
            const TitreSectionFiche(
              'Entretien & Hygrométrie',
              icone: SymbolesAgri.thermostat,
              couleurIcone: AgriColors.infoBlue,
              tailleIcone: 18,
            ),
            const SizedBox(height: AgriSpacing.xs),
            const ModuleEnAttenteFiche(
              key: Key('hygrometrie-en-attente'),
              libelle: 'Le suivi hygrométrique',
              prevu:
                  "à planifier — aucune table de mesures d'hygrométrie n'existe encore ; le ticket 3.11 (soins "
                  'vétérinaires) ne la fournit pas',
            ),
            const SizedBox(height: AgriSpacing.sm),
            ObservationsFiche(libelle: 'Observations', indice: 'ex : RAS', controleur: _observations),
          ],
        ),
        BoutonEnregistrerFiche(onPressed: _enregistrer),
      ],
    );
  }

  /// « Workflow Ponte en Terre & Éclosion des Naissains » — le bloc ambre du Blade.
  Widget _workflowPonte() => Container(
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: TeintesFiche.amber500.withValues(alpha: 0.10),
      border: Border.all(color: TeintesFiche.amber500.withValues(alpha: 0.30)),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreSectionFiche(
          'Workflow Ponte en Terre & Éclosion des Naissains',
          icone: SymbolesAgri.egg_alt,
          couleurIcone: TeintesFiche.amber700,
          couleur: TeintesFiche.amber900,
          tailleIcone: 18,
        ),
        const SizedBox(height: AgriSpacing.sm),
        GrilleFiche(
          ecart: AgriSpacing.sm,
          enfants: [
            ChampSaisieFiche(
              libelle: 'Œufs Pondus (en terre)',
              cle: 'oeufs-terre',
              valeur: _oeufsTerre,
              gras: true,
              onChange: (v) => setState(() => _oeufsTerre = (v ?? 0).toInt()),
            ),
            ChampSaisieFiche(
              libelle: 'Naissains Nés (Éclosion)',
              cle: 'naissains-nes',
              valeur: _naissainsNes,
              gras: true,
              couleur: AgriColors.brandEmerald,
              onChange: (v) => setState(() => _naissainsNes = (v ?? 0).toInt()),
            ),
            ChampLectureFiche(
              libelle: "Taux d'Éclosion Naissains (%)",
              valeur: _pourcent(_tauxEclosion),
              cle: 'champ-taux-eclosion',
              couleur: AgriColors.brandEmerald,
              gras: true,
            ),
          ],
        ),
      ],
    ),
  );

  /// `saveDay()` : la bande, puis l'écriture (achats, naissains, morts et dons du jour — la répartition saisie, sinon
  /// le total enregistré —, œufs pondus, effectifs saisis, poids MOYEN), la cascade du dépôt, le toast du web.
  Future<void> _enregistrer() async {
    final bande = _bande;
    if (bande == null) {
      ToastAgri.afficher(context, "Aucune bande active en héliciculture. Créez d'abord une bande.", type: TypeToast.erreur);
      return;
    }
    await widget.depot.enregistrer(
      lotId: bande.id,
      jour: _jour,
      achat: _achat,
      ne: _naissainsNes,
      mort: _totalMorts,
      don: _totalDons,
      ponteTotal: _oeufsTerre,
      poidsMoyen: FicheJournaliereRepository.poidsMoyen(
        poidsTotalG: _pesee ?? 0,
        tailleEchantillon: _effectifFinal,
      ),
      effectifs: EffectifsSaisis(m: _effectifNaissains, f: _effectifEngraissement, sevres: _effectifBordes),
    );
    if (!mounted) return;
    ToastAgri.afficher(context, 'Jour enregistré avec succès.');
    await _chargerJour();
  }

  /// Le tableau du mois du Blade : TOUS les jours du mois en cours ; une ligne touchée charge son jour (`loadDay`).
  Widget _tableauMensuel() {
    final jours = _mois?.jours ?? const <JourFiche>[];
    final cellules = [for (final j in jours) j.cellules(EspeceFiche.escargots)];
    final indexChoisi = jours.indexWhere((j) => j.jour == JournalStocks.jour(_jour));
    ColonneMensuelle colonne(
      String libelle,
      int rang, {
      double largeur = 1,
      bool gras = false,
      bool aGauche = false,
      Color? Function(int)? couleur,
      bool Function(int)? grasSelon,
    }) => ColonneMensuelle(
      libelle: libelle,
      largeur: largeur,
      gras: gras,
      aGauche: aGauche,
      couleur: couleur,
      grasSelon: grasSelon,
      valeur: (i) => cellules[i][rang],
    );
    bool mort(int i) => (jours[i].fiche?.mort ?? 0) > 0;
    bool taux(int i) => (jours[i].tauxMortalite ?? 0) > 0;

    return TableauMensuel(
      key: const Key('tableau-mois'),
      libelleDate: 'Date',
      nombreDeJours: jours.length,
      jourActif: indexChoisi < 0 ? null : indexChoisi,
      zebre: false,
      invite: null,
      dateDe: (i) => jours[i].date,
      onOuvrirJour: (i) => _ouvrirJour(jours[i].jour),
      groupes: [
        GroupeColonnes(libelle: 'Entrées', colonnes: [colonne('Achat', 0), colonne('Naissain Né', 1, largeur: 1.3)]),
        GroupeColonnes(
          libelle: 'Sorties',
          colonnes: [
            colonne('Mort', 2, couleur: (i) => mort(i) ? AgriColors.errorDeep : null, grasSelon: mort),
            colonne('Vente', 3),
            colonne('Don', 4),
          ],
        ),
        GroupeColonnes(
          libelle: 'Effectif Final du Jour',
          colonnes: [
            colonne('Naissains', 5, largeur: 1.2),
            colonne('Engraiss.', 6, largeur: 1.2),
            colonne('Bordés', 7),
            colonne('Total', 8, gras: true),
          ],
        ),
      ],
      colonnesSimples: [
        colonne(
          'Taux Mort %',
          9,
          largeur: 1.2,
          couleur: (i) => taux(i) ? AgriColors.errorDeep : null,
          grasSelon: taux,
        ),
        colonne('Poids Général (g)', 10, largeur: 1.4),
        colonne('Traitements & Prophylaxie', 11, largeur: 3, aGauche: true, couleur: (_) => AgriColors.outline),
      ],
    );
  }

  /// ⚠️ CHARGE LA JOURNÉE DANS LE FORMULAIRE (`loadDay`).
  Future<void> _ouvrirJour(DateTime jour) async {
    setState(() => _jour = DateTime(jour.year, jour.month, jour.day));
    await _chargerJour();
  }
}
