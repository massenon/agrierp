import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrierp/core/erreurs/message_erreur.dart';
import 'package:agrierp/core/localisation/localisation_poste.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/theme/agri_theme.dart';

import 'fidelite_libelles_test.dart' show chainesDe;

/// Ticket U5 (décision D-U5 du 19/10/2026) — LE POSTE EST EN FRANÇAIS, Y
/// COMPRIS SES COMPOSANTS FLUTTER ET SES MESSAGES D'ÉCHEC.
///
/// Sans délégués de localisation, le sélecteur de date affichait « Select
/// date », « Cancel » et des mois anglais ; trois écrans de synchronisation et
/// deux exports affichaient l'exception brute (« DioException [connection
/// error] … », « FileSystemException: Cannot open file … »).
void main() {
  group('MaterialApp en français', () {
    test('le MaterialApp du poste branche la localisation française', () {
      final source = File('lib/main.dart').readAsStringSync();

      expect(source, contains('locale: LocalisationPoste.locale'));
      expect(source, contains('supportedLocales: LocalisationPoste.locales'));
      expect(
        source,
        contains('localizationsDelegates: LocalisationPoste.delegues'),
      );
      expect(source, contains("initializeDateFormatting('fr_FR')"));
      expect(LocalisationPoste.locale, const Locale('fr'));
      expect(LocalisationPoste.locales, [const Locale('fr')]);

      // Deux MaterialApp dans lib/, pas un de plus : celui du poste et celui de l'écran « AgriERP ne peut pas démarrer »
      // (montré AVANT que l'application existe). Un autre échapperait à la localisation ; et le second doit porter
      // EXACTEMENT la même localisation que le premier.
      final applications = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('MaterialApp('))
          .map((f) => f.path.replaceAll(r'\', '/'))
          .toList()
        ..sort();
      expect(applications, ['lib/core/demarrage/demarrage_poste.dart', 'lib/main.dart']);
      final demarrage = File('lib/core/demarrage/demarrage_poste.dart').readAsStringSync();
      expect(demarrage, contains('locale: LocalisationPoste.locale'));
      expect(demarrage, contains('supportedLocales: LocalisationPoste.locales'));
      expect(demarrage, contains('localizationsDelegates: LocalisationPoste.delegues'));
    });

    testWidgets(
      'le sélecteur de date affiche des mois et des boutons français',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AgriTheme.light,
            locale: LocalisationPoste.locale,
            supportedLocales: LocalisationPoste.locales,
            localizationsDelegates: LocalisationPoste.delegues,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('ouvrir-calendrier'),
                  onPressed: () => showDatePicker(
                    context: context,
                    initialDate: DateTime(2026, 10, 19),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  ),
                  child: const Text('Choisir'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('ouvrir-calendrier')));
        await tester.pumpAndSettle();

        final contexte = tester.element(find.byType(DatePickerDialog));
        final traductions = MaterialLocalizations.of(contexte);
        expect(traductions.cancelButtonLabel, 'Annuler');
        expect(traductions.formatMonthYear(DateTime(2026, 10)), 'octobre 2026');

        expect(find.text('octobre 2026'), findsOneWidget);
        expect(find.text('Annuler'), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
        expect(find.text('Select date'), findsNothing);
        expect(find.textContaining('October'), findsNothing);

        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
      },
    );
  });

  group('messages d\'échec en français', () {
    DioException dio(DioExceptionType type, {int? statut, Object? corps}) =>
        DioException(
          requestOptions: RequestOptions(path: '/api/sync/pull'),
          type: type,
          response: statut == null
              ? null
              : Response(
                  requestOptions: RequestOptions(path: '/api/sync/pull'),
                  statusCode: statut,
                  data: corps,
                ),
        );

    test('une erreur réseau est nommée, jamais « DioException [...] »', () {
      expect(
        messageErreur(dio(DioExceptionType.connectionError)),
        startsWith('Serveur injoignable'),
      );
      expect(
        messageErreur(dio(DioExceptionType.receiveTimeout)),
        startsWith('Le serveur ne répond pas'),
      );
      expect(
        messageErreur(dio(DioExceptionType.badResponse, statut: 401)),
        startsWith('Session expirée'),
      );
      expect(
        messageErreur(
          dio(
            DioExceptionType.badResponse,
            statut: 500,
            corps: {'message': 'Server Error'},
          ),
        ),
        startsWith('Le serveur a rencontré une erreur'),
      );
      // Le motif français du serveur (lang/fr, ticket U5) est repris mot pour mot.
      expect(
        messageErreur(
          dio(
            DioExceptionType.badResponse,
            statut: 422,
            corps: {'message': 'Le champ nom du poste est obligatoire.'},
          ),
        ),
        'Le champ nom du poste est obligatoire.',
      );
      expect(
        messageErreur(dio(DioExceptionType.unknown)),
        isNot(contains('DioException')),
      );
    });

    test(
      'le motif français d\'une erreur du poste est gardé, le détail anglais remplacé',
      () {
        // Absorbeur strict du moteur de synchronisation : déjà une phrase française.
        expect(
          messageErreur(
            const FormatException('Fiche F1 refusée : « ne » absent.'),
          ),
          'Fiche F1 refusée : « ne » absent.',
        );
        expect(
          messageErreur(
            const EchecSynchronisation('Session expirée : reconnectez-vous.'),
          ),
          'Session expirée : reconnectez-vous.',
        );
        // Message technique de Dart : remplacé.
        expect(
          messageErreur(const FormatException('Unexpected character')),
          messageGenerique,
        );
        expect(
          messageErreur(StateError('Bad state: No element')),
          messageGenerique,
        );
        expect(
          estPhraseFrancaise('Le champ nom du poste est obligatoire.'),
          isTrue,
        );
        expect(
          estPhraseFrancaise('The route api/x could not be found.'),
          isFalse,
        );
        expect(estPhraseFrancaise('Server Error'), isFalse);
        expect(messageErreur(Exception('boom')), messageGenerique);
      },
    );

    test('un fichier impossible à écrire est dit en français', () {
      final message = messageEcritureFichier(
        const FileSystemException(
          'Cannot open file',
          r'C:\Exports\attestation.pdf',
        ),
      );
      expect(
        message,
        startsWith(
          "Impossible d'écrire le fichier « C:\\Exports\\attestation.pdf »",
        ),
      );
      expect(message, isNot(contains('Cannot open')));
      expect(
        messageErreur(const FileSystemException('Access is denied')),
        startsWith("Impossible d'écrire le fichier"),
      );
    });
  });

  /// Garde-fou : aucun message d'erreur ANGLAIS dans les littéraux de chaîne de
  /// `lib/`, et aucune exception affichée brute (`'… $e'`). Les commentaires
  /// sont ignorés (`chainesDe`) ; seuls les littéraux qui contiennent une espace
  /// sont lus — une clé technique (« login.failed ») n'en contient jamais.
  test('aucun message d\'erreur anglais dans les chaînes de lib/', () {
    final anglais = RegExp(
      r'\b(Error|Failed|failed to|Unknown error|Invalid|invalid|Something went wrong|Please|please|'
      r'Try again|try again|Cannot|cannot|Unable to|unable to|not found|Not found|Warning|Exception:|'
      r'Loading|Retry|Success|Successfully|is required|must be|Are you sure)\b',
    );
    final exceptionBrute = RegExp(
      r'\$(e|err|erreur|error|exception)\b|\$\{(e|err|erreur|error)(\.toString\(\))?\}',
    );

    final fautes = <String>[];
    for (final fichier in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      final chemin = fichier.path.replaceAll(r'\', '/');
      if (!chemin.endsWith('.dart') || chemin.endsWith('.g.dart')) continue;
      for (final litteral in chainesDe(
        fichier.readAsStringSync(),
      ).split('\n')) {
        if (!litteral.contains(' ')) continue;
        // Ligne de JOURNAL (debugPrint) : le détail technique y est voulu, il
        // n'est jamais affiché.
        if (litteral.contains('détail technique')) continue;
        if (anglais.hasMatch(litteral) || exceptionBrute.hasMatch(litteral)) {
          fautes.add('$chemin : « $litteral »');
        }
      }
    }

    expect(fautes, isEmpty, reason: fautes.join('\n'));
  });
}
