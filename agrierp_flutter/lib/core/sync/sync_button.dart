import 'package:flutter/material.dart';

import '../theme/agri_tokens.dart';
import 'sync_engine.dart';

/// Bouton « Synchroniser » du pied de la barre latérale.
///
/// FIDÉLITÉ À LA MAQUETTE — `prototype_html/assets/js/sidebar.js`, ligne 94 :
/// ```
/// w-full py-sm bg-accent-yellow text-brand-forest font-bold rounded-lg
/// flex items-center justify-center gap-xs text-xs
/// <span class="material-symbols-outlined text-[16px]">sync</span> Synchroniser
/// ```
/// Pleine largeur, fond `accent-yellow`, texte `brand-forest` en gras, coins
/// `rounded-lg` (8 px), icône 16 px suivie du libellé, espacés de `gap-xs`.
///
/// ⚠️ CE BOUTON N'EXISTE QUE CÔTÉ FLUTTER. Il a été RETIRÉ de la surface web
/// au Sprint 0 §0.2, et ce n'est pas un oubli : le web écrit en base de façon
/// synchrone, sans file d'attente locale. Un bouton « Synchroniser » y serait
/// un décor sans mécanisme derrière.
///
/// ⚠️ LE BADGE COMPTE DES ENREGISTREMENTS RÉELS, jamais une estimation. Tant
/// qu'il affiche un nombre, ces saisies n'existent QUE sur cet appareil : si
/// l'utilisateur voit « 0 en attente » alors qu'il reste des ventes en file,
/// il éteindra le poste en croyant son travail à l'abri.
class SyncButton extends StatefulWidget {
  const SyncButton({
    super.key,
    required this.engine,
    required this.pendingCount,
    this.onTermine,
  });

  final SyncEngine engine;

  /// Nombre d'enregistrements en attente, relu après chaque tentative.
  final Future<int> Function() pendingCount;

  /// Appelé à la fin de chaque tentative, réussie ou non — pour que la barre
  /// supérieure (compteur de la cloche) relise ce que le tirage a apporté.
  final VoidCallback? onTermine;

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton> {
  int _enAttente = 0;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _rafraichir();
  }

  Future<void> _rafraichir() async {
    final n = await widget.pendingCount();
    if (mounted) setState(() => _enAttente = n);
  }

  Future<void> _synchroniser() async {
    if (_enCours) return;
    setState(() => _enCours = true);

    try {
      final resultat = await widget.engine.synchroniser();
      if (!mounted) return;
      _annoncer(resultat);
    } catch (e) {
      // ⚠️ L'ÉCHEC EST DIT, JAMAIS AVALÉ. Une synchronisation qui échoue en
      // silence laisse croire au travail transmis ; c'est le seul moment où
      // l'utilisateur peut encore agir (rester connecté, réessayer).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AgriColors.errorDeep,
          content: Text('Synchronisation impossible — $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _enCours = false);
      await _rafraichir();
      if (mounted) widget.onTermine?.call();
    }
  }

  void _annoncer(SyncOutcome r) {
    if (r.horsLigne) {
      // Hors ligne est le mode NORMAL de cette ferme : ton d'information,
      // jamais d'erreur. Les données restent en file, et le message le dit.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AgriColors.brandForest,
          content: Text(
            _enAttente > 0
                ? 'Hors ligne — $_enAttente saisie(s) conservée(s) sur cet appareil.'
                : 'Hors ligne — rien à envoyer pour le moment.',
          ),
        ),
      );
      return;
    }

    // ⚠️ F0.84-bis : ce que le tirage a constaté SANS refuser (journal vide à confirmer, journal
    // incomplet) n'est jamais présenté comme un simple « Déjà à jour » : l'utilisateur doit le lire.
    if (r.rejete == 0 && r.avertissements.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AgriColors.errorDeep,
          duration: const Duration(seconds: 12),
          content: Text(r.avertissements.join(' ')),
        ),
      );
      return;
    }

    final phrases = <String>[
      if (r.tire > 0) '${r.tire} référence(s) reçue(s)',
      if (r.accepte > 0) '${r.accepte} saisie(s) envoyée(s)',
    ];

    // ⚠️ UN REJET N'EST JAMAIS PRÉSENTÉ COMME UN SUCCÈS PARTIEL DISCRET :
    // l'enregistrement reste dans la file et le motif serveur est montré.
    if (r.rejete > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AgriColors.errorDeep,
          duration: const Duration(seconds: 8),
          content: Text(
            '${r.rejete} saisie(s) refusée(s) par le serveur, conservée(s) ici. '
            '${r.motifs.isNotEmpty ? r.motifs.first : ''}'
            '${r.avertissements.isNotEmpty ? ' ${r.avertissements.join(' ')}' : ''}',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AgriColors.brandEmerald,
        content: Text(
          phrases.isEmpty ? 'Déjà à jour.' : '${phrases.join(', ')}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _enCours ? null : _synchroniser,
            style: FilledButton.styleFrom(
              backgroundColor: AgriColors.accentYellow,
              foregroundColor: AgriColors.brandForest,
              disabledBackgroundColor: AgriColors.accentYellow.withValues(
                alpha: 0.6,
              ),
              disabledForegroundColor: AgriColors.brandForest,
              padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_enCours)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AgriColors.brandForest,
                    ),
                  )
                else
                  const Icon(Icons.sync, size: 16),
                const SizedBox(width: AgriSpacing.xs),
                const Text(
                  'Synchroniser',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_enAttente > 0) ...[
          const SizedBox(height: AgriSpacing.xs),
          Text(
            '$_enAttente en attente',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: AgriColors.accentYellow,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }
}
