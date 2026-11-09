import 'package:flutter/material.dart';

import '../../core/comptabilite/exercice_choisi.dart' show EtatExercice;
import '../../core/database/app_database.dart' show FiscalYear, PeriodicClosure;
import '../rapports/rapports_exports_screen.dart' show Editeur;
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'cloture_exercice_repository.dart';
import 'documents_comptabilite.dart';

/// Ticket CP-4 — `Livewire\Comptabilite\ClotureExercice` (route `/cloture-exercice`, carte « Clôture Périodique & Annuelle »).
///
/// Même structure que le Blade : en-tête « Bascule & Clôture d'Exercice Comptable » + « Exporter PDF », deux onglets (Clôture
/// Périodique / Clôture Annuelle), sélecteur de mois, bandeau de balance, bouton « Clôturer le Mois Sélectionné », historique
/// des clôtures de mois ; sélecteur d'exercice, trois cartes (Résultat Provisoire, Comptes de Gestion à Solder, Lettrage
/// Bancaire), assistant en trois étapes, et les quatre modales de confirmation.
///
/// ⚠️ Chaque geste écrit une DEMANDE que le serveur rejoue (`ClotureExerciceService`) : l'exercice clos, le report à nouveau et le
/// verrou des mois redescendent au tirage de confirmation. Les motifs de refus sont ceux du web, dits avant d'écrire.
class ClotureExercicePage extends StatefulWidget {
  const ClotureExercicePage({
    super.key,
    required this.depot,
    this.imprimer,
    this.maintenant,
    this.peutCloturer = true,
    this.peutAdministrer = true,
  });

  final ClotureExerciceRepository depot;
  final Editeur? imprimer;
  final DateTime Function()? maintenant;

  /// `close-fiscal-year` : sans lui, ni « Clôturer le Mois », ni les gestes de l'assistant (le Blade masque le premier, le
  /// serveur refuse les autres).
  final bool peutCloturer;

  /// `manage-modules` (administrateur) : déclôture d'un mois et réouverture d'un exercice.
  final bool peutAdministrer;

  @override
  State<ClotureExercicePage> createState() => _ClotureExercicePageState();
}

class _ClotureExercicePageState extends State<ClotureExercicePage> {
  DonneesCloture? _donnees;
  LettrageExercice? _lettrage;
  String _onglet = 'periodique';
  int? _annee;
  String? _periode;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final d = await widget.depot.charger();
    _annee ??= d.anneeInitiale;
    _periode ??= d.periodesCloturables.first.$1;
    final exercice = d.exercice(_annee!);
    final lettrage = exercice == null ? null : await widget.depot.lettrage(exercice);
    if (mounted) {
      setState(() {
        _donnees = d;
        _lettrage = lettrage;
      });
    }
  }

  static String _m(double v) => DocumentsComptabilite.montant(v);

  static String _deux(int n) => n.toString().padLeft(2, '0');

  static String _jour(DateTime d) => '${_deux(d.day)}/${_deux(d.month)}/${d.year}';

  static String _heure(DateTime d) => '${_deux(d.hour)}:${_deux(d.minute)}';

  void _toast(String message, TypeToast type) {
    if (mounted) ToastAgri.afficher(context, message, type: type, duree: type == TypeToast.erreur ? const Duration(seconds: 7) : null);
  }

  /// Joue un geste du dépôt : succès → toast + rechargement ; refus → toast d'erreur avec le motif du web.
  Future<void> _jouer(Future<void> Function() geste, String succes) async {
    try {
      await geste();
      _toast(succes, TypeToast.succes);
    } on RefusCloture catch (e) {
      _toast(e.motif, TypeToast.erreur);
    }
    await _charger();
  }

  Future<bool> _confirmer({
    required IconData icone,
    required String titre,
    required String message,
    required String libelle,
    required Key cle,
    Color couleurIcone = AgriColors.brandEmerald,
    Color couleurBouton = AgriColors.brandEmerald,
  }) async {
    final ok = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (c) => ModaleConfirmation(
        icone: icone,
        titre: titre,
        message: message,
        couleurIcone: couleurIcone,
        actions: [
          BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(c).pop(false)),
          BoutonModalePrimaire(key: cle, libelle: libelle, couleur: couleurBouton, onPressed: () => Navigator.of(c).pop(true)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _exporter(DonneesCloture d) async {
    final editeur = widget.imprimer;
    final exercice = d.exercice(_annee!);
    if (editeur == null) return;
    final soldes = d.soldesDeGestion(exercice);
    final plan = {for (final c in d.comptes) c.id: c};
    final document = DocumentsComptabilite.cloture(
      exercice: exercice?.year,
      resultat: d.indicateurs(exercice).resultat,
      comptes: [
        for (final s in soldes)
          (code: plan[s.compteId]?.code ?? '—', libelle: plan[s.compteId]?.label ?? '—', classe: s.classe, solde: s.solde),
      ],
    );
    try {
      final message = await editeur(document, widget.maintenant?.call() ?? d.maintenant) ?? 'Document envoyé à l’impression.';
      _toast(message, TypeToast.succes);
    } catch (_) {
      _toast('L’édition du document a échoué. Réessayez ou vérifiez l’imprimante.', TypeToast.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;
    if (d == null) return const Padding(padding: EdgeInsets.all(AgriSpacing.lg), child: Center(child: CircularProgressIndicator()));
    final large = AgriBreakpoints.large(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _enTete(d, large),
        const SizedBox(height: AgriSpacing.md),
        _onglets(),
        const SizedBox(height: AgriSpacing.md),
        if (d.demandes.isNotEmpty) ...[_demandes(d), const SizedBox(height: AgriSpacing.md)],
        if (_onglet == 'periodique') _periodique(d) else _annuelle(d, large),
      ],
    );
  }

  Widget _enTete(DonneesCloture d, bool large) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(SymbolesAgri.event_repeat, size: 26, color: AgriColors.brandEmerald),
                const SizedBox(width: AgriSpacing.xs),
                Flexible(
                  child: Text(
                    "Bascule & Clôture d'Exercice Comptable",
                    style: TextStyle(fontSize: large ? AgriTypography.xxl : AgriTypography.xl, fontWeight: AgriTypography.gras, color: AgriColors.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.xs),
            const Text(
              "Sélection de l'exercice fiscal actif et assistant de clôture annuelle (N vers N+1).",
              style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
          ],
        ),
      ),
      if (widget.imprimer != null) ...[
        const SizedBox(width: AgriSpacing.sm),
        OutlinedButton.icon(
          key: const Key('cloture-exporter'),
          onPressed: () => _exporter(d),
          icon: const Icon(SymbolesAgri.picture_as_pdf, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: AgriColors.brandForest,
            side: const BorderSide(color: AgriColors.outlineVariant),
            shape: const StadiumBorder(),
          ),
          label: const Text('Exporter PDF', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
        ),
      ],
    ],
  );

  Widget _onglets() => Container(
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AgriColors.outlineVariant))),
    child: Row(
      children: [
        _onglet1('periodique', 'Clôture Périodique', const Key('cloture-tab-periodique')),
        _onglet1('annuelle', 'Clôture Annuelle', const Key('cloture-tab-annuelle')),
      ],
    ),
  );

  Widget _onglet1(String id, String libelle, Key cle) {
    final actif = _onglet == id;
    return InkWell(
      key: cle,
      onTap: () => setState(() => _onglet = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 2, color: actif ? AgriColors.brandEmerald : Colors.transparent))),
        child: Text(
          libelle,
          style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: actif ? AgriColors.brandEmerald : AgriColors.outline),
        ),
      ),
    );
  }

  /// Demandes pas encore jouées par le serveur : en attente d'envoi ou refusées avec leur motif.
  Widget _demandes(DonneesCloture d) => Container(
    key: const Key('cloture-demandes'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.accentYellow.withValues(alpha: 0.10),
      border: Border.all(color: AgriColors.accentYellow.withValues(alpha: 0.40)),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Demandes de clôture', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
        const SizedBox(height: AgriSpacing.xs),
        for (final x in d.demandes)
          Padding(
            key: Key('cloture-demande-${x.demande.id}'),
            padding: const EdgeInsets.only(top: AgriSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(x.refusee ? SymbolesAgri.warning : SymbolesAgri.hourglass_empty, size: 16, color: x.refusee ? AgriColors.errorDeep : AgriColors.brandForest),
                const SizedBox(width: AgriSpacing.xs),
                Expanded(
                  child: Text(
                    x.refusee
                        ? '${x.libelle} — refusée par le serveur : ${x.motifRefus ?? 'motif non communiqué'}'
                        : "${x.libelle} — envoyée au serveur à la prochaine synchronisation.",
                    style: TextStyle(fontSize: 11, fontWeight: AgriTypography.gras, color: x.refusee ? AgriColors.errorDeep : AgriColors.brandForest),
                  ),
                ),
                if (x.refusee)
                  TextButton(
                    key: Key('cloture-abandonner-${x.demande.id}'),
                    onPressed: () async {
                      await widget.depot.abandonner(x.demande.id);
                      await _charger();
                    },
                    child: const Text('Abandonner', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  // ── Clôture périodique ─────────────────────────────────────────────────────────────────────────────────────────

  Widget _periodique(DonneesCloture d) {
    final periode = _periode!;
    final balance = d.periodeBalance(periode);
    final deja = d.periodeDejaCloturee(periode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Verrouillage mensuel léger — n'affecte pas le Report à Nouveau. Un déblocage exceptionnel reste possible pour le rôle Administrateur uniquement.",
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.md),
        Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(color: AgriColors.surfaceCard, border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(AgriRadius.lg)),
          child: Wrap(
            spacing: AgriSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('MOIS À CLÔTURER :', style: TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  key: const Key('cloture-mois'),
                  initialValue: periode,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                  style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.onSurface),
                  items: [for (final (v, l) in d.periodesCloturables) DropdownMenuItem(value: v, child: Text(l))],
                  onChanged: (v) => setState(() => _periode = v ?? periode),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        if (!balance.equilibree)
          _bandeau(
            const Key('cloture-balance-desequilibree'),
            AgriColors.errorRed,
            SymbolesAgri.warning,
            AgriColors.errorDeep,
            'Balance Déséquilibrée — Clôture Bloquée',
            "Corrigez l'écart de ${_m(balance.ecart)} FCFA sur Balance Générale avant de pouvoir clôturer ce mois.",
          )
        else if (deja)
          _bandeau(const Key('cloture-mois-deja'), AgriColors.outlineVariant, SymbolesAgri.lock, AgriColors.outline, 'Mois Déjà Clôturé', 'Les écritures de cette période sont verrouillées en lecture seule.')
        else
          _bandeau(
            const Key('cloture-balance-equilibree'),
            AgriColors.brandEmerald,
            SymbolesAgri.check_circle,
            AgriColors.brandEmerald,
            'Balance Équilibrée — Clôture Autorisée',
            'Aucune anomalie détectée pour ce mois. Vous pouvez procéder à la clôture périodique.',
          ),
        const SizedBox(height: AgriSpacing.md),
        if (widget.peutCloturer)
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              key: const Key('cloture-mois-bouton'),
              onPressed: (!balance.equilibree || deja) ? null : () => _cloturerMois(periode),
              icon: const Icon(SymbolesAgri.lock, size: 18),
              style: ElevatedButton.styleFrom(backgroundColor: AgriColors.brandEmerald, foregroundColor: Colors.white, shape: const StadiumBorder()),
              label: const Text('Clôturer le Mois Sélectionné', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
            ),
          ),
        const SizedBox(height: AgriSpacing.md),
        _historique(d),
      ],
    );
  }

  Widget _bandeau(Key cle, Color bordure, IconData icone, Color couleurIcone, String titre, String texte) => Container(
    key: cle,
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: bordure.withValues(alpha: 0.10),
      border: Border.all(color: bordure.withValues(alpha: 0.30)),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 20, color: couleurIcone),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titre, style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: couleurIcone)),
              const SizedBox(height: AgriSpacing.xs),
              Text(texte, style: const TextStyle(fontSize: 11, color: AgriColors.outline)),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _cloturerMois(String periode) async {
    final ok = await _confirmer(
      icone: SymbolesAgri.lock,
      titre: 'Clôturer ce Mois ?',
      message:
          'Les écritures de ce mois seront verrouillées en lecture seule. Contrairement à la clôture annuelle, un déblocage exceptionnel reste possible par un Administrateur.',
      libelle: 'Confirmer la Clôture du Mois',
      cle: const Key('cloture-mois-confirmer'),
    );
    if (!ok) return;
    await _jouer(
      () => widget.depot.cloturerPeriode(periode),
      'Demande de clôture du mois envoyée au serveur — les écritures de cette période seront verrouillées à la prochaine synchronisation.',
    );
  }

  Future<void> _decloturer(PeriodicClosure c) async {
    final ok = await _confirmer(
      icone: SymbolesAgri.lock_open,
      titre: 'Déclôturer ce Mois ?',
      message:
          'Action exceptionnelle réservée aux Administrateurs — sera journalisée dans les Logs d’Audit avec votre identité et un horodatage. Les écritures redeviendront modifiables.',
      libelle: 'Confirmer la Déclôture',
      cle: const Key('cloture-decloture-confirmer'),
      couleurIcone: AgriColors.accentYellow,
      couleurBouton: AgriColors.accentYellow,
    );
    if (!ok) return;
    await _jouer(
      () => widget.depot.decloturerPeriode(c.id),
      "Demande de déclôture envoyée au serveur — action exceptionnelle journalisée dans les Logs d'Audit à la prochaine synchronisation.",
    );
  }

  Widget _historique(DonneesCloture d) => Container(
    decoration: BoxDecoration(color: AgriColors.surfaceCard, border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(AgriRadius.lg)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
          child: Text('Historique des Clôtures Périodiques', style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
        ),
        const Divider(height: 1, color: AgriColors.outlineVariant),
        Container(
          color: AgriColors.surfaceZebra,
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
          child: const Row(
            children: [
              Expanded(child: _Entete('Mois')),
              Expanded(child: _Entete('Date de Clôture')),
              Expanded(child: _Entete('Statut')),
              Expanded(child: _Entete('Action (Admin)', droite: true)),
            ],
          ),
        ),
        if (d.clotures.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AgriSpacing.lg),
            child: Center(child: Text('Aucun mois clôturé à ce jour.', style: TextStyle(color: AgriColors.outline))),
          )
        else
          for (final c in d.clotures) _ligneCloture(c, d),
        const Padding(
          padding: EdgeInsets.all(AgriSpacing.sm),
          child: Text(
            'Le bouton "Déclôturer" n\'est visible et actif que pour le rôle Administrateur — action journalisée dans les Logs d\'Audit.',
            style: TextStyle(fontSize: 11, color: AgriColors.outline),
          ),
        ),
      ],
    ),
  );

  Widget _ligneCloture(PeriodicClosure c, DonneesCloture d) {
    final verrouillee = c.reopenedAt == null;
    final mois = DateTime(int.parse(c.period.substring(0, 4)), int.parse(c.period.substring(5, 7)));
    final enAttente = d.demandeEnAttente('decloturer_periode', clotureId: c.id) != null;

    return Container(
      key: Key('cloture-ligne-${c.period}'),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AgriColors.outlineVariant))),
      child: Row(
        children: [
          Expanded(child: Text(EtatExercice.libelleMois(mois), style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.w600))),
          Expanded(child: Text(c.closedAt == null ? '—' : _jour(c.closedAt!), style: const TextStyle(fontSize: AgriTypography.xs))),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: verrouillee ? '' : 'Déclôturé le ${_jour(c.reopenedAt!)} ${_heure(c.reopenedAt!)}',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: (verrouillee ? AgriColors.errorRed : AgriColors.accentYellow).withValues(alpha: verrouillee ? 0.10 : 0.20),
                    borderRadius: BorderRadius.circular(AgriRadius.full),
                  ),
                  child: Text(
                    verrouillee ? 'Clôturé' : 'Déclôturé',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: verrouillee ? AgriColors.errorDeep : AgriColors.brandForest),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: !widget.peutAdministrer
                  ? const Text('Réservé à l\'Administrateur', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: AgriColors.outline))
                  : verrouillee
                  ? TextButton(
                      key: Key('cloture-decloturer-${c.period}'),
                      onPressed: enAttente ? null : () => _decloturer(c),
                      child: const Text('Déclôturer (exceptionnel)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgriColors.infoBlue)),
                    )
                  : const Text('Déjà déclôturé', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: AgriColors.outline)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Clôture annuelle ───────────────────────────────────────────────────────────────────────────────────────────

  Widget _annuelle(DonneesCloture d, bool large) {
    final annee = _annee!;
    final exercice = d.exercice(annee);
    final ind = d.indicateurs(exercice);
    final lettrage = _lettrage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _selecteur(d, exercice, annee),
        const SizedBox(height: AgriSpacing.md),
        GrilleKpi(
          colonnes: large ? 3 : 1,
          children: [
            CarteKpi(key: const Key('kpi-cloture-resultat'), libelle: 'Résultat Provisoire', valeur: '${_m(ind.resultat)} F', couleurLisere: AgriColors.brandEmerald),
            CarteKpi(key: const Key('kpi-cloture-a-solder'), libelle: 'Comptes de Gestion à Solder', valeur: '${ind.comptesASolder}', couleurLisere: AgriColors.infoBlue),
            if (lettrage == null || lettrage.taux == null)
              const CarteKpi(
                key: Key('kpi-cloture-lettrage'),
                libelle: 'Lettrage Bancaire',
                valeur: '—',
                legende: "Disponible après l'import d'un relevé bancaire (Comptabilité > Rapprochement Bancaire)",
                iconeLegende: SymbolesAgri.hourglass_empty,
                couleurLisere: AgriColors.accentYellow,
              )
            else
              CarteKpi(
                key: const Key('kpi-cloture-lettrage'),
                libelle: 'Lettrage Bancaire',
                valeur: '${lettrage.taux}%',
                legende:
                    '${lettrage.lettrees} / ${lettrage.lignes} lignes lettrées'
                    '${lettrage.comptesSansReleve > 0 ? ' — ${lettrage.comptesSansReleve} compte(s) sans relevé importé' : ''}',
                couleurLisere: AgriColors.accentYellow,
              ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        if (exercice != null && exercice.status == 'ouvert')
          _assistant(d, exercice)
        else if (exercice != null)
          _carteMessage(
            const Key('cloture-exercice-clos'),
            SymbolesAgri.lock,
            'Cet exercice est clôturé.',
            'Consultable en lecture seule — clôturé le ${exercice.closedAt == null ? '—' : '${_jour(exercice.closedAt!)} à ${_heure(exercice.closedAt!)}'}.',
          )
        else
          _carteMessage(const Key('cloture-exercice-absent'), SymbolesAgri.event_busy, "Aucun exercice $annee n'existe.", null),
      ],
    );
  }

  Widget _carteMessage(Key cle, IconData icone, String titre, String? detail) => Container(
    key: cle,
    padding: const EdgeInsets.all(AgriSpacing.lg),
    decoration: BoxDecoration(color: AgriColors.surfaceCard, border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(AgriRadius.lg)),
    child: Column(
      children: [
        Icon(icone, size: 48, color: AgriColors.outlineVariant),
        const SizedBox(height: AgriSpacing.sm),
        Text(titre, style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.w600, color: AgriColors.onSurface)),
        if (detail != null) ...[const SizedBox(height: AgriSpacing.xs), Text(detail, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline))],
      ],
    ),
  );

  Widget _selecteur(DonneesCloture d, FiscalYear? exercice, int annee) {
    Widget fleche(Key cle, IconData icone, int delta) => InkWell(
      key: cle,
      customBorder: const CircleBorder(),
      onTap: () async {
        setState(() => _annee = annee + delta);
        await _charger();
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AgriColors.outlineVariant)),
        child: Icon(icone, size: 18),
      ),
    );

    final ouvert = exercice?.status == 'ouvert';
    final puces = <Widget>[
      if (exercice == null)
        _puce('EXERCICE $annee — INEXISTANT', SymbolesAgri.help, AgriColors.surfaceZebra, AgriColors.outline, AgriColors.outlineVariant, const Key('cloture-statut'))
      else if (ouvert)
        _puce('EXERCICE $annee — OUVERT (Lecture / Écriture)', SymbolesAgri.lock_open, AgriColors.brandEmerald.withValues(alpha: 0.10), AgriColors.brandEmerald, AgriColors.brandEmerald.withValues(alpha: 0.30), const Key('cloture-statut'))
      else
        _puce('EXERCICE $annee — CLOS (Lecture Seule)', SymbolesAgri.lock, AgriColors.errorBg, AgriColors.errorDeep, AgriColors.errorDeep.withValues(alpha: 0.30), const Key('cloture-statut')),
      if (ouvert && widget.peutCloturer && d.peutOuvrirSuivant(exercice))
        ElevatedButton.icon(
          key: const Key('cloture-ouvrir-suivant'),
          onPressed: d.demandeEnAttente('ouvrir_exercice_suivant', annee: annee + 1) != null ? null : () => _ouvrirSuivant(annee + 1),
          icon: const Icon(SymbolesAgri.calendar_month, size: 16),
          style: ElevatedButton.styleFrom(backgroundColor: AgriColors.brandEmerald, foregroundColor: Colors.white, shape: const StadiumBorder()),
          label: Text("Ouvrir l'exercice ${annee + 1}", style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
        ),
      if (exercice != null && !ouvert && widget.peutAdministrer)
        ElevatedButton.icon(
          key: const Key('cloture-rouvrir'),
          onPressed: d.demandeEnAttente('rouvrir_exercice', annee: annee) != null ? null : () => _rouvrir(annee),
          icon: const Icon(SymbolesAgri.lock_open, size: 16),
          style: ElevatedButton.styleFrom(backgroundColor: AgriColors.accentYellow, foregroundColor: AgriColors.brandForest, shape: const StadiumBorder()),
          label: Text("Rouvrir l'Exercice $annee", style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(color: AgriColors.surfaceCard, border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(AgriRadius.lg)),
      child: Wrap(
        spacing: AgriSpacing.md,
        runSpacing: AgriSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          fleche(const Key('cloture-annee-precedente'), SymbolesAgri.chevron_left, -1),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('EXERCICE SÉLECTIONNÉ', style: TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.outline)),
              Text('$annee', key: const Key('cloture-annee'), style: const TextStyle(fontSize: AgriTypography.lg, fontWeight: FontWeight.w800, color: AgriColors.brandForest)),
            ],
          ),
          fleche(const Key('cloture-annee-suivante'), SymbolesAgri.chevron_right, 1),
          ...puces,
        ],
      ),
    );
  }

  Widget _puce(String texte, IconData icone, Color fond, Color couleur, Color bordure, Key cle) => Container(
    key: cle,
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: 8),
    decoration: BoxDecoration(color: fond, border: Border.all(color: bordure), borderRadius: BorderRadius.circular(AgriRadius.full)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 16, color: couleur),
        const SizedBox(width: AgriSpacing.xs),
        Text(texte, style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: couleur)),
      ],
    ),
  );

  Future<void> _ouvrirSuivant(int annee) => _jouer(
    () => widget.depot.ouvrirExerciceSuivant(annee),
    "Demande d'ouverture de l'exercice $annee envoyée au serveur (du 01/01/$annee au 31/12/$annee) — elle sera jouée à la prochaine synchronisation.",
  );

  Future<void> _rouvrir(int annee) async {
    final ok = await _confirmer(
      icone: SymbolesAgri.lock_open,
      titre: "Rouvrir l'Exercice $annee ?",
      message:
          'Action exceptionnelle réservée aux Administrateurs — journalisée dans les Logs d’Audit. Le report à nouveau de ${annee + 1} est contre-passé (il reste lisible au journal) et les écritures de $annee redeviennent modifiables. Une nouvelle clôture repassera le report sur les soldes corrigés.',
      libelle: 'Confirmer la Réouverture',
      cle: const Key('cloture-reouverture-confirmer'),
      couleurIcone: AgriColors.accentYellow,
      couleurBouton: AgriColors.accentYellow,
    );
    if (!ok) return;
    await _jouer(
      () => widget.depot.rouvrirExercice(annee),
      "Demande de réouverture de l'exercice $annee envoyée au serveur — report à nouveau contre-passé et action journalisée à la prochaine synchronisation.",
    );
  }

  Future<void> _cloturerExercice(int annee) async {
    final ok = await _confirmer(
      icone: SymbolesAgri.warning,
      titre: "Clôturer l'Exercice $annee ?",
      message:
          "Cette action verrouille toutes les écritures de $annee (lecture seule) et ouvre l'exercice ${annee + 1} avec les écritures de report à nouveau. Seul un administrateur pourra la défaire, par une réouverture exceptionnelle journalisée.",
      libelle: 'Confirmer la Clôture',
      cle: const Key('cloture-confirmer'),
      couleurIcone: AgriColors.errorDeep,
      couleurBouton: AgriColors.errorRed,
    );
    if (!ok) return;
    await _jouer(
      () => widget.depot.cloturerExercice(annee),
      "Demande de clôture de l'exercice $annee envoyée au serveur — l'exercice ${annee + 1} sera ouvert à la prochaine synchronisation.",
    );
  }

  Widget _assistant(DonneesCloture d, FiscalYear exercice) {
    final annee = exercice.year;
    final etape1Demandee = d.demandeEnAttente('confirmer_etape1', annee: annee) != null;
    final etape2Demandee = d.demandeEnAttente('solder_comptes_gestion', annee: annee) != null;
    final motif = d.motifRefusCloture(exercice);

    Widget etape(int n, String titre, String texte, List<Widget> suite) => Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      margin: const EdgeInsets.only(bottom: AgriSpacing.sm),
      decoration: BoxDecoration(border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(AgriRadius.lg)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AgriColors.brandEmerald, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
                const SizedBox(height: AgriSpacing.xs),
                Text(texte, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
                ...suite,
              ],
            ),
          ),
        ],
      ),
    );

    const demandee = TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest);

    return Container(
      decoration: BoxDecoration(color: AgriColors.surfaceCard, border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(AgriRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
            child: Text("Assistant de Clôture d'Exercice ($annee → ${annee + 1})", style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
          ),
          const Divider(height: 1, color: AgriColors.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(AgriSpacing.md),
            child: Column(
              children: [
                etape(1, "Travaux d'Inventaire & Régularisation",
                    "Rapprochements bancaires (caisse/banque), amortissements, provisions, inventaire physique des stocks, charges/produits constatés d'avance (FNP/FAE) — à passer par le Journal Comptable avant de confirmer.", [
                  if (exercice.step1ConfirmedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AgriSpacing.sm),
                      child: Text('Confirmé le ${_jour(exercice.step1ConfirmedAt!)} à ${_heure(exercice.step1ConfirmedAt!)}', key: const Key('cloture-step1-confirme'), style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandEmerald)),
                    )
                  else if (etape1Demandee)
                    const Padding(padding: EdgeInsets.only(top: AgriSpacing.sm), child: Text("Demande envoyée au serveur : confirmée à la prochaine synchronisation.", key: Key('cloture-step1-demandee'), style: demandee))
                  else if (widget.peutCloturer)
                    TextButton(
                      key: const Key('cloture-step1'),
                      onPressed: () => _jouer(() => widget.depot.confirmerEtape1(annee), "Demande de confirmation de l'étape 1 envoyée au serveur — rapprochements et régularisations confirmés à la prochaine synchronisation."),
                      child: const Text('Marquer comme terminé', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: AgriColors.brandEmerald)),
                    ),
                ]),
                etape(2, 'Solde des Comptes de Gestion (Classes 6 & 7)',
                    'Calcul du résultat net (Produits − Charges) et écriture de solde vers le compte 131 (Bénéfice) ou 139 (Perte).', [
                  if (etape2Demandee)
                    const Padding(padding: EdgeInsets.only(top: AgriSpacing.sm), child: Text("Demande envoyée au serveur : comptes soldés à la prochaine synchronisation.", key: Key('cloture-step2-demandee'), style: demandee))
                  else if (widget.peutCloturer)
                    TextButton(
                      key: const Key('cloture-step2'),
                      onPressed: () => _jouer(() => widget.depot.solderComptesGestion(annee), 'Demande de solde des comptes de charges et produits envoyée au serveur — résultat net calculé à la prochaine synchronisation.'),
                      child: const Text('Calculer et Solder', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: AgriColors.brandEmerald)),
                    ),
                ]),
                etape(3, "Génération des Écritures d'À-Nouveaux (RAN)",
                    "Création de l'exercice ${annee + 1} et report des soldes de bilan (Classes 1 à 5) au 1er janvier ${annee + 1}. Verrouillage définitif de l'exercice $annee.", [
                  if (widget.peutCloturer)
                    Padding(
                      padding: const EdgeInsets.only(top: AgriSpacing.sm),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Tooltip(
                          message: motif ?? '',
                          child: ElevatedButton(
                            key: const Key('cloture-step3'),
                            onPressed: motif != null ? null : () => _cloturerExercice(annee),
                            style: ElevatedButton.styleFrom(backgroundColor: AgriColors.errorRed, foregroundColor: Colors.white, shape: const StadiumBorder()),
                            child: Text("Clôturer l'Exercice $annee", style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ),
                  if (motif != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AgriSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(SymbolesAgri.info, size: 16, color: AgriColors.errorDeep),
                          const SizedBox(width: AgriSpacing.xs),
                          Expanded(child: Text(motif, key: const Key('cloture-step3-motif'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep))),
                        ],
                      ),
                    ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Entete extends StatelessWidget {
  const _Entete(this.texte, {this.droite = false});

  final String texte;
  final bool droite;

  @override
  Widget build(BuildContext context) => Text(
    texte.toUpperCase(),
    textAlign: droite ? TextAlign.right : TextAlign.left,
    style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.outline),
  );
}
