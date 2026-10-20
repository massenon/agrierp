import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../stocks/pmp_service.dart';

/// Dépense refusée avant d'être écrite.
///
/// ⚠️ REFUSER AVANT D'ÉCRIRE, PAS APRÈS. Une dépense enregistrée localement
/// puis rejetée par le serveur reste des jours dans la file du poste, et
/// l'animalier ne l'apprend qu'à la synchronisation suivante — trop tard pour
/// corriger de mémoire.
///
/// Ticket U14 — les refus sont rendus PAR CHAMP, avec les messages du web (`lang/fr/validation.php` et les noms de
/// champ du composant : `expenseDate` → « date de la dépense », `label` → « libellé », `category` → « catégorie »,
/// `amount` → « montant », `treasuryAccountId` → « compte de trésorerie ») : l'écran les affiche sous leur champ, comme
/// `@error(…)` du Blade. Clés : `date`, `libelle`, `categorie`, `montant`, `compte`.
class DepenseRefusee implements Exception {
  DepenseRefusee(this.erreurs);

  final Map<String, String> erreurs;

  /// Le premier refus (le champ le plus haut du formulaire).
  String get motif => erreurs.values.first;

  @override
  String toString() => erreurs.values.join(' ');
}

/// Une ligne du tableau de « Saisie des Dépenses ».
class LigneDepense {
  const LigneDepense({required this.depense, this.motifRefus});

  final Expense depense;

  /// Motif du serveur, mot pour mot, quand la dernière saisie de cette dépense a été refusée (`conflict`).
  final String? motifRefus;
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
///
/// 🔴→✅ Ticket U14 — **MODIFIER ET ARCHIVER, COMME LE WEB** (`SaisieDepenses::submitExpense()` en modification,
/// `archiveExpense()`). Le poste écrit le FAIT (`pending`) ; le serveur le rejoue par `SaisieDepenseAction`, le point de
/// passage du composant Livewire (trésorerie réajustée ou réintégrée, contre-passation, journal d'audit). Les règles du
/// web sont appliquées ICI, avant d'écrire, avec ses messages : une dépense comptabilisée ne change ni de date (EX5), ni de montant, ni de
/// compte de charge, ni de compte de trésorerie ; une dépense archivée ne se modifie plus.
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

  /// Ticket EX6 — le point de passage commun de l'exercice d'une saisie (`lib/core/comptabilite/`).
  ExerciceDeSaisie get _exercice => ExerciceDeSaisie(_db);

  /// Borne basse du calendrier « Date de la Transaction » : début du plus ancien exercice OUVERT connu (une
  /// dépense créée passe une écriture), `null` si aucun.
  Future<DateTime?> premierJourSaisissable() => _exercice.premierJour();

  /// `SaisieDepenseAction::MESSAGE_DEJA_COMPTABILISEE` du web, mot pour mot.
  static const messageDejaComptabilisee =
      'Cette dépense est déjà comptabilisée : sa date, son montant, son compte de charge et son compte de '
      'trésorerie ne peuvent plus être modifiés ici. Passez une écriture de correction au Journal Comptable.';

  /// `SaisieDepenseAction::MESSAGE_ARCHIVEE` du web, mot pour mot.
  static const messageArchivee = 'Cette dépense est archivée : elle ne peut plus être modifiée.';

  /// Toasts du web (`SaisieDepenses`) : « Dépense enregistrée avec succès. » (succès) après un enregistrement,
  /// « Dépense archivée — trésorerie réintégrée et charge annulée. » (avertissement) après un archivage. Le poste
  /// n'a pas l'écriture : la variante « écriture non générée » ne peut se dire qu'au serveur (journal d'audit).
  static const toastEnregistree = 'Dépense enregistrée avec succès.';
  static const toastArchivee = 'Dépense archivée — trésorerie réintégrée et charge annulée.';

  /// Options du filtre « Statut » du Blade (`<option value="">Tous les statuts</option><option>Payée</option>…`).
  static const statuts = ['Payée', 'En attente'];

  /// Comptes de charge servis par le serveur (`Expense::CATEGORIES`), dans l'ordre servi — jamais codés en dur ici.
  Future<List<ExpenseCategory>> categories() {
    return (_db.select(
      _db.expenseCategories,
    )..orderBy([(t) => OrderingTerm(expression: t.label)])).get();
  }

  /// Comptes de trésorerie pouvant payer : ceux que le serveur sert (`is_active`, `orderBy('label')`), comme
  /// `getTreasuryAccountsProperty()` du web.
  Future<List<TreasuryAccount>> comptesTresorerie() {
    return (_db.select(
      _db.treasuryAccounts,
    )..orderBy([(t) => OrderingTerm(expression: t.label)])).get();
  }

  /// `getExpensesProperty()` du web : dépenses ACTIVES, `label LIKE '%recherche%'` (collation du serveur, insensible
  /// à la casse et aux accents ; `%` et `_` y sont des jokers ; « 0 » ne filtre pas, `when()` le lit faux), filtre de
  /// statut (« Payée » → `payee`, « En attente » → `en_attente`), `orderByDesc('expense_date')->orderBy('id')`.
  ///
  /// Ticket U13 — les dépenses du serveur DESCENDENT au poste : la liste est celle de l'exploitation, plus les saisies
  /// de ce poste pas encore acquittées. ➕ Ajout du poste : une saisie REFUSÉE (`conflict`) reste listée avec son motif,
  /// même un ARCHIVAGE refusé (la dépense est encore active au serveur) — c'est ici que le refus se voit.
  Future<List<LigneDepense>> depenses({
    String recherche = '',
    String statut = '',
  }) async {
    final lignes =
        await (_db.select(_db.expenses)..where(
              (t) =>
                  t.isActive.equals(true) |
                  t.syncStatus.equalsValue(SyncStatus.conflict),
            ))
            .get();
    final refus = {
      for (final c in await (_db.select(
        _db.syncConflicts,
      )..where((c) => c.sourceTable.equals('expenses'))).get())
        c.recordId: c.reason,
    };
    final filtreTexte = recherche.isEmpty || recherche == '0'
        ? null
        : _motifLike(recherche);
    final retenues = [
      for (final d in lignes)
        if ((filtreTexte == null ||
                filtreTexte.hasMatch(cleCommeLeServeur(d.label))) &&
            (statut.isEmpty ||
                (statut == 'Payée' && d.status == 'payee') ||
                (statut == 'En attente' && d.status == 'en_attente')))
          d,
    ]..sort((a, b) {
        final parDate = b.expenseDate.compareTo(a.expenseDate);
        return parDate != 0 ? parDate : a.id.compareTo(b.id);
      });
    return [
      for (final d in retenues)
        LigneDepense(
          depense: d,
          motifRefus: d.syncStatus == SyncStatus.conflict ? refus[d.id] : null,
        ),
    ];
  }

  /// `LIKE '%…%'` de MySQL sous `utf8mb4_unicode_ci` : `%` = n'importe quelle suite, `_` = un caractère, le reste
  /// littéral, comparé sur la clé de collation ([cleCommeLeServeur]).
  static RegExp _motifLike(String recherche) {
    final motif = StringBuffer();
    for (final c in cleCommeLeServeur(recherche).split('')) {
      motif.write(switch (c) {
        '%' => '.*',
        '_' => '.',
        _ => RegExp.escape(c),
      });
    }
    return RegExp(motif.toString(), dotAll: true);
  }

  /// Règles de `submitExpense()` du web, messages de `lang/fr/validation.php` par champ ; vide si tout est valable.
  ///
  /// `expenseDate` `required|date` · `label` `required|string|max:255` · `category` `required|string` · `amount`
  /// `required|numeric|min:1` · `treasuryAccountId` `required|exists:treasury_accounts,id`. ➕ Comme l'envoi du
  /// serveur (`in:` `Expense::CATEGORIES`), un compte de charge absent de la liste reçue est refusé ici plutôt qu'au
  /// serveur, des jours plus tard.
  static Map<String, String> valider({
    required DateTime? date,
    required String libelle,
    required String? categorie,
    required String montant,
    required String? compteTresorerieId,
    bool categorieConnue = true,
    bool compteConnu = true,
  }) {
    final erreurs = <String, String>{};
    if (date == null) {
      erreurs['date'] = 'Le champ date de la dépense est obligatoire.';
    }
    if (libelle.trim().isEmpty) {
      erreurs['libelle'] = 'Le champ libellé est obligatoire.';
    } else if (libelle.runes.length > 255) {
      erreurs['libelle'] = 'Le champ libellé ne doit pas dépasser 255 caractères.';
    }
    if (categorie == null || categorie.trim().isEmpty) {
      erreurs['categorie'] = 'Le champ catégorie est obligatoire.';
    } else if (!categorieConnue) {
      erreurs['categorie'] = "La valeur du champ catégorie n'est pas autorisée.";
    }
    final texte = montant.trim();
    final valeur = double.tryParse(texte.replaceAll(',', '.'));
    if (texte.isEmpty) {
      erreurs['montant'] = 'Le champ montant est obligatoire.';
    } else if (valeur == null || !valeur.isFinite) {
      erreurs['montant'] = 'Le champ montant doit être un nombre.';
    } else if (valeur < 1) {
      erreurs['montant'] = 'Le champ montant doit être au moins égal à 1.';
    }
    if (compteTresorerieId == null || compteTresorerieId.isEmpty) {
      erreurs['compte'] = 'Le champ compte de trésorerie est obligatoire.';
    } else if (!compteConnu) {
      erreurs['compte'] =
          "La valeur sélectionnée pour le champ compte de trésorerie n'existe pas.";
    }
    return erreurs;
  }

  /// Enregistre une dépense (création, ou modification de [idEnModification]), en attente d'envoi.
  ///
  /// ⚠️ **LES MÊMES BORNES QUE LE WEB, APPLIQUÉES ICI** ([valider]) ; puis, en modification, les deux refus de
  /// `SaisieDepenseAction::modifier()`, sous le champ « Montant » comme au web : dépense archivée, et dépense
  /// comptabilisée (`accounting_entry_id` servi par le tirage) dont la date (EX5), le montant, le compte de charge ou le compte de
  /// trésorerie changerait.
  ///
  /// Une modification repasse la ligne en `pending` à l'instant de la saisie (`updatedAt`) ; elle part entière, le
  /// serveur la rejoue (dernier écrivain gagne, comme au web). Son ancien refus éventuel est effacé : il portait sur
  /// une version dépassée.
  Future<Expense> enregistrer({
    required DateTime date,
    required String libelle,
    required String categorie,
    required double montant,
    required String compteTresorerieId,
    String? idEnModification,
  }) => enregistrerSaisie(
    date: date,
    libelle: libelle,
    categorie: categorie,
    montant: PmpService.flottant(montant),
    compteTresorerieId: compteTresorerieId,
    idEnModification: idEnModification,
  );

  /// [enregistrer] à partir du texte saisi dans « Montant Décaissé (FCFA) » (l'écran) : un montant vide ou illisible
  /// reçoit le message du web, comme `amount` `required|numeric`.
  Future<Expense> enregistrerSaisie({
    required DateTime? date,
    required String libelle,
    required String? categorie,
    required String montant,
    required String? compteTresorerieId,
    String? idEnModification,
  }) async {
    final existante = idEnModification == null
        ? null
        : await (_db.select(
            _db.expenses,
          )..where((t) => t.id.equals(idEnModification))).getSingleOrNull();
    if (idEnModification != null && existante == null) {
      throw DepenseRefusee({'montant': 'Dépense introuvable sur ce poste.'});
    }

    final categorieConnue =
        categorie == null ||
        categorie.isEmpty ||
        await (_db.select(
              _db.expenseCategories,
            )..where((t) => t.label.equals(categorie))).getSingleOrNull() !=
            null;
    final compteConnu =
        compteTresorerieId == null ||
        compteTresorerieId.isEmpty ||
        compteTresorerieId == existante?.treasuryAccountId ||
        await (_db.select(_db.treasuryAccounts)
                  ..where((t) => t.id.equals(compteTresorerieId)))
                .getSingleOrNull() !=
            null;

    final erreurs = valider(
      date: date,
      libelle: libelle,
      categorie: categorie,
      montant: montant,
      compteTresorerieId: compteTresorerieId,
      categorieConnue: categorieConnue,
      compteConnu: compteConnu,
    );
    if (erreurs.isNotEmpty) throw DepenseRefusee(erreurs);

    final valeur = double.parse(montant.trim().replaceAll(',', '.'));
    final jour = DateTime(date!.year, date.month, date.day);
    final maintenant = HeureBenin.versInstant(HeureBenin.maintenant());

    if (existante != null) {
      // Un ARCHIVAGE REFUSÉ par le serveur (`conflict`) laisse la dépense active là-bas : la modifier la garde active.
      final archivageRefuse =
          !existante.isActive && existante.syncStatus == SyncStatus.conflict;
      if (!existante.isActive && !archivageRefuse) {
        throw DepenseRefusee({'montant': messageArchivee});
      }
      // 🔴→✅ Ticket EX6 (EF7) — `SaisieDepenseAction::modifier` : une dépense d'un exercice CLOS ne se modifie plus
      // (motif R4 de sa date d'origine), et ne passe pas non plus dans un exercice clos (motif R4 de la nouvelle date).
      // Règle `refusExerciceClos` : une modification ne passe aucune écriture, un jour qu'aucun exercice ne couvre
      // reste admis.
      await _exercice.refuser(
        existante.expenseDate,
        regle: RegleExercice.closSeulement,
      );
      await _exercice.refuser(jour, regle: RegleExercice.closSeulement);
      final montantChange =
          PmpService.arrondi(valeur, 2) != PmpService.arrondi(existante.amount, 2);
      // 🔴→✅ Ticket EX5 (décision D-U14-1 du 20/10/2026) — la DATE d'une dépense comptabilisée
      // est verrouillée comme son montant (`SaisieDepenseAction::modifier`, même message).
      final ancienJour = DateTime(
        existante.expenseDate.year,
        existante.expenseDate.month,
        existante.expenseDate.day,
      );
      if (existante.accountingEntryId != null &&
          (montantChange ||
              jour != ancienJour ||
              categorie != existante.category ||
              compteTresorerieId != existante.treasuryAccountId)) {
        throw DepenseRefusee({'montant': messageDejaComptabilisee});
      }

      await _db.transaction(() async {
        await (_db.update(
          _db.expenses,
        )..where((t) => t.id.equals(existante.id))).write(
          ExpensesCompanion(
            expenseDate: Value(jour),
            label: Value(libelle.trim()),
            category: Value(categorie!),
            amount: Value(valeur),
            treasuryAccountId: Value(compteTresorerieId!),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: Value(maintenant),
          ),
        );
        await _effacerRefus(existante.id);
      });
      return _lire(existante.id);
    }

    // 🔴→✅ Ticket EX6 (EF7) — `SaisieDepenseAction::creer` : exercice clos refusé avant tout effet, puis l'écriture
    // Débit 6 / Crédit 5 datée de la dépense (`record()`, filet R2 compris) refuse un jour qu'aucun exercice ne couvre.
    await _exercice.refuser(jour);

    final id = _uuid.v4();
    await _db
        .into(_db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: id,
            deviceId: _deviceId,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: maintenant,
            expenseDate: jour,
            label: libelle.trim(),
            category: categorie!,
            amount: valeur,
            treasuryAccountId: compteTresorerieId!,
          ),
        );

    return _lire(id);
  }

  /// `archiveExpense($id)` du web : la dépense devient inactive et part à l'envoi (`pending`) ; le serveur
  /// contre-passe sa charge et réintègre la trésorerie (`SaisieDepenseAction::archiver()`). Déjà archivée : rien.
  Future<void> archiver(String id) async {
    await _db.transaction(() async {
      final d = await (_db.select(
        _db.expenses,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (d == null || (!d.isActive && d.syncStatus != SyncStatus.conflict)) {
        return;
      }
      // 🔴→✅ Ticket EX6 (EF7) — `SaisieDepenseAction::archiver` : une dépense d'un exercice CLOS ne s'archive plus
      // (elle disparaîtrait des états de cet exercice) ; motif R4 de sa date, toast au web.
      await _exercice.refuser(d.expenseDate, regle: RegleExercice.closSeulement);
      await (_db.update(_db.expenses)..where((t) => t.id.equals(id))).write(
        ExpensesCompanion(
          isActive: const Value(false),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(HeureBenin.versInstant(HeureBenin.maintenant())),
        ),
      );
      await _effacerRefus(id);
    });
  }

  Future<void> _effacerRefus(String id) => (_db.delete(
    _db.syncConflicts,
  )..where((c) => c.id.equals('expenses:$id'))).go();

  Future<Expense> _lire(String id) =>
      (_db.select(_db.expenses)..where((t) => t.id.equals(id))).getSingle();

  /// « Dépenses du mois » du web (`SaisieDepenses::getKpisProperty()` : dépenses ACTIVES dont `expense_date` tombe
  /// dans le mois et l'année de [quand]).
  ///
  /// 🔴→✅ Ticket U13 — l'exploitation entière (les dépenses du serveur descendent), archivées exclues. Règle U8 : une
  /// saisie en attente d'envoi compte (elle part vers le web), une saisie REFUSÉE (`conflict`) n'existe pas au web.
  Future<double> totalDuMois(DateTime quand) async {
    final debut = DateTime(quand.year, quand.month, 1);
    final finExclue = DateTime(quand.year, quand.month + 1, 1);

    final lignes =
        await (_db.select(_db.expenses)..where(
              (t) =>
                  t.expenseDate.isBiggerOrEqualValue(debut) &
                  t.expenseDate.isSmallerThanValue(finExclue) &
                  t.isActive.equals(true) &
                  t.syncStatus.equalsValue(SyncStatus.conflict).not(),
            ))
            .get();

    return lignes.fold<double>(0, (total, d) => total + d.amount);
  }
}
