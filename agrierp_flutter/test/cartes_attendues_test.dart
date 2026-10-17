import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';
import 'structure_maquette.g.dart';

/// Ticket F0.54 — LES ÉCARTS ASSUMÉS SUR LE NOMBRE DE CARTES.
///
/// ⚠️⚠️ **UN ÉCART DÉCLARÉ EST UNE DETTE : IL DOIT SE PÉRIMER BRUYAMMENT.**
/// C'est la leçon du ticket F0.53, où quinze décisions expliquées en
/// commentaire avaient l'air consignées sans l'être, et où une exemption posée
/// trop largement a retiré dix-sept contrôles réels en silence.
void main() {
  test('⚠️ un écart déclaré désigne une page réellement relevée', () {
    final inconnues = ecartsAssumes.keys
        .where((page) => !cartesMaquette.containsKey(page))
        .toList();

    expect(
      inconnues,
      isEmpty,
      reason:
          'Ces pages ne figurent pas dans le relevé de la maquette : leur '
          'écart ne se rapporte à rien.',
    );
  });

  /// ⚠️⚠️ **UN ÉCART QUI RÉPÈTE LE RELEVÉ EST UNE EXEMPTION MORTE.** Il ne
  /// change rien au contrôle, mais il le rendrait muet le jour où la maquette
  /// change — l'écran garderait l'ancien nombre, et l'entrée l'y autoriserait
  /// sans que personne ne l'ait décidé.
  test('⚠️⚠️ un écart déclaré diffère réellement de la maquette', () {
    final morts = ecartsAssumes.entries
        .where((e) => e.value.$1 == cartesMaquette[e.key])
        .map((e) => e.key)
        .toList();

    expect(
      morts,
      isEmpty,
      reason:
          "Ces écarts valent le relevé de la maquette : ils ne décrivent plus "
          "rien et doivent être retirés.",
    );
  });

  /// ⚠️ Un écart sans raison écrite est un écart qu'on ne pourra ni défendre
  /// ni contester six mois plus tard.
  test('⚠️ tout écart porte une raison', () {
    for (final entree in ecartsAssumes.entries) {
      expect(
        entree.value.$2.trim().length,
        greaterThan(40),
        reason: entree.key,
      );
    }
  });

  test('sans écart déclaré, le relevé de la maquette fait foi', () {
    expect(
      cartesAttendues('gestion-stocks.html'),
      cartesMaquette['gestion-stocks.html'],
    );
    expect(cartesAttendues('facturation.html'), 4);
    expect(cartesMaquette['facturation.html'], 3);
  });

  /// ⚠️⚠️ **LES MÊMES GARDES SUR LES MANQUES.** Une dette ouverte qui ne
  /// correspond plus à rien est pire qu'une dette oubliée : elle laisse croire
  /// que le manque est connu et suivi.
  group('manques à traiter', () {
    test('⚠️ un manque déclaré désigne une page réellement relevée', () {
      expect(
        ecartsATraiter.keys.where((p) => !cartesMaquette.containsKey(p)),
        isEmpty,
      );
    });

    test('⚠️⚠️ un manque déclaré diffère réellement de la maquette', () {
      expect(
        ecartsATraiter.entries
            .where((e) => e.value.$1 == cartesMaquette[e.key])
            .map((e) => e.key),
        isEmpty,
        reason:
            "Ces manques valent le relevé : l'écran est conforme et l'entrée "
            'doit être retirée.',
      );
    });

    /// ⚠️ Une page ne peut pas être à la fois un écart ASSUMÉ et un manque À
    /// TRAITER : ce serait dire qu'on a décidé de ne pas faire ce qu'on
    /// s'apprête à faire.
    test('⚠️ aucune page n est à la fois assumée et à traiter', () {
      expect(ecartsAssumes.keys.where(ecartsATraiter.containsKey), isEmpty);
    });

    test('⚠️ tout manque porte une raison', () {
      for (final entree in ecartsATraiter.entries) {
        expect(
          entree.value.$2.trim().length,
          greaterThan(40),
          reason: entree.key,
        );
      }
    });
  });

  group('écarts par panneau', () {
    test('⚠️ un écart de panneau désigne un panneau réellement relevé', () {
      final inconnus = <String>[];

      for (final cle in ecartsPanneaux.keys) {
        final morceaux = cle.split('#');
        final panneaux = cartesParPanneau[morceaux.first];
        if (panneaux == null || !panneaux.containsKey(morceaux.last)) {
          inconnus.add(cle);
        }
      }

      expect(inconnus, isEmpty);
    });

    test('⚠️⚠️ un écart de panneau diffère réellement du relevé', () {
      final morts = ecartsPanneaux.entries
          .where((e) {
            final morceaux = e.key.split('#');
            return cartesParPanneau[morceaux.first]?[morceaux.last] ==
                e.value.$1;
          })
          .map((e) => e.key);

      expect(morts, isEmpty);
    });

    test('⚠️ tout écart de panneau porte une raison', () {
      for (final entree in ecartsPanneaux.entries) {
        expect(
          entree.value.$2.trim().length,
          greaterThan(40),
          reason: entree.key,
        );
      }
    });
  });
}
