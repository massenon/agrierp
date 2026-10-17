import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';

/// Un cycle de reproduction, tel que l'écran l'affiche.
class CycleReproduction {
  const CycleReproduction({
    required this.evenement,
    required this.codeBande,
    required this.codeEspece,
  });

  final LivestockReproductionEvent evenement;
  final String codeBande;
  final String codeEspece;

  /// ⚠️ **UNE PALPATION EST DUE, ELLE N'EST PAS « EN RETARD ».** Le serveur la
  /// compte dès `saillie + 14 jours` tant que `palpation_date` est nulle — la
  /// même règle est appliquée ici, mot pour mot.
  bool palpationDue(DateTime jour, int delai) {
    final saillie = evenement.saillieDate;
    if (saillie == null || evenement.palpationDate != null) return false;
    return !jour.isBefore(saillie.add(Duration(days: delai)));
  }
}

/// Résumé d'un couvoir — volailles ou escargots.
///
/// ⚠️ **AGRÉGAT, PAS UN SECOND FORMULAIRE.** Les panneaux Volailles et
/// Escargots du prototype recouvrent exactement ce que les fiches
/// Reproducteurs et Escargots saisissent déjà (`ponte_total` = œufs couvés,
/// `ne` = nés). Le composant Livewire a explicitement refusé de les
/// reconstruire — deux formulaires pour la même donnée est un piège que ce
/// projet a déjà rencontré. Le poste suit la même règle : un résumé réel, et
/// le renvoi vers la fiche de saisie.
class ResumeCouvoir {
  const ResumeCouvoir({
    required this.couves,
    required this.nes,
    required this.lots,
  });

  final int couves;
  final int nes;
  final int lots;

  /// `null` quand rien n'a été mis à couver : 0 % se lirait comme un échec
  /// total, alors que la campagne n'a simplement pas commencé.
  double? get tauxEclosion => couves > 0 ? (nes / couves) * 100 : null;
}

class DonneesSuiviReproduction {
  const DonneesSuiviReproduction({
    required this.gestantes,
    required this.palpationsDues,
    required this.misesBasDuMois,
    required this.echecs,
    required this.lapins,
    required this.porcs,
    required this.volailles,
    required this.escargots,
  });

  final int gestantes;
  final int palpationsDues;
  final int misesBasDuMois;
  final int echecs;

  final List<CycleReproduction> lapins;
  final List<CycleReproduction> porcs;
  final ResumeCouvoir volailles;
  final ResumeCouvoir escargots;
}

/// Lectures de `prototype_html/suivi-reproduction.html`.
///
/// ⚠️⚠️ **CET ÉCRAN EST LE SEUL À SUIVRE UN ANIMAL NOMMÉ.** R1, R2… chez les
/// lapines ; T1, T2… chez les truies. Les fiches journalières ne connaissent
/// que des agrégats de bande : ni la femelle qui a mis bas, ni le mâle
/// saillisseur n'y figurent. `livestock_reproduction_events` descend au poste
/// depuis le ticket 14.72 — avant, l'écran n'avait littéralement aucune
/// donnée.
///
/// ⚠️⚠️ **LE POSTE DÉCLARE LA SAILLIE, ET ELLE SEULE** (ticket F0.35). C'est
/// l'acte qui se fait au clapier, hors ligne, et qui se perdait jusqu'ici sur
/// un bout de papier. Palpation, mise bas et sevrage restent web : ils
/// CORRIGENT un cycle que le serveur a pu faire évoluer entre-temps, et
/// « dernier écrivain gagne » — acceptable pour une fiche journalière qui se
/// corrige dans la journée — ne l'est pas sur une gestation de trois mois.
class SuiviReproductionRepository {
  SuiviReproductionRepository({
    required this.database,
    this.deviceId = 'poste',
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final String deviceId;
  final Uuid _uuid;

  /// Les deux seules filières suivies par femelle nommée — même règle que le
  /// serveur, qui refuse les autres à l'envoi.
  static const especesSuivies = ['cuniculture', 'porciculture'];

  /// Échéances du cycle, en jours depuis la saillie — Document 05, et
  /// reprises telles quelles des bandeaux « Rappel du cycle » de la maquette.
  ///
  /// ⚠️ « Boîte à nid J+28 » (lapins) n'est PAS ici : c'est un jalon
  /// informatif, sans colonne dédiée ni action de suivi propre. Le composant
  /// Livewire a fait le même constat.
  static const cycleLapins = (palpation: 14, miseBas: 30, sevrage: 60);
  static const cyclePorcs = (retourChaleur: 21, miseBas: 114, sevrage: 42);

  Future<DonneesSuiviReproduction> charger({DateTime? quand}) async {
    final maintenant = quand ?? DateTime.now();
    final jour = DateTime(maintenant.year, maintenant.month, maintenant.day);

    final bandes = await database.select(database.livestockLots).get();
    final evenements = await database
        .select(database.livestockReproductionEvents)
        .get();
    final fiches = await database.select(database.livestockDailyEntries).get();

    final especeDe = {for (final b in bandes) b.id: b.speciesCode ?? ''};
    final codeDe = {for (final b in bandes) b.id: b.code};

    List<CycleReproduction> cyclesDe(String code) =>
        evenements
            .where((e) => especeDe[e.lotId] == code)
            .map(
              (e) => CycleReproduction(
                evenement: e,
                codeBande: codeDe[e.lotId] ?? '—',
                codeEspece: code,
              ),
            )
            .toList()
          ..sort(
            (a, b) => (b.evenement.saillieDate ?? DateTime(1970)).compareTo(
              a.evenement.saillieDate ?? DateTime(1970),
            ),
          );

    final lapins = cyclesDe('cuniculture');
    final porcs = cyclesDe('porciculture');

    // ⚠️ MÊMES RÈGLES QUE LE SERVEUR, une à une : seules cuniculture et
    // porciculture comptent, et seuls les cycles `en_cours`.
    final actifs = [
      ...lapins,
      ...porcs,
    ].where((c) => c.evenement.status == 'en_cours').toList();

    return DonneesSuiviReproduction(
      gestantes: actifs
          .where((c) => c.evenement.miseBasDateActual == null)
          .length,
      palpationsDues: actifs
          .where((c) => c.palpationDue(jour, cycleLapins.palpation))
          .length,
      misesBasDuMois: evenements.where((e) {
        final d = e.miseBasDateActual;
        return d != null && d.year == jour.year && d.month == jour.month;
      }).length,
      echecs: evenements.where((e) {
        final d = e.updatedAt;
        return e.status == 'echec' &&
            d.year == jour.year &&
            d.month == jour.month;
      }).length,
      lapins: lapins,
      porcs: porcs,
      volailles: _couvoir(bandes, fiches, 'aviculture', jour),
      escargots: _couvoir(bandes, fiches, 'helico', jour),
    );
  }

  /// Bandes ouvertes à la déclaration d'une saillie.
  Future<List<LivestockLot>> bandesDeclarables(String codeEspece) async {
    final bandes = await (database.select(
      database.livestockLots,
    )..where((t) => t.isActive.equals(true))).get();

    return bandes.where((b) => b.speciesCode == codeEspece).toList();
  }

  /// Déclare une saillie hors ligne. Retourne l'identifiant créé.
  ///
  /// ⚠️⚠️ **UN SEUL CYCLE EN COURS PAR FEMELLE, VÉRIFIÉ ICI AUSSI.** Le
  /// serveur pose la même règle à la réception — mais un refus découvert au
  /// prochain tirage, trois jours plus tard, laisse l'animalier croire sa
  /// saillie enregistrée. Le refus local est immédiat et compréhensible ; le
  /// contrôle serveur reste le garde-fou, car deux postes peuvent déclarer la
  /// même femelle sans se voir.
  Future<String> declarerSaillie({
    required String lotId,
    required String numeroFemelle,
    String? numeroMale,
    required DateTime dateSaillie,
    DateTime? maintenant,
  }) async {
    final jour = maintenant ?? DateTime.now();

    final bande = await (database.select(
      database.livestockLots,
    )..where((t) => t.id.equals(lotId))).getSingleOrNull();

    if (bande == null || !especesSuivies.contains(bande.speciesCode)) {
      throw ArgumentError(
        'Le suivi par femelle nommée ne couvre que la cuniculture et la '
        'porciculture.',
      );
    }

    // ⚠️ Une saillie datée du futur n'a pas eu lieu — même borne que le
    // serveur (`before_or_equal:today`), pour que le refus ne survienne pas
    // trois jours plus tard.
    //
    // ⚠️⚠️ **COMPARAISON EN JOURS, PAS EN INSTANTS.** Comparer les DateTime
    // bruts refusait « aujourd'hui à 14 h » comme daté du futur, parce que
    // l'instant est postérieur à minuit : la toute première déclaration de
    // l'animalier aurait été rejetée.
    final jourSaillie = DateTime(
      dateSaillie.year,
      dateSaillie.month,
      dateSaillie.day,
    );

    if (jourSaillie.isAfter(DateTime(jour.year, jour.month, jour.day))) {
      throw ArgumentError('Une saillie ne peut pas être datée du futur.');
    }

    final dejaEnCours =
        await (database.select(database.livestockReproductionEvents)..where(
              (t) =>
                  t.lotId.equals(lotId) &
                  t.motherRef.equals(numeroFemelle) &
                  t.status.equals('en_cours'),
            ))
            .get();

    if (dejaEnCours.isNotEmpty) {
      throw ArgumentError(
        'Un cycle est déjà en cours pour $numeroFemelle sur cette bande.',
      );
    }

    final id = _uuid.v4();

    await database
        .into(database.livestockReproductionEvents)
        .insert(
          LivestockReproductionEventsCompanion.insert(
            id: id,
            deviceId: deviceId,
            // ⚠️ `pending` : c'est ce statut qui met la saillie dans la file
            // d'envoi et la fait compter dans le badge « en attente ».
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: jour,
            lotId: lotId,
            motherRef: numeroFemelle,
            sireRef: Value(numeroMale),
            saillieDate: Value(dateSaillie),
            status: const Value('en_cours'),
          ),
        );

    return id;
  }

  /// Résumé du couvoir du mois, reconstruit depuis les fiches journalières.
  ///
  /// ⚠️ `ponte_total` = œufs COUVÉS et `ne` = NÉS sur les fiches
  /// Reproducteurs et Escargots — la même convention que le serveur, et celle
  /// que les fiches d'espèce écrivent déjà.
  ResumeCouvoir _couvoir(
    List<LivestockLot> bandes,
    List<LivestockDailyEntry> fiches,
    String code,
    DateTime jour,
  ) {
    final lots = bandes
        .where((b) => b.speciesCode == code && b.isActive)
        .map((b) => b.id)
        .toSet();

    final duMois = fiches.where(
      (f) =>
          lots.contains(f.lotId) &&
          f.entryDate.year == jour.year &&
          f.entryDate.month == jour.month,
    );

    return ResumeCouvoir(
      couves: duMois.fold<int>(0, (t, f) => t + (f.ponteTotal ?? 0)),
      nes: duMois.fold<int>(0, (t, f) => t + f.ne),
      lots: lots.length,
    );
  }
}
