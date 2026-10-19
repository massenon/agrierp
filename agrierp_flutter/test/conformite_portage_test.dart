import 'dart:io';

import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chemins_depot.dart';

/// Ticket F0.40 — GARDE-FOUS DE LA DOCTRINE DE PORTAGE.
///
/// ⚠️⚠️ **CES TESTS LISENT LE CODE SOURCE, ET C'EST VOLONTAIRE.** Les trois
/// écarts qu'ils verrouillent sont **invisibles à l'exécution** : l'écran
/// s'affiche, il est simplement différent de celui que le commanditaire a
/// validé. Aucun test de rendu ne les attrape, l'analyseur non plus. Sans
/// garde-fou, ils reviennent au premier écran suivant — les trois avaient
/// d'ailleurs été commis sur **quatorze** fichiers avant d'être relevés.
void main() {
  List<File> sources() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList();

  /// Une ligne de code, commentaires exclus : un garde-fou qui se déclenche
  /// sur sa propre explication serait ingérable.
  bool estDuCode(String ligne) {
    final t = ligne.trim();
    return t.isNotEmpty && !t.startsWith('//') && !t.startsWith('///');
  }

  /// ⚠️⚠️ **LA MISE EN PAGE SE DÉCIDE SUR LA LARGEUR DE L'ÉCRAN, JAMAIS SUR
  /// CELLE DU CONTENU.** Dans le socle du poste, la zone de contenu est
  /// amputée de la barre latérale et des marges : un écran de 1280 px ne
  /// présente qu'environ 980 px de contrainte, et bascule donc en mise en page
  /// « moyenne » là où le navigateur applique `lg:`. La page reste belle —
  /// simplement, ce n'est pas celle qui a été validée.
  ///
  /// Mesurer la place disponible pour dimensionner un enfant reste légitime :
  /// c'est décider d'une DISPOSITION sur cette largeur qui ne l'est pas.
  /// ⚠️⚠️ **UN ABSORBEUR ÉCRIT MAIS JAMAIS APPELÉ EST UNE TABLE QUI NE
  /// DESCEND PAS** — et rien ne le dit : l'écran s'affiche vide, le tirage
  /// annonce un succès, et on cherche le défaut côté serveur.
  ///
  /// Le cas s'est produit au ticket F0.51 : la commande qui posait les quatre
  /// absorbeurs comptables a été interrompue, les tests d'écran ont continué
  /// de passer (ils écrivent en base directement), et seule une relecture l'a
  /// vu. Ce contrôle le voit désormais tout seul.
  test('⚠️⚠️ chaque absorbeur déclaré est réellement appelé au tirage', () {
    final moteur = File('lib/core/sync/sync_engine.dart').readAsStringSync();

    final declares = RegExp(
      r'Future<int> (_absorber\w+)\(',
    ).allMatches(moteur).map((m) => m.group(1)!).toSet();

    final appeles = RegExp(
      r'await (_absorber\w+)\(',
    ).allMatches(moteur).map((m) => m.group(1)!).toSet();

    expect(
      declares.difference(appeles),
      isEmpty,
      reason:
          'Ces absorbeurs existent mais ne sont jamais appelés : les '
          'tables correspondantes ne descendront jamais au poste.',
    );

    expect(
      appeles.difference(declares),
      isEmpty,
      reason: 'Ces absorbeurs sont appelés sans exister.',
    );
  });

  /// ⚠️⚠️ TICKET F0.94 — UNE TABLE SERVIE SANS ABSORBEUR EST UNE TABLE QUI NE DESCEND PAS.
  ///
  /// Le contrôle précédent voit un absorbeur écrit et jamais appelé ; il ne voyait PAS une table
  /// que `/sync/pull` sert et pour laquelle aucun absorbeur n'existe. C'est exactement ce qui est
  /// arrivé à `livestock_daily_entries` : servie depuis le Sprint 0, jamais absorbée, aucune
  /// erreur — les journées saisies sur le web n'arrivaient jamais au poste.
  ///
  /// [tablesServies] est la liste des clés de la réponse de `SyncController::pull` (Laravel),
  /// RELUE le 14/10/2026. Chacune est soit passée à un `_absorber…` dans `_tirer`, soit ignorée
  /// EXPLICITEMENT avec sa raison ([ignorees]). Le second test compare cette copie au code du
  /// serveur quand le dépôt Laravel est présent : une table ajoutée côté serveur le fait échouer.
  const tablesServies = {
    'server_time',
    'data_reset_at',
    'products',
    'product_categories',
    'livestock_lots',
    'livestock_daily_entries',
    'livestock_transfers',
    'feed_ration_standards',
    // Ticket U2 (D-U2) — objectifs de GMQ.
    'growth_standards',
    'veterinary_withdrawal_periods',
    'prophylaxis_schedule_standards',
    'veterinary_records',
    'infirmary_records',
    'veterinary_calendar_events',
    'livestock_reproduction_events',
    'customers',
    'receivables',
    'customer_advances',
    'customer_reminders',
    'feed_types',
    'elevage_numbering',
    'suppliers',
    'purchases',
    'supplier_credits',
    'purchase_orders',
    'payables',
    'employees',
    'internships',
    'attendance_records',
    'mails',
    'administrative_documents',
    'archived_documents',
    'chart_of_accounts',
    'fiscal_years',
    'accounting_entries',
    'accounting_entry_lines',
    'accounting_entry_ids',
    'company_settings',
    'modules_config',
    'roles',
    'users',
    'audit_logs',
    'notifications',
    'lot_revenues',
    'animals',
    'livestock_species',
    'attestation_templates',
    'attestation_counts',
    'sales',
    // Ticket U4 (D-U4) — lignes des ventes et des achats servis, avec leur pièce.
    'sale_lines',
    'purchase_lines',
    'treasury_accounts',
    'expense_categories',
  };

  const ignorees = {
    'server_time':
        'curseur du tirage (horloge du serveur), noté par noterEtatDeSynchronisation : '
        'ce n est pas une table',
    'data_reset_at':
        'marque de réinitialisation (15.50), lue en tête de _tirer pour purger le poste : '
        'ce n est pas une table',
  };

  Set<String> clesAbsorbees() {
    final moteur = File('lib/core/sync/sync_engine.dart').readAsStringSync();
    final appels = RegExp(
      r'await _absorber\w+\(([^;]*?)\);',
      dotAll: true,
    ).allMatches(moteur);
    return {
      for (final a in appels)
        for (final c in RegExp(r"corps\['(\w+)'\]").allMatches(a.group(1)!))
          c.group(1)!,
    };
  }

  test(
    '⚠️⚠️ toute table servie par le tirage est absorbée ou explicitement ignorée (F0.94)',
    () {
      final absorbees = clesAbsorbees();

      expect(
        tablesServies.difference(absorbees).difference(ignorees.keys.toSet()),
        isEmpty,
        reason:
            'Tables servies par /sync/pull sans absorbeur ni raison d être ignorées : '
            'elles ne descendront jamais au poste.',
      );
      expect(
        absorbees.difference(tablesServies),
        isEmpty,
        reason:
            'Clés lues par un absorbeur que le serveur ne sert pas (faute de frappe ?) : '
            'l absorbeur reçoit toujours null et ne fait rien.',
      );
      expect(
        absorbees.intersection(ignorees.keys.toSet()),
        isEmpty,
        reason: 'Une table ne peut pas être à la fois absorbée et ignorée.',
      );
      expect(absorbees, contains('livestock_daily_entries'));
    },
  );

  final controleur = File(
    '$dossierLaravel/app/Http/Controllers/Api/SyncController.php',
  );
  test(
    '⚠️ la liste des tables servies est celle du serveur (SyncController::pull)',
    () {
      final source = controleur.readAsStringSync();
      final debut = source.indexOf('public function pull(');
      // Ticket H3 : le corps du tirage est construit dans `$reponse = [ … ];` (journalisé avant d'être renvoyé).
      final reponse = source.indexOf(r'$reponse = [', debut);
      final fin = source.indexOf('];', reponse);
      expect(debut, greaterThan(-1));
      expect(reponse, greaterThan(debut));
      final bloc = source.substring(reponse, fin);
      final servies = {
        for (final m in RegExp(
          r"^\s*'(\w+)'\s*=>",
          multiLine: true,
        ).allMatches(bloc))
          m.group(1)!,
      };

      expect(
        servies,
        tablesServies,
        reason:
            'Le serveur sert une autre liste de tables : mettez à jour tablesServies, puis '
            'absorbez la nouvelle table ou ignorez-la AVEC sa raison.',
      );
    },
    skip: controleur.existsSync()
        ? false
        : 'dépôt Laravel absent ($dossierLaravel) : comparaison au serveur impossible',
  );

  test('⚠️⚠️ aucune disposition ne se décide sur constraints.maxWidth', () {
    final fautifs = <String>[];

    for (final f in sources()) {
      for (final ligne in f.readAsLinesSync()) {
        if (!estDuCode(ligne)) continue;
        if (RegExp(r'maxWidth\s*(>=|>|<=|<)').hasMatch(ligne)) {
          fautifs.add('${f.path} : ${ligne.trim()}');
        }
      }
    }

    expect(
      fautifs,
      isEmpty,
      reason: 'Employer AgriBreakpoints, qui lit MediaQuery.',
    );
  });

  /// ⚠️⚠️ **`text-xs` VAUT 13,6 px DANS CE PROJET**, pas les 12 px de
  /// Tailwind : `assets/css/common.css` l.48-49 le surcharge à
  /// `0.85rem !important`. C'est la taille la plus employée du prototype —
  /// 3 569 occurrences — donc l'écart le plus visible qu'un portage puisse
  /// commettre. Elle avait été traduite en 12 px à 224 endroits.
  test('⚠️⚠️ la taille de texte du prototype est celle qui est mesurée', () {
    expect(AgriTypography.xs, 13.6);

    final fautifs = <String>[];

    for (final f in sources()) {
      for (final ligne in f.readAsLinesSync()) {
        if (!estDuCode(ligne)) continue;
        // 12, 12.5 et 13 ne correspondent à AUCUNE taille du prototype.
        if (RegExp(r'fontSize:\s*(12(\.5)?|13)\b').hasMatch(ligne)) {
          fautifs.add('${f.path} : ${ligne.trim()}');
        }
      }
    }

    expect(
      fautifs,
      isEmpty,
      reason: 'Employer AgriTypography.xs, mesuré sur common.css.',
    );
  });

  /// ⚠️⚠️ **`border-l-4` SE POSE, IL NE S'ÉTIRE PAS.** Un `Container(width: 4)`
  /// dans une `Row(crossAxisAlignment: stretch)` réclame une hauteur bornée :
  /// placé dans une colonne défilante, il lève « BoxConstraints forces an
  /// infinite height ». Le défaut ne se voit qu'au rendu — il s'est produit
  /// deux fois sur ce projet (tickets F0.32 et F0.39). `CarteKpi` le dessine
  /// avec `Stack` + `Positioned`, ce qui rend la contrainte infinie
  /// impossible.
  test('⚠️⚠️ aucun liseré de carte n est un enfant étiré', () {
    final fautifs = <String>[];

    for (final f in sources()) {
      for (final ligne in f.readAsLinesSync()) {
        if (!estDuCode(ligne)) continue;
        if (RegExp(r'Container\(\s*width:\s*4\s*,\s*color:').hasMatch(ligne)) {
          fautifs.add('${f.path} : ${ligne.trim()}');
        }
      }
    }

    expect(
      fautifs,
      isEmpty,
      reason: 'Employer CarteKpi, qui pose le liseré en Positioned.',
    );
  });

  /// ⚠️ **UNE SEULE IMPLÉMENTATION DE LA CARTE D'INDICATEUR.** Elle vivait en
  /// treize exemplaires recopiés ; deux avaient déjà divergé. Deux copies d'un
  /// même composant finissent toujours par diverger.
  test('⚠️ la carte KPI n a qu une implémentation', () {
    final implementations = sources()
        .where((f) => f.readAsStringSync().contains('class CarteKpi'))
        .map((f) => f.path)
        .toList();

    expect(implementations, hasLength(1));
    expect(implementations.single, endsWith('carte_kpi.dart'));
  });

  /// ⚠️⚠️ **UN `AlertDialog` N'EST PAS LA MODALE DE LA MAQUETTE.** Le composant
  /// Material par défaut porte ses propres marges, sa propre typographie de
  /// titre, son propre alignement de boutons, et n'a **ni bouton ✕ ni
  /// séparateur de pied**. Cinq écrans l'employaient : ils affichaient une
  /// boîte de dialogue Material là où le commanditaire a validé un gabarit
  /// précis, partagé par 125 modales du prototype.
  test('⚠️⚠️ aucune modale n est un AlertDialog Material', () {
    final fautifs = <String>[];

    for (final f in sources()) {
      for (final ligne in f.readAsLinesSync()) {
        if (!estDuCode(ligne)) continue;
        if (ligne.contains('AlertDialog(')) {
          fautifs.add('${f.path} : ${ligne.trim()}');
        }
      }
    }

    expect(
      fautifs,
      isEmpty,
      reason: 'Employer ModaleAgri ou ModaleConfirmation.',
    );
  });

  /// ⚠️ **LE VOILE PASSE PAR `afficherModale`.** `showDialog` appelé
  /// directement retombe sur le voile Material (`black54`) au lieu des
  /// `bg-black/50` et `bg-black/60` du prototype — deux teintes assez proches
  /// pour passer inaperçues seules, et assez différentes pour qu'une
  /// comparaison écran-à-écran les sépare.
  test('⚠️ aucune modale n ouvre showDialog directement', () {
    final fautifs = <String>[];

    for (final f in sources()) {
      if (f.path.endsWith('modale_agri.dart')) continue;
      for (final ligne in f.readAsLinesSync()) {
        if (!estDuCode(ligne)) continue;
        if (ligne.contains('showDialog<') || ligne.contains('showDialog(')) {
          fautifs.add('${f.path} : ${ligne.trim()}');
        }
      }
    }

    expect(fautifs, isEmpty, reason: 'Employer afficherModale.');
  });
}
