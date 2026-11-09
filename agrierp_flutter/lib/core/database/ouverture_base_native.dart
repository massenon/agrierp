import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../demarrage/dossier_donnees.dart';

/// Ouvre la base du poste Windows : `agrierp.sqlite` dans le dossier des données (créé au besoin).
///
/// ⚠️ `NativeDatabase.createInBackground` SEUL sur Windows Desktop. Ne JAMAIS réintroduire
/// `open.overrideFor(OperatingSystem.windows, ...)` : ce motif a déjà cassé une compilation dans ce projet et n'apporte
/// rien ici, `sqlite3_flutter_libs` fournissant déjà la bibliothèque.
QueryExecutor ouvrirConnexionPoste() {
  return LazyDatabase(() async {
    final dossier = await DossierDonnees.courant();
    await dossier.create(recursive: true);
    final fichier = File(p.join(dossier.path, 'agrierp.sqlite'));

    return NativeDatabase.createInBackground(fichier);
  });
}
