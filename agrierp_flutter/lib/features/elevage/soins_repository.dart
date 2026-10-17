import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';

/// Soins vétérinaires saisis au poste.
///
/// ⚠️⚠️ **UN SOIN CRÉE SA RÉMANENCE LOCALEMENT, PAS SEULEMENT AU SERVEUR.**
/// Le serveur la crée bien à la réception (ticket 14.54), mais un poste peut
/// rester des jours hors ligne : d'ici là, la caisse du poste continuerait de
/// vendre une bande qui vient d'être traitée. Le blocage sanitaire doit exister
/// **au moment du soin**, là où il est saisi — pas seulement à l'arrivée.
///
/// C'est le même raisonnement que pour les quatre effets d'une vente : ce que
/// le serveur rejoue, le poste doit le produire tout de suite.
/// Un traitement du protocole, situe par rapport a la bande et au jour.
class TraitementPrevu {
  const TraitementPrevu({required this.standard, required this.dejaAdministre});

  final ProphylaxisScheduleStandard standard;

  /// Un soin du meme libelle a deja ete enregistre pour cette bande ce jour-la.
  final bool dejaAdministre;

  int get remanenceJours => standard.withdrawalDays;
}

/// Ce que le poste peut dire du protocole d'une bande a une date donnee.
///
/// ⚠️ **L'INDETERMINATION EST UNE REPONSE, PAS UNE LISTE VIDE.** Une liste vide
/// se lit « rien de prevu aujourd'hui » ; or le poste peut aussi etre dans
/// l'incapacite de calculer le jour de cycle. Confondre les deux ferait sauter
/// un traitement sans que personne ne s'en apercoive.
class ProtocoleDuJour {
  const ProtocoleDuJour({
    required this.traitements,
    required this.jourDeCycle,
    required this.motifIndetermine,
    required this.calendairesNonEvalues,
  });

  final List<TraitementPrevu> traitements;

  /// Jour de cycle de la bande (J1 = mise en lot, ou dernière saillie pour une
  /// bande en reproduction) — `null` si non calculable. Peut valoir 0 ou moins
  /// avant le jour de référence.
  final int? jourDeCycle;

  /// Pourquoi le jour de cycle est inconnu, a afficher tel quel.
  final String? motifIndetermine;

  /// Entrees du protocole que le poste n'a PAS pu evaluer (bornes nulles).
  ///
  /// ⚠️ COMPTEES, JAMAIS MASQUEES : les taire laisserait croire a un protocole
  /// integralement couvert.
  final int calendairesNonEvalues;

  bool get determinable => jourDeCycle != null;

  int get enAttente => traitements.where((t) => !t.dejaAdministre).length;
}

class SoinsRepository {
  SoinsRepository({
    required AppDatabase database,
    required String deviceId,
    Uuid? uuid,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _deviceId = deviceId,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final String _deviceId;
  final Uuid _uuid;

  /// Protocole prévu pour une espèce, tel que le serveur le sert.
  ///
  /// ⚠️ Jamais de traitement codé en dur : le protocole est éditable depuis
  /// l'écran Paramètres > Élevage, et le figer proposerait un soin périmé.
  Future<List<ProphylaxisScheduleStandard>> protocole(String codeEspece) {
    return (_db.select(_db.prophylaxisScheduleStandards)
          ..where((t) => t.speciesCode.equals(codeEspece))
          ..orderBy([(t) => OrderingTerm(expression: t.periodLabel)]))
        .get();
  }

  /// Traitements dus pour une bande a une date donnee.
  ///
  /// ⚠️⚠️ **MÊME RÈGLE QUE `ProtocoleDuJourService` CÔTÉ SERVEUR (15.35)**,
  /// comparée ligne à ligne au ticket F0.91 et verrouillée par
  /// `test/protocole_du_jour_parite_test.dart` (jeu commun recopié du test
  /// serveur). Ne pas la « corriger » ici seul : deux copies d'une règle
  /// sanitaire qui divergent font administrer un traitement au mauvais jour.
  ///
  /// ⚠️⚠️ **LE JOUR DE CYCLE VIENT DE BORNES ENTIERES, JAMAIS DU LIBELLE.**
  /// `periodLabel` est du texte libre (« Le 5e jour », « Semaine 4 ») ; le
  /// serveur a ajoute `cycle_day_start`/`cycle_day_end` precisement parce que
  /// l'interpreter n'etait pas fiable. Dû si `debut <= J <= fin` ; une entrée
  /// à bornes nulles (« Le 1er du mois ») n'est JAMAIS évaluée, mais COMPTÉE.
  ///
  /// ⚠️ **JOUR DE RÉFÉRENCE (J1 = ce jour lui-même)** : la DERNIÈRE saillie
  /// connue pour une bande au stade `reproduction` (F0.91 : la saillie descend
  /// au poste depuis 14.72, `_absorberReproduction`), la mise en lot sinon.
  /// Comme au serveur (`latest('saillie_date')`), la dernière saillie vaut
  /// pour TOUT jour consulté, même antérieur à elle (J ≤ 0 : rien de dû).
  ///
  /// ⚠️ **DEUX CAS RESTENT INDETERMINABLES, ET SONT DITS PLUTOT QUE DEVINES** :
  /// une bande en reproduction sans aucune saillie connue du poste, et une
  /// bande hors reproduction sans date de mise en lot. Retomber sur la mise en
  /// lot pour la première ferait administrer un traitement au mauvais moment
  /// (le serveur ne le fait pas non plus).
  Future<ProtocoleDuJour> protocoleDuJour({
    required LivestockLot bande,
    required String codeEspece,
    DateTime? quand,
  }) async {
    final maintenant = quand ?? DateTime.now();
    final jour = DateTime(maintenant.year, maintenant.month, maintenant.day);

    final standards = await protocole(codeEspece);

    // ⚠️ Comptees AVANT tout filtrage : le decompte doit refleter le protocole
    // reel, pas ce qu'il en reste apres selection.
    final calendaires = standards.where((s) => s.cycleDayStart == null).length;

    String? motif;
    int? jourDeCycle;

    final DateTime? reference;
    if (bande.stage == 'reproduction') {
      reference = await _derniereSaillie(bande.id);
      if (reference == null) {
        motif =
            'Bande en reproduction : le cycle se compte depuis la dernière '
            "saillie, et aucune saillie n'est enregistrée pour cette bande "
            'sur ce poste.';
      }
    } else {
      reference = bande.createdDate;
      if (reference == null) {
        motif =
            'Date de mise en lot inconnue : le jour du cycle ne peut pas '
            'être calculé.';
      }
    }

    if (reference != null) {
      // J1 = le jour de reference lui-meme, comme cote serveur.
      jourDeCycle = joursCalendairesEntre(reference, jour) + 1;
    }

    if (jourDeCycle == null) {
      return ProtocoleDuJour(
        traitements: const [],
        jourDeCycle: null,
        motifIndetermine: motif,
        calendairesNonEvalues: calendaires,
      );
    }

    final jourCourant = jourDeCycle;
    final dus = standards.where((s) {
      final debut = s.cycleDayStart;
      final fin = s.cycleDayEnd;
      if (debut == null || fin == null) return false;
      return debut <= jourCourant && fin >= jourCourant;
    }).toList();

    // Même ordre que le serveur (`orderBy('cycle_day_start')->orderBy('treatment')`) :
    // `protocole()` range sur le LIBELLÉ de période, où « J10 » passe avant « J2 ».
    dus.sort((a, b) {
      final parDebut = a.cycleDayStart!.compareTo(b.cycleDayStart!);
      return parDebut != 0 ? parDebut : a.treatment.compareTo(b.treatment);
    });

    // Un soin porte le libelle du traitement : c'est ce qui relie le registre
    // au protocole, faute d'une reference explicite cote serveur.
    //
    // ⚠️ Rapprochement sur le JOUR CALENDAIRE (`whereDate` du serveur), pas sur
    // l'égalité d'instant : un soin daté avec une heure (10 h 15) est bien du
    // jour, et l'égalité stricte le faisait proposer une seconde fois.
    final lendemain = DateTime(jour.year, jour.month, jour.day + 1);
    final soinsDuJour =
        await (_db.select(_db.veterinaryRecords)..where(
              (t) => Expression.and([
                t.lotId.equals(bande.id),
                t.recordDate.isBiggerOrEqualValue(jour),
                t.recordDate.isSmallerThanValue(lendemain),
              ]),
            ))
            .get();
    final libellesFaits = soinsDuJour.map((s) => s.actionType).toSet();

    return ProtocoleDuJour(
      traitements: dus
          .map(
            (s) => TraitementPrevu(
              standard: s,
              dejaAdministre: libellesFaits.contains(s.treatment),
            ),
          )
          .toList(),
      jourDeCycle: jourDeCycle,
      motifIndetermine: null,
      calendairesNonEvalues: calendaires,
    );
  }

  /// Dernière saillie connue du poste pour une bande — `null` si aucune.
  ///
  /// Même source que le serveur (`reproductionEvents()->latest('saillie_date')`,
  /// sans filtre de statut `en_cours`/`termine`/`echec`), avec une seule
  /// restriction propre au poste : une déclaration en `conflict` a été REFUSÉE
  /// par le serveur, qui ne la connaît donc pas ; la compter donnerait au poste
  /// un jour de cycle que le serveur n'a pas. Une déclaration `pending` compte :
  /// c'est un fait saisi ici, pas encore acquitté.
  Future<DateTime?> _derniereSaillie(String lotId) async {
    final evenements =
        await (_db.select(_db.livestockReproductionEvents)..where(
              (t) => Expression.and([
                t.lotId.equals(lotId),
                t.saillieDate.isNotNull(),
                t.syncStatus.equalsValue(SyncStatus.conflict).not(),
              ]),
            ))
            .get();

    DateTime? derniere;
    for (final e in evenements) {
      final d = e.saillieDate!;
      if (derniere == null || d.isAfter(derniere)) derniere = d;
    }
    return derniere;
  }

  /// Nombre de jours CALENDAIRES de `de` à `a` (négatif si `a` précède `de`).
  ///
  /// ⚠️ Défaut payé au serveur (15.35) : un écart d'instants n'est pas un
  /// nombre de jours (5,25 à 06 h pour un J5). Ici seules l'année, le mois et le
  /// jour sont lus, et l'écart est pris entre deux minuits UTC : ni l'heure
  /// portée par une date, ni un changement d'heure local (journée de 23 h ou
  /// 25 h, dont `Duration.inDays` tronque le résultat) ne décalent le jour.
  static int joursCalendairesEntre(DateTime de, DateTime a) => DateTime.utc(
    a.year,
    a.month,
    a.day,
  ).difference(DateTime.utc(de.year, de.month, de.day)).inDays;

  /// Soins déjà administrés à une bande, le plus récent d'abord.
  Future<List<VeterinaryRecord>> historique(String lotId) {
    return (_db.select(_db.veterinaryRecords)
          ..where((t) => t.lotId.equals(lotId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.recordDate, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Enregistre un soin et, si un délai d'attente est prévu, bloque la bande.
  ///
  /// ⚠️ **LA RÉMANENCE N'EST CRÉÉE QUE SI UN PRODUIT EST NOMMÉ** — même
  /// condition que le serveur : un délai sans produit ne dit pas de quoi la
  /// viande doit se purger.
  ///
  /// ⚠️ **TOUT OU RIEN** : un soin enregistré sans sa rémanence laisserait la
  /// bande vendable alors qu'elle vient d'être traitée.
  Future<VeterinaryRecord> enregistrer({
    required String lotId,
    required String typeAction,
    String? produit,
    String? dose,
    String? veterinaire,
    String? symptomes,
    double? cout,
    int delaiAttenteJours = 0,
    DateTime? quand,
  }) async {
    final jour = quand ?? DateTime.now();
    late final String soinId;

    await _db.transaction(() async {
      soinId = await _inserer(
        lotId: lotId,
        typeAction: typeAction,
        produit: produit,
        dose: dose,
        veterinaire: veterinaire,
        symptomes: symptomes,
        cout: cout,
        delaiAttenteJours: delaiAttenteJours,
        jour: jour,
      );
    });

    return (await (_db.select(
      _db.veterinaryRecords,
    )..where((t) => t.id.equals(soinId))).getSingle());
  }

  /// Valide les traitements COCHÉS du protocole du jour d'une bande — portage
  /// de `ValidateProphylaxisTreatmentsAction` (serveur, ticket 15.35).
  ///
  /// ⚠️⚠️ **TICKET F0.93 — IDEMPOTENT AU NIVEAU DU DÉPÔT, PAS DU BOUTON.** Les
  /// fiches parcouraient l'instantané du protocole chargé à l'affichage et
  /// écrivaient soin par soin : deux appels en rafale (double clic avant le
  /// `setState`, deux fenêtres) écrivaient DEUX soins et DEUX périodes de
  /// rémanence pour le même traitement. Comme au serveur, le protocole est
  /// RECALCULÉ à l'instant de l'écriture, DANS une transaction Drift (les
  /// transactions d'une même base sont sérialisées : la seconde validation
  /// voit le soin écrit par la première) ; ne sont écrits que les
  /// traitements :
  ///  - DUS ce jour-là (un identifiant d'un autre jour de cycle, ou inconnu,
  ///    est ignoré) ;
  ///  - non encore administrés (même règle que [protocoleDuJour] : un soin du
  ///    même libellé, même bande, même jour calendaire) ;
  ///  - cochés ([idsBareme]).
  ///
  /// Aucune règle sanitaire ne change : même soin, même rémanence (via la même
  /// écriture que [enregistrer]). Rend les soins RÉELLEMENT créés (vide si
  /// rien n'était à écrire).
  Future<List<VeterinaryRecord>> validerTraitementsDuJour({
    required LivestockLot bande,
    required String codeEspece,
    required DateTime quand,
    required Set<String> idsBareme,
    String? observations,
  }) async {
    final obs = observations?.trim();
    final symptomes = (obs == null || obs.isEmpty) ? null : obs;
    final crees = <String>[];

    await _db.transaction(() async {
      final etat = await protocoleDuJour(
        bande: bande,
        codeEspece: codeEspece,
        quand: quand,
      );

      for (final t in etat.traitements) {
        if (t.dejaAdministre) continue;
        if (!idsBareme.contains(t.standard.id)) continue;

        crees.add(
          await _inserer(
            lotId: bande.id,
            // Le libellé du traitement relie le registre au protocole : c'est
            // la clé de « déjà administré ».
            typeAction: t.standard.treatment,
            produit: t.standard.productRecommended,
            dose: t.standard.dosage,
            symptomes: symptomes,
            delaiAttenteJours: t.remanenceJours,
            jour: quand,
          ),
        );
      }
    });

    if (crees.isEmpty) return const [];
    return (_db.select(
      _db.veterinaryRecords,
    )..where((t) => t.id.isIn(crees))).get();
  }

  /// Écrit un soin et sa rémanence — À APPELER DANS UNE TRANSACTION (tout ou
  /// rien : un soin sans sa rémanence laisserait la bande vendable).
  Future<String> _inserer({
    required String lotId,
    required String typeAction,
    String? produit,
    String? dose,
    String? veterinaire,
    String? symptomes,
    double? cout,
    required int delaiAttenteJours,
    required DateTime jour,
  }) async {
    final date = DateTime(jour.year, jour.month, jour.day);
    final soinId = _uuid.v4();
    await _db
        .into(_db.veterinaryRecords)
        .insert(
          VeterinaryRecordsCompanion.insert(
            id: soinId,
            deviceId: _deviceId,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: jour,
            lotId: lotId,
            actionType: typeAction,
            productUsed: Value(produit),
            dose: Value(dose),
            vetName: Value(veterinaire),
            symptomes: Value(symptomes),
            cost: Value(cout),
            recordDate: date,
            withdrawalDays: Value(delaiAttenteJours),
          ),
        );

    if (delaiAttenteJours > 0 && produit != null && produit.isNotEmpty) {
      await _db
          .into(_db.veterinaryWithdrawalPeriods)
          .insert(
            VeterinaryWithdrawalPeriodsCompanion.insert(
              // Identifiant dérivé du soin : un renvoi ou une relecture ne
              // doit pas créer une seconde période pour le même traitement.
              id: soinId,
              lotId: lotId,
              productUsed: Value(produit),
              endDate: date.add(Duration(days: delaiAttenteJours)),
            ),
          );
    }
    return soinId;
  }
}
