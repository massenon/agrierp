import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/temps/heure_benin.dart';

/// Sprint C — Accès aux données de clôture de caisse.
///
/// Le poste ne CRÉE PAS lui-même de clôture de caisse validée : il envoie
/// une demande via `pushCashClosures` et le serveur valide. Une clôture
/// locale `en_cours` est créée en mémoire uniquement pour afficher le
/// récapitulatif avant envoi.
///
/// La lecture utilise `AppDatabase.cashClosures` (Drift v88).
class ClotureCaisseRepository {
  final AppDatabase _db;

  ClotureCaisseRepository(this._db);

  static String _dateVersStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Clôtures pour la date du jour sur CE poste (device_id courant).
  Future<List<CashClosure>> cloturesAujourdhui(String deviceId) {
    final aujourdhuiStr = _dateVersStr(HeureBenin.aujourdhui());
    return (_db.select(_db.cashClosures)
          ..where((t) =>
              t.closureDate.equals(aujourdhuiStr) &
              t.deviceId.equals(deviceId)))
        .get();
  }

  /// Vrai si une clôture validée (ou en cours) existe aujourd'hui sur ce poste.
  Future<bool> dejaValideAujourdhui(String deviceId) async {
    final resultat = await cloturesAujourdhui(deviceId);
    return resultat.any(
        (c) => c.statut == 'validée' || c.statut == 'en_cours');
  }

  /// Les 10 dernières clôtures de CE poste, les plus récentes d'abord.
  Future<List<CashClosure>> dernieresCloturesPoste(String deviceId) {
    return (_db.select(_db.cashClosures)
          ..where((t) => t.deviceId.equals(deviceId))
          ..orderBy([(t) => OrderingTerm.desc(t.closureDate)])
          ..limit(10))
        .get();
  }

  /// Toutes les clôtures visibles par ce rôle, les plus récentes d'abord.
  Future<List<CashClosure>> toutesLesCloturesRecentes({int limite = 30}) {
    return (_db.select(_db.cashClosures)
          ..orderBy([(t) => OrderingTerm.desc(t.closureDate)])
          ..limit(limite))
        .get();
  }

  /// Ventes du jour par mode sur CE poste (depuis la table locale `sales`).
  Future<Map<String, double>> ventesJourParMode({
    required String closureDate,
    required String deviceId,
  }) async {
    final ventes = await (_db.select(_db.sales)
          ..where((t) =>
              t.soldAt.year.equals(int.parse(closureDate.substring(0, 4))) &
              t.soldAt.month.equals(int.parse(closureDate.substring(5, 7))) &
              t.soldAt.day.equals(int.parse(closureDate.substring(8, 10))) &
              t.deviceId.equals(deviceId) &
              t.status.isNotIn(['annulee'])))
        .get();

    double especes = 0, mobile = 0, virement = 0;
    for (final v in ventes) {
      switch (v.paymentMode) {
        case 'especes':
          especes += v.total;
        case 'mobile_money':
          mobile += v.total;
        case 'virement':
          virement += v.total;
      }
    }
    return {
      'especes': especes,
      'mobile_money': mobile,
      'virement': virement,
    };
  }
}
