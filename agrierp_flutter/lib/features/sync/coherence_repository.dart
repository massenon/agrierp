import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/agregats_coherence.dart';

/// Nombre de lignes et total d'un jour, d'un côté.
class TotauxJour {
  const TotauxJour({required this.nombre, required this.total});

  final int nombre;
  final double total;

  @override
  bool operator ==(Object other) =>
      other is TotauxJour && other.nombre == nombre && other.total == total;

  @override
  int get hashCode => Object.hash(nombre, total);

  @override
  String toString() => '($nombre ; $total)';
}

/// Une table un jour donné : ce que dit le poste, ce que dit le serveur. `null` : aucune ligne ce jour-là.
class LigneCoherence {
  const LigneCoherence({required this.jour, this.poste, this.serveur});

  /// `AAAA-MM-JJ`.
  final String jour;
  final TotauxJour? poste;
  final TotauxJour? serveur;

  int get ecartNombre => (poste?.nombre ?? 0) - (serveur?.nombre ?? 0);

  double get ecartTotal =>
      ControleCoherenceRepository.arrondi((poste?.total ?? 0) - (serveur?.total ?? 0));

  /// Au centime près : deux sommes de réels peuvent différer d'un bruit d'arrondi.
  bool get conforme => ecartNombre == 0 && ecartTotal.abs() < 0.005;
}

class TableCoherence {
  const TableCoherence({
    required this.table,
    required this.libelle,
    required this.ecarts,
    required this.conformes,
  });

  final String table;
  final String libelle;

  /// Jours en écart, du plus récent au plus ancien.
  final List<LigneCoherence> ecarts;

  /// Jours conformes, du plus récent au plus ancien (repliés à l'écran).
  final List<LigneCoherence> conformes;
}

class ResultatCoherence {
  const ResultatCoherence({required this.depuis, required this.tables});

  final DateTime depuis;
  final List<TableCoherence> tables;

  int get nombreEcarts => tables.fold(0, (s, t) => s + t.ecarts.length);
}

/// Ticket S-T6 — CONTRÔLE DE COHÉRENCE DU POSTE (méthode TATACORA).
///
/// Le poste calcule, sur SA base, le nombre de lignes et le total par table et par jour (table de correspondance
/// [AgregatsCoherence], copie conforme du serveur), demande les mêmes chiffres au serveur (`GET /api/sync/coherence`)
/// et compare. Un écart signale une ligne perdue dans un sens ou dans l'autre, ou un montant qui a divergé.
///
/// ⚠️ **AU POSTE, SEULES LES LIGNES `synced` COMPTENT** quand la table porte un statut : ce sont celles que le
/// serveur doit avoir. Une saisie en attente ou refusée n'y est pas encore : la compter ferait crier à l'écart pour
/// une vente simplement pas encore envoyée — l'écran « En attente » le dit déjà.
class ControleCoherenceRepository {
  ControleCoherenceRepository({
    required AppDatabase database,
    required Future<Map<String, dynamic>> Function(String depuis) serveur,
    DateTime Function()? maintenant,
  }) : _db = database,
       // Paramètre NOMMÉ : Dart interdit `this._serveur` (voir `SyncEngine`).
       // ignore: prefer_initializing_formals
       _serveur = serveur,
       _maintenant = maintenant ?? DateTime.now;

  final AppDatabase _db;
  final Future<Map<String, dynamic>> Function(String depuis) _serveur;
  final DateTime Function() _maintenant;

  /// Fenêtre par défaut du contrôle : les 30 derniers jours, aujourd'hui compris.
  static const joursParDefaut = 30;

  static double arrondi(double v) => (v * 100).roundToDouble() / 100;

  static String cleJour(DateTime d) {
    final l = d.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  /// Comptes du poste, table par table puis jour par jour, depuis [depuis] (minuit local).
  Future<Map<String, Map<String, TotauxJour>>> calculerLocal(DateTime depuis) async {
    final debut = DateTime(depuis.year, depuis.month, depuis.day);
    final resultat = <String, Map<String, TotauxJour>>{};

    for (final a in AgregatsCoherence.tables) {
      final table = _db.allTables.firstWhere((t) => t.actualTableName == a.table);
      final colonnes = table.columnsByName;
      final jour = a.jour.first;

      final conditions = ['$jour >= ?'];
      final variables = <Variable<Object>>[Variable<DateTime>(debut)];
      if (colonnes.containsKey('sync_status')) {
        conditions.add("sync_status = 'synced'");
      }
      final filtre = a.filtre;
      if (filtre != null) {
        final (colonne, operateur, valeur) = filtre;
        conditions.add('$colonne $operateur ?');
        variables.add(
          valeur is int ? Variable<int>(valeur) : Variable<String>(valeur.toString()),
        );
      }

      final lignes = await _db
          .customSelect(
            'SELECT $jour AS jour, ${a.montant} AS montant FROM ${a.table} '
            'WHERE ${conditions.join(' AND ')}',
            variables: variables,
            readsFrom: {table},
          )
          .get();

      final nombres = <String, int>{};
      final totaux = <String, double>{};
      for (final l in lignes) {
        final quand = l.readNullable<DateTime>('jour');
        if (quand == null) continue;
        final cle = cleJour(quand);
        nombres[cle] = (nombres[cle] ?? 0) + 1;
        totaux[cle] = (totaux[cle] ?? 0) + (l.readNullable<double>('montant') ?? 0);
      }

      resultat[a.table] = {
        for (final cle in nombres.keys)
          cle: TotauxJour(nombre: nombres[cle]!, total: arrondi(totaux[cle]!)),
      };
    }

    return resultat;
  }

  /// Lit la réponse de `GET /api/sync/coherence` (`tables.<table>.jours.<AAAA-MM-JJ>.{nombre, total}`).
  ///
  /// ⚠️ PHP encode un tableau vide en `[]`, pas en `{}` : une table sans aucune ligne arrive comme une liste.
  static Map<String, Map<String, TotauxJour>> lireServeur(Map<String, dynamic> corps) {
    final tables = corps['tables'];
    final resultat = <String, Map<String, TotauxJour>>{};
    if (tables is! Map) return resultat;

    for (final entree in tables.entries) {
      final jours = entree.value is Map ? (entree.value as Map)['jours'] : null;
      final parJour = <String, TotauxJour>{};
      if (jours is Map) {
        for (final j in jours.entries) {
          final v = j.value;
          if (v is! Map) continue;
          parJour[j.key.toString()] = TotauxJour(
            nombre: (v['nombre'] as num?)?.toInt() ?? 0,
            total: arrondi((v['total'] as num?)?.toDouble() ?? 0),
          );
        }
      }
      resultat[entree.key.toString()] = parJour;
    }

    return resultat;
  }

  /// Compare les deux côtés, table par table dans l'ordre de [AgregatsCoherence.tables].
  static List<TableCoherence> comparer(
    Map<String, Map<String, TotauxJour>> poste,
    Map<String, Map<String, TotauxJour>> serveur,
  ) {
    return [
      for (final a in AgregatsCoherence.tables)
        () {
          final cotePoste = poste[a.table] ?? const <String, TotauxJour>{};
          final coteServeur = serveur[a.table] ?? const <String, TotauxJour>{};
          final jours = {...cotePoste.keys, ...coteServeur.keys}.toList()
            ..sort((x, y) => y.compareTo(x));
          final lignes = [
            for (final j in jours)
              LigneCoherence(jour: j, poste: cotePoste[j], serveur: coteServeur[j]),
          ];
          return TableCoherence(
            table: a.table,
            libelle: a.libelle,
            ecarts: [for (final l in lignes) if (!l.conforme) l],
            conformes: [for (final l in lignes) if (l.conforme) l],
          );
        }(),
    ];
  }

  /// Contrôle complet depuis [depuis] (par défaut : les [joursParDefaut] derniers jours). Lève si le serveur ne
  /// répond pas : l'écran le dit, sans erreur rouge pour un poste simplement hors ligne.
  Future<ResultatCoherence> verifier({DateTime? depuis}) async {
    final aujourdhui = _maintenant();
    final debut =
        depuis ??
        DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day)
            .subtract(const Duration(days: joursParDefaut - 1));

    final corps = await _serveur(cleJour(debut));
    final local = await calculerLocal(debut);

    return ResultatCoherence(
      depuis: DateTime(debut.year, debut.month, debut.day),
      tables: comparer(local, lireServeur(corps)),
    );
  }
}
