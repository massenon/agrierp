/// Suffixe d'une clé de ligne quand deux bandes portent le même code (`-2`, `-3`…) ; vide pour la première.
///
/// 🔴→✅ « Duplicate keys found » : deux bandes de même code (ex. `AVI-2026-01`) donnaient deux lignes de clé
/// identique, ce qui arrête le dessin de l'écran entier sans aucune erreur de compilation. La première garde sa clé
/// d'origine (les tests la retrouvent), les suivantes reçoivent un rang.
///
/// Ticket UNI : les doublons ne se créent plus, mais ceux déjà présents le restent jusqu'à ce que le client les renomme ;
/// tout écran qui clé une ligne sur le code d'une bande passe par ici.
String suffixeDoublon(Iterable<String> codes, int index) {
  final liste = codes.toList();
  final rang = liste.sublist(0, index + 1).where((c) => c == liste[index]).length;
  return rang <= 1 ? '' : '-$rang';
}
