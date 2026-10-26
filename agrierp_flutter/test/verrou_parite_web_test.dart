import 'dart:io';

import 'package:agrierp/core/auth/verrou_inactivite.dart';
import 'package:agrierp/core/auth/verrou_local.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket VW5 — LE VERROU EST PRÉSENT DES DEUX CÔTÉS, AVEC UN SEUL JEU DE TEXTES.
///
/// Décision du client (26/10/2026) : « appliquer aussi le module de verrou session sur le web ». Le web est le maître
/// (doctrine, article 0) : ses libellés sont LUS dans le Blade (`verrou-session.blade.php`, `mon-profil.blade.php`,
/// `layouts/app.blade.php`) et ses durées sont CELLES DU VRAI PHP (`VerrouSessionService`, exécuté). Ce que chaque côté
/// fait pour déverrouiller (mot de passe vérifié par le serveur / PIN local sans réseau) reste propre à lui : seuls
/// les textes COMMUNS sont verrouillés ici. Un renommage au web, ou au poste, fait rougir ce test.
void main() {
  final blade = File('$dossierLaravel/resources/views/components/verrou-session.blade.php');
  final profilBlade = File('$dossierLaravel/resources/views/livewire/profil/mon-profil.blade.php');
  final layoutBlade = File('$dossierLaravel/resources/views/layouts/app.blade.php');
  final service = File('$dossierLaravel/app/Services/VerrouSessionService.php');
  final sansLaravel = blade.existsSync() && profilBlade.existsSync() && layoutBlade.existsSync() && service.existsSync()
      ? false
      : 'dépôt Laravel absent ou sans le verrou web ($dossierLaravel)';

  String poste(String chemin) => File(chemin).readAsStringSync();
  String normaliser(String s) => s.replaceAll(RegExp(r'\s+'), ' ').replaceAll('&amp;', '&').replaceAll('&nbsp;', ' ');

  group('textes de l\'écran de verrouillage', () {
    test('titre, libellé de l\'identifiant et bouton sont identiques au web', () {
      final web = normaliser(blade.readAsStringSync());
      final ecran = poste('lib/features/verrou/ecran_verrou.dart');

      for (final texte in ['Application verrouillée', "NOM D'UTILISATEUR", 'DÉVERROUILLER']) {
        expect(web, contains(texte), reason: 'le Blade web a perdu « $texte »');
        expect(ecran, contains(texte), reason: 'l\'écran du poste a perdu « $texte »');
      }
    }, skip: sansLaravel);

    test('le sous-titre est « Session de {nom}. Saisissez votre … pour reprendre votre travail. »', () {
      final web = normaliser(blade.readAsStringSync());
      final ecran = normaliser(poste('lib/features/verrou/ecran_verrou.dart'));

      expect(web, contains('Session de {{ \$nom }}. Saisissez votre mot de passe pour reprendre votre travail.'));
      // Même phrase au poste, seul le secret change (code PIN).
      expect(ecran, contains('Session de \${widget.nomUtilisateur}. Saisissez votre code PIN pour reprendre votre travail.'));
    }, skip: sansLaravel);

    test('le message du limiteur et sa mise en forme sont les mêmes', () {
      final web = poste('$dossierLaravel/app/Http/Controllers/Auth/VerrouSessionController.php');
      final ecran = poste('lib/features/verrou/ecran_verrou.dart');

      expect(web, contains('"Trop d\'essais. Réessayez dans "'));
      expect(ecran, contains('Trop d\'essais. Réessayez dans '));
      // « 1 min 05 s » / « 42 s » des deux côtés.
      expect(poste(service.path), contains("' min '.str_pad((string) (\$secondes % 60), 2, '0', STR_PAD_LEFT).' s'"));
      expect(ecran, contains("\${secondes ~/ 60} min \${(secondes % 60).toString().padLeft(2, '0')} s"));
    }, skip: sansLaravel);

    test('les dix échecs déconnectent des deux côtés : même début de message', () {
      final ecran = poste('lib/features/verrou/ecran_verrou.dart');

      expect(poste('$dossierLaravel/app/Http/Controllers/Auth/VerrouSessionController.php'), contains("Trop d'échecs :"));
      expect(ecran, contains("Trop d'échecs :"));
    }, skip: sansLaravel);

    test('les seuils (5 essais avant l\'attente, 10 échecs avant la déconnexion) sont ceux du VRAI PHP', () {
      final raison = sautSansPhp();
      if (raison != null) {
        markTestSkipped(raison);
        return;
      }
      final r = executerPhp(r'''
require 'vendor/autoload.php';
use App\Services\VerrouSessionService as V;
echo json_encode(['essais' => V::MAX_TENTATIVES, 'echecs' => V::ECHECS_MAX, 'blocage' => V::DUREE_BLOCAGE]);
''', null) as Map<String, dynamic>;

      expect(r['essais'], VerrouLocal.echecsAvantAttente);
      expect(r['echecs'], VerrouLocal.echecsAvantReconnexion);
      expect([r['essais'], r['echecs']], [5, 10], reason: 'littéraux du PRD, § 5');
      // Le web bloque 15 minutes (900 s) au 5e échec, le poste temporise à son rythme (30 s, 1, 5, 15, 30 min).
      expect(r['blocage'], 900);
    });
  });

  group('menu du compte', () {
    test('« Verrouiller » avec l\'icône lock, avant Déconnexion, des deux côtés', () {
      final web = layoutBlade.readAsStringSync();
      final menu = web.substring(web.indexOf('id="dd-profile"'), web.indexOf('</form>', web.indexOf('id="dd-profile"')));
      expect(menu, contains('text-[16px]">lock</span>Verrouiller</button>'));
      expect(menu.indexOf('Verrouiller'), lessThan(menu.indexOf('Déconnexion')));

      final barre = poste('lib/core/widgets/barre_superieure.dart');
      expect(barre, contains("SymbolesAgri.lock, 'Verrouiller'"));
      expect(barre.indexOf("'Verrouiller'"), lessThan(barre.indexOf("'Déconnexion'")));
    }, skip: sansLaravel);
  });

  group('Mon Profil — Verrouillage automatique', () {
    test('même titre et même phrase d\'aide (début identique)', () {
      final web = normaliser(profilBlade.readAsStringSync());
      final profil = normaliser(poste('lib/features/profil/mon_profil_screen.dart'));

      expect(web, contains('>Verrouillage automatique</p>'));
      expect(profil, contains("'Verrouillage automatique'.toUpperCase()"));

      const debut = "Après ce délai sans toucher à la souris ni au clavier, l'application se verrouille : le ";
      expect(web, contains(debut));
      expect(profil, contains(debut));
    }, skip: sansLaravel);

    test('les durées, le défaut et leurs libellés sont ceux du VRAI PHP du serveur', () {
      final raison = sautSansPhp();
      if (raison != null) {
        markTestSkipped(raison);
        return;
      }
      final r = executerPhp(r'''
require 'vendor/autoload.php';
use App\Services\VerrouSessionService as V;
echo json_encode([
  'durees' => V::DUREES,
  'defaut' => V::DUREE_PAR_DEFAUT,
  'echecs' => V::ECHECS_MAX,
  'libelles' => array_map(fn ($m) => V::libelleDuree($m), V::DUREES),
], JSON_UNESCAPED_UNICODE);
''', null) as Map<String, dynamic>;

      expect(r['durees'], ReglageInactivite.choix);
      expect(r['defaut'], ReglageInactivite.parDefaut);
      expect(r['libelles'], [for (final m in ReglageInactivite.choix) ReglageInactivite.libelle(m)]);
      // Littéraux calculés à la main : le test ne se contente pas de comparer deux sorties du même code.
      expect(ReglageInactivite.choix, [0, 1, 5, 15, 30]);
      expect(ReglageInactivite.parDefaut, 5);
      expect([for (final m in ReglageInactivite.choix) ReglageInactivite.libelle(m)],
          ['Jamais', '1 minute', '5 minutes', '15 minutes', '30 minutes']);
    });

    test('les durées du JavaScript du web sont celles du poste', () {
      final js = File('$dossierLaravel/resources/js/verrou-logique.js');
      if (!js.existsSync()) {
        markTestSkipped('verrou-logique.js absent ($dossierLaravel)');
        return;
      }
      final m = RegExp(r'export const DUREES = \[([0-9, ]+)\]').firstMatch(js.readAsStringSync())!;
      expect(m.group(1)!.split(',').map((e) => int.parse(e.trim())).toList(), ReglageInactivite.choix);
    });
  });
}
