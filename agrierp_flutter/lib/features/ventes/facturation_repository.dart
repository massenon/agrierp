import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';

/// Statut de normalisation fiscale d'une facture, tel que la maquette le nomme.
enum StatutMecef {
  transmise('transmise', 'Transmise'),
  enAttente('en_attente', 'En attente'),
  erreur('erreur', 'Erreur MeCeF'),

  /// ⚠️⚠️ **JAMAIS TRANSMISE** — le statut serveur est nul. C'était le cas de
  /// TOUTE vente encaissée hors ligne avant le ticket 14.80 : le canal d'envoi
  /// appliquait les quatre effets métier et oubliait la normalisation. Le
  /// confondre avec « En attente » masquerait un trou fiscal.
  jamais(null, 'Non transmise');

  const StatutMecef(this.code, this.libelle);

  final String? code;
  final String libelle;

  static StatutMecef depuis(String? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => jamais);
}

/// Une ligne du tableau des factures.
class LigneFacture {
  const LigneFacture({required this.vente, required this.envoyee});

  final Sale vente;

  /// ⚠️ Une facture encore `pending` n'est pas encore arrivée au serveur : elle
  /// ne peut donc pas avoir été transmise à la DGI, et le dire est le seul
  /// moyen pour la caissière de savoir ce qui reste à faire partir.
  final bool envoyee;

  StatutMecef get statut => StatutMecef.depuis(vente.mecefStatus);

  String get client => vente.customerName ?? 'Client de passage';
}

class DonneesFacturation {
  const DonneesFacturation({required this.factures, required this.mois});

  final List<LigneFacture> factures;
  final DateTime mois;

  List<LigneFacture> get duMois => factures
      .where(
        (f) =>
            f.vente.soldAt.year == mois.year &&
            f.vente.soldAt.month == mois.month,
      )
      .toList();

  int compte(StatutMecef statut) =>
      duMois.where((f) => f.statut == statut).length;

  double get montantDuMois =>
      duMois.fold<double>(0, (t, f) => t + f.vente.total);

  /// Factures qui n'ont pas quitté ce poste — donc pas normalisées non plus.
  int get enAttenteDEnvoi => factures.where((f) => !f.envoyee).length;
}

/// Lectures de `prototype_html/facturation.html`.
///
/// ⚠️⚠️ **UNE FACTURE EST UNE VENTE.** Il n'existe pas de table `invoices` :
/// `sales.mecef_status` et `sales.mecef_qr_ref` portent la normalisation
/// fiscale (ticket 7.1). Le poste lit donc ses ventes — les siennes ET celles
/// de toute la ferme, descendues depuis le ticket 14.80.
///
/// ⚠️ **AUCUNE FACTURE NE SE CRÉE ICI.** La maquette propose « Nouvelle
/// Facture » avec Client + Montant HT + TVA, sans article : elle créerait une
/// facture déconnectée de toute vente et de tout stock. La surface web a
/// tranché en redirigeant vers la caisse, seul point d'entrée réel ; le poste
/// applique la même règle.
class FacturationRepository {
  FacturationRepository({required this.database});

  final AppDatabase database;

  Future<DonneesFacturation> charger({DateTime? mois}) async {
    final ventes = await database.select(database.sales).get();

    return DonneesFacturation(
      mois: mois ?? DateTime.now(),
      factures: (ventes.toList()..sort((a, b) => b.soldAt.compareTo(a.soldAt)))
          .map(
            (v) => LigneFacture(
              vente: v,
              envoyee: v.syncStatus == SyncStatus.synced,
            ),
          )
          .toList(),
    );
  }
}
