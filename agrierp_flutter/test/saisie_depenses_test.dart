import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/saisie_depenses_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.18 — SAISIE DES DÉPENSES AU POSTE (`saisie-depenses.html`).
///
/// ⚠️⚠️ Ce que ces tests protègent :
/// 1. **Les bornes du serveur sont appliquées AVANT d'écrire** — un refus qui
///    n'arrive qu'à la synchronisation laisse l'animalier sans recours sur le
///    terrain, des jours plus tard.
/// 2. **Le poste ne prétend rien décaisser** : il n'a ni comptabilité ni solde
///    faisant foi.
/// 3. **La liste n'est pas celle de l'exploitation** — et l'écran le dit.
void main() {
  late AppDatabase db;
  late DepensesRepository depot;

  const compteId = 'cccccccc-1111-4111-8111-cccccccccccc';

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

    for (final libelle in ['601 - Aliments', '605 - Énergie']) {
      await db
          .into(db.expenseCategories)
          .insert(ExpenseCategoriesCompanion.insert(label: libelle));
    }
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SaisieDepensesScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String texte) =>
      tester.getTopLeft(find.text(texte)).dy;

  // ── Le dépôt : les bornes du serveur, appliquées au poste ──────────────

  test('une dépense valide est enregistrée en attente d envoi', () async {
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
  });

  test('⚠️ un montant nul est refusé AVANT écriture', () async {
    await expectLater(
      depot.enregistrer(
        date: DateTime(2026, 8, 19),
        libelle: 'Sac',
        categorie: '601 - Aliments',
        montant: 0,
        compteTresorerieId: compteId,
      ),
      throwsA(isA<DepenseRefusee>()),
    );

    expect(
      await depot.mesDepenses(),
      isEmpty,
      reason: 'rien ne doit rester dans la file d envoi',
    );
  });

  test('⚠️ un compte de charge inconnu est refusé', () async {
    await expectLater(
      depot.enregistrer(
        date: DateTime(2026, 8, 19),
        libelle: 'Sac',
        categorie: '999 - Compte inventé',
        montant: 25000,
        compteTresorerieId: compteId,
      ),
      throwsA(isA<DepenseRefusee>()),
    );

    expect(await depot.mesDepenses(), isEmpty);
  });

  test('⚠️ un compte payeur inconnu est refusé', () async {
    await expectLater(
      depot.enregistrer(
        date: DateTime(2026, 8, 19),
        libelle: 'Sac',
        categorie: '601 - Aliments',
        montant: 25000,
        compteTresorerieId: '11111111-1111-4111-8111-111111111111',
      ),
      throwsA(isA<DepenseRefusee>()),
    );
  });

  test('un libellé vide est refusé', () async {
    await expectLater(
      depot.enregistrer(
        date: DateTime(2026, 8, 19),
        libelle: '   ',
        categorie: '601 - Aliments',
        montant: 25000,
        compteTresorerieId: compteId,
      ),
      throwsA(isA<DepenseRefusee>()),
    );
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

      expect(
        compte.balance,
        500000,
        reason: 'le decaissement reel a lieu au serveur, a la reception',
      );
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

  // ── L'écran : conformité et honnêteté ──────────────────────────────────

  testWidgets("l'ordre des sections suit la maquette", (tester) async {
    await afficher(tester);

    final positions = [
      y(tester, 'Indicateurs de performance'),
      y(tester, 'Nouvelle Dépense'),
      y(tester, 'DATE DE LA TRANSACTION *'),
      y(tester, 'LIBELLÉ DE LA DÉPENSE *'),
      y(tester, 'CATÉGORIE DE CHARGES (SYSCOHADA) *'),
      y(tester, 'MONTANT DÉCAISSÉ (FCFA) *'),
      y(tester, 'COMPTE DE TRÉSORERIE DÉBITÉ *'),
      y(tester, 'REÇU / FACTURE (PHOTO)'),
      y(tester, 'Dépenses saisies sur ce poste'),
    ];

    expect(positions, equals([...positions]..sort()));
  });

  testWidgets(
    "⚠️⚠️ Charges Fixes et Variables affichent un tiret, pas un montant réparti au jugé",
    (tester) async {
      await afficher(tester);

      expect(find.text('CHARGES FIXES'), findsOneWidget);
      expect(find.text('CHARGES VARIABLES'), findsOneWidget);
      expect(
        find.text('—'),
        findsNWidgets(2),
        reason: 'le classement fixe/variable n est defini nulle part',
      );
      expect(find.text('classement à arbitrer'), findsNWidgets(2));
    },
  );

  testWidgets("⚠️ l'écran dit que la liste ne couvre que ce poste", (
    tester,
  ) async {
    await afficher(tester);

    expect(
      find.textContaining("sur le web ou sur un autre poste n'y figurent pas"),
      findsOneWidget,
      reason: 'sinon la liste se lit comme l etat complet de l exploitation',
    );
  });

  testWidgets('⚠️ le champ justificatif annonce sa limite au lieu de mentir', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.textContaining('ne transporte aucun fichier'), findsOneWidget);
  });

  testWidgets('une saisie complète apparaît dans le tableau, « À envoyer »', (
    tester,
  ) async {
    await afficher(tester);

    await tester.enterText(
      find.byKey(const Key('champ-libelle')),
      'Sac de provende ponte',
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('liste-categorie')));
    await tester.tap(find.byKey(const Key('liste-categorie')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('601 - Aliments').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('champ-montant')), '25000');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('liste-compte')));
    await tester.tap(find.byKey(const Key('liste-compte')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caisse Physique (531)').last);
    await tester.pumpAndSettle();

    final bouton = find.byKey(const Key('bouton-enregistrer-depense'));
    await tester.ensureVisible(bouton);
    await tester.tap(bouton);
    await tester.pumpAndSettle();

    expect(await depot.mesDepenses(), hasLength(1));
    expect(find.text('Sac de provende ponte'), findsOneWidget);
    // ⚠️ « À envoyer », jamais « Payée » : tant que la dépense n'est pas
    // partie, elle n'engage rien.
    expect(find.text('À envoyer'), findsOneWidget);
    expect(find.text('25 000 F'), findsWidgets);
  });

  testWidgets('⚠️ un montant vide affiche le motif au lieu d écrire', (
    tester,
  ) async {
    await afficher(tester);

    await tester.enterText(find.byKey(const Key('champ-libelle')), 'Sac');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('liste-categorie')));
    await tester.tap(find.byKey(const Key('liste-categorie')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('601 - Aliments').last);
    await tester.pumpAndSettle();

    final bouton = find.byKey(const Key('bouton-enregistrer-depense'));
    await tester.ensureVisible(bouton);
    await tester.tap(bouton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('erreur-depense')), findsOneWidget);
    expect(await depot.mesDepenses(), isEmpty);
  });

  testWidgets('sans référentiel reçu, l écran renvoie à la synchronisation', (
    tester,
  ) async {
    await db.delete(db.expenseCategories).go();

    await afficher(tester);

    expect(
      find.textContaining('synchronisez le poste avant de saisir'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('bouton-enregistrer-depense')), findsNothing);
  });

  // ── L'accès ────────────────────────────────────────────────────────────

  test(
    "⚠️⚠️ seul l'admin atteint la saisie des dépenses — conséquence de RBAC_PAGE_MAP",
    () {
      // `saisie-depenses.html` n'apparaît dans AUCUNE des quatre listes ; seul
      // `admin`, dont la liste vaut `null`, n'est pas restreint.
      expect(
        PermissionsPoste.autorise('admin', EcranPoste.saisieDepenses),
        isTrue,
      );

      for (final role in ['caissier', 'animalier', 'comptable']) {
        expect(
          PermissionsPoste.autorise(role, EcranPoste.saisieDepenses),
          isFalse,
          reason: '$role ne doit pas decaisser depuis un poste de terrain',
        );
      }
    },
  );
}
