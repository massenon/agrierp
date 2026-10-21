import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/core/config/parametres_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:agrierp/features/administration/administration_repository.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/elevage/bandes_repository.dart';
import 'package:agrierp/features/elevage/reproducteurs_repository.dart';
import 'package:agrierp/features/elevage/sujets_entrees_repository.dart';
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
import 'package:agrierp/features/ventes/avoirs_repository.dart';
import 'package:agrierp/features/ventes/historique_ventes_repository.dart';
import 'package:agrierp/features/ventes/ventes_devis_repository.dart';
import 'package:agrierp/main.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show Key, Listenable;

/// Coque complète du poste (`SocleAccueil` : barre latérale, barre supérieure, écran) sur une base [db], pour les
/// tests du châssis (tickets H1, H2) et les captures (`capture_ecrans_test.dart`).
///
/// Ticket S-T3 — [changementsReseau] active la synchronisation automatique de la session (sans lui, aucune), avec
/// [engine], [gestes] et [synchroniserALOuverture] comme dans `AgriErpApp`.
SocleAccueil coqueDeTest(
  AppDatabase db, {
  String poste = 'poste-audit',
  Dio? client,
  SyncEngine? engine,
  Stream<List<ConnectivityResult>>? changementsReseau,
  Listenable? gestes,
  bool synchroniserALOuverture = true,
  Key? key,
}) {
  final soins = SoinsRepository(database: db, deviceId: poste);
  final dio = client ?? Dio();
  return SocleAccueil(
    key: key,
    changementsReseau: changementsReseau,
    gestes: gestes,
    synchroniserALOuverture: synchroniserALOuverture,
    database: db,
    engine: engine ?? SyncEngine(database: db, client: dio, deviceId: poste),
    auth: AuthService(client: dio, deviceName: poste),
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
    bandes: BandesRepository(database: db, deviceId: poste),
    reproducteurs: ReproducteursRepository(database: db, deviceId: poste),
    sujetsEntrees: SujetsEntreesRepository(
      database: db,
      fiches: FicheJournaliereRepository(database: db, deviceId: poste),
    ),
    reproduction: SuiviReproductionRepository(database: db, deviceId: poste),
    soinsVaccins: SoinsVaccinsRepository(database: db, soins: soins),
    parametresElevage: ParametresElevageRepository(database: db),
    ventesDevis: VentesDevisRepository(database: db),
    avoirs: AvoirsRepository(database: db, identifiantPoste: poste),
    historiqueVentes: HistoriqueVentesRepository(database: db),
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
