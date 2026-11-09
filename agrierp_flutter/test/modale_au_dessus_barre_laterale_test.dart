import 'package:agrierp/core/widgets/modale_agri.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Défaut du web (27/10/2026) : la modale de Synchronisation, rendue dans l'en-tête, passait
/// SOUS la barre latérale et se trouvait rognée à gauche. Au poste, `afficherModale` ouvre la
/// modale sur le navigateur racine : voile et fenêtre couvrent toute la fenêtre, barre latérale
/// comprise. Ce test verrouille cette propriété (un `Navigator` imbriqué dans la zone de
/// contenu la ferait disparaître sans qu'aucune erreur ne le dise).
void main() {
  testWidgets('la modale couvre toute la fenêtre, barre latérale comprise', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Container(key: const Key('barre-laterale'), width: 288, color: Colors.green),
            Expanded(
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    key: const Key('ouvrir'),
                    onPressed: () => afficherModale<void>(
                      context: context,
                      constructeur: (_) => const ModaleAgri(
                        titre: 'Synchronisation',
                        contenu: SizedBox(height: 40),
                        largeur: LargeurModale.xl,
                      ),
                    ),
                    child: const Text('ouvrir'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await t.tap(find.byKey(const Key('ouvrir')));
    await t.pumpAndSettle();

    final voile = t.getRect(find.byType(ModalBarrier).last);
    expect(voile, const Rect.fromLTWH(0, 0, 1280, 800), reason: 'le voile couvre aussi la barre latérale');

    final fenetre = t.getRect(find.text('Synchronisation'));
    expect(fenetre.left, greaterThan(0));
    expect(fenetre.right, lessThan(1280));
  });
}
