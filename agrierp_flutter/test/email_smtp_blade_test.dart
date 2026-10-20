import 'dart:io';

import 'package:agrierp/core/config/parametres_smtp.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'fidelite_libelles_test.dart' show chainesDe;

/// Tickets CFG-1 / CFG-2 — GARDE-FOU : L'ONGLET « EMAIL (SMTP) » DU POSTE CONFRONTÉ AU BLADE MAÎTRE.
///
/// ⚠️⚠️ **LE WEB EST MAÎTRE** (doctrine, article 5). Titre, cartes, libellés des champs, aides, boutons, états du
/// mot de passe, modale d'effacement, choix de sécurité, messages des toasts et messages de validation sont LUS dans
/// `email-smtp.blade.php`, `EmailSmtp.php`, `modal-confirm-hard-delete.blade.php` et `lang/fr/validation.php`,
/// jamais recopiés ici : une retouche du web fait rougir le poste au lieu de diverger en silence. La place de
/// l'onglet dans le hub est lue dans `parametres-hub.blade.php`.
String? _lireLaravel(String relatif) {
  final f = File('$dossierLaravel/$relatif');
  return f.existsSync() ? f.readAsStringSync() : null;
}

final String? _blade = _lireLaravel('resources/views/livewire/parametres/email-smtp.blade.php');
final String? _composant = _lireLaravel('app/Livewire/Parametres/EmailSmtp.php');
final String? _hub = _lireLaravel('resources/views/livewire/parametres/parametres-hub.blade.php');
final String? _validation = _lireLaravel('lang/fr/validation.php');

/// Littéraux du poste pour cet onglet : l'écran et le service d'envoi (messages du test).
final String _poste = [
  'lib/features/parametres/onglet_email_smtp.dart',
  'lib/core/config/envoi_email_test.dart',
  'lib/core/config/parametres_smtp.dart',
].map((f) => chainesDe(File(f).readAsStringSync())).join('\n');

String _html(String s) => s
    .replaceAll('&gt;', '>')
    .replaceAll('&lt;', '<')
    .replaceAll('&amp;', '&')
    .replaceAll('&#039;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Textes visibles du Blade : étiquettes, titres, boutons, paragraphes d'état, aides (`placeholder`).
List<String> _textesDuBlade(String blade) {
  final textes = <String>[];
  for (final m in RegExp(r'<label[^>]*>([^<]+)</label>').allMatches(blade)) {
    textes.add(_html(m.group(1)!));
  }
  for (final m in RegExp(r'<h[23][^>]*>.*?</span>([^<]+)\s*</h[23]>', dotAll: true).allMatches(blade)) {
    textes.add(_html(m.group(1)!));
  }
  for (final m in RegExp(r'<button[^>]*>(?:\s*<span[^>]*>[^<]*</span>)?([^<]+)</button>', dotAll: true).allMatches(blade)) {
    final t = _html(m.group(1)!);
    if (t.isNotEmpty) textes.add(t);
  }
  for (final m in RegExp(r'<p dusk="smtp-mot-de-passe-etat"[^>]*>(?:<span[^>]*>[^<]*</span>)?([^<]+)</p>').allMatches(blade)) {
    textes.add(_html(m.group(1)!));
  }
  for (final m in RegExp(r'placeholder="([^"{]+)"').allMatches(blade)) {
    final t = _html(m.group(1)!);
    // « ex : … » : exemples de saisie, propres à chaque surface (le poste écrit les siens).
    if (!t.startsWith('ex :')) textes.add(t);
  }
  return textes;
}

void main() {
  final absent = _blade == null || _composant == null || _hub == null || _validation == null
      ? 'dépôt Laravel absent ($dossierLaravel) : comparaison au web impossible'
      : null;

  test('⚠️⚠️ chaque texte de l onglet web existe dans l onglet du poste', () {
    final textes = _textesDuBlade(_blade!);
    // Repères : le relevé ne doit pas être vide parce qu'une expression a cessé de correspondre.
    expect(
      textes,
      containsAll([
        'Email (SMTP)',
        'Serveur SMTP',
        'Hôte SMTP *',
        'Port *',
        'Sécurité',
        'Utilisateur SMTP',
        'Mot de Passe SMTP',
        "Adresse d'Expédition",
        'Enregistrer la Configuration SMTP',
        'Envoyer un e-mail de test',
        'Destinataire du test',
        'Mot de passe enregistré',
        'Aucun mot de passe enregistré',
        'Effacer le mot de passe',
        'Laisser vide pour conserver le mot de passe actuel',
      ]),
    );

    final manquants = textes.where((t) => !_poste.contains(t)).toSet().toList();
    expect(manquants, isEmpty, reason: 'Libellés du Blade absents du poste (le web est maître).');
  }, skip: absent ?? false);

  test('⚠️ les choix de sécurité sont ceux du web, dans son ordre', () {
    final bloc = RegExp(r'SECURITES = \[(.*?)\];', dotAll: true).firstMatch(_composant!)!.group(1)!;
    final web = [
      for (final m in RegExp(r"'([^']*)' => '([^']*)'").allMatches(bloc)) (m.group(1)!, m.group(2)!),
    ];
    expect(web, [for (final s in SecuriteSmtp.values) (s.code, s.libelle)]);
  }, skip: absent ?? false);

  test('⚠️ les messages des toasts sont ceux du composant web', () {
    final messages = [
      for (final m in RegExp(r'''message: (['"])(.*?)\1''').allMatches(_composant!)) m.group(2)!,
    ];
    expect(messages, isNotEmpty);
    for (final message in messages) {
      // Une interpolation PHP (`{$this->testEmailTo}`) se compare morceau par morceau.
      for (final morceau in message.replaceAll(r"\'", "'").split(RegExp(r'\{\$[^}]+\}'))) {
        if (morceau.trim().isEmpty) continue;
        expect(_poste, contains(morceau), reason: 'message du web : « $message »');
      }
    }
  }, skip: absent ?? false);

  test('⚠️ la modale d effacement reprend celle du web', () {
    final modale = RegExp(r'<x-modal-confirm-hard-delete(.*?)/>', dotAll: true).firstMatch(_blade!)!.group(1)!;
    String attribut(String nom) => _html(RegExp('$nom="([^"]*)"').firstMatch(modale)!.group(1)!);
    expect(_poste, contains(attribut('title')));
    expect(_poste, contains(attribut('confirm-label')));
    expect(_poste, contains(attribut('item-label')));
    expect(_poste, contains(attribut('warning')));
    // Corps du composant partagé : « … sera supprimé(e) définitivement. Cette action est irréversible. »
    expect(_poste, contains('sera supprimé(e) définitivement. Cette action est irréversible.'));
  }, skip: absent ?? false);

  /// Parité des refus (article 5.4) : `lang/fr/validation.php` + attributs de `EmailSmtp::save()`.
  test('⚠️ les messages de validation sont ceux du web', () {
    String regle(String cle) => RegExp("'$cle' => '([^']*)'").firstMatch(_validation!)!.group(1)!;
    String regleImbriquee(String groupe, String cle) {
      final bloc = RegExp("'$groupe' => \\[(.*?)\\]", dotAll: true).firstMatch(_validation!)!.group(1)!;
      return RegExp("'$cle' => '([^']*)'").firstMatch(bloc)!.group(1)!;
    }

    String attribut(String champ) {
      final m = RegExp("'$champ' => (?:'([^']*)'|\"([^\"]*)\")")
          .firstMatch(_composant!.substring(_composant!.indexOf('], [], [')))!;
      return m.group(1) ?? m.group(2)!;
    }

    String message(String gabarit, String champ, [Map<String, String> autres = const {}]) {
      var m = gabarit.replaceAll(':attribute', attribut(champ));
      autres.forEach((k, v) => m = m.replaceAll(':$k', v));
      return m;
    }

    final e = ParametresSmtp.erreursDeSaisie;
    expect(e(hote: '', port: '25')['hote'], message(regle('required'), 'smtpHost'));
    expect(e(hote: 'x' * 151, port: '25')['hote'], message(regleImbriquee('max', 'string'), 'smtpHost', {'max': '150'}));
    expect(e(hote: 'h', port: '')['port'], message(regle('required'), 'smtpPort'));
    expect(e(hote: 'h', port: 'abc')['port'], message(regle('integer'), 'smtpPort'));
    expect(e(hote: 'h', port: '0')['port'], message(regleImbriquee('min', 'numeric'), 'smtpPort', {'min': '1'}));
    expect(e(hote: 'h', port: '70000')['port'], message(regleImbriquee('max', 'numeric'), 'smtpPort', {'max': '65535'}));
    expect(
      e(hote: 'h', port: '25', utilisateur: 'u' * 151)['utilisateur'],
      message(regleImbriquee('max', 'string'), 'smtpUser', {'max': '150'}),
    );
    expect(e(hote: 'h', port: '25', expediteur: 'x')['expediteur'], message(regle('email'), 'fromAddress'));
  }, skip: absent ?? false);

  /// Place de l'onglet : comme au web, « Email (SMTP) » suit « Données de l'Entreprise », et l'appairage suit
  /// « Gestion Utilisateurs » (« Postes & Appairage » au web).
  test('⚠️ les onglets de configuration sont à la place qu ils ont au web', () {
    final web = [for (final m in RegExp(r"'label' => '((?:[^'\\]|\\.)*)'").allMatches(_hub!)) m.group(1)!.replaceAll(r"\'", "'")];
    final poste = ParametresGenerauxScreen.onglets.map((o) => o.$1).toList();

    int apres(List<String> l, String a, String b) => l.indexOf(b) - l.indexOf(a);
    expect(apres(web, "Données de l'Entreprise", 'Email (SMTP)'), 1);
    expect(apres(poste, "Données de l'Entreprise", ParametresGenerauxScreen.ongletEmailSmtp), 1);
    expect(apres(web, 'Gestion Utilisateurs', 'Postes & Appairage'), 1);
    expect(apres(poste, 'Gestion Utilisateurs', ParametresGenerauxScreen.ongletAppairage), 1);
    expect(web, contains(ParametresGenerauxScreen.ongletEmailSmtp));
  }, skip: absent ?? false);
}
