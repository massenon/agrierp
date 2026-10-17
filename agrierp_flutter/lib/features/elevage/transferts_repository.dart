import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import 'effectif_par_categorie.dart';
import 'fiche_journaliere_repository.dart';

/// Refus d'un transfert, avec son motif tel que l'écran l'affiche (mêmes phrases que le serveur).
class TransfertRefuse implements Exception {
  const TransfertRefuse(this.motif);

  final String motif;

  @override
  String toString() => motif;
}

/// Ticket 15.46 — TRANSFERTS ENTRE BANDES SUR LE POSTE, miroir de `TransferBetweenLotsAction`.
///
/// Hors ligne, le poste enregistre le transfert (`pending`), le reporte sur la fiche du jour des deux
/// bandes et recalcule la cascade locale, pour que les effectifs affichés soient justes tout de suite.
/// À l'envoi, le serveur le REJOUE avec ses propres contrôles : en cas de refus (une saisie faite
/// ailleurs entre-temps), le transfert passe en conflit avec son motif.
///
/// ⚠️ Mêmes contrôles que le serveur, jamais d'effectif inventé : bandes distinctes, même espèce, non
/// archivées ; date ni future ni antérieure à la création d'une bande ; catégorie obligatoire pour
/// lapins et porcs ; effectif suffisant le jour même ET chaque jour suivant ; une constitution est
/// datée du jour de création de la bande cible et ne dépasse pas son effectif initial.
class TransfertsRepository {
  TransfertsRepository({
    required AppDatabase database,
    required String deviceId,
    FicheJournaliereRepository? fiches,
  }) : _db = database,
       _deviceId = deviceId,
       _fiches =
           fiches ??
           FicheJournaliereRepository(database: database, deviceId: deviceId);

  final AppDatabase _db;
  final String _deviceId;
  final FicheJournaliereRepository _fiches;
  static const _uuid = Uuid();

  static const categories = ['repro', 'sevre', 'jeune'];

  /// Stade de bande → catégorie (`EffectifParCategorieService::categorieDuStade`).
  static String? categorieDuStade(String? stade) =>
      EffectifParCategorie.categorieDuStade(stade);

  /// Libellés des catégories d'une espèce (glossaire du 17/10/2026 pour les lapins).
  static Map<String, String> libellesCategories(String? codeEspece) =>
      switch (EffectifParCategorie.especeDuCode(codeEspece)) {
        EffectifParCategorie.lapins => const {
          'repro': 'Reproducteur',
          'sevre': 'Sous-mères',
          'jeune': 'Jeune',
        },
        EffectifParCategorie.porcs => const {
          'repro': 'Reproducteur',
          'sevre': 'Porcelet',
          'jeune': 'Porc Marchand',
        },
        _ => const {},
      };

  Future<List<LivestockLot>> bandes() => (_db.select(_db.livestockLots)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.code)]))
      .get();

  Future<List<LivestockTransfer>> transferts() => (_db.select(_db.livestockTransfers)
        ..orderBy([
          (t) => OrderingTerm.desc(t.transferDate),
          (t) => OrderingTerm.desc(t.updatedAt),
        ])
        ..limit(100))
      .get();

  /// Bandes vivantes sans origine, précédées par une autre bande de la même espèce : seules celles-là
  /// peuvent être issues d'une autre. Le rattachement reste une décision de l'exploitant.
  Future<List<LivestockLot>> bandesARattacher() async {
    final lots = await bandes();
    return lots.where((lot) {
      final creee = lot.createdDate;
      if (lot.lotSourceId != null || creee == null) return false;
      return lots.any(
        (autre) =>
            autre.id != lot.id &&
            autre.speciesId == lot.speciesId &&
            autre.createdDate != null &&
            autre.createdDate!.isBefore(creee),
      );
    }).toList();
  }

  Future<LivestockTransfer> creer({
    required String sourceLotId,
    required String targetLotId,
    required DateTime jour,
    required int quantite,
    String? categorie,
    bool constitution = false,
    String? motif,
  }) => _db.transaction(() async {
    final date = _minuit(jour);
    final source = await _bande(sourceLotId);
    final cible = await _bande(targetLotId);

    await _verifier(source, cible, date, quantite, categorie, constitution);

    final transfert = LivestockTransfersCompanion.insert(
      id: _uuid.v4(),
      deviceId: _deviceId,
      sourceLotId: source!.id,
      targetLotId: cible!.id,
      transferDate: date,
      quantity: quantite,
      categorie: Value(categorie),
      constitution: Value(constitution),
      motif: Value(motif == null || motif.trim().isEmpty ? null : motif.trim()),
      updatedAt: DateTime.now(),
    );
    await _db.into(_db.livestockTransfers).insert(transfert);

    if (constitution && cible.lotSourceId == null) {
      await (_db.update(_db.livestockLots)..where((t) => t.id.equals(cible.id)))
          .write(LivestockLotsCompanion(lotSourceId: Value(source.id)));
    }

    await reporterSurFiche(source.id, date);
    await reporterSurFiche(cible.id, date);

    return (await (_db.select(
      _db.livestockTransfers,
    )..where((t) => t.id.equals(transfert.id.value))).getSingle());
  });

  /// Annule un transfert (jamais supprimé) : les deux bandes sont recalculées, l'annulation part au serveur.
  Future<void> annuler(String id) => _db.transaction(() async {
    final t = await (_db.select(
      _db.livestockTransfers,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (t == null || !t.isActive) return;

    final date = _minuit(t.transferDate);
    if (!t.constitution) {
      final cible = await _bande(t.targetLotId);
      await _verifierDisponible(cible!, date, t.quantity, t.categorie, 'la bande ${cible.code}');
    }

    await (_db.update(_db.livestockTransfers)..where((x) => x.id.equals(id))).write(
      LivestockTransfersCompanion(
        isActive: const Value(false),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (t.constitution) {
      final autres = await (_db.select(_db.livestockTransfers)
            ..where(
              (x) => Expression.and([
                x.targetLotId.equals(t.targetLotId),
                x.constitution.equals(true),
                x.isActive.equals(true),
              ]),
            ))
          .get();
      if (autres.isEmpty) {
        await (_db.update(_db.livestockLots)
              ..where((x) => x.id.equals(t.targetLotId)))
            .write(const LivestockLotsCompanion(lotSourceId: Value(null)));
      }
    }

    await reporterSurFiche(t.sourceLotId, date);
    await reporterSurFiche(t.targetLotId, date);
  });

  /// Reporte sur la fiche (bande, jour) la somme des transferts ACTIFS du jour, puis recalcule l'effectif
  /// du jour et la cascade — miroir de `TransferBetweenLotsAction::reporterSurFiche`.
  ///
  /// ⚠️ Une fiche CRÉÉE pour le transfert part au serveur (`pending`) : le serveur la reçoit avant le
  /// transfert et la retrouve, au lieu d'en créer une seconde sous un autre identifiant.
  Future<void> reporterSurFiche(String lotId, DateTime jour) async {
    final date = _minuit(jour);
    final actifs = await (_db.select(
      _db.livestockTransfers,
    )..where((t) => t.isActive.equals(true) & t.transferDate.equals(date))).get();

    final sorties = actifs.where((t) => t.sourceLotId == lotId);
    final entrees = actifs.where((t) => t.targetLotId == lotId && !t.constitution);
    int somme(Iterable<LivestockTransfer> l, [String? cat]) => l
        .where((t) => cat == null || t.categorie == cat)
        .fold(0, (s, t) => s + t.quantity);

    final colonnes = LivestockDailyEntriesCompanion(
      transfertEntree: Value(somme(entrees)),
      transfertSortie: Value(somme(sorties)),
      transfertEntreeRepro: Value(somme(entrees, 'repro')),
      transfertEntreeSevre: Value(somme(entrees, 'sevre')),
      transfertEntreeJeune: Value(somme(entrees, 'jeune')),
      transfertSortieRepro: Value(somme(sorties, 'repro')),
      transfertSortieSevre: Value(somme(sorties, 'sevre')),
      transfertSortieJeune: Value(somme(sorties, 'jeune')),
    );

    var fiche = await _fiches.chargerJour(lotId, date);
    if (fiche == null) {
      if (somme(entrees) == 0 && somme(sorties) == 0) return;

      final bande = await _bande(lotId);
      final precedent = await _fiches.effectifPrecedent(lotId, date);
      var nouvelle = LivestockDailyEntriesCompanion.insert(
        id: _uuid.v4(),
        deviceId: _deviceId,
        lotId: lotId,
        entryDate: date,
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: DateTime.now(),
      );
      if (EffectifParCategorie.especeDuCode(bande?.speciesCode) != null) {
        nouvelle = nouvelle.copyWith(
          mortRepro: const Value(0),
          mortSevre: const Value(0),
          mortJeune: const Value(0),
          donRepro: const Value(0),
          donSevre: const Value(0),
          donJeune: const Value(0),
          passageSevreJeune: const Value(0),
        );
        // Première fiche d'une bande à catégories : départ DÉDUIT du stade (`departDepuisStade`).
        final cat = categorieDuStade(bande?.stage);
        if (cat != null && !await _fiches.aUneChaine(lotId)) {
          nouvelle = nouvelle.copyWith(
            catDepartRepro: Value(cat == 'repro' ? precedent : 0),
            catDepartSevre: Value(cat == 'sevre' ? precedent : 0),
            catDepartJeune: Value(cat == 'jeune' ? precedent : 0),
          );
        }
      }
      await _db.into(_db.livestockDailyEntries).insert(nouvelle);
      fiche = await _fiches.chargerJour(lotId, date);
    }

    await (_db.update(_db.livestockDailyEntries)..where((t) => t.id.equals(fiche!.id)))
        .write(colonnes);
    final ajour = (await _fiches.chargerJour(lotId, date))!;
    final effectif = EffectifParCategorie.effectifFinal(
      precedent: await _fiches.effectifPrecedent(lotId, date),
      achat: ajour.achat,
      ne: ajour.ne,
      mort: ajour.mort,
      vente: ajour.vente,
      don: ajour.don,
      transfertEntree: ajour.transfertEntree,
      transfertSortie: ajour.transfertSortie,
    );
    await (_db.update(_db.livestockDailyEntries)..where((t) => t.id.equals(ajour.id)))
        .write(LivestockDailyEntriesCompanion(effectifFinal: Value(effectif)));

    await _fiches.recalculerEnCascade(lotId, date);
  }

  Future<LivestockLot?> _bande(String id) => (_db.select(
    _db.livestockLots,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> _verifier(
    LivestockLot? source,
    LivestockLot? cible,
    DateTime date,
    int quantite,
    String? categorie,
    bool constitution,
  ) async {
    Never refus(String motif) => throw TransfertRefuse(motif);

    if (source == null || cible == null) {
      refus('Bande source ou bande cible introuvable.');
    }
    if (source.id == cible.id) {
      refus('La bande source et la bande cible doivent être différentes.');
    }
    if (source.speciesId != cible.speciesId) {
      refus(
        'Les deux bandes doivent être de la même espèce (${source.code} et ${cible.code} ne le sont pas).',
      );
    }
    if (!source.isActive || !cible.isActive) {
      refus('Une bande archivée ne peut ni céder ni recevoir de sujets.');
    }
    if (quantite < 1) {
      refus('Le nombre de sujets transférés doit être au moins 1.');
    }
    if (date.isAfter(_minuit(DateTime.now()))) {
      refus('Un transfert ne peut pas être daté dans le futur.');
    }
    for (final lot in [source, cible]) {
      final creee = lot.createdDate;
      if (creee != null && date.isBefore(_minuit(creee))) {
        refus(
          'Le transfert est antérieur à la création de la bande ${lot.code} (${_fr(creee)}).',
        );
      }
    }

    final aCategories =
        EffectifParCategorie.especeDuCode(source.speciesCode) != null;
    if (aCategories && !categories.contains(categorie)) {
      refus('Lapins et porcs : précisez la catégorie des sujets transférés.');
    }
    if (!aCategories && categorie != null) {
      refus(
        "Cette espèce n'est pas suivie par catégorie : aucune catégorie ne doit être choisie.",
      );
    }

    if (constitution) {
      final creee = cible.createdDate;
      if (creee == null || _minuit(creee) != date) {
        refus(
          'Une constitution de bande est datée du jour de création de la bande cible (${creee == null ? 'inconnu' : _fr(creee)}).',
        );
      }
      final deja = (await (_db.select(_db.livestockTransfers)
                ..where(
                  (t) => Expression.and([
                    t.targetLotId.equals(cible.id),
                    t.constitution.equals(true),
                    t.isActive.equals(true),
                  ]),
                ))
              .get())
          .fold(0, (s, t) => s + t.quantity);
      if (deja + quantite > cible.initialQuantity) {
        refus(
          'La bande ${cible.code} a été créée avec ${cible.initialQuantity} sujet(s) ; '
          '$deja sont déjà rattachés à leur bande d\'origine. Impossible d\'en rattacher $quantite de plus.',
        );
      }
    }

    await _verifierDisponible(
      source,
      date,
      quantite,
      categorie,
      'la bande source ${source.code}',
    );
  }

  /// La bande compte-t-elle au moins [quantite] sujets (et dans la catégorie, si elle est connue) à la fin
  /// du jour et chaque jour suivant ? Sinon le retrait rendrait un effectif négatif.
  Future<void> _verifierDisponible(
    LivestockLot lot,
    DateTime date,
    int quantite,
    String? categorie,
    String libelle,
  ) async {
    final fiches = (await (_db.select(_db.livestockDailyEntries)
              ..where((t) => t.lotId.equals(lot.id))
              ..orderBy([(t) => OrderingTerm(expression: t.entryDate)]))
            .get())
        .where((f) => !_minuit(f.entryDate).isBefore(date))
        .toList();
    final duJour = fiches.where((f) => _minuit(f.entryDate) == date);

    final points = <(DateTime, int)>[
      if (duJour.isEmpty) (date, await _fiches.effectifPrecedent(lot.id, date)),
      for (final f in fiches) (_minuit(f.entryDate), f.effectifFinal),
    ];
    for (final (jour, effectif) in points) {
      if (effectif < quantite) {
        throw TransfertRefuse(
          'Transfert refusé : $libelle ne compte que $effectif sujet(s) le ${_fr(jour)}, '
          'moins que les $quantite à transférer.',
        );
      }
    }

    if (categorie == null) return;
    final libelles = libellesCategories(lot.speciesCode);
    int? cat(LivestockDailyEntry f) => switch (categorie) {
      'repro' => f.catEffRepro,
      'sevre' => f.catEffSevre,
      _ => f.catEffJeune,
    };

    final parJour = <(DateTime, int)>[];
    if (duJour.isEmpty) {
      final veille = (await (_db.select(_db.livestockDailyEntries)
                ..where((t) => t.lotId.equals(lot.id) & t.entryDate.isSmallerThanValue(date))
                ..orderBy([(t) => OrderingTerm.desc(t.entryDate)])
                ..limit(1))
              .getSingleOrNull());
      final v = veille == null ? null : cat(veille);
      if (v != null) parJour.add((date, v));
    }
    for (final f in fiches) {
      final v = cat(f);
      if (v != null) parJour.add((_minuit(f.entryDate), v));
    }
    for (final (jour, effectif) in parJour) {
      if (effectif < quantite) {
        throw TransfertRefuse(
          'Transfert refusé : $libelle ne compte que $effectif ${libelles[categorie] ?? categorie} '
          'le ${_fr(jour)}, moins que les $quantite à transférer.',
        );
      }
    }
  }

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _fr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
