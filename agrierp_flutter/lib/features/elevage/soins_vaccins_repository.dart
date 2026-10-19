import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import 'soins_repository.dart';

/// Un soin du registre, avec sa bande et l'espèce de celle-ci.
class LigneRegistre {
  const LigneRegistre({
    required this.soin,
    required this.codeBande,
    required this.codeEspece,
    required this.libelleEspece,
  });

  final VeterinaryRecord soin;
  final String codeBande;
  final String codeEspece;

  /// `species.label` de la bande — `'—'` si l'espèce est inconnue du poste.
  final String libelleEspece;

  /// Cellule « Lot / Espèce » du Blade : `{{ $rec->lot?->code }} ({{ $rec->lot?->species?->label }})`.
  String get lotEspece => '$codeBande ($libelleEspece)';

  /// ⚠️ **DEUX STATUTS SEULEMENT AU POSTE.** La maquette en affiche trois —
  /// Effectué · Planifié · Annulé. Le registre local ne contient QUE des soins
  /// administrés : un soin planifié vit dans le calendrier, pas dans
  /// `veterinary_records`.
  bool get effectue => true;
}

/// Une case de la grille du Calendrier Vétérinaire (`$colorMap` du Blade).
enum EtatIntervention { effectue, planifie, enRetard, traitementEnCours }

/// Ajout du poste (décision client du 19/10/2026, GARDÉ) : une intervention CALCULÉE depuis le protocole
/// prophylactique, ou une rémanence en cours.
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

/// Ticket H8b — une intervention PLANIFIÉE (`veterinary_calendar_events`), comme au web.
class EvenementPlanifie {
  const EvenementPlanifie({
    required this.id,
    required this.jour,
    required this.tache,
    required this.statut,
    required this.etat,
  });

  final String id;
  final DateTime jour;
  final String tache;

  /// Statut STOCKÉ (`planned`, `done`, `late`, `inprogress`).
  final String statut;

  /// Statut AFFICHÉ (`display_status` du modèle web).
  final EtatIntervention etat;

  /// `@if($event->status !== 'done') wire:click="confirmAdministration(…)"`.
  bool get confirmable => statut != 'done';
}

/// Une ligne de la grille : une bande active, ses interventions planifiées (web) et calculées (poste).
class LigneCalendrier {
  const LigneCalendrier({
    required this.lotId,
    required this.codeBande,
    required this.evenements,
    required this.interventions,
    required this.motifIndetermine,
  });

  final String lotId;
  final String codeBande;

  /// Interventions planifiées de la fenêtre — une par jour au plus, comme `keyBy` au web.
  final List<EvenementPlanifie> evenements;

  /// Ajout du poste : protocole calculé et rémanences.
  final List<InterventionCalendrier> interventions;

  /// ⚠️ **L'INDÉTERMINATION EST UNE RÉPONSE, PAS UNE LIGNE VIDE.** Une bande en
  /// reproduction compte son cycle depuis la dernière saillie ; une bande sans
  /// date de mise en lot n'a pas de jour de cycle du tout. Une ligne vide se
  /// lirait « rien de prévu », ce qui ferait sauter des traitements.
  final String? motifIndetermine;
}

/// Ticket H8b — une entrée de l'infirmerie, avec le code de sa bande.
class LigneInfirmerie {
  const LigneInfirmerie({required this.entree, required this.codeBande});

  final InfirmaryRecord entree;
  final String codeBande;

  /// Cellule « Lot / Sujet » : `{{ $rec->lot?->code }}{{ $rec->sujet_ref ? ' — '.$rec->sujet_ref : '' }}`.
  String get lotSujet {
    final sujet = entree.sujetRef;
    return sujet == null || sujet.isEmpty ? codeBande : '$codeBande — $sujet';
  }
}

/// Les quatre KPI de l'infirmerie (`getKpisInfirmerieProperty`).
class KpisInfirmerie {
  const KpisInfirmerie({
    required this.enQuarantaine,
    required this.guerisMois,
    required this.sousTraitement,
    required this.decesMois,
  });

  final int enQuarantaine;
  final int guerisMois;
  final int sousTraitement;
  final int decesMois;
}

/// Une bande proposée dans les modales (`getActiveLotsProperty`).
class BandeProposee {
  const BandeProposee({
    required this.id,
    required this.code,
    required this.libelleEspece,
  });

  final String id;
  final String code;
  final String libelleEspece;

  /// Option de la modale « Nouveau Soin » : `{{ $lot->code }} ({{ $lot->species?->label }})`.
  String get libelleAvecEspece => '$code ($libelleEspece)';
}

class DonneesSoinsVaccins {
  const DonneesSoinsVaccins({
    required this.interventionsDuMois,
    required this.vaccinationsPlanifiees,
    required this.enQuarantaine,
    required this.coutDuMois,
    required this.registre,
    required this.calendrier,
    required this.fenetre,
    required this.infirmerie,
    required this.kpisInfirmerie,
  });

  final int interventionsDuMois;

  /// `VeterinaryCalendarEvent::where('status', 'planned')->count()` — toutes dates.
  final int vaccinationsPlanifiees;

  /// `InfirmaryRecord::where('status', 'en_cours')->count()`.
  final int enQuarantaine;
  final double coutDuMois;
  final List<LigneRegistre> registre;

  /// Une ligne par bande ACTIVE (vide : « Aucune bande active pour le moment. »).
  final List<LigneCalendrier> calendrier;

  /// Les jours affichés en colonnes par le Gantt.
  final List<DateTime> fenetre;
  final List<LigneInfirmerie> infirmerie;
  final KpisInfirmerie kpisInfirmerie;
}

/// Lectures et écritures de l'écran Soins et vaccins — maître : `App\Livewire\Elevage\SoinsVaccinsHub`.
///
/// ⚠️ **LE HUB EST UN ÉCRAN À TROIS ONGLETS, PAS TROIS ENTRÉES DE MENU.** La
/// barre latérale ne porte que « Soins et vaccins ».
///
/// 🔴→✅ **TICKET H8b (décision client D-H8 du 19/10/2026) — L'INFIRMERIE ET LE CALENDRIER PLANIFIÉ SONT
/// SAISIS AU POSTE.** `infirmary_records` et `veterinary_calendar_events` descendent au tirage et repartent à
/// l'envoi (`pending`). Avant, l'onglet « Suivi Sanitaire » disait « module non embarqué » et le KPI
/// « Animaux en quarantaine » valait « — ».
class SoinsVaccinsRepository {
  SoinsVaccinsRepository({
    required this.database,
    required this.soins,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final SoinsRepository soins;
  final Uuid _uuid;

  /// Fenêtre du Gantt : AUJOURD'HUI → J+13 (`getGanttDaysProperty`, `range(0, 13)`).
  ///
  /// 🔴 Ticket H8 : le poste montrait J−3 → J+10 ; le Blade fait foi.
  static const joursAvant = 0;
  static const joursApres = 13;

  /// Registre : `orderByDesc('record_date')->limit(50)` du web.
  static const limiteRegistre = 50;

  /// Infirmerie : `orderByDesc('entry_date')->limit(50)` du web.
  static const limiteInfirmerie = 50;

  /// Les trois niveaux d'isolement de la modale (`<option>` du Blade, `in:` de `pushInfirmerie`).
  static const niveauxIsolement = [
    'Quarantaine stricte',
    'Infirmerie',
    'Simple surveillance',
  ];

  /// `number_format($montant, 0, ',', ' ').' FCFA'` — arrondi à l'unité, milliers séparés par une espace.
  static String fcfa(double montant) {
    final entier = montant.round();
    final chiffres = entier.abs().toString();
    final groupes = <String>[];
    for (var fin = chiffres.length; fin > 0; fin -= 3) {
      groupes.insert(0, chiffres.substring(fin - 3 < 0 ? 0 : fin - 3, fin));
    }
    return '${entier < 0 ? '-' : ''}${groupes.join(' ')} FCFA';
  }

  Future<DonneesSoinsVaccins> charger({DateTime? quand}) async {
    final maintenant = quand ?? DateTime.now();
    final jour = DateTime(maintenant.year, maintenant.month, maintenant.day);

    final toutesBandes = await database.select(database.livestockLots).get();
    final especes = {
      for (final e in await database.select(database.livestockSpecies).get())
        e.id: e.label,
    };
    // Ticket U3 — soins ACTIFS seulement : le registre (`where('is_active', true)`) et les KPI du mois (même
    // filtre, posé au web au même ticket) ; un soin archivé reste en base, sa rémanence aussi.
    final registre = await (database.select(
      database.veterinaryRecords,
    )..where((t) => t.isActive.equals(true))).get();
    final remanences = await database
        .select(database.veterinaryWithdrawalPeriods)
        .get();
    final entrees = await database.select(database.infirmaryRecords).get();
    final evenements = await database
        .select(database.veterinaryCalendarEvents)
        .get();

    final bandeDe = {for (final b in toutesBandes) b.id: b};
    // `getActiveLotsProperty` : `status = 'actif'` ET `is_active`.
    final actives = toutesBandes.where(_estActive).toList();

    bool duMois(DateTime d) => d.year == jour.year && d.month == jour.month;
    final soinsDuMois = registre.where((s) => duMois(s.recordDate)).toList();

    final fenetre = [
      for (var i = -joursAvant; i <= joursApres; i++)
        DateTime(jour.year, jour.month, jour.day + i),
    ];
    bool dansFenetre(DateTime d) {
      final j = DateTime(d.year, d.month, d.day);
      return !j.isBefore(fenetre.first) && !j.isAfter(fenetre.last);
    }

    final lignes = <LigneCalendrier>[];
    for (final bande in actives) {
      // Web : `whereIn('scheduled_date', $days)->get()->keyBy(date)` — une intervention par jour, la dernière
      // lue l'emporte. Le poste lit dans l'ordre d'insertion (rowid).
      final parJour = <DateTime, EvenementPlanifie>{};
      for (final e in evenements.where(
        (e) => e.lotId == bande.id && dansFenetre(e.scheduledDate),
      )) {
        final j = DateTime(
          e.scheduledDate.year,
          e.scheduledDate.month,
          e.scheduledDate.day,
        );
        parJour[j] = EvenementPlanifie(
          id: e.id,
          jour: j,
          tache: e.taskType,
          statut: e.status,
          etat: etatAffiche(e.status, j, maintenant),
        );
      }

      final (interventions, motif) = await _calculees(
        bande,
        fenetre,
        jour,
        remanences,
      );

      lignes.add(
        LigneCalendrier(
          lotId: bande.id,
          codeBande: bande.code,
          evenements: parJour.values.toList(),
          interventions: interventions,
          motifIndetermine: motif,
        ),
      );
    }

    final enCours = entrees.where((e) => e.status == 'en_cours').length;
    final infirmerie =
        (entrees.toList()..sort((a, b) => b.entryDate.compareTo(a.entryDate)))
            .take(limiteInfirmerie)
            .map(
              (e) => LigneInfirmerie(
                entree: e,
                codeBande: bandeDe[e.lotId]?.code ?? '—',
              ),
            )
            .toList();

    return DonneesSoinsVaccins(
      interventionsDuMois: soinsDuMois.length,
      vaccinationsPlanifiees: evenements
          .where((e) => e.status == 'planned')
          .length,
      enQuarantaine: enCours,
      coutDuMois: soinsDuMois.fold<double>(0, (t, s) => t + (s.cost ?? 0)),
      registre:
          (registre.toList()
                ..sort((a, b) => b.recordDate.compareTo(a.recordDate)))
              .take(limiteRegistre)
              .map((s) {
                final bande = bandeDe[s.lotId];
                return LigneRegistre(
                  soin: s,
                  codeBande: bande?.code ?? '—',
                  codeEspece: bande?.speciesCode ?? '',
                  libelleEspece: especes[bande?.speciesId] ?? '—',
                );
              })
              .toList(),
      calendrier: lignes,
      fenetre: fenetre,
      infirmerie: infirmerie,
      kpisInfirmerie: KpisInfirmerie(
        enQuarantaine: enCours,
        guerisMois: entrees
            .where((e) => duMois(e.entryDate) && e.status == 'reintegre')
            .length,
        sousTraitement: enCours,
        decesMois: entrees
            .where((e) => duMois(e.entryDate) && e.status == 'deces')
            .length,
      ),
    );
  }

  /// `display_status` de `VeterinaryCalendarEvent` : un `planned` dont la date est PASSÉE s'affiche « En
  /// retard », sans que la valeur stockée change.
  ///
  /// ⚠️ Port EXACT de `scheduled_date->isPast()` : la date est à minuit, donc une intervention planifiée
  /// AUJOURD'HUI est « En retard » dès minuit passé — c'est le comportement du web, signalé, pas corrigé ici.
  static EtatIntervention etatAffiche(
    String statut,
    DateTime date,
    DateTime maintenant,
  ) {
    if (statut == 'planned' &&
        DateTime(date.year, date.month, date.day).isBefore(maintenant)) {
      return EtatIntervention.enRetard;
    }
    return switch (statut) {
      'done' => EtatIntervention.effectue,
      'late' => EtatIntervention.enRetard,
      'inprogress' => EtatIntervention.traitementEnCours,
      // `$colorMap[...] ?? 'bg-accent-yellow'`.
      _ => EtatIntervention.planifie,
    };
  }

  /// Ajout du poste, GARDÉ (décision client) : le protocole prophylactique calculé et les rémanences en cours.
  Future<(List<InterventionCalendrier>, String?)> _calculees(
    LivestockLot bande,
    List<DateTime> fenetre,
    DateTime jour,
    List<VeterinaryWithdrawalPeriod> remanences,
  ) async {
    final espece = bande.speciesCode;
    final interventions = <InterventionCalendrier>[];
    String? motif;

    if (espece != null) {
      for (final j in fenetre) {
        final protocole = await soins.protocoleDuJour(
          bande: bande,
          codeEspece: espece,
          quand: j,
        );
        motif ??= protocole.motifIndetermine;
        for (final t in protocole.traitements) {
          interventions.add(
            InterventionCalendrier(
              jour: j,
              traitement: t.standard.treatment,
              etat: t.dejaAdministre
                  ? EtatIntervention.effectue
                  // ⚠️ « EN RETARD » N'EST PAS « PLANIFIÉ » : un traitement dû et non administré doit sauter
                  // aux yeux.
                  : j.isBefore(jour)
                  ? EtatIntervention.enRetard
                  : EtatIntervention.planifie,
            ),
          );
        }
      }
    }

    // ⚠️ Une rémanence en cours colore la journée en bleu — « Traitement en cours » de la légende. Elle ne
    // remplace jamais une intervention calculée : elle s'y ajoute, sur les jours où aucune n'est prévue.
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

    return (interventions, motif);
  }

  static bool _estActive(LivestockLot b) => b.status == 'actif' && b.isActive;

  /// Bandes proposées par les trois modales (`getActiveLotsProperty` : `status = 'actif'` ET `is_active`).
  Future<List<BandeProposee>> bandesActives() async {
    final especes = {
      for (final e in await database.select(database.livestockSpecies).get())
        e.id: e.label,
    };
    final bandes = await database.select(database.livestockLots).get();
    return [
      for (final b in bandes.where(_estActive))
        BandeProposee(
          id: b.id,
          code: b.code,
          libelleEspece: especes[b.speciesId] ?? '—',
        ),
    ];
  }

  // ── Archivage d'un soin (U3) ────────────────────────────────────────────────────────────────────────────

  /// `archiveSoin()` du web (ticket U3, décision client D-U3 du 19/10/2026) : `is_active = false`, la ligne
  /// RESTE (archivage logique) et repart à l'envoi (`pending`), où le serveur l'archive et journalise
  /// `veterinary_record.archived`. ⚠️ La période de rémanence créée par le soin n'est PAS touchée : au web non
  /// plus, archiver un soin ne rend pas la bande vendable.
  Future<void> archiverSoin(String id, {DateTime? quand}) =>
      (database.update(
        database.veterinaryRecords,
      )..where((t) => t.id.equals(id))).write(
        VeterinaryRecordsCompanion(
          isActive: const Value(false),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(quand ?? DateTime.now()),
        ),
      );

  // ── Infirmerie (H8b) ────────────────────────────────────────────────────────────────────────────────────

  /// `saveInfirmaryEntry()` : nouvelle entrée `en_cours`, écrite localement en `pending`.
  Future<String> enregistrerEntreeInfirmerie({
    required String lotId,
    String? sujetRef,
    required String motif,
    required String niveauIsolement,
    required DateTime dateEntree,
    DateTime? quand,
  }) async {
    final id = _uuid.v4();
    final sujet = sujetRef?.trim();
    await database
        .into(database.infirmaryRecords)
        .insert(
          InfirmaryRecordsCompanion.insert(
            id: id,
            deviceId: soins.deviceId,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: quand ?? DateTime.now(),
            lotId: lotId,
            // `$this->infSujetRef ?: null`.
            sujetRef: Value(sujet == null || sujet.isEmpty ? null : sujet),
            motif: motif.trim(),
            isolationLevel: Value(niveauIsolement),
            entryDate: DateTime(dateEntree.year, dateEntree.month, dateEntree.day),
            status: const Value('en_cours'),
          ),
        );
    return id;
  }

  /// `reintegrer()` : statut `reintegre`, repart à l'envoi.
  Future<void> reintegrer(String id, {DateTime? quand}) =>
      _changerStatutInfirmerie(id, 'reintegre', quand);

  /// `declarerDeces()` : statut `deces`, repart à l'envoi.
  Future<void> declarerDeces(String id, {DateTime? quand}) =>
      _changerStatutInfirmerie(id, 'deces', quand);

  Future<void> _changerStatutInfirmerie(
    String id,
    String statut,
    DateTime? quand,
  ) =>
      (database.update(
        database.infirmaryRecords,
      )..where((t) => t.id.equals(id))).write(
        InfirmaryRecordsCompanion(
          status: Value(statut),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(quand ?? DateTime.now()),
        ),
      );

  // ── Calendrier planifié (H8b) ───────────────────────────────────────────────────────────────────────────

  /// `savePlan()` : intervention `planned`, écrite localement en `pending`.
  Future<String> planifierIntervention({
    required String lotId,
    required String intervention,
    required DateTime datePrevue,
    DateTime? quand,
  }) async {
    final id = _uuid.v4();
    await database
        .into(database.veterinaryCalendarEvents)
        .insert(
          VeterinaryCalendarEventsCompanion.insert(
            id: id,
            deviceId: soins.deviceId,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: quand ?? DateTime.now(),
            lotId: lotId,
            taskType: intervention.trim(),
            scheduledDate: DateTime(
              datePrevue.year,
              datePrevue.month,
              datePrevue.day,
            ),
            status: const Value('planned'),
          ),
        );
    return id;
  }

  /// `confirmAdministration()` : statut `done`, repart à l'envoi.
  Future<void> confirmerAdministration(String id, {DateTime? quand}) =>
      (database.update(
        database.veterinaryCalendarEvents,
      )..where((t) => t.id.equals(id))).write(
        VeterinaryCalendarEventsCompanion(
          status: const Value('done'),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(quand ?? DateTime.now()),
        ),
      );
}
