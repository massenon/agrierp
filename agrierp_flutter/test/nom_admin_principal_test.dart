import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket ENV1 (demande 1) — LE COMPTE ADMINISTRATEUR PRINCIPAL S'APPELLE « M. Olouchègoun ».
///
/// Décision client du 17/10/2026 (seeder web `DemoUsersSeeder`). Le poste ne doit plus montrer l'ancien nom de
/// démonstration (« Manager Olouwachegoun ») : ni en valeur par défaut du tableau de bord, ni en repli du socle quand
/// aucune session n'est ouverte, ni comme jeu d'essai. Seul le NOM D'AFFICHAGE change : l'identifiant reste `admin`.
///
/// ⚠️ Ce garde-fou LIT LE CODE : un nom par défaut n'apparaît qu'à l'exécution, dans un cas que les tests de rendu
/// ne parcourent pas (aucune session). Les libellés tirés de la maquette (`inventaire_maquette.g.dart`, qui cite
/// « Bienvenue, Manager Olouwachegoun 👋 » tel que la maquette l'écrit) ne sont pas concernés : ils sont GÉNÉRÉS.
void main() {
  const ancien = 'Manager Olouwachegoun';
  const nouveau = 'M. Olouchègoun';

  Iterable<File> fichiers(String dossier) => Directory(dossier)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));

  test("aucun code du poste ne cite l'ancien nom de démonstration de l'administrateur", () {
    final coupables = [
      for (final f in fichiers('lib'))
        if (f.readAsStringSync().contains(ancien)) f.path,
    ];
    expect(coupables, isEmpty, reason: 'remplacer « $ancien » par « $nouveau »');
  });

  test("les jeux d'essai du poste utilisent le nom du client (sauf le test de la maquette et celui-ci)", () {
    final coupables = [
      for (final f in fichiers('test'))
        if (!f.path.endsWith('nom_admin_principal_test.dart') &&
            !f.path.endsWith('fidelite_libelles_test.dart') &&
            f.readAsStringSync().contains(ancien))
          f.path,
    ];
    expect(coupables, isEmpty);
  });

  test("le tableau de bord et le socle se rabattent sur « $nouveau » quand aucune session n'est ouverte", () {
    expect(File('lib/features/pilotage/tableau_de_bord_screen.dart').readAsStringSync(),
        contains("this.nomUtilisateur = '$nouveau'"));
    expect(File('lib/main.dart').readAsStringSync(), contains("?? '$nouveau'"));
  });

  test("le seeder web nomme l'administrateur « $nouveau » sans toucher à son identifiant `admin`", () {
    final seeder = File('$dossierLaravel/database/seeders/DemoUsersSeeder.php');
    if (!seeder.existsSync()) {
      markTestSkipped('agrierp_laravel introuvable (AGRIERP_LARAVEL)');
      return;
    }
    expect(seeder.readAsStringSync(), contains("['name' => '$nouveau', 'username' => 'admin',"));
  });
}
