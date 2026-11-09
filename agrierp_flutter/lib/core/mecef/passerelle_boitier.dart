/// MECEF-2 — LE CONTRAT DU BOÎTIER FISCAL Eltrade CC300 vu du poste : une interface, des résultats typés, jamais un code HTTP brut.
///
/// Le boîtier est piloté par un petit serveur HTTP LOCAL (le « pilote », `http://localhost:38917`) SANS AUTHENTIFICATION : le
/// poste ne s'y adresse que par `localhost` ([adresseBoitier]) et ne l'expose jamais. Faits relus dans le pilote
/// (`eltrade-cc300-driver`, `Readme.md`, `server/handlers.go`), JAMAIS essayés avec un vrai appareil (NON VÉRIFIÉ) :
///  - `GET /check` : 200 `{"status":"Ready"}` ou 503 `{"status":"DeviceNotConnected"}` ;
///  - `GET /info` : NIM, IFU, compteurs… (« cette requête prend 4 s ») ;
///  - `POST /bill` : 200 `{"qr_code":"F;NIM;CODE;IFU;AAAAMMJJHHMMSS"}` ; **200 MÊME EN ÉCHEC, avec un `qr_code` VIDE** (le pilote
///    n'examine pas l'erreur de l'appareil) ; 400 `{"errors": …}` si la charge viole le schéma ; 503 appareil absent.
/// ⇒ SEUL un `qr_code` non vide prouve le succès. Jamais le code HTTP.
library;

/// L'adresse du pilote. Jamais exposée, jamais réglable vers une autre machine.
const adresseBoitier = 'http://localhost:38917';

/// Hôtes autorisés pour joindre le pilote (le pilote n'a aucune authentification : seul « cette machine » est admis).
const hotesBoitierAutorises = {'localhost', '127.0.0.1', '::1', '[::1]'};

/// Délais EXPLICITES (le pilote annonce 4 s pour `/info`).
class DelaisBoitier {
  const DelaisBoitier({
    this.connexion = const Duration(seconds: 2),
    this.verification = const Duration(seconds: 3),
    this.informations = const Duration(seconds: 8),
    this.facture = const Duration(seconds: 30),
  });

  final Duration connexion;
  final Duration verification;
  final Duration informations;
  final Duration facture;
}

/// Réponse de `GET /check`.
class EtatBoitier {
  const EtatBoitier({required this.pret, required this.message});

  /// Le boîtier est branché et prêt (`{"status":"Ready"}`).
  final bool pret;

  /// Phrase française à montrer (jamais le texte brut du pilote).
  final String message;

  static const injoignable = EtatBoitier(pret: false, message: 'Boîtier injoignable');
}

/// Réponse de `GET /info` : ce que le pilote dit de l'appareil et du contribuable (clés du `Readme.md` du pilote).
class InfoBoitier {
  const InfoBoitier({required this.nim, required this.ifu, required this.compteur, required this.compteurVentes, required this.brut});

  final String nim;
  final String ifu;

  /// `COUNTER` : compteur des documents de l'appareil.
  final String compteur;

  /// `SellBillCounter` : compteur des factures de vente.
  final String compteurVentes;

  /// La réponse complète (pour le journal d'essai).
  final Map<String, Object?> brut;
}

/// Issue d'une demande de facture. SEUL [FactureCertifiee] prouve que la facture existe.
sealed class ResultatFacturation {
  const ResultatFacturation();
}

/// `qr_code` non vide : la facture est certifiée par le boîtier.
class FactureCertifiee extends ResultatFacturation {
  const FactureCertifiee(this.qrCode);

  final String qrCode;
}

/// Le boîtier REFUSE (400 : charge hors schéma, ou 200 avec `qr_code` vide : l'appareil a échoué). Rien n'a été certifié ; une
/// nouvelle tentative est permise (depuis l'écran, jamais en boucle).
class FactureRefusee extends ResultatFacturation {
  const FactureRefusee(this.motif);

  final String motif;
}

/// Le boîtier n'a PAS été joint (503, connexion refusée, délai de connexion) : rien n'est parti, la facture reste « en attente »
/// et sera reprise quand le boîtier reviendra. Ce n'est PAS une erreur.
class BoitierInjoignable extends ResultatFacturation {
  const BoitierInjoignable([this.motif = 'Boîtier injoignable']);

  final String motif;
}

/// Résultat INCERTAIN : la demande est partie mais la réponse n'est pas revenue (délai dépassé après l'envoi). Le boîtier a PEUT-ÊTRE
/// certifié la facture : on ne renvoie JAMAIS automatiquement (risque de deux factures pour une vente).
class FactureIncertaine extends ResultatFacturation {
  const FactureIncertaine(this.motif);

  final String motif;
}

/// L'interface du poste vers le boîtier. Remplaçable en test par un faux pilote ou une simulation.
abstract class PasserelleBoitier {
  /// `GET /check` — ne lève jamais : un boîtier absent est un état, pas une erreur.
  Future<EtatBoitier> verifier();

  /// `GET /info` — `null` si le boîtier n'est pas joignable ou répond n'importe quoi.
  Future<InfoBoitier?> informations();

  /// `POST /bill` — [charge] est la charge du schéma `bill.spec.json` (`FactureMecef.versBoitier`). Ne lève jamais.
  Future<ResultatFacturation> facturer(Map<String, Object?> charge);
}

/// Les éléments d'un `qr_code` du pilote, d'après son SEUL exemple (`F;ED04000623;NW34NID6ZHANFNMZ2IU7LL3H;3201910768821;20200503135002`) :
/// type, NIM, code MeCeF/DGI, IFU, instant `AAAAMMJJHHMMSS`. ⚠️ NON VÉRIFIÉ avec un vrai appareil : une forme différente ne lève
/// rien (les champs restent `null`), le `qr_code` brut est de toute façon gardé.
class QrBoitier {
  const QrBoitier({this.nim, this.code, this.ifu, this.instant});

  final String? nim;
  final String? code;
  final String? ifu;
  final DateTime? instant;

  static QrBoitier lire(String qr) {
    final p = qr.split(';');
    if (p.length < 5) return const QrBoitier();
    DateTime? instant;
    final d = p[4].trim();
    if (RegExp(r'^\d{14}$').hasMatch(d)) {
      instant = DateTime(
        int.parse(d.substring(0, 4)),
        int.parse(d.substring(4, 6)),
        int.parse(d.substring(6, 8)),
        int.parse(d.substring(8, 10)),
        int.parse(d.substring(10, 12)),
        int.parse(d.substring(12, 14)),
      );
    }
    String? champ(String s) => s.trim().isEmpty ? null : s.trim();
    return QrBoitier(nim: champ(p[1]), code: champ(p[2]), ifu: champ(p[3]), instant: instant);
  }
}
