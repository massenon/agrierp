import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'core/auth/auth_service.dart';
import 'core/auth/garde_ecran.dart';
import 'core/auth/permissions_poste.dart';
import 'core/config/parametres_poste.dart';
import 'core/database/app_database.dart';
import 'core/export/pdf_recu.dart';
import 'core/sync/sync_button.dart';
import 'core/sync/sync_engine.dart';
import 'core/theme/agri_theme.dart';
import 'core/widgets/barre_superieure.dart';
import 'core/theme/agri_tokens.dart';
import 'features/auth/login_screen.dart';
import 'features/elevage/fiche_journaliere_repository.dart';
import 'features/achats/achats_commandes_screen.dart';
import 'features/achats/achats_repository.dart';
import 'features/achats/fournisseurs_repository.dart';
import 'features/achats/fournisseurs_screen.dart';
import 'features/achats/depenses_repository.dart';
import 'features/achats/saisie_depenses_screen.dart';
import 'features/elevage/dashboard_elevage_repository.dart';
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
import 'features/parametres/parametres_poste_screen.dart';
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

  late final AuthService _auth = AuthService(
    client: _client,
    deviceName: widget.identifiantPoste,
  );

  late final FicheJournaliereRepository _fiches = FicheJournaliereRepository(
    database: _db,
    deviceId: widget.identifiantPoste,
  );

  late final CaisseRepository _caisse = CaisseRepository(
    database: _db,
    deviceId: widget.identifiantPoste,
  );

  late final SoinsRepository _soins = SoinsRepository(
    database: _db,
    deviceId: widget.identifiantPoste,
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

  @override
  void initState() {
    super.initState();
    _reprendre();
  }

  Future<void> _reprendre() async {
    final ouverte = await _auth.reprendreSession();
    if (mounted) setState(() => _sessionOuverte = ouverte);
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgriERP — Ferme École OLOUWACHEGOUN',
      debugShowCheckedModeBanner: false,
      theme: AgriTheme.light,
      home: switch (_sessionOuverte) {
        null => const Scaffold(
          backgroundColor: AgriColors.surfaceBg,
          body: Center(child: CircularProgressIndicator()),
        ),
        false => LoginScreen(
          auth: _auth,
          onConnecte: () => setState(() => _sessionOuverte = true),
        ),
        true => SocleAccueil(
          database: _db,
          engine: _engine,
          auth: _auth,
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
  });

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

  /// Brouillon de « Contactez l'Éditeur », possédé ICI pour survivre aux
  /// changements d'écran : un texte rédigé hors ligne ne doit pas disparaître
  /// parce qu'on est allé vérifier une information ailleurs.
  final _brouillonContact = BrouillonContact();

  String get _role => widget.auth.utilisateur?.role ?? '';

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
  }

  /// Groupe et libellé de l'écran courant, pour le fil d'Ariane.
  ///
  /// ⚠️ LUS DANS L'ARBORESCENCE DE LA BARRE, jamais recopiés : deux libellés
  /// séparés divergeraient au premier renommage, et le fil d'Ariane
  /// annoncerait un écran qui ne porte plus ce nom.
  (String, String) get _situation {
    // ⚠️ « Mon Profil » s'ouvre depuis le menu du compte, pas depuis la barre
    // latérale : la maquette n'y met aucun groupe, son fil d'Ariane se réduit à
    // l'écran. Un groupe vide le dit à `BarreSuperieure`.
    if (_ecran == EcranPoste.monProfil) return ('', 'Mon Profil');
    // ⚠️ Le fil d'Ariane de la maquette dit « Notifications », pas le titre de
    // la page (« Centre de Notifications »).
    if (_ecran == EcranPoste.notifications) return ('', 'Notifications');
    if (_ecran == EcranPoste.aideEtAPropos) return ('', 'Aide & À Propos');
    if (_ecran == EcranPoste.ficheSujet) return ('Élevage', 'Fiche Sujet');
    if (_ecran == EcranPoste.contactEditeur) {
      return ('', "Contactez l'Éditeur");
    }

    for (final (titre, entrees) in _BarreLaterale.arborescence) {
      for (final (_, libelle, ecran) in entrees) {
        if (ecran == _ecran) return (titre, libelle);
      }
    }

    // ⚠️ Les fiches d'espèce ne figurent pas dans la barre — la maquette non
    // plus ne les y met pas : elles s'ouvrent depuis « Gestion Élevage ».
    return ('PRODUCTION ÉLEVAGE & SOINS', _libelleFiche(_ecran));
  }

  static String _libelleFiche(EcranPoste e) => switch (e) {
    EcranPoste.ficheElevage => 'Fiches Lapins',
    EcranPoste.fichePondeuses => 'Fiches Pondeuses',
    EcranPoste.ficheReproducteurs => 'Fiches Reproducteurs',
    EcranPoste.fichePorcs => 'Fiches Porcs',
    EcranPoste.ficheEscargots => 'Fiches Escargots',
    _ => e.name,
  };

  @override
  void dispose() {
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
              database: widget.database,
              engine: widget.engine,
              auth: widget.auth,
              actif: _ecran,
              ecrans: PermissionsPoste.ecransDe(_role),
              onNaviguer: (e) => setState(() => _ecran = e),
              onSynchronise: () => setState(() => _versionTirage++),
              onIndisponible: (libelle) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '« $libelle » vit sur l\'application web : ce poste '
                      "n'embarque que la saisie de terrain.",
                    ),
                  ),
                );
              },
            ),
          Expanded(
            child: Column(
              children: [
                // ⚠️ LE COMPTEUR EST LU EN DIRECT : figer sa valeur au
                // montage laisserait la pastille annoncer « Sync » alors
                // qu'une journée vient d'être saisie.
                FutureBuilder<(int, DonneesNotifications)>(
                  future: _etatDeLaBarre(),
                  builder: (context, instantane) => BarreSuperieure(
                    groupe: groupe,
                    ecran: ecranCourant,
                    enAttente: instantane.data?.$1 ?? 0,
                    nonLues: instantane.data?.$2.nonLues,
                    recentes: [
                      for (final n in (instantane.data?.$2.lignes ?? []).take(
                        4,
                      ))
                        ApercuNotification(
                          message: n.message,
                          dateTexte: n.dateTexte,
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
                  ),
                ),
                Expanded(child: _contenu()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ce que lit la barre supérieure : la file d'attente et les notifications.
  Future<(int, DonneesNotifications)> _etatDeLaBarre() async => (
    await widget.database.pendingCount(),
    await widget.notifications.charger(),
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
        EcranPoste.dashboardElevage => DashboardElevageScreen(
          depot: widget.dashboardElevage,
        ),
        EcranPoste.suiviReproduction => SuiviReproductionScreen(
          depot: widget.reproduction,
          onOuvrirSujet: (id) => setState(() {
            _sujetId = id;
            _avantSujet = EcranPoste.suiviReproduction;
            _ecran = EcranPoste.ficheSujet;
          }),
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
        ),
        EcranPoste.clientsEtCreances => ClientsCreancesScreen(
          depot: widget.clients,
          imprimer: EditeursRapports.imprimer,
        ),
        EcranPoste.gestionStocks => GestionStocksScreen(depot: widget.stocks),
        // ⚠️ MEME DEPOT que Gestion Stocks : deux lecteurs paralleles
        // des memes tables finiraient par diverger.
        EcranPoste.catalogueProduits => CatalogueProduitsScreen(
          depot: widget.stocks,
          produits: widget.produits,
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
        EcranPoste.parametres => ParametresPosteScreen(
          parametres: widget.parametres,
          identifiantActuel: widget.identifiantPoste,
        ),
        EcranPoste.ficheElevage => FicheLapinsScreen(
          depot: widget.fiches,
          soins: widget.soins,
        ),
        EcranPoste.gestionElevage => GestionElevageScreen(
          onOuvrir: (e) => setState(() => _ecran = e),
          modules: widget.parametresGeneraux,
        ),
        EcranPoste.comptabilite => ComptabiliteScreen(
          depot: widget.comptabilite,
          imprimer: EditeursRapports.imprimer,
        ),
        EcranPoste.parametresGeneraux => ParametresGenerauxScreen(
          depot: widget.parametresGeneraux,
        ),
        EcranPoste.rapportsEtExports => RapportsExportsScreen(
          depot: widget.rapports,
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
        EcranPoste.ficheEscargots => FicheEscargotsScreen(
          depot: widget.fiches,
          soins: widget.soins,
        ),
        EcranPoste.ficheReproducteurs => FicheReproducteursScreen(
          depot: widget.fiches,
          soins: widget.soins,
        ),
        EcranPoste.fichePorcs => FichePorcsScreen(
          depot: widget.fiches,
          soins: widget.soins,
        ),
        EcranPoste.fichePondeuses => FichePondeusesScreen(
          depot: widget.fiches,
          soins: widget.soins,
          production: widget.production,
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
    required this.database,
    required this.engine,
    required this.auth,
    required this.actif,
    required this.ecrans,
    required this.onNaviguer,
    required this.onIndisponible,
    this.onSynchronise,
  });

  /// Appelé à la fin d'une synchronisation : le tirage a pu apporter de
  /// nouvelles notifications, que la cloche doit montrer.
  final VoidCallback? onSynchronise;

  final AppDatabase database;
  final SyncEngine engine;
  final AuthService auth;
  final EcranPoste actif;
  final List<EcranPoste> ecrans;
  final void Function(EcranPoste) onNaviguer;

  /// Appelé quand l'utilisateur touche une entrée dont le poste n'embarque pas
  /// l'écran — pour le dire, plutôt que de ne rien faire du tout.
  final void Function(String libelle) onIndisponible;

  /// Arborescence **complète** de la barre latérale de la maquette
  /// (`assets/js/sidebar.js`) : chaque groupe, chaque entrée, chaque icône,
  /// dans l'ordre exact.
  ///
  /// ⚠️⚠️ **TOUTES LES ENTRÉES SONT RENDUES, PAS SEULEMENT LES ÉCRANS DU
  /// POSTE.** J'avais d'abord retenu l'inverse — n'afficher que les écrans
  /// construits, pour ne pas promettre d'écran inexistant. Le client a tranché
  /// autrement : la maquette est la référence de mise en page, et sa barre se
  /// reproduit intégralement. Les entrées sans écran embarqué restent donc
  /// visibles, **estompées**, et disent au clic qu'elles vivent sur
  /// l'application web — c'est la seule façon de tenir la mise en page sans
  /// mentir sur ce que le poste sait faire.
  ///
  /// ⚠️ Le troisième champ est l'écran atteint, `null` si le poste ne
  /// l'embarque pas.
  static const arborescence = <(String, List<(IconData, String, EcranPoste?)>)>[
    (
      'PILOTAGE',
      [(Icons.dashboard, 'Tableau de Bord', EcranPoste.tableauDeBord)],
    ),
    (
      'PRODUCTION ÉLEVAGE & SOINS',
      [
        // ⚠️ « Gestion Élevage » mène aux fiches, exactement comme dans la
        // maquette : celle-ci ne liste AUCUNE fiche dans sa barre, elles
        // s'ouvrent depuis cet écran.
        (Icons.pets, 'Gestion Élevage', EcranPoste.gestionElevage),
        (Icons.dashboard, 'Dashboard Élevage', EcranPoste.dashboardElevage),
        (Icons.favorite, 'Suivi Reproduction', EcranPoste.suiviReproduction),
        (Icons.vaccines, 'Soins et vaccins', EcranPoste.soinsEtVaccins),
        (Icons.tune, 'Paramètres Élevage', EcranPoste.parametresElevage),
      ],
    ),
    (
      'VENTES FERME',
      [
        (Icons.point_of_sale, 'Ventes & Devis', EcranPoste.ventesEtDevis),
        (Icons.payments, 'Clients et Créances', EcranPoste.clientsEtCreances),
      ],
    ),
    (
      'ACHATS & CHARGES',
      [
        (
          Icons.local_shipping,
          'Achats & Commandes',
          EcranPoste.achatsEtCommandes,
        ),
        (Icons.contact_page, 'Fournisseurs', EcranPoste.fournisseurs),
        (Icons.receipt, 'Saisie Dépenses', EcranPoste.saisieDepenses),
      ],
    ),
    (
      'STOCKS & PRODUITS',
      [
        (Icons.inventory_2, 'Gestion Stocks', EcranPoste.gestionStocks),
        (Icons.category, 'Catalogue Produits', EcranPoste.catalogueProduits),
      ],
    ),
    (
      'FACTURATION',
      [(Icons.receipt_long, 'Facturation & MeCeF', EcranPoste.facturation)],
    ),
    (
      'RESSOURCES HUMAINES',
      [(Icons.badge, 'Personnel & Stages', EcranPoste.personnelEtStages)],
    ),
    (
      'ADMINISTRATION',
      [
        (
          Icons.folder_shared,
          'Administration & Document',
          EcranPoste.administrationEtDocument,
        ),
      ],
    ),
    (
      'COMPTABILITÉ & ADMIN',
      [
        (Icons.account_balance, 'Comptabilité', EcranPoste.comptabilite),
        (Icons.settings, 'Paramètres Général', EcranPoste.parametresGeneraux),
      ],
    ),
    (
      'EDITIONS',
      [
        (
          Icons.picture_as_pdf,
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
        (Icons.sync, 'Synchronisation', EcranPoste.synchronisation),
        (
          Icons.settings_applications,
          'Paramètres du poste',
          EcranPoste.parametres,
        ),
      ],
    ),
  ];

  /// En-tête de groupe — même graisse et même casse que la maquette.
  Widget _titreGroupe(String titre) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AgriSpacing.xs,
        top: AgriSpacing.sm,
        bottom: 2,
      ),
      child: Text(
        titre,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: Colors.white38,
        ),
      ),
    );
  }

  Widget _entree(IconData icone, String libelle, EcranPoste? ecran) {
    final selectionne = ecran != null && ecran == actif;

    // ⚠️ TROIS ÉTATS, PAS DEUX. Une entrée peut être : active, disponible, ou
    // **présente mais non embarquée**. Ce dernier cas est celui de la plupart
    // des écrans de la maquette : le poste n'en porte que quelques-uns.
    final embarque = ecran != null && ecrans.contains(ecran);

    return InkWell(
      key: Key('nav-${ecran?.name ?? libelle}'),
      onTap: () {
        if (embarque) {
          onNaviguer(ecran);
          return;
        }
        onIndisponible(libelle);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.md,
          vertical: 9,
        ),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: selectionne ? Colors.white.withValues(alpha: 0.14) : null,
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Row(
          children: [
            Icon(
              icone,
              size: 18,
              // Estompé quand l'écran n'est pas embarqué.
              color: embarque ? Colors.white : Colors.white30,
            ),
            const SizedBox(width: AgriSpacing.sm),
            Expanded(
              child: Text(
                libelle,
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: selectionne ? FontWeight.bold : FontWeight.w500,
                  color: embarque ? Colors.white : Colors.white38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AgriColors.brandForest,
      child: Column(
        children: [
          const SizedBox(height: AgriSpacing.lg),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AgriSpacing.md),
            child: Row(
              children: [
                Icon(Icons.agriculture, color: AgriColors.accentYellow),
                SizedBox(width: AgriSpacing.sm),
                Text(
                  'AgriERP',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AgriSpacing.lg),
          // ⚠️ REGROUPÉES COMME DANS LA MAQUETTE. Seuls les écrans autorisés
          // par le rôle sont proposés, et un groupe dont aucun écran ne l'est
          // ne s'affiche pas du tout — plutôt qu'un titre suivi du vide.
          // ⚠️ TOUS LES GROUPES ET TOUTES LES ENTRÉES DE LA MAQUETTE, dans son
          // ordre. Une entrée dont le poste n'embarque pas l'écran reste
          // visible mais estompée — la mise en page est tenue sans mentir sur
          // ce que l'application sait faire.
          for (final (titre, entrees) in arborescence) ...[
            _titreGroupe(titre),
            for (final (icone, libelle, ecran) in entrees)
              _entree(icone, libelle, ecran),
          ],
          const Spacer(),
          // Pied de barre latérale : le bouton « Synchroniser » y est placé
          // exactement comme dans la maquette, au-dessus du bloc utilisateur.
          Padding(
            padding: const EdgeInsets.all(AgriSpacing.md),
            child: Column(
              children: [
                SyncButton(
                  engine: engine,
                  pendingCount: database.pendingCount,
                  onTermine: onSynchronise,
                ),
                const SizedBox(height: AgriSpacing.sm),
                // Bloc utilisateur, sous le bouton comme dans la maquette.
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white24,
                      child: Icon(
                        Icons.account_circle,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: AgriSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.utilisateur?.nom ?? 'Utilisateur',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AgriTypography.xs,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            (auth.utilisateur?.roleLibelle ?? '').toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              letterSpacing: 1,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
