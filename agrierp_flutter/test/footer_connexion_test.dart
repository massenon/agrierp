// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde-fou : le texte du footer de l'écran de connexion doit être identique
/// côté web (Blade) et côté poste (Flutter).
///
/// Ce test lit les deux fichiers sources et vérifie que le texte de référence
/// du client apparaît dans chacun d'eux.
void main() {
  const texteAttendu = 'Dr MASSENON Rhodes';
  const texteCompletClient =
      '(PAEB)/Cabinet FAGUEZ SARL — Conçu par Dr MASSENON Rhodes';

  /// Chemin vers la vue Blade dans le monorepo.
  /// La variable d'environnement AGRIERP_LARAVEL permet de pointer vers un
  /// chemin différent (ex. : ancien chemin Windows).
  String cheminBlade() {
    final env = Platform.environment['AGRIERP_LARAVEL'];
    if (env != null && env.isNotEmpty) {
      return '$env/resources/views/livewire/auth/login.blade.php';
    }
    // Chemin relatif au monorepo (ce fichier est dans agrierp_flutter/test/).
    return '../../agrierp_laravel/resources/views/livewire/auth/login.blade.php';
  }

  group('Footer de connexion — parité web ↔ poste', () {
    test('le Blade de connexion contient le texte du client', () {
      final fichier = File(cheminBlade());
      expect(
        fichier.existsSync(),
        isTrue,
        reason:
            'La vue Blade ${fichier.path} est introuvable. '
            'Vérifier le chemin ou définir AGRIERP_LARAVEL.',
      );
      final contenu = fichier.readAsStringSync();
      expect(
        contenu,
        contains(texteAttendu),
        reason:
            'Le footer du Blade de connexion doit contenir "$texteAttendu".',
      );
      expect(
        contenu,
        contains(texteCompletClient),
        reason:
            'Le footer du Blade de connexion doit contenir "$texteCompletClient".',
      );
    });

    test('le widget Flutter de connexion contient le texte du client', () {
      const cheminFlutter =
          'lib/features/auth/login_screen.dart';
      final fichier = File(cheminFlutter);
      expect(
        fichier.existsSync(),
        isTrue,
        reason: 'Le fichier Flutter $cheminFlutter est introuvable.',
      );
      final contenu = fichier.readAsStringSync();
      expect(
        contenu,
        contains(texteAttendu),
        reason:
            'Le widget Flutter de connexion doit contenir "$texteAttendu".',
      );
      expect(
        contenu,
        contains(texteCompletClient),
        reason:
            'Le widget Flutter de connexion doit contenir "$texteCompletClient".',
      );
    });

    test('le texte du footer web et du footer Flutter sont identiques', () {
      final blade = File(cheminBlade());
      const flutter = 'lib/features/auth/login_screen.dart';

      if (!blade.existsSync()) {
        markTestSkipped(
          'Vue Blade introuvable (${blade.path}) — test de parité ignoré.',
        );
        return;
      }

      final contenuBlade = blade.readAsStringSync();
      final contenuFlutter = File(flutter).readAsStringSync();

      // Les deux fichiers doivent contenir exactement le même texte de référence.
      expect(
        contenuBlade,
        contains(texteAttendu),
        reason: 'Le Blade ne contient pas "$texteAttendu".',
      );
      expect(
        contenuFlutter,
        contains(texteAttendu),
        reason: 'Le widget Flutter ne contient pas "$texteAttendu".',
      );

      // Les deux doivent contenir la formulation complète du client.
      expect(
        contenuBlade,
        contains(texteCompletClient),
        reason: 'Le Blade ne contient pas la formulation complète du client.',
      );
      expect(
        contenuFlutter,
        contains(texteCompletClient),
        reason:
            'Le widget Flutter ne contient pas la formulation complète du client.',
      );
    });
  });
}
