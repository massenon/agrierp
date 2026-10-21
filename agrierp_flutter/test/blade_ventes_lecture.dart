import 'dart:io';

import 'chemins_depot.dart';

/// Tickets AV1 / AV2 — LECTURE DU BLADE ET DU COMPOSANT LIVEWIRE pour les garde-fous « Retours et Avoirs » et
/// « Historique des Ventes » : les attendus sont LUS dans le web (le maître, doctrine art. 5), jamais recopiés.

String _chemin(String relatif) => '$dossierLaravel/$relatif';

File blade(String nom) => File(_chemin('resources/views/livewire/ventes/$nom.blade.php'));

File livewire(String nom) => File(_chemin('app/Livewire/Ventes/$nom.php'));

File serviceAvoir() => File(_chemin('app/Services/AvoirClientService.php'));

File validationFr() => File(_chemin('lang/fr/validation.php'));

/// Sans le dépôt Laravel, ces contrôles se sautent AVEC leur raison : ils n'ont rien à quoi comparer.
String? sautSansWebVentes() {
  for (final f in [
    blade('retours-avoirs'),
    blade('historique-ventes'),
    livewire('RetoursAvoirs'),
    livewire('HistoriqueVentes'),
    serviceAvoir(),
    validationFr(),
  ]) {
    if (!f.existsSync()) return 'SAUT : ${f.path} absent — rien à comparer';
  }
  return null;
}

/// Texte brut d'un Blade : sans commentaires Blade `{{-- --}}`.
String sansCommentaires(String blade) => blade.replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');

/// Les en-têtes `<th …>Libellé</th>` d'un Blade, dans l'ordre.
List<String> entetes(String blade) => [
  for (final m in RegExp(r'<th[^>]*>([^<]+)</th>').allMatches(blade)) m.group(1)!.trim(),
];

/// Nombre de cartes KPI : un `border-l-4 border-l-<couleur>` par carte (ni un simple `border-l-4`).
int cartes(String blade) => RegExp(r'border-l-4 border-l-[a-z-]+').allMatches(blade).length;

/// Libellés et icônes des cartes : `<span …uppercase">Libellé</span><span …material-symbols-outlined…>icone</span>`.
List<(String, String)> libellesDeCartes(String blade) => [
  for (final m in RegExp(
    r'text-\[10px\] text-outline font-bold uppercase">([^<]+)</span><span class="material-symbols-outlined[^"]*">([^<]+)</span>',
  ).allMatches(blade))
    (m.group(1)!.trim(), m.group(2)!.trim()),
];

/// Les chaînes littérales d'un fichier Dart (`'…'` et `"…"`) : un commentaire ne satisfait jamais le garde-fou.
Set<String> litteraux(Iterable<String> chemins) {
  final sortie = <String>{};
  for (final chemin in chemins) {
    final source = File(chemin).readAsStringSync();
    for (final m in RegExp(r"'((?:[^'\\\n]|\\.)*)'|" r'"((?:[^"\\\n]|\\.)*)"').allMatches(source)) {
      sortie.add((m.group(1) ?? m.group(2)!).replaceAll(r"\'", "'").replaceAll(r'\$', r'$'));
    }
  }
  return sortie;
}

/// Source Dart sans les lignes de commentaire.
String codeSeul(String chemin) => File(chemin)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// `:attribute` d'un attribut de `lang/fr/validation.php` (`'saleId' => 'vente'`).
String attribut(String validation, String cle) {
  final m = RegExp("'$cle' => '((?:[^'\\\\]|\\\\.)*)'").firstMatch(validation);
  if (m == null) throw StateError('attribut $cle absent de validation.php');
  return m.group(1)!.replaceAll(r"\'", "'");
}

/// Un message de `validation.php`, `:attribute` / `:min` / `:max` remplacés.
String messageValidation(String validation, String regle, {String? type, required String attr, Map<String, String> params = const {}}) {
  final motif = type == null
      ? RegExp("'$regle' => '((?:[^'\\\\]|\\\\.)*)'")
      : RegExp("'$regle' => \\[[^\\]]*?'$type' => '((?:[^'\\\\]|\\\\.)*)'", dotAll: true);
  final m = motif.firstMatch(validation);
  if (m == null) throw StateError('règle $regle ($type) absente de validation.php');
  var texte = m.group(1)!.replaceAll(r"\'", "'").replaceAll(':attribute', attr);
  params.forEach((k, v) => texte = texte.replaceAll(':$k', v));
  return texte;
}
