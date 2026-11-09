import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';

/// Saisie refusée AVANT d'être écrite : un message par champ, ceux du web (clés = propriétés de `TransformationForm`).
class TransformationRefusee implements Exception {
  const TransformationRefusee(this.erreurs);

  /// `lotId` · `qtyAnimals` · `productId` · `qtyProduced` · `transformationDate`.
  final Map<String, String> erreurs;

  @override
  String toString() => erreurs.values.join(' ');
}

/// Une bande proposée par la liste « Lot / Bande d'Élevage » : le code, l'effectif DISPONIBLE et l'espèce.
class LotTransformable {
  const LotTransformable({required this.lot, required this.disponible, required this.espece});

  final LivestockLot lot;

  /// Effectif de la bande moins les sujets des transformations de ce poste pas encore parties : le poste n'écrit jamais
  /// l'effectif, mais ne laisse pas transformer deux fois les mêmes sujets en attendant le serveur.
  final int disponible;
  final String? espece;

  /// `{{ $lot->code }} — {{ $lot->current_quantity }} sujets ({{ $lot->species?->label }})`.
  String get libelle => '${lot.code} — $disponible sujets (${espece ?? ''})';
}

/// Les deux compteurs du mois (`getKpisProperty`).
class KpisTransformation {
  const KpisTransformation({required this.transformationsDuMois, required this.sujetsTransformes});

  final int transformationsDuMois;
  final int sujetsTransformes;
}

/// Une ligne de « Historique des Transformations ».
class LigneTransformation {
  const LigneTransformation({required this.transformation, required this.codeBande, required this.produit, this.motifRefus});

  final Transformation transformation;
  final String? codeBande;
  final String? produit;
  final String? motifRefus;
}

/// Ticket EL-1 — `Livewire\Elevage\TransformationForm` (« Bon d'Abattage & Transformation », route `/transformation`).
///
/// ⚠️⚠️ **LE POSTE N'ÉCRIT QUE LE FAIT** : bande, nombre de sujets, produit fini, quantité produite, jour. Ni l'effectif de la
/// bande, ni la fiche du jour (la transformation est une VENTE de sujets vifs, décision client du 17/10/2026), ni le stock du
/// produit fini ne sont touchés ici : le serveur rejoue tout par `SaisieTransformationAction` (verrous, vente sur la fiche,
/// stock, audit `transformation.recorded`), et le poste se recale au tirage. UN SEUL écrivain de `transformations`.
///
/// Refus AVANT d'écrire, mots pour mots ceux du web (`lang/fr/validation.php` et l'action) : champs obligatoires, nombre
/// entier d'au moins 1, quantité d'au moins 0, effectif disponible, exercice clos (motif R4, sous la date). Le serveur re-juge
/// à l'envoi (effectif modifié ailleurs entre-temps) : la ligne passe alors en `conflict` avec son motif.
class TransformationRepository {
  TransformationRepository({required AppDatabase database, required String deviceId, Uuid? uuid})
    : _db = database,
      // ignore: prefer_initializing_formals
      _deviceId = deviceId,
      _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final String _deviceId;
  final Uuid _uuid;

  ExerciceDeSaisie get _exercice => ExerciceDeSaisie(_db);

  static const _attributs = {
    'lotId': 'bande',
    'qtyAnimals': "nombre d'animaux",
    'productId': 'produit',
    'qtyProduced': 'quantité produite',
    'transformationDate': 'date de transformation',
  };

  static String obligatoire(String champ) => 'Le champ ${_attributs[champ]} est obligatoire.';

  static String inexistant(String champ) => "La valeur sélectionnée pour le champ ${_attributs[champ]} n'existe pas.";

  static String messageEffectifInsuffisant(int disponible) =>
      "La quantité ne peut pas dépasser l'effectif disponible du lot ($disponible).";

  /// `dispatch('toast', message: …)` après la validation.
  static String toast(int sujets, String produit) =>
      'Transformation validée — $sujets sujet(s) transformé(s) en $produit.';

  /// `rtrim(rtrim(number_format($t->qty_produced, 2, '.', ''), '0'), '.')`.
  static String quantite(double v) {
    final texte = v.toStringAsFixed(2);
    return texte.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static String jourFr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Sujets déjà engagés par les transformations de CE poste pas encore parties (`pending`).
  Future<Map<String, int>> _engages() async {
    final enAttente = await (_db.select(_db.transformations)..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();
    final somme = <String, int>{};
    for (final t in enAttente) {
      somme[t.lotId] = (somme[t.lotId] ?? 0) + t.qtyAnimals;
    }
    return somme;
  }

  /// `getLotsProperty` : bandes `actif`, actives, d'effectif disponible > 0.
  Future<List<LotTransformable>> lots() async {
    final engages = await _engages();
    final especes = {for (final e in await _db.select(_db.livestockSpecies).get()) e.id: e.label};
    final bandes = await (_db.select(_db.livestockLots)
          ..where((t) => t.status.equals('actif') & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.code)]))
        .get();
    return [
      for (final b in bandes)
        if (b.currentQuantity - (engages[b.id] ?? 0) > 0)
          LotTransformable(lot: b, disponible: b.currentQuantity - (engages[b.id] ?? 0), espece: especes[b.speciesId]),
    ];
  }

  /// `getEligibleProductsProperty` : produits actifs de l'espèce de la bande ou sans espèce, par nom.
  Future<List<Product>> produits(String lotId) async {
    final lot = await (_db.select(_db.livestockLots)..where((t) => t.id.equals(lotId))).getSingleOrNull();
    if (lot == null) return const [];
    return (_db.select(_db.products)
          ..where((t) => t.isActive.equals(true) & (t.speciesId.equals(lot.speciesId) | t.speciesId.isNull()))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
  }

  /// `getKpisProperty` : transformations du mois et sujets transformés. Une transformation REFUSÉE par le serveur n'a pas
  /// eu lieu : elle ne compte pas.
  Future<KpisTransformation> kpis(DateTime maintenant) async {
    final duMois = (await _db.select(_db.transformations).get()).where(
      (t) =>
          t.syncStatus != SyncStatus.conflict &&
          t.transformationDate.year == maintenant.year &&
          t.transformationDate.month == maintenant.month,
    );
    return KpisTransformation(
      transformationsDuMois: duMois.length,
      sujetsTransformes: duMois.fold(0, (s, t) => s + t.qtyAnimals),
    );
  }

  /// `getHistoryProperty` : les 20 dernières, la plus récente d'abord.
  Future<List<LigneTransformation>> historique() async {
    final lignes = await (_db.select(_db.transformations)
          ..orderBy([
            (t) => OrderingTerm.desc(t.transformationDate),
            (t) => OrderingTerm.desc(t.updatedAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(20))
        .get();
    final codes = {for (final b in await _db.select(_db.livestockLots).get()) b.id: b.code};
    final noms = {for (final p in await _db.select(_db.products).get()) p.id: p.name};
    final refus = {for (final c in await _db.select(_db.syncConflicts).get()) c.id: c.reason};
    return [
      for (final t in lignes)
        LigneTransformation(
          transformation: t,
          codeBande: codes[t.lotId],
          produit: noms[t.productId],
          motifRefus: t.syncStatus == SyncStatus.conflict ? refus['transformations:${t.id}'] : null,
        ),
    ];
  }

  /// `validateTransformation()` : valide, refuse avant d'écrire ([TransformationRefusee]), puis écrit le fait (`pending`).
  /// Rend la transformation écrite ; [produitNom] sert au toast.
  Future<({Transformation transformation, String produitNom})> enregistrer({
    required String lotId,
    required String qtyAnimals,
    required String productId,
    required String qtyProduced,
    required DateTime? date,
  }) => _db.transaction(() async {
    final erreurs = <String, String>{};

    final lot = lotId.isEmpty ? null : await (_db.select(_db.livestockLots)..where((t) => t.id.equals(lotId))).getSingleOrNull();
    if (lotId.isEmpty) {
      erreurs['lotId'] = obligatoire('lotId');
    } else if (lot == null) {
      erreurs['lotId'] = inexistant('lotId');
    }

    final texteSujets = qtyAnimals.trim();
    final sujets = int.tryParse(texteSujets);
    if (texteSujets.isEmpty) {
      erreurs['qtyAnimals'] = obligatoire('qtyAnimals');
    } else if (sujets == null) {
      erreurs['qtyAnimals'] = "Le champ ${_attributs['qtyAnimals']} doit être un nombre entier.";
    } else if (sujets < 1) {
      erreurs['qtyAnimals'] = "Le champ ${_attributs['qtyAnimals']} doit être au moins égal à 1.";
    }

    final produit = productId.isEmpty ? null : await (_db.select(_db.products)..where((t) => t.id.equals(productId))).getSingleOrNull();
    if (productId.isEmpty) {
      erreurs['productId'] = obligatoire('productId');
    } else if (produit == null) {
      erreurs['productId'] = inexistant('productId');
    }

    final texteProduit = qtyProduced.trim();
    final produite = double.tryParse(texteProduit.replaceAll(',', '.'));
    if (texteProduit.isEmpty) {
      erreurs['qtyProduced'] = obligatoire('qtyProduced');
    } else if (produite == null) {
      erreurs['qtyProduced'] = 'Le champ ${_attributs['qtyProduced']} doit être un nombre.';
    } else if (produite < 0) {
      erreurs['qtyProduced'] = 'Le champ ${_attributs['qtyProduced']} doit être au moins égal à 0.';
    }

    if (date == null) erreurs['transformationDate'] = obligatoire('transformationDate');

    if (erreurs.isNotEmpty) throw TransformationRefusee(erreurs);

    final jour = _minuit(date!);

    // Exercice clos (motif R4, règle `closSeulement` de `AccountingEntryService::refusExerciceClos`) : sous la date.
    final clos = await _exercice.refus(jour, regle: RegleExercice.closSeulement);
    if (clos != null) throw TransformationRefusee({'transformationDate': clos});

    // ⚠️ Le stock du produit fini entre à la date du JOUR (`AdjustStockAction`, sans date) : un exercice clos qui couvre
    // aujourd'hui refuse la transformation, sous la même date, avec le motif R4 de CE jour-là.
    final closAujourdhui = await _exercice.refus(HeureBenin.aujourdhui(), regle: RegleExercice.closSeulement);
    if (closAujourdhui != null) throw TransformationRefusee({'transformationDate': closAujourdhui});

    final engage = (await _engages())[lot!.id] ?? 0;
    final disponible = lot.currentQuantity - engage;
    if (sujets! > disponible) {
      throw TransformationRefusee({'qtyAnimals': messageEffectifInsuffisant(disponible)});
    }

    final id = _uuid.v4();
    await _db.into(_db.transformations).insert(
      TransformationsCompanion.insert(
        id: id,
        deviceId: _deviceId,
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: HeureBenin.maintenant(),
        lotId: lot.id,
        productId: produit!.id,
        qtyAnimals: sujets,
        // `decimal(10, 2)` du serveur : le poste arrondit comme lui.
        qtyProduced: double.parse(produite!.toStringAsFixed(2)),
        transformationDate: jour,
      ),
    );

    return (
      transformation: await (_db.select(_db.transformations)..where((t) => t.id.equals(id))).getSingle(),
      produitNom: produit.name,
    );
  });
}
