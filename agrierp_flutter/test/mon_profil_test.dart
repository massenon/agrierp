import 'package:agrierp/core/audit/libelles_audit.dart';
import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/profil/mon_profil_repository.dart';
import 'package:agrierp/features/profil/mon_profil_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.57 — MON PROFIL (`mon-profil.html`).
///
/// ⚠️⚠️ **« MIS À JOUR » NE S'AFFICHE QUE SI LE SERVEUR L'A CONFIRMÉ.** Le
/// prototype simule un succès sans rien envoyer ; le poste, lui, appelle
/// `POST /api/auth/password` et montre l'échec, avec sa cause, quand il a lieu.
void main() {
  late AppDatabase db;
  late MonProfilRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  const session = SessionUtilisateur(
    id: '00000000-0000-0000-0000-00000000aaaa',
    nom: 'Manager Olouwachegoun',
    identifiant: 'admin',
    email: 'dg@fermeolouwachegoun.com',
    role: 'admin',
    roleLibelle: 'Administrateur Principal',
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = MonProfilRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> utilisateur({bool actif = true, String? nom}) => db
      .into(db.utilisateurs)
      .insert(
        UtilisateursCompanion.insert(
          id: session.id,
          name: nom ?? session.nom,
          isActive: Value(actif),
        ),
      );

  Future<void> trace(
    String cle,
    String action,
    DateTime quand, {
    String? qui,
    String? module,
    String? ip,
  }) => db
      .into(db.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          id: uuid(cle),
          userName: Value(qui ?? session.nom),
          action: action,
          module: Value(module),
          ipAddress: Value(ip),
          // Ticket U12b — [quand] est l'heure du BÉNIN de l'action ; `created_at` est l'INSTANT qui y correspond.
          createdAt: Value(HeureBenin.versInstant(quand)),
        ),
      );

  Future<void> afficher(
    WidgetTester tester, {
    SessionUtilisateur? ouverte = session,
    Size taille = const Size(1600, 2000),
    Future<void> Function({
      required String ancien,
      required String nouveau,
      required String confirmation,
    })?
    changer,
  }) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MonProfilScreen(depot: depot, session: ouverte, changer: changer),
      ),
    );
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  group('identité', () {
    testWidgets('la carte dit qui est connecté', (tester) async {
      await utilisateur();
      await afficher(tester);

      expect(texte(tester, 'profil-nom'), 'Manager Olouwachegoun');
      expect(texte(tester, 'profil-email'), 'dg@fermeolouwachegoun.com');
      expect(texte(tester, 'profil-initiales'), 'MO');
      expect(find.text('Administrateur Principal'), findsOneWidget);
      expect(texte(tester, 'profil-statut'), 'Actif');
    });

    testWidgets('un compte désactivé se lit « Inactif »', (tester) async {
      await utilisateur(actif: false);
      await afficher(tester);

      expect(texte(tester, 'profil-statut'), 'Inactif');
    });

    testWidgets('⚠️ sans fiche tirée, le statut est « — », pas « Actif »', (
      tester,
    ) async {
      await afficher(tester);

      expect(texte(tester, 'profil-statut'), '—');
    });

    testWidgets('sans libellé de rôle, aucun badge n\'est inventé', (
      tester,
    ) async {
      await afficher(
        tester,
        ouverte: const SessionUtilisateur(
          id: '',
          nom: 'Sans Rôle',
          identifiant: 'sr',
          email: 'sr@ferme.bj',
          role: '',
          roleLibelle: '',
        ),
      );

      expect(find.byKey(const Key('profil-role')), findsNothing);
    });

    testWidgets('⚠️ sans session, tout se lit « — » et rien ne plante', (
      tester,
    ) async {
      await afficher(tester, ouverte: null);

      expect(texte(tester, 'profil-nom'), '—');
      expect(texte(tester, 'profil-email'), '—');
      expect(texte(tester, 'profil-initiales'), '?');
      expect(texte(tester, 'profil-derniere-connexion'), '—');
      expect(texte(tester, 'profil-ip'), '—');
    });

    test('initiales : deux mots au plus, majuscules, « ? » si vide', () {
      expect(MonProfilRepository.initialesDe('Manager Olouwachegoun'), 'MO');
      expect(MonProfilRepository.initialesDe('  éric  gbaguidi  tossou'), 'ÉG');
      expect(MonProfilRepository.initialesDe('admin'), 'A');
      expect(MonProfilRepository.initialesDe('   '), '?');
    });
  });

  group('métadonnées de session', () {
    testWidgets('la dernière connexion est la plus récente des deux sortes', (
      tester,
    ) async {
      await utilisateur();
      await trace('a', 'login', DateTime(2026, 7, 26, 8), ip: '10.0.0.1');
      await trace(
        'b',
        'api.login',
        DateTime(2026, 7, 28, 6, 14),
        ip: '192.168.1.42',
      );
      await trace('c', 'sale.created', DateTime(2026, 7, 28, 7));
      await afficher(tester);

      expect(texte(tester, 'profil-derniere-connexion'), '28/07/2026 06:14');
      expect(texte(tester, 'profil-ip'), '192.168.1.42');
    });

    testWidgets('⚠️ aucune connexion tirée : « — », jamais une date du jour', (
      tester,
    ) async {
      await utilisateur();
      await trace('a', 'sale.created', DateTime(2026, 7, 28, 7));
      await afficher(tester);

      expect(texte(tester, 'profil-derniere-connexion'), '—');
      expect(texte(tester, 'profil-ip'), '—');
    });
  });

  group('journal d\'audit', () {
    testWidgets('⚠️ ne montre QUE les actions de l\'utilisateur, dix au plus, '
        'la plus récente d\'abord', (tester) async {
      await utilisateur();
      // Douze actions de l'utilisateur, une par jour du 1er au 12 juillet…
      for (var j = 1; j <= 12; j++) {
        await trace(
          'u${j.toString().padLeft(2, 'a')}',
          'sale.created',
          DateTime(2026, 7, j, 9),
          module: 'ventes',
        );
      }
      // … et une action plus récente encore, d'une AUTRE personne.
      await trace(
        'autre',
        'sale.created',
        DateTime(2026, 7, 20, 9),
        qui: 'Quelqu\'un d\'autre',
      );
      await afficher(tester);

      final lignes = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('ligne-journal-'),
      );
      expect(lignes, findsNWidgets(10));

      // Recalcul indépendant : jours 12 → 3, soit la première ligne du 12.
      expect(
        find.descendant(
          of: find.byKey(const Key('ligne-journal-0')),
          matching: find.text('12/07/2026 09:00'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ligne-journal-9')),
          matching: find.text('03/07/2026 09:00'),
        ),
        findsOneWidget,
      );
      expect(find.text('20/07/2026 09:00'), findsNothing);
    });

    testWidgets('les clés techniques sont traduites, une clé inconnue reste '
        'brute', (tester) async {
      await utilisateur();
      await trace(
        'a',
        'login',
        DateTime(2026, 7, 28, 6, 14),
        module: 'auth',
        ip: '192.168.1.42',
      );
      await trace('b', 'cle.future.inconnue', DateTime(2026, 7, 27, 6));
      await afficher(tester);

      expect(find.text('Connexion réussie'), findsOneWidget);
      expect(find.text('Authentification'), findsOneWidget);
      expect(find.text('cle.future.inconnue'), findsOneWidget);
      // Une ligne sans module ni IP : des tirets, pas des cases vides.
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('sans action, le journal le dit et annonce sa portée', (
      tester,
    ) async {
      await afficher(tester);

      expect(find.byKey(const Key('journal-vide')), findsOneWidget);
      expect(
        texte(tester, 'journal-portee'),
        contains('200 dernières actions'),
      );
    });

    testWidgets('les quatre colonnes de la maquette, dans son ordre', (
      tester,
    ) async {
      await afficher(tester);

      final entetes = ['DATE / HEURE', 'ACTION', 'MODULE', 'IP'];
      final x = [for (final e in entetes) tester.getTopLeft(find.text(e)).dx];
      expect(x, orderedEquals([...x]..sort()));
    });
  });

  group('changement de mot de passe', () {
    /// Ce que le faux serveur a reçu, dans l'ordre des appels.
    final envois = <List<String>>[];

    setUp(envois.clear);

    Future<void> accepte({
      required String ancien,
      required String nouveau,
      required String confirmation,
    }) async => envois.add([ancien, nouveau, confirmation]);

    Future<void> refuse({
      required String ancien,
      required String nouveau,
      required String confirmation,
    }) async => throw const EchecChangementMotDePasse(
      'Changement impossible.',
      champs: {
        'ancien':
            "L'ancien mot de passe ne correspond pas à votre mot de passe "
            'actuel.',
      },
    );

    Future<void> horsLigne({
      required String ancien,
      required String nouveau,
      required String confirmation,
    }) async => throw const EchecChangementMotDePasse(
      'Serveur injoignable. Ce changement nécessite le réseau : '
      'réessayez une fois connecté.',
    );

    Future<void> saisir(
      WidgetTester tester, {
      String ancien = '',
      String nouveau = '',
      String confirmation = '',
    }) async {
      await tester.enterText(find.byKey(const Key('mdp-ancien')), ancien);
      await tester.enterText(find.byKey(const Key('mdp-nouveau')), nouveau);
      await tester.enterText(
        find.byKey(const Key('mdp-confirmation')),
        confirmation,
      );
      await tester.ensureVisible(find.byKey(const Key('mdp-envoyer')));
      await tester.tap(find.byKey(const Key('mdp-envoyer')));
      await tester.pumpAndSettle();
    }

    String contenu(WidgetTester tester, String cle) =>
        tester.widget<TextField>(find.byKey(Key(cle))).controller!.text;

    testWidgets('trois champs masqués, comme la maquette', (tester) async {
      await afficher(tester, changer: accepte);

      for (final cle in ['mdp-ancien', 'mdp-nouveau', 'mdp-confirmation']) {
        final champ = tester.widget<TextField>(find.byKey(Key(cle)));
        expect(champ.obscureText, isTrue, reason: cle);
      }
      expect(find.text('ANCIEN MOT DE PASSE *'), findsOneWidget);
      expect(find.text('NOUVEAU MOT DE PASSE *'), findsOneWidget);
      expect(find.text('CONFIRMER LE NOUVEAU MOT DE PASSE *'), findsOneWidget);
    });

    testWidgets(
      "l'aide reprend la règle du prototype, tranchée par le client",
      (tester) async {
        await afficher(tester, changer: accepte);

        expect(
          find.text('Min. 8 caractères, 1 majuscule, 1 chiffre'),
          findsOneWidget,
        );
      },
    );

    testWidgets("champs vides : trois « obligatoire », rien n'est envoyé", (
      tester,
    ) async {
      await afficher(tester, changer: accepte);
      await saisir(tester);

      expect(find.text('Ce champ est obligatoire.'), findsNWidgets(3));
      expect(envois, isEmpty);
    });

    for (final (mdp, raison) in [
      ('Court1A', 'sept caractères'),
      ('minuscule1', 'sans majuscule'),
      ('MajusculeSeule', 'sans chiffre'),
    ]) {
      testWidgets("⚠️ $raison est refusé AVANT l'envoi", (tester) async {
        await afficher(tester, changer: accepte);
        await saisir(
          tester,
          ancien: 'Ancien1',
          nouveau: mdp,
          confirmation: mdp,
        );

        expect(find.byKey(const Key('erreur-nouveau')), findsOneWidget);
        expect(envois, isEmpty);
      });
    }

    testWidgets('une confirmation différente est refusée', (tester) async {
      await afficher(tester, changer: accepte);
      await saisir(
        tester,
        ancien: 'Ancien1',
        nouveau: 'Longueur8',
        confirmation: 'Longueur9',
      );

      expect(
        find.text('Les mots de passe ne correspondent pas.'),
        findsOneWidget,
      );
      expect(envois, isEmpty);
    });

    testWidgets(
      '⚠️⚠️ une saisie valide est ENVOYÉE, puis les champs se vident',
      (tester) async {
        await afficher(tester, changer: accepte);
        await saisir(
          tester,
          ancien: 'Ancien1',
          nouveau: 'Longueur8',
          confirmation: 'Longueur8',
        );

        expect(envois, [
          ['Ancien1', 'Longueur8', 'Longueur8'],
        ]);
        expect(find.byKey(const Key('mdp-reussi')), findsOneWidget);
        expect(
          find.text('Mot de passe mis à jour avec succès.'),
          findsOneWidget,
        );
        expect(contenu(tester, 'mdp-nouveau'), isEmpty);
      },
    );

    testWidgets("⚠️⚠️ un refus du serveur n'affiche JAMAIS un succès et place le "
        'message sous le bon champ', (tester) async {
      await afficher(tester, changer: refuse);
      await saisir(
        tester,
        ancien: 'Faux1',
        nouveau: 'Longueur8',
        confirmation: 'Longueur8',
      );

      expect(find.byKey(const Key('mdp-echec')), findsOneWidget);
      expect(find.byKey(const Key('mdp-reussi')), findsNothing);
      expect(find.textContaining('mis à jour avec'), findsNothing);
      expect(find.byKey(const Key('erreur-ancien')), findsOneWidget);
      // La saisie est conservée : l'utilisateur corrige, il ne retape pas tout.
      expect(contenu(tester, 'mdp-nouveau'), 'Longueur8');
    });

    testWidgets("⚠️ hors ligne, l'échec le dit sans rien simuler", (
      tester,
    ) async {
      await afficher(tester, changer: horsLigne);
      await saisir(
        tester,
        ancien: 'Ancien1',
        nouveau: 'Longueur8',
        confirmation: 'Longueur8',
      );

      expect(find.textContaining('nécessite le réseau'), findsOneWidget);
      expect(find.byKey(const Key('mdp-reussi')), findsNothing);
    });

    testWidgets("sans session, rien n'est envoyé et l'écran le dit", (
      tester,
    ) async {
      await afficher(tester, ouverte: null);
      await saisir(
        tester,
        ancien: 'Ancien1',
        nouveau: 'Longueur8',
        confirmation: 'Longueur8',
      );

      expect(
        find.text('Aucune session ouverte : connectez-vous.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('mdp-reussi')), findsNothing);
    });

    test(
      'la validation est la règle du client : 8, une majuscule, un chiffre',
      () {
        List<String> cles(String mdp) => MonProfilRepository.validerMotDePasse(
          ancien: 'a',
          nouveau: mdp,
          confirmation: mdp,
        ).keys.toList();

        expect(cles('Abcdefg1'), isEmpty); // huit exactement, sans symbole
        expect(cles('Abcdef1'), ['nouveau']); // sept
        expect(cles('abcdefg1'), ['nouveau']); // sans majuscule
        expect(cles('Abcdefgh'), ['nouveau']); // sans chiffre
      },
    );
  });

  group('mise en page', () {
    testWidgets('lg: deux colonnes 35 / 65', (tester) async {
      await afficher(tester, taille: const Size(1400, 1800));

      final gauche = tester.getRect(find.byKey(const Key('carte-identite')));
      final droite = tester.getRect(
        find.byKey(const Key('carte-mot-de-passe')),
      );

      expect(gauche.top, droite.top);
      expect(gauche.right, lessThan(droite.left));
      // Rapport 35 / 65 des largeurs (la gouttière de 16 px est hors rapport).
      expect(gauche.width / droite.width, closeTo(35 / 65, 0.01));
    });

    testWidgets('sous lg: les cartes s\'empilent', (tester) async {
      await afficher(tester, taille: const Size(800, 2400));

      final identite = tester.getRect(find.byKey(const Key('carte-identite')));
      final mdp = tester.getRect(find.byKey(const Key('carte-mot-de-passe')));

      expect(mdp.top, greaterThan(identite.bottom));
    });

    testWidgets('aucune carte d\'indicateur, comme la maquette', (
      tester,
    ) async {
      await afficher(tester);

      expect(
        find.byType(CarteKpi),
        findsNWidgets(cartesAttendues('mon-profil.html')),
      );
    });
  });

  group('RBAC — décision du commanditaire', () {
    test('⚠️ tout rôle ouvre son profil, bien que la page soit hors de la '
        'carte', () {
      final toutesLesListes = PermissionsPoste.carte.values
          .whereType<List<String>>()
          .expand((l) => l);
      // La carte du prototype reste recopiée sans retouche…
      expect(toutesLesListes, isNot(contains('mon-profil.html')));

      // … et c'est la règle des écrans universels qui ouvre la porte.
      for (final role in ['admin', 'caissier', 'animalier', 'comptable', 'x']) {
        expect(
          PermissionsPoste.autorise(role, EcranPoste.monProfil),
          isTrue,
          reason: role,
        );
      }
    });

    test('⚠️ la décision ne déborde pas : les autres écrans hors carte restent '
        'restreints', () {
      expect(
        PermissionsPoste.autorise('caissier', EcranPoste.suiviReproduction),
        isFalse,
      );
      expect(
        PermissionsPoste.autorise('caissier', EcranPoste.rapportsEtExports),
        isFalse,
      );
    });
  });

  group('menu du compte', () {
    Future<void> barre(
      WidgetTester tester, {
      VoidCallback? onMonProfil,
      String groupe = '',
    }) async {
      tester.view.physicalSize = const Size(1600, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarreSuperieure(
              groupe: groupe,
              ecran: 'Mon Profil',
              enAttente: 0,
              onBasculerMenu: () {},
              nomUtilisateur: 'Manager Olouwachegoun',
              onMonProfil: onMonProfil,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('« Mon Profil » ouvre l\'écran', (tester) async {
      var ouvert = 0;
      await barre(tester, onMonProfil: () => ouvert++);

      await tester.tap(find.byKey(const Key('menu-compte')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-compte-profil')));
      await tester.pumpAndSettle();

      expect(ouvert, 1);
    });

    testWidgets('sans accès, l\'entrée n\'est pas proposée', (tester) async {
      await barre(tester);

      expect(find.byKey(const Key('menu-compte')), findsNothing);
      expect(find.byKey(const Key('compte-nom')), findsOneWidget);
    });

    testWidgets('le fil d\'Ariane se réduit à l\'écran quand il n\'a pas de '
        'groupe', (tester) async {
      await barre(tester);

      expect(texte(tester, 'fil-ariane'), 'Mon Profil');
    });
  });

  group('libellés du journal', () {
    test('les clés de connexion portent le libellé du serveur', () {
      expect(LibellesAudit.action('login'), 'Connexion réussie');
      expect(
        LibellesAudit.action('api.login'),
        'Connexion API (appareil Flutter)',
      );
      expect(LibellesAudit.module('rh'), 'Personnel & Stages');
      expect(LibellesAudit.module(null), isNull);
    });

    test('⚠️ la table générée n\'a pas été tronquée', () {
      // 117 actions et 12 modules à la génération (outils/libelles_audit.py).
      // Un nombre plus bas dit qu'elle a été régénérée sur un modèle amputé.
      expect(LibellesAudit.actions.length, greaterThanOrEqualTo(117));
      expect(LibellesAudit.modules.length, greaterThanOrEqualTo(12));
    });
  });
}
