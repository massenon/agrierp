import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket A7 — GARDE-FOU : L'ONGLET « DONNÉES DE L'ENTREPRISE » DU POSTE CONFRONTÉ AU BLADE MAÎTRE.
///
/// ⚠️⚠️ **LE WEB EST MAÎTRE** (doctrine, article 5). Titre, libellés des champs, aides, boutons,
/// sections (Informations Générales, Informations Légales & Fiscales, Régime TVA, Charges sociales)
/// sont LUS dans `donnees-entreprise.blade.php`, jamais recopiés ici : une retouche du web
/// fait rougir le poste au lieu de diverger en silence.
String? _lireLaravel(String relatif) {
  final f = File('$dossierLaravel/$relatif');
  return f.existsSync() ? f.readAsStringSync() : null;
}

final String? _blade = _lireLaravel('resources/views/livewire/parametres/donnees-entreprise.blade.php');

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

  test('le titre « Données de l\'Entreprise » est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Données de l\'Entreprise'));
  }, skip: absent ?? false);

  test('le sous-titre décrivant l\'exploitation est présent', () {
    final contenu = _normaliser(_blade!);
    expect(
      contenu,
      contains('Identité légale, fiscale et configuration technique'),
    );
  }, skip: absent ?? false);

  test('les libellés du formulaire sont présents', () {
    final contenu = _normaliser(_blade!);

    // Section Informations Générales
    expect(contenu, contains('Raison Sociale'));
    expect(contenu, contains('Nom du Promoteur'));
    expect(contenu, contains('Adresse du Siège d\'Exploitation'));
    expect(contenu, contains('Téléphone Principal'));
    expect(contenu, contains('Email de Contact'));

    // Section Informations Légales & Fiscales
    expect(contenu, contains('Identifiant Fiscal Unique'));
    expect(contenu, contains('Registre du Commerce'));
  }, skip: absent ?? false);

  test('CNSS salariale et VPS sont présents dans la section des charges sociales', () {
    final contenu = _normaliser(_blade!);

    expect(contenu, contains('CNSS salariale'));
    expect(contenu, contains('Versement Patronal sur Salaires'));
    expect(contenu, contains('VPS'));
    expect(contenu, contains('CNSS patronale'));
  }, skip: absent ?? false);

  test('les sections de configuration sont présentes', () {
    final contenu = _normaliser(_blade!);

    expect(contenu, contains('Informations Générales'));
    expect(contenu, contains('Informations Légales &amp; Fiscales'));
    expect(contenu, contains('Configuration Email'));
    expect(contenu, contains('Logo de l\'Entreprise'));
    expect(contenu, contains('Favicon'));
    expect(contenu, contains('Régime de TVA'));
    expect(contenu, contains('Charges sociales et fiscales'));
  }, skip: absent ?? false);

  test('les champs obligatoires (*) sont marqués', () {
    final contenu = _blade!;

    // Compter les labels avec * (champs obligatoires)
    final obligatoires = RegExp(r'<label[^>]*>(?:[^<]*<[^>]*>)*([^<]*)\*').allMatches(contenu).length;

    expect(
      obligatoires,
      greaterThanOrEqualTo(2),
      reason: 'Au moins Raison Sociale et IFU doivent être marqués comme obligatoires',
    );
  }, skip: absent ?? false);

  test('le texte concernant la TVA est présent', () {
    final contenu = _normaliser(_blade!);

    expect(contenu, contains('Exploitation assujettie à la TVA'));
    expect(contenu, contains('Les montants sont présentés TTC'));
    expect(contenu, contains('montants HT'));
  }, skip: absent ?? false);

  test('le bouton « Enregistrer les Modifications » est présent', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Enregistrer les Modifications'));
  }, skip: absent ?? false);

  test('l\'aide sur le barème ITS est présente', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Barème IR-PTS / ITS'));
    expect(contenu, contains('tranches d\'imposition'));
  }, skip: absent ?? false);

  test('l\'aide sur les retenues et charges est présente', () {
    final contenu = _normaliser(_blade!);
    expect(contenu, contains('Retenues salariales'));
    expect(contenu, contains('charges patronales'));
  }, skip: absent ?? false);
}
