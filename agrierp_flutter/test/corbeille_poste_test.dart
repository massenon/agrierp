import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/gestes_importants.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/widgets/modale_agri.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/parametres/corbeille_repository.dart';
import 'package:agrierp/features/parametres/onglet_corbeille.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tickets ARC3 / ARC4 — LA CORBEILLE AU POSTE (PRD `docs/prd/archives.md`).
///
/// ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. Le poste n'enregistre que la DEMANDE (`corbeille_demandes`) : JAMAIS `is_active`, JAMAIS
/// un effacement de ligne métier — le serveur fait les effets (`CorbeilleService`) et peut refuser. La liste est l'instantané
/// du serveur (avec ce qu'il permet et pourquoi) plus ce que ce poste vient d'archiver lui-même. Les chiffres attendus sont
/// ceux du PRD § 5.3, calculés à la main : client « Kossi Adjovi » (0 vente), client « SOGEA » (3 ventes), dépense de
/// 60 000 FCFA, produit « Maïs » référencé → 4 archivés, 3 restaurables, 1 supprimable.
///
/// Écrits AVANT l'écran (rouge d'abord) ; épreuve de mutation dans le rapport du ticket.
void main() {
  late AppDatabase db;
  late CorbeilleRepository depot;
  late int signaux;

  final maintenant = DateTime(2026, 6, 20, 9);

  String uuid(String graine) => graine.padRight(36, '_').substring(0, 36);

  Future<void> element(
    String type,
    String id,
    String titre, {
    String detail = '',
    String module = 'ventes',
    DateTime? archiveLe,
    String? archivePar,
    bool restaurable = true,
    String? motifRestauration,
    bool supprimable = true,
    String? motifSuppression,
  }) => db.into(db.corbeilleElements).insert(
    CorbeilleElementsCompanion.insert(
      id: uuid('i-$id'),
      type: type,
      elementId: uuid(id),
      titre: titre,
      detail: Value(detail),
      module: module,
      archiveLe: Value(archiveLe ?? maintenant),
      archivePar: Value(archivePar),
      restaurable: restaurable,
      motifRestauration: Value(motifRestauration),
      supprimable: supprimable,
      motifSuppression: Value(motifSuppression),
    ),
  );

  /// L'exemple du PRD § 5.3.
  Future<void> exempleDuPrd() async {
    await element('clients', 'kossi', 'Kossi Adjovi', detail: '+22997000001', archiveLe: DateTime(2026, 6, 5, 8));
    await element(
      'clients',
      'sogea',
      'SOGEA',
      archiveLe: DateTime(2026, 6, 10, 8),
      supprimable: false,
      motifSuppression: 'SOGEA est référencé par 3 vente(s) : il ne peut pas être supprimé, il reste archivé.',
    );
    await element(
      'depenses',
      'depense',
      'Provende ponte, Vermifuge et 1 autre',
      detail: '60 000 FCFA',
      module: 'achats',
      archiveLe: DateTime(2026, 6, 15, 23, 59, 59),
      restaurable: false,
      motifRestauration: CorbeilleRepository.refusDepense,
      supprimable: false,
      motifSuppression: CorbeilleRepository.motifsSuppression['depenses'],
    );
    await element(
      'produits',
      'mais',
      'Maïs concassé',
      detail: 'ALI-001',
      module: 'stocks',
      archiveLe: DateTime(2026, 6, 12, 8),
      supprimable: false,
      motifSuppression: 'Maïs concassé est référencé par 4 ligne(s) de vente : il ne peut pas être supprimé, il reste archivé.',
    );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final gestes = GestesImportants();
    signaux = 0;
    gestes.addListener(() => signaux++);
    depot = CorbeilleRepository(database: db, identifiantPoste: 'poste-test', horloge: () => maintenant, gestes: gestes);
  });

  tearDown(() async => db.close());

  Future<List<DemandeCorbeille>> demandes() => db.select(db.corbeilleDemandes).get();

  // ── La liste ───────────────────────────────────────────────────────────────────────────────────────────────────────────

  group('liste', () {
    test("⚠️ l'instantané du serveur, du plus récemment archivé au plus ancien, avec ce que le serveur permet", () async {
      await exempleDuPrd();

      final l = await depot.lignes();

      expect(l.map((e) => e.titre), ['Provende ponte, Vermifuge et 1 autre', 'Maïs concassé', 'SOGEA', 'Kossi Adjovi']);
      expect(l.map((e) => e.libelleType), ['Dépense', 'Produit', 'Client', 'Client']);
      expect(l.map((e) => e.module), ['achats', 'stocks', 'ventes', 'ventes']);
      final depense = l.first;
      expect(depense.restaurable, isFalse);
      expect(depense.motifRestauration, CorbeilleRepository.refusDepense);
      expect(depense.locale, isFalse);
    });

    test('⚠️ ARC-Q2 — la ligne porte l\'auteur servi (null : inconnu) ; une entité archivée ICI et pas encore servie n\'en a pas', () async {
      await element('clients', 'kossi', 'Kossi Adjovi', archivePar: 'Marie Gestionnaire');
      await element('clients', 'sogea', 'SOGEA');
      await db.into(db.customers).insert(
        CustomersCompanion.insert(id: uuid('client-local'), name: 'Client archivé ici', isActive: const Value(false), syncStatus: const Value(SyncStatus.pending)),
      );

      final l = {for (final e in await depot.lignes()) e.titre: e};

      expect(l['Kossi Adjovi']!.archivePar, 'Marie Gestionnaire');
      expect(l['SOGEA']!.archivePar, isNull);
      expect(l['Client archivé ici']!.locale, isTrue);
      expect(l['Client archivé ici']!.archivePar, isNull, reason: 'le poste ne devine pas : le serveur le dira au prochain tirage');
    });

    test('PRD § 5.3 — les trois cartes : 4 archivés, 3 restaurables, 1 supprimable', () async {
      await exempleDuPrd();

      final c = CorbeilleRepository.cartes(await depot.lignes());

      expect(c.archives, 4);
      // Kossi, SOGEA et le maïs se restaurent ; la dépense non.
      expect(c.restaurables, 3);
      // Kossi seul : SOGEA et le maïs sont référencés, la dépense est un fait comptable.
      expect(c.supprimables, 1);
    });

    test('recherche (casse, accents, espaces ignorés), type, période aux bornes INCLUSIVES', () async {
      await exempleDuPrd();
      final l = await depot.lignes();

      expect(CorbeilleRepository.filtrer(l, recherche: 'MAIS').map((e) => e.type), ['produits']);
      expect(CorbeilleRepository.filtrer(l, recherche: 'kossi  adjovi').map((e) => e.type), ['clients']);
      // la recherche porte aussi sur le TYPE affiché
      expect(CorbeilleRepository.filtrer(l, recherche: 'depense').map((e) => e.type), ['depenses']);
      expect(CorbeilleRepository.filtrer(l, type: 'clients'), hasLength(2));
      // la dépense est archivée le 15 à 23:59:59 : dans « au 15 »
      expect(CorbeilleRepository.filtrer(l, du: DateTime(2026, 6, 5), au: DateTime(2026, 6, 15)), hasLength(4));
      expect(CorbeilleRepository.filtrer(l, du: DateTime(2026, 6, 6), au: DateTime(2026, 6, 14)).map((e) => e.type), ['produits', 'clients']);
      expect(CorbeilleRepository.filtrer(l, du: DateTime(2026, 6, 15)), hasLength(1));
      expect(CorbeilleRepository.filtrer(l, au: DateTime(2026, 6, 10)), hasLength(2));
      expect(CorbeilleRepository.filtrer(l, recherche: 'introuvable'), isEmpty);
    });

    test('⚠️⚠️ ce que CE poste vient d\'archiver apparaît dès l\'archivage, avec les règles de son type', () async {
      await db.into(db.customers).insert(
        CustomersCompanion.insert(
          id: uuid('client-local'),
          name: 'Client archivé ici',
          phone: const Value('+22997111111'),
          isActive: const Value(false),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: uuid('depense-locale'),
          deviceId: 'poste-test',
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: DateTime.utc(2026, 6, 20, 8),
          expenseDate: DateTime(2026, 6, 19),
          label: 'Transport',
          category: 'transport',
          amount: 12500,
          treasuryAccountId: Value(uuid('caisse')),
          isActive: const Value(false),
        ),
      );

      final l = await depot.lignes();

      final client = l.singleWhere((e) => e.type == 'clients');
      expect(client.titre, 'Client archivé ici');
      expect(client.detail, '+22997111111');
      expect(client.locale, isTrue);
      expect(client.restaurable, isTrue);
      expect(client.supprimable, isTrue, reason: 'règle du TYPE : le serveur juge les références à l\'envoi');
      final depense = l.singleWhere((e) => e.type == 'depenses');
      expect(depense.titre, 'Transport');
      expect(depense.detail, '12 500 FCFA');
      expect(depense.restaurable, isFalse);
      expect(depense.motifRestauration, CorbeilleRepository.refusDepense);
      expect(depense.supprimable, isFalse);
      expect(depense.motifSuppression, CorbeilleRepository.motifsSuppression['depenses']);
      // 20/06/2026 08:00 UTC = 09:00 au Bénin
      expect(depense.archiveLe, DateTime(2026, 6, 20, 9));
    });

    test('une entité archivée déjà ACQUITTÉE n\'y revient pas (elle est dans l\'instantané, ou supprimée), ni deux fois', () async {
      await db.into(db.customers).insert(
        CustomersCompanion.insert(id: uuid('client-synced'), name: 'Déjà acquitté', isActive: const Value(false), syncStatus: const Value(SyncStatus.synced)),
      );
      await db.into(db.customers).insert(
        CustomersCompanion.insert(id: uuid('client-connu'), name: 'Connu du serveur', isActive: const Value(false), syncStatus: const Value(SyncStatus.pending)),
      );
      await element('clients', 'client-connu', 'Connu du serveur');

      final l = await depot.lignes();

      expect(l.map((e) => e.titre), ['Connu du serveur']);
      expect(l.single.locale, isFalse, reason: 'la ligne du serveur l\'emporte : pas de doublon');
    });

    test('une vente annulée et un transfert annulé au poste sont en consultation seule', () async {
      await db.into(db.sales).insert(
        SalesCompanion.insert(
          id: uuid('vente-annulee'),
          deviceId: 'poste-test',
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: DateTime.utc(2026, 6, 20, 8),
          paymentMode: 'especes',
          total: 5000,
          status: const Value('annulee'),
          soldAt: DateTime(2026, 6, 10, 10),
        ),
      );

      final v = (await depot.lignes()).single;

      expect(v.titre, 'Vente du 10/06/2026');
      expect(v.detail, '5 000 FCFA');
      expect(v.libelleType, 'Vente annulée');
      expect(v.restaurable, isFalse);
      expect(v.motifRestauration, CorbeilleRepository.refusVente);
      expect(v.supprimable, isFalse);
    });

    test('les types du poste sont ceux du registre du serveur, dans son ordre', () {
      expect(TypesCorbeille.tous.map((t) => t.cle), [
        'produits', 'fournisseurs', 'clients', 'depenses', 'bandes', 'soins', 'rations', 'provendes', 'prophylaxie', 'absences',
        'documents', 'pieces', 'courriers', 'comptes', 'devis', 'avances', 'employes', 'pointages', 'ventes', 'transferts',
      ]);
      expect(TypesCorbeille.tous.where((t) => t.restaurationInterdite).map((t) => t.cle), ['depenses', 'ventes', 'transferts']);
      expect(TypesCorbeille.tous.where((t) => t.suppressionAdmise).map((t) => t.cle), [
        'produits', 'fournisseurs', 'clients', 'rations', 'provendes', 'prophylaxie', 'absences', 'documents', 'pieces', 'employes',
      ]);
    });
  });

  // ── Les demandes ───────────────────────────────────────────────────────────────────────────────────────────────────────

  group('demandes', () {
    test('⚠️⚠️ « Restaurer » écrit UNE demande en attente — JAMAIS is_active, jamais de ligne métier touchée — et signale la synchronisation', () async {
      await exempleDuPrd();
      await db.into(db.customers).insert(
        CustomersCompanion.insert(id: uuid('kossi'), name: 'Kossi Adjovi', isActive: const Value(false), syncStatus: const Value(SyncStatus.synced)),
      );
      final kossi = (await depot.lignes()).singleWhere((e) => e.titre == 'Kossi Adjovi');

      final r = await depot.demanderRestauration(kossi);

      expect(r.ok, isTrue);
      expect(r.message, 'Restauration demandée : elle sera faite par le serveur à la prochaine synchronisation.');
      final d = (await demandes()).single;
      expect(d.type, 'clients');
      expect(d.elementId, uuid('kossi'));
      expect(d.action, 'restaurer');
      expect(d.confirmation, isNull);
      expect(d.syncStatus, SyncStatus.pending);
      expect(d.deviceId, 'poste-test');
      expect(d.titre, 'Kossi Adjovi');
      expect(d.id, hasLength(36));
      // La ligne métier n'a PAS bougé : le serveur fait l'effet.
      final client = await (db.select(db.customers)..where((c) => c.id.equals(uuid('kossi')))).getSingle();
      expect(client.isActive, isFalse);
      expect(client.syncStatus, SyncStatus.synced);
      expect(signaux, 1);
    });

    test('⚠️ une ligne annoncée non restaurable est refusée AVANT d\'écrire, avec le motif du serveur', () async {
      await exempleDuPrd();
      final depense = (await depot.lignes()).singleWhere((e) => e.type == 'depenses');

      final r = await depot.demanderRestauration(depense);

      expect(r.ok, isFalse);
      expect(r.message, CorbeilleRepository.refusDepense);
      expect(await demandes(), isEmpty);
      expect(signaux, 0);
    });

    test('« Supprimer définitivement » exige le mot SUPPRIMER exactement, puis écrit la demande avec le mot', () async {
      await exempleDuPrd();
      final kossi = (await depot.lignes()).singleWhere((e) => e.titre == 'Kossi Adjovi');

      for (final mauvais in ['', 'supprimer', 'SUPPRIMER ', 'OUI', 'Supprimer']) {
        final r = await depot.demanderSuppression(kossi, mauvais);
        expect(r.ok, isFalse, reason: '« $mauvais » accepté');
        expect(r.message, 'Pour confirmer, saisissez le mot SUPPRIMER.');
      }
      expect(await demandes(), isEmpty);

      final r = await depot.demanderSuppression(kossi, 'SUPPRIMER');

      expect(r.ok, isTrue);
      expect(r.message, 'Suppression définitive demandée : elle sera faite par le serveur à la prochaine synchronisation.');
      final d = (await demandes()).single;
      expect(d.action, 'supprimer');
      expect(d.confirmation, 'SUPPRIMER');
      expect(d.syncStatus, SyncStatus.pending);
    });

    test('une ligne annoncée non supprimable (référencée, fait comptable) est refusée avant d\'écrire, avec son motif', () async {
      await exempleDuPrd();
      final sogea = (await depot.lignes()).singleWhere((e) => e.titre == 'SOGEA');
      final depense = (await depot.lignes()).singleWhere((e) => e.type == 'depenses');

      final a = await depot.demanderSuppression(sogea, 'SUPPRIMER');
      final b = await depot.demanderSuppression(depense, 'SUPPRIMER');

      expect(a.ok, isFalse);
      expect(a.message, 'SOGEA est référencé par 3 vente(s) : il ne peut pas être supprimé, il reste archivé.');
      expect(b.ok, isFalse);
      expect(b.message, CorbeilleRepository.motifsSuppression['depenses']);
      expect(await demandes(), isEmpty);
    });

    test('une demande déjà en attente pour l\'élément n\'est pas doublée', () async {
      await exempleDuPrd();
      final kossi = (await depot.lignes()).singleWhere((e) => e.titre == 'Kossi Adjovi');
      await depot.demanderRestauration(kossi);

      final enAttente = (await depot.lignes()).singleWhere((e) => e.titre == 'Kossi Adjovi');
      expect(enAttente.enAttente, isTrue);
      final r = await depot.demanderSuppression(enAttente, 'SUPPRIMER');

      expect(r.ok, isFalse);
      expect(r.message, CorbeilleRepository.messageDemandeEnAttente);
      expect(await demandes(), hasLength(1));
    });

    test('⚠️ une demande REFUSÉE (conflict) est remplacée par la suivante : une seule demande par élément, refus effacé', () async {
      await exempleDuPrd();
      final kossi = (await depot.lignes()).singleWhere((e) => e.titre == 'Kossi Adjovi');
      await depot.demanderRestauration(kossi);
      final ancienne = (await demandes()).single;
      await (db.update(db.corbeilleDemandes)..where((d) => d.id.equals(ancienne.id))).write(
        const CorbeilleDemandesCompanion(syncStatus: Value(SyncStatus.conflict)),
      );
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'corbeille_demandes:${ancienne.id}',
          sourceTable: 'corbeille_demandes',
          recordId: ancienne.id,
          reason: 'Restauration impossible : élément introuvable ou déjà restauré.',
          detectedAt: DateTime(2026, 6, 20),
        ),
      );
      final refusee = (await depot.lignes()).singleWhere((e) => e.titre == 'Kossi Adjovi');
      expect(refusee.refusee, isTrue);
      expect(refusee.refus, 'Restauration impossible : élément introuvable ou déjà restauré.');

      final r = await depot.demanderSuppression(refusee, 'SUPPRIMER');

      expect(r.ok, isTrue);
      final d = (await demandes()).single;
      expect(d.action, 'supprimer');
      expect(d.id, isNot(ancienne.id));
      expect(await db.select(db.syncConflicts).get(), isEmpty, reason: 'le refus de la demande remplacée ne survit pas');
    });
  });

  // ── L'écran ────────────────────────────────────────────────────────────────────────────────────────────────────────────

  group('écran', () {
    Future<void> monter(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      HeureBenin.horloge = () => maintenant.subtract(HeureBenin.decalage);
      addTearDown(HeureBenin.reinitialiser);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OngletCorbeille(depot: depot)),
        ),
      );
      await tester.pumpAndSettle();
    }

    String valeur(WidgetTester tester, String cle) => tester
        .widgetList<Text>(find.descendant(of: find.byKey(Key(cle)), matching: find.byType(Text)))
        .map((t) => t.data)
        .join('|');

    testWidgets("l'en-tête, trois cartes et leurs valeurs (PRD § 5.3) : 4, 3, 1", (tester) async {
      await exempleDuPrd();
      await monter(tester);

      expect(find.text('Corbeille'), findsOneWidget);
      expect(find.textContaining("Rien n'est effacé par erreur"), findsOneWidget);
      expect(find.byType(CarteKpi), findsNWidgets(3));
      for (final l in ['ÉLÉMENTS ARCHIVÉS', 'RESTAURABLES', 'SUPPRESSION DÉFINITIVE POSSIBLE']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(valeur(tester, 'kpi-Éléments archivés'), contains('4'));
      expect(valeur(tester, 'kpi-Restaurables'), contains('3'));
      expect(valeur(tester, 'kpi-Suppression définitive possible'), contains('1'));
    });

    testWidgets('le tableau : sept colonnes, une ligne par élément, « — » pour un détail vide, jour et heure du Bénin', (tester) async {
      await element('provendes', 'prov', 'Provende croissance', module: 'elevage', archiveLe: DateTime(2026, 6, 20, 9, 5));
      await monter(tester);

      for (final c in ['TYPE', 'ÉLÉMENT', 'DÉTAIL', 'MODULE', 'ARCHIVÉ LE', 'ARCHIVÉ PAR', 'ACTIONS']) {
        // « TYPE » est aussi l'étiquette du filtre : deux occurrences.
        expect(find.text(c), c == 'TYPE' ? findsNWidgets(2) : findsOneWidget, reason: c);
      }
      expect(find.text('Type de provende'), findsWidgets);
      expect(find.text('Provende croissance'), findsOneWidget);
      // deux « — » : le détail vide ET l'auteur inconnu (ARC-Q2)
      expect(find.text('—'), findsNWidgets(2), reason: 'détail vide + auteur inconnu');
      expect(find.text('Elevage'), findsOneWidget, reason: 'ucfirst(module)');
      expect(find.text('20/06/2026 à 09:05'), findsOneWidget);
    });

    testWidgets('⚠️ le refus est DIT par une phrase, sans bouton mort : « Non restaurable : … » et « Suppression définitive impossible : … »', (tester) async {
      await exempleDuPrd();
      await monter(tester);

      expect(find.text('Non restaurable : ${CorbeilleRepository.refusDepense}'), findsOneWidget);
      expect(find.text('Suppression définitive impossible : ${CorbeilleRepository.motifsSuppression['depenses']}'), findsOneWidget);
      expect(
        find.text('Suppression définitive impossible : SOGEA est référencé par 3 vente(s) : il ne peut pas être supprimé, il reste archivé.'),
        findsOneWidget,
      );
      // 3 restaurables, 1 supprimable : trois « Restaurer », un seul « Supprimer définitivement »
      expect(find.text('Restaurer'), findsNWidgets(3));
      expect(find.text('Supprimer définitivement'), findsOneWidget);
    });

    testWidgets('« Restaurer » pose la demande, le dit (toast) et la ligne affiche « Demande en attente d\'envoi »', (tester) async {
      await exempleDuPrd();
      await monter(tester);

      await tester.tap(find.byKey(Key('corbeille-restaurer-clients-${uuid('kossi')}')));
      await tester.pumpAndSettle();

      expect(find.text('Restauration demandée : elle sera faite par le serveur à la prochaine synchronisation.'), findsOneWidget);
      expect((await demandes()).single.action, 'restaurer');
      expect(find.text("Demande en attente d'envoi"), findsOneWidget);
      // la ligne n'offre plus d'action tant que la demande n'est pas partie
      final bouton = tester.widget<TextButton>(find.byKey(Key('corbeille-restaurer-clients-${uuid('kossi')}')));
      expect(bouton.onPressed, isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('⚠️⚠️ suppression en DEUX TEMPS : la modale, le bouton grisé tant que le mot n\'est pas exact, puis la demande', (tester) async {
      await exempleDuPrd();
      await monter(tester);

      await tester.tap(find.byKey(Key('corbeille-supprimer-clients-${uuid('kossi')}')));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer définitivement ?'), findsOneWidget);
      expect(
        find.text("Kossi Adjovi (Client) sera supprimé définitivement. Cette action est irréversible : l'élément ne pourra plus être restauré."),
        findsOneWidget,
      );
      expect(find.text('Pour confirmer, saisissez le mot SUPPRIMER'), findsOneWidget);

      VoidCallback? confirmer() => tester.widget<BoutonModalePrimaire>(find.byKey(const Key('corbeille-confirmer-suppression'))).onPressed;
      expect(confirmer(), isNull, reason: 'grisé sans mot');
      await tester.enterText(find.byKey(const Key('corbeille-confirmation')), 'supprimer');
      await tester.pump();
      expect(confirmer(), isNull, reason: 'la casse compte');
      await tester.enterText(find.byKey(const Key('corbeille-confirmation')), 'SUPPRIMER');
      await tester.pump();
      expect(confirmer(), isNotNull);

      await tester.tap(find.byKey(const Key('corbeille-confirmer-suppression')));
      await tester.pumpAndSettle();

      final d = (await demandes()).single;
      expect((d.action, d.confirmation, d.type, d.elementId), ('supprimer', 'SUPPRIMER', 'clients', uuid('kossi')));
      expect(find.text('Suppression définitive demandée : elle sera faite par le serveur à la prochaine synchronisation.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('« Annuler » dans la modale n\'écrit rien', (tester) async {
      await exempleDuPrd();
      await monter(tester);

      await tester.tap(find.byKey(Key('corbeille-supprimer-clients-${uuid('kossi')}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(await demandes(), isEmpty);
      expect(find.text('Supprimer définitivement ?'), findsNothing);
    });

    testWidgets('l\'état de la demande : traitée par le serveur, et REFUSÉE avec son motif mot pour mot', (tester) async {
      await exempleDuPrd();
      await db.into(db.corbeilleDemandes).insert(
        CorbeilleDemandesCompanion.insert(
          id: uuid('demande-1'),
          deviceId: 'poste-test',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: DateTime.utc(2026, 6, 20, 8),
          type: 'clients',
          elementId: uuid('kossi'),
          action: 'restaurer',
        ),
      );
      await db.into(db.corbeilleDemandes).insert(
        CorbeilleDemandesCompanion.insert(
          id: uuid('demande-2'),
          deviceId: 'poste-test',
          syncStatus: const Value(SyncStatus.conflict),
          updatedAt: DateTime.utc(2026, 6, 20, 8),
          type: 'clients',
          elementId: uuid('sogea'),
          action: 'supprimer',
          confirmation: const Value('SUPPRIMER'),
        ),
      );
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'corbeille_demandes:${uuid('demande-2')}',
          sourceTable: 'corbeille_demandes',
          recordId: uuid('demande-2'),
          reason: 'SOGEA est référencé par 3 vente(s) : il ne peut pas être supprimé, il reste archivé.',
          detectedAt: DateTime(2026, 6, 20),
        ),
      );
      await monter(tester);

      expect(find.text('Demande traitée par le serveur'), findsOneWidget);
      expect(
        find.text('Refusée par le serveur : SOGEA est référencé par 3 vente(s) : il ne peut pas être supprimé, il reste archivé.'),
        findsOneWidget,
      );
    });

    testWidgets('filtres : recherche, type, période et « Réinitialiser » (visible seulement quand un filtre est posé)', (tester) async {
      await exempleDuPrd();
      await monter(tester);
      expect(find.byKey(const Key('corbeille-reinitialiser')), findsNothing);

      await tester.enterText(find.byKey(const Key('corbeille-recherche')), 'sogea');
      await tester.pump(OngletCorbeille.delaiRecherche + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('SOGEA'), findsOneWidget);
      expect(find.text('Kossi Adjovi'), findsNothing);
      expect(find.byKey(const Key('corbeille-reinitialiser')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('corbeille-recherche')), 'zzz');
      await tester.pump(OngletCorbeille.delaiRecherche + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Aucun élément archivé ne correspond à cette recherche.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('corbeille-reinitialiser')));
      await tester.pumpAndSettle();
      expect(find.text('Kossi Adjovi'), findsOneWidget);
      expect(find.byKey(const Key('corbeille-reinitialiser')), findsNothing);

      await tester.tap(find.byKey(const Key('corbeille-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dépense').last);
      await tester.pumpAndSettle();
      expect(find.text('Kossi Adjovi'), findsNothing);
      expect(find.text('Provende ponte, Vermifuge et 1 autre'), findsOneWidget);
    });

    testWidgets('la corbeille vide le dit ; 27 éléments : pagination de 25', (tester) async {
      await monter(tester);
      expect(find.text('La corbeille est vide — aucun élément archivé.'), findsOneWidget);
      expect(find.text('0 élément — page 1 sur 1'), findsOneWidget);
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      depot = CorbeilleRepository(database: db, identifiantPoste: 'poste-test', horloge: () => maintenant);
      for (var i = 1; i <= 27; i++) {
        await element('clients', 'client-$i', 'Client ${i.toString().padLeft(2, '0')}', archiveLe: DateTime(2026, 6, 1).add(Duration(minutes: i)));
      }
      await tester.pumpWidget(const SizedBox());
      await monter(tester);

      expect(find.text('27 éléments — page 1 sur 2'), findsOneWidget);
      expect(find.text('Client 27'), findsOneWidget, reason: 'le plus récent d\'abord');
      expect(find.text('Client 03'), findsOneWidget);
      expect(find.text('Client 02'), findsNothing, reason: 'les 26e et 27e sont sur la page 2');
      await tester.ensureVisible(find.byKey(const Key('pagination-corbeille-suivant')));
      await tester.tap(find.byKey(const Key('pagination-corbeille-suivant')));
      await tester.pumpAndSettle();
      expect(find.text('27 éléments — page 2 sur 2'), findsOneWidget);
      expect(find.text('Client 01'), findsOneWidget);
      expect(find.text('Client 02'), findsOneWidget);
    });

    testWidgets('⚠️ ARC-Q2 — « Archivé par » affiche le nom servi par le serveur, « — » quand il est inconnu (jamais « 0 », jamais un nom inventé)', (tester) async {
      await element('clients', 'kossi', 'Kossi Adjovi', detail: '+22997000001', archivePar: 'Marie Gestionnaire');
      await element('fournisseurs', 'ancien', 'Ancien fournisseur', detail: 'x');
      await monter(tester);

      expect(find.text('ARCHIVÉ PAR'), findsOneWidget);
      expect(find.text('Marie Gestionnaire'), findsOneWidget);
      expect(find.text('—'), findsOneWidget, reason: "l'ancien archivage : un seul tiret (détail renseigné), pas de nom");
      expect(find.text('0'), findsNothing);
    });

    testWidgets('une entité archivée sur ce poste porte la mention « Archivé sur ce poste — pas encore synchronisé »', (tester) async {
      await db.into(db.customers).insert(
        CustomersCompanion.insert(id: uuid('client-local'), name: 'Client archivé ici', isActive: const Value(false), syncStatus: const Value(SyncStatus.pending)),
      );
      await monter(tester);

      expect(find.text('Client archivé ici'), findsOneWidget);
      expect(find.text('Archivé sur ce poste — pas encore synchronisé'), findsOneWidget);
    });
  });
}
