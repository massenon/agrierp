import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/temps/heure_benin.dart';

/// État de synchronisation d'une ligne saisie au poste (ticket H9b).
///
/// ➕ AJOUT DU POSTE : le web écrit directement en base, il n'a pas d'« en attente ». Le poste le montre, comme
/// ses autres écrans qui envoient : une modification en attente ou refusée ne doit pas passer pour appliquée.
class EtatEnvoi {
  const EtatEnvoi({required this.statut, this.motifRefus});

  final SyncStatus statut;

  /// Motif du refus du serveur, MOT POUR MOT (`sync_conflicts`) — seulement en `conflict`.
  final String? motifRefus;

  bool get enAttente => statut == SyncStatus.pending;
  bool get refuse => statut == SyncStatus.conflict;
}

/// Une ligne de « Fiche de Rationnement des Animaux ».
class LigneRation {
  const LigneRation({
    required this.ration,
    required this.especeLisible,
    required this.etat,
  });

  final FeedRationStandard ration;

  /// Le code espèce rendu lisible — `cuniculture` → « Cuniculture » (classe `capitalize` du Blade).
  final String especeLisible;

  final EtatEnvoi etat;
}

/// Une ligne du « Calendrier de Prophylaxie », pour une espèce.
class LigneProphylaxie {
  const LigneProphylaxie({required this.entree, required this.etat});

  final ProphylaxisScheduleStandard entree;

  final EtatEnvoi etat;

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
  const LigneProvende({required this.type, required this.etat});

  final FeedType type;

  final EtatEnvoi etat;
}

/// Une espèce proposée dans « Espèce Cible * » (`LivestockSpecies::enabled()->orderBy('label')`).
class OptionEspece {
  const OptionEspece({
    required this.id,
    required this.code,
    required this.libelle,
  });

  final String id;
  final String code;
  final String libelle;
}

/// Les trois espèces des sous-onglets de prophylaxie, dans l'ordre du Blade
/// (`parametres-elevage.blade.php`, boutons `$set('prophySpecies', …)`).
enum EspeceProphylaxie {
  lapins('cuniculture', '🐰 Cuniculture (Lapins)'),
  volailles('aviculture', '🐔 Aviculture (Volailles)'),
  porcs('porciculture', '🐖 Porciculture (Porcs)');

  const EspeceProphylaxie(this.code, this.libelle);

  final String code;
  final String libelle;
}

/// Les neuf formats de numérotation, sous leur clé du serveur (`numbering.*` du composant web).
typedef FormatsNumerotation = Map<String, String>;

class DonneesParametresElevage {
  const DonneesParametresElevage({
    required this.rations,
    required this.prophylaxies,
    required this.provendes,
    required this.numerotation,
    required this.etatNumerotation,
    required this.especesProvende,
    required this.rappelSoinsJours,
    required this.etatRappelSoins,
  });

  /// Lignes ACTIVES seulement (`where('is_active', true)` du composant) : une ligne archivée disparaît.
  final List<LigneRation> rations;
  final List<LigneProphylaxie> prophylaxies;
  final List<LigneProvende> provendes;

  /// ⚠️ `null` tant qu'aucun tirage n'a eu lieu : les préfixes ne sont pas
  /// devinables. Afficher « R » par défaut ferait croire à une convention
  /// confirmée alors qu'on ne l'a jamais lue.
  final ElevageNumberingSetting? numerotation;
  final EtatEnvoi? etatNumerotation;

  final List<OptionEspece> especesProvende;

  /// Délai du rappel des soins planifiés (R-SOINS-01) ; `null` : jamais tiré, inconnu du poste.
  final int? rappelSoinsJours;
  final EtatEnvoi? etatRappelSoins;

  List<LigneProphylaxie> prophylaxiePour(EspeceProphylaxie espece) =>
      prophylaxies.where((p) => p.entree.speciesCode == espece.code).toList();
}

/// Lectures et écritures de `parametres-elevage.blade.php` (composant `App\Livewire\Elevage\ParametresElevage`).
///
/// ⚠️⚠️ **TICKET H9b — DÉCISION CLIENT D-H9 (19/10/2026) : « PARAMÈTRES ÉLEVAGE MODIFIABLES SUR LE POSTE ET LE
/// WEB ».** Jusqu'ici ces quatre onglets étaient en lecture seule, parce que le serveur ignorait tout envoi les
/// concernant (`referentiels_ignored`). Depuis le ticket H9b serveur, `RecordParametresElevageFromDeviceAction`
/// les accepte du droit `manage-elevage`, avec les validations du composant web, l'archivage logique et la
/// règle « dernier écrivain gagne ». Le poste écrit donc la saisie en `pending` (instant de SAISIE), le moteur
/// l'envoie, l'accusé la passe `synced`, un refus la passe `conflict` avec son motif.
///
/// ⚠️ **SUPPRIMER = ARCHIVER** (ticket 14.55 du web) : `is_active = false`. La ligne quitte l'écran et les
/// calculs (provende du Dashboard Élevage, protocole de Soins et Vaccins), et reste restaurable côté serveur.
///
/// ⚠️ **CES TABLES PILOTENT DES ÉCRANS DÉJÀ LIVRÉS** : une ration corrigée ici change la provende calculée
/// au poste dès l'enregistrement, avant même l'envoi — comme au web, où l'effet est immédiat.
class ParametresElevageRepository {
  ParametresElevageRepository({
    required this.database,
    DateTime Function()? maintenant,
    Uuid? uuid,
  }) : _maintenant = maintenant ?? HeureBenin.maintenant,
       _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final DateTime Function() _maintenant;
  final Uuid _uuid;

  /// Codes espèce → libellé, tel que la ferme les nomme.
  static const especes = <String, String>{
    'cuniculture': 'Cuniculture',
    'aviculture': 'Aviculture',
    'porciculture': 'Porciculture',
    'heliciculture': 'Héliciculture',
  };

  /// Options « Espèce * » de la modale Ration, dans l'ordre du Blade (`<option value="aviculture">…`).
  static const especesRation = <(String, String)>[
    ('aviculture', 'Aviculture (Volailles)'),
    ('cuniculture', 'Cuniculture (Lapins)'),
    ('porciculture', 'Porciculture (Porcs)'),
  ];

  /// Clés des neuf formats et leur longueur maximale (`saveNumbering()` du composant web, `max:`).
  static const longueursNumerotation = <String, int>{
    'bande_format': 50,
    'lapine_prefix': 10,
    'male_prefix': 10,
    'truie_prefix': 10,
    'verrat_prefix': 10,
    'portee_prefix': 10,
    'volaille_prefix': 20,
    'parc_prefix': 20,
    'escargot_prefix': 20,
  };

  static String especeLisible(String code) =>
      especes[code] ?? (code.isEmpty ? '—' : code);

  // ── Lecture ─────────────────────────────────────────────────────────────────────────────────────────

  Future<DonneesParametresElevage> charger() async {
    final rations = await (database.select(
      database.feedRationStandards,
    )..where((t) => t.isActive.equals(true))).get();
    final prophylaxies = await (database.select(
      database.prophylaxisScheduleStandards,
    )..where((t) => t.isActive.equals(true))).get();
    final provendes = await (database.select(
      database.feedTypes,
    )..where((t) => t.isActive.equals(true))).get();
    final numerotation = await database
        .select(database.elevageNumberingSettings)
        .getSingleOrNull();
    final entreprise = await database
        .select(database.companySettings)
        .getSingleOrNull();
    final especesActives = await database
        .select(database.livestockSpecies)
        .get();

    // Motifs des refus, MOT POUR MOT, par table et identifiant.
    final refus = <String, String>{
      for (final c in await database.select(database.syncConflicts).get())
        '${c.sourceTable}:${c.recordId}': c.reason,
    };
    EtatEnvoi etat(SyncStatus statut, String cle) => EtatEnvoi(
      statut: statut,
      motifRefus: statut == SyncStatus.conflict ? refus[cle] : null,
    );

    return DonneesParametresElevage(
      // `orderBy('species_code')->orderBy('ration_g_per_day')` du composant (stade en dernier recours).
      rations:
          (rations.toList()..sort((a, b) {
                final espece = a.speciesCode.compareTo(b.speciesCode);
                if (espece != 0) return espece;
                final grammes = a.rationGPerDay.compareTo(b.rationGPerDay);
                return grammes != 0
                    ? grammes
                    : _cle(a.stageLabel).compareTo(_cle(b.stageLabel));
              }))
              .map(
                (r) => LigneRation(
                  ration: r,
                  especeLisible: especeLisible(r.speciesCode),
                  etat: etat(r.syncStatus, 'feed_ration_standards:${r.id}'),
                ),
              )
              .toList(),
      // `orderBy('created_at')` du composant. ⚠️ Deux échéances créées au même instant (semences du serveur)
      // n'ont pas d'ordre garanti au web non plus : le jour de cycle puis le libellé les départagent ici.
      prophylaxies:
          (prophylaxies.toList()..sort((a, b) {
                final creation = _avantNul(a.createdAt, b.createdAt);
                if (creation != 0) return creation;
                final jour = (a.cycleDayStart ?? 9999).compareTo(
                  b.cycleDayStart ?? 9999,
                );
                return jour != 0
                    ? jour
                    : _cle(a.periodLabel).compareTo(_cle(b.periodLabel));
              }))
              .map(
                (p) => LigneProphylaxie(
                  entree: p,
                  etat: etat(
                    p.syncStatus,
                    'prophylaxis_schedule_standards:${p.id}',
                  ),
                ),
              )
              .toList(),
      // `orderBy('name')` — collation MySQL insensible à la casse et aux accents, d'où la clé normalisée.
      provendes:
          (provendes.toList()
                ..sort((a, b) => _cle(a.name).compareTo(_cle(b.name))))
              .map(
                (t) => LigneProvende(
                  type: t,
                  etat: etat(t.syncStatus, 'feed_types:${t.id}'),
                ),
              )
              .toList(),
      numerotation: numerotation,
      etatNumerotation: numerotation == null
          ? null
          : etat(
              numerotation.syncStatus,
              '${ParametresElevageCles.numerotation}:${ParametresElevageCles.numerotation}',
            ),
      especesProvende: [
        for (final e in especesActives)
          OptionEspece(id: e.id, code: e.code, libelle: e.label),
      ]..sort((a, b) => _cle(a.libelle).compareTo(_cle(b.libelle))),
      rappelSoinsJours: entreprise?.rappelSoinsJours,
      etatRappelSoins: entreprise == null
          ? null
          : etat(
              entreprise.syncStatus,
              '${ParametresElevageCles.rappelSoins}:${ParametresElevageCles.rappelSoins}',
            ),
    );
  }

  // ── Validation (règles du composant web, messages du serveur `MotifsRefusPush`) ─────────────────────

  static String _obligatoire(String champ) =>
      'Le champ $champ est obligatoire.';
  static String _tropLong(String champ, int max) =>
      'Le champ $champ dépasse le maximum autorisé ($max).';
  static String _tropPetit(String champ, num min) =>
      'Le champ $champ est inférieur au minimum autorisé (${_nombre(min)}).';

  /// `saveRation()` : espèce dans la liste, stade `required|max:100`, grammes `required|integer|min:1`.
  static List<String> erreursRation({
    required String? espece,
    required String stade,
    required String grammes,
  }) {
    final g = int.tryParse(grammes.trim());
    return [
      if (espece == null || !especesRation.any((e) => e.$1 == espece))
        _obligatoire('Espèce'),
      if (stade.trim().isEmpty)
        _obligatoire("Stade Physiologique / Tranche d'Âge"),
      if (stade.trim().length > 100)
        _tropLong("Stade Physiologique / Tranche d'Âge", 100),
      if (grammes.trim().isEmpty)
        _obligatoire('Ration Normative (g/tête/jour)')
      else if (g == null)
        'Le champ Ration Normative (g/tête/jour) doit être un nombre entier.'
      else if (g < 1)
        _tropPetit('Ration Normative (g/tête/jour)', 1),
    ];
  }

  /// `saveProphy()` : période `max:100`, traitement, produit et dose `max:150`, rémanence `integer|min:0`.
  static List<String> erreursEcheance({
    required String periode,
    required String traitement,
    required String produit,
    required String dose,
    required String remanence,
  }) {
    final j = int.tryParse(remanence.trim());
    return [
      for (final (valeur, champ, max) in [
        (periode, 'Jour / Âge', 100),
        (traitement, 'Traitement Prévu', 150),
        (produit, 'Produit Conseillé', 150),
        (dose, 'Dose', 150),
      ]) ...[
        if (valeur.trim().isEmpty) _obligatoire(champ),
        if (valeur.trim().length > max) _tropLong(champ, max),
      ],
      if (remanence.trim().isEmpty)
        _obligatoire('Délai de Rémanence')
      else if (j == null)
        'Le champ Délai de Rémanence doit être un nombre entier.'
      else if (j < 0)
        _tropPetit('Délai de Rémanence', 0),
    ];
  }

  /// `saveProvende()` : nom `max:150`, espèce connue, sac `numeric|min:0.01`, prix `numeric|min:0`.
  static List<String> erreursProvende({
    required String nom,
    required String? especeId,
    required List<OptionEspece> especes,
    required String sac,
    required String prix,
  }) {
    final s = double.tryParse(sac.trim().replaceAll(',', '.'));
    final p = double.tryParse(prix.trim().replaceAll(',', '.'));
    return [
      if (nom.trim().isEmpty) _obligatoire("Nom du Type d'Aliment"),
      if (nom.trim().length > 150) _tropLong("Nom du Type d'Aliment", 150),
      if (especeId == null || !especes.any((e) => e.id == especeId))
        _obligatoire('Espèce Cible'),
      if (sac.trim().isEmpty)
        _obligatoire('Poids Sac Standard (Kg)')
      else if (s == null)
        'Le champ Poids Sac Standard (Kg) doit être un nombre.'
      else if (s < 0.01)
        _tropPetit('Poids Sac Standard (Kg)', 0.01),
      if (prix.trim().isEmpty)
        _obligatoire('Prix Indicatif (FCFA/Kg)')
      else if (p == null)
        'Le champ Prix Indicatif (FCFA/Kg) doit être un nombre.'
      else if (p < 0)
        _tropPetit('Prix Indicatif (FCFA/Kg)', 0),
    ];
  }

  /// `saveNumbering()` : les neuf formats `required|string|max:…`.
  static List<String> erreursNumerotation(
    FormatsNumerotation formats,
    Map<String, String> libelles,
  ) => [
    for (final MapEntry(key: cle, value: max) in longueursNumerotation.entries)
      if ((formats[cle] ?? '').trim().isEmpty)
        _obligatoire(libelles[cle] ?? cle)
      else if (formats[cle]!.trim().length > max)
        _tropLong(libelles[cle] ?? cle, max),
  ];

  /// `saveRappelSoins()` : `required|integer|min:0|max:30` (attribut « délai de rappel »).
  static List<String> erreursRappelSoins(String saisie) {
    final n = int.tryParse(saisie.trim());
    return [
      if (saisie.trim().isEmpty)
        _obligatoire('délai de rappel')
      else if (n == null)
        'Le champ délai de rappel doit être un nombre entier.'
      else if (n < 0)
        _tropPetit('délai de rappel', 0)
      else if (n > 30)
        _tropLong('délai de rappel', 30),
    ];
  }

  // ── Écritures (toujours `pending`, instant de SAISIE) ───────────────────────────────────────────────

  /// `saveRation()` — création (UUID tiré au poste) ou modification. Rend l'identifiant.
  Future<String> enregistrerRation({
    String? id,
    required String espece,
    required String stade,
    required int grammes,
  }) async {
    final cle = id ?? _uuid.v4();
    final ligne = FeedRationStandardsCompanion.insert(
      id: cle,
      speciesCode: espece,
      stageLabel: stade.trim(),
      rationGPerDay: grammes.toDouble(),
      isActive: const Value(true),
      syncStatus: const Value(SyncStatus.pending),
      updatedAt: Value(HeureBenin.versInstant(_maintenant())),
    );
    await database
        .into(database.feedRationStandards)
        .insert(ligne, onConflict: DoUpdate((_) => ligne));
    return cle;
  }

  /// `deleteRation()` — ARCHIVAGE, jamais de suppression (ticket 14.55).
  Future<void> archiverRation(String id) =>
      (database.update(
        database.feedRationStandards,
      )..where((t) => t.id.equals(id))).write(
        FeedRationStandardsCompanion(
          isActive: const Value(false),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(HeureBenin.versInstant(_maintenant())),
        ),
      );

  /// `saveProphy()` — l'espèce est celle du sous-onglet ouvert (`$this->prophySpecies`), comme au web.
  Future<String> enregistrerEcheance({
    String? id,
    required String espece,
    required String periode,
    required String traitement,
    required String produit,
    required String dose,
    required int remanence,
  }) async {
    final maintenant = _maintenant();
    final cle = id ?? _uuid.v4();
    final existante = id == null
        ? null
        : await (database.select(
            database.prophylaxisScheduleStandards,
          )..where((t) => t.id.equals(id))).getSingleOrNull();
    final ligne = ProphylaxisScheduleStandardsCompanion.insert(
      id: cle,
      speciesCode: espece,
      periodLabel: periode.trim(),
      treatment: traitement.trim(),
      productRecommended: Value(produit.trim()),
      dosage: Value(dose.trim()),
      withdrawalDays: Value(remanence),
      // Les bornes de cycle ne se saisissent pas (le web non plus) : une modification garde celles du serveur.
      cycleDayStart: Value(existante?.cycleDayStart),
      cycleDayEnd: Value(existante?.cycleDayEnd),
      // Tri du web (`created_at`) : une échéance créée ici se place en dernier, une modification garde sa place.
      createdAt: Value(existante == null ? maintenant : existante.createdAt),
      isActive: const Value(true),
      syncStatus: const Value(SyncStatus.pending),
      updatedAt: Value(HeureBenin.versInstant(maintenant)),
    );
    await database
        .into(database.prophylaxisScheduleStandards)
        .insert(ligne, onConflict: DoUpdate((_) => ligne));
    return cle;
  }

  Future<void> archiverEcheance(String id) =>
      (database.update(
        database.prophylaxisScheduleStandards,
      )..where((t) => t.id.equals(id))).write(
        ProphylaxisScheduleStandardsCompanion(
          isActive: const Value(false),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(HeureBenin.versInstant(_maintenant())),
        ),
      );

  /// `saveProvende()` — l'espèce part par son identifiant ; son code et son libellé sont gardés pour
  /// l'affichage (le poste n'a pas de table des espèces désactivées).
  Future<String> enregistrerProvende({
    String? id,
    required String nom,
    required OptionEspece espece,
    required double sacKg,
    required double prixKg,
  }) async {
    final cle = id ?? _uuid.v4();
    final ligne = FeedTypesCompanion.insert(
      id: cle,
      name: nom.trim(),
      speciesId: Value(espece.id),
      speciesCode: Value(espece.code),
      speciesLabel: Value(espece.libelle),
      standardBagWeightKg: Value(sacKg),
      pricePerKg: Value(prixKg),
      isActive: const Value(true),
      syncStatus: const Value(SyncStatus.pending),
      updatedAt: Value(HeureBenin.versInstant(_maintenant())),
    );
    await database
        .into(database.feedTypes)
        .insert(ligne, onConflict: DoUpdate((_) => ligne));
    return cle;
  }

  Future<void> archiverProvende(String id) =>
      (database.update(
        database.feedTypes,
      )..where((t) => t.id.equals(id))).write(
        FeedTypesCompanion(
          isActive: const Value(false),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(HeureBenin.versInstant(_maintenant())),
        ),
      );

  /// `saveNumbering()` — les neuf formats, ligne unique `unique`.
  Future<void> enregistrerNumerotation(FormatsNumerotation f) async {
    String v(String cle) => (f[cle] ?? '').trim();
    final ligne = ElevageNumberingSettingsCompanion.insert(
      id: const Value('unique'),
      bandeFormat: Value(v('bande_format')),
      lapinePrefix: Value(v('lapine_prefix')),
      malePrefix: Value(v('male_prefix')),
      truiePrefix: Value(v('truie_prefix')),
      verratPrefix: Value(v('verrat_prefix')),
      porteePrefix: Value(v('portee_prefix')),
      volaillePrefix: Value(v('volaille_prefix')),
      parcPrefix: Value(v('parc_prefix')),
      escargotPrefix: Value(v('escargot_prefix')),
      syncStatus: const Value(SyncStatus.pending),
      updatedAt: Value(HeureBenin.versInstant(_maintenant())),
    );
    await database
        .into(database.elevageNumberingSettings)
        .insert(ligne, onConflict: DoUpdate((_) => ligne));
  }

  /// `saveRappelSoins()` — SEUL champ de l'entreprise que le poste écrit ; l'identité n'est pas touchée.
  Future<void> enregistrerRappelSoins(int jours) async {
    final ligne = CompanySettingsCompanion.insert(
      id: const Value('unique'),
      rappelSoinsJours: Value(jours),
      syncStatus: const Value(SyncStatus.pending),
      updatedAt: Value(HeureBenin.versInstant(_maintenant())),
    );
    await database
        .into(database.companySettings)
        .insert(
          ligne,
          onConflict: DoUpdate(
            (_) => CompanySettingsCompanion(
              rappelSoinsJours: Value(jours),
              syncStatus: const Value(SyncStatus.pending),
              updatedAt: ligne.updatedAt,
            ),
          ),
        );
  }

  // ── Formats d'affichage du Blade ───────────────────────────────────────────────────────────────────

  /// `{{ $r->ration_g_per_day }} g` — la colonne est entière au serveur.
  static String grammes(double valeur) => '${valeur.round()} g';

  /// `rtrim(rtrim(number_format($kg, 2, '.', ''), '0'), '.') . ' Kg'` — « 25 Kg », « 12.5 Kg ».
  static String sac(double? kg) {
    if (kg == null) return '—';
    var texte = _arrondi(kg, 2).toStringAsFixed(2);
    texte = texte.replaceFirst(RegExp(r'0+$'), '');
    texte = texte.replaceFirst(RegExp(r'\.$'), '');
    return '$texte Kg';
  }

  /// `number_format($prix, 0, ',', ' ') . ' FCFA'` — « 1 250 FCFA ».
  static String prix(double? fcfa) {
    if (fcfa == null) return '—';
    final entier = _arrondi(fcfa, 0).round();
    final chiffres = entier.abs().toString();
    final groupes = <String>[];
    for (var i = chiffres.length; i > 0; i -= 3) {
      groupes.insert(0, chiffres.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${entier < 0 ? '-' : ''}${groupes.join(' ')} FCFA';
  }

  /// Valeur d'un champ numérique pré-rempli (`wire:model` d'un float) : « 25 », « 12.5 ».
  static String saisie(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.round().toString() : v.toString();
  }

  /// Arrondi « demi loin de zéro » de PHP (`number_format`), pas l'arrondi bancaire.
  static double _arrondi(double v, int decimales) {
    var facteur = 1.0;
    for (var i = 0; i < decimales; i++) {
      facteur *= 10;
    }
    final n =
        (v.abs() * facteur + 1e-9).floor() +
        ((v.abs() * facteur + 1e-9) % 1 >= 0.5 ? 1 : 0);
    return (v < 0 ? -n : n) / facteur;
  }

  static String _nombre(num n) =>
      n == n.roundToDouble() ? n.round().toString() : n.toString();

  /// Clé de tri insensible à la casse et aux accents (collation du serveur).
  static String _cle(String texte) {
    const accents = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'í': 'i',
      'ô': 'o',
      'ö': 'o',
      'ó': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ú': 'u',
      'ÿ': 'y',
      'œ': 'oe',
      'æ': 'ae',
    };
    final sortie = StringBuffer();
    for (final c in texte.toLowerCase().split('')) {
      sortie.write(accents[c] ?? c);
    }
    return sortie.toString();
  }

  /// Instant de création croissant, l'inconnu en dernier.
  static int _avantNul(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }
}
