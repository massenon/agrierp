import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/clients/fiche_client_modales.dart';
import 'package:agrierp/features/ventes/choix_facture.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MECEF-3 — l'IFU du client (13 chiffres, FACULTATIF : un client particulier n'en a pas), saisi à la fiche du client au poste comme
/// au web (`CustomerCatalogService`, `ListeClients`) : même règle, même motif, envoyé avec la fiche, préremplit la facture normalisée.
void main() {
  late AppDatabase db;
  late ClientsCreancesRepository depot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ClientsCreancesRepository(database: db, deviceId: 'poste-test');
  });

  tearDown(() async => db.close());

  group('dépôt', () {
    test('la fiche garde l\'IFU saisi (vide = client sans IFU) et repart en attente d\'envoi', () async {
      final avec = await depot.creerClient(const FormulaireClient(nom: 'Société AGRO', ifu: ' 3202601234567 '));
      final sans = await depot.creerClient(const FormulaireClient(nom: 'Particulier'));

      expect([avec.ifu, avec.syncStatus], ['3202601234567', SyncStatus.pending]);
      expect(sans.ifu, isNull);

      final modifiee = await depot.modifierClient(avec.id, const FormulaireClient(nom: 'Société AGRO', ifu: '1111111111111'));
      expect(modifiee.ifu, '1111111111111');
      expect((await depot.modifierClient(avec.id, const FormulaireClient(nom: 'Société AGRO'))).ifu, isNull, reason: 'effacé : client sans IFU');
    });

    test('⚠️ la règle et le motif sont ceux du serveur : 13 chiffres exactement, ou vide', () {
      for (final mauvais in ['12345', '12345678901234', 'ABCDEFGHIJKLM', '320260123456a']) {
        expect(ClientsCreancesRepository.validerFiche(FormulaireClient(nom: 'A', ifu: mauvais))['ifu'], ChoixFacture.motifIfu, reason: mauvais);
      }
      for (final bon in ['', '   ', '3202601234567']) {
        expect(ClientsCreancesRepository.validerFiche(FormulaireClient(nom: 'A', ifu: bon)), isEmpty, reason: '« $bon »');
      }
      // Le même motif que le web (lang/fr/validation.php, `custom.ifu.regex`).
      final php = File('../agrierp_laravel/lang/fr/validation.php');
      if (php.existsSync()) {
        expect(php.readAsStringSync(), contains(ChoixFacture.motifIfu));
      }
    });
  });

  group('écran', () {
    Future<void> ouvrir(WidgetTester tester, {Customer? existant}) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) => TextButton(onPressed: () => ouvrirFicheClient(context: c, depot: depot, existant: existant), child: const Text('ouvrir'))),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('le formulaire porte le champ « IFU » après l\'e-mail, comme le web ; un IFU invalide est refusé avec son motif', (tester) async {
      await ouvrir(tester);

      expect(find.text('IFU'), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('client-ifu'))).dy, greaterThan(tester.getTopLeft(find.byKey(const Key('client-email'))).dy));

      await tester.enterText(find.byKey(const Key('client-nom')), 'Société AGRO');
      await tester.enterText(find.byKey(const Key('client-ifu')), '123');
      await tester.tap(find.byKey(const Key('client-enregistrer')));
      await tester.pumpAndSettle();
      expect(find.text(ChoixFacture.motifIfu), findsOneWidget);
      expect(await db.select(db.customers).get(), isEmpty);

      await tester.enterText(find.byKey(const Key('client-ifu')), '3202601234567');
      await tester.tap(find.byKey(const Key('client-enregistrer')));
      await tester.pumpAndSettle();
      expect((await db.select(db.customers).getSingle()).ifu, '3202601234567');
    });

    testWidgets('modifier un client reprend son IFU', (tester) async {
      final c = await depot.creerClient(const FormulaireClient(nom: 'Société AGRO', ifu: '3202601234567'));
      await ouvrir(tester, existant: c);

      expect(tester.widget<TextField>(find.byKey(const Key('client-ifu'))).controller!.text, '3202601234567');
    });
  });

  test('la fiche client du web porte le même champ (même libellé), le même ordre', () {
    final blade = File('../agrierp_laravel/resources/views/livewire/ventes/liste-clients.blade.php');
    if (!blade.existsSync()) {
      markTestSkipped('SAUT : dépôt Laravel absent');
      return;
    }
    final b = blade.readAsStringSync();
    expect(b, contains('>IFU</label>'));
    expect(b.indexOf('>Email</label>'), lessThan(b.indexOf('>IFU</label>')));
  });
}
