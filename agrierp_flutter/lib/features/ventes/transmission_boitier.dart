import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/database/app_database.dart';
import '../../core/mecef/facture_mecef.dart';
import '../../core/mecef/marque_boitier.dart';
import '../../core/mecef/passerelle_boitier.dart';
import 'caisse_repository.dart';
import 'facturation_repository.dart';

/// MECEF-2 — issue d'une demande de transmission d'UNE vente au boîtier.
enum IssueTransmission {
  /// Le boîtier a certifié la facture (qr_code non vide) : elle est « Normalisée », elle repart au serveur.
  transmise,

  /// Déjà normalisée, simple, annulée, marquée « incertaine » ou transmise en même temps : RIEN n'est appelé.
  nonConcernee,

  /// Boîtier injoignable : la facture reste « En attente » et sera reprise à son retour. Pas une erreur.
  enAttente,

  /// Le boîtier a refusé : « Refusée » avec son motif ; reprise à la main.
  refusee,

  /// La réponse n'est pas revenue : le boîtier a PEUT-ÊTRE certifié. Jamais de reprise automatique.
  incertaine,
}

class ResultatTransmission {
  const ResultatTransmission(this.issue, this.message);

  final IssueTransmission issue;
  final String message;
}

/// MECEF-2 — LA TRANSMISSION DES FACTURES NORMALISÉES PAR LE POSTE, quand le serveur est en mode `boitier`.
///
/// ⚠️ NON VÉRIFIÉ AVEC UN VRAI BOÎTIER : tout est éprouvé contre un faux pilote (`test/boitier_faux_pilote.dart`).
///
/// Règles (doctrine : le poste reprend la logique du serveur, `FacturationMecefService`) :
///  - la charge est celle du serveur, portée en Dart (`FactureMecef`, parité exécutée avec le PHP) ;
///  - AUCUN jeton : le boîtier n'en a pas, e-MECeF n'a pas cours ici ;
///  - UNE SEULE transmission par vente : la vente est réservée (marque posée AVANT l'appel, dans une transaction), un verrou
///    mémoire empêche deux appels simultanés, une vente « Normalisée » n'est jamais renvoyée, une vente marquée « incertaine »
///    n'est jamais reprise seule ;
///  - une facture normalisée est VERROUILLÉE : une correction passe par un avoir (inchangé) ;
///  - boîtier injoignable : « En attente », reprise automatique par [reprendre] (au retour du boîtier, après chaque synchronisation,
///    bouton de l'écran).
class TransmissionBoitier extends ChangeNotifier {
  TransmissionBoitier({required CaisseRepository caisse, required AppDatabase database, required PasserelleBoitier passerelle})
    :
      // ignore: prefer_initializing_formals
      _caisse = caisse,
      // ignore: prefer_initializing_formals
      _db = database,
      // ignore: prefer_initializing_formals
      _passerelle = passerelle;

  final CaisseRepository _caisse;
  final AppDatabase _db;
  final PasserelleBoitier _passerelle;

  /// Le service du poste en cours (posé par `main.dart`), lu par les écrans (indicateur du boîtier). `null` : navigateur, tests,
  /// ou poste sans boîtier — les écrans n'affichent alors rien.
  static TransmissionBoitier? courant;

  // Verrou mémoire : défense en plus de la réservation en base (la marque posée dans la transaction est la garantie première).
  final Set<String> _enCours = {};

  /// Dernier état connu du boîtier (`/check`), pour l'indicateur ; `null` tant qu'il n'a pas été vérifié.
  EtatBoitier? etat;

  /// Dernier résultat d'une transmission (bandeau de la caisse).
  ResultatTransmission? dernier;

  PasserelleBoitier get passerelle => _passerelle;

  /// Le poste transmet-il ? Mode `boitier` servi par le tirage ET module actif.
  Future<bool> actif() async {
    final f = FacturationRepository(database: _db, mecefParDefaut: false);
    return await f.mecefMode() == 'boitier' && await f.mecefActif();
  }

  /// `GET /check` : met l'indicateur à jour. Ne lève jamais.
  Future<EtatBoitier> verifier() async {
    final e = await _passerelle.verifier();
    etat = e;
    notifyListeners();
    return e;
  }

  /// Transmet UNE vente. [apresVerification] : l'utilisateur a vérifié sur l'appareil que la facture marquée « incertaine » n'a
  /// PAS été certifiée (sinon la relancer la certifierait deux fois).
  Future<ResultatTransmission> transmettre(String venteId, {bool apresVerification = false}) async {
    if (!await actif()) {
      return const ResultatTransmission(IssueTransmission.nonConcernee, "Le mode boîtier n'est pas actif.");
    }
    if (!_enCours.add(venteId)) {
      return const ResultatTransmission(IssueTransmission.nonConcernee, 'Cette facture est déjà en cours de transmission.');
    }
    try {
      final r = await _transmettre(venteId, apresVerification);
      dernier = r;
      notifyListeners();
      return r;
    } finally {
      _enCours.remove(venteId);
    }
  }

  Future<ResultatTransmission> _transmettre(String venteId, bool apresVerification) async {
    // Lu directement (clés posées par le tirage) : ne pas importer le dépôt des réglages, qui élargirait le périmètre de tirage des écrans de vente.
    final cles = {
      for (final l in await (_db.select(_db.appSettings)..where((r) => r.key.isIn(['mecef.operateur_id', 'mecef.operateur_nom']))).get()) l.key: l.value,
    };
    final reglage = (operateurId: cles['mecef.operateur_id'] ?? '', operateurNom: cles['mecef.operateur_nom'] ?? '');
    if (reglage.operateurId.trim().isEmpty || reglage.operateurNom.trim().isEmpty) {
      return const ResultatTransmission(
        IssueTransmission.nonConcernee,
        "Renseignez l'identifiant et le nom de l'opérateur dans Paramètres, Facturation normalisée.",
      );
    }

    final charge = await _charge(venteId, reglage.operateurId, reglage.operateurNom);
    if (charge is ResultatTransmission) return charge;

    // La marque est posée AVANT l'appel : un arrêt de l'application, ou une réponse perdue, laisse la vente « incertaine ».
    final reservee = await _caisse.reserverTransmissionBoitier(venteId, apresVerification: apresVerification);
    if (reservee == null) {
      return const ResultatTransmission(IssueTransmission.nonConcernee, 'Rien à transmettre pour cette facture (déjà normalisée, simple, annulée ou à vérifier sur le boîtier).');
    }

    final issue = await _passerelle.facturer(charge as Map<String, Object?>);
    switch (issue) {
      case FactureCertifiee(:final qrCode):
        final qr = QrBoitier.lire(qrCode);
        await _caisse.noterFactureCertifiee(venteId, qr: qrCode, code: qr.code, nim: qr.nim, instant: qr.instant);
        return const ResultatTransmission(IssueTransmission.transmise, 'Facture normalisée par le boîtier.');
      case FactureRefusee(:final motif):
        await _caisse.noterRefusBoitier(venteId, motif);
        return ResultatTransmission(IssueTransmission.refusee, motif);
      case BoitierInjoignable():
        await _caisse.relacherTransmissionBoitier(venteId);
        return const ResultatTransmission(IssueTransmission.enAttente, messageBoitierInjoignable);
      case FactureIncertaine(:final motif):
        // La marque reste : jamais de reprise automatique.
        return ResultatTransmission(IssueTransmission.incertaine, motif);
    }
  }

  /// La charge du boîtier d'une vente locale, ou le résultat qui explique pourquoi elle ne part pas.
  Future<Object> _charge(String venteId, String operateurId, String operateurNom) async {
    final v = await (_db.select(_db.sales)..where((t) => t.id.equals(venteId))).getSingleOrNull();
    if (v == null) return const ResultatTransmission(IssueTransmission.nonConcernee, 'Vente introuvable.');

    final lignes = await (_db.select(_db.saleLines)..where((t) => t.saleId.equals(venteId))).get();
    if (lignes.isEmpty) {
      // Vente tirée du serveur dont les lignes ne sont pas encore arrivées : on attend, on ne déclare pas une facture vide.
      return const ResultatTransmission(IssueTransmission.enAttente, 'Lignes de la vente non encore reçues : synchronisez le poste.');
    }
    final produits = {
      for (final p in await (_db.select(_db.products)..where((t) => t.id.isIn([for (final l in lignes) l.productId]))).get()) p.id: p,
    };
    final entreprise = await (_db.select(_db.companySettings)..where((c) => c.id.equals('unique'))).getSingleOrNull();
    var nomClient = v.customerName;
    if ((nomClient ?? '').isEmpty && v.customerId != null) {
      nomClient = (await (_db.select(_db.customers)..where((c) => c.id.equals(v.customerId!))).getSingleOrNull())?.name;
    }

    final vente = VenteMecef(
      lignes: [
        for (final l in lignes)
          LigneMecef(
            nom: produits[l.productId]?.name ?? 'Article',
            unite: produits[l.productId]?.unit ?? '',
            quantite: l.qty,
            montant: l.manualTotalAmount,
            tauxProduit: produits[l.productId]?.tvaRate ?? 0,
          ),
      ],
      remise: v.discount,
      total: v.total,
      modePaiement: v.paymentMode,
      livraisonIncluse: v.deliveryInTotal,
      fraisLivraison: v.deliveryFee,
      clientNomFacture: v.clientNomFacture,
      nomClient: nomClient,
      clientIfu: v.clientIfu,
      aibTaux: v.aibTaux,
    );
    try {
      final enLigne = FactureMecef.pourVente(
        vente,
        emetteur: {'ifu': entreprise?.ifu ?? '', 'operateur_id': operateurId, 'operateur_nom': operateurNom},
        tvaActive: entreprise?.tvaEnabled ?? false,
      );
      return FactureMecef.versBoitier(enLigne, vendeurId: operateurId, vendeurNom: operateurNom);
    } on FactureMecefInvalide catch (e) {
      // Charge refusée par le constructeur (mêmes motifs qu'au serveur) : état « Refusée », rien n'est envoyé au boîtier.
      await _caisse.noterRefusBoitier(venteId, e.message);
      return ResultatTransmission(IssueTransmission.refusee, e.message);
    }
  }

  bool _reprise = false;

  /// Reprend les factures « En attente » (jamais les refusées ni les marquées « incertaines »), dans l'ordre des ventes. S'arrête
  /// dès que le boîtier est injoignable. Rend le nombre de factures normalisées. Un seul passage à la fois.
  Future<int> reprendre() async {
    if (_reprise || !await actif()) return 0;
    _reprise = true;
    try {
      final aTransmettre = await _caisse.ventesATransmettreAuBoitier();
      if (aTransmettre.isEmpty) return 0;
      if (!(await verifier()).pret) return 0;
      var faites = 0;
      for (final v in aTransmettre) {
        final r = await transmettre(v.id);
        if (r.issue == IssueTransmission.transmise) faites++;
        if (r.issue == IssueTransmission.enAttente || r.issue == IssueTransmission.incertaine) break;
      }
      return faites;
    } finally {
      _reprise = false;
    }
  }

  /// Les ventes marquées « incertaines » (à vérifier sur l'appareil).
  Future<List<Sale>> aVerifier() async => [
    for (final v in await _caisse.ventesATransmettreAuBoitier(marquees: true, refusees: true))
      if (v.mecefMessage == marqueTransmissionBoitier) v,
  ];

  /// Nombre de factures qui attendent le boîtier (pour l'indicateur), refusées et incertaines comprises.
  Future<({int enAttente, int refusees, int aVerifier})> compteurs() async {
    final toutes = await _caisse.ventesATransmettreAuBoitier(marquees: true, refusees: true);
    return (
      enAttente: toutes.where((v) => v.mecefMessage != marqueTransmissionBoitier && v.mecefStatus != StatutMecef.erreur.code).length,
      refusees: toutes.where((v) => v.mecefStatus == StatutMecef.erreur.code).length,
      aVerifier: toutes.where((v) => v.mecefMessage == marqueTransmissionBoitier).length,
    );
  }
}
