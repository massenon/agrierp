import '../../core/database/app_database.dart';

/// Une ligne de « Fiche de Rationnement des Animaux ».
class LigneRation {
  const LigneRation({required this.ration, required this.especeLisible});

  final FeedRationStandard ration;

  /// Le code espèce rendu lisible — `cuniculture` → « Cuniculture ».
  final String especeLisible;
}

/// Une ligne du « Calendrier de Prophylaxie », pour une espèce.
class LigneProphylaxie {
  const LigneProphylaxie({required this.entree});

  final ProphylaxisScheduleStandard entree;

  /// ⚠️ **LES BORNES DE JOUR PEUVENT ÊTRE NULLES, ET CE N'EST PAS UN TROU.**
  /// `periodLabel` est du texte libre (« Le 5e jour », « Le 1er du mois ») ; le
  /// serveur a explicitement REFUSÉ de convertir les entrées calendaires, dont
  /// la base de calcul n'est pas le jour de cycle. Une entrée sans bornes ne
  /// doit jamais être présentée comme due aujourd'hui.
  bool get porteeParLeCycle =>
      entree.cycleDayStart != null && entree.cycleDayEnd != null;
}

/// Une ligne du « Catalogue des Types de Provende ».
class LigneProvende {
  const LigneProvende({required this.type});

  final FeedType type;
}

/// Les quatre espèces de la ferme, dans l'ordre des sous-onglets de la
/// maquette (`parametres-elevage.html` l.160-163).
enum EspeceProphylaxie {
  lapins('cuniculture', '🐰 Cuniculture (Lapins)'),
  volailles('aviculture', '🐔 Aviculture (Volailles)'),
  porcs('porciculture', '🐖 Porciculture (Porcs)');

  const EspeceProphylaxie(this.code, this.libelle);

  final String code;
  final String libelle;
}

class DonneesParametresElevage {
  const DonneesParametresElevage({
    required this.rations,
    required this.prophylaxies,
    required this.provendes,
    required this.numerotation,
  });

  final List<LigneRation> rations;
  final List<LigneProphylaxie> prophylaxies;
  final List<LigneProvende> provendes;

  /// ⚠️ `null` tant qu'aucun tirage n'a eu lieu : les préfixes ne sont pas
  /// devinables. Afficher « R » par défaut ferait croire à une convention
  /// confirmée alors qu'on ne l'a jamais lue.
  final ElevageNumberingSetting? numerotation;

  List<LigneProphylaxie> prophylaxiePour(EspeceProphylaxie espece) =>
      prophylaxies.where((p) => p.entree.speciesCode == espece.code).toList();
}

/// Lectures de `prototype_html/parametres-elevage.html`.
///
/// ⚠️⚠️ **LES QUATRE ONGLETS SONT EN LECTURE SEULE, ET C'EST LA RÈGLE DU
/// SERVEUR, PAS UN RENONCEMENT.** Rations, calendriers, provendes et préfixes
/// sont des référentiels : le serveur ignore tout envoi les concernant et le
/// compte dans `referentiels_ignored`. Une ration corrigée au poste
/// disparaîtrait au tirage suivant, sans un mot — c'est le défaut que la règle
/// « le serveur a toujours raison » existe pour empêcher.
///
/// ⚠️ **CES QUATRE TABLES PILOTENT DES ÉCRANS DÉJÀ LIVRÉS** : les rations
/// calculent la provende du Dashboard Élevage, le calendrier alimente les
/// traitements prévus de Soins et Vaccins. Cet écran ne les crée pas — il
/// montre enfin ce que le poste applique déjà.
class ParametresElevageRepository {
  ParametresElevageRepository({required this.database});

  final AppDatabase database;

  /// Codes espèce → libellé, tel que la ferme les nomme.
  static const especes = <String, String>{
    'cuniculture': 'Cuniculture',
    'aviculture': 'Aviculture',
    'porciculture': 'Porciculture',
    'heliciculture': 'Héliciculture',
  };

  static String especeLisible(String code) =>
      especes[code] ?? (code.isEmpty ? '—' : code);

  Future<DonneesParametresElevage> charger() async {
    final rations = await database.select(database.feedRationStandards).get();
    final prophylaxies = await database
        .select(database.prophylaxisScheduleStandards)
        .get();
    final provendes = await database.select(database.feedTypes).get();
    final numerotation = await database
        .select(database.elevageNumberingSettings)
        .getSingleOrNull();

    return DonneesParametresElevage(
      rations:
          (rations.toList()..sort((a, b) {
                final espece = a.speciesCode.compareTo(b.speciesCode);
                return espece != 0
                    ? espece
                    : a.stageLabel.compareTo(b.stageLabel);
              }))
              .map(
                (r) => LigneRation(
                  ration: r,
                  especeLisible: especeLisible(r.speciesCode),
                ),
              )
              .toList(),
      prophylaxies:
          (prophylaxies.toList()..sort((a, b) {
                final espece = a.speciesCode.compareTo(b.speciesCode);
                if (espece != 0) return espece;
                // ⚠️ Le tri suit le JOUR DE CYCLE, pas le libellé : « Le 10e
                // jour » précède « Le 5e jour » dans l'ordre alphabétique.
                return (a.cycleDayStart ?? 9999).compareTo(
                  b.cycleDayStart ?? 9999,
                );
              }))
              .map((p) => LigneProphylaxie(entree: p))
              .toList(),
      provendes: (provendes.toList()..sort((a, b) => a.name.compareTo(b.name)))
          .map((t) => LigneProvende(type: t))
          .toList(),
      numerotation: numerotation,
    );
  }
}
