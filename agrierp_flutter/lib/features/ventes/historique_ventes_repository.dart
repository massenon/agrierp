import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/export/pdf_recu.dart';
import 'avoirs_repository.dart';
import 'caisse_repository.dart';

/// Les quatre cartes de `historique-ventes.blade.php`, calculées comme `HistoriqueVentes::getKpisProperty()`.
class KpisHistorique {
  const KpisHistorique({
    required this.chiffreAffaires,
    required this.transactions,
    required this.panierMoyen,
    required this.encoursCreances,
  });

  /// Somme des totaux des ventes VALIDÉES de la période.
  final double chiffreAffaires;
  final int transactions;

  /// `round(CA / transactions)`, `0` sans vente — le web affiche « 0 FCFA », jamais un tiret.
  final double panierMoyen;

  /// `Receivable::where('status', '!=', 'soldee')` : `Σ amount − Σ amount_paid`, toutes périodes.
  final double encoursCreances;
}

/// Une ligne du tableau de l'historique.
class LigneVente {
  const LigneVente({
    required this.vente,
    required this.client,
    required this.articles,
    required this.reste,
    required this.envoyee,
  });

  final Sale vente;

  /// `$sale->customer?->name ?? 'Client Anonyme'`.
  final String client;

  /// `$sale->lines->count()`.
  final int articles;

  /// `$sale->status === 'annulee' ? 0 : ($sale->receivable?->balance ?? 0)`.
  final double reste;

  /// Vente reçue par le serveur (ou venue de lui) : `false` pour une vente saisie ici et pas encore acquittée.
  final bool envoyee;

  bool get annulee => vente.status == 'annulee';

  /// `$sale->status === 'annulee' ? 0 : $sale->total - $reste`.
  double get paye => annulee ? 0 : vente.total - reste;

  /// `strtoupper(substr($sale->id, 0, 8))`.
  String get facture => AvoirsRepository.referenceDeVente(vente.id);

  /// Pastille : Annulée, sinon En attente si un reste est dû, sinon Payée.
  String get statut => annulee ? 'Annulée' : (reste > 0 ? 'En attente' : 'Payée');

  /// `$modeLabels[$sale->payment_mode] ?? $sale->payment_mode`.
  String get mode => HistoriqueVentesRepository.libellesModes[vente.paymentMode] ?? vente.paymentMode;
}

/// Une ligne du détail d'une vente (le tiroir).
class ArticleVente {
  const ArticleVente({required this.nom, required this.quantite, required this.montant});

  final String nom;
  final double quantite;
  final double montant;
}

class DetailVente {
  const DetailVente({required this.ligne, required this.articles});

  final LigneVente ligne;
  final List<ArticleVente> articles;
}

/// Tout ce que l'écran lit, chargé une fois ; les filtres et les cartes s'en déduisent sans retourner en base.
class InstantaneHistorique {
  InstantaneHistorique({
    required this.ventes,
    required this.lignesParVente,
    required this.clients,
    required this.produits,
    required this.creancesParVente,
    required this.encoursCreances,
  });

  final List<Sale> ventes;
  final Map<String, List<SaleLine>> lignesParVente;
  final Map<String, Customer> clients;
  final Map<String, Product> produits;
  final Map<String, Receivable> creancesParVente;
  final double encoursCreances;

  /// `Customer::where('is_active', true)->orderBy('name')` : les clients du filtre « Client : Tous ».
  List<Customer> get clientsActifs => [
    for (final c in clients.values)
      if (c.isActive) c,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

  LigneVente _ligne(Sale v) {
    final c = creancesParVente[v.id];
    // ⚠️ Une vente saisie ici et pas encore reçue n'a pas encore de créance côté ferme : le serveur en ouvre UNE si — et
    // seulement si — le mode est « Crédit client » ET un client est rattaché (`pushSales`). Le poste applique la même règle.
    final double reste;
    if (v.status == 'annulee') {
      reste = 0;
    } else if (v.syncStatus != SyncStatus.synced) {
      reste = v.paymentMode == 'credit' && v.customerId != null ? v.total : 0;
    } else {
      final solde = c == null ? 0.0 : c.amount - c.amountPaid;
      reste = solde < 0 ? 0 : solde;
    }
    return LigneVente(
      vente: v,
      client: AvoirsRepository.nomDuClient(v, clients),
      articles: lignesParVente[v.id]?.length ?? 0,
      reste: reste,
      envoyee: v.syncStatus == SyncStatus.synced,
    );
  }

  /// `getKpisProperty()` : ventes dont la date effective tombe dans [du]..[au] (journées entières).
  KpisHistorique kpis(DateTime du, DateTime au) {
    final debut = _jour(du);
    final fin = _jour(au);
    final valides = [
      for (final v in ventes)
        if (v.status == 'validee' && !_jour(v.soldAt).isBefore(debut) && !_jour(v.soldAt).isAfter(fin)) v,
    ];
    final total = valides.fold<double>(0, (t, v) => t + v.total);
    return KpisHistorique(
      chiffreAffaires: total,
      transactions: valides.length,
      // `round()` de PHP : à l'entier le plus proche, les demis s'éloignent de zéro.
      panierMoyen: valides.isEmpty ? 0 : (total / valides.length).roundToDouble(),
      encoursCreances: encoursCreances,
    );
  }

  /// `getSalesProperty()` — SANS la pagination : les ventes de l'exercice affiché (`dansExercice`), filtrées et triées comme
  /// le web (date effective décroissante, puis identifiant décroissant).
  ///
  /// Les filtres du web : la recherche (« Facture, client... ») porte sur l'identifiant COMPLET de la vente ou le nom du
  /// client ; « Statut » : `annulee` · `payee` (validée, hors crédit) · `attente` (validée, mode crédit) — ⚠️ le web juge
  /// « En attente » sur le MODE, pas sur le reste dû ; « Mode » ; « Client ».
  List<LigneVente> filtrer({
    String recherche = '',
    String statut = '',
    String mode = '',
    String clientId = '',
    bool Function(DateTime soldAt)? dansExercice,
  }) {
    final cherche = recherche.toLowerCase();

    bool correspond(Sale v) {
      if (!(dansExercice?.call(v.soldAt) ?? true)) return false;
      if (cherche.isNotEmpty) {
        final parId = v.id.toLowerCase().contains(cherche);
        // `orWhereHas('customer', …)` : seul un client rattaché peut répondre à la recherche, jamais « Client Anonyme ».
        final rattachee = v.customerId != null || v.customerName != null;
        final parClient = rattachee && AvoirsRepository.nomDuClient(v, clients).toLowerCase().contains(cherche);
        if (!parId && !parClient) return false;
      }
      final statutOk = switch (statut) {
        'annulee' => v.status == 'annulee',
        'payee' => v.status == 'validee' && v.paymentMode != 'credit',
        'attente' => v.status == 'validee' && v.paymentMode == 'credit',
        _ => true,
      };
      if (!statutOk) return false;
      if (mode.isNotEmpty && v.paymentMode != mode) return false;
      if (clientId.isNotEmpty && v.customerId != clientId) return false;
      return true;
    }

    final retenues = ventes.where(correspond).toList()
      ..sort((a, b) {
        final c = b.soldAt.compareTo(a.soldAt);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    return [for (final v in retenues) _ligne(v)];
  }

  /// `getViewingSaleProperty()` : le détail d'une vente (client, date, articles, totaux).
  DetailVente? detail(String id) {
    final v = ventes.where((x) => x.id == id).firstOrNull;
    if (v == null) return null;
    return DetailVente(
      ligne: _ligne(v),
      articles: [
        for (final l in lignesParVente[id] ?? const <SaleLine>[])
          ArticleVente(nom: produits[l.productId]?.name ?? '—', quantite: l.qty, montant: l.manualTotalAmount),
      ],
    );
  }
}

/// Échec du « Télécharger PDF » d'une vente, avec une phrase lisible.
class EchecTicketVente implements Exception {
  const EchecTicketVente(this.message);

  final String message;

  @override
  String toString() => message;
}

/// « Télécharger PDF » du détail d'une vente, contre `GET /api/ventes/{id}/pdf` (ticket AV2).
///
/// ⚠️ **LE PDF EST PRODUIT PAR LE SERVEUR** — le ticket de caisse porte l'en-tête officiel de la ferme, comme
/// `exports.sale-ticket` du web — et exige donc le réseau, ce que l'écran dit au lieu de produire un document approximatif.
class ClientVentes {
  ClientVentes(this._client);

  final Dio _client;

  Future<PdfRecu> pdf(String venteId) async {
    try {
      final reponse = await _client.get<List<int>>(
        '/api/ventes/$venteId/pdf',
        options: Options(responseType: ResponseType.bytes),
      );
      final octets = Uint8List.fromList(reponse.data ?? const <int>[]);
      if (octets.isEmpty) throw const EchecTicketVente('Le serveur a renvoyé un document vide.');
      return PdfRecu(
        octets: octets,
        fichier: PdfRecu.nomDepuis(reponse.headers.value('content-disposition'), repli: 'vente.pdf'),
      );
    } on DioException catch (e) {
      throw _echec(e);
    }
  }

  static EchecTicketVente _echec(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.receiveTimeout) {
      return const EchecTicketVente(
        'Serveur injoignable. Cet export nécessite le réseau : réessayez une fois connecté.',
      );
    }

    // ⚠️ `ResponseType.bytes` : le corps d'erreur arrive en octets — sans le décoder, la phrase du serveur serait perdue.
    String? serveur;
    final brut = e.response?.data;
    try {
      final corps = brut is List<int> ? jsonDecode(utf8.decode(brut)) : brut;
      if (corps is Map && corps['message'] is String) serveur = corps['message'] as String;
    } on Object {
      // Corps non JSON : on s'en tient au code d'état.
    }

    return EchecTicketVente(switch (e.response?.statusCode) {
      401 => 'Session expirée : reconnectez-vous.',
      403 => serveur ?? "Votre rôle ne permet pas d'exporter le ticket d'une vente.",
      404 => "Cette vente n'existe pas sur le serveur : elle n'a pas encore été envoyée. Synchronisez.",
      429 => 'Trop de demandes. Réessayez dans une minute.',
      _ => 'Export impossible.',
    });
  }
}

/// Onglet « Historique des Ventes » du hub Ventes & Devis (`historique-ventes.blade.php`, `Livewire\Ventes\HistoriqueVentes`,
/// ticket AV2).
///
/// ⚠️⚠️ **LE POSTE ENREGISTRE LA DEMANDE, LE SERVEUR FAIT LES EFFETS.** « Annuler » passe la vente à `annulee` ICI et la
/// renvoie (`pending`) : le serveur réintègre le stock des produits vendus et passe la vente à `annulee`
/// (`AnnulerVenteAction`, celle de `cancelSale()` du web), une seule fois. Le stock local ne bouge pas : il se met à
/// jour au tirage — un ajustement ici ferait un double décrément silencieux.
///
/// ⚠️ **L'HISTORIQUE EST CELUI DE LA FERME** (« Toutes les ventes enregistrées de l'entreprise »), plus celui de ce
/// poste seul : `sales`, `sale_lines`, `receivables` et `customers` descendent au tirage. Une vente saisie ici et pas
/// encore reçue y figure aussi, sans reste dû tant que le serveur n'a pas ouvert sa créance (voir [InstantaneHistorique]).
class HistoriqueVentesRepository {
  HistoriqueVentesRepository({
    required this.database,
    this.client,
    this.horloge,
    CaisseRepository? caisse,
  }) : _caisse =
           caisse ??
           CaisseRepository(database: database, deviceId: 'historique', maintenant: horloge);

  final AppDatabase database;

  /// L'UNIQUE dépôt écrivain de `sales` (S-T7) : l'annulation lui est déléguée.
  final CaisseRepository _caisse;

  /// `null` : aucune session — « Télécharger PDF » répond par une phrase.
  final ClientVentes? client;
  final DateTime Function()? horloge;

  /// `$modeLabels` du Blade, dans l'ordre du filtre « Mode : Tous ».
  static const libellesModes = {
    'especes': 'Espèces',
    'mobile_money': 'Mobile Money',
    'virement': 'Virement',
    'credit': 'Crédit client',
    'avance': 'Avance',
  };

  /// `<option>` du filtre « Statut » : (valeur, libellé).
  static const statuts = [('payee', 'Payée'), ('attente', 'En attente'), ('annulee', 'Annulée')];

  Future<InstantaneHistorique> charger() async {
    final ventes = await database.select(database.sales).get();
    final lignes = await database.select(database.saleLines).get();
    final creances = await database.select(database.receivables).get();

    final parVente = <String, List<SaleLine>>{};
    for (final l in lignes) {
      parVente.putIfAbsent(l.saleId, () => []).add(l);
    }

    // `HistoriqueVentes` lit `Receivable::where('status', '!=', 'soldee')`, toutes périodes.
    final ouvertes = creances.where((c) => c.status != 'soldee');

    return InstantaneHistorique(
      ventes: ventes,
      lignesParVente: parVente,
      clients: {for (final c in await database.select(database.customers).get()) c.id: c},
      produits: {for (final p in await database.select(database.products).get()) p.id: p},
      creancesParVente: {
        for (final c in creances)
          if (c.saleId != null) c.saleId!: c,
      },
      encoursCreances: ouvertes.fold<double>(0, (t, c) => t + c.amount) - ouvertes.fold<double>(0, (t, c) => t + c.amountPaid),
    );
  }

  /// « Oui, Annuler la Vente » : la vente passe à `annulee` et repart `pending` (écrite par [CaisseRepository.annulerVente],
  /// l'unique écrivain de `sales`) ; `false` si elle l'était déjà (le web ne fait alors rien non plus, ni toast ni stock).
  Future<bool> annuler(String id) => _caisse.annulerVente(id);

  /// « Télécharger PDF » : le ticket de la vente, produit par le serveur.
  Future<PdfRecu> ticketPdf(String venteId) async {
    final c = client;
    if (c == null) throw const EchecTicketVente('Aucune session ouverte : reconnectez-vous pour exporter le ticket.');
    return c.pdf(venteId);
  }
}
