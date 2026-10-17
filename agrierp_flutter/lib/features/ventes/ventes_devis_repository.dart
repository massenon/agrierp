import '../../core/database/app_database.dart';

/// Une ligne de l'historique des ventes.
class LigneHistorique {
  const LigneHistorique({required this.vente, required this.nombreArticles});

  final Sale vente;
  final int nombreArticles;

  /// ⚠️ **PAYÉ ET RESTE VIENNENT DE LA SEULE DONNÉE STOCKÉE.** `cash_received`
  /// n'existe que pour un règlement en espèces ; pour les autres modes, le
  /// poste ne sait pas ce qui a été encaissé — l'échéancier vit dans
  /// `receivables`, table qui ne descend pas. Déduire « payé = total » pour un
  /// virement supposerait qu'il a été reçu.
  double? get paye => vente.cashReceived;

  double? get reste =>
      vente.cashReceived == null ? null : vente.total - vente.cashReceived!;
}

class DonneesHistorique {
  const DonneesHistorique({
    required this.chiffreAffaires,
    required this.transactions,
    required this.lignes,
    required this.encoursCreances,
  });

  final double chiffreAffaires;
  final int transactions;
  final List<LigneHistorique> lignes;

  /// 🔴→✅ TICKET F0.43 — plus un tiret : `receivables` descend au poste
  /// depuis le ticket 14.75.
  ///
  /// ⚠️ **LE RESTE DÛ, PAS LE MONTANT FACTURÉ.**
  final double encoursCreances;

  /// `null` quand aucune vente n'a été encaissée : diviser par zéro donnerait
  /// un panier moyen de 0 F, qui se lirait comme un panier réellement vide.
  double? get panierMoyen =>
      transactions == 0 ? null : chiffreAffaires / transactions;
}

/// Lectures du hub `prototype_html/ventes-devis.html`.
///
/// ⚠️⚠️ **LE TIRAGE NE DESCEND PAS `sales`.** L'historique du poste ne contient
/// donc que **ses propres** encaissements — pas ceux du comptoir web ni d'un
/// autre poste. Le sous-titre de la maquette dit « Toutes les ventes
/// enregistrées de l'entreprise » : au poste, c'est faux, et l'écran le
/// corrige plutôt que de le recopier.
///
/// ⚠️ **NI `quotes` NI `credit_notes` NE DESCENDENT** : les onglets « Devis
/// Prestations » et « Retours et Avoirs » n'ont aucune donnée locale, et leurs
/// écritures — un avoir passe une écriture comptable — n'ont pas de canal
/// d'envoi. Ils restent présents et disent pourquoi.
class VentesDevisRepository {
  VentesDevisRepository({required this.database});

  final AppDatabase database;

  /// Modes de règlement du filtre de la maquette, dans son ordre.
  static const modes = ['Espèces', 'Mobile Money', 'Virement', 'Crédit client'];

  /// Statuts du filtre de la maquette, dans son ordre.
  static const statuts = ['Payée', 'En attente', 'Annulée'];

  Future<DonneesHistorique> charger() async {
    final ventes = await database.select(database.sales).get();
    final lignes = await database.select(database.saleLines).get();
    final creances = await database.select(database.receivables).get();

    final parVente = <String, int>{};
    for (final l in lignes) {
      parVente[l.saleId] = (parVente[l.saleId] ?? 0) + 1;
    }

    final triees = ventes.toList()
      ..sort((a, b) => b.soldAt.compareTo(a.soldAt));

    // ⚠️ UNE VENTE ANNULÉE NE COMPTE PAS AU CHIFFRE D'AFFAIRES, mais elle
    // reste dans l'historique : c'est l'historique, pas le journal des ventes
    // valides.
    final retenues = triees.where((v) => v.status != 'annulee').toList();

    return DonneesHistorique(
      chiffreAffaires: retenues.fold<double>(0, (t, v) => t + v.total),
      transactions: retenues.length,
      encoursCreances: creances.fold<double>(
        0,
        (t, c) => t + (c.amount - c.amountPaid),
      ),
      lignes: triees
          .map(
            (v) =>
                LigneHistorique(vente: v, nombreArticles: parVente[v.id] ?? 0),
          )
          .toList(),
    );
  }
}
