/// MECEF-3 — le choix « Facture simple » / « Facture normalisée » fait à la vente, côté poste.
///
/// Transposition Dart de `App\Services\Mecef\ChoixFactureService` (le serveur REVALIDE tout à l'envoi) et de `App\Support\FactureType`
/// / `App\Support\AibTaux` — mêmes libellés, mêmes motifs, même ordre. Parité EXÉCUTÉE contre le serveur par
/// `test/choix_facture_parite_php_test.dart`.
///
///  - type absent = FACTURE SIMPLE (défaut, jamais transmise à la DGI, pas de QR) ; type inconnu = refus ;
///  - facture simple : l'identité fiscale de l'acheteur n'a pas d'objet, elle n'est jamais gardée ;
///  - facture normalisée : NOM ET PRÉNOM obligatoires ; IFU facultatif — vide = client SANS IFU (un client particulier : la DGI
///    l'accepte) ; présent = 13 chiffres exactement ; taux d'AIB dans la liste (5 %, 1 %, N/A), jamais deviné quand il manque.
///
/// ⚠️ Le MONTANT de l'AIB n'est jamais calculé ici ni par le serveur : c'est la DGI qui le calcule et le renvoie.
class ChoixFacture {
  const ChoixFacture._();

  static const simple = 'simple';
  static const normalisee = 'normalisee';

  /// Libellés de la liste « Type de Facture » (`FactureType::LIBELLES`), dans l'ordre de la caisse du web.
  static const libellesTypes = {simple: 'Facture simple', normalisee: 'Facture normalisée'};

  /// Taux d'AIB (`AibTaux::LIBELLES`) : 5 % d'abord, c'est le cas général et le défaut.
  static const aibDefaut = '5%';
  static const libellesAib = {'5%': '5 %', '1%': '1 %', 'N/A': 'Aucun (N/A)'};

  static const motifType = 'Type de facture inconnu : choisissez « Facture simple » ou « Facture normalisée ».';
  static const motifNom = 'Le nom et prénom du client sont obligatoires pour une facture normalisée.';
  static const motifIfu = "L'IFU du client doit comporter 13 chiffres (laissez-le vide pour un client sans IFU).";
  static const motifAib = "Choisissez le taux d'AIB : 5 %, 1 % ou Aucun (N/A).";
  static const nomMax = 150;

  /// Mentions imprimées sur la facture (`FactureType::MENTION_*`).
  static const mentionSimple = 'Facture simple — non normalisée DGI';
  static const mentionEnAttente = 'Facture normalisée demandée — en attente';

  /// Valide le choix : le résultat est ce que la vente écrit ; sinon [ChoixFactureRefuse] (champ + motif).
  static ChoixValide valider({String? type, String? ifu, String? nom, String? aib}) {
    final t = type == null || type.trim().isEmpty ? simple : type.trim();
    if (!libellesTypes.containsKey(t)) throw const ChoixFactureRefuse('facture_type', motifType);
    if (t == simple) return const ChoixValide(type: simple);

    final n = (nom ?? '').trim();
    if (n.isEmpty || n.runes.length > nomMax) throw const ChoixFactureRefuse('client_nom_facture', motifNom);

    final i = (ifu ?? '').replaceAll(RegExp(r'\s+'), '');
    if (i.isNotEmpty && !RegExp(r'^\d{13}$').hasMatch(i)) throw const ChoixFactureRefuse('client_ifu', motifIfu);

    if (aib == null || !libellesAib.containsKey(aib)) throw const ChoixFactureRefuse('aib_taux', motifAib);

    return ChoixValide(type: t, ifu: i.isEmpty ? null : i, nom: n, aib: aib);
  }
}

/// Le choix validé : ce qui s'écrit dans `sales.facture_type`, `client_ifu`, `client_nom_facture`, `aib_taux`.
class ChoixValide {
  const ChoixValide({required this.type, this.ifu, this.nom, this.aib});

  final String type;
  final String? ifu;
  final String? nom;
  final String? aib;

  bool get normalisee => type == ChoixFacture.normalisee;
}

/// Refus motivé du choix, avec le champ fautif (`client_ifu`, `client_nom_facture`, `aib_taux`, `facture_type`).
class ChoixFactureRefuse implements Exception {
  const ChoixFactureRefuse(this.champ, this.message);

  final String champ;
  final String message;

  @override
  String toString() => message;
}
