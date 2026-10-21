import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/core/config/domaine_email.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket MAIL1 (décision du client, 21/10/2026) — PALIER v50 : les anciennes adresses `@olouwachegoun.bj` déjà
/// enregistrées au poste deviennent `@fermeolouwachegoun.com`.
///
/// Méthode : une base neuve est peuplée à l'ANCIEN domaine, refermée, ramenée à `user_version = 49`, puis rouverte —
/// la vraie migration s'exécute. Les valeurs attendues sont des littéraux écrits à la main.
///
/// ⚠️ Les tests qui comptent le plus sont ceux de ce qui NE doit PAS bouger : `sync_status`, `updated_at`, les autres
/// colonnes, les adresses d'un autre domaine, le nom de serveur sans « @ ».
void main() {
  late Directory dossier;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dossier = Directory.systemTemp.createTempSync('agrierp_mail1_');
  });
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    try {
      dossier.deleteSync(recursive: true);
    } catch (_) {}
  });

  final instant = DateTime(2026, 9, 1, 8);

  /// Peuple une base au schéma courant, la referme, la ramène au palier [version] et la rouvre.
  Future<AppDatabase> baseAuPalier(
    String nom,
    Future<void> Function(AppDatabase) peupler, {
    int version = 49,
  }) async {
    final fichier = File('${dossier.path}${Platform.pathSeparator}$nom.db');
    final avant = AppDatabase.forTesting(NativeDatabase(fichier));
    await peupler(avant);
    await avant.close();
    return AppDatabase.forTesting(
      NativeDatabase(fichier, setup: (raw) => raw.execute('PRAGMA user_version = $version')),
    );
  }

  Future<void> peuplement(AppDatabase d) async {
    await d.into(d.customers).insert(CustomersCompanion.insert(
          id: '00000000-0000-0000-0000-000000000001',
          name: 'Mama',
          phone: const Value('0100000001'),
          email: const Value('Mama@OLOUWACHEGOUN.BJ'),
          syncStatus: const Value(SyncStatus.pending),
        ));
    await d.into(d.customers).insert(CustomersCompanion.insert(
          id: '00000000-0000-0000-0000-000000000002',
          name: 'Autre domaine',
          email: const Value('resto@restaurant.bj'),
        ));
    await d.into(d.customers).insert(CustomersCompanion.insert(
          id: '00000000-0000-0000-0000-000000000003',
          name: 'Sans e-mail',
        ));
    await d.into(d.suppliers).insert(SuppliersCompanion.insert(
          id: '00000000-0000-0000-0000-000000000011',
          name: 'Provenderie',
          email: const Value('achats@olouwachegoun.bj'),
          syncStatus: const Value(SyncStatus.pending),
        ));
    await d.into(d.companySettings).insert(CompanySettingsCompanion.insert(
          id: const Value('unique'),
          email: const Value('contact@olouwachegoun.bj'),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(instant),
          rappelSoinsJours: const Value(7),
        ));
    await d.into(d.utilisateurs).insert(UtilisateursCompanion.insert(
          id: '00000000-0000-0000-0000-000000000021',
          name: 'Comptable',
          username: const Value('compta'),
          email: const Value('compta@olouwachegoun.bj'),
          role: const Value('comptable'),
        ));
    await d.into(d.notifications).insert(NotificationsCompanion.insert(
          id: '00000000-0000-0000-0000-000000000031',
          type: 'system',
          title: 'Bienvenue',
          message: 'Écrivez à contact@olouwachegoun.bj ou à dg@OLOUWACHEGOUN.bj.',
        ));
    for (final (cle, valeur) in [
      ('smtp.hote', 'smtp.olouwachegoun.bj'),
      ('smtp.utilisateur', 'notifications@olouwachegoun.bj'),
      ('smtp.expediteur', 'envoi@Olouwachegoun.BJ'),
      ('smtp.securite', 'tls'),
      ('poste.identifiant', 'caisse-1'),
    ]) {
      await d.into(d.appSettings).insert(AppSettingsCompanion.insert(key: cle, value: valeur));
    }
  }

  test('⚠️ une base v49 peuplée à l’ancien domaine passe au nouveau, sans rien toucher d’autre', () async {
    final db = await baseAuPalier('v49', peuplement);
    addTearDown(db.close);

    final client = await (db.select(db.customers)..where((t) => t.id.like('%0001'))).getSingle();
    expect(client.email, 'Mama@fermeolouwachegoun.com');
    // La ligne reste ce qu'elle était : toujours `pending`, mêmes autres colonnes.
    expect(client.syncStatus, SyncStatus.pending);
    expect(client.name, 'Mama');
    expect(client.phone, '0100000001');

    final autre = await (db.select(db.customers)..where((t) => t.id.like('%0002'))).getSingle();
    expect(autre.email, 'resto@restaurant.bj');
    final sans = await (db.select(db.customers)..where((t) => t.id.like('%0003'))).getSingle();
    expect(sans.email, isNull);

    final fournisseur = await db.select(db.suppliers).getSingle();
    expect(fournisseur.email, 'achats@fermeolouwachegoun.com');
    expect(fournisseur.syncStatus, SyncStatus.pending);

    final ferme = await db.select(db.companySettings).getSingle();
    expect(ferme.email, 'contact@fermeolouwachegoun.com');
    expect(ferme.syncStatus, SyncStatus.pending);
    expect(ferme.updatedAt, instant);
    expect(ferme.rappelSoinsJours, 7);

    final utilisateur = await db.select(db.utilisateurs).getSingle();
    expect(utilisateur.email, 'compta@fermeolouwachegoun.com');
    expect(utilisateur.username, 'compta');
    expect(utilisateur.role, 'comptable');

    final notification = await db.select(db.notifications).getSingle();
    expect(notification.message, 'Écrivez à contact@fermeolouwachegoun.com ou à dg@fermeolouwachegoun.com.');
    expect(notification.title, 'Bienvenue');
  });

  test('⚠️ les réglages de app_settings : adresses converties, nom de serveur et autres clés intacts', () async {
    final db = await baseAuPalier('v49_reglages', peuplement);
    addTearDown(db.close);

    final reglages = {for (final l in await db.select(db.appSettings).get()) l.key: l.value};
    expect(reglages, {
      // Un nom de serveur n'est pas une adresse (pas de « @ ») : intact.
      'smtp.hote': 'smtp.olouwachegoun.bj',
      'smtp.utilisateur': 'notifications@fermeolouwachegoun.com',
      'smtp.expediteur': 'envoi@fermeolouwachegoun.com',
      'smtp.securite': 'tls',
      'poste.identifiant': 'caisse-1',
    });
  });

  test('la migration est sans effet une seconde fois et ne touche pas une base déjà au palier courant', () async {
    final db = await baseAuPalier('v49_deux_fois', peuplement);
    await db.select(db.customers).get(); // La migration s'exécute à la première requête.
    await db.close();
    // Le fichier est rouvert au même palier que celui qu'il vient d'atteindre : aucun palier ne rejoue.
    final fichier = File('${dossier.path}${Platform.pathSeparator}v49_deux_fois.db');
    final encore = AppDatabase.forTesting(NativeDatabase(fichier));
    addTearDown(encore.close);
    expect((await encore.select(encore.customers).get()).map((c) => c.email).whereType<String>().toSet(), {
      'Mama@fermeolouwachegoun.com',
      'resto@restaurant.bj',
    });

    // Une adresse à l'ancien domaine saisie APRÈS la migration (palier courant) n'est pas reprise.
    await encore.into(encore.customers).insert(CustomersCompanion.insert(
          id: '00000000-0000-0000-0000-000000000009',
          name: 'Tardif',
          email: const Value('tard@olouwachegoun.bj'),
        ));
    await encore.close();
    final troisieme = AppDatabase.forTesting(NativeDatabase(fichier));
    addTearDown(troisieme.close);
    final tardif = await (troisieme.select(troisieme.customers)..where((t) => t.id.like('%0009'))).getSingle();
    expect(tardif.email, 'tard@olouwachegoun.bj');
  });

  test('une valeur qui porte l’adresse deux fois est entièrement convertie', () async {
    final db = await baseAuPalier('v49_double', (d) async {
      await d.into(d.notifications).insert(NotificationsCompanion.insert(
            id: '00000000-0000-0000-0000-000000000041',
            type: 'system',
            title: 'a@olouwachegoun.bj',
            message: 'a@olouwachegoun.bj, b@olouwachegoun.bj et c@olouwachegoun.bjx',
          ));
    });
    addTearDown(db.close);

    final n = await db.select(db.notifications).getSingle();
    expect(n.title, 'a@fermeolouwachegoun.com');
    // « .bjx » n'est pas notre domaine : la 3e adresse reste, les deux premières changent.
    expect(n.message, 'a@fermeolouwachegoun.com, b@fermeolouwachegoun.com et c@olouwachegoun.bjx');
  });

  test('la session mise en cache au coffre est convertie à la lecture', () {
    final j = jsonDecode(
      '{"id":"u1","name":"M. Olouchègoun","username":"admin","email":"DG@Olouwachegoun.bj","role":"admin","role_label":"Administrateur"}',
    ) as Map<String, dynamic>;
    final session = SessionUtilisateur.depuisJson(j);
    expect(session.email, 'DG@fermeolouwachegoun.com');
    expect(session.identifiant, 'admin');
    expect(convertirDomaineEmail('smtp.olouwachegoun.bj'), 'smtp.olouwachegoun.bj');
    expect(convertirDomaineEmail('x@gmail.com'), 'x@gmail.com');
  });
}
