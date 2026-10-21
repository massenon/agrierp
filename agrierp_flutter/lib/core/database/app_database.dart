import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/domaine_email.dart';
import 'sync_columns.dart';

part 'app_database.g.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  RÉFÉRENTIELS — TIRÉS DU SERVEUR, JAMAIS POUSSÉS
// ═══════════════════════════════════════════════════════════════════════════
// ⚠️ Le serveur IGNORE explicitement tout push sur ces tables (« le serveur a
// toujours raison »), et le dit dans sa réponse (`referentiels_ignored`)
// plutôt que d'accepter puis d'écraser au pull suivant. Les rendre modifiables
// localement produirait une saisie que l'utilisateur verrait disparaître sans
// explication à la synchronisation suivante.
//
// ⚠️ EXCEPTION (ticket H9b, décision client D-H9 du 19/10/2026) : les barèmes
// d'élevage (rations, prophylaxie, provendes, numérotation, délai du rappel des
// soins) sont désormais ACCEPTÉS par le serveur (`manage-elevage`) et envoyés
// par le poste — voir [BaremeElevageSynchronisable].

class ProductCategories extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get label => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Products extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get sku => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get speciesId => text().nullable()();
  TextColumn get unit => text()();

  /// `fixe` ou `fourchette` — le mode de tarification décide si la caisse
  /// impose le prix ou laisse le caissier le saisir dans une plage.
  TextColumn get pricingMode => text()();
  RealColumn get priceMin => real().nullable()();
  RealColumn get priceMax => real().nullable()();
  RealColumn get tvaRate => real().withDefault(const Constant(0))();

  /// ⚠️ PEUT ÊTRE NÉGATIF, et ce n'est pas une anomalie de données : c'est le
  /// signe d'une ENTRÉE NON SAISIE (production ou achat pas encore
  /// enregistré), régularisable par un ajustement d'inventaire. Aucun
  /// plancher n'est posé ici — le plancher s'applique à la VALORISATION, pas
  /// à la quantité (voir `stockValorisable`).
  RealColumn get stockQty => real().withDefault(const Constant(0))();
  RealColumn get alertThreshold => real().nullable()();

  /// Description libre, servie avec le produit (ticket F0.67). `null` : aucune.
  TextColumn get description => text().nullable()();

  /// ⚠️ **UN PRODUIT CRÉÉ OU MODIFIÉ AU POSTE EST `pending` JUSQU'À L'ACQUITTEMENT**
  /// (ticket F0.67). Défaut `synced` : tout ce qui descend du serveur l'est, et les
  /// lignes d'avant la migration aussi. Le tirage ne touche JAMAIS un produit qui
  /// ne l'est pas — il effacerait la saisie.
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Espèce d'élevage ACTIVE — référentiel remplacé à chaque tirage (ticket F0.67).
///
/// ⚠️ **SEULES LES ESPÈCES DONT LE MODULE EST ACTIF** sont servies : le formulaire
/// « Ajouter un Produit » propose la « Filière d'élevage », et en proposer une
/// éteinte laisserait créer un produit pour une filière que l'exploitant a
/// désactivée. Le poste n'avait jusqu'ici que les CODES d'espèce, portés par les
/// bandes — pas d'identifiant à écrire dans `products.species_id`.
@DataClassName('EspeceElevage')
class LivestockSpecies extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get code => text()();
  TextColumn get label => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Règlement d'un fournisseur saisi au poste (ticket F0.69).
///
/// ⚠️⚠️ **LE POSTE N'IMPUTE RIEN ET NE TOUCHE PAS À LA TRÉSORERIE** : il enregistre
/// « tant, à ce fournisseur, depuis ce compte ». Le serveur impute sur les dettes les
/// plus anciennes, décaisse le compte ET passe l'écriture 401/5xx. Même schéma que les
/// dépenses : un solde de trésorerie inventé ici n'engagerait rien et divergerait du
/// serveur dès la première saisie faite ailleurs.
@DataClassName('ReglementFournisseur')
class SupplierPayments extends Table with SyncColumns {
  TextColumn get supplierId => text().withLength(min: 36, max: 36)();
  TextColumn get treasuryAccountId => text().withLength(min: 36, max: 36)();
  RealColumn get amount => real()();
  DateTimeColumn get paymentDate => dateTime()();
}

/// Demande de retour fournisseur saisie au poste (ticket F0.74).
///
/// ⚠️⚠️ **LE POSTE ENREGISTRE LA DEMANDE, PAS SES EFFETS.** Un retour est l'ANNULATION
/// COMPLÈTE d'un achat (D6) : le poste ne dit NI quelles lignes NI quelles quantités — le
/// serveur choisit les lignes concernées, décrémente le stock (jamais sous zéro),
/// contre-passe l'écriture d'achat, annule la part non payée de la dette et ouvre la
/// créance fournisseur (409) sur la part déjà payée. Il peut refuser : achat sans écriture
/// d'origine, stock insuffisant, exercice clos, déjà retourné.
///
/// ⚠️ **JAMAIS d'ajustement de stock pour un retour** : le serveur rejette toute sortie qui
/// le désigne, et décrémenter ici ferait un double décrément silencieux.
/// Ticket U8 — la table reçoit AUSSI les LIGNES de retour servies par le serveur (`purchase_returns`, une
/// ligne par ligne d'achat retournée, `device_id` = `serveur`, `synced`) : la carte « Écarts / Retours »
/// les compte comme le web. Une demande `pending`/`conflict` du poste n'est jamais touchée par le tirage ;
/// une demande acquittée est remplacée par les lignes que le serveur a créées. Aucune colonne ajoutée.
@DataClassName('RetourFournisseur')
class PurchaseReturns extends Table with SyncColumns {
  TextColumn get purchaseId => text().withLength(min: 36, max: 36)();

  /// Motif du retour, ≤ 500 caractères (contrat 15.20).
  TextColumn get reason => text()();

  /// Date du FAIT (jour), ≤ aujourd'hui et pas antérieure à l'achat.
  DateTimeColumn get returnDate => dateTime()();
}

/// Remboursement reçu d'un fournisseur, saisi au poste (ticket F0.74).
///
/// ⚠️⚠️ **LE POSTE N'ENCAISSE RIEN** : il enregistre « tant, de ce fournisseur, sur ce
/// compte ». Le serveur plafonne à la créance ouverte, fait entrer l'argent dans les DEUX
/// livres de trésorerie et passe Débit trésorerie / Crédit 409. Cette table ne descend
/// pas du serveur.
@DataClassName('RemboursementFournisseur')
class SupplierRefunds extends Table with SyncColumns {
  TextColumn get supplierId => text().withLength(min: 36, max: 36)();
  TextColumn get treasuryAccountId => text().withLength(min: 36, max: 36)();
  RealColumn get amount => real()();
  DateTimeColumn get refundDate => dateTime()();
}

/// Créance OUVERTE par fournisseur, calculée et servie par le serveur (`supplier_credits`).
///
/// ⚠️⚠️ **REMPLACÉE EN ENTIER À CHAQUE TIRAGE** (le serveur la sert sans filtre `since`,
/// seulement pour les fournisseurs > 0) : aucune écriture locale n'y a lieu. Le poste en
/// déduit ses remboursements en attente pour ne pas proposer plus que ce que le serveur
/// accepterait.
@DataClassName('CreanceFournisseur')
class SupplierCredits extends Table {
  TextColumn get supplierId => text().withLength(min: 36, max: 36)();
  TextColumn get supplierName => text().nullable()();
  RealColumn get openCredit => real()();

  @override
  Set<Column> get primaryKey => {supplierId};
}

class LivestockLots extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get code => text()();
  TextColumn get speciesId => text()();

  /// Code de l'espece, servi avec la bande par le tirage.
  ///
  /// ⚠️ LE POSTE N'A PAS DE TABLE DES ESPECES. Sans ce champ, il ne peut pas
  /// appliquer le garde-fou « aviculture + stade ponte » du serveur, et une
  /// ponte d'escargots — stade « ponte » elle aussi — entrerait au stock des
  /// oeufs de table.
  TextColumn get speciesCode => text().nullable()();
  TextColumn get stage => text().nullable()();
  IntColumn get initialQuantity => integer().withDefault(const Constant(0))();
  IntColumn get currentQuantity => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdDate => dateTime().nullable()();
  RealColumn get acquisitionCost => real().nullable()();
  TextColumn get productId => text().nullable()();
  TextColumn get status => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// Ticket 15.46 (v39) — bande d'origine d'une bande constituée à partir d'une autre (portée, sevrés).
  TextColumn get lotSourceId => text().nullable()();

  /// ⚠️ **UNE BANDE CRÉÉE, MODIFIÉE OU ARCHIVÉE AU POSTE EST `pending` JUSQU'À L'ACQUITTEMENT** (ticket BS1, v49). Défaut
  /// `synced` : tout ce qui descend du serveur l'est, et les bandes d'avant la migration aussi. Le tirage ne touche
  /// JAMAIS une bande qui ne l'est pas (`_absorberBandes`, strict).
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();

  /// Ticket BS1 (v49) — CORRECTION MANUELLE DE L'EFFECTIF ACTUEL (« Modifier la Bande » du web), à envoyer. `null` :
  /// aucune. ⚠️ L'effectif d'une bande est celui de ses fiches (cascade) : la ligne envoyée ne porte `effectif_corrige`
  /// que si l'exploitant l'a explicitement corrigé, sinon le serveur garderait un effectif périmé du poste. Vidé à
  /// l'acquittement.
  IntColumn get effectifCorrige => integer().nullable()();

  /// Ticket BS-Q7 (v50) — RESTAURATION d'une bande archivée, à envoyer : geste EXPLICITE (jamais déduit de
  /// `is_active = true`, qui peut venir d'une copie périmée d'un autre poste). Vidé à l'acquittement.
  BoolColumn get restauree => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ticket H9b (décision client D-H9 du 19/10/2026 : « Paramètres Élevage modifiables sur le poste et le web »)
/// — colonnes communes aux trois barèmes d'élevage désormais ENVOYÉS par le poste (rations, prophylaxie,
/// provendes).
///
/// ⚠️ Ce n'est pas [SyncColumns] : ces tables existaient avant la décision, leurs lignes tirées n'ont ni
/// appareil d'origine ni instant de saisie, et le serveur (`RecordParametresElevageFromDeviceAction`) n'en lit
/// aucun. Elles reçoivent donc, comme `customers` au ticket F0.72, un statut de synchronisation par défaut
/// `synced` (tout ce qui descend du serveur l'est) et un instant de saisie NULLABLE.
///
/// ⚠️⚠️ **SUPPRIMER = ARCHIVER** (ticket 14.55 du web) : `is_active = false`, la ligne disparaît de l'écran
/// et des calculs (provende, protocole) mais reste restaurable côté serveur. Un barème effacé faisait
/// disparaître la provende calculée de toute une catégorie sans que rien ne l'explique.
mixin BaremeElevageSynchronisable on Table {
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// `pending` : saisi ou archivé au poste, pas encore acquitté — le tirage ne l'écrase JAMAIS.
  /// `conflict` : refusé par le serveur, motif mot pour mot dans `sync_conflicts`.
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();

  /// Instant de la SAISIE au poste (jamais de l'envoi) ; nul pour une ligne tirée du serveur. Il sert à
  /// n'acquitter que la version partie : une ligne modifiée pendant l'envoi reste `pending`.
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// Ration normative par espèce et par stade, en grammes par jour.
///
/// ⚠️ RÉFÉRENTIEL ÉDITABLE CÔTÉ SERVEUR (écran Paramètres > Élevage) : ces
/// grammages ne sont PAS des constantes. Les coder en dur dans le client
/// ferait diverger la provende calculée le jour où la ferme corrige une
/// ration — sans le moindre signal. Ils descendent donc à chaque tirage.
///
/// ⚠️ Ils sont servis SANS filtre `since`, pour qu'un poste resté longtemps
/// hors ligne ne garde pas un grammage périmé qui fausserait tous ses calculs.
///
/// Ticket H9b (décision client D-H9 du 19/10/2026) — **MODIFIABLE AU POSTE COMME AU WEB** : création,
/// modification et archivage (`is_active = false`, jamais de suppression) partent en `pending` vers
/// `RecordParametresElevageFromDeviceAction` (droit `manage-elevage`). Voir [BaremeElevageSynchronisable].
class FeedRationStandards extends Table with BaremeElevageSynchronisable {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get speciesCode => text()();
  TextColumn get stageLabel => text()();
  RealColumn get rationGPerDay => real()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ticket U2 (décision client D-U2 du 19/10/2026 : « objectifs de GMQ, une seule source ») — barème des
/// OBJECTIFS DE CROISSANCE par espèce et par stade (`growth_standards` du serveur, modèle `GrowthStandard`).
///
/// ⚠️⚠️ **RÉFÉRENTIEL EN LECTURE SEULE** : le poste ne l'écrit jamais (pas de [SyncColumns], le serveur ignore
/// tout envoi et le compte dans `referentiels_ignored`). Servi COMPLET à chaque tirage et remplacé tel quel :
/// c'est la seule source des objectifs du Dashboard Élevage, qui portait jusqu'ici des constantes (15-20,
/// 20-55, 400-650 g/j) recopiées ensuite au web. Règle d'agrégation par espèce :
/// `DashboardElevageRepository.objectifPour` (= `GrowthAnalysisService::objectifPour` du serveur).
class GrowthStandards extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get speciesCode => text()();
  TextColumn get stageLabel => text()();

  /// Objectif minimal, en g/jour (`unsignedInteger` au serveur).
  IntColumn get gmqMinGPerDay => integer()();

  /// Objectif maximal, en g/jour.
  IntColumn get gmqMaxGPerDay => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Type de provende servi en ferme — catalogue des aliments.
///
/// ⚠️⚠️ **C'EST ICI QUE VIT LE POIDS DU SAC.** Le stock compte les aliments
/// **en sacs** (`products.stock_qty`), la ration se calcule **en grammes par
/// tête et par jour** : sans le poids d'un sac, l'autonomie alimentaire du
/// Dashboard Élevage reste un tiret. `standard_bag_weight_kg` porte la donnée
/// — 25 kg pour les cinq types de la ferme.
///
/// ⚠️ **MAIS LE LIEN AVEC LE PRODUIT STOCKÉ N'EXISTE PAS.** « Aliment Ponte
/// (Pondeuse) » (type) et « Aliment ponte 25kg » (produit) sont deux lignes de
/// deux tables que rien ne relie : ni clé étrangère, ni code commun. Les
/// rapprocher sur la ressemblance des noms serait inventer une donnée de
/// gestion. **ARBITRAGE CLIENT** : ajouter `products.feed_type_id`.
///
/// ⚠️ Le libellé de l'espèce voyage avec le type — le poste n'a pas de table
/// des espèces, exactement comme pour le code espèce des bandes (F0.14).
///
/// Ticket H9b (D-H9) — modifiable au poste comme au web, archivage logique : voir
/// [BaremeElevageSynchronisable].
class FeedTypes extends Table with BaremeElevageSynchronisable {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get name => text()();
  TextColumn get speciesId => text().nullable()();
  TextColumn get speciesCode => text().nullable()();
  TextColumn get speciesLabel => text().nullable()();

  RealColumn get standardBagWeightKg => real().nullable()();
  RealColumn get pricePerKg => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Préfixes de numérotation des bandes et des sujets — table à UNE ligne.
///
/// ⚠️⚠️ **CE SONT LES NOMS QUE LA FERME ÉCRIT SUR LES CAGES.** R1, T1,
/// LOT-VOL-1, FOSSE F1 : le registre papier, la fiche d'élevage et l'écran
/// Suivi Reproduction désignent tous le même animal par ce nom. Un poste qui
/// ignorerait ces préfixes proposerait sa propre convention, et deux registres
/// de la même ferme cesseraient de se lire ensemble.
///
/// ⚠️ **UNE SEULE LIGNE, `id = 'unique'`.** Le serveur sert un objet, pas une
/// collection : la clé fixe évite qu'un tirage n'empile des variantes.
///
/// Ticket H9b (D-H9) — les neuf formats s'enregistrent au poste comme au web (`saveNumbering()`) et partent
/// sous la clé `elevage_numbering`. ⚠️ PAS de `is_active` : la table est un singleton, jamais archivé (le
/// serveur n'en a pas non plus).
class ElevageNumberingSettings extends Table {
  TextColumn get id => text().withDefault(const Constant('unique'))();

  /// Ticket H9b — `pending` tant que l'enregistrement du poste n'est pas acquitté ; `conflict` s'il est
  /// refusé (motif dans `sync_conflicts`). Défaut `synced` : ce qui descend du serveur l'est.
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();

  /// Ticket H9b — instant de la SAISIE au poste (nul pour une ligne tirée) : seule la version partie est
  /// acquittée.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get bandeFormat => text().nullable()();
  TextColumn get lapinePrefix => text().nullable()();
  TextColumn get malePrefix => text().nullable()();
  TextColumn get truiePrefix => text().nullable()();
  TextColumn get verratPrefix => text().nullable()();
  TextColumn get porteePrefix => text().nullable()();
  TextColumn get volaillePrefix => text().nullable()();
  TextColumn get parcPrefix => text().nullable()();
  TextColumn get escargotPrefix => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Protocole prophylactique prévu, par espèce et par période.
///
/// ⚠️ RÉFÉRENTIEL ÉDITABLE, comme les rations : les grammages et les délais
/// d'attente se corrigent depuis l'écran Paramètres > Élevage. Servi sans
/// filtre `since` pour qu'un poste longtemps hors ligne ne propose pas un
/// protocole périmé — sur un sujet sanitaire, la valeur périmée est le pire cas.
///
/// Ticket H9b (D-H9) — modifiable au poste comme au web, archivage logique : voir
/// [BaremeElevageSynchronisable].
class ProphylaxisScheduleStandards extends Table
    with BaremeElevageSynchronisable {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get speciesCode => text()();
  TextColumn get periodLabel => text()();

  /// Bornes du jour de cycle, en jours depuis la date de reference de la bande.
  ///
  /// ⚠️ NULLABLES, ET C'EST LE POINT IMPORTANT. `periodLabel` est du texte
  /// libre (« Le 5e jour », « Le 1er du mois ») : le serveur a explicitement
  /// REFUSE de le convertir pour les entrees calendaires, dont la base de
  /// calcul n'est pas le jour de cycle. Ces entrees arrivent avec des bornes
  /// nulles et ne doivent JAMAIS etre presentees comme dues aujourd'hui — un
  /// jour devine a tort ferait administrer un traitement au mauvais moment.
  IntColumn get cycleDayStart => integer().nullable()();
  IntColumn get cycleDayEnd => integer().nullable()();
  TextColumn get treatment => text()();
  TextColumn get productRecommended => text().nullable()();
  TextColumn get dosage => text().nullable()();
  IntColumn get withdrawalDays => integer().withDefault(const Constant(0))();

  /// Ticket H9 — instant de création côté serveur (`created_at`), pour TRIER COMME LE WEB
  /// (`getProphylaxiesProperty` : `orderBy('created_at')`). Une échéance créée au poste prend l'instant de sa
  /// saisie ; nul pour une ligne tirée d'un serveur qui ne le sert pas.
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Période de rémanence vétérinaire — délai d'attente après traitement.
///
/// ⚠️⚠️ BLOCAGE DE SANTÉ PUBLIQUE, PAS UN CONFORT. Tant que la période court,
/// la bande ne doit RIEN vendre : la viande porterait des résidus
/// d'antibiotiques. La caisse web refuse déjà ces ventes ; le poste Desktop
/// encaisse HORS LIGNE et n'avait, avant le ticket 14.53, aucun moyen de
/// connaître l'interdiction — il l'aurait donc laissée passer.
///
/// Le serveur ne sert que les périodes ENCORE ACTIVES : une période expirée ne
/// bloque plus rien et n'a pas à encombrer le poste.
class VeterinaryWithdrawalPeriods extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get lotId => text().withLength(min: 36, max: 36)();
  TextColumn get productUsed => text().nullable()();
  DateTimeColumn get endDate => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cycle de reproduction d'une femelle NOMMÉE — R1, R2… chez les lapins,
/// T1, T2… chez les porcs.
///
/// ⚠️⚠️ **SEULE TABLE DU SYSTÈME QUI SUIVE UN ANIMAL INDIVIDUEL.** Les fiches
/// journalières ne connaissent que des agrégats de bande : ni la lapine qui a
/// mis bas, ni le verrat saillisseur n'y apparaissent. Le prototype construit
/// tout l'écran Suivi Reproduction sur cette granularité.
///
/// ⚠️ **REÇUE ET ENVOYÉE** depuis le ticket F0.35 : le poste déclare une
/// saillie hors ligne. Les lignes venues du serveur portent
/// `device_id = 'serveur'` et `sync_status = synced`, convention déjà en place
/// pour le registre vétérinaire — une ligne tirée n'a été écrite par aucun
/// poste, et ne doit jamais repartir à l'envoi.
///
/// ⚠️⚠️ **LE POSTE NE DÉCLARE QUE LA SAILLIE.** Palpation, mise bas et
/// sevrage restent web : ils CORRIGENT un cycle que le serveur a pu faire
/// évoluer entre-temps, et « dernier écrivain gagne » — acceptable pour une
/// fiche journalière qui se corrige dans la journée — ne l'est pas sur une
/// gestation de trois mois.
class LivestockReproductionEvents extends Table with SyncColumns {
  TextColumn get lotId => text().withLength(min: 36, max: 36)();

  /// Référence de la femelle telle que la ferme la nomme — « R1 », « T3 ».
  TextColumn get motherRef => text()();

  /// Référence du mâle. Nullable : une insémination n'en a pas.
  TextColumn get sireRef => text().nullable()();

  DateTimeColumn get saillieDate => dateTime().nullable()();

  /// ⚠️ `null` = palpation PAS ENCORE FAITE, et c'est ce qui rend une
  /// palpation « due » : le serveur en tire son KPI.
  DateTimeColumn get palpationDate => dateTime().nullable()();

  DateTimeColumn get miseBasDateExpected => dateTime().nullable()();
  DateTimeColumn get miseBasDateActual => dateTime().nullable()();
  DateTimeColumn get sevrageDateExpected => dateTime().nullable()();

  IntColumn get nesVivants => integer().nullable()();
  IntColumn get nesMorts => integer().nullable()();

  /// `en_cours` · `echec` · `termine`.
  TextColumn get status => text().withDefault(const Constant('en_cours'))();
}

/// Client de la ferme — référentiel servi par le serveur.
///
/// ⚠️⚠️ **SANS LUI, LA CAISSE NE PEUT NOMMER PERSONNE.** `sales.customer_id`
/// existe depuis l'origine, mais le poste n'avait aucune liste où choisir :
/// toute vente hors ligne partait anonyme, et l'historique affichait « Client
/// non synchronisé ». Descendue au ticket 14.75.
///
/// ⚠️ **LECTURE SEULE.** Comme les produits, c'est un référentiel : le serveur
/// ignore tout envoi le concernant.
class Customers extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get city => text().nullable()();

  /// Adresse e-mail (ticket F0.72) : le tirage la sert désormais, le formulaire la saisit.
  TextColumn get email => text().nullable()();

  /// Plafond de crédit accordé, en FCFA. ⚠️ Jamais saisi ni envoyé par le poste.
  RealColumn get creditLimit => real().withDefault(const Constant(0))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// ⚠️ **UNE FICHE CRÉÉE, MODIFIÉE OU ARCHIVÉE AU POSTE EST `pending` JUSQU'À
  /// L'ACQUITTEMENT** (ticket F0.72). Défaut `synced` : tout ce qui descend du serveur
  /// l'est, et les lignes d'avant la migration aussi. Le tirage ne touche JAMAIS une
  /// fiche qui ne l'est pas.
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Créance client — ce qu'une vente à crédit laisse à recouvrer.
///
/// ⚠️⚠️ **LE RESTE DÛ SE CALCULE, IL N'EST PAS STOCKÉ** : `amount -
/// amount_paid`. Afficher `amount` comme encours compterait deux fois ce qui a
/// déjà été réglé — c'est le défaut que la balance âgée du serveur a dû
/// corriger (ticket 14.5x, `AgedBalanceService`).
///
/// ⚠️ **LE SERVEUR NE DESCEND QUE CE QUI RESTE DÛ**, sans filtre `since` : une
/// facture échue il y a trois mois n'a plus bougé depuis, et c'est précisément
/// celle qu'il faut relancer.
class Receivables extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get customerId => text().withLength(min: 36, max: 36)();
  TextColumn get saleId => text().nullable()();

  RealColumn get amount => real()();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();

  /// ⚠️ **L'ÉCHÉANCE, PAS LA DATE D'ÉMISSION.** L'âge d'une créance se compte
  /// depuis son échéance : une facture émise il y a 90 jours mais payable à
  /// 120 n'est pas en retard.
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// `en_cours` · `soldee` · `en_retard`.
  TextColumn get status => text().withDefault(const Constant('en_cours'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Avance versée par un client, à imputer sur ses achats à venir.
///
/// ⚠️⚠️ **UNE AVANCE S'ÉCRIT AU POSTE DEPUIS F0.73** : `pending` jusqu'à l'acquittement
/// du serveur, qui fait entrer l'argent en trésorerie (deux livres) et passe l'écriture
/// D 5xx / C 419. Le poste n'enregistre que le FAIT : ni solde de compte ni écriture.
/// `amount_used` n'est JAMAIS écrit au poste : il vient du tirage.
class CustomerAdvances extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get customerId => text().withLength(min: 36, max: 36)();

  RealColumn get amount => real()();
  RealColumn get amountUsed => real().withDefault(const Constant(0))();

  DateTimeColumn get advanceDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Compte de trésorerie où l'argent est entré (contrat 15.19). Nul pour les avances
  /// d'avant le ticket, jamais comptabilisées.
  TextColumn get treasuryAccountId => text().nullable()();

  /// `especes` · `mobile_money` · `virement` · `cheque`.
  TextColumn get paymentMode => text().nullable()();

  TextColumn get motif => text().nullable()();

  /// Poste d'origine, tel que le serveur le conserve.
  TextColumn get deviceId => text().nullable()();

  /// ⚠️ Défaut `synced` : tout ce qui descend du serveur l'est. Le tirage ne touche
  /// JAMAIS une avance `pending` ou `conflict`.
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Imputation d'un acompte sur une créance, saisie au poste (ticket F0.73).
///
/// ⚠️⚠️ **LE POSTE N'IMPUTE RIEN** : il enregistre « tant, de cette avance, sur cette
/// créance » et ne touche NI `amount_used` de l'avance NI `amount_paid` de la créance.
/// Le serveur applique le plafond, met à jour les deux et passe D 419 / C 411.
/// Une créance se désigne par `receivable_id` OU par `sale_id` (contrat 15.19) : l'une
/// des deux est renseignée. Cette table ne descend pas du serveur.
@DataClassName('ImputationAvance')
class AdvanceImputations extends Table with SyncColumns {
  TextColumn get customerAdvanceId => text().withLength(min: 36, max: 36)();
  TextColumn get receivableId => text().nullable()();
  TextColumn get saleId => text().nullable()();
  RealColumn get amount => real()();
  DateTimeColumn get imputationDate => dateTime()();
}

/// Fournisseur de la ferme — référentiel servi par le serveur.
///
/// ⚠️⚠️ **SANS LUI, LE POSTE N'ACHÈTE RIEN HORS LIGNE.** Même dépendance que
/// les clients pour la caisse : un achat sans fournisseur est rejeté à l'envoi,
/// et l'opérateur ne comprend pas pourquoi.
class Suppliers extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get name => text()();
  TextColumn get category => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();

  /// ⚠️ **UNE FICHE CRÉÉE, MODIFIÉE OU ARCHIVÉE AU POSTE EST `pending` JUSQU'À
  /// L'ACQUITTEMENT** (ticket F0.71). Défaut `synced` : tout ce qui descend du serveur
  /// l'est, et les lignes d'avant la migration aussi. Le tirage ne touche JAMAIS une
  /// fiche qui ne l'est pas — il effacerait la saisie.
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();

  /// `false` : archivée au poste, en attente d'envoi. Le serveur ne sert que les actifs ;
  /// l'archivée disparaît donc au tirage qui suit l'acquittement.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Identité de la ferme — table à UNE ligne.
///
/// ⚠️⚠️ **AUCUN SECRET N'EST STOCKÉ ICI, ET CE N'EST PAS UN OUBLI.**
/// `company_settings` porte côté serveur les mots de passe SMTP et les jetons
/// SMS (Twilio, Vonage), chiffrés. Un poste volé donnerait accès au compte SMS
/// et à la boîte mail de la ferme : seuls l'identité et les taux descendent.
class CompanySettings extends Table {
  TextColumn get id => text().withDefault(const Constant('unique'))();

  TextColumn get companyName => text().nullable()();
  TextColumn get promoterName => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get ifu => text().nullable()();
  TextColumn get rccm => text().nullable()();
  BoolColumn get tvaEnabled => boolean().withDefault(const Constant(false))();
  RealColumn get tvaDefaultRate => real().nullable()();

  /// Ticket H9b (D-H9) — délai du rappel des soins planifiés (règle R-SOINS-01), en jours (0 à 30), servi
  /// au tirage et réglé au poste comme au web (`ParametresElevage::saveRappelSoins()`). Nul tant que rien
  /// n'a été tiré : le poste ne connaît pas le réglage de la ferme.
  IntColumn get rappelSoinsJours => integer().nullable()();

  /// Ticket H9b — ⚠️ NE PORTE QUE SUR [rappelSoinsJours], SEUL champ de l'entreprise que le poste envoie
  /// (clé `company_settings`). L'identité de la ferme reste un référentiel : le tirage la met toujours à jour.
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();

  /// Ticket H9b — instant de la saisie du délai au poste (nul pour une ligne tirée).
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Module d'espèce activé ou non par la ferme.
///
/// ⚠️⚠️ **UN MODULE DÉSACTIVÉ DOIT DISPARAÎTRE DE L'ÉCRAN, PAS SEULEMENT DE LA
/// BASE.** La maquette masque les blocs `data-module="helico"` quand
/// l'héliciculture est éteinte. Le poste, lui, ne lisait pas cette table : il
/// proposait la fiche Escargots d'une ferme qui n'élève pas d'escargots.
class ModulesConfig extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  /// `cuniculture` · `aviculture` · `porciculture` · `helico`.
  TextColumn get speciesCode => text()();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Rôle applicatif et ses permissions — référentiel.
class RolesApplicatifs extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Permissions du rôle, séparées par des virgules.
  TextColumn get permissions => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Utilisateur de la ferme — référentiel.
///
/// ⚠️ **NI MOT DE PASSE NI JETON** : la liste sert à savoir QUI travaille sur
/// la ferme, jamais à s'authentifier. L'authentification du poste passe par
/// `POST /api/auth/login`.
class Utilisateurs extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get name => text()();
  TextColumn get username => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get role => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ligne du journal d'audit — les deux cents dernières actions de la ferme (U14 : la liste du web).
class AuditLogs extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get userName => text().nullable()();
  TextColumn get action => text()();
  TextColumn get module => text().nullable()();
  TextColumn get ipAddress => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Notification adressée à l'utilisateur du poste — référentiel remplacé à
/// chaque tirage (ticket F0.59).
///
/// ⚠️ **CLASSE DE LIGNE `NotificationPoste`, PAS `Notification`** : Flutter
/// porte déjà un `Notification` (`widgets.dart`), et Drift aurait généré le
/// même nom — l'un des deux masquerait l'autre selon l'import.
///
/// ⚠️ **LA CATÉGORIE EST CELLE DU SERVEUR**, calculée par son modèle : la
/// recalculer ici ferait diverger deux tables au premier type ajouté.
@DataClassName('NotificationPoste')
class Notifications extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get type => text()();
  TextColumn get category => text().withDefault(const Constant('Système'))();
  TextColumn get severity => text().withDefault(const Constant('info'))();
  TextColumn get title => text()();
  TextColumn get message => text()();
  TextColumn get linkUrl => text().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Revenu d'une bande par produit vendu — référentiel remplacé à chaque tirage
/// (ticket F0.63).
///
/// ⚠️⚠️ **CALCULÉ PAR LE SERVEUR, PAS RECALCULÉ ICI.** Le tirage ne sert des
/// ventes serveur que leur EN-TÊTE, sans lignes : le poste ne sait pas quelle
/// bande a vendu quoi, et un revenu recalculé sur `sale_lines` ne compterait que
/// les ventes faites sur CE poste. Le montant est celui de
/// `LotRevenueService` — ventes validées, nettes des avoirs traités — le même
/// que la page web.
class LotRevenues extends Table {
  TextColumn get lotId => text().withLength(min: 36, max: 36)();
  TextColumn get productId => text().withLength(min: 36, max: 36)();
  TextColumn get label => text()();
  RealColumn get amount => real()();

  @override
  Set<Column> get primaryKey => {lotId, productId};
}

/// Modèle d'attestation (travail ou stage) — référentiel remplacé à chaque tirage
/// (ticket F0.64).
///
/// ⚠️ **DEUX LIGNES, `employe` ET `stagiaire`**, toujours servies : le serveur crée
/// le modèle par défaut s'il manque. Le texte porte des BALISES (`[NOM]`,
/// `[POSTE]`, `[CONTRAT]`, `[SPECIALITE]`, `[ETABLISSEMENT]`, `[DATE_DEBUT]`,
/// `[DATE_FIN]`) que l'aperçu remplace comme le fait le serveur.
///
/// ⚠️ **ÉDITABLE UNIQUEMENT EN LIGNE, PAR LE SERVEUR** : un modèle est un
/// référentiel, tout envoi par `/sync/push` serait ignoré. L'enregistrement passe
/// par `PUT /api/attestation-templates/{type}` ; la ligne locale n'est mise à jour
/// qu'après sa confirmation.
class AttestationTemplates extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get type => text()();
  TextColumn get bodyText => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Sujet suivi INDIVIDUELLEMENT (reproducteur) — référentiel remplacé à chaque
/// tirage (ticket F0.65).
///
/// ⚠️ **SEULS LES REPRODUCTEURS SONT SUIVIS SUJET PAR SUJET** (arbitrage client du
/// ticket Laravel 14.16) : un lot d'engraissement reste une quantité. Cette table
/// ne remplace donc pas `livestock_lots`, elle le complète.
///
/// ⚠️ **LES SORTIS Y SONT AUSSI** (`status` ≠ `actif`, `is_active` faux) : la fiche
/// d'un animal vendu ou mort reste consultable, c'est son historique.
///
/// ⚠️ **L'ESPÈCE ET LA BANDE VIENNENT SOUS FORME DE LIBELLÉ** (`speciesLabel`,
/// `lotCode`) : le poste n'a pas de table des espèces, et la bande peut ne pas lui
/// avoir été descendue.
///
/// ⚠️ **LE LIEN AVEC LA REPRODUCTION EST UN IDENTIFIANT TEXTE** : les événements
/// portent `motherRef` / `sireRef` en texte libre depuis l'origine, et c'est par
/// correspondance sur [identifier] qu'on retrouve ceux d'un sujet — jamais par une
/// clé étrangère, qui aurait laissé orphelins tous les événements déjà saisis.
@DataClassName('Sujet')
class Animals extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get identifier => text()();
  TextColumn get speciesLabel => text().nullable()();
  TextColumn get lotId => text().nullable()();
  TextColumn get lotCode => text().nullable()();
  TextColumn get category =>
      text().withDefault(const Constant('reproducteur'))();

  /// `F` ou `M`.
  TextColumn get sex => text().withDefault(const Constant('F'))();
  TextColumn get breed => text().nullable()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  DateTimeColumn get entryDate => dateTime().nullable()();
  TextColumn get origin => text().nullable()();
  TextColumn get cage => text().nullable()();

  /// `actif`, `vendu`, `mort`, `reforme`…
  TextColumn get status => text().withDefault(const Constant('actif'))();
  DateTimeColumn get exitDate => dateTime().nullable()();
  TextColumn get exitReason => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Ticket BS3 (v51) — l'identifiant de l'ESPÈCE du sujet (le serveur le sert depuis BS3) : le poste écrit désormais un
  /// sujet nominatif et l'envoie avec `species_id`. `null` : sujet reçu d'un serveur antérieur.
  TextColumn get speciesId => text().nullable()();

  /// ⚠️ **UN SUJET ENREGISTRÉ, MODIFIÉ OU SORTI AU POSTE EST `pending` JUSQU'À L'ACQUITTEMENT** (ticket BS3, v51). Défaut
  /// `synced` : tout ce qui descend du serveur l'est. Le tirage ne touche JAMAIS un sujet qui ne l'est pas
  /// (`_absorberSujets`).
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();

  /// Ticket BS3 (v51) — instant de la dernière saisie au poste : l'accusé de réception n'acquitte que la VERSION partie.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Compte du plan SYSCOHADA — référentiel servi par le serveur.
///
/// ⚠️ Sans lui, une ligne d'écriture n'a qu'un UUID à montrer : ni numéro de
/// compte, ni intitulé, ni classe.
class ChartOfAccounts extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get code => text()();
  TextColumn get label => text()();

  /// Classe SYSCOHADA — 1 à 9 (la classe 9, comptabilité analytique, figure au plan officiel).
  IntColumn get accountClass => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Exercice comptable — référentiel.
///
/// ⚠️⚠️ **LA CLÔTURE NE SE SYNCHRONISE JAMAIS** : elle est explicitement hors
/// du contrat de synchronisation (docblock de `SyncController`). Le poste
/// AFFICHE l'état de l'exercice, il ne le change pas.
class FiscalYears extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  IntColumn get year => integer()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();

  /// `ouvert` · `cloture`.
  TextColumn get status => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Écriture comptable — l'en-tête d'une pièce du journal.
///
/// ⚠️⚠️ **LES ÉTATS LISENT LE JOURNAL, JAMAIS DES TABLES MÉTIER DISJOINTES.**
/// C'est la règle du projet depuis l'origine : un Grand Livre ou une Balance
/// recomposés à partir des ventes et des achats donneraient deux comptabilités
/// différentes pour la même ferme. Pour que le poste puisse afficher ces états,
/// il lui faut donc le journal lui-même — pas des agrégats préparés.
///
/// ⚠️ **LECTURE SEULE ABSOLUE.** Une écriture naît d'une opération (vente,
/// achat, dépense, ponte, écart d'inventaire), jamais d'une saisie au poste :
/// c'est ce qui garantit qu'aucun mouvement ne pèse sur les comptes sans avoir
/// pesé sur le stock ou la caisse.
class AccountingEntries extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get fiscalYearId => text().nullable()();
  DateTimeColumn get entryDate => dateTime()();
  TextColumn get reference => text().nullable()();

  /// `sale` · `purchase` · `expense` · `stock_adjustment` · `opening_balance`…
  TextColumn get sourceType => text().nullable()();
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();

  /// Instant de CRÉATION de l'écriture, tel que le serveur le sert (ticket F0.85 / 15.29).
  ///
  /// ⚠️ Il ne sert qu'à DÉPARTAGER deux pièces du même jour au Grand Livre, comme
  /// `orderBy(entry_date)->orderBy(created_at)` côté serveur. `NULL` = inconnu (écriture reçue d'un
  /// serveur qui ne le sert pas encore, ou avant la mise à jour du poste) — jamais « maintenant ».
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ligne d'écriture — un débit OU un crédit sur un compte.
///
/// ⚠️⚠️ **`SUM(debit) = SUM(credit)` PAR ÉCRITURE**, garanti par le serveur
/// avant comptabilisation. Le poste peut donc le VÉRIFIER : une écriture
/// déséquilibrée à l'écran signalerait un tirage incomplet, pas une erreur de
/// saisie.
class AccountingEntryLines extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get entryId => text().withLength(min: 36, max: 36)();
  TextColumn get accountId => text().withLength(min: 36, max: 36)();
  TextColumn get costCenterId => text().nullable()();
  RealColumn get debit => real().withDefault(const Constant(0))();
  RealColumn get credit => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Courrier reçu ou envoyé — saisi au poste, validé par le serveur (ticket F0.78).
///
/// ⚠️ **LA RÉFÉRENCE `CR-AAAA-NNN` N'EST JAMAIS INVENTÉE PAR LE POSTE** : le serveur
/// l'attribue (numéro atomique). `NULL` tant que le courrier n'est pas acquitté, puis
/// elle descend au tirage. Ni statut de courrier ni pièce jointe n'existent en base.
class Mails extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get reference => text().nullable()();

  /// `entrant` · `sortant`.
  TextColumn get type => text()();
  TextColumn get subject => text()();

  /// Expéditeur si le courrier est entrant, destinataire s'il est sortant.
  TextColumn get party => text().nullable()();
  DateTimeColumn get mailDate => dateTime().nullable()();

  /// `false` = archivé (rien n'est supprimé côté serveur). La liste ne montre que les actifs.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// ⚠️ **UN COURRIER ÉCRIT, MODIFIÉ OU ARCHIVÉ AU POSTE EST `pending` JUSQU'À
  /// L'ACQUITTEMENT** (ticket F0.78). Défaut `synced` : tout ce qui descend du serveur
  /// l'est, et les lignes d'avant la migration aussi. Le tirage ne touche JAMAIS une
  /// ligne qui ne l'est pas.
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();

  /// ⚠️⚠️ **LE SERVEUR A-T-IL DÉJÀ ACCEPTÉ CE COURRIER ?** (ticket F0.78-bis). Faux dès la
  /// création au poste, vrai à l'acquittement (ou si la ligne vient du tirage). C'est le SEUL
  /// signal fiable : `reference IS NULL` ne distingue pas « jamais envoyé » de « accepté
  /// mais référence pas encore descendue » (tirage de confirmation tombé en panne). Archiver
  /// un courrier que le serveur ne connaît pas enverrait `{id, is_active:false}` et
  /// recevrait « Courrier inconnu » pour toujours.
  BoolColumn get knownByServer => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Document administratif — registre saisi, modifié et retiré au poste depuis le ticket F0.80.
///
/// ⚠️ **AUCUN FICHIER N'EST GÉNÉRÉ** : c'est une ligne de registre (titre, type, bénéficiaire,
/// date, statut), comme sur la page web. Ni l'en-tête officielle, ni la signature, ni le
/// cachet n'existent au poste.
class AdministrativeDocuments extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get title => text()();

  /// Texte libre côté serveur (colonne `string(100)`).
  TextColumn get type => text().nullable()();
  TextColumn get beneficiary => text().nullable()();
  DateTimeColumn get docDate => dateTime().nullable()();

  /// `signe` · `en_attente`.
  TextColumn get status => text().nullable()();

  /// `false` = retiré du registre (rien n'est supprimé côté serveur). La liste ne montre que
  /// les actifs.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// ⚠️ **UN DOCUMENT ÉCRIT, MODIFIÉ OU RETIRÉ AU POSTE EST `pending` JUSQU'À
  /// L'ACQUITTEMENT** (ticket F0.80). Défaut `synced` : tout ce qui descend du serveur
  /// l'est, et les lignes d'avant la migration aussi. Le tirage ne touche JAMAIS une
  /// ligne qui ne l'est pas.
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();

  /// ⚠️⚠️ **LE SERVEUR A-T-IL DÉJÀ ACCEPTÉ CE DOCUMENT ?** (même signal que `mails` et
  /// `archived_documents`, F0.78-bis). Faux dès la création au poste, vrai à l'acquittement
  /// (ou si la ligne vient du tirage). Retirer un document que le serveur ne connaît pas
  /// enverrait `{id, is_active:false}` et recevrait « Document inconnu » pour toujours, sur
  /// une ligne masquée.
  BoolColumn get knownByServer => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Document archivé — saisi, modifié et retiré au poste depuis le ticket F0.79.
///
/// ⚠️ `expiryDate` porte l'échéance d'un agrément ou d'un contrat : c'est la
/// seule colonne de cette table qui se périme, et l'écran la colore.
///
/// ⚠️ **AUCUN STATUT N'EST STOCKÉ** (ni ici ni sur le serveur) : « Valide / Bientôt expiré /
/// Expiré » se déduit de `expiryDate` par `AdministrationRepository.statutArchive`.
class ArchivedDocuments extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get title => text()();
  TextColumn get category => text().nullable()();
  DateTimeColumn get archivedDate => dateTime().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();

  /// `false` = retiré des archives (rien n'est supprimé côté serveur). La liste ne montre
  /// que les actifs.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// ⚠️ **UN DOCUMENT ÉCRIT, MODIFIÉ OU RETIRÉ AU POSTE EST `pending` JUSQU'À
  /// L'ACQUITTEMENT** (ticket F0.79). Défaut `synced` : tout ce qui descend du serveur
  /// l'est, et les lignes d'avant la migration aussi. Le tirage ne touche JAMAIS une
  /// ligne qui ne l'est pas.
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('synced'))();

  /// ⚠️⚠️ **LE SERVEUR A-T-IL DÉJÀ ACCEPTÉ CE DOCUMENT ?** (même signal que `mails`,
  /// F0.78-bis). Faux dès la création au poste, vrai à l'acquittement (ou si la ligne vient
  /// du tirage). Retirer un document que le serveur ne connaît pas enverrait
  /// `{id, is_active:false}` et recevrait « Document inconnu » pour toujours, sur une ligne
  /// masquée.
  BoolColumn get knownByServer => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Employé de la ferme — référentiel servi par le serveur.
///
/// ⚠️⚠️ **SANS LUI, IL N'Y A PERSONNE À POINTER.** Le pointage est l'acte de
/// terrain par excellence : il se fait à 7 h à la ferme, là où le réseau n'est
/// pas.
class Employees extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  TextColumn get position => text().nullable()();
  RealColumn get baseSalary => real().nullable()();
  DateTimeColumn get hireDate => dateTime().nullable()();

  /// `actif` · `conge` · `suspendu`.
  TextColumn get status => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Stagiaire accueilli par la ferme — référentiel servi par le serveur.
///
/// ⚠️ **UN STAGIAIRE N'EST PAS UN EMPLOYÉ** : la table est autonome, sans
/// relation vers `employees`. C'est aussi pourquoi la feuille de pointage ne
/// le couvre pas — ses absences vivent dans `internship_absences`, que le
/// poste ne reçoit pas.
class Internships extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  TextColumn get school => text().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  RealColumn get monthlyFee => real().nullable()();
  BoolColumn get feePaid => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Dette fournisseur — ce qu'un achat à crédit laisse à régler.
///
/// ⚠️⚠️ **LE RESTE DÛ SE CALCULE** : `amount − amount_paid`. Afficher `amount`
/// comme montant dû compterait une seconde fois ce qui a déjà été réglé —
/// même piège que les créances clients (ticket 14.75).
///
/// ⚠️ **LE SERVEUR NE DESCEND QUE CE QUI RESTE DÛ**, sans filtre `since` : une
/// dette échue il y a trois mois n'a plus bougé, et c'est celle que le
/// fournisseur va réclamer. La table étant remplacée à chaque tirage, une
/// dette soldée entre-temps en disparaît proprement.
class Payables extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get supplierId => text().withLength(min: 36, max: 36)();
  TextColumn get supplierName => text().nullable()();
  TextColumn get purchaseId => text().nullable()();

  RealColumn get amount => real()();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();

  DateTimeColumn get dueDate => dateTime().nullable()();

  /// `en_cours` · `soldee` · `en_retard`.
  TextColumn get status => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Bon de commande — référentiel en lecture seule au poste.
///
/// ⚠️ **LE MONTANT ESTIMÉ EST CALCULÉ PAR LE SERVEUR**, sur les lignes du bon
/// (`estimated_unit_price`, pas `unit_price` — la commande n'est pas livrée).
/// Le recomposer ici ferait afficher deux estimations pour un même bon.
class PurchaseOrders extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get supplierId => text().nullable()();
  TextColumn get supplierName => text().nullable()();
  DateTimeColumn get expectedDeliveryDate => dateTime().nullable()();

  /// `brouillon` · `envoye` · `recu` · `annule`.
  TextColumn get status => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  RealColumn get estimatedTotal => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Relance déjà envoyée à un client sur une créance.
///
/// ⚠️⚠️ **SANS ELLE, LE POSTE RELANCE DEUX FOIS.** La table vit côté serveur —
/// l'écran web `RelancesClients` l'alimente à chaque envoi WhatsApp, mail ou
/// SMS. Un poste qui l'ignore affiche une file de relance où rien ne distingue
/// le débiteur contacté ce matin de celui que personne n'a jamais appelé.
///
/// ⚠️ **LECTURE SEULE, ET CE N'EST PAS UN OUBLI.** Envoyer une relance suppose
/// le réseau ET le canal mail du serveur (`CustomerReminderMail`) : un envoi
/// tenté depuis le poste hors ligne ne serait enregistré nulle part, et le
/// client serait rappelé une seconde fois le lendemain.
class CustomerReminders extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get customerId => text().withLength(min: 36, max: 36)();
  TextColumn get receivableId => text().nullable()();

  /// `whatsapp` · `email` · `sms` · `courrier`.
  TextColumn get channel => text()();

  DateTimeColumn get reminderDate => dateTime().nullable()();
  TextColumn get message => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ═══════════════════════════════════════════════════════════════════════════
//  TABLES SYNCHRONISABLES — SAISIES LOCALEMENT, POUSSÉES AU SERVEUR
// ═══════════════════════════════════════════════════════════════════════════

/// Ticket 15.46 (schéma v39) — TRANSFERT DE SUJETS ENTRE DEUX BANDES, miroir de `livestock_transfers`.
///
/// Source de vérité des colonnes `transfert_*` des fiches. Créé ou annulé au poste (`pending`), le serveur le
/// REJOUE avec ses propres contrôles d'effectif ; jamais supprimé, annulé (`isActive = false`).
/// `constitution` : la bande cible a été créée avec ces sujets (seule la sortie de la source est inscrite).
class LivestockTransfers extends Table with SyncColumns {
  TextColumn get sourceLotId => text().withLength(min: 36, max: 36)();
  TextColumn get targetLotId => text().withLength(min: 36, max: 36)();
  DateTimeColumn get transferDate => dateTime()();
  IntColumn get quantity => integer()();

  /// `repro` | `sevre` | `jeune` pour lapins et porcs ; null pour les autres espèces.
  TextColumn get categorie => text().nullable()();
  BoolColumn get constitution => boolean().withDefault(const Constant(false))();
  TextColumn get motif => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Fiche journalière d'élevage. Règle serveur : **dernier écrivain gagne**,
/// upsert sur l'UUID client.
///
/// ⚠️ L'UNICITÉ `(lotId, entryDate)` EST INDISPENSABLE. Une fiche se corrige
/// dans la journée : sans cette contrainte, chaque enregistrement créerait une
/// ligne de plus et l'effectif du jour serait compté autant de fois que
/// l'éleveur a sauvegardé.
class LivestockDailyEntries extends Table with SyncColumns {
  TextColumn get lotId => text().withLength(min: 36, max: 36)();
  DateTimeColumn get entryDate => dateTime()();

  IntColumn get achat => integer().withDefault(const Constant(0))();
  IntColumn get ne => integer().withDefault(const Constant(0))();
  IntColumn get mort => integer().withDefault(const Constant(0))();
  IntColumn get vente => integer().withDefault(const Constant(0))();
  IntColumn get don => integer().withDefault(const Constant(0))();
  IntColumn get effectifFinal => integer().withDefault(const Constant(0))();

  IntColumn get ponteTotal => integer().nullable()();
  IntColumn get ponteCasses => integer().nullable()();
  RealColumn get feedQtyKg => real().nullable()();
  RealColumn get weightSampleAvgG => real().nullable()();

  // ── Ticket F0.95 (schéma v38) — EFFECTIF PAR CATÉGORIE, colonnes du serveur (15.39, 14.11, 3.x) ──
  //
  // ⚠️⚠️ TOUTES NULLABLES, SANS DÉFAUT : `null` = « non ventilé / inconnu », JAMAIS 0 (un 0 dirait
  // « rien ne s'est passé dans cette catégorie »). Types : `unsignedInteger` nullable au serveur.
  // Emplacements génériques : `repro` = Reproducteur ; `sevre` = Sous-mères (lapins) / Porcelet (porcs) ;
  // `jeune` = Jeune (lapins) / Porc Marchand (porcs) — glossaire du 17/10/2026.

  /// Morts et dons PAR CATÉGORIE (saisis). Le total `mort` / `don` doit en être la somme.
  IntColumn get mortRepro => integer().nullable()();
  IntColumn get mortSevre => integer().nullable()();
  IntColumn get mortJeune => integer().nullable()();
  IntColumn get donRepro => integer().nullable()();
  IntColumn get donSevre => integer().nullable()();
  IntColumn get donJeune => integer().nullable()();

  /// Passage de stade (QC3/D3) : un FAIT saisi, transfert Jeune → Chair / Porcelet → Marchand.
  IntColumn get passageSevreJeune => integer().nullable()();

  /// Effectif de départ (D4), sur la SEULE fiche tête de chaîne : effectif au DÉBUT du jour.
  IntColumn get catDepartRepro => integer().nullable()();
  IntColumn get catDepartSevre => integer().nullable()();
  IntColumn get catDepartJeune => integer().nullable()();

  /// Effectifs par catégorie DÉRIVÉS (fin de journée), comme `effectif_final` : le serveur les
  /// recalcule sur une bande à chaîne, le poste ne les ENVOIE JAMAIS.
  IntColumn get catEffRepro => integer().nullable()();
  IntColumn get catEffSevre => integer().nullable()();
  IntColumn get catEffJeune => integer().nullable()();

  /// Quatrième catégorie (pondeuses, ticket 14.11) — reçue du serveur, jamais envoyée.
  /// ⚠️ Nom explicite : la conversion automatique de `catEff4` donnerait `cat_eff4`.
  IntColumn get catEff4 => integer().named('cat_eff_4').nullable()();

  /// Ventilation par sexe et par état (QC5 : SAISIS) — décision D16 : portés dès la v38.
  IntColumn get effectifM => integer().nullable()();
  IntColumn get effectifF => integer().nullable()();
  IntColumn get effectifSevres => integer().nullable()();
  IntColumn get effectifSmeres => integer().nullable()();

  // ── Ticket U10 (schéma v45) — colonnes du Tableau 2 et de « CA Ventes du Lot » du Rapport Élevage ──
  //
  // REÇUES du serveur, JAMAIS envoyées : le poste ne les saisit pas (`fill()` du serveur ne réécrit que les clés
  // reçues, elles y restent intactes). Toutes nullables : `null` = « le serveur n'en a pas » (le web affiche alors
  // « — », « RAS » ou « 0 », comme son Blade).

  /// `vente_sexe` : M, F ou Mixte.
  TextColumn get venteSexe => text().nullable()();

  /// `vente_montant` (FCFA), posé par la vente qui touche la fiche (`RecordSaleOnFicheElevageAction`).
  RealColumn get venteMontant => real().nullable()();

  /// `treatment_product_id` : produit du traitement administré (nom lu dans `products`).
  TextColumn get treatmentProductId => text().nullable()();

  TextColumn get treatmentDose => text().nullable()();
  TextColumn get symptomes => text().nullable()();

  // ── Ticket 15.46 (schéma v39) — TRANSFERTS ENTRE BANDES, DÉRIVÉS de `LivestockTransfers` ──
  //
  // Comme `effectif_final` : jamais saisis dans la fiche, jamais envoyés au serveur (il les recalcule).
  // NOT NULL à 0 : une fiche sans transfert garde exactement son effectif.
  IntColumn get transfertEntree => integer().withDefault(const Constant(0))();
  IntColumn get transfertSortie => integer().withDefault(const Constant(0))();
  IntColumn get transfertEntreeRepro =>
      integer().withDefault(const Constant(0))();
  IntColumn get transfertEntreeSevre =>
      integer().withDefault(const Constant(0))();
  IntColumn get transfertEntreeJeune =>
      integer().withDefault(const Constant(0))();
  IntColumn get transfertSortieRepro =>
      integer().withDefault(const Constant(0))();
  IntColumn get transfertSortieSevre =>
      integer().withDefault(const Constant(0))();
  IntColumn get transfertSortieJeune =>
      integer().withDefault(const Constant(0))();

  @override
  List<String> get customConstraints => ['UNIQUE (lot_id, entry_date)'];
}

/// Vente encaissée. Règle serveur : **jamais de mise à jour** — une vente
/// validée ne se modifie pas après coup, seul un avoir la corrige.
///
/// ⚠️ Un push répété de la même vente (coupure réseau au moment de la réponse)
/// est traité par le serveur comme un succès silencieux, pas comme une erreur.
/// Le client peut donc renvoyer sans risque ce dont il n'a pas eu l'accusé.
class Sales extends Table with SyncColumns {
  TextColumn get customerId => text().nullable()();
  TextColumn get paymentMode => text()();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
  RealColumn get cashReceived => real().nullable()();
  RealColumn get changeDue => real().nullable()();
  TextColumn get status => text().withDefault(const Constant('validee'))();
  DateTimeColumn get soldAt => dateTime()();

  /// Nom du client, servi AVEC la facture par le tirage.
  ///
  /// ⚠️ Le poste a bien la table `customers`, mais une vente au comptant n'a
  /// pas de client, et la vente d'un client archivé doit rester nommée.
  TextColumn get customerName => text().nullable()();

  /// ⚠️⚠️ **LA NORMALISATION FISCALE — `transmise` · `en_attente` · `erreur`.**
  /// Une facture EST une vente : il n'existe pas de table `invoices`. Ce statut
  /// dit si la DGI (dispositif MeCeF) a reçu la facture. NUL signifie « jamais
  /// transmise » — c'était le cas de TOUTE vente encaissée hors ligne avant le
  /// ticket 14.80, le canal d'envoi appliquant les quatre effets métier et
  /// oubliant le cinquième.
  TextColumn get mecefStatus => text().nullable()();

  /// Référence portée par le QR de la facture normalisée (NIM + signature).
  TextColumn get mecefQrRef => text().nullable()();
}

/// Achat saisi au poste, ou reçu du serveur.
///
/// ⚠️⚠️ **UN ACHAT PORTE CINQ EFFETS, ET AUCUN N'EST APPLIQUÉ ICI.** Pièce et
/// lignes, entrée en stock, décaissement, dette fournisseur, écriture
/// SYSCOHADA : tout est rejoué par le SERVEUR à la réception
/// (`RecordPurchaseAction`). Le poste enregistre l'intention et la pousse —
/// recalculer un PMP localement ferait diverger deux valorisations.
///
/// ⚠️ **CRÉATION SEULEMENT.** Le serveur refuse toute mise à jour d'un achat
/// déjà reçu : défaire cinq effets n'est possible nulle part.
class Purchases extends Table with SyncColumns {
  TextColumn get supplierId => text().withLength(min: 36, max: 36)();

  /// Nom et catégorie servis avec l'achat : le poste doit afficher la liste
  /// même si le fournisseur a été archivé depuis.
  TextColumn get supplierName => text().nullable()();
  TextColumn get supplierCategory => text().nullable()();

  TextColumn get paymentMode => text()();
  TextColumn get treasuryAccountId => text().nullable()();
  RealColumn get total => real()();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();

  /// ⚠️ Calculé par le SERVEUR pour les achats reçus, jamais au poste : deux
  /// règles de statut donneraient deux listes pour la même ferme.
  BoolColumn get hasDebt => boolean().withDefault(const Constant(false))();

  DateTimeColumn get purchaseDate => dateTime()();

  /// Instant où le SERVEUR a retourné l'achat (`returned_at`), nul sinon (ticket F0.74).
  /// ⚠️ Jamais écrit au poste : il vient du tirage. Un retour demandé ici mais pas encore
  /// appliqué vit dans `purchase_returns`.
  DateTimeColumn get returnedAt => dateTime().nullable()();

  /// Part déjà payée devenue créance sur le fournisseur (`supplier_credit`, compte 409).
  /// Nulle tant que le serveur ne l'a pas servie : le poste ne la calcule pas.
  RealColumn get supplierCredit => real().nullable()();
}

/// Pointage d'un employé, saisi au poste ou reçu du serveur.
///
/// ⚠️⚠️ **L'IDENTITÉ D'UN POINTAGE N'EST PAS SON UUID, C'EST LE COUPLE
/// (EMPLOYÉ, JOUR).** Le serveur porte `unique(employee_id, attendance_date)`
/// depuis le ticket 8.1 : un employé n'a qu'un pointage par jour. À la
/// réception, le serveur cherche donc par ce couple et complète s'il existe —
/// un simple `insert` échouerait dès que le web a déjà pointé la même personne
/// le même matin, et le poste rejouerait indéfiniment un envoi rejeté.
///
/// ⚠️ **LE JOUR EST UNE DATE, PAS UN INSTANT.** Le serveur le sert en
/// « Y-m-d » précisément pour qu'aucun décalage horaire ne fasse pointer la
/// veille.
class AttendanceRecords extends Table with SyncColumns {
  TextColumn get employeeId => text().withLength(min: 36, max: 36)();
  DateTimeColumn get attendanceDate => dateTime()();

  /// Heures au format « HH:mm:ss », telles que le serveur les sert.
  TextColumn get checkIn => text().nullable()();
  TextColumn get checkOut => text().nullable()();

  /// `present` · `absent` · `conge` · `maladie` · `retard`.
  TextColumn get status => text()();
}

class PurchaseLines extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get purchaseId => text().withLength(min: 36, max: 36)();
  TextColumn get productId => text().withLength(min: 36, max: 36)();
  TextColumn get productName => text().nullable()();
  RealColumn get qty => real()();
  RealColumn get unitPrice => real()();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleLines extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get saleId => text().withLength(min: 36, max: 36)();
  TextColumn get productId => text().withLength(min: 36, max: 36)();

  /// ⚠️ Bande d'origine du sujet vendu. Renseignée par la caisse pour tout
  /// produit lié à une espèce — c'est ce qui permet d'imputer le revenu à la
  /// bande réellement vendue plutôt qu'à une répartition inventée.
  TextColumn get lotId => text().nullable()();

  RealColumn get qty => real()();
  RealColumn get unitPrice => real()();

  /// Source de vérité du montant de la ligne : le prix unitaire n'est qu'un
  /// affichage reconstitué, jamais l'inverse.
  RealColumn get manualTotalAmount => real()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Retour d'une vente et son avoir (`credit_notes`) — écran « Retours et Avoirs » (tickets AV1 / AV2).
///
/// ⚠️⚠️ **LE POSTE ENREGISTRE LA DEMANDE, PAS SES EFFETS** (même motif que le retour fournisseur F0.74, [PurchaseReturns]) :
/// « ce produit, de cette vente, cette quantité, ce motif, réintégré ou réformé, pour ce montant, ce jour ». Le serveur
/// attribue le numéro `AV-AAAA-NNN`, réintègre le stock (décision « réintégré »), passe l'écriture inverse 701 / 443 / 411
/// et la date de ce JOUR (`created_at` ci-dessous est le jour du FAIT). Il peut refuser : vente inconnue ou annulée,
/// produit absent de la vente, quantité au-delà de « vendu − déjà retourné », montant au-delà de « ligne − déjà crédité »,
/// exercice clos, plan comptable incomplet. Son motif est gardé tel quel (`sync_conflicts`).
///
/// ⚠️ **JAMAIS d'ajustement de stock ni d'écriture au poste pour un avoir** : le serveur le fait, en une transaction, par
/// `AvoirClientService` (le point de passage de `RetoursAvoirs::saveReturn()` du web).
///
/// TABLE MIXTE : une ligne `pending` / `conflict` saisie ICI n'est jamais écrasée par le tirage ; les avoirs du web et des
/// autres postes descendent (`device_id` = `serveur`, `synced`) et remplacent les lignes acquittées. « Marquer comme
/// traité » est aussi une demande : le statut passe à `traite`, la ligne repart `pending`, le serveur la marque une fois.
/// `credit_note_number` est NUL tant que le serveur ne l'a pas attribué (la demande n'a pas de numéro avant l'envoi).
/// `accounting_entry_id` ne descend pas : le poste ne tient pas la comptabilité d'un avoir.
@DataClassName('AvoirClient')
class CreditNotes extends Table with SyncColumns {
  TextColumn get saleId => text().withLength(min: 36, max: 36)();
  TextColumn get productId => text().withLength(min: 36, max: 36)();

  /// `AV-AAAA-NNN`, attribué par le serveur seul. `null` : demande pas encore reçue.
  TextColumn get creditNoteNumber => text().nullable()();

  /// Quantité retournée (nulle en base web pour un avoir sans produit : jamais saisie ainsi).
  RealColumn get qty => real().nullable()();
  RealColumn get amount => real()();
  TextColumn get reason => text().nullable()();

  /// `reintegre` · `reforme`.
  TextColumn get decision => text().nullable()();
  TextColumn get inspectionNotes => text().nullable()();

  /// `en_attente` · `traite`.
  TextColumn get status => text().withDefault(const Constant('en_attente'))();

  /// Le JOUR DU FAIT (heure du Bénin), pas celui de l'envoi : l'écriture inverse et le stock en portent la date.
  DateTimeColumn get createdAt => dateTime()();
}

/// Soin vétérinaire administré, saisi au poste ou reçu du serveur.
///
/// ⚠️ `withdrawalDays` N'EST PAS UNE COLONNE DU REGISTRE CÔTÉ SERVEUR : c'est
/// l'INSTRUCTION qui déclenche la création de la période de rémanence. Elle est
/// conservée localement uniquement pour être transmise à l'envoi — le serveur
/// la consomme puis la jette. La confondre avec une donnée du soin ferait
/// croire qu'un registre reçu du serveur porte encore son délai.
class VeterinaryRecords extends Table with SyncColumns {
  TextColumn get lotId => text().withLength(min: 36, max: 36)();
  TextColumn get actionType => text()();
  TextColumn get productUsed => text().nullable()();
  TextColumn get dose => text().nullable()();
  TextColumn get vetName => text().nullable()();
  TextColumn get symptomes => text().nullable()();
  RealColumn get cost => real().nullable()();
  DateTimeColumn get recordDate => dateTime()();
  IntColumn get withdrawalDays => integer().withDefault(const Constant(0))();

  /// Ticket U3 (décision client D-U3 du 19/10/2026) — ARCHIVAGE LOGIQUE, au poste comme au web
  /// (`SoinsVaccinsHub::archiveSoin()`). Un soin archivé (`false`) quitte le registre et tout calcul (KPI,
  /// Dashboard Élevage, Bilan, protocole du jour, recherche) ; la ligne reste, et la rémanence qu'il a créée
  /// reste en vigueur, exactement comme au web. Servi au tirage, envoyé (`pending`) à l'archivage.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Ticket H8b (décision client D-H8 du 19/10/2026) — ENTRÉE D'INFIRMERIE (`infirmary_records` du serveur),
/// saisie au poste comme au web (`SoinsVaccinsHub::saveInfirmaryEntry()`, `reintegrer()`, `declarerDeces()`).
///
/// ⚠️ Reçue ET envoyée. Le serveur (`SyncController::pushInfirmerie`) crée l'entrée inconnue, puis ne change
/// plus que le `status` d'une entrée connue (dernier écrivain gagne) : bande, motif et date d'entrée sont figés.
/// Ticket U6 (décision client D-U6 du 19/10/2026) — `entry_date` peut être FUTURE, comme au web
/// (`saveInfirmaryEntry()` : `required|date`) ; l'envoi l'accepte aussi.
class InfirmaryRecords extends Table with SyncColumns {
  TextColumn get lotId => text().withLength(min: 36, max: 36)();

  /// Sujet isolé (« #A-204 ») — optionnel : l'entrée peut viser la bande entière.
  TextColumn get sujetRef => text().nullable()();
  TextColumn get motif => text()();

  /// `Quarantaine stricte` | `Infirmerie` | `Simple surveillance` (nullable au serveur).
  TextColumn get isolationLevel => text().nullable()();
  DateTimeColumn get entryDate => dateTime()();

  /// `en_cours` | `reintegre` | `deces` (enum du serveur).
  TextColumn get status => text().withDefault(const Constant('en_cours'))();
}

/// Ticket H8b (D-H8) — INTERVENTION PLANIFIÉE du calendrier vétérinaire (`veterinary_calendar_events` du
/// serveur) : `SoinsVaccinsHub::savePlan()` (statut `planned`) et `confirmAdministration()` (statut `done`).
///
/// ⚠️ « En retard » n'est JAMAIS stocké par le poste : c'est un affichage (`display_status` du modèle web,
/// `planned` dont la date est passée). Le serveur refuse `late` à l'envoi.
class VeterinaryCalendarEvents extends Table with SyncColumns {
  TextColumn get lotId => text().withLength(min: 36, max: 36)();
  TextColumn get taskType => text()();
  DateTimeColumn get scheduledDate => dateTime()();

  /// `planned` | `done` | `late` | `inprogress` (enum du serveur ; le poste n'écrit que les deux premiers).
  TextColumn get status => text().withDefault(const Constant('planned'))();
}

/// Ajustement de stock saisi hors ligne.
///
/// ⚠️ LE SERVEUR NE L'APPLIQUE JAMAIS TEL QUEL : il le rejoue par son action
/// d'ajustement, en recalculant le solde depuis l'état réel du produit au
/// moment du push. Un delta hors-ligne appliqué aveuglément produirait un
/// double décrément indétectable si le même mouvement partait deux fois.
class StockAdjustments extends Table with SyncColumns {
  TextColumn get productId => text().withLength(min: 36, max: 36)();

  /// `entree` ou `sortie` — le signe n'est jamais porté par la quantité.
  TextColumn get type => text()();
  RealColumn get quantity => real()();
  TextColumn get referenceType => text()();
  TextColumn get reason => text().nullable()();

  /// Écart d'inventaire : l'INSTANT du comptage (heure murale du Bénin, S-T11). Ajout manuel : le jour choisi.
  DateTimeColumn get movementDate => dateTime()();

  /// Ticket S-T10 — inventaire : la QUANTITÉ COMPTÉE. Le serveur calcule l'écart contre SON stock à l'instant du
  /// comptage (`InventaireAuComptageService`) ; `type` + `quantity` (écart contre le stock LOCAL) ne servent plus qu'à
  /// l'affichage et à un serveur ancien. `null` : ajout manuel, ou inventaire saisi avant S-T10.
  RealColumn get countedQuantity => real().nullable()();
}

/// Ticket U9 — LE GRAND LIVRE DES STOCKS du serveur (`stock_movements`), tiré au poste.
///
/// ⚠️⚠️ **JOURNAL EN LECTURE SEULE, ÉCRIT PAR LE SERVEUR SEUL** (`AdjustStockAction`, point de passage unique de
/// toute mutation de `products.stock_qty`). Pas de [SyncColumns] : le poste ne l'écrit jamais et ne l'envoie jamais
/// (le serveur ignorerait l'envoi et le compterait dans `referentiels_ignored`). Un ajustement saisi ici part dans
/// [StockAdjustments] ; le serveur le rejoue, et le mouvement qui en naît redescend ici avec `reference_id` =
/// identifiant de la ligne du poste.
///
/// Il alimente, comme au web : « Rotation du Stock » (`StockRotationService`), « Écarts d'Inventaire »
/// (`GestionStocks`), le Journal des Mouvements et le Tableau 3 de la ponte (`EggStockLedgerService`). Les saisies
/// encore EN ATTENTE d'envoi y sont ajoutées par `JournalStocks` (`lib/features/stocks/journal_stocks.dart`), jamais
/// écrites dans cette table.
class StockMovements extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get productId => text().withLength(min: 36, max: 36)();

  /// `entree`, `sortie` ou `ajustement` (enum du serveur) ; la quantité est toujours positive.
  TextColumn get type => text()();
  RealColumn get quantity => real()();

  /// `sale`, `purchase`, `daily_entry`, `adjustment`, `inventaire`… (motif du journal du web).
  TextColumn get referenceType => text()();

  /// Pièce d'origine (vente, achat, fiche, ligne d'ajustement du poste) ; `null` pour un ajustement du web.
  TextColumn get referenceId => text().nullable()();
  TextColumn get reason => text().nullable()();

  /// Heure MURALE du serveur : le web compare des JOURS (`whereDate`).
  DateTimeColumn get movementDate => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Enregistrement REFUSÉ par le serveur, avec son motif.
///
/// Table prévue au CDC (§309, « Système / Synchronisation :
/// `sync_queue`, `sync_conflicts`, `backups` »).
///
/// ⚠️ SANS ELLE, UN REJET N'EXISTAIT QUE DANS UN MESSAGE ÉPHÉMÈRE. Le motif
/// disparaissait avec le bandeau, et l'enregistrement restait `pending` — donc
/// renvoyé à chaque synchronisation, refusé à chaque fois, indéfiniment. Une
/// boucle silencieuse que personne ne pouvait diagnostiquer.
///
/// ⚠️ LE MOTIF EST CONSERVÉ MOT POUR MOT. C'est le serveur qui sait pourquoi
/// il refuse ; le reformuler ferait perdre l'information dont le responsable a
/// besoin pour corriger.
class SyncConflicts extends Table {
  /// Clé LOCALE `table:identifiant` — pas un UUID synchronisé, donc sans la
  /// contrainte de 36 caractères des tables du contrat. Elle garantit un seul
  /// conflit ouvert par enregistrement : un refus répété met à jour le motif
  /// au lieu d'empiler des doublons.
  TextColumn get id => text()();

  /// Table d'origine (`livestock_daily_entries`, `sales`, …).
  ///
  /// Nommée `sourceTable` et non `tableName` : ce dernier est déjà une
  /// propriété de `Table` chez Drift, et la redéfinir casse la génération.
  TextColumn get sourceTable => text()();
  TextColumn get recordId => text()();
  TextColumn get reason => text()();
  DateTimeColumn get detectedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Réglages du poste, en clé/valeur.
///
/// ⚠️ PAS DANS LE COFFRE DU SYSTÈME : ce ne sont pas des secrets. L'identifiant
/// du poste et l'adresse du serveur doivent au contraire être LISIBLES par le
/// support, qui en a besoin pour diagnostiquer un conflit ou une panne réseau.
/// Compte de tresorerie servi par le serveur — qui paie une depense.
///
/// ⚠️ REFERENTIEL EN LECTURE SEULE. Le solde affiche est celui du dernier
/// tirage : le poste ne le recalcule pas. Une depense saisie hors ligne pese
/// sur le solde REEL au moment ou le serveur la recoit, pas avant.
class TreasuryAccounts extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get label => text()();
  TextColumn get accountCode => text().nullable()();
  TextColumn get type => text().nullable()();
  RealColumn get balance => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Comptes de charge proposes a la saisie — servis par le serveur.
///
/// ⚠️ JAMAIS CODES EN DUR AU POSTE. La liste vit dans `Expense::CATEGORIES`
/// cote serveur et descend par la synchronisation : la recopier ici ferait
/// diverger les deux au premier ajout, sans que rien ne le signale.
class ExpenseCategories extends Table {
  TextColumn get label => text()();

  @override
  Set<Column> get primaryKey => {label};
}

/// Depense saisie au poste.
///
/// ⚠️⚠️ **DEUX EFFETS COTE SERVEUR, AUCUN AU POSTE.** A la reception, le
/// serveur decaisse la tresorerie ET passe l'ecriture SYSCOHADA (ticket 14.62).
/// Le poste, lui, ne tient NI comptabilite NI solde de tresorerie faisant foi :
/// il n'a pas de plan comptable, pas d'exercice, pas de journal. Reproduire un
/// decaissement local donnerait un solde qui n'engage rien et qui divergerait
/// du serveur des la premiere depense saisie ailleurs.
///
/// C'est une difference assumee avec les ventes et la ponte, ou l'effet local
/// existe parce que le poste EN A BESOIN tout de suite (vendre, servir la
/// provende). Ici, personne au poste ne decide sur la foi du solde.
///
/// Ticket U13 — TABLE MIXTE, comme les clients ou les achats : les dépenses du serveur (web, autres postes) y
/// DESCENDENT, au curseur, avec leur archivage (`is_active`) ; une saisie locale `pending` ou `conflict` n'est jamais
/// écrasée par le tirage (`SyncEngine._absorberDepenses`).
class Expenses extends Table with SyncColumns {
  DateTimeColumn get expenseDate => dateTime()();
  TextColumn get label => text()();
  TextColumn get category => text()();
  RealColumn get amount => real()();
  TextColumn get treasuryAccountId => text()();

  /// Ticket U13 — archivage logique du web (`SaisieDepenses::archiveExpense()` : montant réintégré, charge
  /// contre-passée). Une dépense archivée n'est plus une dépense : aucun écran ni rapport ne la compte. Défaut `true` :
  /// toute dépense saisie ici, ou déjà présente avant U13, est active (comme au serveur à sa création).
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Ticket U14 — `expenses.status` du serveur (`payee` / `en_attente`) : le badge et le filtre « Statut » du Blade.
  /// Défaut `payee` : une dépense saisie est immédiatement décaissée (le serveur la crée `payee`, toujours).
  TextColumn get status => text().withDefault(const Constant('payee'))();

  /// Ticket U14 — `expenses.accounting_entry_id` du serveur : une dépense COMPTABILISÉE ne change plus de montant, de
  /// compte de charge ni de compte de trésorerie (`SaisieDepenseAction`). Le poste refuse avant d'écrire, comme le web.
  /// `null` : pas d'écriture connue (saisie de ce poste pas encore reçue, ou plan comptable incomplet au serveur).
  TextColumn get accountingEntryId => text().nullable()();
}

/// Ticket DEV — DEVIS (« Devis & Proforma » : `quotes` du serveur), TABLE MIXTE comme les dépenses : saisis, avancés dans
/// leur cycle et archivés au poste (`pending`, envoyés), ET tirés du serveur (web, autres postes) au curseur, archivés
/// compris. Un devis y est, comme au web, une description libre des prestations + un montant HT global + une TVA + une
/// validité en jours — jamais des lignes de produits.
///
/// ⚠️ **LE NUMÉRO `DEV-AAAA-NNN` N'EST JAMAIS INVENTÉ PAR LE POSTE** (même principe que la référence des courriers) : le
/// serveur l'attribue à la réception, `NULL` tant que le devis n'est pas acquitté puis tiré (« — » à l'écran). Deux postes
/// hors ligne auraient sinon deux devis au même numéro.
///
/// ⚠️ `status` : `brouillon` → `envoye` → `accepte` | `refuse` (le poste ne pose jamais `facture`, que le serveur seul
/// pourrait poser). Une saisie locale `pending` ou `conflict` n'est jamais écrasée par le tirage
/// (`SyncEngine._absorberDevis`).
class Quotes extends Table with SyncColumns {
  /// `DEV-AAAA-NNN`, attribué par le serveur (voir plus haut).
  TextColumn get quoteNumber => text().nullable()();
  TextColumn get customerId => text()();
  TextColumn get articlesDescription => text()();

  /// Montant HT global (FCFA).
  RealColumn get amount => real()();
  RealColumn get tvaRate => real().withDefault(const Constant(0))();
  IntColumn get validityDays => integer().withDefault(const Constant(15))();
  DateTimeColumn get quoteDate => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('brouillon'))();

  /// Archivage logique (`false` : archivé, rien n'est supprimé).
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Ticket U13 — PAIE RÉGLÉE (`payslips` du serveur), en LECTURE SEULE : seules les colonnes que le rapport « Recettes
/// et Dépenses » du web lit (`RecettesDepenses::depensesRows()`) descendent — l'instant du règlement, le nom de
/// l'employé et le net versé. ⚠️ RIEN D'AUTRE SUR LA PAIE (protections S3 sur les salaires) : ni brut, ni retenues,
/// ni charges patronales, ni période. Servie aux comptes qui lisent les rapports (`view-rapports`), qui voient ces
/// mêmes lignes au web. Jamais écrite ici, jamais envoyée.
class Payslips extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  /// `last_name.' '.first_name` de l'employé ; `null` : employé introuvable (« Employé » au rapport).
  TextColumn get employeeName => text().nullable()();

  /// Net versé (`net_salary`).
  RealColumn get netSalary => real()();

  /// Instant du règlement (`created_at`), en HEURE MURALE du serveur (Bénin) : le jour du rapport est son jour.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// État du moteur de synchronisation — une seule ligne.
///
/// ⚠️ `lastPulledAt` VIENT DE L'HORLOGE DU SERVEUR (`server_time` de la
/// réponse), jamais de celle de l'appareil. Une tablette dont l'heure retarde
/// de dix minutes redemanderait sans cesse les mêmes changements ; une qui
/// avance en sauterait définitivement.
class SyncState extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();
  DateTimeColumn get lastPushedAt => dateTime().nullable()();

  /// Ticket H2 — fin de la dernière synchronisation ABOUTIE (tirage puis envoi, refus compris : la liaison a
  /// marché). À l'heure du SERVEUR : c'est l'instant du tirage de cette synchronisation, jamais l'horloge du poste.
  DateTimeColumn get lastSucceededAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    ProductCategories,
    Products,
    LivestockLots,
    FeedRationStandards,
    GrowthStandards,
    VeterinaryWithdrawalPeriods,
    LivestockReproductionEvents,
    Customers,
    Receivables,
    CustomerAdvances,
    CustomerReminders,
    FeedTypes,
    ElevageNumberingSettings,
    Suppliers,
    PurchaseOrders,
    Payables,
    Employees,
    Internships,
    AttendanceRecords,
    Mails,
    AdministrativeDocuments,
    ArchivedDocuments,
    ChartOfAccounts,
    FiscalYears,
    AccountingEntries,
    AccountingEntryLines,
    CompanySettings,
    ModulesConfig,
    RolesApplicatifs,
    Utilisateurs,
    AuditLogs,
    Notifications,
    LotRevenues,
    AttestationTemplates,
    Animals,
    LivestockSpecies,
    SupplierPayments,
    PurchaseReturns,
    SupplierRefunds,
    SupplierCredits,
    AdvanceImputations,
    Purchases,
    PurchaseLines,
    LivestockDailyEntries,
    LivestockTransfers,
    ProphylaxisScheduleStandards,
    VeterinaryRecords,
    InfirmaryRecords,
    VeterinaryCalendarEvents,
    Sales,
    SaleLines,
    CreditNotes,
    StockAdjustments,
    StockMovements,
    SyncConflicts,
    TreasuryAccounts,
    ExpenseCategories,
    Expenses,
    Quotes,
    Payslips,
    AppSettings,
    SyncState,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  /// ⚠️ TOUTE TABLE OU COLONNE AJOUTÉE IMPOSE D'INCRÉMENTER CE NUMÉRO **et**
  /// d'écrire son pas de migration ci-dessous. Sans cela, une base déjà
  /// présente sur un poste garde l'ancien schéma : la première requête sur la
  /// table manquante lève « no such table » et l'écran devient inutilisable —
  /// alors que tout fonctionne sur une installation neuve, ce qui rend la
  /// panne invisible en développement.
  @override
  int get schemaVersion => 54;

  /// Ajoute [colonne] à [table] SEULEMENT si la colonne n'y est pas déjà.
  ///
  /// 🔴 ⚠️⚠️ **UN `createTable` POSE LE SCHÉMA COURANT, PAS CELUI DE SON PALIER**
  /// (ticket F0.85-bis). Depuis une base en v19, `accounting_entries` est créée au
  /// palier v20 AVEC `created_at`, et le palier v37 la rajoutait : « duplicate column
  /// name: created_at », le poste ne s'ouvrait plus. Même famille pour vingt-deux autres
  /// colonnes (fournisseurs, clients, avances, achats, courriers, archives, documents,
  /// prophylaxie) : toute base antérieure à la v20 était inouvrable. Les tests de
  /// migration ne partaient que de N-1 ; `migration_toutes_versions_test.dart` part
  /// désormais de CHAQUE version. Le schéma final est inchangé : la colonne présente a
  /// été posée par le même `createTable` du schéma courant.
  Future<void> _ajouterColonneSiAbsente(
    Migrator m,
    TableInfo table,
    GeneratedColumn colonne,
  ) async {
    final existantes = await m.database
        .customSelect('PRAGMA table_info("${table.actualTableName}")')
        .get();
    if (existantes.any((l) => l.read<String>('name') == colonne.name)) return;
    await m.addColumn(table, colonne);
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // v2 — rations normatives descendues du serveur (ticket F0.4).
      if (from < 2) {
        await m.createTable(feedRationStandards);
      }
      // v3 — rémanence vétérinaire descendue du serveur (ticket F0.5).
      if (from < 3) {
        await m.createTable(veterinaryWithdrawalPeriods);
      }
      // v4 — journal des refus serveur (ticket F0.7).
      if (from < 4) {
        await m.createTable(syncConflicts);
      }
      // v5 — réglages du poste : identifiant et adresse serveur (F0.8).
      if (from < 5) {
        await m.createTable(appSettings);
      }
      // v6 — prophylaxie et registre vétérinaire (ticket F0.11).
      if (from < 6) {
        await m.createTable(prophylaxisScheduleStandards);
        await m.createTable(veterinaryRecords);
      }
      // v7 — bornes de jour de cycle : sans elles, le poste ne peut pas
      // savoir quels traitements sont dus aujourd'hui (ticket F0.12).
      if (from < 7) {
        await _ajouterColonneSiAbsente(
          m,
          prophylaxisScheduleStandards,
          prophylaxisScheduleStandards.cycleDayStart,
        );
        await _ajouterColonneSiAbsente(
          m,
          prophylaxisScheduleStandards,
          prophylaxisScheduleStandards.cycleDayEnd,
        );
      }
      // v8 — code espece de la bande : le garde-fou du stock d'oeufs en
      // depend (ticket F0.14).
      if (from < 8) {
        await _ajouterColonneSiAbsente(
          m,
          livestockLots,
          livestockLots.speciesCode,
        );
      }
      // v9 — saisie des depenses au poste (ticket F0.18).
      if (from < 9) {
        await m.createTable(treasuryAccounts);
        await m.createTable(expenseCategories);
        await m.createTable(expenses);
      }
      // v10 — cycle de reproduction par femelle nommee (ticket F0.34).
      if (from < 10) {
        await m.createTable(livestockReproductionEvents);
      }
      // v11 — la saillie se declare AU POSTE (ticket F0.35) : la table
      // passe de « recue » a « recue et envoyee », donc gagne
      // `device_id` et `sync_status`, et son `updated_at` cesse d'etre
      // nullable.
      //
      // ⚠️ RECONSTRUCTION DE TABLE, PAS UN `ADD COLUMN` : SQLite refuse
      // d'ajouter une colonne NOT NULL sans valeur par defaut, et
      // `updated_at` change de nullabilite. Les lignes existantes ne
      // peuvent venir que du serveur — le canal d'envoi n'existait pas en
      // v10 — d'ou `'serveur'` et `synced`.
      if (from < 11) {
        await m.alterTable(
          TableMigration(
            livestockReproductionEvents,
            columnTransformer: {
              livestockReproductionEvents.deviceId: const Constant<String>(
                'serveur',
              ),
              livestockReproductionEvents.syncStatus: const Constant<String>(
                'synced',
              ),
              livestockReproductionEvents.updatedAt: coalesce([
                livestockReproductionEvents.updatedAt,
                currentDateAndTime,
              ]),
            },
            newColumns: [
              livestockReproductionEvents.deviceId,
              livestockReproductionEvents.syncStatus,
            ],
          ),
        );
      }
      // v12 — fichier clients, créances et avances (ticket F0.43).
      //
      // ⚠️ Trois référentiels servis par le serveur : `createTable` suffit,
      // aucune donnée locale ne peut préexister.
      if (from < 12) {
        await m.createTable(customers);
        await m.createTable(receivables);
        await m.createTable(customerAdvances);
      }
      // v13 — relances deja envoyees (ticket F0.43 / 14.76).
      //
      // Quatrieme referentiel du meme domaine : sans lui, la file de relance
      // ne distingue pas le debiteur contacte ce matin de celui que personne
      // n a jamais appele.
      if (from < 13) {
        await m.createTable(customerReminders);
      }
      // v14 — types de provende et prefixes de numerotation (ticket F0.44).
      //
      // Les deux derniers referentiels d'elevage que le serveur ne servait
      // pas : le catalogue des aliments (avec le poids du sac) et les
      // prefixes qui nomment les animaux sur le terrain.
      if (from < 14) {
        await m.createTable(feedTypes);
        await m.createTable(elevageNumberingSettings);
      }
      // v15 — domaine achat (ticket F0.45).
      //
      // Deux referentiels (fournisseurs, bons de commande) et une table
      // SYNCHRONISABLE : un achat saisi hors ligne part au serveur, qui seul
      // applique ses cinq effets.
      if (from < 15) {
        await m.createTable(suppliers);
        await m.createTable(purchaseOrders);
        await m.createTable(purchases);
        await m.createTable(purchaseLines);
      }
      // v16 — dettes fournisseurs (ticket F0.46).
      if (from < 16) {
        await m.createTable(payables);
      }
      // v17 — la facture normalisee (ticket F0.47).
      //
      // ⚠️ TROIS COLONNES AJOUTEES A UNE TABLE QUI PORTE DES VENTES REELLES :
      // `addColumn`, jamais un `createTable` qui les perdrait.
      if (from < 17) {
        await _ajouterColonneSiAbsente(m, sales, sales.customerName);
        await _ajouterColonneSiAbsente(m, sales, sales.mecefStatus);
        await _ajouterColonneSiAbsente(m, sales, sales.mecefQrRef);
      }
      // v18 — personnel, stagiaires et pointage (ticket F0.48).
      if (from < 18) {
        await m.createTable(employees);
        await m.createTable(internships);
        await m.createTable(attendanceRecords);
      }
      // v19 — secretariat : courriers, documents, archives (ticket F0.49).
      if (from < 19) {
        await m.createTable(mails);
        await m.createTable(administrativeDocuments);
        await m.createTable(archivedDocuments);
      }
      // v20 — le journal comptable (ticket F0.50).
      if (from < 20) {
        await m.createTable(chartOfAccounts);
        await m.createTable(fiscalYears);
        await m.createTable(accountingEntries);
        await m.createTable(accountingEntryLines);
      }
      // v21 — parametres generaux (ticket F0.51).
      if (from < 21) {
        await m.createTable(companySettings);
        await m.createTable(modulesConfig);
        await m.createTable(rolesApplicatifs);
        await m.createTable(utilisateurs);
        await m.createTable(auditLogs);
      }
      // v22 — le centre de notifications (ticket F0.59).
      if (from < 22) {
        await m.createTable(notifications);
      }
      // v23 — revenus par bande du bilan technico-économique (ticket F0.63).
      if (from < 23) {
        await m.createTable(lotRevenues);
      }
      // v24 — modèles d'attestation (ticket F0.64).
      if (from < 24) {
        await m.createTable(attestationTemplates);
      }
      // v25 — les sujets suivis individuellement (ticket F0.65).
      if (from < 25) {
        await m.createTable(animals);
      }
      // v26 — espèces actives et description du produit (ticket F0.67).
      if (from < 26) {
        await m.createTable(livestockSpecies);
        await _ajouterColonneSiAbsente(m, products, products.description);
      }
      // v27 — statut de synchronisation du produit (création au poste).
      if (from < 27) {
        await _ajouterColonneSiAbsente(m, products, products.syncStatus);
      }
      // v28 — règlements fournisseurs saisis au poste (ticket F0.69).
      if (from < 28) {
        await m.createTable(supplierPayments);
      }
      // v29 — fiches fournisseurs saisies au poste (ticket F0.71).
      if (from < 29) {
        await _ajouterColonneSiAbsente(m, suppliers, suppliers.syncStatus);
        await _ajouterColonneSiAbsente(m, suppliers, suppliers.isActive);
      }
      // v30 — fiches clients saisies au poste (ticket F0.72).
      if (from < 30) {
        await _ajouterColonneSiAbsente(m, customers, customers.email);
        await _ajouterColonneSiAbsente(m, customers, customers.syncStatus);
      }
      // v31 — avances clients et imputations saisies au poste (ticket F0.73).
      if (from < 31) {
        await _ajouterColonneSiAbsente(
          m,
          customerAdvances,
          customerAdvances.treasuryAccountId,
        );
        await _ajouterColonneSiAbsente(
          m,
          customerAdvances,
          customerAdvances.paymentMode,
        );
        await _ajouterColonneSiAbsente(
          m,
          customerAdvances,
          customerAdvances.motif,
        );
        await _ajouterColonneSiAbsente(
          m,
          customerAdvances,
          customerAdvances.deviceId,
        );
        await _ajouterColonneSiAbsente(
          m,
          customerAdvances,
          customerAdvances.syncStatus,
        );
        await m.createTable(advanceImputations);
      }
      // v32 — retours et remboursements fournisseurs saisis au poste (ticket F0.74).
      if (from < 32) {
        await _ajouterColonneSiAbsente(m, purchases, purchases.returnedAt);
        await _ajouterColonneSiAbsente(m, purchases, purchases.supplierCredit);
        await m.createTable(purchaseReturns);
        await m.createTable(supplierRefunds);
        await m.createTable(supplierCredits);
      }
      // v33 — courriers saisis au poste (ticket F0.78).
      if (from < 33) {
        await _ajouterColonneSiAbsente(m, mails, mails.isActive);
        await _ajouterColonneSiAbsente(m, mails, mails.syncStatus);
      }
      // v34 — « connu du serveur » : distingue un courrier jamais envoyé d'un courrier
      // accepté dont la référence n'est pas encore descendue (ticket F0.78-bis).
      if (from < 34) {
        await _ajouterColonneSiAbsente(m, mails, mails.knownByServer);
      }
      // v35 — documents archivés saisis, modifiés et retirés au poste (ticket F0.79). Les
      // lignes existantes sont actives, synchronisées et réputées connues du serveur.
      if (from < 35) {
        await _ajouterColonneSiAbsente(
          m,
          archivedDocuments,
          archivedDocuments.isActive,
        );
        await _ajouterColonneSiAbsente(
          m,
          archivedDocuments,
          archivedDocuments.syncStatus,
        );
        await _ajouterColonneSiAbsente(
          m,
          archivedDocuments,
          archivedDocuments.knownByServer,
        );
      }
      // v36 — documents administratifs saisis, modifiés et retirés au poste (ticket F0.80).
      // Les lignes existantes sont actives, synchronisées et réputées connues du serveur.
      if (from < 36) {
        await _ajouterColonneSiAbsente(
          m,
          administrativeDocuments,
          administrativeDocuments.isActive,
        );
        await _ajouterColonneSiAbsente(
          m,
          administrativeDocuments,
          administrativeDocuments.syncStatus,
        );
        await _ajouterColonneSiAbsente(
          m,
          administrativeDocuments,
          administrativeDocuments.knownByServer,
        );
      }
      // v37 — instant de création des écritures, pour départager deux pièces du même jour au
      // Grand Livre (ticket F0.85). Les écritures déjà présentes le reçoivent à la
      // resynchronisation UNIQUE du journal (réglage `journal_resync_f085`), jamais inventé ici.
      if (from < 37) {
        await _ajouterColonneSiAbsente(
          m,
          accountingEntries,
          accountingEntries.createdAt,
        );
      }
      // v38 — effectif par catégorie et ventilation par sexe des fiches journalières (ticket
      // F0.95). Toutes NULLABLES sans défaut : les fiches existantes restent « inconnues », jamais
      // 0. Elles reçoivent les valeurs du serveur à la resynchronisation UNIQUE des fiches
      // (réglage `fiches_resync_f095`).
      if (from < 38) {
        for (final colonne in [
          livestockDailyEntries.mortRepro,
          livestockDailyEntries.mortSevre,
          livestockDailyEntries.mortJeune,
          livestockDailyEntries.donRepro,
          livestockDailyEntries.donSevre,
          livestockDailyEntries.donJeune,
          livestockDailyEntries.passageSevreJeune,
          livestockDailyEntries.catDepartRepro,
          livestockDailyEntries.catDepartSevre,
          livestockDailyEntries.catDepartJeune,
          livestockDailyEntries.catEffRepro,
          livestockDailyEntries.catEffSevre,
          livestockDailyEntries.catEffJeune,
          livestockDailyEntries.catEff4,
          livestockDailyEntries.effectifM,
          livestockDailyEntries.effectifF,
          livestockDailyEntries.effectifSevres,
          livestockDailyEntries.effectifSmeres,
        ]) {
          await _ajouterColonneSiAbsente(m, livestockDailyEntries, colonne);
        }
      }

      // v39 — transferts entre bandes (ticket 15.46) : table, colonnes dérivées des fiches, bande d'origine.
      if (from < 39) {
        if (!await _tableExiste(m, livestockTransfers)) {
          await m.createTable(livestockTransfers);
        }
        for (final colonne in [
          livestockDailyEntries.transfertEntree,
          livestockDailyEntries.transfertSortie,
          livestockDailyEntries.transfertEntreeRepro,
          livestockDailyEntries.transfertEntreeSevre,
          livestockDailyEntries.transfertEntreeJeune,
          livestockDailyEntries.transfertSortieRepro,
          livestockDailyEntries.transfertSortieSevre,
          livestockDailyEntries.transfertSortieJeune,
        ]) {
          await _ajouterColonneSiAbsente(m, livestockDailyEntries, colonne);
        }
        await _ajouterColonneSiAbsente(
          m,
          livestockLots,
          livestockLots.lotSourceId,
        );
      }

      // v40 — ticket H2 : instant de la dernière synchronisation aboutie (modale « Synchronisation »).
      if (from < 40) {
        await _ajouterColonneSiAbsente(m, syncState, syncState.lastSucceededAt);
      }

      // v41 — ticket H8b (D-H8) : infirmerie et calendrier vétérinaire planifié, saisis au poste.
      if (from < 41) {
        if (!await _tableExiste(m, infirmaryRecords)) {
          await m.createTable(infirmaryRecords);
        }
        if (!await _tableExiste(m, veterinaryCalendarEvents)) {
          await m.createTable(veterinaryCalendarEvents);
        }
      }

      // v42 — ticket H9b (D-H9) : Paramètres Élevage modifiables au poste comme au web. Les trois barèmes
      // reçoivent l'archivage logique et leur statut de synchronisation ; la numérotation et l'entreprise
      // (délai du rappel des soins) leur statut ; la prophylaxie son instant de création (tri du web, H9).
      if (from < 42) {
        for (final (table, colonnes) in <(TableInfo, List<GeneratedColumn>)>[
          (
            feedRationStandards,
            [
              feedRationStandards.isActive,
              feedRationStandards.syncStatus,
              feedRationStandards.updatedAt,
            ],
          ),
          (
            prophylaxisScheduleStandards,
            [
              prophylaxisScheduleStandards.isActive,
              prophylaxisScheduleStandards.syncStatus,
              prophylaxisScheduleStandards.updatedAt,
              prophylaxisScheduleStandards.createdAt,
            ],
          ),
          (
            feedTypes,
            [feedTypes.isActive, feedTypes.syncStatus, feedTypes.updatedAt],
          ),
          (
            elevageNumberingSettings,
            [
              elevageNumberingSettings.syncStatus,
              elevageNumberingSettings.updatedAt,
            ],
          ),
          (
            companySettings,
            [
              companySettings.rappelSoinsJours,
              companySettings.syncStatus,
              companySettings.updatedAt,
            ],
          ),
        ]) {
          for (final colonne in colonnes) {
            await _ajouterColonneSiAbsente(m, table, colonne);
          }
        }
      }

      // v43 — tickets U2 et U3 (décisions client du 19/10/2026, « uniformiser web et poste ») : barème des
      // objectifs de GMQ tiré du serveur ; archivage logique des soins (défaut `true` : tout soin existant est
      // actif, comme au serveur où la colonne existe depuis l'origine).
      if (from < 43) {
        if (!await _tableExiste(m, growthStandards)) {
          await m.createTable(growthStandards);
        }
        await _ajouterColonneSiAbsente(
          m,
          veterinaryRecords,
          veterinaryRecords.isActive,
        );
      }

      // v44 — ticket U9 : grand livre des stocks du serveur (`stock_movements`), en lecture seule.
      if (from < 44) {
        if (!await _tableExiste(m, stockMovements)) {
          await m.createTable(stockMovements);
        }
      }

      // v45 — ticket U10 : colonnes de la fiche reçues du serveur pour le Rapport Élevage (Tableau 2, CA Ventes).
      if (from < 45) {
        for (final colonne in [
          livestockDailyEntries.venteSexe,
          livestockDailyEntries.venteMontant,
          livestockDailyEntries.treatmentProductId,
          livestockDailyEntries.treatmentDose,
          livestockDailyEntries.symptomes,
        ]) {
          await _ajouterColonneSiAbsente(m, livestockDailyEntries, colonne);
        }
      }

      // v46 — ticket S-T10 : quantité comptée d'un inventaire (l'écart est calculé par le serveur).
      if (from < 46) {
        await _ajouterColonneSiAbsente(m, stockAdjustments, stockAdjustments.countedQuantity);
      }

      // v47 — ticket U13 : les dépenses du serveur descendent avec leur archivage (défaut `true` : toute dépense déjà
      // présente est active) ; la paie réglée (`payslips`) descend en lecture seule pour « Recettes et Dépenses ».
      if (from < 47) {
        await _ajouterColonneSiAbsente(m, expenses, expenses.isActive);
        if (!await _tableExiste(m, payslips)) {
          await m.createTable(payslips);
        }
      }

      // v48 — ticket U14 : statut (badge et filtre du Blade) et écriture comptable de la dépense (règle de modification).
      if (from < 48) {
        await _ajouterColonneSiAbsente(m, expenses, expenses.status);
        await _ajouterColonneSiAbsente(m, expenses, expenses.accountingEntryId);
      }

      // v49 — ticket BS1 : bandes créées, modifiées et archivées au poste (statut d'envoi, correction d'effectif).
      if (from < 49) {
        await _ajouterColonneSiAbsente(m, livestockLots, livestockLots.syncStatus);
        await _ajouterColonneSiAbsente(m, livestockLots, livestockLots.effectifCorrige);
      }

      // v50 — décision BS-Q7 : une bande archivée se restaure au poste (geste explicite à envoyer).
      if (from < 50) {
        await _ajouterColonneSiAbsente(m, livestockLots, livestockLots.restauree);
      }

      // v51 — décision BS-Q1 (ticket BS3) : le registre nominatif des reproducteurs s'écrit au poste.
      if (from < 51) {
        await _ajouterColonneSiAbsente(m, animals, animals.speciesId);
        await _ajouterColonneSiAbsente(m, animals, animals.syncStatus);
        await _ajouterColonneSiAbsente(m, animals, animals.updatedAt);
      }

      // v52 — ticket MAIL1 (décision du client du 21/10/2026) : les anciennes adresses `@olouwachegoun.bj` déjà
      // enregistrées au poste passent à `@fermeolouwachegoun.com`. AUCUN changement de table : `app_database.g.dart` ne
      // bouge pas. Voir [_convertirAdressesEmail].
      if (from < 52) {
        await _convertirAdressesEmail();
      }

      // v53 — ticket DEV : « Devis & Proforma » au poste (table `quotes`, saisie ET tirée).
      if (from < 53) {
        if (!await _tableExiste(m, quotes)) {
          await m.createTable(quotes);
        }
      }

      // v54 — tickets AV1 / AV2 : retours et avoirs clients saisis au poste (`credit_notes`, table mixte : demandes
      // `pending` ET avoirs tirés du serveur). Une base en v52, v53 ou v54 passe ici sans trou (`from < 53`, `from < 54`).
      if (from < 54) {
        if (!await _tableExiste(m, creditNotes)) {
          await m.createTable(creditNotes);
        }
      }
    },
  );

  /// Palier v52 (ticket MAIL1) — remplace `@olouwachegoun.bj` par `@fermeolouwachegoun.com` (insensible à la casse, en
  /// SQL) dans TOUTES les colonnes locales susceptibles de porter une adresse : l'e-mail des clients, des fournisseurs,
  /// de l'identité de la ferme et des utilisateurs, le titre et le message des notifications, et les valeurs de
  /// `app_settings` (réglages non secrets de l'onglet « Email (SMTP) » : utilisateur, expéditeur).
  ///
  /// ⚠️ **UNE LIGNE RESTE CE QU'ELLE ÉTAIT** : seule la colonne d'adresse est écrite. NI `sync_status` NI `updated_at` ne
  /// bougent — une fiche `pending` reste `pending`, une `synced` reste `synced` ; le serveur, migré lui aussi, fait converger
  /// les postes au tirage. Les adresses d'un autre domaine sont intactes.
  ///
  /// ⚠️ Aucune contrainte d'unicité locale sur ces colonnes (la clé primaire est l'UUID), donc aucun conflit à arbitrer
  /// (le web, lui, journalise un `users.email` déjà pris). Le journal d'audit local n'est pas réécrit (historique).
  ///
  /// ⚠️ **AUCUN SECRET N'EST LU** : le mot de passe SMTP et le jeton vivent au coffre du système (`flutter_secure_storage`),
  /// jamais dans ces tables ; la base n'ouvre pas le coffre. L'e-mail de la session mise en cache (au coffre) est converti
  /// à la lecture, par `convertirDomaineEmail` (`SessionUtilisateur.depuisJson`).
  ///
  /// Une valeur qui porterait l'adresse DEUX fois est reprise à la passe suivante (au plus dix) ; un nom de serveur
  /// (`smtp.olouwachegoun.bj`, sans « @ ») n'est pas une adresse et n'est pas touché.
  Future<void> _convertirAdressesEmail() async {
    final cibles = <(String, String)>[
      (customers.actualTableName, customers.email.name),
      (suppliers.actualTableName, suppliers.email.name),
      (companySettings.actualTableName, companySettings.email.name),
      (utilisateurs.actualTableName, utilisateurs.email.name),
      (notifications.actualTableName, notifications.title.name),
      (notifications.actualTableName, notifications.message.name),
      (appSettings.actualTableName, appSettings.value.name),
    ];
    const ancien = '@$ancienDomaineEmail';
    const nouveau = '@$nouveauDomaineEmail';
    const longueur = ancien.length;

    for (final (table, colonne) in cibles) {
      final c = '"$colonne"';
      final position = "instr(lower($c), '$ancien')";
      for (var passe = 0; passe < 10; passe++) {
        final modifiees = await customUpdate(
          'UPDATE "$table" SET $c = substr($c, 1, $position - 1) || \'$nouveau\' || substr($c, $position + $longueur) '
          "WHERE $c IS NOT NULL AND $position > 0 "
          "AND NOT (substr(lower($c), $position + $longueur, 1) GLOB '[a-z0-9-]')",
        );
        if (modifiees == 0) break;
      }
    }
  }

  /// Vrai si [table] existe déjà (un `createTable` d'un palier antérieur pose le schéma COURANT).
  Future<bool> _tableExiste(Migrator m, TableInfo table) async {
    final lignes = await m.database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable.withString(table.actualTableName)],
        )
        .get();
    return lignes.isNotEmpty;
  }

  /// État du moteur de synchronisation, **toutes lignes fusionnées**.
  ///
  /// 🔴 ⚠️⚠️ **LA TABLE N'A JAMAIS DÛ AVOIR PLUSIEURS LIGNES, ET ELLE EN AVAIT**
  /// (ticket F0.63). Chaque tirage insérait `SyncStateCompanion.insert(...)` SANS
  /// identifiant : SQLite lui en attribuait un nouveau (2, 3…) au lieu de mettre à
  /// jour la ligne 1. Dès la deuxième synchronisation la table comptait deux
  /// lignes, et la troisième échouait pour toujours sur `getSingleOrNull()` —
  /// « Bad state: Too many elements ». Aucun test ne synchronisait trois fois la
  /// même base ; l'échec ne se voit qu'en usage réel.
  ///
  /// Cette lecture tolère les bases DÉJÀ abîmées : elle prend, parmi toutes les
  /// lignes, la date de tirage et la date d'envoi les plus récentes. Elle ne
  /// lève jamais « trop d'éléments ».
  Future<SyncStateData?> etatDeSynchronisation() async {
    final lignes = await select(syncState).get();
    if (lignes.isEmpty) return null;

    DateTime? plusRecente(Iterable<DateTime?> dates) {
      final presentes = dates.whereType<DateTime>().toList()..sort();
      return presentes.isEmpty ? null : presentes.last;
    }

    return SyncStateData(
      id: 1,
      lastPulledAt: plusRecente(lignes.map((l) => l.lastPulledAt)),
      lastPushedAt: plusRecente(lignes.map((l) => l.lastPushedAt)),
    );
  }

  /// Note l'instant du dernier tirage ([tire]) et/ou du dernier envoi
  /// ([envoye]), **en gardant UNE SEULE ligne** (identifiant 1).
  ///
  /// ⚠️ Ce qui n'est pas passé est conservé tel quel : un tirage ne doit pas
  /// effacer la date du dernier envoi, ni l'inverse. Les lignes en trop, héritées
  /// de l'ancien défaut, sont fusionnées puis supprimées.
  Future<void> noterEtatDeSynchronisation({
    DateTime? tire,
    DateTime? envoye,
    DateTime? reussi,
  }) async {
    await transaction(() async {
      final actuel = await etatDeSynchronisation();

      await delete(syncState).go();
      await into(syncState).insert(
        SyncStateCompanion.insert(
          id: const Value(1),
          lastPulledAt: Value(tire ?? actuel?.lastPulledAt),
          lastPushedAt: Value(envoye ?? actuel?.lastPushedAt),
          lastSucceededAt: Value(reussi ?? actuel?.lastSucceededAt),
        ),
      );
    });
  }

  /// Ticket H2 — TABLES QUE LE POSTE ENVOIE au serveur (`SyncEngine._pousser`), nom SQL.
  ///
  /// 🔴 Le compteur « en attente » était une liste tenue à la main, ajoutée table par table (F0.35, F0.45,
  /// F0.48, F0.78…) : huit tables envoyées y manquaient (produits, fournisseurs, clients, règlements, avances,
  /// imputations, retours, remboursements). Un client ou un article créé hors ligne affichait « 0 en
  /// attente », et la confirmation de fermeture laissait quitter sans prévenir. Un test compare désormais
  /// cette liste aux tables lues par `_pousser` : la prochaine table envoyée ne peut plus être oubliée ici.
  static const tablesEnvoyees = <String>[
    'livestock_daily_entries',
    'sales',
    'stock_adjustments',
    'veterinary_records',
    'expenses',
    // Ticket DEV — devis saisis au poste.
    'quotes',
    'livestock_reproduction_events',
    'purchases',
    'attendance_records',
    'products',
    'suppliers',
    'supplier_payments',
    'customers',
    'mails',
    'archived_documents',
    'administrative_documents',
    'customer_advances',
    'advance_imputations',
    'purchase_returns',
    'supplier_refunds',
    'livestock_transfers',
    // Tickets AV1 / AV2 — retours et avoirs clients (demandes de retour, « marquer comme traité »).
    'credit_notes',
    // Ticket BS1 — bandes saisies au poste.
    'livestock_lots',
    // Ticket BS3 — reproducteurs nominatifs saisis au poste.
    'animals',
    // Ticket H8b (D-H8) — infirmerie et calendrier planifié saisis au poste.
    'infirmary_records',
    'veterinary_calendar_events',
    // Ticket H9b (D-H9) — Paramètres Élevage modifiables au poste (le délai du rappel des soins vit dans
    // `company_settings`).
    'feed_ration_standards',
    'prophylaxis_schedule_standards',
    'feed_types',
    'elevage_numbering_settings',
    'company_settings',
  ];

  /// Nombre d'enregistrements en attente d'envoi, toutes tables confondues.
  /// C'est le chiffre porté par le badge du bouton « Synchroniser ».
  ///
  /// ⚠️ LES REFUSÉS COMPTENT AUSSI. Un enregistrement en conflit n'est PAS
  /// arrivé au serveur : l'exclure du compteur afficherait « 0 en attente »
  /// alors que des ventes n'existent que sur ce poste — et l'utilisateur
  /// éteindrait la machine en croyant son travail à l'abri.
  Future<int> pendingCount() async {
    final c = await compteursSynchronisation();
    return c.aEnvoyer + c.refuses;
  }

  /// Ticket H2 — enregistrements non synchronisés, séparés en « à envoyer » (`pending`) et « refusés par le
  /// serveur » (`conflict`), sur toutes les [tablesEnvoyees]. Lu par la modale « Synchronisation ».
  Future<({int aEnvoyer, int refuses})> compteursSynchronisation() async {
    final unions = tablesEnvoyees
        .map((t) => "SELECT sync_status FROM $t WHERE sync_status <> 'synced'")
        .join(' UNION ALL ');
    final ligne = await customSelect(
      "SELECT "
      "COALESCE(SUM(CASE WHEN sync_status = 'conflict' THEN 0 ELSE 1 END), 0) AS a_envoyer, "
      "COALESCE(SUM(CASE WHEN sync_status = 'conflict' THEN 1 ELSE 0 END), 0) AS refuses "
      "FROM ($unions)",
    ).getSingle();

    return (aEnvoyer: ligne.read<int>('a_envoyer'), refuses: ligne.read<int>('refuses'));
  }

  /// Ticket 15.50 — tables d'ACTIVITÉ effacées quand le serveur a été réinitialisé : le miroir de
  /// `ReinitialisationDonneesService::tablesTransactionnelles()`, plus les tables du poste qui en
  /// dérivent (créances fournisseurs, revenus de bande, conflits de synchronisation).
  ///
  /// ⚠️ LISTE EXPLICITE, comme au serveur : chaque table du schéma est classée dans
  /// [tablesDActivite] OU [tablesConservees] — un test le vérifie, pour que la prochaine table
  /// ajoutée ne soit pas oubliée sans bruit.
  static const tablesDActivite = [
    'livestock_lots', 'livestock_daily_entries', 'livestock_transfers',
    'livestock_reproduction_events', 'veterinary_records', 'veterinary_withdrawal_periods',
    'infirmary_records', 'veterinary_calendar_events', // H8b
    'animals', 'lot_revenues',
    'customers', 'receivables', 'customer_advances', 'customer_reminders',
    'advance_imputations', 'sales', 'sale_lines', 'credit_notes', // AV1
    'suppliers', 'purchase_orders', 'purchases', 'purchase_lines', 'purchase_returns',
    'payables', 'supplier_payments', 'supplier_refunds', 'supplier_credits',
    'expenses', 'stock_adjustments', 'stock_movements', // U9
    'quotes', // DEV
    'payslips', // U13
    'employees', 'internships', 'attendance_records',
    'accounting_entries', 'accounting_entry_lines',
    'mails', 'administrative_documents', 'archived_documents', 'notifications',
    'sync_conflicts',
  ];

  /// Référentiels et réglages CONSERVÉS (préservés au serveur ; les comptes restent pour que la
  /// connexion hors ligne survive à une purge suivie d'un tirage interrompu).
  static const tablesConservees = [
    'product_categories', 'products', 'feed_ration_standards', 'growth_standards', 'feed_types',
    'prophylaxis_schedule_standards', 'livestock_species', 'elevage_numbering_settings',
    'chart_of_accounts', 'fiscal_years', 'treasury_accounts', 'expense_categories',
    'company_settings', 'modules_config', 'attestation_templates',
    'roles_applicatifs', 'utilisateurs', 'audit_logs',
    'app_settings', 'sync_state',
  ];

  /// Efface les données d'activité, remet à zéro les soldes qui en dérivent (stock, trésorerie,
  /// comme le serveur) et le curseur de tirage. Rend le nombre d'enregistrements EN ATTENTE perdus.
  ///
  /// ⚠️ Ticket H9b — SEULES LES TABLES EFFACÉES COMPTENT : un barème d'élevage (ou un produit) en attente est
  /// conservé par la purge et repartira ; le compter dans « saisies perdues » annoncerait une perte qui n'a pas
  /// eu lieu.
  Future<int> purgerDonneesDActivite() async {
    final effacees = tablesEnvoyees.where(tablesDActivite.contains);
    final perdus = effacees.isEmpty
        ? 0
        : (await customSelect(
            'SELECT COUNT(*) AS n FROM ('
            '${effacees.map((t) => "SELECT 1 FROM $t WHERE sync_status <> 'synced'").join(' UNION ALL ')})',
          ).getSingle()).read<int>('n');
    await transaction(() async {
      for (final table in tablesDActivite) {
        await customStatement('DELETE FROM $table');
      }
      await customStatement('UPDATE products SET stock_qty = 0');
      await customStatement('UPDATE treasury_accounts SET balance = 0');
      await delete(syncState).go();
    });
    return perdus;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dossier = await getApplicationSupportDirectory();
    final fichier = File(p.join(dossier.path, 'agrierp.sqlite'));

    // ⚠️ `NativeDatabase.createInBackground` SEUL sur Windows Desktop. Ne
    // JAMAIS réintroduire `open.overrideFor(OperatingSystem.windows, ...)` :
    // ce motif a déjà cassé une compilation dans ce projet et n'apporte rien
    // ici, `sqlite3_flutter_libs` fournissant déjà la bibliothèque.
    return NativeDatabase.createInBackground(fichier);
  });
}
