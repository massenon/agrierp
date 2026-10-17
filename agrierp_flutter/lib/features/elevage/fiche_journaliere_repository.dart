import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import 'effectif_par_categorie.dart';

/// Ticket F0.95 — compte rendu de [FicheJournaliereRepository.recalculerEnCascade].
class RapportCascade {
  const RapportCascade({
    required this.totauxModifies,
    required this.categoriesModifiees,
    required this.chaine,
  });

  /// Fiches dont l'effectif total a été réécrit.
  final int totauxModifies;

  /// Fiches dont au moins une catégorie (`cat_eff_*`) a été réécrite.
  final int categoriesModifiees;

  /// Simulation de la chaîne par catégorie (refus de départ, avertissements D3/D8).
  final ResultatChaine chaine;
}

/// Tickets F0.96 / F0.97 — MOUVEMENTS DU JOUR PAR CATÉGORIE (lapins et porcs), miroir des colonnes
/// `mort_*`, `don_*` et `passage_sevre_jeune` du serveur (15.39). Emplacements : `repro`, `sevre`
/// (Sous-mères / Porcelet), `jeune` (Jeune / Porc Marchand).
///
/// ⚠️ Sans eux, une fiche du poste avec des morts ou des dons sur une bande à chaîne était REFUSÉE par le
/// serveur (D7 : « morts non ventilés par catégorie ») : la saisie restait en conflit.
class VentilationJour {
  const VentilationJour({
    this.mortRepro = 0,
    this.mortSevre = 0,
    this.mortJeune = 0,
    this.donRepro = 0,
    this.donSevre = 0,
    this.donJeune = 0,
    this.passage = 0,
  });

  final int mortRepro;
  final int mortSevre;
  final int mortJeune;
  final int donRepro;
  final int donSevre;
  final int donJeune;

  /// Passage de stade du jour (Sous-mères → Jeune, Porcelet → Porc Marchand) : un FAIT saisi.
  final int passage;

  int get totalMorts => mortRepro + mortSevre + mortJeune;
  int get totalDons => donRepro + donSevre + donJeune;
}

/// Saisie refusée avant toute écriture, avec le motif du serveur (D3 : passage supérieur à la source).
class FicheRefusee implements Exception {
  const FicheRefusee(this.motif);

  final String motif;

  @override
  String toString() => motif;
}

/// Saisie journalière du cheptel — accès local et règles de calcul.
///
/// ⚠️ LA FORMULE EST CELLE DU SERVEUR, AU CARACTÈRE PRÈS :
/// ```
/// Effectif Final = Effectif (J-1) + Achats + Nés − (Morts + Ventes + Dons)
/// ```
/// C'est aussi celle qu'affiche la maquette sous le champ calculé. La
/// réécrire « à l'équivalent » ici ferait diverger deux chiffres censés être
/// le même, sans qu'aucune erreur ne le signale.
class FicheJournaliereRepository {
  FicheJournaliereRepository({
    required AppDatabase database,
    required String deviceId,
    Uuid? uuid,
  }) : _db = database,
       // `prefer_initializing_formals` suggere `this._deviceId` : Dart
       // l'interdit sur un parametre NOMME prive.
       // ignore: prefer_initializing_formals
       _deviceId = deviceId,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final String _deviceId;
  final Uuid _uuid;

  /// Point de vérité unique du calcul — jamais recopié dans un écran.
  static int calculerEffectifFinal({
    required int effectifPrecedent,
    required int achat,
    required int ne,
    required int mort,
    required int vente,
    required int don,
    int transfertEntree = 0,
    int transfertSortie = 0,
  }) {
    // Ticket 15.46 : les transferts entre bandes du jour entrent dans la même formule (0 sans transfert).
    return effectifPrecedent +
        achat +
        ne +
        transfertEntree -
        (mort + vente + don + transfertSortie);
  }

  Future<List<LivestockLot>> bandesActives() {
    return (_db.select(_db.livestockLots)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.code)]))
        .get();
  }

  /// Fiche déjà saisie pour cette bande à cette date, s'il y en a une.
  Future<LivestockDailyEntry?> chargerJour(String lotId, DateTime jour) {
    return (_db.select(_db.livestockDailyEntries)..where(
          (t) => t.lotId.equals(lotId) & t.entryDate.equals(_minuit(jour)),
        ))
        .getSingleOrNull();
  }

  /// Effectif de la veille — base de tout le calcul.
  ///
  /// ⚠️ **LE JOUR COURANT EST EXCLU EXPLICITEMENT.** Côté serveur, l'omission
  /// de cette exclusion a produit un défaut réel : la fiche se trouvait
  /// ELLE-MÊME comme « jour précédent » et repartait de son propre effectif.
  /// Deux ventes le même jour donnaient alors −8 au lieu de 35, la seconde
  /// repartant du résultat déjà décrémenté par la première.
  ///
  /// ⚠️ **COMPARAISON SUR DES DATES À MINUIT**, jamais sur un horodatage : une
  /// heure résiduelle rendrait `<` vrai pour la journée elle-même.
  ///
  /// Sans aucune fiche antérieure, on repart de l'effectif INITIAL de la bande
  /// — pas de son effectif courant, qui a déjà encaissé les mouvements.
  Future<int> effectifPrecedent(String lotId, DateTime jour) async {
    final veille =
        await (_db.select(_db.livestockDailyEntries)
              ..where(
                (t) =>
                    t.lotId.equals(lotId) &
                    t.entryDate.isSmallerThanValue(_minuit(jour)),
              )
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.entryDate,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();

    if (veille != null) return veille.effectifFinal;

    final bande = await (_db.select(
      _db.livestockLots,
    )..where((t) => t.id.equals(lotId))).getSingleOrNull();

    return bande?.initialQuantity ?? 0;
  }

  /// Enregistre la journée et la met en file de synchronisation.
  ///
  /// ⚠️ **`vente` N'EST JAMAIS ÉCRASÉ PAR CE FORMULAIRE.** La colonne est
  /// alimentée par la caisse (le champ est en lecture seule dans la maquette),
  /// et un défaut réel côté serveur l'a remise à zéro à chaque enregistrement
  /// de la journée : la vente disparaissait de la fiche dès que l'éleveur
  /// sauvegardait après le passage en caisse. On relit donc la valeur existante
  /// au lieu de la supposer nulle.
  ///
  /// ⚠️ **UPSERT SUR (bande, date)**, jamais un insert : une fiche se corrige
  /// dans la journée, et chaque correction créerait sinon une ligne de plus.
  Future<LivestockDailyEntry> enregistrer({
    required String lotId,
    required DateTime jour,
    required int achat,
    required int ne,
    required int mort,
    required int don,
    int? ponteTotal,
    int? ponteCasses,
    double? aliment,
    double? poidsMoyen,
    VentilationJour? ventilation,
  }) async {
    final date = _minuit(jour);
    final existante = await chargerJour(lotId, date);

    // F0.96 / F0.97 — saisie VENTILÉE : les totaux sont la somme des catégories (règle du serveur).
    if (ventilation != null) {
      mort = ventilation.totalMorts;
      don = ventilation.totalDons;
    }
    final departDeduit = ventilation == null
        ? null
        : await _departAEcrire(lotId, date);
    if (ventilation != null) {
      await _refuserPassageImpossible(
        lotId,
        date,
        existante,
        ventilation,
        departDeduit,
        achat: achat,
        ne: ne,
      );
    }

    final vente = existante?.vente ?? 0;
    final effectif = calculerEffectifFinal(
      effectifPrecedent: await effectifPrecedent(lotId, date),
      achat: achat,
      ne: ne,
      mort: mort,
      vente: vente,
      don: don,
      // Ticket 15.46 : les transferts du jour restent comptés quand la fiche est ressaisie.
      transfertEntree: existante?.transfertEntree ?? 0,
      transfertSortie: existante?.transfertSortie ?? 0,
    );

    final ligne = LivestockDailyEntriesCompanion(
      id: Value(existante?.id ?? _uuid.v4()),
      deviceId: Value(_deviceId),
      // ⚠️ REPASSE EN `pending` À CHAQUE CORRECTION : une fiche déjà
      // synchronisée puis rectifiée doit repartir, sinon le serveur garde
      // l'ancienne valeur et l'écran local affiche la nouvelle — deux vérités.
      syncStatus: const Value(SyncStatus.pending),
      // ⚠️ Horodatage de la SAISIE, jamais de l'envoi : c'est lui qui arbitre
      // les conflits en dernière-écriture-gagnante.
      updatedAt: Value(DateTime.now()),
      lotId: Value(lotId),
      entryDate: Value(date),
      achat: Value(achat),
      ne: Value(ne),
      mort: Value(mort),
      vente: Value(vente),
      don: Value(don),
      effectifFinal: Value(effectif),
      ponteTotal: Value(ponteTotal),
      ponteCasses: Value(ponteCasses),
      feedQtyKg: Value(aliment),
      weightSampleAvgG: Value(poidsMoyen),
    );
    final ventilee = ventilation == null
        ? null
        : LivestockDailyEntriesCompanion(
            mortRepro: Value(ventilation.mortRepro),
            mortSevre: Value(ventilation.mortSevre),
            mortJeune: Value(ventilation.mortJeune),
            donRepro: Value(ventilation.donRepro),
            donSevre: Value(ventilation.donSevre),
            donJeune: Value(ventilation.donJeune),
            passageSevreJeune: Value(ventilation.passage),
            catDepartRepro: departDeduit == null
                ? const Value.absent()
                : Value(departDeduit.repro),
            catDepartSevre: departDeduit == null
                ? const Value.absent()
                : Value(departDeduit.sevre),
            catDepartJeune: departDeduit == null
                ? const Value.absent()
                : Value(departDeduit.jeune),
          );

    // ⚠️⚠️ F0.95 — UNE VENTILATION DEVENUE FAUSSE DEVIENT INCONNUE, jamais recopiée. Ce formulaire
    // ne saisit que les TOTAUX (la ventilation arrive avec les écrans F0.96/F0.97) ; une fiche
    // descendue du web porte peut-être `mort_*`/`don_*`. Si le nouveau total ne vaut plus leur
    // somme, les garder ferait partir à l'envoi la somme PÉRIMÉE à la place du total saisi
    // (`_ficheEnJson` envoie `mort` = somme de la ventilation) : la correction disparaîtrait sans
    // un mot. Mises à null (inconnu), elles ne partent plus : le serveur juge alors la fiche
    // (refus « ventilation incohérente » ou D7, visible en conflit) — rien n'est inventé.
    final perimees = <String, Value<int?>>{};
    if (existante != null && ventilation == null) {
      if (_ventilationContredite(
        existante.mortRepro,
        existante.mortSevre,
        existante.mortJeune,
        mort,
      )) {
        perimees.addAll({
          'mort_repro': const Value(null),
          'mort_sevre': const Value(null),
          'mort_jeune': const Value(null),
        });
      }
      if (_ventilationContredite(
        existante.donRepro,
        existante.donSevre,
        existante.donJeune,
        don,
      )) {
        perimees.addAll({
          'don_repro': const Value(null),
          'don_sevre': const Value(null),
          'don_jeune': const Value(null),
        });
      }
    }

    await _db
        .into(_db.livestockDailyEntries)
        .insertOnConflictUpdate(
          ligne.copyWith(
            mortRepro: perimees['mort_repro'] ?? const Value.absent(),
            mortSevre: perimees['mort_sevre'] ?? const Value.absent(),
            mortJeune: perimees['mort_jeune'] ?? const Value.absent(),
            donRepro: perimees['don_repro'] ?? const Value.absent(),
            donSevre: perimees['don_sevre'] ?? const Value.absent(),
            donJeune: perimees['don_jeune'] ?? const Value.absent(),
          ),
        );
    if (ventilee != null) {
      await (_db.update(_db.livestockDailyEntries)
            ..where((t) => t.lotId.equals(lotId) & t.entryDate.equals(date)))
          .write(ventilee);
    }

    // L'effectif courant de la bande suit la fiche : sans cela, l'écran de
    // caisse continuerait de proposer des sujets déjà morts ou vendus.
    //
    // 🔴→✅ CORRECTIF « EFFECTIF TOTAL VIVANT » — la bande prenait l'effectif du jour ÉDITÉ.
    // Saisir ou corriger une fiche antérieure à la dernière la ramenait à l'effectif de CE jour,
    // sans recalculer les fiches suivantes. Même défaut que les fiches web Reproducteurs /
    // Pondeuses / Escargots, corrigé des deux côtés : cascade unique (F0.95), jours suivants
    // recalculés, bande = DERNIÈRE fiche.
    await recalculerEnCascade(lotId, date);

    return (await chargerJour(lotId, date))!;
  }

  /// F0.96 / F0.97 — départ DÉDUIT du stade à écrire sur cette fiche : seulement pour une bande d'espèce
  /// suivie qui n'a pas encore de chaîne (`AvecDepartAutomatique` du web). null sinon.
  Future<EffectifCategories?> _departAEcrire(String lotId, DateTime jour) async {
    final bande = await (_db.select(
      _db.livestockLots,
    )..where((t) => t.id.equals(lotId))).getSingleOrNull();
    if (bande == null || await aUneChaine(lotId)) return null;
    return EffectifParCategorie.departDepuisStade(
      codeEspece: bande.speciesCode,
      stade: bande.stage,
      totalDebutJour: await effectifPrecedent(lotId, jour),
    );
  }

  /// D3 AVANT ÉCRITURE (comme `saveDay` du web) : un passage de stade supérieur à la catégorie source
  /// n'est pas enregistré. Lève [FicheRefusee] avec le motif du serveur.
  Future<void> _refuserPassageImpossible(
    String lotId,
    DateTime jour,
    LivestockDailyEntry? existante,
    VentilationJour v,
    EffectifCategories? departDeduit, {
    required int achat,
    required int ne,
  }) async {
    if (v.passage == 0) return;
    final bande = await (_db.select(
      _db.livestockLots,
    )..where((t) => t.id.equals(lotId))).getSingleOrNull();
    final autres = await (_db.select(
      _db.livestockDailyEntries,
    )..where((t) => t.lotId.equals(lotId))).get();
    final proposee = FicheChaine(
      id: existante?.id ?? 'proposee',
      jour: _minuit(jour),
      effectifFinal: 0,
      achat: achat,
      ne: ne,
      vente: existante?.vente ?? 0,
      mortRepro: v.mortRepro,
      mortSevre: v.mortSevre,
      mortJeune: v.mortJeune,
      donRepro: v.donRepro,
      donSevre: v.donSevre,
      donJeune: v.donJeune,
      passage: v.passage,
      departRepro: departDeduit?.repro ?? existante?.catDepartRepro,
      departSevre: departDeduit?.sevre ?? existante?.catDepartSevre,
      departJeune: departDeduit?.jeune ?? existante?.catDepartJeune,
      transfertEntreeRepro: existante?.transfertEntreeRepro ?? 0,
      transfertEntreeSevre: existante?.transfertEntreeSevre ?? 0,
      transfertEntreeJeune: existante?.transfertEntreeJeune ?? 0,
      transfertSortieRepro: existante?.transfertSortieRepro ?? 0,
      transfertSortieSevre: existante?.transfertSortieSevre ?? 0,
      transfertSortieJeune: existante?.transfertSortieJeune ?? 0,
    );
    final refus = EffectifParCategorie.refusDuPassage(
      espece: EffectifParCategorie.especeDuCode(bande?.speciesCode),
      autres: [for (final f in autres) ficheChaine(f)],
      proposee: proposee,
    );
    if (refus != null) throw FicheRefusee(refus);
  }

  /// F0.96 — catégories au DÉBUT du jour [jour] (veille de la chaîne, ou départ déduit du stade pour une
  /// bande d'espèce suivie sans chaîne), pour calculer l'aperçu du jour avec `calculerJour` — miroir de
  /// `categoriesJour` de la fiche web. null : catégories inconnues (avant le départ, départ refusé, stade
  /// sans catégorie).
  Future<EffectifCategories?> veilleParCategorie(
    String lotId,
    DateTime jour,
  ) async {
    final bande = await (_db.select(
      _db.livestockLots,
    )..where((t) => t.id.equals(lotId))).getSingleOrNull();
    if (bande == null) return null;
    final fiches = await (_db.select(
      _db.livestockDailyEntries,
    )..where((t) => t.lotId.equals(lotId))).get();
    final etat = EffectifParCategorie.etatPourJour(
      espece: EffectifParCategorie.especeDuCode(bande.speciesCode),
      fiches: [for (final f in fiches) ficheChaine(f)],
      initialQuantity: bande.initialQuantity,
      jour: jour,
    );
    if (etat.mode == 'chaine') return etat.veille;
    if (etat.mode != 'sans_chaine') return null;
    return EffectifParCategorie.departDepuisStade(
      codeEspece: bande.speciesCode,
      stade: bande.stage,
      totalDebutJour: await effectifPrecedent(lotId, jour),
    );
  }

  /// Vrai si les trois catégories sont connues et que leur somme contredit [total].
  static bool _ventilationContredite(int? a, int? b, int? c, int total) =>
      a != null && b != null && c != null && a + b + c != total;

  /// Lecture d'une fiche par la chaîne par catégorie (aucune règle ici : simple transposition).
  static FicheChaine ficheChaine(LivestockDailyEntry f) => FicheChaine(
    id: f.id,
    jour: _minuit(f.entryDate),
    effectifFinal: f.effectifFinal,
    achat: f.achat,
    ne: f.ne,
    vente: f.vente,
    mortRepro: f.mortRepro,
    mortSevre: f.mortSevre,
    mortJeune: f.mortJeune,
    donRepro: f.donRepro,
    donSevre: f.donSevre,
    donJeune: f.donJeune,
    passage: f.passageSevreJeune,
    departRepro: f.catDepartRepro,
    departSevre: f.catDepartSevre,
    departJeune: f.catDepartJeune,
    catEffRepro: f.catEffRepro,
    catEffSevre: f.catEffSevre,
    catEffJeune: f.catEffJeune,
    transfertEntreeRepro: f.transfertEntreeRepro,
    transfertEntreeSevre: f.transfertEntreeSevre,
    transfertEntreeJeune: f.transfertEntreeJeune,
    transfertSortieRepro: f.transfertSortieRepro,
    transfertSortieSevre: f.transfertSortieSevre,
    transfertSortieJeune: f.transfertSortieJeune,
  );

  /// Une bande a une chaîne exploitable : espèce suivie (lapins, porcs) ET une de ses fiches porte
  /// un départ COMPLET — miroir de `EffectifParCategorieService::aUneChaine`.
  Future<bool> aUneChaine(String lotId) async {
    final bande = await (_db.select(
      _db.livestockLots,
    )..where((t) => t.id.equals(lotId))).getSingleOrNull();
    if (bande == null ||
        EffectifParCategorie.especeDuCode(bande.speciesCode) == null) {
      return false;
    }
    final tete =
        await (_db.select(_db.livestockDailyEntries)
              ..where(
                (t) => Expression.and([
                  t.lotId.equals(lotId),
                  t.catDepartRepro.isNotNull(),
                  t.catDepartSevre.isNotNull(),
                  t.catDepartJeune.isNotNull(),
                ]),
              )
              ..limit(1))
            .getSingleOrNull();
    return tete != null;
  }

  /// 🔴→✅ TICKET F0.95 — LA CASCADE LOCALE UNIQUE (caisse aujourd'hui, fiches F0.96/F0.97).
  ///
  /// Miroir de `RecordSaleOnFicheElevageAction::recalculerEnCascade` (15.31, 15.40) suivi de
  /// `EffectifParCategorieService::recalculerChaine` (15.39), dans UNE transaction :
  ///  1. TOTAUX : point de départ = effectif final STOCKÉ de la fiche du jour [apres] (à défaut,
  ///     celui de la dernière fiche antérieure, sinon l'effectif initial) ; les fiches
  ///     STRICTEMENT postérieures sont recalculées dans l'ordre des jours, bornées à 0
  ///     ([EffectifParCategorie.effectifFinal], 14.63) ; seule une valeur fausse est réécrite ;
  ///  2. BANDE : `current_quantity` = effectif de la DERNIÈRE fiche (borné à 0), écrit seulement
  ///     s'il change ;
  ///  3. CATÉGORIES : chaîne recalculée depuis le départ et les mouvements stockés ; départ
  ///     incohérent = rien d'écrit (motif dans le rapport) ; bande sans chaîne = rien d'écrit.
  ///
  /// ⚠️ Les mouvements saisis ne sont JAMAIS touchés, ni le statut de synchronisation, ni
  /// l'horodatage : totaux et catégories sont DÉRIVÉS, le serveur les recalcule de son côté et
  /// ne les reprend jamais du poste. IDEMPOTENTE : un second passage n'écrit rien.
  Future<RapportCascade> recalculerEnCascade(
    String lotId,
    DateTime apres,
  ) => _db.transaction(() async {
    final jour = _minuit(apres);
    final bande = await (_db.select(
      _db.livestockLots,
    )..where((t) => t.id.equals(lotId))).getSingleOrNull();

    var fiches =
        await (_db.select(_db.livestockDailyEntries)
              ..where((t) => t.lotId.equals(lotId))
              ..orderBy([(t) => OrderingTerm(expression: t.entryDate)]))
            .get();

    // (1) Totaux.
    final duJour = fiches.where((f) => _minuit(f.entryDate) == jour);
    var courant = duJour.isNotEmpty
        ? duJour.first.effectifFinal
        : await effectifPrecedent(lotId, jour);
    var totauxModifies = 0;
    for (final f in fiches) {
      if (!_minuit(f.entryDate).isAfter(jour)) continue;
      final juste = EffectifParCategorie.effectifFinal(
        precedent: courant,
        achat: f.achat,
        ne: f.ne,
        mort: f.mort,
        vente: f.vente,
        don: f.don,
        transfertEntree: f.transfertEntree,
        transfertSortie: f.transfertSortie,
      );
      if (juste != f.effectifFinal) {
        await (_db.update(_db.livestockDailyEntries)
              ..where((t) => t.id.equals(f.id)))
            .write(LivestockDailyEntriesCompanion(effectifFinal: Value(juste)));
        totauxModifies++;
      }
      courant = juste;
    }

    // (2) La bande suit la DERNIÈRE fiche.
    if (fiches.isNotEmpty && bande != null) {
      fiches =
          await (_db.select(_db.livestockDailyEntries)
                ..where((t) => t.lotId.equals(lotId))
                ..orderBy([(t) => OrderingTerm(expression: t.entryDate)]))
              .get();
      final cible = fiches.last.effectifFinal < 0 ? 0 : fiches.last.effectifFinal;
      if (bande.currentQuantity != cible) {
        await (_db.update(_db.livestockLots)..where((t) => t.id.equals(lotId)))
            .write(LivestockLotsCompanion(currentQuantity: Value(cible)));
      }
    }

    // (3) Catégories.
    final chaine = EffectifParCategorie.simulerChaine(
      espece: EffectifParCategorie.especeDuCode(bande?.speciesCode),
      fiches: [for (final f in fiches) ficheChaine(f)],
      initialQuantity: bande?.initialQuantity ?? 0,
    );
    var categoriesModifiees = 0;
    if (chaine.chaine && chaine.refus == null) {
      for (final f in fiches) {
        final r = chaine.resultats[f.id];
        if (r == null) continue;
        if (r.repro != f.catEffRepro ||
            r.sevre != f.catEffSevre ||
            r.jeune != f.catEffJeune) {
          await (_db.update(
            _db.livestockDailyEntries,
          )..where((t) => t.id.equals(f.id))).write(
            LivestockDailyEntriesCompanion(
              catEffRepro: Value(r.repro),
              catEffSevre: Value(r.sevre),
              catEffJeune: Value(r.jeune),
            ),
          );
          categoriesModifiees++;
        }
      }
    }

    return RapportCascade(
      totauxModifies: totauxModifies,
      categoriesModifiees: categoriesModifiees,
      chaine: chaine,
    );
  });

  /// Rations normatives d'une espèce, telles que le serveur les sert.
  ///
  /// ⚠️ JAMAIS DE GRAMMAGE CODÉ EN DUR. Ces valeurs sont éditables depuis
  /// l'écran Paramètres > Élevage : les figer ici ferait diverger la provende
  /// calculée le jour d'une correction, sans le moindre signal.
  Future<List<FeedRationStandard>> rations(String codeEspece) {
    return (_db.select(_db.feedRationStandards)
          ..where((t) => t.speciesCode.equals(codeEspece))
          ..orderBy([(t) => OrderingTerm(expression: t.stageLabel)]))
        .get();
  }

  /// Fiches du mois pour une bande, du 1er au dernier jour, par date.
  ///
  /// ⚠️ TOUTES LES JOURNÉES SAISIES, pas seulement celles de ce poste : le
  /// tableau mensuel de la maquette montre le mois entier, et une journée
  /// enregistrée sur le web puis redescendue doit y figurer.
  Future<List<LivestockDailyEntry>> fichesDuMois(
    String lotId, {
    DateTime? quand,
  }) {
    final maintenant = quand ?? DateTime.now();
    final debut = DateTime(maintenant.year, maintenant.month, 1);
    final finExclue = DateTime(maintenant.year, maintenant.month + 1, 1);

    return (_db.select(_db.livestockDailyEntries)
          ..where(
            (t) =>
                t.lotId.equals(lotId) &
                t.entryDate.isBiggerOrEqualValue(debut) &
                t.entryDate.isSmallerThanValue(finExclue),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.entryDate)]))
        .get();
  }

  /// Indicateurs du mois affichés en tête de fiche.
  ///
  /// ⚠️ MÊMES FORMULES QUE LE SERVEUR (`FicheLapins::getKpisProperty`) :
  /// effectif = somme des `current_quantity` des bandes ; naissances = somme
  /// des `ne` du mois ; taux de mortalité = morts du mois ÷ somme des effectifs
  /// de DÉPART de chaque journée — pas ÷ l'effectif courant, qui donnerait un
  /// taux différent du web pour les mêmes données.
  ///
  /// ⚠️ **« GÉNITEURS (M/F) » N'EST PAS CALCULABLE ICI** : le serveur le tire de
  /// `effectif_m` / `effectif_f`, deux colonnes que le contrat de
  /// synchronisation ne descend pas. L'écran affiche un tiret et le dit, plutôt
  /// qu'un zéro qui se lirait « plus aucun géniteur ».
  Future<({int effectif, int naissances, double? tauxMortalite})>
  indicateursDuMois({
    required List<LivestockLot> bandes,
    DateTime? quand,
  }) async {
    final maintenant = quand ?? DateTime.now();
    final debut = DateTime(maintenant.year, maintenant.month, 1);
    final finExclue = DateTime(maintenant.year, maintenant.month + 1, 1);

    final effectif = bandes.fold<int>(0, (t, b) => t + b.currentQuantity);

    if (bandes.isEmpty) {
      return (effectif: 0, naissances: 0, tauxMortalite: null);
    }

    final ids = bandes.map((b) => b.id).toList();

    final fiches =
        await (_db.select(_db.livestockDailyEntries)..where(
              (t) =>
                  t.lotId.isIn(ids) &
                  t.entryDate.isBiggerOrEqualValue(debut) &
                  t.entryDate.isSmallerThanValue(finExclue),
            ))
            .get();

    var naissances = 0;
    var morts = 0;
    var effectifsDepart = 0;

    for (final fiche in fiches) {
      naissances += fiche.ne;
      morts += fiche.mort;
      effectifsDepart += await effectifPrecedent(fiche.lotId, fiche.entryDate);
    }

    return (
      effectif: effectif,
      naissances: naissances,
      tauxMortalite: effectifsDepart > 0
          ? (morts / effectifsDepart) * 100
          : null,
    );
  }

  /// Provende servie pour une catégorie : effectif × ration, en grammes.
  ///
  /// ⚠️ LE CALCUL RESTE EN GRAMMES jusqu'au total. Convertir chaque ligne en
  /// kilos puis additionner accumulerait les arrondis : sur une dizaine de
  /// catégories, l'écart devient visible au stock.
  static double provendeGrammes({
    required int effectif,
    required double rationGParJour,
  }) {
    if (effectif <= 0 || rationGParJour <= 0) return 0;
    return effectif * rationGParJour;
  }

  /// Poids moyen constaté : poids total pesé ÷ taille de l'échantillon.
  ///
  /// La maquette (`computePoidsMoyenLapin`) prend l'EFFECTIF FINAL comme
  /// taille d'échantillon — le champ est verrouillé et annoté « Auto =
  /// Effectif Final ».
  ///
  /// ⚠️ `null` PLUTÔT QUE ZÉRO quand rien n'a été pesé ou que l'effectif est
  /// nul. Le prototype affiche « 0 g » dans ce cas, ce qui se lit comme un
  /// cheptel sans poids — alors qu'il s'agit d'une absence de mesure. La
  /// distinction compte : un poids moyen de zéro enregistré fausserait le
  /// suivi de croissance, une absence de mesure ne fausse rien.
  static double? poidsMoyen({
    required double poidsTotalG,
    required int tailleEchantillon,
  }) {
    if (poidsTotalG <= 0 || tailleEchantillon <= 0) return null;
    return (poidsTotalG / tailleEchantillon).roundToDouble();
  }

  /// Taux de mortalité du jour, en pourcentage de l'effectif de départ.
  ///
  /// ⚠️ `null` et non `0` quand l'effectif de départ est nul : sans cheptel,
  /// le taux n'existe pas — l'afficher à 0 % ferait lire « aucune perte ».
  static double? tauxMortalite({
    required int effectifPrecedent,
    required int mort,
  }) {
    if (effectifPrecedent <= 0) return null;
    return (mort / effectifPrecedent) * 100;
  }

  /// Les dates sont des JOURS : toute heure résiduelle fausserait à la fois
  /// l'unicité (bande, date) et la recherche de la veille.
  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);
}
