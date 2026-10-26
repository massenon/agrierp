import 'dart:math';

import 'package:agrierp/core/auth/verrou_inactivite.dart';
import 'package:agrierp/core/auth/verrou_local.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

/// Ticket VL-2 — verrouillage automatique après inactivité (décision du client du 21/10/2026, VL-Q1 : OUI).
///
/// Le minuteur est une `Timer` : `FakeAsync` le pilote, aucune attente réelle.
void main() {
  late CoffreMemoire coffre;
  late VerrouLocal verrou;
  late ReglageInactivite reglage;
  late VerrouInactivite controle;
  late int verrouillages;

  setUp(() {
    coffre = CoffreMemoire();
    verrou = VerrouLocal(coffre: coffre, alea: Random(1), iterations: 20);
    reglage = ReglageInactivite(coffre: coffre);
    controle = VerrouInactivite(reglage: reglage, verrou: verrou);
    verrouillages = 0;
  });

  /// Arme le contrôle pour [id] (PIN défini sauf [sansPin]) et laisse les lectures asynchrones se résoudre.
  void armer(FakeAsync fa, {String id = 'u1', bool sansPin = false}) {
    if (!sansPin) verrou.definir(id, '1234');
    fa.flushMicrotasks();
    controle.armer(idUtilisateur: id, verrouiller: () => verrouillages++);
    fa.flushMicrotasks();
  }

  group('durée', () {
    test('par défaut : 5 minutes, et les choix sont Jamais / 1 / 5 / 15 / 30', () {
      expect(ReglageInactivite.parDefaut, 5);
      expect(ReglageInactivite.choix, [0, 1, 5, 15, 30]);
    });

    test('le réglage est PROPRE À CHAQUE UTILISATEUR et survit au redémarrage (coffre)', () async {
      expect(await reglage.lire('u1'), 5);
      await reglage.ecrire('u1', 15);
      await reglage.ecrire('u2', 0);
      // Une autre instance sur le même coffre : le « redémarrage ».
      final apres = ReglageInactivite(coffre: coffre);
      expect(await apres.lire('u1'), 15);
      expect(await apres.lire('u2'), 0);
      expect(await apres.lire('u3'), 5);
    });

    test('une durée hors des choix est refusée ; un coffre illisible rend le défaut', () async {
      expect(() => reglage.ecrire('u1', 7), throwsArgumentError);
      expect(await ReglageInactivite(coffre: const CoffreIllisible()).lire('u1'), 5);
    });
  });

  group('minuteur', () {
    test('verrouille après 5 min sans interaction (pas avant)', () {
      fakeAsync((fa) {
        armer(fa);
        fa.elapse(const Duration(minutes: 4, seconds: 59));
        expect(verrouillages, 0);
        fa.elapse(const Duration(seconds: 1));
        fa.flushMicrotasks();
        expect(verrouillages, 1);
      });
    });

    test('une interaction repousse l\'échéance', () {
      fakeAsync((fa) {
        armer(fa);
        fa.elapse(const Duration(minutes: 4));
        controle.activite();
        fa.elapse(const Duration(minutes: 4));
        fa.flushMicrotasks();
        expect(verrouillages, 0, reason: '4 min après l\'interaction : pas encore');
        fa.elapse(const Duration(minutes: 1));
        fa.flushMicrotasks();
        expect(verrouillages, 1);
      });
    });

    test('« Jamais » ne verrouille jamais', () {
      fakeAsync((fa) {
        reglage.ecrire('u1', 0);
        armer(fa);
        fa.elapse(const Duration(hours: 10));
        fa.flushMicrotasks();
        expect(verrouillages, 0);
      });
    });

    test('la durée choisie est respectée (1 min), et un changement en cours de route s\'applique aussitôt', () {
      fakeAsync((fa) {
        reglage.ecrire('u1', 1);
        armer(fa);
        fa.elapse(const Duration(minutes: 1));
        fa.flushMicrotasks();
        expect(verrouillages, 1);
      });
      fakeAsync((fa) {
        armer(fa, id: 'u2');
        controle.regler(15);
        fa.flushMicrotasks();
        fa.elapse(const Duration(minutes: 14));
        fa.flushMicrotasks();
        expect(verrouillages, 1, reason: 'inchangé : le second contrôle n\'a pas verrouillé à 5 min');
        fa.elapse(const Duration(minutes: 1));
        fa.flushMicrotasks();
        expect(verrouillages, 2);
      });
    });

    test('aucun PIN défini : pas de verrou', () {
      fakeAsync((fa) {
        armer(fa, sansPin: true);
        fa.elapse(const Duration(hours: 1));
        fa.flushMicrotasks();
        expect(verrouillages, 0);
      });
    });

    test('désarmé (écran de verrouillage, de définition, de connexion) : jamais de verrouillage', () {
      fakeAsync((fa) {
        armer(fa);
        fa.elapse(const Duration(minutes: 2));
        controle.desarmer();
        controle.activite();
        fa.elapse(const Duration(hours: 1));
        fa.flushMicrotasks();
        expect(verrouillages, 0);
      });
    });

    test('un seul verrouillage par armement, même si le temps continue', () {
      fakeAsync((fa) {
        armer(fa);
        fa.elapse(const Duration(hours: 1));
        fa.flushMicrotasks();
        expect(verrouillages, 1);
      });
    });

    test('une synchronisation en cours n\'est pas interrompue : le verrou attend sa fin', () {
      fakeAsync((fa) {
        var enCours = true;
        controle.synchroEnCours = () => enCours;
        armer(fa);
        fa.elapse(const Duration(minutes: 20));
        fa.flushMicrotasks();
        expect(verrouillages, 0);
        enCours = false;
        fa.elapse(VerrouInactivite.delaiSynchro);
        fa.flushMicrotasks();
        expect(verrouillages, 1);
      });
    });

    test('formulaire modal ouvert : report de 1 min UNE fois, puis verrou', () {
      fakeAsync((fa) {
        controle.modaleOuverte = () => true;
        armer(fa);
        fa.elapse(const Duration(minutes: 5));
        fa.flushMicrotasks();
        expect(verrouillages, 0, reason: 'premier report');
        fa.elapse(const Duration(seconds: 59));
        fa.flushMicrotasks();
        expect(verrouillages, 0);
        fa.elapse(const Duration(seconds: 1));
        fa.flushMicrotasks();
        expect(verrouillages, 1, reason: 'un seul report, ensuite on verrouille');
      });
    });

    test('une interaction pendant le report rend son report au prochain verrou', () {
      fakeAsync((fa) {
        controle.modaleOuverte = () => true;
        armer(fa);
        fa.elapse(const Duration(minutes: 5));
        controle.activite();
        fa.elapse(const Duration(minutes: 5));
        fa.flushMicrotasks();
        expect(verrouillages, 0, reason: 'nouveau report après la nouvelle inactivité');
        fa.elapse(const Duration(minutes: 1));
        fa.flushMicrotasks();
        expect(verrouillages, 1);
      });
    });

    test('le PIN effacé entre-temps : pas de verrouillage', () {
      fakeAsync((fa) {
        armer(fa);
        verrou.effacer('u1');
        fa.elapse(const Duration(minutes: 10));
        fa.flushMicrotasks();
        expect(verrouillages, 0);
      });
    });
  });

  group('détection globale', () {
    testWidgets('pointeur, défilement et clavier réinitialisent le minuteur', (tester) async {
      await verrou.definir('u1', '1234');
      controle.armer(idUtilisateur: 'u1', verrouiller: () => verrouillages++);
      await tester.pumpWidget(
        MaterialApp(
          home: SurveillanceInactivite(
            controleur: controle,
            child: ListView(children: [for (var i = 0; i < 60; i++) Text('ligne $i')]),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      // Chaque geste, 4 min après le précédent : jamais 5 min d'inactivité consécutive.
      Future<void> apres4min(Future<void> Function() geste) async {
        await tester.pump(const Duration(minutes: 4));
        expect(verrouillages, 0);
        await geste();
      }

      await apres4min(() => tester.tap(find.text('ligne 1')));
      await apres4min(() => tester.drag(find.text('ligne 1'), const Offset(0, -80)));
      await apres4min(() => tester.sendKeyEvent(LogicalKeyboardKey.keyA));
      await apres4min(() async {
        final souris = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await souris.addPointer(location: Offset.zero);
        await souris.moveTo(const Offset(50, 50));
      });
      await apres4min(() async {});
      expect(verrouillages, 0);
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(verrouillages, 1);
    });
  });
}
