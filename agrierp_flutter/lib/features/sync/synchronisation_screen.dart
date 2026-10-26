import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/erreurs/message_erreur.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/synchronisation_automatique.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/toast_agri.dart';
import '../comptabilite/soldes_exercice.dart';
import 'coherence_repository.dart';

/// Écran de synchronisation — ce qui attend, ce qui est parti, ce qui a été
/// refusé.
///
/// ⚠️ **CET ÉCRAN N'EST PAS DANS LA MAQUETTE, ET C'EST ASSUMÉ.** Le prototype
/// est une surface WEB : il n'a ni file d'attente locale ni notion de poste
/// hors ligne, donc rien à montrer ici. Le CDC, lui, prévoit explicitement les
/// tables `sync_queue` et `sync_conflicts` (§309) : l'écran leur donne enfin
/// une surface. C'est un AJOUT au-delà du prototype, pas une conversion.
///
/// ⚠️ **POURQUOI IL EST NÉCESSAIRE.** Avant lui, un refus du serveur n'existait
/// que dans un bandeau de huit secondes. Le caissier qui s'absentait ne le
/// voyait jamais ; l'enregistrement restait sur le poste, et personne ne
/// pouvait dire pourquoi. Un travail invisible est un travail perdu.
class SynchronisationScreen extends StatefulWidget {
  const SynchronisationScreen({
    super.key,
    required this.database,
    required this.engine,
    this.coherence,
  });

  final AppDatabase database;
  final SyncEngine engine;

  /// Ticket S-T6 — contrôle de cohérence ; `null` : celui du moteur ([SyncEngine.coherenceDuServeur]).
  final ControleCoherenceRepository? coherence;

  @override
  State<SynchronisationScreen> createState() => _SynchronisationScreenState();
}

class _SynchronisationScreenState extends State<SynchronisationScreen> {
  int _enAttente = 0;
  List<SyncConflict> _conflits = const [];
  SyncStateData? _etat;
  bool _enCours = false;

  late final ControleCoherenceRepository _depotCoherence =
      widget.coherence ??
      ControleCoherenceRepository(
        database: widget.database,
        serveur: widget.engine.coherenceDuServeur,
      );
  ResultatCoherence? _coherence;
  bool _verification = false;

  /// Tables dont les jours conformes sont dépliés.
  final Set<String> _deplies = {};

  @override
  void initState() {
    super.initState();
    _rafraichir();
  }

  Future<void> _rafraichir() async {
    final attente = await widget.database.pendingCount();
    final conflits = await widget.engine.conflits();
    final etat = await widget.database.etatDeSynchronisation();

    if (mounted) {
      setState(() {
        _enAttente = attente;
        _conflits = conflits;
        _etat = etat;
      });
    }
  }

  Future<void> _synchroniser() async {
    if (_enCours) return;
    setState(() => _enCours = true);

    try {
      final r = await widget.engine.synchroniser();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: r.horsLigne
              ? AgriColors.brandForest
              : (r.rejete > 0 ? AgriColors.errorDeep : AgriColors.brandEmerald),
          content: Text(
            r.horsLigne
                ? 'Hors ligne — rien n\'a été envoyé.'
                : '${r.tire} référence(s) reçue(s), ${r.accepte} envoyée(s), '
                      '${r.rejete} refusée(s).',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AgriColors.errorDeep,
            // Ticket U5 : jamais l'exception brute (anglaise) à l'écran.
            content: Text('Synchronisation impossible — ${messageErreur(e)}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
      await _rafraichir();
    }
  }

  Future<void> _relancer(SyncConflict conflit) async {
    await widget.engine.relancer(conflit);
    await _rafraichir();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AgriColors.brandForest,
          content: Text(
            'Remis en file. Si la cause n\'a pas été corrigée côté serveur, '
            'le refus se reproduira.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: RefreshIndicator(
        onRefresh: _rafraichir,
        child: ListView(
          padding: const EdgeInsets.all(AgriSpacing.lg),
          children: [
            const Text(
              'Synchronisation',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AgriColors.onSurface,
              ),
            ),
            const SizedBox(height: AgriSpacing.xs),
            const Text(
              'Ce poste travaille hors ligne : les saisies restent ici jusqu\'à '
              'leur envoi.',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
            const SizedBox(height: AgriSpacing.lg),
            _etatDuPoste(),
            const SizedBox(height: AgriSpacing.lg),
            _blocConflits(),
            const SizedBox(height: AgriSpacing.lg),
            _blocCoherence(),
          ],
        ),
      ),
    );
  }

  Widget _etatDuPoste() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'EN ATTENTE D\'ENVOI',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AgriColors.brandForest,
                        ),
                      ),
                      const SizedBox(height: AgriSpacing.xs),
                      Text(
                        '$_enAttente',
                        key: const Key('compteur-attente'),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          // ⚠️ Le compteur inclut les REFUSÉS : ils ne sont pas
                          // arrivés au serveur non plus. Afficher « 0 » alors
                          // que des ventes n'existent que sur ce poste ferait
                          // éteindre la machine en croyant le travail à l'abri.
                          color: _enAttente > 0
                              ? AgriColors.accentYellow
                              : AgriColors.brandEmerald,
                        ),
                      ),
                      Text(
                        _enAttente == 0
                            ? 'Tout est parti au serveur.'
                            : 'Ces saisies n\'existent que sur ce poste.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AgriColors.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    key: const Key('bouton-synchroniser'),
                    onPressed: _enCours ? null : _synchroniser,
                    icon: _enCours
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AgriColors.brandForest,
                            ),
                          )
                        : const Icon(SymbolesAgri.sync, size: 18),
                    label: const Text('Synchroniser'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AgriColors.accentYellow,
                      foregroundColor: AgriColors.brandForest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AgriRadius.lg),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: AgriSpacing.lg),
            _ligneEtat('Dernière réception', _etat?.lastPulledAt),
            const SizedBox(height: AgriSpacing.xs),
            _ligneEtat('Dernier envoi', _etat?.lastPushedAt),
          ],
        ),
      ),
    );
  }

  Widget _ligneEtat(String libelle, DateTime? quand) {
    return Row(
      children: [
        Expanded(
          child: Text(
            libelle,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
        ),
        Text(
          // ⚠️ « Jamais » plutôt qu'une date vide : un poste qui n'a jamais
          // synchronisé doit le dire, c'est l'information la plus utile.
          quand == null ? 'Jamais' : _horodatage(quand),
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _blocConflits() {
    if (_conflits.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AgriSpacing.md),
          child: Row(
            children: [
              Icon(
                SymbolesAgri.check_circle,
                color: AgriColors.brandEmerald,
                size: 20,
              ),
              SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: Text(
                  'Aucun refus du serveur.',
                  style: TextStyle(fontSize: AgriTypography.xs),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  SymbolesAgri.error_outline,
                  color: AgriColors.errorDeep,
                  size: 20,
                ),
                const SizedBox(width: AgriSpacing.sm),
                Text(
                  'REFUSÉS PAR LE SERVEUR (${_conflits.length})',
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.errorDeep,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.xs),
            const Text(
              'Ces saisies restent sur ce poste et ne sont plus renvoyées '
              'automatiquement : sans correction, le refus se reproduirait à '
              'chaque tentative.',
              style: TextStyle(fontSize: 11, color: AgriColors.outline),
            ),
            const Divider(),
            for (final c in _conflits) _ligneConflit(c),
          ],
        ),
      ),
    );
  }

  Widget _ligneConflit(SyncConflict conflit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AgriSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _libelleTable(conflit.sourceTable),
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                // Le motif du serveur, mot pour mot : le responsable doit
                // pouvoir le citer pour faire corriger la cause.
                Text(
                  conflit.reason,
                  key: Key('motif-${conflit.recordId}'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AgriColors.errorDeep,
                  ),
                ),
                Text(
                  '${_horodatage(conflit.detectedAt)} · ${conflit.recordId}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: AgriColors.outline,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: Key('relancer-${conflit.recordId}'),
            onPressed: () => _relancer(conflit),
            child: const Text(
              'Remettre en file',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ticket S-T6 : contrôle de cohérence ───────────────────────────────────────────────────────────────────

  /// « Vérifier la cohérence » : comptes du poste et du serveur, comparés. Hors ligne ou serveur injoignable :
  /// un avertissement (jamais une erreur rouge, c'est l'état normal de la ferme) ; refus du serveur : une erreur
  /// avec son message français.
  Future<void> _verifierCoherence() async {
    if (_verification) return;
    if (!await widget.engine.estEnLigne()) {
      if (mounted) {
        ToastAgri.afficher(
          context,
          'Hors ligne — le contrôle de cohérence demande le serveur.',
          type: TypeToast.avertissement,
        );
      }
      return;
    }

    setState(() => _verification = true);
    try {
      final resultat = await _depotCoherence.verifier();
      if (!mounted) return;
      setState(() => _coherence = resultat);
      final n = resultat.nombreEcarts;
      final a = resultat.nombreEcartsAnouveaux;
      ToastAgri.afficher(
        context,
        n == 0 && a == 0
            ? 'Contrôle de cohérence : aucun écart.'
            : 'Contrôle de cohérence : ${[
                if (n > 0) '$n jour(s) en écart',
                if (a > 0) "$a compte(s) dont l'ouverture ne reprend pas la clôture",
              ].join(' ; ')}.',
        type: n == 0 && a == 0 ? TypeToast.succes : TypeToast.avertissement,
      );
    } catch (e) {
      if (mounted) {
        final reseau = SynchronisationAutomatique.estEchecReseau(e);
        ToastAgri.afficher(
          context,
          reseau
              ? 'Serveur injoignable — contrôle impossible pour le moment.'
              : 'Contrôle de cohérence impossible — ${messageErreur(e)}',
          type: reseau ? TypeToast.avertissement : TypeToast.erreur,
        );
      }
    } finally {
      if (mounted) setState(() => _verification = false);
    }
  }

  Widget _blocCoherence() {
    final resultat = _coherence;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(SymbolesAgri.fact_check, color: AgriColors.brandForest, size: 20),
                const SizedBox(width: AgriSpacing.sm),
                const Expanded(
                  child: Text(
                    'Contrôle de cohérence',
                    style: TextStyle(
                      fontSize: AgriTypography.sm,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('bouton-verifier-coherence'),
                  onPressed: _verification ? null : _verifierCoherence,
                  icon: _verification
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(SymbolesAgri.sync, size: 16),
                  label: const Text(
                    'Vérifier la cohérence',
                    style: TextStyle(fontSize: AgriTypography.xs),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.xs),
            const Text(
              'Compare, table par table et jour par jour, le nombre de lignes et leur total sur ce poste '
              '(lignes déjà envoyées ou reçues) et sur le serveur, sur les '
              '${ControleCoherenceRepository.joursParDefaut} derniers jours.',
              style: TextStyle(fontSize: 11, color: AgriColors.outline),
            ),
            const Divider(),
            if (resultat == null)
              const Text(
                'Aucun contrôle effectué pendant cette session.',
                key: Key('coherence-aucun-controle'),
                style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
              )
            else ...[
              Text(
                resultat.nombreEcarts == 0
                    ? 'Depuis le ${_jourFr(ControleCoherenceRepository.cleJour(resultat.depuis))} : aucun écart.'
                    : 'Depuis le ${_jourFr(ControleCoherenceRepository.cleJour(resultat.depuis))} : '
                          '${resultat.nombreEcarts} jour(s) en écart.',
                key: const Key('coherence-synthese'),
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: resultat.nombreEcarts == 0
                      ? AgriColors.brandEmerald
                      : AgriColors.errorDeep,
                ),
              ),
              for (final t in resultat.tables) _tableCoherence(t),
              if (resultat.anouveauxServeur != null) _blocAnouveaux(resultat),
            ],
          ],
        ),
      ),
    );
  }

  /// Ticket EX1 — invariant « ouverture de N+1 = clôture de N » (classes 1 à 5), au serveur et au poste.
  Widget _blocAnouveaux(ResultatCoherence r) {
    final controles = <({String cote, ControleAnouveau c})>[
      for (final c in r.anouveauxServeur ?? const <ControleAnouveau>[]) (cote: 'Serveur', c: c),
      for (final c in r.anouveauxPoste ?? const <ControleAnouveau>[]) (cote: 'Poste', c: c),
    ];
    const style = TextStyle(fontSize: 11, color: AgriColors.onSurface);

    return Padding(
      key: const Key('coherence-anouveaux'),
      padding: const EdgeInsets.only(top: AgriSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Ouverture N+1 = clôture N (comptes des classes 1 à 5)',
                  style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                r.nombreEcartsAnouveaux == 0 ? 'Conforme' : '${r.nombreEcartsAnouveaux} écart(s)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: r.nombreEcartsAnouveaux == 0 ? AgriColors.brandEmerald : AgriColors.errorDeep,
                ),
              ),
            ],
          ),
          if (controles.isEmpty)
            const Text('Un seul exercice : rien à comparer.', style: TextStyle(fontSize: 11, color: AgriColors.outline)),
          for (final x in controles) ...[
            Text(
              '${x.cote} — exercice ${x.c.exercice} (ouverture) / ${x.c.precedent} '
              '(${x.c.statutPrecedent == 'cloture' ? 'clôturé' : 'ouvert — à-nouveaux provisoires'}) : '
              '${x.c.ecarts.isEmpty ? 'conforme' : '${x.c.ecarts.length} compte(s) en écart'}',
              style: style,
            ),
            for (final e in x.c.ecarts)
              Text(
                '   ${e.code} — ${e.libelle} : clôture ${_nombre(e.cloture)}, ouverture ${_nombre(e.ouverture)}',
                style: style.copyWith(color: AgriColors.errorDeep, fontWeight: FontWeight.bold),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tableCoherence(TableCoherence t) {
    final deplie = _deplies.contains(t.table);

    return Padding(
      key: Key('coherence-${t.table}'),
      padding: const EdgeInsets.only(top: AgriSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.libelle,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                t.ecarts.isEmpty ? 'Conforme' : '${t.ecarts.length} écart(s)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: t.ecarts.isEmpty ? AgriColors.brandEmerald : AgriColors.errorDeep,
                ),
              ),
            ],
          ),
          if (t.ecarts.isNotEmpty || deplie) _enteteCoherence(),
          for (final l in t.ecarts) _ligneCoherence(t.table, l),
          if (t.conformes.isNotEmpty)
            TextButton.icon(
              key: Key('coherence-deplier-${t.table}'),
              onPressed: () => setState(
                () => deplie ? _deplies.remove(t.table) : _deplies.add(t.table),
              ),
              icon: Icon(
                deplie ? SymbolesAgri.expand_less : SymbolesAgri.expand_more,
                size: 16,
              ),
              label: Text(
                '${t.conformes.length} jour(s) conforme(s)',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          if (deplie)
            for (final l in t.conformes) _ligneCoherence(t.table, l),
          if (t.ecarts.isEmpty && t.conformes.isEmpty)
            const Text(
              'Aucune ligne sur la période, ni au poste ni au serveur.',
              style: TextStyle(fontSize: 11, color: AgriColors.outline),
            ),
        ],
      ),
    );
  }

  Widget _enteteCoherence() {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: AgriColors.outline,
    );
    return const Padding(
      padding: EdgeInsets.only(top: AgriSpacing.xs),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Jour', style: style)),
          Expanded(flex: 3, child: Text('Poste', style: style)),
          Expanded(flex: 3, child: Text('Serveur', style: style)),
          Expanded(flex: 3, child: Text('Écart', style: style)),
        ],
      ),
    );
  }

  Widget _ligneCoherence(String table, LigneCoherence l) {
    final couleur = l.conforme ? AgriColors.onSurface : AgriColors.errorDeep;
    final style = TextStyle(fontSize: 11, color: couleur);

    return Padding(
      key: Key('coherence-$table-${l.jour}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(_jourFr(l.jour), style: style)),
          Expanded(flex: 3, child: Text(_totaux(l.poste), style: style)),
          Expanded(flex: 3, child: Text(_totaux(l.serveur), style: style)),
          Expanded(
            flex: 3,
            child: Text(
              l.conforme
                  ? '—'
                  : '${_signe(l.ecartNombre.toDouble())} ligne(s) · ${_signe(l.ecartTotal)}',
              style: style.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// « 3 · 3 500,5 » ; aucune ligne : « — » (le poste ou le serveur n'a rien ce jour-là).
  static String _totaux(TotauxJour? t) =>
      t == null ? '—' : '${t.nombre} · ${_nombre(t.total)}';

  static String _signe(double v) => v > 0 ? '+${_nombre(v)}' : _nombre(v);

  static String _nombre(double v) {
    final entier = v == v.roundToDouble();
    final texte = entier ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return texte.replaceAll('.', ',');
  }

  /// `AAAA-MM-JJ` → `JJ/MM/AAAA`.
  static String _jourFr(String jour) {
    final p = jour.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : jour;
  }

  static String _libelleTable(String table) => switch (table) {
    'livestock_daily_entries' => 'Fiche journalière d\'élevage',
    // Ticket BS1 — bande créée, modifiée ou archivée au poste.
    'livestock_lots' => 'Bande',
    'sales' => 'Vente',
    // Tickets AV1 / AV2 — retour client (demande de retour ou « marquer comme traité »).
    'credit_notes' => 'Retour client',
    'stock_adjustments' => 'Ajustement de stock',
    'expenses' => 'Dépense',
    // Ticket DEV — devis saisi, avancé ou archivé au poste.
    'quotes' => 'Devis',
    // Ticket DEV3 — demande de conversion d'un devis accepté en facture.
    'quote_conversions' => 'Conversion de devis en facture',
    'purchases' => 'Achat',
    'livestock_reproduction_events' => 'Saillie',
    'mails' => 'Courrier',
    'archived_documents' => 'Document archivé',
    'administrative_documents' => 'Document administratif',
    // Ticket H9b — Paramètres Élevage modifiés au poste.
    'feed_ration_standards' => 'Ration (Paramètres Élevage)',
    'prophylaxis_schedule_standards' => 'Échéance de prophylaxie',
    'feed_types' => 'Type de provende',
    'elevage_numbering' => 'Numérotation des bandes et sujets',
    'company_settings' => 'Rappel des soins planifiés',
    _ => table,
  };

  /// Un instant technique, affiché à l'heure du Bénin quel que soit le réglage de Windows (S-T11).
  static String _horodatage(DateTime d) {
    final l = HeureBenin.depuisInstant(d);
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}
