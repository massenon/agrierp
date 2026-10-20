import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Coffre du système EN MÉMOIRE (tickets CFG-2) — les tests n'ont pas de gestionnaire d'identifiants Windows.
/// [contenu] est exposé : un test vérifie ce qui y est rangé, et ce qui n'y est pas.
class CoffreMemoire extends FlutterSecureStorage {
  CoffreMemoire([Map<String, String>? contenu]) : contenu = contenu ?? {};

  final Map<String, String> contenu;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => contenu[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      contenu.remove(key);
    } else {
      contenu[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    contenu.remove(key);
  }
}

/// Coffre ILLISIBLE : la plateforme n'a pas de coffre (test de rendu sans canal natif).
class CoffreIllisible extends FlutterSecureStorage {
  const CoffreIllisible();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw Exception('aucun coffre');
}
