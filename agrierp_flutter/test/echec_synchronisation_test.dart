import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket S3 — les refus du serveur sont nommés, jamais affichés comme une erreur technique brute.
void main() {
  test(
    'une session expirée (401) demande de se reconnecter et rassure sur les saisies',
    () {
      final motif = EchecSynchronisation.motifHttp(401, null)!;
      expect(motif, contains('Session expirée'));
      expect(motif, contains('conservées'));
    },
  );

  test('un compte désactivé (403) reprend le message du serveur', () {
    expect(
      EchecSynchronisation.motifHttp(403, {
        'message': "Compte désactivé : contactez l'administrateur de la ferme.",
      }),
      "Compte désactivé : contactez l'administrateur de la ferme.",
    );
    expect(EchecSynchronisation.motifHttp(403, null), contains('Accès refusé'));
  });

  test('le débit dépassé (429) invite à patienter', () {
    expect(
      EchecSynchronisation.motifHttp(429, null),
      contains('réessayez dans une minute'),
    );
  });

  test('les autres erreurs ne sont pas réinterprétées', () {
    expect(EchecSynchronisation.motifHttp(500, null), isNull);
    expect(EchecSynchronisation.motifHttp(null, null), isNull);
  });

  test("le message s'affiche tel quel", () {
    expect('${const EchecSynchronisation('Motif')}', 'Motif');
  });
}
