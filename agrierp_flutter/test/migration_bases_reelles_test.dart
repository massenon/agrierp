import 'dart:io';

import 'package:agrierp/core/config/parametres_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// sqlite3 est la dépendance directe de Drift : le test écrit des bases d'anciennes formes en SQL brut.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as raw;

/// 🔴 « Le logiciel ne s'ouvre pas » — poste où AgriERP avait DÉJÀ été installé puis désinstallé (la base reste dans le profil
/// Windows) : le processus restait en arrière-plan, sans fenêtre, parce que la migration de la VRAIE base échouait avant
/// `runApp`. Un poste neuf, lui, s'ouvrait.
///
/// `migration_toutes_versions_test.dart` part d'une base NEUVE dont on retire des colonnes : il ne voit donc ni une table
/// d'une autre FORME (`expenses` d'avant le palier 59 : trésorerie obligatoire, sans `on_credit` ni `receipt_local_path`,
/// que le palier 59 RECONSTRUIT en recopiant les colonnes du schéma courant), ni une base dont le numéro de version dépasse
/// ce qu'elle contient (paliers 57 à 59 numérotés sur des branches parallèles : `user_version` 60 sans la Corbeille).
/// Ici, ces deux formes sont REPRODUITES à partir de vraies bases produites par d'anciennes versions du code.

/// `CREATE TABLE expenses` TEL QUE LE PALIER 56 L'A POSÉ (relu d'une vraie base de l'époque).
const _depensesV56 =
    'CREATE TABLE "expenses" ("id" TEXT NOT NULL, "device_id" TEXT NOT NULL, "sync_status" TEXT NOT NULL DEFAULT \'pending\', '
    '"updated_at" INTEGER NOT NULL, "expense_date" INTEGER NOT NULL, "label" TEXT NOT NULL, "category" TEXT NOT NULL, '
    '"amount" REAL NOT NULL, "treasury_account_id" TEXT NOT NULL, "is_active" INTEGER NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)), '
    '"status" TEXT NOT NULL DEFAULT \'payee\', "accounting_entry_id" TEXT NULL, "payment_mode" TEXT NULL, "cost_center_id" TEXT NULL, '
    '"supplier_id" TEXT NULL, "beneficiary" TEXT NULL, "created_by" TEXT NULL, "ecriture_refus" TEXT NULL, PRIMARY KEY ("id"))';

void main() {
  late File fichier;

  setUp(() {
    fichier = File('${Directory.systemTemp.createTempSync('migration_reelle').path}/agrierp.sqlite');
  });
  tearDown(() => fichier.parent.deleteSync(recursive: true));

  /// Base au schéma COURANT, puis ramenée à la forme voulue par [deformer] et à `user_version` [version].
  Future<void> baseAncienne(int version, void Function(raw.Database) deformer) async {
    final neuve = AppDatabase.forTesting(NativeDatabase(fichier));
    await neuve.customSelect('select 1').get();
    await neuve.close();

    final brut = raw.sqlite3.open(fichier.path);
    deformer(brut);
    brut.execute('PRAGMA user_version = $version');
    brut.close();
  }

  void ancienneDepense(raw.Database b) {
    b.execute('DROP TABLE expenses');
    b.execute(_depensesV56);
    b.execute(
      "INSERT INTO expenses (id, device_id, updated_at, expense_date, label, category, amount, treasury_account_id) "
      "VALUES ('d1', 'poste-1', 1700000000, 1700000000, 'Carburant', '605', 12500.0, 't1')",
    );
  }

  Future<AppDatabase> ouvrir() async {
    final db = AppDatabase.forTesting(NativeDatabase(fichier));
    // Ce que fait `main()` avant `runApp` : la première lecture déclenche la migration.
    await ParametresPoste(database: db).identifiant();
    return db;
  }

  Future<Map<String, int>> colonnes(AppDatabase db, String table) async => {
    for (final c in await db.customSelect('PRAGMA table_info("$table")').get())
      c.read<String>('name'): c.read<int>('notnull'),
  };

  test('⚠️ une dépense d\'avant le palier 59 est reconstruite SANS perdre la ligne, même avec les colonnes des paliers suivants', () async {
    await baseAncienne(58, ancienneDepense);

    final db = await ouvrir();
    final c = await colonnes(db, 'expenses');

    expect(c.keys, containsAll(['on_credit', 'receipt_local_path']));
    expect(c['treasury_account_id'], 0, reason: 'trésorerie facultative depuis le palier 59 (dépense à crédit)');
    final lignes = await db.customSelect("SELECT label, amount FROM expenses WHERE id = 'd1'").get();
    expect(lignes.single.read<String>('label'), 'Carburant');
    expect(lignes.single.read<double>('amount'), 12500.0);
    await db.close();
  });

  test('⚠️ une base en version 60 SANS les paliers 57 à 59 (autre chaîne) reçoit sa Corbeille et ses colonnes', () async {
    await baseAncienne(60, (b) {
      ancienneDepense(b);
      b.execute('DROP TABLE corbeille_elements');
      b.execute('DROP TABLE corbeille_demandes');
      b.execute('ALTER TABLE quotes DROP COLUMN converted_sale_id');
      b.execute('ALTER TABLE quotes DROP COLUMN invoice_number');
    });

    final db = await ouvrir();

    expect((await colonnes(db, 'corbeille_elements')).keys, contains('archive_par'));
    expect(await colonnes(db, 'corbeille_demandes'), isNotEmpty);
    expect((await colonnes(db, 'quotes')).keys, containsAll(['converted_sale_id', 'invoice_number']));
    expect((await colonnes(db, 'expenses'))['treasury_account_id'], 0);
    expect((await colonnes(db, 'expenses')).keys, containsAll(['on_credit', 'receipt_local_path']));
    await db.close();
  });

  test('une base déjà à jour s\'ouvre sans rien changer', () async {
    await baseAncienne(66, (_) {});

    final db = await ouvrir();

    expect((await colonnes(db, 'expenses'))['treasury_account_id'], 0);
    await db.close();
  });
}
