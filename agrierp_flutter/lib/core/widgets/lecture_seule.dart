import 'package:flutter/material.dart';

import '../comptabilite/exercice_choisi.dart';

/// Ticket EX7 (EF10) — `@lectureSeule` du web au poste : un bouton de saisie (Nouveau, Modifier, Archiver,
/// Enregistrer) est grisé quand l'exercice affiché est clos, avec le motif « Exercice 2026 clôturé — lecture seule » en
/// info-bulle. Consultation, exports et impression restent ouverts.
///
/// ⚠️ Confort seulement : `ExerciceDeSaisie` (au poste) et le serveur (à l'envoi) jugent chaque saisie sur SA DATE.
abstract final class LectureSeule {
  /// Le motif, ou `null` (exercice ouvert, ou écran hors du socle : rien n'est grisé).
  static String? motif(BuildContext context) =>
      PorteeExerciceChoisi.lire(context)?.motifLectureSeule;

  /// [enfant] sous l'info-bulle du [motif] ; tel quel sans motif.
  static Widget infobulle(String? motif, Widget enfant) =>
      motif == null ? enfant : Tooltip(message: motif, child: enfant);
}
