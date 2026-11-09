/// Ticket CONF-3 (DV-22) — LIBELLÉ FRANÇAIS D'UN MODE DE RÈGLEMENT : l'unique point de passage du poste.
///
/// Même table et même repli que `App\Support\ModePaiement::libelle` du web (parité EXÉCUTÉE contre le PHP :
/// `test/mode_paiement_parite_php_test.dart`). La clé stockée (`sales.payment_mode`…) ne change jamais : seul l'affichage
/// passe par ici. Clé inconnue : la clé telle quelle (« _ » lus comme des espaces, première lettre en capitale) ; clé absente
/// ou vide : « — », jamais une chaîne vide.
class ModePaiement {
  const ModePaiement._();

  static const libelles = {
    'especes': 'Espèces',
    'mobile_money': 'Mobile Money',
    'virement': 'Virement bancaire',
    'cheque': 'Chèque',
    'credit': 'Crédit client',
    'avance': 'Avance',
  };

  static String libelle(String? cle) {
    final c = (cle ?? '').trim();
    if (c.isEmpty) return '—';
    final connu = libelles[c];
    if (connu != null) return connu;
    final lisible = c.replaceAll('_', ' ').trim();
    if (lisible.isEmpty) return c; // « _ » seul : la clé telle quelle, jamais vide
    return lisible.substring(0, 1).toUpperCase() + lisible.substring(1);
  }
}
