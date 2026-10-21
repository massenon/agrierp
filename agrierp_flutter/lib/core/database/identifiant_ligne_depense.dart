import 'package:uuid/uuid.dart';

/// Ticket DEP4 — espace de noms de l'identifiant d'une ligne de dépense CONVERTIE depuis une ancienne dépense
/// (`ExpenseLine::ESPACE_CONVERSION` au serveur, mot pour mot).
const espaceConversionLigneDepense = 'c5a0e7a2-6f55-4a52-9e0e-3f1f2f6d0a11';

/// Identifiant de la ligne unique d'une dépense convertie : UUID v5 de l'identifiant de la dépense
/// (`ExpenseLine::idDeConversion` au serveur). La conversion du serveur (migration, poste ancien) et celle du poste
/// (palier Drift v56) donnent la MÊME valeur : la ligne convertie ici et celle convertie là-bas sont la même, jamais
/// deux. Vérifié contre PHP (`depenses_multilignes_test.dart`).
String idLigneConvertie(String idDepense) =>
    const Uuid().v5(espaceConversionLigneDepense, idDepense);
