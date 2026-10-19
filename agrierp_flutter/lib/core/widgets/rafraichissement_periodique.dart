import 'dart:async';

import 'package:flutter/widgets.dart';

/// Ticket U14 — `wire:poll.30s` du web : reconstruit [builder] toutes les [intervalle].
///
/// La cloche du web (`notification-bell.blade.php`) se relit toutes les 30 secondes : non lues, quatre dernières et
/// « il y a … » recalculé. Le socle du poste pose ce widget autour de la barre supérieure, dont le `FutureBuilder`
/// relit alors la base locale à chaque tour.
///
/// ⚠️ LA MINUTERIE MEURT AVEC LE WIDGET (`dispose`) : une minuterie orpheline continuerait de reconstruire un arbre
/// démonté (et ferait échouer tout test qui la laisse en vie). Un changement d'[intervalle] la relance.
class RafraichissementPeriodique extends StatefulWidget {
  const RafraichissementPeriodique({
    super.key,
    required this.intervalle,
    required this.builder,
  });

  final Duration intervalle;
  final WidgetBuilder builder;

  @override
  State<RafraichissementPeriodique> createState() => _RafraichissementPeriodiqueState();
}

class _RafraichissementPeriodiqueState extends State<RafraichissementPeriodique> {
  Timer? _minuterie;

  @override
  void initState() {
    super.initState();
    _demarrer();
  }

  @override
  void didUpdateWidget(RafraichissementPeriodique ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.intervalle != widget.intervalle) _demarrer();
  }

  void _demarrer() {
    _minuterie?.cancel();
    _minuterie = Timer.periodic(widget.intervalle, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    _minuterie = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
