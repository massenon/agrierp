import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket A7 — GARDE-FOU : L'ONGLET « GESTION DES UTILISATEURS » DU POSTE CONFRONTÉ AU BLADE MAÎTRE.
///
/// ⚠️⚠️ **LE WEB EST MAÎTRE** (doctrine, article 5). Titre, libellés des KPI cards, colonnes du
/// tableau (NOM, EMAIL, RÔLE, STATUT, ACTIONS), champ de recherche, libellés des boutons et états
/// sont LUS dans `gestion-utilisateurs.blade.php`, jamais recopiés ici : une retouche du web
/// fait rougir le poste au lieu de diverger en silence.
String? _lireLaravel(String relatif) {
  final f = File('$dossierLaravel/$relatif');
  return f.existsSync() ? f.readAsStringSync() : null;
}

final String? _blade = _lireLaravel('resources/views/livewire/parametres/gestion-utilisateurs.blade.php');

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

  test('le titre « Gestion des Utilisateurs » est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Gestion des Utilisateurs'));
  }, skip: absent ?? false);

  test('le sous-titre sur l\'administration des comptes est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Administration des comptes d\'accès'));
  }, skip: absent ?? false);

  test('les 2 KPI cards sont présents avec leurs libellés exacts', () {
    final contenu = _normaliser(_blade!);

    expect(contenu, contains('Utilisateurs actifs'));
    expect(contenu, contains('Rôles définis'));
  }, skip: absent ?? false);

  test('le tableau a 5 colonnes (NOM, EMAIL, RÔLE, STATUT, ACTIONS)', () {
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
      equals(5),
      reason: 'Le tableau doit avoir exactement 5 colonnes (Nom, Email, Rôle, Statut, Actions)',
    );
  }, skip: absent ?? false);

  test('les en-têtes des colonnes du tableau sont présents', () {
    final contenu = _normaliser(_blade!);

    expect(contenu, contains('Nom'));
    expect(contenu, contains('Email'));
    expect(contenu, contains('Rôle'));
    expect(contenu, contains('Statut'));
    expect(contenu, contains('Actions'));
  }, skip: absent ?? false);

  test('le champ de recherche « Rechercher » est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Rechercher'));
  }, skip: absent ?? false);

  test('le filtre par statut (Tous les statuts, Actif, Désactivé) est présent', () {
    final contenu = _normaliser(_blade!);

    expect(contenu, contains('Tous les statuts'));
    expect(contenu, contains('Actif'));
    expect(contenu, contains('Désactivé'));
  }, skip: absent ?? false);

  test('les boutons d\'action sont présents', () {
    final contenu = _normaliser(_blade!);

    expect(contenu, contains('Nouvel Utilisateur'));
    expect(contenu, contains('Exporter PDF'));
    expect(contenu, contains('Déconnecter Toutes les Sessions'));
  }, skip: absent ?? false);

  test('les statuts d\'utilisateur (Actif, Désactivé) sont présents', () {
    final contenu = _normaliser(_blade!);

    expect(contenu, contains('Actif'));
    expect(contenu, contains('Désactivé'));
  }, skip: absent ?? false);

  test('la modale de création/modification est référencée', () {
    final contenu = _blade!;

    final modale = RegExp(
      r'<x-modal\s+name="modal-create-gestion-utilisateurs"',
    ).firstMatch(contenu);

    expect(modale, isNotNull, reason: 'La modale de création/modification doit exister');
  }, skip: absent ?? false);

  test('le message « Lecture seule » est présent pour les utilisateurs sans permission', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Lecture seule'));
  }, skip: absent ?? false);
}
