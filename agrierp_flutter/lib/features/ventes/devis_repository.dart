import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/export/document_officiel.dart';
import '../../core/temps/heure_benin.dart';
import '../stocks/pmp_service.dart';

/// Devis refusé avant d'être écrit.
///
/// ⚠️ REFUSER AVANT D'ÉCRIRE, PAS APRÈS : un devis enregistré localement puis rejeté par le serveur reste des jours dans
/// la file du poste. Les refus sont rendus PAR CHAMP, avec les messages du web (`lang/fr/validation.php` et les noms de
/// champ de `lang/fr/validation.php` → `attributes`) : l'écran les affiche sous leur champ, comme `@error(…)` du Blade.
/// Clés : `client`, `articles`, `montant`, `tva`, `validite`, `date` ; `devis` pour un refus qui n'est celui d'aucun
/// champ (devis archivé ou facturé : toast d'erreur au web).
class DevisRefuse implements Exception {
  DevisRefuse(this.erreurs);

  final Map<String, String> erreurs;

  /// Le premier refus (le champ le plus haut du formulaire).
  String get motif => erreurs.values.first;

  @override
  String toString() => erreurs.values.join(' ');
}

/// Une ligne du tableau « Devis & Proforma » : le devis, le nom de son client, et — pour une saisie refusée du poste —
/// le motif du serveur, mot pour mot.
class LigneDevis {
  const LigneDevis({required this.devis, this.client, this.motifRefus});

  final Quote devis;

  /// `$quote->customer?->name` du Blade ; `null` : client inconnu de ce poste (colonne vide, comme au web).
  final String? client;
  final String? motifRefus;

  /// `getValidUntilAttribute()` du web : date du devis + validité en jours.
  DateTime get valideJusqua => HeureBenin.plusJours(devis.quoteDate, devis.validityDays);

  /// ➕ Ticket DEV3 — la DEMANDE de conversion en facture de ce poste est ouverte : écrite hors ligne, pas encore
  /// acquittée par le serveur (en attente d'envoi, ou refusée). Le devis est alors figé.
  bool get conversionDemandee => devis.conversionRequestedAt != null && devis.convertedSaleId == null;

  /// ➕ Ticket DEV3 — la demande a été REFUSÉE par le serveur ([motifRefus] en donne la raison, mot pour mot).
  bool get conversionRefusee => conversionDemandee && devis.syncStatus == SyncStatus.conflict;
}

/// Ticket DEV3 — le résultat d'une demande de conversion : le devis, et `deja` quand il était déjà facturé (le web
/// répond alors par un avertissement, jamais par une seconde facture).
typedef ConversionDemandee = ({Quote devis, bool deja});

/// Les quatre cartes de `Devis::getKpisProperty()`.
class KpisDevis {
  const KpisDevis({
    required this.devisActifs,
    required this.valeurTotale,
    required this.tauxConversion,
    required this.enAttenteDeRelance,
  });

  final int devisActifs;
  final double valeurTotale;
  final int tauxConversion;
  final int enAttenteDeRelance;
}

class DonneesDevis {
  const DonneesDevis({required this.lignes, required this.kpis, required this.clients});

  final List<LigneDevis> lignes;
  final KpisDevis kpis;

  /// `getCustomersProperty()` : clients ACTIFS, par nom (formulaire et filtre « Client »).
  final List<Customer> clients;
}

/// « Devis & Proforma » au poste — `app/Livewire/Ventes/Devis.php` (maître, article 5) et `SaisieDevisAction`.
///
/// ⚠️⚠️ **LE POSTE ÉCRIT LE FAIT ; LE SERVEUR LE REJOUE** par `SaisieDevisAction` (le point de passage du composant
/// Livewire) : numéro `DEV-AAAA-NNN` attribué par lui seul, exercice clos refusé, changement de statut jugé, audit. Les
/// règles du web sont appliquées ICI avant d'écrire, avec ses messages :
///  - création : `brouillon`, actif, SANS numéro (« — » jusqu'à l'acquittement) ;
///  - modification : tous les champs saisis, sauf numéro et statut ; un devis archivé ou facturé ne se modifie plus ;
///  - statut : un seul pas du cycle `brouillon → envoyé → accepté | refusé`, tout autre changement refusé ;
///  - archivage : logique (`is_active = false`), un second archivage ne fait rien ;
///  - exercice : un devis daté d'un exercice CLOS est en lecture seule (règle `closSeulement`, motif R4), jamais jugé sur
///    une écriture : un devis n'en passe aucune.
class DevisRepository {
  DevisRepository({
    required AppDatabase database,
    required String deviceId,
    Uuid? uuid,
  }) : _db = database,
       // ignore: prefer_initializing_formals
       _deviceId = deviceId,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final String _deviceId;
  final Uuid _uuid;

  ExerciceDeSaisie get _exercice => ExerciceDeSaisie(_db);

  /// Statuts du cycle de vie et leur libellé (`$statusLabels` du Blade), dans l'ordre du filtre « Statut ».
  static const statuts = <String, String>{
    'brouillon': 'Brouillon',
    'envoye': 'Envoyé',
    'accepte': 'Accepté',
    'refuse': 'Refusé',
    'facture': 'Facturé',
  };

  /// Pas autorisés (`SaisieDevisAction::TRANSITIONS`).
  static const transitions = <String, List<String>>{
    'brouillon': ['envoye'],
    'envoye': ['accepte', 'refuse'],
  };

  /// `SaisieDevisAction::MESSAGE_ARCHIVE` du web, mot pour mot.
  static const messageArchive = 'Ce devis est archivé : il ne peut plus être modifié.';

  /// `SaisieDevisAction::MESSAGE_FACTURE` du web, mot pour mot.
  static const messageFacture = 'Ce devis est facturé : il ne peut plus être modifié.';

  /// `SaisieDevisAction::messageStatutInterdit()` du web, mot pour mot.
  static String messageStatutInterdit(String de, String vers) =>
      'Changement de statut interdit : un devis « ${statuts[de] ?? de} » ne peut pas passer à « ${statuts[vers] ?? vers} ».';

  /// Toasts du composant web `Devis` (`$this->dispatch('toast', …)`), mot pour mot.
  static const toastCree = 'Devis créé avec succès.';
  static const toastModifie = 'Devis modifié avec succès.';
  static const toastEnvoye = 'Devis marqué comme envoyé.';
  static const toastAccepte = 'Devis marqué comme accepté.';
  static const toastRefuse = 'Devis marqué comme refusé.';
  static const toastArchive = 'Devis archivé avec succès.';

  /// 🔴→✅ Ticket DEV3 — « Convertir en Facture » est construit : les motifs de refus sont ceux de
  /// `ConvertirDevisEnFactureAction` (mot pour mot, lus par `devis_blade_test.dart`), jugés AVANT d'écrire la demande.
  static const messageConversionArchive = 'Ce devis est archivé : il ne peut pas être converti en facture.';
  static const messageConversionSansClient = "Ce devis n'a pas de client : une facture à crédit en exige un.";
  static String messageConversionStatut(String statut) =>
      'Seul un devis accepté peut être converti en facture : celui-ci est « ${statuts[statut] ?? statut} ».';
  static String messageConversionClientArchive(String nom) =>
      'Le client « $nom » est archivé : réactivez-le avant de facturer ce devis.';
  static String messageConversionPlanIncomplet(String code, String libelle) =>
      'Plan comptable incomplet : le compte $code ($libelle) est introuvable. '
      'Complétez le plan comptable puis relancez la conversion.';

  /// Toast du web quand le devis est déjà converti (`convertToInvoice()`).
  static String toastDejaFacture(String numero) => 'Ce devis est déjà facturé : facture $numero.';

  /// ⚠️ ÉCART ASSUMÉ (fonction propre au poste hors ligne, doctrine § 5.6) : le web convertit sur place et annonce « Devis
  /// converti en facture FV-… avec succès. » ; le poste, sans réseau, écrit la DEMANDE — le numéro de la facture
  /// n'existe qu'au serveur, il apparaît dans le tableau à l'acquittement. Le devis est figé entre-temps.
  static const toastConversionDemandee =
      'Conversion en facture demandée : la facture sera créée à la prochaine synchronisation.';
  static const toastConversionAnnulee = 'Demande de conversion annulée.';
  static const messageConversionDemandee =
      'Une conversion en facture est demandée pour ce devis : il ne peut plus être modifié.';

  /// Comptes de l'écriture de la facture et leur libellé (`ConvertirDevisEnFactureAction::COMPTES`).
  static const comptesDeLaFacture = <String, String>{'411': 'Clients', '701': 'Ventes de produits', '443': 'TVA facturée'};

  /// Valeur par défaut de « Validité (jours) » et de « TVA (%) » du formulaire (`newQuote()` du web).
  static const validiteParDefaut = 15;
  static const tvaParDefaut = 18;

  /// Les deux taux du `<select>` « TVA (%) » du Blade.
  static const tauxTva = [0, 18];

  /// Clients du formulaire et du filtre (`Customer::where('is_active', true)->orderBy('name')`).
  Future<List<Customer>> clients() async {
    final lignes = await (_db.select(_db.customers)..where((t) => t.isActive.equals(true))).get();
    lignes.sort((a, b) => comparerCommeLeServeur(a.name, b.name));
    return lignes;
  }

  /// `getQuotesProperty()` et `getKpisProperty()` du web.
  ///
  /// Liste : devis ACTIFS (`is_active`), recherche `quote_number LIKE %…%` ou nom du client (collation du serveur,
  /// insensible à la casse et aux accents ; `%` et `_` y sont des jokers ; « 0 » ne filtre pas, `when()` le lit faux),
  /// filtre de statut, filtre de client, `orderByDesc('quote_date')`. ➕ Ajout du poste : une saisie REFUSÉE
  /// (`conflict`) reste listée avec son motif, même un ARCHIVAGE refusé (le devis est encore actif au serveur) — c'est
  /// ici que le refus se voit.
  ///
  /// Cartes : sur TOUS les devis actifs, jamais filtrés ; « Taux de Conversion » sur le mois de [maintenant]. Règle U8 :
  /// une saisie en attente d'envoi compte (elle part vers le web), une saisie REFUSÉE n'existe pas au web.
  Future<DonneesDevis> charger({
    String recherche = '',
    String statut = '',
    String clientId = '',
    DateTime? maintenant,
  }) async {
    final clients = await this.clients();
    final tous = await _db.select(_db.customers).get();
    final nomDe = {for (final c in tous) c.id: c.name};

    // Un devis refusé : le motif de sa saisie (`quotes`) ou, plus récent, celui de sa DEMANDE de conversion
    // (`quote_conversions`, ticket DEV3) — ce dernier prime, la saisie ayant été acceptée avant lui.
    final refus = <String, String>{};
    for (final c in await (_db.select(_db.syncConflicts)
          ..where((c) => c.sourceTable.isIn(const ['quotes', 'quote_conversions']))
          ..orderBy([(c) => OrderingTerm(expression: c.sourceTable)]))
        .get()) {
      refus[c.recordId] = c.reason;
    }
    final lignes =
        await (_db.select(_db.quotes)..where(
              (t) => t.isActive.equals(true) | t.syncStatus.equalsValue(SyncStatus.conflict),
            ))
            .get();

    final filtreTexte = recherche.isEmpty || recherche == '0' ? null : _motifLike(recherche);
    bool retenu(Quote d) =>
        (filtreTexte == null ||
            filtreTexte.hasMatch(cleCommeLeServeur(d.quoteNumber ?? '')) ||
            filtreTexte.hasMatch(cleCommeLeServeur(nomDe[d.customerId] ?? ''))) &&
        (statut.isEmpty || d.status == statut) &&
        (clientId.isEmpty || d.customerId == clientId);

    final retenues = [
      for (final d in lignes)
        if (retenu(d)) d,
    ]..sort((a, b) {
        final parDate = b.quoteDate.compareTo(a.quoteDate);
        return parDate != 0 ? parDate : a.id.compareTo(b.id);
      });

    return DonneesDevis(
      lignes: [
        for (final d in retenues)
          LigneDevis(
            devis: d,
            client: nomDe[d.customerId],
            motifRefus: d.syncStatus == SyncStatus.conflict ? refus[d.id] : null,
          ),
      ],
      kpis: _kpis(
        [
          for (final d in lignes)
            if (d.isActive && d.syncStatus != SyncStatus.conflict) d,
        ],
        maintenant ?? HeureBenin.maintenant(),
      ),
      clients: clients,
    );
  }

  /// `LIKE '%…%'` de MySQL sous `utf8mb4_unicode_ci` : `%` = n'importe quelle suite, `_` = un caractère, le reste
  /// littéral, comparé sur la clé de collation ([cleCommeLeServeur]).
  static RegExp _motifLike(String recherche) {
    final motif = StringBuffer();
    for (final c in cleCommeLeServeur(recherche).split('')) {
      motif.write(switch (c) {
        '%' => '.*',
        '_' => '.',
        _ => RegExp.escape(c),
      });
    }
    return RegExp(motif.toString(), dotAll: true);
  }

  /// `Devis::getKpisProperty()` : [actifs] = devis actifs. « Devis Actifs » et « Valeur Totale » : brouillon + envoyé +
  /// accepté ; « Taux de Conversion » : acceptés / (acceptés + refusés) DU MOIS de [maintenant], arrondi, 0 sans devis
  /// jugé ; « En Attente de Relance » : envoyés.
  static KpisDevis _kpis(List<Quote> actifs, DateTime maintenant) {
    final enCours = actifs.where((d) => const ['brouillon', 'envoye', 'accepte'].contains(d.status)).toList();
    final duMois = actifs.where((d) => d.quoteDate.month == maintenant.month && d.quoteDate.year == maintenant.year);
    final acceptes = duMois.where((d) => d.status == 'accepte').length;
    final juges = duMois.where((d) => d.status == 'accepte' || d.status == 'refuse').length;

    return KpisDevis(
      devisActifs: enCours.length,
      valeurTotale: enCours.fold<double>(0, (somme, d) => somme + d.amount),
      tauxConversion: juges > 0 ? PmpService.arrondi(acceptes / juges * 100, 0).round() : 0,
      enAttenteDeRelance: actifs.where((d) => d.status == 'envoye').length,
    );
  }

  /// Règles de `saveQuote()` du web, messages de `lang/fr/validation.php` par champ ; vide si tout est valable.
  ///
  /// `customerId` `required|exists:customers,id` · `articlesDescription` `required|string|max:2000` · `amount`
  /// `required|numeric|min:0` · `tvaRate` `required|numeric|min:0|max:100` · `validityDays` `required|integer|min:1` ·
  /// `quoteDate` `required|date`. Noms de champ du web : client, description des articles, montant, taux de TVA, durée
  /// de validité (jours), date du devis.
  static Map<String, String> valider({
    required String? clientId,
    required String articles,
    required String montant,
    required String tva,
    required String validite,
    required DateTime? date,
    bool clientConnu = true,
  }) {
    final erreurs = <String, String>{};
    if (clientId == null || clientId.isEmpty) {
      erreurs['client'] = 'Le champ client est obligatoire.';
    } else if (!clientConnu) {
      erreurs['client'] = "La valeur sélectionnée pour le champ client n'existe pas.";
    }
    if (articles.trim().isEmpty) {
      erreurs['articles'] = 'Le champ description des articles est obligatoire.';
    } else if (articles.runes.length > 2000) {
      erreurs['articles'] = 'Le champ description des articles ne doit pas dépasser 2000 caractères.';
    }

    final m = montant.trim();
    final valeur = double.tryParse(m.replaceAll(',', '.'));
    if (m.isEmpty) {
      erreurs['montant'] = 'Le champ montant est obligatoire.';
    } else if (valeur == null || !valeur.isFinite) {
      erreurs['montant'] = 'Le champ montant doit être un nombre.';
    } else if (valeur < 0) {
      erreurs['montant'] = 'Le champ montant doit être au moins égal à 0.';
    }

    final t = tva.trim();
    final taux = double.tryParse(t.replaceAll(',', '.'));
    if (t.isEmpty) {
      erreurs['tva'] = 'Le champ taux de TVA est obligatoire.';
    } else if (taux == null || !taux.isFinite) {
      erreurs['tva'] = 'Le champ taux de TVA doit être un nombre.';
    } else if (taux < 0) {
      erreurs['tva'] = 'Le champ taux de TVA doit être au moins égal à 0.';
    } else if (taux > 100) {
      erreurs['tva'] = 'Le champ taux de TVA ne doit pas dépasser 100.';
    }

    final v = validite.trim();
    final jours = int.tryParse(v);
    if (v.isEmpty) {
      erreurs['validite'] = 'Le champ durée de validité (jours) est obligatoire.';
    } else if (jours == null) {
      erreurs['validite'] = 'Le champ durée de validité (jours) doit être un nombre entier.';
    } else if (jours < 1) {
      erreurs['validite'] = 'Le champ durée de validité (jours) doit être au moins égal à 1.';
    }

    if (date == null) {
      erreurs['date'] = 'Le champ date du devis est obligatoire.';
    }
    return erreurs;
  }

  /// Enregistre un devis (création, ou modification de [idEnModification]), en attente d'envoi.
  ///
  /// ⚠️ **LES MÊMES BORNES QUE LE WEB, APPLIQUÉES ICI** ([valider]) ; puis, en modification, les refus de
  /// `SaisieDevisAction::modifier()` (devis archivé, devis facturé : sous « devis », toast d'erreur au web) et celui de
  /// l'exercice clos (motif R4, sous « Date du Devis »), de la date d'origine comme de la nouvelle.
  ///
  /// Une modification repasse la ligne en `pending` à l'instant de la saisie (`updatedAt`) ; elle part entière, le
  /// serveur la rejoue. Son ancien refus éventuel est effacé : il portait sur une version dépassée. Le numéro et le
  /// statut ne changent jamais ici.
  Future<Quote> enregistrer({
    required String? clientId,
    required String articles,
    required String montant,
    required String tva,
    required String validite,
    required DateTime? date,
    String note = '',
    String? idEnModification,
  }) async {
    final existant = idEnModification == null
        ? null
        : await (_db.select(_db.quotes)..where((t) => t.id.equals(idEnModification))).getSingleOrNull();
    if (idEnModification != null && existant == null) {
      throw DevisRefuse({'devis': 'Devis introuvable sur ce poste.'});
    }

    final clientConnu =
        clientId == null ||
        clientId.isEmpty ||
        clientId == existant?.customerId ||
        await (_db.select(_db.customers)..where((t) => t.id.equals(clientId))).getSingleOrNull() != null;
    final erreurs = valider(
      clientId: clientId,
      articles: articles,
      montant: montant,
      tva: tva,
      validite: validite,
      date: date,
      clientConnu: clientConnu,
    );
    if (erreurs.isNotEmpty) throw DevisRefuse(erreurs);

    final jour = HeureBenin.jour(date!);
    final valeur = double.parse(montant.trim().replaceAll(',', '.'));
    final taux = double.parse(tva.trim().replaceAll(',', '.'));
    final jours = int.parse(validite.trim());
    final remarque = note.isEmpty ? null : note;
    final maintenant = HeureBenin.versInstant(HeureBenin.maintenant());

    if (existant != null) {
      // Un ARCHIVAGE REFUSÉ par le serveur (`conflict`) laisse le devis actif là-bas : le modifier le garde actif.
      final archivageRefuse = !existant.isActive && existant.syncStatus == SyncStatus.conflict;
      if (!existant.isActive && !archivageRefuse) {
        throw DevisRefuse({'devis': messageArchive});
      }
      if (existant.status == 'facture') {
        throw DevisRefuse({'devis': messageFacture});
      }
      // Ticket DEV3 — une demande de conversion ouverte fige le devis (le serveur le facturerait tel qu'il est).
      if (existant.conversionRequestedAt != null) {
        throw DevisRefuse({'devis': messageConversionDemandee});
      }
      final identique =
          existant.customerId == clientId &&
          existant.articlesDescription == articles &&
          PmpService.arrondi(existant.amount, 2) == PmpService.arrondi(valeur, 2) &&
          PmpService.arrondi(existant.tvaRate, 2) == PmpService.arrondi(taux, 2) &&
          existant.validityDays == jours &&
          HeureBenin.jour(existant.quoteDate) == jour &&
          existant.note == remarque;
      if (identique && !archivageRefuse && existant.syncStatus != SyncStatus.conflict) {
        return existant;
      }
      // `SaisieDevisAction::modifier` : le devis d'un exercice CLOS est en lecture seule (motif R4 de sa date d'origine),
      // et ne passe pas non plus dans un exercice clos (motif R4 de la nouvelle date).
      try {
        await _exercice.refuser(existant.quoteDate, regle: RegleExercice.closSeulement);
      } on RefusExercice catch (e) {
        throw DevisRefuse({'date': e.motif});
      }
      await _refuserDate(jour);

      await _db.transaction(() async {
        await (_db.update(_db.quotes)..where((t) => t.id.equals(existant.id))).write(
          QuotesCompanion(
            customerId: Value(clientId!),
            articlesDescription: Value(articles),
            amount: Value(valeur),
            tvaRate: Value(taux),
            validityDays: Value(jours),
            quoteDate: Value(jour),
            note: Value(remarque),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: Value(maintenant),
          ),
        );
        await _effacerRefus(existant.id);
      });
      return _lire(existant.id);
    }

    await _refuserDate(jour);

    final id = _uuid.v4();
    await _db
        .into(_db.quotes)
        .insert(
          QuotesCompanion.insert(
            id: id,
            deviceId: _deviceId,
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: maintenant,
            customerId: clientId!,
            articlesDescription: articles,
            amount: valeur,
            tvaRate: Value(taux),
            validityDays: Value(jours),
            quoteDate: jour,
            note: Value(remarque),
          ),
        );
    return _lire(id);
  }

  /// Exercice clos qui couvre [jour] : refusé sous « Date du Devis » (`SaisieDevisAction::creer` / `modifier`).
  Future<void> _refuserDate(DateTime jour) async {
    try {
      await _exercice.refuser(jour, regle: RegleExercice.closSeulement);
    } on RefusExercice catch (e) {
      throw DevisRefuse({'date': e.motif});
    }
  }

  /// Un pas du cycle de vie (`markAsSent` / `markAsAccepted` / `markAsRefused` du web) : le devis part à l'envoi
  /// (`pending`), le serveur le rejoue. Même statut : rien. Rend `false` quand rien n'a été écrit.
  ///
  /// Refuse (`DevisRefuse`, clé `devis` : toast d'erreur au web) : devis archivé, pas interdit, devis d'un exercice clos.
  Future<bool> changerStatut(String id, String statut) async {
    return _db.transaction(() async {
      final d = await (_db.select(_db.quotes)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (d == null) throw DevisRefuse({'devis': 'Devis introuvable sur ce poste.'});
      if (d.status == statut && d.isActive) return false;
      if (!d.isActive && d.syncStatus != SyncStatus.conflict) {
        throw DevisRefuse({'devis': messageArchive});
      }
      if (d.conversionRequestedAt != null && d.convertedSaleId == null) {
        throw DevisRefuse({'devis': messageConversionDemandee});
      }
      if (!(transitions[d.status] ?? const []).contains(statut)) {
        throw DevisRefuse({'devis': messageStatutInterdit(d.status, statut)});
      }
      try {
        await _exercice.refuser(d.quoteDate, regle: RegleExercice.closSeulement);
      } on RefusExercice catch (e) {
        throw DevisRefuse({'devis': e.motif});
      }
      await (_db.update(_db.quotes)..where((t) => t.id.equals(id))).write(
        QuotesCompanion(
          status: Value(statut),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(HeureBenin.versInstant(HeureBenin.maintenant())),
        ),
      );
      await _effacerRefus(id);
      return true;
    });
  }

  /// `archiveQuote($id)` du web : le devis devient inactif et part à l'envoi (`pending`). Déjà archivé : rien (rend
  /// `false`, pas de toast). Refuse (`DevisRefuse`, clé `devis`) : devis d'un exercice clos.
  Future<bool> archiver(String id) async {
    return _db.transaction(() async {
      final d = await (_db.select(_db.quotes)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (d == null || (!d.isActive && d.syncStatus != SyncStatus.conflict)) return false;
      if (d.conversionRequestedAt != null && d.convertedSaleId == null) {
        throw DevisRefuse({'devis': messageConversionDemandee});
      }
      try {
        await _exercice.refuser(d.quoteDate, regle: RegleExercice.closSeulement);
      } on RefusExercice catch (e) {
        throw DevisRefuse({'devis': e.motif});
      }
      await (_db.update(_db.quotes)..where((t) => t.id.equals(id))).write(
        QuotesCompanion(
          isActive: const Value(false),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(HeureBenin.versInstant(HeureBenin.maintenant())),
        ),
      );
      await _effacerRefus(id);
      return true;
    });
  }

  /// 🔴→✅ Ticket DEV3 — « CONVERTIR EN FACTURE » (`convertToInvoice()` du web, `ConvertirDevisEnFactureAction`).
  ///
  /// ⚠️⚠️ **LE POSTE N'ÉCRIT QUE LA DEMANDE.** La facture est une vente à crédit sans ligne que le SERVEUR crée, numérote
  /// (`FV-AAAA-XXXXXX`), comptabilise et lie au devis ; elle revient à l'acquittement (`SyncEngine`). Les refus de
  /// l'action sont jugés ICI avant d'écrire (même ordre, mêmes motifs, mot pour mot) : devis inconnu ; déjà converti
  /// (`deja`, aucune seconde demande) ; demande déjà ouverte ; archivé ; statut autre qu'`accepte` ; client absent ou
  /// archivé ; devis d'un exercice clos (lecture seule) ; date de la facture (aujourd'hui) future, ou d'un exercice absent
  /// ou clos (« Facture refusée : … ») ; plan comptable incomplet (juge seulement si le plan est connu de ce poste : un
  /// poste qui ne l'a pas tiré laisse le serveur trancher). Droits : `manage-ventes` ET `manage-facturation`, jugés par
  /// l'écran (bouton) et par le serveur (refus motivé).
  ///
  /// Écrit : `conversion_requested_at` = l'instant du clic (heure du Bénin ; le serveur date la facture de ce jour-là), le
  /// devis repart en `pending`. Il est figé jusqu'à l'acquittement.
  Future<ConversionDemandee> demanderConversion(String id, {DateTime? maintenant}) async {
    final instant = maintenant ?? HeureBenin.maintenant();
    return _db.transaction(() async {
      final d = await (_db.select(_db.quotes)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (d == null) throw DevisRefuse({'devis': 'Devis introuvable sur ce poste.'});
      if (d.status == 'facture' && d.convertedSaleId != null) return (devis: d, deja: true);
      if (d.conversionRequestedAt != null) throw DevisRefuse({'devis': messageConversionDemandee});
      if (!d.isActive) throw DevisRefuse({'devis': messageConversionArchive});
      if (d.status != 'accepte') throw DevisRefuse({'devis': messageConversionStatut(d.status)});

      final client = await (_db.select(_db.customers)..where((t) => t.id.equals(d.customerId))).getSingleOrNull();
      if (client == null) throw DevisRefuse({'devis': messageConversionSansClient});
      if (!client.isActive) throw DevisRefuse({'devis': messageConversionClientArchive(client.name)});

      // Le devis d'un exercice clos est en lecture seule (EF6) : le passer à « facturé » le modifierait.
      try {
        await _exercice.refuser(d.quoteDate, regle: RegleExercice.closSeulement);
      } on RefusExercice catch (e) {
        throw DevisRefuse({'devis': e.motif});
      }
      // `VerifySaleDateAction` : la date de la facture est jugée comme celle de toute vente (futur : jamais, c'est
      // aujourd'hui ; exercice absent ou clos), préfixée « Facture refusée : ».
      final refusDate = await _exercice.refus(HeureBenin.jour(instant));
      if (refusDate != null) {
        throw DevisRefuse({
          'devis': ExerciceDeSaisie.prefixeVente(refusDate).replaceFirst('Vente refusée', 'Facture refusée'),
        });
      }
      await _exigerLePlanComptable(d);

      await _db.update(_db.quotes).replace(
        d.copyWith(
          conversionRequestedAt: Value(instant),
          syncStatus: SyncStatus.pending,
          updatedAt: HeureBenin.versInstant(instant),
        ),
      );
      await _effacerRefus(id);
      return (devis: await _lire(id), deja: false);
    });
  }

  /// Plan comptable incomplet : 411, 701 et — si le devis porte une TVA ET que l'exploitation y est assujettie
  /// (`TvaSettingService` : sans réglage connu, assujettie, comme le serveur) — 443. Un plan inconnu de ce poste (jamais
  /// tiré) ne juge rien : le serveur le fera.
  Future<void> _exigerLePlanComptable(Quote d) async {
    final comptes = await _db.select(_db.chartOfAccounts).get();
    if (comptes.isEmpty) return;
    final reglage = await _db.select(_db.companySettings).getSingleOrNull();
    final avecTva = (reglage?.tvaEnabled ?? true) && d.tvaRate > 0;
    final codes = {for (final c in comptes) c.code};
    for (final MapEntry(key: code, value: libelle) in comptesDeLaFacture.entries) {
      if (code == '443' && !avecTva) continue;
      if (!codes.contains(code)) throw DevisRefuse({'devis': messageConversionPlanIncomplet(code, libelle)});
    }
  }

  /// ➕ Ticket DEV3 (poste seul) — « Annuler la demande » : la demande de conversion REFUSÉE par le serveur est retirée et le
  /// devis redevient libre (`accepte`, modifiable). Seule une demande REFUSÉE s'annule ici : une demande en attente
  /// d'envoi part à la prochaine synchronisation. Rend `false` quand il n'y avait rien à annuler.
  Future<bool> annulerConversion(String id) async {
    return _db.transaction(() async {
      final d = await (_db.select(_db.quotes)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (d == null || d.conversionRequestedAt == null || d.convertedSaleId != null) return false;
      if (d.syncStatus != SyncStatus.conflict) return false;
      await (_db.update(_db.quotes)..where((t) => t.id.equals(id))).write(
        QuotesCompanion(
          conversionRequestedAt: const Value(null),
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: Value(HeureBenin.versInstant(HeureBenin.maintenant())),
        ),
      );
      await _effacerRefus(id);
      return true;
    });
  }

  Future<void> _effacerRefus(String id) =>
      (_db.delete(_db.syncConflicts)..where((c) => c.id.isIn(['quotes:$id', 'quote_conversions:$id']))).go();

  Future<Quote> _lire(String id) => (_db.select(_db.quotes)..where((t) => t.id.equals(id))).getSingle();

  /// `exports.devis` du web (`PdfExportService::render('exports.devis', …, 'Devis & Proforma', 'État au d/m/Y')`) : les
  /// devis AFFICHÉS (filtres actifs), colonnes N° Devis · Client · Date · Montant · Statut. Une liste vide donne la ligne
  /// « Aucun devis ne correspond aux filtres actifs. » — le web édite aussi un état vide. Nom du fichier :
  /// `devis-AAAA-MM-JJ.pdf`.
  static DocumentOfficiel documentPdf(List<LigneDevis> lignes, DateTime maintenant) {
    String deux(int n) => n.toString().padLeft(2, '0');
    String jour(DateTime d) => '${deux(d.day)}/${deux(d.month)}/${d.year}';
    final enAttente = lignes.where((l) => l.devis.syncStatus != SyncStatus.synced).length;

    return DocumentOfficiel(
      titre: 'Devis & Proforma',
      sousTitre: 'État au ${jour(maintenant)}',
      entetes: const ['N° Devis', 'Client', 'Date', 'Montant', 'Statut'],
      fichier: 'devis-{jour}.pdf',
      lignes: [
        if (lignes.isEmpty)
          const DonneesDocument(['Aucun devis ne correspond aux filtres actifs.', '', '', '', ''])
        else
          for (final l in lignes)
            DonneesDocument([
              l.devis.quoteNumber ?? '—',
              l.client ?? '—',
              jour(l.devis.quoteDate),
              '${PmpService.francs(l.devis.amount)} FCFA',
              statuts[l.devis.status] ?? l.devis.status,
            ]),
      ],
      noteDePied: enAttente == 0
          ? null
          : '$enAttente devis saisi(s) sur ce poste, pas encore reçu(s) par la ferme (en attente de synchronisation) : '
                "« — » en N° Devis, le serveur l'attribue à la synchronisation.",
    );
  }
}
