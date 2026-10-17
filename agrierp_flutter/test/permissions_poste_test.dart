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

        // ⚠️ `suivi-reproduction.html` N'EST DANS AUCUNE liste de
        // `RBAC_PAGE_MAP` — verifie dans `common.js`. L'animalier ne l'atteint
        // donc pas, alors meme que c'est lui qui palpe les lapines. La carte
        // est recopiee telle quelle ; l'ecart est signale, pas corrige.
        EcranPoste.ficheElevage,
        EcranPoste.fichePondeuses,
        EcranPoste.fichePorcs,
        EcranPoste.ficheReproducteurs,
        EcranPoste.ficheEscargots,
        EcranPoste.monProfil,
        EcranPoste.notifications,
        EcranPoste.aideEtAPropos,
        EcranPoste.contactEditeur,
        EcranPoste.synchronisation,
      ]);

      // ⚠️⚠️ **LE TICKET F0.52 DONNE ENFIN AU COMPTABLE UN ÉCRAN MÉTIER.**
      // `rapports-exports.html` figure dans SA liste et dans aucune autre :
      // c'est le seul écran du poste que la carte lui réserve.
      //
      // ⚠️ **« Comptabilité » RESTE HORS DE SA PORTÉE, ET CE N'EST PAS UN
      // OUBLI DU PORTAGE.** L'écran porte `comptabilite-hub.html` ; la liste
      // du comptable nomme `journal-comptable.html`, `rapport-bilan.html`,
      // `cloture-exercice.html` et `comptabilite-analytique.html` — **jamais
      // le hub**. Appliquée telle quelle, la carte lui ferme donc la porte de
      // l'écran qui contient son propre journal. C'est une incohérence de
      // `RBAC_PAGE_MAP`, relevée ici et **non corrigée** : compléter la carte
      // est un arbitrage client, comme pour les six écrans qui n'y figurent
      // pas du tout.
      expect(PermissionsPoste.ecransDe('comptable'), [
        EcranPoste.tableauDeBord,
        EcranPoste.rapportsEtExports,
        EcranPoste.monProfil,
        EcranPoste.notifications,
        EcranPoste.aideEtAPropos,
        EcranPoste.contactEditeur,
        EcranPoste.synchronisation,
      ]);
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
