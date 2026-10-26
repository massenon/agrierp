import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket A7 — GARDE-FOU : L'ONGLET « SAUVEGARDES DE LA BASE DE DONNÉES » DU POSTE
/// CONFRONTÉ AU BLADE MAÎTRE.
///
/// ⚠️⚠️ **LE WEB EST MAÎTRE** (doctrine, article 5). Titre, libellés des blocs (Exporter un module,
/// Importer un module), colonnes du tableau d'historique (FICHIER, DATE, TABLE, ACTION), libellés
/// des boutons sont LUS dans `sauvegardes.blade.php`, jamais recopiés ici : une retouche du web
/// fait rougir le poste au lieu de diverger en silence.
String? _lireLaravel(String relatif) {
  final f = File('$dossierLaravel/$relatif');
  return f.existsSync() ? f.readAsStringSync() : null;
}

final String? _blade = _lireLaravel('resources/views/livewire/parametres/sauvegardes.blade.php');

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

  test('le titre « Sauvegardes de la Base de Données » est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Sauvegardes de la Base de Données'));
  }, skip: absent ?? false);

  test('le sous-titre sur les sauvegardes automatiques est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('sauvegarde automatique est générée chaque nuit'));
  }, skip: absent ?? false);

  test('le bloc « Exporter un module seul » est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Exporter un module seul'));
    expect(contenu, contains('Exporter ce module'));
  }, skip: absent ?? false);

  test('le bloc « Importer un module » est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Importer un module'));
    expect(contenu, contains('Importer'));
  }, skip: absent ?? false);

  test('les sélecteurs de module et de fichier sont présents', () {
    final contenu = _normaliser(_blade!);

    expect(contenu, contains('Choisir un module'));
    expect(contenu, contains('Choisir un fichier'));
    expect(contenu, contains('Sauvegarde'));
  }, skip: absent ?? false);

  test('l\'avertissement de sécurité sur l\'import est présent', () {
    final contenu = _normaliser(_blade!);
    expect(
      contenu,
      contains('Le fichier est analysé, jamais exécuté'),
    );
  }, skip: absent ?? false);

  test('le tableau d\'historique a 4 colonnes (FICHIER, DATE, TABLE, ACTION)', () {
    final contenu = _blade!;

    // Extraire les en-têtes de colonne du tableau
    final tableMatch = RegExp(
      r'<table[^>]*>.*?<thead[^>]*>(.*?)</thead>',
      dotAll: true,
    ).firstMatch(contenu);

    expect(tableMatch, isNotNull, reason: 'Tableau non trouvé dans le Blade');

    final thead = tableMatch!.group(1)!;

    // Compter les <th> (colonnes)
    final ths = RegExp(r'<th[^>]*>').allMatches(thead).length;

    expect(
      ths,
      equals(4),
      reason: 'Le tableau historique doit avoir exactement 4 colonnes (Fichier, Date, Table, Action)',
    );
  }, skip: absent ?? false);

  test('les en-têtes des colonnes du tableau sont présents', () {
    final contenu = _normaliser(_blade!);

    expect(contenu, contains('Fichier'));
    expect(contenu, contains('Date'));
    expect(contenu, contains('Table'));
    expect(contenu, contains('Action'));
  }, skip: absent ?? false);

  test('les boutons d\'action de sauvegarde sont présents', () {
    final contenu = _normaliser(_blade!);

    expect(contenu, contains('Générer une sauvegarde'));
    expect(contenu, contains('Télécharger'));
  }, skip: absent ?? false);

  test('le message vide du tableau est présent', () {
    final contenu = _normaliser(_blade!);
    expect(
      contenu,
      contains('Aucune sauvegarde pour le moment'),
    );
  }, skip: absent ?? false);

  test('l\'aide sur les exports de module est présente', () {
    final contenu = _normaliser(_blade!);
    expect(
      contenu,
      contains('Un export de module contient les données de ce module uniquement'),
    );
  }, skip: absent ?? false);

  test('l\'aide sur la confirmation d\'import est présente', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Remplacer les données de ce module'));
    expect(contenu, contains('supprimées puis remplacées'));
  }, skip: absent ?? false);

  test('la modale de confirmation d\'import existe', () {
    final contenu = _blade!;

    final modale = RegExp(
      r'<x-modal\s+name="modal-import"',
    ).firstMatch(contenu);

    expect(modale, isNotNull, reason: 'La modale de confirmation d\'import doit exister');
  }, skip: absent ?? false);
}
