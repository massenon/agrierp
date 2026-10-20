import 'package:flutter/widgets.dart';

import '../database/app_database.dart';
import '../temps/heure_benin.dart';

/// Ticket EX7 (EF8, EF9, EF10 du PRD `docs/prd/exercices-comptables.md`) — L'EXERCICE AFFICHÉ, point de passage
/// unique du poste. Copie de `App\Support\ExerciceChoisi` (web, le maître), comparée au PHP EXÉCUTÉ par
/// `test/selecteur_exercice_test.dart`.
///
/// Toute lecture de « l'exercice que l'utilisateur regarde » passe par ici : le sélecteur de la barre supérieure, le
/// bandeau de lecture seule, la Balance (« Exercice 2026 »), le Plan comptable, le tableau de bord, les périodes par
/// défaut et les listes paginées dans l'exercice.
///
/// ⚠️ AFFICHER ≠ ÉCRIRE. Ce choix ne décide jamais de l'exercice d'une saisie : elle appartient à l'exercice qui
/// contient SA DATE, jugé par `ExerciceDeSaisie` au poste et par le serveur à l'envoi. Le grisé des boutons d'un
/// exercice clos (EF10) n'est qu'un confort.
///
/// Choix mémorisé dans les paramètres locaux du poste (`app_settings`, clé [ExerciceChoisi.cleParametre]) ; par défaut,
/// l'exercice qui contient le jour à l'heure du Bénin, sinon le plus récent.

/// L'état de l'exercice affiché, SANS BASE : la liste des exercices connus, l'année mémorisée, aujourd'hui (heure du
/// Bénin). Chaque accesseur reproduit la méthode de même rôle de `ExerciceChoisi.php`.
class EtatExercice {
  EtatExercice({
    required List<FiscalYear> exercices,
    required this.memorise,
    required DateTime aujourdhui,
  }) : exercices = [
         for (final e in exercices)
           if (e.startDate != null && e.endDate != null) e,
       ],
       aujourdhui = _jour(aujourdhui);

  /// Les exercices connus au poste (ceux sans dates — impossible au serveur — sont écartés).
  final List<FiscalYear> exercices;

  /// L'année mémorisée (`null` : aucun choix).
  final int? memorise;

  /// Aujourd'hui, à minuit, heure du Bénin.
  final DateTime aujourdhui;

  /// `ExerciceChoisi::exercice()` — celui mémorisé s'il existe encore, sinon [parDefaut].
  FiscalYear? get exercice =>
      exercices.where((e) => e.year == memorise).firstOrNull ?? parDefaut;

  /// `ExerciceChoisi::parDefaut()` — l'exercice qui contient le jour ; à défaut le plus récent.
  FiscalYear? get parDefaut {
    final couvrants = exercices.where((e) => _couvre(e, aujourdhui)).toList()
      ..sort((a, b) => a.startDate!.compareTo(b.startDate!));
    if (couvrants.isNotEmpty) return couvrants.first;
    if (exercices.isEmpty) return null;
    return exercices.reduce((a, b) => a.year >= b.year ? a : b);
  }

  /// `ExerciceChoisi::annee()` — l'année civile du jour si aucun exercice n'est connu.
  int get annee => exercice?.year ?? aujourdhui.year;

  /// `ExerciceChoisi::statutDe()` : `cloture`, `provisoire` (ouvert ET le précédent n'est pas clos : à-nouveaux
  /// calculés, R3), ou `ouvert` (précédent clos, ou premier exercice).
  String statutDe(FiscalYear e) {
    if (e.status == 'cloture') return 'cloture';
    final debut = _jour(e.startDate!);
    if (!exercices.any((x) => _jour(x.startDate!).isBefore(debut))) {
      return 'ouvert';
    }
    final veille = HeureBenin.plusJours(debut, -1);
    final precedents = exercices.where((x) => _couvre(x, veille)).toList()
      ..sort((a, b) => a.startDate!.compareTo(b.startDate!));
    return precedents.firstOrNull?.status == 'cloture' ? 'ouvert' : 'provisoire';
  }

  /// `ExerciceChoisi::liste()` — le plus récent d'abord.
  List<EntreeExercice> get liste {
    final choisi = exercice?.year;
    return [
      for (final e in [...exercices]..sort((a, b) => b.year.compareTo(a.year)))
        EntreeExercice(
          annee: e.year,
          statut: statutDe(e),
          choisi: e.year == choisi,
        ),
    ];
  }

  /// `ExerciceChoisi::bornes()` — l'année civile du jour si aucun exercice n'est connu.
  ({DateTime debut, DateTime fin}) get bornes {
    final e = exercice;
    if (e != null) return (debut: _jour(e.startDate!), fin: _jour(e.endDate!));
    return (debut: DateTime(aujourdhui.year), fin: DateTime(aujourdhui.year, 12, 31));
  }

  bool get contientAujourdhui =>
      !aujourdhui.isBefore(bornes.debut) && !aujourdhui.isAfter(bornes.fin);

  bool get clos => exercice?.status == 'cloture';

  /// `ExerciceChoisi::exerciceDeSaisie()` — l'exercice OUVERT qui contient le jour, sinon le plus récent ouvert.
  FiscalYear? get exerciceDeSaisie {
    final ouverts = exercices.where((e) => e.status == 'ouvert').toList();
    return ouverts.where((e) => _couvre(e, aujourdhui)).firstOrNull ??
        (ouverts.isEmpty
            ? null
            : ouverts.reduce((a, b) => a.year >= b.year ? a : b));
  }

  /// `ExerciceChoisi::motifLectureSeule()` — info-bulle des boutons grisés ; `null` : exercice ouvert.
  String? get motifLectureSeule => motifLectureSeuleDe(exercice);

  /// `ExerciceChoisi::motifLectureSeuleDe()` — le motif d'un exercice DONNÉ : l'exercice affiché, ou celui du jour
  /// choisi d'une fiche d'élevage (EF12, fusion EX7 + EX8).
  static String? motifLectureSeuleDe(FiscalYear? e) =>
      e?.status == 'cloture' ? 'Exercice ${e!.year} clôturé — lecture seule' : null;

  /// `ExerciceChoisi::exerciceDuJour()` — l'exercice qui contient [jour] (le premier par date de début) ; `null` si
  /// aucun ne le couvre.
  FiscalYear? exerciceDuJour(DateTime jour) {
    final j = _jour(jour);
    final couvrants = exercices.where((e) => _couvre(e, j)).toList()
      ..sort((a, b) => a.startDate!.compareTo(b.startDate!));
    return couvrants.firstOrNull;
  }

  /// `ExerciceChoisi::bandeau()` — texte du bandeau et année du lien « Passer à … » ; `null` : pas de bandeau.
  ({String texte, int? cible})? get bandeau => bandeauDe(exercice);

  /// `ExerciceChoisi::bandeauDe()` — le bandeau d'un exercice DONNÉ, même texte et même lien en haut du contenu
  /// ([BandeauExercice]) et en tête d'une fiche d'élevage (`BandeauLectureSeule`, fusion EX7 + EX8).
  ({String texte, int? cible})? bandeauDe(FiscalYear? e) {
    final motif = motifLectureSeuleDe(e);
    if (motif == null) return null;
    final saisie = exerciceDeSaisie;
    return (
      texte:
          '$motif.${saisie != null ? " Les saisies se font dans l'exercice ${saisie.year}." : ''}',
      cible: saisie?.year,
    );
  }

  /// `ExerciceChoisi::borner()` — une date ramenée dans l'exercice affiché.
  DateTime borner(DateTime date) {
    final j = _jour(date);
    final b = bornes;
    return j.isBefore(b.debut) ? b.debut : (j.isAfter(b.fin) ? b.fin : j);
  }

  /// `ExerciceChoisi::periodeParDefaut()` — la période de l'écran ramenée dans l'exercice quand il contient le jour,
  /// l'exercice entier sinon.
  ({DateTime debut, DateTime fin}) periodeParDefaut(DateTime debut, DateTime fin) =>
      contientAujourdhui ? (debut: borner(debut), fin: borner(fin)) : bornes;

  /// `ExerciceChoisi::bornerPeriode()` — une période saisie, ramenée dans l'exercice (début ≤ fin).
  ({DateTime debut, DateTime fin}) bornerPeriode(DateTime debut, DateTime fin) {
    final d = borner(debut);
    final f = borner(fin);
    return f.isBefore(d) ? (debut: d, fin: d) : (debut: d, fin: f);
  }

  /// `ExerciceChoisi::dateArrete()` — aujourd'hui ramené dans l'exercice affiché : la date d'arrêté du Bilan et du
  /// Compte de résultat N / N-1 (`EtatsComparatifs`, fusion EX7 + EX8), `arreteDe(annee)`.
  DateTime get dateArrete => arreteDe(exercices, annee, aujourdhui);

  /// `ExerciceChoisi::arreteDe()` — LA RÈGLE de la date d'arrêté des états d'un exercice [annee] : aujourd'hui s'il
  /// est en cours, sa clôture s'il est passé, son premier jour s'il est à venir ; l'année civile s'il n'est pas connu.
  /// `EtatsComparatifs.arreteDeLExercice` (EX8) y renvoie.
  static DateTime arreteDe(List<FiscalYear> exercices, int annee, DateTime aujourdhui) {
    final e = exercices.where((x) => x.year == annee && x.startDate != null && x.endDate != null).firstOrNull;
    final debut = e == null ? DateTime(annee) : _jour(e.startDate!);
    final fin = e == null ? DateTime(annee, 12, 31) : _jour(e.endDate!);
    final jour = _jour(aujourdhui);
    return jour.isBefore(debut) ? debut : (jour.isAfter(fin) ? fin : jour);
  }

  /// `ExerciceChoisi::moisDeReference()` — premier jour du mois du jour, ou du dernier mois de l'exercice affiché.
  DateTime get moisDeReference => DateTime(dateArrete.year, dateArrete.month);

  /// `ExerciceChoisi::moisDeLExercice()` — du mois de référence au premier mois de l'exercice.
  List<DateTime> get moisDeLExercice {
    final premier = DateTime(bornes.debut.year, bornes.debut.month);
    return [
      for (var m = moisDeReference; !m.isBefore(premier); m = DateTime(m.year, m.month - 1)) m,
    ];
  }

  /// La date est-elle dans l'exercice affiché ? (listes paginées dans l'exercice).
  bool contient(DateTime date) {
    final j = _jour(date);
    return !j.isBefore(bornes.debut) && !j.isAfter(bornes.fin);
  }

  /// « Décembre 2026 » (`ucfirst(translatedFormat('F Y'))`, locale `fr`).
  static String libelleMois(DateTime mois) =>
      '${moisFr[mois.month - 1]} ${mois.year}';

  static const moisFr = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];

  static bool _couvre(FiscalYear e, DateTime jour) =>
      !_jour(e.startDate!).isAfter(jour) && !_jour(e.endDate!).isBefore(jour);

  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Une ligne du sélecteur : l'année, son statut (`ouvert`, `provisoire`, `cloture`) et son libellé de badge.
class EntreeExercice {
  const EntreeExercice({
    required this.annee,
    required this.statut,
    required this.choisi,
  });

  final int annee;
  final String statut;
  final bool choisi;

  String get libelle => ExerciceChoisi.libelles[statut]!;
}

/// Le service du poste : lit les exercices et le choix mémorisé, mémorise un nouveau choix, prévient la barre, le
/// bandeau et le socle (qui reconstruit l'écran affiché). Un seul par session, posé par le socle sous
/// [PorteeExerciceChoisi].
class ExerciceChoisi extends ChangeNotifier {
  ExerciceChoisi(AppDatabase database, {DateTime Function()? maintenant})
    : _db = database,
      _maintenant = maintenant ?? HeureBenin.maintenant;

  /// Clé du choix dans les paramètres locaux du poste (`app_settings`, jamais synchronisés).
  static const cleParametre = 'poste.exercice_choisi';

  /// `ExerciceChoisi::PAR_PAGE` — lignes par page des listes paginées dans l'exercice.
  static const parPage = 25;

  /// `ExerciceChoisi::LIBELLES` — badges du sélecteur, mot pour mot.
  static const libelles = {
    'ouvert': 'Ouvert',
    'provisoire': 'Provisoire',
    'cloture': 'Clôturé',
  };

  final AppDatabase _db;
  final DateTime Function() _maintenant;

  EtatExercice? _etat;

  /// L'état lu au dernier [charger] ; `null` avant.
  EtatExercice? get etat => _etat;

  /// Relit les exercices (ils changent au tirage) et le choix mémorisé.
  Future<void> charger() async {
    final exercices = await _db.select(_db.fiscalYears).get();
    final ligne = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(cleParametre))).getSingleOrNull();
    _etat = EtatExercice(
      exercices: exercices,
      memorise: int.tryParse(ligne?.value ?? ''),
      aujourdhui: _maintenant(),
    );
    notifyListeners();
  }

  /// Mémorise [annee] ; faux (et rien ne change) si l'exercice n'est pas connu au poste.
  Future<bool> choisir(int annee) async {
    final exercices = await _db.select(_db.fiscalYears).get();
    if (!exercices.any((e) => e.year == annee)) return false;
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: cleParametre, value: '$annee'),
        );
    await charger();
    return true;
  }
}

/// Diffuse l'exercice affiché aux écrans. Un écran SANS portée au-dessus de lui (tests d'écran, outils) ne borne rien
/// et ne grise rien : comportement d'avant EX7.
class PorteeExerciceChoisi extends InheritedNotifier<ExerciceChoisi> {
  const PorteeExerciceChoisi({
    super.key,
    required ExerciceChoisi super.notifier,
    required super.child,
  });

  /// Le service, avec abonnement (barre supérieure, bandeau).
  static ExerciceChoisi? de(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PorteeExerciceChoisi>()
      ?.notifier;

  /// L'état, SANS abonnement — utilisable dans `initState` : le socle reconstruit l'écran affiché quand l'exercice
  /// ou son statut change (clé de l'écran), il n'a donc pas à écouter.
  static EtatExercice? lire(BuildContext context) => context
      .getInheritedWidgetOfExactType<PorteeExerciceChoisi>()
      ?.notifier
      ?.etat;
}
