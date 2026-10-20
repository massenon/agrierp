import 'package:flutter/material.dart';

import '../../core/erreurs/message_erreur.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/agri_tokens.dart';
import 'premier_demarrage_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// Ticket F0.98 — écran du PREMIER DÉMARRAGE, affiché après la connexion sur un poste qui n'a jamais
/// synchronisé (hors maquette, demandé par le client). ⚠️ NON BLOQUANT : « Plus tard » ouvre l'application.
/// Chaque étape est constatée, jamais cochée à la main.
class PremierDemarrageScreen extends StatefulWidget {
  const PremierDemarrageScreen({
    super.key,
    required this.depot,
    required this.engine,
    required this.utilisateur,
    required this.onTermine,
  });

  final PremierDemarrageRepository depot;
  final SyncEngine engine;
  final String utilisateur;
  final VoidCallback onTermine;

  @override
  State<PremierDemarrageScreen> createState() => _PremierDemarrageScreenState();
}

class _PremierDemarrageScreenState extends State<PremierDemarrageScreen> {
  String? _adresse;
  String? _identifiant;
  bool _enCours = false;
  bool _synchronise = false;
  String? _compteRendu;
  String? _echec;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final adresse = await widget.depot.adresse();
    final identifiant = await widget.depot.identifiant();
    final neuf = await widget.depot.posteNeuf();
    if (!mounted) return;
    setState(() {
      _adresse = adresse;
      _identifiant = identifiant;
      _synchronise = !neuf;
    });
  }

  Future<void> _synchroniser() async {
    setState(() {
      _enCours = true;
      _echec = null;
    });
    try {
      final r = await widget.engine.synchroniser();
      final neuf = await widget.depot.posteNeuf();
      if (!mounted) return;
      setState(() {
        if (r.horsLigne) {
          _echec = 'Serveur injoignable : vérifiez la connexion du poste, puis relancez.';
        } else {
          _synchronise = !neuf;
          _compteRendu = [
            '${r.tire} enregistrement(s) reçu(s) du serveur.',
            ...r.avertissements,
            ...r.motifs,
          ].join('\n');
        }
      });
    } catch (e) {
      // Ticket U5 : jamais l'exception brute (anglaise) à l'écran.
      if (mounted) {
        setState(() => _echec = 'Synchronisation impossible — ${messageErreur(e)}');
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Widget _etape(String cle, int numero, String titre, String detail, bool fait) {
    return Container(
      key: Key('premier-etape-$cle'),
      margin: const EdgeInsets.only(bottom: AgriSpacing.sm),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            fait ? SymbolesAgri.check_circle : SymbolesAgri.pending,
            size: 20,
            color: fait ? AgriColors.brandEmerald : AgriColors.errorDeep,
          ),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$numero. $titre',
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    color: AgriColors.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AgriSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Premier démarrage du poste',
                  style: TextStyle(
                    fontSize: AgriTypography.xl,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const SizedBox(height: AgriSpacing.xs),
                const Text(
                  "Ce poste n'a encore rien reçu du serveur : bandes, produits, exercice et comptes "
                  "n'y existent qu'après une première synchronisation.",
                  style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
                ),
                const SizedBox(height: AgriSpacing.md),
                _etape(
                  'serveur',
                  1,
                  'Serveur',
                  '${_adresse ?? '—'} · identifiant du poste : ${_identifiant ?? '—'}',
                  _adresse != null,
                ),
                _etape('session', 2, 'Session ouverte', widget.utilisateur, true),
                _etape(
                  'synchronisation',
                  3,
                  'Première synchronisation',
                  _synchronise
                      ? 'Faite : le poste peut travailler hors ligne.'
                      : 'À lancer maintenant, poste connecté.',
                  _synchronise,
                ),
                if (_compteRendu != null)
                  Text(
                    _compteRendu!,
                    key: const Key('premier-compte-rendu'),
                    style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.brandForest),
                  ),
                if (_echec != null)
                  Text(
                    _echec!,
                    key: const Key('premier-echec'),
                    style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
                  ),
                const SizedBox(height: AgriSpacing.md),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AgriSpacing.sm,
                  runSpacing: AgriSpacing.xs,
                  children: [
                    TextButton(
                      key: const Key('premier-plus-tard'),
                      onPressed: widget.onTermine,
                      child: const Text('Plus tard'),
                    ),
                    if (_synchronise)
                      FilledButton(
                        key: const Key('premier-continuer'),
                        onPressed: widget.onTermine,
                        child: const Text('Continuer'),
                      )
                    else
                      FilledButton(
                        key: const Key('premier-synchroniser'),
                        onPressed: _enCours ? null : _synchroniser,
                        child: Text(_enCours ? 'Synchronisation…' : 'Lancer la première synchronisation'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
