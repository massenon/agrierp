import 'dart:io';

/// Ouvre un lien dans l'application du système (navigateur, WhatsApp Web…). Injectable : un test n'ouvre rien.
typedef OuvreurUrl = Future<void> Function(String url);

/// Ouvre [url] avec le gestionnaire du système, sans passer par un interpréteur de commandes (pas de guillemets à
/// échapper : l'adresse `wa.me` porte un `&`, un `?` et le message encodé).
///
/// ⚠️ Windows : `rundll32 url.dll,FileProtocolHandler`, qui rend la main aussitôt. Une panne (aucun navigateur) est
/// avalée : la relance est DÉJÀ écrite, et l'écran l'annonce sans bloquer l'opérateur.
Future<void> ouvrirUrlSysteme(String url) async {
  try {
    if (Platform.isWindows) {
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url], mode: ProcessStartMode.detached);
    } else {
      await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
    }
  } on Object {
    // Voir la docstring.
  }
}
