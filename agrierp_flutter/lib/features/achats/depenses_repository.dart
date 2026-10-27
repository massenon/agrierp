import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/identifiant_ligne_depense.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../stocks/pmp_service.dart' show cleCommeLeServeur;

/// Dépense refusée avant d'être écrite.
///
/// ⚠️ REFUSER AVANT D'ÉCRIRE, PAS APRÈS. Une dépense enregistrée localement puis rejetée par le serveur reste des jours
/// dans la file du poste, et l'animalier ne l'apprend qu'à la synchronisation suivante — trop tard pour corriger de mémoire.
///
/// Ticket DEP4 — les refus sont rendus PAR CHAMP, avec les messages du web (`lang/fr/validation.php`, noms de champ de
/// `SaisieDepenseAction::attributs()`) : l'écran les affiche sous leur champ, comme `@error(…)` du Blade. Clés : `date`,
/// `mode`, `compte`, `centre`, `fournisseur`, `beneficiaire`, `lignes`, `total`, `formulaire`, et par ligne
/// `ligne.N.libelle`, `ligne.N.compte`, `ligne.N.montant`.
class DepenseRefusee implements Exception {
  DepenseRefusee(this.erreurs);

  final Map<String, String> erreurs;

  /// Le premier refus (le champ le plus haut du formulaire).
  String get motif => erreurs.values.first;

  @override
  String toString() => erreurs.values.join(' ');
}

/// Une ligne telle que saisie dans la modale « Nouvelle Dépense » : libellé, compte de charge choisi, montant en TEXTE
/// (un entier de francs). [id] : celui d'une ligne existante (modification), `null` pour une ligne neuve.
class LigneSaisie {
  const LigneSaisie({
    this.id,
    this.libelle = '',
    this.compteChargeId,
    this.montant = '',
  });

  final String? id;
  final String libelle;
  final String? compteChargeId;
  final String montant;
}

/// Une ligne lue pour le détail déplié du tableau.
class DetailLigneDepense {
  const DetailLigneDepense({
    required this.id,
    required this.libelle,
    required this.compte,
    required this.montant,
    this.compteChargeId,
  });

  final String id;
  final String libelle;

  /// « 601 - Achats de marchandises » ; « — » si le plan local ne le connaît pas.
  final String compte;
  final double montant;
  final String? compteChargeId;
}

/// Une dépense du tableau de « Saisie des Dépenses » : l'en-tête, ses lignes et ce que le détail déplié montre.
class LigneDepense {
  const LigneDepense({
    required this.depense,
    this.lignes = const [],
    this.motifRefus,
    this.numeroPiece,
    this.tresorerie,
    this.centreCout,
    this.fournisseur,
    this.auteur,
  });

  final Expense depense;
  final List<DetailLigneDepense> lignes;

  /// Motif du serveur, mot pour mot, quand la dernière saisie de cette dépense a été refusée (`conflict`) : le REFUS DE
  /// LA PIÈCE (`expenses.ecriture_refus`, ou à défaut le conflit de synchronisation).
  final String? motifRefus;

  /// « OD-2026-0012 » : RELU de l'écriture liée (`accounting_entries.reference`), jamais recopié. `null` si la dépense n'a
  /// pas d'écriture, ou si ce poste n'a pas le journal (comptes sans `view-comptabilite`).
  final String? numeroPiece;
  final String? tresorerie;
  final String? centreCout;
  final String? fournisseur;
  final String? auteur;

  /// Pièce comptable liée (`accounting_entry_id` servi par le tirage) : la dépense est IMMUABLE.
  bool get comptabilisee => depense.accountingEntryId != null;
}

/// Saisie des dépenses au poste.
///
/// ⚠️⚠️ **LE POSTE N'A NI COMPTABILITÉ NI SOLDE FAISANT FOI.** Le serveur, à la réception, décaisse la trésorerie ET passe
/// l'écriture SYSCOHADA (ticket 14.62). Le poste ne reproduit **aucun** de ces deux effets : il enregistre le FAIT
/// (`pending`) et le serveur le rejoue par `SaisieDepenseAction`.
///
/// 🔴→✅ Ticket U14 — **MODIFIER ET ARCHIVER, COMME LE WEB**.
///
/// 🔴→✅ Ticket DEP4 (PRD `docs/prd/depenses-multilignes.md`) — **UNE DÉPENSE, PLUSIEURS LIGNES.** L'en-tête (date, mode,
/// trésorerie, centre de coût, fournisseur ou bénéficiaire, auteur) et ses lignes (libellé, compte de charge, montant)
/// s'écrivent dans UNE SEULE transaction Drift ; le total est la SOMME des lignes (jamais saisi), le libellé de l'en-tête
/// leur résumé. La pièce est passée par le SERVEUR au rejeu ; son refus (exercice clos, trésorerie sans compte du plan…)
/// revient au poste (`ecriture_refus`) et s'affiche sous la dépense. Une dépense COMPTABILISÉE (pièce connue) est
/// IMMUABLE — comme au web, on l'archive (contre-passation par le serveur) puis on la saisit à nouveau.
class DepensesRepository {
  DepensesRepository({
    required AppDatabase database,
    required String deviceId,
    String? Function()? auteurId,
    Uuid? uuid,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _deviceId = deviceId,
       // ignore: prefer_initializing_formals
       _auteurId = auteurId,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final String _deviceId;
  final String? Function()? _auteurId;
  final Uuid _uuid;

  /// Ticket EX6 — le point de passage commun de l'exercice d'une saisie (`lib/core/comptabilite/`).
  ExerciceDeSaisie get _exercice => ExerciceDeSaisie(_db);

  /// Borne basse du calendrier « Date de la Transaction » : début du plus ancien exercice OUVERT connu (une
  /// dépense créée passe une écriture), `null` si aucun.
  Future<DateTime?> premierJourSaisissable() => _exercice.premierJour();

  /// `SaisieDepenseAction::MESSAGE_DEJA_COMPTABILISEE` du web, mot pour mot.
  static const messageDejaComptabilisee =
      'Cette dépense est déjà comptabilisée : elle ne peut plus être modifiée. Archivez-la (la charge est extournée et '
      'la trésorerie réintégrée), puis saisissez-la à nouveau.';

  /// `SaisieDepenseAction::MESSAGE_ARCHIVEE` du web, mot pour mot.
  static const messageArchivee = 'Cette dépense est archivée : elle ne peut plus être modifiée.';

  /// Toasts du web (`SaisieDepenses`) : « Dépense enregistrée avec succès. » (succès) après un enregistrement,
  /// « Dépense archivée — trésorerie réintégrée et charge annulée. » (avertissement) après un archivage.
  static const toastEnregistree = 'Dépense enregistrée avec succès.';
  static const toastArchivee = 'Dépense archivée — trésorerie réintégrée et charge annulée.';

  /// `SaisieDepenseAction::MESSAGE_CENTRE_OBLIGATOIRE` du web, mot pour mot (ticket DEP6, DEP-Q1).
  static const messageCentreObligatoire =
      'Le centre de coût est obligatoire : choisissez la filière ou le lot qui supporte cette dépense.';

  /// `SaisieDepenseAction::MESSAGE_CREDIT_SANS_FOURNISSEUR` du web, mot pour mot (ticket DEP7, DEP-Q3).
  static const messageCreditSansFournisseur =
      'Choisissez le fournisseur : une dépense à crédit crée une dette à son nom.';

  /// `SaisieDepenseAction::MESSAGE_CREDIT_SANS_PIECE` du web, mot pour mot (ticket DEP7).
  static const messageCreditSansPiece =
      'Une dépense existante sans pièce ne peut pas passer à crédit : archivez-la, puis saisissez-la à nouveau à crédit.';

  /// Toast du web quand on archive une dépense À CRÉDIT (`SaisieDepenses::archiveExpense()`, ticket DEP7).
  static const toastArchiveeACredit = 'Dépense archivée — dette fournisseur annulée et charge annulée.';

  /// « Règlement » de la modale (`Expense::REGLEMENTS` du web, mot pour mot) : clé = valeur du champ, valeur = libellé.
  static const reglements = {
    'comptant': 'Payée comptant',
    'credit': 'À crédit (dette fournisseur)',
  };

  /// `Expense::libelleReglement()` du web, mot pour mot : le règlement tel que le détail déplié le dit.
  static String libelleReglement({required bool aCredit, required String statut}) {
    if (!aCredit) return 'Payée comptant';
    return statut == 'payee' ? 'À crédit — réglée' : 'À crédit — en attente';
  }

  /// Options du filtre « Pièce » du Blade (`<option value="">Toutes les pièces</option><option>Comptabilisée</option>…`).
  static const filtresPiece = ['Comptabilisée', 'Sans pièce'];

  /// Modes de paiement : type du compte de trésorerie → libellé (`Expense::MODES_DE_PAIEMENT` du web, mot pour mot).
  static const modesDePaiement = {
    'caisse': 'Espèces',
    'banque': 'Banque',
    'mobile_money': 'Mobile Money',
  };

  /// Les comptes de CHARGE du plan comptable local (classe 6, par code) : la liste de chaque ligne
  /// (`getChargeAccountsProperty()` du web). Jamais codés en dur ici : le plan descend par la synchronisation.
  Future<List<ChartOfAccount>> comptesDeCharge() {
    return (_db.select(_db.chartOfAccounts)
          ..where((t) => t.accountClass.equals(6))
          ..orderBy([(t) => OrderingTerm(expression: t.code)]))
        .get();
  }

  /// Comptes de trésorerie pouvant payer : ceux que le serveur sert (`is_active`, `orderBy('label')`), comme
  /// `getTreasuryAccountsProperty()` du web ; [mode] (type du compte) les filtre comme le web quand un mode est choisi.
  Future<List<TreasuryAccount>> comptesTresorerie({String? mode}) {
    return (_db.select(_db.treasuryAccounts)
          ..where((t) => mode == null || mode.isEmpty ? const Constant(true) : t.type.equals(mode))
          ..orderBy([(t) => OrderingTerm(expression: t.label)]))
        .get();
  }

  /// Centres de coût actifs (`getCostCentersProperty()` du web : `is_active`, `orderBy('label')`).
  Future<List<CostCenter>> centresDeCout() {
    return (_db.select(_db.costCenters)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.label)]))
        .get();
  }

  /// Fournisseurs actifs (`getSuppliersProperty()` du web : `is_active`, `orderBy('name')`).
  Future<List<Supplier>> fournisseurs() {
    return (_db.select(_db.suppliers)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
  }

  /// `getExpensesProperty()` du web : dépenses ACTIVES, `label LIKE '%recherche%'` sur le résumé OU sur un libellé de
  /// ligne (collation du serveur, insensible à la casse et aux accents ; `%` et `_` y sont des jokers ; « 0 » ne
  /// filtre pas, `when()` le lit faux), filtre « Pièce » (« Comptabilisée » : `accounting_entry_id` non nul, « Sans
  /// pièce » : nul), `orderByDesc('expense_date')->orderBy('id')`.
  ///
  /// Ticket U13 — les dépenses du serveur DESCENDENT au poste. ➕ Ajout du poste : une saisie REFUSÉE (`conflict`) reste
  /// listée avec son motif, même un ARCHIVAGE refusé (la dépense est encore active au serveur).
  /// Ticket EX7 (EF9) — [bornes] (l'exercice affiché) : seules les dépenses datées dans l'exercice ; sans bornes, toutes.
  Future<List<LigneDepense>> depenses({
    String recherche = '',
    String piece = '',
    ({DateTime debut, DateTime fin})? bornes,
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
    bool dansLExercice(DateTime jour) =>
        bornes == null ||
        (!DateTime(jour.year, jour.month, jour.day).isBefore(bornes.debut) &&
            !DateTime(jour.year, jour.month, jour.day).isAfter(bornes.fin));

    final detail = await _detailDesLignes();
    final retenues = [
      for (final d in lignes)
        if (dansLExercice(d.expenseDate) &&
            (filtreTexte == null ||
                filtreTexte.hasMatch(cleCommeLeServeur(d.label)) ||
                (detail[d.id] ?? const []).any((l) => filtreTexte.hasMatch(cleCommeLeServeur(l.libelle)))) &&
            (piece.isEmpty ||
                (piece == 'Comptabilisée' && d.accountingEntryId != null) ||
                (piece == 'Sans pièce' && d.accountingEntryId == null)))
          d,
    ]..sort((a, b) {
        final parDate = b.expenseDate.compareTo(a.expenseDate);
        return parDate != 0 ? parDate : a.id.compareTo(b.id);
      });

    final tresoreries = {for (final t in await _db.select(_db.treasuryAccounts).get()) t.id: t.label};
    final centres = {for (final c in await _db.select(_db.costCenters).get()) c.id: c.label};
    final fournisseurs = {for (final f in await _db.select(_db.suppliers).get()) f.id: f.name};
    final auteurs = {for (final u in await _db.select(_db.utilisateurs).get()) u.id: u.name};
    final pieces = {
      for (final e in await _db.select(_db.accountingEntries).get())
        e.id: (e.reference ?? '').split(' — ').first.trim(),
    };

    return [
      for (final d in retenues)
        LigneDepense(
          depense: d,
          lignes: detail[d.id] ?? [_ligneDeRepli(d)],
          motifRefus: d.syncStatus == SyncStatus.conflict ? (d.ecritureRefus ?? refus[d.id]) : null,
          numeroPiece: () {
            final n = pieces[d.accountingEntryId];
            return n == null || n.isEmpty ? null : n;
          }(),
          tresorerie: tresoreries[d.treasuryAccountId],
          centreCout: centres[d.costCenterId],
          fournisseur: fournisseurs[d.supplierId],
          auteur: auteurs[d.createdBy],
        ),
    ];
  }

  /// Les lignes de chaque dépense, par ordre de position ; la clé est l'identifiant de la dépense.
  Future<Map<String, List<DetailLigneDepense>>> _detailDesLignes() async {
    final comptes = {for (final c in await _db.select(_db.chartOfAccounts).get()) c.id: '${c.code} - ${c.label}'};
    final lignes = await (_db.select(_db.expenseLines)
          ..orderBy([(l) => OrderingTerm(expression: l.position), (l) => OrderingTerm(expression: l.id)]))
        .get();
    final parDepense = <String, List<DetailLigneDepense>>{};
    for (final l in lignes) {
      parDepense.putIfAbsent(l.expenseId, () => []).add(
        DetailLigneDepense(
          id: l.id,
          libelle: l.label,
          compte: comptes[l.chargeAccountId] ?? '—',
          montant: l.amount,
          compteChargeId: l.chargeAccountId,
        ),
      );
    }
    return parDepense;
  }

  /// Une dépense SANS ligne (poste qui n'a pas encore reçu ses lignes du serveur, ou plan local absent à la migration) :
  /// l'écran en montre une, faite de l'ancien libellé, de l'ancienne catégorie et du montant — jamais un détail vide.
  DetailLigneDepense _ligneDeRepli(Expense d) => DetailLigneDepense(
    id: idLigneConvertie(d.id),
    libelle: d.label,
    compte: d.category.isEmpty ? '—' : d.category,
    montant: d.amount,
  );

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


  /// Règles de `SaisieDepenseAction::valider()` du web, messages de `lang/fr/validation.php` par champ ; vide si tout est
  /// valable. [compteTresorerie] : le compte choisi (type comparé au mode), `null` s'il est inconnu ou non choisi.
  ///
  /// `expense_date` `required|date` · `payment_mode` cohérent avec le type du compte · `treasury_account_id`
  /// `required|exists` (sauf À CRÉDIT, DEP7 : `supplier_id` `required` à la place) · `cost_center_id` `required|exists`
  /// (DEP6) · `beneficiary` `max:150` · `lines` `required|min:1` · par ligne : `label` `required|max:255`,
  /// `charge_account_id` `required|exists` (classe 6 du plan), `amount` `required|integer|min:1`.
  static Map<String, String> valider({
    required DateTime? date,
    required String? mode,
    required String? compteTresorerieId,
    required String? typeDuCompte,
    required bool compteConnu,
    required String beneficiaire,
    required List<LigneSaisie> lignes,
    required Set<String> comptesDeChargeConnus,
    String? centreCoutId,
    bool centreConnu = true,
    String? fournisseurId,
    bool aCredit = false,
  }) {
    final erreurs = <String, String>{};
    if (date == null) {
      erreurs['date'] = 'Le champ date de la dépense est obligatoire.';
    }
    // Ticket DEP7 — à crédit : ni mode ni trésorerie (rien n'est décaissé), mais un FOURNISSEUR (la dette est à son nom).
    if (aCredit) {
      if (fournisseurId == null || fournisseurId.isEmpty) {
        erreurs['fournisseur'] = messageCreditSansFournisseur;
      }
    } else {
      if (mode == null || mode.isEmpty) {
        erreurs['mode'] = 'Le champ mode de paiement est obligatoire.';
      }
      if (compteTresorerieId == null || compteTresorerieId.isEmpty) {
        erreurs['compte'] = 'Le champ compte de trésorerie est obligatoire.';
      } else if (!compteConnu) {
        erreurs['compte'] =
            "La valeur sélectionnée pour le champ compte de trésorerie n'existe pas.";
      } else if (mode != null && mode.isNotEmpty && typeDuCompte != null && typeDuCompte != mode) {
        erreurs['mode'] = 'Le mode de paiement ne correspond pas au type du compte de trésorerie choisi.';
      }
    }
    // Ticket DEP6 (DEP-Q1) — le centre de coût est OBLIGATOIRE (`cost_center_id` `required|exists`).
    if (centreCoutId == null || centreCoutId.isEmpty) {
      erreurs['centre'] = messageCentreObligatoire;
    } else if (!centreConnu) {
      erreurs['centre'] = "La valeur sélectionnée pour le champ centre de coût n'existe pas.";
    }
    if (beneficiaire.runes.length > 150) {
      erreurs['beneficiaire'] = 'Le champ bénéficiaire ne doit pas dépasser 150 caractères.';
    }
    if (lignes.isEmpty) {
      erreurs['lignes'] = 'Ajoutez au moins une ligne à la dépense.';
    }
    for (final (i, l) in lignes.indexed) {
      if (l.libelle.trim().isEmpty) {
        erreurs['ligne.$i.libelle'] = 'Le champ libellé de la ligne est obligatoire.';
      } else if (l.libelle.runes.length > 255) {
        erreurs['ligne.$i.libelle'] = 'Le champ libellé de la ligne ne doit pas dépasser 255 caractères.';
      }
      final compte = l.compteChargeId;
      if (compte == null || compte.isEmpty) {
        erreurs['ligne.$i.compte'] = 'Le champ compte de charge de la ligne est obligatoire.';
      } else if (!comptesDeChargeConnus.contains(compte)) {
        erreurs['ligne.$i.compte'] = "Le compte de charge de la ligne n'existe pas au plan comptable (classe 6).";
      }
      final texte = l.montant.trim();
      final valeur = int.tryParse(texte);
      if (texte.isEmpty) {
        erreurs['ligne.$i.montant'] = 'Le champ montant de la ligne est obligatoire.';
      } else if (valeur == null) {
        erreurs['ligne.$i.montant'] = 'Le champ montant de la ligne doit être un nombre entier.';
      } else if (valeur < 1) {
        erreurs['ligne.$i.montant'] = 'Le champ montant de la ligne doit être au moins égal à 1.';
      }
    }
    return erreurs;
  }

  /// Le TOTAL d'une saisie : la SOMME des lignes lisibles (une ligne illisible compte 0), en francs entiers — le
  /// « Total : N FCFA » en direct de la modale (`getTotalProperty()` du web).
  static int total(List<LigneSaisie> lignes) {
    var somme = 0;
    for (final l in lignes) {
      final v = double.tryParse(l.montant.trim());
      if (v != null && v.isFinite) somme += v.round();
    }
    return somme;
  }

  /// Le libellé-RÉSUMÉ de l'en-tête (`Expense::resume()` du web, mot pour mot) : le libellé de la ligne seule, sinon
  /// « premier libellé (+N autre(s)) ».
  static String resume(List<String> libelles) {
    if (libelles.isEmpty) return '';
    final reste = libelles.length - 1;
    return reste <= 0 ? libelles.first : '${libelles.first} (+$reste ${reste == 1 ? 'autre' : 'autres'})';
  }

  /// Enregistre une dépense (création, ou modification de [idEnModification]) : l'en-tête ET ses lignes dans UNE SEULE
  /// transaction, en attente d'envoi.
  ///
  /// ⚠️ **LES MÊMES BORNES QUE LE WEB, APPLIQUÉES ICI** ([valider]) ; puis, en modification, les refus de
  /// `SaisieDepenseAction::modifier()` : dépense archivée, exercice clos (motif R4), et dépense comptabilisée
  /// (`accounting_entry_id` servi par le tirage) : IMMUABLE, sous le champ « formulaire » comme au web.
  ///
  /// Une modification repasse l'en-tête en `pending` à l'instant de la saisie (`updatedAt`) ; il part entier avec ses
  /// lignes (les anciennes sont REMPLACÉES), le serveur le rejoue. Son ancien refus éventuel est effacé : il portait sur
  /// une version dépassée.
  Future<Expense> enregistrer({
    required DateTime? date,
    required String? modePaiement,
    required String? compteTresorerieId,
    required List<LigneSaisie> lignes,
    String? centreCoutId,
    String? fournisseurId,
    String beneficiaire = '',
    String? idEnModification,
    bool aCredit = false,
    /// Ticket #48 — chemin absolu local du justificatif copié ; ticket AC-3 : envoyé au serveur une fois la dépense acceptée.
    String? receiptLocalPath,
  }) async {
    final existante = idEnModification == null
        ? null
        : await (_db.select(
            _db.expenses,
          )..where((t) => t.id.equals(idEnModification))).getSingleOrNull();
    if (idEnModification != null && existante == null) {
      throw DepenseRefusee({'formulaire': 'Dépense introuvable sur ce poste.'});
    }

    final compte = compteTresorerieId == null || compteTresorerieId.isEmpty
        ? null
        : await (_db.select(_db.treasuryAccounts)
                ..where((t) => t.id.equals(compteTresorerieId)))
              .getSingleOrNull();
    final planDeCharge = {for (final c in await comptesDeCharge()) c.id: c};
    // Ticket DEP7 — un règlement « À crédit » n'a de sens qu'avec un fournisseur choisi (la modale réinitialise sinon).
    final credit = aCredit && fournisseurId != null && fournisseurId.isNotEmpty;
    final centreConnu = centreCoutId == null || centreCoutId.isEmpty
        ? false
        : await (_db.select(_db.costCenters)..where((c) => c.id.equals(centreCoutId))).getSingleOrNull() != null;

    final erreurs = valider(
      date: date,
      mode: modePaiement,
      compteTresorerieId: compteTresorerieId,
      typeDuCompte: compte?.type,
      compteConnu: compte != null,
      beneficiaire: beneficiaire,
      lignes: lignes,
      comptesDeChargeConnus: planDeCharge.keys.toSet(),
      centreCoutId: centreCoutId,
      centreConnu: centreConnu,
      fournisseurId: fournisseurId,
      aCredit: aCredit,
    );
    if (erreurs.isNotEmpty) throw DepenseRefusee(erreurs);

    final jour = DateTime(date!.year, date.month, date.day);
    final maintenant = HeureBenin.versInstant(HeureBenin.maintenant());
    final entiers = [for (final l in lignes) int.parse(l.montant.trim())];
    final totalSaisi = entiers.fold<int>(0, (a, b) => a + b);
    final resumeLibelle = resume([for (final l in lignes) l.libelle.trim()]);
    final premier = planDeCharge[lignes.first.compteChargeId]!;
    // « Catégorie » conservée pour les serveurs non migrés : le compte de la première ligne.
    final categorie = '${premier.code} - ${premier.label}';
    final beneficiaireNet = beneficiaire.trim().isEmpty ? null : beneficiaire.trim();

    Future<void> ecrireLesLignes(String idDepense) async {
      await (_db.delete(_db.expenseLines)..where((l) => l.expenseId.equals(idDepense))).go();
      for (final (i, l) in lignes.indexed) {
        await _db.into(_db.expenseLines).insert(
          ExpenseLinesCompanion.insert(
            id: l.id ?? _uuid.v4(),
            expenseId: idDepense,
            position: Value(i),
            label: l.libelle.trim(),
            chargeAccountId: l.compteChargeId!,
            amount: entiers[i].toDouble(),
          ),
        );
      }
    }

    if (existante != null) {
      // Un ARCHIVAGE REFUSÉ par le serveur (`conflict`) laisse la dépense active là-bas : la modifier la garde active.
      final archivageRefuse =
          !existante.isActive && existante.syncStatus == SyncStatus.conflict;
      if (!existante.isActive && !archivageRefuse) {
        throw DepenseRefusee({'formulaire': messageArchivee});
      }
      // 🔴→✅ Ticket EX6 (EF7) — `SaisieDepenseAction::modifier` : une dépense d'un exercice CLOS ne se modifie plus
      // (motif R4 de sa date d'origine), et ne passe pas non plus dans un exercice clos (motif R4 de la nouvelle date).
      await _exercice.refuser(
        existante.expenseDate,
        regle: RegleExercice.closSeulement,
      );
      await _exercice.refuser(jour, regle: RegleExercice.closSeulement);
      // 🔴→✅ Ticket DEP1 — UNE DÉPENSE COMPTABILISÉE EST IMMUABLE (`SaisieDepenseAction::modifier`, même message).
      if (existante.accountingEntryId != null) {
        throw DepenseRefusee({'formulaire': messageDejaComptabilisee});
      }
      // Ticket DEP7 — une reprise de l'ancien (sans pièce) ne reçoit jamais de pièce rétroactive : ni crédit ni dette.
      if (credit) {
        throw DepenseRefusee({'formulaire': messageCreditSansPiece});
      }

      await _db.transaction(() async {
        await (_db.update(
          _db.expenses,
        )..where((t) => t.id.equals(existante.id))).write(
          ExpensesCompanion(
            expenseDate: Value(jour),
            label: Value(resumeLibelle),
            category: Value(categorie),
            amount: Value(totalSaisi.toDouble()),
            treasuryAccountId: Value(compteTresorerieId),
            paymentMode: Value(modePaiement),
            costCenterId: Value(centreCoutId),
            supplierId: Value(fournisseurId == null || fournisseurId.isEmpty ? null : fournisseurId),
            beneficiary: Value(beneficiaireNet),
            onCredit: const Value(false),
            ecritureRefus: const Value(null),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: Value(maintenant),
            receiptLocalPath: Value(receiptLocalPath),
            // Ticket AC-3 — un NOUVEAU fichier est à envoyer ; le même fichier, déjà reçu du serveur, n'est pas renvoyé.
            receiptSent: Value(receiptLocalPath == existante.receiptLocalPath && existante.receiptSent),
          ),
        );
        await ecrireLesLignes(existante.id);
        await _effacerRefus(existante.id);
      });
      return _lire(existante.id);
    }

    // 🔴→✅ Ticket EX6 (EF7) — `SaisieDepenseAction::creer` : exercice clos refusé avant tout effet, puis l'écriture
    // Débit 6 / Crédit 5 datée de la dépense (`record()`, filet R2 compris) refuse un jour qu'aucun exercice ne couvre.
    await _exercice.refuser(jour);

    final id = _uuid.v4();
    // 🔴→✅ Ticket DEP4 — UNE SEULE TRANSACTION : l'en-tête et ses lignes partent ensemble ou pas du tout (la file
    // d'envoi lit l'en-tête `pending`, jamais une dépense sans ses lignes).
    await _db.transaction(() async {
      await _db
          .into(_db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: id,
              deviceId: _deviceId,
              syncStatus: const Value(SyncStatus.pending),
              updatedAt: maintenant,
              expenseDate: jour,
              label: resumeLibelle,
              category: categorie,
              amount: totalSaisi.toDouble(),
              // Ticket DEP7 — à crédit : AUCUNE trésorerie ni mode (la dette crédite le 401 au serveur), `en_attente` jusqu'au
              // règlement de la dette ; payée comptant : `payee`, comme avant.
              treasuryAccountId: Value(credit ? null : compteTresorerieId),
              paymentMode: Value(credit ? null : modePaiement),
              costCenterId: Value(centreCoutId),
              supplierId: Value(fournisseurId == null || fournisseurId.isEmpty ? null : fournisseurId),
              beneficiary: Value(beneficiaireNet),
              onCredit: Value(credit),
              status: Value(credit ? 'en_attente' : 'payee'),
              createdBy: Value(_auteurId?.call()),
              receiptLocalPath: Value(receiptLocalPath),
            ),
          );
      await ecrireLesLignes(id);
    });

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
          ecritureRefus: const Value(null),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(HeureBenin.versInstant(HeureBenin.maintenant())),
        ),
      );
      await _effacerRefus(id);
    });
  }

  /// Les refus de `editExpense()` du web AVANT d'ouvrir la modale : exercice clos (le motif R4 de la date), dépense
  /// comptabilisée (IMMUABLE : [messageDejaComptabilisee]), dépense archivée ([messageArchivee]). `null` : modifiable.
  Future<String?> refusAvantModification(Expense d) async {
    try {
      await _exercice.refuser(d.expenseDate, regle: RegleExercice.closSeulement);
    } on RefusExercice catch (e) {
      return e.motif;
    }
    if (d.accountingEntryId != null) return messageDejaComptabilisee;
    if (!d.isActive && d.syncStatus != SyncStatus.conflict) return messageArchivee;
    return null;
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
