import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// PWA-2b — GARDE-FOU WINDOWS : l'en-tête `Accept: application/json` du client Dio (ajouté par PWA-2 pour le navigateur) ne
/// gêne PAS le poste natif. Le poste lit des réponses JSON (tirage, envoi, refus 4xx) et des OCTETS (PDF, logos : `ResponseType.bytes`) ;
/// un serveur qui rend un PDF à une requête `Accept: application/json` ne le refuse pas (Laravel : aucun `406`, aucune négociation
/// de contenu sur ces routes — `expectsJson()` n'est lu que par les gardes d'authentification et de validation, pour rendre du JSON
/// au lieu d'une redirection). Joué sur le VRAI adaptateur natif (`dart:io`) contre un serveur local.
void main() {
  late HttpServer serveur;
  late Dio client;
  String? acceptRecu;

  setUp(() async {
    serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serveur.listen((requete) async {
      acceptRecu = requete.headers.value('accept');
      if (requete.uri.path == '/pdf') {
        requete.response
          ..headers.contentType = ContentType('application', 'pdf')
          ..add([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]); // %PDF-1
      } else if (requete.uri.path == '/refus') {
        requete.response
          ..statusCode = 422
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'message': 'Refusé'}));
      } else {
        requete.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'ok': true}));
      }
      await requete.response.close();
    });
    // EXACTEMENT les BaseOptions de `lib/main.dart` (garde ci-dessous).
    client = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${serveur.port}', headers: const {'Accept': 'application/json'}));
  });
  tearDown(() => serveur.close(force: true));

  test('les BaseOptions du poste portent Accept: application/json, une seule fois', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect("headers: const {'Accept': 'application/json'}".allMatches(source), hasLength(1));
  });

  test('JSON : lu comme avant', () async {
    final r = await client.get<Map<String, dynamic>>('/json');
    expect(r.data, {'ok': true});
    expect(acceptRecu, 'application/json');
  });

  test('octets (PDF, logo) : rendus intacts malgré Accept: application/json', () async {
    final r = await client.get<List<int>>('/pdf', options: Options(responseType: ResponseType.bytes));
    expect(r.data, [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]);
    expect(r.headers.value('content-type'), contains('application/pdf'));
  });

  test('refus 4xx : le corps JSON arrive, y compris en octets', () async {
    await expectLater(
      client.get<List<int>>('/refus', options: Options(responseType: ResponseType.bytes)),
      throwsA(isA<DioException>().having((e) => utf8.decode(e.response!.data as List<int>), 'corps', contains('Refusé'))),
    );
  });
}
