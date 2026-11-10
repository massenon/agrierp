import 'package:agrierp/core/auth/garde_ecran.dart';
import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 0 Flutter — CONTRÔLE D'ACCÈS PAR RÔLE.
///
/// 🔴 Avant ce ticket, le rôle était reçu à la connexion et **jamais
/// consulté** : un caissier ouvrait la fiche d'élevage, un animalier la caisse.
/// Le CDC l'exige au Sprint 5 Flutter.
///
/// La carte est celle de `RBAC_PAGE_MAP` (prototype), recopiée sans
/// réinterprétation : le projet porte une incohérence connue sur le nombre de
/// rôles qu'il est interdit de résoudre sans accord du client.
void main() {
  group('carte des roles', () {
    /// `'admin': null` dans la carte — aucune restriction.
    test('l administrateur accede a tout', () {
      for (final ecran in EcranPoste.values) {
        expect(
          PermissionsPoste.autorise('admin', ecran),
          isTrue,
          reason: '${ecran.name} doit rester ouvert a l admin',
        );
      }
    });

    test('l animalier accede a la fiche mais pas a la caisse', () {
      expect(
        PermissionsPoste.autorise('animalier', EcranPoste.ficheElevage),
        isTrue,
      );
      expect(
        PermissionsPoste.autorise('animalier', EcranPoste.caisse),
        isFalse,
      );
    });

    test('le caissier accede a la caisse mais pas a la fiche', () {
      expect(PermissionsPoste.autorise('caissier', EcranPoste.caisse), isTrue);
      expect(
        PermissionsPoste.autorise('caissier', EcranPoste.ficheElevage),
        isFalse,
      );
    });

    /// Le comptable n'a ni `pos-interface.html` ni `fiche-lapins.html` dans sa
    /// liste : les deux écrans métier du poste lui sont fermés.
    test('le comptable n a acces a aucun des deux ecrans metier', () {
      expect(
        PermissionsPoste.autorise('comptable', EcranPoste.caisse),
        isFalse,
      );
      expect(
        PermissionsPoste.autorise('comptable', EcranPoste.ficheElevage),
        isFalse,
      );
    });

    /// ⚠️ LA SYNCHRONISATION EST OUVERTE À TOUS : la réserver emprisonnerait
    /// les ventes du caissier sur la machine jusqu'au passage d'un admin.
    test('la synchronisation reste ouverte a tous les roles', () {
      for (final role in ['admin', 'caissier', 'animalier', 'comptable']) {
        expect(
          PermissionsPoste.autorise(role, EcranPoste.synchronisation),
          isTrue,
          reason: '$role doit pouvoir envoyer son propre travail',
        );
      }
    });

    /// ⚠️ Les paramètres du poste changent l'adresse du serveur : ce n'est pas
    /// un geste de comptoir.
    test('les parametres du poste sont reserves a l administrateur', () {
      expect(PermissionsPoste.autorise('admin', EcranPoste.parametres), isTrue);

      for (final role in ['caissier', 'animalier', 'comptable']) {
        expect(PermissionsPoste.autorise(role, EcranPoste.parametres), isFalse);
      }
    });

    /// ⚠️⚠️ COMPORTEMENT DU PROTOTYPE, REPRODUIT ET SIGNALÉ. Un rôle absent de
    /// la carte n'est PAS restreint (`if (allowedPages)` : sans entrée, aucune
    /// vérification). Le CDC annonce 7 rôles, la carte en implémente 4 — un
    /// utilisateur portant l'un des trois autres accéderait à tout.
    /// ARBITRAGE CLIENT REQUIS ; le trancher ici serait choisir à sa place.
    test('un role absent de la carte n est pas restreint', () {
      expect(
        PermissionsPoste.autorise('veterinaire', EcranPoste.caisse),
        isTrue,
      );
      expect(PermissionsPoste.autorise('', EcranPoste.ficheElevage), isTrue);
    });

    test('les ecrans proposes suivent le role', () {
      expect(PermissionsPoste.ecransDe('caissier'), [
        // ⚠️ `dashboard.html` est dans LES QUATRE listes de `RBAC_PAGE_MAP` :
        // le tableau de bord précède la caisse pour tous les rôles.
        EcranPoste.tableauDeBord,
        // ⚠️ Le HUB précède la caisse : c'est lui que la barre latérale ouvre.
        EcranPoste.ventesEtDevis,
        // `creances-clients.html` figure aussi dans la liste du caissier :
        // c'est lui qui encaisse et qui relance.
        EcranPoste.clientsEtCreances,
        // ⚠️ `facturation.html` FIGURE AUSSI DANS LA LISTE DU CAISSIER — c'est
        // lui qui encaisse, donc lui qui facture. Écrit d'abord comme un
        // septième écran ABSENT de la carte, par extrapolation des six
        // précédents ; c'est ce test qui a montré le contraire en voyant la
        // liste du caissier s'allonger (ticket F0.47).
        EcranPoste.caisse,
        EcranPoste.facturation,
        EcranPoste.monProfil, // universel : décision du commanditaire (F0.57)
        EcranPoste.notifications, // universel : extension à confirmer (F0.59)
        EcranPoste.aideEtAPropos, // idem (F0.60)
        EcranPoste.contactEditeur, // idem (F0.62)
        EcranPoste.synchronisation,
        // Ticket IMPORT-1 — hors maquette : le caissier a `manage-ventes` (module Clients).
        EcranPoste.importationMasse,
      ]);

      // `RBAC_PAGE_MAP` accorde a l'animalier les fiches d'espece — ici les
      // trois deja converties.
      expect(PermissionsPoste.ecransDe('animalier'), [
        EcranPoste.tableauDeBord,
        // `gestion-elevage.html` figure dans la liste de l'animalier : c'est
        // l'ecran d'ou la maquette ouvre les fiches d'espece.
        EcranPoste.gestionElevage,
        // `elevage-dashboard.html` y figure aussi — pas chez le caissier.
        EcranPoste.dashboardElevage,
        // Le hub des soins figure, lui, bien dans la liste de l'animalier.
        EcranPoste.soinsEtVaccins,
        // Ticket EL-1 — `transformation.html` figure dans la liste de l'animalier.
        EcranPoste.transformation,

        // ⚠️ `suivi-reproduction.html` N'EST DANS AUCUNE liste de
        // `RBAC_PAGE_MAP` — verifie dans `common.js`. L'animalier ne l'atteint
        // donc pas, alors meme que c'est lui qui palpe les lapines. La carte
        // est recopiee telle quelle ; l'ecart est signale, pas corrige.
        EcranPoste.ficheElevage,
        EcranPoste.fichePondeuses,
        EcranPoste.fichePorcs,
        EcranPoste.ficheReproducteurs,
        EcranPoste.ficheEscargots,
        // Tickets BS1 et BS2 — `gestion-bandes.html` et `enregistrer-sujets.html` figurent dans la liste de l'animalier.
        EcranPoste.gestionBandes,
        EcranPoste.enregistrerSujets,
        // Ticket BS3 — `registre-reproducteurs.html` (le web exige `view-elevage`) : dans la liste de l'animalier.
        EcranPoste.registreReproducteurs,
        EcranPoste.monProfil,
        EcranPoste.notifications,
        EcranPoste.aideEtAPropos,
        EcranPoste.contactEditeur,
        EcranPoste.synchronisation,
        // Ticket 15.46 — hors maquette : mêmes rôles que `manage-elevage` (admin, animalier).
        EcranPoste.transfertsBandes,
        // Ticket IMPORT-4 — hors maquette : l'animalier a `manage-elevage` (module Rations).
        EcranPoste.importationMasse,
      ]);

      // ⚠️⚠️ **LE TICKET F0.52 DONNE ENFIN AU COMPTABLE UN ÉCRAN MÉTIER.**
      // `rapports-exports.html` figure dans SA liste et dans aucune autre :
      // c'est le seul écran du poste que la carte lui réserve.
      //
      // ⚠️ **« Comptabilité » : ANCIENNE INCOHÉRENCE DE `RBAC_PAGE_MAP`, FERMÉE PAR CONF-5.** L'écran porte
      // `comptabilite-hub.html` ; la liste du comptable nommait `journal-comptable.html`, `rapport-bilan.html`,
      // `cloture-exercice.html` et `comptabilite-analytique.html`, jamais le hub : la carte lui fermait l'écran qui contient
      // son propre journal. Le web (`view-comptabilite`) lui ouvre tout le hub : le poste aussi (extension voulue, dite).
      //
      // ⚠️ TICKET CONF-4 (DV-20, « le même périmètre dans LogiAgriERP ») : le comptable LIT les ventes (hub Ventes & Devis
      // sans la caisse), consulte la facturation, lit les achats et les stocks. La caisse (`pos-interface.html`) n'entre PAS
      // dans sa liste (voir `permissions_poste.dart`).
      //
      // ⚠️ TICKET CONF-5 : « Clients et Créances » (lecture : le web l'ouvre avec `view-ventes`) et le HUB Comptabilité
      // (`comptabilite-hub.html`, incohérence ancienne de la carte : le comptable avait ses pages, jamais le hub) s'ajoutent.
      expect(PermissionsPoste.ecransDe('comptable'), [
        EcranPoste.tableauDeBord,
        EcranPoste.ventesEtDevis,
        EcranPoste.clientsEtCreances,
        EcranPoste.achatsEtCommandes,
        EcranPoste.fournisseurs,
        EcranPoste.facturation,
        EcranPoste.comptabilite, // CONF-5 : le hub (ordre de l'enum)
        EcranPoste.saisieDepenses,
        EcranPoste.gestionStocks,
        EcranPoste.catalogueProduits,
        EcranPoste.rapportsEtExports,
        EcranPoste.monProfil,
        EcranPoste.notifications,
        EcranPoste.aideEtAPropos,
        EcranPoste.contactEditeur,
        EcranPoste.synchronisation,
        // Ticket IMPORT-3 — hors maquette : le comptable a `manage-comptabilite` (module Plan comptable).
        EcranPoste.importationMasse,
      ]);
    });
  });

  group('CONF-4 : périmètre du comptable (DV-20)', () {
    test('il lit les ventes, la facturation, les achats et les stocks, JAMAIS la caisse', () {
      for (final ecran in [
        EcranPoste.ventesEtDevis,
        EcranPoste.facturation,
        EcranPoste.achatsEtCommandes,
        EcranPoste.fournisseurs,
        EcranPoste.saisieDepenses,
        EcranPoste.gestionStocks,
        EcranPoste.catalogueProduits,
        EcranPoste.rapportsEtExports,
      ]) {
        expect(PermissionsPoste.autorise('comptable', ecran), isTrue, reason: ecran.name);
      }
      expect(PermissionsPoste.autorise('comptable', EcranPoste.caisse), isFalse);
      // IMPORT-3 : l'importation en masse s'ouvre au comptable (`manage-comptabilite` : plan comptable) ; ses autres modules lui sont refusés.
      expect(PermissionsPoste.autorise('comptable', EcranPoste.importationMasse), isTrue);

      // Ni élevage, ni utilisateurs / réglages, ni inventaire en masse, ni RH, ni administration.
      for (final ecran in [
        EcranPoste.gestionElevage,
        EcranPoste.parametresElevage,
        EcranPoste.transfertsBandes,
        EcranPoste.parametresGeneraux,
        EcranPoste.parametres,
        EcranPoste.personnelEtStages,
        EcranPoste.administrationEtDocument,
      ]) {
        expect(PermissionsPoste.autorise('comptable', ecran), isFalse, reason: ecran.name);
      }
    });

    test('droits : lecture + correction, aucun droit d\'écriture de la caisse, des achats, des stocks ni de l\'élevage', () {
      for (final d in ['view-ventes', 'view-achats', 'view-stocks', 'view-facturation', 'correct-invoices', 'manage-comptabilite', 'export-ventes']) {
        expect(PermissionsPoste.peut('comptable', d), isTrue, reason: d);
      }
      for (final d in [
        'manage-ventes',
        'manage-achats',
        'manage-stocks',
        'manage-elevage',
        'manage-users',
        'manage-parametres',
        'manage-facturation',
      ]) {
        expect(PermissionsPoste.peut('comptable', d), isFalse, reason: d);
      }
    });

    test('les deux portes de correction du web (Gates avoir-client et retransmettre-facture)', () {
      // Avoir : manage-ventes OU correct-invoices.
      expect(PermissionsPoste.peutCorrigerParAvoir('admin'), isTrue);
      expect(PermissionsPoste.peutCorrigerParAvoir('caissier'), isTrue);
      expect(PermissionsPoste.peutCorrigerParAvoir('comptable'), isTrue);
      expect(PermissionsPoste.peutCorrigerParAvoir('animalier'), isFalse);
      // Retransmettre une facture : manage-facturation OU correct-invoices ; le caissier ne la gagne pas.
      expect(PermissionsPoste.peutRetransmettreFacture('admin'), isTrue);
      expect(PermissionsPoste.peutRetransmettreFacture('comptable'), isTrue);
      expect(PermissionsPoste.peutRetransmettreFacture('caissier'), isFalse);
      expect(PermissionsPoste.peutRetransmettreFacture('animalier'), isFalse);
    });

    test('caissier (hors CONF-5) et animalier sont inchangés', () {
      // CONF-5 (DV-06) : le caissier gagne `view-facturation` (lecture seule), rien d'autre.
      expect(PermissionsPoste.permissionsDuRole['caissier'], {'view-ventes', 'manage-ventes', 'export-ventes', 'view-facturation'});
      expect(PermissionsPoste.permissionsDuRole['animalier'], {'view-elevage', 'manage-elevage', 'archive-elevage', 'export-elevage'});
      expect(PermissionsPoste.peut('caissier', 'correct-invoices'), isFalse);
    });

    testWidgets('la garde d\'écran refuse la caisse au comptable et laisse passer le hub des ventes', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: GardeEcran(role: 'comptable', ecran: EcranPoste.caisse, enfant: Text('caisse'))),
      );
      expect(find.byKey(const Key('acces-refuse')), findsOneWidget);
      expect(find.text('caisse'), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(home: GardeEcran(role: 'comptable', ecran: EcranPoste.ventesEtDevis, enfant: Text('hub'))),
      );
      expect(find.text('hub'), findsOneWidget);
    });
  });

  group('CONF-5 : Clients et Créances en lecture, hub Comptabilité, caissier et facturation', () {
    test('le comptable ouvre Clients et Créances (lecture) et tout le hub Comptabilité, jamais la caisse', () {
      expect(PermissionsPoste.autorise('comptable', EcranPoste.clientsEtCreances), isTrue);
      expect(PermissionsPoste.autorise('comptable', EcranPoste.comptabilite), isTrue);
      expect(PermissionsPoste.autorise('comptable', EcranPoste.caisse), isFalse);
      // Lecture seule : aucun droit d'écriture de Clients et Créances (`manage-ventes`).
      expect(PermissionsPoste.peut('comptable', 'view-ventes'), isTrue);
      expect(PermissionsPoste.peut('comptable', 'manage-ventes'), isFalse);
      // L'animalier ne gagne rien.
      expect(PermissionsPoste.autorise('animalier', EcranPoste.clientsEtCreances), isFalse);
      expect(PermissionsPoste.autorise('animalier', EcranPoste.comptabilite), isFalse);
      // Le caissier garde Clients et Créances, n'a toujours pas la comptabilité.
      expect(PermissionsPoste.autorise('caissier', EcranPoste.clientsEtCreances), isTrue);
      expect(PermissionsPoste.autorise('caissier', EcranPoste.comptabilite), isFalse);
    });

    test('le caissier consulte et réimprime la facturation, sans retransmettre ni corriger ni convertir', () {
      expect(PermissionsPoste.autorise('caissier', EcranPoste.facturation), isTrue);
      expect(PermissionsPoste.peut('caissier', 'view-facturation'), isTrue);
      for (final d in ['manage-facturation', 'correct-invoices']) {
        expect(PermissionsPoste.peut('caissier', d), isFalse, reason: d);
      }
      expect(PermissionsPoste.peutRetransmettreFacture('caissier'), isFalse);
    });

    testWidgets('la garde d\'écran laisse passer le comptable sur Clients et Créances et le hub Comptabilité', (tester) async {
      for (final ecran in [EcranPoste.clientsEtCreances, EcranPoste.comptabilite]) {
        await tester.pumpWidget(MaterialApp(home: GardeEcran(role: 'comptable', ecran: ecran, enfant: const Text('ouvert'))));
        expect(find.text('ouvert'), findsOneWidget, reason: ecran.name);
      }
    });
  });

  group('garde d ecran', () {
    /// ⚠️ MASQUER UNE ENTRÉE DE MENU N'EST PAS UNE AUTORISATION : l'écran
    /// atteint autrement doit refuser lui-même.
    testWidgets('un ecran interdit refuse meme atteint directement', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GardeEcran(
            role: 'caissier',
            ecran: EcranPoste.ficheElevage,
            enfant: Text('contenu confidentiel'),
          ),
        ),
      );

      expect(find.byKey(const Key('acces-refuse')), findsOneWidget);
      expect(find.text('contenu confidentiel'), findsNothing);
    });

    /// Le rôle est nommé : « accès refusé » sans dire pourquoi envoie
    /// l'utilisateur chercher une panne inexistante.
    testWidgets('le refus nomme le role', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GardeEcran(
            role: 'comptable',
            ecran: EcranPoste.caisse,
            enfant: SizedBox.shrink(),
          ),
        ),
      );

      expect(find.textContaining('(comptable)'), findsOneWidget);
    });

    testWidgets('un ecran autorise passe sans entrave', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GardeEcran(
            role: 'animalier',
            ecran: EcranPoste.ficheElevage,
            enfant: Text('fiche du jour'),
          ),
        ),
      );

      expect(find.text('fiche du jour'), findsOneWidget);
      expect(find.byKey(const Key('acces-refuse')), findsNothing);
    });
  });
}
