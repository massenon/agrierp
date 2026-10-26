import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Issue d'une vérification du code PIN.
enum ResultatVerrou {
  /// Code exact (ou, pour [VerrouLocal.etat], aucun blocage en cours).
  ok,

  /// Code inexact : l'utilisateur peut réessayer.
  refuse,

  /// Trop d'échecs : le service ne regarde même pas le code avant [TentativeVerrou.attente].
  temporise,

  /// Dix échecs cumulés : l'accès local est refusé, il faut se reconnecter EN LIGNE.
  reconnexionRequise,
}

/// Réponse du verrou : l'issue, le nombre d'échecs cumulés et, si temporisé, l'attente restante.
class TentativeVerrou {
  const TentativeVerrou(this.resultat, {this.echecs = 0, this.attente});

  final ResultatVerrou resultat;
  final int echecs;
  final Duration? attente;
}

/// Ticket VL-1 — verrou local : code PIN de 4 à 6 chiffres vérifié SANS réseau, à chaque lancement.
///
/// ⚠️ **MÉCANISME PROPRE AU POSTE** : depuis le ticket VW (26/10/2026) le web a aussi un verrou de session, dont le secret
/// est le mot de passe du compte, vérifié par le serveur. Le poste reprend sa session HORS LIGNE : il ne peut pas
/// interroger le serveur, d'où ce PIN local. Textes communs aux deux côtés : `verrou_parite_web_test.dart`.
///
/// ⚠️ **LE PIN N'EST JAMAIS STOCKÉ.** On range, par utilisateur, un sel aléatoire de 16 octets et l'empreinte
/// PBKDF2-HMAC-SHA256 (au moins 100 000 itérations) ; la comparaison se fait à temps constant. Le tout dans le
/// coffre du système (`flutter_secure_storage`), sous une clé qui porte l'identifiant de l'utilisateur.
///
/// ⚠️ **LIMITE DOCUMENTÉE — L'HORLOGE.** La temporisation (30 s, 1 min, 5 min, 15 min, 30 min dès le 5e échec)
/// se mesure à l'horloge de Windows, que l'utilisateur peut avancer. Bornes simples : reculer l'horloge ne
/// raccourcit rien (l'attente se compte depuis le dernier essai connu, jamais avant), et surtout le plafond de
/// 10 échecs CUMULÉS ne dépend d'aucune horloge : il force la reconnexion en ligne. Avancer l'horloge ne fait
/// gagner que des minutes, pas des essais. Quelqu'un qui peut lire le coffre de la session Windows de
/// l'utilisateur n'est de toute façon pas arrêté par un PIN de 4 à 6 chiffres : ce verrou protège d'un passant,
/// pas d'un attaquant maître de la machine.
class VerrouLocal {
  VerrouLocal({
    FlutterSecureStorage? coffre,
    DateTime Function()? horloge,
    Random? alea,
    this.iterations = iterationsParDefaut,
  }) : _coffre = coffre ?? const FlutterSecureStorage(),
       _horloge = horloge ?? DateTime.now,
       _alea = alea ?? Random.secure();

  /// Réglage de production de PBKDF2 (≥ 100 000). Les tests en passent moins, pour la vitesse.
  static const iterationsParDefaut = 100000;
  static const longueurMin = 4;
  static const longueurMax = 6;

  /// Échecs cumulés à partir desquels l'accès local est refusé.
  static const echecsAvantReconnexion = 10;

  /// Échecs à partir desquels la temporisation commence.
  static const echecsAvantAttente = 5;

  /// Attente imposée après le 5e, 6e, 7e, 8e et 9e échec.
  static const paliers = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];

  final FlutterSecureStorage _coffre;
  final DateTime Function() _horloge;
  final Random _alea;
  final int iterations;

  static String _cle(String idUtilisateur) => 'agrierp.verrou.$idUtilisateur';

  /// 4 à 6 chiffres, rien d'autre.
  static bool pinValide(String pin) => RegExp(r'^[0-9]{4,6}$').hasMatch(pin);

  /// PBKDF2-HMAC-SHA256, une seule sortie de 32 octets (RFC 8018).
  static List<int> deriver(String pin, List<int> sel, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    var u = hmac.convert([...sel, 0, 0, 0, 1]).bytes;
    final t = List<int>.of(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t;
  }

  /// Comparaison à temps constant : la durée ne dit pas à partir de quel octet les empreintes diffèrent.
  static bool egauxATempsConstant(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<Map<String, dynamic>?> _lire(String id) async {
    final brut = await _coffre.read(key: _cle(id));
    if (brut == null) return null;
    try {
      return jsonDecode(brut) as Map<String, dynamic>;
    } on Object {
      // Enregistrement corrompu : mieux vaut « pas de PIN » (donc redéfinition en ligne) qu'une porte fermée à jamais.
      return null;
    }
  }

  Future<void> _ecrire(String id, Map<String, dynamic> e) =>
      _coffre.write(key: _cle(id), value: jsonEncode(e));

  /// Un PIN est-il défini pour cet utilisateur ?
  Future<bool> estDefini(String idUtilisateur) async =>
      await _lire(idUtilisateur) != null;

  /// Définit (ou remplace) le PIN : sel neuf, compteurs remis à zéro. Lève [ArgumentError] si le format est faux.
  Future<void> definir(String idUtilisateur, String pin) async {
    if (!pinValide(pin)) {
      throw ArgumentError('Le code PIN comporte de 4 à 6 chiffres.');
    }
    final sel = List<int>.generate(16, (_) => _alea.nextInt(256));
    await _ecrire(idUtilisateur, {
      'sel': base64Encode(sel),
      'empreinte': base64Encode(deriver(pin, sel, iterations)),
      'iterations': iterations,
      'echecs': 0,
      'dernier': 0,
      'jusqua': 0,
    });
  }

  /// Oublie le PIN de cet utilisateur (« PIN oublié », dix échecs) : la prochaine connexion en ligne en redéfinit un.
  Future<void> effacer(String idUtilisateur) =>
      _coffre.delete(key: _cle(idUtilisateur));

  /// Blocage en cours, sans rien vérifier ni compter : [ResultatVerrou.ok] veut dire « on peut saisir ».
  Future<TentativeVerrou> etat(String idUtilisateur) async {
    final e = await _lire(idUtilisateur);
    if (e == null) return const TentativeVerrou(ResultatVerrou.ok);
    return _blocage(e) ?? TentativeVerrou(ResultatVerrou.ok, echecs: e['echecs'] as int);
  }

  TentativeVerrou? _blocage(Map<String, dynamic> e) {
    final echecs = e['echecs'] as int;
    if (echecs >= echecsAvantReconnexion) {
      return TentativeVerrou(ResultatVerrou.reconnexionRequise, echecs: echecs);
    }
    final maintenant = _horloge().millisecondsSinceEpoch;
    // Borne contre le recul d'horloge : jamais avant le dernier essai connu.
    final effectif = maintenant > (e['dernier'] as int) ? maintenant : e['dernier'] as int;
    final reste = (e['jusqua'] as int) - effectif;
    if (reste > 0) {
      return TentativeVerrou(
        ResultatVerrou.temporise,
        echecs: echecs,
        attente: Duration(milliseconds: reste),
      );
    }
    return null;
  }

  /// Vérifie un PIN. Pendant une temporisation ou après dix échecs, le code n'est pas examiné.
  Future<TentativeVerrou> verifier(String idUtilisateur, String pin) async {
    final e = await _lire(idUtilisateur);
    if (e == null) return const TentativeVerrou(ResultatVerrou.refuse);

    final bloque = _blocage(e);
    if (bloque != null) return bloque;

    final sel = base64Decode(e['sel'] as String);
    final attendue = base64Decode(e['empreinte'] as String);
    final calculee = deriver(pin, sel, e['iterations'] as int);

    if (egauxATempsConstant(calculee, attendue)) {
      e['echecs'] = 0;
      e['jusqua'] = 0;
      await _ecrire(idUtilisateur, e);
      return const TentativeVerrou(ResultatVerrou.ok);
    }

    final echecs = (e['echecs'] as int) + 1;
    final maintenant = _horloge().millisecondsSinceEpoch;
    final dernier = maintenant > (e['dernier'] as int) ? maintenant : e['dernier'] as int;
    e['echecs'] = echecs;
    e['dernier'] = dernier;

    if (echecs >= echecsAvantReconnexion) {
      await _ecrire(idUtilisateur, e);
      return TentativeVerrou(ResultatVerrou.reconnexionRequise, echecs: echecs);
    }
    if (echecs >= echecsAvantAttente) {
      final attente = paliers[echecs - echecsAvantAttente];
      e['jusqua'] = dernier + attente.inMilliseconds;
      await _ecrire(idUtilisateur, e);
      return TentativeVerrou(ResultatVerrou.temporise, echecs: echecs, attente: attente);
    }
    await _ecrire(idUtilisateur, e);
    return TentativeVerrou(ResultatVerrou.refuse, echecs: echecs);
  }

  /// Changement de PIN : l'ancien est requis et compte comme n'importe quel essai (pas de contournement par
  /// « Mon profil »). Lève [ArgumentError] si le nouveau n'a pas 4 à 6 chiffres.
  Future<TentativeVerrou> changer(
    String idUtilisateur, {
    required String ancien,
    required String nouveau,
  }) async {
    if (!pinValide(nouveau)) {
      throw ArgumentError('Le code PIN comporte de 4 à 6 chiffres.');
    }
    final t = await verifier(idUtilisateur, ancien);
    if (t.resultat == ResultatVerrou.ok) await definir(idUtilisateur, nouveau);
    return t;
  }
}
