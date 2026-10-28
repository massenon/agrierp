// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/modale_agri.dart';

/// Refus d'un geste d'administration en ligne : le message du serveur (ou celui du poste hors ligne).
class RefusAdministration implements Exception {
  const RefusAdministration(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Un poste appairé tel que le serveur le décrit (`JournalSynchronisationService::etatDesPostes`).
class PosteAppaire {
  const PosteAppaire({required this.poste, required this.utilisateur, required this.etat, required this.dernierContact, required this.dernierEnvoi});

  final String poste;
  final String utilisateur;
  final String etat;
  final String? dernierContact;
  final String? dernierEnvoi;
}

class FichierSauvegarde {
  const FichierSauvegarde({required this.fichier, required this.date, required this.portee, required this.taille});

  final String fichier;
  final String date;
  final String portee;
  final int taille;
}

/// Tickets PA-1, PA-5, PA-6, PA-8 (SMS de test) — GESTES D'ADMINISTRATION EN LIGNE : déconnecter toutes les sessions, gérer
/// les postes appairés, les sauvegardes, tester le fournisseur SMS.
///
/// ⚠️ Ces gestes AGISSENT SUR LE SERVEUR : ils n'ont pas de version hors ligne et ne s'écrivent pas en base locale. Même
/// précédent que la réinitialisation (R-1) : la route du serveur (mêmes services et mêmes droits que le web), par le client
/// partagé qui porte le jeton. Hors ligne, le poste le dit au lieu de laisser croire à une panne.
class AdministrationEnLigne {
  AdministrationEnLigne({
    required Dio client,
    required SyncEngine engine,
    required String Function() role,
    Future<Directory?> Function()? dossierTelechargement,
  }) :
       _client = client,
       _engine = engine,
       _role = role,
       _dossier = dossierTelechargement ?? _dossierParDefaut;

  final Dio _client;
  final SyncEngine _engine;
  final String Function() _role;
  final Future<Directory?> Function() _dossier;

  static const refusHorsLigne =
      "Hors ligne : ce geste agit sur le serveur, que ce poste ne peut pas joindre. Reconnectez le poste au réseau pour l'utiliser.";

  static Future<Directory?> _dossierParDefaut() async => (await getDownloadsDirectory()) ?? await getApplicationDocumentsDirectory();

  bool peut(String permission) => PermissionsPoste.peut(_role(), permission);

  Future<bool> estEnLigne() => _engine.estEnLigne();

  Future<Map<String, dynamic>> _appeler(Future<Response<dynamic>> Function() requete) async {
    if (!await _engine.estEnLigne()) throw const RefusAdministration(refusHorsLigne);
    try {
      final r = await requete();
      final corps = r.data;
      return corps is Map ? Map<String, dynamic>.from(corps) : <String, dynamic>{};
    } on DioException catch (e) {
      final corps = e.response?.data;
      final message = corps is Map ? corps['message'] : null;
      throw RefusAdministration(message is String && message.isNotEmpty ? message : "Le serveur n'a pas répondu : réessayez dans un instant.");
    }
  }

  // PA-1
  Future<String> viderSessions() async => '${(await _appeler(() => _client.post<Map<String, dynamic>>('/api/parametres/sessions/vider')))['message']}';

  // PA-5
  Future<List<PosteAppaire>> postes() async {
    final r = await _appeler(() => _client.get<Map<String, dynamic>>('/api/parametres/postes'));
    return [
      for (final p in (r['postes'] as List? ?? const []).cast<Map>())
        PosteAppaire(
          poste: '${p['poste']}', utilisateur: '${p['utilisateur'] ?? '—'}', etat: '${p['libelle_etat'] ?? p['etat'] ?? '—'}',
          dernierContact: p['dernier_contact'] as String?, dernierEnvoi: p['dernier_envoi'] as String?,
        ),
    ];
  }

  Future<String> demanderSynchronisation([String? poste]) async =>
      '${(await _appeler(() => _client.post<Map<String, dynamic>>('/api/parametres/postes/demander', data: {'poste': poste})))['message']}';

  Future<String> revoquer(String poste) async =>
      '${(await _appeler(() => _client.post<Map<String, dynamic>>('/api/parametres/postes/revoquer', data: {'poste': poste})))['message']}';

  // PA-6
  Future<({List<FichierSauvegarde> fichiers, Map<String, String> modules})> sauvegardes() async {
    final r = await _appeler(() => _client.get<Map<String, dynamic>>('/api/parametres/sauvegardes'));
    return (
      fichiers: [
        for (final f in (r['fichiers'] as List? ?? const []).cast<Map>())
          FichierSauvegarde(fichier: '${f['fichier']}', date: '${f['date']}', portee: '${f['portee']}', taille: (f['taille'] as num?)?.toInt() ?? 0),
      ],
      modules: {for (final e in ((r['modules'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    );
  }

  Future<String> generer({String? module}) async =>
      '${(await _appeler(() => _client.post<Map<String, dynamic>>('/api/parametres/sauvegardes/generer', data: {'module': ?module})))['message']}';

  Future<String> importer({required String fichier, required String module}) async =>
      '${(await _appeler(() => _client.post<Map<String, dynamic>>('/api/parametres/sauvegardes/importer', data: {'fichier': fichier, 'module': module})))['message']}';

  /// Télécharge [fichier] dans le dossier Téléchargements du poste ; rend le chemin écrit.
  Future<String> telecharger(String fichier) async {
    if (!await _engine.estEnLigne()) throw const RefusAdministration(refusHorsLigne);
    try {
      final r = await _client.get<List<int>>('/api/parametres/sauvegardes/telecharger/${Uri.encodeComponent(fichier)}', options: Options(responseType: ResponseType.bytes));
      final dossier = await _dossier();
      if (dossier == null) throw const RefusAdministration("Aucun dossier de téléchargement n'est disponible sur ce poste.");
      final cible = File('${dossier.path}${Platform.pathSeparator}$fichier');
      await cible.writeAsBytes(r.data ?? const []);
      return cible.path;
    } on DioException {
      throw const RefusAdministration('Sauvegarde introuvable.');
    }
  }

  // PA-8
  Future<({String message, bool succes})> testerSms(String destinataire) async {
    final r = await _appeler(() => _client.post<Map<String, dynamic>>('/api/parametres/sms/tester', data: {'destinataire': destinataire}));
    return (message: '${r['message']}', succes: r['type'] == 'success');
  }
}

String _taille(int octets) => octets >= 1048576 ? '${(octets / 1048576).toStringAsFixed(1)} Mo' : '${(octets / 1024).toStringAsFixed(1)} Ko';

Future<bool> confirmerViderSessions({required BuildContext context, required AdministrationEnLigne admin, required void Function(String) surMessage}) async {
  final ok = await afficherModale<bool>(
    context: context,
    confirmation: true,
    constructeur: (_) => _ModaleViderSessions(admin: admin, surMessage: surMessage),
  );
  return ok == true;
}

class _ModaleViderSessions extends StatefulWidget {
  const _ModaleViderSessions({required this.admin, required this.surMessage});

  final AdministrationEnLigne admin;
  final void Function(String) surMessage;

  @override
  State<_ModaleViderSessions> createState() => _ModaleViderSessionsState();
}

class _ModaleViderSessionsState extends State<_ModaleViderSessions> {
  String? _refus;

  Future<void> _ok() async {
    try {
      widget.surMessage(await widget.admin.viderSessions());
    } on RefusAdministration catch (r) {
      setState(() => _refus = r.message);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => ModaleConfirmation(
    titre: 'Déconnecter toutes les sessions ?',
    message:
        "Tous les utilisateurs du site sont déconnectés et chaque poste Windows devra se reconnecter. Les saisies en attente sur les postes sont conservées et partiront après la reconnexion. Votre propre session reste ouverte. L'action est journalisée."
        '${_refus == null ? '' : '\n\n$_refus'}',
    icone: SymbolesAgri.logout,
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
      BoutonModalePrimaire(key: const Key('sessions-deconnecter'), libelle: 'Déconnecter', couleur: AgriColors.errorRed, onPressed: _ok),
    ],
  );
}

/// Onglet « Sauvegardes » (`Parametres\Sauvegardes`) : générer, exporter un module, télécharger, importer un module.
class OngletSauvegardes extends StatefulWidget {
  const OngletSauvegardes({super.key, required this.admin});

  final AdministrationEnLigne admin;

  @override
  State<OngletSauvegardes> createState() => _OngletSauvegardesState();
}

class _OngletSauvegardesState extends State<OngletSauvegardes> {
  List<FichierSauvegarde>? _fichiers;
  Map<String, String> _modules = const {};
  String? _message;
  String? _refus;
  String _moduleExport = '';
  String _fichierImport = '';
  String _moduleImport = '';
  bool _confirmerImport = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final r = await widget.admin.sauvegardes();
      if (mounted) {
        setState(() {
          _fichiers = r.fichiers;
          _modules = r.modules;
          _refus = null;
        });
      }
    } on RefusAdministration catch (e) {
      if (mounted) setState(() => _refus = e.message);
    }
  }

  Future<void> _faire(Future<String> Function() geste) async {
    try {
      final m = await geste();
      setState(() {
        _message = m;
        _refus = null;
      });
      await _charger();
    } on RefusAdministration catch (e) {
      setState(() => _refus = e.message);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: const [
          Icon(SymbolesAgri.database, size: 26, color: AgriColors.brandEmerald),
          SizedBox(width: AgriSpacing.xs),
          Text('Sauvegardes de la Base de Données', style: TextStyle(fontSize: AgriTypography.xl, fontWeight: AgriTypography.gras, color: AgriColors.onSurface)),
        ]),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Une sauvegarde automatique est générée chaque nuit et conservée 30 jours. Téléchargez-la régulièrement : un fichier resté sur le serveur ne protège de rien si le serveur tombe.',
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
        _liste('sauvegarde-fichier-import', _fichierImport, {for (final f in fichiers ?? const <FichierSauvegarde>[]) f.fichier: f.fichier}, '-- Choisir un fichier --', (v) => _fichierImport = v),
        const SizedBox(height: AgriSpacing.xs),
        _liste('sauvegarde-module-import', _moduleImport, _modules, '-- Choisir un module --', (v) => _moduleImport = v),
        const SizedBox(height: AgriSpacing.xs),
        if (!_confirmerImport)
          _bouton('sauvegarde-importer', 'Importer', SymbolesAgri.upload, _fichierImport.isEmpty || _moduleImport.isEmpty ? null : () => setState(() => _confirmerImport = true))
        else ...[
          const Text(
            'Remplacer les données de ce module ? Les données actuelles du module sélectionné seront supprimées puis remplacées par celles du fichier. Les enregistrements d\'autres modules qui y font référence peuvent devenir orphelins. Générez une sauvegarde complète avant de poursuivre.',
            key: Key('sauvegarde-confirmation'),
            style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
          ),
          const SizedBox(height: AgriSpacing.xs),
          Row(children: [
            TextButton(onPressed: () => setState(() => _confirmerImport = false), child: const Text('Annuler')),
            _bouton('sauvegarde-confirmer-import', "Confirmer l'import", SymbolesAgri.upload, () async {
              setState(() => _confirmerImport = false);
              await _faire(() => widget.admin.importer(fichier: _fichierImport, module: _moduleImport));
            }, plein: true),
          ]),
        ],
        const SizedBox(height: AgriSpacing.lg),
        if (fichiers == null && _refus == null) const Center(child: CircularProgressIndicator()),
        if (fichiers != null && fichiers.isEmpty)
          const Text('Aucune sauvegarde pour le moment — générez-en une avec le bouton ci-dessus.', key: Key('sauvegarde-vide'), style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
        for (final f in fichiers ?? const <FichierSauvegarde>[])
          ListTile(
            key: Key('sauvegarde-${f.fichier}'),
            dense: true,
            title: Text(f.fichier, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
            subtitle: Text('${f.date} · ${f.portee} · ${_taille(f.taille)}', style: const TextStyle(fontSize: 11)),
            trailing: TextButton.icon(
              key: Key('sauvegarde-telecharger-${f.fichier}'),
              onPressed: () => _faire(() async => 'Sauvegarde téléchargée : ${await widget.admin.telecharger(f.fichier)}'),
              icon: const Icon(SymbolesAgri.download, size: 18),
              label: const Text('Télécharger'),
            ),
          ),
      ],
    );
  }
}

/// « Postes & Appairage » (`Parametres\PostesAppairage`) : les AUTRES postes appairés au serveur.
class SectionPostesAppaires extends StatefulWidget {
  const SectionPostesAppaires({super.key, required this.admin});

  final AdministrationEnLigne admin;

  @override
  State<SectionPostesAppaires> createState() => _SectionPostesAppairesState();
}

class _SectionPostesAppairesState extends State<SectionPostesAppaires> {
  List<PosteAppaire>? _postes;
  String? _message;
  String? _refus;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final p = await widget.admin.postes();
      if (mounted) {
        setState(() {
          _postes = p;
          _refus = null;
        });
      }
    } on RefusAdministration catch (e) {
      if (mounted) setState(() => _refus = e.message);
    }
  }

  Future<void> _faire(Future<String> Function() geste) async {
    try {
      final m = await geste();
      setState(() {
        _message = m;
        _refus = null;
      });
      await _charger();
    } on RefusAdministration catch (e) {
      setState(() => _refus = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final postes = _postes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Postes & Appairage', style: TextStyle(fontSize: AgriTypography.xl, fontWeight: AgriTypography.gras, color: AgriColors.onSurface)),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          "Postes Windows appairés au serveur : un poste est appairé dès qu'un compte s'y connecte, et le reste jusqu'à l'expiration de son jeton ou sa révocation.",
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.sm),
        Wrap(spacing: AgriSpacing.sm, children: [
          OutlinedButton.icon(key: const Key('postes-demander-tous'), onPressed: () => _faire(widget.admin.demanderSynchronisation), icon: const Icon(SymbolesAgri.sync, size: 18), label: const Text('Demander la synchronisation des postes')),
          OutlinedButton.icon(key: const Key('postes-actualiser'), onPressed: _charger, icon: const Icon(SymbolesAgri.refresh, size: 18), label: const Text('Actualiser')),
        ]),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: AgriSpacing.xs), child: Text(_message!, key: const Key('postes-message'), style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest))),
        if (_refus != null) Padding(padding: const EdgeInsets.only(top: AgriSpacing.xs), child: Text(_refus!, key: const Key('postes-refus'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep))),
        const SizedBox(height: AgriSpacing.sm),
        if (postes != null && postes.isEmpty) const Text("Aucun poste n'est appairé au serveur pour le moment.", key: Key('postes-vide'), style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
        for (final p in postes ?? const <PosteAppaire>[])
          ListTile(
            key: Key('poste-${p.poste}'),
            dense: true,
            title: Text(p.poste, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
            subtitle: Text('${p.utilisateur} · ${p.etat}', style: const TextStyle(fontSize: 11)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(key: Key('poste-demander-${p.poste}'), tooltip: 'Demander la synchronisation de ce poste', onPressed: () => _faire(() => widget.admin.demanderSynchronisation(p.poste)), icon: const Icon(SymbolesAgri.sync, size: 18)),
              IconButton(key: Key('poste-revoquer-${p.poste}'), tooltip: "Révoquer l'appairage", onPressed: () => _faire(() => widget.admin.revoquer(p.poste)), icon: const Icon(SymbolesAgri.lock, size: 18, color: AgriColors.errorDeep)),
            ]),
          ),
        const SizedBox(height: AgriSpacing.sm),
        const Text(
          "« Révoquer l'appairage » supprime les jetons de ce poste, pour tous les comptes qui s'y sont connectés : utile pour un poste perdu, volé ou remplacé. « Demander la synchronisation » dépose une demande que chaque poste connecté lit dans les 30 secondes.",
          style: TextStyle(fontSize: 11, color: AgriColors.outline),
        ),
      ],
    );
  }
}
