import 'dart:io';

import 'package:agrierp/core/theme/symboles_agri.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:agrierp/features/parametres/reinitialisation_poste.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'fidelite_libelles_test.dart' show chainesDe;

/// Ticket R-1 — GARDE-FOU : L'ONGLET « RÉINITIALISATION » DU POSTE CONFRONTÉ AU BLADE MAÎTRE.
///
/// ⚠️⚠️ **LE WEB EST MAÎTRE** (doctrine, article 5). Les textes visibles, les icônes, le mot de confirmation, les
/// messages (champ, refus) et la place de l'onglet sont LUS dans `reinitialisation-donnees.blade.php`,
/// `ReinitialisationDonneesService.php`, `ReinitialisationDonneesController.php`, `parametres-hub.blade.php` et
/// `routes/api.php`, jamais recopiés ici : une retouche du web fait rougir le poste au lieu de diverger en silence.
String? _lireLaravel(String relatif) {
  final f = File('$dossierLaravel/$relatif');
  return f.existsSync() ? f.readAsStringSync() : null;
}

final String? _blade = _lireLaravel('resources/views/livewire/parametres/reinitialisation-donnees.blade.php');
final String? _service = _lireLaravel('app/Services/ReinitialisationDonneesService.php');
final String? _controleur = _lireLaravel('app/Http/Controllers/Api/ReinitialisationDonneesController.php');
final String? _hub = _lireLaravel('resources/views/livewire/parametres/parametres-hub.blade.php');
final String? _routes = _lireLaravel('routes/api.php');

const _fichiersPoste = [
  'lib/features/parametres/onglet_reinitialisation.dart',
  'lib/features/parametres/reinitialisation_poste.dart',
];

String _espaces(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Littéraux du poste pour cet onglet (écran + dépôt), espaces normalisés.
final String _poste = _espaces(_fichiersPoste.map((f) => chainesDe(File(f).readAsStringSync())).join('\n'));

/// Source du poste SANS commentaires (icônes employées).
final String _codePoste = _fichiersPoste
    .map((f) => File(f).readAsStringSync().split('\n').map((l) => l.split('//').first).join('\n'))
    .join('\n');

String _html(String s) => s
    .replaceAll('&gt;', '>')
    .replaceAll('&lt;', '<')
    .replaceAll('&amp;', '&')
    .replaceAll('&#039;', "'");

/// Textes visibles du Blade : tout ce qui reste entre les balises, une fois retirés les icônes, les expressions
/// `{{ … }}` et les directives. Les deux libellés de la bascule (`'Activé' : 'Désactivé'`) sont repris de leur
/// expression ; `<strong>` est une mise en forme dans la phrase, pas une coupure.
List<String> _textesDuBlade(String blade) {
  final textes = <String>[
    for (final m in RegExp(r"\? '([^']+)' : '([^']+)' \}\}").allMatches(blade))
      // Un libellé commence par une majuscule ; une classe CSS ou un nom d'icône, non.
      if (RegExp(r'^[A-ZÉ]').hasMatch(m.group(1)!)) ...[m.group(1)!, m.group(2)!],
  ];
  // Coupure entre deux textes : une balise, une icône, une expression, une directive — jamais un retour à la
  // ligne, qui ne fait que mettre en page une phrase du Blade.
  const coupure = '\u0000';
  final nu = blade
      .replaceAll(RegExp(r'<span class="material-symbols-outlined[^>]*>.*?</span>', dotAll: true), coupure)
      .replaceAll(RegExp(r'\{\{.*?\}\}', dotAll: true), coupure)
      .replaceAll(RegExp(r'@(if|elseif|error)\b\(.*?\)\s', dotAll: true), coupure)
      .replaceAll(RegExp(r'@(else|endif|enderror)\b'), coupure)
      .replaceAll(RegExp(r'</?strong>'), '')
      .replaceAll(RegExp(r'<[^>]+>', dotAll: true), coupure);
  for (final morceau in nu.split(coupure)) {
    final t = _espaces(_html(morceau));
    if (t.isNotEmpty) textes.add(t);
  }
  for (final m in RegExp(r'placeholder="([^"{]+)"').allMatches(blade)) {
    textes.add(_html(m.group(1)!));
  }
  return textes;
}

/// Constante PHP `NOM = '…';` d'une source.
String _constante(String source, String nom) {
  final m = RegExp("$nom = '((?:[^'\\\\]|\\\\.)*)';").firstMatch(source)!;
  return m.group(1)!.replaceAll(r"\'", "'");
}

void main() {
  final absent = [_blade, _service, _controleur, _hub, _routes].contains(null)
      ? 'dépôt Laravel absent ($dossierLaravel) : comparaison au web impossible'
      : null;

  test('⚠️⚠️ chaque texte de l onglet web existe dans l onglet du poste', () {
    final textes = _textesDuBlade(_blade!);
    // Repères : le relevé ne doit pas être vide parce qu'une expression a cessé de correspondre.
    expect(
      textes,
      containsAll([
        'Réinitialisation des Données',
        "Vide les données d'activité pour repartir d'une base propre après une démonstration.",
        'Mode démonstration',
        'Activé',
        'Désactivé',
        "Cette opération vide TOUTES les données d'activité",
        'Supprimé',
        'Conservé',
        'Réinitialiser les données',
        "Réinitialiser toutes les données d'activité ?",
        'Saisissez REINITIALISER pour confirmer',
        'REINITIALISER',
        'Annuler',
        'Confirmer la réinitialisation',
        'Réinitialisation verrouillée',
        'Activez le mode démonstration ci-dessus pour y accéder.',
      ]),
    );
    // La phrase coupée par `<strong>` reste entière.
    expect(textes.any((t) => t.startsWith('Cette action est irréversible :')), isTrue);
    expect(textes.any((t) => t.endsWith("· Journal d'audit")), isTrue);

    final manquants = textes.where((t) => !_poste.contains(t)).toSet().toList();
    expect(manquants, isEmpty, reason: 'Textes du Blade absents du poste (le web est maître).');
  }, skip: absent ?? false);

  test('⚠️ les icônes du web sont celles du poste', () {
    final icones = {
      for (final m in RegExp(r'material-symbols-outlined[^>]*>\s*([a-z_]+)\s*<').allMatches(_blade!)) m.group(1)!,
      // La bascule choisit son icône dans une expression.
      for (final m in RegExp(r"'(toggle_[a-z]+)'").allMatches(_blade!)) m.group(1)!,
    };
    expect(icones, containsAll(['restart_alt', 'warning', 'delete_sweep', 'shield', 'lock', 'toggle_on', 'toggle_off']));
    for (final icone in icones) {
      expect(_codePoste, contains('SymbolesAgri.$icone'), reason: 'icône du web « $icone »');
    }
  }, skip: absent ?? false);

  test('⚠️ mot de confirmation et messages : ceux du service web, mot pour mot', () {
    final mot = _constante(_service!, 'MOT_DE_CONFIRMATION');
    expect(ReinitialisationPoste.motDeConfirmation, mot);
    // `messageConfirmation()` : 'Saisissez '.self::MOT_DE_CONFIRMATION.' pour confirmer.'
    final gabarit = RegExp(r"return '([^']*)'\.self::MOT_DE_CONFIRMATION\.'([^']*)';").firstMatch(_service!)!;
    expect(ReinitialisationPoste.messageConfirmation, '${gabarit.group(1)}$mot${gabarit.group(2)}');
    // Le champ du Blade nomme le même mot.
    expect(_blade, contains('placeholder="$mot"'));
    // Refus du rôle : celui de la route du poste.
    expect(ReinitialisationPoste.refusRole, _constante(_controleur!, 'REFUS_ROLE'));
  }, skip: absent ?? false);

  test('⚠️ l onglet est à la place qu il a au web, sous son libellé et son icône', () {
    final onglets = [
      for (final m in RegExp(r"\['key' => '([^']*)', 'label' => '((?:[^'\\]|\\.)*)', 'icon' => '([^']*)'\]").allMatches(_hub!))
        (cle: m.group(1)!, libelle: m.group(2)!.replaceAll(r"\'", "'"), icone: m.group(3)!),
    ];
    final web = onglets.firstWhere((o) => o.cle == 'reinitialisation');
    final poste = ParametresGenerauxScreen.onglets.map((o) => o.$1).toList();

    expect(ParametresGenerauxScreen.ongletReinitialisation, web.libelle);
    expect(
      ParametresGenerauxScreen.onglets.firstWhere((o) => o.$1 == web.libelle).$2,
      SymbolesAgri.restart_alt,
    );
    expect(web.icone, 'restart_alt');
    // Au web : … Audit Logs, Corbeille (ARC4 : présente au poste), Réinitialisation, Sauvegardes (absente du poste).
    final libellesWeb = onglets.map((o) => o.libelle).toList();
    final precedentWeb = libellesWeb
        .sublist(0, libellesWeb.indexOf(web.libelle))
        .lastWhere(poste.contains);
    expect(poste.indexOf(web.libelle) - poste.indexOf(precedentWeb), 1);
    expect(precedentWeb, 'Corbeille');
  }, skip: absent ?? false);

  test('⚠️ les routes appelées par le poste existent au serveur', () {
    final source = File('lib/features/parametres/reinitialisation_poste.dart').readAsStringSync();
    expect(source, contains("_route = '/api/parametres/reinitialisation'"));
    for (final route in ["'/parametres/reinitialisation'", "'/parametres/reinitialisation/mode-demo'"]) {
      expect(_routes, contains(route));
    }
  }, skip: absent ?? false);
}
