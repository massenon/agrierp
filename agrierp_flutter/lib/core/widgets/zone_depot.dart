import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

/// Ticket CONF-2 — GLISSER-DÉPOSER D'UN FICHIER sur le poste (paquet `desktop_drop` 0.8.4, Windows compris).
///
/// Le web a son glisser-déposer depuis CONF-1 ; le poste l'a maintenant : même geste, MÊME jugement que le clic (le
/// parent reçoit un `(nom, octets)` et le fait passer par la validation qu'il applique déjà au sélecteur de fichier).
///
/// ⚠️ Le plugin natif est ABSENT en test : la source de dépôt est INJECTABLE (`SourceDepot.courante`), comme le sélecteur
/// de fichier ou `FenetrePoste`. Un test pose une source simulée et déclenche survol / dépôt sans aucun plugin.
///
/// Un seul fichier : si plusieurs sont déposés, le PREMIER est retenu (le champ du web n'est pas `multiple`).
/// Un dossier, ou un fichier illisible, est ignoré (le survol s'éteint, rien n'est choisi).
typedef FichierDepose = ({String nom, Uint8List octets});

abstract class SourceDepot {
  /// Source du poste ; les tests la remplacent.
  static SourceDepot courante = const SourceDepotNative();

  /// Lit les octets d'un chemin déposé (surchargé par les tests : les E/S réelles n'avancent pas dans le temps simulé).
  Future<Uint8List?> lire(String chemin);

  /// Enveloppe `enfant` : `surSurvol(true/false)` à l'entrée / la sortie du glisser, `surChemins(chemins)` au dépôt.
  Widget envelopper({
    required Widget enfant,
    required ValueChanged<bool> surSurvol,
    required Future<void> Function(List<String> chemins) surChemins,
    required bool actif,
  });
}

/// La vraie source : `DropTarget` de `desktop_drop`.
class SourceDepotNative implements SourceDepot {
  const SourceDepotNative();

  @override
  Future<Uint8List?> lire(String chemin) async => File(chemin).readAsBytes();

  @override
  Widget envelopper({
    required Widget enfant,
    required ValueChanged<bool> surSurvol,
    required Future<void> Function(List<String> chemins) surChemins,
    required bool actif,
  }) => DropTarget(
    enable: actif,
    onDragEntered: (_) => surSurvol(true),
    onDragExited: (_) => surSurvol(false),
    onDragDone: (d) {
      surSurvol(false);
      surChemins([for (final f in d.files) f.path]);
    },
    child: enfant,
  );
}

/// Zone de dépôt : le survol est exposé au constructeur d'enfant (bordure et fond de survol, comme `survol` du Blade).
class ZoneDepot extends StatefulWidget {
  const ZoneDepot({
    super.key,
    required this.surFichier,
    required this.enfant,
    this.actif = true,
  });

  /// Appelé avec le fichier déposé (un seul).
  final Future<void> Function(FichierDepose fichier) surFichier;
  final Widget Function(BuildContext context, bool survol) enfant;
  final bool actif;

  @override
  State<ZoneDepot> createState() => _ZoneDepotState();
}

class _ZoneDepotState extends State<ZoneDepot> {
  bool _survol = false;

  Future<Uint8List?> _lire(String chemin) async {
    try {
      return await SourceDepot.courante.lire(chemin);
    } catch (_) {
      return null; // dossier, fichier disparu ou illisible : rien n'est choisi
    }
  }

  Future<void> _surChemins(List<String> chemins) async {
    if (chemins.isEmpty || !widget.actif) return;
    final chemin = chemins.first;
    final octets = await _lire(chemin);
    if (octets == null || !mounted) return;
    await widget.surFichier((nom: p.basename(chemin), octets: octets));
  }

  @override
  Widget build(BuildContext context) => SourceDepot.courante.envelopper(
    actif: widget.actif,
    surSurvol: (v) {
      if (mounted && v != _survol) setState(() => _survol = v);
    },
    surChemins: _surChemins,
    enfant: widget.enfant(context, _survol),
  );
}
