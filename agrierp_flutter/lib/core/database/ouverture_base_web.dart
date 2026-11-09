import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Nom de la base dans IndexedDB (le navigateur n'a pas de dossier de données).
const nomBaseWeb = 'agrierp';

/// Ouvre la base du poste dans le navigateur.
///
/// ⚠️ Chemins RELATIFS : l'application est servie sous `/poste/` (`--base-href /poste/`), donc `sqlite3.wasm` et
/// `drift_worker.js` sont cherchés dans `/poste/`. Stockage : IndexedDB partagé, tant que la page n'est PAS servie avec
/// COOP/COEP (voir `docs/logialvia/45_...` §7 : avec ces en-têtes, drift passe en OPFS et le tirage dure ≈ 150 s).
QueryExecutor ouvrirConnexionPoste() {
  return driftDatabase(
    name: nomBaseWeb,
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
