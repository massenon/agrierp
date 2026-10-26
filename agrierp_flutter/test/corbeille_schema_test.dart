import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket ARC3 — COHÉRENCE SERVEUR ↔ DRIFT de la Corbeille, et palier de schéma 58.
///
/// ⚠️ LU DANS LE CODE DES DEUX CÔTÉS : les clés de l'instantané `corbeille` servies par `SyncController` doivent toutes avoir
/// leur colonne dans `corbeille_elements` ; les clés de la demande que `pushCorbeilleDemandes` valide doivent toutes être
/// envoyées par le poste.
void main() {
  final controleur = File('$dossierLaravel/app/Http/Controllers/Api/SyncController.php');
  final saut = controleur.existsSync() ? null : 'SAUT : dépôt Laravel absent ($dossierLaravel)';

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('⚠️ le palier 58 crée les deux tables ; 57, 59 et 60 sont réservés à d\'autres branches', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(58));
    final source = File('lib/core/database/app_database.dart').readAsStringSync();
    expect(source, contains('if (from < 58) {'));
    expect(source, isNot(contains('if (from < 57) {')));
    expect({for (final c in db.corbeilleElements.$columns) c.name}, {
      'id', 'type', 'element_id', 'titre', 'detail', 'module', 'archive_le', 'restaurable', 'motif_restauration', 'supprimable', 'motif_suppression',
    });
    expect({for (final c in db.corbeilleDemandes.$columns) c.name}, {
      'id', 'device_id', 'sync_status', 'updated_at', 'type', 'element_id', 'action', 'titre', 'confirmation',
    });
  });

  test('⚠️⚠️ ce que le tirage sert tient dans `corbeille_elements`', () {
    final bloc = controleur.readAsStringSync().split("'corbeille' => fn () =>")[1].split('])->values()')[0];
    final servies = {for (final m in RegExp(r"'([a-z_]+)' =>").allMatches(bloc)) m.group(1)!};
    expect(servies, containsAll(['id', 'type', 'element_id', 'titre', 'detail', 'module', 'archive_le', 'restaurable', 'motif_restauration', 'supprimable', 'motif_suppression']));
    expect(servies.difference({for (final c in db.corbeilleElements.$columns) c.name}), isEmpty);
  }, skip: saut);

  test('⚠️ ce que le poussoir valide est ce que le poste envoie', () {
    final bloc = controleur.readAsStringSync().split('private function pushCorbeilleDemandes')[1].split('], MotifsRefusPush::messages()')[0];
    final validees = {for (final m in RegExp(r"'([a-z_]+)' => \[").allMatches(bloc)) m.group(1)!};
    expect(validees, {'id', 'type', 'element_id', 'action', 'confirmation'});
    final moteur = File('lib/core/sync/sync_engine.dart').readAsStringSync();
    final envoi = moteur.split('_demandeCorbeilleEnJson(DemandeCorbeille d) => {')[1].split('};')[0];
    for (final cle in validees) {
      expect(envoi, contains("'$cle':"), reason: cle);
    }
    // Sans droit, le serveur refuse l'écriture de la table : la même permission que l'instantané.
    final php = controleur.readAsStringSync();
    expect(php, contains("'corbeille_demandes' => 'manage-parametres'"));
    expect(php, contains("'corbeille' => ['manage-parametres']"));
  }, skip: saut);

  test('les deux tables sont classées : demandes envoyées, les deux purgées à la réinitialisation', () {
    expect(AppDatabase.tablesEnvoyees, contains('corbeille_demandes'));
    expect(AppDatabase.tablesDActivite, containsAll(['corbeille_elements', 'corbeille_demandes']));
    expect(AppDatabase.tablesEnvoyees, isNot(contains('corbeille_elements')), reason: 'lecture seule');
  });
}
