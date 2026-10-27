import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/export/pdf_recu.dart';
import '../../core/sync/sync_engine.dart';

/// Échec d'une opération sur les attestations : un message général, et ceux du
/// serveur PAR CHAMP (`personne`, `modele`) quand il en a rendu.
class EchecAttestation implements Exception {
  const EchecAttestation(this.message, {this.champs = const {}});

  final String message;
  final Map<String, String> champs;

  @override
  String toString() => message;
}

/// Le PDF rendu par le serveur — voir [PdfRecu].
typedef PdfAttestation = PdfRecu;

/// Appels au serveur : `POST /api/attestations` et
/// `PUT /api/attestation-templates/{type}` (ticket Laravel 15.13).
///
/// ⚠️⚠️ **LE PDF EST PRODUIT PAR LE SERVEUR, ET C'EST UN CHOIX.** Une attestation
/// est un document officiel : en-tête de la ferme, RCCM, mention du Directeur
/// Général — des éléments d'identité qui n'ont pas à être recopiés sur chaque
/// machine. Surtout, **la génération laisse sa trace d'audit côté serveur** : le
/// compteur « Attestations émises » n'est que ce décompte. Un PDF fabriqué au
/// poste sans passer par le serveur ne laisserait aucune trace et ne serait
/// compté nulle part.
///
/// ⚠️ **ELLE EXIGE DONC LE RÉSEAU**, et le dit : hors ligne, la génération est
/// refusée par une phrase, rien n'est produit en cachette.
class ClientAttestations {
  ClientAttestations(this._client);

  final Dio _client;

  Future<PdfAttestation> generer({
    required String type,
    required String personneId,
    required String contrat,
    DateTime? debut,
    DateTime? fin,
    String note = '',
    List<String> domaines = const [],
    String appreciation = '',
    DateTime? birthDate,
    String birthPlace = '',
    String civilite = 'M.',
    Map<String, String> signataires = const {},
  }) async {
    try {
      final reponse = await _client.post<List<int>>(
        '/api/attestations',
        data: {
          'type': type,
          'person_id': personneId,
          if (type == 'employe') 'contract_type': contrat,
          'start_date': ?_jour(debut),
          'end_date': ?_jour(fin),
          if (note.trim().isNotEmpty) 'note': note,
          if (domaines.isNotEmpty) 'domaines': domaines,
          if (appreciation.trim().isNotEmpty) 'appreciation': appreciation,
          if (birthDate != null) 'birth_date': _jour(birthDate),
          if (birthPlace.trim().isNotEmpty) 'birth_place': birthPlace,
          'civilite': civilite,
          // ATT-2 : les modifications des signataires POUR CETTE attestation (`sig2_nom`, `sig3_fonction`…). Les clés sont
          // celles du serveur ; la position 1 est le Directeur Général, 2 l'Examinateur, 3 le Président du Jury.
          ...signataires,
        },
        options: Options(responseType: ResponseType.bytes),
      );

      final octets = Uint8List.fromList(reponse.data ?? const <int>[]);
      if (octets.isEmpty) {
        throw const EchecAttestation('Le serveur a renvoyé un document vide.');
      }

      return PdfRecu(
        octets: octets,
        fichier: PdfRecu.nomDepuis(
          reponse.headers.value('content-disposition'),
          repli: 'attestation.pdf',
        ),
      );
    } on DioException catch (e) {
      throw _echec(e);
    }
  }

  Future<void> enregistrerModele(String type, String texte) async {
    try {
      await _client.put<dynamic>(
        '/api/attestation-templates/$type',
        data: {'body_text': texte},
      );
    } on DioException catch (e) {
      throw _echec(e);
    }
  }

  /// Enregistre la règle de signature d'un modèle (ATT-2) : seuil, signataires, qui signe chaque palier, appréciation.
  Future<void> enregistrerReglage(String type, ReglageSignature r) async {
    try {
      await _client.put<dynamic>(
        '/api/attestation-templates/$type',
        data: r.versServeur(),
      );
    } on DioException catch (e) {
      throw _echec(e);
    }
  }

  /// `Y-m-d` — une DATE pure. Un ISO complet décalerait d'un jour selon le
  /// fuseau du serveur.
  static String? _jour(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';

  static EchecAttestation _echec(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.receiveTimeout) {
      return const EchecAttestation(
        'Serveur injoignable. Cette action nécessite le réseau : réessayez une '
        'fois connecté.',
      );
    }

    // ⚠️ Avec `ResponseType.bytes`, le corps d'erreur arrive en OCTETS : sans le
    // décoder, le message du serveur (« votre rôle ne permet pas… ») serait perdu.
    final corps = _json(e.response?.data);
    final champs = <String, String>{};

    if (e.response?.statusCode == 422 && corps['errors'] is Map) {
      const correspondance = {
        'person_id': 'personne',
        'type': 'personne',
        'body_text': 'modele',
        'seuil_signature_mois': 'reglage',
      };
      (corps['errors'] as Map).forEach((cle, messages) {
        final champ = correspondance[cle];
        if (champ != null && messages is List && messages.isNotEmpty) {
          champs[champ] = messages.first.toString();
        }
      });
    }

    final serveur = corps['message'];

    return EchecAttestation(switch (e.response?.statusCode) {
      401 => 'Session expirée : reconnectez-vous.',
      403 =>
        serveur is String && serveur.isNotEmpty
            ? serveur
            : "Votre rôle ne permet pas cette action.",
      429 => 'Trop de demandes. Réessayez dans une minute.',
      _ => 'Action impossible.',
    }, champs: champs);
  }

  static Map<dynamic, dynamic> _json(Object? brut) {
    if (brut is Map) return brut;

    if (brut is List<int>) {
      try {
        final decode = jsonDecode(utf8.decode(brut));
        if (decode is Map) return decode;
      } on Object {
        // Corps qui n'est pas du JSON (page d'erreur HTML d'un proxy) : on s'en
        // tient au code d'état.
      }
    }

    return const {};
  }
}

/// Un signataire du modèle d'attestation (ATT-2).
///
/// ⚠️ LA POSITION EST CELLE DU SERVEUR : 1 = Directeur Général (le promoteur), 2 = Examinateur, 3 = Président du Jury.
/// L'ordre d'IMPRESSION, de gauche à droite, est Examinateur (2), Président du Jury (3), Directeur Général (1).
class SignataireModele {
  const SignataireModele({
    required this.position,
    this.titre = '',
    this.nom = '',
    this.fonction = '',
    this.court = false,
    this.long = false,
  });

  final int position;

  /// Intitulé souligné au-dessus du nom (« Examinateur ») ; vide pour le Directeur, qui n'en a pas.
  final String titre;
  final String nom;
  final String fonction;

  /// Signe-t-il les attestations du palier court (jusqu'au seuil) / long (au-delà) ?
  final bool court;
  final bool long;

  SignataireModele avec({String? titre, String? nom, String? fonction, bool? court, bool? long}) => SignataireModele(
    position: position,
    titre: titre ?? this.titre,
    nom: nom ?? this.nom,
    fonction: fonction ?? this.fonction,
    court: court ?? this.court,
    long: long ?? this.long,
  );
}

/// La règle de signature d'un modèle d'attestation (ATT-2) : seuil de durée, signataires, appréciation.
///
/// ⚠️⚠️ **QUI SIGNE EST UNE RÈGLE DU MODÈLE, SERVIE PAR LE SERVEUR** — jamais une constante du poste. Demande du client :
/// d'un mois à un an, SEUL le promoteur signe ; au-delà d'un an, TROIS personnes signent. `palier` et `requis` sont la
/// transposition de `AttestationService::palier()` / `signataires()` ; `test/attestations_parite_php_test.dart` les
/// exécute contre le vrai PHP. Le PDF, lui, vient du serveur et fait foi : ceci pilote le formulaire et l'aperçu.
class ReglageSignature {
  const ReglageSignature({
    this.seuilMois = 12,
    required this.signataires,
    this.appreciationText,
    this.appreciationImprimee = true,
  });

  /// Jusqu'à ce nombre de mois INCLUS : palier court ; au-delà : palier long.
  final int seuilMois;

  /// Clés 1 à 3.
  final Map<int, SignataireModele> signataires;

  /// Phrase d'appréciation par défaut ; `null` = la phrase standard du modèle officiel.
  final String? appreciationText;

  /// Faux : seule l'appréciation saisie à l'émission s'imprime.
  final bool appreciationImprimee;

  static const ordreImpression = [2, 3, 1];

  /// Les valeurs d'un modèle neuf du serveur (modèle fourni par le client, attestation du 24/10/2026).
  static const defaut = ReglageSignature(
    signataires: {
      1: SignataireModele(
        position: 1,
        nom: 'Hassimiyou O. OLOUKOUNLE',
        fonction: 'Directeur de la Ferme ÉCOLE OLOUWACHEGOUN',
        court: true,
        long: true,
      ),
      2: SignataireModele(
        position: 2,
        titre: 'Examinateur',
        nom: 'SOGNIGBE Gbédjinou Serge Bruno',
        fonction: "Chef Cellule Communale de l'ATDA Pôle 6(Plateau)",
        long: true,
      ),
      3: SignataireModele(
        position: 3,
        titre: 'Président du Jury',
        nom: 'Elisée Kocou HOUNKPONOU',
        fonction:
            'Président de la Fédération Nationale des Coopératives de Cuniculteurs Modernes et Professionnel du Bénin FN-CCPB',
        long: true,
      ),
    },
  );

  ReglageSignature avec({
    int? seuilMois,
    Map<int, SignataireModele>? signataires,
    String? appreciationText,
    bool effacerAppreciation = false,
    bool? appreciationImprimee,
  }) => ReglageSignature(
    seuilMois: seuilMois ?? this.seuilMois,
    signataires: signataires ?? this.signataires,
    appreciationText: effacerAppreciation ? null : (appreciationText ?? this.appreciationText),
    appreciationImprimee: appreciationImprimee ?? this.appreciationImprimee,
  );

  /// `court` ou `long` — voir `AttestationService::palier()`.
  ///
  /// Compté en mois CALENDAIRES depuis la date de début : du 15/10/2025 au 15/10/2026 = 12 mois exactement = palier court ;
  /// le 16/10/2026 = palier long. Sans date de fin, la durée court jusqu'à [aujourdhui] ; sans date de début, rien n'est
  /// mesurable : palier court (le promoteur seul).
  static String palier(DateTime? debut, DateTime? fin, int seuilMois, DateTime aujourdhui) {
    if (debut == null) return 'court';

    final d = DateTime(debut.year, debut.month, debut.day);
    final f = fin ?? aujourdhui;
    final limite = ajouterMois(d, seuilMois);

    return DateTime(f.year, f.month, f.day).isAfter(limite) ? 'long' : 'court';
  }

  /// `addMonthsNoOverflow` de Carbon : le 31 janvier + 1 mois = le 28 (ou 29) février.
  static DateTime ajouterMois(DateTime d, int n) {
    final total = d.year * 12 + (d.month - 1) + n;
    final annee = total ~/ 12;
    final mois = total % 12 + 1;
    final dernier = DateTime(annee, mois + 1, 0).day;

    return DateTime(annee, mois, math.min(d.day, dernier));
  }

  /// Les signataires à imprimer, de gauche à droite, pour cette durée — voir `AttestationService::signataires()`.
  /// [surcharges] : « sig1 » … « sig3 » → (`titre` | `nom` | `fonction`) saisis pour CETTE attestation (vides ignorés).
  List<SignataireModele> requis({
    required DateTime? debut,
    required DateTime? fin,
    required DateTime aujourdhui,
    Map<int, Map<String, String>> surcharges = const {},
  }) {
    final p = palier(debut, fin, seuilMois, aujourdhui);
    final liste = <SignataireModele>[];

    for (final position in ordreImpression) {
      final s = signataires[position];
      if (s == null || !(p == 'long' ? s.long : s.court)) continue;

      String choix(String champ, String modele) {
        final saisi = (surcharges[position]?[champ] ?? '').trim();
        return saisi.isNotEmpty ? saisi : modele.trim();
      }

      final titre = choix('titre', s.titre);
      final nom = choix('nom', s.nom);
      final fonction = choix('fonction', s.fonction);
      if (titre.isEmpty && nom.isEmpty && fonction.isEmpty) continue;

      liste.add(s.avec(titre: titre, nom: nom, fonction: fonction));
    }

    return liste;
  }

  /// Le corps de `PUT /api/attestation-templates/{type}` pour cette règle (le texte du modèle n'y est pas : il a son
  /// propre bouton, et le serveur ne touche pas à ce qui n'est pas envoyé).
  Map<String, Object?> versServeur() => {
    'seuil_signature_mois': seuilMois,
    'appreciation_text': (appreciationText ?? '').trim().isEmpty ? null : appreciationText,
    'appreciation_imprimee': appreciationImprimee,
    for (final n in [1, 2, 3]) ...{
      'sig${n}_titre': signataires[n]?.titre ?? '',
      'sig${n}_nom': signataires[n]?.nom ?? '',
      'sig${n}_fonction': signataires[n]?.fonction ?? '',
      'sig${n}_court': signataires[n]?.court ?? false,
      'sig${n}_long': signataires[n]?.long ?? false,
    },
  };
}

/// Une personne proposée au sélecteur, avec ce que la page préremplit.
class PersonneAttestation {
  const PersonneAttestation({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.poste,
    required this.etablissement,
    required this.debut,
    required this.fin,
    this.birthDate,
    this.birthPlace,
    this.civilite = 'M.',
  });

  final String id;
  final String nom;
  final String prenom;

  /// Poste d'un employé ; `null` pour un stagiaire.
  final String? poste;

  /// Établissement d'un stagiaire ; `null` pour un employé.
  final String? etablissement;

  /// Employé : date d'embauche. Stagiaire : début de stage.
  final DateTime? debut;

  /// Employé : jamais (un contrat en cours n'a pas de fin). Stagiaire : fin.
  final DateTime? fin;

  /// Date de naissance du stagiaire (ATT-1).
  final DateTime? birthDate;

  /// Lieu de naissance du stagiaire (ATT-1).
  final String? birthPlace;

  /// Civilité (M. / Mme) — conditionne l'accord grammatical dans l'attestation.
  final String civilite;

  /// « AGOSSOU Jean » — l'ordre de la page web (`last_name first_name`).
  String get libelle => '$nom $prenom';
}

/// Lectures et règles de `prototype_html/rh-attestations.html`.
///
/// ⚠️⚠️ **L'APERÇU COMPOSE LE TEXTE COMME LE SERVEUR** (`AttestationService`) :
/// mêmes balises, mêmes remplacements, « ce jour » quand il n'y a pas de date de
/// fin. Le PDF, lui, vient du serveur et fait foi : l'aperçu n'est qu'un
/// confort, jamais le document.
///
/// ⚠️ **LE COMPTEUR « ATTESTATIONS ÉMISES » EST CELUI DU SERVEUR.** Un décompte
/// de ses lignes d'audit sur tout l'historique ; le poste ne détient que les cent
/// dernières lignes d'audit de la ferme et ne peut pas le recalculer.
class AttestationsRepository {
  AttestationsRepository({required this.database, this.client});

  final AppDatabase database;

  /// `null` : aucune session — génération et enregistrement répondent par une
  /// phrase, sans rien tenter.
  final ClientAttestations? client;

  static const types = ['employe', 'stagiaire'];

  static const contrats = ['CDI', 'CDD', 'Stage conventionné'];

  Future<List<PersonneAttestation>> personnes(String type) async {
    if (type == 'employe') {
      final lignes = await database.select(database.employees).get();
      return [
        for (final e
            in lignes..sort((a, b) => a.lastName.compareTo(b.lastName)))
          PersonneAttestation(
            id: e.id,
            nom: e.lastName,
            prenom: e.firstName,
            poste: e.position,
            etablissement: null,
            debut: e.hireDate,
            fin: null,
          ),
      ];
    }

    final lignes = await database.select(database.internships).get();
    return [
      for (final s in lignes..sort((a, b) => a.lastName.compareTo(b.lastName)))
        PersonneAttestation(
          id: s.id,
          nom: s.lastName,
          prenom: s.firstName,
          poste: null,
          etablissement: s.school,
          debut: s.startDate,
          fin: s.endDate,
          birthDate: s.birthDate,
          birthPlace: s.birthPlace,
          civilite: s.civilite,
        ),
    ];
  }

  /// Texte du modèle, `null` tant que le poste ne l'a pas reçu.
  Future<String?> modele(String type) async {
    final ligne = await (database.select(
      database.attestationTemplates,
    )..where((m) => m.type.equals(type))).getSingleOrNull();
    return ligne?.bodyText;
  }

  /// La règle de signature d'un modèle (ATT-2), `null` tant que le poste ne l'a pas reçue.
  Future<ReglageSignature?> reglage(String type) async {
    final m = await (database.select(
      database.attestationTemplates,
    )..where((t) => t.type.equals(type))).getSingleOrNull();
    if (m == null) return null;

    return ReglageSignature(
      seuilMois: m.seuilSignatureMois,
      appreciationText: m.appreciationText,
      appreciationImprimee: m.appreciationImprimee,
      signataires: {
        1: SignataireModele(position: 1, titre: m.sig1Titre ?? '', nom: m.sig1Nom ?? '', fonction: m.sig1Fonction ?? '', court: m.sig1Court, long: m.sig1Long),
        2: SignataireModele(position: 2, titre: m.sig2Titre ?? '', nom: m.sig2Nom ?? '', fonction: m.sig2Fonction ?? '', court: m.sig2Court, long: m.sig2Long),
        3: SignataireModele(position: 3, titre: m.sig3Titre ?? '', nom: m.sig3Nom ?? '', fonction: m.sig3Fonction ?? '', court: m.sig3Court, long: m.sig3Long),
      },
    );
  }

  /// Enregistre la règle de signature : le serveur d'abord, la base locale ensuite (comme [enregistrerModele] : une règle
  /// affichée « enregistrée » avant que le serveur l'ait prise ferait produire des attestations avec l'ancienne).
  Future<void> enregistrerReglage(String type, ReglageSignature r) async {
    await _client().enregistrerReglage(type, r);

    final sig = r.signataires;
    await (database.update(database.attestationTemplates)..where((m) => m.type.equals(type))).write(
      AttestationTemplatesCompanion(
        seuilSignatureMois: Value(r.seuilMois),
        appreciationText: Value((r.appreciationText ?? '').trim().isEmpty ? null : r.appreciationText),
        appreciationImprimee: Value(r.appreciationImprimee),
        sig1Titre: Value(sig[1]?.titre ?? ''),
        sig1Nom: Value(sig[1]?.nom ?? ''),
        sig1Fonction: Value(sig[1]?.fonction ?? ''),
        sig2Titre: Value(sig[2]?.titre ?? ''),
        sig2Nom: Value(sig[2]?.nom ?? ''),
        sig2Fonction: Value(sig[2]?.fonction ?? ''),
        sig3Titre: Value(sig[3]?.titre ?? ''),
        sig3Nom: Value(sig[3]?.nom ?? ''),
        sig3Fonction: Value(sig[3]?.fonction ?? ''),
        sig1Court: Value(sig[1]?.court ?? false),
        sig2Court: Value(sig[2]?.court ?? false),
        sig3Court: Value(sig[3]?.court ?? false),
        sig1Long: Value(sig[1]?.long ?? false),
        sig2Long: Value(sig[2]?.long ?? false),
        sig3Long: Value(sig[3]?.long ?? false),
      ),
    );
  }

  /// Nombre d'attestations émises d'un type, `null` si le poste ne l'a jamais
  /// reçu — ⚠️ jamais zéro : « 0 » dirait qu'aucune n'a été délivrée.
  Future<int?> emises(String type) async {
    final ligne =
        await (database.select(database.appSettings)..where(
              (s) => s.key.equals(SyncEngine.cleAttestationsEmises(type)),
            ))
            .getSingleOrNull();
    return ligne == null ? null : int.tryParse(ligne.value);
  }

  /// Aperçu : le modèle, balises remplacées, exactement comme le serveur.
  ///
  /// ⚠️ `[DATE_FIN]` vaut « ce jour » sans date de fin : un contrat en cours n'a
  /// pas de fin, et « du 01/03/2024 au  » serait une phrase brisée sur un
  /// document officiel.
  static String apercu({
    required String modele,
    required String type,
    required PersonneAttestation personne,
    required String contrat,
    DateTime? debut,
    DateTime? fin,
    DateTime? birthDate,
    String birthPlace = '',
    String civilite = 'M.',
    DateTime? aujourdhui,
  }) => sansMarques(
    remplacer(
      modele: modele,
      type: type,
      personne: personne,
      contrat: contrat,
      debut: debut,
      fin: fin,
      birthDate: birthDate,
      birthPlace: birthPlace,
      civilite: civilite,
      aujourdhui: aujourdhui,
    ),
  );

  /// Phrase standard d'appréciation du modèle « stagiaire » (modèle officiel) — `AttestationTemplate::APPRECIATION_STAGIAIRE`.
  static const appreciationStagiaire =
      'Au cours de sa formation, [CIVILITE_LONGUE] **[NOM]** s’est distingué[ACCORD_E] par sa ponctualité, '
      'son esprit d’initiative, sa capacité d’adaptation et sa motivation à apprendre.';

  /// La phrase d'appréciation du document : la saisie de l'émetteur, sinon celle du modèle (`appreciationText`, ou la
  /// phrase standard d'une formation) ; `null` = rien à imprimer — `AttestationService::appreciation()`. Sans les `**`.
  static String? appreciation({
    required String type,
    required PersonneAttestation personne,
    required String saisie,
    required ReglageSignature? reglage,
    DateTime? debut,
    DateTime? fin,
    String civilite = 'M.',
    DateTime? aujourdhui,
  }) {
    if (saisie.trim().isNotEmpty) return saisie.trim();
    if (reglage != null && !reglage.appreciationImprimee) return null;

    final modele = reglage?.appreciationText ?? (type == 'stagiaire' ? appreciationStagiaire : '');
    if (modele.trim().isEmpty) return null;

    return sansMarques(
      remplacer(
        modele: modele,
        type: type,
        personne: personne,
        contrat: '',
        debut: debut,
        fin: fin,
        civilite: civilite,
        aujourdhui: aujourdhui,
      ),
    );
  }

  /// Retire les marques `**gras**` du texte du modèle (l'aperçu les affiche sans astérisques ; le PDF les imprime en gras).
  static String sansMarques(String texte) => texte.replaceAll('**', '');

  /// Le texte du modèle, balises remplacées, marques `**gras**` CONSERVÉES — `AttestationService::remplacer()`.
  static String remplacer({
    required String modele,
    required String type,
    required PersonneAttestation personne,
    required String contrat,
    DateTime? debut,
    DateTime? fin,
    DateTime? birthDate,
    String birthPlace = '',
    String civilite = 'M.',
    DateTime? aujourdhui,
  }) {
    final accordE = civilite == 'Mme' ? 'e' : '';
    final civiliteLongue = civilite == 'Mme' ? 'Madame' : 'Monsieur';
    final titreNom = '$civiliteLongue ${personne.libelle}';
    final commun = <String, String>{
      '[NOM]': personne.libelle,
      '[CIVILITE]': civilite,
      '[TITRE_NOM]': titreNom,
      '[CIVILITE_LONGUE]': civiliteLongue,
      '[ACCORD_E]': accordE,
      '[DATE_DEBUT]': _date(debut) ?? '',
      '[DATE_FIN]': _date(fin) ?? 'ce jour',
      '[DATE_DEBUT_LONGUE]': debut == null ? '' : dateLongue(debut),
      '[DATE_FIN_LONGUE]': fin == null ? 'ce jour' : dateLongue(fin),
      '[DUREE]': formatDuree(debut, fin, aujourdhui: aujourdhui),
      '[DE_DUREE]': deDuree(debut, fin, aujourdhui: aujourdhui),
    };
    final propres = type == 'employe'
        ? {'[POSTE]': personne.poste ?? '', '[CONTRAT]': contrat}
        : {
            '[SPECIALITE]': personne.etablissement ?? '',
            '[ETABLISSEMENT]': personne.etablissement ?? '',
            '[DATE_NAISSANCE]': _date(birthDate) ?? '',
            '[DATE_NAISSANCE_LONGUE]': birthDate == null ? '' : dateLongue(birthDate),
            '[LIEU_NAISSANCE]': birthPlace,
          };

    // ⚠️ UN SEUL PASSAGE, comme `strtr` du serveur : une valeur qui ressemblerait à une balise n'est pas remplacée à son tour.
    final toutes = {...commun, ...propres};
    final motif = RegExp(toutes.keys.map(RegExp.escape).join('|'));

    return modele.replaceAllMapped(motif, (m) => toutes[m.group(0)]!);
  }

  static const _mois = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  /// « 15 octobre 2025 » — `AttestationService::dateLongue()`.
  static String dateLongue(DateTime d) => '${d.day} ${_mois[d.month - 1]} ${d.year}';

  /// Durée entre deux dates en mois PLEINS, dite en toutes lettres : « six (06) mois », « un (01) an et trois (03) mois ».
  /// ⚠️ « an » (jamais « ans ») pour 1 an exactement. Vide sous un mois — `AttestationService::formatDuree()`.
  static String formatDuree(DateTime? debut, DateTime? fin, {DateTime? aujourdhui}) {
    if (debut == null) return '';

    final d = DateTime(debut.year, debut.month, debut.day);
    final f0 = fin ?? aujourdhui ?? DateTime.now();
    final f = DateTime(f0.year, f0.month, f0.day);

    var total = (f.year - d.year) * 12 + (f.month - d.month);
    if (f.day < d.day) total -= 1;
    if (total <= 0) return '';

    final ans = total ~/ 12;
    final mois = total % 12;
    final parties = <String>[];

    if (ans > 0) {
      parties.add('${_motNombre(ans)} (${ans.toString().padLeft(2, '0')}) ${ans == 1 ? 'an' : 'ans'}');
    }
    if (mois > 0) {
      parties.add('${_motNombre(mois)} (${mois.toString().padLeft(2, '0')}) mois');
    }

    return parties.join(' et ');
  }

  /// « d'un (01) an » / « de six (06) mois », avec l'espace qui l'attache au mot précédent ; vide sans durée.
  static String deDuree(DateTime? debut, DateTime? fin, {DateTime? aujourdhui}) {
    final duree = formatDuree(debut, fin, aujourdhui: aujourdhui);
    if (duree.isEmpty) return '';

    return duree.startsWith('un ') ? " d'$duree" : ' de $duree';
  }

  static String _motNombre(int n) =>
      const {
        1: 'un', 2: 'deux', 3: 'trois', 4: 'quatre', 5: 'cinq', 6: 'six', 7: 'sept', 8: 'huit', 9: 'neuf',
        10: 'dix', 11: 'onze', 12: 'douze', 13: 'treize', 14: 'quatorze', 15: 'quinze', 16: 'seize',
        17: 'dix-sept', 18: 'dix-huit', 19: 'dix-neuf', 20: 'vingt', 21: 'vingt et un', 22: 'vingt-deux',
        23: 'vingt-trois', 24: 'vingt-quatre',
      }[n] ??
      '$n';

  static String? _date(DateTime? d) => d == null
      ? null
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<PdfAttestation> generer({
    required String type,
    required PersonneAttestation personne,
    required String contrat,
    DateTime? debut,
    DateTime? fin,
    String note = '',
    List<String> domaines = const [],
    String appreciation = '',
    DateTime? birthDate,
    String birthPlace = '',
    String civilite = 'M.',
    Map<String, String> signataires = const {},
  }) async => _client().generer(
    type: type,
    personneId: personne.id,
    contrat: contrat,
    debut: debut,
    fin: fin,
    note: note,
    domaines: domaines,
    appreciation: appreciation,
    birthDate: birthDate,
    birthPlace: birthPlace,
    civilite: civilite,
    signataires: signataires,
  );

  /// Enregistre un modèle : le serveur d'abord, la base locale ensuite.
  ///
  /// ⚠️ LA LIGNE LOCALE N'EST MODIFIÉE QU'APRÈS LA CONFIRMATION DU SERVEUR : le
  /// modèle fait foi sur un document officiel, l'afficher « enregistré » avant
  /// que le serveur l'ait pris ferait produire des attestations avec l'ancien
  /// texte sans que personne le sache.
  Future<void> enregistrerModele(String type, String texte) async {
    await _client().enregistrerModele(type, texte);

    await (database.update(database.attestationTemplates)
          ..where((m) => m.type.equals(type)))
        .write(AttestationTemplatesCompanion(bodyText: Value(texte)));
  }

  ClientAttestations _client() =>
      client ??
      (throw const EchecAttestation(
        'Aucune session ouverte : connectez-vous.',
      ));
}
