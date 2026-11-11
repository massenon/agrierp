import 'package:agrierp/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket B3 — historique des tentatives de synchronisation.
///
/// Vérifie :
///   - `enregistrerHistorique` crée une ligne lisible par `dernierHistorique`.
///   - Une tentative hors ligne est correctement distinguée d'une tentative aboutie.
///   - Une tentative avec refus est lisible.
///   - Le plafond de 30 lignes est respecté : la 31e supprime la plus ancienne.
///   - `dernierHistorique` retourne par ordre décroissant (la plus récente d'abord).
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('une tentative aboutie est enregistrée et lue', () async {
    await db.enregistrerHistorique(tire: 12, accepte: 3, rejete: 0, horsLigne: false);
    final lignes = await db.dernierHistorique();

    expect(lignes, hasLength(1));
    final h = lignes.first;
    expect(h.tire, 12);
    expect(h.accepte, 3);
    expect(h.rejete, 0);
    expect(h.horsLigne, isFalse);
  });

  test('une tentative hors ligne est enregistrée et distinguée', () async {
    await db.enregistrerHistorique(tire: 0, accepte: 0, rejete: 0, horsLigne: true);
    final lignes = await db.dernierHistorique();

    expect(lignes, hasLength(1));
    expect(lignes.first.horsLigne, isTrue);
    expect(lignes.first.tire, 0);
  });

  test('une tentative avec refus est enregistrée', () async {
    await db.enregistrerHistorique(tire: 5, accepte: 2, rejete: 1, horsLigne: false);
    final lignes = await db.dernierHistorique();

    expect(lignes.first.rejete, 1);
  });

  test('les tentatives sont retournées par ordre décroissant (la plus récente en tête)', () async {
    await db.enregistrerHistorique(tire: 1, accepte: 0, rejete: 0, horsLigne: false);
    await db.enregistrerHistorique(tire: 2, accepte: 0, rejete: 0, horsLigne: false);
    await db.enregistrerHistorique(tire: 3, accepte: 0, rejete: 0, horsLigne: false);
    final lignes = await db.dernierHistorique();

    expect(lignes.map((l) => l.tire).toList(), [3, 2, 1]);
  });

  test('le plafond de 30 lignes est respecté : la plus ancienne est supprimée', () async {
    for (var i = 1; i <= 31; i++) {
      await db.enregistrerHistorique(tire: i, accepte: 0, rejete: 0, horsLigne: false);
    }
    final toutes = await db.dernierHistorique(limite: 100);

    expect(toutes, hasLength(30));
    // La plus récente a tire = 31, la plus ancienne conservée a tire = 2 (la 1 a été supprimée).
    expect(toutes.first.tire, 31);
    expect(toutes.last.tire, 2);
  });

  test('dernierHistorique(limite: 5) retourne au plus 5 lignes', () async {
    for (var i = 0; i < 10; i++) {
      await db.enregistrerHistorique(tire: i, accepte: 0, rejete: 0, horsLigne: false);
    }
    final lignes = await db.dernierHistorique(limite: 5);
    expect(lignes, hasLength(5));
  });
}
