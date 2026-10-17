import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';

/// Ce que l'utilisateur saisit dans « Nouveau Courrier » / « Modifier — Gestion des Courriers ».
class FormulaireCourrier {
  const FormulaireCourrier({
    this.type = '',
    this.objet = '',
    this.partie = '',
    this.date,
  });

  /// `entrant` · `sortant` (le libellé affiché est « Entrant » / « Sortant »).
  final String type;
  final String objet;

  /// Expéditeur si le courrier est entrant, destinataire s'il est sortant.
  final String partie;
  final DateTime? date;
}

/// Ce que l'utilisateur saisit dans « Archiver un Document » / « Modifier — Archivage des
/// Documents ». ⚠️ Aucun fichier : ni la maquette ni le schéma n'en ont.
class FormulaireArchive {
  const FormulaireArchive({
    this.titre = '',
    this.categorie = '',
    this.dateArchivage,
    this.echeance,
  });

  final String titre;

  /// Texte libre côté serveur ; l'écran propose Juridique / Fiscal / Sanitaire / Foncier /
  /// Autre mais accepte et affiche toute valeur reçue.
  final String categorie;
  final DateTime? dateArchivage;

  /// Facultative ; si présente, jamais antérieure à [dateArchivage].
  final DateTime? echeance;
}

/// Ce que l'utilisateur saisit dans « Générer un Document » / « Modifier — Documents
/// Administratifs ». ⚠️ Aucun fichier n'est produit : c'est une ligne de registre.
class FormulaireDocument {
  const FormulaireDocument({
    this.titre = '',
    this.type = '',
    this.beneficiaire = '',
    this.date,
    this.statut = 'en_attente',
  });

  final String titre;

  /// Texte libre côté serveur ; l'écran propose Attestation / Certificat / Note interne /
  /// Correspondance mais accepte et affiche toute valeur reçue.
  final String type;
  final String beneficiaire;
  final DateTime? date;

  /// `signe` · `en_attente`.
  final String statut;
}

/// Statut d'échéance d'un document archivé. ⚠️ Jamais stocké : toujours déduit de l'échéance
/// par [AdministrationRepository.statutArchive].
enum StatutArchive {
  valide('Valide'),
  bientotExpire('Bientôt expiré'),
  expire('Expiré');

  const StatutArchive(this.libelle);

  final String libelle;
}

class DonneesAdministration {
  const DonneesAdministration({
    required this.courriers,
    required this.documents,
    required this.archives,
    required this.mois,
    this.refusCourriers = const {},
    this.refusArchives = const {},
    this.refusDocuments = const {},
  });

  /// Idem pour les documents administratifs (création, modification OU retrait refusés).
  final Map<String, String> refusDocuments;

  /// Motif du refus du serveur, par identifiant de courrier (courrier en `conflict`),
  /// conservé mot pour mot.
  final Map<String, String> refusCourriers;

  /// Idem pour les documents archivés (création, modification OU retrait refusés).
  final Map<String, String> refusArchives;

  /// Courriers ACTIFS, plus les archivés dont l'archivage a été REFUSÉ par le serveur
  /// (`conflict`) : un refus ne doit pas disparaître avec la ligne (F0.78-bis). Les cartes
  /// ne comptent que les actifs.
  final List<Mail> courriers;

  /// Documents administratifs ACTIFS, plus les retraits REFUSÉS par le serveur (`conflict`),
  /// comme les courriers et les archives. Les cartes ne comptent que les actifs.
  final List<AdministrativeDocument> documents;

  /// Documents ACTIFS, plus les retraits REFUSÉS par le serveur (`conflict`) : un refus ne
  /// doit pas disparaître avec la ligne (même règle que les courriers, F0.78-bis). Les
  /// cartes ne comptent que les actifs.
  final List<ArchivedDocument> archives;
  final DateTime mois;

  List<ArchivedDocument> get archivesActives =>
      archives.where((a) => a.isActive).toList();

  List<Mail> get courriersDuMois => courriers
      .where(
        (c) =>
            c.isActive &&
            c.mailDate != null &&
            c.mailDate!.year == mois.year &&
            c.mailDate!.month == mois.month,
      )
      .toList();

  int get recus => courriersDuMois.where((c) => c.type == 'entrant').length;

  int get envoyes => courriersDuMois.where((c) => c.type == 'sortant').length;

  /// ⚠️ **TOUJOURS `null`** : aucun statut de courrier n'existe en base (ni sur le poste ni
  /// sur le serveur), la maquette en suppose un (« En attente »). On n'en invente pas :
  /// compter « 0 » affirmerait qu'aucun courrier n'attend de réponse.
  int? get enAttente => null;

  List<AdministrativeDocument> get documentsActifs =>
      documents.where((d) => d.isActive).toList();

  /// Carte « Générés (mois) » : documents ACTIFS dont la date tombe dans le mois (et l'année)
  /// de [mois] — le calcul de la page web, quel que soit le statut. Un retrait, refusé ou non,
  /// ne compte pas.
  int get generesDuMois => documentsActifs
      .where(
        (d) =>
            d.docDate != null &&
            d.docDate!.year == mois.year &&
            d.docDate!.month == mois.month,
      )
      .length;

  /// Carte « En attente » (signature) : documents ACTIFS au statut `en_attente`.
  int get documentsEnAttente =>
      documentsActifs.where((d) => d.status == 'en_attente').length;

  /// ⚠️⚠️ **UNE ARCHIVE EXPIRÉE EST UN AGRÉMENT PÉRIMÉ**, pas une ligne de
  /// tableau : un contrat de bail ou un agrément vétérinaire dont l'échéance
  /// est passée expose la ferme. C'est la seule donnée de cet écran qui doit
  /// alerter.
  ///
  /// ⚠️ Documents ACTIFS seulement, statut du serveur (échéance atteinte ou dépassée).
  List<ArchivedDocument> expirees(DateTime jour) =>
      _actifsAuStatut(StatutArchive.expire, jour);

  /// Carte « Expirant sous 30j » : documents ACTIFS en « Bientôt expiré » (les expirés n'y
  /// sont pas, les retirés non plus) — règle du serveur (15.24).
  List<ArchivedDocument> bientotExpirees(DateTime jour) =>
      _actifsAuStatut(StatutArchive.bientotExpire, jour);

  List<ArchivedDocument> _actifsAuStatut(StatutArchive statut, DateTime jour) =>
      archivesActives
          .where(
            (a) =>
                AdministrationRepository.statutArchive(a.expiryDate, jour) ==
                statut,
          )
          .toList();
}

/// Lectures et écritures de `prototype_html/administration.html`.
///
/// ⚠️⚠️ **LES TROIS ONGLETS S'ÉCRIVENT AU POSTE** (courriers F0.78, archivage F0.79,
/// documents administratifs F0.80) : local d'abord, `pending`, le serveur valide (et attribue
/// la référence d'un courrier). ⚠️ « Générer un Document » n'écrit qu'une ligne de registre :
/// l'en-tête officielle, la signature et le fichier, le poste ne les a pas.
class AdministrationRepository {
  AdministrationRepository({required this.database, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final Uuid _uuid;

  /// Seuil « Bientôt expiré », en jours — celui du serveur
  /// (`ArchivedDocument::SEUIL_BIENTOT_EXPIRE_JOURS`, ticket 15.24). L'ancien seuil du poste
  /// (60 j, « À renouveler ») n'existait ni dans la maquette ni sur le serveur.
  static const int seuilBientotExpireJours = 30;

  /// Catégories proposées par la page web (Laravel). ⚠️ Le serveur ne contraint PAS la
  /// valeur (texte libre) : toute catégorie reçue s'affiche et se modifie telle quelle.
  static const categoriesProposees = <String>[
    'Juridique',
    'Fiscal',
    'Sanitaire',
    'Foncier',
    'Autre',
  ];

  /// Longueur de la colonne `archived_documents.category` côté serveur (`string(100)`). La
  /// validation Laravel n'a pas de `max` : le poste l'applique pour qu'une saisie trop
  /// longue ne parte pas vers une erreur de base.
  static const int categorieMax = 100;

  /// ⚠️⚠️ **LA SEULE FONCTION DE STATUT DU POSTE** — la règle du serveur (15.24),
  /// `ArchivedDocument::statutPour()`. Jours CALENDAIRES (heures ignorées) entre l'échéance
  /// et [aujourdhui] : sans échéance = Valide ; jours ≤ 0 = Expiré (l'échéance du jour est
  /// déjà expirée) ; 1 à 30 = Bientôt expiré ; 31 et plus = Valide.
  ///
  /// [aujourdhui] est le jour LOCAL du poste. Le calcul passe par des dates UTC construites
  /// à partir des seules composantes année/mois/jour : un changement d'heure ne décale
  /// jamais le nombre de jours.
  static StatutArchive statutArchive(DateTime? echeance, DateTime aujourdhui) {
    if (echeance == null) return StatutArchive.valide;

    final jours = DateTime.utc(echeance.year, echeance.month, echeance.day)
        .difference(
          DateTime.utc(aujourdhui.year, aujourdhui.month, aujourdhui.day),
        )
        .inDays;

    if (jours <= 0) return StatutArchive.expire;
    if (jours <= seuilBientotExpireJours) return StatutArchive.bientotExpire;
    return StatutArchive.valide;
  }

  /// Règles de saisie, identiques à `ArchiveDocumentService::regles()` (Laravel) : titre
  /// obligatoire ≤ 255, catégorie obligatoire (texte libre), date d'archivage obligatoire,
  /// échéance facultative mais jamais antérieure à la date d'archivage. Vide si recevable.
  /// Clés : `titre`, `categorie`, `dateArchivage`, `echeance`.
  static Map<String, String> validerArchive(FormulaireArchive f) {
    final e = <String, String>{};

    final titre = f.titre.trim();
    if (titre.isEmpty) {
      e['titre'] = 'Le champ « Nom du document » est obligatoire.';
    } else if (titre.length > 255) {
      e['titre'] = '255 caractères au plus.';
    }

    final categorie = f.categorie.trim();
    if (categorie.isEmpty) {
      e['categorie'] = 'Le champ « Catégorie » est obligatoire.';
    } else if (categorie.length > categorieMax) {
      e['categorie'] = '$categorieMax caractères au plus.';
    }

    if (f.dateArchivage == null) {
      e['dateArchivage'] = "Le champ « Date d'archivage » est obligatoire.";
    } else if (f.echeance != null &&
        _jour(f.echeance!).isBefore(_jour(f.dateArchivage!))) {
      e['echeance'] =
          "La date d'expiration doit être postérieure ou égale à la date d'archivage.";
    }

    return e;
  }

  /// Archive un document, EN ATTENTE d'envoi. Aucun statut n'est écrit (il se déduit).
  Future<ArchivedDocument> creerArchive(FormulaireArchive f) async {
    _exigerArchive(f);
    final id = _uuid.v4();

    await database
        .into(database.archivedDocuments)
        .insert(
          ArchivedDocumentsCompanion.insert(
            id: id,
            title: f.titre.trim(),
            category: Value(f.categorie.trim()),
            archivedDate: Value(_jour(f.dateArchivage!)),
            expiryDate: Value(f.echeance == null ? null : _jour(f.echeance!)),
            syncStatus: const Value(SyncStatus.pending),
            knownByServer: const Value(false),
          ),
        );

    return (await _archive(id))!;
  }

  /// Modifie un document ACTIF. Un document retiré ne se modifie plus (le serveur le
  /// refuse aussi). ⚠️ Corriger une ligne REFUSÉE efface son refus : le motif ne doit pas
  /// survivre à la correction.
  Future<ArchivedDocument> modifierArchive(
    String id,
    FormulaireArchive f,
  ) async {
    _exigerArchive(f);
    final actuel = await _archive(id);
    if (actuel == null) throw StateError('Document inconnu.');
    if (!actuel.isActive) {
      throw StateError(
        'Ce document est retiré des archives : il ne peut plus être modifié.',
      );
    }

    await database.transaction(() async {
      await (database.update(
        database.archivedDocuments,
      )..where((a) => a.id.equals(id))).write(
        ArchivedDocumentsCompanion(
          title: Value(f.titre.trim()),
          category: Value(f.categorie.trim()),
          archivedDate: Value(_jour(f.dateArchivage!)),
          expiryDate: Value(f.echeance == null ? null : _jour(f.echeance!)),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await (database.delete(
        database.syncConflicts,
      )..where((c) => c.id.equals('archived_documents:$id'))).go();
    });

    return (await _archive(id))!;
  }

  /// Retire un document des archives : `is_active = false`, rien n'est supprimé. Retourne
  /// `false` s'il était déjà retiré ou inconnu (idempotent, comme le serveur).
  ///
  /// ⚠️⚠️ **UN DOCUMENT QUE LE SERVEUR N'A JAMAIS ACCEPTÉ N'A RIEN À RETIRER LÀ-BAS**
  /// (même règle que les courriers, F0.78-bis) : l'envoi `{id, is_active:false}` recevrait
  /// « Document inconnu » pour toujours, sur une ligne masquée. Il est donc supprimé du poste,
  /// avec son éventuel refus de création ; rien n'est envoyé.
  Future<bool> retirerArchive(String id) async {
    final actuel = await _archive(id);
    if (actuel == null || !actuel.isActive) return false;

    if (!actuel.knownByServer) {
      await database.transaction(() async {
        await (database.delete(
          database.archivedDocuments,
        )..where((a) => a.id.equals(id))).go();
        await (database.delete(
          database.syncConflicts,
        )..where((c) => c.id.equals('archived_documents:$id'))).go();
      });
      return true;
    }

    // ⚠️ F0.79-bis : le retrait remplace l'état refusé ; son ancien motif ne doit pas rester
    // orphelin (la ligne devient invisible, le motif apparaîtrait seul dans Synchronisation).
    await database.transaction(() async {
      await (database.update(
        database.archivedDocuments,
      )..where((a) => a.id.equals(id))).write(
        const ArchivedDocumentsCompanion(
          isActive: Value(false),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      await (database.delete(
        database.syncConflicts,
      )..where((c) => c.id.equals('archived_documents:$id'))).go();
    });

    return true;
  }

  void _exigerArchive(FormulaireArchive f) {
    final erreurs = validerArchive(f);
    if (erreurs.isNotEmpty) throw ArgumentError(erreurs.values.join(' '));
  }

  Future<ArchivedDocument?> _archive(String id) => (database.select(
    database.archivedDocuments,
  )..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Règles de saisie, identiques à `CourrierService::regles()` (Laravel) : les QUATRE
  /// champs sont obligatoires, `type` ∈ {entrant, sortant}, objet ≤ 255, partie ≤ 150.
  /// Vide si recevable. Les clés sont `type`, `objet`, `partie`, `date`.
  static Map<String, String> validerCourrier(FormulaireCourrier f) {
    final e = <String, String>{};

    if (f.type != 'entrant' && f.type != 'sortant') {
      e['type'] = f.type.isEmpty
          ? 'Le champ « Type » est obligatoire.'
          : 'Type de courrier invalide.';
    }
    final objet = f.objet.trim();
    if (objet.isEmpty) {
      e['objet'] = 'Le champ « Objet » est obligatoire.';
    } else if (objet.length > 255) {
      e['objet'] = '255 caractères au plus.';
    }
    final partie = f.partie.trim();
    if (partie.isEmpty) {
      e['partie'] = 'Le champ « Expéditeur / Destinataire » est obligatoire.';
    } else if (partie.length > 150) {
      e['partie'] = '150 caractères au plus.';
    }
    if (f.date == null) e['date'] = 'Le champ « Date » est obligatoire.';

    return e;
  }

  /// Enregistre un courrier, EN ATTENTE d'envoi. ⚠️ **La référence reste vide** : le poste
  /// n'invente JAMAIS `CR-AAAA-NNN`, le serveur l'attribue et elle redescend au tirage.
  Future<Mail> creerCourrier(FormulaireCourrier f) async {
    _exiger(f);
    final id = _uuid.v4();

    await database
        .into(database.mails)
        .insert(
          MailsCompanion.insert(
            id: id,
            type: f.type,
            subject: f.objet.trim(),
            party: Value(f.partie.trim()),
            mailDate: Value(_jour(f.date!)),
            syncStatus: const Value(SyncStatus.pending),
            knownByServer: const Value(false),
          ),
        );

    return (await _courrier(id))!;
  }

  /// Modifie un courrier ACTIF (la référence ne change jamais). Un courrier archivé ne se
  /// modifie plus — le serveur le refuse aussi.
  Future<Mail> modifierCourrier(String id, FormulaireCourrier f) async {
    _exiger(f);
    final actuel = await _courrier(id);
    if (actuel == null) throw StateError('Courrier inconnu.');
    if (!actuel.isActive) {
      throw StateError(
        'Ce courrier est archivé : il ne peut plus être modifié.',
      );
    }

    // ⚠️ F0.79-bis : corriger un courrier refusé efface son refus (même transaction).
    await database.transaction(() async {
      await (database.update(
        database.mails,
      )..where((m) => m.id.equals(id))).write(
        MailsCompanion(
          type: Value(f.type),
          subject: Value(f.objet.trim()),
          party: Value(f.partie.trim()),
          mailDate: Value(_jour(f.date!)),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await (database.delete(
        database.syncConflicts,
      )..where((c) => c.id.equals('mails:$id'))).go();
    });

    return (await _courrier(id))!;
  }

  /// Archive : `is_active = false`, rien n'est supprimé. Retourne `false` si le courrier
  /// était déjà archivé ou inconnu (idempotent, comme le serveur).
  ///
  /// ⚠️⚠️ **UN COURRIER QUE LE SERVEUR N'A JAMAIS ACCEPTÉ N'A RIEN À ARCHIVER LÀ-BAS**
  /// (F0.78-bis) : l'envoi `{id, is_active:false}` recevrait « Courrier inconnu » pour
  /// toujours, sur une ligne masquée. Il est donc retiré du poste, avec son éventuel refus de
  /// création ; rien n'est envoyé. Le signal est `known_by_server`, PAS `reference IS NULL` :
  /// un courrier accepté dont la référence n'est pas encore descendue, lui, doit être archivé
  /// côté serveur.
  Future<bool> archiverCourrier(String id) async {
    final actuel = await _courrier(id);
    if (actuel == null || !actuel.isActive) return false;

    if (!actuel.knownByServer) {
      await database.transaction(() async {
        await (database.delete(
          database.mails,
        )..where((m) => m.id.equals(id))).go();
        await (database.delete(
          database.syncConflicts,
        )..where((c) => c.id.equals('mails:$id'))).go();
      });
      return true;
    }

    // ⚠️ F0.79-bis : l'archivage remplace l'état refusé ; son ancien motif ne reste pas orphelin.
    await database.transaction(() async {
      await (database.update(
        database.mails,
      )..where((m) => m.id.equals(id))).write(
        const MailsCompanion(
          isActive: Value(false),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      await (database.delete(
        database.syncConflicts,
      )..where((c) => c.id.equals('mails:$id'))).go();
    });

    return true;
  }

  void _exiger(FormulaireCourrier f) {
    final erreurs = validerCourrier(f);
    if (erreurs.isNotEmpty) throw ArgumentError(erreurs.values.join(' '));
  }

  Future<Mail?> _courrier(String id) => (database.select(
    database.mails,
  )..where((m) => m.id.equals(id))).getSingleOrNull();

  /// Types proposés par la page web (Laravel). ⚠️ Le serveur ne contraint PAS la valeur
  /// (texte libre) : tout type reçu s'affiche et se modifie tel quel. Ce ne sont PAS les
  /// quatre options de la maquette (« Attestation de stage », « Certificat de travail »… qui
  /// y servent aussi de titre).
  static const typesProposes = <String>[
    'Attestation',
    'Certificat',
    'Note interne',
    'Correspondance',
  ];

  /// Longueur de la colonne `administrative_documents.type` côté serveur (`string(100)`). La
  /// validation Laravel n'a pas de `max` : le poste l'applique pour qu'une saisie trop longue
  /// ne parte pas vers une erreur de base (qui ferait échouer tout l'envoi).
  static const int typeMax = 100;

  static const statutSigne = 'signe';
  static const statutEnAttente = 'en_attente';

  /// Règles de saisie, identiques à `DocumentAdministratifService::regles()` (Laravel) : titre
  /// obligatoire ≤ 255, type obligatoire (texte libre, ≤ 100 au poste), bénéficiaire
  /// obligatoire ≤ 150, date obligatoire, statut ∈ {signe, en_attente}. Vide si recevable.
  /// Clés : `titre`, `type`, `beneficiaire`, `date`, `statut`.
  static Map<String, String> validerDocument(FormulaireDocument f) {
    final e = <String, String>{};

    final titre = f.titre.trim();
    if (titre.isEmpty) {
      e['titre'] = 'Le champ « Titre du document » est obligatoire.';
    } else if (titre.length > 255) {
      e['titre'] = '255 caractères au plus.';
    }

    final type = f.type.trim();
    if (type.isEmpty) {
      e['type'] = 'Le champ « Type de document » est obligatoire.';
    } else if (type.length > typeMax) {
      e['type'] = '$typeMax caractères au plus.';
    }

    final beneficiaire = f.beneficiaire.trim();
    if (beneficiaire.isEmpty) {
      e['beneficiaire'] = 'Le champ « Bénéficiaire » est obligatoire.';
    } else if (beneficiaire.length > 150) {
      e['beneficiaire'] = '150 caractères au plus.';
    }

    if (f.date == null) e['date'] = 'Le champ « Date » est obligatoire.';

    if (f.statut != statutSigne && f.statut != statutEnAttente) {
      e['statut'] = 'Statut invalide : « Signé » ou « En attente ».';
    }

    return e;
  }

  /// Enregistre un document au registre, EN ATTENTE d'envoi. ⚠️ Aucun fichier n'est généré.
  Future<AdministrativeDocument> creerDocument(FormulaireDocument f) async {
    _exigerDocument(f);
    final id = _uuid.v4();

    await database
        .into(database.administrativeDocuments)
        .insert(
          AdministrativeDocumentsCompanion.insert(
            id: id,
            title: f.titre.trim(),
            type: Value(f.type.trim()),
            beneficiary: Value(f.beneficiaire.trim()),
            docDate: Value(_jour(f.date!)),
            status: Value(f.statut),
            syncStatus: const Value(SyncStatus.pending),
            knownByServer: const Value(false),
          ),
        );

    return (await _document(id))!;
  }

  /// Modifie un document ACTIF. Un document retiré ne se modifie plus (le serveur le refuse
  /// aussi). ⚠️ Corriger une ligne REFUSÉE efface son refus : le motif ne doit pas survivre à
  /// la correction.
  Future<AdministrativeDocument> modifierDocument(
    String id,
    FormulaireDocument f,
  ) async {
    _exigerDocument(f);
    final actuel = await _document(id);
    if (actuel == null) throw StateError('Document inconnu.');
    if (!actuel.isActive) {
      throw StateError(
        'Ce document est retiré du registre : il ne peut plus être modifié.',
      );
    }

    await database.transaction(() async {
      await (database.update(
        database.administrativeDocuments,
      )..where((d) => d.id.equals(id))).write(
        AdministrativeDocumentsCompanion(
          title: Value(f.titre.trim()),
          type: Value(f.type.trim()),
          beneficiary: Value(f.beneficiaire.trim()),
          docDate: Value(_jour(f.date!)),
          status: Value(f.statut),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await (database.delete(
        database.syncConflicts,
      )..where((c) => c.id.equals('administrative_documents:$id'))).go();
    });

    return (await _document(id))!;
  }

  /// Retire un document du registre : `is_active = false`, rien n'est supprimé. Retourne
  /// `false` s'il était déjà retiré ou inconnu (idempotent, comme le serveur).
  ///
  /// ⚠️⚠️ **UN DOCUMENT QUE LE SERVEUR N'A JAMAIS ACCEPTÉ N'A RIEN À RETIRER LÀ-BAS** (même
  /// règle que les courriers et les archives, F0.78-bis) : l'envoi `{id, is_active:false}`
  /// recevrait « Document inconnu » pour toujours, sur une ligne masquée. Il est donc
  /// supprimé du poste, avec son éventuel refus de création ; rien n'est envoyé.
  Future<bool> retirerDocument(String id) async {
    final actuel = await _document(id);
    if (actuel == null || !actuel.isActive) return false;

    if (!actuel.knownByServer) {
      await database.transaction(() async {
        await (database.delete(
          database.administrativeDocuments,
        )..where((d) => d.id.equals(id))).go();
        await (database.delete(
          database.syncConflicts,
        )..where((c) => c.id.equals('administrative_documents:$id'))).go();
      });
      return true;
    }

    // ⚠️ F0.79-bis : le retrait remplace l'état refusé ; son ancien motif ne doit pas rester
    // orphelin (la ligne devient invisible, le motif apparaîtrait seul dans Synchronisation).
    await database.transaction(() async {
      await (database.update(
        database.administrativeDocuments,
      )..where((d) => d.id.equals(id))).write(
        const AdministrativeDocumentsCompanion(
          isActive: Value(false),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      await (database.delete(
        database.syncConflicts,
      )..where((c) => c.id.equals('administrative_documents:$id'))).go();
    });

    return true;
  }

  void _exigerDocument(FormulaireDocument f) {
    final erreurs = validerDocument(f);
    if (erreurs.isNotEmpty) throw ArgumentError(erreurs.values.join(' '));
  }

  Future<AdministrativeDocument?> _document(String id) => (database.select(
    database.administrativeDocuments,
  )..where((d) => d.id.equals(id))).getSingleOrNull();

  /// Une date de courrier est un JOUR, sans heure.
  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<DonneesAdministration> charger({DateTime? mois}) async {
    // ⚠️ Les courriers ARCHIVÉS ne se montrent pas (comme le web) : ils restent en base
    // le temps de leur acquittement, mais quittent la liste et les cartes. EXCEPTION : un
    // archivage REFUSÉ par le serveur (`conflict`) reste affiché avec son motif (F0.78-bis).
    final courriers =
        await (database.select(database.mails)..where(
              (m) => Expression.or([
                m.isActive.equals(true),
                m.syncStatus.equalsValue(SyncStatus.conflict),
              ]),
            ))
            .get();
    // ⚠️ Même règle : les documents RETIRÉS ne se montrent pas, sauf un retrait REFUSÉ par le
    // serveur (`conflict`), qui garde sa ligne et son motif.
    final documents =
        await (database.select(database.administrativeDocuments)..where(
              (d) => Expression.or([
                d.isActive.equals(true),
                d.syncStatus.equalsValue(SyncStatus.conflict),
              ]),
            ))
            .get();
    // ⚠️ Même règle que les courriers : les documents RETIRÉS ne se montrent pas, sauf un
    // retrait REFUSÉ par le serveur (`conflict`), qui garde sa ligne et son motif.
    final archives =
        await (database.select(database.archivedDocuments)..where(
              (a) => Expression.or([
                a.isActive.equals(true),
                a.syncStatus.equalsValue(SyncStatus.conflict),
              ]),
            ))
            .get();

    final refus = {
      for (final c in await (database.select(
        database.syncConflicts,
      )..where((c) => c.sourceTable.equals('mails'))).get())
        c.recordId: c.reason,
    };
    final refusDesArchives = {
      for (final c in await (database.select(
        database.syncConflicts,
      )..where((c) => c.sourceTable.equals('archived_documents'))).get())
        c.recordId: c.reason,
    };

    final refusDesDocuments = {
      for (final c in await (database.select(
        database.syncConflicts,
      )..where((c) => c.sourceTable.equals('administrative_documents'))).get())
        c.recordId: c.reason,
    };

    return DonneesAdministration(
      mois: mois ?? DateTime.now(),
      refusCourriers: refus,
      refusArchives: refusDesArchives,
      refusDocuments: refusDesDocuments,
      courriers: courriers.toList()
        ..sort(
          (a, b) => (b.mailDate ?? DateTime(1970)).compareTo(
            a.mailDate ?? DateTime(1970),
          ),
        ),
      documents: documents.toList()
        ..sort(
          (a, b) => (b.docDate ?? DateTime(1970)).compareTo(
            a.docDate ?? DateTime(1970),
          ),
        ),
      archives: archives.toList()
        ..sort(
          (a, b) => (b.archivedDate ?? DateTime(1970)).compareTo(
            a.archivedDate ?? DateTime(1970),
          ),
        ),
    );
  }
}
