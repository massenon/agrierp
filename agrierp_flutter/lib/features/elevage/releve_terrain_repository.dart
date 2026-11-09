import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import 'parametres_elevage_repository.dart' show EtatEnvoi;
import 'releve_terrain.dart';

/// Saisie refusée AVANT d'être écrite : un message par champ (`label`, `species_code`, `data.x`), ceux du web.
class ReleveRefuse implements Exception {
  const ReleveRefuse(this.erreurs);

  final Map<String, String> erreurs;

  @override
  String toString() => erreurs.values.join(' ');
}

/// Une ligne de l'onglet « Relevés de terrain ».
class LigneReleve {
  const LigneReleve({required this.entree, required this.data, required this.etat});

  final FieldSurveyEntry entree;
  final Map<String, dynamic> data;
  final EtatEnvoi etat;

  bool get aValider => entree.status == ReleveTerrain.aValider;
}

/// Délais constatés d'un fournisseur de provende (5 derniers bons reçus de la catégorie « Aliments »).
class DelaisFournisseur {
  const DelaisFournisseur({required this.fournisseur, required this.nb, required this.bons, required this.critiquePropose});

  final String fournisseur;
  final int nb;

  /// `date_bon`, `date_reception` (AAAA-MM-JJ), `delai_jours`.
  final List<Map<String, dynamic>> bons;
  final int? critiquePropose;
}

/// Synthèse du bloc « Relevés de terrain » du Dashboard Élevage (celle de `ReleveTerrainService::synthese`).
class SyntheseReleves {
  const SyntheseReleves({
    required this.aValider,
    required this.nbLots,
    this.fertiliteMoyenne,
    this.eclosionMoyenne,
    this.dureeObserveeMoyenne,
    this.dureeRegleMoyenne,
    required this.delai,
    this.delaiConstateMax,
  });

  final int aValider;
  final int nbLots;
  final double? fertiliteMoyenne;
  final double? eclosionMoyenne;
  final double? dureeObserveeMoyenne;
  final double? dureeRegleMoyenne;
  final RegleDelai delai;
  final int? delaiConstateMax;
}

/// Ticket RELEVES-1 — l'UNIQUE écrivain de `field_survey_entries` au poste (miroir de `ReleveTerrainService`).
///
/// ⚠️⚠️ **RÈGLE « À VALIDER → VALIDÉ » (DV-24)** : seules les propositions semées par le SERVEUR sont « À valider ».
/// TOUT enregistrement fait ici (création, modification, bouton « Valider » de la modale) écrit `valide` +
/// `validated_at` + `pending` ; le statut « À valider » ne subsiste jamais après un enregistrement humain.
/// Le poste n'écrit que le fait ; le serveur revalide et pose lui-même « validé par ».
class ReleveTerrainRepository {
  ReleveTerrainRepository({required this.database, DateTime Function()? maintenant, Uuid? uuid})
    : _maintenant = maintenant ?? HeureBenin.maintenant,
      _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final DateTime Function() _maintenant;
  final Uuid _uuid;

  // ── Lecture ─────────────────────────────────────────────────────────────────────────────────────────

  static Map<String, dynamic> donnees(FieldSurveyEntry l) {
    try {
      final d = jsonDecode(l.dataJson);
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Lignes ACTIVES d'une famille, dans l'ordre du serveur (type, puis poids / date / libellé).
  Future<List<LigneReleve>> lignes(String famille) async {
    final types = [for (final e in ReleveTerrain.familles.entries) if (e.value == famille) e.key];
    final toutes = await (database.select(database.fieldSurveyEntries)
          ..where((t) => t.isActive.equals(true) & t.type.isIn(types)))
        .get();
    final refus = <String, String>{
      for (final c in await database.select(database.syncConflicts).get()) '${c.sourceTable}:${c.recordId}': c.reason,
    };
    final ordreTypes = ReleveTerrain.familles.keys.toList();
    final lignes = [
      for (final l in toutes)
        LigneReleve(
          entree: l,
          data: donnees(l),
          etat: EtatEnvoi(
            statut: l.syncStatus,
            motifRefus: l.syncStatus == SyncStatus.conflict ? refus['field_survey_entries:${l.id}'] : null,
          ),
        ),
    ];
    lignes.sort((a, b) {
      final t = ordreTypes.indexOf(a.entree.type).compareTo(ordreTypes.indexOf(b.entree.type));
      if (t != 0) return t;
      if (a.entree.type == ReleveTerrain.poissonBareme) {
        final p = ((a.data['poids_min_g'] as num?) ?? 0).compareTo((b.data['poids_min_g'] as num?) ?? 0);
        if (p != 0) return p;
      }
      if (a.entree.type == ReleveTerrain.incubationLot) {
        final m = ((a.data['mise_date'] as String?) ?? '').compareTo((b.data['mise_date'] as String?) ?? '');
        if (m != 0) return m;
      }
      return a.entree.label.toLowerCase().compareTo(b.entree.label.toLowerCase());
    });
    return lignes;
  }

  Future<int> nombreAValider() async {
    final r = await (database.select(database.fieldSurveyEntries)
          ..where((t) => t.isActive.equals(true) & t.status.equals(ReleveTerrain.aValider)))
        .get();
    return r.length;
  }

  // ── Écriture (tous les chemins HUMAINS posent « Validé ») ───────────────────────────────────────────

  Future<ResultatReleve> _normaliser(
    String type, {
    required String? label,
    required String? especeCode,
    required Map<String, dynamic> data,
    String? idExistant,
  }) async {
    final r = ReleveTerrain.normaliser(type, label: label, especeCode: especeCode, data: data);
    final erreurs = Map<String, String>.from(r.erreurs);
    final actives = await (database.select(database.fieldSurveyEntries)..where((t) => t.isActive.equals(true) & t.type.equals(type))).get();
    final autres = actives.where((l) => l.id != idExistant).toList();

    // Contrôles de base (comme `ReleveTerrainService::normaliser`), faits même si les valeurs sont refusées.
    final espece = (especeCode ?? '').trim().isEmpty ? null : especeCode!.trim();
    final libelle = (label ?? '').trim();
    switch (type) {
      case ReleveTerrain.incubationRegle:
        if (espece != null && !erreurs.containsKey('species_code') && autres.any((l) => l.speciesCode == espece)) {
          erreurs['species_code'] = "Une règle d'incubation existe déjà pour cette espèce.";
        }
      case ReleveTerrain.incubationLot:
        if (espece != null) {
          final regles = await (database.select(database.fieldSurveyEntries)
                ..where((t) => t.isActive.equals(true) & t.type.equals(ReleveTerrain.incubationRegle) & t.speciesCode.equals(espece)))
              .get();
          if (regles.isEmpty) erreurs['species_code'] = "Aucune règle d'incubation n'existe pour cette espèce : créez-la d'abord.";
        }
        if (libelle.isNotEmpty && autres.any((l) => l.label == libelle)) erreurs['label'] = 'Un relevé existe déjà pour ce code de lot.';
      case ReleveTerrain.delaiRegle:
        if (idExistant == null && actives.isNotEmpty) erreurs['label'] = 'La règle du délai fournisseur existe déjà : modifiez-la.';
    }
    if (erreurs.isNotEmpty) throw ReleveRefuse(erreurs);
    return r;
  }

  Future<void> _ecrire({
    required String id,
    required String type,
    required ResultatReleve r,
    String? validePar,
  }) async {
    final maintenant = _maintenant();
    final ligne = FieldSurveyEntriesCompanion.insert(
      id: id,
      type: type,
      label: r.label!,
      speciesCode: Value(r.especeCode),
      dataJson: Value(jsonEncode(r.data)),
      status: const Value(ReleveTerrain.valide),
      validatedByName: Value(validePar),
      validatedAt: Value(HeureBenin.versInstant(maintenant)),
      isActive: const Value(true),
      syncStatus: const Value(SyncStatus.pending),
      updatedAt: Value(HeureBenin.versInstant(maintenant)),
    );
    await database.into(database.fieldSurveyEntries).insert(ligne, onConflict: DoUpdate((_) => ligne));
  }

  Future<String> creer(String type, {required String? label, String? especeCode, required Map<String, dynamic> data, String? validePar}) async {
    final r = await _normaliser(type, label: label, especeCode: especeCode, data: data);
    final id = _uuid.v4();
    await _ecrire(id: id, type: type, r: r, validePar: validePar);
    return id;
  }

  /// Modifier puis ENREGISTRER : la ligne passe à « Validé ».
  Future<void> modifier(String id, {required String? label, String? especeCode, required Map<String, dynamic> data, String? validePar}) async {
    final l = await _ligne(id);
    final r = await _normaliser(l.type, label: label, especeCode: especeCode, data: data, idExistant: id);
    await _ecrire(id: id, type: l.type, r: r, validePar: validePar);
  }

  /// Modale « Valider » : valeurs relues (corrigées ou non), puis « À valider » → « Validé ».
  Future<void> valider(String id, {String? label, String? especeCode, Map<String, dynamic>? data, String? validePar}) async {
    final l = await _ligne(id);
    final r = await _normaliser(
      l.type,
      label: label ?? l.label,
      especeCode: especeCode ?? l.speciesCode,
      data: data ?? donnees(l),
      idExistant: id,
    );
    await _ecrire(id: id, type: l.type, r: r, validePar: validePar);
  }

  /// Archivage logique (jamais de suppression) ; le statut n'est pas touché.
  Future<void> archiver(String id) =>
      (database.update(database.fieldSurveyEntries)..where((t) => t.id.equals(id))).write(
        FieldSurveyEntriesCompanion(
          isActive: const Value(false),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(HeureBenin.versInstant(_maintenant())),
        ),
      );

  Future<FieldSurveyEntry> _ligne(String id) => (database.select(database.fieldSurveyEntries)..where((t) => t.id.equals(id))).getSingle();

  // ── Délai fournisseur de provende (calculé en lecture des bons reçus) ───────────────────────────────

  static String _jourDe(DateTime d) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${deux(d.month)}-${deux(d.day)}';
  }

  /// Les 5 derniers bons de commande REÇUS de la catégorie « Aliments », par fournisseur : du jour du bon au jour
  /// de la réception (achat qui porte `purchase_order_id`). Lecture seule.
  Future<List<DelaisFournisseur>> delaisFournisseurs() async {
    final bons = await (database.select(database.purchaseOrders)..where((b) => b.status.equals('recu'))).get();
    if (bons.isEmpty) return const [];
    final achats = await database.select(database.purchases).get();
    final achatDuBon = <String, Purchase>{
      for (final a in achats)
        if (a.purchaseOrderId != null) a.purchaseOrderId!: a,
    };
    final lignes = await database.select(database.purchaseOrderLines).get();
    final produits = {for (final p in await database.select(database.products).get()) p.id: p};
    final categories = {for (final c in await database.select(database.productCategories).get()) c.id: c.label};

    bool aliment(String bonId) => lignes.any((l) => l.purchaseOrderId == bonId && categories[produits[l.productId]?.categoryId] == 'Aliments');

    final parFournisseur = <String, List<PurchaseOrder>>{};
    for (final b in bons) {
      if (b.createdAt == null || b.supplierId == null || !achatDuBon.containsKey(b.id) || !aliment(b.id)) continue;
      parFournisseur.putIfAbsent(b.supplierId!, () => []).add(b);
    }

    final sortie = <DelaisFournisseur>[];
    for (final e in parFournisseur.entries) {
      final tries = e.value.toList()
        ..sort((a, b) {
          String cle(PurchaseOrder x) => '${_jourDe(achatDuBon[x.id]!.purchaseDate)}${x.createdAt!.toIso8601String()}${x.id}';
          return cle(b).compareTo(cle(a));
        });
      final retenus = tries.take(ReleveTerrain.nbBons).toList();
      final lignesBons = [
        for (final b in retenus)
          () {
            final jb = DateTime.utc(b.createdAt!.year, b.createdAt!.month, b.createdAt!.day);
            final pd = achatDuBon[b.id]!.purchaseDate;
            final jr = DateTime.utc(pd.year, pd.month, pd.day);
            final d = jr.difference(jb).inDays;
            return <String, dynamic>{'date_bon': _jourDe(jb), 'date_reception': _jourDe(jr), 'delai_jours': d < 0 ? 0 : d};
          }(),
      ];
      final plusLong = lignesBons.isEmpty ? null : lignesBons.map((x) => x['delai_jours'] as int).reduce((a, b) => a > b ? a : b);
      sortie.add(
        DelaisFournisseur(
          fournisseur: retenus.first.supplierName ?? '—',
          nb: lignesBons.length,
          bons: lignesBons,
          critiquePropose: lignesBons.length >= ReleveTerrain.nbBons ? plusLong : null,
        ),
      );
    }
    sortie.sort((a, b) => a.fournisseur.toLowerCase().compareTo(b.fournisseur.toLowerCase()));
    return sortie;
  }

  /// Règle du délai fournisseur EN VIGUEUR (`ReleveTerrainService::regleEnVigueur`) : 3 j / 7 j tant que la règle
  /// n'est pas validée ou qu'aucun fournisseur n'a 5 bons.
  Future<RegleDelai> regleEnVigueur() async {
    final lignes = await (database.select(database.fieldSurveyEntries)
          ..where((t) => t.isActive.equals(true) & t.type.equals(ReleveTerrain.delaiRegle))
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(1))
        .get();
    final l = lignes.isEmpty ? null : lignes.first;
    final propositions = [for (final f in await delaisFournisseurs()) if (f.critiquePropose != null) f.critiquePropose!];
    return ReleveTerrain.regleEnVigueur(statut: l?.status, data: l == null ? null : donnees(l), propositions: propositions);
  }

  Future<SyntheseReleves> synthese() async {
    final lots = await (database.select(database.fieldSurveyEntries)
          ..where((t) => t.isActive.equals(true) & t.type.equals(ReleveTerrain.incubationLot)))
        .get();
    final regles = {
      for (final r in await (database.select(database.fieldSurveyEntries)
            ..where((t) => t.isActive.equals(true) & t.type.equals(ReleveTerrain.incubationRegle)))
          .get())
        r.speciesCode: donnees(r),
    };
    final fertilite = <double>[], eclosion = <double>[], durees = <int>[], dureesRegle = <int>[];
    for (final lot in lots) {
      final c = ReleveTerrain.calculsLot(donnees(lot));
      if (c.tauxFertilite != null) fertilite.add(c.tauxFertilite!);
      if (c.tauxEclosion != null) eclosion.add(c.tauxEclosion!);
      if (c.dureeJours != null) {
        durees.add(c.dureeJours!);
        final regle = regles[lot.speciesCode]?['duree_jours'];
        if (regle != null) dureesRegle.add((regle as num).toInt());
      }
    }
    double? moy(List<num> v) => v.isEmpty ? null : ((v.fold<double>(0, (t, x) => t + x) / v.length) * 10).round() / 10;
    final delais = await delaisFournisseurs();
    return SyntheseReleves(
      aValider: await nombreAValider(),
      nbLots: lots.length,
      fertiliteMoyenne: moy(fertilite),
      eclosionMoyenne: moy(eclosion),
      dureeObserveeMoyenne: moy(durees),
      dureeRegleMoyenne: moy(dureesRegle),
      delai: await regleEnVigueur(),
      delaiConstateMax: delais.isEmpty
          ? null
          : delais.map((f) => f.bons.map((b) => b['delai_jours'] as int).reduce((a, b) => a > b ? a : b)).reduce((a, b) => a > b ? a : b),
    );
  }
}
