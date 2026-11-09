import 'dart:io';

/// Windows (référence), puis macOS et Linux : le gestionnaire du système, INCHANGÉ depuis l'origine du poste.
Future<void> ouvrirUrlPlateforme(String url) async {
  if (Platform.isWindows) {
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
  } else if (Platform.isMacOS) {
    await Process.start('open', [url], mode: ProcessStartMode.detached);
  } else {
    await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
  }
}
