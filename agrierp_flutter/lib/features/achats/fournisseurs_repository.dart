import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import 'achats_repository.dart' show LigneAchat;

/// Une ligne de « Fiches Fournisseurs » et de « Ajouter Fournisseur ».
class LigneFournisseur {
  const LigneFournisseur({
    required this.fournisseur,
    required this.totalAchatsAnnee,
    required this.derniereCommande,
  });

  /// ⚠️ Une fiche saisie ici et pas encore acquittée n'existe que sur ce poste : le
  /// dire à l'écran est le seul moyen de savoir que la ferme ne la connaît pas encore.
  bool get enAttente => fournisseur.syncStatus != SyncStatus.synced;

  final Supplier fournisseur;

  /// ⚠️ **SOMME DES ACHATS DE L'ANNÉE CIVILE EN COURS**, calculée sur les
  /// achats présents au poste. Le premier tirage les descend tous, et chaque
  /// tirage incrémental apporte les nouveaux : la somme converge donc vers
  /// celle du serveur. Un achat encore `pending` y figure aussi — il est réel,
  /// même si la ferme ne le connaît pas encore.
  final double totalAchatsAnnee;

  final DateTime? derniereCommande;
}

/// Une ligne de « Dettes Fournisseurs ».
class LigneDette {
  const LigneDette({required this.dette});

  final Payable dette;

  /// ⚠️⚠️ **LE MONTANT DÛ SE CALCULE** : `amount − amount_paid`. Afficher
  /// `amount` compterait une seconde fois ce qui a déjà été réglé — même piège
  /// que les créances clients.
  double get montantDu => dette.amount - dette.amountPaid;

  /// Jours écoulés depuis l'échéance — négatif si elle n'est pas atteinte.
  int? retard(DateTime jour) {
    final echeance = dette.dueDate;
    if (echeance == null) return null;
    return jour
        .difference(DateTime(echeance.year, echeance.month, echeance.day))
        .inDays;
  }

  bool echue(DateTime jour) => (retard(jour) ?? -1) > 0;
}

/// Ce que l'utilisateur saisit dans « Nouveau Fournisseur » / « Modifier ».
class FormulaireFournisseur {
  const FormulaireFournisseur({
    required this.nom,
    required this.categorie,
    required this.telephone,
    this.adresse = '',
  });

  final String nom;
  final String categorie;
  final String telephone;
  final String adresse;
}

/// Catégories proposées par le formulaire (maquette ET page web).
const categoriesFournisseur = <String>[
  'Aliments',
  'Produits vétérinaires',
  'Intrants agricoles',
  'Matériel',
  'Autre',
];

/// Règlement refusé AVANT d'être écrit : mieux vaut le dire tout de suite que de
/// laisser un règlement voué au rejet dormir dans la file.
class ReglementRefuse implements Exception {
  ReglementRefuse(this.motif);

  final String motif;

  @override
  String toString() => motif;
}

/// Le profil d'un fournisseur (`profile-fournisseur.html`).
class ProfilFournisseur {
  const ProfilFournisseur({
    required this.fournisseur,
    required this.achats,
    required this.dettes,
    required this.commandes,
    required this.comptes,
    required this.enAttente,
    this.categorieParAchat = const {},
  });

  final Supplier fournisseur;

  /// Les 20 derniers achats, le plus récent d'abord (comme Laravel).
  final List<LigneAchat> achats;

  /// Dettes encore ouvertes, échéance croissante.
  final List<LigneDette> dettes;

  /// Les 20 derniers bons de commande, le plus récent d'abord.
  final List<PurchaseOrder> commandes;

  final List<TreasuryAccount> comptes;

  /// Règlements saisis ici pour ce fournisseur et pas encore acquittés.
  final double enAttente;

  /// Catégorie de PRODUIT de la première ligne de l'achat, comme Laravel.
  ///
  /// ⚠️ Les lignes d'un achat ne descendent pas du serveur : seuls les achats saisis
  /// sur CE poste en ont une. Les autres n'ont pas de catégorie ici — l'écran met un
  /// tiret, il ne la devine pas à partir de la catégorie du fournisseur.
  final Map<String, String> categorieParAchat;

  /// « Solde Global Dû » : reste dû, règlements en attente déduits.
  ///
  /// ⚠️ Net des règlements en attente, sinon le poste inviterait à payer deux fois
  /// ce qui vient de l'être. Jamais négatif.
  double get soldeGlobal {
    final brut = dettes.fold<double>(0, (t, d) => t + d.montantDu);
    final net = brut - enAttente;
    return net < 0 ? 0 : net;
  }
}

class DonneesFournisseurs {
  const DonneesFournisseurs({
    required this.fournisseurs,
    required this.dettes,
    required this.volumeAchatDuMois,
    this.comptes = const [],
    this.reglementsEnAttente = const {},
  });

  /// Comptes de trésorerie servis par le serveur (jamais codés en dur).
  final List<TreasuryAccount> comptes;

  /// Règlements saisis ici et pas encore acquittés, par fournisseur.
  ///
  /// ⚠️ Ils comptent comme faits : le règlement est réel, même si la ferme ne le
  /// connaît pas encore. Sans cela, le poste afficherait encore dû ce qui vient
  /// d'être payé et inviterait à le payer DEUX fois.
  final Map<String, double> reglementsEnAttente;

  double get totalEnAttente =>
      reglementsEnAttente.values.fold<double>(0, (t, v) => t + v);

  final List<LigneFournisseur> fournisseurs;
  final List<LigneDette> dettes;

  /// « Volume d'achat (mois) » de la maquette.
  ///
  /// ⚠️⚠️ **CE QUE LE POSTE DÉTIENT, PAS CE QUE LA FERME A ACHETÉ.** Les achats
  /// sont tirés avec un filtre `since` : un achat saisi ce mois-ci sur un AUTRE
  /// poste n'entre dans ce total qu'après une synchronisation. Un achat saisi
  /// ici et pas encore parti y figure, lui, tout de suite — il est réel, même
  /// si la ferme ne le connaît pas encore. Même règle que le total annuel par
  /// fournisseur, juste au-dessus.
  final double volumeAchatDuMois;

  /// « Fournisseurs actifs » de la maquette.
  ///
  /// ⚠️ **C'EST BIEN LE NOMBRE D'ACTIFS, ET SANS FILTRE ICI.** Le serveur ne
  /// sert QUE les fournisseurs actifs (`where('is_active', true)`) et ne
  /// descend même pas la colonne. Tout ce que le poste détient est donc actif
  /// par construction : compter la table donne exactement le chiffre attendu,
  /// là où un filtre local supposerait une information qu'il n'a pas.
  int get fournisseursActifs => fournisseurs.length;

  /// « Nouveaux (mois) » de la maquette — **jamais calculable au poste**.
  ///
  /// ⚠️⚠️ `created_at` NE VOYAGE PAS. Le tirage sélectionne six colonnes
  /// (`id`, `name`, `category`, `phone`, `email`, `address`) : aucune date de
  /// création. Le poste ne peut donc pas savoir lequel est nouveau, et « 0 »
  /// affirmerait qu'aucun fournisseur n'est arrivé ce mois-ci — une phrase que
  /// rien ne permet de tenir. La carte porte un tiret, et dit pourquoi.
  int? get nouveauxDuMois => null;

  /// Ardoise nette des règlements en attente (jamais négative).
  double get ardoiseTotale {
    final brut = dettes.fold<double>(0, (t, d) => t + d.montantDu);
    final net = brut - totalEnAttente;
    return net < 0 ? 0 : net;
  }

  int echues(DateTime jour) => dettes.where((d) => d.echue(jour)).length;

  /// ⚠️ **TOUJOURS `null`** : `suppliers` descend sans `is_active` — le serveur
  /// ne sert QUE les fournisseurs actifs. Le poste ne peut donc pas distinguer
  /// un partenaire archivé, et compter « 0 archivé » affirmerait qu'aucun ne
  /// l'a jamais été.
  int? get archives => null;
}

/// Lectures de `prototype_html/fournisseurs.html`.
///
/// ⚠️⚠️ **`suppliers` EST EN LECTURE SEULE** : référentiel, le serveur ignore tout
/// envoi le concernant. Un RÈGLEMENT, lui, s'enregistre au poste (ticket F0.69) mais
/// n'y décaisse rien et n'y impute rien : le serveur décaisse, impute sur les dettes
/// les plus anciennes et passe l'écriture.
class FournisseursRepository {
  FournisseursRepository({
    required this.database,
    this.deviceId = 'poste',
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final String deviceId;
  final Uuid _uuid;

  /// Règles de saisie, identiques à `SupplierCatalogService` (Laravel) : nom, catégorie
  /// et téléphone obligatoires. Vide si recevable.
  static Map<String, String> validerFiche(FormulaireFournisseur f) {
    const obligatoire = 'Ce champ est obligatoire.';
    final e = <String, String>{};

    if (f.nom.trim().isEmpty) {
      e['nom'] = obligatoire;
    } else if (f.nom.trim().length > 150) {
      e['nom'] = '150 caractères au plus.';
    }
    if (f.categorie.isEmpty) e['categorie'] = obligatoire;
    if (f.telephone.trim().isEmpty) {
      e['telephone'] = obligatoire;
    } else if (f.telephone.trim().length > 30) {
      e['telephone'] = '30 caractères au plus.';
    }
    if (f.adresse.trim().length > 255) e['adresse'] = '255 caractères au plus.';

    return e;
  }

  /// Crée une fiche, EN ATTENTE d'envoi. Le serveur la valide à la synchronisation.
  Future<Supplier> creerFournisseur(FormulaireFournisseur f) async {
    final id = _uuid.v4();

    await database
        .into(database.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: id,
            name: f.nom.trim(),
            category: Value(f.categorie),
            phone: Value(f.telephone.trim()),
            address: Value(f.adresse.trim().isEmpty ? null : f.adresse.trim()),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );

    return (await _fiche(id))!;
  }

  /// ⚠️ L'e-mail n'est pas touché : le formulaire n'a pas ce champ.
  Future<Supplier> modifierFournisseur(
    String id,
    FormulaireFournisseur f,
  ) async {
    await (database.update(
      database.suppliers,
    )..where((s) => s.id.equals(id))).write(
      SuppliersCompanion(
        name: Value(f.nom.trim()),
        category: Value(f.categorie),
        phone: Value(f.telephone.trim()),
        address: Value(f.adresse.trim().isEmpty ? null : f.adresse.trim()),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );

    return (await _fiche(id))!;
  }

  /// Archive la fiche : `is_active = false`, rien n'est supprimé. Ses achats et ses
  /// dettes restent. Elle disparaît des listes tout de suite, du poste au tirage
  /// suivant l'acquittement.
  Future<void> archiverFournisseur(String id) async {
    await (database.update(
      database.suppliers,
    )..where((s) => s.id.equals(id))).write(
      const SuppliersCompanion(
        isActive: Value(false),
        syncStatus: Value(SyncStatus.pending),
      ),
    );
  }

  Future<Supplier?> _fiche(String id) => (database.select(
    database.suppliers,
  )..where((s) => s.id.equals(id))).getSingleOrNull();

  /// Ce que le poste doit encore à ce fournisseur, règlements en attente déduits.
  Future<double> du(String fournisseurId) async {
    final dettes = await (database.select(
      database.payables,
    )..where((p) => p.supplierId.equals(fournisseurId))).get();
    final brut = dettes.fold<double>(
      0,
      (t, p) => t + (p.amount - p.amountPaid > 0 ? p.amount - p.amountPaid : 0),
    );
    final net = brut - (await _enAttente())[fournisseurId].orZero;
    return net < 0 ? 0 : net;
  }

  Future<Map<String, double>> _enAttente() async {
    final lignes = await (database.select(
      database.supplierPayments,
    )..where((r) => r.syncStatus.equalsValue(SyncStatus.pending))).get();
    final parFournisseur = <String, double>{};
    for (final r in lignes) {
      parFournisseur[r.supplierId] =
          (parFournisseur[r.supplierId] ?? 0) + r.amount;
    }
    return parFournisseur;
  }

  /// Enregistre un règlement fournisseur, EN ATTENTE d'envoi.
  ///
  /// ⚠️ **REFUSER AVANT D'ÉCRIRE.** Montant strictement positif, fournisseur et compte
  /// connus, et jamais plus que ce qui reste dû : le serveur ne solderait que ce qui
  /// existe, et un trop-versé laissé partir ferait croire à un paiement entier.
  Future<ReglementFournisseur> enregistrerReglement({
    required String fournisseurId,
    required double montant,
    required String compteId,
    required DateTime date,
  }) async {
    if (montant <= 0) {
      throw ReglementRefuse('Le montant réglé doit être supérieur à zéro.');
    }

    final fournisseur = await (database.select(
      database.suppliers,
    )..where((f) => f.id.equals(fournisseurId))).getSingleOrNull();
    if (fournisseur == null || !fournisseur.isActive) {
      throw ReglementRefuse('Fournisseur inconnu — synchronisez le poste.');
    }

    final compte = await (database.select(
      database.treasuryAccounts,
    )..where((c) => c.id.equals(compteId))).getSingleOrNull();
    if (compte == null) {
      throw ReglementRefuse(
        'Compte de trésorerie inconnu — synchronisez le poste avant de saisir.',
      );
    }

    final reste = await du(fournisseurId);
    if (reste <= 0) {
      throw ReglementRefuse("Ce fournisseur n'a aucune dette ouverte.");
    }
    if (montant > reste) {
      throw ReglementRefuse(
        'Le montant dépasse ce qui reste dû à ce fournisseur '
        '(${reste.toStringAsFixed(0)} F).',
      );
    }

    final id = _uuid.v4();
    await database
        .into(database.supplierPayments)
        .insert(
          SupplierPaymentsCompanion.insert(
            id: id,
            deviceId: deviceId,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: DateTime.now(),
            supplierId: fournisseurId,
            treasuryAccountId: compteId,
            amount: montant,
            paymentDate: DateTime(date.year, date.month, date.day),
          ),
        );

    return (database.select(
      database.supplierPayments,
    )..where((r) => r.id.equals(id))).getSingle();
  }

  /// Profil d'un fournisseur, `null` s'il n'est pas (ou plus) au poste.
  Future<ProfilFournisseur?> profil(String fournisseurId) async {
    final fournisseur = await (database.select(
      database.suppliers,
    )..where((f) => f.id.equals(fournisseurId))).getSingleOrNull();
    if (fournisseur == null) return null;

    final achats =
        await (database.select(database.purchases)
              ..where((a) => a.supplierId.equals(fournisseurId))
              ..orderBy([
                (a) => OrderingTerm(
                  expression: a.purchaseDate,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(20))
            .get();

    final dettes = await (database.select(
      database.payables,
    )..where((p) => p.supplierId.equals(fournisseurId))).get();

    final ouvertes =
        (dettes.where((d) => d.amount - d.amountPaid > 0).toList()..sort(
              (a, b) => (a.dueDate ?? DateTime(2100)).compareTo(
                b.dueDate ?? DateTime(2100),
              ),
            ))
            .map((d) => LigneDette(dette: d))
            .toList();

    final commandes =
        await (database.select(database.purchaseOrders)
              ..where((c) => c.supplierId.equals(fournisseurId))
              ..orderBy([
                (c) => OrderingTerm(
                  expression: c.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(20))
            .get();

    final categorieParAchat = <String, String>{};
    for (final a in achats) {
      final lignes =
          await (database.select(database.purchaseLines)
                ..where((l) => l.purchaseId.equals(a.id))
                ..limit(1))
              .get();
      if (lignes.isEmpty) continue;

      final produit = await (database.select(
        database.products,
      )..where((p) => p.id.equals(lignes.first.productId))).getSingleOrNull();
      final categorie = produit?.categoryId == null
          ? null
          : await (database.select(database.productCategories)
                  ..where((c) => c.id.equals(produit!.categoryId!)))
                .getSingleOrNull();
      if (categorie != null) categorieParAchat[a.id] = categorie.label;
    }

    return ProfilFournisseur(
      categorieParAchat: categorieParAchat,
      fournisseur: fournisseur,
      achats: [
        for (final a in achats)
          LigneAchat(achat: a, envoye: a.syncStatus == SyncStatus.synced),
      ],
      dettes: ouvertes,
      commandes: commandes,
      comptes: await database.select(database.treasuryAccounts).get(),
      enAttente: (await _enAttente())[fournisseurId] ?? 0,
    );
  }

  Future<DonneesFournisseurs> charger({DateTime? jour}) async {
    final aujourdhui = jour ?? DateTime.now();

    final fournisseurs = await (database.select(
      database.suppliers,
    )..where((f) => f.isActive.equals(true))).get();
    final achats = await database.select(database.purchases).get();
    final dettes = await database.select(database.payables).get();
    final comptes = await database.select(database.treasuryAccounts).get();
    final enAttente = await _enAttente();

    final totalParFournisseur = <String, double>{};
    final derniereParFournisseur = <String, DateTime>{};
    var volumeDuMois = 0.0;

    for (final achat in achats) {
      if (achat.purchaseDate.year == aujourdhui.year) {
        totalParFournisseur[achat.supplierId] =
            (totalParFournisseur[achat.supplierId] ?? 0) + achat.total;

        // ⚠️ LE MOIS SE COMPARE AVEC L'ANNÉE. Tester le seul numéro de mois
        // ferait entrer les achats de juillet dernier dans le juillet courant
        // — un volume mensuel qui double une fois l'an, sans rien signaler.
        if (achat.purchaseDate.month == aujourdhui.month) {
          volumeDuMois += achat.total;
        }
      }

      final connue = derniereParFournisseur[achat.supplierId];
      if (connue == null || achat.purchaseDate.isAfter(connue)) {
        derniereParFournisseur[achat.supplierId] = achat.purchaseDate;
      }
    }

    return DonneesFournisseurs(
      comptes: comptes,
      reglementsEnAttente: enAttente,
      volumeAchatDuMois: volumeDuMois,
      fournisseurs:
          (fournisseurs.toList()..sort((a, b) => a.name.compareTo(b.name)))
              .map(
                (f) => LigneFournisseur(
                  fournisseur: f,
                  totalAchatsAnnee: totalParFournisseur[f.id] ?? 0,
                  derniereCommande: derniereParFournisseur[f.id],
                ),
              )
              .toList(),
      dettes:
          (dettes.toList()..sort(
                (a, b) => (a.dueDate ?? DateTime(2100)).compareTo(
                  b.dueDate ?? DateTime(2100),
                ),
              ))
              .map((d) => LigneDette(dette: d))
              .toList(),
    );
  }
}

extension on double? {
  double get orZero => this ?? 0;
}
