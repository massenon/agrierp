import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../rapports/rapports_exports_screen.dart' show Editeur;
import '../../core/export/document_officiel.dart';
import 'comptabilite_repository.dart';
import 'documents_comptabilite.dart';

/// `prototype_html/comptabilite-hub.html` → Comptabilité.
///
/// ⚠️⚠️ **CE HUB N'EST PAS FAIT D'ONGLETS MAIS DE CARTES DE NAVIGATION** — neuf
/// dans la maquette, chacune ouvrant une page. Le poste reproduit les neuf,
/// dans leur ordre : quatre mènent à un écran réel, cinq disent pourquoi elles
/// restent sur la surface web.
///
/// ⚠️⚠️ **LES ÉTATS LISENT LE JOURNAL, JAMAIS DES TABLES MÉTIER DISJOINTES.**
/// Grand Livre et Balance sont calculés à partir des écritures reçues — pas des
/// ventes et des achats du poste, qui donneraient une seconde comptabilité pour
/// la même ferme.
class ComptabiliteScreen extends StatefulWidget {
  const ComptabiliteScreen({
    super.key,
    required this.depot,
    this.maintenant = DateTime.now,
    this.imprimer,
  });

  final ComptabiliteRepository depot;

  /// Éditeur des documents officiels (« Exporter PDF », ticket F0.87). Injecté : `main.dart` y
  /// branche `EditeursRapports.imprimer` (polices embarquées, boîte d'impression de Windows) ; un
  /// test y branche un collecteur. Sans éditeur, le bouton ne fait rien.
  final Editeur? imprimer;

  /// L'horloge du poste — injectable pour que la période par défaut du Grand Livre (du premier du
  /// mois à aujourd'hui, comme le composant web) se teste sans dépendre du jour d'exécution.
  final DateTime Function() maintenant;

  @override
  State<ComptabiliteScreen> createState() => _ComptabiliteScreenState();
}

/// Les neuf cartes du hub, dans l'ordre de la maquette.
enum PageComptable {
  hub('Comptabilité', Icons.account_balance),
  planComptable('Plan Comptable', Icons.list_alt),
  journal('Journal Comptable', Icons.menu_book),
  grandLivre('Grand Livre', Icons.auto_stories),
  balance('Balance Générale', Icons.balance),
  etatsFinanciers('États Financiers', Icons.assessment),
  cloture('Clôture Périodique & Annuelle', Icons.lock_clock),
  analytique('Comptabilité Analytique', Icons.pie_chart),
  tva('Déclaration TVA', Icons.receipt_long),
  rapprochement('Rapprochement Bancaire', Icons.account_balance_wallet);

  const PageComptable(this.libelle, this.icone);

  final String libelle;
  final IconData icone;
}

class _ComptabiliteScreenState extends State<ComptabiliteScreen> {
  /// ⚠️ **CINQ PAGES RESTENT SUR LE WEB, CHACUNE POUR SA RAISON.** Un motif
  /// générique — « non embarqué » — ne dirait pas au comptable s'il doit
  /// attendre une synchronisation ou aller sur un poste connecté.
  static const motifs = <PageComptable, String>{
    PageComptable.etatsFinanciers:
        "Bilan et Compte de Résultat rangent chaque compte dans une rubrique "
        "SYSCOHADA selon des règles qui vivent sur le serveur. Un état "
        "recomposé ici pourrait être juste au centime près et faux de "
        'structure — et rien à l\'écran ne le dirait.',
    PageComptable.cloture:
        "La clôture d'exercice est explicitement hors du contrat de "
        'synchronisation : elle fige les comptes de toute la ferme. La lancer '
        "depuis un poste qui n'a pas encore reçu les dernières pièces "
        "clôturerait un exercice incomplet.",
    PageComptable.analytique:
        "La ventilation analytique s'appuie sur les centres de coût, qui ne "
        'descendent pas au poste : les lignes reçues portent leur identifiant, '
        'jamais leur libellé.',
    PageComptable.tva:
        "La déclaration de TVA est une pièce fiscale : elle s'établit et se "
        'télédéclare depuis la surface web, avec le régime et les taux en '
        'vigueur.',
    PageComptable.rapprochement:
        "Le rapprochement pointe le Grand Livre contre un RELEVÉ de banque ou "
        "de Mobile Money — un document que le poste ne reçoit pas.",
  };

  PageComptable _page = PageComptable.hub;
  String? _compteGrandLivre;

  /// Période et recherche du Grand Livre. Par défaut : du premier du mois À AUJOURD'HUI, comme le
  /// composant web (`now()->startOfMonth()` → `now()`), calculés sur l'horloge du poste.
  DateTime? _debut;
  DateTime? _fin;
  String _recherche = '';
  final _champRecherche = TextEditingController();

  /// Période de la Balance : « mois courant » par défaut, comme le composant web (`$periode = 'mois'`).
  PeriodeBalance _periodeBalance = PeriodeBalance.mois;

  DonneesComptabilite? _donnees;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    if (!mounted) return;

    final aujourdhui = widget.maintenant();

    setState(() {
      _donnees = donnees;
      _compteGrandLivre ??= donnees.compteGrandLivreParDefaut?.id;
      _debut ??= DateTime(aujourdhui.year, aujourdhui.month, 1);
      _fin ??= DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
    });
  }

  @override
  void dispose() {
    _champRecherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final large = AgriBreakpoints.large(context);

                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    large ? AgriSpacing.lg : AgriSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_page != PageComptable.hub) _retour(),
                      switch (_page) {
                        PageComptable.planComptable => _pagePlan(d, large),
                        PageComptable.journal => _pageJournal(d, large),
                        PageComptable.grandLivre => _pageGrandLivre(d, large),
                        PageComptable.balance => _pageBalance(d, large),
                        PageComptable.hub => _pageHub(d, large),
                        _ => _pageNonEmbarquee(_page, large),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _retour() => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: AgriSpacing.md),
      child: TextButton.icon(
        key: const Key('retour-hub'),
        onPressed: () => setState(() => _page = PageComptable.hub),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text(
          'Comptabilité',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: AgriTypography.gras,
          ),
        ),
        style: TextButton.styleFrom(foregroundColor: AgriColors.brandEmerald),
      ),
    ),
  );

  // ── Le hub : neuf cartes de navigation ────────────────────────────────────

  Widget _pageHub(DonneesComptabilite d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Comptabilité', large),
      const SizedBox(height: AgriSpacing.md),
      _grilleKpis(large, [
        CarteKpi(
          libelle: 'Écritures reçues',
          valeur: '${d.journal.length}',
          legende: d.exerciceOuvert == null
              ? 'Exercice non synchronisé'
              : 'Exercice ${d.exerciceOuvert!.year}',
          couleurLisere: AgriColors.brandEmerald,
          icone: Icons.menu_book,
        ),
        CarteKpi(
          libelle: 'Total Débit',
          valeur: _montant(d.totalDebit),
          unite: 'FCFA',
          couleurLisere: AgriColors.infoBlue,
          icone: Icons.trending_up,
          couleurIcone: AgriColors.infoBlue,
        ),
        CarteKpi(
          libelle: 'Total Crédit',
          valeur: _montant(d.totalCredit),
          unite: 'FCFA',
          couleurLisere: AgriColors.brandForest,
          icone: Icons.trending_down,
          couleurIcone: AgriColors.brandForest,
        ),
        // ⚠️⚠️ UN DÉSÉQUILIBRE N'EST PAS UNE ERREUR COMPTABLE. Le serveur
        // garantit `SUM(debit) = SUM(credit)` avant de comptabiliser : une
        // écriture déséquilibrée AU POSTE signale un tirage incomplet — des
        // lignes pas encore descendues. Le dire évite qu'un comptable cherche
        // une faute qui n'existe pas.
        CarteKpi(
          libelle: 'Écritures incomplètes',
          valeur: '${d.ecrituresIncompletes}',
          legende: 'Lignes non encore reçues',
          couleurLisere: d.ecrituresIncompletes > 0
              ? AgriColors.accentYellow
              : AgriColors.brandEmerald,
          icone: Icons.sync_problem,
          couleurIcone: AgriColors.brandForest,
        ),
      ]),
      const SizedBox(height: AgriSpacing.lg),
      GridView.count(
        crossAxisCount: large ? 3 : 1,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AgriSpacing.md,
        crossAxisSpacing: AgriSpacing.md,
        childAspectRatio: large ? 3.2 : 4.5,
        children: [
          for (final page in PageComptable.values)
            if (page != PageComptable.hub) _carteNavigation(page),
        ],
      ),
    ],
  );

  Widget _carteNavigation(PageComptable page) {
    final embarquee = !motifs.containsKey(page);

    return InkWell(
      key: Key('carte-${page.name}'),
      onTap: () => setState(() => _page = page),
      child: Container(
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: AgriColors.surfaceCard,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Row(
          children: [
            Icon(
              page.icone,
              size: 24,
              color: embarquee ? AgriColors.brandEmerald : AgriColors.outline,
            ),
            const SizedBox(width: AgriSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    page.libelle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AgriTypography.sm,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.brandForest,
                    ),
                  ),
                  if (!embarquee)
                    const Text(
                      'Consultation sur la surface web',
                      style: TextStyle(fontSize: 10, color: AgriColors.outline),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Plan Comptable ────────────────────────────────────────────────────────

  Widget _pagePlan(DonneesComptabilite d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _enTete(
        _titre('Plan Comptable SYSCOHADA', large),
        _boutonExport(
          'exporter-pdf-plan',
          () => _exporter(
            DocumentsComptabilite.plan(d, le: widget.maintenant()),
            'Aucun compte à exporter.',
          ),
        ),
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ LES DEUX CARTES DE `plan-comptable.html` (`menu_book`, `event`).
      _grilleKpis(large, [
        CarteKpi(
          key: const Key('kpi-plan-comptes'),
          libelle: 'Comptes actifs',
          valeur: '${d.comptesActifs}',
          couleurLisere: AgriColors.brandEmerald,
          icone: Icons.menu_book,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-plan-exercice'),
          libelle: 'Exercice',
          // ⚠️ Un tiret si aucun exercice OUVERT n'est descendu : afficher
          // l'année courante laisserait croire qu'un exercice l'est.
          valeur: '${d.anneeExerciceOuvert ?? '—'}',
          couleurLisere: AgriColors.brandEmerald,
          icone: Icons.event,
          couleurIcone: AgriColors.outline,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 800,
        colonnes: const [
          ('N° Compte', 3),
          ('Intitulé', 7),
          ('Classe', 2),
          ('Actions', 2),
        ],
        vide: '— Aucun compte synchronisé —',
        lignes: [
          for (var i = 0; i < d.comptes.length; i++)
            _ligne(i, [
              (
                Text(
                  d.comptes[i].code,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandEmerald,
                  ),
                ),
                3,
              ),
              (
                Text(
                  d.comptes[i].label,
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                7,
              ),
              (Text('${d.comptes[i].accountClass ?? '—'}', style: _cellule), 2),
              (_actionInerte(), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ (Ticket F0.83, 10 oct. 2026) Le serveur sert désormais le plan SYSCOHADA révisé
      // officiel (1 332 comptes + ceux de la ferme absents du CSV) : l'étroitesse du plan,
      // arbitrage ouvert depuis le Sprint 14, est levée pour l'AJOUT de comptes. Le REMAPPAGE
      // des comptes de la ferme au sens divergent reste la phase B (cabinet FAGUEZ).
      _mentionPoste(
        "Le plan comptable se modifie sur la surface web : ajouter un compte "
        "depuis le poste donnerait une saisie effacée au tirage suivant.",
      ),
    ],
  );

  // ── Journal Comptable ─────────────────────────────────────────────────────

  Widget _pageJournal(DonneesComptabilite d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _enTete(
        _titre('Journal Comptable', large),
        _boutonExport(
          'exporter-pdf-journal',
          () => _exporter(
            DocumentsComptabilite.journal(d, le: widget.maintenant()),
            'Aucune écriture à exporter.',
          ),
        ),
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ LES TROIS CARTES DE `journal-comptable.html` (`receipt_long`,
      // `arrow_downward`, `arrow_upward`).
      //
      // ⚠️⚠️ **LEURS PORTÉES DIFFÈRENT, ET C'EST LA MAQUETTE QUI LE DIT.** Seule
      // la première porte « (mois) » ; les deux totaux n'ont pas de qualificatif
      // et couvrent donc le journal détenu. Les légendes le disent, faute de
      // quoi trois cartes côte à côte se liraient comme une même période.
      _grilleKpis(large, [
        CarteKpi(
          key: const Key('kpi-journal-ecritures'),
          libelle: 'Écritures (mois)',
          valeur: '${d.ecrituresDuMois(DateTime.now())}',
          couleurLisere: AgriColors.brandEmerald,
          icone: Icons.receipt_long,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-journal-debit'),
          libelle: 'Total Débit',
          valeur: _montant(d.totalDebit),
          unite: 'F',
          legende: 'Journal reçu au poste',
          couleurLisere: AgriColors.brandEmerald,
          icone: Icons.arrow_downward,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-journal-credit'),
          libelle: 'Total Crédit',
          valeur: _montant(d.totalCredit),
          unite: 'F',
          legende: 'Journal reçu au poste',
          couleurLisere: AgriColors.brandEmerald,
          icone: Icons.arrow_upward,
          couleurIcone: AgriColors.outline,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1200,
        colonnes: const [
          ('N° Pièce', 4),
          ('Date', 2),
          ('Libellé', 5),
          ('Débit', 2),
          ('Crédit', 2),
          ('Montant', 3),
          ('Actions', 2),
        ],
        vide: '— Aucune écriture synchronisée —',
        lignes: [
          for (var i = 0; i < d.journal.length; i++)
            _ligne(i, [
              (
                // ⚠️ F0.87 : la PIÈCE (référence avant « — »), comme la page web — et non plus le
                // type de source (« sale », « purchase »), qui n'est pas un numéro de pièce.
                Text(
                  d.journal[i].piece.isEmpty ? '—' : d.journal[i].piece,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                4,
              ),
              (
                Text(_date(d.journal[i].ecriture.entryDate), style: _cellule),
                2,
              ),
              (
                Text(
                  d.journal[i].libelle.isEmpty ? '—' : d.journal[i].libelle,
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                5,
              ),
              (
                Text(
                  d.journal[i].comptesDebites,
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                2,
              ),
              (
                Text(
                  d.journal[i].comptesCredites,
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                2,
              ),
              (_montantEcriture(d.journal[i]), 3),
              (_actionInerte(), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ AUCUNE ÉCRITURE NE SE SAISIT AU POSTE, et ce n'est pas un manque.
      // Une écriture naît d'une opération — vente, achat, dépense, ponte,
      // écart d'inventaire — et le serveur la génère lui-même. C'est ce qui
      // garantit qu'aucun mouvement ne pèse sur les comptes sans avoir pesé
      // sur le stock ou la caisse.
      _mentionPoste(
        "Une écriture naît d'une opération — vente, achat, dépense, écart "
        "d'inventaire — et le serveur la génère lui-même. La saisie manuelle "
        "d'écriture reste sur la surface web : une écriture saisie à la main "
        'ne pèserait ni sur le stock ni sur la caisse.',
      ),
    ],
  );

  Widget _montantEcriture(LigneJournal e) {
    if (!e.equilibree) {
      return Text(
        '${_montant(e.totalDebit)} ⚠',
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          fontWeight: AgriTypography.gras,
          color: AgriColors.errorDeep,
        ),
      );
    }

    return Text(
      _montant(e.totalDebit),
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: AgriTypography.gras,
      ),
    );
  }

  // ── Grand Livre ───────────────────────────────────────────────────────────

  /// Raison d'un montant inconnu, ou `null` quand il est connu.
  String? _motifTiret(GrandLivreCompte g, {required bool dependDeLHistorique}) {
    if (g.sansEcriture) return 'Aucune écriture sur ce compte';
    if (dependDeLHistorique && g.journalIncomplet) {
      return _motifJournalIncomplet;
    }
    return null;
  }

  Widget _pageGrandLivre(DonneesComptabilite d, bool large) {
    final g = _compteGrandLivre == null
        ? null
        : d.grandLivreCompte(
            _compteGrandLivre!,
            debut: _debut,
            fin: _fin,
            recherche: _recherche,
          );

    final motifHistorique = g == null
        ? 'Aucune écriture sur ce compte'
        : _motifTiret(g, dependDeLHistorique: true);
    final motifPeriode = g == null
        ? 'Aucune écriture sur ce compte'
        : _motifTiret(g, dependDeLHistorique: false);
    final mouvements = g?.mouvements ?? const <MouvementCompte>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _enTete(
          _titre('Grand Livre', large),
          // ⚠️ Le document reprend le compte, la période ET la recherche AFFICHÉS (même objet `g`).
          _boutonExport(
            'exporter-pdf-grand-livre',
            () => _exporter(
              g == null
                  ? const DocumentOfficiel(
                      titre: 'Grand Livre',
                      sousTitre: '',
                      lignes: [],
                    )
                  : DocumentsComptabilite.grandLivre(
                      g,
                      debut: _debut!,
                      fin: _fin!,
                    ),
              'Aucune écriture à exporter pour ce compte sur cette période.',
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          "Écritures chronologiques d'un compte, avec solde progressif.",
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        // ⚠️ Barre de filtres de `grand-livre.html` : compte, période « du … au … ».
        Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AgriSpacing.sm,
            runSpacing: AgriSpacing.sm,
            children: [
              const Text(
                'Compte :',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandForest,
                ),
              ),
              SizedBox(
                width: 380,
                child: DropdownButtonFormField<String>(
                  key: const Key('compte-grand-livre'),
                  initialValue: _compteGrandLivre,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  // État vide de la page web : « Aucun compte au plan comptable ».
                  hint: const Text('Aucun compte au plan comptable'),
                  style: const TextStyle(
                    fontSize: AgriTypography.sm,
                    color: AgriColors.onSurface,
                  ),
                  items: [
                    for (final c in d.comptes)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.code} — ${c.label}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _compteGrandLivre = v),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AgriColors.surfaceZebra,
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _champDate(
                      const Key('gl-date-debut'),
                      _debut!,
                      (v) => _debut = v,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AgriSpacing.xs),
                      child: Text(
                        'au',
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          color: AgriColors.outline,
                        ),
                      ),
                    ),
                    _champDate(
                      const Key('gl-date-fin'),
                      _fin!,
                      (v) => _fin = v,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        // ⚠️ LES QUATRE CARTES DE `grand-livre.html` (la dernière, « Solde Final », sur fond jaune
        // pâle dans la maquette ; la page web la rend avec le liseré jaune de `x-kpi-card`).
        // ⚠️⚠️ UN MONTANT QUE LE POSTE NE CONNAÎT PAS EST « — », jamais « 0 », avec sa raison :
        // compte sans aucune écriture, ou journal incomplet (ouverture et final seulement).
        _grilleKpis(large, [
          CarteKpi(
            key: const Key('kpi-livre-ouverture'),
            libelle: "Solde d'Ouverture",
            valeur: g?.soldeOuverture == null
                ? '—'
                : _montant(g!.soldeOuverture!),
            unite: g?.soldeOuverture == null ? null : 'F',
            legende: motifHistorique,
            couleurLisere: AgriColors.brandEmerald,
          ),
          CarteKpi(
            key: const Key('kpi-livre-debit'),
            libelle: 'Total Débit Période',
            valeur: motifPeriode != null ? '—' : _montant(g!.totalDebit),
            unite: motifPeriode != null ? null : 'F',
            legende: motifPeriode,
            couleurLisere: AgriColors.infoBlue,
          ),
          CarteKpi(
            key: const Key('kpi-livre-credit'),
            libelle: 'Total Crédit Période',
            valeur: motifPeriode != null ? '—' : _montant(g!.totalCredit),
            unite: motifPeriode != null ? null : 'F',
            legende: motifPeriode,
            couleurLisere: AgriColors.errorRed,
          ),
          CarteKpi(
            key: const Key('kpi-livre-final'),
            libelle: 'Solde Final',
            valeur: g?.soldeFinal == null ? '—' : _montant(g!.soldeFinal!),
            unite: g?.soldeFinal == null ? null : 'F',
            legende: motifHistorique,
            couleurLisere: AgriColors.accentYellow,
          ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        // Recherche : « Rechercher un libellé, une pièce... » (porte sur la référence entière).
        Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 320,
              child: TextField(
                key: const Key('gl-recherche'),
                controller: _champRecherche,
                onChanged: (v) => setState(() => _recherche = v),
                style: const TextStyle(fontSize: AgriTypography.xs),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Rechercher un libellé, une pièce...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        _tableau(
          largeur: 1000,
          colonnes: const [
            ('Date', 2),
            ('N° Pièce', 3),
            ('Libellé', 5),
            ('Débit', 2),
            ('Crédit', 2),
            ('Solde Progressif', 3),
          ],
          vide: 'Aucune écriture ne correspond à ces critères.',
          lignes: [
            for (var i = 0; i < mouvements.length; i++)
              _ligne(i, [
                (
                  Text(
                    _date(mouvements[i].ecriture.entryDate),
                    style: _cellule,
                  ),
                  2,
                ),
                (
                  Text(
                    mouvements[i].piece.isEmpty ? '—' : mouvements[i].piece,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontFamily: 'monospace',
                      color: AgriColors.outline,
                    ),
                  ),
                  3,
                ),
                (
                  Text(
                    mouvements[i].libelle.isEmpty ? '—' : mouvements[i].libelle,
                    overflow: TextOverflow.ellipsis,
                    style: _cellule,
                  ),
                  5,
                ),
                (
                  Text(
                    _montantOuTiret(mouvements[i].ligne.debit),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: mouvements[i].ligne.debit > 0
                          ? AgriTypography.gras
                          : null,
                      color: mouvements[i].ligne.debit > 0
                          ? AgriColors.brandEmerald
                          : AgriColors.outline,
                    ),
                  ),
                  2,
                ),
                (
                  Text(
                    _montantOuTiret(mouvements[i].ligne.credit),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: mouvements[i].ligne.credit > 0
                          ? AgriTypography.gras
                          : null,
                      color: mouvements[i].ligne.credit > 0
                          ? AgriColors.errorDeep
                          : AgriColors.outline,
                    ),
                  ),
                  2,
                ),
                (
                  Text(
                    _montant(mouvements[i].soldeProgressif),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.brandForest,
                    ),
                  ),
                  3,
                ),
              ]),
          ],
        ),
      ],
    );
  }

  /// Champ « date » de la barre de filtres : un clic ouvre le calendrier. Le Grand Livre se recalcule
  /// aussitôt (tout est en mémoire, rien à recharger).
  Widget _champDate(
    Key cle,
    DateTime valeur,
    void Function(DateTime) affecter,
  ) {
    return InkWell(
      key: cle,
      onTap: () async {
        final choisie = await showDatePicker(
          context: context,
          initialDate: valeur,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (choisie == null) return;
        setState(() => affecter(choisie));
      },
      child: Padding(
        padding: const EdgeInsets.all(AgriSpacing.xs),
        child: Text(
          _date(valeur),
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: AgriTypography.gras,
            color: AgriColors.brandForest,
          ),
        ),
      ),
    );
  }

  // ── Balance Générale ──────────────────────────────────────────────────────

  Widget _pageBalance(DonneesComptabilite d, bool large) {
    final maintenant = widget.maintenant();
    final exercice = d.exerciceOuvert;
    final bornes = DonneesComptabilite.bornesBalance(
      _periodeBalance,
      maintenant,
      exercice,
    );
    final b = d.balanceGenerale(debut: bornes.debut, fin: bornes.fin);
    final lignes = b.lignes;

    // ⚠️⚠️ Un solde que le poste ne peut pas affirmer est « — », avec sa raison, jamais « 0 ».
    // Même raison que le document édité (F0.87).
    final motif = DocumentsComptabilite.motifBalance(b);
    String solde(double v) => motif != null ? '—' : _montantOuTiret(v);
    String total(double v) => motif != null ? '—' : _montant(v);

    final couleurEcart = motif != null
        ? AgriColors.onSurface
        : b.equilibree
        ? AgriColors.brandEmerald
        : AgriColors.errorDeep;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _enTete(
          _titre('Balance Générale', large),
          // ⚠️ Le document reprend la période AFFICHÉE (même `b`, même libellé que l'option choisie).
          _boutonExport(
            'exporter-pdf-balance',
            () => _exporter(
              DocumentsComptabilite.balance(
                b,
                periode: DonneesComptabilite.libellePeriodeBalance(
                  _periodeBalance,
                  maintenant,
                  exercice,
                ),
              ),
              'Aucun compte mouvementé à exporter sur cette période.',
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          "Synthèse des soldes de tous les comptes utilisés — vérification de l'équilibre avant clôture.",
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        // ⚠️ Sélecteur de `balance-generale.html` (`bal-periode-select`) : DEUX options, pas un
        // calendrier — « mois courant » ou « exercice complet », comme le composant web.
        Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AgriSpacing.sm,
            runSpacing: AgriSpacing.sm,
            children: [
              const Text(
                'Période :',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandForest,
                ),
              ),
              SizedBox(
                width: 320,
                child: DropdownButtonFormField<PeriodeBalance>(
                  key: const Key('balance-periode'),
                  initialValue: _periodeBalance,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontSize: AgriTypography.sm,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.onSurface,
                  ),
                  items: [
                    for (final p in PeriodeBalance.values)
                      DropdownMenuItem(
                        value: p,
                        child: Text(
                          DonneesComptabilite.libellePeriodeBalance(
                            p,
                            maintenant,
                            exercice,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _periodeBalance = v);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        // ⚠️⚠️ LES CARTES TOTALISENT DES SOLDES FINAUX, PAS DES MOUVEMENTS. Un compte est débiteur OU
        // créditeur ; additionner la colonne des débits donnerait le total des mouvements, bien plus
        // grand, tout aussi équilibré, et faux sous ce libellé.
        // ⚠️ La troisième carte, « Écart (doit être 0) », n'a pas de liseré dans la maquette (fond
        // teinté vert ou rouge) : `CarteKpi` la rend avec un liseré de la même couleur.
        _grilleKpis(large, [
          CarteKpi(
            key: const Key('kpi-balance-debits'),
            libelle: 'Total Débits (Soldes Finaux)',
            valeur: total(b.totalFinalDebit),
            unite: motif != null ? null : 'F',
            legende: motif,
            couleurLisere: AgriColors.brandEmerald,
          ),
          CarteKpi(
            key: const Key('kpi-balance-credits'),
            libelle: 'Total Crédits (Soldes Finaux)',
            valeur: total(b.totalFinalCredit),
            unite: motif != null ? null : 'F',
            legende: motif,
            couleurLisere: AgriColors.errorRed,
          ),
          CarteKpi(
            key: const Key('kpi-balance-ecart'),
            libelle: 'Écart (doit être 0)',
            // ⚠️⚠️ F0.88 (arbitrage client du 13/10/2026), ÉCART ASSUMÉ vs web : un écart non nul
            // s'écrit AVEC ses centimes (« -0,40 »), jamais « 0 » rouge sous le bandeau. Nul : « 0 ».
            // Seuil d'équilibre inchangé (`equilibree`, < 0,01). Le bandeau et la ligne TOTAUX ne
            // portent pas l'écart (maquette) ; le document l'imprime avec le même formateur.
            valeur: motif != null
                ? '—'
                : DocumentsComptabilite.montantEcart(b.ecart),
            unite: motif != null ? null : 'F',
            legende: motif,
            couleurValeur: couleurEcart,
            couleurLisere: motif != null
                ? AgriColors.outlineVariant
                : b.equilibree
                ? AgriColors.brandEmerald
                : AgriColors.errorRed,
          ),
        ]),
        if (motif == null && !b.equilibree) ...[
          const SizedBox(height: AgriSpacing.md),
          Container(
            key: const Key('bal-alerte-desequilibre'),
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(
              color: AgriColors.errorRed.withValues(alpha: 0.10),
              border: Border.all(
                color: AgriColors.errorRed.withValues(alpha: 0.30),
              ),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning, size: 20, color: AgriColors.errorDeep),
                SizedBox(width: AgriSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Balance Déséquilibrée',
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          fontWeight: AgriTypography.gras,
                          color: AgriColors.errorDeep,
                        ),
                      ),
                      SizedBox(height: AgriSpacing.xs),
                      Text(
                        DocumentsComptabilite.anomalieBalance,
                        style: TextStyle(
                          fontSize: 11,
                          color: AgriColors.errorDeep,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (b.journalIncomplet && !b.journalVide) ...[
          const SizedBox(height: AgriSpacing.md),
          _mentionPoste(
            '$_motifJournalIncomplet. ${DocumentsComptabilite.suiteBalanceIncomplete}',
          ),
        ],
        const SizedBox(height: AgriSpacing.md),
        // ⚠️⚠️ **HUIT COLONNES SOUS TROIS GROUPES, PAS SEPT COLONNES À PLAT.**
        // La maquette coiffe « Solde Ouverture », « Mouvements Période » et
        // « Solde Final » (`colspan=2`) d'une seconde rangée Débit/Crédit, et
        // garde « N° Compte » et « Libellé » sur toute la hauteur
        // (`rowspan=2`). Lu en aplatissant les deux rangées, le tableau
        // paraissait avoir ONZE colonnes ; porté sans les groupes, il n'en
        // avait que SEPT — et le rapprochement débit/crédit d'un solde
        // devenait impossible à lire. `balance-generale.html` l.115-128.
        _tableauGroupe(
          largeur: 1200,
          groupes: const [
            ('N° Compte', 2, 1),
            ('Libellé', 5, 1),
            ('Solde Ouverture', 4, 2),
            ('Mouvements Période', 4, 2),
            ('Solde Final', 4, 2),
          ],
          // État vide de la page web (la maquette n'en a pas : ses lignes sont écrites en dur).
          vide: 'Aucun compte mouvementé sur cette période.',
          lignes: [
            for (var i = 0; i < lignes.length; i++)
              _ligne(i, [
                (
                  Text(
                    lignes[i].code,
                    key: Key('bal-$i-code'),
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      fontFamily: 'monospace',
                    ),
                  ),
                  2,
                ),
                (
                  Text(
                    lignes[i].libelle,
                    overflow: TextOverflow.ellipsis,
                    style: _cellule,
                  ),
                  5,
                ),
                // Ouverture (nette) et mouvements (bruts) : « — » pour un zéro, comme la maquette.
                _celluleBalance(i, 0, solde(lignes[i].ouvertureDebit)),
                _celluleBalance(i, 1, solde(lignes[i].ouvertureCredit)),
                _celluleBalance(
                  i,
                  2,
                  _montantOuTiret(lignes[i].mouvementsDebit),
                ),
                _celluleBalance(
                  i,
                  3,
                  _montantOuTiret(lignes[i].mouvementsCredit),
                ),
                // Solde final : gras, vert au débit, rouge au crédit (`text-brand-emerald` /
                // `text-error-deep`).
                _celluleBalance(
                  i,
                  4,
                  solde(lignes[i].finalDebit),
                  couleur: AgriColors.brandEmerald,
                ),
                _celluleBalance(
                  i,
                  5,
                  solde(lignes[i].finalCredit),
                  couleur: AgriColors.errorDeep,
                ),
              ]),
          ],
          // Ligne TOTAUX de la maquette (`bal-tfoot`), seulement s'il y a des lignes (page web).
          pied: lignes.isEmpty
              ? null
              : Container(
                  color: AgriColors.brandForest,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AgriSpacing.md,
                    vertical: AgriSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        flex: 7,
                        child: Text('TOTAUX', style: _totaux),
                      ),
                      for (final (c, v) in [
                        (0, total(b.totalOuvertureDebit)),
                        (1, total(b.totalOuvertureCredit)),
                        (2, _montant(b.totalMouvementsDebit)),
                        (3, _montant(b.totalMouvementsCredit)),
                        (4, total(b.totalFinalDebit)),
                        (5, total(b.totalFinalCredit)),
                      ])
                        Expanded(
                          flex: 2,
                          child: Text(
                            v,
                            key: Key('bal-total-$c'),
                            textAlign: TextAlign.right,
                            style: _totaux,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// Raison commune d'un solde inconnu (Grand Livre et Balance) — la même que sur le document édité.
  static const _motifJournalIncomplet =
      DocumentsComptabilite.motifJournalIncomplet;

  // ── « Exporter PDF » (ticket F0.87) ───────────────────────────────────────

  /// Titre de page et bouton d'export sur une ligne, comme l'en-tête des quatre pages de la maquette.
  Widget _enTete(Widget titre, Widget bouton) => Row(
    children: [
      Expanded(child: titre),
      const SizedBox(width: AgriSpacing.sm),
      bouton,
    ],
  );

  /// Le bouton blanc « Exporter PDF » de la maquette (`picture_as_pdf`, bord fin, arrondi plein).
  Widget _boutonExport(String cle, VoidCallback onPressed) =>
      OutlinedButton.icon(
        key: Key(cle),
        onPressed: onPressed,
        icon: const Icon(Icons.picture_as_pdf, size: 18),
        style: OutlinedButton.styleFrom(
          foregroundColor: AgriColors.brandForest,
          side: const BorderSide(color: AgriColors.outlineVariant),
          shape: const StadiumBorder(),
        ),
        label: const Text(
          'Exporter PDF',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  /// Édite le document des lignes AFFICHÉES (patron F0.82 / F0.82-bis). ⚠️ Un document sans ligne
  /// n'est pas édité : réduit à son en-tête, il ressemblerait à un état « rien à signaler » alors que
  /// le poste n'a simplement rien (même choix que Liste d'Achats, F0.75).
  Future<void> _exporter(DocumentOfficiel document, String vide) async {
    if (document.lignes.isEmpty) {
      _annoncer(vide);
      return;
    }
    final editeur = widget.imprimer;
    if (editeur == null) return;

    // ⚠️ Polices introuvables, imprimante absente, construction du PDF : l'éditeur peut lever.
    // Sans cette capture, l'erreur resterait asynchrone et non gérée, sans aucun retour.
    try {
      final message = await editeur(document, widget.maintenant());
      _annoncer(message ?? 'Document envoyé à l’impression.');
    } catch (_) {
      _annoncer(
        'L’édition du document a échoué. Réessayez ou vérifiez l’imprimante.',
      );
    }
  }

  void _annoncer(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: AgriTypography.xs),
        ),
        backgroundColor: AgriColors.brandEmerald,
      ),
    );
  }

  static const _totaux = TextStyle(
    fontSize: AgriTypography.xs,
    fontWeight: AgriTypography.gras,
    color: Colors.white,
  );

  (Widget, int) _celluleBalance(
    int ligne,
    int colonne,
    String texte, {
    Color? couleur,
  }) => (
    Text(
      texte,
      key: Key('bal-$ligne-$colonne'),
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: couleur == null ? null : AgriTypography.gras,
        color: couleur,
      ),
    ),
    2,
  );

  // ── Les cinq pages qui restent sur le web ─────────────────────────────────

  Widget _pageNonEmbarquee(PageComptable page, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre(page.libelle, large),
      const SizedBox(height: AgriSpacing.md),
      _mentionPoste(motifs[page] ?? ''),
    ],
  );

  // ── Briques communes ──────────────────────────────────────────────────────

  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.outline,
  );

  Widget _titre(String texte, bool large) => Text(
    texte,
    style: TextStyle(
      fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
      fontWeight: AgriTypography.gras,
      color: AgriColors.onSurface,
    ),
  );

  Widget _grilleKpis(bool large, List<Widget> cartes) => GridView.count(
    crossAxisCount: large ? cartes.length : 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AgriSpacing.md,
    crossAxisSpacing: AgriSpacing.md,
    childAspectRatio: large ? 2.4 : 1.6,
    children: cartes,
  );

  /// Tableau à en-tête sur DEUX niveaux — le gabarit de la Balance Générale.
  ///
  /// ⚠️⚠️ **UN GROUPE COIFFE DEUX COLONNES : Débit et Crédit.** `groupes` porte
  /// le libellé du groupe, son poids total, et le nombre de sous-colonnes
  /// qu'il coiffe — 1 pour une colonne pleine hauteur (`rowspan=2` dans la
  /// maquette), 2 pour un groupe (`colspan=2`).
  ///
  /// ⚠️ Les colonnes déclarées à plat pour le contrôle de structure sont les
  /// FEUILLES : « N° Compte, Libellé, Débit, Crédit, Débit, Crédit, Débit,
  /// Crédit » — huit, comme dans la maquette.
  Widget _tableauGroupe({
    required double largeur,
    required List<(String, int, int)> groupes,
    required List<Widget> lignes,
    required String vide,
    Widget? pied,
  }) {
    // ⚠️ Le nombre de feuilles déclarées doit égaler celui des sous-colonnes
    // rendues : si les deux divergent, l'en-tête ment sur le tableau.
    assert(
      colonnesBalance.length == groupes.fold<int>(0, (t, g) => t + g.$3),
      'Les colonnes déclarées ne correspondent plus aux groupes rendus.',
    );
    return Container(
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: largeur,
          child: Column(
            children: [
              // Premier niveau : les groupes.
              Container(
                color: AgriColors.surfaceZebra,
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                child: Row(
                  children: [
                    for (final (libelle, poids, sous) in groupes)
                      Expanded(
                        flex: poids,
                        child: Text(
                          libelle.toUpperCase(),
                          textAlign: sous > 1
                              ? TextAlign.center
                              : TextAlign.start,
                          style: _enteteColonne,
                        ),
                      ),
                  ],
                ),
              ),
              // Second niveau : les sous-colonnes des groupes.
              Container(
                color: AgriColors.surfaceZebra,
                padding: const EdgeInsets.only(
                  left: AgriSpacing.md,
                  right: AgriSpacing.md,
                  bottom: AgriSpacing.xs,
                ),
                child: Row(
                  children: [
                    for (final (_, poids, sous) in groupes)
                      Expanded(
                        flex: poids,
                        child: sous > 1
                            ? Row(
                                children: [
                                  Expanded(
                                    child: Text('DÉBIT', style: _enteteColonne),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'CRÉDIT',
                                      style: _enteteColonne,
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
              if (lignes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AgriSpacing.lg),
                  child: Text(
                    vide,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontStyle: FontStyle.italic,
                      color: AgriColors.outline,
                    ),
                  ),
                ),
              ...lignes,
              ?pied,
            ],
          ),
        ),
      ),
    );
  }

  /// Colonnes FEUILLES de la Balance, déclarées à plat pour le contrôle de
  /// structure — `_tableauGroupe` les rend sous leurs trois groupes.
  static const colonnesBalance = <(String, int)>[
    ('N° Compte', 2),
    ('Libellé', 5),
    ('Débit', 2),
    ('Crédit', 2),
    ('Débit', 2),
    ('Crédit', 2),
    ('Débit', 2),
    ('Crédit', 2),
  ];

  Widget _tableau({
    required double largeur,
    required List<(String, int)> colonnes,
    required List<Widget> lignes,
    required String vide,
  }) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: largeur,
        child: Column(
          children: [
            Container(
              color: AgriColors.surfaceZebra,
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
              child: Row(
                children: [
                  for (final (libelle, flex) in colonnes)
                    Expanded(
                      flex: flex,
                      child: Text(libelle.toUpperCase(), style: _enteteColonne),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  vide,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            ...lignes,
          ],
        ),
      ),
    ),
  );

  Widget _ligne(int index, List<(Widget, int)> cellules) => Container(
    key: Key('ligne-$index'),
    color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(
      children: [
        for (final (contenu, flex) in cellules)
          Expanded(flex: flex, child: contenu),
      ],
    ),
  );

  Widget _actionInerte() => const Opacity(
    opacity: 0.4,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Icon(Icons.visibility, size: 16, color: AgriColors.outline),
    ),
  );

  Widget _mentionPoste(String texte) => Container(
    key: const Key('mention-poste'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.accentYellow.withValues(alpha: 0.10),
      border: Border.all(
        color: AgriColors.accentYellow.withValues(alpha: 0.30),
      ),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 18, color: AgriColors.brandForest),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Text(
            texte,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
    ),
  );

  /// ⚠️⚠️ **LES FORMATEURS SONT CEUX DU DOCUMENT ÉDITÉ** (ticket F0.87) : un seul endroit
  /// (`DocumentsComptabilite`) écrit un montant, un tiret ou une date, à l'écran comme sur le PDF.
  /// Règles inchangées : « — » pour un montant nul (`> 0 ? montant : '—'`) ; signe lu sur la valeur
  /// ARRONDIE (F0.86-bis, jamais « -0 »).
  static String _montantOuTiret(double valeur) =>
      DocumentsComptabilite.montantOuTiret(valeur);

  static String _montant(double valeur) =>
      DocumentsComptabilite.montant(valeur);

  static String _date(DateTime d) => DocumentsComptabilite.jour(d);
}
