// Ticket PWA-2 — OUVERTURE DE LA BASE LOCALE : une seule porte, deux implémentations.
//
// - Windows (et tous les tests, en VM) : [ouverture_base_native.dart] — SQLite natif dans `%APPDATA%\OLOUWACHEGOUN\donnees`,
//   EXACTEMENT comme avant le ticket ;
// - navigateur : [ouverture_base_web.dart] — SQLite compilé en WebAssembly (`sqlite3.wasm` + `drift_worker.js`), stocké dans IndexedDB.
//
// ⚠️ L'import conditionnel est le SEUL mécanisme qui isole `dart:ffi` du build web : ne jamais importer
// `package:drift/native.dart` ailleurs que dans `ouverture_base_native.dart`.
export 'ouverture_base_native.dart' if (dart.library.js_interop) 'ouverture_base_web.dart';
