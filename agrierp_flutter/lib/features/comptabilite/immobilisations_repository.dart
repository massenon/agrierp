import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import 'comptabilite_repository.dart';

/// Ticket CP-3 — AMORTISSEMENT LINÉAIRE, transposition EXACTE de `App\Models\FixedAsset` (annuité, cumul au prorata, valeur
/// nette), prouvée par une parité EXÉCUTÉE contre le vrai PHP (`test/immobilisations_parite_php_test.dart`).
///
/// ⚠️⚠️ **LE « PRORATA MENSUEL » DU WEB EST UN PRORATA FRACTIONNAIRE** : le web appelle `Carbon::diffInMonths`, qui depuis
/// Carbon 3 rend un NOMBRE DE MOIS À VIRGULE — les mois entiers, plus la part de jours du mois entamé (jours écoulés ÷ jours
/// du mois, bornes calculées avec le débordement de fin de mois de `addMonths`). Un bien acquis le 31/01 et arrêté au 28/02
/// vaut donc 0,903 mois, pas 1 ni 0. Le poste reproduit cette arithmétique : le cumul affiché ici est celui du web, au franc.
abstract final class CalculAmortissement {
  static DateTime _jour(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// `addMonths` de Carbon : le jour DÉBORDE sur le mois suivant (31/01 + 1 mois = 03/03), exactement comme `DateTime`.
  static DateTime _plusMois(DateTime d, int n) => DateTime.utc(d.year, d.month + n, d.day);

  static int _jours(DateTime a, DateTime b) => b.difference(a).inDays;

  /// `$debut->diffInMonths($fin)` de Carbon 3 : signé, à virgule.
  static double moisEntre(DateTime debut, DateTime fin) {
    var start = _jour(debut);
    var end = _jour(fin);

    var mois = (end.year - start.year) * 12 + end.month - start.month;
    if (mois > 0) {
      if (start.day > end.day) mois -= 1;
    } else if (mois < 0) {
      if (start.day < end.day) mois += 1;
    }

    final croissant = !start.isAfter(end);
    final signe = croissant ? 1 : -1;
    mois = mois.abs();
    if (!croissant) {
      final t = start;
      start = end;
      end = t;
    }

    final plancher = _plusMois(start, mois);
    if (!plancher.isBefore(end)) return signe * mois.toDouble();

    final plafond = _plusMois(start, mois + 1);
    final joursAuPlancher = _jours(plancher, end);
    final joursAuPlafond = _jours(end, plafond);

    return signe * (mois + joursAuPlancher / (joursAuPlafond + joursAuPlancher));
  }

  /// `round($v, 2)` de PHP.
  static double arrondi(double v) {
    final x = (v * 100).roundToDouble() / 100;
    return x == 0 ? 0 : x;
  }

  /// `baseAmortissable()` : valeur d'acquisition − valeur résiduelle, jamais négative.
  static double base(FixedAsset b) {
    final v = b.acquisitionValue - b.residualValue;
    return arrondi(v > 0 ? v : 0);
  }

  /// `annuite()` : annuité pleine.
  static double annuite(FixedAsset b) => b.durationYears <= 0 ? 0 : arrondi(base(b) / b.durationYears);

  /// `cumulAmortissement($date)` : prorata, plafonné à la base, arrêté à la date de sortie.
  static double cumul(FixedAsset b, DateTime arrete) {
    var fin = _jour(arrete);
    final acquisition = _jour(b.acquisitionDate);
    if (fin.isBefore(acquisition)) return 0;

    // Un bien cédé cesse de s'amortir à sa date de sortie.
    if (b.disposalDate != null && fin.isAfter(_jour(b.disposalDate!))) fin = _jour(b.disposalDate!);

    final mois = moisEntre(acquisition, fin);
    final brut = annuite(b) * (mois / 12);
    final plafond = base(b);

    return arrondi(brut < plafond ? brut : plafond);
  }

  static double valeurNette(FixedAsset b, DateTime arrete) => arrondi(b.acquisitionValue - cumul(b, arrete));

  /// `estTotalementAmorti($date)`.
  static bool totalementAmorti(FixedAsset b, DateTime arrete) => cumul(b, arrete) >= base(b) - 0.01;
}

/// Une ligne de la ventilation par nature d'actif (Note 2 des États Financiers).
class LigneVentilation {
  const LigneVentilation({
    required this.code,
    required this.libelle,
    required this.brut,
    required this.amortissement,
    required this.net,
    required this.nombre,
    required this.horsCompta,
  });

  final String code;
  final String libelle;
  final double brut;
  final double amortissement;
  final double net;
  final int nombre;
  final double horsCompta;
}

/// Les cartes de l'écran. [aDoter] vaut `null` quand le poste ne sait pas (aucune écriture reçue : le solde de 281 est
/// inconnu) — un tiret à l'écran, jamais 0.
class KpisImmobilisations {
  const KpisImmobilisations({
    required this.brut,
    required this.amortissement,
    required this.net,
    required this.aDoter,
    required this.horsCompta,
  });

  final double brut;
  final double amortissement;
  final double net;
  final double? aDoter;
  final double horsCompta;
}

/// Une demande de dotation pas encore jouée par le serveur : en attente d'envoi ou refusée avec son motif.
class DemandeDotation {
  const DemandeDotation({required this.demande, this.motifRefus});

  final DepreciationRequest demande;
  final String? motifRefus;

  bool get refusee => demande.syncStatus == SyncStatus.conflict;
}

class DonneesImmobilisations {
  const DonneesImmobilisations({
    required this.biens,
    required this.natures,
    required this.comptesTresorerie,
    required this.dotations,
    required this.journalConnu,
    required this.plan281,
    required this.refus,
    required this.soldeAmortissements,
  });

  /// Tout le registre actif (`FixedAsset::active()`), avant filtre.
  final List<FixedAsset> biens;

  /// `ImmobilisationService::natures()`.
  final List<ChartOfAccount> natures;
  final List<TreasuryAccount> comptesTresorerie;
  final List<DemandeDotation> dotations;

  /// Le poste a reçu au moins une écriture : le solde de 281 est connu.
  final bool journalConnu;

  /// Le plan comptable porte un compte 281 : sans lui le serveur ne dote rien (`montantADoter` = 0).
  final bool plan281;

  /// Motif de refus du serveur par identifiant de bien (`fixed_assets:<id>`).
  final Map<String, String> refus;

  /// Solde CRÉDITEUR de 281 à la date d'arrêté demandée (voir [ImmobilisationsRepository.charger]) ; `null` si inconnu.
  final double? Function(DateTime) soldeAmortissements;
}

/// Saisie refusée AVANT d'être écrite : un message par champ, ceux du web, ou un message général (`formulaire`).
class SaisieImmobilisationRefusee implements Exception {
  const SaisieImmobilisationRefusee(this.erreurs);

  final Map<String, String> erreurs;

  @override
  String toString() => erreurs.values.join(' ');
}

/// Ticket CP-3 — LE REGISTRE DES IMMOBILISATIONS au poste (`Livewire\Comptabilite\Immobilisations`). UN SEUL ÉCRIVAIN de
/// `fixed_assets` et de `depreciation_requests`.
///
/// ⚠️ Le poste écrit le BIEN (`pending`) ; il n'écrit JAMAIS l'écriture d'acquisition ni la dotation : le serveur
/// (`ImmobilisationService`) capitalise, dote (681 / 281) et rend les écritures au tirage. `isCapitalized` n'est jamais posé ici.
class ImmobilisationsRepository {
  ImmobilisationsRepository({required this.database, this.deviceId = 'poste', Uuid? uuid, this.horloge}) : _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final String deviceId;
  final Uuid _uuid;
  final DateTime Function()? horloge;

  DateTime _maintenant() => (horloge ?? HeureBenin.maintenant)();

  ExerciceDeSaisie get _exercice => ExerciceDeSaisie(database, maintenant: horloge ?? HeureBenin.maintenant);

  /// Natures de la ferme proposées d'origine (`ImmobilisationService::NATURES_FERME`).
  static const naturesFerme = ['221', '241', '244'];

  static const motifValeurFigee =
      "Ce bien est déjà comptabilisé : sa valeur d'acquisition ne peut plus être modifiée ici. Passez une écriture de correction au Journal Comptable.";

  static const motifRienADoter = 'Aucune dotation à passer à cette date — les amortissements sont déjà comptabilisés.';

  Future<List<ChartOfAccount>> natures() async {
    final utilisees = {for (final b in await database.select(database.fixedAssets).get()) b.accountCode};
    final retenues = {...naturesFerme, ...utilisees};
    final comptes = await (database.select(database.chartOfAccounts)
          ..where((c) => c.accountClass.equals(2) & c.isActive.equals(true) & c.code.like('28%').not()))
        .get();
    return [for (final c in comptes) if (retenues.contains(c.code)) c]..sort((a, b) => a.code.compareTo(b.code));
  }

  Future<DonneesImmobilisations> charger() async {
    final biens = await (database.select(database.fixedAssets)
          ..where((b) => b.isActive.equals(true))
          ..orderBy([(b) => OrderingTerm.asc(b.acquisitionDate), (b) => OrderingTerm.asc(b.code)]))
        .get();
    final tresorerie = await (database.select(database.treasuryAccounts)..orderBy([(t) => OrderingTerm.asc(t.label)])).get();
    final enAttente = await (database.select(database.depreciationRequests)
          ..where((d) => d.syncStatus.equalsValue(SyncStatus.synced).not())
          ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]))
        .get();
    final refus = {for (final c in await database.select(database.syncConflicts).get()) c.id: c.reason};

    // Le solde de 281 vient du journal reçu, par la règle R1 (`FinancialReportService::soldeCompte`).
    final compta = await ComptabiliteRepository(database: database, deviceId: deviceId).charger();
    final compte281 = compta.comptes.where((c) => c.code == '281').firstOrNull;

    return DonneesImmobilisations(
      biens: biens,
      natures: await natures(),
      comptesTresorerie: tresorerie,
      dotations: [
        for (final d in enAttente)
          DemandeDotation(demande: d, motifRefus: d.syncStatus == SyncStatus.conflict ? refus['depreciation_requests:${d.id}'] : null),
      ],
      journalConnu: compta.journal.isNotEmpty,
      plan281: compte281 != null,
      refus: refus,
      soldeAmortissements: (date) {
        if (compte281 == null || compta.journal.isEmpty) return null;
        // `dejaComptabilise` = −solde(281) : le crédit déjà passé.
        return CalculAmortissement.arrondi(-compta.soldesExercice.soldes(date).netDe(compte281.id));
      },
    );
  }

  // ── Calculs de l'écran (transposition de `Immobilisations::getVentilationProperty / getKpisProperty`) ──────────

  /// Ventilation par nature des biens EN SERVICE, sur TOUT le registre (jamais sur la liste filtrée).
  static List<LigneVentilation> ventilation(DonneesImmobilisations d, DateTime arrete) {
    final enService = [for (final b in d.biens) if (b.status == 'en_service') b];
    final parCompte = <String, List<FixedAsset>>{};
    for (final b in enService) {
      parCompte.putIfAbsent(b.accountCode, () => []).add(b);
    }
    final libelles = {for (final n in d.natures) n.code: n.label};

    final lignes = <LigneVentilation>[];
    for (final e in parCompte.entries) {
      final brut = CalculAmortissement.arrondi(e.value.fold(0.0, (s, b) => s + b.acquisitionValue));
      final amortissement = CalculAmortissement.arrondi(e.value.fold(0.0, (s, b) => s + CalculAmortissement.cumul(b, arrete)));
      lignes.add(
        LigneVentilation(
          code: e.key,
          libelle: libelles[e.key] ?? e.key,
          brut: brut,
          amortissement: amortissement,
          net: CalculAmortissement.arrondi(brut - amortissement),
          nombre: e.value.length,
          horsCompta: CalculAmortissement.arrondi(e.value.where((b) => !b.isCapitalized).fold(0.0, (s, b) => s + b.acquisitionValue)),
        ),
      );
    }
    lignes.sort((a, b) => a.code.compareTo(b.code));
    return lignes;
  }

  /// `RecordDepreciationEntryAction::montantADoter` : cumul des biens CAPITALISÉS − crédit déjà passé en 281, jamais négatif.
  /// `null` si le solde de 281 est inconnu ; 0 si le plan n'a pas de compte 281 (comme le serveur).
  static double? montantADoter(DonneesImmobilisations d, DateTime arrete) {
    if (!d.plan281) return 0;
    final dejaPasse = d.soldeAmortissements(arrete);
    if (dejaPasse == null) return null;
    final theorique = CalculAmortissement.arrondi(
      d.biens.where((b) => b.isCapitalized).fold(0.0, (s, b) => s + CalculAmortissement.cumul(b, arrete)),
    );
    final a = CalculAmortissement.arrondi(theorique - dejaPasse);
    return a > 0 ? a : 0;
  }

  static KpisImmobilisations kpis(DonneesImmobilisations d, DateTime arrete) {
    final v = ventilation(d, arrete);
    final brut = CalculAmortissement.arrondi(v.fold(0.0, (s, l) => s + l.brut));
    final amortissement = CalculAmortissement.arrondi(v.fold(0.0, (s, l) => s + l.amortissement));
    return KpisImmobilisations(
      brut: brut,
      amortissement: amortissement,
      net: CalculAmortissement.arrondi(brut - amortissement),
      aDoter: montantADoter(d, arrete),
      horsCompta: CalculAmortissement.arrondi(v.fold(0.0, (s, l) => s + l.horsCompta)),
    );
  }

  // ── Saisie (règles de `ImmobilisationService::regles`, messages de `lang/fr`) ───────────────────────────────────

  static String _nombre(String brut) => brut.trim();

  /// Règles de saisie ; vide si recevable. [idModifie] : le bien en cours de modification.
  Future<Map<String, String>> valider({
    required String code,
    required String libelle,
    required String nature,
    required DateTime? dateAcquisition,
    required String valeur,
    required String residuelle,
    required String duree,
    String contrepartie = '',
    String? idModifie,
  }) async {
    final e = <String, String>{};

    final c = code.trim();
    if (c.isEmpty) {
      e['code'] = 'Le champ code est obligatoire.';
    } else if (c.length > 50) {
      e['code'] = 'Le champ code ne doit pas dépasser 50 caractères.';
    } else {
      final pris = await (database.select(database.fixedAssets)
            ..where((b) => b.code.equals(c) & (idModifie == null ? const Constant(true) : b.id.equals(idModifie).not())))
          .get();
      if (pris.isNotEmpty) e['code'] = 'La valeur du champ code est déjà utilisée.';
    }

    final l = libelle.trim();
    if (l.isEmpty) {
      e['label'] = 'Le champ libellé est obligatoire.';
    } else if (l.length > 150) {
      e['label'] = 'Le champ libellé ne doit pas dépasser 150 caractères.';
    }

    if (nature.isEmpty) {
      e['accountCode'] = 'Le champ nature est obligatoire.';
    } else if (!(await natures()).any((n) => n.code == nature)) {
      e['accountCode'] = "La valeur sélectionnée pour le champ nature n'est pas valide.";
    }

    if (dateAcquisition == null) {
      e['acquisitionDate'] = "Le champ date d'acquisition est obligatoire.";
    } else {
      final auj = _maintenant();
      if (DateTime(dateAcquisition.year, dateAcquisition.month, dateAcquisition.day).isAfter(DateTime(auj.year, auj.month, auj.day))) {
        e['acquisitionDate'] = "Le champ date d'acquisition doit être une date antérieure ou égale à aujourd'hui.";
      }
    }

    final v = double.tryParse(_nombre(valeur).replaceAll(',', '.'));
    if (valeur.trim().isEmpty) {
      e['acquisitionValue'] = "Le champ valeur d'acquisition est obligatoire.";
    } else if (v == null) {
      e['acquisitionValue'] = "Le champ valeur d'acquisition doit être un nombre.";
    } else if (v < 1) {
      e['acquisitionValue'] = "Le champ valeur d'acquisition doit être au moins égal à 1.";
    }

    final r = double.tryParse(_nombre(residuelle).replaceAll(',', '.'));
    if (residuelle.trim().isEmpty) {
      e['residualValue'] = 'Le champ valeur résiduelle est obligatoire.';
    } else if (r == null) {
      e['residualValue'] = 'Le champ valeur résiduelle doit être un nombre.';
    } else if (r < 0) {
      e['residualValue'] = 'Le champ valeur résiduelle doit être au moins égal à 0.';
    } else if (v != null && r >= v) {
      e['residualValue'] = 'Le champ valeur résiduelle doit être inférieur à ${_nombre(valeur)}.';
    }

    final n = int.tryParse(duree.trim());
    if (duree.trim().isEmpty) {
      e['durationYears'] = "Le champ durée d'amortissement est obligatoire.";
    } else if (n == null) {
      e['durationYears'] = "Le champ durée d'amortissement doit être un nombre entier.";
    } else if (n < 1) {
      e['durationYears'] = "Le champ durée d'amortissement doit être au moins égal à 1.";
    } else if (n > 50) {
      e['durationYears'] = "Le champ durée d'amortissement ne doit pas dépasser 50.";
    }

    if (contrepartie.isNotEmpty && contrepartie != 'credit' && !(await database.select(database.treasuryAccounts).get()).any((t) => t.id == contrepartie)) {
      e['contrepartie'] = "La valeur sélectionnée pour le champ contrepartie n'est pas valide.";
    }

    return e;
  }

  /// « Nouvelle Immobilisation » : écrit le bien LOCALEMENT (`pending`) ; le serveur l'enregistre et, sauf reprise
  /// d'antériorité (`contrepartie` vide), le capitalise.
  Future<FixedAsset> creer({
    required String code,
    required String libelle,
    required String nature,
    required DateTime? dateAcquisition,
    required String valeur,
    required String residuelle,
    required String duree,
    String contrepartie = '',
  }) async {
    final refus = await valider(
      code: code, libelle: libelle, nature: nature, dateAcquisition: dateAcquisition,
      valeur: valeur, residuelle: residuelle, duree: duree, contrepartie: contrepartie,
    );
    if (refus.isNotEmpty) throw SaisieImmobilisationRefusee(refus);

    final id = _uuid.v4();
    await database.into(database.fixedAssets).insert(
      FixedAssetsCompanion.insert(
        id: id,
        deviceId: Value(deviceId),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(_maintenant()),
        code: code.trim(),
        label: libelle.trim(),
        accountCode: nature,
        acquisitionDate: dateAcquisition!,
        acquisitionValue: double.parse(valeur.trim().replaceAll(',', '.')),
        durationYears: int.parse(duree.trim()),
        residualValue: Value(double.parse(residuelle.trim().replaceAll(',', '.'))),
        counterpart: Value(contrepartie),
      ),
    );
    return (await bien(id))!;
  }

  /// « Modifier l'Immobilisation » : un bien DÉJÀ COMPTABILISÉ ne voit pas sa valeur d'acquisition changer (le registre
  /// divergerait du grand livre).
  Future<FixedAsset> modifier(
    String id, {
    required String code,
    required String libelle,
    required String nature,
    required DateTime? dateAcquisition,
    required String valeur,
    required String residuelle,
    required String duree,
  }) async {
    final actuel = await bien(id);
    if (actuel == null) throw const SaisieImmobilisationRefusee({'formulaire': 'Immobilisation inconnue — synchronisez le poste.'});

    final refus = await valider(
      code: code, libelle: libelle, nature: nature, dateAcquisition: dateAcquisition,
      valeur: valeur, residuelle: residuelle, duree: duree, idModifie: id,
    );
    final nouvelle = double.tryParse(valeur.trim().replaceAll(',', '.'));
    if (refus.isEmpty && actuel.isCapitalized && nouvelle != null && CalculAmortissement.arrondi(nouvelle) != CalculAmortissement.arrondi(actuel.acquisitionValue)) {
      refus['acquisitionValue'] = motifValeurFigee;
    }
    if (refus.isNotEmpty) throw SaisieImmobilisationRefusee(refus);

    await (database.update(database.fixedAssets)..where((b) => b.id.equals(id))).write(
      FixedAssetsCompanion(
        code: Value(code.trim()),
        label: Value(libelle.trim()),
        accountCode: Value(nature),
        acquisitionDate: Value(dateAcquisition!),
        acquisitionValue: Value(double.parse(valeur.trim().replaceAll(',', '.'))),
        residualValue: Value(double.parse(residuelle.trim().replaceAll(',', '.'))),
        durationYears: Value(int.parse(duree.trim())),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(_maintenant()),
      ),
    );
    return (await bien(id))!;
  }

  /// « Sortie d'Immobilisation » : cession ou réforme, jamais une suppression. Le bien cesse de s'amortir à cette date.
  Future<FixedAsset> sortir(String id, {required DateTime? date, required String statut, required String motif}) async {
    final actuel = await bien(id);
    if (actuel == null || actuel.status != 'en_service') {
      throw const SaisieImmobilisationRefusee({'formulaire': 'Ce bien est déjà sorti du registre.'});
    }

    final e = <String, String>{};
    if (date == null) {
      e['cessionDate'] = 'Le champ date de sortie est obligatoire.';
    } else if (DateTime(date.year, date.month, date.day).isBefore(DateTime(actuel.acquisitionDate.year, actuel.acquisitionDate.month, actuel.acquisitionDate.day))) {
      e['cessionDate'] = "La date de sortie ne peut pas précéder l'acquisition.";
    }
    if (statut != 'cede' && statut != 'reforme') {
      e['cessionStatus'] = "La valeur sélectionnée pour le champ statut de la cession n'est pas valide.";
    }
    final m = motif.trim();
    if (m.isEmpty) {
      e['cessionReason'] = 'Le champ motif est obligatoire.';
    } else if (m.length > 150) {
      e['cessionReason'] = 'Le champ motif ne doit pas dépasser 150 caractères.';
    }
    if (e.isNotEmpty) throw SaisieImmobilisationRefusee(e);

    await (database.update(database.fixedAssets)..where((b) => b.id.equals(id))).write(
      FixedAssetsCompanion(
        status: Value(statut),
        disposalDate: Value(date),
        disposalReason: Value(m),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(_maintenant()),
      ),
    );
    return (await bien(id))!;
  }

  /// « Passer la Dotation » : écrit la DEMANDE (la date d'arrêté seule) ; le serveur recalcule l'écart contre le grand livre.
  /// Refusée AVANT d'écrire si la date tombe dans un exercice clos ou absent, ou s'il n'y a rien à doter.
  Future<DepreciationRequest> passerDotation(DateTime arrete) async {
    final jour = DateTime(arrete.year, arrete.month, arrete.day);
    try {
      await _exercice.refuser(jour);
    } on RefusExercice catch (r) {
      throw SaisieImmobilisationRefusee({'formulaire': r.motif});
    }

    final d = await charger();
    final a = montantADoter(d, jour);
    if (a != null && a <= 0) throw const SaisieImmobilisationRefusee({'formulaire': motifRienADoter});

    // Une demande déjà en attente pour ce jour n'est pas doublée.
    for (final existante in d.dotations) {
      if (!existante.refusee && DateTime(existante.demande.dateArrete.year, existante.demande.dateArrete.month, existante.demande.dateArrete.day) == jour) {
        return existante.demande;
      }
    }

    final id = _uuid.v4();
    await database.into(database.depreciationRequests).insert(
      DepreciationRequestsCompanion.insert(
        id: id,
        deviceId: deviceId,
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: _maintenant(),
        dateArrete: jour,
      ),
    );
    return (await (database.select(database.depreciationRequests)..where((x) => x.id.equals(id))).getSingle());
  }

  Future<FixedAsset?> bien(String id) => (database.select(database.fixedAssets)..where((b) => b.id.equals(id))).getSingleOrNull();
}
