import 'dart:math';

import 'package:agrierp/core/auth/verrou_local.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

/// Ticket VL-1 — verrou local : le service du code PIN (dérivation salée, compteur d'échecs, temporisation).
///
/// Les tests emploient peu d'itérations (vitesse) ; un test dédié vérifie que le réglage de production est au moins
/// de 100 000.
void main() {
  late CoffreMemoire coffre;
  late DateTime maintenant;
  late VerrouLocal verrou;

  setUp(() {
    coffre = CoffreMemoire();
    maintenant = DateTime.utc(2026, 10, 21, 8);
    verrou = VerrouLocal(
      coffre: coffre,
      horloge: () => maintenant,
      alea: Random(1),
      iterations: 50,
    );
  });

  test('le réglage de production dérive en au moins 100 000 itérations', () {
    expect(VerrouLocal.iterationsParDefaut, greaterThanOrEqualTo(100000));
  });

  test("la dérivation PBKDF2-HMAC-SHA256 est conforme au vecteur RFC 7914 (c = 1)", () {
    // RFC 7914 §11 : PBKDF2-HMAC-SHA-256 (P = "passwd", S = "salt", c = 1, dkLen = 32).
    final cle = VerrouLocal.deriver('passwd', 'salt'.codeUnits, 1);
    final hex = cle.map((o) => o.toRadixString(16).padLeft(2, '0')).join();
    expect(hex, '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc');
  });

  test('deux sels différents donnent deux empreintes différentes pour le même PIN', () {
    final a = VerrouLocal.deriver('1234', List.filled(16, 1), 50);
    final b = VerrouLocal.deriver('1234', List.filled(16, 2), 50);
    expect(a, isNot(b));
  });

  test("définir un PIN : jamais en clair au coffre, sel et empreinte par utilisateur", () async {
    await verrou.definir('u1', '123456');
    expect(await verrou.estDefini('u1'), isTrue);
    expect(await verrou.estDefini('u2'), isFalse);
    expect(coffre.contenu.values.any((v) => v.contains('123456')), isFalse);
    expect(coffre.contenu.keys.single, contains('u1'));
  });

  test('deux utilisateurs avec le même PIN ont des sels, donc des empreintes, différents', () async {
    await verrou.definir('u1', '1234');
    await verrou.definir('u2', '1234');
    expect(coffre.contenu.values.toSet().length, 2);
  });

  test('longueur de 4 à 6 chiffres exigée, chiffres seulement', () async {
    expect(VerrouLocal.pinValide('123'), isFalse);
    expect(VerrouLocal.pinValide('1234'), isTrue);
    expect(VerrouLocal.pinValide('123456'), isTrue);
    expect(VerrouLocal.pinValide('1234567'), isFalse);
    expect(VerrouLocal.pinValide('12a4'), isFalse);
    await expectLater(verrou.definir('u1', '123'), throwsArgumentError);
    await expectLater(verrou.definir('u1', 'abcd'), throwsArgumentError);
  });

  test('le bon PIN est accepté, le mauvais refusé', () async {
    await verrou.definir('u1', '1234');
    expect((await verrou.verifier('u1', '1234')).resultat, ResultatVerrou.ok);
    final t = await verrou.verifier('u1', '4321');
    expect(t.resultat, ResultatVerrou.refuse);
    expect(t.echecs, 1);
  });

  test("sans PIN défini, rien n'est accepté", () async {
    expect((await verrou.verifier('u1', '1234')).resultat, ResultatVerrou.refuse);
  });

  test("le compteur d'échecs survit à un nouveau service (persistant) et un succès le remet à zéro", () async {
    await verrou.definir('u1', '1234');
    await verrou.verifier('u1', '0000');
    await verrou.verifier('u1', '0000');
    final relance = VerrouLocal(coffre: coffre, horloge: () => maintenant, iterations: 50);
    expect((await relance.verifier('u1', '0000')).echecs, 3);
    expect((await relance.verifier('u1', '1234')).resultat, ResultatVerrou.ok);
    expect((await relance.verifier('u1', '0000')).echecs, 1);
  });

  test('quatre échecs : pas de temporisation ; le cinquième impose 30 s', () async {
    await verrou.definir('u1', '1234');
    for (var i = 0; i < 4; i++) {
      expect((await verrou.verifier('u1', '0000')).resultat, ResultatVerrou.refuse);
    }
    final t = await verrou.verifier('u1', '0000');
    expect(t.resultat, ResultatVerrou.temporise);
    expect(t.attente, const Duration(seconds: 30));
  });

  test('pendant la temporisation, même le bon PIN est refusé sans être examiné', () async {
    await verrou.definir('u1', '1234');
    for (var i = 0; i < 5; i++) {
      await verrou.verifier('u1', '0000');
    }
    maintenant = maintenant.add(const Duration(seconds: 10));
    final t = await verrou.verifier('u1', '1234');
    expect(t.resultat, ResultatVerrou.temporise);
    expect(t.attente, const Duration(seconds: 20));
    expect((await verrou.etat('u1')).resultat, ResultatVerrou.temporise);
  });

  test('après le délai, le bon PIN passe et le compteur repart de zéro', () async {
    await verrou.definir('u1', '1234');
    for (var i = 0; i < 5; i++) {
      await verrou.verifier('u1', '0000');
    }
    maintenant = maintenant.add(const Duration(seconds: 31));
    expect((await verrou.verifier('u1', '1234')).resultat, ResultatVerrou.ok);
    expect((await verrou.verifier('u1', '0000')).echecs, 1);
  });

  test('la temporisation croît : 30 s, 1 min, 5 min, 15 min, 30 min', () async {
    await verrou.definir('u1', '1234');
    final attentes = <Duration>[];
    for (var i = 0; i < 9; i++) {
      final t = await verrou.verifier('u1', '0000');
      if (t.resultat == ResultatVerrou.temporise) {
        attentes.add(t.attente!);
        maintenant = maintenant.add(t.attente! + const Duration(seconds: 1));
      }
    }
    expect(attentes, const [
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
      Duration(minutes: 30),
    ]);
  });

  test("reculer l'horloge ne raccourcit pas l'attente en cours (borne : depuis le dernier essai)", () async {
    await verrou.definir('u1', '1234');
    for (var i = 0; i < 5; i++) {
      await verrou.verifier('u1', '0000');
    }
    maintenant = maintenant.subtract(const Duration(days: 1));
    final t = await verrou.verifier('u1', '1234');
    expect(t.resultat, ResultatVerrou.temporise);
    expect(t.attente, const Duration(seconds: 30));
  });

  test('dix échecs cumulés : accès local refusé, reconnexion en ligne exigée, même avec le bon PIN', () async {
    await verrou.definir('u1', '1234');
    ResultatVerrou? dernier;
    for (var i = 0; i < 10; i++) {
      dernier = (await verrou.verifier('u1', '0000')).resultat;
      maintenant = maintenant.add(const Duration(hours: 2));
    }
    expect(dernier, ResultatVerrou.reconnexionRequise);
    expect((await verrou.verifier('u1', '1234')).resultat, ResultatVerrou.reconnexionRequise);
    expect((await verrou.etat('u1')).resultat, ResultatVerrou.reconnexionRequise);
  });

  test("effacer : le PIN disparaît (la reconnexion en ligne le redéfinit)", () async {
    await verrou.definir('u1', '1234');
    await verrou.effacer('u1');
    expect(await verrou.estDefini('u1'), isFalse);
    await verrou.definir('u1', '5678');
    expect((await verrou.verifier('u1', '5678')).resultat, ResultatVerrou.ok);
  });

  test("changer : l'ancien PIN est requis, le nouveau remplace l'ancien", () async {
    await verrou.definir('u1', '1234');
    expect((await verrou.changer('u1', ancien: '0000', nouveau: '5678')).resultat, ResultatVerrou.refuse);
    expect((await verrou.verifier('u1', '1234')).resultat, ResultatVerrou.ok);

    expect((await verrou.changer('u1', ancien: '1234', nouveau: '5678')).resultat, ResultatVerrou.ok);
    expect((await verrou.verifier('u1', '1234')).resultat, ResultatVerrou.refuse);
    expect((await verrou.verifier('u1', '5678')).resultat, ResultatVerrou.ok);
    await expectLater(verrou.changer('u1', ancien: '5678', nouveau: '12'), throwsArgumentError);
  });

  test("un PIN faux au changement compte comme un échec (pas de contournement par Mon profil)", () async {
    await verrou.definir('u1', '1234');
    for (var i = 0; i < 5; i++) {
      await verrou.changer('u1', ancien: '0000', nouveau: '5678');
    }
    expect((await verrou.etat('u1')).resultat, ResultatVerrou.temporise);
  });
}
