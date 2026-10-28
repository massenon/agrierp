import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../localisation/localisation_poste.dart';
import '../theme/agri_tokens.dart';
import '../temps/heure_benin.dart';
import 'dossier_donnees.dart';

/// Démarrage du poste : une panne AU LANCEMENT se VOIT, elle ne laisse pas un processus fantôme.
///
/// ⚠️⚠️ **POURQUOI.** La fenêtre du poste est créée CACHÉE et n'est montrée qu'à la première image (`flutter_window.cpp`).
/// Si `main()` lève une exception ou attend indéfiniment AVANT `runApp` (base locale illisible, migration impossible,
/// fichier verrouillé par une autre instance), aucune image n'est jamais dessinée : l'utilisateur double-clique,
/// rien ne s'ouvre, et `agrierp.exe` reste dans les processus d'arrière-plan sans que personne sache pourquoi.
/// Ici, toute panne de démarrage est journalisée (`demarrage.log`, dossier des données du poste) ET remplacée par un
/// écran qui dit quoi faire.
class DemarragePoste {
  const DemarragePoste._();

  /// Au-delà, la préparation est tenue pour bloquée (base verrouillée par une autre instance, disque très lent).
  static const delaiMaximal = Duration(seconds: 45);

  /// Construit l'application, ou à défaut l'écran d'échec de démarrage. Ne lève JAMAIS.
  static Future<Widget> preparer({
    required Future<Widget> Function() construire,
    Duration delai = delaiMaximal,
    Future<String?> Function(String texte)? journaliser,
  }) async {
    final ecrire = journaliser ?? ecrireJournal;

    try {
      return await construire().timeout(delai);
    } on TimeoutException {
      final chemin = await ecrire(
        'Démarrage bloqué : la préparation de la base locale a dépassé ${delai.inSeconds} s.',
      );

      return EcranDemarrageImpossible(
        cause:
            "La base locale ne s'est pas ouverte en ${delai.inSeconds} secondes. Une autre fenêtre AgriERP est peut-être "
            "encore ouverte en arrière-plan.",
        journal: chemin,
      );
    } on Object catch (e, pile) {
      final chemin = await ecrire('Démarrage impossible : $e\n$pile');

      return EcranDemarrageImpossible(
        cause: "La base locale n'a pas pu être ouverte (détail technique) : $e",
        journal: chemin,
      );
    }
  }

  /// Ajoute une ligne datée à `demarrage.log` (dossier des données du poste) ; rend son chemin, `null` si l'écriture
  /// elle-même échoue — le journal ne doit jamais ajouter une panne à la panne.
  static Future<String?> ecrireJournal(String texte) async {
    try {
      final dossier = await DossierDonnees.courant();
      final fichier = File(p.join(dossier.path, 'demarrage.log'));
      await fichier.writeAsString(
        '[${HeureBenin.maintenant().toIso8601String()}] $texte\n',
        mode: FileMode.append,
        flush: true,
      );

      return fichier.path;
    } on Object {
      return null;
    }
  }
}

/// L'écran montré quand le poste ne peut pas démarrer. Il propose de quitter : la fenêtre n'a pas de cadre système.
class EcranDemarrageImpossible extends StatelessWidget {
  const EcranDemarrageImpossible({super.key, required this.cause, this.journal, this.quitter});

  final String cause;

  /// Chemin du journal, `null` s'il n'a pas pu être écrit.
  final String? journal;

  /// Injectable pour les tests ; par défaut, ferme le processus.
  final VoidCallback? quitter;

  @override
  Widget build(BuildContext context) {
    // Le seul autre `MaterialApp` du poste (hors `main.dart`) : il porte la MÊME localisation française, sinon ses
    // boutons et dialogues systèmes sortiraient en anglais (`localisation_francaise_test.dart` le garde).
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: LocalisationPoste.locale,
      supportedLocales: LocalisationPoste.locales,
      localizationsDelegates: LocalisationPoste.delegues,
      home: Scaffold(
        backgroundColor: const Color(0xFFF8FAF9),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AgriERP ne peut pas démarrer',
                    key: Key('demarrage-titre'),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF052E16)),
                  ),
                  const SizedBox(height: 12),
                  Text(cause, key: const Key('demarrage-cause'), style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  const Text(
                    "Que faire : fermez toute autre fenêtre AgriERP (Gestionnaire des tâches, processus « agrierp.exe »), "
                    "puis relancez le logiciel. Vos données ne sont pas touchées. Si le message revient, transmettez le "
                    "fichier ci-dessous à l'Éditeur.",
                    style: TextStyle(fontSize: AgriTypography.xs),
                  ),
                  if (journal != null) ...[
                    const SizedBox(height: 12),
                    SelectableText('Journal : $journal', key: const Key('demarrage-journal'), style: const TextStyle(fontSize: AgriTypography.xs)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('demarrage-quitter'),
                    onPressed: quitter ?? () => exit(0),
                    child: const Text('Quitter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
