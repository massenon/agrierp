import 'dart:convert';

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
          if (type == 'stagiaire' && domaines.isNotEmpty) 'domaines': domaines,
          if (type == 'stagiaire' && appreciation.trim().isNotEmpty)
            'appreciation': appreciation,
          if (type == 'stagiaire' && birthDate != null) 'birth_date': _jour(birthDate),
          if (type == 'stagiaire' && birthPlace.trim().isNotEmpty)
            'birth_place': birthPlace,
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
  }) {
    final remplacements = type == 'employe'
        ? {
            '[NOM]': personne.libelle,
            '[POSTE]': personne.poste ?? '',
            '[CONTRAT]': contrat,
            '[DATE_DEBUT]': _date(debut) ?? '',
            '[DATE_FIN]': _date(fin) ?? 'ce jour',
          }
        : {
            '[NOM]': personne.libelle,
            '[SPECIALITE]': personne.etablissement ?? '',
            '[ETABLISSEMENT]': personne.etablissement ?? '',
            '[DATE_DEBUT]': _date(debut) ?? '',
            '[DATE_FIN]': _date(fin) ?? 'ce jour',
            '[DATE_NAISSANCE]': _date(birthDate) ?? '',
            '[LIEU_NAISSANCE]': birthPlace,
          };

    var texte = modele;
    remplacements.forEach((balise, valeur) {
      texte = texte.replaceAll(balise, valeur);
    });
    return texte;
  }

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
