import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/sync/gestes_importants.dart';
import '../../core/temps/heure_benin.dart';
import '../stocks/pmp_service.dart';

/// Saisie d'un reproducteur refusée AVANT toute écriture : un message par champ, ceux du web (`lang/fr/validation.php`).
/// Clés = les noms des propriétés du composant `RegistreReproducteurs` : `identifier`, `species_id`, `lot_id`, `sex`,
/// `breed`, `birth_date`, `entry_date`, `origin`, `cage` (fiche) ; `exitStatus`, `exit_date`, `exit_reason` (sortie) ; et
/// `sujet` (le sujet lui-même : introuvable).
class ReproducteurRefuse implements Exception {
  const ReproducteurRefuse(this.erreurs);

  final Map<String, String> erreurs;

  @override
  String toString() => erreurs.values.join(' ');
}

/// Ce que l'exploitant a saisi dans la modale « Enregistrer un Reproducteur » / « Modifier le Reproducteur »
/// (`RegistreReproducteurs::saveAnimal`).
class FormulaireReproducteur {
  const FormulaireReproducteur({
    this.speciesId = '',
    this.identifier = '',
    this.lotId = '',
    this.sex = 'F',
    this.breed = '',
    this.birthDate,
    this.entryDate,
    this.origin = '',
    this.cage = '',
  });

  final String speciesId;
  final String identifier;
  final String lotId;

  /// `F` ou `M` (`public string $sex = 'F'`).
  final String sex;
  final String breed;
  final DateTime? birthDate;
  final DateTime? entryDate;
  final String origin;
  final String cage;

  FormulaireReproducteur copieAvec({
    String? speciesId,
    String? identifier,
    String? lotId,
    String? sex,
    String? breed,
    DateTime? birthDate,
    DateTime? entryDate,
    String? origin,
    String? cage,
  }) => FormulaireReproducteur(
    speciesId: speciesId ?? this.speciesId,
    identifier: identifier ?? this.identifier,
    lotId: lotId ?? this.lotId,
    sex: sex ?? this.sex,
    breed: breed ?? this.breed,
    birthDate: birthDate ?? this.birthDate,
    entryDate: entryDate ?? this.entryDate,
    origin: origin ?? this.origin,
    cage: cage ?? this.cage,
  );

  /// `editAnimal($id)` : la modale reprend le sujet.
  factory FormulaireReproducteur.depuis(Sujet a) => FormulaireReproducteur(
    speciesId: a.speciesId ?? '',
    identifier: a.identifier,
    lotId: a.lotId ?? '',
    sex: a.sex,
    breed: a.breed ?? '',
    birthDate: a.birthDate,
    entryDate: a.entryDate,
    origin: a.origin ?? '',
    cage: a.cage ?? '',
  );
}

/// La modale « Enregistrer une Sortie » (`RegistreReproducteurs::confirmExit`).
class FormulaireSortie {
  const FormulaireSortie({this.status = 'reforme', this.exitDate, this.reason = ''});

  /// `reforme`, `vendu` ou `mort`.
  final String status;
  final DateTime? exitDate;
  final String reason;
}

/// Une ligne du tableau (`getAnimalsProperty()`).
class LigneReproducteur {
  const LigneReproducteur({required this.animal, required this.especeLibelle, required this.lotCode, this.motifRefus});

  final Sujet animal;
  final String? especeLibelle;
  final String? lotCode;

  /// Motif du serveur, mot pour mot, quand le dernier envoi de ce sujet a été refusé (`conflict`).
  final String? motifRefus;
}

/// Les quatre cartes de `RegistreReproducteurs::getKpisProperty()`.
class IndicateursReproducteurs {
  const IndicateursReproducteurs({required this.total, required this.presents, required this.femelles, required this.males});

  final int total;
  final int presents;
  final int femelles;
  final int males;
}

/// Ticket BS3 (décision BS-Q1 du 21/10/2026) — « Registre des Reproducteurs » du poste : miroir de
/// `App\Livewire\Elevage\RegistreReproducteurs` et de `App\Actions\SaisieReproducteurAction` (le point de passage que
/// partagent l'écran web et l'envoi du poste).
///
/// Hors ligne, le poste enregistre, modifie et sort ses reproducteurs : la ligne est écrite tout de suite, `pending`,
/// avec un UUID créé ici ; le serveur la REJOUE à l'envoi par la même action que le web (mêmes règles, même audit), et
/// un refus devient un `conflict` avec son motif.
///
/// ⚠️⚠️ **IDENTIFIER UN SUJET N'EST PAS LE FAIRE ENTRER** (ticket 14.17) : aucune écriture ne touche à l'effectif d'une
/// bande — le sujet est déjà compté dans sa bande, la fiche journalière fait foi. Comme au web, il n'y a aucune cascade.
/// ⚠️ **SORTIR N'EFFACE RIEN** : le statut, la date et le motif changent, la ligne et son historique restent.
class ReproducteursRepository {
  ReproducteursRepository({
    required AppDatabase database,
    required String deviceId,
    GestesImportants? gestes,
    DateTime Function()? horloge,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _gestes = gestes,
       _horloge = horloge ?? HeureBenin.maintenant;

  final AppDatabase _db;
  final GestesImportants? _gestes;
  final DateTime Function() _horloge;
  static const _uuid = Uuid();

  /// Toasts de `RegistreReproducteurs`, mot pour mot.
  static const toastEnregistre = "Reproducteur enregistré — l'effectif de la bande est inchangé, ce sujet y était déjà compté.";
  static const toastMisAJour = 'Reproducteur mis à jour.';
  static const toastSortie =
      "Sortie enregistrée. L'effectif de la bande doit être ajusté depuis la fiche journalière — c'est elle qui fait foi sur les quantités.";

  /// `SaisieReproducteurAction::messageDejaSorti()` : « Ce reproducteur est déjà sorti (Vendu) : … ».
  static String messageDejaSorti(String statut) =>
      'Ce reproducteur est déjà sorti (${libelleStatut(statut)}) : sa sortie ne peut pas être modifiée.';

  /// `SaisieReproducteurAction::libelleStatut()`.
  static String libelleStatut(String statut) => switch (statut) {
    'actif' => 'Actif',
    'reforme' => 'Réformé',
    'vendu' => 'Vendu',
    'mort' => 'Mort',
    _ => statut.isEmpty ? statut : statut[0].toUpperCase() + statut.substring(1),
  };

  static const messageNaissanceApresEntree = "La date de naissance ne peut pas être postérieure à la date d'entrée.";
  static const messageSortieAvantEntree = "La date de sortie ne peut pas précéder la date d'entrée du sujet.";

  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get _aujourdhui => _jour(_horloge());

  static String? _vide(String s) => s.isEmpty ? null : s;

  // ── Lecture ──────────────────────────────────────────────────────────────────────────────────────────────────────

  /// `Animal::breeders()->active()` : la catégorie « reproducteur », non archivée.
  Future<List<Sujet>> _reproducteurs() => (_db.select(_db.animals)
        ..where((t) => t.category.equals('reproducteur') & t.isActive.equals(true)))
      .get();

  Future<IndicateursReproducteurs> indicateurs() async {
    final tous = await _reproducteurs();
    final presents = tous.where((a) => a.status == 'actif').toList();
    return IndicateursReproducteurs(
      total: tous.length,
      presents: presents.length,
      femelles: presents.where((a) => a.sex == 'F').length,
      males: presents.where((a) => a.sex == 'M').length,
    );
  }

  /// `getSpeciesOptionsProperty()` : les espèces servies par le serveur, par libellé.
  Future<List<EspeceElevage>> especes() async => [
    ...await _db.select(_db.livestockSpecies).get(),
  ]..sort((a, b) => cleCommeLeServeur(a.label).compareTo(cleCommeLeServeur(b.label)));

  /// `getLotOptionsProperty()` : bandes EN COURS et non archivées (de l'espèce choisie), par code.
  Future<List<LivestockLot>> bandes({String speciesId = ''}) =>
      (_db.select(_db.livestockLots)
            ..where((t) {
              final base = t.status.equals('actif') & t.isActive.equals(true);
              return speciesId.isEmpty ? base : base & t.speciesId.equals(speciesId);
            })
            ..orderBy([(t) => OrderingTerm(expression: t.code)]))
          .get();

  /// `getAnimalsProperty()` : par identifiant ; recherche sur l'identifiant OU la race, filtre d'espèce, filtre de statut.
  Future<List<LigneReproducteur>> reproducteurs({String recherche = '', String speciesId = '', String statut = ''}) async {
    final especes = {for (final e in await _db.select(_db.livestockSpecies).get()) e.id: e};
    final lots = {for (final b in await _db.select(_db.livestockLots).get()) b.id: b};
    final refus = await _motifsDeRefus();
    final filtre = cleCommeLeServeur(recherche);

    final lignes = [
      for (final a in await _reproducteurs())
        if (recherche.isEmpty || cleCommeLeServeur(a.identifier).contains(filtre) || cleCommeLeServeur(a.breed ?? '').contains(filtre))
          if (speciesId.isEmpty || _especeDe(a, especes) == speciesId)
            if (statut.isEmpty || a.status == statut) a,
    ]..sort((a, b) => cleCommeLeServeur(a.identifier).compareTo(cleCommeLeServeur(b.identifier)));

    return [
      for (final a in lignes)
        LigneReproducteur(
          animal: a,
          especeLibelle: especes[a.speciesId]?.label ?? a.speciesLabel,
          lotCode: _vide(lots[a.lotId]?.code ?? a.lotCode ?? ''),
          motifRefus: a.syncStatus == SyncStatus.conflict ? refus[a.id] : null,
        ),
    ];
  }

  /// L'identifiant d'espèce d'un sujet ; un sujet reçu d'un serveur antérieur n'a que le libellé.
  static String? _especeDe(Sujet a, Map<String, EspeceElevage> especes) {
    if (a.speciesId != null) return a.speciesId;
    return especes.values.where((e) => e.label == a.speciesLabel).map((e) => e.id).firstOrNull;
  }

  Future<Map<String, String>> _motifsDeRefus() async => {
    for (final c in await (_db.select(_db.syncConflicts)..where((t) => t.sourceTable.equals('animals'))).get()) c.recordId: c.reason,
  };

  Future<Sujet?> sujet(String id) => (_db.select(_db.animals)..where((t) => t.id.equals(id))).getSingleOrNull();

  // ── Validation (les règles de `saveAnimal()`, messages de `lang/fr/validation.php`) ───────────────────────────────

  Future<Map<String, String>> _valider(FormulaireReproducteur f, {String? sauf}) async {
    final e = <String, String>{};
    final identifiant = f.identifier;
    if (identifiant.isEmpty) {
      e['identifier'] = 'Le champ identifiant est obligatoire.';
    } else if (identifiant.runes.length > 50) {
      e['identifier'] = 'Le champ identifiant ne doit pas dépasser 50 caractères.';
    } else {
      // `unique:animals,identifier` : comparaison sous la collation du serveur, tous les sujets (sorti ou non).
      final pris = (await _db.select(_db.animals).get()).any((a) => a.id != sauf && cleCommeLeServeur(a.identifier) == cleCommeLeServeur(identifiant));
      if (pris) e['identifier'] = 'La valeur du champ identifiant est déjà utilisée.';
    }

    if (f.speciesId.isEmpty) {
      e['species_id'] = 'Le champ espèce est obligatoire.';
    } else if (await (_db.select(_db.livestockSpecies)..where((t) => t.id.equals(f.speciesId))).getSingleOrNull() == null) {
      e['species_id'] = "La valeur sélectionnée pour le champ espèce n'existe pas.";
    }

    if (f.lotId.isNotEmpty && await (_db.select(_db.livestockLots)..where((t) => t.id.equals(f.lotId))).getSingleOrNull() == null) {
      e['lot_id'] = "La valeur sélectionnée pour le champ bande n'existe pas.";
    }
    if (f.sex != 'M' && f.sex != 'F') e['sex'] = "La valeur sélectionnée pour le champ sexe n'est pas valide.";
    if (f.breed.runes.length > 100) e['breed'] = 'Le champ race ne doit pas dépasser 100 caractères.';

    final aujourdhui = _aujourdhui;
    final naissance = f.birthDate;
    if (naissance != null && _jour(naissance).isAfter(aujourdhui)) {
      e['birth_date'] = "Le champ date de naissance doit être une date antérieure ou égale à aujourd'hui.";
    }
    final entree = f.entryDate;
    if (entree == null) {
      e['entry_date'] = "Le champ date d'entrée est obligatoire.";
    } else if (_jour(entree).isAfter(aujourdhui)) {
      e['entry_date'] = "Le champ date d'entrée doit être une date antérieure ou égale à aujourd'hui.";
    }
    if (f.origin.runes.length > 150) e['origin'] = "Le champ origine ne doit pas dépasser 150 caractères.";
    if (f.cage.runes.length > 30) e['cage'] = 'Le champ cage ne doit pas dépasser 30 caractères.';

    // `SaisieReproducteurAction::verifierLesDates` — seulement quand tout le reste est valable (comme le web).
    if (e.isEmpty && naissance != null && _jour(naissance).isAfter(_jour(entree!))) {
      e['birth_date'] = messageNaissanceApresEntree;
    }
    return e;
  }

  // ── Écriture ─────────────────────────────────────────────────────────────────────────────────────────────────────

  /// `saveAnimal()` (création) : le sujet est écrit `pending`, `actif`, catégorie « reproducteur » — l'effectif de la
  /// bande n'est PAS touché. Lève [ReproducteurRefuse] (messages du web, sous leur champ).
  Future<Sujet> enregistrer(FormulaireReproducteur f) async {
    final erreurs = await _valider(f);
    if (erreurs.isNotEmpty) throw ReproducteurRefuse(erreurs);

    final espece = await (_db.select(_db.livestockSpecies)..where((t) => t.id.equals(f.speciesId))).getSingle();
    final lot = f.lotId.isEmpty ? null : await (_db.select(_db.livestockLots)..where((t) => t.id.equals(f.lotId))).getSingle();
    final id = _uuid.v4();

    await _db.into(_db.animals).insert(
      AnimalsCompanion.insert(
        id: id,
        identifier: f.identifier,
        speciesId: Value(f.speciesId),
        speciesLabel: Value(espece.label),
        lotId: Value(lot?.id),
        lotCode: Value(lot?.code),
        category: const Value('reproducteur'),
        sex: Value(f.sex),
        breed: Value(_vide(f.breed)),
        birthDate: Value(f.birthDate == null ? null : _jour(f.birthDate!)),
        entryDate: Value(_jour(f.entryDate!)),
        origin: Value(_vide(f.origin)),
        cage: Value(_vide(f.cage)),
        status: const Value('actif'),
        isActive: const Value(true),
        updatedAt: Value(HeureBenin.versInstant(_horloge())),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
    _gestes?.signaler();
    return (await sujet(id))!;
  }

  /// `saveAnimal()` (édition) : la fiche du sujet — jamais son statut ni sa sortie. Une modification qui ne change rien
  /// n'écrit rien (aucune mise en file).
  Future<Sujet> modifier(String id, FormulaireReproducteur f) async {
    final a = await sujet(id);
    if (a == null) throw const ReproducteurRefuse({'sujet': 'Reproducteur introuvable sur ce poste.'});

    final erreurs = await _valider(f, sauf: id);
    if (erreurs.isNotEmpty) throw ReproducteurRefuse(erreurs);

    final espece = await (_db.select(_db.livestockSpecies)..where((t) => t.id.equals(f.speciesId))).getSingle();
    final lot = f.lotId.isEmpty ? null : await (_db.select(_db.livestockLots)..where((t) => t.id.equals(f.lotId))).getSingle();
    final naissance = f.birthDate == null ? null : _jour(f.birthDate!);
    final entree = _jour(f.entryDate!);

    final change = a.identifier != f.identifier ||
        a.speciesId != f.speciesId ||
        a.lotId != lot?.id ||
        a.sex != f.sex ||
        a.breed != _vide(f.breed) ||
        (a.birthDate == null ? null : _jour(a.birthDate!)) != naissance ||
        (a.entryDate == null ? null : _jour(a.entryDate!)) != entree ||
        a.origin != _vide(f.origin) ||
        a.cage != _vide(f.cage);
    if (!change) return a;

    await (_db.update(_db.animals)..where((t) => t.id.equals(id))).write(
      AnimalsCompanion(
        identifier: Value(f.identifier),
        speciesId: Value(f.speciesId),
        speciesLabel: Value(espece.label),
        lotId: Value(lot?.id),
        lotCode: Value(lot?.code),
        sex: Value(f.sex),
        breed: Value(_vide(f.breed)),
        birthDate: Value(naissance),
        entryDate: Value(entree),
        origin: Value(_vide(f.origin)),
        cage: Value(_vide(f.cage)),
        updatedAt: Value(HeureBenin.versInstant(_horloge())),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
    _gestes?.signaler();
    return (await sujet(id))!;
  }

  /// `confirmExit()` : statut, date et motif ; le sujet reste (archivage LOGIQUE) et l'effectif de la bande n'est pas
  /// touché. `true` : sortie écrite ; `false` : la même sortie était déjà enregistrée (rien n'est écrit). Un sujet déjà
  /// sorti autrement est refusé.
  Future<bool> sortir(String id, FormulaireSortie f) async {
    final a = await sujet(id);
    if (a == null) throw const ReproducteurRefuse({'sujet': 'Reproducteur introuvable sur ce poste.'});

    final e = <String, String>{};
    if (f.status.isEmpty) {
      e['exitStatus'] = 'Le champ statut de sortie est obligatoire.';
    } else if (!const ['reforme', 'vendu', 'mort'].contains(f.status)) {
      e['exitStatus'] = "La valeur sélectionnée pour le champ statut de sortie n'est pas valide.";
    }
    final date = f.exitDate;
    if (date == null) {
      e['exit_date'] = 'Le champ date de sortie est obligatoire.';
    } else if (_jour(date).isAfter(_aujourdhui)) {
      e['exit_date'] = "Le champ date de sortie doit être une date antérieure ou égale à aujourd'hui.";
    }
    if (f.reason.runes.length > 150) e['exit_reason'] = 'Le champ motif ne doit pas dépasser 150 caractères.';
    if (e.isNotEmpty) throw ReproducteurRefuse(e);

    final jour = _jour(date!);
    if (a.status != 'actif') {
      final meme = a.status == f.status &&
          a.exitDate != null &&
          _jour(a.exitDate!) == jour &&
          (a.exitReason ?? '') == f.reason;
      if (meme) return false;
      throw ReproducteurRefuse({'exitStatus': messageDejaSorti(a.status)});
    }
    if (a.entryDate != null && jour.isBefore(_jour(a.entryDate!))) {
      throw const ReproducteurRefuse({'exit_date': messageSortieAvantEntree});
    }

    await (_db.update(_db.animals)..where((t) => t.id.equals(id))).write(
      AnimalsCompanion(
        status: Value(f.status),
        exitDate: Value(jour),
        exitReason: Value(_vide(f.reason)),
        updatedAt: Value(HeureBenin.versInstant(_horloge())),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
    _gestes?.signaler();
    return true;
  }
}
