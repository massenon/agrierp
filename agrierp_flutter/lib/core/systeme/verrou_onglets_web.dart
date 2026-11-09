import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Navigateur : verrou exclusif `navigator.locks` (nom `agrierp-synchro`). Navigateur sans `navigator.locks` : l'action
/// s'exécute sans verrou (la garde « une tentative à la fois » du moteur reste valable DANS l'onglet).
Future<T> verrouEntreOngletsPlateforme<T>(Future<T> Function() action) {
  final fin = Completer<T>();
  try {
    final rappel = ((JSAny? _) => (() async {
      try {
        fin.complete(await action());
      } on Object catch (e, pile) {
        fin.completeError(e, pile);
      }
    })().toJS).toJS;
    web.window.navigator.locks.request('agrierp-synchro', rappel);
  } on Object {
    if (!fin.isCompleted) return action();
  }
  return fin.future;
}
