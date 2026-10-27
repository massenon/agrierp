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
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/erreurs/message_erreur.dart';

/// `prototype_html/personnel-stages.html` → Personnel & Stages.
///
/// ⚠️⚠️ **HUB À CINQ ONGLETS**, dans l'ordre du hub : Registre Employés ·
/// Registre Stagiaires · Feuille de Pointage · Gestion de la Paie ·
/// Attestations.
///
/// ⚠️⚠️ **LES CINQ ONGLETS ÉCRIVENT, HORS LIGNE** (tickets RH-1 à RH-4, PRD `docs/prd/rh-crud-poste.md`) : employés,
/// stagiaires, absences de stagiaire, pointages (création, modification, archivage) partent `pending` et sont rejoués
/// au serveur par les Actions du web (`SaisieEmployeAction`, `SaisieStagiaireAction`, `pushAttendance`) ; la paie se
/// calcule ici comme au web (`CalculPaie`) et « Valider le règlement » envoie une DEMANDE (`ReglementPaieService`).
///
/// ⚠️ **L'ONGLET « ATTESTATIONS » EST PORTÉ (ticket F0.64, ATT-3)** : le poste fabrique le PDF ; le serveur attribue le
/// numéro et garde la trace. Voir [AttestationsVue].
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

  /// RH-Q1 — le filtre « statut » de `registre-employes.blade.php` (`''`, `actif`, `conge`, `suspendu`, `archive`).
  String _filtreEmployes = '';

  /// Les options du filtre, dans l'ordre et avec les mots du Blade.
  static const filtresEmployes = <(String, String)>[
    ('', 'Tous les statuts'),
    ('actif', 'Actif'),
    ('conge', 'Congé'),
    ('suspendu', 'Suspendu'),
    ('archive', 'Archivé'),
  ];

  /// Ticket RH-4 — le mois affiché par « Gestion de la Paie » (`AAAA-MM`), le mois courant à l'ouverture.
  late String _periodePaie = PersonnelRepository.periodeDe(HeureBenin.maintenant());
  PaieDuMois? _paie;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    final paie = await widget.depot.paie(_periodePaie);
    if (!mounted) return;
    setState(() {
      _donnees = donnees;
      _paie = paie;
    });
  }

  static String _ecrire(DateTime? d) => d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';

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

  // ── Briques de saisie (modales) ───────────────────────────────────────────

  /// `jj/mm/aaaa` → date, `null` si vide ou invalide (`DateTime(2026, 2, 31)` déborderait : refusé).
  static DateTime? _lire(String texte) {
    final m = RegExp(r'^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*$').firstMatch(texte);
    if (m == null) return null;
    final j = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final a = int.parse(m.group(3)!);
    final d = DateTime(a, mo, j);
    return (d.year == a && d.month == mo && d.day == j) ? d : null;
  }

  Widget _champ(String cle, TextEditingController c, {String? indication, String? erreur, TextInputType? clavier}) =>
      TextField(
        key: Key(cle),
        controller: c,
        keyboardType: clavier,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          hintText: indication,
          errorText: erreur,
        ),
        style: const TextStyle(fontSize: AgriTypography.sm),
      );

  Widget _liste<T>({
    required String cle,
    required T valeur,
    required List<(T, String)> choix,
    required ValueChanged<T?>? onChanged,
  }) => DropdownButtonFormField<T>(
    key: Key(cle),
    initialValue: valeur,
    isDense: true,
    isExpanded: true,
    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
    style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
    items: [for (final (v, libelle) in choix) DropdownMenuItem(value: v, child: Text(libelle))],
    onChanged: onChanged,
  );

  Widget _boutonAjout(String cle, String libelle, VoidCallback? onPressed) => Align(
    alignment: Alignment.centerLeft,
    child: FilledButton.icon(
      key: Key(cle),
      onPressed: onPressed,
      icon: const Icon(SymbolesAgri.add, size: 18),
      style: FilledButton.styleFrom(backgroundColor: AgriColors.brandEmerald),
      label: Text(libelle, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
    ),
  );

  Widget _actions(List<(String, IconData, Color, VoidCallback?)> boutons) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      for (final (cle, icone, couleur, onPressed) in boutons)
        IconButton(
          key: Key(cle),
          onPressed: onPressed,
          icon: Icon(icone, size: 18, color: onPressed == null ? AgriColors.outline : couleur),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
    ],
  );

  /// Un refus (règles du web) s'affiche dans la modale, champ par champ ; une erreur technique, en français.
  Future<bool> _tenter(Future<void> Function() geste, void Function(Map<String, String>) surRefus) async {
    try {
      await geste();
      return true;
    } on RefusSaisieRh catch (e) {
      surRefus(e.champs);
      return false;
    } on Object catch (e) {
      surRefus({'': messageErreur(e)});
      return false;
    }
  }

  Widget _bandeau(String texte, {Key? cle}) => Container(
    key: cle,
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.brandEmerald.withValues(alpha: 0.10),
      border: Border.all(color: AgriColors.brandEmerald.withValues(alpha: 0.30)),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Text(texte, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.brandForest)),
  );

  Future<void> _confirmerArchivage(String titre, String message, Future<void> Function() geste, String succes) async {
    await afficherModale<void>(
      context: context,
      constructeur: (context) => ModaleConfirmation(
        icone: SymbolesAgri.archive,
        titre: titre,
        message: message,
        couleurIcone: AgriColors.accentYellow,
        actions: [
          BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
          BoutonModalePrimaire(
            libelle: 'Archiver',
            couleur: AgriColors.errorRed,
            onPressed: () async {
              await geste();
              if (!context.mounted) return;
              Navigator.of(context).pop();
              setState(() => _message = succes);
              await _charger();
            },
          ),
        ],
      ),
    );
  }

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
      // Ticket RH-1 — « Nouvel Employé » (bouton de `registre-employes.blade.php`), créé hors ligne.
      _boutonAjout('nouvel-employe', 'Nouvel Employé', () => _ouvrirEmploye(null)),
      const SizedBox(height: AgriSpacing.md),
      // RH-Q1 — le filtre « statut » du Blade ; « Archivé » liste les employés archivés, en lecture.
      Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 220,
          child: _liste<String>(
            cle: 'employes-filtre',
            valeur: _filtreEmployes,
            choix: filtresEmployes,
            onChanged: (v) => setState(() => _filtreEmployes = v ?? ''),
          ),
        ),
      ),
      if (_message != null && _onglet == 'Registre Employés') ...[
        const SizedBox(height: AgriSpacing.md),
        _bandeau(_message!, cle: const Key('bandeau-employes')),
      ],
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
        vide: '— Aucun employé —',
        lignes: [
          for (final (i, e) in d.employesFiltres(_filtreEmployes).indexed)
            _ligne(i, [
              (
                Text(
                  '${e.firstName} ${e.lastName}',
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
                  e.position ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              (Text(_date(e.hireDate), style: _cellule), 3),
              (Text(_montant(e.baseSalary), style: _cellule), 3),
              (
                _pastilleEmploye(e),
                3,
              ),
              (
                // RH-Q1 — un employé archivé est en lecture (« Lecture seule », comme le Blade) : ni « Modifier » ni « Archiver ».
                e.isActive
                    ? _actions([
                        ('employe-modifier-$i', SymbolesAgri.edit, AgriColors.infoBlue, () => _ouvrirEmploye(e)),
                        (
                          'employe-archiver-$i',
                          SymbolesAgri.archive,
                          AgriColors.errorRed,
                          () => _confirmerArchivage(
                            "Archiver l'employé",
                            '${e.lastName} ${e.firstName} sera archivé(e) : il restera restaurable depuis la Corbeille.',
                            () => widget.depot.archiverEmploye(e.id),
                            'Employé archivé avec succès.',
                          ),
                        ),
                      ])
                    : Text('Lecture seule', key: Key('employe-lecture-seule-$i'), textAlign: TextAlign.right, style: const TextStyle(fontSize: AgriTypography.xs, fontStyle: FontStyle.italic, color: AgriColors.outline)),
                2,
              ),
            ]),
        ],
      ),
    ],
  );

  Widget _pastilleEmploye(Employee e) {
    // RH-Q1 — « Archivé » avant le statut, comme le Blade.
    final libelle = !e.isActive ? 'Archivé' : PersonnelRepository.statutsEmploye[e.status] ?? (e.status ?? '—');
    final couleur = !e.isActive
        ? AgriColors.outline
        : switch (e.status) {
            'conge' => AgriColors.accentYellow,
            'suspendu' => AgriColors.errorRed,
            _ => AgriColors.brandEmerald,
          };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: _pastille(libelle, couleur: couleur)),
        if (e.syncStatus != SyncStatus.synced) ...[
          const SizedBox(width: AgriSpacing.xs),
          Flexible(child: _pastille(e.syncStatus == SyncStatus.conflict ? 'Refusé' : 'Pas encore envoyé', couleur: e.syncStatus == SyncStatus.conflict ? AgriColors.errorRed : AgriColors.accentYellow)),
        ],
      ],
    );
  }

  /// La modale « Nouvel Employé » / « Modifier l'Employé » de `registre-employes.blade.php` — mêmes champs, même liste.
  void _ouvrirEmploye(Employee? e) {
    final prenom = TextEditingController(text: e?.firstName ?? '');
    final nom = TextEditingController(text: e?.lastName ?? '');
    final embauche = TextEditingController(text: _ecrire(e?.hireDate ?? HeureBenin.aujourdhui()));
    final salaire = TextEditingController(text: e?.baseSalary == null ? '' : e!.baseSalary!.round().toString());
    var fonction = e?.position ?? '';
    var statut = e?.status ?? 'actif';
    var erreurs = <String, String>{};

    afficherModale<void>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, majModale) => ModaleAgri(
          titre: e == null ? 'Nouvel Employé' : "Modifier l'Employé",
          contenu: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (erreurs[''] != null) ...[
                Text(erreurs['']!, key: const Key('employe-erreur'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorRed)),
                const SizedBox(height: AgriSpacing.sm),
              ],
              Row(
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_etiquette('Prénom *'), _champ('employe-prenom', prenom, indication: 'ex : Bernadin', erreur: erreurs['prenom'])])),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_etiquette('Nom *'), _champ('employe-nom', nom, indication: 'ex : ADJOVI', erreur: erreurs['nom'])])),
                ],
              ),
              const SizedBox(height: AgriSpacing.sm),
              _etiquette('Fonction *'),
              _liste<String>(
                cle: 'employe-fonction',
                valeur: fonction,
                choix: [
                  ('', '-- Sélectionner --'),
                  for (final f in PersonnelRepository.fonctions) (f, f),
                  if (fonction.isNotEmpty && !PersonnelRepository.fonctions.contains(fonction)) (fonction, fonction),
                ],
                onChanged: (v) => majModale(() => fonction = v ?? ''),
              ),
              if (erreurs['fonction'] != null) Text(erreurs['fonction']!, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorRed)),
              const SizedBox(height: AgriSpacing.sm),
              Row(
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_etiquette("Date d'embauche *"), _champ('employe-embauche', embauche, indication: 'jj/mm/aaaa', erreur: erreurs['embauche'])])),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_etiquette('Salaire de base (FCFA)'), _champ('employe-salaire', salaire, indication: 'ex : 85000', erreur: erreurs['salaire'], clavier: TextInputType.number)])),
                ],
              ),
              const SizedBox(height: AgriSpacing.sm),
              _etiquette('Statut'),
              _liste<String>(
                cle: 'employe-statut',
                valeur: statut,
                choix: [for (final s in PersonnelRepository.statutsEmploye.entries) (s.key, s.value)],
                onChanged: (v) => majModale(() => statut = v ?? 'actif'),
              ),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
            BoutonModalePrimaire(
              libelle: 'Enregistrer',
              onPressed: () async {
                final ok = await _tenter(
                  () => widget.depot.enregistrerEmploye(
                    id: e?.id,
                    prenom: prenom.text,
                    nom: nom.text,
                    fonction: fonction,
                    embauche: _lire(embauche.text),
                    salaire: salaire.text.trim().isEmpty ? null : double.tryParse(salaire.text.trim().replaceAll(' ', '')),
                    statut: statut,
                  ),
                  (champs) => majModale(() => erreurs = champs),
                );
                if (!ok || !context.mounted) return;
                Navigator.of(context).pop();
                setState(() => _message = e == null ? 'Enregistrement effectué avec succès.' : 'Modification enregistrée avec succès.');
                await _charger();
              },
            ),
          ],
        ),
      ),
    );
  }

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
          // ⚠️⚠️ UN TIRET, JAMAIS UN ZÉRO. « 0 » affirmerait qu'aucune n'a été délivrée : c'est le décompte du serveur.
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
      // Ticket RH-2 — « Nouveau Stagiaire » (bouton de `registre-stagiaires.blade.php`), créé hors ligne.
      _boutonAjout('nouveau-stagiaire', 'Nouveau Stagiaire', () => _ouvrirStagiaire(null)),
      if (_message != null && _onglet == 'Registre Stagiaires') ...[
        const SizedBox(height: AgriSpacing.md),
        _bandeau(_message!, cle: const Key('bandeau-stagiaires')),
      ],
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
        vide: '— Aucun stagiaire —',
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: _pastille(d.stagiaires[i].feePaid ? 'Frais réglés' : 'Frais dus', couleur: d.stagiaires[i].feePaid ? AgriColors.brandEmerald : AgriColors.accentYellow)),
                    if (d.stagiaires[i].syncStatus != SyncStatus.synced) ...[
                      const SizedBox(width: AgriSpacing.xs),
                      Flexible(child: _pastille(d.stagiaires[i].syncStatus == SyncStatus.conflict ? 'Refusé' : 'Pas encore envoyé', couleur: d.stagiaires[i].syncStatus == SyncStatus.conflict ? AgriColors.errorRed : AgriColors.accentYellow)),
                    ],
                  ],
                ),
                3,
              ),
              (
                _actions([
                  ('stagiaire-modifier-$i', SymbolesAgri.edit, AgriColors.infoBlue, () => _ouvrirStagiaire(d.stagiaires[i])),
                  ('stagiaire-absences-$i', SymbolesAgri.event, AgriColors.brandForest, () => _ouvrirAbsences(d.stagiaires[i])),
                ]),
                2,
              ),
            ]),
        ],
      ),
    ],
  );

  /// La modale « Nouveau Stagiaire » / « Modifier le Stagiaire » de `registre-stagiaires.blade.php`.
  void _ouvrirStagiaire(Internship? s) {
    final prenom = TextEditingController(text: s?.firstName ?? '');
    final nom = TextEditingController(text: s?.lastName ?? '');
    final etablissement = TextEditingController(text: s?.school ?? '');
    final debut = TextEditingController(text: _ecrire(s?.startDate ?? HeureBenin.aujourdhui()));
    final fin = TextEditingController(text: _ecrire(s?.endDate));
    final frais = TextEditingController(text: s?.monthlyFee == null ? '' : s!.monthlyFee!.round().toString());
    var fraisRegles = s?.feePaid ?? false;
    var erreurs = <String, String>{};

    afficherModale<void>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, majModale) => ModaleAgri(
          titre: s == null ? 'Nouveau Stagiaire' : 'Modifier le Stagiaire',
          contenu: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (erreurs[''] != null) ...[
                Text(erreurs['']!, key: const Key('stagiaire-erreur'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorRed)),
                const SizedBox(height: AgriSpacing.sm),
              ],
              Row(
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_etiquette('Prénom *'), _champ('stagiaire-prenom', prenom, erreur: erreurs['prenom'])])),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_etiquette('Nom *'), _champ('stagiaire-nom', nom, erreur: erreurs['nom'])])),
                ],
              ),
              const SizedBox(height: AgriSpacing.sm),
              _etiquette("Établissement d'origine *"),
              _champ('stagiaire-etablissement', etablissement, indication: 'ex : Lycée agricole de Sékou', erreur: erreurs['etablissement']),
              const SizedBox(height: AgriSpacing.sm),
              Row(
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_etiquette('Date de début *'), _champ('stagiaire-debut', debut, indication: 'jj/mm/aaaa', erreur: erreurs['debut'])])),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_etiquette('Date de fin'), _champ('stagiaire-fin', fin, indication: 'jj/mm/aaaa', erreur: erreurs['fin'])])),
                ],
              ),
              const SizedBox(height: AgriSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_etiquette('Frais de stage (FCFA)'), _champ('stagiaire-frais', frais, indication: 'ex : 25000', erreur: erreurs['frais'], clavier: TextInputType.number)])),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(
                    child: InkWell(
                      key: const Key('stagiaire-frais-regles'),
                      onTap: () => majModale(() => fraisRegles = !fraisRegles),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(value: fraisRegles, onChanged: (v) => majModale(() => fraisRegles = v ?? false)),
                          const Text('Frais réglés', style: TextStyle(fontSize: AgriTypography.sm)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
            BoutonModalePrimaire(
              libelle: 'Enregistrer',
              onPressed: () async {
                final ok = await _tenter(
                  () => widget.depot.enregistrerStagiaire(
                    id: s?.id,
                    prenom: prenom.text,
                    nom: nom.text,
                    etablissement: etablissement.text,
                    debut: _lire(debut.text),
                    fin: fin.text.trim().isEmpty ? null : _lire(fin.text),
                    frais: frais.text.trim().isEmpty ? null : double.tryParse(frais.text.trim().replaceAll(' ', '')),
                    fraisRegles: fraisRegles,
                  ),
                  (champs) => majModale(() => erreurs = champs),
                );
                if (!ok || !context.mounted) return;
                Navigator.of(context).pop();
                setState(() => _message = s == null ? 'Enregistrement effectué avec succès.' : 'Modification enregistrée avec succès.');
                await _charger();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// La modale « Absences » de `registre-stagiaires.blade.php` : la liste des absences actives, une date, un motif.
  void _ouvrirAbsences(Internship s) {
    final jour = TextEditingController(text: _ecrire(HeureBenin.aujourdhui()));
    final motif = TextEditingController();
    var erreurs = <String, String>{};
    var absences = _donnees?.absencesDe(s.id) ?? const <InternshipAbsence>[];

    afficherModale<void>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, majModale) => ModaleAgri(
          titre: 'Absences — ${s.lastName} ${s.firstName}',
          contenu: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_etiquette('Date *'), _champ('absence-date', jour, indication: 'jj/mm/aaaa', erreur: erreurs['date'])])),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_etiquette('Motif'), _champ('absence-motif', motif, indication: 'ex : Maladie', erreur: erreurs['motif'])])),
                ],
              ),
              if (erreurs[''] != null) Text(erreurs['']!, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorRed)),
              const SizedBox(height: AgriSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: BoutonModalePrimaire(
                  libelle: "Ajouter l'absence",
                  onPressed: () async {
                    final ok = await _tenter(
                      () => widget.depot.noterAbsence(stagiaireId: s.id, jour: _lire(jour.text), motif: motif.text),
                      (champs) => majModale(() => erreurs = champs),
                    );
                    if (!ok) return;
                    await _charger();
                    majModale(() {
                      erreurs = {};
                      motif.clear();
                      absences = _donnees?.absencesDe(s.id) ?? const [];
                    });
                  },
                ),
              ),
              const SizedBox(height: AgriSpacing.md),
              if (absences.isEmpty)
                const Text('Aucune absence enregistrée.', key: Key('absences-vide'), style: TextStyle(fontSize: AgriTypography.xs, fontStyle: FontStyle.italic, color: AgriColors.outline))
              else
                for (var i = 0; i < absences.length; i++)
                  Row(
                    key: Key('absence-$i'),
                    children: [
                      Expanded(child: Text('${_date(absences[i].absenceDate)} — ${absences[i].reason ?? '—'}', style: _cellule)),
                      if (absences[i].syncStatus != SyncStatus.synced)
                        _pastille('Pas encore envoyé', couleur: AgriColors.accentYellow),
                      IconButton(
                        key: Key('absence-archiver-$i'),
                        icon: const Icon(SymbolesAgri.delete, size: 18, color: AgriColors.errorRed),
                        onPressed: () async {
                          await widget.depot.archiverAbsence(absences[i].id);
                          await _charger();
                          majModale(() => absences = _donnees?.absencesDe(s.id) ?? const []);
                        },
                      ),
                    ],
                  ),
            ],
          ),
          actions: [BoutonModaleSecondaire(libelle: 'Fermer', onPressed: () => Navigator.of(context).pop())],
        ),
      ),
    );
  }

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
      _boutonAjout('ouvrir-pointage', 'Enregistrer un Pointage', d.employes.isEmpty ? null : () => _ouvrirPointage(d, null)),
      if (_message != null && _onglet == 'Feuille de Pointage') ...[
        const SizedBox(height: AgriSpacing.md),
        _bandeau(_message!, cle: const Key('bandeau-pointage')),
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
        vide: '— Aucun pointage —',
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
              (
                _actions([
                  ('pointage-modifier-$i', SymbolesAgri.edit, AgriColors.infoBlue, () => _ouvrirPointage(d, d.pointages[i].pointage)),
                  (
                    'pointage-archiver-$i',
                    SymbolesAgri.archive,
                    AgriColors.errorRed,
                    () => _confirmerArchivage(
                      'Archiver le pointage',
                      'Le pointage de ${d.pointages[i].nom} du ${_date(d.pointages[i].pointage.attendanceDate)} sera archivé : il ne comptera plus.',
                      () => widget.depot.archiverPointage(d.pointages[i].pointage.id),
                      'Pointage archivé avec succès.',
                    ),
                  ),
                ]),
                2,
              ),
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

  /// La modale « Enregistrer un Pointage » de la maquette (création ou modification, ticket RH-3 : date saisissable).
  void _ouvrirPointage(DonneesPersonnel d, AttendanceRecord? existant) {
    var employeId = existant?.employeeId ?? d.employes.first.id;
    var statut = existant == null ? StatutPointage.present : StatutPointage.depuis(existant.status);
    final jour = TextEditingController(text: _ecrire(existant?.attendanceDate ?? HeureBenin.aujourdhui()));
    final arrivee = TextEditingController(text: existant == null ? '07:00' : _heure(existant.checkIn).replaceAll('—', ''));
    final depart = TextEditingController(text: existant == null ? '' : _heure(existant.checkOut).replaceAll('—', ''));
    var erreurs = <String, String>{};
    final employes = d.employes.any((e) => e.id == employeId) ? d.employes : [...d.employes];

    afficherModale<void>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, majModale) => ModaleAgri(
          titre: existant == null ? 'Enregistrer un Pointage' : 'Modifier le Pointage',
          contenu: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (erreurs[''] != null) Text(erreurs['']!, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorRed)),
              _etiquette('Employé *'),
              _liste<String>(
                cle: 'pointage-employe',
                valeur: employes.any((e) => e.id == employeId) ? employeId : employes.first.id,
                choix: [for (final e in employes) (e.id, '${e.firstName} ${e.lastName}')],
                onChanged: existant == null ? (v) => majModale(() => employeId = v ?? employeId) : null,
              ),
              const SizedBox(height: AgriSpacing.sm),
              _etiquette('Date *'),
              _champ('pointage-date', jour, indication: 'jj/mm/aaaa', erreur: erreurs['date']),
              const SizedBox(height: AgriSpacing.sm),
              _etiquette('Statut *'),
              _liste<StatutPointage>(
                cle: 'pointage-statut',
                valeur: statut,
                choix: [for (final s in StatutPointage.values) (s, s.libelle)],
                onChanged: (v) => majModale(() => statut = v ?? statut),
              ),
              const SizedBox(height: AgriSpacing.sm),
              _etiquette("Heure d'arrivée *"),
              _champ('pointage-arrivee', arrivee, indication: '07:00', erreur: erreurs['arrivee']),
              const SizedBox(height: AgriSpacing.sm),
              _etiquette('Heure de départ'),
              _champ('pointage-depart', depart, indication: '17:00', erreur: erreurs['depart']),
              const SizedBox(height: AgriSpacing.sm),
              const Text(
                'Un seul pointage par employé et par jour : repointer le même jour corrige. Il partira à la prochaine '
                'synchronisation ; la ferme ne le connaît pas encore.',
                style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
              ),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
            BoutonModalePrimaire(
              libelle: 'Enregistrer',
              onPressed: () async {
                final date = _lire(jour.text);
                if (date == null) {
                  majModale(() => erreurs = {'date': 'Date invalide (jj/mm/aaaa).'});
                  return;
                }
                final ok = await _tenter(
                  () => widget.depot.pointer(
                    employeId: employeId,
                    jour: date,
                    statut: statut,
                    arrivee: arrivee.text.trim().isEmpty ? null : arrivee.text.trim(),
                    depart: depart.text.trim().isEmpty ? null : depart.text.trim(),
                  ),
                  (champs) => majModale(() => erreurs = champs),
                );
                if (!ok || !context.mounted) return;
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

  /// Ticket RH-4 — LA PAIE DU MOIS, CALCULÉE COMME LE WEB (`CalculPaie` = `PayrollCalculationService`, parité exécutée) ;
  /// un bulletin reçu l'emporte. « Valider le règlement » = une DEMANDE réglée par le serveur (bulletin, trésorerie,
  /// écriture, audit) : le poste n'envoie aucun montant.
  Widget _ongletPaie(DonneesPersonnel d, bool large) {
    final p = _paie;
    final moisLibelle = p == null ? '—' : _libelleMois(p.periode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _titre('Gestion de la Paie', large)),
            IconButton(key: const Key('paie-mois-precedent'), onPressed: () => _changerMois(-1), icon: const Icon(SymbolesAgri.chevron_left)),
            Text(moisLibelle, key: const Key('paie-periode'), style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras)),
            IconButton(key: const Key('paie-mois-suivant'), onPressed: () => _changerMois(1), icon: const Icon(SymbolesAgri.chevron_right)),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        // LES QUATRE CARTES DE `gestion-paie.html`, calculées comme `GestionPaie::getKpisProperty()`.
        _grilleKpis(large, [
          CarteKpi(
            key: const Key('kpi-paie-masse'),
            libelle: 'Masse Salariale',
            valeur: p == null ? '—' : _montant(p.masseSalariale),
            couleurLisere: AgriColors.brandEmerald,
            icone: SymbolesAgri.account_balance_wallet,
            couleurIcone: AgriColors.outline,
          ),
          CarteKpi(
            key: const Key('kpi-paie-bulletins'),
            libelle: 'Bulletins Émis',
            valeur: p == null ? '—' : '${p.bulletinsEmis}',
            couleurLisere: AgriColors.infoBlue,
            icone: SymbolesAgri.description,
            couleurIcone: AgriColors.outline,
          ),
          CarteKpi(
            key: const Key('kpi-paie-cnss'),
            libelle: 'Charges Sociales (CNSS)',
            valeur: p == null ? '—' : _montant(p.chargesCnss),
            couleurLisere: AgriColors.accentYellow,
            icone: SymbolesAgri.shield,
            couleurIcone: AgriColors.outline,
          ),
          CarteKpi(
            key: const Key('kpi-paie-attente'),
            libelle: 'En Attente de Paiement',
            valeur: p == null ? '—' : '${p.enAttente}',
            couleurLisere: AgriColors.errorRed,
            icone: SymbolesAgri.pending,
            couleurIcone: AgriColors.outline,
          ),
        ]),
        if (_message != null && _onglet == 'Gestion de la Paie') ...[
          const SizedBox(height: AgriSpacing.md),
          _bandeau(_message!, cle: const Key('bandeau-paie')),
        ],
        if (p != null && !p.baremeItsRenseigne && p.lignes.isNotEmpty) ...[
          const SizedBox(height: AgriSpacing.md),
          _mentionPoste(
            key: const Key('mention-bareme-its'),
            "Barème ITS non renseigné : l'ITS vaut 0 faute de barème, pas parce que le salaire est sous le seuil "
            "d'imposition. Le barème est servi par le serveur à la synchronisation.",
          ),
        ],
        const SizedBox(height: AgriSpacing.md),
        _tableau(
          largeur: 1300,
          // ⚠️ LES NEUF COLONNES DE `gestion-paie.html` (la maquette). Le web en a onze (Ret. ITS, Charges patronales) :
          // l'ITS est déduit dans « Net à Payer » et les deux montants se lisent dans l'info-bulle de la ligne.
          colonnes: const [
            ('Employé', 4),
            ('Poste', 3),
            ('Salaire Brut', 3),
            ('Absences', 2),
            ('Ret. Absences', 3),
            ('Ret. CNSS', 3),
            ('Net à Payer', 3),
            ('Statut', 3),
            ('Actions', 3),
          ],
          vide: '— Aucun employé —',
          lignes: [
            if (p != null)
              for (var i = 0; i < p.lignes.length; i++)
                _ligne(i, [
                  (
                    Text(
                      '${p.lignes[i].employe.firstName} ${p.lignes[i].employe.lastName}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
                    ),
                    4,
                  ),
                  (Text(p.lignes[i].employe.position ?? '—', overflow: TextOverflow.ellipsis, style: _cellule), 3),
                  (Text(_montant(p.lignes[i].brut), key: Key('paie-brut-$i'), style: _cellule), 3),
                  (Text(p.lignes[i].joursAbsence == null ? '—' : '${p.lignes[i].joursAbsence}', key: Key('paie-absences-$i'), style: _cellule), 2),
                  (Text(_montant(p.lignes[i].retenueAbsence), key: Key('paie-ret-absence-$i'), style: _cellule), 3),
                  (Text(_montant(p.lignes[i].retenueCnss), key: Key('paie-ret-cnss-$i'), style: _cellule), 3),
                  (
                    Tooltip(
                      message: 'Ret. ITS : ${_montant(p.lignes[i].retenueIts)} · Charges patronales : ${_montant(p.lignes[i].chargesPatronales)}',
                      child: Text(
                        _montant(p.lignes[i].net),
                        key: Key('paie-net-$i'),
                        style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
                      ),
                    ),
                    3,
                  ),
                  (_statutPaie(p.lignes[i]), 3),
                  (
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: Key('paie-valider-$i'),
                        onPressed: p.lignes[i].reglee || p.lignes[i].demandeEnCours
                            ? null
                            : () => _validerReglement(p.lignes[i]),
                        icon: const Icon(SymbolesAgri.check_circle, size: 16),
                        label: const Text('Valider le règlement', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
                      ),
                    ),
                    3,
                  ),
                ]),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _mentionPoste(
          'Le règlement validé ici est une demande : le serveur passe le bulletin, le mouvement de trésorerie et '
          "l'écriture à la prochaine synchronisation ; le bulletin redescend ensuite. Les montants affichés sont ceux "
          'du calcul du web (barème ITS et taux de paie reçus du serveur).',
        ),
      ],
    );
  }

  Widget _statutPaie(LignePaie l) {
    if (l.reglee) return _pastille('Réglé', couleur: AgriColors.brandEmerald);
    if (l.demandeRefusee) return _pastille('Demande refusée', couleur: AgriColors.errorRed);
    if (l.demandeEnCours) return _pastille('Demande envoyée', couleur: AgriColors.infoBlue);
    return _pastille('En attente', couleur: AgriColors.accentYellow);
  }

  static const _moisLongs = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

  static String _libelleMois(String periode) {
    final annee = periode.substring(0, 4);
    final mois = int.tryParse(periode.substring(5, 7)) ?? 1;
    final nom = _moisLongs[(mois - 1).clamp(0, 11)];
    return '${nom[0].toUpperCase()}${nom.substring(1)} $annee';
  }

  Future<void> _changerMois(int delta) async {
    final annee = int.parse(_periodePaie.substring(0, 4));
    final mois = int.parse(_periodePaie.substring(5, 7));
    final d = DateTime(annee, mois + delta, 1);
    setState(() {
      _periodePaie = PersonnelRepository.periodeDe(d);
      _message = null;
    });
    await _charger();
  }

  Future<void> _validerReglement(LignePaie l) async {
    await afficherModale<void>(
      context: context,
      constructeur: (context) => ModaleConfirmation(
        icone: SymbolesAgri.payments,
        titre: 'Valider le règlement',
        message: 'Régler la paie de ${l.employe.lastName} ${l.employe.firstName} pour ${_libelleMois(_periodePaie)} '
            '(net à payer : ${_montant(l.net)} FCFA) ? Le serveur passera le bulletin, la trésorerie et l\'écriture.',
        actions: [
          BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
          BoutonModalePrimaire(
            libelle: 'Valider',
            onPressed: () async {
              await widget.depot.demanderReglement(employeId: l.employe.id, periode: _periodePaie);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              setState(() => _message = 'Demande de règlement enregistrée — elle partira à la prochaine synchronisation.');
              await _charger();
            },
          ),
        ],
      ),
    );
  }

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

  Widget _mentionPoste(String texte, {Key key = const Key('mention-poste')}) => Container(
    key: key,
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
