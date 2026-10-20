import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/sync/gestes_importants.dart';
import '../../core/temps/heure_benin.dart';
import '../elevage/fiche_journaliere_repository.dart';

/// Ligne du panier de caisse.
class LignePanier {
  const LignePanier({
    required this.produit,
    required this.quantite,
    required this.montant,
    this.lotId,
  });

  final Product produit;
  final int quantite;

  /// ⚠️ MONTANT DE LA LIGNE, source de vérité. Le prix unitaire n'est qu'un
  /// affichage reconstitué (`montant ÷ quantité`), jamais l'inverse : les
  /// produits en fourchette se négocient au montant, et repartir du prix
  /// unitaire arrondi ferait dériver le total de la vente.
  final double montant;

  /// Bande d'origine, obligatoire pour tout produit lié à une espèce.
  final String? lotId;

  double get prixUnitaire => quantite > 0 ? montant / quantite : 0;
}

/// Refus opposé à une vente, avec son motif.
class VenteRefusee implements Exception {
  const VenteRefusee(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Caisse hors ligne — enregistrement local d'une vente et de ses effets.
///
/// ⚠️ **LES QUATRE EFFETS SONT REPRODUITS LOCALEMENT**, exactement comme le
/// serveur les rejoue à la synchronisation (ticket 14.53) : vente, décrément
/// du stock, mise à jour de la fiche d'élevage, mise en file. Ne persister que
/// la vente laisserait le comptoir proposer des sujets déjà vendus et
/// afficherait un effectif périmé sur la fiche jusqu'au prochain tirage — sur
/// un poste qui peut rester des jours hors ligne.
///
/// ⚠️ L'écriture comptable et l'encaissement, eux, restent au SERVEUR : le
/// poste ne tient pas de grand livre. C'est le seul des quatre effets qui n'a
/// pas d'équivalent local, et c'est voulu — deux grands livres à réconcilier
/// seraient pires que pas de grand livre local du tout.
class CaisseRepository {
  CaisseRepository({
    required AppDatabase database,
    required String deviceId,
    Uuid? uuid,
    DateTime Function()? maintenant,
    GestesImportants? gestes,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _deviceId = deviceId,
       _uuid = uuid ?? const Uuid(),
       maintenant = maintenant ?? HeureBenin.maintenant,
       // ignore: prefer_initializing_formals
       _gestes = gestes;

  final AppDatabase _db;
  final String _deviceId;
  final Uuid _uuid;

  /// Ticket S-T3 — une vente enregistrée est un geste important : la synchronisation automatique la pousse
  /// après un court délai d'agrégation. `null` : aucun signal.
  final GestesImportants? _gestes;

  /// Horloge du poste — injectable pour les tests (F0.89). C'est elle qui dit « aujourd'hui » à
  /// l'écran, aux bornes du calendrier et à l'horodatage de la saisie : une seule source.
  final DateTime Function() maintenant;

  /// Aujourd'hui, à minuit.
  DateTime aujourdhui() => _minuit(maintenant());

  /// Ticket EX6 — le point de passage commun de l'exercice d'une saisie, à l'horloge de cette caisse.
  ExerciceDeSaisie get _exercice => ExerciceDeSaisie(_db, maintenant: maintenant);

  /// 🔴→✅ TICKET F0.89 — LA DATE CHOISIE EST-ELLE ACCEPTABLE ? `null` = oui, sinon le motif.
  ///
  /// Copie des contrôles de `VerifySaleDateAction` (serveur, 15.30) que le poste PEUT juger,
  /// avec LEURS MESSAGES mot pour mot (un caissier lit le même refus au poste et sur le web) :
  ///  1. date future → refus ;
  ///  2. exercice : la règle de `AccountingEntryService::exerciceOuvertPour` (un exercice dont
  ///     les bornes couvrent le jour, et il doit être `ouvert`) → « aucun exercice ne couvre »
  ///     ou « est clos ». Une date antérieure au plus ancien exercice OUVERT tombe forcément
  ///     dans l'un des deux cas.
  ///
  /// ⚠️ **AUCUN EXERCICE CONNU AU POSTE = AUCUN BLOCAGE** : un poste qui n'a pas encore tiré
  /// `fiscal_years` ne doit pas arrêter le comptoir ; le serveur jugera à l'envoi (rejet motivé,
  /// la vente passe alors en `conflict`).
  ///
  /// ⚠️ **LE MOIS CLÔTURÉ N'EST PAS JUGÉ ICI** : les clôtures périodiques ne descendent pas au
  /// poste. Seul le serveur peut le refuser — c'est le seul motif que le caissier ne découvre
  /// qu'à la synchronisation.
  ///
  /// ⚠️ **LA VENTE DU JOUR NE SUBIT AUCUN GARDE**, comme au POS web (15.32) : le comptoir ne
  /// s'arrête pas pour un exercice que le poste croit clos. (Le serveur, lui, juge toute vente
  /// qui porte `sold_at` — voir le ticket F0.89, constat.)
  Future<String?> refusDeDate(DateTime jour) async {
    final j = _minuit(jour);
    final auj = aujourdhui();

    if (j.isAfter(auj)) {
      return 'Vente refusée : la date du ${_jourFr(j)} est dans le futur.';
    }
    if (j == auj) return null;

    // 🔴→✅ Ticket EX6 (EF7) — la règle de l'exercice vit dans UN point de passage, partagé par tous les écrans de
    // saisie du poste : `ExerciceDeSaisie` (règle `exerciceOuvertPour` du serveur, filet R2 compris, aucun exercice
    // connu = aucun blocage, messages R4 de `NoOpenFiscalYearException` / `ClosedFiscalYearException`), précédés de
    // « Vente refusée : » (`VerifySaleDateAction::prefixe`).
    final motif = await _exercice.refus(j);
    return motif == null ? null : ExerciceDeSaisie.prefixeVente(motif);
  }

  /// Bornes INDICATIVES du calendrier (comme `PosInterface::getDateMin/MaxProperty`, 15.32) :
  /// `premier` = début du plus ancien exercice OUVERT connu (nul si aucun), `dernier` =
  /// aujourd'hui. [refusDeDate] reste le juge ; le serveur re-juge tout.
  ///
  /// ⚠️ La borne haute n'est PAS rabattue sur la fin de l'exercice ouvert (le web le fait) : le
  /// calendrier s'ouvre sur aujourd'hui, qui doit rester sélectionnable ; une date postérieure
  /// à l'exercice est refusée par [refusDeDate] avec son motif.
  Future<({DateTime? premier, DateTime dernier})> bornesDateVente() async =>
      (premier: await _exercice.premierJour(), dernier: aujourdhui());

  Future<List<Product>> catalogue() {
    return (_db.select(_db.products)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
  }

  /// Categories du catalogue, servies par le serveur.
  ///
  /// ⚠️ SEULES LES CATEGORIES ACTIVES : une categorie archivee cote serveur ne
  /// doit plus filtrer, sinon le caissier choisit un filtre qui ne rend rien.
  Future<List<ProductCategory>> categories() {
    return (_db.select(_db.productCategories)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.label)]))
        .get();
  }

  Future<List<LivestockLot>> bandesDe(String speciesId) {
    return (_db.select(_db.livestockLots)
          ..where(
            (t) => t.speciesId.equals(speciesId) & t.isActive.equals(true),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.code)]))
        .get();
  }

  /// ⚠️⚠️ BLOCAGE SANITAIRE. Une bande sous délai d'attente après traitement ne
  /// vend RIEN : la viande porterait des résidus d'antibiotiques. C'est le seul
  /// refus dur de cette caisse — le stock, lui, alerte sans bloquer.
  Future<VeterinaryWithdrawalPeriod?> remanenceActive(String lotId) async {
    return (_db.select(_db.veterinaryWithdrawalPeriods)
          ..where(
            (t) =>
                t.lotId.equals(lotId) &
                t.endDate.isBiggerOrEqualValue(aujourdhui()),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// Enregistre la vente et tous ses effets locaux, en une transaction.
  ///
  /// ⚠️ **TOUT OU RIEN.** Une vente enregistrée dont le stock n'aurait pas
  /// bougé — parce qu'une écriture a échoué en cours de route — laisserait la
  /// caisse et l'inventaire en désaccord sans que rien ne le signale.
  ///
  /// 🔴→✅ TICKET F0.89 — `dateVente` : le JOUR choisi au panier (nul ou aujourd'hui = vente du
  /// jour, comportement STRICTEMENT inchangé). Deux horodatages, qui ne se confondent jamais :
  ///  - `updatedAt` = l'instant de la SAISIE, toujours : il arbitre les conflits en dernier
  ///    écrivain gagne, et un horodatage antidaté perdrait contre des saisies plus anciennes ;
  ///  - `soldAt` = le jour choisi, à l'heure courante (comme `setTimeFrom(now())` du POS web,
  ///    15.32) ; il part en heure LOCALE sans `toUtc()` (règle du ticket 14.71, `_instant`).
  Future<Sale> enregistrerVente({
    required List<LignePanier> panier,
    required String modePaiement,
    String? clientId,
    double remise = 0,
    double? especesRecues,
    DateTime? dateVente,
  }) async {
    if (panier.isEmpty) {
      throw const VenteRefusee('Le panier est vide.');
    }

    final saisie = maintenant();
    final jourVente = dateVente == null ? aujourdhui() : _minuit(dateVente);
    final anterieure = jourVente.isBefore(aujourdhui());

    // ⚠️ GARDE DE DATE AVANT TOUT EFFET (même ordre que `PosInterface::validateSale`).
    final refus = await refusDeDate(jourVente);
    if (refus != null) throw VenteRefusee(refus);

    final soldAt = anterieure
        ? DateTime(
            jourVente.year,
            jourVente.month,
            jourVente.day,
            saisie.hour,
            saisie.minute,
            saisie.second,
            saisie.millisecond,
            saisie.microsecond,
          )
        : saisie;

    // ⚠️ CONTRÔLE SANITAIRE AVANT TOUT ENREGISTREMENT : une vente refusée ne
    // doit laisser aucune trace partielle.
    //
    // ⚠️ F0.89 — VENTE ANTÉRIEURE : ENREGISTRÉE, la rémanence est SIGNALÉE par le serveur
    // (`FlagSaleUnderWithdrawalAction`, jugée sur `sold_at` et bornée par `start_date`), jamais
    // refusée — décision client du 14/10/2026, appliquée telle quelle au POS web (15.32). Le
    // poste ne peut pas la juger lui-même : la période descendue n'a pas de date de DÉBUT, et
    // la juger « active aujourd'hui » refuserait une vente faite AVANT le traitement.
    // 🔶 QA6 (non tranché) : antidater contourne donc le blocage du jour, comme sur le web.
    for (final ligne in panier) {
      if (anterieure) break;
      if (ligne.lotId == null) continue;

      final remanence = await remanenceActive(ligne.lotId!);
      if (remanence != null) {
        final bande = await (_db.select(
          _db.livestockLots,
        )..where((t) => t.id.equals(ligne.lotId!))).getSingleOrNull();

        throw VenteRefusee(
          'Vente interdite — bande ${bande?.code ?? ''} sous rémanence '
          'vétérinaire jusqu\'au ${_jourFr(remanence.endDate)}.',
        );
      }
    }

    final sousTotal = panier.fold<double>(0, (s, l) => s + l.montant);
    final total = sousTotal - remise;
    final venteId = _uuid.v4();

    await _db.transaction(() async {
      await _db
          .into(_db.sales)
          .insert(
            SalesCompanion.insert(
              id: venteId,
              deviceId: _deviceId,
              syncStatus: const Value(SyncStatus.pending),
              // S-T11 : `saisie` est l'heure murale du Bénin ; `updatedAt` reste un INSTANT.
              updatedAt: HeureBenin.versInstant(saisie),
              customerId: Value(clientId),
              paymentMode: modePaiement,
              subtotal: Value(sousTotal),
              discount: Value(remise),
              total: total,
              cashReceived: Value(especesRecues),
              changeDue: Value(
                especesRecues == null ? null : especesRecues - total,
              ),
              soldAt: soldAt,
            ),
          );

      for (final ligne in panier) {
        await _db
            .into(_db.saleLines)
            .insert(
              SaleLinesCompanion.insert(
                id: _uuid.v4(),
                saleId: venteId,
                productId: ligne.produit.id,
                lotId: Value(ligne.lotId),
                qty: ligne.quantite.toDouble(),
                unitPrice: ligne.prixUnitaire,
                manualTotalAmount: ligne.montant,
              ),
            );

        // Effet 1 — le stock local suit immédiatement.
        //
        // ⚠️ AUCUN PLANCHER À ZÉRO. Un stock négatif n'est pas une fraude :
        // c'est le signe d'une ENTRÉE NON SAISIE, régularisable par un
        // ajustement d'inventaire. Le brider ici masquerait l'anomalie et
        // ferait diverger le poste du serveur, qui ne la bride pas non plus.
        //
        // 🔴→✅ TICKET F0.90 (défaut B1, mesuré en F0.89) — DÉCRÉMENT SUR L'ÉTAT RÉEL DE LA BASE,
        // pas sur l'instantané du panier. `ligne.produit.stockQty` est le stock au moment où le
        // produit a été mis au panier : deux lignes du même produit (2 puis 1, stock 20) écrivaient
        // chacune `20 − q`, la seconde écrasant la première (19 au lieu de 17) ; un tirage entre
        // l'ajout et la validation était effacé de même. `stock_qty = stock_qty − q` est appliqué
        // ligne par ligne par SQLite, comme le serveur rejoue `AdjustStockAction` ligne par ligne.
        await (_db.update(
          _db.products,
        )..where((t) => t.id.equals(ligne.produit.id))).write(
          ProductsCompanion.custom(
            stockQty:
                _db.products.stockQty - Constant(ligne.quantite.toDouble()),
          ),
        );

        // Effet 2 — la fiche d'élevage DU JOUR DE LA VENTE suit la sortie du cheptel.
        if (ligne.lotId != null) {
          await _repercuterSurFiche(
            ligne.lotId!,
            ligne.quantite,
            jourVente,
            saisie,
          );
        }
      }
    });

    // Ticket S-T3 — APRÈS la transaction : la vente est écrite, elle peut partir.
    _gestes?.signaler();

    return (await (_db.select(
      _db.sales,
    )..where((t) => t.id.equals(venteId))).getSingle());
  }

  /// Répercute la vente sur la fiche du JOUR DE LA VENTE, puis recalcule les fiches suivantes.
  ///
  /// Ticket S-T7 — la fiche n'est écrite QUE par son dépôt (un seul écrivain par table au poste) :
  /// [FicheJournaliereRepository.repercuterVente] porte désormais l'écriture qui vivait ici, telle quelle
  /// (fiche complétée jamais écrasée, effectif par le point de vérité unique, cascade du dépôt). Le même
  /// générateur d'identifiants est transmis : une fiche créée par la vente garde l'identifiant que la caisse
  /// lui aurait donné.
  Future<void> _repercuterSurFiche(
    String lotId,
    int quantite,
    DateTime jour,
    DateTime saisie,
  ) => FicheJournaliereRepository(
    database: _db,
    deviceId: _deviceId,
    uuid: _uuid,
  ).repercuterVente(lotId, quantite, jour, saisie);

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _jourFr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
