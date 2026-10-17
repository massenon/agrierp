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
    if (mounted) {
      setState(() {
        _enregistree = actuelle;
        _adresse.text = actuelle;
      });
    }
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
        ],
      ),
    );
  }
}
