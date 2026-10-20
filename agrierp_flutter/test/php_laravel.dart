// Ticket F0.95 — exécution du VRAI code PHP du serveur depuis un test (parité exécutée).
//
// Rien n'est recopié : le test envoie ses entrées en JSON, le PHP du dépôt Laravel calcule, le
// test compare. Sans PHP ni dépôt Laravel, les tests concernés sont SAUTÉS AVEC LEUR RAISON
// (jamais verts à vide, jamais rouges hors ligne).
import 'dart:convert';
import 'dart:io';
import 'chemins_depot.dart';


/// Exécutable PHP trouvé (PATH puis Laragon), ou null.
String? executablePhp() {
  for (final candidat in ['php', 'php.exe']) {
    try {
      final r = Process.runSync(candidat, ['-v']);
      if (r.exitCode == 0) return candidat;
    } catch (_) {}
  }
  final base = Directory('C:/laragon/bin/php');
  if (base.existsSync()) {
    for (final d in base.listSync().whereType<Directory>()) {
      final exe = File('${d.path}/php.exe');
      if (exe.existsSync()) return exe.path;
    }
  }
  return null;
}

/// Raison du saut, ou null si le vrai PHP du serveur est exécutable.
String? sautSansPhp() {
  final service = File(
    '$dossierLaravel/app/Services/EffectifParCategorieService.php',
  );
  final autoload = File('$dossierLaravel/vendor/autoload.php');
  final php = executablePhp();
  if (!service.existsSync() || !autoload.existsSync() || php == null) {
    return 'SAUT : dépôt Laravel ou PHP absent (service ${service.existsSync()}, '
        'vendor ${autoload.existsSync()}, php $php) — parité exécutée impossible';
  }
  return null;
}

/// Exécute [script] (code PHP complet) avec [entree] en JSON, dans le dépôt Laravel, et rend la
/// sortie JSON décodée. [application] : variables d'environnement d'une base SQLite EN MÉMOIRE
/// (celles de `phpunit.xml`) — aucune base réelle n'est touchée, aucun journal n'est écrit.
Object? executerPhp(
  String script,
  Object? entree, {
  bool application = false,
}) {
  final php = executablePhp()!;
  final marque = DateTime.now().microsecondsSinceEpoch;
  final fichierScript = File(
    '${Directory.systemTemp.path}/agrierp_f095_$marque.php',
  )..writeAsStringSync(script);
  final fichierEntree = File(
    '${Directory.systemTemp.path}/agrierp_f095_$marque.json',
  )..writeAsStringSync(jsonEncode(entree));
  try {
    final r = Process.runSync(
      php,
      [fichierScript.path, fichierEntree.path],
      workingDirectory: dossierLaravel,
      environment: application
          ? const {
              'APP_ENV': 'testing',
              'DB_CONNECTION': 'sqlite',
              'DB_DATABASE': ':memory:',
              'DB_URL': '',
              'CACHE_STORE': 'array',
              'SESSION_DRIVER': 'array',
              'QUEUE_CONNECTION': 'sync',
              'MAIL_MAILER': 'array',
              'BROADCAST_CONNECTION': 'null',
              'LOG_CHANNEL': 'null',
            }
          : null,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) {
      throw StateError('PHP a échoué (${r.exitCode}) : ${r.stderr}\n${r.stdout}');
    }
    return jsonDecode(r.stdout as String);
  } finally {
    fichierScript.deleteSync();
    fichierEntree.deleteSync();
  }
}

/// Démarre Laravel sur SQLite EN MÉMOIRE et migre. Refuse de continuer sur une autre base.
const amorceApplication = r'''
require 'vendor/autoload.php';
$app = require 'bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
if (config('database.default') !== 'sqlite' || config('database.connections.sqlite.database') !== ':memory:') {
    fwrite(STDERR, 'Refus : la base n est pas une base SQLite en memoire.');
    exit(3);
}
Illuminate\Support\Facades\Artisan::call('migrate', ['--force' => true]);
''';
