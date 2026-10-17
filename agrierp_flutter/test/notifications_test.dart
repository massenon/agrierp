import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/notifications/notifications_repository.dart';
import 'package:agrierp/features/notifications/notifications_screen.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.59 — CENTRE DE NOTIFICATIONS (`notifications.html`) et cloche.
///
/// ⚠️⚠️ **LES NOTIFICATIONS SONT PRODUITES PAR LE SERVEUR.** Le poste les affiche
/// après un tirage ; « lue » et « supprimer » exigent le réseau et ne sont
/// jamais appliqués localement sans la confirmation du serveur.
class _ServeurFeint extends Interceptor {
  _ServeurFeint({this.code = 200, this.horsLigne = false});

  final int code;
  final bool horsLigne;
  final appels = <String>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    appels.add('${options.method} ${options.path}');

    if (horsLigne) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
    } else if (code >= 400) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: code,
          ),
        ),
      );
    } else {
      handler.resolve(
        Response<dynamic>(requestOptions: options, statusCode: 200),
      );
    }
  }
}

void main() {
  late AppDatabase db;
  final maintenant = DateTime(2026, 7, 28, 12);

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> notif(
    String cle,
    String message, {
    String categorie = 'Stocks',
    String gravite = 'info',
    bool lue = false,
    DateTime? date,
    String? lien,
    bool sansDate = false,
  }) => db
      .into(db.notifications)
      .insert(
        NotificationsCompanion.insert(
          id: uuid(cle),
          type: 'stock_low',
          category: Value(categorie),
          severity: Value(gravite),
          title: message,
          message: message,
          linkUrl: Value(lien),
          isRead: Value(lue),
          createdAt: Value(sansDate ? null : (date ?? maintenant)),
        ),
      );

  /// Les six lignes de la maquette.
  Future<void> jeuDeLaMaquette() async {
    await notif(
      'a',
      'Autonomie alimentaire critique — Provende Lapins',
      categorie: 'Élevage',
      gravite: 'critique',
      date: DateTime(2026, 7, 28, 6, 12),
      lien: '/bons-commande',
    );
    await notif(
      'b',
      'Seuil critique atteint — Vaccin Newcastle',
      categorie: 'Stocks',
      gravite: 'critique',
      date: DateTime(2026, 7, 27, 18, 40),
      lien: '/gestion-stocks?produit=X',
    );
    await notif(
      'c',
      'Facture FAC-2026-101 en attente de règlement',
      categorie: 'Finance',
      gravite: 'moyen',
      date: DateTime(2026, 7, 27, 9, 5),
      lien: '/creances-clients',
    );
    await notif(
      'd',
      'Frais de stage AGOSSOU Félicité en attente',
      categorie: 'RH',
      gravite: 'info',
      lue: true,
      date: DateTime(2026, 7, 26, 14, 22),
      lien: '/personnel-stages',
    );
    await notif(
      'e',
      'Rappel vaccination Newcastle — Volailles Lot B',
      categorie: 'Élevage',
      gravite: 'moyen',
      lue: true,
      date: DateTime(2026, 7, 25, 8),
      lien: '/soins-vaccins-hub',
    );
    await notif(
      'f',
      'Réception validée — Bon de commande BC-2026-06-0001',
      categorie: 'Stocks',
      gravite: 'info',
      lue: true,
      date: DateTime(2026, 7, 24, 16, 10),
      lien: '/gestion-stocks',
    );
  }

  NotificationsRepository depot({_ServeurFeint? serveur}) {
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'));
    if (serveur != null) client.interceptors.add(serveur);
    return NotificationsRepository(
      database: db,
      serveur: serveur == null ? null : ServeurNotifications(client),
    );
  }

  group('dépôt', () {
    test('⚠️ les trois indicateurs se recalculent à part', () async {
      await jeuDeLaMaquette();
      // Une critique DÉJÀ LUE ne compte pas parmi les « Critiques ».
      await notif(
        'g',
        'Ancienne alerte critique',
        gravite: 'critique',
        lue: true,
        date: DateTime(2026, 7, 20),
      );
      // Hors fenêtre de 30 jours : ne compte que dans aucun total.
      await notif(
        'h',
        'Vieille notification',
        lue: true,
        date: DateTime(2026, 5, 1),
      );

      final d = await depot().charger(maintenant: maintenant);

      // Recalcul indépendant, ligne par ligne de la maquette.
      expect(d.nonLues, 3);
      expect(d.critiques, 2);
      expect(d.total30Jours, 7); // six de la maquette + « Ancienne alerte »
      expect(d.lignes, hasLength(8));
    });

    test('la plus récente d\'abord, les sans-date en dernier', () async {
      await notif('a', 'ancienne', date: DateTime(2026, 7, 1));
      await notif('b', 'sans date', sansDate: true);
      await notif('c', 'récente', date: DateTime(2026, 7, 28));

      final d = await depot().charger(maintenant: maintenant);

      expect(d.lignes.map((l) => l.message), [
        'récente',
        'ancienne',
        'sans date',
      ]);
    });

    test(
      '⚠️ une ligne sans date n\'est jamais comptée comme récente',
      () async {
        await notif('a', 'sans date', sansDate: true);

        final d = await depot().charger(maintenant: maintenant);

        expect(d.total30Jours, 0);
        expect(d.lignes.single.dateTexte, '—');
      },
    );

    test(
      'base vide : des zéros VRAIS, car le poste sait qu\'il n\'a rien',
      () async {
        final d = await depot().charger(maintenant: maintenant);

        expect(d.nonLues, 0);
        expect(d.critiques, 0);
        expect(d.total30Jours, 0);
      },
    );
  });

  group('filtres', () {
    Future<List<LigneNotification>> toutes() async {
      await jeuDeLaMaquette();
      return (await depot().charger(maintenant: maintenant)).lignes;
    }

    test('catégorie', () async {
      final l = NotificationsRepository.filtrer(
        await toutes(),
        categorie: 'Élevage',
      );
      expect(l, hasLength(2));
    });

    test('⚠️ « RH » ne ramène que ce que le serveur a classé RH', () async {
      final l = NotificationsRepository.filtrer(
        await toutes(),
        categorie: 'RH',
      );
      expect(l.single.message, contains('AGOSSOU'));
    });

    test('statut', () async {
      final tout = await toutes();
      expect(
        NotificationsRepository.filtrer(tout, statut: 'Non lue'),
        hasLength(3),
      );
      expect(
        NotificationsRepository.filtrer(tout, statut: 'Lue'),
        hasLength(3),
      );
    });

    test(
      '⚠️ la recherche ignore la casse ET les accents de majuscule',
      () async {
        // `LIKE` de SQLite échouerait sur « élevage » contre « Élevage ».
        final l = NotificationsRepository.filtrer(
          await toutes(),
          recherche: 'élevage',
        );
        expect(l, hasLength(2));
      },
    );

    test('la recherche porte sur toute la ligne affichée', () async {
      final tout = await toutes();
      expect(
        NotificationsRepository.filtrer(tout, recherche: 'critique'),
        hasLength(2),
        reason: 'gravité « Critique » + message « critique »',
      );
      expect(
        NotificationsRepository.filtrer(tout, recherche: 'non lue'),
        hasLength(3),
      );
    });

    test('les filtres se combinent', () async {
      final l = NotificationsRepository.filtrer(
        await toutes(),
        categorie: 'Stocks',
        statut: 'Lue',
      );
      expect(l.single.message, contains('BC-2026'));
    });
  });

  group('« Résoudre »', () {
    LigneNotification avec(String? lien) => LigneNotification(
      id: 'x',
      message: 'm',
      categorie: 'Stocks',
      gravite: 'info',
      lue: false,
      date: null,
      lien: lien,
    );

    test('l\'écran se déduit de l\'adresse, requête ignorée', () {
      expect(
        avec('/gestion-stocks?produit=SKU1').ecranDuLien,
        EcranPoste.gestionStocks,
      );
    });

    test('une adresse absolue est lue comme un chemin', () {
      expect(
        avec('http://ferme.test/soins-vaccins-hub').ecranDuLien,
        EcranPoste.soinsEtVaccins,
      );
    });

    test('⚠️ une page que le poste n\'a pas ne donne PAS de flèche', () {
      expect(avec('/gestion-bandes?search=LOT1').ecranDuLien, isNull);
      expect(avec('/page-inconnue').ecranDuLien, isNull);
      expect(avec(null).ecranDuLien, isNull);
      expect(avec('').ecranDuLien, isNull);
      expect(avec('/').ecranDuLien, isNull);
    });
  });

  group('actions', () {
    test('marquer lue : serveur d\'abord, base ensuite', () async {
      await notif('a', 'm');
      final serveur = _ServeurFeint();

      await depot(serveur: serveur).marquerLue(uuid('a'));

      expect(serveur.appels, ['POST /api/notifications/${uuid('a')}/read']);
      expect((await db.select(db.notifications).getSingle()).isRead, isTrue);
    });

    test('supprimer : serveur d\'abord, base ensuite', () async {
      await notif('a', 'm');
      final serveur = _ServeurFeint();

      await depot(serveur: serveur).supprimer(uuid('a'));

      expect(serveur.appels, ['DELETE /api/notifications/${uuid('a')}']);
      expect(await db.select(db.notifications).get(), isEmpty);
    });

    test(
      '⚠️⚠️ hors ligne : refusé, et RIEN n\'est modifié localement',
      () async {
        await notif('a', 'm');
        final r = depot(serveur: _ServeurFeint(horsLigne: true));

        await expectLater(
          r.marquerLue(uuid('a')),
          throwsA(
            isA<EchecNotification>().having(
              (e) => e.message,
              'message',
              contains('nécessite le réseau'),
            ),
          ),
        );
        await expectLater(
          r.supprimer(uuid('a')),
          throwsA(isA<EchecNotification>()),
        );

        final ligne = await db.select(db.notifications).getSingle();
        expect(ligne.isRead, isFalse);
      },
    );

    test('un 404 dit que la notification n\'existe plus', () async {
      await notif('a', 'm');

      await expectLater(
        depot(serveur: _ServeurFeint(code: 404)).marquerLue(uuid('a')),
        throwsA(
          isA<EchecNotification>().having(
            (e) => e.message,
            'message',
            contains("n'existe plus"),
          ),
        ),
      );
    });

    test('sans session, l\'action le dit', () async {
      await notif('a', 'm');

      await expectLater(
        depot().marquerLue(uuid('a')),
        throwsA(
          isA<EchecNotification>().having(
            (e) => e.message,
            'message',
            contains('Aucune session'),
          ),
        ),
      );
    });
  });

  group('écran', () {
    Future<void> afficher(
      WidgetTester tester, {
      NotificationsRepository? d,
      void Function(EcranPoste)? onOuvrir,
      VoidCallback? onModifie,
      Size taille = const Size(1600, 2000),
    }) async {
      tester.view.physicalSize = taille;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            depot: d ?? depot(serveur: _ServeurFeint()),
            onOuvrir: onOuvrir,
            onModifie: onModifie,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String valeurDe(WidgetTester tester, String libelle) {
      final carte = find.ancestor(
        of: find.text(libelle.toUpperCase()),
        matching: find.byType(CarteKpi),
      );
      return tester.widget<CarteKpi>(carte).valeur;
    }

    testWidgets(
      'titre, sous-titre et trois cartes dans l\'ordre de la maquette',
      (tester) async {
        await jeuDeLaMaquette();
        await afficher(tester);

        expect(find.text('Centre de Notifications'), findsOneWidget);
        expect(
          find.text("Toutes les alertes et notifications système d'AgriERP."),
          findsOneWidget,
        );
        expect(
          find.byType(CarteKpi),
          findsNWidgets(cartesAttendues('notifications.html')),
        );

        final cartes = tester
            .widgetList<CarteKpi>(find.byType(CarteKpi))
            .toList();
        // ⚠️ LES LIBELLÉS DE CARTE, que l'extracteur de vocabulaire ne voit pas.
        expect(cartes.map((c) => c.libelle), [
          'Non Lues',
          'Critiques',
          'Total (30 jours)',
        ]);
        expect(cartes.map((c) => c.couleurLisere), [
          AgriColorsAlias.rouge,
          AgriColorsAlias.jaune,
          AgriColorsAlias.vert,
        ]);
      },
    );

    testWidgets('les valeurs affichées sont celles du recalcul', (
      tester,
    ) async {
      // Dates relatives à MAINTENANT : l'écran lit l'horloge réelle.
      final hier = DateTime.now().subtract(const Duration(days: 1));
      await notif('a', 'critique non lue', gravite: 'critique', date: hier);
      await notif('b', 'moyenne non lue', gravite: 'moyen', date: hier);
      await notif('c', 'info lue', lue: true, date: hier);
      await afficher(tester);

      expect(valeurDe(tester, 'Non Lues'), '2');
      expect(valeurDe(tester, 'Critiques'), '1');
      expect(valeurDe(tester, 'Total (30 jours)'), '3');
    });

    testWidgets('les six colonnes de la maquette, dans son ordre', (
      tester,
    ) async {
      await jeuDeLaMaquette();
      await afficher(tester);

      final x = [
        for (final e in [
          'DATE / HEURE',
          'CATÉGORIE',
          'MESSAGE',
          'GRAVITÉ',
          'STATUT',
          'ACTIONS',
        ])
          tester.getTopLeft(find.text(e)).dx,
      ];
      expect(x, orderedEquals([...x]..sort()));
    });

    testWidgets(
      'six lignes, la plus récente en tête, date au format maquette',
      (tester) async {
        await jeuDeLaMaquette();
        await afficher(tester);

        for (var i = 0; i < 6; i++) {
          expect(find.byKey(Key('ligne-notif-$i')), findsOneWidget);
        }
        expect(find.byKey(const Key('ligne-notif-6')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('ligne-notif-0')),
            matching: find.text('28/07/2026 - 06:12'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('ligne-notif-0')),
            matching: find.text('Critique'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('filtrer par statut puis par recherche', (tester) async {
      await jeuDeLaMaquette();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('notif-statut')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Non lue').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ligne-notif-2')), findsOneWidget);
      expect(find.byKey(const Key('ligne-notif-3')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('notif-recherche')),
        'vaccin',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ligne-notif-0')), findsOneWidget);
      expect(find.byKey(const Key('ligne-notif-1')), findsNothing);
    });

    testWidgets('aucun résultat : le tableau le dit', (tester) async {
      await jeuDeLaMaquette();
      await afficher(tester);

      await tester.enterText(find.byKey(const Key('notif-recherche')), 'zzz');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notif-vide')), findsOneWidget);
    });

    testWidgets('marquer lue : la ligne passe « Lue », la carte baisse', (
      tester,
    ) async {
      await jeuDeLaMaquette();
      var modifie = 0;
      await afficher(tester, onModifie: () => modifie++);

      expect(
        tester.widget<Text>(find.byKey(const Key('statut-notif-0'))).data,
        'Non lue',
      );
      await tester.tap(find.byKey(const Key('lue-0')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('statut-notif-0'))).data,
        'Lue',
      );
      expect(find.byKey(const Key('notif-reussi')), findsOneWidget);
      expect(valeurDe(tester, 'Non Lues'), '2');
      expect(modifie, 1, reason: 'la cloche doit être rafraîchie');
    });

    testWidgets('supprimer retire la ligne', (tester) async {
      await jeuDeLaMaquette();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('suppr-0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ligne-notif-5')), findsNothing);
      expect(find.text('Notification supprimée.'), findsOneWidget);
      expect(await db.select(db.notifications).get(), hasLength(5));
    });

    testWidgets(
      '⚠️⚠️ hors ligne : échec visible, ligne inchangée, pas de succès',
      (tester) async {
        await jeuDeLaMaquette();
        await afficher(
          tester,
          d: depot(serveur: _ServeurFeint(horsLigne: true)),
        );

        await tester.tap(find.byKey(const Key('lue-0')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('notif-echec')), findsOneWidget);
        expect(find.byKey(const Key('notif-reussi')), findsNothing);
        expect(find.textContaining('nécessite le réseau'), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('statut-notif-0'))).data,
          'Non lue',
        );
      },
    );

    testWidgets(
      '« Résoudre » ouvre l\'écran visé, et n\'existe que s\'il y en a un',
      (tester) async {
        await jeuDeLaMaquette();
        // Une notification dont le lien n'a pas d'écran au poste, la plus récente.
        await notif(
          'z',
          'Lot à surveiller',
          date: DateTime(2026, 7, 29),
          lien: '/gestion-bandes?search=L1',
        );
        EcranPoste? ouvert;
        await afficher(tester, onOuvrir: (e) => ouvert = e);

        // Ligne 0 = « Lot à surveiller » : aucune flèche.
        expect(find.byKey(const Key('resoudre-0')), findsNothing);
        // Ligne 2 = « Seuil critique atteint » → /gestion-stocks.
        await tester.tap(find.byKey(const Key('resoudre-2')));
        await tester.pumpAndSettle();

        expect(ouvert, EcranPoste.gestionStocks);
      },
    );

    testWidgets(
      'l\'écran dit que ce sont les notifications du dernier tirage',
      (tester) async {
        await afficher(tester);

        expect(
          tester.widget<Text>(find.byKey(const Key('notif-portee'))).data,
          contains('dernier tirage'),
        );
      },
    );
  });

  group('cloche', () {
    Future<void> barre(
      WidgetTester tester, {
      int? nonLues,
      List<ApercuNotification> recentes = const [],
      VoidCallback? onNotifications,
    }) async {
      tester.view.physicalSize = const Size(1600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarreSuperieure(
              groupe: '',
              ecran: 'Notifications',
              enAttente: 0,
              onBasculerMenu: () {},
              nonLues: nonLues,
              recentes: recentes,
              onNotifications: onNotifications,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ApercuNotification ap(int i, {bool lue = false}) => ApercuNotification(
      message: 'Message $i',
      dateTexte: '28/07/2026 - 0$i:00',
      lue: lue,
      critique: i == 0,
    );

    testWidgets('le compteur affiche les non lues', (tester) async {
      await barre(tester, nonLues: 3, onNotifications: () {});

      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('cloche-compteur')),
                matching: find.byType(Text),
              ),
            )
            .data,
        '3',
      );
    });

    testWidgets(
      '⚠️ zéro non lue : pas de badge, mais la cloche reste utilisable',
      (tester) async {
        await barre(tester, nonLues: 0, onNotifications: () {});

        expect(find.byKey(const Key('cloche-compteur')), findsNothing);
        expect(find.byKey(const Key('cloche-notifications')), findsOneWidget);
      },
    );

    testWidgets('au-delà de 99, « 99+ »', (tester) async {
      await barre(tester, nonLues: 150, onNotifications: () {});

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('le menu montre QUATRE notifications au plus', (tester) async {
      await barre(
        tester,
        nonLues: 6,
        recentes: [for (var i = 0; i < 6; i++) ap(i)],
        onNotifications: () {},
      );

      await tester.tap(find.byKey(const Key('cloche-notifications')));
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        expect(find.byKey(Key('cloche-notif-$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('cloche-notif-4')), findsNothing);
    });

    testWidgets('« Voir toutes les notifications » ouvre le Centre', (
      tester,
    ) async {
      var ouvert = 0;
      await barre(
        tester,
        nonLues: 1,
        recentes: [ap(0)],
        onNotifications: () => ouvert++,
      );

      await tester.tap(find.byKey(const Key('cloche-notifications')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloche-voir-toutes')));
      await tester.pumpAndSettle();

      expect(ouvert, 1);
    });

    testWidgets('sans notification, le menu le dit', (tester) async {
      await barre(tester, nonLues: 0, onNotifications: () {});

      await tester.tap(find.byKey(const Key('cloche-notifications')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloche-vide')), findsOneWidget);
    });
  });

  group('RBAC', () {
    test('⚠️ ouvert à tout rôle — extension à confirmer par le client', () {
      for (final role in ['admin', 'caissier', 'animalier', 'comptable', 'x']) {
        expect(
          PermissionsPoste.autorise(role, EcranPoste.notifications),
          isTrue,
          reason: role,
        );
      }
    });

    test('la carte du prototype reste recopiée sans la page', () {
      final listes = PermissionsPoste.carte.values
          .whereType<List<String>>()
          .expand((l) => l);
      expect(listes, isNot(contains('notifications.html')));
    });
  });
}

/// Couleurs des trois liserés de la maquette (`border-l-error-red`,
/// `border-l-accent-yellow`, `border-l-brand-emerald`).
class AgriColorsAlias {
  static const rouge = Color(0xFFDC2626);
  static const jaune = Color(0xFFFFD55F);
  static const vert = Color(0xFF065F46);
}
