import 'passerelle_boitier.dart';
import 'passerelle_boitier_native.dart' if (dart.library.js_interop) 'passerelle_boitier_web.dart';

/// MECEF-2 — la passerelle du poste. Natif : le client HTTP vers `http://localhost:38917`. Navigateur : AUCUN boîtier (une page
/// web n'a pas de pilote local à joindre ; non étudié, voir `docs/logialvia/41_MECEF_EMECEF.md` § 3.3).
PasserelleBoitier creerPasserelleBoitier({Uri? adresse}) => creerPasserelleBoitierPlateforme(adresse: adresse);
