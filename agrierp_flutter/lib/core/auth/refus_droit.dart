import 'package:flutter/material.dart';

import '../widgets/toast_agri.dart';

/// Ticket CONF-4 (DV-20) — REFUS D'UNE ACTION D'ÉCRITURE SANS LE DROIT DU WEB, avec son motif.
///
/// Un compte qui LIT un module sans l'écrire (le comptable : ventes, achats, stocks) ouvre les écrans du poste ; chaque geste
/// d'écriture est refusé ICI, avant d'ouvrir une modale ou d'écrire dans la base locale, plutôt que d'être saisi puis refusé
/// à la synchronisation (stock ou trésorerie du poste déjà bougés, saisie rejetée). Même texte que « Retours et Avoirs » et
/// « Historique des Ventes » ; au web le même geste est un 403 (`authorize()`).
///
/// ⚠️ Confort : le serveur re-juge chaque envoi (`SyncController::PERMISSION_PAR_TABLE`, motif français par table).
abstract final class RefusDroit {
  static const message = 'Votre rôle ne permet pas cette action.';

  /// `true` si [autorise] ; sinon affiche [message] (toast d'erreur) et rend `false` : `if (!RefusDroit.verifier(...)) return;`.
  static bool verifier(BuildContext context, bool autorise) {
    if (autorise) return true;
    ToastAgri.afficher(context, message, type: TypeToast.erreur);
    return false;
  }
}
