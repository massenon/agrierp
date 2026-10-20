import 'dart:io';

import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/saisie_depenses_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'fidelite_libelles_test.dart' show chainesDe;
import 'php_laravel.dart';

/// « Saisie des Dépenses » au poste — tickets F0.18, U13 et 🔴→✅ U14 (l'écran sur son Blade, modifier et archiver).
///
/// ⚠️⚠️ Ce que ces tests protègent :
/// 1. **Les règles du web sont appliquées AVANT d'écrire**, avec ses messages, sous leur champ (`lang/fr/validation.php`
///    et `SaisieDepenseAction`) : un refus qui n'arrive qu'à la synchronisation laisse l'utilisateur sans recours.
/// 2. **Le poste ne prétend rien décaisser** : il n'a ni comptabilité ni solde faisant foi.
/// 3. **L'écran est celui du Blade** (lu dans `saisie-depenses.blade.php`, jamais recopié ici) : en-tête, cartes,
///    formulaire « Nouvelle Dépense » / « Modifier la Dépense », recherche, filtre de statut, tableau, actions
///    « Modifier » et « Archiver » (modale `x-modal-confirm-delete`), toasts.
/// 4. **La liste est celle du web** : parité EXÉCUTÉE avec `SaisieDepenses::getExpensesProperty()` (recherche `LIKE`,
///    statut, ordre `expense_date` décroissant puis identifiant).
void main() {
  late AppDatabase db;
  late DepensesRepository depot;

  const compteId = 'cccccccc-1111-4111-8111-cccccccccccc';
  const banqueId = 'cccccccc-2222-4222-8222-cccccccccccc';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = DepensesRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.treasuryAccounts)
        .insert(
          TreasuryAccountsCompanion.insert(
            id: compteId,
            label: 'Caisse Physique',
            accountCode: const Value('531'),
            balance: const Value(500000),
          ),
        );
    await db
        .into(db.treasuryAccounts)
        .insert(
          TreasuryAccountsCompanion.insert(
            id: banqueId,
            label: 'Banque',
            accountCode: const Value('521'),
            balance: const Value(1250000),
          ),
        );

    for (final libelle in ['601 - Aliments', '605 - Énergie']) {
      await db
          .into(db.expenseCategories)
          .insert(ExpenseCategoriesCompanion.insert(label: libelle));
    }
  });

  tearDown(() async => db.close());

  /// Une dépense telle que le tirage la dépose (U13, U14) : `synced`, `device_id` d'origine.
  Future<void> depenseDuServeur(
    String id,
    DateTime date,
    double montant, {
    String? libelle,
    bool actif = true,
    SyncStatus statut = SyncStatus.synced,
    String statutWeb = 'payee',
    String? ecriture,
    String categorie = '601 - Aliments',
  }) => db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          id: id,
          deviceId: 'serveur',
          syncStatus: Value(statut),
          updatedAt: DateTime(2026, 8, 20),
          expenseDate: date,
          label: libelle ?? 'Dépense $id',
          category: categorie,
          amount: montant,
          treasuryAccountId: compteId,
          isActive: Value(actif),
          status: Value(statutWeb),
          accountingEntryId: Value(ecriture),
        ),
      );

  Future<Expense> lire(String id) =>
      (db.select(db.expenses)..where((t) => t.id.equals(id))).getSingle();

  Future<Map<String, String>> refus(Future<Object?> Function() geste) async {
    try {
      await geste();
    } on DepenseRefusee catch (e) {
      return e.erreurs;
    }
    return const {};
  }

  // ── Le dépôt : les règles du web, appliquées au poste ──────────────────

  group('dépôt', () {
    test('une dépense valide est enregistrée en attente d envoi, « payee », sans écriture connue', () async {
      final depense = await depot.enregistrer(
        date: DateTime(2026, 8, 19),
        libelle: 'Sac de provende ponte',
        categorie: '601 - Aliments',
        montant: 25000,
        compteTresorerieId: compteId,
      );

      expect(depense.syncStatus, SyncStatus.pending);
      expect(depense.amount, 25000);
      expect(depense.deviceId, 'poste-test');
      expect(depense.status, 'payee');
      expect(depense.accountingEntryId, isNull);
      expect(depense.isActive, isTrue);
    });

    test('⚠️ U14 — chaque champ reçoit le message du web (`lang/fr/validation.php`)', () async {
      Future<Map<String, String>> saisie({
        String libelle = 'Carburant',
        String? categorie = '601 - Aliments',
        String montant = '25000',
        String? compte = compteId,
      }) => refus(
        () => depot.enregistrerSaisie(
          date: DateTime(2026, 8, 19),
          libelle: libelle,
          categorie: categorie,
          montant: montant,
          compteTresorerieId: compte,
        ),
      );

      expect(await saisie(libelle: '   ', categorie: null, montant: '', compte: null), {
        'libelle': 'Le champ libellé est obligatoire.',
        'categorie': 'Le champ catégorie est obligatoire.',
        'montant': 'Le champ montant est obligatoire.',
        'compte': 'Le champ compte de trésorerie est obligatoire.',
      });
      expect(await saisie(libelle: 'x' * 256), {'libelle': 'Le champ libellé ne doit pas dépasser 255 caractères.'});
      expect(await saisie(montant: 'cent'), {'montant': 'Le champ montant doit être un nombre.'});
      expect(await saisie(montant: '0.5'), {'montant': 'Le champ montant doit être au moins égal à 1.'});
      expect(await saisie(montant: '0'), {'montant': 'Le champ montant doit être au moins égal à 1.'});
      expect(await saisie(categorie: '699 - Inconnu'), {
        'categorie': "La valeur du champ catégorie n'est pas autorisée.",
      });
      expect(await saisie(compte: 'dddddddd-0000-4000-8000-000000000000'), {
        'compte': "La valeur sélectionnée pour le champ compte de trésorerie n'existe pas.",
      });
      expect(await db.select(db.expenses).get(), isEmpty, reason: 'rien n est écrit');
      expect(await saisie(montant: '1'), isEmpty, reason: '`min:1` : un franc est accepté');
    });

    test(
      '⚠️⚠️ le poste ne décaisse PAS le solde de trésorerie : ce serait un chiffre qui n engage rien',
      () async {
        await depot.enregistrer(
          date: DateTime(2026, 8, 19),
          libelle: 'Sac de provende',
          categorie: '601 - Aliments',
          montant: 25000,
          compteTresorerieId: compteId,
        );

        final compte = await (db.select(
          db.treasuryAccounts,
        )..where((t) => t.id.equals(compteId))).getSingle();

        expect(compte.balance, 500000, reason: 'le decaissement reel a lieu au serveur, a la reception');
      },
    );

    test('le total du mois ne compte que les dépenses de ce mois', () async {
      for (final (jour, montant) in [(5, 10000.0), (19, 25000.0)]) {
        await depot.enregistrer(
          date: DateTime(2026, 8, jour),
          libelle: 'Depense $jour',
          categorie: '601 - Aliments',
          montant: montant,
          compteTresorerieId: compteId,
        );
      }
      await depot.enregistrer(
        date: DateTime(2026, 7, 12),
        libelle: 'Mois precedent',
        categorie: '601 - Aliments',
        montant: 99000,
        compteTresorerieId: compteId,
      );

      expect(await depot.totalDuMois(DateTime(2026, 8, 19)), 35000);
    });

    test(
      "⚠️ U13/U14 — liste : celle du web (archivées exclues, date décroissante puis identifiant) ; refusée listée",
      () async {
        const web = 'aaaaaaaa-0000-4000-8000-000000000001';
        const archivee = 'aaaaaaaa-0000-4000-8000-000000000002';
        const refusee = 'aaaaaaaa-0000-4000-8000-000000000003';
        const memeJourB = 'aaaaaaaa-0000-4000-8000-00000000000b';
        const memeJourA = 'aaaaaaaa-0000-4000-8000-00000000000a';
        await depenseDuServeur(web, DateTime(2026, 8, 3), 12000);
        await depenseDuServeur(archivee, DateTime(2026, 8, 4), 70000, actif: false);
        await depenseDuServeur(refusee, DateTime(2026, 8, 5), 9000, statut: SyncStatus.conflict);
        await depenseDuServeur(memeJourB, DateTime(2026, 8, 3), 1000);
        await depenseDuServeur(memeJourA, DateTime(2026, 8, 3), 1000);
        await db.into(db.syncConflicts).insert(
          SyncConflictsCompanion.insert(
            id: 'expenses:$refusee',
            sourceTable: 'expenses',
            recordId: refusee,
            reason: "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 05/08/2026.",
            detectedAt: DateTime(2026, 8, 6),
          ),
        );

        final liste = await depot.depenses();
        expect(
          [for (final l in liste) l.depense.id],
          [refusee, web, memeJourA, memeJourB],
          reason: 'même jour : identifiant croissant (`orderBy(\'id\')`, U14)',
        );
        expect(
          liste.first.motifRefus,
          "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 05/08/2026.",
        );
        expect(liste[1].motifRefus, isNull);
        // 12 000 + 1 000 + 1 000 ; ni l'archivée (70 000), ni la refusée (9 000).
        expect(await depot.totalDuMois(DateTime(2026, 8, 19)), 14000);
      },
    );

    test('U14 — recherche comme `LIKE` sous la collation du serveur, et filtre de statut', () async {
      await depenseDuServeur('aaaaaaaa-0000-4000-8000-000000000001', DateTime(2026, 8, 3), 1, libelle: 'Électricité SBEE');
      await depenseDuServeur('aaaaaaaa-0000-4000-8000-000000000002', DateTime(2026, 8, 2), 1, libelle: 'Carburant 10%');
      await depenseDuServeur(
        'aaaaaaaa-0000-4000-8000-000000000003',
        DateTime(2026, 8, 1),
        1,
        libelle: 'carburant groupe',
        statutWeb: 'en_attente',
      );

      Future<List<String>> chercher(String r, {String statut = ''}) async => [
        for (final l in await depot.depenses(recherche: r, statut: statut)) l.depense.label,
      ];

      expect(await chercher('ELECTRI'), ['Électricité SBEE'], reason: 'sans casse ni accents (utf8mb4_unicode_ci)');
      expect(await chercher('électricité'), ['Électricité SBEE']);
      expect(await chercher('CARBURANT'), ['Carburant 10%', 'carburant groupe']);
      expect(await chercher('c_rburant g'), ['carburant groupe'], reason: '`_` : un caractère quelconque');
      expect(await chercher('10%'), ['Carburant 10%']);
      expect(await chercher('0'), hasLength(3), reason: '`when(\'0\')` est faux en PHP : pas de filtre');
      expect(await chercher('', statut: 'En attente'), ['carburant groupe']);
      expect(await chercher('carb', statut: 'Payée'), ['Carburant 10%']);
      expect(await chercher('zzz'), isEmpty);
    });

    test('⚠️ U14 / EX5 — modifier une dépense comptabilisée : libellé oui ; date (D-U14-1), montant, compte de '
        'charge, compte de trésorerie non (message du web sous « Montant »)', () async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000021';
      await depenseDuServeur(id, DateTime(2026, 8, 3), 25000, ecriture: 'eeeeeeee-0000-4000-8000-000000000001');

      Future<Map<String, String>> modifier({
        DateTime? date,
        String libelle = 'Dépense corrigée',
        String categorie = '601 - Aliments',
        double montant = 25000,
        String compte = compteId,
      }) => refus(
        () => depot.enregistrer(
          date: date ?? DateTime(2026, 8, 3),
          libelle: libelle,
          categorie: categorie,
          montant: montant,
          compteTresorerieId: compte,
          idEnModification: id,
        ),
      );

      for (final interdit in [
        // 🔴→✅ EX5 (D-U14-1) : la date changée seule déplaçait la dépense, son écriture restait au 03/08.
        () => modifier(date: DateTime(2026, 8, 4)),
        () => modifier(montant: 30000),
        () => modifier(categorie: '605 - Énergie'),
        () => modifier(compte: banqueId),
      ]) {
        expect(await interdit(), {'montant': DepensesRepository.messageDejaComptabilisee});
      }
      expect((await lire(id)).syncStatus, SyncStatus.synced, reason: 'rien n est écrit');

      expect(await modifier(), isEmpty);
      final d = await lire(id);
      expect(d.label, 'Dépense corrigée');
      expect(d.expenseDate, DateTime(2026, 8, 3));
      expect(d.syncStatus, SyncStatus.pending, reason: 'la modification part au serveur');
      expect(d.deviceId, 'serveur', reason: 'l origine de la saisie est gardée');
    });

    test('U14 — une dépense SANS écriture connue change de montant et de compte (le web l accepte)', () async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000022';
      await depenseDuServeur(id, DateTime(2026, 8, 3), 25000);

      await depot.enregistrer(
        date: DateTime(2026, 8, 3),
        libelle: 'Provende',
        categorie: '605 - Énergie',
        montant: 30000,
        compteTresorerieId: banqueId,
        idEnModification: id,
      );

      final d = await lire(id);
      expect((d.amount, d.category, d.treasuryAccountId), (30000.0, '605 - Énergie', banqueId));
    });

    test('⚠️ U14 — une dépense archivée ne se modifie plus ; un archivage est idempotent', () async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000023';
      await depenseDuServeur(id, DateTime(2026, 8, 3), 25000);

      await depot.archiver(id);
      final archivee = await lire(id);
      expect((archivee.isActive, archivee.syncStatus), (false, SyncStatus.pending));

      expect(
        await refus(
          () => depot.enregistrer(
            date: DateTime(2026, 8, 3),
            libelle: 'X',
            categorie: '601 - Aliments',
            montant: 25000,
            compteTresorerieId: compteId,
            idEnModification: id,
          ),
        ),
        {'montant': DepensesRepository.messageArchivee},
      );
      expect(await depot.depenses(), isEmpty, reason: 'archivée : hors de la liste, comme au web');
    });

    test('U14 — corriger une saisie refusée efface son ancien refus ; modifier un ARCHIVAGE refusé la réactive', () async {
      const refusee = 'aaaaaaaa-0000-4000-8000-000000000024';
      const archivageRefuse = 'aaaaaaaa-0000-4000-8000-000000000025';
      await depenseDuServeur(refusee, DateTime(2026, 8, 3), 25000, statut: SyncStatus.conflict);
      await depenseDuServeur(archivageRefuse, DateTime(2026, 8, 3), 5000, statut: SyncStatus.conflict, actif: false);
      for (final id in [refusee, archivageRefuse]) {
        await db.into(db.syncConflicts).insert(
          SyncConflictsCompanion.insert(
            id: 'expenses:$id',
            sourceTable: 'expenses',
            recordId: id,
            reason: 'Refus',
            detectedAt: DateTime(2026, 8, 6),
          ),
        );
      }
      expect([for (final l in await depot.depenses()) l.depense.id], containsAll([refusee, archivageRefuse]));

      for (final id in [refusee, archivageRefuse]) {
        await depot.enregistrer(
          date: DateTime(2026, 8, 3),
          libelle: 'Corrigée',
          categorie: '601 - Aliments',
          montant: 4000,
          compteTresorerieId: compteId,
          idEnModification: id,
        );
        final d = await lire(id);
        expect((d.syncStatus, d.isActive), (SyncStatus.pending, true), reason: id);
      }
      expect(await db.select(db.syncConflicts).get(), isEmpty);
    });
  });

  // ── Lu dans le Blade et dans le composant (sans PHP) ───────────────────

  group('lu dans le web', () {
    String? lireLaravel(String relatif) {
      final f = File('$dossierLaravel/$relatif');
      return f.existsSync() ? f.readAsStringSync() : null;
    }

    final blade = lireLaravel('resources/views/livewire/achats/saisie-depenses.blade.php');
    final composant = lireLaravel('app/Livewire/Achats/SaisieDepenses.php');
    final action = lireLaravel('app/Actions/SaisieDepenseAction.php');
    final modale = lireLaravel('resources/views/components/modal-confirm-delete.blade.php');
    final carte = lireLaravel('resources/views/components/kpi-card.blade.php');
    final saut = blade == null || composant == null || action == null || modale == null || carte == null
        ? 'dépôt Laravel absent ($dossierLaravel) : comparaison au web impossible'
        : null;

    final poste = [
      'lib/features/achats/saisie_depenses_screen.dart',
      'lib/features/achats/depenses_repository.dart',
    ].map((f) => chainesDe(File(f).readAsStringSync())).join('\n');

    String html(String s) => s
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    test('⚠️⚠️ chaque texte visible du Blade existe dans l écran du poste', () {
      final b = blade!;
      final textes = <String>{
        for (final m in RegExp(r'<label[^>]*>([^<]+)</label>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'</span>([^<]+)</h2>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'<p class="text-xs text-outline[^"]*">([^<]+)</p>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'</span>([^<]+)\s*</button>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'placeholder="([^"]+)"').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'<option[^>]*>([^<{]+)</option>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'<th[^>]*>([^<]+)</th>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'<x-kpi-card label="([^"]+)"').allMatches(b)) html(m[1]!),
        // Ticket EX7 : une info-bulle CALCULÉE (`title="{{ … }}"`, motif de la date grisée) n'est pas un texte littéral ;
        // `selecteur_exercice_test.dart` la compare à la constante du poste.
        for (final m in RegExp(r'title="([^"{]+)"').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'border-brand-emerald/30">([^<]+)</span>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'border-accent-yellow">([^<]+)</span>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r"editingExpenseId \? '([^']+)' : '([^']+)'").allMatches(b)) ...[
          html(m[1]!),
          html(m[2]!),
        ],
        for (final m in RegExp(r'colspan="6"[^>]*>([^<]+)<').allMatches(b)) html(m[1]!),
      };
      // Repères écrits à la main : le relevé ne doit pas être vide parce qu'une expression a cessé de correspondre.
      expect(
        textes,
        containsAll([
          'Saisie des Dépenses',
          "Enregistrement des charges d'exploitation courantes de la ferme (SYSCOHADA Classe 6).",
          'Dépenses du mois',
          'Charges Fixes',
          'Charges Variables',
          'Nouvelle Dépense',
          'Modifier la Dépense',
          "Enregistrez une charge d'exploitation de trésorerie directe.",
          'Date de la Transaction *',
          'Libellé de la Dépense *',
          'Catégorie de Charges (SYSCOHADA) *',
          'Montant Décaissé (FCFA) *',
          'Compte de Trésorerie Débité *',
          'Reçu / Facture (Photo)',
          'Enregistrer la Dépense',
          'Rechercher...',
          'Tous les statuts',
          'Payée',
          'En attente',
          'Date',
          'Libellé',
          'Montant',
          'Statut',
          'Actions',
          'Modifier',
          'Archiver',
          'Aucune dépense pour le moment.',
          'ex : 25000',
        ]),
      );
      for (final t in textes) {
        // « -- Sélectionner -- » : texte des listes, présent au poste ; les en-têtes `uppercase` s'écrivent en
        // capitales au poste.
        expect(
          poste.contains(t) || poste.contains(t.toUpperCase()),
          isTrue,
          reason: 'texte du Blade absent du poste : « $t »',
        );
      }
    }, skip: saut);

    test('les cartes en attente, la modale d archivage et les toasts sont ceux du web', () {
      final pendingSince = RegExp(r'pending-since="([^"]+)"').allMatches(blade!).map((m) => m[1]!).toSet().single;
      expect(carte!, contains('Disponible après {{ \$pendingSince'));
      expect(SaisieDepensesScreen.legendeEnAttente, 'Disponible après $pendingSince');

      for (final t in ["Confirmer l'archivage", 'sera marqué(e) comme archivé(e) (statut inactif).',
        "Aucune suppression définitive n'est effectuée.", 'Annuler', 'Archiver']) {
        expect(modale!, contains(t));
        expect(poste, contains(t), reason: t);
      }

      for (final t in [DepensesRepository.toastEnregistree, DepensesRepository.toastArchivee]) {
        expect(composant!, contains("'$t'"), reason: 'toast du composant : $t');
      }
    }, skip: saut);

    test('⚠️ les refus de modification sont ceux de `SaisieDepenseAction`, mot pour mot', () {
      String constante(String nom) =>
          RegExp("const $nom = '([^']+)';").firstMatch(action!)![1]!;

      expect(DepensesRepository.messageDejaComptabilisee, constante('MESSAGE_DEJA_COMPTABILISEE'));
      expect(DepensesRepository.messageArchivee, constante('MESSAGE_ARCHIVEE'));
    }, skip: saut);

    test('les colonnes du tableau sont celles du Blade, dans son ordre', () {
      final colonnes = [
        for (final m in RegExp(r'<th[^>]*>([^<]+)</th>').allMatches(blade!)) html(m[1]!).toUpperCase(),
      ];
      expect(colonnes, ['DATE', 'LIBELLÉ', 'CATÉGORIE', 'MONTANT', 'STATUT', 'ACTIONS']);
      final ecran = File('lib/features/achats/saisie_depenses_screen.dart').readAsStringSync();
      final tableau = ecran.substring(ecran.indexOf('Widget _tableau()'));
      final ordre = [for (final c in colonnes) tableau.indexOf("'$c'")];
      expect(ordre.every((p) => p >= 0), isTrue, reason: '$ordre');
      expect(ordre, [...ordre]..sort());
    }, skip: saut);
  });

  // ── Parité exécutée avec le composant Livewire ─────────────────────────

  group('parité exécutée', () {
    final saut = sautSansPhp();

    test('⚠️⚠️ U14 — la liste du poste est celle de `getExpensesProperty()` (recherches, statuts, ordre)', () async {
      final depenses = <Map<String, Object?>>[];
      var n = 0;
      for (final (libelle, jour, statut, actif) in [
        ('Carburant livraison', 3, 'payee', true),
        ('carburant groupe', 3, 'en_attente', true),
        ('CARBURANT 10%', 3, 'payee', true),
        ('Achat provende Lot 3', 2, 'payee', true),
        ('Achat provende Lot 3', 2, 'en_attente', true),
        ('Doublon archivé', 4, 'payee', false),
        ('Eau', 1, 'payee', true),
        ('Transport a_b', 5, 'payee', true),
        ('Transport axb', 5, 'en_attente', true),
      ]) {
        n++;
        depenses.add({
          // Identifiants dans le désordre, pour que l'ordre par identifiant se voie.
          'id': 'aaaaaaaa-0000-4000-8000-${((n * 7919) % 1000).toString().padLeft(12, '0')}',
          'date': '2026-08-${jour.toString().padLeft(2, '0')}',
          'libelle': libelle,
          'statut': statut,
          'actif': actif,
        });
      }
      final recherches = ['', 'carb', 'CARBURANT', '%', '10%', 'a_b', 'lot 3', '0', ' ', 'zzz'];
      final statuts = ['', 'Payée', 'En attente'];

      final sortie = executerPhp('<?php\n$amorceApplication\n$_scriptParite', {
        'compte': compteId,
        'depenses': depenses,
        'recherches': recherches,
        'statuts': statuts,
      }, application: true) as Map<String, dynamic>;

      for (final d in depenses) {
        await depenseDuServeur(
          d['id']! as String,
          DateTime.parse(d['date']! as String),
          1000,
          libelle: d['libelle']! as String,
          statutWeb: d['statut']! as String,
          actif: d['actif']! as bool,
        );
      }
      var comparaisons = 0;
      for (final r in recherches) {
        for (final s in statuts) {
          final web = (sortie['$r|$s'] as List).cast<String>();
          final ici = [for (final l in await depot.depenses(recherche: r, statut: s)) l.depense.id];
          expect(ici, web, reason: 'recherche « $r », statut « $s »');
          comparaisons++;
        }
      }
      expect(comparaisons, 30);
      expect((sortie['carb|'] as List), hasLength(3), reason: 'témoin : trois carburants actifs');
    }, skip: saut);
  });

  // ── L'écran ────────────────────────────────────────────────────────────

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: SaisieDepensesScreen(depot: depot)));
      await tester.pumpAndSettle();
    }

    double y(WidgetTester tester, String texte) => tester.getTopLeft(find.text(texte).first).dy;

    testWidgets("U14 — l'ordre des sections suit le Blade", (tester) async {
      await afficher(tester);

      final positions = [
        y(tester, 'Saisie des Dépenses'),
        y(tester, "Enregistrement des charges d'exploitation courantes de la ferme (SYSCOHADA Classe 6)."),
        y(tester, 'DÉPENSES DU MOIS'),
        y(tester, 'Nouvelle Dépense'),
        y(tester, "Enregistrez une charge d'exploitation de trésorerie directe."),
        y(tester, 'DATE DE LA TRANSACTION *'),
        y(tester, 'CATÉGORIE DE CHARGES (SYSCOHADA) *'),
        y(tester, 'COMPTE DE TRÉSORERIE DÉBITÉ *'),
        y(tester, 'Enregistrer la Dépense'),
        y(tester, 'Tous les statuts'),
        y(tester, 'DATE'),
        y(tester, 'Aucune dépense pour le moment.'),
      ];
      expect(positions, equals([...positions]..sort()));
      // `md:grid-cols-2` : Date et Libellé côte à côte, Catégorie et Montant, Compte et Reçu.
      expect(y(tester, 'DATE DE LA TRANSACTION *'), y(tester, 'LIBELLÉ DE LA DÉPENSE *'));
      expect(y(tester, 'COMPTE DE TRÉSORERIE DÉBITÉ *'), y(tester, 'REÇU / FACTURE (PHOTO)'));
      expect(find.text('Indicateurs de performance'), findsNothing, reason: 'le Blade n a pas ce titre');
    });

    testWidgets('U14 — cartes du Blade : « … FCFA », deux cartes « en attente » maïs puis bleue', (tester) async {
      await depenseDuServeur('aaaaaaaa-0000-4000-8000-000000000031', HeureBenin.aujourdhui(), 12500);
      await afficher(tester);

      expect(
        find.descendant(of: find.byKey(const Key('kpi-Dépenses du mois')), matching: find.text('12 500 FCFA')),
        findsOneWidget,
      );
      expect(find.text('Disponible après Aucun champ Fixe/Variable dans le formulaire source'), findsNWidgets(2));
      Color lisere(String libelle) => tester.widget<CarteKpi>(find.byKey(Key('kpi-$libelle'))).couleurLisere;
      expect(lisere('Charges Fixes'), const Color(0xFFFFD55F), reason: '`maize`');
      expect(lisere('Charges Variables'), const Color(0xFF2563EB), reason: '`blue`');
    });

    testWidgets('U14 — options du compte : « libellé (solde FCFA) » comme le Blade', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('liste-compte')));
      await tester.pumpAndSettle();

      expect(find.text('Caisse Physique (500 000 FCFA)'), findsWidgets);
      expect(find.text('Banque (1 250 000 FCFA)'), findsWidgets);
    });

    testWidgets('⚠️ U14 — erreurs sous leur champ, messages du web, rien n est écrit', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.pumpAndSettle();

      expect(find.text('Le champ libellé est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ catégorie est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ montant est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ compte de trésorerie est obligatoire.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('erreur-libelle'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const Key('champ-libelle'))).dy),
        reason: 'sous le champ, comme `@error` du Blade',
      );
      expect(await db.select(db.expenses).get(), isEmpty);
    });

    testWidgets('U14 — une saisie complète : toast du web, formulaire remis à neuf, compte gardé, ligne « À envoyer »', (
      tester,
    ) async {
      await afficher(tester);

      await tester.enterText(find.byKey(const Key('champ-libelle')), 'Sac de provende ponte');
      await tester.enterText(find.byKey(const Key('champ-montant')), '25000');
      await tester.tap(find.byKey(const Key('liste-categorie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('601 - Aliments').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('liste-compte')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caisse Physique (500 000 FCFA)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.pumpAndSettle();

      expect(find.text('Dépense enregistrée avec succès.'), findsOneWidget);
      expect(find.text('Sac de provende ponte'), findsOneWidget, reason: 'dans le tableau');
      expect(find.text('25 000 FCFA'), findsWidgets);
      expect(find.text('À envoyer'), findsOneWidget);
      expect(find.text('Payée'), findsWidgets, reason: 'badge du Blade : le serveur la créera `payee`');
      expect(tester.widget<TextField>(find.byKey(const Key('champ-libelle'))).controller!.text, isEmpty);
      expect(
        tester.widget<DropdownButton<String>>(find.byKey(const Key('liste-compte'))).value,
        compteId,
        reason: '`reset()` du web ne vide pas le compte de trésorerie',
      );
      expect(tester.widget<DropdownButton<String>>(find.byKey(const Key('liste-categorie'))).value, isNull);

      await tester.pump(ToastAgri.duree);
      await tester.pumpAndSettle();
    });

    testWidgets('⚠️ U14 — « Modifier » : formulaire « Modifier la Dépense » rempli, refus du web sous « Montant »', (
      tester,
    ) async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000041';
      await depenseDuServeur(
        id,
        DateTime(2026, 8, 3),
        25000,
        libelle: 'Carburant groupe',
        ecriture: 'eeeeeeee-0000-4000-8000-000000000001',
      );
      await afficher(tester);

      await tester.tap(find.byKey(const Key('depense-modifier-$id')));
      await tester.pumpAndSettle();

      expect(find.text('Modifier la Dépense'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('champ-libelle'))).controller!.text, 'Carburant groupe');
      expect(tester.widget<TextField>(find.byKey(const Key('champ-montant'))).controller!.text, '25000');
      expect(find.text('03/08/2026'), findsWidgets);

      await tester.enterText(find.byKey(const Key('champ-montant')), '30000');
      await tester.tap(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.pumpAndSettle();
      expect(find.text(DepensesRepository.messageDejaComptabilisee), findsOneWidget);
      expect((await lire(id)).amount, 25000);

      await tester.enterText(find.byKey(const Key('champ-montant')), '25000');
      await tester.enterText(find.byKey(const Key('champ-libelle')), 'Carburant groupe électrogène');
      await tester.tap(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.pumpAndSettle();

      expect(find.text('Nouvelle Dépense'), findsOneWidget, reason: 'retour à la saisie après enregistrement');
      expect((await lire(id)).label, 'Carburant groupe électrogène');
      expect((await lire(id)).syncStatus, SyncStatus.pending);
      await tester.pump(ToastAgri.duree);
      await tester.pumpAndSettle();
    });

    testWidgets('⚠️ U14 — « Archiver » : modale du web, puis archivage en attente d envoi et toast d avertissement', (
      tester,
    ) async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000051';
      await depenseDuServeur(id, DateTime(2026, 8, 3), 25000, libelle: 'Doublon carburant');
      await afficher(tester);

      await tester.tap(find.byKey(const Key('depense-archiver-$id')));
      await tester.pumpAndSettle();
      expect(find.text("Confirmer l'archivage"), findsOneWidget);
      expect(
        find.text(
          'Doublon carburant sera marqué(e) comme archivé(e) (statut inactif). '
          "Aucune suppression définitive n'est effectuée.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect((await lire(id)).isActive, isTrue, reason: 'annuler ne touche à rien');

      await tester.tap(find.byKey(const Key('depense-archiver-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('archivage-depense-confirmer')));
      await tester.pumpAndSettle();

      final d = await lire(id);
      expect((d.isActive, d.syncStatus), (false, SyncStatus.pending));
      expect(find.text('Dépense archivée — trésorerie réintégrée et charge annulée.'), findsOneWidget);
      expect(find.text('Doublon carburant'), findsNothing, reason: 'hors de la liste, comme au web');
      expect(find.text('Aucune dépense pour le moment.'), findsOneWidget);
      await tester.pump(ToastAgri.duree);
      await tester.pumpAndSettle();
    });

    testWidgets('U14 — « Rechercher... » attend 300 ms ; le filtre de statut s applique aussitôt', (tester) async {
      await depenseDuServeur('aaaaaaaa-0000-4000-8000-000000000061', DateTime(2026, 8, 3), 1, libelle: 'Électricité');
      await depenseDuServeur(
        'aaaaaaaa-0000-4000-8000-000000000062',
        DateTime(2026, 8, 2),
        1,
        libelle: 'Carburant',
        statutWeb: 'en_attente',
      );
      await afficher(tester);
      expect(find.text('En attente'), findsWidgets, reason: 'badge maïs du Blade');

      await tester.enterText(find.byKey(const Key('depenses-recherche')), 'electri');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Carburant'), findsOneWidget, reason: 'pas encore : 300 ms');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(find.text('Carburant'), findsNothing);
      expect(find.text('Électricité'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('depenses-recherche')), '');
      await tester.pump(SaisieDepensesScreen.delaiRecherche);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('depenses-filtre-statut')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('En attente').last);
      await tester.pumpAndSettle();
      expect(find.text('Électricité'), findsNothing);
      expect(find.text('Carburant'), findsOneWidget);
    });

    testWidgets('➕ une saisie refusée montre son état et le motif du serveur, mot pour mot', (tester) async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000071';
      await depenseDuServeur(id, DateTime(2026, 8, 3), 1, statut: SyncStatus.conflict);
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'expenses:$id',
          sourceTable: 'expenses',
          recordId: id,
          reason: DepensesRepository.messageDejaComptabilisee,
          detectedAt: DateTime(2026, 8, 6),
        ),
      );
      await afficher(tester);

      expect(find.text('Refusée'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('depense-motif-$id'))).data,
        DepensesRepository.messageDejaComptabilisee,
      );
    });

    testWidgets('⚠️ le champ justificatif annonce sa limite au lieu de mentir', (tester) async {
      await afficher(tester);

      expect(find.byKey(const Key('depense-recu-limite')), findsOneWidget);
      expect(find.textContaining('ne transporte aucun fichier'), findsOneWidget);
    });
  });

  // ── L'accès ────────────────────────────────────────────────────────────

  test("⚠️⚠️ seul l'admin atteint la saisie des dépenses — conséquence de RBAC_PAGE_MAP", () {
    // `saisie-depenses.html` n'apparaît dans AUCUNE des quatre listes ; seul `admin`, dont la liste vaut `null`,
    // n'est pas restreint.
    expect(PermissionsPoste.autorise('admin', EcranPoste.saisieDepenses), isTrue);
    for (final role in ['caissier', 'animalier', 'comptable']) {
      expect(
        PermissionsPoste.autorise(role, EcranPoste.saisieDepenses),
        isFalse,
        reason: '$role ne doit pas decaisser depuis un poste de terrain',
      );
    }
  });
}

/// Script de la parité : les dépenses en base SQLite mémoire, puis `getExpensesProperty()` pour chaque recherche et
/// chaque statut — les identifiants, dans l'ordre du web.
const _scriptParite = r'''
$e = json_decode(file_get_contents($argv[1]), true);
$t = '2026-08-20 10:00:00';
app('db')->table('treasury_accounts')->insert([
    'id' => $e['compte'], 'label' => 'Caisse', 'type' => 'caisse', 'account_code' => '531', 'balance' => 0,
    'is_active' => 1, 'created_at' => $t, 'updated_at' => $t,
]);
foreach ($e['depenses'] as $d) {
    app('db')->table('expenses')->insert([
        'id' => $d['id'], 'expense_date' => $d['date'], 'label' => $d['libelle'], 'category' => '601 - Aliments',
        'amount' => 1000, 'treasury_account_id' => $e['compte'], 'status' => $d['statut'],
        'is_active' => $d['actif'] ? 1 : 0, 'created_at' => $t, 'updated_at' => $t,
    ]);
}
$sortie = [];
foreach ($e['recherches'] as $r) {
    foreach ($e['statuts'] as $s) {
        $c = new App\Livewire\Achats\SaisieDepenses();
        $c->search = $r;
        $c->statusFilter = $s;
        $sortie[$r.'|'.$s] = $c->getExpensesProperty()->pluck('id')->all();
    }
}
echo json_encode($sortie);
''';
