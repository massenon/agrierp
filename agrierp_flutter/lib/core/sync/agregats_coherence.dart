/// Ticket S-T6 — TABLE DE CORRESPONDANCE DU CONTRÔLE DE COHÉRENCE (méthode TATACORA : nombre et total par table et
/// par jour, au poste et au serveur).
///
/// ⚠️⚠️ COPIE CONFORME de `CoherenceSynchronisationService::AGREGATS` (`agrierp_laravel/app/Services/
/// CoherenceSynchronisationService.php`). `test/coherence_synchronisation_test.dart` lit le PHP et exige l'égalité
/// entrée par entrée : table, libellé, colonnes du jour, colonne du montant, filtre. Une définition qui ne serait
/// changée que d'un côté ferait apparaître des écarts qui n'existent pas — ou en cacherait de vrais.
///
/// Seules les tables dont le poste tient un MIROIR COMPLET y figurent (voir le PHP) : les dépenses, qui ne
/// descendent pas au poste, n'y sont pas.
class AgregatCoherence {
  const AgregatCoherence({
    required this.table,
    required this.libelle,
    required this.jour,
    required this.montant,
    this.filtre,
  });

  /// Nom SQL de la table, identique des deux côtés.
  final String table;

  /// Libellé affiché (le même qu'au serveur, qui le rend dans sa réponse).
  final String libelle;

  /// Colonne(s) qui datent la ligne au SERVEUR, la première non nulle. Le poste lit la PREMIÈRE seule : pour les
  /// ventes, `sold_at` y porte déjà la date effective (`sold_at ?? created_at`), servie sous ce nom par le tirage.
  final List<String> jour;

  /// Colonne sommée.
  final String montant;

  /// Condition `(colonne, opérateur, valeur)`, ou `null`.
  final (String, String, Object)? filtre;
}

class AgregatsCoherence {
  AgregatsCoherence._();

  static const tables = <AgregatCoherence>[
    AgregatCoherence(
      table: 'sales',
      libelle: 'Ventes',
      jour: ['sold_at', 'created_at'],
      montant: 'total',
      filtre: ('status', '<>', 'annulee'),
    ),
    AgregatCoherence(
      table: 'purchases',
      libelle: 'Achats',
      jour: ['purchase_date'],
      montant: 'total',
    ),
    AgregatCoherence(
      table: 'livestock_daily_entries',
      libelle: 'Fiches journalières (morts)',
      jour: ['entry_date'],
      montant: 'mort',
    ),
    AgregatCoherence(
      table: 'veterinary_records',
      libelle: 'Soins (coût)',
      jour: ['record_date'],
      montant: 'cost',
      filtre: ('is_active', '=', 1),
    ),
    AgregatCoherence(
      table: 'customer_advances',
      libelle: 'Avances clients',
      jour: ['advance_date'],
      montant: 'amount',
      filtre: ('is_active', '=', 1),
    ),
    AgregatCoherence(
      table: 'livestock_transfers',
      libelle: 'Transferts entre bandes (sujets)',
      jour: ['transfer_date'],
      montant: 'quantity',
      filtre: ('is_active', '=', 1),
    ),
    AgregatCoherence(
      table: 'stock_movements',
      libelle: 'Mouvements de stock, ajustements compris (quantités)',
      jour: ['movement_date'],
      montant: 'quantity',
    ),
  ];
}
