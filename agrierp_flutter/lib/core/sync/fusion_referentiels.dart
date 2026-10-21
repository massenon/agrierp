import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Ticket S-T5 (méthode TATACORA) — LE POSTE APPREND L'IDENTIFIANT DU SERVEUR.
///
/// Un client, un fournisseur ou un produit créé sur ce poste alors que le serveur avait déjà la même fiche (même clé
/// naturelle, règle unique du serveur : `FusionReferentielsService`) n'y a pas été créé une seconde fois : l'envoi
/// l'acquitte (`accepted`) ET le signale dans `merged` — `{id: <id du poste>, id_serveur: <id existant>}`.
///
/// À réception, le poste remplace PARTOUT son identifiant par celui du serveur, dans UNE transaction :
///  1. la fiche : copiée sous l'identifiant du serveur (`synced`, le tirage suivant y écrit la version du serveur) si
///     le poste ne l'a pas encore, puis la ligne du poste est retirée — jamais deux fiches pour un même client ;
///  2. toutes les références locales ([references]) : ventes, créances, avances, relances, achats, dettes, bons de
///     commande, règlements, remboursements, lignes de vente et d'achat, ajustements et mouvements de stock, bandes,
///     revenus par bande, fiches journalières. Une saisie en attente (`pending`) le RESTE et part avec le bon
///     identifiant (le serveur sait de toute façon traduire l'ancien) ; son état et son instant de saisie ne changent
///     pas ;
///  3. un refus encore ouvert sur l'identifiant du poste (`sync_conflicts`) est retiré.
///
/// ⚠️ Idempotent : un renvoi du même `merged` (accusé rejoué, lot répété) ne trouve plus rien sous l'identifiant du
/// poste et ne change rien.
///
/// ⚠️ Un garde-fou (`test/fusion_referentiels_test.dart`) vérifie, sur le schéma Drift lui-même, que CHAQUE colonne
/// `customer_id`, `supplier_id` et `…product_id` est dans [references] : une table ajoutée plus tard sans y figurer
/// garderait un identifiant qui n'existe plus au poste.
///
/// Écrivain légitime de ces tables au même titre que le moteur de synchronisation (`ecrivain_unique_test.dart`) :
/// c'est l'acquittement de l'envoi.
class FusionReferentiels {
  FusionReferentiels(this._db);

  final AppDatabase _db;

  /// Référentiels fusionnables, sous le nom de table de l'envoi (et du schéma).
  static const tables = ['customers', 'suppliers', 'products'];

  /// ⚠️⚠️ TOUTES les références locales vers chaque référentiel : (table, colonne) du schéma Drift.
  static const references = <String, List<(String, String)>>{
    'customers': [
      ('sales', 'customer_id'),
      ('receivables', 'customer_id'),
      ('customer_advances', 'customer_id'),
      ('customer_reminders', 'customer_id'),
      // Ticket DEV — le client d'un devis du poste.
      ('quotes', 'customer_id'),
    ],
    'suppliers': [
      ('purchases', 'supplier_id'),
      ('payables', 'supplier_id'),
      ('purchase_orders', 'supplier_id'),
      ('supplier_payments', 'supplier_id'),
      ('supplier_refunds', 'supplier_id'),
      ('supplier_credits', 'supplier_id'),
      // Ticket DEP4 — le fournisseur (facultatif) d'une dépense.
      ('expenses', 'supplier_id'),
    ],
    'products': [
      ('sale_lines', 'product_id'),
      ('purchase_lines', 'product_id'),
      ('stock_adjustments', 'product_id'),
      ('stock_movements', 'product_id'),
      ('livestock_lots', 'product_id'),
      ('lot_revenues', 'product_id'),
      // Tickets AV1 / AV2 — un avoir en attente désigne son produit.
      ('credit_notes', 'product_id'),
      ('livestock_daily_entries', 'treatment_product_id'),
    ],
  };

  /// Miroirs du serveur dont la référence fait partie de la CLÉ PRIMAIRE (`supplier_credits` : le fournisseur ;
  /// `lot_revenues` : bande + produit). Une ligne déjà présente sous l'identifiant du serveur fait foi ; celle du poste,
  /// qui la doublerait, est retirée (le tirage suivant resservira les chiffres du serveur).
  static const miroirsACle = {'supplier_credits', 'lot_revenues'};

  /// Les fusions d'une réponse d'envoi pour [table] : `merged` = liste de `{id, id_serveur}`. Une entrée illisible est
  /// ignorée (le serveur reste capable de traduire l'ancien identifiant).
  static List<(String, String)> fusionsDe(Object? resultat) {
    if (resultat is! Map) return const [];
    final brut = resultat['merged'];
    if (brut is! List) return const [];
    return [
      for (final m in brut)
        if (m is Map &&
            m['id'] is String &&
            m['id_serveur'] is String &&
            (m['id'] as String).isNotEmpty &&
            (m['id_serveur'] as String).isNotEmpty)
          (m['id'] as String, m['id_serveur'] as String),
    ];
  }

  /// Applique toutes les fusions de la réponse (fusionnée) d'un envoi, dans UNE transaction. Rend leur nombre.
  Future<int> appliquerReponse(Map<String, dynamic> corps) async {
    final aFaire = [
      for (final table in tables)
        for (final (idPoste, idServeur) in fusionsDe(corps[table]))
          (table, idPoste, idServeur),
    ];
    final fiches = fusionsDe(corps['livestock_daily_entries']);
    if (aFaire.isEmpty && fiches.isEmpty) return 0;

    await _db.transaction(() async {
      for (final (table, idPoste, idServeur) in aFaire) {
        await appliquer(table, idPoste, idServeur);
      }
      for (final (idPoste, idServeur) in fiches) {
        await appliquerFiche(idPoste, idServeur);
      }
    });
    return aFaire.length + fiches.length;
  }

  /// Ticket S-T9 — FICHE DU JOUR FUSIONNÉE : le serveur tenait déjà une fiche pour la même (bande, jour), sous un
  /// autre identifiant (créée par la vente d'un autre poste, ou par son animalier), et y a réuni celle du poste. La
  /// fiche locale prend l'identifiant du serveur, SUR PLACE : `UNIQUE (lot_id, entry_date)` interdit d'en avoir deux le
  /// temps d'une copie, et aucune table du poste ne référence une fiche. Son statut ne change pas (l'acquittement
  /// vient de le poser) ; le tirage suivant y écrit la version du serveur, datée par la fusion. Un refus encore ouvert
  /// sous l'ancien identifiant est retiré. Idempotent : un second passage ne trouve plus l'identifiant du poste.
  Future<void> appliquerFiche(String idPoste, String idServeur) async {
    if (idPoste == idServeur) return;
    final info = _table('livestock_daily_entries');
    final serveurPresent = (await _db
            .customSelect(
              'SELECT 1 FROM livestock_daily_entries WHERE id = ?',
              variables: [Variable.withString(idServeur)],
            )
            .get())
        .isNotEmpty;
    await _db.customUpdate(
      serveurPresent
          ? 'DELETE FROM livestock_daily_entries WHERE id = ?'
          : 'UPDATE livestock_daily_entries SET id = ? WHERE id = ?',
      variables: [
        if (!serveurPresent) Variable.withString(idServeur),
        Variable.withString(idPoste),
      ],
      updates: {info},
      updateKind: serveurPresent ? UpdateKind.delete : UpdateKind.update,
    );
    await (_db.delete(_db.syncConflicts)..where(
          (c) => Expression.and([
            c.sourceTable.equals('livestock_daily_entries'),
            c.recordId.equals(idPoste),
          ]),
        ))
        .go();
  }

  /// Remplace partout [idPoste] par [idServeur] pour le référentiel [table], dans une transaction.
  Future<void> appliquer(String table, String idPoste, String idServeur) {
    final cibles = references[table];
    if (cibles == null) {
      throw ArgumentError.value(table, 'table', 'référentiel non fusionnable');
    }
    if (idPoste == idServeur) return Future.value();

    return _db.transaction(() async {
      final info = _table(table);

      Future<bool> existe(String id) async =>
          (await _db
                  .customSelect(
                    'SELECT 1 FROM $table WHERE id = ?',
                    variables: [Variable.withString(id)],
                  )
                  .get())
              .isNotEmpty;

      // 1. La fiche : sous l'identifiant du serveur, une seule.
      if (await existe(idPoste)) {
        if (!await existe(idServeur)) {
          final colonnes = [for (final c in info.$columns) c.name];
          final valeurs = [
            for (final c in colonnes)
              c == 'id'
                  ? '?'
                  : c == 'sync_status'
                  ? "'synced'"
                  : c,
          ];
          await _db.customInsert(
            'INSERT INTO $table (${colonnes.join(', ')}) '
            'SELECT ${valeurs.join(', ')} FROM $table WHERE id = ?',
            variables: [
              Variable.withString(idServeur),
              Variable.withString(idPoste),
            ],
            updates: {info},
          );
        }
      }

      // 2. Toutes les références locales.
      for (final (cible, colonne) in cibles) {
        final infoCible = _table(cible);
        final variables = [
          Variable.withString(idServeur),
          Variable.withString(idPoste),
        ];
        if (miroirsACle.contains(cible)) {
          await _db.customUpdate(
            'UPDATE OR IGNORE $cible SET $colonne = ? WHERE $colonne = ?',
            variables: variables,
            updates: {infoCible},
            updateKind: UpdateKind.update,
          );
          await _db.customUpdate(
            'DELETE FROM $cible WHERE $colonne = ?',
            variables: [Variable.withString(idPoste)],
            updates: {infoCible},
            updateKind: UpdateKind.delete,
          );
        } else {
          await _db.customUpdate(
            'UPDATE $cible SET $colonne = ? WHERE $colonne = ?',
            variables: variables,
            updates: {infoCible},
            updateKind: UpdateKind.update,
          );
        }
      }

      // 1 (fin). La ligne du poste est retirée : elle n'existe pas au serveur.
      await _db.customUpdate(
        'DELETE FROM $table WHERE id = ?',
        variables: [Variable.withString(idPoste)],
        updates: {info},
        updateKind: UpdateKind.delete,
      );

      // 3. Un refus encore ouvert sur l'identifiant du poste n'a plus d'objet.
      await (_db.delete(_db.syncConflicts)..where(
            (c) => Expression.and([
              c.sourceTable.equals(table),
              c.recordId.equals(idPoste),
            ]),
          ))
          .go();
    });
  }

  TableInfo<Table, dynamic> _table(String nom) =>
      _db.allTables.firstWhere(
        (t) => t.actualTableName == nom,
        orElse: () => throw StateError('table absente du schéma : $nom'),
      );
}
