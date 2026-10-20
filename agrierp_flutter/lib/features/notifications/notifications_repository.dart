import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/database/app_database.dart';
import '../../core/temps/duree_relative.dart';
import '../../core/temps/heure_benin.dart';
import '../stocks/pmp_service.dart';

/// Échec d'une action sur une notification, porteur d'une phrase lisible.
class EchecNotification implements Exception {
  const EchecNotification(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Actions sur les notifications, contre `POST /api/notifications/{id}/read`
/// et `DELETE /api/notifications/{id}` (ticket Laravel 15.10).
///
/// ⚠️⚠️ **CES DEUX GESTES EXIGENT LE RÉSEAU, ET ILS NE SONT PAS MIS EN FILE.**
/// Ni « lue » ni « supprimée » ne passe par la file de synchronisation : le
/// contrat de `/sync/push` ne les connaît pas. Hors ligne, l'action est donc
/// REFUSÉE avec une phrase — jamais appliquée localement en silence, ce qui
/// ferait réapparaître la notification « non lue » au tirage suivant et ne
/// laisserait aucune trace de ce que l'utilisateur croyait avoir fait. À
/// reprendre si le client juge ces gestes assez fréquents hors ligne pour
/// justifier une file dédiée.
class ServeurNotifications {
  ServeurNotifications(this._client);

  final Dio _client;

  Future<void> marquerLue(String id) =>
      _appeler(() => _client.post<dynamic>('/api/notifications/$id/read'));

  Future<void> supprimer(String id) =>
      _appeler(() => _client.delete<dynamic>('/api/notifications/$id'));

  Future<void> _appeler(Future<Object?> Function() requete) async {
    try {
      await requete();
    } on DioException catch (e) {
      throw EchecNotification(_message(e));
    }
  }

  static String _message(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Serveur injoignable. Cette action nécessite le réseau : '
          'réessayez une fois connecté.';
    }
    return switch (e.response?.statusCode) {
      401 => 'Session expirée : reconnectez-vous.',
      // 404 : supprimée ailleurs entre-temps, ou jamais adressée à ce compte.
      404 =>
        "Cette notification n'existe plus sur le serveur. "
            'Synchronisez pour actualiser la liste.',
      _ => 'Action impossible.',
    };
  }
}

/// Une notification, prête à afficher.
class LigneNotification {
  const LigneNotification({
    required this.id,
    required this.titre,
    required this.message,
    required this.categorie,
    required this.gravite,
    required this.lue,
    required this.date,
    required this.lien,
  });

  final String id;

  /// Ticket U14 — `title` : ce que la CLOCHE du web affiche (`$notif->title`) ; le Centre de notifications affiche
  /// le message, comme sa vue web.
  final String titre;
  final String message;

  /// Catégorie calculée par le serveur : Élevage, Stocks, Finance, Système…
  final String categorie;

  /// Clé du serveur : `critique`, `moyen` ou `info`.
  final String gravite;
  final bool lue;
  final DateTime? date;

  /// Adresse web que le serveur associe à « Résoudre ». `null` si aucune.
  final String? lien;

  /// Écran du poste que « Résoudre » ouvre, `null` si le poste n'a pas la page.
  ///
  /// ⚠️ **DÉDUIT DE L'ADRESSE, PAS D'UNE TABLE RECOPIÉE** : les chemins web
  /// portent le nom de la page du prototype sans son `.html`
  /// (`/gestion-stocks` ↔ `gestion-stocks.html`), et c'est ce nom que
  /// `EcranPoste.page` détient déjà. Une adresse sans écran au poste
  /// (`/gestion-bandes`) ne donne PAS de bouton : mieux vaut aucune flèche
  /// qu'une flèche qui ne mène nulle part.
  EcranPoste? get ecranDuLien {
    final adresse = lien;
    if (adresse == null || adresse.isEmpty) return null;

    final chemin = Uri.tryParse(adresse)?.path.replaceAll('/', '');
    if (chemin == null || chemin.isEmpty) return null;

    for (final e in EcranPoste.values) {
      if (e.page == '$chemin.html') return e;
    }
    return null;
  }

  /// « 28/07/2026 - 06:12 » (`$notif->created_at->format('d/m/Y - H:i')` du web) ; « — » sans date.
  ///
  /// 🔴→✅ Ticket U12b (reste de S-T11) — `created_at` est un INSTANT : il s'affiche à l'heure du Bénin, celle du
  /// serveur (`Africa/Porto-Novo`), et non à celle de Windows. La cloche et le Centre de notifications lisent ce texte.
  String get dateTexte {
    final instant = date;
    if (instant == null) return '—';
    final d = HeureBenin.depuisInstant(instant);
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)}/${d.year} - '
        '${deux(d.hour)}:${deux(d.minute)}';
  }

  /// Ticket U13 — « il y a 5 minutes » : le rendu de la CLOCHE du web (`$notif->created_at->diffForHumans()`, Carbon
  /// en français, à l'heure du Bénin), vu depuis [maintenant] (un instant) ; « — » sans date. Le Centre de
  /// notifications garde, comme au web, la date « jj/mm/AAAA - HH:mm » ([dateTexte]).
  String dateRelative(DateTime maintenant) {
    final instant = date;
    if (instant == null) return '—';
    return DureeRelative.depuis(instant, maintenant: maintenant);
  }

  String get graviteLibelle => switch (gravite) {
    'critique' => 'Critique',
    'moyen' => 'Moyen',
    _ => 'Info',
  };
}

class DonneesNotifications {
  const DonneesNotifications({required this.lignes, required this.maintenant});

  /// Les plus récentes d'abord.
  final List<LigneNotification> lignes;

  /// Instant de référence des 30 jours, fixé au chargement : l'écran et ses
  /// tests lisent la même fenêtre.
  final DateTime maintenant;

  int get nonLues => lignes.where((l) => !l.lue).length;

  /// ⚠️ NON LUES SEULEMENT, comme `Notifications\Index::getKpisProperty` : une
  /// alerte critique déjà lue ne réclame plus rien.
  int get critiques =>
      lignes.where((l) => l.gravite == 'critique' && !l.lue).length;

  /// Total sur 30 jours, lues comprises. ⚠️ Une ligne SANS date n'est pas
  /// comptée : on ne sait pas où la ranger, et la compter reviendrait à
  /// affirmer qu'elle est récente.
  int get total30Jours {
    final limite = maintenant.subtract(const Duration(days: 30));
    return lignes
        .where((l) => l.date != null && !l.date!.isBefore(limite))
        .length;
  }
}

/// Lectures et actions de `prototype_html/notifications.html`.
///
/// ⚠️ **CE QUE LE POSTE VOIT EST CE QUE LE DERNIER TIRAGE A APPORTÉ** : les 200
/// dernières notifications visibles par l'utilisateur connecté. Une alerte
/// levée depuis le dernier tirage n'y figure pas ; l'écran dit la date de ce
/// tirage plutôt que de laisser croire à un direct.
class NotificationsRepository {
  NotificationsRepository({required this.database, this.serveur});

  final AppDatabase database;

  /// `null` : aucune connexion possible (tests, poste sans session) — les
  /// actions répondent alors par une phrase, sans rien modifier.
  final ServeurNotifications? serveur;

  Future<DonneesNotifications> charger({DateTime? maintenant}) async {
    final brutes =
        await (database.select(database.notifications)..orderBy([
              (n) => OrderingTerm(
                expression: n.createdAt,
                mode: OrderingMode.desc,
                nulls: NullsOrder.last,
              ),
            ]))
            .get();

    return DonneesNotifications(
      maintenant: maintenant ?? HeureBenin.horloge(),
      lignes: [
        for (final n in brutes)
          LigneNotification(
            id: n.id,
            titre: n.title,
            message: n.message,
            categorie: n.category,
            gravite: n.severity,
            lue: n.isRead,
            date: n.createdAt,
            lien: n.linkUrl,
          ),
      ],
    );
  }

  /// Filtres de l'écran, comme `Notifications\Index::getNotificationsProperty()` du web.
  ///
  /// 🔴→✅ Ticket U14 — LA RECHERCHE DU WEB : `message LIKE '%…%' OR title LIKE '%…%'`, sous la collation du serveur
  /// (ni casse ni accents ; `%` et `_` sont des jokers) ; « 0 » ne filtre pas (`when()` le lit faux). Le poste cherchait
  /// dans toute la ligne affichée (catégorie, gravité, statut compris), comme le `textContent` du prototype : « critique »
  /// trouvait une notification d'information au message anodin, que le web ne montrait pas.
  ///
  /// ⚠️ **COMPARAISON FAITE EN DART, PAS EN SQL** : `LIKE` de SQLite ne ramène la casse que pour l'ASCII.
  static List<LigneNotification> filtrer(
    List<LigneNotification> lignes, {
    String recherche = '',
    String categorie = '',
    String statut = '',
  }) {
    RegExp? like;
    if (recherche.isNotEmpty && recherche != '0') {
      final motif = StringBuffer();
      for (final c in cleCommeLeServeur(recherche).split('')) {
        motif.write(switch (c) {
          '%' => '.*',
          '_' => '.',
          _ => RegExp.escape(c),
        });
      }
      like = RegExp(motif.toString(), dotAll: true);
    }

    return [
      for (final l in lignes)
        if ((like == null ||
                like.hasMatch(cleCommeLeServeur(l.message)) ||
                like.hasMatch(cleCommeLeServeur(l.titre))) &&
            (categorie.isEmpty || l.categorie == categorie) &&
            (statut.isEmpty || (l.lue ? 'Lue' : 'Non lue') == statut))
          l,
    ];
  }

  /// Marque lue : le serveur d'abord, la base locale ensuite.
  ///
  /// ⚠️ **LA BASE LOCALE N'EST MODIFIÉE QU'APRÈS LA CONFIRMATION DU SERVEUR.**
  /// L'ordre inverse afficherait « lue » pour une action perdue en route.
  Future<void> marquerLue(String id) async {
    await _serveur().marquerLue(id);
    await (database.update(database.notifications)
          ..where((n) => n.id.equals(id)))
        .write(const NotificationsCompanion(isRead: Value(true)));
  }

  Future<void> supprimer(String id) async {
    await _serveur().supprimer(id);
    await (database.delete(
      database.notifications,
    )..where((n) => n.id.equals(id))).go();
  }

  ServeurNotifications _serveur() =>
      serveur ??
      (throw const EchecNotification(
        'Aucune session ouverte : connectez-vous.',
      ));
}
