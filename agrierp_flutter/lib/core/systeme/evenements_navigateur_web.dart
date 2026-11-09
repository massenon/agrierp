import 'dart:async';

import 'package:web/web.dart' as web;
import 'dart:js_interop';

import 'evenements_navigateur.dart';

/// Navigateur : `online` (fenêtre) et `visibilitychange` (document, seulement vers « visible »).
Stream<EvenementNavigateur> evenementsNavigateurPlateforme() {
  late final StreamController<EvenementNavigateur> flux;
  late final JSFunction enLigne;
  late final JSFunction visibilite;
  flux = StreamController<EvenementNavigateur>.broadcast(
    onListen: () {
      enLigne = ((web.Event _) => flux.add(EvenementNavigateur.retourEnLigne)).toJS;
      visibilite = ((web.Event _) {
        if (web.document.visibilityState == 'visible') flux.add(EvenementNavigateur.ongletVisible);
      }).toJS;
      web.window.addEventListener('online', enLigne);
      web.document.addEventListener('visibilitychange', visibilite);
    },
    onCancel: () {
      web.window.removeEventListener('online', enLigne);
      web.document.removeEventListener('visibilitychange', visibilite);
    },
  );
  return flux.stream;
}
