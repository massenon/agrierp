import 'dart:io';

import 'package:agrierp/core/config/envoi_email_test.dart';
import 'package:agrierp/core/config/parametres_smtp.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/erreurs/message_erreur.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'coffre_memoire.dart';

/// Ticket CFG-2 (décision client du 19/10/2026, D-CFG-2) — ONGLET « EMAIL (SMTP) » DU POSTE.
///
/// ⚠️⚠️ **LE MOT DE PASSE SMTP VA AU COFFRE DU SYSTÈME, JAMAIS EN BASE DRIFT, JAMAIS SYNCHRONISÉ.** Deux garde-fous :
/// à l'exécution (après enregistrement, AUCUNE table de la base ne contient la valeur) et dans le source (aucune
/// écriture de `app_settings` ne reçoit le mot de passe ; sa clé de coffre ne sert qu'au coffre).
///
/// ⚠️ Champ vide = mot de passe INCHANGÉ ; l'effacer est un geste explicite. L'e-mail de test est réel (paquet
/// `mailer`), l'envoi est injecté ici : aucun réseau.
void main() {
  late AppDatabase db;
  late CoffreMemoire coffre;
  late ParametresSmtp smtp;

  /// Mot de passe témoin : une valeur qu'aucune donnée de la base ne peut porter par hasard.
  const secret = 'Mdp-Smtp-Témoin-7f3a9c';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coffre = CoffreMemoire();
    smtp = ParametresSmtp(database: db, coffre: coffre);
  });

  tearDown(() async => db.close());

  Future<void> enregistrerComplet({String motDePasse = secret}) => smtp.enregistrer(
    hote: 'smtp.ferme.bj',
    port: 465,
    securite: SecuriteSmtp.ssl,
    utilisateur: 'notifications@fermeolouwachegoun.com',
    expediteur: 'ne-pas-repondre@fermeolouwachegoun.com',
    motDePasse: motDePasse,
  );

  /// Toutes les cellules de toutes les tables de la base, en texte.
  Future<List<String>> toutesLesValeurs() async {
    final valeurs = <String>[];
    for (final table in db.allTables) {
      final lignes = await db.customSelect('SELECT * FROM "${table.actualTableName}"').get();
      for (final l in lignes) {
        valeurs.addAll(l.data.values.whereType<Object>().map((v) => '$v'));
      }
    }
    return valeurs;
  }

  group('réglages', () {
    test('sans réglage : port 587, TLS, rien d enregistré', () async {
      final c = await smtp.charger();
      expect([c.hote, c.port, c.securite, c.utilisateur, c.expediteur, c.motDePasseEnregistre], [
        '',
        587,
        SecuriteSmtp.tls,
        '',
        '',
        false,
      ]);
    });

    test('les réglages vont dans app_settings, le mot de passe au coffre', () async {
      await enregistrerComplet();

      final c = await smtp.charger();
      expect([c.hote, c.port, c.securite, c.utilisateur, c.expediteur, c.motDePasseEnregistre], [
        'smtp.ferme.bj',
        465,
        SecuriteSmtp.ssl,
        'notifications@fermeolouwachegoun.com',
        'ne-pas-repondre@fermeolouwachegoun.com',
        true,
      ]);
      expect(coffre.contenu[ParametresSmtp.cleCoffreMotDePasse], secret);
      final cles = (await db.select(db.appSettings).get()).map((l) => l.key).toSet();
      expect(cles, ParametresSmtp.clesReglages.toSet());
    });

    /// ⚠️⚠️ Un enregistrement sans retaper le mot de passe ne doit pas l'effacer.
    test('⚠️⚠️ un champ vide laisse le mot de passe inchangé', () async {
      await enregistrerComplet();
      await smtp.enregistrer(hote: 'smtp2.ferme.bj', port: 2525, securite: SecuriteSmtp.tls);

      expect(coffre.contenu[ParametresSmtp.cleCoffreMotDePasse], secret);
      expect((await smtp.charger()).hote, 'smtp2.ferme.bj');
      expect(await smtp.motDePassePourEnvoi(), secret);
    });

    test('un nouveau mot de passe remplace l ancien ; l effacement est explicite', () async {
      await enregistrerComplet();
      await enregistrerComplet(motDePasse: 'nouveau');
      expect(await smtp.motDePassePourEnvoi(), 'nouveau');

      await smtp.effacerMotDePasse();
      expect(coffre.contenu, isNot(contains(ParametresSmtp.cleCoffreMotDePasse)));
      expect((await smtp.charger()).motDePasseEnregistre, isFalse);
      expect(await smtp.motDePassePourEnvoi(), isNull);
    });

    test('les erreurs de saisie sont celles du web, en français', () {
      expect(ParametresSmtp.erreursDeSaisie(hote: ' ', port: ''), {
        'hote': 'Le champ hôte SMTP est obligatoire.',
        'port': 'Le champ port est obligatoire.',
      });
      expect(ParametresSmtp.erreursDeSaisie(hote: 'h', port: 'abc')['port'], 'Le champ port doit être un nombre entier.');
      expect(ParametresSmtp.erreursDeSaisie(hote: 'h', port: '0')['port'], 'Le champ port doit être au moins égal à 1.');
      expect(ParametresSmtp.erreursDeSaisie(hote: 'h', port: '70000')['port'], 'Le champ port ne doit pas dépasser 65535.');
      expect(
        ParametresSmtp.erreursDeSaisie(hote: 'h', port: '25', expediteur: 'pas-une-adresse')['expediteur'],
        "Le champ adresse d'expédition doit être une adresse e-mail valide.",
      );
      expect(ParametresSmtp.erreursDeSaisie(hote: 'h', port: '25', expediteur: 'a@b.bj'), isEmpty);
    });

    test('une saisie invalide n est pas enregistrée', () async {
      await expectLater(
        smtp.enregistrer(hote: '', port: 25, securite: SecuriteSmtp.tls, motDePasse: secret),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', 'Le champ hôte SMTP est obligatoire.')),
      );
      expect(await db.select(db.appSettings).get(), isEmpty);
      expect(coffre.contenu, isEmpty);
    });

    test('l expéditeur retombe sur l e-mail de contact de la ferme, puis sur l utilisateur', () async {
      await smtp.enregistrer(hote: 'h', port: 25, securite: SecuriteSmtp.tls, utilisateur: 'user@ferme.bj');
      expect((await smtp.charger()).adresseExpedition, 'user@ferme.bj');

      await db
          .into(db.companySettings)
          .insert(CompanySettingsCompanion.insert(id: const Value('unique'), email: const Value('contact@ferme.bj')));
      expect((await smtp.charger()).adresseExpedition, 'contact@ferme.bj');

      await smtp.enregistrer(hote: 'h', port: 25, securite: SecuriteSmtp.tls, expediteur: 'envoi@ferme.bj');
      expect((await smtp.charger()).adresseExpedition, 'envoi@ferme.bj');
    });
  });

  group('⚠️⚠️ garde-fou : le mot de passe n entre dans aucune table Drift', () {
    test('à l exécution : après enregistrement, aucune cellule de la base ne contient la valeur', () async {
      await enregistrerComplet();
      await smtp.charger();

      final valeurs = await toutesLesValeurs();
      expect(valeurs, isNotEmpty, reason: 'les réglages non secrets, eux, sont bien en base');
      expect(valeurs.where((v) => v.contains(secret)), isEmpty);
      expect(valeurs.where((v) => v.contains('Mdp-Smtp')), isEmpty);
      // Et il est bien quelque part : au coffre.
      expect(coffre.contenu.values, contains(secret));
    });

    test('dans le source : aucune écriture de app_settings ne reçoit le mot de passe', () {
      final source = File('lib/core/config/parametres_smtp.dart').readAsStringSync();

      // Les clés de réglage ne nomment pas un secret.
      expect(
        ParametresSmtp.clesReglages.where((c) => RegExp('mot_de_passe|password|secret', caseSensitive: false).hasMatch(c)),
        isEmpty,
      );
      // Une seule construction d'écriture `app_settings` dans ce service : celle de `_ecrireReglage`.
      expect('AppSettingsCompanion'.allMatches(source).length, 1);
      // Aucun appel de `_ecrireReglage` ne porte le mot de passe.
      final appels = RegExp(r'await _ecrireReglage\(([^;]*)\);').allMatches(source).map((m) => m.group(1)!).toList();
      expect(appels, hasLength(ParametresSmtp.clesReglages.length));
      expect(appels.where((a) => RegExp('motDePasse|password', caseSensitive: false).hasMatch(a)), isEmpty);
      // La clé du coffre ne sert qu'au coffre.
      for (final ligne in source.split('\n').where((l) => l.contains('cleCoffreMotDePasse'))) {
        expect(
          ligne.contains('_coffre.') || ligne.trimLeft().startsWith('static const cleCoffreMotDePasse'),
          isTrue,
          reason: ligne.trim(),
        );
      }
    });

    test('dans tout lib/ : seule la configuration SMTP touche la clé du coffre, et aucune écriture de app_settings '
        'ne reçoit un mot de passe', () {
      final fautifs = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
        final source = f.readAsStringSync();
        final chemin = f.path.replaceAll(r'\', '/');
        if (source.contains('cleCoffreMotDePasse') && !chemin.endsWith('core/config/parametres_smtp.dart')) {
          fautifs.add('$chemin : clé du coffre SMTP');
        }
        for (final m in RegExp(r'AppSettingsCompanion(?:\.insert)?\(([^;]*?)\)', dotAll: true).allMatches(source)) {
          if (RegExp('motDePasse|password|smtpPassword', caseSensitive: false).hasMatch(m.group(1)!)) {
            fautifs.add('$chemin : ${m.group(0)}');
          }
        }
      }
      expect(fautifs, isEmpty);
    });

    test('le schéma local n a aucune colonne SMTP', () {
      for (final table in db.allTables) {
        for (final colonne in table.$columns) {
          expect(colonne.name.toLowerCase(), isNot(contains('smtp')), reason: '${table.actualTableName}.${colonne.name}');
        }
      }
    });
  });

  group('e-mail de test', () {
    late List<(Message, SmtpServer)> envoyes;
    late bool enLigne;
    late Object? echec;
    late EnvoiEmailTest envoi;

    setUp(() {
      envoyes = [];
      enLigne = true;
      echec = null;
      envoi = EnvoiEmailTest(
        parametres: smtp,
        envoyeur: (message, serveur) async {
          if (echec != null) throw echec!;
          envoyes.add((message, serveur));
        },
        enLigne: () async => enLigne,
      );
    });

    test('part réellement avec la configuration enregistrée et le mot de passe du coffre', () async {
      await enregistrerComplet();

      expect(await envoi.envoyer('dg@fermeolouwachegoun.com'), 'E-mail de test envoyé à dg@fermeolouwachegoun.com.');

      expect(envoyes, hasLength(1));
      final (message, serveur) = envoyes.single;
      expect([serveur.host, serveur.port, serveur.ssl, serveur.allowInsecure, serveur.username, serveur.password], [
        'smtp.ferme.bj',
        465,
        true,
        false,
        'notifications@fermeolouwachegoun.com',
        secret,
      ]);
      expect((message.from as Address).mailAddress, 'ne-pas-repondre@fermeolouwachegoun.com');
      expect(message.recipients, ['dg@fermeolouwachegoun.com']);
      expect(message.subject, EnvoiEmailTest.sujet);
    });

    test('la sécurité choisie règle la connexion : TLS exige STARTTLS, Aucune l autorise en clair', () {
      const base = ConfigurationSmtp(hote: 'h');
      final tls = EnvoiEmailTest.serveurPour(base, null);
      expect([tls.ssl, tls.allowInsecure, tls.username, tls.password], [false, false, null, null]);
      final aucune = EnvoiEmailTest.serveurPour(
        const ConfigurationSmtp(hote: 'h', securite: SecuriteSmtp.aucune),
        null,
      );
      expect([aucune.ssl, aucune.allowInsecure], [false, true]);
    });

    test('sans hôte enregistré, le test est refusé avec le message du web', () async {
      await expectLater(
        envoi.envoyer('dg@fermeolouwachegoun.com'),
        throwsA(
          isA<EchecEnvoiEmail>().having(
            (e) => e.message,
            'message',
            "Enregistrez d'abord l'hôte SMTP avant d'envoyer un e-mail de test.",
          ),
        ),
      );
      expect(envoyes, isEmpty);
    });

    test('⚠️ hors ligne, le poste le dit au lieu d attendre', () async {
      await enregistrerComplet();
      enLigne = false;

      await expectLater(
        envoi.envoyer('dg@fermeolouwachegoun.com'),
        throwsA(isA<EchecEnvoiEmail>().having((e) => e.message, 'message', contains('Poste hors ligne'))),
      );
      expect(envoyes, isEmpty);
    });

    test('un destinataire invalide est refusé avant tout envoi', () async {
      await enregistrerComplet();
      await expectLater(envoi.envoyer('pas-une-adresse'), throwsA(isA<EchecEnvoiEmail>()));
      expect(envoyes, isEmpty);
    });

    test('⚠️ chaque échec se dit en français, jamais l exception brute ni le mot de passe', () async {
      await enregistrerComplet();
      final cas = <Object, String>{
        SmtpClientAuthenticationException('Incorrect username or password ($secret)'):
            'identifiant ou mot de passe refusé par le serveur SMTP',
        const SocketException('Connection refused'):
            "serveur SMTP injoignable : vérifiez l'hôte, le port et la connexion du poste",
        SmtpUnsecureException('Server does not support STARTTLS'):
            "le serveur n'accepte pas de connexion chiffrée",
        Exception('boom'): messageGenerique,
      };
      for (final MapEntry(key: erreur, value: attendu) in cas.entries) {
        echec = erreur;
        try {
          await envoi.envoyer('dg@fermeolouwachegoun.com');
          fail('un échec était attendu');
        } on EchecEnvoiEmail catch (e) {
          expect(e.message, startsWith("Échec de l'envoi — vérifiez la configuration SMTP ("));
          expect(e.message, contains(attendu));
          expect(e.message, isNot(contains(secret)));
          expect(e.message, isNot(contains('Exception')));
        }
      }
    });
  });

  group('onglet « Email (SMTP) » du hub', () {
    late List<(Message, SmtpServer)> envoyes;
    late bool enLigne;

    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      envoyes = [];
      enLigne = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ParametresGenerauxScreen(
            depot: ParametresGenerauxRepository(database: db),
            smtp: smtp,
            envoiEmail: EnvoiEmailTest(
              parametres: smtp,
              envoyeur: (m, s) async => envoyes.add((m, s)),
              enLigne: () async => enLigne,
            ),
            ongletInitial: ParametresGenerauxScreen.ongletEmailSmtp,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> nettoyer(WidgetTester tester) async {
      ToastAgri.toutRetirer();
      await tester.pumpWidget(const SizedBox());
    }

    String champ(WidgetTester tester, String cle) =>
        tester.widget<TextField>(find.byKey(Key(cle))).controller!.text;

    testWidgets('⚠️⚠️ le mot de passe enregistré n est jamais réaffiché', (tester) async {
      await enregistrerComplet();
      await afficher(tester);

      expect(champ(tester, 'smtp-hote'), 'smtp.ferme.bj');
      expect(champ(tester, 'smtp-port'), '465');
      expect(champ(tester, 'smtp-mot-de-passe'), isEmpty);
      expect(tester.widget<TextField>(find.byKey(const Key('smtp-mot-de-passe'))).obscureText, isTrue);
      expect(find.text('Mot de passe enregistré'), findsOneWidget);
      expect(find.textContaining(secret), findsNothing);
      await nettoyer(tester);
    });

    testWidgets('⚠️⚠️ enregistrer sans retaper le mot de passe le conserve', (tester) async {
      await enregistrerComplet();
      await afficher(tester);

      await tester.enterText(find.byKey(const Key('smtp-port')), '587');
      await tester.tap(find.byKey(const Key('smtp-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.text('Configuration SMTP enregistrée avec succès.'), findsOneWidget);
      expect((await smtp.charger()).port, 587);
      expect(coffre.contenu[ParametresSmtp.cleCoffreMotDePasse], secret);
      await nettoyer(tester);
    });

    testWidgets('une saisie neuve : réglages en base, mot de passe au coffre, champ vidé', (tester) async {
      await afficher(tester);
      expect(find.text('Aucun mot de passe enregistré'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('smtp-hote')), 'smtp.gmail.com');
      await tester.enterText(find.byKey(const Key('smtp-utilisateur')), 'ferme@gmail.com');
      await tester.enterText(find.byKey(const Key('smtp-mot-de-passe')), secret);
      await tester.tap(find.byKey(const Key('smtp-enregistrer')));
      await tester.pumpAndSettle();

      expect(coffre.contenu[ParametresSmtp.cleCoffreMotDePasse], secret);
      expect(champ(tester, 'smtp-mot-de-passe'), isEmpty);
      expect(find.text('Mot de passe enregistré'), findsOneWidget);
      expect((await toutesLesValeurs()).where((v) => v.contains(secret)), isEmpty);
      await nettoyer(tester);
    });

    testWidgets('les erreurs de saisie s affichent sous le champ, rien n est enregistré', (tester) async {
      await afficher(tester);
      await tester.enterText(find.byKey(const Key('smtp-port')), '0');
      await tester.tap(find.byKey(const Key('smtp-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.text('Le champ hôte SMTP est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ port doit être au moins égal à 1.'), findsOneWidget);
      expect(await db.select(db.appSettings).get(), isEmpty);
      await nettoyer(tester);
    });

    testWidgets('« Effacer le mot de passe » demande confirmation puis efface', (tester) async {
      await enregistrerComplet();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('smtp-effacer-mot-de-passe')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(coffre.contenu[ParametresSmtp.cleCoffreMotDePasse], secret);

      await tester.tap(find.byKey(const Key('smtp-effacer-mot-de-passe')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('smtp-effacer-confirmer')));
      await tester.pumpAndSettle();

      expect(coffre.contenu, isNot(contains(ParametresSmtp.cleCoffreMotDePasse)));
      expect(find.text('Mot de passe SMTP effacé.'), findsOneWidget);
      expect(find.text('Aucun mot de passe enregistré'), findsOneWidget);
      expect(find.byKey(const Key('smtp-effacer-mot-de-passe')), findsNothing);
      await nettoyer(tester);
    });

    testWidgets('« Envoyer un e-mail de test » envoie et le dit ; hors ligne, le dit aussi', (tester) async {
      await enregistrerComplet();
      await afficher(tester);
      // Destinataire proposé : l'expéditeur réel, comme au web.
      expect(champ(tester, 'smtp-destinataire'), 'ne-pas-repondre@fermeolouwachegoun.com');

      await tester.enterText(find.byKey(const Key('smtp-destinataire')), 'dg@fermeolouwachegoun.com');
      await tester.tap(find.byKey(const Key('smtp-envoyer-test')));
      await tester.pumpAndSettle();
      expect(find.text('E-mail de test envoyé à dg@fermeolouwachegoun.com.'), findsOneWidget);
      expect(envoyes, hasLength(1));

      ToastAgri.toutRetirer();
      enLigne = false;
      await tester.tap(find.byKey(const Key('smtp-envoyer-test')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('toast-erreur')), findsOneWidget);
      expect(find.textContaining('Poste hors ligne'), findsOneWidget);
      expect(envoyes, hasLength(1));
      await nettoyer(tester);
    });
  });
}
