import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/erreurs/message_erreur.dart';
import '../../core/temps/heure_benin.dart';
import '../achats/fournisseurs_repository.dart';
import '../clients/clients_creances_repository.dart';
import '../comptabilite/comptabilite_repository.dart';
import '../elevage/categorie_volaille.dart';
import '../elevage/parametres_elevage_repository.dart';
import '../elevage/stade_pondeuse.dart';
import '../rh/personnel_repository.dart';
import '../stocks/produits_repository.dart';

/// Ticket IMPORT-1 — un fichier (ou un import entier) refusé AVANT toute écriture : le message est celui de l'écran.
class ImportationRefusee implements Exception {
  ImportationRefusee(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Une colonne d'un modèle d'importation — copie de `App\Services\Import\ColonneImport` (prouvée par `importation_parite_php_test.dart`).
class ColonneImportation {
  const ColonneImportation(this.cle, this.libelle, {required this.obligatoire, required this.type, this.liste});

  final String cle;
  final String libelle;
  final bool obligatoire;

  /// `texte`, `telephone`, `entier`, `decimal`, `liste`.
  final String type;
  final String? liste;

  /// En-tête EXACT du fichier : le libellé, suivi de « * » quand la colonne est obligatoire.
  String get entete => '$libelle${obligatoire ? ' *' : ''}';
}

/// Un module importable — copie de `ModuleImport` du serveur : version, colonnes, droit.
class ModuleImportation {
  const ModuleImportation({
    required this.cle,
    required this.libelle,
    required this.description,
    required this.permission,
    required this.version,
    required this.colonnes,
    this.colonnesSensibles = const [],
  });

  final String cle;
  final String libelle;
  final String description;

  /// Droit du web (`manage-stocks`, `manage-ventes`, `manage-achats`), lu par [PermissionsPoste.peut].
  final String permission;
  final int version;
  final List<ColonneImportation> colonnes;

  /// Colonnes SENSIBLES (le salaire) : jamais au rapport, jamais gardées après l'import (`ModuleImport::colonnesSensibles`).
  final List<String> colonnesSensibles;

  ColonneImportation colonne(String cle) => colonnes.firstWhere((c) => c.cle == cle);

  String get nomDeFichier => 'Modele_${cle[0].toUpperCase()}${cle.substring(1)}_v$version.xlsx';
}

/// Une ligne du fichier, son état et son motif — copie d'une entrée de `import_batches.lignes` du serveur.
class LigneImportation {
  LigneImportation({
    required this.ligne,
    required this.designation,
    required this.brut,
    this.statut = ImportationRepository.valide,
    this.motif,
    this.doublon = false,
  });

  /// Numéro de la ligne dans le fichier (l'en-tête est la ligne 1).
  final int ligne;
  final String designation;

  /// Valeurs lues (clé de colonne → texte) ; `null` une fois la fiche créée ou ignorée (rapport).
  Map<String, String>? brut;
  String statut;
  String? motif;
  bool doublon;
}

/// L'aperçu d'un fichier (étape 4) puis son rapport (étape 6).
class ApercuImportation {
  ApercuImportation({
    required this.module,
    required this.nomFichier,
    required this.lignes,
    this.bloquant,
    this.termine = false,
  });

  final ModuleImportation module;
  final String nomFichier;
  final List<LigneImportation> lignes;

  /// Motif qui interdit TOUT l'import (exercice clos…) : refusé à l'aperçu, avant la confirmation.
  final String? bloquant;
  bool termine;

  int get lues => lignes.length;
  int get valides => _compte(ImportationRepository.valide);
  int get ignorees => _compte(ImportationRepository.ignoree);
  int get refusees => _compte(ImportationRepository.refusee);
  int get creees => _compte(ImportationRepository.creee);

  int _compte(String statut) => lignes.where((l) => l.statut == statut).length;
}

/// Ticket IMPORT-1 — « IMPORTATION EN MASSE » AU POSTE (décision du client, 08/11/2026) : le dépôt de l'écran.
///
/// ⚠️⚠️ **LA RÈGLE EST CELLE DU SERVEUR, TRANSPOSÉE** (`App\Services\Import\*`, le web est le maître) : mêmes colonnes et
/// même version de modèle, mêmes normalisations de cellules, mêmes règles de validation (celles de `ProductCatalogService`,
/// `CustomerCatalogService`, `SupplierCatalogService`), mêmes clés de ligne, mêmes motifs. Le test
/// `importation_parite_php_test.dart` fait lire par ce dépôt le fichier que le VRAI PHP a fabriqué et compare, ligne par
/// ligne, état et motif au résultat de `ImportMasseService::analyser`.
///
/// ⚠️⚠️ **UN SEUL ÉCRIVAIN PAR TABLE.** Ce dépôt n'écrit rien lui-même : chaque ligne valide passe par le dépôt propriétaire
/// de sa table (`ProduitsRepository.creer`, `ClientsCreancesRepository.creerClient`,
/// `FournisseursRepository.creerFournisseur`), qui l'écrit `pending` ; la synchronisation ordinaire l'envoie (aucun endpoint
/// d'import : hors ligne, idempotence par UUID, droits par table et audit existent déjà dans `POST /api/sync/push`). Le serveur
/// re-juge tout : une ligne refusée au serveur revient `conflict` avec son motif, à l'écran de synchronisation.
///
/// ⚠️ STOCK INITIAL : règle existante du poste, inchangée — le produit part avec sa quantité (`stock_qty`, « Stock Initial »,
/// uniquement à la création) et c'est le SERVEUR qui l'écrit en mouvement « Stock initial » (`AdjustStockAction`) à l'envoi. Un
/// produit déjà au catalogue est IGNORÉ et son stock n'est pas ajouté (comme au web).
///
/// ⚠️ LE MODÈLE xlsx est GÉNÉRÉ ICI, hors ligne ([genererModele]) : mêmes en-têtes, même version, mêmes feuilles que le
/// modèle du serveur, un fichier de l'un est accepté par l'autre. Seule différence : le paquet `excel` n'écrit pas de listes
/// déroulantes de validation (aucune API de validation de données, vérifié) — la feuille « Listes » les remplace, et
/// l'aperçu refuse une valeur hors liste avec le motif du web. Le modèle du web les porte.
class ImportationRepository {
  ImportationRepository({
    required this.database,
    this.deviceId = 'poste',
    DateTime Function()? maintenant,
  }) : _maintenant = maintenant ?? HeureBenin.maintenant;

  final AppDatabase database;
  final String deviceId;
  final DateTime Function() _maintenant;

  static const valide = 'valide';
  static const ignoree = 'ignoree';
  static const refusee = 'refusee';
  static const creee = 'creee';

  /// Limites — celles de `LecteurXlsx`.
  static const tailleMaxOctets = 5 * 1024 * 1024;
  static const lignesMax = 5000;
  static const lignesParcouruesMax = 20000;

  static const feuilleDonnees = 'Données';
  static const feuilleInstructions = 'Instructions';
  static const feuilleListes = 'Listes';
  static const feuilleMeta = 'Modele';

  /// Espace de noms des UUID v5 de l'importation — `ModuleImport::ESPACE_UUID`.
  static const espaceUuid = 'b3b0e2c4-6f5e-5b7a-9a4d-2f1c7a1d0e51';

  static const modeFourchette = 'Fourchette';
  static const modeDevis = 'Sur devis';

  /// Catégories de fournisseur — `SupplierCatalogService::CATEGORIES` (même liste que `categoriesFournisseur`).
  static const categoriesFournisseur = ['Aliments', 'Produits vétérinaires', 'Intrants agricoles', 'Matériel', 'Autre'];

  /// Unités proposées par la liste du modèle (`ImportStocksService::UNITES_PROPOSEES`).
  static const unitesProposees = ['u', 'sac', 'plateau', 'carton', 'botte', 'flacon', 'boîte'];

  // ── Registre des modules (copie de `ImportMasseService::REGISTRE`) ────────────────────────────────────────────

  static const stocks = ModuleImportation(
    cle: 'stocks',
    libelle: 'Stocks',
    description: 'Produits du catalogue avec leur stock initial (un mouvement « Stock initial » par produit).',
    permission: 'manage-stocks',
    version: 1,
    colonnes: [
      ColonneImportation('nom', 'Nom', obligatoire: true, type: 'texte'),
      ColonneImportation('categorie', 'Catégorie', obligatoire: true, type: 'liste', liste: 'categories'),
      ColonneImportation('unite', 'Unité', obligatoire: true, type: 'liste', liste: 'unites'),
      ColonneImportation('filiere', 'Filière', obligatoire: false, type: 'liste', liste: 'filieres'),
      ColonneImportation('mode_prix', 'Mode de prix', obligatoire: true, type: 'liste', liste: 'modes_prix'),
      ColonneImportation('prix_min', 'Prix min (FCFA)', obligatoire: false, type: 'entier'),
      ColonneImportation('prix_max', 'Prix max (FCFA)', obligatoire: false, type: 'entier'),
      ColonneImportation('tva', 'TVA %', obligatoire: true, type: 'decimal'),
      ColonneImportation('seuil', "Seuil d'alerte", obligatoire: true, type: 'decimal'),
      ColonneImportation('stock_initial', 'Stock initial', obligatoire: true, type: 'decimal'),
      ColonneImportation('categorie_effectif', "Catégorie d'effectif", obligatoire: false, type: 'liste', liste: 'categories_effectif'),
      ColonneImportation('description', 'Description', obligatoire: false, type: 'texte'),
    ],
  );

  static const clients = ModuleImportation(
    cle: 'clients',
    libelle: 'Clients',
    description: 'Fiches clients : nom, téléphone, e-mail, ville et IFU.',
    permission: 'manage-ventes',
    version: 1,
    colonnes: [
      ColonneImportation('nom', 'Nom', obligatoire: true, type: 'texte'),
      ColonneImportation('telephone', 'Téléphone', obligatoire: false, type: 'telephone'),
      ColonneImportation('email', 'E-mail', obligatoire: false, type: 'texte'),
      ColonneImportation('ville', 'Ville', obligatoire: false, type: 'texte'),
      ColonneImportation('ifu', 'IFU', obligatoire: false, type: 'telephone'),
    ],
  );

  static const fournisseurs = ModuleImportation(
    cle: 'fournisseurs',
    libelle: 'Fournisseurs',
    description: 'Fiches fournisseurs : nom, catégorie, téléphone et adresse.',
    permission: 'manage-achats',
    version: 1,
    colonnes: [
      ColonneImportation('nom', 'Nom', obligatoire: true, type: 'texte'),
      ColonneImportation('categorie', 'Catégorie', obligatoire: true, type: 'liste', liste: 'categories'),
      ColonneImportation('telephone', 'Téléphone', obligatoire: true, type: 'telephone'),
      ColonneImportation('adresse', 'Adresse', obligatoire: false, type: 'texte'),
    ],
  );

  /// IMPORT-2 — employés : point de passage `PersonnelRepository.enregistrerEmploye` (`SaisieEmployeAction` au web), droit `manage-rh`.
  static const employes = ModuleImportation(
    cle: 'employes',
    libelle: 'Employés',
    description: "Registre des employés : nom, prénom, poste, date d'embauche, salaire de base et statut.",
    permission: 'manage-rh',
    version: 1,
    colonnes: [
      ColonneImportation('nom', 'Nom', obligatoire: true, type: 'texte'),
      ColonneImportation('prenom', 'Prénom', obligatoire: true, type: 'texte'),
      ColonneImportation('poste', 'Poste', obligatoire: true, type: 'texte'),
      ColonneImportation('date_embauche', "Date d'embauche", obligatoire: true, type: 'date'),
      ColonneImportation('salaire', 'Salaire de base (FCFA)', obligatoire: false, type: 'entier'),
      ColonneImportation('statut', 'Statut', obligatoire: false, type: 'liste', liste: 'statuts'),
    ],
    colonnesSensibles: ['salaire'],
  );

  /// IMPORT-3 — comptes complémentaires : `ComptabiliteRepository.creerCompte` (`PlanComptableService::creer`), droit `manage-comptabilite`.
  static const planComptable = ModuleImportation(
    cle: 'plan_comptable',
    libelle: 'Plan comptable',
    description: 'Comptes complémentaires du plan comptable : numéro, intitulé et classe.',
    permission: 'manage-comptabilite',
    version: 1,
    colonnes: [
      ColonneImportation('numero', 'Numéro de compte', obligatoire: true, type: 'code'),
      ColonneImportation('libelle', 'Intitulé', obligatoire: true, type: 'texte'),
      ColonneImportation('classe', 'Classe', obligatoire: true, type: 'liste', liste: 'classes'),
    ],
  );

  /// IMPORT-4 — barème de rationnement : `ParametresElevageRepository.enregistrerRation` (`RationStandardService::creer`), droit `manage-elevage`.
  static const rations = ModuleImportation(
    cle: 'rations',
    libelle: 'Rations',
    description: 'Barème de rationnement : espèce, stade physiologique et ration normative en grammes par tête et par jour.',
    permission: 'manage-elevage',
    version: 1,
    colonnes: [
      ColonneImportation('espece', 'Espèce', obligatoire: true, type: 'liste', liste: 'especes'),
      ColonneImportation('stade', "Stade physiologique / tranche d'âge", obligatoire: true, type: 'texte'),
      ColonneImportation('grammes', 'Ration normative (g/tête/jour)', obligatoire: true, type: 'entier'),
    ],
  );

  /// Libellés de la liste « Statut » (`ImportEmployesService::STATUTS`) : clé du statut → libellé.
  static const statutsEmploye = {'actif': 'Actif', 'conge': 'Congé', 'suspendu': 'Suspendu'};

  /// Libellés de la liste « Classe » (`PlanComptableService::LIBELLES_CLASSE`).
  static const classesComptables = {
    1: '1 - Ressources', 2: '2 - Immobilisations', 3: '3 - Stocks', 4: '4 - Tiers', 5: '5 - Trésorerie',
    6: '6 - Charges', 7: '7 - Produits', 8: '8 - Autres', 9: '9 - Hors bilan et analytique',
  };

  /// Libellés de la liste « Espèce » (`RationStandardService::ESPECES`) : code → libellé.
  static const especesRation = {
    'aviculture': 'Aviculture (Volailles)',
    'cuniculture': 'Cuniculture (Lapins)',
    'porciculture': 'Porciculture (Porcs)',
  };

  /// Dans l'ordre de l'écran web (copie de `ImportMasseService::REGISTRE`).
  static const modules = [stocks, clients, fournisseurs, employes, planComptable, rations];

  static ModuleImportation? module(String cle) => modules.where((m) => m.cle == cle).firstOrNull;

  /// Les modules que [role] a le droit d'importer (`ImportMasseService::modulesAutorises`) — les autres sont absents de l'écran.
  static List<ModuleImportation> modulesAutorises(String role) => [
    for (final m in modules)
      if (PermissionsPoste.peut(role, m.permission)) m,
  ];

  /// Droit d'ouvrir l'écran : celui d'au moins un module (Gate `importation-masse` du web).
  static bool peutImporter(String role) => modulesAutorises(role).isNotEmpty;

  // ── Lecture des cellules (copie de `LectureValeurs`) ──────────────────────────────────────────────────────

  /// Retire espaces, insécables (U+00A0), fines (U+202F, U+2009) : « 1 500 » → « 1500 ».
  static String sansEspaces(String texte) => texte.replaceAll(RegExp('[\\s   ]+'), '');

  /// 1500.0 → « 1500 » ; 2.5 → « 2.5 » ; jamais de notation scientifique.
  static String nombreEnTexte(num nombre) {
    if (nombre is int || (nombre.floorToDouble() == nombre && nombre.abs() < 1e15)) return nombre.toInt().toString();
    var s = nombre.toStringAsFixed(10);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  /// Texte d'une cellule : espaces de bord et insécables retirés ; jamais nul.
  static String texte(Object? valeur) {
    if (valeur == null) return '';
    if (valeur is CellValue) {
      return switch (valeur) {
        IntCellValue(:final value) => nombreEnTexte(value),
        DoubleCellValue(:final value) => nombreEnTexte(value),
        BoolCellValue(:final value) => value ? 'VRAI' : 'FAUX',
        TextCellValue(:final value) => texte(value.toString()),
        FormulaCellValue(:final formula) => texte(formula.startsWith('=') ? formula : '=$formula'),
        _ => texte(valeur.toString()),
      };
    }
    if (valeur is num) return nombreEnTexte(valeur);
    if (valeur is bool) return valeur ? 'VRAI' : 'FAUX';
    return valeur.toString().replaceAll(' ', ' ').trim();
  }

  /// Entier de FCFA strict (chiffres seuls) ; `null` si la saisie n'en est pas un.
  static int? entier(String texte) {
    final propre = sansEspaces(texte);
    return RegExp(r'^\d{1,15}$').hasMatch(propre) ? int.parse(propre) : null;
  }

  /// Nombre décimal (virgule ou point) ; `null` si illisible.
  static double? decimal(String texte) {
    final propre = sansEspaces(texte).replaceAll(',', '.');
    return RegExp(r'^-?\d+(\.\d+)?$').hasMatch(propre) ? double.parse(propre) : null;
  }

  static const _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae', 'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'œ': 'oe', 'ø': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'ß': 'ss',
  };

  /// Clé de comparaison : minuscules, sans accents, tout ce qui n'est pas lettre ou chiffre réduit à un espace
  /// (`LectureValeurs::cle` = `FusionReferentielsService::normaliserNom`).
  static String cle(String texte) {
    final sb = StringBuffer();
    for (final c in texte.toLowerCase().split('')) {
      sb.write(_accents[c] ?? c);
    }
    return sb.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  /// Chiffres seuls, sans préfixe international du Bénin ; `null` sous 8 chiffres (`FusionReferentielsService::normaliserTelephone`).
  static String? normaliserTelephone(String? telephone) {
    if (telephone == null) return null;
    var chiffres = telephone.replaceAll(RegExp(r'\D+'), '');
    if (chiffres.startsWith('00')) chiffres = chiffres.substring(2);
    if (chiffres.startsWith('229') && chiffres.length >= 11) chiffres = chiffres.substring(3);
    return chiffres.length >= 8 ? chiffres : null;
  }

  static int _longueur(String s) => s.runes.length;

  // ── Messages de validation (lang/fr/validation.php, mot pour mot) ─────────────────────────────────────────

  static String _obligatoire(String a) => 'Le champ $a est obligatoire.';
  static String _tropLong(String a, int max) => 'Le champ $a ne doit pas dépasser $max caractères.';
  static String _auMoins(String a, int min) => 'Le champ $a doit être au moins égal à $min.';
  static String _pasPlusDe(String a, int max) => 'Le champ $a ne doit pas dépasser $max.';
  static const _motifMax = 'Le prix maximum doit être supérieur ou égal au prix minimum.';
  static const _motifEffectif =
      "La catégorie d'effectif doit être Reproducteur, Jeune ou Poussin (reproducteurs), ou l'un des quatre stades des pondeuses "
      '(Poussin ponte, Poussin en croissance, Poulette, Pondeuse).';

  /// « Feuille « Données », ligne 7, colonne « Nom * » : motif » — une ligne par colonne en erreur.
  static String motifsDeColonnes(ModuleImportation m, int numero, Map<String, String> erreurs) => [
    for (final e in erreurs.entries)
      'Feuille « $feuilleDonnees », ligne $numero, colonne « ${m.colonne(e.key).entete} » : ${e.value}',
  ].join('\n');

  // ── Validation d'UNE ligne ────────────────────────────────────────────────────────────────────────────────

  /// Traduit les valeurs lues et les fait valider par les règles des services (transposées). Rend `(valeurs, erreurs)` ;
  /// [contexte] porte les listes lues UNE fois pour tout l'import.
  ({Map<String, Object?> valeurs, Map<String, String> erreurs}) validerLigne(ModuleImportation m, Map<String, String> brut, ContexteImportation contexte) =>
      switch (m.cle) {
        'stocks' => _validerStocks(brut, contexte),
        'clients' => _validerClients(brut),
        'fournisseurs' => _validerFournisseurs(brut),
        'employes' => _validerEmployes(brut),
        'plan_comptable' => _validerPlanComptable(brut),
        'rations' => _validerRations(brut),
        _ => throw ArgumentError('Module inconnu : ${m.cle}'),
      };

  ({Map<String, Object?> valeurs, Map<String, String> erreurs}) _validerStocks(Map<String, String> brut, ContexteImportation c) {
    final e = <String, String>{};

    final nom = texte(brut['nom']);
    final unite = texte(brut['unite']);
    final descr = texte(brut['description']);

    final texteCategorie = texte(brut['categorie']);
    String? categorieId = texteCategorie.isEmpty ? '' : c.categories[cle(texteCategorie)];
    if (categorieId == null) {
      e['categorie'] = "Catégorie inconnue : « $texteCategorie ». Choisissez une valeur de la liste déroulante.";
      categorieId = '';
    }

    final texteFiliere = texte(brut['filiere']);
    final especeId = texteFiliere.isEmpty ? null : c.filieres[cle(texteFiliere)];
    if (texteFiliere.isNotEmpty && especeId == null) {
      e['filiere'] = "Filière inconnue : « $texteFiliere ». Choisissez une valeur de la liste déroulante.";
    }

    final texteMode = texte(brut['mode_prix']);
    final mode = switch (cle(texteMode)) {
      'fourchette' => 'fourchette',
      'sur devis' || 'quote' => 'quote',
      _ => null,
    };
    if (mode == null && texteMode.isNotEmpty) {
      e['mode_prix'] = "Mode de prix inconnu : « $texteMode ». Attendu : « Fourchette » ou « Sur devis ».";
    }

    // Montants : des FCFA ENTIERS (durcissement du FORMAT du fichier).
    final prix = <String, int?>{};
    for (final col in ['prix_min', 'prix_max']) {
      final t = texte(brut[col]);
      prix[col] = null;
      if (t.isEmpty) continue;
      final n = entier(t);
      if (n == null) {
        e[col] = 'Montant invalide : un nombre entier de FCFA est attendu.';
      } else {
        prix[col] = n;
      }
    }

    final nombres = <String, double?>{};
    for (final col in ['tva', 'seuil', 'stock_initial']) {
      final t = texte(brut[col]);
      nombres[col] = null;
      if (t.isEmpty) continue;
      final n = decimal(t);
      if (n == null) {
        e[col] = 'Nombre invalide : un nombre est attendu (virgule ou point).';
      } else {
        nombres[col] = n;
      }
    }

    final texteEffectif = texte(brut['categorie_effectif']);
    final effectif = texteEffectif.isEmpty ? '' : (c.effectifs[cle(texteEffectif)] ?? texteEffectif);

    // Les règles de `ProductCatalogService::regles()`, dans l'ordre du serveur : le premier motif par colonne, sans écraser
    // un motif déjà posé par le format de la cellule.
    void regle(String colonne, String? motif) {
      if (motif != null) e.putIfAbsent(colonne, () => motif);
    }

    final tva = nombres['tva'];
    final seuil = nombres['seuil'];
    final stock = nombres['stock_initial'];

    regle('nom', nom.isEmpty ? _obligatoire('nom') : (_longueur(nom) > 150 ? _tropLong('nom', 150) : null));
    regle('description', _longueur(descr) > 2000 ? _tropLong('description', 2000) : null);
    regle('categorie', categorieId.isEmpty ? _obligatoire('catégorie') : null);
    regle('unite', unite.isEmpty ? _obligatoire('unité') : (_longueur(unite) > 20 ? _tropLong('unité', 20) : null));
    regle('mode_prix', mode == null ? _obligatoire('mode de prix') : null);
    regle('tva', tva == null ? _obligatoire('TVA') : (tva < 0 ? _auMoins('TVA', 0) : (tva > 100 ? _pasPlusDe('TVA', 100) : null)));
    regle('seuil', seuil == null ? _obligatoire("seuil d'alerte") : (seuil < 0 ? _auMoins("seuil d'alerte", 0) : null));
    final effectifValide = effectif.isEmpty || CategorieVolaille.estValide(effectif) || StadePondeuse.estValide(effectif);
    regle('categorie_effectif', effectifValide ? null : _motifEffectif);
    regle('stock_initial', stock == null ? _obligatoire('stock initial') : (stock < 0 ? _auMoins('stock initial', 0) : null));

    if (mode == 'fourchette') {
      final min = prix['prix_min'];
      final max = prix['prix_max'];
      final formatMin = e.containsKey('prix_min');
      regle('prix_min', min == null ? _obligatoire('prix min') : null);
      String? motifMax;
      if (max == null) {
        motifMax = _obligatoire('prix max');
      } else if (min == null || max < min) {
        // Laravel : `gte` sans valeur de comparaison est faux. Un prix min illisible fausse la comparaison : le motif du
        // format suffit, pas un second motif parasite.
        motifMax = formatMin ? null : _motifMax;
      }
      regle('prix_max', motifMax);
    }

    final valeurs = <String, Object?>{
      'name': nom,
      'description': descr.isEmpty ? null : descr,
      'category_id': categorieId,
      'species_id': especeId,
      'unit': unite,
      'pricing_mode': mode ?? '',
      'price_min': prix['prix_min'],
      'price_max': prix['prix_max'],
      'tva_rate': tva,
      'alert_threshold': seuil,
      'stock_qty': stock,
      'categorie_effectif': effectif.isEmpty ? null : effectif,
      'categorie_libelle': texteCategorie,
      'filiere_libelle': texteFiliere,
    };
    return (valeurs: valeurs, erreurs: e);
  }

  ({Map<String, Object?> valeurs, Map<String, String> erreurs}) _validerClients(Map<String, String> brut) {
    final nom = texte(brut['nom']);
    final tel = texte(brut['telephone']);
    final mail = texte(brut['email']);
    final ville = texte(brut['ville']);
    final ifu = texte(brut['ifu']);
    final e = <String, String>{};

    if (nom.isEmpty) {
      e['nom'] = _obligatoire('nom');
    } else if (_longueur(nom) > 150) {
      e['nom'] = _tropLong('nom', 150);
    }
    if (_longueur(tel) > 30) e['telephone'] = _tropLong('téléphone', 30);
    if (mail.isNotEmpty) {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
        e['email'] = 'Le champ e-mail doit être une adresse e-mail valide.';
      } else if (_longueur(mail) > 150) {
        e['email'] = _tropLong('e-mail', 150);
      }
    }
    if (_longueur(ville) > 100) e['ville'] = _tropLong('ville', 100);
    if (ifu.isNotEmpty && !RegExp(r'^\d{13}$').hasMatch(ifu)) {
      e['ifu'] = "L'IFU du client doit comporter 13 chiffres (laissez-le vide pour un client sans IFU).";
    }

    return (
      valeurs: {
        'name': nom,
        'phone': tel.isEmpty ? null : tel,
        'email': mail.isEmpty ? null : mail,
        'city': ville.isEmpty ? null : ville,
        'ifu': ifu.isEmpty ? null : ifu,
      },
      erreurs: e,
    );
  }

  ({Map<String, Object?> valeurs, Map<String, String> erreurs}) _validerFournisseurs(Map<String, String> brut) {
    final e = <String, String>{};
    final texteCategorie = texte(brut['categorie']);
    var categorie = '';
    for (final propose in categoriesFournisseur) {
      if (texteCategorie.isNotEmpty && cle(propose) == cle(texteCategorie)) categorie = propose;
    }
    if (texteCategorie.isNotEmpty && categorie.isEmpty) {
      e['categorie'] = "Catégorie inconnue : « $texteCategorie ». Choisissez une valeur de la liste déroulante.";
    }

    final nom = texte(brut['nom']);
    final tel = texte(brut['telephone']);
    final adresse = texte(brut['adresse']);

    void regle(String colonne, String? motif) {
      if (motif != null) e.putIfAbsent(colonne, () => motif);
    }

    regle('nom', nom.isEmpty ? _obligatoire('nom') : (_longueur(nom) > 150 ? _tropLong('nom', 150) : null));
    regle('categorie', categorie.isEmpty ? _obligatoire('catégorie') : null);
    regle('telephone', tel.isEmpty ? _obligatoire('téléphone') : (_longueur(tel) > 30 ? _tropLong('téléphone', 30) : null));
    regle('adresse', _longueur(adresse) > 255 ? _tropLong('adresse', 255) : null);

    return (
      valeurs: {'name': nom, 'category': categorie, 'phone': tel, 'address': adresse.isEmpty ? null : adresse},
      erreurs: e,
    );
  }

  /// Entier au sens de la règle `integer` de Laravel (`FILTER_VALIDATE_INT`) : signe facultatif, pas de zéro initial.
  static int? _entierLaravel(String t) => RegExp(r'^[+-]?(0|[1-9]\d{0,17})$').hasMatch(t) ? int.parse(t) : null;

  /// IMPORT-2 — règles de `SaisieEmployeAction::regles()`, noms de colonne du web (« prénom », « nom », « poste », « date d'embauche »).
  ({Map<String, Object?> valeurs, Map<String, String> erreurs}) _validerEmployes(Map<String, String> brut) {
    final e = <String, String>{};

    final texteDate = texte(brut['date_embauche']);
    var date = '';
    if (texteDate.isNotEmpty) {
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(texteDate);
      var valide = false;
      if (m != null) {
        final a = int.parse(m.group(1)!);
        final mo = int.parse(m.group(2)!);
        final j = int.parse(m.group(3)!);
        final d = DateTime(a, mo, j);
        valide = a >= 1 && d.year == a && d.month == mo && d.day == j;
      }
      if (valide) {
        date = texteDate;
      } else {
        e['date_embauche'] = 'Date invalide : « $texteDate ». Écrivez la date au format AAAA-MM-JJ (exemple : 2026-11-08).';
      }
    }

    final texteStatut = texte(brut['statut']);
    var statut = 'actif';
    if (texteStatut.isNotEmpty) {
      statut = '';
      for (final entree in statutsEmploye.entries) {
        if (cle(texteStatut) == cle(entree.value) || cle(texteStatut) == entree.key) statut = entree.key;
      }
      if (statut.isEmpty) e['statut'] = 'Statut inconnu : « $texteStatut ». Choisissez une valeur de la liste déroulante.';
    }

    final texteSalaire = texte(brut['salaire']);
    int? salaire;
    if (texteSalaire.isNotEmpty) {
      salaire = entier(texteSalaire);
      if (salaire == null) e['salaire'] = 'Montant invalide : un nombre entier de FCFA est attendu.';
    }

    final nom = texte(brut['nom']);
    final prenom = texte(brut['prenom']);
    final poste = texte(brut['poste']);

    void regle(String colonne, String? motif) {
      if (motif != null) e.putIfAbsent(colonne, () => motif);
    }

    regle('nom', nom.isEmpty ? _obligatoire('nom') : (_longueur(nom) > 100 ? _tropLong('nom', 100) : null));
    regle('prenom', prenom.isEmpty ? _obligatoire('prénom') : (_longueur(prenom) > 100 ? _tropLong('prénom', 100) : null));
    regle('poste', poste.isEmpty ? _obligatoire('poste') : (_longueur(poste) > 100 ? _tropLong('poste', 100) : null));
    regle('date_embauche', date.isEmpty ? _obligatoire("date d'embauche") : null);

    return (
      valeurs: {'last_name': nom, 'first_name': prenom, 'position': poste, 'hire_date': date, 'base_salary': salaire, 'status': statut},
      erreurs: e,
    );
  }

  /// IMPORT-3 — règles de `PlanComptableService::regles()` SANS `unique` (un numéro déjà là est « ignoré », création seule).
  ({Map<String, Object?> valeurs, Map<String, String> erreurs}) _validerPlanComptable(Map<String, String> brut) {
    final e = <String, String>{};

    final texteClasse = texte(brut['classe']);
    var classe = texteClasse;
    for (final entree in classesComptables.entries) {
      if (texteClasse.isNotEmpty && cle(entree.value) == cle(texteClasse)) classe = '${entree.key}';
    }

    final code = texte(brut['numero']);
    final libelle = texte(brut['libelle']);

    void regle(String colonne, String? motif) {
      if (motif != null) e.putIfAbsent(colonne, () => motif);
    }

    regle('numero', code.isEmpty ? _obligatoire('code') : (_longueur(code) > 20 ? _tropLong('code', 20) : null));
    regle('libelle', libelle.isEmpty ? _obligatoire('libellé') : (_longueur(libelle) > 255 ? _tropLong('libellé', 255) : null));
    final n = _entierLaravel(classe);
    regle(
      'classe',
      classe.isEmpty
          ? _obligatoire('classe')
          : (n == null ? 'Le champ classe doit être un nombre entier.' : ((n < 1 || n > 9) ? 'Le champ classe doit être compris entre 1 et 9.' : null)),
    );

    return (valeurs: {'code': code, 'label': libelle, 'class': classe}, erreurs: e);
  }

  /// IMPORT-4 — règles de `RationStandardService::regles()`, noms de colonne du web (« espèce », « stade », « ration (grammes) »).
  ({Map<String, Object?> valeurs, Map<String, String> erreurs}) _validerRations(Map<String, String> brut) {
    final e = <String, String>{};

    final texteEspece = texte(brut['espece']);
    var espece = '';
    for (final entree in especesRation.entries) {
      if (texteEspece.isNotEmpty && (cle(texteEspece) == cle(entree.value) || cle(texteEspece) == entree.key)) espece = entree.key;
    }
    if (texteEspece.isNotEmpty && espece.isEmpty) {
      e['espece'] = "Espèce inconnue : « $texteEspece ». Choisissez une valeur de la liste déroulante.";
    }

    final stade = texte(brut['stade']);
    final grammes = sansEspaces(texte(brut['grammes']));

    void regle(String colonne, String? motif) {
      if (motif != null) e.putIfAbsent(colonne, () => motif);
    }

    regle('espece', espece.isEmpty ? _obligatoire('espèce') : null);
    regle('stade', stade.isEmpty ? _obligatoire('stade') : (_longueur(stade) > 100 ? _tropLong('stade', 100) : null));
    final g = _entierLaravel(grammes);
    regle(
      'grammes',
      grammes.isEmpty
          ? _obligatoire('ration (grammes)')
          : (g == null ? 'Le champ ration (grammes) doit être un nombre entier.' : (g < 1 ? _auMoins('ration (grammes)', 1) : null)),
    );

    return (valeurs: {'species_code': espece, 'stage_label': stade, 'ration_g_per_day': g ?? 0}, erreurs: e);
  }

  /// Clé naturelle NORMALISÉE d'une ligne valide (doublon dans le fichier, UUID v5) — `ModuleImport::cleLigne`.
  String cleLigne(ModuleImportation m, Map<String, Object?> v) => switch (m.cle) {
    'stocks' =>
      '${cle('${v['name']}')}|${cle('${v['categorie_libelle']}')}|${cle('${v['unit']}')}|${cle('${v['filiere_libelle']}').isEmpty ? '-' : cle('${v['filiere_libelle']}')}',
    'clients' => '${cle('${v['name']}')}|${normaliserTelephone(v['phone'] as String?) ?? '-'}',
    'fournisseurs' => '${cle('${v['name']}')}|${normaliserTelephone(v['phone'] as String?) ?? _chiffresOuTiret(v['phone'] as String?)}',
    'employes' => '${'${v['last_name']}'.toLowerCase()}|${'${v['first_name']}'.toLowerCase()}|${v['hire_date']}',
    'plan_comptable' => cleDeCompte('${v['code']}'),
    'rations' => '${v['species_code']}|${cle('${v['stage_label']}')}',
    _ => throw ArgumentError('Module inconnu : ${m.cle}'),
  };

  /// Clé d'un numéro de compte : sans espace, en minuscules (`ImportPlanComptableService::cleDeCode`).
  static String cleDeCompte(String code) => sansEspaces(code).toLowerCase();

  static String _chiffresOuTiret(String? t) {
    final d = (t ?? '').replaceAll(RegExp(r'\D+'), '');
    return d.isEmpty || d == '0' ? '-' : d;
  }

  /// UUID v5 DÉTERMINISTE d'une ligne : le même fichier produit les mêmes identifiants qu'au web — `ModuleImport::idLigne`.
  String idLigne(ModuleImportation m, Map<String, Object?> v) => const Uuid().v5(espaceUuid, '${m.cle}|${cleLigne(m, v)}');

  // ── Aperçu (étape 4) ──────────────────────────────────────────────────────────────────────────────────────

  /// Lit et VALIDE le fichier, sans rien écrire. [nomFichier] : celui du fichier choisi (extension contrôlée).
  ///
  /// Lève [ImportationRefusee] quand le fichier ENTIER est refusé (mêmes messages que `LecteurXlsx`).
  Future<ApercuImportation> analyser(ModuleImportation m, Uint8List octets, String nomFichier) async {
    if (!nomFichier.toLowerCase().endsWith('.xlsx')) {
      throw ImportationRefusee("Seuls les fichiers Excel .xlsx sont acceptés : utilisez le modèle « ${m.libelle} » téléchargé à l'étape 2.");
    }

    final lues = _lire(m, octets);
    final contexte = await ContexteImportation.charger(database, m.cle);

    final lignes = <LigneImportation>[];
    final premiere = <String, int>{};
    for (final entree in lues.entries) {
      final numero = entree.key;
      final brut = entree.value;
      final ligne = LigneImportation(ligne: numero, designation: designation(m, brut), brut: brut);

      final r = validerLigne(m, brut, contexte);
      if (r.erreurs.isNotEmpty) {
        ligne.statut = refusee;
        ligne.motif = motifsDeColonnes(m, numero, r.erreurs);
      } else {
        final cleDeLigne = cleLigne(m, r.valeurs);
        if (premiere.containsKey(cleDeLigne)) {
          ligne.statut = refusee;
          ligne.doublon = true;
          ligne.motif = 'Ligne $numero : doublon de la ligne ${premiere[cleDeLigne]}.';
        } else {
          premiere[cleDeLigne] = numero;
          final deja = await _dejaPresente(m, r.valeurs, contexte);
          if (deja != null) {
            ligne.statut = ignoree;
            ligne.motif = deja;
          }
        }
      }
      lignes.add(ligne);
    }

    return ApercuImportation(module: m, nomFichier: nomFichier, lignes: lignes, bloquant: await _controlePrealable(m));
  }

  /// Texte qui désigne la ligne dans l'aperçu et le rapport (`ModuleImport::designation`).
  static String designation(ModuleImportation m, Map<String, String> brut) => switch (m.cle) {
    'employes' => '${texte(brut['prenom'])} ${texte(brut['nom'])}'.trim(),
    'plan_comptable' => '${texte(brut['numero'])} — ${texte(brut['libelle'])}'.replaceAll(RegExp(r'^[ —]+|[ —]+$'), ''),
    'rations' => texte(brut['stade']),
    _ => brut['nom'] ?? '',
  };

  /// Motif qui interdit TOUT l'import : un exercice CLOS qui couvre le jour de l'import refuse le stock initial
  /// (`AdjustStockAction`, R4) — `ImportStocksService::controlePrealable`. Les cinq autres modules : aucun (aucun n'écrit dans un exercice).
  Future<String?> _controlePrealable(ModuleImportation m) async {
    if (m.cle != 'stocks') return null;

    return ExerciceDeSaisie(database, maintenant: _maintenant).refus(_maintenant(), regle: RegleExercice.closSeulement);
  }

  /// Lit le classeur : contrôle du FICHIER (taille, signature, lisibilité, modèle, version, en-têtes, nombre de lignes).
  Map<int, Map<String, String>> _lire(ModuleImportation m, Uint8List octets) {
    if (octets.length > tailleMaxOctets) {
      final mo = (octets.length / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',');
      throw ImportationRefusee('Le fichier dépasse ${tailleMaxOctets ~/ 1024 ~/ 1024} Mo ($mo Mo) : réduisez le nombre de lignes.');
    }
    final illisible = ImportationRefusee("Ce fichier n'est pas un classeur Excel (.xlsx) lisible. Utilisez le modèle « ${m.libelle} » téléchargé à l'étape 2.");
    if (octets.length < 2 || octets[0] != 0x50 || octets[1] != 0x4B) throw illisible;

    final Excel classeur;
    try {
      classeur = Excel.decodeBytes(octets);
    } catch (_) {
      throw illisible;
    }

    final meta = classeur.tables[feuilleMeta];
    String celluleMeta(String ref) => meta == null ? '' : texte(meta.cell(CellIndex.indexByString(ref)).value);
    final modele = celluleMeta('B1');
    final version = celluleMeta('B2');

    if (modele.isEmpty) {
      throw ImportationRefusee("Ce fichier n'est pas un modèle LogiAgriERP : téléchargez le modèle « ${m.libelle} » (version ${m.version}) à l'étape 2.");
    }
    if (modele != m.cle) {
      final autre = module(modele);
      final nom = autre != null ? '« ${autre.libelle} »' : '« $modele »';
      throw ImportationRefusee("Ce fichier n'est pas le modèle « ${m.libelle} » (version ${m.version}) : c'est le modèle $nom. Téléchargez le modèle à jour.");
    }
    if ('${m.version}' != version) {
      throw ImportationRefusee('Ce fichier est le modèle « ${m.libelle} » en version $version ; la version ${m.version} est attendue : téléchargez le modèle à jour.');
    }

    final feuille = classeur.tables[feuilleDonnees];
    if (feuille == null) {
      throw ImportationRefusee('La feuille « $feuilleDonnees » est introuvable : n\'en changez pas le nom, téléchargez le modèle « ${m.libelle} » à jour.');
    }

    final rangees = feuille.rows;
    final entetes = rangees.isEmpty ? <Data?>[] : rangees.first;
    final presentes = <String, int>{};
    for (var c = 0; c < entetes.length; c++) {
      final t = texte(entetes[c]?.value);
      if (t.isNotEmpty) presentes.putIfAbsent(t, () => c);
    }
    final positions = <String, int>{};
    final manquantes = <String>[];
    for (final col in m.colonnes) {
      final p = presentes[col.entete];
      if (p == null) {
        manquantes.add('« ${col.entete} »');
      } else {
        positions[col.cle] = p;
      }
    }
    if (manquantes.isNotEmpty) {
      throw ImportationRefusee(
        '${manquantes.length > 1 ? 'Colonnes manquantes ou renommées' : 'Colonne manquante ou renommée'} dans la feuille « $feuilleDonnees » : '
        '${manquantes.join(', ')}. Ne renommez pas les en-têtes : téléchargez le modèle « ${m.libelle} » à jour.',
      );
    }

    if (rangees.length > lignesParcouruesMax) {
      throw ImportationRefusee('Le classeur compte plus de 20 000 lignes : supprimez les lignes vides ou découpez le fichier.');
    }

    final lignes = <int, Map<String, String>>{};
    for (var r = 1; r < rangees.length; r++) {
      final cellules = rangees[r];
      final brut = <String, String>{};
      var vide = true;
      for (final MapEntry(key: cle, value: c) in positions.entries) {
        final t = c < cellules.length ? texte(cellules[c]?.value) : '';
        if (t.isNotEmpty) vide = false;
        brut[cle] = t;
      }
      if (vide) continue;

      lignes[r + 1] = brut;
      if (lignes.length > lignesMax) {
        throw ImportationRefusee('Le fichier dépasse 5 000 lignes : découpez-le en plusieurs fichiers.');
      }
    }
    if (lignes.isEmpty) {
      throw ImportationRefusee("Le fichier ne contient aucune ligne à importer : remplissez la feuille « $feuilleDonnees » sous les en-têtes.");
    }

    return lignes;
  }

  /// Le motif « déjà présente », ou `null` — `ModuleImport::dejaPresente`. Une ligne déjà présente est IGNORÉE, jamais mise à jour.
  Future<String?> _dejaPresente(ModuleImportation m, Map<String, Object?> v, ContexteImportation c) async {
    final id = idLigne(m, v);
    switch (m.cle) {
      case 'stocks':
        if (await (database.select(database.products)..where((p) => p.id.equals(id))).getSingleOrNull() != null) {
          return "Ce produit a déjà été importé : ignoré, le stock initial n'est pas ajouté.";
        }
        final sku = c.produits[_cleNaturelleProduit('${v['name']}', '${v['category_id']}', '${v['unit']}', v['species_id'] as String?)];
        if (sku != null) return "Ce produit existe déjà au catalogue ($sku) : ignoré, le stock initial n'est pas ajouté.";
      case 'clients':
        if (await (database.select(database.customers)..where((x) => x.id.equals(id))).getSingleOrNull() != null) {
          return 'Ce client a déjà été importé : ignoré.';
        }
        if (_cleNaturellePersonne('${v['name']}', v['phone'] as String?, c.clients)) {
          return 'Ce client existe déjà (même nom, même téléphone) : ignoré, la fiche existante est gardée.';
        }
      case 'fournisseurs':
        if (await (database.select(database.suppliers)..where((x) => x.id.equals(id))).getSingleOrNull() != null) {
          return 'Ce fournisseur a déjà été importé : ignoré.';
        }
        if (_cleNaturellePersonne('${v['name']}', v['phone'] as String?, c.fournisseurs)) {
          return 'Ce fournisseur existe déjà (même nom, même téléphone) : ignoré, la fiche existante est gardée.';
        }
      case 'employes':
        if (await (database.select(database.employees)..where((x) => x.id.equals(id))).getSingleOrNull() != null) {
          return 'Cet employé a déjà été importé : ignoré.';
        }
        if (c.employes.contains(cleLigne(m, v))) {
          return "Cet employé existe déjà (même nom, même prénom, même date d'embauche) : ignoré, la fiche existante est gardée.";
        }
      case 'plan_comptable':
        if (await (database.select(database.chartOfAccounts)..where((x) => x.id.equals(id))).getSingleOrNull() != null) {
          return 'Ce compte a déjà été importé : ignoré.';
        }
        if (c.comptes.contains(cleLigne(m, v))) {
          return 'Ce numéro de compte existe déjà au plan comptable : ignoré, le compte existant est gardé.';
        }
      case 'rations':
        if (await (database.select(database.feedRationStandards)..where((x) => x.id.equals(id))).getSingleOrNull() != null) {
          return 'Cette ration a déjà été importée : ignorée.';
        }
        if (c.rations.contains(cleLigne(m, v))) {
          return 'Cette ration existe déjà au barème (même espèce, même stade) : ignorée, la ration existante est gardée.';
        }
    }
    return null;
  }

  /// `FusionReferentielsService::cleNaturelle('products', …)` : nom normalisé, catégorie, unité normalisée, filière.
  static String? _cleNaturelleProduit(String nom, String categorieId, String unite, String? especeId) {
    final n = cle(nom);
    final u = cle(unite);
    if (n.isEmpty || categorieId.isEmpty || u.isEmpty) return null;
    return '$n|$categorieId|$u|${especeId != null && especeId.isNotEmpty ? especeId : '-'}';
  }

  /// `cleNaturelle('customers' | 'suppliers', …)` : nom normalisé + téléphone normalisé (≥ 8 chiffres) ; sans téléphone exploitable, jamais de fusion.
  static bool _cleNaturellePersonne(String nom, String? telephone, Set<String> existantes) {
    final n = cle(nom);
    final t = normaliserTelephone(telephone);
    if (n.isEmpty || t == null) return false;
    return existantes.contains('$n|$t');
  }

  // ── Confirmation et écriture (étape 5) ────────────────────────────────────────────────────────────────────

  /// Écrit les lignes valides de l'aperçu, ligne par ligne, par le dépôt propriétaire de la table (`pending`) ; chaque ligne est
  /// REVALIDÉE avant d'être écrite. Un import interdit (exercice clos) est refusé ICI, avant toute écriture.
  Future<ApercuImportation> importer(ApercuImportation apercu, String role) async {
    final m = apercu.module;
    if (!PermissionsPoste.peut(role, m.permission)) {
      throw ImportationRefusee("Vous n'avez pas le droit d'importer le module « ${m.libelle} ».");
    }
    if (apercu.termine) {
      throw ImportationRefusee("Cet import a déjà été confirmé : recommencez à l'étape 3 avec le fichier.");
    }
    final bloquant = await _controlePrealable(m);
    if (bloquant != null) throw ImportationRefusee(bloquant);

    final contexte = await ContexteImportation.charger(database, m.cle);
    for (final l in apercu.lignes) {
      if (l.statut != valide) continue;

      final r = validerLigne(m, l.brut!, contexte);
      if (r.erreurs.isNotEmpty) {
        l.statut = refusee;
        l.motif = motifsDeColonnes(m, l.ligne, r.erreurs);
        continue;
      }
      final deja = await _dejaPresente(m, r.valeurs, contexte);
      if (deja != null) {
        l.statut = ignoree;
        l.motif = deja;
        continue;
      }

      try {
        await _ecrire(m, r.valeurs, idLigne(m, r.valeurs));
        l.statut = creee;
        _memoriser(m, r.valeurs, contexte);
      } catch (e) {
        l.statut = refusee;
        l.motif = 'Ligne ${l.ligne} : ${messageErreur(e)}';
      }
    }

    // Les valeurs lues ne restent que pour les lignes REFUSÉES (le rapport à corriger).
    for (final l in apercu.lignes) {
      if (l.statut != refusee) {
        l.brut = null;
      } else {
        // IMPORT-2 — une colonne SENSIBLE (le salaire) n'est gardée pour aucune ligne, refusée comprise.
        for (final cleSensible in m.colonnesSensibles) {
          l.brut?[cleSensible] = '';
        }
      }
    }
    apercu.termine = true;
    return apercu;
  }

  /// LE point de passage : le dépôt propriétaire de la table, avec l'UUID déterministe.
  Future<void> _ecrire(ModuleImportation m, Map<String, Object?> v, String id) async {
    switch (m.cle) {
      case 'stocks':
        await ProduitsRepository(database: database).creer(
          FormulaireProduit(
            nom: v['name'] as String,
            categorieId: v['category_id'] as String,
            especeId: (v['species_id'] as String?) ?? '',
            unite: v['unit'] as String,
            mode: v['pricing_mode'] as String,
            prixMin: (v['price_min'] as int?)?.toDouble(),
            prixMax: (v['price_max'] as int?)?.toDouble(),
            stock: v['stock_qty'] as double,
            seuil: v['alert_threshold'] as double,
            tva: v['tva_rate'] as double,
            description: (v['description'] as String?) ?? '',
            categorieEffectif: (v['categorie_effectif'] as String?) ?? '',
          ),
          id: id,
        );
      case 'clients':
        await ClientsCreancesRepository(database: database, deviceId: deviceId).creerClient(
          FormulaireClient(
            nom: v['name'] as String,
            telephone: (v['phone'] as String?) ?? '',
            ville: (v['city'] as String?) ?? '',
            email: (v['email'] as String?) ?? '',
            ifu: (v['ifu'] as String?) ?? '',
          ),
          id: id,
        );
      case 'fournisseurs':
        await FournisseursRepository(database: database, deviceId: deviceId).creerFournisseur(
          FormulaireFournisseur(
            nom: v['name'] as String,
            categorie: v['category'] as String,
            telephone: v['phone'] as String,
            adresse: (v['address'] as String?) ?? '',
          ),
          id: id,
        );
      case 'employes':
        await PersonnelRepository(database: database, identifiantPoste: deviceId).enregistrerEmploye(
          id: id,
          prenom: v['first_name'] as String,
          nom: v['last_name'] as String,
          fonction: v['position'] as String,
          embauche: DateTime.parse(v['hire_date'] as String),
          salaire: (v['base_salary'] as int?)?.toDouble(),
          statut: v['status'] as String,
        );
      case 'plan_comptable':
        await ComptabiliteRepository(database: database, deviceId: deviceId).creerCompte(
          code: v['code'] as String,
          libelle: v['label'] as String,
          classe: v['class'] as String,
          id: id,
        );
      case 'rations':
        await ParametresElevageRepository(database: database, maintenant: _maintenant).enregistrerRation(
          id: id,
          espece: v['species_code'] as String,
          stade: v['stage_label'] as String,
          grammes: v['ration_g_per_day'] as int,
        );
    }
  }

  void _memoriser(ModuleImportation m, Map<String, Object?> v, ContexteImportation c) {
    switch (m.cle) {
      case 'stocks':
        final k = _cleNaturelleProduit('${v['name']}', '${v['category_id']}', '${v['unit']}', v['species_id'] as String?);
        if (k != null) c.produits.putIfAbsent(k, () => 'LOC');
      case 'clients' || 'fournisseurs':
        final t = normaliserTelephone(v['phone'] as String?);
        if (t != null) (m.cle == 'clients' ? c.clients : c.fournisseurs).add('${cle('${v['name']}')}|$t');
      case 'employes':
        c.employes.add(cleLigne(m, v));
      case 'plan_comptable':
        c.comptes.add(cleLigne(m, v));
      case 'rations':
        c.rations.add(cleLigne(m, v));
    }
  }

  // ── Modèle et rapport (xlsx) ──────────────────────────────────────────────────────────────────────────────

  /// Listes de valeurs du modèle (`ModuleImport::listes`), lues dans la base du poste.
  Future<Map<String, List<String>>> listes(ModuleImportation m) async {
    switch (m.cle) {
      case 'stocks':
        final categories = await (database.select(database.productCategories)
              ..where((c) => c.isActive.equals(true))
              ..orderBy([(c) => OrderingTerm(expression: c.label)]))
            .get();
        final especes = await (database.select(database.livestockSpecies)..orderBy([(e) => OrderingTerm(expression: e.label)])).get();
        final unites = [...unitesProposees];
        final existantes = await (database.selectOnly(database.products, distinct: true)..addColumns([database.products.unit])).get();
        for (final u in existantes.map((r) => r.read(database.products.unit)).whereType<String>()) {
          if (u.isNotEmpty && !unites.any((x) => x.toLowerCase() == u.toLowerCase())) unites.add(u);
        }
        return {
          'categories': [for (final c in categories) c.label],
          'unites': unites,
          'filieres': [for (final e in especes) e.label],
          'modes_prix': [modeFourchette, modeDevis],
          'categories_effectif': [...CategorieVolaille.libelles.values, ...StadePondeuse.libelles.values],
        };
      case 'fournisseurs':
        return {'categories': categoriesFournisseur};
      case 'employes':
        return {'statuts': statutsEmploye.values.toList()};
      case 'plan_comptable':
        return {'classes': classesComptables.values.toList()};
      case 'rations':
        return {'especes': especesRation.values.toList()};
      default:
        return {};
    }
  }

  /// Fabrique le modèle .xlsx du module, HORS LIGNE : mêmes feuilles, mêmes en-têtes, même version que le serveur.
  Future<Uint8List> genererModele(ModuleImportation m) async {
    final classeur = Excel.createExcel();
    final instructions = classeur[feuilleInstructions];
    final donnees = classeur[feuilleDonnees];
    final listes = classeur[feuilleListes];
    final meta = classeur[feuilleMeta];
    classeur.delete('Sheet1');

    final enGras = CellStyle(bold: true);
    final valeursListes = await this.listes(m);
    var c = 0;
    for (final MapEntry(key: nom, value: valeurs) in valeursListes.entries) {
      listes.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0), TextCellValue(nom), cellStyle: enGras);
      for (var i = 0; i < valeurs.length; i++) {
        listes.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: i + 1), TextCellValue(valeurs[i]));
      }
      listes.setColumnWidth(c, 28);
      c++;
    }

    for (var i = 0; i < m.colonnes.length; i++) {
      donnees.updateCell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0), TextCellValue(m.colonnes[i].entete), cellStyle: enGras);
      donnees.setColumnWidth(i, (m.colonnes[i].entete.length + 6).clamp(16, 60).toDouble());
    }

    var ligne = 0;
    void ecrire(String a, [String b = '']) {
      instructions.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: ligne), TextCellValue(a));
      if (b.isNotEmpty) instructions.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: ligne), TextCellValue(b));
      ligne++;
    }

    instructions.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), TextCellValue('Modèle « ${m.libelle} » — version ${m.version}'), cellStyle: enGras);
    ligne = 2;
    ecrire('Modèle', m.libelle);
    instructions.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: ligne), TextCellValue('Version du modèle'));
    instructions.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: ligne), IntCellValue(m.version));
    ligne++;
    final maintenant = _maintenant();
    ecrire('Généré le', '${_deux(maintenant.day)}/${_deux(maintenant.month)}/${maintenant.year} ${_deux(maintenant.hour)}:${_deux(maintenant.minute)} (poste)');
    ligne++;
    ecrire('Comment remplir ce modèle');
    ecrire('1.', "Remplissez la feuille « $feuilleDonnees », une ligne par fiche, sous les en-têtes. Les colonnes marquées d'une étoile (*) sont obligatoires.");
    ecrire('2.', "NE RENOMMEZ PAS les en-têtes et ne supprimez aucune colonne ni la feuille « $feuilleDonnees ».");
    ecrire('3.', "Déposez ensuite le fichier à l'étape 3 de l'écran « Importation en masse » : un aperçu ligne par ligne s'affiche AVANT toute écriture.");
    ecrire('Création seule', "Une fiche déjà présente est IGNORÉE, jamais modifiée. Importer deux fois le même fichier ne crée aucun doublon.");
    ecrire('Listes', "Choisissez « Catégorie », « Filière », « Mode de prix »… parmi les valeurs de la feuille « $feuilleListes » : une autre valeur est refusée à l'aperçu.");
    ligne++;
    ecrire('Formats');
    ecrire('Montants', 'Francs CFA ENTIERS, sans décimale ni séparateur de milliers (exemple : 4500).');
    ecrire('Nombres', 'Quantités et pourcentages : virgule ou point (exemple : 8,5).');
    ecrire(
      'Dates',
      m.colonnes.any((c) => c.type == 'date')
          ? 'Format AAAA-MM-JJ (exemple : 2026-11-08). Écrivez la date telle quelle, comme du texte.'
          : "Format AAAA-MM-JJ (exemple : 2026-11-08). Aucune date n'est demandée par ce modèle.",
    );
    ecrire('Téléphones', 'Écrivez les téléphones et l\'IFU comme du texte (le zéro initial doit rester).');
    ecrire('Limites', '5 000 lignes et 5 Mo au plus par fichier. Fichier .xlsx uniquement.');
    ligne++;
    ecrire('Les colonnes');
    for (final col in m.colonnes) {
      ecrire(col.entete, col.obligatoire ? 'Obligatoire' : 'Facultatif');
    }
    instructions.setColumnWidth(0, 30);
    instructions.setColumnWidth(1, 60);

    final lignesMeta = [('modele', m.cle), ('version', '${m.version}'), ('genere_le', maintenant.toIso8601String())];
    for (var i = 0; i < lignesMeta.length; i++) {
      meta.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i), TextCellValue(lignesMeta[i].$1));
    }
    meta.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0), TextCellValue(m.cle));
    meta.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1), IntCellValue(m.version));
    meta.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2), TextCellValue(lignesMeta[2].$2));

    classeur.setDefaultSheet(feuilleInstructions);
    final sortie = classeur.encode();
    if (sortie == null) throw StateError('Le modèle n’a pas pu être encodé.');
    return Uint8List.fromList(sortie);
  }

  static String _deux(int n) => n.toString().padLeft(2, '0');

  /// Libellés des états (`ImportMasseService::libellesDeStatut`).
  static String libelleDeStatut(String statut, {required bool termine}) => switch (statut) {
    creee => 'Créée',
    ignoree => 'Ignorée (déjà présente)',
    refusee => 'Refusée',
    _ => 'Valide',
  };

  /// Rapport téléchargeable : feuille « Rapport » et feuille « Lignes refusées » (leurs valeurs, à corriger puis à ré-importer).
  /// Les valeurs sont écrites comme du TEXTE (jamais une formule).
  Uint8List rapport(ApercuImportation apercu) {
    final classeur = Excel.createExcel();
    final rapport = classeur['Rapport'];
    final refusees = classeur['Lignes refusées'];
    classeur.delete('Sheet1');
    final enGras = CellStyle(bold: true);

    void ligneTexte(Sheet f, int r, List<String> valeurs, {bool gras = false}) {
      for (var i = 0; i < valeurs.length; i++) {
        f.updateCell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: r), TextCellValue(valeurs[i]), cellStyle: gras ? enGras : null);
      }
    }

    ligneTexte(rapport, 0, ['Ligne', 'Désignation', 'Résultat', 'Motif'], gras: true);
    for (var i = 0; i < apercu.lignes.length; i++) {
      final l = apercu.lignes[i];
      ligneTexte(rapport, i + 1, ['${l.ligne}', l.designation, libelleDeStatut(l.statut, termine: apercu.termine), l.motif ?? '']);
    }

    ligneTexte(refusees, 0, ['Ligne', 'Motif', for (final c in apercu.module.colonnes) c.entete], gras: true);
    var n = 1;
    for (final l in apercu.lignes.where((l) => l.statut == refusee)) {
      // Une colonne sensible reste VIDE : le rapport ne reproduit jamais un salaire.
      ligneTexte(refusees, n++, [
        '${l.ligne}',
        l.motif ?? '',
        for (final c in apercu.module.colonnes) apercu.module.colonnesSensibles.contains(c.cle) ? '' : (l.brut?[c.cle] ?? ''),
      ]);
    }

    final sortie = classeur.encode();
    if (sortie == null) throw StateError('Le rapport n’a pas pu être encodé.');
    return Uint8List.fromList(sortie);
  }

  /// Nom du rapport — `ImportMasseService::nomDuRapport`.
  String nomDuRapport(ApercuImportation apercu) {
    final h = _maintenant();
    return 'Rapport_importation_${apercu.module.cle}_${h.year}${_deux(h.month)}${_deux(h.day)}_${_deux(h.hour)}${_deux(h.minute)}${_deux(h.second)}.xlsx';
  }
}

/// Listes et fiches existantes, lues UNE fois pour tout l'import (5 000 lignes ne relisent pas 5 000 fois le catalogue).
class ContexteImportation {
  ContexteImportation({
    required this.categories,
    required this.filieres,
    required this.effectifs,
    required this.produits,
    required this.clients,
    required this.fournisseurs,
    required this.employes,
    required this.comptes,
    required this.rations,
  });

  /// clé de comparaison du libellé → identifiant.
  final Map<String, String> categories;
  final Map<String, String> filieres;

  /// clé de comparaison du libellé → clé de la catégorie d'effectif.
  final Map<String, String> effectifs;

  /// clé naturelle → SKU des produits ACTIFS.
  final Map<String, String> produits;

  /// clés naturelles « nom|téléphone » des fiches ACTIVES (téléphone exploitable seulement).
  final Set<String> clients;
  final Set<String> fournisseurs;

  /// clés de ligne des employés ACTIFS (`nom|prénom|date d'embauche`), des comptes du plan (tous, archivés compris) et des rations ACTIVES.
  final Set<String> employes;
  final Set<String> comptes;
  final Set<String> rations;

  /// Ne lit que ce que [module] consulte : un caissier qui importe des clients ne lit ni le catalogue ni les fournisseurs.
  static Future<ContexteImportation> charger(AppDatabase db, String module) async {
    final categories = <String, String>{};
    final stocks = module == 'stocks';
    for (final c in stocks ? await (db.select(db.productCategories)..where((c) => c.isActive.equals(true))).get() : const <ProductCategory>[]) {
      categories.putIfAbsent(ImportationRepository.cle(c.label), () => c.id);
    }
    final filieres = <String, String>{};
    for (final e in stocks ? await db.select(db.livestockSpecies).get() : const <EspeceElevage>[]) {
      filieres.putIfAbsent(ImportationRepository.cle(e.label), () => e.id);
    }
    final effectifs = <String, String>{
      for (final e in {...CategorieVolaille.libelles, ...StadePondeuse.libelles}.entries) ImportationRepository.cle(e.value): e.key,
    };

    final produits = <String, String>{};
    final actifs = !stocks
        ? const <Product>[]
        : await (db.select(db.products)
              ..where((p) => p.isActive.equals(true))
              ..orderBy([(p) => OrderingTerm(expression: p.id)]))
            .get();
    for (final p in actifs) {
      final k = ImportationRepository._cleNaturelleProduit(p.name, p.categoryId ?? '', p.unit, p.speciesId);
      if (k != null) produits.putIfAbsent(k, () => p.sku);
    }

    final clients = <String>{};
    for (final x in module != 'clients' ? const <Customer>[] : await (db.select(db.customers)..where((c) => c.isActive.equals(true))).get()) {
      final t = ImportationRepository.normaliserTelephone(x.phone);
      final n = ImportationRepository.cle(x.name);
      if (t != null && n.isNotEmpty) clients.add('$n|$t');
    }
    final fournisseurs = <String>{};
    for (final x in module != 'fournisseurs' ? const <Supplier>[] : await (db.select(db.suppliers)..where((s) => s.isActive.equals(true))).get()) {
      final t = ImportationRepository.normaliserTelephone(x.phone);
      final n = ImportationRepository.cle(x.name);
      if (t != null && n.isNotEmpty) fournisseurs.add('$n|$t');
    }

    final employes = <String>{};
    for (final x in module != 'employes' ? const <Employee>[] : await (db.select(db.employees)..where((t) => t.isActive.equals(true))).get()) {
      final h = x.hireDate;
      final date = h == null ? '' : '${h.year.toString().padLeft(4, '0')}-${h.month.toString().padLeft(2, '0')}-${h.day.toString().padLeft(2, '0')}';
      employes.add('${ImportationRepository.cle(x.lastName)}|${ImportationRepository.cle(x.firstName)}|$date');
    }
    final comptes = <String>{};
    for (final x in module != 'plan_comptable' ? const <ChartOfAccount>[] : await db.select(db.chartOfAccounts).get()) {
      comptes.add(ImportationRepository.cleDeCompte(x.code));
    }
    final rations = <String>{};
    for (final x in module != 'rations' ? const <FeedRationStandard>[] : await (db.select(db.feedRationStandards)..where((t) => t.isActive.equals(true))).get()) {
      rations.add('${x.speciesCode}|${ImportationRepository.cle(x.stageLabel)}');
    }

    return ContexteImportation(
      categories: categories,
      filieres: filieres,
      effectifs: effectifs,
      produits: produits,
      clients: clients,
      fournisseurs: fournisseurs,
      employes: employes,
      comptes: comptes,
      rations: rations,
    );
  }
}
