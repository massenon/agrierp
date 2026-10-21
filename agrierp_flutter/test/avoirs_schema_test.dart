import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Tickets AV1 / AV2 — COHÉRENCE DE SCHÉMA LARAVEL ↔ DRIFT pour `credit_notes` (règle du monorepo : une table synchronisable
/// modifiée d'un côté l'est de l'autre).
///
/// ⚠️⚠️ **LU DANS LE CODE DES DEUX CÔTÉS, RIEN N'EST RECOPIÉ** : les colonnes que les migrations Laravel créent, les clés que
/// le tirage sert (`SyncController`, famille `credit_notes`), les clés que le poussoir valide (`pushCreditNotes`), et les
/// colonnes de la table Drift `CreditNotes`. Une colonne ajoutée au web sans son miroir au poste (ou l'inverse) fait rougir ce
/// fichier au lieu de se perdre au tirage, sans erreur.
void main() {
  final migrations = Directory('$dossierLaravel/database/migrations');
  final controleur = File('$dossierLaravel/app/Http/Controllers/Api/SyncController.php');
  final saut = migrations.existsSync() && controleur.existsSync()
      ? null
      : 'SAUT : dépôt Laravel absent ($dossierLaravel) — rien à comparer';

  /// Les colonnes de `credit_notes` d'après TOUTES les migrations qui la touchent, dans l'ordre des fichiers.
  Set<String> colonnesLaravel() {
    final colonnes = <String>{};
    final fichiers = migrations.listSync().whereType<File>().where((f) => f.path.endsWith('.php')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in fichiers) {
      final source = f.readAsStringSync();
      for (final m in RegExp(r"Schema::(create|table)\('credit_notes', function \(Blueprint \$table\) \{(.*?)\n        \}\);", dotAll: true)
          .allMatches(source)) {
        final corps = m.group(2)!;
        for (final c in RegExp(r"\$table->(\w+)\('([a-z_]+)'").allMatches(corps)) {
          if (c.group(1) == 'dropColumn') continue;
          colonnes.add(c.group(2)!);
        }
        if (corps.contains(r'$table->timestamps()')) colonnes.addAll(['created_at', 'updated_at']);
      }
    }
    return colonnes;
  }

  /// Les clés du JSON servi au tirage (`enJson` de la famille `credit_notes`).
  Set<String> clesDuTirage() {
    final source = controleur.readAsStringSync();
    final bloc = source.split("'cle' => 'credit_notes',")[1].split("'enJson'")[1].split('],')[0];
    return {for (final m in RegExp(r"'([a-z_]+)' =>").allMatches(bloc)) m.group(1)!};
  }

  /// Les clés que le poussoir valide (`pushCreditNotes`).
  Set<String> clesDeLEnvoi() {
    final source = controleur.readAsStringSync();
    final bloc = source.split('private function pushCreditNotes')[1].split("], MotifsRefusPush::messages()")[0];
    return {for (final m in RegExp(r"'([a-z_]+)' => \[").allMatches(bloc)) m.group(1)!};
  }

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Set<String> colonnesDrift() => {for (final c in db.creditNotes.$columns) c.name};

  test('⚠️⚠️ chaque colonne de `credit_notes` du web a son miroir Drift — sauf `accounting_entry_id`, écart assumé', () {
    final web = colonnesLaravel();
    expect(web, containsAll(['id', 'credit_note_number', 'sale_id', 'product_id', 'qty', 'amount', 'reason', 'decision', 'inspection_notes', 'status', 'created_at', 'updated_at', 'accounting_entry_id']));

    final poste = colonnesDrift();
    // ⚠️ ÉCART ASSUMÉ : l'écriture comptable d'un avoir est tenue par le serveur ; le poste ne la reçoit pas (voir la table Drift).
    const absentesAuPoste = {'accounting_entry_id'};
    expect(web.difference(poste).difference(absentesAuPoste), isEmpty, reason: 'colonne du web sans miroir au poste');
    // Les colonnes PROPRES au poste : l'origine de la saisie et le statut d'envoi (SyncColumns).
    expect(poste.difference(web), {'device_id', 'sync_status'});
  }, skip: saut);

  test('⚠️⚠️ ce que le tirage sert tient dans la table Drift (sinon une colonne se perdrait à l\'absorption)', () {
    final servies = clesDuTirage();
    expect(servies, containsAll(['id', 'credit_note_number', 'sale_id', 'product_id', 'qty', 'amount', 'reason', 'decision', 'inspection_notes', 'status', 'created_at']));
    expect(servies.difference(colonnesDrift()), isEmpty);
    // ⚠️ `accounting_entry_id` ne descend pas : le poste ne tient pas la comptabilité d'un avoir.
    expect(servies, isNot(contains('accounting_entry_id')));
    expect(servies, isNot(contains('credit_date')));
  }, skip: saut);

  test('⚠️⚠️ ce que le poste envoie est ce que le poussoir valide : aucune clé inconnue du serveur, aucune règle sans valeur', () {
    final moteur = File('lib/core/sync/sync_engine.dart').readAsStringSync();
    final bloc = moteur.split('Map<String, dynamic> _avoirEnJson(AvoirClient a) => {')[1].split('};')[0];
    final envoyees = {for (final m in RegExp(r"'([a-z_]+)':").allMatches(bloc)) m.group(1)!};
    final validees = clesDeLEnvoi();

    expect(envoyees, containsAll(['id', 'sale_id', 'product_id', 'qty', 'amount', 'reason', 'decision', 'status', 'credit_date']));
    // `device_id` est lu au niveau de la requête (jeton), pas validé par ligne ; `inspection_notes` est facultatif.
    expect(envoyees.difference(validees), {'device_id'}, reason: 'une clé envoyée que le serveur ne lit pas');
    expect(validees.difference(envoyees), isEmpty, reason: 'une règle du serveur que le poste ne renseigne jamais');
    // Jamais le numéro ni l'écriture : c'est le serveur qui les attribue.
    expect(envoyees, isNot(contains('credit_note_number')));
    expect(envoyees, isNot(contains('accounting_entry_id')));
  }, skip: saut);

  test('le droit d\'écriture et de lecture de la table : `manage-ventes` à l\'envoi, `view-ventes` au tirage', () {
    final source = controleur.readAsStringSync();
    expect(source, contains("'credit_notes' => 'manage-ventes',"));
    expect(source, contains("'credit_notes' => ['view-ventes'],"));
  }, skip: saut);

  test('la table est dans les listes du poste : envoyée, purgée à la réinitialisation, libellée', () {
    expect(AppDatabase.tablesEnvoyees, contains('credit_notes'));
    expect(AppDatabase.tablesDActivite, contains('credit_notes'));
    expect(SyncEngine_ordreDuServeur, contains('credit_notes'));
    // Après les ventes (un retour peut viser la vente du même envoi), avant les imputations.
    final i = SyncEngine_ordreDuServeur;
    expect(i.indexOf('credit_notes'), greaterThan(i.indexOf('sales')));
  });
}

/// L'ordre d'envoi du poste, lu dans `SyncEngine.ordreDuServeur`.
// ignore: non_constant_identifier_names
final List<String> SyncEngine_ordreDuServeur = () {
  final source = File('lib/core/sync/sync_engine.dart').readAsStringSync();
  final bloc = source.split('static const ordreDuServeur = [')[1].split('];')[0];
  return [for (final m in RegExp(r"'([a-z_]+)'").allMatches(bloc)) m.group(1)!];
}();
