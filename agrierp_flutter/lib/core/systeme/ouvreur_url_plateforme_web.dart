import 'package:web/web.dart' as web;

/// Navigateur : nouvel onglet, sans accès à la page d'origine.
Future<void> ouvrirUrlPlateforme(String url) async {
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
