import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/sync/gestes_importants.dart';
import '../../core/temps/heure_benin.dart';
import '../stocks/pmp_service.dart';
import 'effectif_par_categorie.dart';
import 'jour_categories.dart';
import 'transferts_repository.dart';

/// Saisie d'une bande refusée AVANT toute écriture : un message par champ, ceux du web (`lang/fr/validation.php`).
/// Clés = les noms des propriétés du composant : `species_id`, `code`, `stage`, `created_date`, `quantity`,
/// `product_id`, `lot_origine_id`, `status`, et `bande` (la bande elle-même : archivée, introuvable).
class BandeRefusee implements Exception {
  const BandeRefusee(this.erreurs);

  final Map<String, String> erreurs;

  @override
  String toString() => erreurs.values.join(' ');
}

/// Ce que l'exploitant a saisi dans la modale « Nouvelle Bande » (`GestionBandes::saveLot`).
class FormulaireBande {
  const FormulaireBande({
    this.speciesId = '',
    this.code = '',
    this.stage = 'reproduction',
    this.createdDate,
    this.quantite = '',
    this.coutAcquisition = '',
    this.productId = '',
    this.lotOrigineId = '',
  });

  final String speciesId;
  final String code;
  final String stage;
  final DateTime? createdDate;

  /// Texte du champ « Quantité Initiale (Effectif) * » : vide = 0 (`public int $quantity = 0`).
  final String quantite;

  /// Texte du champ « Coût d'Acquisition (FCFA) » (`?int`).
  final String coutAcquisition;
  final String productId;
  final String lotOrigineId;
}

/// Une ligne du tableau « Bandes & Sujets » (`getLotsProperty()`).
class LigneBande {
  const LigneBande({
    required this.bande,
    required this.especeLibelle,
    required this.libelleStade,
    required this.mortalite,
    this.motifRefus,
  });

  final LivestockLot bande;
  final String? especeLibelle;

  /// `libelleStade()` : le libellé du stade selon l'espèce.
  final String libelleStade;

  /// `round((initial − actuel) / initial × 100, 1)`, ou `null` quand l'effectif initial est 0 (inconnu : « — »).
  final double? mortalite;

  /// Motif du serveur, mot pour mot, quand la dernière saisie de cette bande a été refusée (`conflict`).
  final String? motifRefus;
}

/// Les quatre cartes de `GestionBandes::getKpisProperty()`.
class IndicateursBandes {
  const IndicateursBandes({
    required this.bandesActives,
    required this.enReproduction,
    required this.effectifTotal,
    required this.alertesSanitaires,
  });

  final int bandesActives;
  final int enReproduction;
  final int effectifTotal;
  final int alertesSanitaires;
}

/// Le tiroir de détail d'une bande (`viewingLot`, `autonomieBande`, `suiviSanitaireBande`).
class DetailBande {
  const DetailBande({
    required this.bande,
    required this.especeLibelle,
    required this.libelleStade,
    required this.autonomie,
    required this.provendeBandeKg,
    required this.dateDerniereFiche,
    required this.remanence,
    required this.infirmerie,
    required this.mortsSurSeptJours,
    required this.mortaliteSurSeptJours,
    required this.derniersSoins,
  });

  final LivestockLot bande;
  final String? especeLibelle;
  final String libelleStade;

  /// Autonomie de la FILIÈRE (`AutonomieAlimentaireService::pourEspece`).
  final AutonomieAlimentaire autonomie;

  /// `feed_qty_kg` de la DERNIÈRE fiche de la bande ; `null` : inconnue (« — »).
  final double? provendeBandeKg;
  final DateTime? dateDerniereFiche;

  /// Délai d'attente en cours (le plus long), s'il y en a un.
  final VeterinaryWithdrawalPeriod? remanence;
  final int infirmerie;
  final int mortsSurSeptJours;
  final double? mortaliteSurSeptJours;
  final List<VeterinaryRecord> derniersSoins;
}

/// Ticket BS1 — « Bandes & Sujets » du poste : miroir de `App\Livewire\Elevage\GestionBandes`
/// et de `App\Actions\SaisieBandeAction` (le point de passage que partagent l'écran web et l'envoi du poste).
///
/// Hors ligne, le poste crée, modifie et archive ses bandes : la ligne est écrite tout de suite, `pending`, avec un
/// UUID créé ici ; le serveur la REJOUE à l'envoi par la même action que le web (mêmes règles, même audit), et un
/// refus devient un `conflict` avec son motif.
///
/// ⚠️ **L'EFFECTIF D'UNE BANDE EST CELUI DE SES FICHES** (cascade unique) : le poste ne renvoie `current_quantity` que
/// sur CORRECTION explicite de l'exploitant (`effectifCorrige`, « Modifier la Bande »), comme le web l'écrit.
/// ⚠️ **ARCHIVER N'EFFACE RIEN** (`is_active = false`) ; la ligne reste, un second archivage ne fait rien.
class BandesRepository {
  BandesRepository({
    required AppDatabase database,
    required String deviceId,
    TransfertsRepository? transferts,
    GestesImportants? gestes,
    DateTime Function()? horloge,
  }) : _db = database,
       _transferts = transferts ?? TransfertsRepository(database: database, deviceId: deviceId),
       // ignore: prefer_initializing_formals
       _gestes = gestes,
       _horloge = horloge ?? HeureBenin.maintenant;

  final AppDatabase _db;
  final TransfertsRepository _transferts;
  final GestesImportants? _gestes;
  final DateTime Function() _horloge;
  static const _uuid = Uuid();

  /// `SaisieBandeAction::MESSAGE_ARCHIVEE`, mot pour mot.
  static const messageArchivee = 'Cette bande est archivée : elle ne peut plus être modifiée.';

  /// Toasts de `GestionBandes`, mot pour mot.
  static const toastCreee = 'Bande créée avec succès.';
  static const toastModifiee = 'Bande modifiée avec succès.';
  static const toastArchivee = 'Bande archivée avec succès.';

  /// `LivestockLot::stadesPourEspece()` : Reproducteur / Jeune / Sous-mères pour les lapins (décision client du
  /// 17/10/2026), les quatre stades génériques sinon. Valeur STOCKÉE => libellé.
  static Map<String, String> stadesPourEspece(String? codeEspece) => codeEspece == 'cuniculture'
      ? const {'reproduction': 'Reproducteur', 'engraissement': 'Jeune', 'croissance': 'Sous-mères'}
      : const {
          'reproduction': 'Reproduction',
          'croissance': 'Croissance',
          'ponte': 'Ponte',
          'engraissement': 'Engraissement',
        };

  /// `libelleStade()` : `ucfirst($stage)` si le stade n'est pas connu.
  static String libelleStade(String? codeEspece, String? stade) {
    final connu = stadesPourEspece(codeEspece)[stade];
    if (connu != null) return connu;
    final s = stade ?? '';
    return s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
  }

  /// `{{ $mortaliteRate }}%` du Blade : `round(x, 1)` de PHP rendu sans zéro inutile (`10` et non `10.0`).
  static String formaterMortalite(double? taux) {
    if (taux == null) return '—';
    final dixiemes = (taux * 10).round();
    final texte = dixiemes % 10 == 0 ? '${dixiemes ~/ 10}' : (dixiemes / 10).toString();
    return '$texte%';
  }

  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

  // ── Lecture ──────────────────────────────────────────────────────────────────────────────────────────────────────

  /// `LivestockLot::vivantes()` : `status = actif` ET `is_active`, les DEUX (correctif « ARCHIVAGE » du web).
  Future<List<LivestockLot>> _vivantes() => (_db.select(
    _db.livestockLots,
  )..where((t) => t.status.equals('actif') & t.isActive.equals(true))).get();

  Future<IndicateursBandes> indicateurs() async {
    final vivantes = await _vivantes();
    final aujourdhui = _jour(_horloge());
    final ids = {for (final b in vivantes) b.id};
    final periodes = await (_db.select(
      _db.veterinaryWithdrawalPeriods,
    )..where((t) => t.endDate.isBiggerOrEqualValue(aujourdhui))).get();

    return IndicateursBandes(
      bandesActives: vivantes.length,
      enReproduction: vivantes.where((b) => b.stage == 'reproduction').length,
      effectifTotal: vivantes.fold<int>(0, (s, b) => s + b.currentQuantity),
      alertesSanitaires: {for (final p in periodes) if (ids.contains(p.lotId)) p.lotId}.length,
    );
  }

  /// `getSpeciesOptionsProperty()` : `LivestockSpecies::enabled()` (code présent et actif dans `modules_config`),
  /// par libellé.
  Future<List<EspeceElevage>> especes() async {
    final actifs = {
      for (final m in await _db.select(_db.modulesConfig).get())
        if (m.isEnabled) m.speciesCode,
    };
    final toutes = await _db.select(_db.livestockSpecies).get();
    return [
      for (final e in toutes)
        if (actifs.contains(e.code)) e,
    ]..sort((a, b) => cleCommeLeServeur(a.label).compareTo(cleCommeLeServeur(b.label)));
  }

  /// `getLotsProperty()` : bandes non archivées, recherche sur le code, filtre d'espèce, les plus récentes d'abord.
  Future<List<LigneBande>> bandes({String recherche = '', String filiere = ''}) async {
    final especes = {for (final e in await _db.select(_db.livestockSpecies).get()) e.id: e};
    final refus = await _motifsDeRefus();
    final filtre = cleCommeLeServeur(recherche);

    final lignes = [
      for (final b in await (_db.select(_db.livestockLots)..where((t) => t.isActive.equals(true))).get())
        if (recherche.isEmpty || cleCommeLeServeur(b.code).contains(filtre))
          if (filiere.isEmpty || (especes[b.speciesId]?.code ?? b.speciesCode) == filiere) b,
    ]..sort((a, b) {
        final c = (b.createdDate ?? DateTime(1970)).compareTo(a.createdDate ?? DateTime(1970));
        return c != 0 ? c : a.code.compareTo(b.code);
      });

    return [
      for (final b in lignes)
        LigneBande(
          bande: b,
          especeLibelle: especes[b.speciesId]?.label,
          libelleStade: libelleStade(especes[b.speciesId]?.code ?? b.speciesCode, b.stage),
          mortalite: b.initialQuantity > 0
              ? ((b.initialQuantity - b.currentQuantity) / b.initialQuantity * 1000).round() / 10
              : null,
          motifRefus: b.syncStatus == SyncStatus.conflict ? refus[b.id] : null,
        ),
    ];
  }

  Future<Map<String, String>> _motifsDeRefus() async => {
    for (final c in await (_db.select(_db.syncConflicts)..where((t) => t.sourceTable.equals('livestock_lots'))).get())
      c.recordId: c.reason,
  };

  /// `LivestockLot::suggestNextCode()` : le prochain code libre de l'espèce, d'après les préfixes de la numérotation
  /// (`elevage_numbering_settings`, valeurs par défaut de la migration si la ligne manque).
  Future<String> codeSuggere(String speciesId) async {
    final espece = await (_db.select(_db.livestockSpecies)..where((t) => t.id.equals(speciesId))).getSingleOrNull();
    if (espece == null) return '';
    final reglage = await (_db.select(_db.elevageNumberingSettings)..limit(1)).getSingleOrNull();
    final prefixe = switch (espece.code) {
      'cuniculture' => 'LOT-LAP',
      'aviculture' => reglage?.volaillePrefix ?? 'LOT-VOL',
      'porciculture' => 'LOT-POR',
      'helico' => reglage?.escargotPrefix ?? 'FOSSE',
      _ => 'LOT',
    };
    final debut = cleCommeLeServeur('$prefixe-');
    var dernier = 0;
    for (final b in await _db.select(_db.livestockLots).get()) {
      if (!cleCommeLeServeur(b.code).startsWith(debut)) continue;
      // `(int) preg_replace('/\D/', '', substr(strrchr($code, '-'), 1))`.
      final suffixe = b.code.substring(b.code.lastIndexOf('-') + 1);
      final n = int.tryParse(suffixe.replaceAll(RegExp(r'\D'), '')) ?? 0;
      if (n > dernier) dernier = n;
    }
    return '$prefixe-${dernier + 1}';
  }

  /// `getProduitsCandidatsProperty()` : produits actifs de l'espèce, hors intrants (`ALI-%`, `MED-%`), par nom.
  Future<List<Product>> produitsCandidats(String speciesId) async {
    if (speciesId.isEmpty) return const [];
    return [
      for (final p in await _db.select(_db.products).get())
        if (p.isActive &&
            p.speciesId == speciesId &&
            !cleCommeLeServeur(p.sku).startsWith('ali-') &&
            !cleCommeLeServeur(p.sku).startsWith('med-'))
          p,
    ]..sort((a, b) => cleCommeLeServeur(a.name).compareTo(cleCommeLeServeur(b.name)));
  }

  /// `getBandesOriginePossiblesProperty()` : bandes non archivées de l'espèce choisie, par code.
  Future<List<LivestockLot>> bandesOrigine(String speciesId) async {
    if (speciesId.isEmpty) return const [];
    return (_db.select(_db.livestockLots)
          ..where((t) => t.speciesId.equals(speciesId) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.code)]))
        .get();
  }

  /// Le tiroir de détail (`view($id)`).
  Future<DetailBande?> detail(String id) async {
    final bande = await (_db.select(_db.livestockLots)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (bande == null) return null;
    final especes = await _db.select(_db.livestockSpecies).get();
    final espece = especes.where((e) => e.id == bande.speciesId).firstOrNull;
    final codeEspece = espece?.code ?? bande.speciesCode;
    final aujourdhui = _jour(_horloge());

    final fiches = await (_db.select(_db.livestockDailyEntries)..where((t) => t.lotId.equals(id))).get();
    final derniere = ([...fiches]..sort((a, b) => b.entryDate.compareTo(a.entryDate))).firstOrNull;

    // `AutonomieAlimentaireService::pourEspece()` : provende servie à chaque bande VIVANTE de la filière, prise sur sa
    // dernière fiche ; une bande vivante dont la dernière fiche n'a pas de provende connue rend la consommation
    // inconnue (jamais 0).
    double? consommation = 0;
    final vivantes = [for (final b in await _vivantes()) if (b.speciesId == bande.speciesId) b];
    for (final b in vivantes) {
      final f = ([
        for (final x in await (_db.select(_db.livestockDailyEntries)..where((t) => t.lotId.equals(b.id))).get()) x,
      ]..sort((a, c) => c.entryDate.compareTo(a.entryDate))).firstOrNull;
      if (f == null) continue;
      if (f.feedQtyKg == null) {
        consommation = null;
        break;
      }
      consommation = consommation! + f.feedQtyKg!;
    }
    final produits = await _db.select(_db.products).get();
    final types = await _db.select(_db.feedTypes).get();
    final produit = codeEspece == null ? null : AutonomieAlimentaire.produitProvende(codeEspece, produits, especes);
    final autonomie = AutonomieAlimentaire.evaluer(
      produit,
      produit == null ? null : AutonomieAlimentaire.stockEnKg(produit, types),
      consommation,
    );

    // `suiviSanitaireBande` : fiches des 7 derniers jours (aujourd'hui compris).
    final depuis = HeureBenin.plusJours(aujourdhui, -6);
    final fiches7j = [for (final f in fiches) if (!_jour(f.entryDate).isBefore(depuis)) f]
      ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
    final departSeptJours = fiches7j.isEmpty ? null : _precedent(fiches7j.first, fiches, bande.initialQuantity);
    final morts7j = fiches7j.fold<int>(0, (s, f) => s + f.mort);

    final periodes = [
      for (final p in await (_db.select(_db.veterinaryWithdrawalPeriods)
                ..where((t) => t.lotId.equals(id) & t.endDate.isBiggerOrEqualValue(aujourdhui)))
              .get())
        p,
    ]..sort((a, b) => b.endDate.compareTo(a.endDate));

    final soins = [
      for (final s in await (_db.select(_db.veterinaryRecords)..where((t) => t.lotId.equals(id) & t.isActive.equals(true))).get()) s,
    ]..sort((a, b) {
        final c = b.recordDate.compareTo(a.recordDate);
        return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
      });

    return DetailBande(
      bande: bande,
      especeLibelle: espece?.label,
      libelleStade: libelleStade(codeEspece, bande.stage),
      autonomie: autonomie,
      provendeBandeKg: derniere?.feedQtyKg == null ? null : PmpService.arrondi(derniere!.feedQtyKg!, 2),
      dateDerniereFiche: derniere?.entryDate,
      remanence: periodes.firstOrNull,
      infirmerie: await (_db.select(_db.infirmaryRecords)..where((t) => t.lotId.equals(id) & t.status.equals('en_cours'))).get().then((l) => l.length),
      mortsSurSeptJours: morts7j,
      mortaliteSurSeptJours: departSeptJours == null || departSeptJours == 0
          ? null
          : (morts7j / departSeptJours * 1000).round() / 10,
      derniersSoins: soins.take(3).toList(),
    );
  }

  /// `previousEffectif()` : `effectif_final` de la fiche la plus récente STRICTEMENT antérieure, sinon l'effectif initial.
  static int _precedent(LivestockDailyEntry fiche, List<LivestockDailyEntry> toutes, int initial) {
    final jour = _jour(fiche.entryDate);
    LivestockDailyEntry? veille;
    for (final f in toutes) {
      if (f.id == fiche.id || !_jour(f.entryDate).isBefore(jour)) continue;
      if (veille == null || f.entryDate.isAfter(veille.entryDate)) veille = f;
    }
    return veille?.effectifFinal ?? initial;
  }

  // ── Écriture ─────────────────────────────────────────────────────────────────────────────────────────────────────

  /// Les règles de `saveLot()` : `code` `required|string|max:50|unique`, `species_id` `required|exists`, `stage`
  /// `required|in:<stades de l'espèce>`, `created_date` `required|date`, `quantity` `required|integer|min:1`,
  /// `product_id` / `lot_origine_id` `nullable|exists`. Messages de `lang/fr/validation.php`. Vide si tout est valable.
  static Map<String, String> valider(
    FormulaireBande f, {
    required String? codeEspece,
    required bool especeConnue,
    required bool codeDejaPris,
    bool produitConnu = true,
    bool origineConnue = true,
  }) {
    final e = <String, String>{};
    if (f.speciesId.isEmpty) {
      e['species_id'] = 'Le champ espèce est obligatoire.';
    } else if (!especeConnue) {
      e['species_id'] = "La valeur sélectionnée pour le champ espèce n'existe pas.";
    }
    final code = f.code;
    if (code.isEmpty) {
      e['code'] = 'Le champ code est obligatoire.';
    } else if (code.runes.length > 50) {
      e['code'] = 'Le champ code ne doit pas dépasser 50 caractères.';
    } else if (codeDejaPris) {
      e['code'] = 'La valeur du champ code est déjà utilisée.';
    }
    if (f.stage.isEmpty) {
      e['stage'] = 'Le champ stade est obligatoire.';
    } else if (!stadesPourEspece(codeEspece).containsKey(f.stage)) {
      e['stage'] = "La valeur sélectionnée pour le champ stade n'est pas valide.";
    }
    if (f.createdDate == null) e['created_date'] = 'Le champ date de création est obligatoire.';
    final quantite = quantiteDe(f.quantite);
    if (quantite == null) {
      e['quantity'] = 'Le champ quantité doit être un nombre entier.';
    } else if (quantite < 1) {
      e['quantity'] = 'Le champ quantité doit être au moins égal à 1.';
    }
    if (f.coutAcquisition.trim().isNotEmpty && int.tryParse(f.coutAcquisition.trim()) == null) {
      e['acquisition_cost'] = "Le champ coût d'acquisition doit être un nombre entier.";
    }
    if (f.productId.isNotEmpty && !produitConnu) {
      e['product_id'] = "La valeur sélectionnée pour le champ produit n'existe pas.";
    }
    if (f.lotOrigineId.isNotEmpty && !origineConnue) {
      e['lot_origine_id'] = "La valeur sélectionnée pour le champ lot origine n'existe pas.";
    }
    return e;
  }

  /// Un champ numérique vide vaut 0 (`public int $quantity = 0`) ; illisible : `null`.
  static int? quantiteDe(String texte) {
    final t = texte.trim();
    if (t.isEmpty) return 0;
    return int.tryParse(t);
  }

  /// `saveLot()` : crée la bande (`pending`), et sa constitution si une bande d'origine est choisie — le tout dans
  /// UNE transaction, comme `DB::transaction(creerLaBande)` du web.
  ///
  /// Lève [BandeRefusee] (messages du web, sous leur champ) ; `RefusExercice` quand la date tombe dans un exercice
  /// CLOS (motif R4, sous « Date de Création »).
  Future<LivestockLot> creer(FormulaireBande f) async {
    final espece = f.speciesId.isEmpty
        ? null
        : await (_db.select(_db.livestockSpecies)..where((t) => t.id.equals(f.speciesId))).getSingleOrNull();
    final tousLesCodes = await _db.select(_db.livestockLots).get();
    final erreurs = valider(
      f,
      codeEspece: espece?.code,
      especeConnue: espece != null,
      // `unique:livestock_lots,code` : comparaison sous la collation du serveur, archivées comprises.
      codeDejaPris: tousLesCodes.any((b) => cleCommeLeServeur(b.code) == cleCommeLeServeur(f.code)),
      produitConnu: f.productId.isEmpty || await (_db.select(_db.products)..where((t) => t.id.equals(f.productId))).getSingleOrNull() != null,
      origineConnue: f.lotOrigineId.isEmpty || tousLesCodes.any((b) => b.id == f.lotOrigineId),
    );
    if (erreurs.isNotEmpty) throw BandeRefusee(erreurs);

    final date = _jour(f.createdDate!);
    // `SaisieBandeAction::creer` — une bande datée dans un exercice CLOS est refusée (règle `refusExerciceClos`).
    await ExerciceDeSaisie(_db, maintenant: _horloge).refuser(date, regle: RegleExercice.closSeulement);

    final quantite = quantiteDe(f.quantite)!;
    final id = _uuid.v4();
    final cout = f.coutAcquisition.trim().isEmpty ? null : double.parse(f.coutAcquisition.trim());

    await _db.transaction(() async {
      await _db.into(_db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: id,
          code: f.code,
          speciesId: f.speciesId,
          speciesCode: Value(espece!.code),
          stage: Value(f.stage),
          initialQuantity: Value(quantite),
          currentQuantity: Value(quantite),
          createdDate: Value(date),
          acquisitionCost: Value(cout),
          productId: Value(f.productId.isEmpty ? null : f.productId),
          status: const Value('actif'),
          isActive: const Value(true),
          updatedAt: Value(HeureBenin.versInstant(_horloge())),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );

      if (f.lotOrigineId.isNotEmpty) {
        try {
          await _transferts.creer(
            sourceLotId: f.lotOrigineId,
            targetLotId: id,
            jour: date,
            quantite: quantite,
            // Lapins et porcs : la catégorie du stade ; les autres espèces n'en ont pas.
            categorie: EffectifParCategorie.especeDuCode(espece.code) != null
                ? EffectifParCategorie.categorieDuStade(f.stage)
                : null,
            constitution: true,
            motif: 'Constitution de la bande ${f.code}',
          );
        } on TransfertRefuse catch (e) {
          // La constitution est refusée : la bande n'est pas créée non plus (la transaction est annulée).
          throw BandeRefusee({'lot_origine_id': e.motif});
        }
      }
    });

    _gestes?.signaler();
    return (await (_db.select(_db.livestockLots)..where((t) => t.id.equals(id))).getSingle());
  }

  /// `updateLot()` : stade, effectif actuel (correction explicite), statut — rien d'autre. Le code, l'espèce, l'effectif
  /// initial et la date ne changent jamais. Une bande archivée n'est plus modifiable ; une modification qui ne change
  /// rien n'écrit rien (aucune mise en file).
  Future<LivestockLot> modifier(String id, {required String stage, required String quantite, required String status}) async {
    final bande = await (_db.select(_db.livestockLots)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (bande == null) throw const BandeRefusee({'bande': 'Bande introuvable sur ce poste.'});

    final espece = await (_db.select(_db.livestockSpecies)..where((t) => t.id.equals(bande.speciesId))).getSingleOrNull();
    final erreurs = <String, String>{};
    if (stage.isEmpty) {
      erreurs['stage'] = 'Le champ stade est obligatoire.';
    } else if (!stadesPourEspece(espece?.code ?? bande.speciesCode).containsKey(stage)) {
      erreurs['stage'] = "La valeur sélectionnée pour le champ stade n'est pas valide.";
    }
    final n = quantiteDe(quantite);
    if (n == null) {
      erreurs['quantity'] = 'Le champ quantité doit être un nombre entier.';
    } else if (n < 0) {
      erreurs['quantity'] = 'Le champ quantité doit être au moins égal à 0.';
    }
    if (status.isEmpty) {
      erreurs['status'] = 'Le champ statut est obligatoire.';
    } else if (status != 'actif' && status != 'cloture') {
      erreurs['status'] = "La valeur sélectionnée pour le champ statut n'est pas valide.";
    }
    if (erreurs.isNotEmpty) throw BandeRefusee(erreurs);

    if (!bande.isActive) throw const BandeRefusee({'bande': messageArchivee});

    final change = bande.stage != stage || bande.status != status || bande.currentQuantity != n;
    if (!change) return bande;

    await (_db.update(_db.livestockLots)..where((t) => t.id.equals(id))).write(
      LivestockLotsCompanion(
        stage: Value(stage),
        status: Value(status),
        currentQuantity: Value(n!),
        // Une correction de l'effectif part avec la ligne ; sans correction, l'effectif reste celui des fiches.
        effectifCorrige: bande.currentQuantity != n ? Value(n) : const Value.absent(),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(HeureBenin.versInstant(_horloge())),
      ),
    );
    _gestes?.signaler();
    return (await (_db.select(_db.livestockLots)..where((t) => t.id.equals(id))).getSingle());
  }

  /// `archiveLot()` : `is_active = false`, la ligne est gardée. `false` : la bande l'était déjà (rien n'est écrit).
  Future<bool> archiver(String id) async {
    final bande = await (_db.select(_db.livestockLots)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (bande == null) throw const BandeRefusee({'bande': 'Bande introuvable sur ce poste.'});
    if (!bande.isActive) return false;

    await (_db.update(_db.livestockLots)..where((t) => t.id.equals(id))).write(
      LivestockLotsCompanion(
        isActive: const Value(false),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(HeureBenin.versInstant(_horloge())),
      ),
    );
    _gestes?.signaler();
    return true;
  }
}
