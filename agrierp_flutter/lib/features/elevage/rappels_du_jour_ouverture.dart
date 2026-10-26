import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/temps/heure_benin.dart';
import 'rappels_du_jour_repository.dart';

/// Ticket POP3 — la préférence « Ne plus afficher aujourd'hui », PROPRE AU POSTE ET À L'UTILISATEUR.
///
/// Rangée au coffre du système sous `agrierp.rappels.masque.<id utilisateur>` (comme le réglage d'inactivité) : aucune
/// table, aucune synchronisation, aucune migration Drift. La valeur est le JOUR masqué (`AAAA-MM-JJ`, heure du Bénin) ;
/// le lendemain elle ne vaut plus rien et la fenêtre revient.
class ReglageRappels {
  ReglageRappels({FlutterSecureStorage? coffre}) : _coffre = coffre ?? const FlutterSecureStorage();

  final FlutterSecureStorage _coffre;

  static String _cle(String id) => 'agrierp.rappels.masque.$id';

  /// Jour masqué par cet utilisateur ; `null` si aucun, ou si le coffre est inaccessible (mieux vaut une fenêtre de
  /// trop qu'un rappel sanitaire manqué).
  Future<String?> masqueLe(String idUtilisateur) async {
    try {
      return await _coffre.read(key: _cle(idUtilisateur));
    } on Object {
      return null;
    }
  }

  Future<void> masquer(String idUtilisateur, String jour) async {
    try {
      await _coffre.write(key: _cle(idUtilisateur), value: jour);
    } on Object catch (e) {
      debugPrint('Rappels du jour : préférence illisible ou non enregistrée ($e).');
    }
  }
}

/// Ticket POP3 — DÉCIDE si la fenêtre « Rappels du jour » doit s'ouvrir. Ne bloque jamais le démarrage ni la synchro :
/// toute erreur est journalisée (`debugPrint`) et rend `null` — jamais d'écran rouge.
///
/// Rend `null` (pas de fenêtre) quand : l'utilisateur est inconnu, son rôle ne voit pas Soins et vaccins, il a
/// masqué la fenêtre pour aujourd'hui, il n'y a AUCUN rappel (jamais une fenêtre vide), ou le calcul échoue.
class OuvertureRappels {
  OuvertureRappels({required this.depot, required this.reglage});

  final RappelsDuJourRepository depot;
  final ReglageRappels reglage;

  Future<RappelsDuJour?> aMontrer({required String? idUtilisateur, required String? role, DateTime? quand}) async {
    try {
      if (idUtilisateur == null || idUtilisateur.isEmpty) return null;
      final aujourdhui = HeureBenin.cleJour(HeureBenin.jour(quand ?? HeureBenin.maintenant()));
      if (await reglage.masqueLe(idUtilisateur) == aujourdhui) return null;

      final rappels = await depot.pourRole(role, quand: quand);
      return rappels.vide ? null : rappels;
    } on Object catch (e, pile) {
      debugPrint('Rappels du jour : calcul impossible ($e).\n$pile');
      return null;
    }
  }

  Future<void> masquerAujourdhui(String idUtilisateur, {DateTime? quand}) =>
      reglage.masquer(idUtilisateur, HeureBenin.cleJour(HeureBenin.jour(quand ?? HeureBenin.maintenant())));
}
