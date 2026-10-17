import 'dart:io';

import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/config/parametres_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/theme/agri_theme.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:agrierp/features/administration/administration_repository.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/elevage/transferts_repository.dart';
import 'package:agrierp/features/elevage/dashboard_elevage_repository.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/parametres_elevage_repository.dart';
import 'package:agrierp/features/elevage/production_oeufs_service.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/elevage/soins_vaccins_repository.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_repository.dart';
import 'package:agrierp/features/contact/contact_editeur_repository.dart';
import 'package:agrierp/features/notifications/notifications_repository.dart';
import 'package:agrierp/features/elevage/sujets_repository.dart';
import 'package:agrierp/features/rh/attestations_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_repository.dart';
import 'package:agrierp/features/rapports/rapports_repository.dart';
import 'package:agrierp/features/rh/personnel_repository.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/facturation_repository.dart';
import 'package:agrierp/features/ventes/ventes_devis_repository.dart';
import 'package:agrierp/main.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket AF1.4 — CAPTURES DU POSTE (phase 1D de AUDIT_FIDELISATION.md).
///
/// ⚠️⚠️ **INSTRUMENT, PAS TEST.** Monte la coque complète (`SocleAccueil` : barre
/// latérale + barre supérieure + écran) et écrit des PNG dans
/// `build/audit/captures/`, que `outils/captures.py` met en regard de ceux du
/// prototype (Chrome headless, mêmes dimensions).
///
/// ⚠️ **LES POLICES SONT CHARGÉES À LA MAIN.** `flutter test` rend tout en police
/// « Ahem » (des carrés) tant qu'on ne lui en donne pas d'autre. On charge ici
/// Segoe UI — la police que Windows fournit au poste quand aucune police n'est
/// embarquée, ce qui est le cas (voir RAPPORT_JETONS.md § 6) — et les icônes
/// Material du SDK. La capture montre donc ce que verrait l'utilisateur, pas le
/// rendu de test.
///
/// ⚠️ **NE S'EXÉCUTE QUE SUR DEMANDE** : `AUDIT_RENDU=1 flutter test
/// test/capture_ecrans_test.dart --update-goldens`. Les « goldens » ne servent
/// ici qu'à écrire les images ; rien n'est comparé.
///
/// ⚠️ **LIMITES** : base vide (aucune ligne de tableau), utilisateur non connecté
/// (« Utilisateur » dans le pied de barre), emoji et polices absentes de Segoe UI
/// remplacés. Ce sont les différences de DONNÉES qui apparaîtront à côté du
/// prototype, pas des défauts.
void main() {
  final actif = Platform.environment['AUDIT_RENDU'] == '1';

  /// Écran du poste ↔ page du prototype capturée à côté.
  const ecrans = <EcranPoste, String>{
    EcranPoste.tableauDeBord: 'dashboard',
    EcranPoste.gestionElevage: 'gestion-elevage',
    EcranPoste.dashboardElevage: 'elevage-dashboard',
    EcranPoste.suiviReproduction: 'suivi-reproduction',
    EcranPoste.soinsEtVaccins: 'soins-vaccins-hub',
    EcranPoste.parametresElevage: 'parametres-elevage',
    EcranPoste.ventesEtDevis: 'ventes-devis',
    EcranPoste.clientsEtCreances: 'creances-clients',
    EcranPoste.achatsEtCommandes: 'achats-commandes',
    EcranPoste.fournisseurs: 'fournisseurs',
    EcranPoste.saisieDepenses: 'saisie-depenses',
    EcranPoste.gestionStocks: 'gestion-stocks',
    EcranPoste.catalogueProduits: 'catalogue-produits',
    EcranPoste.facturation: 'facturation',
    EcranPoste.personnelEtStages: 'personnel-stages',
    EcranPoste.administrationEtDocument: 'administration',
    EcranPoste.comptabilite: 'comptabilite-hub',
    EcranPoste.parametresGeneraux: 'parametres-hub',
    EcranPoste.rapportsEtExports: 'rapports-exports',
  };

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> chargerPolices() async {
    Future<ByteData> octets(String chemin) async => ByteData.sublistView(
      Uint8List.fromList(File(chemin).readAsBytesSync()),
    );

    final segoe = FontLoader('Segoe UI')
      ..addFont(octets(r'C:\Windows\Fonts\segoeui.ttf'))
      ..addFont(octets(r'C:\Windows\Fonts\seguisb.ttf'))
      ..addFont(octets(r'C:\Windows\Fonts\segoeuib.ttf'));
    await segoe.load();

    final icones = FontLoader('MaterialIcons')
      ..addFont(
        octets(
          r'C:\src\flutter\bin\cache\artifacts\material_fonts\'
          'materialicons-regular.otf',
        ),
      );
    await icones.load();
  }

  SocleAccueil coque() {
    const poste = 'poste-audit';
    final soins = SoinsRepository(database: db, deviceId: poste);
    final client = Dio();
    return SocleAccueil(
      database: db,
      engine: SyncEngine(database: db, client: client, deviceId: poste),
      auth: AuthService(client: client, deviceName: poste),
      fiches: FicheJournaliereRepository(database: db, deviceId: poste),
      caisse: CaisseRepository(database: db, deviceId: poste),
      soins: soins,
      production: ProductionOeufsService(database: db),
      depenses: DepensesRepository(database: db, deviceId: poste),
      achats: AchatsRepository(database: db, identifiantPoste: poste),
      fournisseurs: FournisseursRepository(database: db),
      facturation: FacturationRepository(database: db),
      personnel: PersonnelRepository(database: db, identifiantPoste: poste),
      administration: AdministrationRepository(database: db),
      comptabilite: ComptabiliteRepository(database: db),
      parametresGeneraux: ParametresGenerauxRepository(database: db),
      rapports: RapportsRepository(database: db),
      tableauDeBord: TableauDeBordRepository(database: db),
      dashboardElevage: DashboardElevageRepository(database: db, soins: soins),
      transferts: TransfertsRepository(database: db, deviceId: poste),
      reproduction: SuiviReproductionRepository(database: db, deviceId: poste),
      soinsVaccins: SoinsVaccinsRepository(database: db, soins: soins),
      parametresElevage: ParametresElevageRepository(database: db),
      ventesDevis: VentesDevisRepository(database: db),
      stocks: StocksRepository(database: db, deviceId: poste),
      clients: ClientsCreancesRepository(database: db, deviceId: 'poste-test'),
      notifications: NotificationsRepository(database: db),
      contact: const ContactEditeurRepository(),
      attestations: AttestationsRepository(database: db),
      sujets: SujetsRepository(database: db),
      parametres: ParametresPoste(database: db),
      identifiantPoste: poste,
    );
  }

  final alertes = <Map<String, String>>[];
  var ou = '';

  Future<void> monter(WidgetTester t, Size taille) async {
    t.view.physicalSize = taille;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AgriTheme.light,
        home: coque(),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('captures de la coque et des écrans', (t) async {
    // ⚠️ `flutter test` suppose Android, dont la police est Roboto ; le poste
    // tourne sous Windows, dont la police est Segoe UI. Sans cette ligne la
    // police chargée ci-dessus n'est jamais demandée.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await chargerPolices();

    final ancien = FlutterError.onError;
    FlutterError.onError = (d) {
      alertes.add({
        'ou': ou,
        'message': d.exceptionAsString().split('\n').first,
      });
    };

    Future<void> capturer(String nom) async {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../build/audit/captures/poste_$nom.png'),
      );
    }

    // 1. La coque du tableau de bord à trois tailles de fenêtre. C'est ici que
    //    se voit — ou non — le défilement de la barre latérale.
    for (final (l, h) in [(1280, 720), (1366, 768), (1920, 1080)]) {
      ou = 'coque ${l}x$h';
      await monter(t, Size(l.toDouble(), h.toDouble()));
      await capturer('dashboard_${l}x$h');
    }

    // 2. Chaque écran, à 1280×720, comme la capture du prototype.
    await monter(t, const Size(1280, 720));
    for (final e in ecrans.entries) {
      ou = 'écran ${e.value}';
      final entree = find.byKey(Key('nav-${e.key.name}'));
      if (entree.evaluate().isEmpty) continue;
      await t.ensureVisible(entree.first);
      await t.tap(entree.first, warnIfMissed: false);
      await t.pumpAndSettle();
      await capturer(e.value.replaceAll('-', '_'));
    }

    // 3. « Mon Profil » : hors barre latérale, il s'ouvre par le menu du compte.
    ou = 'écran mon-profil';
    await t.tap(find.byKey(const Key('menu-compte')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-compte-profil')));
    await t.pumpAndSettle();
    await capturer('mon_profil');

    // 4. Centre de Notifications : les six lignes de la maquette, ouvertes par
    //    le menu de la cloche.
    ou = 'écran notifications';
    final lignes = [
      (
        DateTime(2026, 7, 28, 6, 12),
        'elevage',
        'critique',
        false,
        'Autonomie alimentaire critique — Provende Lapins (2.8 jours restants)',
      ),
      (
        DateTime(2026, 7, 27, 18, 40),
        'stock_low',
        'critique',
        false,
        'Seuil critique atteint — Vaccin Newcastle (2 boîtes restantes)',
      ),
      (
        DateTime(2026, 7, 27, 9, 5),
        'payment_due',
        'moyen',
        false,
        'Facture FAC-2026-101 en attente de règlement depuis 15 jours',
      ),
      (
        DateTime(2026, 7, 26, 14, 22),
        'system',
        'info',
        true,
        'Frais de stage AGOSSOU Félicité en attente de paiement',
      ),
      (
        DateTime(2026, 7, 25, 8),
        'prophylaxis_due',
        'moyen',
        true,
        'Rappel vaccination Newcastle — Volailles Lot B dans 2 jours',
      ),
      (
        DateTime(2026, 7, 24, 16, 10),
        'stock_low',
        'info',
        true,
        'Réception validée — Bon de commande BC-2026-06-0001',
      ),
    ];
    const categories = {
      'elevage': 'Élevage',
      'stock_low': 'Stocks',
      'payment_due': 'Finance',
      'system': 'RH',
      'prophylaxis_due': 'Élevage',
    };
    for (var i = 0; i < lignes.length; i++) {
      final (date, type, gravite, lue, message) = lignes[i];
      await db
          .into(db.notifications)
          .insert(
            NotificationsCompanion.insert(
              id: 'notif-${i.toString().padLeft(2, '0')}'.padRight(36, '0'),
              type: type,
              category: Value(categories[type]!),
              severity: Value(gravite),
              title: message,
              message: message,
              isRead: Value(lue),
              createdAt: Value(date),
            ),
          );
    }
    // Un changement d'écran relit la cloche, comme le ferait une synchronisation.
    await t.tap(find.byKey(const Key('nav-tableauDeBord')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('cloche-notifications')));
    await t.pumpAndSettle();
    await capturer('notifications_menu');
    await t.tap(find.byKey(const Key('cloche-voir-toutes')));
    await t.pumpAndSettle();
    await capturer('notifications');

    // 5. Aide & À Propos, par le menu du compte.
    ou = 'écran aide-a-propos';
    await t.tap(find.byKey(const Key('menu-compte')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-compte-aide')));
    await t.pumpAndSettle();
    await capturer('aide_a_propos');

    // 5 bis. Bilan Technico-Économique : un onglet du Dashboard Élevage, avec une
    //        bande aux ordres de grandeur de la maquette (LOT-LAP-2026-06).
    ou = 'écran bilan-technico-economique';
    final lotBilan = 'lot-bilan'.padRight(36, '0');
    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: lotBilan,
            code: 'LOT-LAP-2026-06',
            speciesId: 'espece-cuniculture',
            speciesCode: const Value('cuniculture'),
            initialQuantity: const Value(27),
            acquisitionCost: const Value(135000),
            createdDate: Value(DateTime(2026, 6, 1)),
          ),
        );
    await db
        .into(db.feedTypes)
        .insert(
          FeedTypesCompanion.insert(
            id: 'feed-bilan'.padRight(36, '0'),
            name: 'Provende lapins',
            speciesId: const Value('espece-cuniculture'),
            speciesLabel: const Value('Cuniculture'),
            pricePerKg: const Value(700),
          ),
        );
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: 'fiche-bilan'.padRight(36, '0'),
            deviceId: 'poste-audit',
            updatedAt: DateTime(2026, 7, 1),
            lotId: lotBilan,
            entryDate: DateTime(2026, 7, 1),
            feedQtyKg: const Value(120.3),
          ),
        );
    await db
        .into(db.veterinaryRecords)
        .insert(
          VeterinaryRecordsCompanion.insert(
            id: 'soin-bilan'.padRight(36, '0'),
            deviceId: 'poste-audit',
            updatedAt: DateTime(2026, 7, 1),
            lotId: lotBilan,
            actionType: 'Vaccination',
            recordDate: DateTime(2026, 7, 1),
            cost: const Value(12500),
          ),
        );
    for (final (i, (nom, montant)) in [
      ('Lapin vif (POS)', 145000.0),
      ('Viande de lapin', 62000.0),
    ].indexed) {
      await db
          .into(db.lotRevenues)
          .insert(
            LotRevenuesCompanion.insert(
              lotId: lotBilan,
              productId: 'prod-bilan-$i'.padRight(36, '0'),
              label: 'Ventes — $nom',
              amount: montant,
            ),
          );
    }
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: SyncEngine.cleRevenusTires,
            value: DateTime.now().toUtc().toIso8601String(),
          ),
        );
    await t.tap(find.byKey(const Key('nav-dashboardElevage')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('onglet-Rentabilité')));
    await t.pumpAndSettle();
    await capturer('bilan_technico_economique');

    // 5 ter. Attestations : onglet du hub Personnel & Stages, avec un modèle et
    //        une personne choisie (l'aperçu se compose au poste).
    ou = 'écran rh-attestations';
    await db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            id: 'emp-attest'.padRight(36, '0'),
            firstName: 'Jean',
            lastName: 'AGOSSOU',
            position: const Value('Animalier'),
            hireDate: Value(DateTime(2024, 3, 1)),
          ),
        );
    await db
        .into(db.attestationTemplates)
        .insert(
          AttestationTemplatesCompanion.insert(
            id: 'mod-emp'.padRight(36, '0'),
            type: 'employe',
            bodyText:
                'Nous soussigné, Ferme École OLOUWACHEGOUN, attestons que [NOM], '
                'est employé(e) au sein de notre structure en qualité de [POSTE] '
                'sous contrat [CONTRAT] du [DATE_DEBUT] au [DATE_FIN].',
          ),
        );
    // ⚠️ L'entrée « Personnel & Stages » est HORS DE LA FENÊTRE à 720 px de haut
    // (la barre latérale ne défile pas — voir RAPPORT_VISUEL.md). On agrandit la
    // fenêtre le temps du clic, puis on la rend à sa taille.
    t.view.physicalSize = const Size(1280, 1500);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('nav-personnelEtStages')));
    await t.pumpAndSettle();
    t.view.physicalSize = const Size(1280, 720);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('onglet-personnel-Attestations')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('att-personne')));
    await t.pumpAndSettle();
    await t.tap(find.text('AGOSSOU Jean').last);
    await t.pumpAndSettle();
    await capturer('rh_attestations');

    // 5 quater. Fiche Sujet : ouverte par le lien d'une référence de saillie.
    ou = 'écran animal-details';
    final lotSujet = 'lot-sujet'.padRight(36, '0');
    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: lotSujet,
            code: 'LOT-CUNI-2026-011',
            speciesId: 'espece-cuniculture',
            speciesCode: const Value('cuniculture'),
            currentQuantity: const Value(20),
          ),
        );
    await db
        .into(db.animals)
        .insert(
          AnimalsCompanion.insert(
            id: 'sujet-143'.padRight(36, '0'),
            identifier: 'LAP-2026-0143',
            speciesLabel: const Value('Lapin (Cuniculture)'),
            lotId: Value(lotSujet),
            lotCode: const Value('LOT-CUNI-2026-011'),
            breed: const Value('Néo-Zélandais Blanc'),
            birthDate: Value(DateTime(2026, 2, 12)),
            entryDate: Value(DateTime(2026, 2, 15)),
            origin: const Value('Naissance interne (Lot LOT-CUNI-2026-002)'),
            cage: const Value('C5'),
          ),
        );
    await db
        .into(db.livestockReproductionEvents)
        .insert(
          LivestockReproductionEventsCompanion.insert(
            id: 'rep-sujet'.padRight(36, '0'),
            deviceId: 'serveur',
            updatedAt: DateTime.now(),
            lotId: lotSujet,
            motherRef: 'LAP-2026-0143',
            sireRef: const Value('LAP-2026-0098'),
            saillieDate: Value(
              DateTime.now().subtract(const Duration(days: 20)),
            ),
          ),
        );
    await t.tap(find.byKey(const Key('nav-suiviReproduction')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('lien-sujet-LAP-2026-0143')));
    await t.pumpAndSettle();
    await capturer('animal_details');

    // 6. Contactez l'Éditeur, par le menu du compte.
    ou = 'écran contact-editeur';
    await t.tap(find.byKey(const Key('menu-compte')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-compte-contact')));
    await t.pumpAndSettle();
    await capturer('contact_editeur');

    FlutterError.onError = ancien;
    debugDefaultTargetPlatformOverride = null;
    File('build/audit/alertes_capture.txt')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        alertes.map((a) => '${a['ou']}\t${a['message']}').join('\n'),
      );
  }, skip: !actif);
}
