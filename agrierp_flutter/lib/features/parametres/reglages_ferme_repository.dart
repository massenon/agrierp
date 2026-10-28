import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/fichiers_entreprise.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';

/// Saisie refusée AVANT d'être écrite : un message par champ (les clés du Blade), ou `formulaire`.
/// Un fichier image choisi (nom et octets) pour le logo ou le favicon.
typedef FichierChoisi = ({String nom, Uint8List octets});

class ReglageRefuse implements Exception {
  const ReglageRefuse(this.erreurs);

  final Map<String, String> erreurs;

  @override
  String toString() => erreurs.values.join(' ');
}

/// Une tranche du barème ITS en cours de saisie.
class TrancheSaisie {
  const TrancheSaisie({required this.de, required this.a, required this.taux});

  final double de;
  final double? a;
  final double taux;
}

/// Tickets PA-2, PA-3, PA-4, PA-7, PA-8 — LES RÉGLAGES DE LA FERME s'écrivent au poste en DEMANDES (`settings_requests`).
/// UN SEUL ÉCRIVAIN de cette table.
///
/// ⚠️ Le poste écrit la DEMANDE (`pending`) ; le serveur la joue par les services du web (`EntrepriseService`, `BaremeItsService`,
/// `ModesPaiementService`, `RoleService`) avec les mêmes règles, les mêmes messages et les mêmes verrous
/// administrateur ; l'état redescend au tirage. Ce dépôt REPRODUIT les refus du web avant d'écrire, pour que la saisie soit
/// refusée tout de suite, mais le serveur reste le juge. 
class ReglagesFermeRepository {
  ReglagesFermeRepository({required this.database, this.deviceId = 'poste', Uuid? uuid, this.horloge, FichiersEntreprise? fichiersEntreprise})
    : _uuid = uuid ?? const Uuid(),
      fichiersEntreprise = fichiersEntreprise ?? FichiersEntreprise.courant;

  final AppDatabase database;
  final String deviceId;
  final Uuid _uuid;
  final DateTime Function()? horloge;
  final FichiersEntreprise fichiersEntreprise;

  DateTime _maintenant() => (horloge ?? HeureBenin.maintenant)();

  static const rolesFondamentaux = ['admin', 'comptable', 'caissier', 'animalier'];

  Future<String> _ecrire(String kind, Map<String, Object?> contenu, {String? id}) async {
    final cle = id ?? _uuid.v4();
    await database.into(database.settingsRequests).insert(
      SettingsRequestsCompanion.insert(
        id: cle,
        deviceId: deviceId,
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: _maintenant(),
        kind: kind,
        payload: jsonEncode(contenu),
      ),
    );
    return cle;
  }

  /// Demandes pas encore jouées (en attente d'envoi) ou refusées, avec le motif du serveur.
  Future<List<({SettingsRequest demande, String? motif})>> enAttente({String? kind}) async {
    final refus = {for (final c in await database.select(database.syncConflicts).get()) c.id: c.reason};
    final lignes = await (database.select(database.settingsRequests)
          ..where((r) => r.syncStatus.equalsValue(SyncStatus.synced).not())
          ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)]))
        .get();
    return [
      for (final r in lignes)
        if (kind == null || r.kind == kind)
          (demande: r, motif: r.syncStatus == SyncStatus.conflict ? refus['settings_requests:${r.id}'] : null),
    ];
  }

  Future<CompanySetting?> entreprise() => (database.select(database.companySettings)..where((c) => c.id.equals('unique'))).getSingleOrNull();

  // ── PA-3 · Données de l'entreprise ───────────────────────────────────────

  static double? _nombre(String brut) => double.tryParse(brut.trim().replaceAll(',', '.'));

  /// Règles de `EntrepriseService::regles` + verrou des taux (administrateur après la première configuration).
  Future<Map<String, String>> validerEntreprise({
    required String raisonSociale,
    required String ifu,
    required String email,
    required String vps,
    required String cnssSalarie,
    required String cnssPension,
    required String cnssFamille,
    required String cnssRisque,
    required bool estAdmin,
  }) async {
    final e = <String, String>{};
    if (raisonSociale.trim().isEmpty) {
      e['companyName'] = 'Le champ raison sociale est obligatoire.';
    } else if (raisonSociale.trim().length > 150) {
      e['companyName'] = 'Le champ raison sociale ne doit pas dépasser 150 caractères.';
    }
    if (ifu.trim().isEmpty) {
      e['ifu'] = 'Le champ IFU est obligatoire.';
    } else if (!RegExp(r'^[0-9]+$').hasMatch(ifu.trim())) {
      e['ifu'] = "L'IFU doit contenir uniquement des chiffres.";
    } else if (ifu.trim().length > 50) {
      e['ifu'] = 'Le champ IFU ne doit pas dépasser 50 caractères.';
    }
    if (email.trim().isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      e['email'] = 'Le champ adresse e-mail doit être une adresse e-mail valide.';
    }
    void taux(String cle, String libelle, String brut, double min, double max) {
      final v = _nombre(brut);
      if (brut.trim().isEmpty) {
        e[cle] = 'Le champ $libelle est obligatoire.';
      } else if (v == null) {
        e[cle] = 'Le champ $libelle doit être un nombre.';
      } else if (v < min) {
        e[cle] = 'Le champ $libelle doit être au moins égal à ${_s(min)}.';
      } else if (v > max) {
        e[cle] = 'Le champ $libelle ne doit pas dépasser ${_s(max)}.';
      }
    }

    taux('vpsRate', 'taux du VPS', vps, 0, 10);
    taux('cnssEmployeeRate', 'taux CNSS salarié', cnssSalarie, 0, 20);
    taux('cnssEmployerPensionRate', 'taux CNSS employeur (pension)', cnssPension, 0, 20);
    taux('cnssEmployerFamilyRate', 'taux CNSS employeur (prestations familiales)', cnssFamille, 0, 20);
    taux('cnssEmployerRiskRate', 'taux CNSS employeur (risques professionnels)', cnssRisque, 1, 4);

    final actuel = await entreprise();
    if (e.isEmpty && actuel != null && actuel.payrollLocked && !estAdmin) {
      bool change(double? ancien, String neuf) => (ancien ?? double.nan) != _nombre(neuf);
      if (change(actuel.vpsRate, vps) ||
          change(actuel.cnssEmployeeRate, cnssSalarie) ||
          change(actuel.cnssEmployerPensionRate, cnssPension) ||
          change(actuel.cnssEmployerFamilyRate, cnssFamille) ||
          change(actuel.cnssEmployerRiskRate, cnssRisque)) {
        e['vpsRate'] = 'Les taux de charges sociales ont été arrêtés le ${actuel.payrollEditedAt ?? '—'}. Seul un administrateur peut les modifier.';
      }
    }
    return e;
  }

  static String _s(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  Future<void> enregistrerEntreprise({
    required String raisonSociale,
    required String promoteur,
    required String adresse,
    required String telephone,
    required String email,
    required String ifu,
    required String rccm,
    required bool tva,
    required String vps,
    required String cnssSalarie,
    required String cnssPension,
    required String cnssFamille,
    required String cnssRisque,
    required bool estAdmin,
    FichierChoisi? logo,
    FichierChoisi? favicon,
  }) async {
    final refus = await validerEntreprise(
      raisonSociale: raisonSociale, ifu: ifu, email: email, vps: vps, cnssSalarie: cnssSalarie,
      cnssPension: cnssPension, cnssFamille: cnssFamille, cnssRisque: cnssRisque, estAdmin: estAdmin,
    );
    final refusFichiers = <String, String>{
      for (final (champ, genre, f) in [('logoFile', 'logo', logo), ('faviconFile', 'favicon', favicon)])
        if (f != null && FichiersEntreprise.valider(genre, f.nom, f.octets.length) != null) champ: FichiersEntreprise.valider(genre, f.nom, f.octets.length)!,
    };
    if (refus.isNotEmpty || refusFichiers.isNotEmpty) throw ReglageRefuse({...refus, ...refusFichiers});

    // Ticket AUT-2 — le fichier est gardé tout de suite sur le poste (autonomie) ; la demande ne porte que le drapeau, les octets
    // sont lus au moment d'envoyer.
    for (final (genre, f) in [('logo', logo), ('favicon', favicon)]) {
      if (f != null) await fichiersEntreprise.enregistrer(genre, f.octets, f.nom);
    }

    await _ecrire('entreprise', {
      if (logo != null) 'logoNom': logo.nom,
      if (favicon != null) 'faviconNom': favicon.nom,
      'companyName': raisonSociale.trim(), 'promoterName': promoteur.trim(), 'address': adresse.trim(), 'phone': telephone.trim(),
      'email': email.trim(), 'ifu': ifu.trim(), 'rccm': rccm.trim(), 'tvaEnabled': tva,
      'vpsRate': _nombre(vps), 'cnssEmployeeRate': _nombre(cnssSalarie), 'cnssEmployerPensionRate': _nombre(cnssPension),
      'cnssEmployerFamilyRate': _nombre(cnssFamille), 'cnssEmployerRiskRate': _nombre(cnssRisque),
    });
  }

  // ── PA-7 · Barème ITS ────────────────────────────────────────────────────

  Future<List<IncomeTaxBracket>> bareme() =>
      (database.select(database.incomeTaxBrackets)..orderBy([(t) => OrderingTerm.asc(t.fromAmount)])).get();

  /// `BaremeItsService::verifierCoherence`, mot pour mot.
  static String? verifierCoherence(List<TrancheSaisie> saisies) {
    if (saisies.isEmpty) return 'Le barème doit comporter au moins une tranche.';
    final t = [...saisies]..sort((a, b) => a.de.compareTo(b.de));
    if (t.first.de != 0) {
      return 'La première tranche doit partir de 0 : sans elle, les revenus les plus bas ne seraient couverts par aucune tranche.';
    }
    for (var i = 0; i < t.length; i++) {
      if (t[i].taux < 0 || t[i].taux > 100) return 'Un taux doit être compris entre 0 et 100 %.';
      if (i == t.length - 1) {
        if (t[i].a != null) {
          return 'La dernière tranche doit être ouverte (sans plafond) : sinon les revenus au-delà ne seraient pas imposés du tout.';
        }
        continue;
      }
      if (t[i].a == null) return 'Seule la dernière tranche peut être sans plafond.';
      if (t[i].a! <= t[i].de) return "Le plafond d'une tranche doit être supérieur à son plancher.";
      if (t[i + 1].de != t[i].a) {
        return 'Les tranches doivent se suivre sans trou ni chevauchement : la tranche suivante doit commencer exactement à '
            '${_espaces(t[i].a!.round())} FCFA.';
      }
    }
    return null;
  }

  static String _espaces(int n) {
    final s = n.abs().toString();
    final morceaux = <String>[];
    for (var i = s.length; i > 0; i -= 3) {
      morceaux.insert(0, s.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${n < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  Future<void> enregistrerBareme(List<TrancheSaisie> tranches, {required bool estAdmin}) async {
    final c = await entreprise();
    if (c != null && c.payrollLocked && !estAdmin) {
      throw ReglageRefuse({'tranches': 'Le barème a déjà été arrêté le ${c.payrollEditedAt ?? '—'}. Seul un administrateur peut le modifier.'});
    }
    final erreur = verifierCoherence(tranches);
    if (erreur != null) throw ReglageRefuse({'tranches': erreur});

    await _ecrire('bareme_its', {
      'tranches': [for (final t in tranches) {'from': t.de, 'to': t.a, 'rate': t.taux}],
    });
  }

  // ── PA-4 · Modes de paiement ─────────────────────────────────────────────

  Future<void> creerBanque({required String banque, required String titulaire, required String rib, required String iban, String compte = ''}) async {
    final e = <String, String>{};
    if (banque.trim().isEmpty) e['bankName'] = 'Le champ bank name est obligatoire.';
    if (rib.trim().isEmpty) {
      e['rib'] = 'Le champ rib est obligatoire.';
    } else if (rib.trim().length > 100) {
      e['rib'] = 'Le champ rib ne doit pas dépasser 100 caractères.';
    }
    if (iban.trim().isEmpty) {
      e['iban'] = 'Le champ iban est obligatoire.';
    } else if (iban.trim().length > 40) {
      e['iban'] = 'Le champ iban ne doit pas dépasser 40 caractères.';
    }
    if (e.isNotEmpty) throw ReglageRefuse(e);

    await _ecrire('mode_paiement', {
      'geste': 'banque', 'bankName': banque.trim(), 'holderName': titulaire.trim(), 'rib': rib.trim(), 'iban': iban.trim(), 'accountCode': compte.trim(),
    });
  }

  Future<void> creerMomo({required String operateur, required String telephone, String titulaire = '', String sim = '', String compte = ''}) async {
    final e = <String, String>{};
    if (operateur.trim().isEmpty) e['operatorName'] = 'Le champ operator name est obligatoire.';
    if (telephone.trim().isEmpty) {
      e['phoneNumber'] = 'Le champ numéro de téléphone est obligatoire.';
    } else if (telephone.trim().length > 30) {
      e['phoneNumber'] = 'Le champ numéro de téléphone ne doit pas dépasser 30 caractères.';
    }
    if (e.isNotEmpty) throw ReglageRefuse(e);

    await _ecrire('mode_paiement', {
      'geste': 'momo', 'operatorName': operateur.trim(), 'phoneNumber': telephone.trim(), 'holderName': titulaire.trim(), 'simSerial': sim.trim(), 'accountCode': compte.trim(),
    });
  }

  /// Virement interne : refus du web (comptes différents, montant, solde) reproduits sur les soldes DU POSTE ; le solde réel
  /// reste jugé par le serveur.
  Future<void> virer({required String sourceId, required String destinationId, required String montant, String motif = ''}) async {
    final e = <String, String>{};
    final comptes = {for (final c in await database.select(database.treasuryAccounts).get()) c.id: c};
    if (sourceId.isEmpty) e['transferFromId'] = 'Le champ compte source est obligatoire.';
    if (destinationId.isEmpty) {
      e['transferToId'] = 'Le champ compte destinataire est obligatoire.';
    } else if (destinationId == sourceId) {
      e['transferToId'] = 'Le compte destinataire doit être différent du compte source.';
    }
    final m = _nombre(montant);
    if (montant.trim().isEmpty) {
      e['transferAmount'] = 'Le champ montant est obligatoire.';
    } else if (m == null) {
      e['transferAmount'] = 'Le champ montant doit être un nombre.';
    } else if (m < 1) {
      e['transferAmount'] = 'Le champ montant doit être au moins égal à 1.';
    } else if (comptes[sourceId] != null && comptes[sourceId]!.balance.roundToDouble() < m) {
      e['transferAmount'] = 'Solde insuffisant sur ${comptes[sourceId]!.label} : ${_espaces(comptes[sourceId]!.balance.round())} FCFA disponibles.';
    }
    if (motif.trim().length > 150) e['transferReason'] = 'Le champ motif du virement ne doit pas dépasser 150 caractères.';
    if (e.isNotEmpty) throw ReglageRefuse(e);

    await _ecrire('mode_paiement', {
      'geste': 'virement', 'transferFromId': sourceId, 'transferToId': destinationId, 'transferAmount': m, 'transferReason': motif.trim(),
    });
  }

  // ── PA-2 · Rôles & permissions ───────────────────────────────────────────

  Future<List<String>> droits() async =>
      [for (final p in await (database.select(database.permissionsApplicatives)..orderBy([(p) => OrderingTerm.asc(p.name)])).get()) p.name];

  /// `RoleService` : nom en minuscules, chiffres et tirets, unique ; l'administrateur seul.
  Future<void> enregistrerRole({String? ancienNom, required String nom, required Set<String> permissions, required bool estAdmin}) async {
    if (!estAdmin) throw const ReglageRefuse({'formulaire': "Seul l'administrateur peut gérer les rôles."});
    final e = <String, String>{};
    final n = nom.trim();
    if (n.isEmpty) {
      e['roleName'] = 'Le champ nom du rôle est obligatoire.';
    } else if (n.length > 50) {
      e['roleName'] = 'Le champ nom du rôle ne doit pas dépasser 50 caractères.';
    } else if (!RegExp(r'^[a-z0-9\-]+$').hasMatch(n)) {
      e['roleName'] = 'Le nom du rôle ne doit contenir que des lettres minuscules, chiffres et tirets (ex : responsable-achats).';
    } else {
      final pris = await (database.select(database.rolesApplicatifs)..where((r) => r.name.equals(n))).get();
      if (pris.any((r) => r.name != ancienNom)) e['roleName'] = 'La valeur du champ nom du rôle est déjà utilisée.';
    }
    if (e.isNotEmpty) throw ReglageRefuse(e);

    await _ecrire('role', {'ancienNom': ancienNom, 'roleName': n, 'permissions': permissions.toList()..sort()});
  }

  /// Rend le motif de refus du web (rôle fondamental, rôle encore porté), ou écrit la demande de suppression.
  Future<String?> supprimerRole(String nom, {required bool estAdmin}) async {
    if (!estAdmin) throw const ReglageRefuse({'formulaire': "Seul l'administrateur peut gérer les rôles."});
    if (rolesFondamentaux.contains(nom)) {
      return "Le rôle « $nom » fait partie des 4 rôles fondamentaux du système et ne peut jamais être supprimé.";
    }
    final porteurs = await (database.select(database.utilisateurs)..where((u) => u.role.equals(nom) & u.isActive.equals(true))).get();
    if (porteurs.isNotEmpty) return 'Impossible de supprimer « $nom » : ${porteurs.length} utilisateur(s) porte(nt) encore ce rôle.';

    await _ecrire('role', {'geste': 'supprimer', 'roleName': nom});
    return null;
  }
}
