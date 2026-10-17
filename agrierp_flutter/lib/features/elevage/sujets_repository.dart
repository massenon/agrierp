import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/export/pdf_recu.dart';

/// Échec d'une opération sur la fiche d'un sujet, avec une phrase lisible.
class EchecSujet implements Exception {
  const EchecSujet(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Export PDF de la fiche, contre `GET /api/animals/{id}/pdf` (ticket Laravel
/// 15.14).
///
/// ⚠️ **LE PDF EST PRODUIT PAR LE SERVEUR** — l'en-tête officiel de la ferme n'a
/// pas à être recopié sur chaque machine — et exige donc le réseau, ce que
/// l'écran dit au lieu de produire un document approximatif.
class ClientSujets {
  ClientSujets(this._client);

  final Dio _client;

  Future<PdfRecu> pdf(String sujetId) async {
    try {
      final reponse = await _client.get<List<int>>(
        '/api/animals/$sujetId/pdf',
        options: Options(responseType: ResponseType.bytes),
      );
      final octets = Uint8List.fromList(reponse.data ?? const <int>[]);
      if (octets.isEmpty) {
        throw const EchecSujet('Le serveur a renvoyé un document vide.');
      }
      return PdfRecu(
        octets: octets,
        fichier: PdfRecu.nomDepuis(
          reponse.headers.value('content-disposition'),
          repli: 'sujet.pdf',
        ),
      );
    } on DioException catch (e) {
      throw _echec(e);
    }
  }

  static EchecSujet _echec(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.receiveTimeout) {
      return const EchecSujet(
        'Serveur injoignable. Cet export nécessite le réseau : réessayez une '
        'fois connecté.',
      );
    }

    // ⚠️ `ResponseType.bytes` : le corps d'erreur arrive en octets — sans le
    // décoder, la phrase du serveur serait perdue.
    String? serveur;
    final brut = e.response?.data;
    try {
      final corps = brut is List<int> ? jsonDecode(utf8.decode(brut)) : brut;
      if (corps is Map && corps['message'] is String) {
        serveur = corps['message'] as String;
      }
    } on Object {
      // Corps non JSON : on s'en tient au code d'état.
    }

    return EchecSujet(switch (e.response?.statusCode) {
      401 => 'Session expirée : reconnectez-vous.',
      403 => serveur ?? "Votre rôle ne permet pas d'exporter une fiche sujet.",
      404 => "Ce sujet n'existe plus sur le serveur. Synchronisez.",
      429 => 'Trop de demandes. Réessayez dans une minute.',
      _ => 'Export impossible.',
    });
  }
}

/// Une saillie du sujet, vue comme la page web la montre.
class EvenementSujet {
  const EvenementSujet({
    required this.saillie,
    required this.role,
    required this.miseBas,
    required this.vivants,
    required this.morts,
    required this.statut,
  });

  final DateTime? saillie;

  /// `Mère` ou `Géniteur`.
  final String role;
  final DateTime? miseBas;
  final int? vivants;
  final int? morts;

  /// « En cours », « Termine »… — `ucfirst(str_replace('_', ' ', status))`.
  final String statut;
}

class SoinSujet {
  const SoinSujet({
    required this.date,
    required this.action,
    required this.produit,
    required this.dose,
  });

  final DateTime date;
  final String action;
  final String? produit;
  final String? dose;
}

class MouvementSujet {
  const MouvementSujet({
    required this.date,
    required this.libelle,
    required this.detail,
  });

  final DateTime? date;
  final String libelle;
  final String detail;
}

class LigneHistorique {
  const LigneHistorique({
    required this.date,
    required this.type,
    required this.libelle,
  });

  final DateTime? date;
  final String type;
  final String libelle;
}

/// La fiche complète d'un sujet.
class FicheSujet {
  const FicheSujet({
    required this.sujet,
    required this.ageEnMois,
    required this.reproduction,
    required this.soins,
    required this.mouvements,
    required this.historique,
  });

  final Sujet sujet;

  /// `null` sans date de naissance.
  final int? ageEnMois;
  final List<EvenementSujet> reproduction;
  final List<SoinSujet> soins;
  final List<MouvementSujet> mouvements;
  final List<LigneHistorique> historique;

  bool get present => sujet.status == 'actif';

  /// « Actif — Reproducteur » ou, pour un sujet sorti, son statut (« Vendu »).
  String get badge => present
      ? 'Actif — ${SujetsRepository.majuscule(sujet.category)}'
      : SujetsRepository.majuscule(sujet.status);

  String get sexe => sujet.sex == 'F' ? 'Femelle' : 'Mâle';
}

/// Lectures de `prototype_html/animal-details.html`.
///
/// ⚠️⚠️ **RIEN N'EST FABRIQUÉ** — c'est la règle de la page web (ticket 14.16),
/// reprise à la lettre :
///  * les **mouvements** sont l'entrée du sujet et, s'il est sorti, sa sortie.
///    Aucun historique de cage n'est modélisé : en inventer un afficherait des
///    lignes que personne n'a jamais saisies ;
///  * les **soins** sont ceux de la BANDE du sujet. La prophylaxie est administrée
///    par bande sur cette ferme ; ces soins concernent le sujet sans être des
///    traitements individuels, et l'écran le dit ;
///  * la **reproduction** est retrouvée par correspondance sur l'identifiant, dans
///    les références mère / géniteur déjà saisies.
class SujetsRepository {
  SujetsRepository({required this.database, this.client});

  final AppDatabase database;

  /// `null` : aucune session — l'export répond par une phrase.
  final ClientSujets? client;

  /// `identifiant → id` des sujets connus : sert à rendre cliquable une référence
  /// de saillie quand un sujet porte ce nom.
  Future<Map<String, String>> identifiants() async {
    final lignes = await database.select(database.animals).get();
    return {for (final s in lignes) s.identifier: s.id};
  }

  Future<FicheSujet?> charger(String id, {DateTime? maintenant}) async {
    final sujet = await (database.select(
      database.animals,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (sujet == null) return null;

    // ── Reproduction : mère OU géniteur, par correspondance de référence ──
    final evenements =
        await (database.select(database.livestockReproductionEvents)..where(
              (e) =>
                  e.motherRef.equals(sujet.identifier) |
                  e.sireRef.equals(sujet.identifier),
            ))
            .get();
    evenements.sort(
      (a, b) => (b.saillieDate ?? DateTime(1970)).compareTo(
        a.saillieDate ?? DateTime(1970),
      ),
    );

    final reproduction = [
      for (final e in evenements)
        EvenementSujet(
          saillie: e.saillieDate,
          role: e.motherRef == sujet.identifier ? 'Mère' : 'Géniteur',
          miseBas: e.miseBasDateActual,
          vivants: e.nesVivants,
          morts: e.nesMorts,
          statut: majuscule(e.status.replaceAll('_', ' ')),
        ),
    ];

    // ── Soins : ceux de la BANDE ──────────────────────────────────────────
    final lotId = sujet.lotId;
    final soinsBruts = lotId == null
        ? <VeterinaryRecord>[]
        : await (database.select(database.veterinaryRecords)
                ..where((v) => v.lotId.equals(lotId))
                ..orderBy([
                  (v) => OrderingTerm(
                    expression: v.recordDate,
                    mode: OrderingMode.desc,
                  ),
                ]))
              .get();
    final soins = [
      for (final v in soinsBruts)
        SoinSujet(
          date: v.recordDate,
          action: v.actionType,
          produit: v.productUsed,
          dose: v.dose,
        ),
    ];

    // ── Mouvements : l'entrée, et la sortie si elle a eu lieu ─────────────
    final mouvements = [
      MouvementSujet(
        date: sujet.entryDate,
        libelle: 'Entrée en élevage',
        detail: _ou(sujet.origin, 'Origine non précisée'),
      ),
      if (sujet.exitDate != null)
        MouvementSujet(
          date: sujet.exitDate,
          libelle: 'Sortie — ${sujet.status}',
          detail: _ou(sujet.exitReason, 'Motif non précisé'),
        ),
    ];

    // ── Historique consolidé, du plus récent au plus ancien ───────────────
    final historique = <LigneHistorique>[
      for (final m in mouvements)
        LigneHistorique(
          date: m.date,
          type: 'Mouvement',
          libelle: '${m.libelle} — ${m.detail}',
        ),
      for (final e in reproduction)
        LigneHistorique(
          date: e.saillie,
          type: 'Reproduction',
          libelle:
              'Saillie${e.miseBas != null ? ' — mise bas le ${_date(e.miseBas)}' : ' (en cours)'}',
        ),
      for (final s in soins)
        LigneHistorique(
          date: s.date,
          type: 'Soin (bande)',
          libelle:
              '${s.action}${(s.produit ?? '').isNotEmpty ? ' — ${s.produit}' : ''}',
        ),
    ]..sort((a, b) => (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970)));

    return FicheSujet(
      sujet: sujet,
      ageEnMois: sujet.birthDate == null
          ? null
          : moisEntre(sujet.birthDate!, maintenant ?? DateTime.now()),
      reproduction: reproduction,
      soins: soins,
      mouvements: mouvements,
      historique: historique,
    );
  }

  /// Export PDF : le serveur le produit, le poste le reçoit.
  Future<PdfRecu> exporterPdf(String id) async =>
      (client ??
              (throw const EchecSujet(
                'Aucune session ouverte : connectez-vous.',
              )))
          .pdf(id);

  /// Mois ENTIERS écoulés entre deux dates — `Carbon::diffInMonths` : un sujet né
  /// le 12 février a 5 mois le 12 juillet, mais 4 le 11.
  static int moisEntre(DateTime debut, DateTime fin) {
    var mois = (fin.year - debut.year) * 12 + fin.month - debut.month;
    if (fin.day < debut.day) mois--;
    return mois < 0 ? 0 : mois;
  }

  static String majuscule(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static String _ou(String? valeur, String parDefaut) =>
      (valeur == null || valeur.isEmpty) ? parDefaut : valeur;

  static String? _date(DateTime? d) => d == null
      ? null
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
