import 'dart:io';

import 'package:agrierp/core/mecef/passerelle_boitier.dart';
import 'package:agrierp/core/mecef/passerelle_boitier_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'boitier_faux_pilote.dart';

// MECEF-2 — le client HTTP du boîtier, contre un FAUX PILOTE local. NON VÉRIFIÉ avec un vrai boîtier.
void main() {
  late FauxPilote pilote;
  late PasserelleBoitierHttp passerelle;

  setUp(() async {
    pilote = await FauxPilote.demarrer();
    passerelle = PasserelleBoitierHttp(
      adresse: pilote.adresse,
      delais: const DelaisBoitier(connexion: Duration(milliseconds: 500), verification: Duration(milliseconds: 500), informations: Duration(milliseconds: 600), facture: Duration(milliseconds: 600)),
    );
  });
  tearDown(() => pilote.arreter());

  const charge = {'seller_id': 'X', 'products': []};

  test('succès : qr_code non vide => FactureCertifiee, la charge est bien transmise, aucun jeton', () async {
    final r = await passerelle.facturer(charge);
    expect(r, isA<FactureCertifiee>());
    expect((r as FactureCertifiee).qrCode, startsWith('F;ED04000623;'));
    expect(pilote.chargesRecues.single['seller_id'], 'X');
    expect(pilote.enTetesAuthorization.single, isNull, reason: 'jamais de jeton vers le pilote');
  });

  test('200 avec qr_code VIDE => refus (jamais un succès)', () async {
    pilote.scenario = ScenarioPilote.qrVide;
    final r = await passerelle.facturer(charge);
    expect(r, isA<FactureRefusee>());
  });

  test('400 => refus avec un motif en français', () async {
    pilote.scenario = ScenarioPilote.refus400;
    final r = await passerelle.facturer(charge);
    expect(r, isA<FactureRefusee>());
    expect((r as FactureRefusee).motif, contains('refusé'));
    expect(r.motif, contains('price'));
  });

  test('503 => « Boîtier injoignable », pas une erreur', () async {
    pilote.scenario = ScenarioPilote.indisponible503;
    expect(await passerelle.facturer(charge), isA<BoitierInjoignable>());
    final e = await passerelle.verifier();
    expect(e.pret, isFalse);
    expect(await passerelle.informations(), isNull);
  });

  test('connexion refusée (pilote arrêté) => injoignable, jamais une exception', () async {
    await pilote.arreter();
    expect(await passerelle.facturer(charge), isA<BoitierInjoignable>());
    final e = await passerelle.verifier();
    expect(e.pret, isFalse);
    expect(e.message, 'Boîtier injoignable');
  });

  test('délai dépassé après envoi => INCERTAIN (jamais un refus ni un succès)', () async {
    pilote.scenario = ScenarioPilote.delai;
    pilote.delai = const Duration(seconds: 2);
    final r = await passerelle.facturer(charge);
    expect(r, isA<FactureIncertaine>());
  });

  test('check et info : prêt + informations lues', () async {
    expect((await passerelle.verifier()).pret, isTrue);
    final i = await passerelle.informations();
    expect(i?.nim, 'ED04000623');
    expect(i?.compteurVentes, '7');
  });

  test('info plus lent que le délai => null', () async {
    pilote.delai = const Duration(seconds: 2);
    expect(await passerelle.informations(), isNull);
  });

  test('GARDE : le client refuse toute adresse hors de cette machine', () {
    for (final h in ['http://192.168.1.20:38917', 'http://exemple.fr:38917', 'http://0.0.0.0:38917']) {
      expect(() => PasserelleBoitierHttp(adresse: Uri.parse(h)), throwsArgumentError, reason: h);
    }
    for (final h in ['http://localhost:38917', 'http://127.0.0.1:38917', 'http://[::1]:38917']) {
      expect(() => PasserelleBoitierHttp(adresse: Uri.parse(h)), returnsNormally, reason: h);
    }
    expect(adresseBoitier, 'http://localhost:38917');
  });

  test('lecture du qr_code du pilote', () {
    final q = QrBoitier.lire('F;ED04000623;NW34NID6ZHANFNMZ2IU7LL3H;3201910768821;20200503135002');
    expect(q.nim, 'ED04000623');
    expect(q.ifu, '3201910768821');
    expect(q.instant, DateTime(2020, 5, 3, 13, 50, 2));
    expect(QrBoitier.lire('autre chose').nim, isNull);
  });

  test('le fichier natif ne code aucune autre adresse que localhost', () {
    final src = File('lib/core/mecef/passerelle_boitier_native.dart').readAsStringSync();
    expect(RegExp(r'https?://(?!localhost)').hasMatch(src), isFalse);
  });
}
