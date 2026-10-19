import '../../core/auth/permissions_poste.dart';
import '../../core/database/app_database.dart';

/// Un résultat de la recherche globale (`GlobalSearch.php` : `label`, `sublabel`, `icon`, `critical`, `url`).
class ResultatRecherche {
  const ResultatRecherche({
    required this.libelle,
    required this.sousLibelle,
    required this.icone,
    required this.cible,
    this.critique = false,
  });

  final String libelle;
  final String sousLibelle;

  /// Nom Material Symbols du web (`pets`, `medication`…), traduit en icône par l'écran.
  final String icone;

  /// L'écran du poste qui correspond à l'`url` du web.
  final EcranPoste cible;
  final bool critique;
}

/// Un domaine de résultats (`$domains` de `GlobalSearch::getResultsProperty`).
class DomaineRecherche {
  const DomaineRecherche({
    required this.cle,
    required this.libelle,
    required this.icone,
    required this.couleur,
    required this.resultats,
  });

  final String cle;
  final String libelle;
  final String icone;

  /// `emerald` | `blue` | `maize`, comme au web.
  final String couleur;
  final List<ResultatRecherche> resultats;
}

/// Ticket H1b — RECHERCHE GLOBALE DU POSTE, transposée de `App\Livewire\Shared\GlobalSearch` (le maître) sur la base
/// locale. 🔴 Avant : un champ désactivé « Recherche (application web) ».
///
/// Mêmes cinq domaines, mêmes libellés, mêmes limites (5 par domaine, 5 lots puis 5 cycles, 3 fournisseurs…), même
/// seuil de 2 caractères, et SURTOUT le même filtrage par droit EN AMONT : un domaine que le rôle ne voit pas n'est
/// jamais interrogé (« la recherche ne doit jamais devenir une voie de contournement du RBAC »).
///
/// ⚠️ LA COMPARAISON SE FAIT EN DART, sur un texte normalisé : `LIKE` de SQLite n'ignore la casse que pour l'ASCII
/// (« Œufs » cherché « œufs » ne serait pas trouvé — `agrierp_flutter/CLAUDE.md`).
class RechercheGlobaleRepository {
  RechercheGlobaleRepository({required this.database});

  final AppDatabase database;

  /// Permissions du web (`RolesAndPermissionsSeeder`) utilisées par `GlobalSearch` : l'administrateur a tout, le
  /// comptable `view-comptabilite`, le caissier `view-ventes`, l'animalier `view-elevage` ; `view-stocks`,
  /// `view-achats` et `view-rh` n'appartiennent qu'à l'administrateur.
  static bool peut(String role, String permission) => switch (role) {
    'admin' => true,
    'comptable' => permission == 'view-comptabilite',
    'caissier' => permission == 'view-ventes',
    'animalier' => permission == 'view-elevage',
    _ => false,
  };

  /// Texte comparable : minuscules, sans accents ni ligatures.
  static String normaliser(String? texte) {
    const accents = {
      'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i',
      'í': 'i', 'ô': 'o', 'ö': 'o', 'ó': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae',
    };
    final bas = (texte ?? '').toLowerCase();
    final sortie = StringBuffer();
    for (final c in bas.split('')) {
      sortie.write(accents[c] ?? c);
    }
    return sortie.toString();
  }

  static bool _contient(String? texte, String cherche) => normaliser(texte).contains(cherche);

  static String _milliers(num v) {
    final entier = v.round().abs().toString();
    final groupes = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      groupes.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${v.round() < 0 ? '-' : ''}${groupes.join(' ')}';
  }

  static String _nombre(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Moins de 2 caractères : aucune recherche (`updatedQuery` du web).
  Future<List<DomaineRecherche>> rechercher(String saisie, String role) async {
    final q = normaliser(saisie.trim());
    if (q.length < 2) return const [];

    final domaines = [
      DomaineRecherche(cle: 'elevage', libelle: 'Élevage & Cheptel', icone: 'pets', couleur: 'emerald', resultats: await _elevage(q, role)),
      DomaineRecherche(cle: 'sante', libelle: 'Vétérinaire & Soins', icone: 'medication', couleur: 'blue', resultats: await _sante(q, role)),
      DomaineRecherche(cle: 'commercial', libelle: 'Commercial & Caisse', icone: 'point_of_sale', couleur: 'maize', resultats: await _commercial(q, role)),
      DomaineRecherche(cle: 'achats_stocks', libelle: 'Achats & Stocks', icone: 'inventory_2', couleur: 'maize', resultats: await _achatsStocks(q, role)),
      DomaineRecherche(cle: 'comptabilite_admin', libelle: 'Comptabilité & Admin', icone: 'account_balance', couleur: 'blue', resultats: await _comptabiliteAdmin(q, role)),
    ];
    return [for (final d in domaines) if (d.resultats.isNotEmpty) d];
  }

  Future<List<ResultatRecherche>> _elevage(String q, String role) async {
    if (!peut(role, 'view-elevage')) return const [];

    final especes = {for (final e in await database.select(database.livestockSpecies).get()) e.code: e.label};
    final lots = [
      for (final l in await database.select(database.livestockLots).get())
        if (_contient(l.code, q))
          ResultatRecherche(
            libelle: l.code,
            sousLibelle: '${especes[l.speciesCode] ?? ''} — ${l.currentQuantity} sujets',
            icone: 'pets',
            cible: EcranPoste.gestionElevage,
          ),
    ].take(5);
    final cycles = [
      for (final e in await database.select(database.livestockReproductionEvents).get())
        if (_contient(e.motherRef, q) || _contient(e.sireRef, q))
          ResultatRecherche(
            libelle: 'Reproduction — ${e.motherRef}',
            sousLibelle: 'Statut : ${e.status}',
            icone: 'pets',
            cible: EcranPoste.suiviReproduction,
          ),
    ].take(5);
    return [...lots, ...cycles].take(5).toList();
  }

  Future<List<ResultatRecherche>> _sante(String q, String role) async {
    if (!peut(role, 'view-elevage')) return const [];

    return [
      for (final v in await database.select(database.veterinaryRecords).get())
        if (_contient(v.productUsed, q) || _contient(v.vetName, q))
          ResultatRecherche(
            libelle: v.productUsed ?? v.actionType,
            sousLibelle: '${_date(v.recordDate)} — ${v.vetName ?? ''}',
            icone: 'medication',
            cible: EcranPoste.soinsEtVaccins,
          ),
    ].take(5).toList();
  }

  Future<List<ResultatRecherche>> _commercial(String q, String role) async {
    if (!peut(role, 'view-ventes')) return const [];

    final clients = [
      for (final c in await database.select(database.customers).get())
        if (c.isActive && (_contient(c.name, q) || _contient(c.phone, q)))
          ResultatRecherche(
            libelle: c.name,
            sousLibelle: c.phone ?? '',
            icone: 'person',
            cible: EcranPoste.clientsEtCreances,
          ),
    ].take(5);
    final ventes = [
      for (final s in await database.select(database.sales).get())
        if (_contient(s.customerName, q) || _contient(s.mecefQrRef, q))
          ResultatRecherche(
            libelle: 'Vente — ${s.customerName ?? 'Client comptant'}',
            sousLibelle: '${_milliers(s.total)} FCFA',
            icone: 'point_of_sale',
            cible: EcranPoste.ventesEtDevis,
          ),
    ].take(5);
    return [...clients, ...ventes].take(5).toList();
  }

  Future<List<ResultatRecherche>> _achatsStocks(String q, String role) async {
    if (!peut(role, 'view-stocks') && !peut(role, 'view-achats')) return const [];

    final resultats = <ResultatRecherche>[];
    if (peut(role, 'view-stocks')) {
      resultats.addAll([
        for (final p in await database.select(database.products).get())
          if (p.isActive && (_contient(p.name, q) || _contient(p.sku, q)))
            () {
              final critique = p.alertThreshold != null && p.stockQty <= p.alertThreshold!;
              return ResultatRecherche(
                libelle: p.name,
                sousLibelle: 'Stock : ${_nombre(p.stockQty)} ${p.unit}${critique ? ' — Alerte Critique' : ''}',
                icone: 'inventory_2',
                cible: EcranPoste.gestionStocks,
                critique: critique,
              );
            }(),
      ].take(5));
    }
    if (peut(role, 'view-achats')) {
      resultats.addAll([
        for (final s in await database.select(database.suppliers).get())
          if (s.isActive && _contient(s.name, q))
            ResultatRecherche(
              libelle: s.name,
              sousLibelle: s.category ?? '',
              icone: 'local_shipping',
              cible: EcranPoste.fournisseurs,
            ),
      ].take(3));
      resultats.addAll([
        for (final b in await database.select(database.purchaseOrders).get())
          if (_contient(b.supplierName, q))
            ResultatRecherche(
              libelle: 'Bon de commande — ${b.supplierName ?? ''}',
              sousLibelle: 'Statut : ${b.status}',
              icone: 'local_shipping',
              cible: EcranPoste.achatsEtCommandes,
            ),
      ].take(2));
    }
    return resultats.take(5).toList();
  }

  Future<List<ResultatRecherche>> _comptabiliteAdmin(String q, String role) async {
    if (!peut(role, 'view-comptabilite') && !peut(role, 'view-rh')) return const [];

    final resultats = <ResultatRecherche>[];
    if (peut(role, 'view-comptabilite')) {
      // Ticket 15.27 du web : codes courts (plus généraux) d'abord, puis par code.
      final comptes = [
        for (final a in await database.select(database.chartOfAccounts).get())
          if (_contient(a.code, q) || _contient(a.label, q)) a,
      ]..sort((a, b) => a.code.length != b.code.length ? a.code.length.compareTo(b.code.length) : a.code.compareTo(b.code));
      resultats.addAll([
        for (final a in comptes.take(3))
          ResultatRecherche(
            libelle: '${a.code} — ${a.label}',
            sousLibelle: 'Classe ${a.accountClass ?? ''}',
            icone: 'menu_book',
            cible: EcranPoste.comptabilite,
          ),
      ]);
      resultats.addAll([
        for (final e in await database.select(database.accountingEntries).get())
          if (_contient(e.reference, q))
            ResultatRecherche(
              libelle: e.reference ?? 'Écriture',
              sousLibelle: _date(e.entryDate),
              icone: 'account_balance',
              cible: EcranPoste.comptabilite,
            ),
      ].take(2));
    }
    if (peut(role, 'view-rh')) {
      resultats.addAll([
        for (final e in await database.select(database.employees).get())
          if (_contient(e.firstName, q) || _contient(e.lastName, q))
            ResultatRecherche(
              libelle: '${e.lastName} ${e.firstName}',
              sousLibelle: e.position ?? '',
              icone: 'badge',
              cible: EcranPoste.personnelEtStages,
            ),
      ].take(3));
    }
    return resultats.take(5).toList();
  }
}
