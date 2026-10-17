import '../../core/database/app_database.dart';
import 'soins_repository.dart';

/// Un soin du registre, avec le libellé de sa bande.
class LigneRegistre {
  const LigneRegistre({
    required this.soin,
    required this.codeBande,
    required this.codeEspece,
  });

  final VeterinaryRecord soin;
  final String codeBande;
  final String codeEspece;

  /// ⚠️ **DEUX STATUTS SEULEMENT AU POSTE.** La maquette en affiche trois —
  /// Effectué · Planifié · Annulé. Le registre local ne contient QUE des soins
  /// administrés : un soin planifié vit dans le calendrier prophylactique, pas
  /// dans `veterinary_records`. Afficher « Planifié » ici supposerait une
  /// table de planification que ni le poste ni le serveur ne portent.
  bool get effectue => true;
}

/// Une case de la grille du Calendrier Vétérinaire.
enum EtatIntervention { effectue, planifie, enRetard, traitementEnCours }

class InterventionCalendrier {
  const InterventionCalendrier({
    required this.jour,
    required this.traitement,
    required this.etat,
  });

  final DateTime jour;
  final String traitement;
  final EtatIntervention etat;
}

/// Une ligne de la grille : une bande et ses interventions sur la fenêtre.
class LigneCalendrier {
  const LigneCalendrier({
    required this.codeBande,
    required this.interventions,
    required this.motifIndetermine,
  });

  final String codeBande;
  final List<InterventionCalendrier> interventions;

  /// ⚠️ **L'INDÉTERMINATION EST UNE RÉPONSE, PAS UNE LIGNE VIDE.** Une bande en
  /// reproduction compte son cycle depuis la dernière saillie ; une bande sans
  /// date de mise en lot n'a pas de jour de cycle du tout. Une ligne vide se
  /// lirait « rien de prévu », ce qui ferait sauter des traitements.
  final String? motifIndetermine;
}

class DonneesSoinsVaccins {
  const DonneesSoinsVaccins({
    required this.interventionsDuMois,
    required this.vaccinationsPlanifiees,
    required this.coutDuMois,
    required this.registre,
    required this.calendrier,
    required this.fenetre,
  });

  final int interventionsDuMois;
  final int vaccinationsPlanifiees;
  final double coutDuMois;
  final List<LigneRegistre> registre;
  final List<LigneCalendrier> calendrier;

  /// Les jours affichés en colonnes par le Gantt.
  final List<DateTime> fenetre;
}

/// Lectures de `prototype_html/soins-vaccins-hub.html` et de ses trois pages
/// (`vms-registre`, `vms-calendrier`, `vms-suivi`).
///
/// ⚠️ **LE HUB EST UN ÉCRAN À TROIS ONGLETS, PAS TROIS ENTRÉES DE MENU.** La
/// maquette charge les trois pages dans des `<iframe>` d'un même écran ; la
/// barre latérale ne porte que « Soins et vaccins ». Le poste reproduit cette
/// structure.
///
/// ⚠️⚠️ **`infirmary_records` N'EXISTE PAS AU POSTE.** La table est bien créée
/// côté serveur — vérifiée présente, et vide à ce jour — mais elle ne figure
/// pas dans la charge du tirage. Tout l'onglet « Suivi Sanitaire » en dépend,
/// ainsi que le KPI « Animaux en quarantaine » du registre : ils affichent un
/// tiret motivé plutôt qu'un zéro qui se lirait « aucun animal isolé ».
class SoinsVaccinsRepository {
  SoinsVaccinsRepository({required this.database, required this.soins});

  final AppDatabase database;
  final SoinsRepository soins;

  /// Fenêtre du Gantt : trois jours en arrière, dix en avant — quatorze
  /// colonnes, comme la maquette.
  static const joursAvant = 3;
  static const joursApres = 10;

  Future<DonneesSoinsVaccins> charger({DateTime? quand}) async {
    final maintenant = quand ?? DateTime.now();
    final jour = DateTime(maintenant.year, maintenant.month, maintenant.day);

    final bandes = await (database.select(
      database.livestockLots,
    )..where((t) => t.isActive.equals(true))).get();
    final registre = await database.select(database.veterinaryRecords).get();
    final remanences = await database
        .select(database.veterinaryWithdrawalPeriods)
        .get();

    final codeDe = {for (final b in bandes) b.id: b.code};
    final especeDe = {for (final b in bandes) b.id: b.speciesCode ?? ''};

    final duMois = registre
        .where(
          (s) =>
              s.recordDate.year == jour.year &&
              s.recordDate.month == jour.month,
        )
        .toList();

    final fenetre = [
      for (var i = -joursAvant; i <= joursApres; i++)
        jour.add(Duration(days: i)),
    ];

    final lignes = <LigneCalendrier>[];
    var planifiees = 0;

    for (final bande in bandes) {
      final espece = bande.speciesCode;
      if (espece == null) continue;

      final interventions = <InterventionCalendrier>[];
      String? motif;

      for (final j in fenetre) {
        final protocole = await soins.protocoleDuJour(
          bande: bande,
          codeEspece: espece,
          quand: j,
        );

        motif ??= protocole.motifIndetermine;

        for (final t in protocole.traitements) {
          final etat = t.dejaAdministre
              ? EtatIntervention.effectue
              // ⚠️ « EN RETARD » N'EST PAS « PLANIFIÉ ». Un traitement dû
              // avant-hier et non administré doit sauter aux yeux : c'est
              // toute la raison d'être de ce calendrier.
              : j.isBefore(jour)
              ? EtatIntervention.enRetard
              : EtatIntervention.planifie;

          if (etat == EtatIntervention.planifie) planifiees++;

          interventions.add(
            InterventionCalendrier(
              jour: j,
              traitement: t.standard.treatment,
              etat: etat,
            ),
          );
        }
      }

      // ⚠️ Une rémanence en cours colore la journée en bleu — « Traitement en
      // cours » de la légende. Elle ne remplace jamais une intervention : elle
      // s'y ajoute, sur les jours où aucune n'est prévue.
      for (final r in remanences.where((r) => r.lotId == bande.id)) {
        for (final j in fenetre) {
          final couvert = !j.isAfter(r.endDate);
          final dejaOccupe = interventions.any((i) => i.jour == j);
          if (couvert && !dejaOccupe) {
            interventions.add(
              InterventionCalendrier(
                jour: j,
                traitement: 'Rémanence — ${r.productUsed ?? 'traitement'}',
                etat: EtatIntervention.traitementEnCours,
              ),
            );
          }
        }
      }

      lignes.add(
        LigneCalendrier(
          codeBande: bande.code,
          interventions: interventions,
          motifIndetermine: motif,
        ),
      );
    }

    return DonneesSoinsVaccins(
      interventionsDuMois: duMois.length,
      vaccinationsPlanifiees: planifiees,
      coutDuMois: duMois.fold<double>(0, (t, s) => t + (s.cost ?? 0)),
      registre:
          (registre.toList()
                ..sort((a, b) => b.recordDate.compareTo(a.recordDate)))
              .map(
                (s) => LigneRegistre(
                  soin: s,
                  codeBande: codeDe[s.lotId] ?? '—',
                  codeEspece: especeDe[s.lotId] ?? '',
                ),
              )
              .toList(),
      calendrier: lignes,
      fenetre: fenetre,
    );
  }

  /// Bandes actives, pour la modale « Nouveau Soin ».
  Future<List<LivestockLot>> bandesActives() {
    return (database.select(
      database.livestockLots,
    )..where((t) => t.isActive.equals(true))).get();
  }
}
