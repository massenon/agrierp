import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket S-T7 (méthode TATACORA, piège « un seul écrivain par table ») — CHAQUE TABLE SYNCHRONISABLE DU POSTE N'EST
/// ÉCRITE QUE PAR SON DÉPÔT PROPRIÉTAIRE ET PAR LE MOTEUR DE SYNCHRONISATION.
///
/// Une table envoyée au serveur porte des invariants qu'un seul endroit doit tenir : remise en file (`pending`),
/// horodatage de la SAISIE, identifiant tiré une fois, cascade des effectifs. Un deuxième écrivain en oublie un sans
/// erreur : la ligne ne part pas, ou part avec un horodatage d'envoi qui écrase une saisie plus récente ailleurs.
///
/// ⚠️ CE TEST LIT LE CODE SOURCE DE `lib/`, comme les garde-fous de portage : un écrivain de trop est invisible à
/// l'exécution. Le relevé couvre les écritures Drift (`into(db.x)…`, `update(db.x)`, `delete(db.x)`, les lots
/// `b.insert(db.x, …)`, `insertAll`, `insertOnConflictUpdate`…) et le SQL brut (`INSERT INTO`, `UPDATE`, `DELETE FROM`).
///
/// 🔴 Relevé au premier passage (19/10/2026) et corrigé : la fiche journalière avait TROIS écrivains (son dépôt, la
/// caisse, les transferts) et les soins deux (`SoinsRepository`, `SoinsVaccinsRepository.archiverSoin`). Les écritures
/// ont été déplacées dans `FicheJournaliereRepository.repercuterVente` / `reporterTransferts` et
/// `SoinsRepository.archiverSoin`.
void main() {
  /// Le moteur : tirage (absorbeurs) et acquittement de l'envoi écrivent toutes les tables. Ticket S-T5 : la fusion
  /// par clé naturelle (`fusion_referentiels.dart`) fait partie de l'acquittement — elle remplace l'identifiant d'un
  /// client, fournisseur ou produit fusionné au serveur dans la fiche et dans toutes ses références.
  const moteur = {'lib/core/sync/sync_engine.dart', 'lib/core/sync/fusion_referentiels.dart'};

  /// Dépôt propriétaire de chaque table envoyée (`AppDatabase.tablesEnvoyees`).
  const proprietaires = <String, String>{
    'livestock_daily_entries': 'lib/features/elevage/fiche_journaliere_repository.dart',
    'sales': 'lib/features/ventes/caisse_repository.dart',
    'stock_adjustments': 'lib/features/stocks/stocks_repository.dart',
    'veterinary_records': 'lib/features/elevage/soins_repository.dart',
    'expenses': 'lib/features/achats/depenses_repository.dart',
    // Ticket DEV — « Devis & Proforma » : le devis se crée, avance et s'archive par ce dépôt.
    'quotes': 'lib/features/ventes/devis_repository.dart',
    'livestock_reproduction_events': 'lib/features/elevage/suivi_reproduction_repository.dart',
    'purchases': 'lib/features/achats/achats_repository.dart',
    'attendance_records': 'lib/features/rh/personnel_repository.dart',
    'products': 'lib/features/stocks/produits_repository.dart',
    'suppliers': 'lib/features/achats/fournisseurs_repository.dart',
    'supplier_payments': 'lib/features/achats/fournisseurs_repository.dart',
    'customers': 'lib/features/clients/clients_creances_repository.dart',
    'mails': 'lib/features/administration/administration_repository.dart',
    'archived_documents': 'lib/features/administration/administration_repository.dart',
    'administrative_documents': 'lib/features/administration/administration_repository.dart',
    'customer_advances': 'lib/features/clients/clients_creances_repository.dart',
    'advance_imputations': 'lib/features/clients/clients_creances_repository.dart',
    'purchase_returns': 'lib/features/achats/achats_repository.dart',
    'supplier_refunds': 'lib/features/achats/achats_repository.dart',
    'livestock_transfers': 'lib/features/elevage/transferts_repository.dart',
    // Tickets AV1 / AV2 — « Retours et Avoirs » : la demande de retour et « marquer comme traité » passent par ce dépôt.
    'credit_notes': 'lib/features/ventes/avoirs_repository.dart',
    // Ticket BS1 — « Bandes & Sujets » : la bande se crée, se modifie et s'archive par ce dépôt.
    'livestock_lots': 'lib/features/elevage/bandes_repository.dart',
    // Ticket BS3 — « Registre des Reproducteurs » : le sujet nominatif s'enregistre, se modifie et se sort par ce dépôt.
    'animals': 'lib/features/elevage/reproducteurs_repository.dart',
    'infirmary_records': 'lib/features/elevage/soins_vaccins_repository.dart',
    'veterinary_calendar_events': 'lib/features/elevage/soins_vaccins_repository.dart',
    'feed_ration_standards': 'lib/features/elevage/parametres_elevage_repository.dart',
    'prophylaxis_schedule_standards': 'lib/features/elevage/parametres_elevage_repository.dart',
    'feed_types': 'lib/features/elevage/parametres_elevage_repository.dart',
    'elevage_numbering_settings': 'lib/features/elevage/parametres_elevage_repository.dart',
    'company_settings': 'lib/features/elevage/parametres_elevage_repository.dart',
  };

  /// EXCEPTIONS LÉGITIMES, chacune justifiée. Clé : `table <- fichier`. Une exception devenue inutile fait échouer le
  /// test (elle ne doit pas rester ouverte pour le prochain écrivain de trop).
  ///
  /// `products.stock_qty` est un MIROIR LOCAL du grand livre : au serveur, `AdjustStockAction` est le seul point de
  /// passage et le stock n'est jamais envoyé comme tel (le serveur ne lit `stock_qty` qu'à la CRÉATION d'un produit,
  /// `_produitEnJson`). La vente, l'inventaire et la ponte en répercutent l'effet au poste en écrivant `stock_qty`
  /// SEUL, sans remettre le produit en file : le test l'exige ([colonnesPermises]). Les réunir derrière un point unique
  /// côté poste est souhaitable, mais touche `lib/features/stocks/` (ticket U10 en cours) : ticket à part.
  const exceptions = <String, String>{
    'products <- lib/features/ventes/caisse_repository.dart':
        'vente : décrément de stock_qty ligne par ligne (F0.90), comme AdjustStockAction au serveur',
    'products <- lib/features/stocks/stocks_repository.dart':
        'écart d\'inventaire : stock_qty ramené au stock physique, l\'ajustement part dans stock_adjustments',
    'products <- lib/features/elevage/production_oeufs_service.dart':
        'ponte : entrée des plateaux nets au stock d\'œufs à la création de la fiche, comme au serveur',
    'livestock_lots <- lib/features/elevage/fiche_journaliere_repository.dart':
        'cascade unique : la bande suit la DERNIÈRE fiche (current_quantity DÉRIVÉ, jamais remis en file : le serveur le recalcule par la même cascade)',
    'livestock_lots <- lib/features/elevage/transferts_repository.dart':
        'constitution : lot_source_id DÉRIVÉ du transfert (le serveur le pose lui-même en rejouant le transfert), jamais remis en file',
    'products <- lib/core/database/app_database.dart':
        'purge après réinitialisation du serveur (15.50) : stock_qty remis à zéro, comme au serveur',
  };

  /// Seules colonnes qu'une exception peut écrire, par table : `products.stock_qty` (miroir du grand livre) ; ticket BS1,
  /// `livestock_lots.current_quantity` (la bande suit sa dernière fiche, cascade unique) et `lot_source_id` (dérivé du
  /// transfert de constitution) — DÉRIVÉES, que le serveur recalcule : elles ne remettent JAMAIS la bande en file.
  const colonnesPermises = <String, Set<String>>{
    'products': {'stockQty', 'stock_qty'},
    'livestock_lots': {'currentQuantity', 'current_quantity', 'lotSourceId', 'lot_source_id'},
  };

  String sqlDe(String getter) =>
      getter.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  /// Commentaires retirés (`//` en début de ligne ou après un blanc : une URL `http://` dans une chaîne reste).
  String sansCommentaires(String source) =>
      source.replaceAll(RegExp(r'(^|\s)//[^\n]*', multiLine: true), r'$1');

  /// Blancs retirés autour de la ponctuation (une instruction formatée sur plusieurs lignes devient une seule), mais
  /// gardés entre deux mots : `await into(sales)` ne doit pas devenir `awaitinto(sales)`.
  String compacter(String source) => source
      .replaceAllMapped(RegExp(r'\s*([^\w\s])\s*'), (m) => m[1]!)
      .replaceAll(RegExp(r'\s+'), ' ');

  /// Écritures relevées : (table SQL, fichier, extrait de l'instruction).
  List<(String, String, String)> releve() {
    final ecritures = <(String, String, String)>[];
    final fichiers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));

    final drift = RegExp(r'(?<![\w.])(?:\w+\.)?(?:into|update|delete)\((?:\w+\.)?(\w+),?\)');
    final lot = RegExp(
      r'\.(?:insert|insertAll|insertAllOnConflictUpdate|insertOnConflictUpdate|replace|replaceAll|update|delete|'
      r'deleteWhere|deleteAll)\((?:\w+\.)?(\w+),',
    );
    final sql = RegExp(r'(?:INSERT\s+(?:OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+(\w+)');

    for (final f in fichiers) {
      final chemin = f.path.replaceAll(r'\', '/');
      final source = sansCommentaires(f.readAsStringSync());
      final compact = compacter(source);
      String extrait(int debut) {
        final fin = compact.indexOf(';', debut);
        return compact.substring(debut, fin < 0 ? compact.length : fin);
      }

      for (final m in drift.allMatches(compact)) {
        ecritures.add((sqlDe(m[1]!), chemin, extrait(m.start)));
      }
      for (final m in lot.allMatches(compact)) {
        ecritures.add((sqlDe(m[1]!), chemin, extrait(m.start)));
      }
      for (final m in sql.allMatches(source)) {
        final fin = source.indexOf(';', m.start);
        ecritures.add((m[1]!, chemin, source.substring(m.start, fin < 0 ? source.length : fin)));
      }
    }
    return ecritures;
  }

  test('les tables synchronisables (`SyncColumns`) sont toutes dans la liste des tables envoyées, avec un propriétaire', () {
    final source = File('lib/core/database/app_database.dart').readAsStringSync();
    final avecColonnes = RegExp(r'class (\w+) extends Table with SyncColumns')
        .allMatches(source)
        .map((m) => sqlDe(m[1]![0].toLowerCase() + m[1]!.substring(1)))
        .toSet();

    expect(avecColonnes, isNotEmpty);
    expect(AppDatabase.tablesEnvoyees.toSet().containsAll(avecColonnes), isTrue,
        reason: 'table SyncColumns non envoyée : ${avecColonnes.difference(AppDatabase.tablesEnvoyees.toSet())}');
    expect(proprietaires.keys.toSet(), AppDatabase.tablesEnvoyees.toSet(),
        reason: 'chaque table envoyée doit avoir son dépôt propriétaire déclaré ici');
    for (final f in proprietaires.values) {
      expect(File(f).existsSync(), isTrue, reason: 'dépôt propriétaire introuvable : $f');
    }
  });

  test('⚠️⚠️ chaque table envoyée n\'est écrite que par son dépôt propriétaire et par le moteur', () {
    final ecritures = releve();
    // Le relevé voit bien les écritures : sinon le test passerait sur un relevé vide.
    expect(
      ecritures.where((e) => e.$1 == 'sales' && e.$2 == proprietaires['sales']),
      isNotEmpty,
    );

    final parasites = <String>{};
    final exceptionsVues = <String>{};
    for (final (table, fichier, extrait) in ecritures) {
      final proprietaire = proprietaires[table];
      if (proprietaire == null) continue; // table non envoyée : hors du périmètre
      if (fichier == proprietaire || moteur.contains(fichier)) continue;

      final cle = '$table <- $fichier';
      if (exceptions.containsKey(cle)) {
        exceptionsVues.add(cle);
        // Une exception sur `products` n'écrit QUE le stock, et ne remet pas le produit en file.
        final hors = RegExp(r'(\w+):').allMatches(extrait.split('Companion').skip(1).join()).map((m) => m[1]!).toSet()
          ..removeAll(colonnesPermises[table] ?? const <String>{});
        // SQL brut : `SET stock_qty = 0` et rien d'autre (aucune seconde colonne après une virgule).
        final sqlHors = extrait.contains('SET') && !RegExp(r'SET\s+stock_qty\s*=\s*0(?![\w,])').hasMatch(extrait);
        if (hors.isNotEmpty || sqlHors || extrait.contains('syncStatus') || extrait.contains('sync_status')) {
          parasites.add('$cle écrit au-delà de ses colonnes dérivées : $extrait');
        }
        continue;
      }
      parasites.add('$cle ($extrait)');
    }

    expect(parasites, isEmpty, reason: 'écrivain(s) de trop — passer par le dépôt propriétaire, ou justifier une exception');
    expect(exceptionsVues, exceptions.keys.toSet(), reason: 'exception devenue inutile : à retirer');
  });

  test('le relevé reconnaît chaque forme d\'écriture (contrôle du garde-fou lui-même)', () {
    final dossier = Directory.systemTemp.createTempSync('ecrivain_unique');
    addTearDown(() => dossier.deleteSync(recursive: true));
    // Rejoue l'expression du relevé sur des formes connues, hors de `lib/`.
    final drift = RegExp(r'(?<![\w.])(?:\w+\.)?(?:into|update|delete)\((?:\w+\.)?(\w+),?\)');
    final lot = RegExp(
      r'\.(?:insert|insertAll|insertAllOnConflictUpdate|insertOnConflictUpdate|replace|replaceAll|update|delete|'
      r'deleteWhere|deleteAll)\((?:\w+\.)?(\w+),',
    );
    String compacte(String s) => compacter(s);

    for (final forme in [
      'await _db.into(_db.sales).insert(x);',
      'await (database.update(\n  database.sales,\n)..where((t) => t.id.equals(id))).write(c);',
      'await (db.delete(db.sales)..where((t) => t.id.equals(id))).go();',
      'await into(sales).insert(x);',
      'await _db.into(_db.sales).insertOnConflictUpdate(x);',
    ]) {
      expect(drift.firstMatch(compacte(forme))?[1], 'sales', reason: forme);
    }
    for (final forme in [
      '_db.batch((b) => b.insertAll(_db.sales, lignes));',
      'batch.update(db.sales, c, where: (t) => t.id.isIn(ids));',
      'b.insertOnConflictUpdate(_db.sales, c);',
    ]) {
      expect(lot.firstMatch(compacte(forme))?[1], 'sales', reason: forme);
    }
    expect(drift.firstMatch(compacte('_deplies.remove(table); map.update(k, f);')), isNull);
  });
}
