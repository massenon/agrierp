import '../../core/database/app_database.dart';

/// `LivestockDailyEntry::previousEffectif()` du web, sur des fiches DÉJÀ lues : effectif final de la fiche de la même
/// bande au jour STRICTEMENT antérieur le plus récent, sinon `initial_quantity` de la bande, sinon 0.
///
/// Une seule écriture de la règle, partagée par le Rapport Élevage (`RapportsRepository`) et la fiche Pondeuses
/// (`MoisPondeuses`, ticket U11) — fichier sans dépendance, pour que la fiche n'importe pas le dépôt des rapports
/// (et ses tables, que l'animalier ne reçoit pas : `perimetre_tirage_test.dart`).
int effectifPrecedentDe(
  LivestockDailyEntry fiche,
  List<LivestockDailyEntry> toutes,
  List<LivestockLot> bandes,
) {
  DateTime jour(DateTime d) => DateTime(d.year, d.month, d.day);
  final ce = jour(fiche.entryDate);
  LivestockDailyEntry? precedente;
  for (final f in toutes) {
    if (f.lotId != fiche.lotId || f.id == fiche.id || !jour(f.entryDate).isBefore(ce)) {
      continue;
    }
    if (precedente == null || f.entryDate.isAfter(precedente.entryDate)) {
      precedente = f;
    }
  }
  if (precedente != null) return precedente.effectifFinal;
  for (final b in bandes) {
    if (b.id == fiche.lotId) return b.initialQuantity;
  }
  return 0;
}
