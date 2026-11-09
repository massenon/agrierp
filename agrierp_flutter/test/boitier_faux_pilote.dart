import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// MECEF-2 — FAUX PILOTE du boîtier Eltrade CC300 pour les tests (aucun vrai appareil : NON VÉRIFIÉ avec un vrai boîtier).
/// Rejoue ce que dit le `Readme.md` du pilote : `/check`, `/info`, `/bill` (200 même en échec, `qr_code` vide).
enum ScenarioPilote { succes, qrVide, refus400, indisponible503, delai }

class FauxPilote {
  FauxPilote._(this._serveur);

  final HttpServer _serveur;
  ScenarioPilote scenario = ScenarioPilote.succes;
  Duration delai = Duration.zero;
  final List<Map<String, Object?>> chargesRecues = [];
  final List<String?> enTetesAuthorization = [];
  int appelsBill = 0;

  static Future<FauxPilote> demarrer() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final p = FauxPilote._(s);
    s.listen(p._traiter);
    return p;
  }

  int get port => _serveur.port;
  Uri get adresse => Uri.parse('http://localhost:$port');

  Future<void> arreter() => _serveur.close(force: true);

  Future<void> _traiter(HttpRequest r) async {
    Future<void> repondre(int code, Object corps) async {
      r.response.statusCode = code;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(corps));
      await r.response.close();
    }

    final chemin = r.uri.path;
    if (chemin == '/check') {
      if (scenario == ScenarioPilote.indisponible503) return repondre(503, {'status': 'DeviceNotConnected'});
      return repondre(200, {'status': 'Ready'});
    }
    if (chemin == '/info') {
      if (scenario == ScenarioPilote.indisponible503) return repondre(503, {'status': 'DeviceNotConnected'});
      await Future<void>.delayed(delai);
      return repondre(200, {'NIM': 'ED04000623', 'IFU': '3201910768821', 'COUNTER': '12', 'SellBillCounter': '7'});
    }
    if (chemin == '/bill' && r.method == 'POST') {
      appelsBill++;
      enTetesAuthorization.add(r.headers.value('authorization'));
      final corps = await utf8.decoder.bind(r).join();
      try {
        chargesRecues.add((jsonDecode(corps) as Map).cast<String, Object?>());
      } catch (_) {}
      await Future<void>.delayed(delai);
      switch (scenario) {
        case ScenarioPilote.succes:
        case ScenarioPilote.delai:
          return repondre(200, {'qr_code': 'F;ED04000623;NW34NID6ZHANFNMZ2IU7LL3H;3201910768821;20200503135002'});
        case ScenarioPilote.qrVide:
          return repondre(200, {'qr_code': ''});
        case ScenarioPilote.refus400:
          return repondre(400, {'errors': 'products[0].price : requis'});
        case ScenarioPilote.indisponible503:
          return repondre(503, {'status': 'DeviceNotConnected'});
      }
    }
    return repondre(404, {'erreur': 'inconnu'});
  }
}
