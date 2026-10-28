import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/database/app_database.dart';
import '../../core/demarrage/dossier_donnees.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/modale_agri.dart';

/// Refus d'un geste d'administration : le motif, en français.
class RefusAdministration implements Exception {
  const RefusAdministration(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Un fichier de sauvegarde gardé sur ce poste.
class FichierSauvegarde {
  const FichierSauvegarde({required this.fichier, required this.date, required this.portee, required this.taille, required this.complete});

  final String fichier;
  final DateTime date;
  final String portee;
  final int taille;

  /// Sauvegarde COMPLÈTE (base SQLite entière, schéma compris) : la seule qui se restaure ; un export de module est un JSON.
  final bool complete;
}

/// Tickets AUT-4 (PA-1, PA-5, PA-6) — ADMINISTRATION DU POSTE, SANS LE SERVEUR.
///
/// Le poste reste pleinement autonome : sauvegarder, restaurer et fermer les sessions agissent sur CE poste (sa base
/// SQLite, son coffre), jamais sur le serveur. Les gestes du web (`Sauvegardes`, `GestionUtilisateurs::viderSessions`) ont ici
/// leur équivalent local, mêmes libellés et mêmes protections (réservé à l'administrateur, confirmation avant de remplacer).
class AdministrationLocale {
  AdministrationLocale({
    required this.database,
    required this.role,
    required this.idUtilisateur,
    FlutterSecureStorage? coffre,
    Future<Directory> Function()? dossierSauvegardes,
    Future<Directory?> Function()? dossierCopie,
    DateTime Function()? maintenant,
  }) : _coffre = coffre ?? const FlutterSecureStorage(),
       _dossier = dossierSauvegardes ?? _dossierParDefaut,
       _copie = dossierCopie ?? _copieParDefaut,
       _maintenant = maintenant ?? DateTime.now;

  final AppDatabase database;
  final String Function() role;
  final String Function() idUtilisateur;
  final FlutterSecureStorage _coffre;
  final Future<Directory> Function() _dossier;
  final Future<Directory?> Function() _copie;
  final DateTime Function() _maintenant;

  /// Rétention du web (`agrierp:backup`) : 30 jours.
  static const retentionJours = 30;

  /// Les modules de `SauvegardeService::modules()` (web), enfants AVANT parents. Seules les tables que ce poste porte sont lues.
  static const modules = <String, ({String libelle, List<String> tables})>{
    'ventes': (libelle: 'Ventes & Clients', tables: ['sale_lines', 'credit_notes', 'quotes', 'advance_imputations', 'receivables', 'customer_advances', 'customer_reminders', 'sales', 'customers']),
    'achats': (libelle: 'Achats & Fournisseurs', tables: ['purchase_lines', 'purchase_order_lines', 'purchase_returns', 'supplier_payments', 'supplier_refunds', 'payables', 'purchases', 'purchase_orders', 'expense_lines', 'expenses', 'suppliers']),
    'stocks': (libelle: 'Stocks', tables: ['stock_movements', 'products', 'product_categories']),
    'elevage': (libelle: 'Élevage', tables: ['livestock_daily_entries', 'livestock_reproduction_events', 'animals', 'transformations', 'veterinary_records', 'veterinary_withdrawal_periods', 'veterinary_calendar_events', 'infirmary_records', 'livestock_lots', 'feed_ration_standards', 'prophylaxis_schedule_standards', 'feed_types', 'livestock_species']),
    'comptabilite': (libelle: 'Comptabilité', tables: ['accounting_entry_lines', 'accounting_entries', 'accounting_reference_sequences', 'periodic_closures', 'bank_statement_lines', 'fixed_assets', 'cost_centers', 'treasury_accounts', 'fiscal_years', 'chart_of_accounts']),
    'rh': (libelle: 'Ressources Humaines', tables: ['payslips', 'attendance_records', 'internship_absences', 'internships', 'employees', 'income_tax_brackets']),
  };

  /// Nom du fichier posé à côté de la base : `appliquerRestaurationEnAttente` l'installe au prochain lancement.
  static const fichierRestauration = 'agrierp.restauration';

  static Future<Directory> _dossierParDefaut() async => Directory(p.join((await DossierDonnees.courant()).path, 'sauvegardes'));

  static Future<Directory?> _copieParDefaut() async => (await getDownloadsDirectory()) ?? await getApplicationDocumentsDirectory();

  bool peut(String permission) => PermissionsPoste.peut(role(), permission);

  // ── PA-1 · Déconnecter les autres comptes de ce poste ────────────────────

  /// Efface, au coffre de ce poste, le code PIN et les réglages de verrouillage des AUTRES comptes : ils devront se reconnecter
  /// (en ligne) et redéfinir leur code. La session en cours est conservée. Rend le message annoncé.
  Future<String> viderSessions() async {
    final courant = idUtilisateur();
    var n = 0;
    for (final cle in (await _coffre.readAll()).keys) {
      final autre = cle.startsWith('agrierp.verrou.') && cle != 'agrierp.verrou.$courant';
      final reglage = (cle.startsWith('agrierp.inactivite.') && cle != 'agrierp.inactivite.$courant') ||
          (cle.startsWith('agrierp.rappels.masque.') && cle != 'agrierp.rappels.masque.$courant');
      if (!autre && !reglage) continue;
      await _coffre.delete(key: cle);
      if (autre) n++;
    }
    return '$n compte(s) déconnecté(s) de ce poste. Votre session est conservée.';
  }

  // ── PA-6 · Sauvegardes de ce poste ───────────────────────────────────────

  String _horodatage() {
    String d(int v) => v.toString().padLeft(2, '0');
    final m = _maintenant();
    return '${m.year}-${d(m.month)}-${d(m.day)}_${d(m.hour)}${d(m.minute)}';
  }

  Future<Set<String>> _tablesPresentes() async =>
      {for (final r in await database.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()) r.read<String>('name')};

  Future<File> _cible(Directory d, String suffixe) async {
    var f = File(p.join(d.path, 'backup_${_horodatage()}_$suffixe'));
    var n = 1;
    while (await f.exists()) {
      f = File(p.join(d.path, 'backup_${_horodatage()}_${n++}_$suffixe'));
    }
    return f;
  }

  Future<List<FichierSauvegarde>> sauvegardes() async {
    final d = await _dossier();
    if (!await d.exists()) return const [];
    final limite = _maintenant().subtract(const Duration(days: retentionJours));
    final sortie = <FichierSauvegarde>[];
    await for (final f in d.list()) {
      if (f is! File) continue;
      final nom = p.basename(f.path);
      final complete = nom.endsWith('_complete.sqlite');
      final module = modules.entries.where((e) => nom.endsWith('_${e.key}.json')).firstOrNull;
      if (!complete && module == null) continue;
      final date = (await f.stat()).modified;
      if (date.isBefore(limite)) {
        await f.delete();
        continue;
      }
      sortie.add(FichierSauvegarde(
        fichier: nom, date: date, taille: await f.length(), complete: complete,
        portee: complete ? 'Sauvegarde complète' : '${module!.value.libelle} (export, sans schéma)',
      ));
    }
    return sortie..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Sauvegarde COMPLÈTE (copie cohérente de la base, schéma compris) ou, avec [module], export JSON de ses tables.
  Future<String> generer({String? module}) async {
    final d = await _dossier();
    await d.create(recursive: true);

    if (module == null) {
      final f = await _cible(d, 'complete.sqlite');
      await database.customStatement("VACUUM INTO '${f.path.replaceAll("'", "''")}'");
      return 'Sauvegarde complète générée : ${p.basename(f.path)}';
    }

    final definition = modules[module];
    if (definition == null) throw const RefusAdministration('Module inconnu.');
    final presentes = await _tablesPresentes();
    final contenu = <String, Object?>{'module': module, 'genere_le': _maintenant().toIso8601String(), 'tables': <String, Object?>{}};
    for (final t in definition.tables.where(presentes.contains)) {
      (contenu['tables']! as Map<String, Object?>)[t] = [for (final r in await database.customSelect('SELECT * FROM $t').get()) _jsonable(r.data)];
    }
    final f = await _cible(d, '$module.json');
    await f.writeAsString(jsonEncode(contenu));
    return 'Export du module « ${definition.libelle} » généré : ${p.basename(f.path)}';
  }

  static Map<String, Object?> _jsonable(Map<String, Object?> ligne) => {
    for (final e in ligne.entries) e.key: e.value is List<int> ? base64Encode(e.value! as List<int>) : e.value,
  };

  /// Copie [fichier] dans le dossier Téléchargements (clé USB, disque externe : à copier ensuite) ; rend le chemin écrit.
  Future<String> copier(String fichier) async {
    final source = File(p.join((await _dossier()).path, fichier));
    if (!await source.exists()) throw const RefusAdministration('Sauvegarde introuvable.');
    final cible = await _copie();
    if (cible == null) throw const RefusAdministration("Aucun dossier de téléchargement n'est disponible sur ce poste.");
    final destination = File(p.join(cible.path, fichier));
    await source.copy(destination.path);
    return destination.path;
  }

  /// Restauration COMPLÈTE : la base actuelle est remplacée par [fichier] au PROCHAIN LANCEMENT (une base ouverte ne se remplace
  /// pas à chaud). L'ancienne base est gardée à côté.
  Future<String> programmerRestauration(String fichier) async {
    final source = File(p.join((await _dossier()).path, fichier));
    if (!fichier.endsWith('_complete.sqlite') || !await source.exists()) {
      throw const RefusAdministration('Seule une sauvegarde complète peut être restaurée.');
    }
    await source.copy(p.join((await _dossier()).parent.path, fichierRestauration));
    return 'Restauration programmée : fermez puis rouvrez AgriERP pour l\'appliquer. La base actuelle est conservée sous le nom agrierp.avant-restauration.sqlite.';
  }

  /// À appeler AU LANCEMENT, avant d'ouvrir la base : installe la restauration programmée. Une panne laisse la base intacte.
  static Future<void> appliquerRestaurationEnAttente({Directory? dossierDonnees}) async {
    try {
      final d = dossierDonnees ?? await DossierDonnees.courant();
      final restauration = File(p.join(d.path, fichierRestauration));
      if (!await restauration.exists()) return;
      final base = File(p.join(d.path, 'agrierp.sqlite'));
      final ancienne = File(p.join(d.path, 'agrierp.avant-restauration.sqlite'));
      if (await ancienne.exists()) await ancienne.delete();
      if (await base.exists()) await base.rename(ancienne.path);
      for (final suffixe in ['-wal', '-shm']) {
        final annexe = File('${base.path}$suffixe');
        if (await annexe.exists()) await annexe.delete();
      }
      await restauration.rename(base.path);
    } catch (_) {
      // Voir la docstring : jamais bloquer le lancement.
    }
  }

  /// Remplace les données d'UN module par celles d'une sauvegarde complète. Les lignes reprises repartent `pending` (le serveur
  /// les rejouera). ⚠️ Mêmes réserves que le web : des enregistrements d'autres modules peuvent devenir orphelins.
  Future<String> importerModule({required String fichier, required String module}) async {
    final definition = modules[module];
    if (definition == null) throw const RefusAdministration('Module inconnu.');
    final source = File(p.join((await _dossier()).path, fichier));
    if (!fichier.endsWith('_complete.sqlite') || !await source.exists()) {
      throw const RefusAdministration("Choisissez une sauvegarde complète : un export JSON ne se réimporte pas.");
    }

    final presentes = await _tablesPresentes();
    await database.customStatement("ATTACH DATABASE '${source.path.replaceAll("'", "''")}' AS sauvegarde");
    try {
      final dansSauvegarde = {for (final r in await database.customSelect("SELECT name FROM sauvegarde.sqlite_master WHERE type = 'table'").get()) r.read<String>('name')};
      final tables = definition.tables.where((t) => presentes.contains(t) && dansSauvegarde.contains(t)).toList();
      await database.transaction(() async {
        for (final t in tables) {
          await database.customStatement('DELETE FROM main.$t');
        }
        for (final t in tables.reversed) {
          final communes = await _colonnesCommunes(t);
          final liste = communes.join(', ');
          await database.customStatement('INSERT INTO main.$t ($liste) SELECT $liste FROM sauvegarde.$t');
          if (communes.contains('sync_status') && AppDatabase.tablesEnvoyees.contains(t)) {
            await database.customStatement("UPDATE main.$t SET sync_status = 'pending'");
          }
        }
      });
      return 'Module « ${definition.libelle} » remplacé par le contenu de $fichier (${tables.length} table(s)).';
    } finally {
      await database.customStatement('DETACH DATABASE sauvegarde');
    }
  }

  Future<List<String>> _colonnesCommunes(String table) async {
    Future<List<String>> colonnes(String schema) async =>
        [for (final r in await database.customSelect('PRAGMA $schema.table_info($table)').get()) r.read<String>('name')];
    final locales = await colonnes('main');
    final reprises = (await colonnes('sauvegarde')).toSet();
    return locales.where(reprises.contains).toList();
  }

  // ── PA-5 · Ce poste ──────────────────────────────────────────────────────

  /// État de CE poste : saisies en attente d'envoi, conflits, dernière synchronisation aboutie.
  Future<({int enAttente, int conflits, DateTime? derniere})> etatDuPoste() async {
    var attente = 0;
    var conflits = 0;
    final presentes = await _tablesPresentes();
    for (final t in AppDatabase.tablesEnvoyees.where(presentes.contains)) {
      final r = await database.customSelect(
        "SELECT SUM(sync_status = 'pending') AS a, SUM(sync_status = 'conflict') AS c FROM $t",
      ).getSingle();
      attente += r.read<int?>('a') ?? 0;
      conflits += r.read<int?>('c') ?? 0;
    }
    final etat = await database.select(database.syncState).getSingleOrNull();
    return (enAttente: attente, conflits: conflits, derniere: etat?.lastSucceededAt);
  }
}

String _taille(int octets) => octets >= 1048576 ? '${(octets / 1048576).toStringAsFixed(1)} Mo' : '${(octets / 1024).toStringAsFixed(1)} Ko';

String _quand(DateTime d) {
  String v(int n) => n.toString().padLeft(2, '0');
  return '${v(d.day)}/${v(d.month)}/${d.year} ${v(d.hour)}:${v(d.minute)}';
}

Future<bool> confirmerViderSessions({required BuildContext context, required AdministrationLocale admin, required void Function(String) surMessage}) async {
  final ok = await afficherModale<bool>(
    context: context,
    confirmation: true,
    constructeur: (_) => _ModaleViderSessions(admin: admin, surMessage: surMessage),
  );
  return ok == true;
}

class _ModaleViderSessions extends StatelessWidget {
  const _ModaleViderSessions({required this.admin, required this.surMessage});

  final AdministrationLocale admin;
  final void Function(String) surMessage;

  @override
  Widget build(BuildContext context) => ModaleConfirmation(
    titre: 'Déconnecter toutes les sessions ?',
    message:
        "Les autres comptes de ce poste sont déconnectés : leur code PIN et leurs réglages de verrouillage sont effacés, ils devront se reconnecter puis redéfinir leur code. Les saisies en attente sont conservées et partiront après la reconnexion. Votre propre session reste ouverte.",
    icone: SymbolesAgri.logout,
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
      BoutonModalePrimaire(
        key: const Key('sessions-deconnecter'),
        libelle: 'Déconnecter',
        couleur: AgriColors.errorRed,
        onPressed: () async {
          surMessage(await admin.viderSessions());
          if (context.mounted) Navigator.of(context).pop(true);
        },
      ),
    ],
  );
}

/// Onglet « Sauvegardes » (`Parametres\Sauvegardes`) : générer, exporter un module, copier, importer un module, restaurer.
class OngletSauvegardes extends StatefulWidget {
  const OngletSauvegardes({super.key, required this.admin});

  final AdministrationLocale admin;

  @override
  State<OngletSauvegardes> createState() => _OngletSauvegardesState();
}

class _OngletSauvegardesState extends State<OngletSauvegardes> {
  List<FichierSauvegarde>? _fichiers;
  String? _message;
  String? _refus;
  String _moduleExport = '';
  String _fichierImport = '';
  String _moduleImport = '';
  bool _confirmerImport = false;
  String? _restauration;

  static final _modules = {for (final e in AdministrationLocale.modules.entries) e.key: e.value.libelle};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final f = await widget.admin.sauvegardes();
    if (mounted) setState(() => _fichiers = f);
  }

  Future<void> _faire(Future<String> Function() geste) async {
    try {
      final m = await geste();
      if (!mounted) return;
      setState(() {
        _message = m;
        _refus = null;
      });
      await _charger();
    } on RefusAdministration catch (e) {
      if (mounted) setState(() => _refus = e.message);
    } on Object {
      if (mounted) setState(() => _refus = "L'opération a échoué : vérifiez l'espace disque de ce poste puis réessayez.");
    }
  }

  Widget _liste(String cle, String valeur, Map<String, String> options, String vide, ValueChanged<String> surChoix) => DropdownButtonFormField<String>(
    key: Key(cle),
    initialValue: valeur,
    isDense: true,
    isExpanded: true,
    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
    style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
    items: [
      DropdownMenuItem(value: '', child: Text(vide)),
      for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
    ],
    onChanged: (v) => setState(() => surChoix(v ?? '')),
  );

  Widget _bouton(String cle, String libelle, IconData icone, VoidCallback? surAppui, {bool plein = false}) => plein
      ? ElevatedButton.icon(
          key: Key(cle),
          onPressed: surAppui,
          icon: Icon(icone, size: 18),
          style: ElevatedButton.styleFrom(backgroundColor: AgriColors.brandEmerald, foregroundColor: Colors.white, shape: const StadiumBorder()),
          label: Text(libelle, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
        )
      : OutlinedButton.icon(key: Key(cle), onPressed: surAppui, icon: Icon(icone, size: 18), label: Text(libelle, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)));

  @override
  Widget build(BuildContext context) {
    final fichiers = _fichiers;
    final completes = {for (final f in fichiers ?? const <FichierSauvegarde>[]) if (f.complete) f.fichier: f.fichier};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(children: [
          Icon(SymbolesAgri.database, size: 26, color: AgriColors.brandEmerald),
          SizedBox(width: AgriSpacing.xs),
          Text('Sauvegardes de la Base de Données', style: TextStyle(fontSize: AgriTypography.xl, fontWeight: AgriTypography.gras, color: AgriColors.onSurface)),
        ]),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Les sauvegardes sont gardées sur ce poste pendant 30 jours, sans réseau. Copiez-les régulièrement sur une clé USB : un fichier resté sur ce poste ne protège de rien si le poste tombe en panne.',
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.md),
        if (_message != null) Text(_message!, key: const Key('sauvegarde-message'), style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
        if (_refus != null) Text(_refus!, key: const Key('sauvegarde-refus'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
        const SizedBox(height: AgriSpacing.sm),
        Align(alignment: Alignment.centerLeft, child: _bouton('sauvegarde-generer', 'Générer une sauvegarde', SymbolesAgri.backup, () => _faire(widget.admin.generer), plein: true)),
        const SizedBox(height: AgriSpacing.lg),
        const Text('Exporter un module seul', style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
        const SizedBox(height: AgriSpacing.xs),
        _liste('sauvegarde-module-export', _moduleExport, _modules, '-- Choisir un module --', (v) => _moduleExport = v),
        const SizedBox(height: AgriSpacing.xs),
        _bouton('sauvegarde-exporter', 'Exporter ce module', SymbolesAgri.download, _moduleExport.isEmpty ? null : () => _faire(() => widget.admin.generer(module: _moduleExport))),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Un export de module contient les données de ce module uniquement, sans le schéma : il sert à transmettre ou à analyser, jamais à restaurer une exploitation complète.',
          style: TextStyle(fontSize: 11, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.lg),
        const Text('Importer un module', style: TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
        const SizedBox(height: AgriSpacing.xs),
        _liste('sauvegarde-fichier-import', _fichierImport, completes, '-- Choisir une sauvegarde complète --', (v) => _fichierImport = v),
        const SizedBox(height: AgriSpacing.xs),
        _liste('sauvegarde-module-import', _moduleImport, _modules, '-- Choisir un module --', (v) => _moduleImport = v),
        const SizedBox(height: AgriSpacing.xs),
        if (!_confirmerImport)
          _bouton('sauvegarde-importer', 'Importer', SymbolesAgri.upload, _fichierImport.isEmpty || _moduleImport.isEmpty ? null : () => setState(() => _confirmerImport = true))
        else ...[
          const Text(
            "Remplacer les données de ce module ? Les données actuelles du module sélectionné seront supprimées puis remplacées par celles du fichier. Les enregistrements d'autres modules qui y font référence peuvent devenir orphelins. Générez une sauvegarde complète avant de poursuivre.",
            key: Key('sauvegarde-confirmation'),
            style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
          ),
          const SizedBox(height: AgriSpacing.xs),
          Row(children: [
            TextButton(onPressed: () => setState(() => _confirmerImport = false), child: const Text('Annuler')),
            _bouton('sauvegarde-confirmer-import', "Confirmer l'import", SymbolesAgri.upload, () async {
              setState(() => _confirmerImport = false);
              await _faire(() => widget.admin.importerModule(fichier: _fichierImport, module: _moduleImport));
            }, plein: true),
          ]),
        ],
        const SizedBox(height: AgriSpacing.lg),
        if (fichiers == null) const Center(child: CircularProgressIndicator()),
        if (fichiers != null && fichiers.isEmpty)
          const Text('Aucune sauvegarde pour le moment — générez-en une avec le bouton ci-dessus.', key: Key('sauvegarde-vide'), style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
        for (final f in fichiers ?? const <FichierSauvegarde>[])
          ListTile(
            key: Key('sauvegarde-${f.fichier}'),
            dense: true,
            title: Text(f.fichier, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
            subtitle: Text('${_quand(f.date)} · ${f.portee} · ${_taille(f.taille)}', style: const TextStyle(fontSize: 11)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton.icon(
                key: Key('sauvegarde-copier-${f.fichier}'),
                onPressed: () => _faire(() async => 'Sauvegarde copiée : ${await widget.admin.copier(f.fichier)}'),
                icon: const Icon(SymbolesAgri.download, size: 18),
                label: const Text('Copier'),
              ),
              if (f.complete)
                TextButton.icon(
                  key: Key('sauvegarde-restaurer-${f.fichier}'),
                  onPressed: () => setState(() => _restauration = f.fichier),
                  icon: const Icon(SymbolesAgri.restart_alt, size: 18),
                  label: const Text('Restaurer'),
                ),
            ]),
          ),
        if (_restauration != null) ...[
          const SizedBox(height: AgriSpacing.sm),
          Text(
            'Restaurer $_restauration ? La base de ce poste sera REMPLACÉE par cette sauvegarde au prochain lancement : tout ce qui a été saisi depuis est perdu. La base actuelle est gardée à côté (agrierp.avant-restauration.sqlite).',
            key: const Key('sauvegarde-confirmation-restauration'),
            style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
          ),
          const SizedBox(height: AgriSpacing.xs),
          Row(children: [
            TextButton(onPressed: () => setState(() => _restauration = null), child: const Text('Annuler')),
            _bouton('sauvegarde-confirmer-restauration', 'Confirmer la restauration', SymbolesAgri.restart_alt, () async {
              final f = _restauration!;
              setState(() => _restauration = null);
              await _faire(() => widget.admin.programmerRestauration(f));
            }, plein: true),
          ]),
        ],
      ],
    );
  }
}

/// « Postes & Appairage » (`Parametres\PostesAppairage`) : CE poste — le seul qu'il puisse gérer sans le serveur.
class SectionCePoste extends StatefulWidget {
  const SectionCePoste({super.key, required this.admin, required this.identifiant, this.synchroniser});

  final AdministrationLocale admin;
  final String identifiant;

  /// « Synchroniser maintenant » (le moteur du poste) ; `null` : le bouton est masqué.
  final Future<String> Function()? synchroniser;

  @override
  State<SectionCePoste> createState() => _SectionCePosteState();
}

class _SectionCePosteState extends State<SectionCePoste> {
  ({int enAttente, int conflits, DateTime? derniere})? _etat;
  String? _message;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final e = await widget.admin.etatDuPoste();
    if (mounted) setState(() => _etat = e);
  }

  @override
  Widget build(BuildContext context) {
    final e = _etat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Ce poste', style: TextStyle(fontSize: AgriTypography.xl, fontWeight: AgriTypography.gras, color: AgriColors.onSurface)),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          "Ce poste fonctionne seul : ses saisies restent ici jusqu'à la prochaine synchronisation. L'état des autres postes se consulte au serveur.",
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.sm),
        ListTile(
          key: const Key('ce-poste'),
          dense: true,
          title: Text(widget.identifiant, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
          subtitle: Text(
            e == null
                ? '—'
                : '${e.enAttente} saisie(s) en attente · ${e.conflits} refus du serveur · dernière synchronisation : ${e.derniere == null ? '—' : _quand(e.derniere!.toLocal())}',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        Wrap(spacing: AgriSpacing.sm, children: [
          if (widget.synchroniser != null)
            OutlinedButton.icon(
              key: const Key('poste-synchroniser'),
              onPressed: () async {
                final m = await widget.synchroniser!();
                if (!mounted) return;
                setState(() => _message = m);
                await _charger();
              },
              icon: const Icon(SymbolesAgri.sync, size: 18),
              label: const Text('Synchroniser maintenant'),
            ),
          OutlinedButton.icon(key: const Key('poste-actualiser'), onPressed: _charger, icon: const Icon(SymbolesAgri.refresh, size: 18), label: const Text('Actualiser')),
        ]),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: AgriSpacing.xs), child: Text(_message!, key: const Key('poste-message'), style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest))),
      ],
    );
  }
}
