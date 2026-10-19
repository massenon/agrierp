import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';

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
  });

  final AppDatabase database;
  final SyncEngine engine;

  @override
  State<SynchronisationScreen> createState() => _SynchronisationScreenState();
}

class _SynchronisationScreenState extends State<SynchronisationScreen> {
  int _enAttente = 0;
  List<SyncConflict> _conflits = const [];
  SyncStateData? _etat;
  bool _enCours = false;

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
            content: Text('Synchronisation impossible — $e'),
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

  static String _libelleTable(String table) => switch (table) {
    'livestock_daily_entries' => 'Fiche journalière d\'élevage',
    'sales' => 'Vente',
    'stock_adjustments' => 'Ajustement de stock',
    'expenses' => 'Dépense',
    'purchases' => 'Achat',
    'livestock_reproduction_events' => 'Saillie',
    'mails' => 'Courrier',
    'archived_documents' => 'Document archivé',
    'administrative_documents' => 'Document administratif',
    _ => table,
  };

  static String _horodatage(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}
