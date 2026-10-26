import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/sync/gestes_importants.dart';
import '../../core/temps/heure_benin.dart';
import '../stocks/pmp_service.dart' show cleUnicite;

/// Un type de la Corbeille, dans l'ordre de `CorbeilleService::registre()` (ticket ARC3, PRD `docs/prd/archives.md`).
///
/// ⚠️ LA LISTE EST LA COPIE DU REGISTRE DU SERVEUR : libellés, modules et règles par type sont comparés, mot pour mot, par
/// `test/corbeille_blade_test.dart` (qui LIT le PHP). Un type ajouté au serveur et oublié ici rougit ce test.
class TypeCorbeille {
  const TypeCorbeille(this.cle, this.libelle, this.module, {this.restaurationInterdite = false, this.suppressionAdmise = false});

  final String cle;
  final String libelle;
  final String module;

  /// Dépense, vente annulée, transfert annulé : consultation seule (PRD § 5.1).
  final bool restaurationInterdite;

  /// `si_non_reference` / `sans_reference` au serveur ; les autres ne se suppriment jamais (PRD § 5.2).
  final bool suppressionAdmise;
}

class TypesCorbeille {
  const TypesCorbeille._();

  static const tous = <TypeCorbeille>[
    TypeCorbeille('produits', 'Produit', 'stocks', suppressionAdmise: true),
    TypeCorbeille('fournisseurs', 'Fournisseur', 'achats', suppressionAdmise: true),
    TypeCorbeille('clients', 'Client', 'ventes', suppressionAdmise: true),
    TypeCorbeille('depenses', 'Dépense', 'achats', restaurationInterdite: true),
    TypeCorbeille('bandes', 'Bande', 'elevage'),
    TypeCorbeille('soins', 'Soin vétérinaire', 'elevage'),
    TypeCorbeille('rations', 'Ration normative', 'elevage', suppressionAdmise: true),
    TypeCorbeille('provendes', 'Type de provende', 'elevage', suppressionAdmise: true),
    TypeCorbeille('prophylaxie', 'Protocole prophylactique', 'elevage', suppressionAdmise: true),
    TypeCorbeille('absences', 'Absence de stagiaire', 'rh', suppressionAdmise: true),
    TypeCorbeille('documents', 'Document administratif', 'administration', suppressionAdmise: true),
    TypeCorbeille('pieces', 'Pièce archivée', 'administration', suppressionAdmise: true),
    TypeCorbeille('courriers', 'Courrier', 'administration'),
    TypeCorbeille('comptes', 'Compte du plan', 'comptabilite'),
    TypeCorbeille('devis', 'Devis', 'ventes'),
    TypeCorbeille('avances', 'Avance client', 'ventes'),
    TypeCorbeille('employes', 'Employé', 'rh', suppressionAdmise: true),
    TypeCorbeille('pointages', 'Pointage', 'rh'),
    TypeCorbeille('ventes', 'Vente annulée', 'ventes', restaurationInterdite: true),
    TypeCorbeille('transferts', 'Transfert annulé', 'elevage', restaurationInterdite: true),
  ];

  static TypeCorbeille? de(String cle) {
    for (final t in tous) {
      if (t.cle == cle) return t;
    }
    return null;
  }
}

/// Une ligne de la page : un élément de l'instantané du serveur, ou une entité archivée ICI et pas encore connue de lui.
class LigneCorbeille {
  const LigneCorbeille({
    required this.type,
    required this.libelleType,
    required this.module,
    required this.elementId,
    required this.titre,
    required this.detail,
    required this.archiveLe,
    required this.restaurable,
    required this.motifRestauration,
    required this.supprimable,
    required this.motifSuppression,
    required this.locale,
    this.archivePar,
    this.demande,
    this.refus,
  });

  final String type;
  final String libelleType;
  final String module;
  final String elementId;
  final String titre;
  final String detail;
  final DateTime? archiveLe;

  /// Ticket ARC-Q2 — qui a archivé, tel que le serveur le sert ; `null` : inconnu (affiché « — »). Une entité archivée
  /// ICI et pas encore servie n'a pas d'auteur : le poste ne le devine pas.
  final String? archivePar;
  final bool restaurable;
  final String? motifRestauration;
  final bool supprimable;
  final String? motifSuppression;

  /// Archivée sur CE poste, pas encore dans l'instantané : les règles de la ligne sont celles du TYPE ; le serveur
  /// juge à l'envoi (références, exercice clos, code déjà pris) et peut refuser.
  final bool locale;

  /// La dernière demande posée pour cet élément (`pending`, `synced` ou `conflict`).
  final DemandeCorbeille? demande;

  /// Motif de refus du serveur, mot pour mot (`sync_conflicts`), quand la demande est refusée.
  final String? refus;

  bool get enAttente => demande?.syncStatus == SyncStatus.pending;
  bool get traitee => demande?.syncStatus == SyncStatus.synced;
  bool get refusee => demande?.syncStatus == SyncStatus.conflict;
}

/// Les trois cartes de la page (`CorbeilleService::cartes`).
class CartesCorbeille {
  const CartesCorbeille({required this.archives, required this.restaurables, required this.supprimables});

  final int archives;
  final int restaurables;
  final int supprimables;
}

/// Résultat d'une demande posée : `ok` (enregistrée, part à la prochaine synchronisation) ou un refus dit à l'écran.
class ResultatDemandeCorbeille {
  const ResultatDemandeCorbeille.ok(this.message) : ok = true;
  const ResultatDemandeCorbeille.refus(this.message) : ok = false;

  final bool ok;
  final String message;
}

/// Ticket ARC3 — LA CORBEILLE AU POSTE. Une entité archivée apparaît dans la page, se restaure ou se supprime
/// définitivement, **par DEMANDE** : le poste enregistre la demande (`corbeille_demandes`), le serveur fait les effets par
/// `CorbeilleService` (le point de passage de la page web) et renvoie le résultat ou le refus.
///
/// ⚠️⚠️ **LE POSTE N'ÉCRIT JAMAIS `is_active` NI NE SUPPRIME UNE LIGNE MÉTIER.** Une restauration rejouée ici serait
/// fausse pour une dépense (contre-passée et réintégrée en trésorerie : le web l'interdit), pour une bande dont le code est
/// repris, pour un élément d'un exercice clos ; une suppression sans le contrôle des références (ventes, mouvements de stock…
/// dans des tables que le poste ne tient pas toutes) laisserait des orphelins. La liste vient donc du serveur
/// (`corbeille_elements`, instantané) avec, pour chaque ligne, ce que le serveur permet et pourquoi.
///
/// **Surcouche locale** : ce que CE poste vient d'archiver (`is_active = 0`, pas encore acquitté) n'est pas encore dans
/// l'instantané ; il apparaît quand même dans la page (règles du TYPE), et la demande qui le vise part APRÈS son
/// archivage (`ordreDuServeur`).
class CorbeilleRepository {
  CorbeilleRepository({required this.database, required this.identifiantPoste, this.horloge, this.gestes});

  final AppDatabase database;
  final String identifiantPoste;
  final GestesImportants? gestes;
  final DateTime Function()? horloge;

  static const _uuid = Uuid();

  /// Les mots du web (`CorbeilleService`), copiés mot pour mot (`corbeille_blade_test.dart` les compare).
  static const motConfirmation = 'SUPPRIMER';
  static const messageConfirmation = 'Pour confirmer, saisissez le mot SUPPRIMER.';
  static const messageIntrouvable = 'Suppression impossible : élément introuvable ou non archivé.';
  static const refusDepense =
      "Cette dépense a été contre-passée au grand livre et son montant réintégré en trésorerie : la restaurer ne rejouerait ni l'un ni l'autre. Saisissez une nouvelle dépense.";
  static const refusVente = 'Une vente annulée a réintégré son stock : elle ne se restaure pas. Saisissez une nouvelle vente.';
  static const refusTransfert =
      'Un transfert annulé a rendu leurs sujets aux deux bandes : le restaurer ne rejouerait pas le mouvement. Saisissez un nouveau transfert.';

  /// `CorbeilleService::MOTIFS_SUPPRESSION`, mot pour mot.
  static const motifsSuppression = <String, String>{
    'depenses': "Une dépense est un fait comptable : son écriture a été contre-passée, elle reste archivée.",
    'bandes': "Une bande porte ses fiches, ses ventes et ses transferts : un fait zootechnique ne s'efface pas, elle reste archivée.",
    'soins': "Un soin est un fait zootechnique : il ne s'efface pas, il reste archivé.",
    'courriers': "Un courrier porte une référence numérotée (CR-AAAA-NNN) : l'effacer ouvrirait un trou dans le registre, il reste archivé.",
    'comptes': "Un compte du plan comptable ne s'efface pas : il reste archivé.",
    'devis': "Un devis porte un numéro (DEV-AAAA-NNN) : l'effacer ouvrirait un trou dans la numérotation, il reste archivé.",
    'avances': "Une avance est un encaissement comptabilisé : elle ne s'efface pas, elle reste archivée.",
    'pointages': "Un pointage alimente la paie : il ne s'efface pas, il reste archivé.",
    'ventes': "Une vente annulée est un fait comptable : elle ne s'efface pas, elle reste archivée.",
    'transferts': "Un transfert est un fait zootechnique : il ne s'efface pas, il reste archivé.",
  };

  static const messageDemandeEnAttente =
      "Une demande est déjà en attente pour cet élément : elle part à la prochaine synchronisation.";

  DateTime get _maintenant => (horloge ?? HeureBenin.maintenant)();

  // ── Lecture ────────────────────────────────────────────────────────────────────────────────────────────────────────

  /// Tout ce qui est archivé (instantané du serveur + surcouche locale), du plus récemment archivé au plus ancien.
  Future<List<LigneCorbeille>> lignes() async {
    final instantane = await database.select(database.corbeilleElements).get();
    final demandes = await database.select(database.corbeilleDemandes).get();
    final refus = {
      for (final c in await database.select(database.syncConflicts).get()) c.id: c.reason,
    };

    // La dernière demande de chaque élément (une demande refusée est remplacée par la suivante : une seule par élément).
    final parElement = <String, DemandeCorbeille>{};
    for (final d in demandes) {
      final cle = '${d.type}:${d.elementId}';
      final deja = parElement[cle];
      if (deja == null || d.updatedAt.isAfter(deja.updatedAt)) parElement[cle] = d;
    }

    LigneCorbeille construire({
      required String type,
      required String elementId,
      required String titre,
      required String detail,
      required DateTime? archiveLe,
      String? archivePar,
      required bool restaurable,
      required String? motifRestauration,
      required bool supprimable,
      required String? motifSuppression,
      required bool locale,
    }) {
      final t = TypesCorbeille.de(type);
      final demande = parElement['$type:$elementId'];

      return LigneCorbeille(
        type: type,
        libelleType: t?.libelle ?? type,
        module: t?.module ?? '',
        elementId: elementId,
        titre: titre,
        detail: detail,
        archiveLe: archiveLe,
        archivePar: archivePar,
        restaurable: restaurable,
        motifRestauration: motifRestauration,
        supprimable: supprimable,
        motifSuppression: motifSuppression,
        locale: locale,
        demande: demande,
        refus: demande != null && demande.syncStatus == SyncStatus.conflict ? refus['corbeille_demandes:${demande.id}'] : null,
      );
    }

    final lignes = <LigneCorbeille>[
      for (final e in instantane)
        construire(
          type: e.type,
          elementId: e.elementId,
          titre: e.titre,
          detail: e.detail,
          archiveLe: e.archiveLe,
          archivePar: e.archivePar,
          restaurable: e.restaurable,
          motifRestauration: e.motifRestauration,
          supprimable: e.supprimable,
          motifSuppression: e.motifSuppression,
          locale: false,
        ),
    ];

    final connus = {for (final e in instantane) '${e.type}:${e.elementId}'};
    for (final l in await _archiveesIci()) {
      if (connus.contains('${l.type}:${l.elementId}')) continue;
      final t = TypesCorbeille.de(l.type)!;
      lignes.add(
        construire(
          type: l.type,
          elementId: l.elementId,
          titre: l.titre,
          detail: l.detail,
          archiveLe: l.archiveLe,
          restaurable: !t.restaurationInterdite,
          motifRestauration: t.restaurationInterdite ? motifDeRestaurationInterdite(t.cle) : null,
          supprimable: t.suppressionAdmise,
          motifSuppression: t.suppressionAdmise ? null : motifsSuppression[t.cle],
          locale: true,
        ),
      );
    }

    lignes.sort((a, b) {
      final ordre = (b.archiveLe?.millisecondsSinceEpoch ?? 0).compareTo(a.archiveLe?.millisecondsSinceEpoch ?? 0);

      return ordre != 0 ? ordre : a.titre.compareTo(b.titre);
    });

    return lignes;
  }

  /// Le refus de restauration d'un type de consultation seule (dépense, vente annulée, transfert annulé).
  static String? motifDeRestaurationInterdite(String type) => switch (type) {
    'depenses' => refusDepense,
    'ventes' => refusVente,
    'transferts' => refusTransfert,
    _ => null,
  };

  /// Recherche (titre, détail et type : casse, accents et espaces ignorés, comme `CorbeilleService::filtrer`), type et
  /// période d'archivage (bornes incluses, au jour).
  static List<LigneCorbeille> filtrer(
    List<LigneCorbeille> lignes, {
    String? type,
    String recherche = '',
    DateTime? du,
    DateTime? au,
  }) {
    final cle = recherche.trim().isEmpty ? null : cleUnicite(recherche);
    String jour(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final debut = du == null ? null : jour(du);
    final fin = au == null ? null : jour(au);

    return [
      for (final l in lignes)
        if ((type == null || type.isEmpty || l.type == type) &&
            (cle == null || cleUnicite('${l.titre} ${l.detail} ${l.libelleType}').contains(cle)) &&
            (debut == null || (l.archiveLe != null && jour(l.archiveLe!).compareTo(debut) >= 0)) &&
            (fin == null || (l.archiveLe != null && jour(l.archiveLe!).compareTo(fin) <= 0)))
          l,
    ];
  }

  static CartesCorbeille cartes(List<LigneCorbeille> lignes) => CartesCorbeille(
    archives: lignes.length,
    restaurables: lignes.where((l) => l.restaurable).length,
    supprimables: lignes.where((l) => l.supprimable).length,
  );

  // ── Demandes ───────────────────────────────────────────────────────────────────────────────────────────────────────

  /// « Restaurer » : une DEMANDE. Refusée AVANT d'écrire (mêmes motifs que le serveur) si la ligne est annoncée non
  /// restaurable ; sinon enregistrée `pending`, et le serveur fait l'effet à la prochaine synchronisation.
  Future<ResultatDemandeCorbeille> demanderRestauration(LigneCorbeille ligne) async {
    if (!ligne.restaurable) {
      return ResultatDemandeCorbeille.refus(ligne.motifRestauration ?? 'Restauration impossible.');
    }

    return _poser(ligne, 'restaurer', null, 'Restauration demandée : elle sera faite par le serveur à la prochaine synchronisation.');
  }

  /// « Supprimer définitivement » : une DEMANDE, avec le mot saisi. Refusée avant d'écrire si la ligne est annoncée non
  /// supprimable, ou si le mot n'est pas EXACTEMENT `SUPPRIMER` ; le serveur revérifie le mot et les références.
  Future<ResultatDemandeCorbeille> demanderSuppression(LigneCorbeille ligne, String confirmation) async {
    if (!ligne.supprimable) {
      return ResultatDemandeCorbeille.refus(ligne.motifSuppression ?? messageIntrouvable);
    }
    if (confirmation != motConfirmation) return const ResultatDemandeCorbeille.refus(messageConfirmation);

    return _poser(
      ligne,
      'supprimer',
      confirmation,
      'Suppression définitive demandée : elle sera faite par le serveur à la prochaine synchronisation.',
    );
  }

  Future<ResultatDemandeCorbeille> _poser(LigneCorbeille ligne, String action, String? confirmation, String message) async {
    if (ligne.enAttente) return const ResultatDemandeCorbeille.refus(messageDemandeEnAttente);

    await database.transaction(() async {
      // Une demande refusée (ou déjà traitée) est remplacée : une seule demande par élément.
      final anciennes = await (database.select(database.corbeilleDemandes)
            ..where((d) => d.type.equals(ligne.type) & d.elementId.equals(ligne.elementId)))
          .get();
      for (final a in anciennes) {
        await (database.delete(database.syncConflicts)..where((c) => c.id.equals('corbeille_demandes:${a.id}'))).go();
      }
      await (database.delete(database.corbeilleDemandes)
            ..where((d) => d.type.equals(ligne.type) & d.elementId.equals(ligne.elementId)))
          .go();
      await database.into(database.corbeilleDemandes).insert(
        CorbeilleDemandesCompanion.insert(
          id: _uuid.v4(),
          deviceId: identifiantPoste,
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: HeureBenin.versInstant(_maintenant),
          type: ligne.type,
          elementId: ligne.elementId,
          action: action,
          titre: Value(ligne.titre),
          confirmation: Value(confirmation),
        ),
      );
    });
    gestes?.signaler();

    return ResultatDemandeCorbeille.ok(message);
  }

  // ── Surcouche locale : ce que ce poste vient d'archiver ───────────────────────────────────────────────────────────

  Future<List<_Archivee>> _archiveesIci() async {
    final archivees = <_Archivee>[];

    for (final s in _specifications) {
      final lignes = await database
          .customSelect(
            'SELECT * FROM ${s.table} WHERE ${s.condition} AND sync_status <> ?',
            variables: [Variable.withString(SyncStatus.synced.name)],
          )
          .get();
      for (final l in lignes) {
        final id = l.read<String>('id');
        final maj = l.data['updated_at'];
        archivees.add(
          _Archivee(
            type: s.type,
            elementId: id,
            titre: _plein(s.titre(l)) ?? '—',
            detail: s.detail?.call(l) ?? '',
            archiveLe: maj == null ? null : HeureBenin.depuisInstant(l.read<DateTime>('updated_at')),
          ),
        );
      }
    }

    return archivees;
  }

  static String? _plein(String? v) => v == null || v.trim().isEmpty ? null : v.trim();

  static String? _texte(QueryRow l, String colonne) => l.data[colonne] as String?;

  static String _fcfa(Object? v) {
    final n = v is num ? v.toDouble() : 0.0;
    final entier = n.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }

    return '${n.round() < 0 ? '-' : ''}${morceaux.join(' ')} FCFA';
  }

  static String _jourFr(QueryRow l, String colonne) {
    final brut = l.data[colonne];
    if (brut == null) return '—';
    final d = l.read<DateTime>(colonne);

    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Les types que le poste archive lui-même, et comment lire leur titre (mêmes titres que `CorbeilleService::registre`).
  /// ⚠️ Une vente ANNULÉE (`status = 'annulee'`, annulée au poste) ne porte pas `is_active`.
  static final _specifications = <_Specification>[
    _Specification('produits', 'products', 'is_active = 0', (l) => _texte(l, 'name'), (l) => _texte(l, 'sku') ?? ''),
    _Specification('fournisseurs', 'suppliers', 'is_active = 0', (l) => _texte(l, 'name'), (l) => _texte(l, 'category') ?? ''),
    _Specification('clients', 'customers', 'is_active = 0', (l) => _texte(l, 'name'), (l) => _texte(l, 'phone') ?? ''),
    _Specification('depenses', 'expenses', 'is_active = 0', (l) => _texte(l, 'label'), (l) => _fcfa(l.data['amount'])),
    _Specification('bandes', 'livestock_lots', 'is_active = 0', (l) => _texte(l, 'code'), (l) => _texte(l, 'stage') ?? ''),
    _Specification('soins', 'veterinary_records', 'is_active = 0', (l) => _texte(l, 'action_type'), (l) => _texte(l, 'product_used') ?? ''),
    _Specification('rations', 'feed_ration_standards', 'is_active = 0', (l) => _texte(l, 'stage_label'), (l) => _texte(l, 'species_code') ?? ''),
    _Specification('provendes', 'feed_types', 'is_active = 0', (l) => _texte(l, 'name'), null),
    _Specification(
      'prophylaxie',
      'prophylaxis_schedule_standards',
      'is_active = 0',
      (l) => _texte(l, 'treatment'),
      (l) => '${_texte(l, 'species_code') ?? ''} — ${_texte(l, 'period_label') ?? ''}'.replaceAll(RegExp(r'^[ —]+|[ —]+$'), ''),
    ),
    _Specification('documents', 'administrative_documents', 'is_active = 0', (l) => _texte(l, 'title'), (l) => _texte(l, 'type') ?? ''),
    _Specification('pieces', 'archived_documents', 'is_active = 0', (l) => _texte(l, 'title'), (l) => _texte(l, 'category') ?? ''),
    _Specification('courriers', 'mails', 'is_active = 0', (l) => _texte(l, 'subject'), (l) => _texte(l, 'reference') ?? ''),
    _Specification(
      'devis',
      'quotes',
      'is_active = 0',
      (l) => _plein(_texte(l, 'quote_number')) ?? 'Devis sans numéro',
      (l) {
        final texte = _texte(l, 'articles_description') ?? '';
        final court = texte.length > 60 ? '${texte.substring(0, 60)}...' : texte;

        return '$court — ${_fcfa(l.data['amount'])}'.replaceAll(RegExp(r'^[ —]+|[ —]+$'), '');
      },
    ),
    _Specification('avances', 'customer_advances', 'is_active = 0', (l) => 'Avance de ${_fcfa(l.data['amount'])}', null),
    _Specification('ventes', 'sales', "status = 'annulee'", (l) => 'Vente du ${_jourFr(l, 'sold_at')}', (l) => _fcfa(l.data['total'])),
    _Specification(
      'transferts',
      'livestock_transfers',
      'is_active = 0',
      (l) => 'Transfert du ${_jourFr(l, 'transfer_date')}',
      (l) => '${l.data['quantity'] ?? 0} sujet(s)',
    ),
  ];
}

class _Specification {
  const _Specification(this.type, this.table, this.condition, this.titre, this.detail);

  final String type;
  final String table;
  final String condition;
  final String? Function(QueryRow) titre;
  final String Function(QueryRow)? detail;
}

class _Archivee {
  const _Archivee({required this.type, required this.elementId, required this.titre, required this.detail, required this.archiveLe});

  final String type;
  final String elementId;
  final String titre;
  final String detail;
  final DateTime? archiveLe;
}
