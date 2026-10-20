import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Ticket U5 (décision D-U5 du 19/10/2026) — LE POSTE PARLE FRANÇAIS, JUSQUE
/// DANS LES COMPOSANTS DE FLUTTER.
///
/// Sans délégués de localisation, Flutter n'embarque que l'anglais : le
/// sélecteur de date affichait « Select date », « CANCEL », « OK » et des mois
/// anglais, les infobulles « Back », « Close »… — sur un écran par ailleurs
/// entièrement en français. Pire, un `showDatePicker(locale: Locale('fr'))`
/// (Rapports & Exports) n'avait aucune traduction française à charger.
///
/// Un seul point de vérité, lu par le `MaterialApp` de `main.dart` (et par les
/// tests qui veulent l'écran tel que l'utilisateur le voit).
///
/// ⚠️ `flutter_localizations` fait partie du SDK Flutter : rien n'est
/// téléchargé à l'installation, le poste reste installable hors ligne.
abstract final class LocalisationPoste {
  /// Langue unique du poste.
  static const Locale locale = Locale('fr');

  /// Seule langue proposée : aucun repli anglais possible.
  static const List<Locale> locales = [locale];

  /// Traductions Material (dates, boutons, infobulles), Widgets et Cupertino.
  static const List<LocalizationsDelegate<dynamic>> delegues = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}
