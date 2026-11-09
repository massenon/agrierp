import 'dart:convert';

import 'package:dio/dio.dart';

import 'passerelle_boitier.dart';

PasserelleBoitier creerPasserelleBoitierPlateforme({Uri? adresse}) => PasserelleBoitierHttp(adresse: adresse);

/// MECEF-2 — le client HTTP du pilote du boîtier (poste Windows).
///
/// ⚠️ UN CLIENT À PART : jamais le client Dio de la session (il porte l'en-tête `Authorization` du serveur ; le pilote n'a aucune
/// authentification et ne doit jamais recevoir ce jeton). L'adresse ne peut désigner que cette machine ([hotesBoitierAutorises]).
class PasserelleBoitierHttp implements PasserelleBoitier {
  PasserelleBoitierHttp({Uri? adresse, this.delais = const DelaisBoitier(), Dio? client})
    : adresse = adresse ?? Uri.parse(adresseBoitier),
      _client = client ?? Dio() {
    if (!hotesBoitierAutorises.contains(this.adresse.host)) {
      throw ArgumentError('Le boîtier ne se joint que par localhost : « ${this.adresse.host} » est refusé.');
    }
    _client.options
      ..baseUrl = this.adresse.toString().replaceAll(RegExp(r'/+$'), '')
      ..connectTimeout = delais.connexion
      ..responseType = ResponseType.plain
      // Tout code HTTP est une réponse à LIRE (503, 400…), jamais une exception.
      ..validateStatus = (_) => true;
    _client.options.headers.remove('Authorization');
  }

  final Uri adresse;
  final DelaisBoitier delais;
  final Dio _client;

  Map<String, Object?>? _json(Object? corps) {
    // Selon l'en-tête de réponse, Dio rend déjà l'objet décodé ou le texte brut : accepter les deux.
    if (corps is Map) return corps.map((k, x) => MapEntry('$k', x));
    try {
      final v = jsonDecode('$corps');
      return v is Map ? v.map((k, x) => MapEntry('$k', x)) : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<EtatBoitier> verifier() async {
    try {
      final r = await _client.get<Object?>('/check', options: Options(receiveTimeout: delais.verification, sendTimeout: delais.verification));
      final j = _json(r.data);
      if (r.statusCode == 200 && j?['status'] == 'Ready') {
        return const EtatBoitier(pret: true, message: 'Boîtier prêt');
      }
      if (r.statusCode == 503) {
        return const EtatBoitier(pret: false, message: 'Boîtier non connecté : branchez-le puis réessayez');
      }
      return const EtatBoitier(pret: false, message: "Le boîtier n'a pas répondu comme prévu");
    } on DioException {
      return EtatBoitier.injoignable;
    } catch (_) {
      return EtatBoitier.injoignable;
    }
  }

  @override
  Future<InfoBoitier?> informations() async {
    try {
      final r = await _client.get<Object?>('/info', options: Options(receiveTimeout: delais.informations, sendTimeout: delais.informations));
      final j = _json(r.data);
      if (r.statusCode != 200 || j == null || j['NIM'] == null) return null;
      String t(String c) => '${j[c] ?? ''}';
      return InfoBoitier(nim: t('NIM'), ifu: t('IFU'), compteur: t('COUNTER'), compteurVentes: t('SellBillCounter'), brut: j);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ResultatFacturation> facturer(Map<String, Object?> charge) async {
    try {
      final r = await _client.post<Object?>(
        '/bill',
        data: jsonEncode(charge),
        options: Options(
          contentType: Headers.jsonContentType,
          receiveTimeout: delais.facture,
          sendTimeout: delais.facture,
        ),
      );
      final j = _json(r.data);
      switch (r.statusCode) {
        case 200:
          // ⚠️ Le pilote répond 200 même en échec : SEUL un `qr_code` non vide prouve le succès.
          final qr = j?['qr_code'];
          if (qr is String && qr.trim().isNotEmpty) return FactureCertifiee(qr.trim());
          return const FactureRefusee("Le boîtier n'a pas certifié la facture (réponse sans code QR) : vérifiez l'appareil puis retransmettez.");
        case 400:
          final detail = j?['errors'];
          return FactureRefusee('Le boîtier a refusé la facture (données non conformes à son schéma)${detail == null ? '' : ' : $detail'}.');
        case 503:
          return const BoitierInjoignable('Boîtier non connecté : la facture reste en attente.');
        default:
          return BoitierInjoignable('Le boîtier a répondu par le code ${r.statusCode} : la facture reste en attente.');
      }
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.connectionError:
          // La demande n'est jamais arrivée au pilote : rien n'a été certifié, la reprise est sûre.
          return const BoitierInjoignable();
        default:
          // Envoi commencé ou terminé, réponse perdue : le boîtier a PEUT-ÊTRE certifié la facture.
          return const FactureIncertaine("La réponse du boîtier n'est pas revenue : la facture a peut-être été certifiée. Vérifiez sur l'appareil avant de la retransmettre.");
      }
    } catch (_) {
      return const FactureIncertaine("Réponse illisible du boîtier : la facture a peut-être été certifiée. Vérifiez sur l'appareil avant de la retransmettre.");
    }
  }
}
