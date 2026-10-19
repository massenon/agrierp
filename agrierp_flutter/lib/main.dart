import 'dart:ui' show AppExitResponse;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/auth/auth_service.dart';
import 'core/auth/garde_ecran.dart';
import 'core/auth/permissions_poste.dart';
import 'core/config/envoi_email_test.dart';
import 'core/config/parametres_poste.dart';
import 'core/config/parametres_smtp.dart';
import 'core/database/app_database.dart';
import 'core/localisation/localisation_poste.dart';
import 'core/export/pdf_recu.dart';
import 'core/sync/gestes_importants.dart';
import 'core/sync/modale_synchronisation.dart';
import 'core/sync/synchronisation_automatique.dart';
import 'core/widgets/acces_rapide.dart';
import 'features/recherche/recherche_globale_champ.dart';
import 'features/recherche/recherche_globale_repository.dart';
import 'core/widgets/modale_agri.dart';
import 'core/sync/sync_engine.dart';
import 'core/theme/agri_theme.dart';
import 'core/widgets/barre_superieure.dart';
import 'core/theme/agri_tokens.dart';
import 'features/demarrage/premier_demarrage_repository.dart';
import 'features/demarrage/premier_demarrage_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/elevage/fiche_journaliere_repository.dart';
import 'features/achats/achats_commandes_screen.dart';
import 'features/achats/achats_repository.dart';
import 'features/achats/fournisseurs_repository.dart';
import 'features/achats/fournisseurs_screen.dart';
import 'features/achats/depenses_repository.dart';
import 'features/achats/saisie_depenses_screen.dart';
import 'features/elevage/dashboard_elevage_repository.dart';
import 'features/elevage/transferts_bandes_screen.dart';
import 'features/elevage/transferts_repository.dart';
import 'features/elevage/dashboard_elevage_screen.dart';
import 'features/elevage/fiche_escargots_screen.dart';
import 'features/elevage/soins_vaccins_repository.dart';
import 'features/elevage/parametres_elevage_repository.dart';
import 'features/elevage/parametres_elevage_screen.dart';
import 'features/elevage/soins_vaccins_screen.dart';
import 'features/elevage/fiche_sujet_screen.dart';
import 'features/elevage/sujets_repository.dart';
import 'features/elevage/suivi_reproduction_repository.dart';
import 'features/elevage/suivi_reproduction_screen.dart';
import 'features/elevage/gestion_elevage_repository.dart';
import 'features/elevage/gestion_elevage_screen.dart';
import 'features/elevage/fiche_pondeuses_screen.dart';
import 'features/elevage/fiche_porcs_screen.dart';
import 'features/elevage/fiche_reproducteurs_screen.dart';
import 'features/elevage/production_oeufs_service.dart';
import 'features/elevage/soins_repository.dart';
import 'features/elevage/fiche_lapins_screen.dart';
import 'features/ventes/caisse_repository.dart';
import 'features/administration/administration_repository.dart';
import 'features/comptabilite/comptabilite_repository.dart';
import 'features/parametres/parametres_generaux_repository.dart';
import 'features/parametres/parametres_generaux_screen.dart';
import 'features/rapports/rapports_exports_screen.dart';
import 'features/rapports/rapports_repository.dart';
import 'features/comptabilite/comptabilite_screen.dart';
import 'features/administration/administration_screen.dart';
import 'features/rh/attestations_repository.dart';
import 'features/rh/personnel_repository.dart';
import 'features/rh/personnel_stages_screen.dart';
import 'features/ventes/facturation_repository.dart';
import 'features/ventes/facturation_screen.dart';
import 'features/parametres/appairage_poste.dart';
import 'features/parametres/reinitialisation_poste.dart';
import 'features/aide/aide_a_propos_screen.dart';
import 'features/contact/contact_editeur_repository.dart';
import 'features/stocks/produits_repository.dart';
import 'features/contact/contact_editeur_screen.dart';
import 'features/notifications/notifications_repository.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/pilotage/tableau_de_bord_repository.dart';
import 'features/pilotage/tableau_de_bord_screen.dart';
import 'features/profil/mon_profil_repository.dart';
import 'features/profil/mon_profil_screen.dart';
import 'features/sync/synchronisation_screen.dart';
import 'features/clients/clients_creances_repository.dart';
import 'features/clients/clients_creances_screen.dart';
import 'features/stocks/catalogue_produits_screen.dart';
import 'features/stocks/gestion_stocks_screen.dart';
import 'features/stocks/stocks_repository.dart';
import 'features/ventes/caisse_screen.dart';
import 'features/ventes/ventes_devis_repository.dart';
import 'features/ventes/ventes_devis_screen.dart';
import 'core/theme/symboles_agri.dart';

/// AgriERP Desktop — Ferme École OLOUWACHEGOUN (Ikpinlè, Bénin).
///
/// Client Windows offline-first. La base locale fait foi ; la synchronisation
/// avec la surface web Laravel intervient ensuite, à la demande.
/// ⚠️ LES RÉGLAGES DU POSTE SONT LUS AVANT TOUTE CONSTRUCTION. L'identifiant
/// du poste et l'adresse du serveur conditionnent le client HTTP et le moteur
/// de synchronisation : les charger après coup obligerait à les recréer, et un
/// envoi parti entre-temps porterait l'ancienne valeur.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ticket U5 (D-U5) : dates d'`intl` en français (données embarquées, aucun
  // accès réseau) — tout `DateFormat` sans locale explicite écrit « octobre ».
  Intl.defaultLocale = 'fr_FR';
  await initializeDateFormatting('fr_FR');

  final db = AppDatabase();
  final parametres = ParametresPoste(database: db);

  runApp(
    AgriErpApp(
      database: db,
      identifiantPoste: await parametres.identifiant(),
      adresseServeur: await parametres.adresseServeur(),
      parametres: parametres,
    ),
  );
}

class AgriErpApp extends StatefulWidget {
  const AgriErpApp({
    super.key,
    required this.database,
    required this.identifiantPoste,
    required this.adresseServeur,
    required this.parametres,
  });

  final AppDatabase database;
  final String identifiantPoste;
  final String adresseServeur;
  final ParametresPoste parametres;

  @override
  State<AgriErpApp> createState() => _AgriErpAppState();
}

class _AgriErpAppState extends State<AgriErpApp> {
  late final AppDatabase _db = widget.database;

  /// ⚠️ UN SEUL CLIENT HTTP, PARTAGÉ. C'est lui qui porte l'en-tête
  /// `Authorization` une fois la session ouverte : un second client pour la
  /// synchronisation partirait sans jeton et se verrait refuser en 401 —
  /// panne d'autant plus déroutante que la connexion, elle, aurait réussi.
  late final Dio _client = Dio(
    BaseOptions(
      // 🔴→✅ TICKET F0.8 — adresse désormais RÉGLABLE depuis l'écran Paramètres
      // du poste, et non plus figée sur la machine du développeur.
      baseUrl: widget.adresseServeur,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  late final SyncEngine _engine = SyncEngine(
    database: _db,
    client: _client,
    // 🔴→✅ TICKET F0.8 — identifiant TIRÉ UNE FOIS puis conservé, propre à ce
    // poste. La constante partagée d'avant rendait deux postes de la ferme
    // indiscernables : aucun conflit n'était explicable.
    deviceId: widget.identifiantPoste,
  );

  /// Ticket F0.98 — premier démarrage d'un poste neuf (adresse du serveur, première synchronisation).
  late final PremierDemarrageRepository _demarrage = PremierDemarrageRepository(
    database: _db,
    parametres: widget.parametres,
    client: _client,
  );

  late final AuthService _auth = AuthService(
    client: _client,
    deviceName: widget.identifiantPoste,
  );

  /// Ticket R-1 — onglet « Réinitialisation » de Paramètres : la route du serveur (même service que le web), par
  /// le client partagé (il porte le jeton), puis la purge immédiate de ce poste par le moteur (mécanisme 15.50)
  /// et un tirage complet. Le droit est celui du rôle de la session ouverte.
  late final ReinitialisationPoste _reinitialisation = ReinitialisationPoste(
    database: _db,
    client: _client,
    engine: _engine,
    role: () => _auth.utilisateur?.role ?? '',
  );

  /// Ticket S-T3 — point unique des gestes importants (vente, fiche journalière, soin) : les dépôts le
  /// signalent, la synchronisation automatique de la session l'écoute.
  final GestesImportants _gestes = GestesImportants();

  late final FicheJournaliereRepository _fiches = FicheJournaliereRepository(
    database: _db,
    deviceId: widget.identifiantPoste,
    gestes: _gestes,
  );

  late final CaisseRepository _caisse = CaisseRepository(
    database: _db,
    deviceId: widget.identifiantPoste,
    gestes: _gestes,
  );

  late final SoinsRepository _soins = SoinsRepository(
    database: _db,
    deviceId: widget.identifiantPoste,
    gestes: _gestes,
  );

  late final ProductionOeufsService _production = ProductionOeufsService(
    database: _db,
  );

  late final ClientsCreancesRepository _clients = ClientsCreancesRepository(
    database: _db,
    deviceId: widget.identifiantPoste,
  );

  /// ⚠️ Le même client HTTP : il porte le jeton de la session, que le serveur
  /// lit pour décider si ce rôle peut exporter une fiche sujet.
  late final SujetsRepository _sujets = SujetsRepository(
    database: _db,
    client: ClientSujets(_client),
  );

  /// ⚠️ Le même client HTTP : il porte le jeton de la session — c'est lui qui
  /// dit au serveur QUI édite l'attestation, et donc ce que son rôle permet.
  late final AttestationsRepository _attestations = AttestationsRepository(
    database: _db,
    client: ClientAttestations(_client),
  );

  late final ProduitsRepository _produits = ProduitsRepository(database: _db);

  /// ⚠️ Le même client HTTP : il porte le jeton de la session, que le serveur
  /// lit pour savoir QUI écrit à l'éditeur.
  late final ContactEditeurRepository _contact = ContactEditeurRepository(
    client: ClientContact(_client),
  );

  /// ⚠️ Le MÊME client HTTP que partout : il porte le jeton de la session.
  late final NotificationsRepository _notifications = NotificationsRepository(
    database: _db,
    serveur: ServeurNotifications(_client),
  );

  late final StocksRepository _stocks = StocksRepository(
    database: _db,
    deviceId: widget.identifiantPoste,
  );

  late final VentesDevisRepository _ventesDevis = VentesDevisRepository(
    database: _db,
  );

  late final ParametresElevageRepository _parametresElevage =
      ParametresElevageRepository(database: _db);

  late final SoinsVaccinsRepository _soinsVaccins = SoinsVaccinsRepository(
    database: _db,
    soins: _soins,
  );

  late final SuiviReproductionRepository _reproduction =
      SuiviReproductionRepository(
        database: _db,
        deviceId: widget.identifiantPoste,
      );

  late final DashboardElevageRepository _dashboardElevage =
      DashboardElevageRepository(database: _db, soins: _soins);

  late final TransfertsRepository _transferts = TransfertsRepository(
    database: _db,
    deviceId: widget.identifiantPoste,
  );

  late final TableauDeBordRepository _tableauDeBord = TableauDeBordRepository(
    database: _db,
  );

  late final ComptabiliteRepository _comptabilite = ComptabiliteRepository(
    database: _db,
  );

  late final ParametresGenerauxRepository _parametresGeneraux =
      ParametresGenerauxRepository(database: _db);

  late final RapportsRepository _rapports = RapportsRepository(database: _db);

  late final AdministrationRepository _administration =
      AdministrationRepository(database: _db);

  late final PersonnelRepository _personnel = PersonnelRepository(
    database: _db,
    identifiantPoste: widget.identifiantPoste,
  );

  late final FacturationRepository _facturation = FacturationRepository(
    database: _db,
  );

  late final FournisseursRepository _fournisseurs = FournisseursRepository(
    database: _db,
    deviceId: widget.identifiantPoste,
  );

  late final AchatsRepository _achats = AchatsRepository(
    database: _db,
    identifiantPoste: widget.identifiantPoste,
  );

  late final DepensesRepository _depenses = DepensesRepository(
    database: _db,
    deviceId: widget.identifiantPoste,
  );

  /// `null` tant que la reprise de session n'a pas répondu : afficher l'écran
  /// de connexion avant de savoir ferait clignoter le formulaire devant un
  /// utilisateur déjà authentifié.
  bool? _sessionOuverte;

  /// Ticket F0.98 — vrai si la session s'ouvre sur un poste neuf : l'écran de premier démarrage passe
  /// avant l'accueil, jusqu'à « Continuer » ou « Plus tard ».
  bool _premierDemarrage = false;

  /// Ticket S-T3 — l'accueil synchronise à son ouverture, sauf juste après l'écran de premier démarrage, qui
  /// vient de proposer (et le plus souvent de faire) cette synchronisation.
  bool _synchroniserALOuverture = true;

  @override
  void initState() {
    super.initState();
    _reprendre();
  }

  Future<void> _reprendre() async {
    final ouverte = await _auth.reprendreSession();
    final neuf = ouverte && await _demarrage.posteNeuf();
    if (mounted) {
      setState(() {
        _sessionOuverte = ouverte;
        _premierDemarrage = neuf;
        _synchroniserALOuverture = true;
      });
    }
  }

  Future<void> _connecte() async {
    final neuf = await _demarrage.posteNeuf();
    if (mounted) {
      setState(() {
        _sessionOuverte = true;
        _premierDemarrage = neuf;
        _synchroniserALOuverture = true;
      });
    }
  }

  @override
  void dispose() {
    _gestes.dispose();
    _db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgriERP — Ferme École OLOUWACHEGOUN',
      debugShowCheckedModeBanner: false,
      theme: AgriTheme.light,
      // Ticket U5 (D-U5) : composants Material en français (sélecteurs de date,
      // « ANNULER » / « OK », infobulles). Voir `LocalisationPoste`.
      locale: LocalisationPoste.locale,
      supportedLocales: LocalisationPoste.locales,
      localizationsDelegates: LocalisationPoste.delegues,
      home: switch (_sessionOuverte) {
        null => const Scaffold(
          backgroundColor: AgriColors.surfaceBg,
          body: Center(child: CircularProgressIndicator()),
        ),
        false => LoginScreen(
          auth: _auth,
          demarrage: _demarrage,
          onConnecte: _connecte,
        ),
        true when _premierDemarrage => PremierDemarrageScreen(
          depot: _demarrage,
          engine: _engine,
          utilisateur: _auth.utilisateur?.nom ?? '—',
          onTermine: () => setState(() {
            _premierDemarrage = false;
            _synchroniserALOuverture = false;
          }),
        ),
        true => SocleAccueil(
          database: _db,
          engine: _engine,
          auth: _auth,
          reinitialisation: _reinitialisation,
          fiches: _fiches,
          caisse: _caisse,
          soins: _soins,
          production: _production,
          depenses: _depenses,
          achats: _achats,
          fournisseurs: _fournisseurs,
          facturation: _facturation,
          personnel: _personnel,
          administration: _administration,
          comptabilite: _comptabilite,
          parametresGeneraux: _parametresGeneraux,
          rapports: _rapports,
          tableauDeBord: _tableauDeBord,
          dashboardElevage: _dashboardElevage,
          transferts: _transferts,
          reproduction: _reproduction,
          soinsVaccins: _soinsVaccins,
          parametresElevage: _parametresElevage,
          ventesDevis: _ventesDevis,
          stocks: _stocks,
          clients: _clients,
          notifications: _notifications,
          contact: _contact,
          produits: _produits,
          attestations: _attestations,
          sujets: _sujets,
          parametres: widget.parametres,
          identifiantPoste: widget.identifiantPoste,
          onDeconnecte: () => setState(() => _sessionOuverte = false),
          changementsReseau: Connectivity().onConnectivityChanged,
          gestes: _gestes,
          synchroniserALOuverture: _synchroniserALOuverture,
        ),
      },
    );
  }
}

/// Socle de l'application : barre latérale forestière + zone de contenu,
/// disposition reprise de `prototype_html/assets/js/sidebar.js`.
///
/// ⚠️ ÉTAT DU CHANTIER — c'est un SOCLE, pas le tableau de bord. Il n'affiche
/// que ce qui est réellement construit (base locale, moteur de
/// synchronisation) : aucune carte d'indicateur remplie de chiffres
/// décoratifs en attendant les vrais écrans.
class SocleAccueil extends StatefulWidget {
  const SocleAccueil({
    super.key,
    required this.database,
    required this.engine,
    required this.auth,
    required this.fiches,
    required this.caisse,
    required this.soins,
    required this.production,
    required this.depenses,
    required this.achats,
    required this.fournisseurs,
    required this.facturation,
    required this.personnel,
    required this.administration,
    required this.comptabilite,
    required this.parametresGeneraux,
    required this.rapports,
    required this.tableauDeBord,
    required this.dashboardElevage,
    required this.transferts,
    required this.reproduction,
    required this.soinsVaccins,
    required this.parametresElevage,
    required this.ventesDevis,
    required this.stocks,
    required this.clients,
    required this.notifications,
    required this.contact,
    this.produits,
    required this.attestations,
    required this.sujets,
    required this.parametres,
    required this.identifiantPoste,
    this.reinitialisation,
    this.onDeconnecte,
    this.changementsReseau,
    this.gestes,
    this.synchroniserALOuverture = true,
  });

  /// Ticket H1 — appelé après « Déconnexion » : l'application revient à l'écran de connexion.
  final VoidCallback? onDeconnecte;

  /// Ticket R-1 — onglet « Réinitialisation » de Paramètres ; `null` (tests du châssis) : l'onglet le dit.
  final ReinitialisationPoste? reinitialisation;

  /// Ticket H13 — changements de liaison réseau ; `null` = pas de synchronisation automatique (tests du
  /// châssis, qui n'ont pas de plateforme native pour la connectivité).
  final Stream<List<ConnectivityResult>>? changementsReseau;

  /// Ticket S-T3 — gestes importants signalés par les dépôts (vente, fiche, soin) : chacun déclenche la
  /// synchronisation automatique, après son délai d'agrégation.
  final Listenable? gestes;

  /// Ticket S-T3 — synchronisation automatique dès l'ouverture de l'accueil (session ouverte). Faux juste après
  /// l'écran de premier démarrage, qui synchronise déjà.
  final bool synchroniserALOuverture;

  final AppDatabase database;
  final SyncEngine engine;
  final AuthService auth;
  final FicheJournaliereRepository fiches;
  final CaisseRepository caisse;
  final SoinsRepository soins;
  final ProductionOeufsService production;
  final DepensesRepository depenses;
  final AchatsRepository achats;
  final FournisseursRepository fournisseurs;
  final FacturationRepository facturation;
  final PersonnelRepository personnel;
  final AdministrationRepository administration;
  final ComptabiliteRepository comptabilite;
  final ParametresGenerauxRepository parametresGeneraux;
  final RapportsRepository rapports;
  final TableauDeBordRepository tableauDeBord;
  final DashboardElevageRepository dashboardElevage;
  final TransfertsRepository transferts;
  final SuiviReproductionRepository reproduction;
  final SoinsVaccinsRepository soinsVaccins;
  final ParametresElevageRepository parametresElevage;
  final VentesDevisRepository ventesDevis;
  final StocksRepository stocks;
  final ClientsCreancesRepository clients;
  final NotificationsRepository notifications;
  final ContactEditeurRepository contact;

  /// Création / modification de produit, en ligne (ticket F0.67). `null` : le
  /// catalogue reste en consultation.
  final ProduitsRepository? produits;
  final AttestationsRepository attestations;
  final SujetsRepository sujets;
  final ParametresPoste parametres;
  final String identifiantPoste;

  @override
  State<SocleAccueil> createState() => _SocleAccueilState();
}

class _SocleAccueilState extends State<SocleAccueil> {
  /// Écran affiché dans la zone de contenu. La barre latérale de la maquette
  /// en compte bien davantage : seuls ceux réellement construits y figurent,
  /// plutôt que des entrées mortes qui promettraient des écrans inexistants.
  late EcranPoste _ecran;

  /// La maquette porte une bascule de menu dans sa barre supérieure
  /// (`menu` / `menu_open`) : elle replie la barre latérale.
  bool _menuOuvert = true;

  /// Incrémenté à chaque synchronisation. ⚠️ Ne sert de CLÉ qu'au Centre de
  /// Notifications : le mettre sur tous les écrans effacerait une saisie en
  /// cours à chaque tirage.
  int _versionTirage = 0;

  /// Sujet dont la fiche est ouverte, et l'écran d'où l'on est venu (le bouton
  /// « Retour » y revient : le poste n'a pas de bouton « précédent » de
  /// navigateur).
  String? _sujetId;
  EcranPoste _avantSujet = EcranPoste.suiviReproduction;

  /// Ticket U10 — arrivée au Catalogue Produits DEPUIS Gestion des Stocks : onglet (« Seuils d'Alerte ») ou produit
  /// à modifier, lus une fois par l'écran à sa création ([_versionCatalogue] le recrée), puis oubliés — une arrivée
  /// ordinaire par la barre latérale ouvre le catalogue comme avant.
  String? _catalogueOnglet;
  String? _catalogueProduit;
  int _versionCatalogue = 0;

  void _ouvrirCatalogue({String? onglet, String? produit}) {
    setState(() {
      _catalogueOnglet = onglet;
      _catalogueProduit = produit;
      _versionCatalogue++;
      _ecran = EcranPoste.catalogueProduits;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _catalogueOnglet = null;
      _catalogueProduit = null;
    });
  }

  /// Brouillon de « Contactez l'Éditeur », possédé ICI pour survivre aux
  /// changements d'écran : un texte rédigé hors ligne ne doit pas disparaître
  /// parce qu'on est allé vérifier une information ailleurs.
  final _brouillonContact = BrouillonContact();

  String get _role => widget.auth.utilisateur?.role ?? '';

  late final _recherche = RechercheGlobaleRepository(database: widget.database);

  /// Ticket CFG-2 — réglages SMTP de ce poste (mot de passe au coffre du système, jamais en base) et e-mail de test.
  late final _smtp = ParametresSmtp(database: widget.database);
  late final _envoiEmail = EnvoiEmailTest(parametres: _smtp);

  /// Ticket CFG-2 — onglet « Appairage » : réglages du poste, session, état du jeton (S-T1 : synchronisation
  /// automatique suspendue sur 401 / 403) et réappairage (= la « Déconnexion » du menu du compte).
  AppairagePoste get _appairage => AppairagePoste(
    parametres: widget.parametres,
    identifiant: widget.identifiantPoste,
    auth: widget.auth,
    sessionSuspendue: () => _automatique?.suspendue ?? false,
    reappairer: widget.onDeconnecte == null ? null : _deconnecter,
  );

  /// Ticket CFG-2 — hub Paramètres, ouvert sur [ongletInitial] (« Appairage » depuis « Paramètres du poste »).
  Widget _parametresGeneraux({String? ongletInitial}) => ParametresGenerauxScreen(
    // Une clé par point d'entrée : passer de « Paramètres du poste » à « Paramètres » rouvre le bon onglet.
    key: ValueKey('parametres-${ongletInitial ?? 'hub'}'),
    depot: widget.parametresGeneraux,
    smtp: _smtp,
    envoiEmail: _envoiEmail,
    appairage: _appairage,
    reinitialisation: widget.reinitialisation,
    ongletInitial: ongletInitial,
  );

  @override
  void initState() {
    super.initState();

    // ⚠️ ON N'OUVRE PAS SUR UN ÉCRAN INTERDIT. Démarrer sur la fiche d'élevage
    // quel que soit le rôle accueillerait le caissier par un « accès refusé »
    // plein écran — il croirait l'application cassée.
    final accessibles = PermissionsPoste.ecransDe(_role);
    _ecran = accessibles.isEmpty
        ? EcranPoste.synchronisation
        : accessibles.first;

    _demarrerSynchronisationAutomatique();
  }

  /// Ticket H13 (B2) — synchronisation automatique de la session : retour du réseau, intervalle réglé dans
  /// Paramètres du poste, réessais après un échec réseau. Arrêtée à la déconnexion (le socle est démonté).
  /// S-T3 : aussi à l'ouverture de la session et après un geste important. S-T1 : un 401 / 403 la suspend
  /// jusqu'à la fin de CETTE session — la reconnexion monte un socle neuf, donc une instance neuve.
  SynchronisationAutomatique? _automatique;

  /// Ticket H13 — la fermeture par le système (Alt+F4) envoie aussi ce qui attend.
  AppLifecycleListener? _cycleDeVie;

  Future<void> _demarrerSynchronisationAutomatique() async {
    final reseau = widget.changementsReseau;
    if (reseau == null) return;
    final intervalle = await widget.parametres.intervalleSynchronisation();
    if (!mounted) return;
    _automatique = SynchronisationAutomatique(
      synchroniser: widget.engine.synchroniser,
      changementsReseau: reseau,
      intervalle: intervalle,
      // Ticket S-T6 — « Demander la synchronisation des postes » du web, lue toutes les 30 s.
      demandeDuServeur: widget.engine.demandeDuServeur,
      // Le tirage a pu apporter des notifications et vider la file : la barre et le Centre se relisent.
      onTermine: () {
        if (mounted) setState(() => _versionTirage++);
      },
      gestes: widget.gestes,
    )..demarrer(aussitot: widget.synchroniserALOuverture);
    _cycleDeVie = AppLifecycleListener(
      onExitRequested: () async {
        if ((await _restantsAEnvoyer()) > 0) await _automatique?.avantFermeture();
        return AppExitResponse.exit;
      },
    );
  }

  Future<int> _restantsAEnvoyer() async {
    final c = await widget.database.compteursSynchronisation();
    return c.aEnvoyer + c.refuses;
  }

  /// Ticket H13 — synchronisation de fermeture (bouton ✕) : rend ce qui reste à envoyer ensuite.
  Future<int> _avantFermeture() async {
    await _automatique?.avantFermeture();
    if (mounted) setState(() => _versionTirage++);
    return _restantsAEnvoyer();
  }

  /// Titre de la barre supérieure (groupe vide : `BarreSuperieure` affiche alors le seul titre).
  (String, String) get _situation => ('', SocleAccueilTitres.titre(_ecran));

  @override
  void dispose() {
    _automatique?.arreter();
    _cycleDeVie?.dispose();
    _brouillonContact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (groupe, ecranCourant) = _situation;

    return Scaffold(
      body: Row(
        children: [
          // ⚠️ La bascule de la barre supérieure replie la barre latérale,
          // comme `menu` / `menu_open` dans la maquette.
          if (_menuOuvert)
            _BarreLaterale(
              auth: widget.auth,
              actif: _ecran,
              ecrans: PermissionsPoste.ecransDe(_role),
              onNaviguer: (e) => setState(() => _ecran = e),
            ),
          Expanded(
            child: Column(
              children: [
                // ⚠️ LE COMPTEUR EST LU EN DIRECT : figer sa valeur au
                // montage laisserait la pastille annoncer « Sync » alors
                // qu'une journée vient d'être saisie.
                FutureBuilder<(({int aEnvoyer, int refuses}), DonneesNotifications)>(
                  future: _etatDeLaBarre(),
                  builder: (context, instantane) => BarreSuperieure(
                    groupe: groupe,
                    ecran: ecranCourant,
                    enAttente: (instantane.data?.$1.aEnvoyer ?? 0) + (instantane.data?.$1.refuses ?? 0),
                    refuses: instantane.data?.$1.refuses ?? 0,
                    onSynchroniser: _ouvrirSynchronisation,
                    avantFermeture: widget.changementsReseau == null ? null : _avantFermeture,
                    nonLues: instantane.data?.$2.nonLues,
                    recentes: [
                      for (final n in (instantane.data?.$2.lignes ?? []).take(
                        4,
                      ))
                        ApercuNotification(
                          message: n.message,
                          // Ticket U13 — « il y a … » comme la cloche du web (`diffForHumans`), à l'heure du Bénin.
                          dateTexte: n.dateRelative(instantane.data!.$2.maintenant),
                          lue: n.lue,
                          critique: n.gravite == 'critique',
                        ),
                    ],
                    onAide:
                        PermissionsPoste.autorise(
                          _role,
                          EcranPoste.aideEtAPropos,
                        )
                        ? () =>
                              setState(() => _ecran = EcranPoste.aideEtAPropos)
                        : null,
                    onContact:
                        PermissionsPoste.autorise(
                          _role,
                          EcranPoste.contactEditeur,
                        )
                        ? () =>
                              setState(() => _ecran = EcranPoste.contactEditeur)
                        : null,
                    onNotifications: () =>
                        setState(() => _ecran = EcranPoste.notifications),
                    menuOuvert: _menuOuvert,
                    nomUtilisateur: widget.auth.utilisateur?.nom,
                    onMonProfil:
                        PermissionsPoste.autorise(_role, EcranPoste.monProfil)
                        ? () => setState(() => _ecran = EcranPoste.monProfil)
                        : null,
                    onBasculerMenu: () =>
                        setState(() => _menuOuvert = !_menuOuvert),
                    // Ticket H1 — comme au web, « Paramètres » mène à Paramètres Général : l'écran se garde
                    // lui-même (`GardeEcran`) si le rôle n'y a pas droit, comme la route web refuse.
                    onParametres: () => setState(() => _ecran = EcranPoste.parametresGeneraux),
                    // Ticket H1b — recherche globale sur la base locale, avec les droits du web.
                    recherche: RechercheGlobaleChamp(
                      depot: _recherche,
                      role: _role,
                      onNaviguer: (e) => setState(() => _ecran = e),
                    ),
                    onDeconnexion: widget.onDeconnecte == null ? null : _deconnecter,
                  ),
                ),
                // Ticket H1 — bouton flottant « Accès Rapide » au-dessus du contenu, comme `app.blade.php:219`.
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: _contenu()),
                      BoutonAccesRapide(onNaviguer: (e) => setState(() => _ecran = e)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Ticket H1 — RUBAN DE LA BARRE REPLIÉE (`app.blade.php:149-160`) : à droite, 64 px, fond
          // `rgba(5,46,22,0.95)`, six raccourcis puis « Réafficher le menu ».
          if (!_menuOuvert) _RubanReplie(
            onNaviguer: (e) => setState(() => _ecran = e),
            onReafficher: () => setState(() => _menuOuvert = true),
          ),
        ],
      ),
    );
  }

  /// Ticket H1 — « Déconnexion » du menu du compte. Les saisies en attente RESTENT sur le poste (elles partiront
  /// à la prochaine session) : la session se ferme, la base locale ne bouge pas.
  Future<void> _deconnecter() async {
    await widget.auth.deconnecter();
    widget.onDeconnecte?.call();
  }

  /// Ce que lit la barre supérieure : la file d'attente (à envoyer, refusés) et les notifications.
  Future<(({int aEnvoyer, int refuses}), DonneesNotifications)> _etatDeLaBarre() async => (
    await widget.database.compteursSynchronisation(),
    await widget.notifications.charger(),
  );

  /// Ticket H2 — bouton « Synchroniser » de la barre supérieure : ouvre la modale, ouverte à TOUS les rôles
  /// (un caissier doit pouvoir pousser ses ventes, comme sur l'écran Synchronisation).
  Future<void> _ouvrirSynchronisation() => afficherModale<void>(
    context: context,
    constructeur: (_) => ModaleSynchronisation(
      engine: widget.engine,
      database: widget.database,
      onVoirDetail: PermissionsPoste.autorise(_role, EcranPoste.synchronisation)
          ? () => setState(() => _ecran = EcranPoste.synchronisation)
          : null,
      // Le tirage a pu apporter des notifications et vider la file : la barre et le Centre se relisent.
      onTermine: () {
        if (mounted) setState(() => _versionTirage++);
      },
    ),
  );

  /// ⚠️ SECOND NIVEAU : la garde est posée sur l'écran, pas seulement sur
  /// l'entrée de menu. Masquer un menu n'est pas une autorisation.
  Widget _contenu() {
    return GardeEcran(
      role: _role,
      ecran: _ecran,
      enfant: switch (_ecran) {
        // ⚠️ LES DEUX BOUTONS DE L'EN-TETE MENENT AUX ECRANS REELS
        // de la maquette : « Enregistrer une Vente » vers la caisse,
        // « Élevage » vers Gestion Élevage.
        EcranPoste.tableauDeBord => TableauDeBordScreen(
          depot: widget.tableauDeBord,
          nomUtilisateur:
              widget.auth.utilisateur?.nom ?? 'Manager Olouwachegoun',
          onEnregistrerVente: () => setState(() => _ecran = EcranPoste.caisse),
          onElevage: () => setState(() => _ecran = EcranPoste.gestionElevage),
          onOuvrir: (e) => setState(() => _ecran = e),
        ),
        EcranPoste.monProfil => MonProfilScreen(
          depot: MonProfilRepository(database: widget.database),
          session: widget.auth.utilisateur,
          changer: widget.auth.utilisateur == null
              ? null
              : widget.auth.changerMotDePasse,
        ),
        EcranPoste.aideEtAPropos => AideAProposScreen(
          onOuvrir: (e) => setState(() => _ecran = e),
          peutOuvrir: (e) => PermissionsPoste.autorise(_role, e),
          onContact: () => setState(() => _ecran = EcranPoste.contactEditeur),
        ),
        EcranPoste.contactEditeur => ContactEditeurScreen(
          depot: widget.contact,
          brouillon: _brouillonContact,
          onAide: () => setState(() => _ecran = EcranPoste.aideEtAPropos),
        ),
        EcranPoste.notifications => NotificationsScreen(
          key: ValueKey('notifications-$_versionTirage'),
          depot: widget.notifications,
          onOuvrir: (e) => setState(() => _ecran = e),
          // La cloche relit la base à chaque reconstruction : on la provoque.
          onModifie: () => setState(() {}),
        ),
        EcranPoste.transfertsBandes => TransfertsBandesScreen(
          depot: widget.transferts,
        ),
        EcranPoste.dashboardElevage => DashboardElevageScreen(
          depot: widget.dashboardElevage,
          onOuvrirSoins: () =>
              setState(() => _ecran = EcranPoste.soinsEtVaccins),
        ),
        EcranPoste.suiviReproduction => SuiviReproductionScreen(
          depot: widget.reproduction,
          onOuvrirSujet: (id) => setState(() {
            _sujetId = id;
            _avantSujet = EcranPoste.suiviReproduction;
            _ecran = EcranPoste.ficheSujet;
          }),
          // Ticket H7 — « Saisir le Couvoir du Jour → » : les deux `route()` du Blade.
          onSaisirCouvoir: (espece) => setState(
            () => _ecran = espece == 'aviculture'
                ? EcranPoste.ficheReproducteurs
                : EcranPoste.ficheEscargots,
          ),
        ),
        EcranPoste.ficheSujet => FicheSujetScreen(
          // ⚠️ Une clé PAR SUJET : sans elle, passer d'une fiche à une autre
          // réutiliserait l'état de la première.
          key: ValueKey('sujet-$_sujetId'),
          depot: widget.sujets,
          sujetId: _sujetId ?? '',
          enregistrer: (pdf) => LivraisonPdf.enregistrer(pdf),
          imprimer: LivraisonPdf.imprimer,
          onRetour: () => setState(() => _ecran = _avantSujet),
          onOuvrirReproduction: () =>
              setState(() => _ecran = EcranPoste.suiviReproduction),
        ),
        EcranPoste.soinsEtVaccins => SoinsVaccinsScreen(
          depot: widget.soinsVaccins,
          soins: widget.soins,
        ),
        EcranPoste.parametresElevage => ParametresElevageScreen(
          depot: widget.parametresElevage,
          // Ticket H9b — modifier les barèmes = droit `manage-elevage` du web (sinon l'envoi serait refusé).
          peutModifier: PermissionsPoste.peut(_role, 'manage-elevage'),
        ),
        EcranPoste.clientsEtCreances => ClientsCreancesScreen(
          depot: widget.clients,
          imprimer: EditeursRapports.imprimer,
        ),
        // Ticket U10 — « Exporter », « Ajouter Stock » (`manage-stocks`), « Configurer les Seuils d'Alerte » et
        // l'icône Modifier, comme au web.
        EcranPoste.gestionStocks => GestionStocksScreen(
          depot: widget.stocks,
          imprimer: EditeursRapports.imprimer,
          peutGerer: PermissionsPoste.peut(_role, 'manage-stocks'),
          onConfigurerSeuils: () => _ouvrirCatalogue(onglet: "Seuils d'Alerte"),
          onModifierProduit: (id) => _ouvrirCatalogue(produit: id),
        ),
        // ⚠️ MEME DEPOT que Gestion Stocks : deux lecteurs paralleles
        // des memes tables finiraient par diverger.
        EcranPoste.catalogueProduits => CatalogueProduitsScreen(
          key: ValueKey('catalogue-$_versionCatalogue'),
          depot: widget.stocks,
          produits: widget.produits,
          ongletInitial: _catalogueOnglet,
          produitAModifier: _catalogueProduit,
        ),
        EcranPoste.ventesEtDevis => VentesDevisScreen(
          depot: widget.ventesDevis,
          caisse: widget.caisse,
        ),
        EcranPoste.caisse => CaisseScreen(depot: widget.caisse),
        EcranPoste.synchronisation => SynchronisationScreen(
          database: widget.database,
          engine: widget.engine,
        ),
        // 🔁 Ticket CFG-2 — l'écran isolé « Paramètres du poste » est devenu l'onglet « Appairage » du hub.
        EcranPoste.parametres => _parametresGeneraux(
          ongletInitial: ParametresGenerauxScreen.ongletAppairage,
        ),
        // Ticket U12a — « Exporter PDF », lien « Transferts entre Bandes » et « Commander Stock » du Blade.
        EcranPoste.ficheElevage => FicheLapinsScreen(
          depot: widget.fiches,
          soins: widget.soins,
          imprimer: EditeursRapports.imprimer,
          onOuvrirTransferts: () =>
              setState(() => _ecran = EcranPoste.transfertsBandes),
          onCommanderStock: () =>
              setState(() => _ecran = EcranPoste.achatsEtCommandes),
        ),
        EcranPoste.gestionElevage => GestionElevageScreen(
          onOuvrir: (e) => setState(() => _ecran = e),
          depot: GestionElevageRepository(database: widget.database),
        ),
        EcranPoste.comptabilite => ComptabiliteScreen(
          depot: widget.comptabilite,
          imprimer: EditeursRapports.imprimer,
        ),
        EcranPoste.parametresGeneraux => _parametresGeneraux(),
        EcranPoste.rapportsEtExports => RapportsExportsScreen(
          depot: widget.rapports,
          // Ticket U12b — `@can('export-rapports')` du hub web (seeder : admin et comptable).
          peutExporter: PermissionsPoste.peut(_role, 'export-rapports'),
          imprimer: EditeursRapports.imprimer,
          enregistrer: EditeursRapports.enregistrer,
        ),
        EcranPoste.administrationEtDocument => AdministrationScreen(
          depot: widget.administration,
          imprimer: EditeursRapports.imprimer,
        ),
        EcranPoste.personnelEtStages => PersonnelStagesScreen(
          depot: widget.personnel,
          attestations: widget.attestations,
        ),
        EcranPoste.facturation => FacturationScreen(
          depot: widget.facturation,
          onOuvrirCaisse: () => setState(() => _ecran = EcranPoste.caisse),
        ),
        EcranPoste.fournisseurs => FournisseursScreen(
          depot: widget.fournisseurs,
        ),
        EcranPoste.achatsEtCommandes => AchatsCommandesScreen(
          depot: widget.achats,
          depotFournisseurs: widget.fournisseurs,
          imprimer: EditeursRapports.imprimer,
        ),
        EcranPoste.saisieDepenses => SaisieDepensesScreen(
          depot: widget.depenses,
        ),
        // Ticket U12a — « Exporter PDF », liens du Blade (transferts, retour à Gestion Élevage, commande de stock).
        EcranPoste.ficheEscargots => FicheEscargotsScreen(
          depot: widget.fiches,
          soins: widget.soins,
          imprimer: EditeursRapports.imprimer,
          onOuvrirTransferts: () =>
              setState(() => _ecran = EcranPoste.transfertsBandes),
          onRetourGestion: () =>
              setState(() => _ecran = EcranPoste.gestionElevage),
        ),
        EcranPoste.ficheReproducteurs => FicheReproducteursScreen(
          depot: widget.fiches,
          soins: widget.soins,
          imprimer: EditeursRapports.imprimer,
          onOuvrirTransferts: () =>
              setState(() => _ecran = EcranPoste.transfertsBandes),
        ),
        EcranPoste.fichePorcs => FichePorcsScreen(
          depot: widget.fiches,
          soins: widget.soins,
          imprimer: EditeursRapports.imprimer,
          onOuvrirTransferts: () =>
              setState(() => _ecran = EcranPoste.transfertsBandes),
          onCommanderStock: () =>
              setState(() => _ecran = EcranPoste.achatsEtCommandes),
        ),
        // Ticket U11 — « Exporter PDF » et le lien « Transferts entre Bandes » du Blade.
        EcranPoste.fichePondeuses => FichePondeusesScreen(
          depot: widget.fiches,
          soins: widget.soins,
          production: widget.production,
          imprimer: EditeursRapports.imprimer,
          onOuvrirTransferts: () =>
              setState(() => _ecran = EcranPoste.transfertsBandes),
        ),
      },
    );
  }
}

/// Conservé pour mémoire : l'écran d'état du socle, remplacé dans la zone de
/// contenu par la première fiche réelle. Il reste consultable tant qu'aucune
/// navigation n'existe entre écrans.
class EtatDuSocle extends StatelessWidget {
  const EtatDuSocle({super.key, required this.database});

  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AgriSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AgriERP Desktop',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  const Text(
                    'Ferme École OLOUWACHEGOUN — Ikpinlè, Bénin',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.outline,
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AgriSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Socle en place',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AgriColors.brandForest,
                            ),
                          ),
                          const SizedBox(height: AgriSpacing.sm),
                          const Text(
                            'Base locale SQLite (UUID, device_id, sync_status) '
                            'et moteur de synchronisation vers /api/sync/pull '
                            'et /api/sync/push.',
                            style: TextStyle(
                              fontSize: AgriTypography.xs,
                              color: AgriColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: AgriSpacing.sm),
                          FutureBuilder<int>(
                            future: database.pendingCount(),
                            builder: (context, snapshot) => Text(
                              "File d'attente locale : "
                              '${snapshot.data ?? 0} enregistrement(s).',
                              style: const TextStyle(
                                fontSize: AgriTypography.xs,
                                color: AgriColors.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarreLaterale extends StatelessWidget {
  const _BarreLaterale({
    required this.auth,
    required this.actif,
    required this.ecrans,
    required this.onNaviguer,
  });

  final AuthService auth;
  final EcranPoste actif;
  final List<EcranPoste> ecrans;
  final void Function(EcranPoste) onNaviguer;

  /// Arborescence **complète** de la barre latérale (`layouts/app.blade.php`, et avant lui
  /// `assets/js/sidebar.js` de la maquette) : chaque groupe, chaque entrée, chaque icône, dans l'ordre exact.
  ///
  /// ⚠️ Ticket H1 — ce qui est AFFICHÉ suit le web : seules les entrées autorisées au rôle, et un groupe sans
  /// entrée autorisée est masqué (`@hasanyrole`). Les entrées « estompées » (écran non embarqué) n'ont plus lieu
  /// d'être : tous les écrans de la barre web sont embarqués au poste.
  ///
  /// ⚠️ Le troisième champ est l'écran atteint, `null` si le poste ne l'embarque pas (l'entrée n'est alors pas
  /// affichée).
  static const arborescence = <(String, List<(IconData, String, EcranPoste?)>)>[
    (
      'PILOTAGE',
      [(SymbolesAgri.dashboard, 'Tableau de Bord', EcranPoste.tableauDeBord)],
    ),
    (
      'PRODUCTION ÉLEVAGE & SOINS',
      [
        // ⚠️ « Gestion Élevage » mène aux fiches, exactement comme dans la
        // maquette : celle-ci ne liste AUCUNE fiche dans sa barre, elles
        // s'ouvrent depuis cet écran.
        (SymbolesAgri.pets, 'Gestion Élevage', EcranPoste.gestionElevage),
        (SymbolesAgri.dashboard, 'Dashboard Élevage', EcranPoste.dashboardElevage),
        (SymbolesAgri.favorite, 'Suivi Reproduction', EcranPoste.suiviReproduction),
        (SymbolesAgri.vaccines, 'Soins et vaccins', EcranPoste.soinsEtVaccins),
        (SymbolesAgri.tune, 'Paramètres Élevage', EcranPoste.parametresElevage),
      ],
    ),
    (
      'VENTES FERME',
      [
        (SymbolesAgri.point_of_sale, 'Ventes & Devis', EcranPoste.ventesEtDevis),
        (SymbolesAgri.payments, 'Clients et Créances', EcranPoste.clientsEtCreances),
      ],
    ),
    (
      'ACHATS & CHARGES',
      [
        (
          SymbolesAgri.local_shipping,
          'Achats & Commandes',
          EcranPoste.achatsEtCommandes,
        ),
        (SymbolesAgri.contact_page, 'Fournisseurs', EcranPoste.fournisseurs),
        (SymbolesAgri.receipt, 'Saisie Dépenses', EcranPoste.saisieDepenses),
      ],
    ),
    (
      'STOCKS & PRODUITS',
      [
        (SymbolesAgri.inventory_2, 'Gestion Stocks', EcranPoste.gestionStocks),
        (SymbolesAgri.category, 'Catalogue Produits', EcranPoste.catalogueProduits),
      ],
    ),
    (
      'FACTURATION',
      [(SymbolesAgri.receipt_long, 'Facturation & MeCeF', EcranPoste.facturation)],
    ),
    (
      'RESSOURCES HUMAINES',
      [(SymbolesAgri.badge, 'Personnel & Stages', EcranPoste.personnelEtStages)],
    ),
    (
      'ADMINISTRATION',
      [
        (
          SymbolesAgri.folder_shared,
          'Administration & Document',
          EcranPoste.administrationEtDocument,
        ),
      ],
    ),
    (
      'COMPTABILITÉ & ADMIN',
      [
        (SymbolesAgri.account_balance, 'Comptabilité', EcranPoste.comptabilite),
        (SymbolesAgri.settings, 'Paramètres Général', EcranPoste.parametresGeneraux),
      ],
    ),
    (
      'EDITIONS',
      [
        (
          SymbolesAgri.picture_as_pdf,
          'Rapports & Exports',
          EcranPoste.rapportsEtExports,
        ),
      ],
    ),
    // ⚠️ HORS MAQUETTE, ET DIT : la surface web n'a ni file d'attente locale
    // ni adresse serveur à régler. Ces deux écrans n'ont donc aucune entrée à
    // reproduire — ils sont regroupés à part plutôt que glissés sous un
    // intitulé qui ne les couvre pas.
    (
      'POSTE',
      [
        (SymbolesAgri.sync, 'Synchronisation', EcranPoste.synchronisation),
        (
          SymbolesAgri.settings_applications,
          'Paramètres du poste',
          EcranPoste.parametres,
        ),
      ],
    ),
  ];

  /// En-tête de groupe : `text-[10px] text-white/40 font-bold uppercase tracking-wider px-xs pt-sm`.
  Widget _titreGroupe(String titre) {
    return Padding(
      padding: const EdgeInsets.only(left: AgriSpacing.xs, top: AgriSpacing.sm, bottom: AgriSpacing.xs),
      child: Text(
        titre,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: Colors.white.withValues(alpha: 0.40),
        ),
      ),
    );
  }

  /// Lien de `components/sidebar-link.blade.php` : `flex items-center gap-sm px-sm py-xs rounded-lg`, icône
  /// `text-[20px]`, libellé `text-[13px]`. Actif : `bg-white/10 font-bold text-accent-yellow` ; sinon
  /// `text-white/90`.
  Widget _entree(IconData icone, String libelle, EcranPoste ecran) {
    final selectionne = ecran == actif;
    final couleur = selectionne ? AgriColors.accentYellow : Colors.white.withValues(alpha: 0.90);

    return Padding(
      padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
      child: InkWell(
        key: Key('nav-${ecran.name}'),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        hoverColor: Colors.white.withValues(alpha: 0.10),
        onTap: () => onNaviguer(ecran),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: AgriSpacing.xs),
          decoration: BoxDecoration(
            color: selectionne ? Colors.white.withValues(alpha: 0.10) : null,
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Row(
            children: [
              Icon(icone, size: 20, color: couleur),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: Text(
                  libelle,
                  style: TextStyle(
                    fontSize: AgriTypography.lienBarreLaterale,
                    fontWeight: selectionne ? FontWeight.bold : FontWeight.w500,
                    color: couleur,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ticket H1 — valeurs de `layouts/app.blade.php` (le maître) : `w-72` (288 px), dégradé `sidebar-gradient`
    // (#052e16 → #00210d, `app.css`), en-tête `px-md py-lg border-b border-white/10`, navigation
    // `flex-1 overflow-y-auto px-md py-md`, pied `p-md border-t border-white/10`.
    //
    // 🔴 La navigation ne DÉFILAIT PAS (`Column` + `Spacer`) : avec ses onze groupes, la barre débordait sur un
    // petit écran et le bouton « Synchroniser » du pied devenait inatteignable. Le bouton est passé dans la barre
    // supérieure (ticket H2), et la navigation défile.
    return Container(
      key: const Key('barre-laterale'),
      width: 288,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AgriColors.brandForest, AgriColors.brandForestDark],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.lg),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(SymbolesAgri.agriculture, color: AgriColors.accentYellow, size: 26),
                    const SizedBox(width: AgriSpacing.sm),
                    // « Agri » blanc puis « ERP » jaune, `font-extrabold text-lg`.
                    RichText(
                      key: const Key('barre-laterale-marque'),
                      text: const TextSpan(
                        style: TextStyle(fontSize: AgriTypography.lg, fontWeight: FontWeight.w800, color: Colors.white),
                        children: [
                          TextSpan(text: 'Agri'),
                          TextSpan(text: 'ERP', style: TextStyle(color: AgriColors.accentYellow)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AgriSpacing.xs),
                Text(
                  'Ferme École Olouwachegoun'.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.5,
                    color: Colors.white.withValues(alpha: 0.50),
                  ),
                ),
              ],
            ),
          ),
          // ⚠️ SEULS LES ÉCRANS AUTORISÉS SONT PROPOSÉS, ET UN GROUPE SANS ÉCRAN AUTORISÉ N'EST PAS AFFICHÉ —
          // comme les `@hasanyrole` du web, qui masquent les sections. Toutes les entrées du web sont désormais
          // embarquées au poste : une entrée « estompée » ne pouvait plus signifier qu'un refus de droit, et
          // annonçait à tort « vit sur l'application web ». L'écran se garde lui-même (`GardeEcran`).
          Expanded(
            child: SingleChildScrollView(
              key: const Key('barre-laterale-navigation'),
              padding: const EdgeInsets.all(AgriSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (titre, entrees) in arborescence)
                    if (entrees.any((e) => e.$3 != null && ecrans.contains(e.$3))) ...[
                      _titreGroupe(titre),
                      for (final (icone, libelle, ecran) in entrees)
                        if (ecran != null && ecrans.contains(ecran)) _entree(icone, libelle, ecran),
                      const SizedBox(height: AgriSpacing.sm),
                    ],
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AgriSpacing.xs),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    child: const Icon(SymbolesAgri.account_circle, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.utilisateur?.nom ?? '—',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AgriTypography.xs,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // Le web affiche le NOM TECHNIQUE du rôle (`roles->first()?->name`), en capitales.
                        Text(
                          (auth.utilisateur?.role ?? '').toUpperCase(),
                          key: const Key('barre-laterale-role'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 0.45,
                            color: Colors.white.withValues(alpha: 0.50),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ticket H1 — ruban affiché à droite quand la barre latérale est masquée (`app.blade.php:149-160`).
class _RubanReplie extends StatelessWidget {
  const _RubanReplie({required this.onNaviguer, required this.onReafficher});

  final void Function(EcranPoste) onNaviguer;
  final VoidCallback onReafficher;

  /// Les six liens du web, dans l'ordre, avec leur `title` exact.
  static const liens = <(IconData, String, EcranPoste)>[
    (SymbolesAgri.dashboard, 'Tableau de Bord', EcranPoste.tableauDeBord),
    (SymbolesAgri.point_of_sale, 'Caisse POS', EcranPoste.ventesEtDevis),
    (SymbolesAgri.pets, 'Élevage', EcranPoste.gestionElevage),
    (SymbolesAgri.inventory_2, 'Stocks', EcranPoste.gestionStocks),
    (SymbolesAgri.badge, 'Ressources Humaines', EcranPoste.personnelEtStages),
    (SymbolesAgri.account_balance, 'Comptabilité', EcranPoste.comptabilite),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ruban-replie'),
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: AgriSpacing.md),
      color: const Color(0xF2052E16),
      child: Column(
        children: [
          for (final (icone, titre, ecran) in liens)
            Padding(
              padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
              child: IconButton(
                key: Key('ruban-${ecran.name}'),
                tooltip: titre,
                icon: Icon(icone, color: Colors.white.withValues(alpha: 0.80)),
                hoverColor: Colors.white.withValues(alpha: 0.10),
                onPressed: () => onNaviguer(ecran),
              ),
            ),
          const Spacer(),
          IconButton(
            key: const Key('ruban-reafficher'),
            tooltip: 'Réafficher le menu',
            icon: const Icon(SymbolesAgri.menu_open, color: AgriColors.accentYellow),
            hoverColor: Colors.white.withValues(alpha: 0.10),
            onPressed: onReafficher,
          ),
        ],
      ),
    );
  }
}

/// Titres de la barre supérieure du poste, alignés sur le web.
class SocleAccueilTitres {
  SocleAccueilTitres._();

  /// Ticket H1 — TITRE DE LA BARRE SUPÉRIEURE, celui que le web affiche (`$title` de chaque composant Livewire,
  /// relevé le 19/10/2026), et non plus « GROUPE > écran » reconstitué depuis la barre latérale. Les écrans propres
  /// au poste (Synchronisation, Paramètres du poste) portent leur nom.
  static const titresDuWeb = <EcranPoste, String>{
    EcranPoste.tableauDeBord: 'Tableau de Bord',
    EcranPoste.gestionElevage: 'Gestion Élevage',
    EcranPoste.dashboardElevage: 'Élevage > Dashboard Élevage',
    EcranPoste.suiviReproduction: 'Élevage > Suivi Reproduction',
    EcranPoste.soinsEtVaccins: 'Élevage > Soins et Vaccins',
    EcranPoste.parametresElevage: 'Paramètres Élevage',
    EcranPoste.ficheElevage: 'Élevage > Fiches Lapins',
    EcranPoste.fichePondeuses: 'Élevage > Fiches Pondeuses',
    EcranPoste.ficheReproducteurs: 'Élevage > Fiches Volailles Reproducteurs',
    EcranPoste.fichePorcs: 'Élevage > Fiches Porcs',
    EcranPoste.ficheEscargots: 'Élevage > Fiches Escargots',
    EcranPoste.ficheSujet: 'Élevage > Fiche Sujet',
    EcranPoste.transfertsBandes: 'Élevage > Transferts entre Bandes',
    EcranPoste.ventesEtDevis: 'Ventes & Devis',
    EcranPoste.clientsEtCreances: 'Créances Clients',
    EcranPoste.achatsEtCommandes: 'Achats & Commandes',
    EcranPoste.fournisseurs: 'Fournisseurs',
    EcranPoste.saisieDepenses: 'Achats > Saisie des Dépenses',
    EcranPoste.gestionStocks: 'Gestion des Stocks',
    EcranPoste.catalogueProduits: 'Stocks & Produits > Catalogue Produits',
    EcranPoste.facturation: 'Facturation & MeCeF',
    EcranPoste.personnelEtStages: 'Personnel & Stages',
    EcranPoste.administrationEtDocument: 'Administration & Documents',
    EcranPoste.comptabilite: 'Comptabilité',
    EcranPoste.parametresGeneraux: 'Paramètres',
    EcranPoste.rapportsEtExports: 'Rapports & Exports',
    EcranPoste.monProfil: 'Mon Profil',
    EcranPoste.notifications: 'Centre de Notifications',
    EcranPoste.aideEtAPropos: 'Aide & À Propos',
    EcranPoste.contactEditeur: 'Ferme École Olouwachegoun',
    EcranPoste.synchronisation: 'Synchronisation',
    EcranPoste.parametres: 'Paramètres du poste',
  };

  /// Titre affiché pour [ecran] ; le défaut du web (`$title ?? 'Ferme École Olouwachegoun'`) sinon.
  static String titre(EcranPoste ecran) => titresDuWeb[ecran] ?? 'Ferme École Olouwachegoun';
}
