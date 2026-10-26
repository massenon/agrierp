import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import 'attestations_repository.dart';
import 'attestations_vue.dart';
import 'personnel_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/personnel-stages.html` → Personnel & Stages.
///
/// ⚠️⚠️ **HUB À CINQ ONGLETS**, dans l'ordre du hub : Registre Employés ·
/// Registre Stagiaires · Feuille de Pointage · Gestion de la Paie ·
/// Attestations.
///
/// ⚠️⚠️ **UN SEUL DES CINQ ÉCRIT, ET C'EST LE BON.** Le pointage est l'acte de
/// terrain par excellence : il se fait à 7 h à la ferme, là où le réseau n'est
/// pas. Les registres sont des référentiels du serveur ; la paie se calcule
/// avec le barème ITS et les retenues CNSS que le poste ne reçoit pas.
///
/// ⚠️ **L'ONGLET « ATTESTATIONS » EST PORTÉ (ticket F0.64)** : il génère le PDF
/// auprès du serveur — qui le produit ET le compte — et édite les modèles. Il
/// exige donc le réseau. Voir [AttestationsVue].
class PersonnelStagesScreen extends StatefulWidget {
  const PersonnelStagesScreen({
    super.key,
    required this.depot,
    this.attestations,
    this.enregistrerAttestation,
    this.imprimerAttestation,
  });

  final PersonnelRepository depot;

  /// `null` : aucun accès aux attestations (tests sans serveur) — l'onglet le dit.
  final AttestationsRepository? attestations;

  /// Écrit le PDF d'une attestation. Par défaut : Documents\AgriERP.
  final Future<String> Function(PdfAttestation)? enregistrerAttestation;

  /// Ouvre la boîte d'impression. Par défaut : celle de Windows.
  final Future<void> Function(PdfAttestation)? imprimerAttestation;

  @override
  State<PersonnelStagesScreen> createState() => _PersonnelStagesScreenState();
}

class _PersonnelStagesScreenState extends State<PersonnelStagesScreen> {
  /// Les cinq onglets du hub, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Registre Employés', SymbolesAgri.badge),
    ('Registre Stagiaires', SymbolesAgri.school),
    ('Feuille de Pointage', SymbolesAgri.fact_check),
    ('Gestion de la Paie', SymbolesAgri.payments),
    ('Attestations', SymbolesAgri.workspace_premium),
  ];

  String _onglet = onglets.first.$1;
  DonneesPersonnel? _donnees;
  String? _message;

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
                      _barreOnglets(),
                      const SizedBox(height: AgriSpacing.lg),
                      switch (_onglet) {
                        'Registre Stagiaires' => _ongletStagiaires(d, large),
                        'Feuille de Pointage' => _ongletPointage(d, large),
                        'Gestion de la Paie' => _ongletPaie(d, large),
                        'Attestations' => _ongletAttestations(large),
                        _ => _ongletEmployes(d, large),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (titre, icone) in onglets)
            InkWell(
              key: Key('onglet-personnel-$titre'),
              onTap: () => setState(() {
                _onglet = titre;
                _message = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icone,
                      size: 18,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : AgriColors.outline,
                    ),
                    const SizedBox(width: AgriSpacing.xs),
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: AgriTypography.gras,
                        color: _onglet == titre
                            ? AgriColors.brandEmerald
                            : AgriColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  // ── Onglet 1 : Registre Employés ──────────────────────────────────────────

  Widget _ongletEmployes(DonneesPersonnel d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Registre des Employés', large),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ LES DEUX CARTES DE `registre-employes.html` (`badge`, `person_add`),
      // trouvées manquantes par le comptage du ticket F0.54.
      _grilleKpis(large, [
        CarteKpi(
          key: const Key('kpi-employes-actifs'),
          libelle: 'Employés actifs',
          valeur: '${d.employesActifs}',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.badge,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-employes-nouveaux'),
          libelle: 'Nouveaux (année)',
          valeur: '${d.nouveauxEmployesDeLAnnee}',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.person_add,
          couleurIcone: AgriColors.outline,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 950,
        colonnes: const [
          ('Nom', 4),
          ('Fonction', 4),
          ("Date d'embauche", 3),
          ('Salaire', 3),
          ('Statut', 3),
          ('Actions', 2),
        ],
        vide: '— Aucun employé synchronisé —',
        lignes: [
          for (var i = 0; i < d.employes.length; i++)
            _ligne(i, [
              (
                Text(
                  '${d.employes[i].firstName} ${d.employes[i].lastName}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                4,
              ),
              (
                Text(
                  d.employes[i].position ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              (Text(_date(d.employes[i].hireDate), style: _cellule), 3),
              (Text(_montant(d.employes[i].baseSalary), style: _cellule), 3),
              (_pastille(d.employes[i].status ?? '—'), 3),
              (_actionInerte(), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      _mentionPoste(
        "L'embauche, la modification d'un salaire et l'archivage se font sur "
        'la surface web : le serveur sert le registre en lecture seule.',
      ),
    ],
  );

  // ── Onglet 2 : Registre Stagiaires ────────────────────────────────────────

  Widget _ongletStagiaires(DonneesPersonnel d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Registre des Stagiaires', large),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ LES QUATRE CARTES DE `registre-stagiaires.html`, dans son ordre et
      // avec ses couleurs : `school` émeraude, `payments` bleu, `pending`
      // jaune, `workspace_premium` forêt.
      _grilleKpis(large, [
        CarteKpi(
          key: const Key('kpi-stagiaires-actifs'),
          libelle: 'Stagiaires Actifs',
          valeur: '${d.stagiairesActifs}',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.school,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-stagiaires-collectes'),
          libelle: 'Frais Collectés',
          valeur: _montant(d.fraisCollectes),
          couleurLisere: AgriColors.infoBlue,
          icone: SymbolesAgri.payments,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-stagiaires-attente'),
          libelle: 'Frais en Attente',
          valeur: _montant(d.fraisEnAttente),
          couleurLisere: AgriColors.accentYellow,
          icone: SymbolesAgri.pending,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-stagiaires-attestations'),
          // ⚠️⚠️ UN TIRET, JAMAIS UN ZÉRO. Aucune table d'attestations ne
          // descend au poste — l'onglet « Attestations » le dit déjà. « 0 »
          // affirmerait qu'aucune n'a été délivrée.
          libelle: 'Attestations émises',
          valeur: d.attestationsEmises == null
              ? '—'
              : '${d.attestationsEmises}',
          legende: 'Décompte du serveur',
          couleurLisere: AgriColors.brandForest,
          icone: SymbolesAgri.workspace_premium,
          couleurIcone: AgriColors.outline,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1000,
        colonnes: const [
          ('Nom', 4),
          ("Établissement d'Origine", 4),
          ('Période', 4),
          ('Frais de Scolarité', 3),
          ('Statut', 3),
          ('Actions', 2),
        ],
        vide: '— Aucun stagiaire synchronisé —',
        lignes: [
          for (var i = 0; i < d.stagiaires.length; i++)
            _ligne(i, [
              (
                Text(
                  '${d.stagiaires[i].firstName} ${d.stagiaires[i].lastName}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                4,
              ),
              (
                Text(
                  d.stagiaires[i].school ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              (
                Text(
                  '${_date(d.stagiaires[i].startDate)} → '
                  '${_date(d.stagiaires[i].endDate)}',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              (Text(_montant(d.stagiaires[i].monthlyFee), style: _cellule), 3),
              (
                _pastille(
                  d.stagiaires[i].feePaid ? 'Frais réglés' : 'Frais dus',
                ),
                3,
              ),
              (_actionInerte(), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ LES ABSENCES DE STAGIAIRE VIVENT DANS `internship_absences`, une
      // table que le poste ne reçoit pas — et la feuille de pointage ne les
      // couvre pas non plus : `attendance_records.employee_id` pointe sur
      // `employees`, et un stagiaire n'est pas un employé.
      _mentionPoste(
        "Les absences d'un stagiaire se notent sur la surface web : elles "
        "vivent dans une table à part, et la feuille de pointage ne s'applique "
        "qu'aux employés — un stagiaire n'en est pas un dans le schéma.",
      ),
    ],
  );

  // ── Onglet 3 : Feuille de Pointage ────────────────────────────────────────

  Widget _ongletPointage(DonneesPersonnel d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Feuille de Pointage', large),
      const SizedBox(height: AgriSpacing.md),
      _grilleKpis(large, [
        CarteKpi(
          libelle: 'Présents',
          valeur: '${d.presents}',
          legende: 'Retards inclus',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.how_to_reg,
        ),
        CarteKpi(
          libelle: 'Absents',
          valeur: '${d.absents}',
          couleurLisere: AgriColors.errorRed,
          icone: SymbolesAgri.person_off,
          couleurIcone: AgriColors.errorRed,
        ),
        CarteKpi(
          libelle: 'Retards',
          valeur: '${d.retards}',
          couleurLisere: AgriColors.accentYellow,
          icone: SymbolesAgri.schedule,
          couleurIcone: AgriColors.brandForest,
        ),
        CarteKpi(
          libelle: 'À pointer',
          valeur: '${d.nonPointes().length}',
          legende: d.enAttenteDEnvoi > 0
              ? '${d.enAttenteDEnvoi} en attente d\'envoi'
              : 'Tout est parti',
          couleurLisere: AgriColors.infoBlue,
          icone: SymbolesAgri.pending_actions,
          couleurIcone: AgriColors.infoBlue,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const Key('ouvrir-pointage'),
          onPressed: d.employes.isEmpty ? null : () => _ouvrirPointage(d),
          icon: const Icon(SymbolesAgri.add, size: 18),
          style: FilledButton.styleFrom(
            backgroundColor: AgriColors.brandEmerald,
          ),
          label: const Text(
            'Enregistrer un Pointage',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
            ),
          ),
        ),
      ),
      if (_message != null) ...[
        const SizedBox(height: AgriSpacing.md),
        Container(
          key: const Key('bandeau-pointage'),
          padding: const EdgeInsets.all(AgriSpacing.sm),
          decoration: BoxDecoration(
            color: AgriColors.brandEmerald.withValues(alpha: 0.10),
            border: Border.all(
              color: AgriColors.brandEmerald.withValues(alpha: 0.30),
            ),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Text(
            _message!,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 950,
        colonnes: const [
          ('Employé', 4),
          ('Date', 3),
          ('Arrivée', 2),
          ('Départ', 2),
          ('Statut', 4),
          ('Actions', 2),
        ],
        vide: '— Aucun pointage synchronisé —',
        lignes: [
          for (var i = 0; i < d.pointages.length; i++)
            _ligne(i, [
              (
                Text(
                  d.pointages[i].nom,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                4,
              ),
              (
                Text(
                  _date(d.pointages[i].pointage.attendanceDate),
                  style: _cellule,
                ),
                3,
              ),
              (
                Text(_heure(d.pointages[i].pointage.checkIn), style: _cellule),
                2,
              ),
              (
                Text(_heure(d.pointages[i].pointage.checkOut), style: _cellule),
                2,
              ),
              (_statutPointage(d.pointages[i]), 4),
              (_actionInerte(), 2),
            ]),
        ],
      ),
    ],
  );

  Widget _statutPointage(LignePointage l) {
    if (!l.envoye) {
      return _pastille('Pas encore envoyé', couleur: AgriColors.accentYellow);
    }

    final couleur = switch (l.statut) {
      StatutPointage.present => AgriColors.brandEmerald,
      StatutPointage.retard => AgriColors.accentYellow,
      StatutPointage.absent => AgriColors.errorRed,
      _ => AgriColors.infoBlue,
    };

    return _pastille(l.statut.libelle, couleur: couleur);
  }

  /// La modale « Enregistrer un Pointage » de la maquette.
  void _ouvrirPointage(DonneesPersonnel d) {
    var employeId = d.employes.first.id;
    var statut = StatutPointage.present;
    final arrivee = TextEditingController(text: '07:00');
    final depart = TextEditingController();

    afficherModale<void>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, majModale) => ModaleAgri(
          titre: 'Enregistrer un Pointage',
          contenu: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _etiquette('Employé *'),
              DropdownButtonFormField<String>(
                key: const Key('pointage-employe'),
                initialValue: employeId,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontSize: AgriTypography.sm,
                  color: AgriColors.onSurface,
                ),
                items: [
                  for (final e in d.employes)
                    DropdownMenuItem(
                      value: e.id,
                      child: Text('${e.firstName} ${e.lastName}'),
                    ),
                ],
                onChanged: (v) => majModale(() => employeId = v ?? employeId),
              ),
              const SizedBox(height: AgriSpacing.sm),
              _etiquette('Statut *'),
              DropdownButtonFormField<StatutPointage>(
                key: const Key('pointage-statut'),
                initialValue: statut,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontSize: AgriTypography.sm,
                  color: AgriColors.onSurface,
                ),
                items: [
                  for (final s in StatutPointage.values)
                    DropdownMenuItem(value: s, child: Text(s.libelle)),
                ],
                onChanged: (v) => majModale(() => statut = v ?? statut),
              ),
              const SizedBox(height: AgriSpacing.sm),
              _etiquette("Heure d'arrivée *"),
              TextField(
                key: const Key('pointage-arrivee'),
                controller: arrivee,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '07:00',
                ),
                style: const TextStyle(fontSize: AgriTypography.sm),
              ),
              const SizedBox(height: AgriSpacing.sm),
              _etiquette('Heure de départ'),
              TextField(
                key: const Key('pointage-depart'),
                controller: depart,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '17:00',
                ),
                style: const TextStyle(fontSize: AgriTypography.sm),
              ),
              const SizedBox(height: AgriSpacing.sm),
              // ⚠️ La date est celle du jour : la maquette porte un champ
              // « Date * », mais un pointage antidaté depuis le terrain n'a
              // pas de sens — et le serveur refuse toute date future.
              const Text(
                "Le pointage porte la date du jour. Il partira à la prochaine "
                'synchronisation ; la ferme ne le connaît pas encore.',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(),
            ),
            BoutonModalePrimaire(
              libelle: 'Enregistrer',
              onPressed: () async {
                await widget.depot.pointer(
                  employeId: employeId,
                  jour: HeureBenin.maintenant(),
                  statut: statut,
                  arrivee: arrivee.text.trim().isEmpty
                      ? null
                      : arrivee.text.trim(),
                  depart: depart.text.trim().isEmpty
                      ? null
                      : depart.text.trim(),
                );

                if (!context.mounted) return;
                Navigator.of(context).pop();

                setState(
                  () => _message =
                      'Pointage enregistré sur ce poste — il partira à la '
                      'prochaine synchronisation.',
                );
                await _charger();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Onglet 4 : Gestion de la Paie ─────────────────────────────────────────

  Widget _ongletPaie(DonneesPersonnel d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Gestion de la Paie', large),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ LES QUATRE CARTES DE `gestion-paie.html` SONT PRÉSENTES ET TOUTES
      // À TIRET, et c'est le seul rendu honnête : la paie se calcule sur le
      // serveur, le poste ne reçoit que le salaire de BASE.
      //
      // Les retirer aurait été plus propre à l'œil et plus faux : la maquette
      // les demande, et un écran qui les tait laisserait croire que la ferme
      // n'a pas d'indicateur de paie. Chaque carte dit ce qui lui manque.
      _grilleKpis(large, [
        CarteKpi(
          key: const Key('kpi-paie-masse'),
          libelle: 'Masse Salariale',
          valeur: _montant(d.masseSalariale),
          legende: 'Calculée au serveur, charges comprises',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.account_balance_wallet,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-paie-bulletins'),
          libelle: 'Bulletins émis',
          valeur: d.bulletinsEmis == null ? '—' : '${d.bulletinsEmis}',
          legende: 'Bulletins non transmis au poste',
          couleurLisere: AgriColors.infoBlue,
          icone: SymbolesAgri.description,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-paie-cnss'),
          libelle: 'Charges Sociales (CNSS)',
          valeur: _montant(d.chargesSociales),
          // ⚠️ La part PATRONALE ne se déduit pas de la part salariale.
          legende: 'Taux et assiette côté serveur',
          couleurLisere: AgriColors.accentYellow,
          icone: SymbolesAgri.shield,
          couleurIcone: AgriColors.outline,
        ),
        CarteKpi(
          key: const Key('kpi-paie-attente'),
          libelle: 'En Attente de Paiement',
          valeur: d.bulletinsEnAttente == null
              ? '—'
              : '${d.bulletinsEnAttente}',
          legende: 'Statut porté par le bulletin',
          couleurLisere: AgriColors.errorRed,
          icone: SymbolesAgri.pending,
          couleurIcone: AgriColors.outline,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1200,
        colonnes: const [
          ('Employé', 4),
          ('Poste', 3),
          ('Salaire Brut', 3),
          ('Absences', 2),
          ('Ret. Absences', 3),
          ('Ret. CNSS', 3),
          ('Net à Payer', 3),
          ('Statut', 3),
          ('Actions', 2),
        ],
        vide: '— Aucun employé synchronisé —',
        lignes: [
          for (var i = 0; i < d.employes.length; i++)
            _ligne(i, [
              (
                Text(
                  '${d.employes[i].firstName} ${d.employes[i].lastName}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                4,
              ),
              (
                Text(
                  d.employes[i].position ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              (Text(_montant(d.employes[i].baseSalary), style: _cellule), 3),
              (const Text('—', style: _cellule), 2),
              (const Text('—', style: _cellule), 3),
              (const Text('—', style: _cellule), 3),
              (const Text('—', style: _cellule), 3),
              (const Text('—', style: _cellule), 3),
              (_actionInerte(), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ LE SALAIRE BRUT EST CONNU, LE NET NE L'EST PAS. Retenues CNSS et
      // barème ITS vivent sur le serveur, et les bulletins (`payslips`) ne
      // descendent pas. Recomposer un net à payer ici produirait un chiffre
      // que l'employé ne retrouverait sur aucun bulletin — et c'est son
      // salaire.
      _mentionPoste(
        'Le net à payer se calcule sur la surface web : barème ITS, retenues '
        "CNSS et bulletins n'existent pas au poste. Afficher un net calculé "
        "d'ici donnerait à l'employé un chiffre que son bulletin ne "
        'confirmerait pas.',
      ),
    ],
  );

  // ── Onglet 5 : Attestations ───────────────────────────────────────────────

  Widget _ongletAttestations(bool large) {
    final depot = widget.attestations;

    if (depot == null) {
      return _mentionPoste(
        'Les attestations ne sont pas disponibles : aucune session ouverte.',
      );
    }

    return AttestationsVue(
      depot: depot,
      enregistrer:
          widget.enregistrerAttestation ?? LivraisonAttestation.enregistrer,
      imprimer: widget.imprimerAttestation ?? LivraisonAttestation.imprimer,
    );
  }

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

  Widget _etiquette(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
    child: Text(
      texte.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: AgriTypography.gras,
        color: AgriColors.brandForest,
      ),
    ),
  );

  Widget _pastille(String libelle, {Color couleur = AgriColors.brandEmerald}) =>
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            libelle,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: AgriTypography.gras,
              color: couleur == AgriColors.accentYellow
                  ? AgriColors.brandForest
                  : couleur,
            ),
          ),
        ),
      );

  Widget _grilleKpis(bool large, List<Widget> cartes) => GrilleKpi(colonnes: large ? cartes.length : 2, children: cartes,
  );

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
    child: LayoutBuilder(
      builder: (_, contraintes) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: max(largeur, contraintes.maxWidth),
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
      child: Icon(SymbolesAgri.visibility, size: 16, color: AgriColors.outline),
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
        const Icon(SymbolesAgri.info, size: 18, color: AgriColors.brandForest),
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

  static String _montant(double? valeur) {
    if (valeur == null) return '—';
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  /// ⚠️ Le serveur sert « 07:05:00 » : la maquette affiche « 07:05 ».
  static String _heure(String? h) {
    if (h == null || h.isEmpty) return '—';
    final morceaux = h.split(':');
    return morceaux.length >= 2 ? '${morceaux[0]}:${morceaux[1]}' : h;
  }

  static String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
