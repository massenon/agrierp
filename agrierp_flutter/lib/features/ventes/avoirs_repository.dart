import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/sync/gestes_importants.dart';
import '../../core/temps/heure_benin.dart';

/// Les quatre cartes de `retours-avoirs.blade.php`, calculées comme `RetoursAvoirs::getKpisProperty()`.
class KpisAvoirs {
  const KpisAvoirs({
    required this.retoursDuMois,
    required this.montantAvoirs,
    required this.produitsRetournes,
    required this.tauxRetour,
  });

  final int retoursDuMois;
  final double montantAvoirs;

  /// `(int) sum('qty')` : la somme est TRONQUÉE, pas arrondie (2,5 plaquettes → 2), comme le web.
  final int produitsRetournes;

  /// `round(retours / ventes validées du mois × 100, 1)`, `0.0` sans vente (jamais une division par zéro).
  final double tauxRetour;
}

/// Une ligne du tableau « Retours et Avoirs ».
class LigneAvoir {
  const LigneAvoir({required this.avoir, required this.client, this.motifRefus});

  final AvoirClient avoir;

  /// Motif de rejet du serveur, mot pour mot (`sync_conflicts`) : seul le serveur sait pourquoi.
  final String? motifRefus;

  /// `$note->sale?->customer?->name ?? 'Client Anonyme'`.
  final String client;

  /// `strtoupper(substr($note->sale_id, 0, 8))`.
  String get facture => AvoirsRepository.referenceDeVente(avoir.saleId);

  /// `—` tant que le serveur n'a pas attribué `AV-AAAA-NNN` : une demande n'a pas de numéro avant l'envoi.
  String get numero => avoir.creditNoteNumber ?? '—';

  /// Saisie ici, pas encore reçue par le serveur : ni stock, ni écriture, ni numéro n'existent encore là-bas.
  bool get enAttenteDEnvoi => avoir.syncStatus == SyncStatus.pending;

  /// Refusée par le serveur : elle n'existe que sur ce poste et attend une relance depuis la synchronisation.
  bool get refusee => avoir.syncStatus == SyncStatus.conflict;
}

/// Une vente proposée dans « 1. Facture Source » (`recentSales` : les 50 dernières ventes validées).
class VenteRetournable {
  const VenteRetournable({required this.vente, required this.client});

  final Sale vente;
  final String client;

  String get reference => AvoirsRepository.referenceDeVente(vente.id);
}

/// Une ligne de la vente proposée dans « 2. Article Retourné ».
class ArticleRetournable {
  const ArticleRetournable({
    required this.produitId,
    required this.nom,
    required this.unite,
    required this.quantite,
    required this.montant,
  });

  final String produitId;
  final String nom;
  final String unite;
  final double quantite;
  final double montant;
}

class DonneesAvoirs {
  const DonneesAvoirs({required this.kpis, required this.lignes});

  final KpisAvoirs kpis;
  final List<LigneAvoir> lignes;
}

/// Résultat de « Enregistrer le Retour » : des erreurs sous leurs champs (`@error`), un refus dit en toast, ou l'avoir.
class ResultatRetour {
  const ResultatRetour({this.erreurs = const {}, this.refus, this.avoir});

  /// Champ (`saleId`, `productId`, `qty`, `amount`, `reason`) → message, les noms de propriétés du composant Livewire.
  final Map<String, String> erreurs;

  /// Refus d'exercice (R4), dit en toast « Retour refusé : … » ; rien n'a été écrit.
  final String? refus;

  final AvoirClient? avoir;

  bool get enregistre => avoir != null;
}

/// Écran « Retours et Avoirs » du hub Ventes & Devis (`retours-avoirs.blade.php`, `Livewire\Ventes\RetoursAvoirs`).
///
/// ⚠️⚠️ **LE POSTE ENREGISTRE LA DEMANDE, LE SERVEUR FAIT LES EFFETS** (motif du retour fournisseur F0.74, [PurchaseReturns]).
/// « Enregistrer le Retour » écrit UNE ligne `credit_notes` en attente d'envoi : ni stock, ni écriture, ni numéro `AV-…`.
/// Le serveur (`AvoirClientService`, le point de passage de `saveReturn()` du web) numérote, réintègre le stock si la
/// décision est « Réintégré », passe l'écriture inverse 701 / 443 / 411 et date le tout du JOUR du retour. Il peut
/// refuser ; son motif est conservé tel quel (écran Synchronisation).
///
/// ⚠️ **JAMAIS d'ajustement de stock ni d'écriture au poste pour un avoir** : un ajustement ici ferait un double
/// décrément silencieux au tirage suivant. Le stock affiché au poste se met à jour au tirage.
///
/// ⚠️ **LES REFUS DU SERVEUR SONT REPRODUITS AVANT D'ÉCRIRE** (mêmes messages, vérifiés par
/// `test/avoirs_blade_test.dart` contre `AvoirClientService.php`) : vente annulée, produit absent de la vente, quantité
/// au-delà de « vendu − déjà retourné », montant au-delà de « ligne − déjà crédité », exercice clos. Le serveur
/// re-juge tout : un poste désynchronisé qui laisserait passer un retour est refusé à l'envoi, avec son motif.
class AvoirsRepository {
  AvoirsRepository({
    required this.database,
    required this.identifiantPoste,
    this.horloge,
    this.gestes,
  });

  final AppDatabase database;
  final String identifiantPoste;

  /// Ticket S-T3 — signale une saisie en attente : la synchronisation automatique l'écoute.
  final GestesImportants? gestes;

  /// Horloge injectée (tests) : le mois des cartes et le jour du retour se jugent sur le jour du poste.
  final DateTime Function()? horloge;

  DateTime get _maintenant => (horloge ?? HeureBenin.maintenant)();

  static const _uuid = Uuid();

  ExerciceDeSaisie get _exercice =>
      ExerciceDeSaisie(database, maintenant: horloge ?? HeureBenin.maintenant);

  /// `strtoupper(substr($id, 0, 8))` — la « facture » d'une vente, au web comme ici (aucun numéro de facture n'existe).
  static String referenceDeVente(String id) =>
      (id.length >= 8 ? id.substring(0, 8) : id).toUpperCase();

  /// Libellé du client d'une vente : le client rattaché, sinon le nom servi avec la vente, sinon « Client Anonyme ».
  static String nomDuClient(Sale? vente, Map<String, Customer> clients) {
    if (vente == null) return 'Client Anonyme';
    final rattache = vente.customerId == null ? null : clients[vente.customerId!]?.name;
    return rattache ?? vente.customerName ?? 'Client Anonyme';
  }

  // ── Messages : ceux de `lang/fr/validation.php` (attributs `saleId`, `productId`, `qty`, `amount`, `reason`) ──────────

  static const messageVenteObligatoire = 'Le champ vente est obligatoire.';
  static const messageProduitObligatoire = 'Le champ produit est obligatoire.';
  static const messageQuantiteObligatoire = 'Le champ quantité est obligatoire.';
  static const messageQuantiteMinimale = 'Le champ quantité doit être au moins égal à 0.01.';
  static const messageMontantObligatoire = 'Le champ montant est obligatoire.';
  static const messageMontantMinimal = 'Le champ montant doit être au moins égal à 0.';
  static const messageMotifObligatoire = 'Le champ motif est obligatoire.';
  static const messageMotifTropLong = 'Le champ motif ne doit pas dépasser 255 caractères.';

  // ── Messages d'`AvoirClientService` (le serveur re-juge avec ces mêmes textes) ────────────────────────────────────────

  static const messageVenteInconnue = 'Cette vente est inconnue.';
  static const messageVenteAnnulee = "Cette vente est annulée : aucun retour n'est possible.";
  static const messageProduitHorsVente = 'Ce produit ne figure pas sur cette vente.';
  static const messageDejaRetourneEnTotalite = 'Ce produit a déjà été retourné en totalité sur cette vente.';

  static String messageQuantiteAuDela({required double vendu, required double retourne, required double reste}) =>
      'La quantité retournée dépasse ce qui reste retournable : ${_nombre(vendu)} vendu(s), '
      '${_nombre(retourne)} déjà retourné(s), ${_nombre(reste)} restant(s).';

  static String messageMontantAuDela(double reste) =>
      "Le montant de l'avoir dépasse ce qui reste à créditer sur cette ligne : ${montantFr(reste < 0 ? 0 : reste)} FCFA.";

  /// Les messages qui suivent la saisie d'un retour (toasts du web, `saveReturn()`).
  static const toastReintegre = 'Retour enregistré — produit réintégré au stock.';
  static const toastReforme = 'Retour enregistré — produit réformé, aucun impact stock.';
  static const toastComptabilise = ' Avoir comptabilisé (débit 701 / crédit 411).';
  static const toastTraite = 'Avoir marqué comme traité.';

  /// ⚠️ ÉCART ASSUMÉ (hors ligne) : le web écrit « produit réintégré au stock » parce qu'il le fait à l'instant ; au poste,
  /// ce n'est vrai qu'à la synchronisation. Le message le dit au lieu de promettre un effet qui n'a pas eu lieu.
  static String toastDemande(String decision, {required bool montantNul}) {
    final effet = decision == 'reintegre'
        ? 'le stock sera réintégré à la synchronisation'
        : 'produit réformé, aucun impact stock';
    final compta = montantNul
        ? ' Avoir de montant nul : aucune écriture comptable.'
        : ' Avoir comptabilisé (débit 701 / crédit 411) par le serveur.';
    return 'Retour enregistré sur ce poste — $effet.$compta';
  }

  // ── Lectures ───────────────────────────────────────────────────────────────────────────────────────────────────────────

  Future<DonneesAvoirs> charger() async {
    final avoirs = await database.select(database.creditNotes).get();
    final ventes = await database.select(database.sales).get();
    final clients = {for (final c in await database.select(database.customers).get()) c.id: c};
    final parVente = {for (final v in ventes) v.id: v};

    final refus = {
      for (final c in await database.select(database.syncConflicts).get()) c.id: c.reason,
    };

    avoirs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return DonneesAvoirs(
      kpis: _kpis(avoirs, ventes),
      lignes: [
        for (final a in avoirs)
          LigneAvoir(
            avoir: a,
            client: nomDuClient(parVente[a.saleId], clients),
            motifRefus: a.syncStatus == SyncStatus.conflict ? refus['credit_notes:${a.id}'] : null,
          ),
      ],
    );
  }

  /// `getKpisProperty()` : les avoirs et les ventes validées du MOIS COURANT (jour du poste), sur le jour du fait.
  KpisAvoirs _kpis(List<AvoirClient> avoirs, List<Sale> ventes) {
    final maintenant = _maintenant;
    bool dansLeMois(DateTime d) => d.year == maintenant.year && d.month == maintenant.month;

    // Un avoir refusé par le serveur n'existe pas côté ferme : il ne compte pas.
    final mois = avoirs
        .where((a) => a.syncStatus != SyncStatus.conflict && dansLeMois(a.createdAt))
        .toList();
    final ventesDuMois = ventes.where((v) => v.status == 'validee' && dansLeMois(v.soldAt)).length;
    final quantite = mois.fold<double>(0, (t, a) => t + (a.qty ?? 0));

    return KpisAvoirs(
      retoursDuMois: mois.length,
      montantAvoirs: mois.fold<double>(0, (t, a) => t + a.amount),
      produitsRetournes: quantite.truncate(),
      tauxRetour: ventesDuMois > 0 ? (mois.length / ventesDuMois * 1000).roundToDouble() / 10 : 0.0,
    );
  }

  /// `getRecentSalesProperty()` : les 50 dernières ventes VALIDÉES, la plus récente d'abord.
  Future<List<VenteRetournable>> ventesRecentes() async {
    final ventes = await (database.select(database.sales)
          ..where((v) => v.status.equals('validee'))
          ..orderBy([(v) => OrderingTerm.desc(v.soldAt)])
          ..limit(50))
        .get();
    final clients = {for (final c in await database.select(database.customers).get()) c.id: c};
    return [for (final v in ventes) VenteRetournable(vente: v, client: nomDuClient(v, clients))];
  }

  /// Les lignes de la vente choisie (`selectedSale->lines`) : une option par ligne.
  Future<List<ArticleRetournable>> articlesDe(String venteId) async {
    final lignes = await (database.select(database.saleLines)..where((l) => l.saleId.equals(venteId))).get();
    final produits = {for (final p in await database.select(database.products).get()) p.id: p};
    return [
      for (final l in lignes)
        ArticleRetournable(
          produitId: l.productId,
          nom: produits[l.productId]?.name ?? '—',
          unite: produits[l.productId]?.unit ?? '',
          quantite: l.qty,
          montant: l.manualTotalAmount,
        ),
    ];
  }

  // ── Écritures ──────────────────────────────────────────────────────────────────────────────────────────────────────────

  /// « Enregistrer le Retour » : valide comme `saveReturn()`, puis écrit la DEMANDE (`pending`).
  ///
  /// Ordre des contrôles = celui du web : champs du formulaire (tous les messages à la fois), puis règles de retour
  /// (sous les champs `saleId`, `productId`, `qty`, `amount`), puis l'exercice du jour (refus dit en toast).
  Future<ResultatRetour> enregistrer({
    required String? venteId,
    required String? produitId,
    required double? quantite,
    required double? montant,
    required String motif,
    required String decision,
    String notes = '',
  }) async {
    final erreurs = <String, String>{};
    if (venteId == null || venteId.isEmpty) erreurs['saleId'] = messageVenteObligatoire;
    if (produitId == null || produitId.isEmpty) erreurs['productId'] = messageProduitObligatoire;
    if (quantite == null || quantite.isNaN) {
      erreurs['qty'] = messageQuantiteObligatoire;
    } else if (quantite < 0.01) {
      erreurs['qty'] = messageQuantiteMinimale;
    }
    if (montant == null || montant.isNaN) {
      erreurs['amount'] = messageMontantObligatoire;
    } else if (montant < 0) {
      erreurs['amount'] = messageMontantMinimal;
    }
    final motifNet = motif.trim();
    if (motifNet.isEmpty) {
      erreurs['reason'] = messageMotifObligatoire;
    } else if (motifNet.length > 255) {
      erreurs['reason'] = messageMotifTropLong;
    }
    if (erreurs.isNotEmpty) return ResultatRetour(erreurs: erreurs);

    final regles = await _reglesDeRetour(venteId!, produitId!, quantite!, montant!);
    if (regles.isNotEmpty) return ResultatRetour(erreurs: regles);

    // 🔴→✅ Le retour est daté du JOUR : exercice absent ou clos refusé AVANT d'écrire (motif R4 du serveur).
    final maintenant = _maintenant;
    final refus = await _exercice.refus(DateTime(maintenant.year, maintenant.month, maintenant.day));
    if (refus != null) return ResultatRetour(refus: refus);

    final id = _uuid.v4();
    await database.into(database.creditNotes).insert(
      CreditNotesCompanion.insert(
        id: id,
        deviceId: identifiantPoste,
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: HeureBenin.versInstant(maintenant),
        saleId: venteId,
        productId: produitId,
        qty: Value(quantite),
        amount: montant,
        reason: Value(motifNet),
        decision: Value(decision),
        inspectionNotes: Value(notes.trim().isEmpty ? null : notes),
        createdAt: maintenant,
      ),
    );

    gestes?.signaler();

    return ResultatRetour(
      avoir: await (database.select(database.creditNotes)..where((a) => a.id.equals(id))).getSingle(),
    );
  }

  /// Les refus d'`AvoirClientService::verifier()`, reproduits sur les données du poste.
  Future<Map<String, String>> _reglesDeRetour(
    String venteId,
    String produitId,
    double quantite,
    double montant,
  ) async {
    final vente = await (database.select(database.sales)..where((v) => v.id.equals(venteId))).getSingleOrNull();
    if (vente == null) return {'saleId': messageVenteInconnue};
    if (vente.status == 'annulee') return {'saleId': messageVenteAnnulee};

    final lignes = await (database.select(database.saleLines)
          ..where((l) => l.saleId.equals(venteId) & l.productId.equals(produitId)))
        .get();
    if (lignes.isEmpty) return {'productId': messageProduitHorsVente};

    // Les demandes refusées par le serveur n'existent pas côté ferme : elles ne comptent pas dans le « déjà retourné ».
    final deja = await (database.select(database.creditNotes)
          ..where(
            (a) =>
                a.saleId.equals(venteId) &
                a.productId.equals(produitId) &
                a.syncStatus.equalsValue(SyncStatus.conflict).not(),
          ))
        .get();

    final vendu = _arrondi(lignes.fold<double>(0, (t, l) => t + l.qty));
    final retourne = _arrondi(deja.fold<double>(0, (t, a) => t + (a.qty ?? 0)));
    final reste = _arrondi(vendu - retourne);
    if (_arrondi(quantite) > reste) {
      return {
        'qty': reste <= 0
            ? messageDejaRetourneEnTotalite
            : messageQuantiteAuDela(vendu: vendu, retourne: retourne, reste: reste),
      };
    }

    final ligne = _arrondi(lignes.fold<double>(0, (t, l) => t + l.manualTotalAmount));
    final credite = _arrondi(deja.fold<double>(0, (t, a) => t + a.amount));
    final resteMontant = _arrondi(ligne - credite);
    if (_arrondi(montant) > resteMontant) return {'amount': messageMontantAuDela(resteMontant)};

    return const {};
  }

  /// « Marquer comme traité » : le statut passe à `traite` ici (comme au web, à l'instant) et la ligne repart `pending` ;
  /// le serveur la marque une seule fois (`AvoirClientService::marquerTraite`). Déjà traité : rien ne bouge.
  /// ⚠️ Un avoir encore sans numéro (jamais reçu par le serveur) part avec sa demande, déjà « traité ».
  Future<bool> marquerTraite(String id) async {
    final avoir = await (database.select(database.creditNotes)..where((a) => a.id.equals(id))).getSingleOrNull();
    if (avoir == null || avoir.status == 'traite') return false;

    await (database.update(database.creditNotes)..where((a) => a.id.equals(id))).write(
      CreditNotesCompanion(
        status: const Value('traite'),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(HeureBenin.versInstant(_maintenant)),
      ),
    );
    gestes?.signaler();
    return true;
  }

  // ── Formats (ceux du Blade) ────────────────────────────────────────────────────────────────────────────────────────────

  static double _arrondi(double v) => (v * 100).roundToDouble() / 100;

  /// `rtrim(rtrim(number_format($v, 2, ',', ''), '0'), ',')`.
  static String _nombre(double v) {
    final texte = v.toStringAsFixed(2).replaceAll('.', ',');
    return texte.contains(',') ? texte.replaceFirst(RegExp(r',?0+$'), '') : texte;
  }

  /// `rtrim(rtrim(number_format($qty, 2, '.', ''), '0'), '.')` — la quantité du Blade (« 10 », « 2.5 »).
  static String quantiteFr(double v) {
    final texte = v.toStringAsFixed(2);
    return texte.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// `number_format($v, 0, ',', ' ')`.
  static String montantFr(double valeur) {
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }
}
