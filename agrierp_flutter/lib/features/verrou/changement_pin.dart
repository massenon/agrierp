import '../../core/auth/verrou_local.dart';

/// Ticket VL-1 — « Changer le code PIN » de Mon profil : (réussi, message). L'ancien PIN est requis et compte comme
/// un essai (temporisation et plafond de dix échecs s'appliquent ici aussi).
Future<(bool, String)> changerPinDepuisProfil(
  VerrouLocal verrou,
  String idUtilisateur, {
  required String ancien,
  required String nouveau,
  required String confirmation,
}) async {
  if (!VerrouLocal.pinValide(nouveau)) {
    return (false, 'Le nouveau code PIN comporte de 4 à 6 chiffres.');
  }
  if (nouveau != confirmation) {
    return (false, 'Les deux codes ne correspondent pas.');
  }
  final t = await verrou.changer(idUtilisateur, ancien: ancien, nouveau: nouveau);
  return switch (t.resultat) {
    ResultatVerrou.ok => (true, 'Code PIN mis à jour avec succès.'),
    ResultatVerrou.refuse => (false, 'Ancien code PIN incorrect.'),
    ResultatVerrou.temporise => (
      false,
      "Trop d'essais. Réessayez dans ${t.attente?.inSeconds ?? 30} s.",
    ),
    ResultatVerrou.reconnexionRequise => (
      false,
      "Trop d'échecs : reconnectez-vous en ligne pour redéfinir le code PIN.",
    ),
  };
}
