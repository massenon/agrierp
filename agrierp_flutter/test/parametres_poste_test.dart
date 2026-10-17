import 'package:agrierp/core/config/parametres_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/parametres/parametres_poste_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 0 Flutter — RÉGLAGES DU POSTE.
///
/// 🔴 Ce que ce ticket corrige : `deviceId` valait la constante `'poste-dev'`
/// partout, et l'adresse du serveur pointait sur `127.0.0.1`. Toutes les
/// installations auraient partagé le même identifiant — deux postes de la ferme
/// indiscernables, et plus aucun conflit explicable.
void main() {
  late AppDatabase db;
  late ParametresPoste parametres;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    parametres = ParametresPoste(database: db);
  });

  tearDown(() async => db.close());

  /// ⚠️ L'IDENTIFIANT NE CHANGE JAMAIS APRÈS SON PREMIER TIRAGE : il faut
  /// pouvoir dire quel poste a produit une saisie, des mois plus tard.
  test('l identifiant est tire une fois puis conserve', () async {
    final premier = await parametres.identifiant();
    final second = await parametres.identifiant();

    expect(premier, second);
    expect(premier, startsWith('poste-'));
  });

  /// Deux postes distincts obtiennent des identifiants distincts — c'est tout
  /// l'objet du changement.
  test('deux postes obtiennent des identifiants distincts', () async {
    final autreDb = AppDatabase.forTesting(NativeDatabase.memory());
    final autre = ParametresPoste(database: autreDb);

    final a = await parametres.identifiant();
    final b = await autre.identifiant();

    expect(a, isNot(b));

    await autreDb.close();
  });

  test('l adresse par defaut est locale tant que rien n est designe', () async {
    expect(await parametres.adresseServeur(), ParametresPoste.adresseParDefaut);
  });

  test('l adresse designee est conservee', () async {
    await parametres.definirAdresseServeur('http://192.168.1.10:8000');

    expect(await parametres.adresseServeur(), 'http://192.168.1.10:8000');
  });

  /// ⚠️ Une barre oblique finale produirait `//api/sync/pull` — un chemin que
  /// le serveur ne reconnaît pas, et une panne d'autant plus déroutante que
  /// l'adresse « a l'air bonne ».
  test('la barre oblique finale est retiree', () async {
    await parametres.definirAdresseServeur('http://192.168.1.10:8000/');

    expect(await parametres.adresseServeur(), 'http://192.168.1.10:8000');
  });

  /// ⚠️ Sans schéma, le client HTTP échoue sur une erreur peu parlante.
  test('un schema manquant est ajoute', () async {
    await parametres.definirAdresseServeur('192.168.1.10:8000');

    expect(await parametres.adresseServeur(), 'http://192.168.1.10:8000');
  });

  /// Une saisie vide ne doit pas effacer une adresse valide.
  test('une adresse vide ne remplace rien', () async {
    await parametres.definirAdresseServeur('http://192.168.1.10:8000');
    await parametres.definirAdresseServeur('   ');

    expect(await parametres.adresseServeur(), 'http://192.168.1.10:8000');
  });

  testWidgets('l ecran affiche l identifiant et enregistre l adresse', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ParametresPosteScreen(
          parametres: parametres,
          identifiantActuel: 'poste-a1b2c3d4',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('identifiant-poste')))
          .data,
      'poste-a1b2c3d4',
    );

    await tester.enterText(
      find.byKey(const Key('adresse-serveur')),
      '10.0.0.5:8000',
    );
    await tester.tap(find.byKey(const Key('enregistrer-adresse')));
    await tester.pumpAndSettle();

    expect(await parametres.adresseServeur(), 'http://10.0.0.5:8000');
    expect(
      tester.widget<Text>(find.byKey(const Key('adresse-actuelle'))).data,
      'Actuelle : http://10.0.0.5:8000',
    );
    // ⚠️ Le client HTTP est construit au démarrage : l'écran doit dire qu'il
    // faut relancer, sinon on croit à une panne réseau.
    expect(find.textContaining('Redémarrez'), findsOneWidget);
  });
}
