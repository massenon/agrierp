import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';

/// Dépense refusée avant d'être écrite.
///
/// ⚠️ REFUSER AVANT D'ÉCRIRE, PAS APRÈS. Une dépense enregistrée localement
/// puis rejetée par le serveur reste des jours dans la file du poste, et
/// l'animalier ne l'apprend qu'à la synchronisation suivante — trop tard pour
/// corriger de mémoire.
class DepenseRefusee implements Exception {
  DepenseRefusee(this.motif);

  final String motif;

  @override
  String toString() => motif;
}

/// Saisie des dépenses au poste.
///
/// ⚠️⚠️ **LE POSTE N'A NI COMPTABILITÉ NI SOLDE FAISANT FOI.** Le serveur, à la
/// réception, décaisse la trésorerie ET passe l'écriture SYSCOHADA (ticket
/// 14.62). Le poste ne reproduit **aucun** de ces deux effets : il n'a pas de
/// plan comptable, pas d'exercice, pas de journal.
///
/// C'est une différence assumée avec les ventes et la ponte, où l'effet local
/// existe parce que le poste **en a besoin tout de suite** — vendre exige de
/// connaître le stock, servir la provende exige l'effectif. Ici, personne au
/// poste ne décide sur la foi du solde de trésorerie : lui inventer un
/// décaissement local produirait un chiffre qui n'engage rien et qui
/// divergerait du serveur dès la première dépense saisie ailleurs.
class DepensesRepository {
  DepensesRepository({
    required AppDatabase database,
    required String deviceId,
    Uuid? uuid,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _deviceId = deviceId,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final String _deviceId;
  final Uuid _uuid;

  /// Comptes de charge servis par le serveur, jamais codés en dur ici.
  Future<List<ExpenseCategory>> categories() {
    return (_db.select(
      _db.expenseCategories,
    )..orderBy([(t) => OrderingTerm(expression: t.label)])).get();
  }

  /// Comptes de trésorerie pouvant payer.
  Future<List<TreasuryAccount>> comptesTresorerie() {
    return (_db.select(
      _db.treasuryAccounts,
    )..orderBy([(t) => OrderingTerm(expression: t.label)])).get();
  }

  /// Dépenses saisies **sur ce poste**, la plus récente d'abord.
  ///
  /// ⚠️ CE N'EST PAS LA LISTE DE L'EXPLOITATION. Le contrat de synchronisation
  /// ne redescend pas les dépenses du serveur : le poste ne connaît que les
  /// siennes. L'écran doit le dire, sinon la liste se lit comme un état
  /// complet et une dépense saisie ailleurs paraîtra manquante.
  Future<List<Expense>> mesDepenses() {
    return (_db.select(_db.expenses)..orderBy([
          (t) =>
              OrderingTerm(expression: t.expenseDate, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        ]))
        .get();
  }

  /// Enregistre une dépense, en attente d'envoi.
  ///
  /// ⚠️ **LES MÊMES BORNES QUE LE SERVEUR, APPLIQUÉES ICI.** Montant strictement
  /// positif, compte de charge connu, compte payeur connu : le serveur refuse
  /// déjà tout cela, mais un refus qui n'arrive qu'à la synchronisation laisse
  /// l'animalier sans recours sur le terrain.
  Future<Expense> enregistrer({
    required DateTime date,
    required String libelle,
    required String categorie,
    required double montant,
    required String compteTresorerieId,
  }) async {
    if (libelle.trim().isEmpty) {
      throw DepenseRefusee('Le libellé de la dépense est obligatoire.');
    }

    if (montant <= 0) {
      throw DepenseRefusee('Le montant décaissé doit être supérieur à zéro.');
    }

    final categorieConnue = await (_db.select(
      _db.expenseCategories,
    )..where((t) => t.label.equals(categorie))).getSingleOrNull();

    if (categorieConnue == null) {
      throw DepenseRefusee(
        'Compte de charge inconnu — synchronisez le poste pour recevoir la '
        'liste à jour.',
      );
    }

    final compte = await (_db.select(
      _db.treasuryAccounts,
    )..where((t) => t.id.equals(compteTresorerieId))).getSingleOrNull();

    if (compte == null) {
      throw DepenseRefusee(
        'Compte de trésorerie inconnu — synchronisez le poste avant de saisir.',
      );
    }

    final id = _uuid.v4();
    final maintenant = DateTime.now();

    await _db
        .into(_db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: id,
            deviceId: _deviceId,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: maintenant,
            expenseDate: DateTime(date.year, date.month, date.day),
            label: libelle.trim(),
            category: categorie,
            amount: montant,
            treasuryAccountId: compteTresorerieId,
          ),
        );

    return (_db.select(
      _db.expenses,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  /// Total des dépenses saisies sur ce poste pour le mois d'une date donnée.
  ///
  /// ⚠️ « DU POSTE », PAS « DU MOIS DE L'EXPLOITATION » — même raison que
  /// [mesDepenses] : les dépenses saisies sur le web ou sur un autre poste n'y
  /// figurent pas.
  Future<double> totalDuMois(DateTime quand) async {
    final debut = DateTime(quand.year, quand.month, 1);
    final finExclue = DateTime(quand.year, quand.month + 1, 1);

    final lignes =
        await (_db.select(_db.expenses)..where(
              (t) =>
                  t.expenseDate.isBiggerOrEqualValue(debut) &
                  t.expenseDate.isSmallerThanValue(finExclue),
            ))
            .get();

    return lignes.fold<double>(0, (total, d) => total + d.amount);
  }
}
