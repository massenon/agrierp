import 'plateforme_poste.dart';
import 'justificatifs_navigateur.dart';
import 'ouvreur_url_plateforme_native.dart' if (dart.library.js_interop) 'ouvreur_url_plateforme_web.dart';

/// Ouvre un lien dans l'application du système (navigateur, WhatsApp Web…). Injectable : un test n'ouvre rien.
typedef OuvreurUrl = Future<void> Function(String url);

/// Ouvre [url] avec le gestionnaire du système, sans passer par un interpréteur de commandes (pas de guillemets à
/// échapper : l'adresse `wa.me` porte un `&`, un `?` et le message encodé).
///
/// ⚠️ Windows : `rundll32 url.dll,FileProtocolHandler`, qui rend la main aussitôt. Une panne (aucun navigateur) est
/// avalée : la relance est DÉJÀ écrite, et l'écran l'annonce sans bloquer l'opérateur.
/// PWA-2 : dans le navigateur, le lien s'ouvre dans un nouvel onglet (`window.open`, sans `opener`).
Future<void> ouvrirUrlSysteme(String url) async {
  try {
    // PWA-2b — un justificatif rangé dans le navigateur (`navigateur:<clé>/<nom>`) se rouvre en se TÉLÉCHARGEANT.
    final justificatif = JustificatifsNavigateur.decoder(url);
    if (justificatif != null) {
      final octets = await JustificatifsNavigateur.magasin.lire(justificatif.cle);
      if (octets != null) await PlateformePoste.livreurNavigateur(justificatif.nom, octets);
      return;
    }
    await ouvrirUrlPlateforme(url);
  } on Object {
    // Voir la docstring.
  }
}
