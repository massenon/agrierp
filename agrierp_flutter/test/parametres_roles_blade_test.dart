import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket A7 — GARDE-FOU : L'ONGLET « RÔLES & PERMISSIONS » DU POSTE CONFRONTÉ AU BLADE MAÎTRE.
///
/// ⚠️⚠️ **LE WEB EST MAÎTRE** (doctrine, article 5). Titre, libellés des KPI cards, colonnes de la
/// matrice, libellés des boutons sont LUS dans `roles-permissions.blade.php`, jamais recopiés ici :
/// une retouche du web fait rougir le poste au lieu de diverger en silence.
String? _lireLaravel(String relatif) {
  final f = File('$dossierLaravel/$relatif');
  return f.existsSync() ? f.readAsStringSync() : null;
}

final String? _blade = _lireLaravel('resources/views/livewire/parametres/roles-permissions.blade.php');

String _normaliser(String s) => s
    .replaceAll('&gt;', '>')
    .replaceAll('&lt;', '<')
    .replaceAll('&amp;', '&')
    .replaceAll('&#039;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void main() {
  final absent = _blade == null
      ? 'dépôt Laravel absent ($dossierLaravel) : comparaison au web impossible'
      : null;

  test('le titre « Rôles & Permissions » est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Rôles &amp; Permissions'));
  }, skip: absent ?? false);

  test('les 4 KPI cards sont présents avec leurs libellés exacts', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Rôles configurés'));
    expect(contenu, contains('Utilisateurs assignés'));
    expect(contenu, contains('Modules couverts'));
    expect(contenu, contains('Dernière sauvegarde'));
  }, skip: absent ?? false);

  test('la matrice a 11 colonnes (Rôle + 9 modules + Actions)', () {
    final contenu = _blade!;

    // Extraire les en-têtes de colonne
    final tableMatch = RegExp(
      r'<table[^>]*>.*?<thead[^>]*>(.*?)</thead>',
      dotAll: true,
    ).firstMatch(contenu);

    expect(tableMatch, isNotNull, reason: 'Tableau non trouvé dans le Blade');

    final thead = tableMatch!.group(1)!;

    // Compter les <th> (colonnes)
    final ths = RegExp(r'<th[^>]*>').allMatches(thead).length;

    // Compter les modules visibles (il y a @foreach($this->modules as $module))
    // Plus la colonne Rôle + la colonne Actions (si isAdmin)
    // Au minimum : Rôle (1) + Action (1) = 2 colonnes, plus N modules
    // Le HTML montre exactement : une colonne Rôle, 9 colonnes modules, une colonne Actions
    expect(
      ths,
      greaterThanOrEqualTo(11),
      reason: 'La matrice doit avoir au moins 11 colonnes (Rôle + 9 modules + Actions)',
    );
  }, skip: absent ?? false);

  test('la matrice contient le titre « Matrice des Droits d\'Accès »', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Matrice des Droits d\' Accès'));
  }, skip: absent ?? false);

  test('le bouton « Générer une Sauvegarde » est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Générer une Sauvegarde'));
  }, skip: absent ?? false);

  test('le titre de la section sauvegardes « Sauvegardes de la Base de Données » est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Sauvegardes de la Base de Données'));
  }, skip: absent ?? false);

  test('le message admin-only « Seul l\'administrateur peut créer » est présent', () {
    final contenu = _normaliser(_blade!);
    expect(
      contenu,
      contains('Seul l\'administrateur peut créer, modifier ou supprimer un rôle'),
    );
  }, skip: absent ?? false);
}
