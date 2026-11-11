import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../demarrage/dossier_donnees.dart';

/// Ticket B5 — sauvegarde automatique : avant migration (changement de schéma) et quotidienne.
///
/// Ces sauvegardes sont silencieuses : toute erreur (disque plein, dossier absent, navigateur) est
/// avalée. La rétention est de 7 jours, distincte des 30 jours des sauvegardes manuelles.
///
/// Format du nom : `backup_AAAA-MM-JJ_HHmm_<type>_<complement>.sqlite`
///   - type `migration` : avant passage du schéma de v[de] à v[vers]
///   - type `quotidien`  : une fois par jour au premier démarrage
class SauvegardeAutomatique {
  SauvegardeAutomatique._();

  static const retentionAutoJours = 7;

  static String _horodatage(DateTime m) {
    String d(int v) => v.toString().padLeft(2, '0');
    return '${m.year}-${d(m.month)}-${d(m.day)}_${d(m.hour)}${d(m.minute)}';
  }

  static Future<Directory> _dossierParDefaut() async =>
      Directory(p.join((await DossierDonnees.courant()).path, 'sauvegardes'));

  /// Nettoie les sauvegardes automatiques de plus de [retentionAutoJours] jours.
  static Future<void> _nettoyer(
    Directory dossier,
    DateTime maintenant,
  ) async {
    if (!await dossier.exists()) return;
    final limite = maintenant.subtract(
      const Duration(days: retentionAutoJours),
    );
    await for (final f in dossier.list()) {
      if (f is! File) continue;
      final nom = p.basename(f.path);
      if (!nom.endsWith('_migration.sqlite') && !nom.endsWith('_quotidien.sqlite')) continue;
      final date = (await f.stat()).modified;
      if (date.isBefore(limite)) await f.delete();
    }
  }

  /// Sauvegarde AVANT migration : appelée depuis `beforeOpen` lorsque le schéma va changer.
  ///
  /// [de] et [vers] sont les numéros de version de schéma (versionBefore / versionNow).
  /// Silencieuse en cas d'erreur (navigateur, disque plein, etc.).
  static Future<void> avantMigration(
    GeneratedDatabase db,
    int de,
    int vers, {
    DateTime Function()? maintenant,
    Future<Directory> Function()? dossier,
  }) async {
    if (!DossierDonnees.disponible) return;
    try {
      final now = (maintenant ?? DateTime.now)();
      final d = await (dossier ?? _dossierParDefaut)();
      await d.create(recursive: true);
      await _nettoyer(d, now);
      final chemin = p.join(
        d.path,
        'backup_${_horodatage(now)}_v${de}_vers_v${vers}_migration.sqlite',
      );
      await db.customStatement("VACUUM INTO '${chemin.replaceAll("'", "''")}'");
    } catch (_) {}
  }

  /// Sauvegarde QUOTIDIENNE : appelée au démarrage de session, ne s'exécute qu'une fois par jour.
  ///
  /// Vérifie si un fichier `*_quotidien.sqlite` du jour existe déjà avant de créer.
  /// Silencieuse en cas d'erreur.
  static Future<void> quotidienne(
    GeneratedDatabase db, {
    DateTime Function()? maintenant,
    Future<Directory> Function()? dossier,
  }) async {
    if (!DossierDonnees.disponible) return;
    try {
      final now = (maintenant ?? DateTime.now)();
      final d = await (dossier ?? _dossierParDefaut)();
      await d.create(recursive: true);
      await _nettoyer(d, now);

      // Préfixe du jour : backup_AAAA-MM-JJ
      String d2(int v) => v.toString().padLeft(2, '0');
      final prefixeJour = 'backup_${now.year}-${d2(now.month)}-${d2(now.day)}';
      var dejaFaite = false;
      await for (final f in d.list()) {
        if (f is! File) continue;
        final nom = p.basename(f.path);
        if (nom.startsWith(prefixeJour) && nom.endsWith('_quotidien.sqlite')) {
          dejaFaite = true;
          break;
        }
      }
      if (dejaFaite) return;

      final chemin = p.join(
        d.path,
        'backup_${_horodatage(now)}_quotidien.sqlite',
      );
      await db.customStatement("VACUUM INTO '${chemin.replaceAll("'", "''")}'");
    } catch (_) {}
  }
}
