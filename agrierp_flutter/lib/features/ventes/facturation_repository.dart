
import '../../core/database/app_database.dart';
import '../../core/export/document_officiel.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';

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

  /// Numéro de facture, calculé comme `Sale::numero_facture` du web : `FV-AAAA-XXXXXX` (année de la vente, 6 premiers
  /// caractères de l'identifiant en majuscules).
  String get numero => 'FV-${vente.soldAt.year}-${vente.id.substring(0, 6).toUpperCase()}';

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
  FacturationRepository({required this.database, this.mecefParDefaut = true});

  final AppDatabase database;

  /// Valeur du module MeCeF tant que le serveur ne l'a pas dit (`mecef.actif` d'`app_settings`). L'application passe `false` :
  /// comme au serveur (`config/mecef.php`), le module est désactivé jusqu'à sa configuration.
  final bool mecefParDefaut;

  static const cleMecefActif = 'mecef.actif';

  /// Ticket VC-5 — le module MeCeF est-il activé ? Servi par le tirage (`company_settings.mecef_actif`), gardé hors schéma.
  Future<bool> mecefActif() async {
    final ligne = await (database.select(database.appSettings)..where((s) => s.key.equals(cleMecefActif))).getSingleOrNull();
    return ligne == null ? mecefParDefaut : ligne.value == '1';
  }

  Future<void> definirMecefActif(bool actif) => database.into(database.appSettings).insertOnConflictUpdate(
    AppSettingsCompanion.insert(key: cleMecefActif, value: actif ? '1' : '0'),
  );

  /// Facture d'une vente, hors ligne, avec ou sans certification MeCeF (`exports.facture-vente` du web).
  Future<DocumentOfficiel?> documentFacture(String venteId) async {
    final vente = await (database.select(database.sales)..where((s) => s.id.equals(venteId))).getSingleOrNull();
    if (vente == null) return null;
    final lignes = await (database.select(database.saleLines)..where((l) => l.saleId.equals(venteId))).get();
    final produits = {for (final p in await database.select(database.products).get()) p.id: p.name};
    return DocumentsFacturation.facture(LigneFacture(vente: vente, envoyee: vente.syncStatus == SyncStatus.synced), [
      for (final l in lignes) (designation: produits[l.productId] ?? '—', quantite: l.qty, montant: l.manualTotalAmount),
    ]);
  }

  Future<DonneesFacturation> charger({DateTime? mois}) async {
    final ventes = await database.select(database.sales).get();

    return DonneesFacturation(
      mois: mois ?? HeureBenin.maintenant(),
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

/// Ticket VC-5 — le document « Facture » du poste : mêmes mots que `exports.facture-vente` du web.
class DocumentsFacturation {
  const DocumentsFacturation._();

  static String _montant(double v) {
    final entier = v.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${v.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _quantite(double q) => q == q.roundToDouble() ? q.round().toString() : q.toString().replaceAll('.', ',');

  static DocumentOfficiel facture(LigneFacture f, List<({String designation, double quantite, double montant})> lignes) {
    final v = f.vente;
    final certifiee = f.statut == StatutMecef.transmise && v.mecefQrRef != null;
    return DocumentOfficiel(
      titre: 'Facture ${f.numero}',
      sousTitre: 'Du ${_jour(v.soldAt)} — Client : ${f.client}',
      fichier: 'facture-${f.numero}.pdf',
      entetes: const ['Désignation', 'Quantité', 'Prix unitaire', 'Montant'],
      lignes: [
        if (lignes.isEmpty)
          const DonneesDocument(['Aucune ligne.', '', '', ''])
        else
          for (final l in lignes)
            DonneesDocument([l.designation, _quantite(l.quantite), _montant(l.quantite > 0 ? l.montant / l.quantite : 0), _montant(l.montant)]),
        TotalDocument(['Total TTC', '', '', _montant(v.total)], premiere: true),
      ],
      noteDePied: certifiee ? 'Facture normalisée MeCeF — référence : ${v.mecefQrRef}' : 'Facture émise sans certification MeCeF.',
    );
  }
}
