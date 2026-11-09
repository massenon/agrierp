import '../../core/database/app_database.dart';

/// `App\Services\AgedBalanceService` — BALANCE ÂGÉE (clients et fournisseurs), transposée ligne pour ligne.
///
/// ⚠️ **L'ÂGE SE COMPTE DEPUIS L'ÉCHÉANCE, PAS DEPUIS L'ÉMISSION**, et **c'est le RESTE DÛ qui est ventilé**, jamais le
/// montant initial. Une échéance absente = « Non échu » (lacune de saisie, pas un retard). Les tranches sont celles du
/// serveur (`AgedBalanceService::TRANCHES`).
abstract final class BalanceAgee {
  /// Libellés des tranches, dans l'ordre du serveur ; borne haute en jours de retard (`null` : sans borne, `0` : non échu).
  static const tranches = <(String, int?)>[
    ('Non échu', 0),
    ('1 à 30 jours', 30),
    ('31 à 60 jours', 60),
    ('61 à 90 jours', 90),
    ('Plus de 90 jours', null),
  ];

  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

  /// `tranche()` : jours de retard de [echeance] à [arrete] (échéance absente ou non dépassée : « Non échu »).
  static String tranche(DateTime? echeance, DateTime arrete) {
    final a = _jour(arrete);
    if (echeance == null || !_jour(echeance).isBefore(a)) return 'Non échu';
    final e = _jour(echeance);
    // Jours calendaires (UTC : insensible au changement d'heure).
    final retard = DateTime.utc(a.year, a.month, a.day).difference(DateTime.utc(e.year, e.month, e.day)).inDays;
    for (final (libelle, borne) in tranches) {
      if (borne == 0) continue;
      if (borne == null || retard <= borne) return libelle;
    }
    return 'Plus de 90 jours';
  }

  /// `agencer()` : par tiers (nom), le reste dû par tranche ; le plus gros encours d'abord (tri STABLE, comme `uasort` de
  /// PHP 8) ; les totaux par tranche et le total général.
  static BalanceAgeeEtat agencer(List<LigneEncours> lignes, DateTime arrete) {
    final parTiers = <String, Map<String, double>>{};
    final totaux = {for (final (l, _) in tranches) l: 0.0};
    for (final ligne in lignes) {
      final reste = ligne.montant - ligne.regle;
      if (reste <= 0) continue;
      final t = tranche(ligne.echeance, arrete);
      final tiers = parTiers.putIfAbsent(ligne.nom, () => {for (final (l, _) in tranches) l: 0.0});
      tiers[t] = tiers[t]! + reste;
      totaux[t] = totaux[t]! + reste;
    }
    final noms = parTiers.keys.toList();
    double total(String n) => parTiers[n]!.values.fold(0.0, (a, b) => a + b);
    final indices = [for (var i = 0; i < noms.length; i++) i]
      ..sort((a, b) {
        final c = total(noms[b]).compareTo(total(noms[a]));
        return c != 0 ? c : a.compareTo(b);
      });
    return BalanceAgeeEtat(
      tiers: [for (final i in indices) TiersAgee(nom: noms[i], tranches: parTiers[noms[i]]!, total: total(noms[i]))],
      totaux: totaux,
      total: totaux.values.fold(0.0, (a, b) => a + b),
    );
  }

  /// `creances()` : créances OUVERTES (`amount_paid < amount`), le client nommé (« Client supprimé » sinon).
  static BalanceAgeeEtat creances(List<Receivable> creances, List<Customer> clients, DateTime arrete) {
    final nomDe = {for (final c in clients) c.id: c.name};
    return agencer([
      for (final c in creances)
        if (c.amountPaid < c.amount)
          LigneEncours(
            nom: nomDe[c.customerId] ?? 'Client supprimé',
            montant: c.amount,
            regle: c.amountPaid,
            echeance: c.dueDate,
          ),
    ], arrete);
  }

  /// `dettes()` : la règle des créances côté fournisseurs (« Fournisseur supprimé » sinon).
  static BalanceAgeeEtat dettes(List<Payable> dettes, List<Supplier> fournisseurs, DateTime arrete) {
    final nomDe = {for (final f in fournisseurs) f.id: f.name};
    return agencer([
      for (final d in dettes)
        if (d.amountPaid < d.amount)
          LigneEncours(
            nom: d.supplierName ?? nomDe[d.supplierId] ?? 'Fournisseur supprimé',
            montant: d.amount,
            regle: d.amountPaid,
            echeance: d.dueDate,
          ),
    ], arrete);
  }
}

class LigneEncours {
  const LigneEncours({required this.nom, required this.montant, required this.regle, required this.echeance});

  final String nom;
  final double montant;
  final double regle;
  final DateTime? echeance;
}

class TiersAgee {
  const TiersAgee({required this.nom, required this.tranches, required this.total});

  final String nom;
  final Map<String, double> tranches;
  final double total;
}

class BalanceAgeeEtat {
  const BalanceAgeeEtat({required this.tiers, required this.totaux, required this.total});

  final List<TiersAgee> tiers;
  final Map<String, double> totaux;
  final double total;
}

/// Ce que la page lit au poste : créances, dettes et leurs tiers (tables tirées du serveur).
class DonneesBalanceAgee {
  const DonneesBalanceAgee({
    this.creances = const [],
    this.clients = const [],
    this.dettes = const [],
    this.fournisseurs = const [],
  });

  final List<Receivable> creances;
  final List<Customer> clients;
  final List<Payable> dettes;
  final List<Supplier> fournisseurs;

  static Future<DonneesBalanceAgee> charger(AppDatabase db) async => DonneesBalanceAgee(
    creances: await db.select(db.receivables).get(),
    clients: await db.select(db.customers).get(),
    dettes: await db.select(db.payables).get(),
    fournisseurs: await db.select(db.suppliers).get(),
  );

  BalanceAgeeEtat calculer(String volet, DateTime arrete) =>
      volet == 'dettes' ? BalanceAgee.dettes(dettes, fournisseurs, arrete) : BalanceAgee.creances(creances, clients, arrete);
}
