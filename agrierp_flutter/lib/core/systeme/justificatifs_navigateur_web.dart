import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'justificatifs_navigateur.dart';

/// Navigateur : IndexedDB `agrierp_justificatifs`, magasin d'objets `octets` (clé = identifiant du justificatif). Aucune
/// donnée n'est mise dans le cache du service worker. Si IndexedDB est inaccessible, repli en mémoire (session seule).
MagasinJustificatifs creerMagasinJustificatifsPlateforme() => _MagasinIndexedDb();

class _MagasinIndexedDb implements MagasinJustificatifs {
  static const _base = 'agrierp_justificatifs';
  static const _magasin = 'octets';
  final MagasinJustificatifsMemoire _repli = MagasinJustificatifsMemoire();
  Future<web.IDBDatabase>? _ouverte;

  Future<T> _attendre<T extends JSAny?>(web.IDBRequest requete) {
    final fin = Completer<T>();
    requete.onsuccess = ((web.Event _) => fin.complete(requete.result as T)).toJS;
    requete.onerror = ((web.Event _) => fin.completeError(StateError('IndexedDB : ${requete.error?.message}'))).toJS;
    return fin.future;
  }

  Future<web.IDBDatabase> _ouvrir() => _ouverte ??= () {
    final demande = web.window.indexedDB.open(_base, 1);
    demande.onupgradeneeded = ((web.Event _) {
      (demande.result as web.IDBDatabase).createObjectStore(_magasin);
    }).toJS;
    return _attendre<web.IDBDatabase>(demande);
  }();

  Future<T> _avecBase<T>(Future<T> Function(web.IDBDatabase base) geste, Future<T> Function() repli) async {
    try {
      return await geste(await _ouvrir());
    } on Object {
      _ouverte = null;
      return repli();
    }
  }

  web.IDBObjectStore _objets(web.IDBDatabase base, String mode) => base.transaction(_magasin.toJS, mode).objectStore(_magasin);

  @override
  Future<void> ecrire(String cle, Uint8List octets) => _avecBase<void>((base) async {
    await _attendre<JSAny?>(_objets(base, 'readwrite').put(octets.toJS, cle.toJS));
  }, () => _repli.ecrire(cle, octets));

  @override
  Future<Uint8List?> lire(String cle) => _avecBase<Uint8List?>((base) async {
    final valeur = await _attendre<JSAny?>(_objets(base, 'readonly').get(cle.toJS));
    if (valeur == null) return _repli.lire(cle);
    return (valeur as JSUint8Array).toDart;
  }, () => _repli.lire(cle));

  @override
  Future<void> supprimer(String cle) => _avecBase<void>((base) async {
    await _attendre<JSAny?>(_objets(base, 'readwrite').delete(cle.toJS));
  }, () => _repli.supprimer(cle));
}
