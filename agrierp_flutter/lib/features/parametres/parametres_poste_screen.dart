import 'package:flutter/material.dart';

import '../../core/config/parametres_poste.dart';
import '../../core/theme/agri_tokens.dart';

/// Paramètres du poste — identifiant et adresse du serveur.
///
/// ⚠️ **ÉCRAN HORS MAQUETTE, COMME CELUI DE SYNCHRONISATION.** Le prototype
/// est une surface web : il n'a ni poste à identifier ni serveur à désigner.
/// L'écran existe parce qu'une installation réelle en a besoin — AJOUT au-delà
/// du prototype, à valider au prochain point client.
class ParametresPosteScreen extends StatefulWidget {
  const ParametresPosteScreen({
    super.key,
    required this.parametres,
    required this.identifiantActuel,
  });

  final ParametresPoste parametres;
  final String identifiantActuel;

  @override
  State<ParametresPosteScreen> createState() => _ParametresPosteScreenState();
}

class _ParametresPosteScreenState extends State<ParametresPosteScreen> {
  final _adresse = TextEditingController();
  String _enregistree = '';

  /// Ticket H13 — intervalle de la synchronisation automatique, en minutes.
  int? _intervalle;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _adresse.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final actuelle = await widget.parametres.adresseServeur();
    final intervalle = await widget.parametres.intervalleSynchronisation();
    if (mounted) {
      setState(() {
        _enregistree = actuelle;
        _adresse.text = actuelle;
        _intervalle = intervalle.inMinutes;
      });
    }
  }

  Future<void> _changerIntervalle(int? minutes) async {
    if (minutes == null) return;
    await widget.parametres.definirIntervalleSynchronisation(minutes);
    await _charger();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AgriColors.brandEmerald,
        // L'intervalle est lu à l'ouverture de la session, comme l'adresse au démarrage : le dire.
        content: Text(
          'Intervalle enregistré. Il prend effet à la prochaine ouverture '
          'de session.',
        ),
      ),
    );
  }

  Future<void> _enregistrer() async {
    await widget.parametres.definirAdresseServeur(_adresse.text);
    await _charger();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AgriColors.brandEmerald,
        // ⚠️ Le client HTTP est construit au démarrage : dire qu'il faut
        // relancer évite de croire à une panne réseau alors que l'ancienne
        // adresse est encore en usage.
        content: Text(
          'Adresse enregistrée. Redémarrez l\'application pour qu\'elle '
          'prenne effet.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: ListView(
        padding: const EdgeInsets.all(AgriSpacing.lg),
        children: [
          const Text(
            'Paramètres du poste',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AgriColors.onSurface,
            ),
          ),
          const SizedBox(height: AgriSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AgriSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'IDENTIFIANT DE CE POSTE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  SelectableText(
                    widget.identifiantActuel,
                    key: const Key('identifiant-poste'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: AgriColors.brandEmerald,
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  // ⚠️ Non modifiable, et sélectionnable : le support en a
                  // besoin pour diagnostiquer un conflit. Le changer romprait
                  // l'attribution des saisies déjà envoyées — on ne saurait
                  // plus quel poste les a produites.
                  const Text(
                    'Tiré au premier lancement et conservé. Il identifie ce '
                    'poste dans l\'historique de synchronisation : il ne peut '
                    'pas être modifié.',
                    style: TextStyle(fontSize: 11, color: AgriColors.outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AgriSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ADRESSE DU SERVEUR',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  TextField(
                    key: const Key('adresse-serveur'),
                    controller: _adresse,
                    style: const TextStyle(fontSize: AgriTypography.xs),
                    decoration: const InputDecoration(
                      hintText: 'http://192.168.1.10:8000',
                      helperText:
                          'Adresse de l\'espace web AgriERP sur le réseau de '
                          'la ferme.',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Actuelle : $_enregistree',
                          key: const Key('adresse-actuelle'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AgriColors.outline,
                          ),
                        ),
                      ),
                      FilledButton(
                        key: const Key('enregistrer-adresse'),
                        onPressed: _enregistrer,
                        style: FilledButton.styleFrom(
                          backgroundColor: AgriColors.brandEmerald,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Enregistrer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AgriSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SYNCHRONISATION AUTOMATIQUE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  DropdownButton<int>(
                    key: const Key('intervalle-synchronisation'),
                    value: _intervalle,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.onSurface,
                    ),
                    items: [
                      for (final m in ParametresPoste.intervallesProposes)
                        DropdownMenuItem(
                          value: m,
                          child: Text('Toutes les $m minutes'),
                        ),
                    ],
                    onChanged: _changerIntervalle,
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  const Text(
                    'Le poste se synchronise aussi au retour du réseau et à '
                    'la fermeture. Après un échec réseau, il réessaie après '
                    '30 s, 2 min, 5 min, 15 min, puis toutes les heures.',
                    style: TextStyle(fontSize: 11, color: AgriColors.outline),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
