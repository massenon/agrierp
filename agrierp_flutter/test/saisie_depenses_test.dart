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
import 'depenses_aide.dart';
import 'fidelite_libelles_test.dart' show chainesDe;
import 'php_laravel.dart';

/// « Saisie des Dépenses » au poste — tickets F0.18, U13, U14, puis 🔴→✅ DEP4 / DEP5 : UNE DÉPENSE, PLUSIEURS LIGNES.
///
/// ⚠️⚠️ Ce que ces tests protègent :
/// 1. **Les règles du web sont appliquées AVANT d'écrire**, avec ses messages, sous leur champ (`lang/fr/validation.php` et
///    `SaisieDepenseAction`) : un refus qui n'arrive qu'à la synchronisation laisse l'utilisateur sans recours.
/// 2. **Le poste ne prétend rien décaisser** : il n'a ni comptabilité ni solde faisant foi.
/// 3. **L'écran est celui du Blade** (lu dans `saisie-depenses.blade.php`, jamais recopié ici) : en-tête, cartes, barre de
///    recherche, bouton « Nouvelle Dépense », MODALE à lignes dynamiques, tableau Date · Libellé · Total · Mode · Pièce ·
///    Actions et son détail déplié, actions « Modifier » (sans pièce seulement) et « Archiver », toasts.
/// 4. **La liste est celle du web** : parité EXÉCUTÉE avec `SaisieDepenses::getExpensesProperty()` (recherche `LIKE` sur
///    le résumé ET les lignes, filtre de pièce, ordre `expense_date` décroissant puis identifiant).
void main() {
  late AppDatabase db;
  late DepensesRepository depot;

  const compteId = 'cccccccc-1111-4111-8111-cccccccccccc';
  const banqueId = 'cccccccc-2222-4222-8222-cccccccccccc';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = DepensesRepository(database: db, deviceId: 'poste-test', auteurId: () => 'uuuuuuuu-0000-4000-8000-000000000001');

    await db
        .into(db.treasuryAccounts)
        .insert(
          TreasuryAccountsCompanion.insert(
            id: compteId,
            label: 'Caisse Physique',
            accountCode: const Value('531'),
            type: const Value('caisse'),
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
            type: const Value('banque'),
            balance: const Value(1250000),
          ),
        );

    await semerPlanDeCharge(db);
  });

  tearDown(() async => db.close());

  /// Une dépense telle que le tirage la dépose (U13, U14, DEP3) : `synced`, `device_id` d'origine, avec UNE ligne
  /// (sauf [sansLigne] : une dépense que le poste a reçue d'un serveur antérieur à DEP3).
  Future<void> depenseDuServeur(
    String id,
    DateTime date,
    double montant, {
    String? libelle,
    bool actif = true,
    SyncStatus statut = SyncStatus.synced,
    String statutWeb = 'payee',
    String? ecriture,
    String? modePaiement = 'caisse',
    bool sansLigne = false,
    List<(String, String, double)>? lignes,
  }) async {
    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: id,
            deviceId: 'serveur',
            syncStatus: Value(statut),
            updatedAt: DateTime(2026, 8, 20),
            expenseDate: date,
            label: libelle ?? 'Dépense $id',
            category: '601 - Aliments',
            amount: montant,
            treasuryAccountId: Value(compteId),
            isActive: Value(actif),
            status: Value(statutWeb),
            accountingEntryId: Value(ecriture),
            paymentMode: Value(modePaiement),
            // Ticket DEP6 — après la migration du serveur, toute dépense a un centre de coût (« Général » à défaut).
            costCenterId: const Value(centreGeneral),
          ),
        );
    if (sansLigne) return;
    for (final (i, (idLigne, texte, m)) in (lignes ?? [('11111111${id.substring(8)}', libelle ?? 'Dépense $id', montant)]).indexed) {
      await db
          .into(db.expenseLines)
          .insert(
            ExpenseLinesCompanion.insert(
              id: idLigne.length == 36 ? idLigne : '2222222${idLigne.padRight(1, '0')}${id.substring(8)}'.substring(0, 36),
              expenseId: id,
              position: Value(i),
              label: texte,
              chargeAccountId: compte601,
              amount: m,
            ),
          );
    }
  }

  Future<Expense> lire(String id) =>
      (db.select(db.expenses)..where((t) => t.id.equals(id))).getSingle();

  Future<List<ExpenseLine>> lignesDe(String id) =>
      (db.select(db.expenseLines)
            ..where((l) => l.expenseId.equals(id))
            ..orderBy([(l) => OrderingTerm(expression: l.position)]))
          .get();

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
    test('une dépense à une ligne : en-tête + ligne, en attente d envoi, « payee », sans écriture connue', () async {
      final depense = await depot.enregistrerUneLigne(
        date: DateTime(2026, 8, 19),
        libelle: 'Sac de provende ponte',
        montant: 25000,
        compteTresorerieId: compteId,
        centreCoutId: centreGeneral,
      );

      expect(depense.syncStatus, SyncStatus.pending);
      expect(depense.amount, 25000);
      expect(depense.label, 'Sac de provende ponte');
      expect(depense.deviceId, 'poste-test');
      expect(depense.status, 'payee');
      expect(depense.paymentMode, 'caisse');
      expect(depense.createdBy, 'uuuuuuuu-0000-4000-8000-000000000001');
      expect(depense.accountingEntryId, isNull);
      expect(depense.isActive, isTrue);
      final lignes = await lignesDe(depense.id);
      expect(lignes, hasLength(1));
      expect((lignes.single.label, lignes.single.chargeAccountId, lignes.single.amount), ('Sac de provende ponte', compte601, 25000.0));
    });

    test('⚠️ U14 / DEP4 — chaque champ reçoit le message du web (`lang/fr/validation.php`)', () async {
      Future<Map<String, String>> saisie({
        DateTime? date,
        bool sansDate = false,
        String? mode = 'caisse',
        String? compte = compteId,
        String beneficiaire = '',
        List<LigneSaisie>? lignes,
        String? centre = centreGeneral,
        String? fournisseur,
        bool aCredit = false,
      }) => refus(
        () => depot.enregistrer(
          date: sansDate ? null : (date ?? DateTime(2026, 8, 19)),
          modePaiement: mode,
          compteTresorerieId: compte,
          centreCoutId: centre,
          fournisseurId: fournisseur,
          aCredit: aCredit,
          beneficiaire: beneficiaire,
          lignes: lignes ?? const [LigneSaisie(libelle: 'Carburant', compteChargeId: compte605, montant: '25000')],
        ),
      );
      LigneSaisie ligne({String libelle = 'Carburant', String? compte = compte605, String montant = '25000'}) =>
          LigneSaisie(libelle: libelle, compteChargeId: compte, montant: montant);

      expect(await saisie(mode: null, compte: null, lignes: [ligne(libelle: '   ', compte: null, montant: '')]), {
        'mode': 'Le champ mode de paiement est obligatoire.',
        'compte': 'Le champ compte de trésorerie est obligatoire.',
        'ligne.0.libelle': 'Le champ libellé de la ligne est obligatoire.',
        'ligne.0.compte': 'Le champ compte de charge de la ligne est obligatoire.',
        'ligne.0.montant': 'Le champ montant de la ligne est obligatoire.',
      });
      // Ticket DEP6 (DEP-Q1) — le centre de coût est OBLIGATOIRE ; un centre inconnu est refusé comme au web (`exists`).
      expect(await saisie(centre: null), {'centre': DepensesRepository.messageCentreObligatoire});
      expect(await saisie(centre: ''), {'centre': DepensesRepository.messageCentreObligatoire});
      expect(await saisie(centre: 'dddddddd-0000-4000-8000-000000000000'), {
        'centre': "La valeur sélectionnée pour le champ centre de coût n'existe pas.",
      });
      // Ticket DEP7 (DEP-Q3) — À CRÉDIT : un fournisseur, et ni mode ni compte de trésorerie.
      expect(await saisie(aCredit: true, mode: null, compte: null), {
        'fournisseur': DepensesRepository.messageCreditSansFournisseur,
      }, reason: 'à crédit sans fournisseur : aucune dette à créer');
      expect(await saisie(aCredit: true, fournisseur: 'ffffffff-0000-4000-8000-000000000001', mode: null, compte: null), isEmpty,
          reason: 'à crédit : la trésorerie n est PAS demandée');
      await db.delete(db.expenses).go();
      await db.delete(db.expenseLines).go();
      expect(await saisie(lignes: const []), {'lignes': 'Ajoutez au moins une ligne à la dépense.'});
      expect(await saisie(lignes: [ligne(libelle: 'x' * 256)]), {
        'ligne.0.libelle': 'Le champ libellé de la ligne ne doit pas dépasser 255 caractères.',
      });
      expect(await saisie(lignes: [ligne(montant: 'cent')]), {
        'ligne.0.montant': 'Le champ montant de la ligne doit être un nombre entier.',
      });
      expect(await saisie(lignes: [ligne(montant: '100.5')]), {
        'ligne.0.montant': 'Le champ montant de la ligne doit être un nombre entier.',
      });
      expect(await saisie(lignes: [ligne(montant: '0')]), {
        'ligne.0.montant': 'Le champ montant de la ligne doit être au moins égal à 1.',
      });
      expect(await saisie(lignes: [ligne(montant: '-5')]), {
        'ligne.0.montant': 'Le champ montant de la ligne doit être au moins égal à 1.',
      });
      expect(await saisie(lignes: [ligne(compte: compte531)]), {
        'ligne.0.compte': "Le compte de charge de la ligne n'existe pas au plan comptable (classe 6).",
      }, reason: 'un compte de classe 5 n est jamais un compte de charge');
      expect(await saisie(lignes: [ligne(compte: 'dddddddd-0000-4000-8000-000000000000')]), {
        'ligne.0.compte': "Le compte de charge de la ligne n'existe pas au plan comptable (classe 6).",
      });
      expect(await saisie(compte: 'dddddddd-0000-4000-8000-000000000000'), {
        'compte': "La valeur sélectionnée pour le champ compte de trésorerie n'existe pas.",
      });
      expect(await saisie(mode: 'banque'), {
        'mode': 'Le mode de paiement ne correspond pas au type du compte de trésorerie choisi.',
      });
      expect(await saisie(beneficiaire: 'b' * 151), {
        'beneficiaire': 'Le champ bénéficiaire ne doit pas dépasser 150 caractères.',
      });
      expect(await saisie(sansDate: true), {'date': 'Le champ date de la dépense est obligatoire.'});
      // Deuxième ligne fautive : l'erreur porte SON rang.
      expect(await saisie(lignes: [ligne(), ligne(montant: '0')]), {
        'ligne.1.montant': 'Le champ montant de la ligne doit être au moins égal à 1.',
      });
      expect(await db.select(db.expenses).get(), isEmpty, reason: 'rien n est écrit');
      expect(await db.select(db.expenseLines).get(), isEmpty, reason: 'ni ligne');
      expect(await saisie(lignes: [ligne(montant: '1')]), isEmpty, reason: '`min:1` : un franc est accepté');
    });

    test('⚠️ DEP4 — le total est la SOMME des lignes ; l en-tête porte le résumé ; les lignes gardent leur rang', () async {
      final depense = await depot.enregistrer(
        date: DateTime(2026, 6, 15),
        modePaiement: 'caisse',
        compteTresorerieId: compteId,
        centreCoutId: centreGeneral,
        beneficiaire: '  M. Dossou  ',
        lignes: const [
          LigneSaisie(libelle: 'Provende ponte', compteChargeId: compte601, montant: '45000'),
          LigneSaisie(libelle: 'Vermifuge', compteChargeId: compte602, montant: '10000'),
          LigneSaisie(libelle: "Sac d'aliment bis", compteChargeId: compte601, montant: '5000'),
        ],
      );

      expect(depense.amount, 60000, reason: '45 000 + 10 000 + 5 000');
      expect(depense.label, 'Provende ponte (+2 autres)');
      expect(depense.category, '601 - Achats de marchandises', reason: 'compte de la première ligne, pour les serveurs non migrés');
      expect(depense.beneficiary, 'M. Dossou');
      final lignes = await lignesDe(depense.id);
      expect([for (final l in lignes) (l.position, l.label, l.amount)], [
        (0, 'Provende ponte', 45000.0),
        (1, 'Vermifuge', 10000.0),
        (2, "Sac d'aliment bis", 5000.0),
      ]);
      expect([for (final l in lignes) l.chargeAccountId], [compte601, compte602, compte601]);
      expect(lignes.map((l) => l.id).toSet(), hasLength(3), reason: 'un UUID par ligne, créé sur le poste');

      expect(DepensesRepository.total(const [
        LigneSaisie(montant: '45000'), LigneSaisie(montant: '10000'), LigneSaisie(montant: 'abc'), LigneSaisie(montant: ''),
      ]), 55000, reason: 'une ligne illisible compte 0 (`getTotalProperty()` du web)');
      expect(DepensesRepository.resume(['Gasoil']), 'Gasoil');
      expect(DepensesRepository.resume(['Gasoil', 'Huile']), 'Gasoil (+1 autre)');
      expect(DepensesRepository.resume(['Gasoil', 'Huile', 'Filtre']), 'Gasoil (+2 autres)');
    });

    test('⚠️⚠️ DEP4 — UNE SEULE TRANSACTION : un défaut au milieu des lignes n écrit NI en-tête NI ligne', () async {
      const idDouble = 'dddddddd-1111-4111-8111-dddddddddddd';
      await expectLater(
        depot.enregistrer(
          date: DateTime(2026, 6, 15),
          modePaiement: 'caisse',
          compteTresorerieId: compteId,
          centreCoutId: centreGeneral,
          lignes: const [
            LigneSaisie(id: idDouble, libelle: 'A', compteChargeId: compte601, montant: '1000'),
            // Même identifiant : la clé primaire refuse la seconde ligne, APRÈS l'en-tête et la première.
            LigneSaisie(id: idDouble, libelle: 'B', compteChargeId: compte601, montant: '2000'),
          ],
        ),
        throwsA(anything),
      );

      expect(await db.select(db.expenses).get(), isEmpty, reason: 'l en-tête est annulé avec les lignes');
      expect(await db.select(db.expenseLines).get(), isEmpty);
      expect(await db.pendingCount(), 0, reason: 'rien dans la file d envoi');
    });

    test('DEP4 — la file d envoi : une saisie neuve compte pour UN enregistrement en attente (en-tête + lignes)', () async {
      await depot.enregistrer(
        date: DateTime(2026, 6, 15),
        modePaiement: 'caisse',
        compteTresorerieId: compteId,
        centreCoutId: centreGeneral,
        lignes: const [
          LigneSaisie(libelle: 'A', compteChargeId: compte601, montant: '1000'),
          LigneSaisie(libelle: 'B', compteChargeId: compte605, montant: '2000'),
        ],
      );

      expect(await db.pendingCount(), 1);
      expect([for (final d in await db.select(db.expenses).get()) d.syncStatus], [SyncStatus.pending]);
    });

    test(
      '⚠️⚠️ le poste ne décaisse PAS le solde de trésorerie : ce serait un chiffre qui n engage rien',
      () async {
        await depot.enregistrerUneLigne(
          date: DateTime(2026, 8, 19),
          libelle: 'Sac de provende',
          montant: 25000,
          compteTresorerieId: compteId,
          centreCoutId: centreGeneral,
        );

        final compte = await (db.select(
          db.treasuryAccounts,
        )..where((t) => t.id.equals(compteId))).getSingle();

        expect(compte.balance, 500000, reason: 'le decaissement reel a lieu au serveur, a la reception');
      },
    );

    test('le total du mois ne compte que les dépenses de ce mois', () async {
      for (final (jour, montant) in [(5, 10000.0), (19, 25000.0)]) {
        await depot.enregistrerUneLigne(
          date: DateTime(2026, 8, jour),
          libelle: 'Depense $jour',
          montant: montant,
          compteTresorerieId: compteId,
          centreCoutId: centreGeneral,
        );
      }
      await depot.enregistrerUneLigne(
        date: DateTime(2026, 7, 12),
        libelle: 'Mois precedent',
        montant: 99000,
        compteTresorerieId: compteId,
        centreCoutId: centreGeneral,
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

    test('U14 / DEP5 — recherche comme `LIKE` sous la collation du serveur (résumé ET lignes), filtre de pièce', () async {
      await depenseDuServeur('aaaaaaaa-0000-4000-8000-000000000001', DateTime(2026, 8, 3), 1, libelle: 'Électricité SBEE', ecriture: 'eeeeeeee-0000-4000-8000-000000000001');
      await depenseDuServeur('aaaaaaaa-0000-4000-8000-000000000002', DateTime(2026, 8, 2), 1, libelle: 'Carburant 10%');
      await depenseDuServeur(
        'aaaaaaaa-0000-4000-8000-000000000003',
        DateTime(2026, 8, 1),
        3,
        libelle: 'carburant groupe (+1 autre)',
        lignes: [('a1', 'carburant groupe', 1), ('a2', 'Huile moteur', 2)],
      );

      Future<List<String>> chercher(String r, {String piece = ''}) async => [
        for (final l in await depot.depenses(recherche: r, piece: piece)) l.depense.label,
      ];

      expect(await chercher('ELECTRI'), ['Électricité SBEE'], reason: 'sans casse ni accents (utf8mb4_unicode_ci)');
      expect(await chercher('électricité'), ['Électricité SBEE']);
      expect(await chercher('CARBURANT'), ['Carburant 10%', 'carburant groupe (+1 autre)']);
      expect(await chercher('c_rburant g'), ['carburant groupe (+1 autre)'], reason: '`_` : un caractère quelconque');
      expect(await chercher('10%'), ['Carburant 10%']);
      expect(await chercher('huile'), ['carburant groupe (+1 autre)'], reason: 'le libellé d une LIGNE se cherche aussi');
      expect(await chercher('0'), hasLength(3), reason: '`when(\'0\')` est faux en PHP : pas de filtre');
      expect(await chercher('', piece: 'Comptabilisée'), ['Électricité SBEE']);
      expect(await chercher('carb', piece: 'Sans pièce'), ['Carburant 10%', 'carburant groupe (+1 autre)']);
      expect(await chercher('zzz'), isEmpty);
    });

    test('⚠️⚠️ DEP4 — le numéro de pièce est RELU de l écriture liée ; sans le journal : « Comptabilisée » seulement', () async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000011';
      const sansJournal = 'aaaaaaaa-0000-4000-8000-000000000012';
      await db.into(db.accountingEntries).insert(
        AccountingEntriesCompanion.insert(
          id: 'eeeeeeee-0000-4000-8000-000000000011',
          entryDate: DateTime(2026, 8, 3),
          reference: const Value('OD-2026-0012 — Dépense Carburant groupe'),
        ),
      );
      await depenseDuServeur(id, DateTime(2026, 8, 3), 5000, ecriture: 'eeeeeeee-0000-4000-8000-000000000011');
      await depenseDuServeur(sansJournal, DateTime(2026, 8, 2), 5000, ecriture: 'eeeeeeee-0000-4000-8000-0000000000ff');

      final liste = {for (final l in await depot.depenses()) l.depense.id: l};
      expect(liste[id]!.numeroPiece, 'OD-2026-0012');
      expect(liste[id]!.comptabilisee, isTrue);
      expect(liste[sansJournal]!.numeroPiece, isNull);
      expect(liste[sansJournal]!.comptabilisee, isTrue);
    });

    test('DEP4 — une dépense SANS ligne (serveur antérieur à DEP3) montre une ligne de repli : jamais un détail vide', () async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000013';
      await depenseDuServeur(id, DateTime(2026, 8, 3), 7500, libelle: 'Réparation', sansLigne: true);

      final l = (await depot.depenses()).single;
      expect([for (final d in l.lignes) (d.libelle, d.compte, d.montant)], [('Réparation', '601 - Aliments', 7500.0)]);
    });

    test('⚠️ DEP1 — une dépense COMPTABILISÉE est immuable : aucun champ, même le libellé (message du web)', () async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000021';
      await depenseDuServeur(id, DateTime(2026, 8, 3), 25000, ecriture: 'eeeeeeee-0000-4000-8000-000000000001');

      Future<Map<String, String>> modifier({
        DateTime? date,
        String libelle = 'Dépense $id',
        double montant = 25000,
        String compte = compteId,
        String mode = 'caisse',
      }) => refus(
        () => depot.enregistrerUneLigne(
          date: date ?? DateTime(2026, 8, 3),
          libelle: libelle,
          montant: montant,
          compteTresorerieId: compte,
          centreCoutId: centreGeneral,
          modePaiement: mode,
          idEnModification: id,
        ),
      );

      for (final interdit in [
        () => modifier(date: DateTime(2026, 8, 4)),
        () => modifier(montant: 30000),
        () => modifier(libelle: 'Dépense corrigée'),
        () => modifier(compte: banqueId, mode: 'banque'),
        () => modifier(),
      ]) {
        expect(await interdit(), {'formulaire': DepensesRepository.messageDejaComptabilisee});
      }
      expect((await lire(id)).syncStatus, SyncStatus.synced, reason: 'rien n est écrit');
      expect((await lire(id)).label, 'Dépense $id');
      expect(await depot.refusAvantModification(await lire(id)), DepensesRepository.messageDejaComptabilisee);
    });

    test('DEP1 — une dépense SANS pièce se modifie : lignes REMPLACÉES (identifiants gardés), repart en attente', () async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000022';
      await depenseDuServeur(id, DateTime(2026, 8, 3), 25000);
      final avant = (await lignesDe(id)).single;

      await depot.enregistrer(
        date: DateTime(2026, 8, 3),
        modePaiement: 'banque',
        compteTresorerieId: banqueId,
        centreCoutId: centreGeneral,
        idEnModification: id,
        lignes: [
          LigneSaisie(id: avant.id, libelle: 'Provende', compteChargeId: compte605, montant: '20000'),
          const LigneSaisie(libelle: 'Transport', compteChargeId: compte614, montant: '10000'),
        ],
      );

      final d = await lire(id);
      expect((d.amount, d.label, d.treasuryAccountId, d.paymentMode), (30000.0, 'Provende (+1 autre)', banqueId, 'banque'));
      expect((d.syncStatus, d.deviceId), (SyncStatus.pending, 'serveur'), reason: 'part au serveur ; l origine est gardée');
      final lignes = await lignesDe(id);
      expect([for (final l in lignes) (l.label, l.chargeAccountId, l.amount)], [
        ('Provende', compte605, 20000.0),
        ('Transport', compte614, 10000.0),
      ]);
      expect(lignes.first.id, avant.id, reason: 'la ligne reconnue garde son identifiant');
      expect(await depot.refusAvantModification(d), isNull);
    });

    test('⚠️ U14 — une dépense archivée ne se modifie plus ; un archivage est idempotent', () async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000023';
      await depenseDuServeur(id, DateTime(2026, 8, 3), 25000);

      await depot.archiver(id);
      final archivee = await lire(id);
      expect((archivee.isActive, archivee.syncStatus), (false, SyncStatus.pending));

      expect(
        await refus(
          () => depot.enregistrerUneLigne(
            date: DateTime(2026, 8, 3),
            libelle: 'X',
            montant: 25000,
            compteTresorerieId: compteId,
            centreCoutId: centreGeneral,
            idEnModification: id,
          ),
        ),
        {'formulaire': DepensesRepository.messageArchivee},
      );
      expect(await depot.depenses(), isEmpty, reason: 'archivée : hors de la liste, comme au web');
      await depot.archiver(id);
      expect((await lire(id)).syncStatus, SyncStatus.pending);
    });

    test('DEP1 — archiver une dépense COMPTABILISÉE reste possible (le serveur contre-passe)', () async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000026';
      await depenseDuServeur(id, DateTime(2026, 8, 3), 25000, ecriture: 'eeeeeeee-0000-4000-8000-000000000001');

      await depot.archiver(id);

      expect(((await lire(id)).isActive, (await lire(id)).syncStatus), (false, SyncStatus.pending));
    });

    test('U14 / DEP4 — corriger une saisie refusée efface son ancien refus ; modifier un ARCHIVAGE refusé la réactive', () async {
      const refusee = 'aaaaaaaa-0000-4000-8000-000000000024';
      const archivageRefuse = 'aaaaaaaa-0000-4000-8000-000000000025';
      await depenseDuServeur(refusee, DateTime(2026, 8, 3), 25000, statut: SyncStatus.conflict);
      await depenseDuServeur(archivageRefuse, DateTime(2026, 8, 3), 5000, statut: SyncStatus.conflict, actif: false);
      for (final id in [refusee, archivageRefuse]) {
        await (db.update(db.expenses)..where((t) => t.id.equals(id))).write(const ExpensesCompanion(ecritureRefus: Value('Refus de la pièce')));
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
      final liste = {for (final l in await depot.depenses()) l.depense.id: l};
      expect(liste.keys, containsAll([refusee, archivageRefuse]));
      expect(liste[refusee]!.motifRefus, 'Refus de la pièce', reason: '`ecriture_refus` : le refus de la PIÈCE, affiché');

      for (final id in [refusee, archivageRefuse]) {
        await depot.enregistrerUneLigne(
          date: DateTime(2026, 8, 3),
          libelle: 'Corrigée',
          montant: 4000,
          compteTresorerieId: compteId,
          centreCoutId: centreGeneral,
          idEnModification: id,
        );
        final d = await lire(id);
        expect((d.syncStatus, d.isActive, d.ecritureRefus), (SyncStatus.pending, true, null), reason: id);
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
    final modele = lireLaravel('app/Models/Expense.php');
    final saut = blade == null || composant == null || action == null || modale == null || carte == null || modele == null
        ? 'dépôt Laravel absent ($dossierLaravel) : comparaison au web impossible'
        : null;

    final poste = [
      'lib/features/achats/saisie_depenses_screen.dart',
      'lib/features/achats/modale_depense.dart',
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
        for (final m in RegExp(r'<h4[^>]*>([^<]+)</h4>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'<span class="col-span-\d+ text-\[10px\][^"]*">([^<]+)</span>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'placeholder="([^"]+)"').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'<option[^>]*>([^<{]+)</option>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'<th[^>]*>([^<]+)</th>').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'<x-kpi-card label="([^"]+)"').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'title="([^"{]+)"').allMatches(b)) html(m[1]!),
        for (final m in RegExp(r'border-brand-emerald/30">[^<{]*([^<{]+)</span>').allMatches(b)) html(m[1]!),
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
          "Enregistrez une charge d'exploitation de trésorerie directe : une dépense, plusieurs lignes.",
          'Date de la Transaction *',
          'Mode de Paiement *',
          'Compte de Trésorerie Débité *',
          'Centre de Coût *',
          'Fournisseur',
          'Règlement *',
          'Bénéficiaire',
          'Reçu / Facture (Photo)',
          'Lignes de la Dépense *',
          'Libellé *',
          'Compte de Charge *',
          'Montant (FCFA) *',
          'Enregistrer la Dépense',
          'Rechercher...',
          'Toutes les pièces',
          'Comptabilisée',
          'Sans pièce',
          'Date',
          'Libellé',
          'Total',
          'Mode',
          'Pièce',
          'Actions',
          'Compte de Charge',
          'Montant',
          'Modifier',
          'Archiver',
          'Aucune dépense pour le moment.',
          'ex : 25000',
        ]),
      );
      // Le ✕ de la modale (`title="Fermer"`) est celui de `ModaleAgri` (clé `modale-fermer`), commun à toutes les modales.
      for (final t in textes.where((t) => !t.contains('{{') && t != 'Fermer')) {
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

    test('⚠️ les messages de validation par ligne et le résumé sont ceux du web', () {
      for (final t in [
        'Ajoutez au moins une ligne à la dépense.',
        "Le compte de charge de la ligne n\\'existe pas au plan comptable (classe 6).",
        "Le mode de paiement ne correspond pas au type du compte de trésorerie choisi.",
      ]) {
        expect(action!, contains(t.replaceAll("\\'", "\\'")), reason: t);
      }
      expect(composant!, contains('Le champ mode de paiement est obligatoire.'));
      expect(poste, contains('Le champ mode de paiement est obligatoire.'));
      expect(poste, contains('Ajoutez au moins une ligne à la dépense.'));
      // Modes de paiement : type du compte de trésorerie → libellé (`Expense::MODES_DE_PAIEMENT`).
      final modes = {
        for (final m in RegExp(r"'(\w+)' => '([^']+)',").allMatches(modele!.substring(modele.indexOf('MODES_DE_PAIEMENT'), modele.indexOf('MODES_DE_PAIEMENT') + 300)))
          m[1]!: m[2]!,
      };
      expect(DepensesRepository.modesDePaiement, modes);
    }, skip: saut);

    test('les colonnes du tableau sont celles du Blade, dans son ordre', () {
      final tete = blade!.substring(blade.indexOf('<thead class="bg-surface-zebra'), blade.indexOf('</thead>'));
      final colonnes = [
        for (final m in RegExp(r'<th[^>]*>([^<]+)</th>').allMatches(tete)) html(m[1]!).toUpperCase(),
      ];
      expect(colonnes, ['DATE', 'LIBELLÉ', 'TOTAL', 'MODE', 'PIÈCE', 'ACTIONS']);
      final ecran = File('lib/features/achats/saisie_depenses_screen.dart').readAsStringSync();
      final tableau = ecran.substring(ecran.indexOf('Widget _tableau()'));
      final ordre = [for (final c in colonnes) tableau.indexOf("'$c'")];
      expect(ordre.every((p) => p >= 0), isTrue, reason: '$ordre');
      expect(ordre, [...ordre]..sort());

      // Le détail déplié : Libellé · Compte de Charge · Montant, puis la ligne « Trésorerie : … · Saisie par : … ».
      final detail = blade.substring(blade.indexOf('<tr x-show="ouvert"'));
      expect([for (final m in RegExp(r'<th[^>]*>([^<]+)</th>').allMatches(detail)) html(m[1]!)], ['Libellé', 'Compte de Charge', 'Montant']);
      expect(detail, contains('Trésorerie : '));
      for (final t in ['Trésorerie : ', ' · Centre de coût : ', ' · Fournisseur : ', ' · Bénéficiaire : ', ' · Saisie par : ']) {
        expect(ecran, contains(t.trim() == '' ? t : t.replaceAll(' · ', ' · ')), reason: t);
      }
    }, skip: saut);

    test('la modale du web : champs dans l ordre, lignes à trois colonnes, total en direct', () {
      final b = blade!;
      final ordreBlade = [
        'Date de la Transaction *',
        'Mode de Paiement *',
        'Compte de Trésorerie Débité *',
        'Centre de Coût *',
        'Fournisseur',
        'Règlement *',
        'Bénéficiaire',
        'Reçu / Facture (Photo)',
        'Lignes de la Dépense *',
        'Ajouter une ligne',
        'Total : ',
        'Enregistrer la Dépense',
      ];
      // Les libellés de champ se cherchent sous leur forme `<label>` : « Fournisseur » figure aussi dans le détail déplié.
      final positionsBlade = [
        for (final t in ordreBlade)
          b.indexOf(switch (t) {
            'Lignes de la Dépense *' => '>$t</h4>',
            'Ajouter une ligne' || 'Total : ' || 'Enregistrer la Dépense' => t,
            _ => '>$t</label>',
          }),
      ];
      expect(positionsBlade.every((p) => p >= 0), isTrue, reason: '$positionsBlade');
      expect(positionsBlade, [...positionsBlade]..sort());

      final modale = File('lib/features/achats/modale_depense.dart').readAsStringSync();
      final ordrePoste = [
        for (final t in ["'Date de la Transaction *'", "'Mode de Paiement *'", "'Compte de Trésorerie Débité *'",
          "'Centre de Coût *'", "'Fournisseur'", "'Règlement *'", "'Bénéficiaire'", "'Reçu / Facture (Photo)'", "'LIGNES DE LA DÉPENSE *'",
          "'Ajouter une ligne'", "'Total : ", "'Enregistrer la Dépense'"])
          modale.indexOf(t),
      ];
      expect(ordrePoste.every((p) => p >= 0), isTrue, reason: '$ordrePoste');
      expect(ordrePoste, [...ordrePoste]..sort());
      expect(modale, contains('LargeurModale.xl'));
      expect(b, contains('max-width="xl"'));
    }, skip: saut);
  });

  // ── Parité exécutée avec le composant Livewire ─────────────────────────

  group('parité exécutée', () {
    final saut = sautSansPhp();

    test('⚠️⚠️ DEP5 — la liste du poste est celle de `getExpensesProperty()` (recherches, pièces, ordre, lignes)', () async {
      final depenses = <Map<String, Object?>>[];
      var n = 0;
      for (final (libelle, jour, piece, actif, ligne) in [
        ('Carburant livraison', 3, true, true, 'Gasoil'),
        ('carburant groupe', 3, false, true, 'Huile moteur'),
        ('CARBURANT 10%', 3, true, true, 'Filtre'),
        ('Achat provende Lot 3', 2, true, true, 'Maïs'),
        ('Achat provende Lot 3', 2, false, true, 'Soja'),
        ('Doublon archivé', 4, true, false, 'Doublon'),
        ('Eau', 1, true, true, 'Forage'),
        ('Transport a_b', 5, true, true, 'Livraison'),
        ('Transport axb', 5, false, true, 'Livraison bis'),
        ('Divers (+1 autre)', 6, false, true, 'Sac de son'),
      ]) {
        n++;
        depenses.add({
          // Identifiants dans le désordre, pour que l'ordre par identifiant se voie.
          'id': 'aaaaaaaa-0000-4000-8000-${((n * 7919) % 1000).toString().padLeft(12, '0')}',
          'date': '2026-08-${jour.toString().padLeft(2, '0')}',
          'libelle': libelle,
          'piece': piece,
          'actif': actif,
          'ligne': ligne,
        });
      }
      final recherches = ['', 'carb', 'CARBURANT', '%', '10%', 'a_b', 'lot 3', '0', ' ', 'zzz', 'gasoil', 'SOJA', 'sac de'];
      final pieces = ['', 'Comptabilisée', 'Sans pièce'];

      final sortie = executerPhp('<?php\n$amorceApplication\n$_scriptParite', {
        'compte': compteId,
        'depenses': depenses,
        'recherches': recherches,
        'pieces': pieces,
      }, application: true) as Map<String, dynamic>;

      for (final d in depenses) {
        await depenseDuServeur(
          d['id']! as String,
          DateTime.parse(d['date']! as String),
          1000,
          libelle: d['libelle']! as String,
          ecriture: d['piece']! as bool ? 'eeeeeeee-0000-4000-8000-000000000001' : null,
          actif: d['actif']! as bool,
          lignes: [('11111111${(d['id']! as String).substring(8)}', d['ligne']! as String, 1000)],
        );
      }
      var comparaisons = 0;
      for (final r in recherches) {
        for (final p in pieces) {
          final web = (sortie['$r|$p'] as List).cast<String>();
          final ici = [for (final l in await depot.depenses(recherche: r, piece: p)) l.depense.id];
          expect(ici, web, reason: 'recherche « $r », pièce « $p »');
          comparaisons++;
        }
      }
      expect(comparaisons, 39);
      expect((sortie['carb|'] as List), hasLength(3), reason: 'témoin : trois carburants actifs');
      expect((sortie['gasoil|'] as List), hasLength(1), reason: 'témoin : un libellé de LIGNE trouvé');
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

    Future<void> ouvrirModale(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('bouton-nouvelle-depense')));
      await tester.pumpAndSettle();
    }

    Future<void> choisir(WidgetTester tester, String cle, String texte) async {
      await tester.tap(find.byKey(Key(cle)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(texte).last);
      await tester.pumpAndSettle();
    }

    Future<void> remplirLigne(WidgetTester tester, int i, String libelle, String compte, String montant) async {
      await tester.enterText(find.byKey(Key('champ-ligne.$i.libelle')), libelle);
      await choisir(tester, 'liste-ligne-$i-compte', compte);
      await tester.enterText(find.byKey(Key('champ-ligne.$i.montant')), montant);
      await tester.pumpAndSettle();
    }

    double y(WidgetTester tester, String texte) => tester.getTopLeft(find.text(texte).first).dy;

    testWidgets("DEP5 — l'ordre des sections suit le Blade ; la saisie n'est plus un formulaire en page", (tester) async {
      await afficher(tester);

      final positions = [
        y(tester, 'Saisie des Dépenses'),
        y(tester, "Enregistrement des charges d'exploitation courantes de la ferme (SYSCOHADA Classe 6)."),
        y(tester, 'DÉPENSES DU MOIS'),
        y(tester, 'Toutes les pièces'),
        y(tester, 'Nouvelle Dépense'),
        y(tester, 'DATE'),
        y(tester, 'Aucune dépense pour le moment.'),
      ];
      expect(positions, equals([...positions]..sort()));
      expect(find.byKey(const Key('champ-date')), findsNothing, reason: 'le formulaire vit dans la modale');
      expect(find.text('Indicateurs de performance'), findsNothing, reason: 'le Blade n a pas ce titre');
      for (final c in ['DATE', 'LIBELLÉ', 'TOTAL', 'MODE', 'PIÈCE', 'ACTIONS']) {
        expect(find.text(c), findsOneWidget, reason: c);
      }
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

    testWidgets('DEP5 — la modale s ouvre sur UNE ligne vide, total à 0 ; l ordre des champs suit le Blade', (tester) async {
      await afficher(tester);
      await ouvrirModale(tester);

      expect(find.text('Nouvelle Dépense'), findsWidgets);
      expect(find.byKey(const Key('depense-modale-aide')), findsOneWidget);
      expect(find.byKey(const Key('champ-ligne.0.libelle')), findsOneWidget);
      expect(find.byKey(const Key('champ-ligne.1.libelle')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('depense-total'))).data, 'Total : 0 FCFA');
      final positions = [
        y(tester, 'DATE DE LA TRANSACTION *'),
        y(tester, 'COMPTE DE TRÉSORERIE DÉBITÉ *'),
        y(tester, 'REÇU / FACTURE (PHOTO)'),
        y(tester, 'LIGNES DE LA DÉPENSE *'),
        y(tester, 'Enregistrer la Dépense'),
      ];
      expect(positions, equals([...positions]..sort()));
      // `md:grid-cols-2` : Date et Mode côte à côte, Compte et Centre de Coût, Fournisseur et Bénéficiaire.
      expect(y(tester, 'DATE DE LA TRANSACTION *'), y(tester, 'MODE DE PAIEMENT *'));
      expect(y(tester, 'COMPTE DE TRÉSORERIE DÉBITÉ *'), y(tester, 'CENTRE DE COÛT *'));
      expect(y(tester, 'FOURNISSEUR'), y(tester, 'BÉNÉFICIAIRE'));
    });

    testWidgets('⚠️⚠️ DEP5 — lignes dynamiques : ajout, retrait (la dernière jamais), total EN DIRECT', (tester) async {
      await afficher(tester);
      await ouvrirModale(tester);

      expect(tester.widget<IconButton>(find.byKey(const Key('ligne-0-retirer'))).onPressed, isNull, reason: 'une seule ligne : grisé');

      await tester.tap(find.byKey(const Key('bouton-ajouter-ligne')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bouton-ajouter-ligne')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('champ-ligne.2.libelle')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('champ-ligne.0.montant')), '45000');
      await tester.enterText(find.byKey(const Key('champ-ligne.1.montant')), '10000');
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('depense-total'))).data, 'Total : 55 000 FCFA');
      await tester.enterText(find.byKey(const Key('champ-ligne.2.montant')), '5000');
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('depense-total'))).data, 'Total : 60 000 FCFA');

      await tester.tap(find.byKey(const Key('ligne-1-retirer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('champ-ligne.2.libelle')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('depense-total'))).data, 'Total : 50 000 FCFA', reason: 'retirer une ligne retire son montant');

      await tester.enterText(find.byKey(const Key('champ-ligne.0.montant')), 'abc');
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('depense-total'))).data, 'Total : 5 000 FCFA', reason: 'une ligne illisible compte 0');
    });

    testWidgets('DEP5 — le mode filtre les comptes de trésorerie ; un compte fixe le mode ; options « libellé (solde FCFA) »', (tester) async {
      await afficher(tester);
      await ouvrirModale(tester);

      await tester.tap(find.byKey(const Key('liste-compte')));
      await tester.pumpAndSettle();
      expect(find.text('Caisse Physique (500 000 FCFA)'), findsWidgets);
      expect(find.text('Banque (1 250 000 FCFA)'), findsWidgets);
      await tester.tap(find.text('Banque (1 250 000 FCFA)').last);
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<String>>(find.byKey(const Key('liste-mode'))).value, 'banque', reason: 'le compte fixe le mode');

      await choisir(tester, 'liste-mode', 'Espèces');
      expect(tester.widget<DropdownButton<String>>(find.byKey(const Key('liste-compte'))).value, isNull, reason: 'un compte d un autre type est abandonné');
      await tester.tap(find.byKey(const Key('liste-compte')));
      await tester.pumpAndSettle();
      expect(find.text('Caisse Physique (500 000 FCFA)'), findsWidgets);
      expect(find.text('Banque (1 250 000 FCFA)'), findsNothing, reason: 'le mode filtre les comptes');
    });

    testWidgets('⚠️ DEP5 — erreurs sous leur champ, messages du web, rien n est écrit', (tester) async {
      await afficher(tester);
      await ouvrirModale(tester);

      await tester.ensureVisible(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.tap(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.pumpAndSettle();

      expect(find.text('Le champ mode de paiement est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ compte de trésorerie est obligatoire.'), findsOneWidget);
      // Ticket DEP6 (DEP-Q1) — le centre de coût est obligatoire : son message sous le champ, comme `@error('costCenterId')`.
      expect(find.text(DepensesRepository.messageCentreObligatoire), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('erreur-centre'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const Key('liste-centre'))).dy),
        reason: 'sous le champ',
      );
      expect(find.text('Le champ libellé de la ligne est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ compte de charge de la ligne est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ montant de la ligne est obligatoire.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('erreur-ligne.0.libelle'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const Key('champ-ligne.0.libelle'))).dy),
        reason: 'sous le champ, comme `@error` du Blade',
      );
      expect(await db.select(db.expenses).get(), isEmpty);
      expect(await db.select(db.expenseLines).get(), isEmpty);
    });

    testWidgets('⚠️⚠️ DEP5 — une dépense à trois lignes : toast du web, modale fermée, ligne « À envoyer » avec son résumé', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrirModale(tester);

      await choisir(tester, 'liste-compte', 'Caisse Physique (500 000 FCFA)');
      await choisir(tester, 'liste-centre', 'Général');
      await tester.tap(find.byKey(const Key('bouton-ajouter-ligne')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bouton-ajouter-ligne')));
      await tester.pumpAndSettle();
      await remplirLigne(tester, 0, 'Provende ponte', '601 - Achats de marchandises', '45000');
      await remplirLigne(tester, 1, 'Vermifuge', '602 - Produits vétérinaires', '10000');
      await remplirLigne(tester, 2, "Sac d'aliment bis", '601 - Achats de marchandises', '5000');
      expect(tester.widget<Text>(find.byKey(const Key('depense-total'))).data, 'Total : 60 000 FCFA');

      await tester.ensureVisible(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.tap(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.pumpAndSettle();

      expect(find.text('Dépense enregistrée avec succès.'), findsOneWidget);
      expect(find.byKey(const Key('champ-ligne.0.libelle')), findsNothing, reason: 'la modale est fermée');
      expect(find.text('Provende ponte (+2 autres)'), findsOneWidget, reason: 'le résumé, dans le tableau');
      expect(find.text('60 000 FCFA'), findsWidgets);
      expect(find.text('Espèces'), findsOneWidget);
      expect(find.text('À envoyer'), findsOneWidget);
      expect(find.text('Sans pièce'), findsOneWidget, reason: 'la pièce est passée par le serveur au rejeu');
      final d = (await db.select(db.expenses).get()).single;
      expect((d.amount, d.syncStatus, d.paymentMode), (60000.0, SyncStatus.pending, 'caisse'));
      expect(await lignesDe(d.id), hasLength(3));

      // Le détail se déplie sur ses lignes, puis la ligne « Trésorerie : … ».
      expect(find.text('Vermifuge'), findsNothing);
      await tester.tap(find.byKey(const Key('depense-deplier-0')));
      await tester.pumpAndSettle();
      expect(find.text('Vermifuge'), findsOneWidget);
      expect(find.text('602 - Produits vétérinaires'), findsOneWidget);
      expect(find.text('10 000 FCFA'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('depense-detail-resume-0'))).data,
        'Trésorerie : Caisse Physique · Centre de coût : Général · Fournisseur : — · Bénéficiaire : — · Règlement : Payée comptant · Saisie par : —',
      );
      await tester.tap(find.byKey(const Key('depense-deplier-0')));
      await tester.pumpAndSettle();
      expect(find.text('Vermifuge'), findsNothing);

      await tester.pump(ToastAgri.duree);
      await tester.pumpAndSettle();
    });

    testWidgets('⚠️ DEP1/DEP5 — dépense comptabilisée : pas de « Modifier », le numéro de pièce relu ; sans pièce : « Modifier »', (
      tester,
    ) async {
      const comptabilisee = 'aaaaaaaa-0000-4000-8000-000000000041';
      const sansPiece = 'aaaaaaaa-0000-4000-8000-000000000042';
      await db.into(db.accountingEntries).insert(
        AccountingEntriesCompanion.insert(
          id: 'eeeeeeee-0000-4000-8000-000000000041',
          entryDate: DateTime(2026, 8, 3),
          reference: const Value('OD-2026-0012 — Dépense Carburant groupe'),
        ),
      );
      await depenseDuServeur(comptabilisee, DateTime(2026, 8, 3), 25000, libelle: 'Carburant groupe', ecriture: 'eeeeeeee-0000-4000-8000-000000000041');
      await depenseDuServeur(sansPiece, DateTime(2026, 8, 2), 3000, libelle: 'Reprise ancienne');
      await afficher(tester);

      expect(find.byKey(const Key('depense-modifier-$comptabilisee')), findsNothing);
      expect(find.byKey(const Key('depense-archiver-$comptabilisee')), findsOneWidget);
      expect(find.byKey(const Key('depense-modifier-$sansPiece')), findsOneWidget);
      expect(find.text('OD-2026-0012'), findsOneWidget, reason: 'RELU de l écriture liée');
      expect(find.text('Sans pièce'), findsOneWidget);
    });

    testWidgets('⚠️ DEP5 — « Modifier » une dépense sans pièce : modale « Modifier la Dépense » remplie de ses lignes', (tester) async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000043';
      await depenseDuServeur(
        id,
        DateTime(2026, 8, 3),
        30000,
        libelle: 'Provende (+1 autre)',
        lignes: [('b1', 'Provende', 20000), ('b2', 'Transport', 10000)],
      );
      await afficher(tester);

      await tester.tap(find.byKey(const Key('depense-modifier-$id')));
      await tester.pumpAndSettle();

      expect(find.text('Modifier la Dépense'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('champ-ligne.0.libelle'))).controller!.text, 'Provende');
      expect(tester.widget<TextField>(find.byKey(const Key('champ-ligne.1.libelle'))).controller!.text, 'Transport');
      expect(tester.widget<TextField>(find.byKey(const Key('champ-ligne.1.montant'))).controller!.text, '10000');
      expect(tester.widget<Text>(find.byKey(const Key('depense-total'))).data, 'Total : 30 000 FCFA');
      expect(find.text('03/08/2026'), findsWidgets);

      await tester.enterText(find.byKey(const Key('champ-ligne.1.montant')), '12000');
      await tester.ensureVisible(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.tap(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.pumpAndSettle();

      expect(find.text('Modifier la Dépense'), findsNothing, reason: 'la modale est fermée');
      final d = await lire(id);
      expect((d.amount, d.syncStatus), (32000.0, SyncStatus.pending));
      expect((await lignesDe(id)).map((l) => l.amount), [20000.0, 12000.0]);
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

    testWidgets('U14 — « Rechercher... » attend 300 ms ; le filtre de pièce s applique aussitôt', (tester) async {
      await depenseDuServeur('aaaaaaaa-0000-4000-8000-000000000061', DateTime(2026, 8, 3), 1, libelle: 'Électricité', ecriture: 'eeeeeeee-0000-4000-8000-000000000001');
      await depenseDuServeur(
        'aaaaaaaa-0000-4000-8000-000000000062',
        DateTime(2026, 8, 2),
        1,
        libelle: 'Carburant',
      );
      await afficher(tester);
      expect(find.text('Sans pièce'), findsOneWidget, reason: 'badge maïs du Blade');

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
      await tester.tap(find.byKey(const Key('depenses-filtre-piece')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sans pièce').last);
      await tester.pumpAndSettle();
      expect(find.text('Électricité'), findsNothing);
      expect(find.text('Carburant'), findsOneWidget);
    });

    testWidgets('➕ DEP4 — une saisie refusée montre son état et le REFUS DE LA PIÈCE du serveur, mot pour mot', (tester) async {
      const id = 'aaaaaaaa-0000-4000-8000-000000000071';
      const refusDeLaPiece =
          "La dépense ne peut pas être enregistrée : le compte de trésorerie « Caisse orpheline » n'est relié à aucun compte du plan comptable (compte 999 absent). Aucune pièce comptable ne peut être passée.";
      await depenseDuServeur(id, DateTime(2026, 8, 3), 1, statut: SyncStatus.conflict);
      await (db.update(db.expenses)..where((t) => t.id.equals(id))).write(const ExpensesCompanion(ecritureRefus: Value(refusDeLaPiece)));
      await afficher(tester);

      expect(find.text('Refusée'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('depense-motif-$id'))).data, refusDeLaPiece);
    });

    testWidgets('⚠️ le champ justificatif annonce sa limite au lieu de mentir', (tester) async {
      await afficher(tester);
      await ouvrirModale(tester);

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

/// Script de la parité : les dépenses (et leurs lignes) en base SQLite mémoire, puis `getExpensesProperty()` pour chaque
/// recherche et chaque filtre de pièce — les identifiants, dans l'ordre du web.
const _scriptParite = r'''
$e = json_decode(file_get_contents($argv[1]), true);
$t = '2026-08-20 10:00:00';
app('db')->table('treasury_accounts')->insert([
    'id' => $e['compte'], 'label' => 'Caisse', 'type' => 'caisse', 'account_code' => '531', 'balance' => 0,
    'is_active' => 1, 'created_at' => $t, 'updated_at' => $t,
]);
$compteCharge = '60100000-0000-4000-8000-000000000601';
app('db')->table('chart_of_accounts')->insert([
    'id' => $compteCharge, 'code' => '601', 'label' => 'Achats', 'class' => 6, 'is_active' => 1, 'created_at' => $t, 'updated_at' => $t,
]);
foreach ($e['depenses'] as $d) {
    app('db')->table('expenses')->insert([
        'id' => $d['id'], 'expense_date' => $d['date'], 'label' => $d['libelle'], 'category' => '601 - Aliments',
        'amount' => 1000, 'treasury_account_id' => $e['compte'], 'status' => 'payee',
        'accounting_entry_id' => $d['piece'] ? 'eeeeeeee-0000-4000-8000-000000000001' : null,
        'is_active' => $d['actif'] ? 1 : 0, 'created_at' => $t, 'updated_at' => $t,
    ]);
    app('db')->table('expense_lines')->insert([
        'id' => '11111111'.substr($d['id'], 8), 'expense_id' => $d['id'], 'position' => 0, 'label' => $d['ligne'],
        'charge_account_id' => $compteCharge, 'amount' => 1000, 'created_at' => $t, 'updated_at' => $t,
    ]);
}
$sortie = [];
foreach ($e['recherches'] as $r) {
    foreach ($e['pieces'] as $p) {
        $c = new App\Livewire\Achats\SaisieDepenses();
        $c->search = $r;
        $c->pieceFilter = $p;
        $sortie[$r.'|'.$p] = $c->getExpensesProperty()->pluck('id')->all();
    }
}
echo json_encode($sortie);
''';
