import 'package:flutter/foundation.dart';

/// Ticket S-T3 (méthode TATACORA, D-SYNC-1) — POINT UNIQUE DES GESTES IMPORTANTS.
///
/// Une vente enregistrée à la caisse, une fiche journalière, un soin : dès qu'un de ces gestes est écrit en base
/// locale (`pending`), son dépôt appelle [signaler]. La synchronisation automatique de la session
/// (`SynchronisationAutomatique.gestes`) l'écoute et synchronise après un court délai d'agrégation.
///
/// ⚠️ **LES DÉPÔTS NE CONNAISSENT PAS LE MOTEUR.** Ils signalent un fait (« une saisie attend »), ils ne
/// synchronisent rien : une vente reste enregistrée et la caisse reste utilisable hors ligne, que la
/// synchronisation parte, échoue ou soit suspendue. Sans écouteur (tests, écran de premier démarrage), le
/// signal ne fait rien.
class GestesImportants extends ChangeNotifier {
  /// Une saisie importante vient d'être écrite en base locale.
  void signaler() => notifyListeners();
}
