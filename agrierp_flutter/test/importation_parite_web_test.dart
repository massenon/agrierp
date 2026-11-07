import 'dart:io';

import 'package:agrierp/features/importation/importation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket IMPORT-1 — FIDÉLITÉ DE LIBELLÉS : l'écran du poste reprend ceux du Blade du web (le maître), mot pour mot. L'écran
/// n'existe pas dans le prototype : c'est la vue `importation-masse.blade.php` qui est lue ici.
void main() {
  final blade = File('$dossierLaravel/resources/views/livewire/stocks/importation-masse.blade.php');
  final ecran = File('lib/features/importation/importation_screen.dart');
  final saut = blade.existsSync() ? null : 'SAUT : Blade absent (${blade.path})';

  test('chaque libellé de l\'écran web existe dans l\'écran du poste', () {
    final web = blade.readAsStringSync();
    final poste = ecran.readAsStringSync();
    const libelles = [
      'Importation en masse',
      'Module', 'Modèle', 'Fichier', 'Aperçu', 'Confirmation', 'Rapport',
      'Télécharger le modèle',
      "J'ai le modèle rempli : déposer mon fichier",
      'Changer de module',
      'Retour au modèle',
      'Changer de fichier',
      'Abandonner',
      "Confirmer l'importation",
      'Télécharger le rapport',
      'Corriger le fichier puis ré-importer',
      'Nouvel import',
      'Toutes les lignes',
      'Refusées seulement',
      'Ignorées seulement',
      'Créées seulement',
      'Valides seulement',
      'Lignes lues',
      'Ignorées (déjà présentes)',
      'Refusées',
      'Désignation',
      'Valeurs lues',
      'Résultat',
      'Motif',
      'Précédent',
      'Suivant',
      "L'importation ne peut pas être confirmée.",
      'Aucune ligne pour ce filtre.',
    ];
    for (final l in libelles) {
      expect(web, contains(l.replaceAll("'", "'")), reason: 'absent du Blade : $l');
      expect(poste.replaceAll(r"\'", "'"), contains(l.replaceAll("'", "'")), reason: 'absent du poste : $l');
    }
    // Titres d'étapes (casse : le Blade les met en capitales par CSS, le poste les écrit en capitales).
    for (final t in ["1 · Que voulez-vous importer ?", "Aperçu — rien n'est encore écrit", "Rapport d'importation", "Confirmer l'importation"]) {
      expect(web, contains(t));
      expect(poste.toUpperCase().replaceAll(r"\'", "'"), contains(t.toUpperCase()), reason: t);
    }
    expect(web, contains('Employés, plan comptable et barème de rationnement viendront dans une prochaine phase.'));
    expect(poste, contains('Employés, plan comptable et barème de rationnement viendront dans une prochaine phase.'));
  }, skip: saut);

  test('les trois modules ont le libellé et la description du web (un seul registre côté serveur)', () {
    for (final cle in ['Stocks', 'Clients', 'Fournisseurs']) {
      final php = File('$dossierLaravel/app/Services/Import/Import${cle}Service.php').readAsStringSync();
      final m = ImportationRepository.module(cle.toLowerCase())!;
      expect(php, contains("return '${m.libelle}';"));
      expect(php.replaceAll(r"\'", "'"), contains("return '${m.description}';"));
      expect(php, contains("return '${m.permission}';"));
    }
  }, skip: saut);

  test('le poste n\'écrit rien lui-même : seuls les dépôts propriétaires sont appelés (garde de lecture de sources)', () {
    final src = File('lib/features/importation/importation_repository.dart').readAsStringSync();
    expect(src, isNot(contains('.into(database.')), reason: 'aucun INSERT direct');
    expect(src, isNot(contains('database.update(')));
    expect(src, isNot(contains('database.delete(')));
    expect(src, contains('ProduitsRepository(database: database).creer('));
    expect(src, contains('creerClient('));
    expect(src, contains('creerFournisseur('));
    expect(src, isNot(contains('stockQty')), reason: 'aucun stock écrit hors du dépôt des produits');
  });
}
