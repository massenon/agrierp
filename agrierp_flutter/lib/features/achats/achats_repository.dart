import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/export/document_officiel.dart';

/// Une ligne du panier d'achat, avant enregistrement.
class LigneSaisieAchat {
  const LigneSaisieAchat({
    required this.produit,
    required this.quantite,
    required this.prixUnitaire,
  });

  final Product produit;
  final double quantite;
  final double prixUnitaire;

  double get total => quantite * prixUnitaire;
}

/// Une ligne de « Liste d'Achats » et de « Achats Recemment Enregistres ».
class LigneAchat {
  const LigneAchat({
    required this.achat,
    required this.envoye,
    this.retour,
    this.motifRefusRetour,
    this.motifRefusAchat,
  });

  final Purchase achat;

  /// Motif de rejet de l'ACHAT lui-même au push, mot pour mot (ticket F0.77) : compte
  /// absent du plan comptable, total nul, exercice clos… Le serveur seul sait pourquoi.
  final String? motifRefusAchat;

  /// ⚠️⚠️ **ACHAT REFUSÉ PAR LE SERVEUR (`conflict`)** : il n'existe que sur ce poste, ni
  /// stock, ni caisse, ni dette, ni écriture n'ont bougé là-bas. Le dire « en attente de
  /// synchronisation » laisserait croire qu'il partira tout seul : il est sorti des envois
  /// automatiques et attend une correction (souvent côté serveur) puis une relance.
  bool get refuse => achat.syncStatus == SyncStatus.conflict;

  /// ⚠️ **UN ACHAT NON ENVOYÉ N'EXISTE QUE SUR CE POSTE.** Le dire à l'écran
  /// est le seul moyen pour l'acheteur de savoir que la ferme, elle, ne le
  /// connaît pas encore : ni le stock du serveur, ni la caisse, ni la
  /// comptabilité n'ont bougé.
  final bool envoye;

  /// Le retour fournisseur demandé AU POSTE pour cet achat, s'il y en a un (ticket F0.74).
  final RetourFournisseur? retour;

  /// Motif de rejet du retour, mot pour mot tel que le serveur l'a donné.
  final String? motifRefusRetour;

  /// ⚠️ **RETOURNÉ = LE SERVEUR LE DIT (`returned_at`) OU IL A ACQUITTÉ LE RETOUR DU POSTE.**
  /// Un acquittement vaut fait accompli même si le tirage de confirmation a échoué :
  /// proposer un second retour ferait refuser le suivant « déjà retourné ».
  bool get retourne =>
      achat.returnedAt != null || retour?.syncStatus == SyncStatus.synced;

  /// Retour saisi ici, pas encore reçu par le serveur : ni stock, ni dette, ni écriture n'ont
  /// bougé là-bas.
  bool get retourEnAttente => retour?.syncStatus == SyncStatus.pending;

  /// Retour refusé par le serveur : il attend une relance depuis l'écran Synchronisation.
  bool get retourRefuse => retour?.syncStatus == SyncStatus.conflict;

  /// Le bouton « Retour fournisseur » n'est proposé que si rien n'est déjà engagé.
  bool get retournable => !retourne && retour == null;

  String get statut => refuse
      ? 'Refusé par le serveur'
      : retourne
      ? 'Retourné'
      : (envoye
            ? (achat.hasDebt ? 'Dette fournisseur' : 'Payé entièrement')
            : 'En attente de synchronisation');
}

/// Un remboursement fournisseur saisi au poste, avec le motif de rejet éventuel.
class LigneRemboursement {
  const LigneRemboursement({
    required this.remboursement,
    required this.nomFournisseur,
    this.motifRefus,
  });

  final RemboursementFournisseur remboursement;
  final String? nomFournisseur;
  final String? motifRefus;
}

/// Saisie de retour ou de remboursement refusée AVANT d'être écrite — le motif est montré
/// tel quel à l'écran.
class SaisieAchatRefusee implements Exception {
  const SaisieAchatRefusee(this.motif);

  final String motif;

  @override
  String toString() => motif;
}

/// Documents éditables de « Liste d'Achats » (`liste-achats.html`, ticket F0.75).
///
/// ⚠️ **CONSTRUCTEURS PURS, SANS IMPRIMANTE NI DISQUE** : le document est
/// vérifiable par un test ordinaire. L'effet (boîte d'impression) est injecté
/// par l'écran — `EditeursRapports`, le SEUL exportateur du poste.
///
/// ⚠️⚠️ **UN ACHAT NON ENVOYÉ N'EST PAS UN ACHAT REÇU PAR LA FERME.** Le
/// document sort de la ferme : il porte donc, en note de pied, ce que l'écran
/// dit à l'acheteur — sinon une ligne « saisie ici, pas encore reçue » serait
/// imprimée à l'identique d'une ligne acquittée par le serveur.
class DocumentsAchats {
  const DocumentsAchats._();

  /// Tiret affiché pour toute information que le poste ne détient pas.
  static const inconnu = '—';

  /// `exportAchatsPDF()` de la maquette : titre, sous-titre et cinq colonnes
  /// repris mot pour mot (`liste-achats.html` l.592-597).
  static DocumentOfficiel liste(List<LigneAchat> achats) {
    final enAttente = achats.where((a) => !a.envoye).length;

    return DocumentOfficiel(
      titre: 'Liste des Achats',
      sousTitre: 'Historique des achats et bons de commande',
      entetes: const [
        'Référence Achat',
        'Date',
        'Fournisseur',
        'Catégorie',
        'Montant Total',
      ],
      lignes: [
        for (final l in achats)
          DonneesDocument([
            inconnu,
            AchatsRepository.jour(l.achat.purchaseDate),
            l.achat.supplierName ?? inconnu,
            l.achat.supplierCategory ?? inconnu,
            '${AchatsRepository.montant(l.achat.total)} FCFA',
          ]),
      ],
      noteDePied: [
        "« — » : le registre du poste ne tient ni référence d'achat ni "
            'information absente du serveur.',
        if (enAttente > 0)
          '$enAttente achat(s) saisi(s) sur ce poste, pas encore reçu(s) par '
              'la ferme (en attente de synchronisation).',
      ].join(' '),
    );
  }

  /// « Imprimer » du détail : le bon de réception d'UN achat, dans l'ordre des
  /// trois blocs du tiroir de la maquette.
  ///
  /// ⚠️ **RÉFÉRENCE, OPÉRATEUR ET TVA RÉCUPÉRABLE SONT DES TIRETS.** Aucune
  /// référence ni opérateur n'est servi par le serveur ; la TVA se ventile là-bas
  /// ligne à ligne, selon le taux de chaque produit — les lignes d'un achat
  /// reçu ne descendent pas. Un « 0 » imprimé sur un document qui SORT de la
  /// ferme affirmerait qu'il n'y a aucune TVA à récupérer.
  static DocumentOfficiel bonReception(LigneAchat ligne) {
    final a = ligne.achat;

    return DocumentOfficiel(
      titre: 'Bon de Réception',
      sousTitre:
          'Achat du ${AchatsRepository.jour(a.purchaseDate)} — '
          '${a.supplierName ?? inconnu}',
      lignes: [
        const BandeDocument('Informations générales'),
        const DonneesDocument(['Référence', inconnu]),
        DonneesDocument(['Date', AchatsRepository.jour(a.purchaseDate)]),
        const DonneesDocument(['Opérateur', inconnu]),
        const BandeDocument('Fiche Fournisseur'),
        DonneesDocument(['Fournisseur', a.supplierName ?? inconnu]),
        const BandeDocument('Détails Financiers'),
        DonneesDocument([
          'Montant Total',
          '${AchatsRepository.montant(a.total)} FCFA',
        ]),
        const DonneesDocument(['TVA Récupérable (18%)', inconnu]),
        DonneesDocument(['Statut', ligne.statut]),
      ],
      noteDePied: ligne.envoye
          ? null
          : 'Achat saisi sur ce poste, pas encore reçu par la ferme : ni le '
                "stock, ni la caisse, ni la comptabilité n'ont bougé.",
    );
  }
}

class DonneesAchats {
  const DonneesAchats({
    required this.fournisseurs,
    required this.produits,
    required this.comptes,
    required this.achats,
    required this.bonsCommande,
    this.creances = const [],
    this.remboursements = const [],
    this.dettes = const [],
  });

  /// Dettes fournisseurs servies par le serveur (`payables`) : seules à porter `amount_paid`.
  final List<Payable> dettes;

  final List<Supplier> fournisseurs;
  final List<Product> produits;
  final List<TreasuryAccount> comptes;
  final List<LigneAchat> achats;
  final List<PurchaseOrder> bonsCommande;

  /// Créance ouverte par fournisseur, telle que le SERVEUR l'a servie au dernier tirage.
  final List<CreanceFournisseur> creances;

  /// Remboursements saisis au poste (en attente, refusés, ou acquittés).
  final List<LigneRemboursement> remboursements;

  /// Créance ouverte NETTE d'un fournisseur : celle du serveur moins les remboursements
  /// encore en attente d'envoi (ils ne sont pas encore déduits côté serveur). Plancher à
  /// zéro. Un remboursement refusé (`conflict`) n'a rien appliqué : il ne se déduit pas.
  double creanceNette(String fournisseurId) {
    final serveur = creances
        .where((c) => c.supplierId == fournisseurId)
        .fold<double>(0, (t, c) => t + c.openCredit);
    final attente = remboursements
        .where(
          (r) =>
              r.remboursement.supplierId == fournisseurId &&
              r.remboursement.syncStatus == SyncStatus.pending,
        )
        .fold<double>(0, (t, r) => t + r.remboursement.amount);
    final net = serveur - attente;
    return net < 0 ? 0 : net;
  }

  /// Achats retournés : le serveur le dit, ou il a acquitté le retour du poste.
  List<LigneAchat> get achatsRetournes =>
      achats.where((l) => l.retourne).toList();

  /// Retours saisis ici et pas encore appliqués par le serveur.
  int get retoursEnAttente => achats.where((l) => l.retourEnAttente).length;

  /// Les achats du poste en attente d'envoi — le compte que porte le badge.
  int get enAttente => achats.where((a) => !a.envoye).length;

  // ── Cartes de `liste-achats.html` (ticket F0.55) ──────────────────────────

  /// « Dépenses Totales » — tout ce que le poste connaît comme achat.
  ///
  /// ⚠️ **UN ACHAT PAS ENCORE ENVOYÉ Y COMPTE.** La ferme a dépensé l'argent au
  /// moment de l'achat, pas au moment de la synchronisation. L'exclure ferait
  /// mentir la carte précisément quand le poste travaille hors ligne — le seul
  /// moment où il sert vraiment.
  double get depensesTotales =>
      achats.fold<double>(0, (t, l) => t + l.achat.total);

  /// « Achats Réglés » — pièces que le SERVEUR déclare soldées.
  ///
  /// ⚠️⚠️ **SEULS LES ACHATS ENVOYÉS PEUVENT ÊTRE COMPTÉS RÉGLÉS.** `hasDebt`
  /// est calculé par le serveur et vaut `false` par défaut : un achat saisi ici
  /// et pas encore parti porte donc `hasDebt = false` sans que personne n'ait
  /// jamais statué sur son règlement. Le compter comme réglé afficherait un
  /// « payé » que rien n'appuie — et le chiffre se corrigerait tout seul à la
  /// synchronisation suivante, ce qui est plus troublant qu'une erreur franche.
  int get achatsRegles =>
      achats.where((l) => l.envoye && !l.achat.hasDebt).length;

  /// « Dettes en Cours » — reste dû sur les achats que le serveur dit endettés
  /// (ticket F0.77).
  ///
  /// ⚠️ Même restriction : un achat non envoyé n'a pas de statut de dette. Et
  /// le reste dû se CALCULE (`amount − amountPaid`), il n'est pas stocké — même
  /// piège que les créances clients et les dettes fournisseurs.
  ///
  /// ⚠️⚠️ **LE RESTE DÛ SE LIT SUR LA DETTE SERVIE (`payables`), PAS SUR L'ACHAT.** Le
  /// tirage sert les achats SANS `amount_paid` (la colonne reste à son défaut, 0) : calculer
  /// `total − amountPaid` sur un achat reçu du serveur rendait le TOTAL facturé, payé
  /// partiel ou non. Les dettes, elles, portent `amount_paid`.
  ///
  /// ⚠️ **DONNÉE ABSENTE = `null` (affiché « — »), JAMAIS 0.** Un achat endetté sans dette
  /// servie (tirage pas encore reçu, ou serveur qui ne la sert pas) a un reste dû INCONNU :
  /// l'ignorer sous-évaluerait la carte, la compter pour son total la surévaluerait.
  /// Aucun achat endetté = un vrai zéro (le poste SAIT qu'il n'y a pas de dette).
  double? get dettesEnCours {
    var somme = 0.0;
    for (final l in achats.where((l) => l.envoye && l.achat.hasDebt)) {
      final dettesAchat = dettes.where((d) => d.purchaseId == l.achat.id);
      if (dettesAchat.isEmpty) return null;
      for (final d in dettesAchat) {
        final reste = d.amount - d.amountPaid;
        somme += reste > 0 ? reste : 0;
      }
    }
    return somme;
  }

  /// Nombre d'achats endettés dont le reste dû est inconnu (aucune dette servie) — la
  /// légende de la carte « Dettes en Cours » quand elle affiche un tiret.
  int get achatsEndettesSansDette => achats
      .where(
        (l) =>
            l.envoye &&
            l.achat.hasDebt &&
            !dettes.any((d) => d.purchaseId == l.achat.id),
      )
      .length;

  /// Total des achats retournés — pour la légende de « Dépenses Totales ».
  double get depensesRetournees =>
      achatsRetournes.fold<double>(0, (t, l) => t + l.achat.total);

  /// « Écarts / Retours » — le nombre d'ACHATS RETOURNÉS (ticket F0.74).
  ///
  /// Calculable depuis que `returned_at` descend et que le poste acquitte ses propres
  /// retours : un tiret n'est plus honnête, et « 0 » l'est maintenant (le poste SAIT
  /// qu'aucun achat n'est retourné). ⚠️ **L'UNITÉ DIFFÈRE DU SERVEUR** : la page web
  /// compte les LIGNES de retour (`PurchaseReturn::count()`) ; les lignes d'un achat reçu ne
  /// descendent pas, le poste compte donc des achats (un retour annule tout l'achat, D6).
  /// Un retour en attente d'envoi n'est PAS compté : il n'est pas encore un fait pour la
  /// ferme (la légende le dit).
  int get ecartsEtRetours => achatsRetournes.length;
}

/// Lectures et écritures de `prototype_html/achats-commandes.html`.
///
/// ⚠️⚠️ **LE POSTE ENREGISTRE UNE INTENTION, LE SERVEUR APPLIQUE LES EFFETS.**
/// Un achat porte cinq effets — pièce et lignes, entrée en stock avec recalcul
/// du PMP, décaissement, dette fournisseur si le règlement est partiel,
/// écriture SYSCOHADA. Aucun n'est joué ici : `RecordPurchaseAction` les rejoue
/// tous à la réception. Décrémenter un stock local ferait diverger deux
/// valorisations, et le PMP du poste ne vaudrait plus rien.
///
/// ⚠️ **FOURNISSEURS ET BONS DE COMMANDE SONT EN LECTURE SEULE** : le serveur
/// ignore tout envoi les concernant et le compte dans `referentiels_ignored`.
class AchatsRepository {
  AchatsRepository({
    required this.database,
    required this.identifiantPoste,
    this.horloge,
  });

  final AppDatabase database;
  final String identifiantPoste;

  /// Horloge injectée (tests) : « date future refusée » se juge sur le jour du poste.
  final DateTime Function()? horloge;

  DateTime get _maintenant => (horloge ?? DateTime.now)();

  static DateTime _jourSeul(DateTime d) => DateTime(d.year, d.month, d.day);

  static const _uuid = Uuid();

  /// « 185 000 » — séparateur de milliers espace, arrondi au franc.
  static String montant(double valeur) {
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  /// « 14/07/2026 », ou un tiret quand la date est inconnue.
  static String jour(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<DonneesAchats> charger() async {
    // ⚠️ Les fiches archivées (au poste ou ailleurs) ne se proposent plus à l'achat.
    final fournisseurs = await (database.select(
      database.suppliers,
    )..where((f) => f.isActive.equals(true))).get();
    final produits = await (database.select(
      database.products,
    )..where((t) => t.isActive.equals(true))).get();
    final comptes = await database.select(database.treasuryAccounts).get();
    final achats = await database.select(database.purchases).get();
    final bons = await database.select(database.purchaseOrders).get();
    final retours = await database.select(database.purchaseReturns).get();
    final creances = await database.select(database.supplierCredits).get();
    final refus = {
      for (final c in await database.select(database.syncConflicts).get())
        c.id: c.reason,
    };
    final remboursements = await database
        .select(database.supplierRefunds)
        .get();
    final nomsFournisseurs = {
      for (final f in await database.select(database.suppliers).get())
        f.id: f.name,
    };

    // Un seul retour par achat (le dépôt refuse d'en écrire un second) ; en cas de doute,
    // l'acquitté l'emporte sur l'en-attente, qui l'emporte sur le refusé.
    int poids(RetourFournisseur r) => switch (r.syncStatus) {
      SyncStatus.synced => 2,
      SyncStatus.pending => 1,
      SyncStatus.conflict => 0,
    };
    final retourParAchat = <String, RetourFournisseur>{};
    for (final r in retours) {
      final courant = retourParAchat[r.purchaseId];
      if (courant == null || poids(r) > poids(courant)) {
        retourParAchat[r.purchaseId] = r;
      }
    }

    final dettes = await database.select(database.payables).get();

    return DonneesAchats(
      dettes: dettes,
      creances: creances,
      remboursements: [
        for (final r
            in remboursements.toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
          LigneRemboursement(
            remboursement: r,
            nomFournisseur: nomsFournisseurs[r.supplierId],
            motifRefus: r.syncStatus == SyncStatus.conflict
                ? refus['supplier_refunds:${r.id}']
                : null,
          ),
      ],
      fournisseurs: fournisseurs.toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
      produits: produits.toList()..sort((a, b) => a.name.compareTo(b.name)),
      comptes: comptes.toList()..sort((a, b) => a.label.compareTo(b.label)),
      achats:
          (achats.toList()
                ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate)))
              .map(
                (a) => LigneAchat(
                  achat: a,
                  envoye: a.syncStatus == SyncStatus.synced,
                  motifRefusAchat: a.syncStatus == SyncStatus.conflict
                      ? refus['purchases:${a.id}']
                      : null,
                  retour: retourParAchat[a.id],
                  motifRefusRetour:
                      retourParAchat[a.id]?.syncStatus == SyncStatus.conflict
                      ? refus['purchase_returns:${retourParAchat[a.id]!.id}']
                      : null,
                ),
              )
              .toList(),
      bonsCommande: bons.toList()
        ..sort(
          (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
            a.createdAt ?? DateTime(1970),
          ),
        ),
    );
  }

  /// Enregistre l'achat LOCALEMENT, en attente d'envoi.
  ///
  /// ⚠️⚠️ **RIEN N'EST APPLIQUÉ AU STOCK NI À LA CAISSE ICI.** L'achat part
  /// `pending` ; le serveur seul entre la marchandise, décaisse, ouvre la dette
  /// et passe l'écriture. Tant qu'il n'a pas acquitté, l'écran le dit.
  ///
  /// ⚠️ **LA DATE EST CELLE DE LA SAISIE**, pas celle de l'envoi : une
  /// livraison reçue mardi et synchronisée jeudi appartient à mardi — même
  /// règle que `sold_at` pour les ventes (ticket 14.71).
  Future<String> enregistrer({
    required String fournisseurId,
    required List<LigneSaisieAchat> lignes,
    required String modePaiement,
    required String compteId,
    required double montantPaye,
    DateTime? date,
  }) async {
    if (lignes.isEmpty) {
      throw ArgumentError('Un achat sans ligne ne veut rien dire.');
    }

    final fournisseur = await (database.select(
      database.suppliers,
    )..where((t) => t.id.equals(fournisseurId))).getSingleOrNull();

    final total = lignes.fold<double>(0, (t, l) => t + l.total);
    final jour = date ?? DateTime.now();
    final id = _uuid.v4();

    await database.transaction(() async {
      await database
          .into(database.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: id,
              deviceId: identifiantPoste,
              updatedAt: jour,
              supplierId: fournisseurId,
              supplierName: Value(fournisseur?.name),
              supplierCategory: Value(fournisseur?.category),
              paymentMode: modePaiement,
              treasuryAccountId: Value(compteId),
              total: total,
              // ⚠️ On ne règle jamais plus que le total : le serveur plafonne
              // aussi, mais un poste qui envoie une valeur absurde verrait son
              // achat rejeté pour rien.
              amountPaid: Value(montantPaye > total ? total : montantPaye),
              purchaseDate: jour,
            ),
          );

      for (final ligne in lignes) {
        await database
            .into(database.purchaseLines)
            .insert(
              PurchaseLinesCompanion.insert(
                id: _uuid.v4(),
                purchaseId: id,
                productId: ligne.produit.id,
                productName: Value(ligne.produit.name),
                qty: ligne.quantite,
                unitPrice: ligne.prixUnitaire,
              ),
            );
      }
    });

    return id;
  }

  /// Les lignes d'un achat — servent au détail comme au renvoi.
  Future<List<PurchaseLine>> lignesDe(String achatId) => (database.select(
    database.purchaseLines,
  )..where((t) => t.purchaseId.equals(achatId))).get();

  // ── Retour fournisseur et remboursement (ticket F0.74) ────────────────────

  /// Demande le retour d'un achat, EN ATTENTE d'envoi.
  ///
  /// ⚠️⚠️ **LE POSTE N'ÉCRIT QUE LE FAIT.** Il NE DÉCRÉMENTE PAS le stock local, ne touche ni
  /// la trésorerie, ni la dette, ni une écriture, et **n'émet JAMAIS de `stock_adjustments`
  /// pour un retour** : le serveur décrémente lui-même (jamais sous zéro) et rejette toute
  /// sortie qui désigne un retour — un ajustement ici ferait un double décrément que rien ne
  /// signalerait. Le retour est l'ANNULATION COMPLÈTE de l'achat (D6) : le serveur choisit
  /// les lignes concernées ; il peut refuser (achat sans écriture d'origine, stock
  /// insuffisant, exercice clos), et son motif est conservé tel quel.
  ///
  /// ⚠️ **REFUSER AVANT D'ÉCRIRE** : motif vide ou trop long, achat inconnu ou refusé par le
  /// serveur (il n'existe pas côté ferme), achat déjà retourné (marqueur du serveur, ou
  /// retour en attente, acquitté ou refusé et non relancé), date future ou antérieure à
  /// l'achat.
  Future<RetourFournisseur> enregistrerRetour({
    required String achatId,
    required String motif,
    DateTime? date,
  }) async {
    final motifNet = motif.trim();
    if (motifNet.isEmpty) {
      throw const SaisieAchatRefusee('Le motif du retour est obligatoire.');
    }
    if (motifNet.length > 500) {
      throw const SaisieAchatRefusee(
        'Le motif du retour tient en 500 caractères au plus.',
      );
    }

    final achat = await (database.select(
      database.purchases,
    )..where((a) => a.id.equals(achatId))).getSingleOrNull();
    if (achat == null) {
      throw const SaisieAchatRefusee('Achat inconnu — synchronisez le poste.');
    }
    if (achat.syncStatus == SyncStatus.conflict) {
      throw const SaisieAchatRefusee(
        "Cet achat a été refusé par le serveur : il n'existe pas côté ferme, "
        "il n'y a rien à retourner. Relancez-le depuis la synchronisation.",
      );
    }

    final aujourdhui = _jourSeul(_maintenant);
    final jour = _jourSeul(date ?? _maintenant);
    if (jour.isAfter(aujourdhui)) {
      throw const SaisieAchatRefusee(
        'La date du retour ne peut pas être dans le futur.',
      );
    }
    if (jour.isBefore(_jourSeul(achat.purchaseDate))) {
      throw const SaisieAchatRefusee(
        "La date du retour ne peut pas précéder celle de l'achat.",
      );
    }

    if (achat.returnedAt != null) {
      throw const SaisieAchatRefusee(
        "Cet achat a déjà été retourné : un achat ne peut être annulé qu'une fois.",
      );
    }
    final existants = await (database.select(
      database.purchaseReturns,
    )..where((r) => r.purchaseId.equals(achatId))).get();
    for (final r in existants) {
      switch (r.syncStatus) {
        case SyncStatus.synced:
          throw const SaisieAchatRefusee(
            "Cet achat a déjà été retourné : un achat ne peut être annulé qu'une fois.",
          );
        case SyncStatus.pending:
          throw const SaisieAchatRefusee(
            "Un retour est déjà en attente d'envoi pour cet achat.",
          );
        case SyncStatus.conflict:
          throw const SaisieAchatRefusee(
            'Le serveur a refusé le retour déjà demandé pour cet achat : '
            "relancez-le depuis la synchronisation plutôt que d'en demander un second.",
          );
      }
    }

    final id = _uuid.v4();
    await database
        .into(database.purchaseReturns)
        .insert(
          PurchaseReturnsCompanion.insert(
            id: id,
            deviceId: identifiantPoste,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: _maintenant,
            purchaseId: achatId,
            reason: motifNet,
            returnDate: jour,
          ),
        );

    return (database.select(
      database.purchaseReturns,
    )..where((r) => r.id.equals(id))).getSingle();
  }

  /// Créance ouverte NETTE d'un fournisseur, relue en base : celle du serveur moins les
  /// remboursements encore en attente d'envoi.
  Future<double> creanceNette(String fournisseurId) async {
    final creance = await (database.select(
      database.supplierCredits,
    )..where((c) => c.supplierId.equals(fournisseurId))).getSingleOrNull();
    final enAttente =
        await (database.select(database.supplierRefunds)..where(
              (r) => Expression.and([
                r.supplierId.equals(fournisseurId),
                r.syncStatus.equalsValue(SyncStatus.pending),
              ]),
            ))
            .get();
    final net =
        (creance?.openCredit ?? 0) -
        enAttente.fold<double>(0, (t, r) => t + r.amount);
    return net < 0 ? 0 : net;
  }

  /// Enregistre un remboursement reçu d'un fournisseur, EN ATTENTE d'envoi.
  ///
  /// ⚠️⚠️ **LE POSTE N'ENCAISSE RIEN** : ni solde de compte, ni dette, ni écriture. Le serveur
  /// entre l'argent dans les DEUX livres de trésorerie et passe Débit trésorerie / Crédit 409.
  ///
  /// ⚠️ **PLAFOND DU SERVEUR REPRODUIT ICI** : le serveur ACCEPTE un montant supérieur à la
  /// créance ouverte et le plafonne en silence ; le poste refuse plutôt que de laisser croire
  /// que tout a été encaissé. La créance est NETTE des remboursements déjà en attente. Un
  /// fournisseur sans créance ouverte est refusé (« jamais d'argent encaissé sans créance »).
  ///
  /// ⚠️ **`Infinity`** (saisie « 1e999 ») n'est ni NaN ni <= 0 : accepté, il ferait échouer
  /// l'encodage JSON de l'envoi à chaque synchronisation et bloquerait toute la file.
  Future<RemboursementFournisseur> enregistrerRemboursement({
    required String fournisseurId,
    required double montant,
    required DateTime date,
    required String compteId,
  }) async {
    if (montant.isNaN || montant.isInfinite || montant <= 0) {
      throw const SaisieAchatRefusee(
        'Le montant remboursé doit être supérieur à zéro.',
      );
    }
    if (montant < 1) {
      throw const SaisieAchatRefusee(
        'Le montant remboursé doit être d’au moins 1 FCFA.',
      );
    }

    final fournisseur = await (database.select(
      database.suppliers,
    )..where((f) => f.id.equals(fournisseurId))).getSingleOrNull();
    if (fournisseur == null) {
      throw const SaisieAchatRefusee(
        'Fournisseur inconnu — synchronisez le poste.',
      );
    }

    final compte = await (database.select(
      database.treasuryAccounts,
    )..where((c) => c.id.equals(compteId))).getSingleOrNull();
    if (compte == null) {
      throw const SaisieAchatRefusee(
        'Compte de trésorerie inconnu — synchronisez le poste avant de saisir.',
      );
    }

    final jour = _jourSeul(date);
    if (jour.isAfter(_jourSeul(_maintenant))) {
      throw const SaisieAchatRefusee(
        'La date du remboursement ne peut pas être dans le futur.',
      );
    }

    final ouverte = await creanceNette(fournisseurId);
    if (ouverte <= 0) {
      throw const SaisieAchatRefusee(
        "Ce fournisseur n'a aucune créance ouverte : aucun achat payé n'a été "
        'retourné, ou tout est déjà remboursé (remboursements en attente '
        'déduits).',
      );
    }
    if (montant > ouverte + 0.005) {
      throw SaisieAchatRefusee(
        'Le montant dépasse la créance ouverte sur ce fournisseur '
        '(${montantTexte(ouverte)} FCFA), remboursements en attente déduits.',
      );
    }

    final id = _uuid.v4();
    await database
        .into(database.supplierRefunds)
        .insert(
          SupplierRefundsCompanion.insert(
            id: id,
            deviceId: identifiantPoste,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: _maintenant,
            supplierId: fournisseurId,
            treasuryAccountId: compteId,
            amount: montant,
            refundDate: jour,
          ),
        );

    return (database.select(
      database.supplierRefunds,
    )..where((r) => r.id.equals(id))).getSingle();
  }

  /// Alias lisible de [montant] pour les motifs de refus.
  static String montantTexte(double valeur) => montant(valeur);
}
