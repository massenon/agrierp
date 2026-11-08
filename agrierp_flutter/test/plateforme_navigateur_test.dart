import 'dart:convert';
import 'dart:typed_data';

import 'package:agrierp/core/config/envoi_email_test.dart';
import 'package:agrierp/core/config/fichiers_entreprise.dart';
import 'package:agrierp/core/config/parametres_poste.dart';
import 'package:agrierp/core/config/parametres_smtp.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/demarrage/dossier_donnees.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/core/export/export_tableur.dart';
import 'package:agrierp/core/export/pdf_recu.dart';
import 'package:agrierp/core/systeme/fichiers_poste.dart';
import 'package:agrierp/core/systeme/justificatif_local.dart';
import 'package:agrierp/core/systeme/plateforme_poste.dart';
import 'package:agrierp/features/parametres/administration_locale.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

/// Ticket PWA-2 — LE CHEMIN NAVIGATEUR DES INTERFACES D'E/S, joué en VM avec l'implémentation de repli.
///
/// Le navigateur lui-même n'existe pas ici : `PlateformePoste.forcerNavigateur(true)` fait prendre à chaque geste le chemin
/// qu'il prendrait dans Chromium, et `livreurNavigateur` est remplacé par un espion (le vrai télécharge un blob). La preuve
/// dans un vrai Chromium est `outils/e2e_poste_web.mjs`. Le natif, lui, reste couvert par les tests existants (inchangés).
void main() {
  final livraisons = <({String nom, List<int> octets})>[];

  setUp(() {
    livraisons.clear();
    PlateformePoste.forcerNavigateur(true);
    PlateformePoste.livreurNavigateur = (nom, octets) async {
      livraisons.add((nom: nom, octets: octets));
      return messageTelechargement(nom);
    };
  });
  tearDown(() {
    PlateformePoste.forcerNavigateur(null);
    PlateformePoste.livreurNavigateur = livrerFichier;
  });

  group('pièces pures de la livraison', () {
    test('type MIME selon l\'extension', () {
      expect(typeMimeDe('a.pdf'), 'application/pdf');
      expect(typeMimeDe('a.XLSX'), contains('spreadsheetml'));
      expect(typeMimeDe('a.json'), 'application/json');
      expect(typeMimeDe('sans-extension'), 'application/octet-stream');
    });

    test('⚠️ un téléchargement ne porte jamais un chemin ni un caractère interdit', () {
      expect(nomFichierSur(r'C:\Users\x\rapport.pdf'), 'rapport.pdf');
      expect(nomFichierSur('../../etc/passwd'), 'passwd');
      expect(nomFichierSur('a:b*c?.pdf'), 'a_b_c_.pdf');
      expect(nomFichierSur('///'), 'document');
    });

    test('la phrase annoncée remplace le chemin du disque', () {
      expect(messageTelechargement('rapport.pdf'), contains('téléchargé par le navigateur'));
      expect(messageTelechargement('rapport.pdf'), isNot(contains(r'\')));
    });
  });

  group('exports : TÉLÉCHARGEMENT au lieu de Documents\\AgriERP', () {
    test('PDF : LivraisonPdf.enregistrer livre le nom horodaté, sans toucher au disque', () async {
      final message = await LivraisonPdf.enregistrer(
        PdfRecu(octets: Uint8List.fromList([1, 2, 3]), fichier: 'recu.pdf'),
        maintenant: DateTime(2026, 11, 8, 9, 5),
      );

      expect(livraisons.single.nom, 'recu-20261108-0905.pdf');
      expect(livraisons.single.octets, [1, 2, 3]);
      expect(message, contains('téléchargé'));
    });

    test('classeur d\'un document officiel : le .xlsx est livré', () async {
      const doc = DocumentOfficiel(titre: 'Stock du jour', sousTitre: '', lignes: []);
      await ExportTableur.enregistrer(doc, maintenant: DateTime(2026, 11, 8, 9, 5));

      expect(livraisons.single.nom, 'Stock-du-jour-20261108-0905.xlsx');
      expect(livraisons.single.octets.take(2), [0x50, 0x4B], reason: 'un .xlsx est une archive ZIP (PK)');
    });

    test('classeur de rapport : le nom du web, le navigateur renomme lui-même un doublon', () async {
      const classeur = ClasseurRapport(fichier: 'recettes-{jour}.xlsx', onglet: 'Recettes', lignes: [['a', 'b']]);
      await ExportTableur.enregistrerTableau(classeur, maintenant: DateTime(2026, 11, 8));

      expect(livraisons.single.nom, 'recettes-2026-11-08.xlsx');
    });
  });

  group('dossier de données, journal, restauration', () {
    test('le navigateur n\'a pas de dossier : erreur française, jamais un échec obscur', () async {
      expect(DossierDonnees.disponible, isFalse);
      await expectLater(DossierDonnees.courant(), throwsA(isA<UnsupportedError>()));
    });

    test('la restauration programmée est ignorée au démarrage (aucune exception)', () async {
      await AdministrationLocale.appliquerRestaurationEnAttente();
    });
  });

  group('administration locale : sauvegardes', () {
    late AppDatabase db;
    late AdministrationLocale admin;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      admin = AdministrationLocale(database: db, role: () => 'admin', idUtilisateur: () => 'u', coffre: CoffreMemoire());
    });
    tearDown(() => db.close());

    test('aucune sauvegarde listée (pas de dossier)', () async {
      expect(await admin.sauvegardes(), isEmpty);
    });

    test('⚠️ la sauvegarde complète (VACUUM INTO) et la copie disque sont refusées avec leur motif', () async {
      await expectLater(
        admin.generer(),
        throwsA(isA<RefusAdministration>().having((e) => e.message, 'motif', AdministrationLocale.motifNavigateur)),
      );
      await expectLater(admin.copier('x_complete.sqlite'), throwsA(isA<RefusAdministration>()));
      await expectLater(admin.programmerRestauration('x_complete.sqlite'), throwsA(isA<RefusAdministration>()));
      await expectLater(admin.importerModule(fichier: 'x_complete.sqlite', module: 'rh'), throwsA(isA<RefusAdministration>()));
    });

    test('l\'export JSON d\'un module est TÉLÉCHARGÉ', () async {
      final message = await admin.generer(module: 'rh');

      expect(message, contains('téléchargé'));
      final contenu = jsonDecode(utf8.decode(livraisons.single.octets)) as Map<String, dynamic>;
      expect(contenu['module'], 'rh');
      expect(livraisons.single.nom, endsWith('_rh.json'));
    });
  });

  group('e-mail de test', () {
    test('⚠️ impossible au navigateur : le motif renvoie vers le web de gestion', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final essai = EnvoiEmailTest(parametres: ParametresSmtp(database: db, coffre: CoffreMemoire()));

      await expectLater(
        essai.envoyer('a@b.bj'),
        throwsA(isA<EchecEnvoiEmail>().having((e) => e.message, 'message', contains('web de gestion'))),
      );
    });
  });

  group('justificatifs et logo', () {
    test('un justificatif n\'est pas joint au navigateur (motif français à l\'écran)', () async {
      expect(await choisirEtCopierJustificatif(), isNull);
      expect(motifJustificatifNavigateur, contains('navigateur'));
    });

    test('le logo tiré du serveur reste en mémoire pour la session, sans disque', () async {
      final f = FichiersEntreprise();
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]);
      await f.enregistrer('logo', png, 'logo.png', sourceServeur: '/storage/logo.png');

      expect(await f.lire('logo'), png);
      expect(await f.sourceServeur('logo'), '/storage/logo.png');
      expect(await f.logoPourPdf(), png);

      await f.effacer('logo');
      expect(await f.lire('logo'), isNull);
    });
  });

  group('adresse du serveur et identifiant du poste', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async {
      ParametresPoste.origineNavigateur = () => Uri.base.origin;
      await db.close();
    });

    test('adresse par défaut = l\'origine de la page', () async {
      ParametresPoste.origineNavigateur = () => 'https://agrierp.exemple.bj';

      expect(await ParametresPoste(database: db).adresseServeur(), 'https://agrierp.exemple.bj');
    });

    test('une adresse enregistrée l\'emporte sur l\'origine', () async {
      ParametresPoste.origineNavigateur = () => 'https://agrierp.exemple.bj';
      final p = ParametresPoste(database: db);
      await p.definirAdresseServeur('http://autre.bj/');

      expect(await p.adresseServeur(), 'http://autre.bj');
    });

    test('identifiant stable « poste-web-<8 hex> », tiré une seule fois', () async {
      final p = ParametresPoste(database: db);
      final premier = await p.identifiant();

      expect(premier, matches(RegExp(r'^poste-web-[0-9a-f]{8}$')));
      expect(await p.identifiant(), premier);
    });
  });
}
