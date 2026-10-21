import 'package:flutter/material.dart';

import '../../core/database/app_database.dart' show Customer;
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../rapports/rapports_exports_screen.dart' show Editeur;
import 'avances_modales.dart';
import 'clients_creances_repository.dart';
import 'fiche_client_modales.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/creances-clients.html` → Clients et Créances.
///
/// ⚠️⚠️ **HUB À QUATRE ONGLETS**, dans l'ordre du hub : Liste des Clients ·
/// Suivi des Dettes · Relances Clients · Historique Avances — chargés en
/// `<iframe>` par la maquette (`liste-clients`, `suivi-dettes`,
/// `relances-clients`, `historique-avances`).
///
/// ⚠️ **LES FICHES CLIENTS S'ÉCRIVENT AU POSTE** (ticket F0.72) : créées, modifiées,
/// archivées en local, `pending`, puis envoyées — le serveur valide. **Les créances et les
/// relances restent en lecture seule** : une créance se solde par un encaissement, jamais
/// par une édition.
///
/// ⚠️⚠️ **LES AVANCES ET LEURS IMPUTATIONS S'ÉCRIVENT AU POSTE** (ticket F0.73) : « Nouvelle
/// Avance » et « Imputer » écrivent le FAIT en local, `pending` ; le serveur fait entrer
/// l'argent en trésorerie, passe D 5xx / C 419 puis D 419 / C 411. Le poste ne modifie
/// aucun solde : il AFFICHE les soldes nets de ce qu'il a saisi et que le serveur n'a pas
/// encore appliqué. Pas de « Modifier » (D4) ni d'archivage au poste (D5).
class ClientsCreancesScreen extends StatefulWidget {
  const ClientsCreancesScreen({
    super.key,
    required this.depot,
    this.imprimer,
    this.maintenant = HeureBenin.maintenant,
  });

  final ClientsCreancesRepository depot;

  /// Éditeur injecté — `EditeursRapports.imprimer` en production, un espion en test.
  /// Absent, ni le reçu d'acompte ni « Exporter » n'impriment : l'avance est tout de
  /// même écrite.
  final Editeur? imprimer;

  /// Horloge injectée (date des documents).
  final DateTime Function() maintenant;

  @override
  State<ClientsCreancesScreen> createState() => _ClientsCreancesScreenState();
}

class _ClientsCreancesScreenState extends State<ClientsCreancesScreen> {
  /// Les quatre onglets du hub, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Liste des Clients', SymbolesAgri.groups),
    ('Suivi des Dettes', SymbolesAgri.request_quote),
    ('Relances Clients', SymbolesAgri.campaign),
    ('Historique Avances', SymbolesAgri.savings),
  ];

  String _onglet = onglets.first.$1;
  String _recherche = '';

  /// Filtres de « Liste des Clients » et sélection pour l'archivage en masse.
  String _filtreStatut = '';
  String _filtreVille = '';
  final Set<String> _selection = {};

  /// Les trois niveaux du sélecteur — `relances-clients.html` l.161-163.
  static const niveauxRelance = <(String, String)>[
    ('1', 'Niveau 1 : Rappel amiable (J+7)'),
    ('2', 'Niveau 2 : Rappel ferme (30 jours)'),
    ('3', 'Niveau 3 : Mise en demeure'),
  ];

  /// Les trois textes de la maquette, au caractère près (l.331-335).
  static const modelesRelance = <String, String>{
    '1':
        'Bonjour [NOM], nous vous rappelons amicalement que votre facture '
        "[FACTURE] d'un montant de [MONTANT_DU] arrive à échéance le "
        '[DATE_ECHEANCE]. Merci de régulariser votre situation. Ferme École '
        'OLOUWACHEGOUN.',
    '2':
        'Bonjour [NOM], votre facture [FACTURE] de [MONTANT_DU] est en retard '
        'de paiement depuis le [DATE_ECHEANCE]. Merci de procéder au règlement '
        'dans les meilleurs délais. Ferme École OLOUWACHEGOUN.',
    '3':
        'Madame, Monsieur [NOM], malgré nos relances précédentes, votre '
        "facture [FACTURE] d'un montant de [MONTANT_DU] demeure impayée depuis "
        'le [DATE_ECHEANCE]. Nous vous mettons en demeure de régulariser sous '
        '8 jours. Ferme École OLOUWACHEGOUN.',
  };

  /// Niveau sélectionné — `<select id="tpl-level">` de la maquette, dont
  /// l'option 2 porte `selected` (l.162).
  String _niveauRelance = '2';

  DonneesClients? _donnees;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final large = AgriBreakpoints.large(context);

                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    large ? AgriSpacing.lg : AgriSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _barreOnglets(),
                      const SizedBox(height: AgriSpacing.lg),
                      switch (_onglet) {
                        'Suivi des Dettes' => _ongletDettes(d, large),
                        'Relances Clients' => _ongletRelances(d, large),
                        'Historique Avances' => _ongletAvances(d, large),
                        _ => _ongletClients(d, large),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (titre, icone) in onglets)
            InkWell(
              key: Key('onglet-clients-$titre'),
              onTap: () => setState(() => _onglet = titre),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icone,
                      size: 18,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : AgriColors.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: AgriTypography.gras,
                        color: _onglet == titre
                            ? AgriColors.brandEmerald
                            : AgriColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.outline,
  );

  // ── Onglet 1 : Liste des Clients ──────────────────────────────────────────

  Widget _ongletClients(DonneesClients d, bool large) {
    final terme = _recherche.trim().toLowerCase();

    final villes = {
      for (final l in d.clients)
        if ((l.client.city ?? '').isNotEmpty) l.client.city!,
    }.toList()..sort();

    final lignes = d.clients.where((l) {
      if (_filtreStatut.isNotEmpty && l.statut != _filtreStatut) return false;
      if (_filtreVille.isNotEmpty && l.client.city != _filtreVille) {
        return false;
      }
      if (terme.isEmpty) return true;
      // Comme le web : la recherche porte sur le nom.
      return l.client.name.toLowerCase().contains(terme);
    }).toList();

    final choisis = lignes.where((l) => _selection.contains(l.client.id));
    final toutChoisi = lignes.isNotEmpty && choisis.length == lignes.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          'Liste des Clients',
          SymbolesAgri.groups,
          'Répertoire des clients de la ferme et de leur situation commerciale.',
          large,
        ),
        const SizedBox(height: AgriSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            key: const Key('nouveau-client'),
            onPressed: () => _ouvrirFiche(null),
            icon: const Icon(SymbolesAgri.add_circle, size: 18),
            label: const Text(
              'Nouveau Client',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        _grilleKpis(large, [
          CarteKpi(
            libelle: 'Clients actifs',
            valeur: '${d.clientsActifs}',
            couleurLisere: AgriColors.brandEmerald,
            icone: SymbolesAgri.groups,
          ),
          // ⚠️⚠️ TIRET, JAMAIS ZÉRO : `customers` descend sans sa date de
          // création. « 0 nouveau ce mois-ci » affirmerait qu'aucun client
          // n'a été créé, ce que le poste ne peut pas savoir.
          const CarteKpi(
            libelle: 'Nouveaux (mois)',
            valeur: '—',
            legende: 'Date de création non synchronisée',
            couleurLisere: AgriColors.infoBlue,
            icone: SymbolesAgri.person_add,
            couleurIcone: AgriColors.infoBlue,
          ),
          CarteKpi(
            libelle: 'Solde créances',
            valeur: _montant(d.encoursGlobal),
            unite: 'FCFA',
            couleurLisere: AgriColors.errorRed,
            icone: SymbolesAgri.request_quote,
            couleurIcone: AgriColors.errorRed,
          ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        if (_selection.isNotEmpty) ...[
          _barreSelection(d),
          const SizedBox(height: AgriSpacing.md),
        ],
        Wrap(
          spacing: AgriSpacing.sm,
          runSpacing: AgriSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _champRecherche('Rechercher un client...'),
            _liste(
              cle: 'filtre-statut-client',
              valeur: _filtreStatut,
              toutes: 'Statut : Tous',
              options: const ['Actif', 'Créance en retard'],
              onChanged: (v) => setState(() => _filtreStatut = v),
            ),
            _liste(
              cle: 'filtre-ville-client',
              valeur: villes.contains(_filtreVille) ? _filtreVille : '',
              toutes: 'Ville : Toutes',
              options: villes,
              onChanged: (v) => setState(() => _filtreVille = v),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _tableau(
          largeur: 1040,
          teteSelection: Checkbox(
            key: const Key('clients-tout-selectionner'),
            value: toutChoisi,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selection.addAll(lignes.map((l) => l.client.id));
              } else {
                _selection.removeAll(lignes.map((l) => l.client.id));
              }
            }),
          ),
          colonnes: const [
            ('Nom', 4),
            ('Téléphone', 3),
            ('Ville', 3),
            ('Total Achats', 3),
            ('Solde Dû', 3),
            ('Statut', 3),
            ('Actions', 3),
          ],
          vide: '— Aucun client pour ces critères —',
          lignes: [
            for (var i = 0; i < lignes.length; i++)
              _ligne(
                i,
                [
                  (
                    Text(
                      lignes[i].client.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: AgriTypography.gras,
                      ),
                    ),
                    4,
                  ),
                  (Text(lignes[i].client.phone ?? '—', style: _cellule), 3),
                  (Text(lignes[i].client.city ?? '—', style: _cellule), 3),
                  // ⚠️ CE POSTE UNIQUEMENT : le tirage ne descend pas `sales`.
                  (Text(_montant(lignes[i].totalAchats), style: _cellule), 3),
                  (
                    Text(
                      _montant(lignes[i].soldeDu),
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: AgriTypography.gras,
                        color: lignes[i].soldeDu > 0
                            ? AgriColors.errorDeep
                            : AgriColors.onSurface,
                      ),
                    ),
                    3,
                  ),
                  (_statutClient(lignes[i]), 3),
                  (_actionsClient(lignes[i].client), 3),
                ],
                teteSelection: Checkbox(
                  key: Key('client-case-${lignes[i].client.id}'),
                  value: _selection.contains(lignes[i].client.id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selection.add(lignes[i].client.id);
                    } else {
                      _selection.remove(lignes[i].client.id);
                    }
                  }),
                ),
              ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _mentionPoste(
          'Le total des achats ne compte que les ventes encaissées sur ce '
          'poste : celles du comptoir web et des autres postes ne descendent '
          'pas ici. Le solde dû, lui, vient du serveur.',
        ),
      ],
    );
  }

  Future<void> _ouvrirFiche(Customer? existant) async {
    final ecrit = await ouvrirFicheClient(
      context: context,
      depot: widget.depot,
      existant: existant,
    );
    if (ecrit) await _charger();
  }

  Future<void> _archiver(List<Customer> clients) async {
    final ok = await confirmerArchivageClients(
      context: context,
      depot: widget.depot,
      clients: clients,
    );
    if (!ok) return;
    _selection.clear();
    await _charger();
  }

  /// « N client(s) sélectionné(s) » + « Supprimer la sélection » (libellé de la maquette ET
  /// du web ; l'action archive, elle ne supprime rien).
  Widget _barreSelection(DonneesClients d) => Container(
    key: const Key('barre-selection-clients'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.errorRed.withValues(alpha: 0.08),
      border: Border.all(color: AgriColors.errorDeep.withValues(alpha: 0.30)),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${_selection.length} client(s) sélectionné(s)',
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
              color: AgriColors.errorDeep,
            ),
          ),
        ),
        ElevatedButton(
          key: const Key('supprimer-selection-clients'),
          onPressed: () => _archiver([
            for (final l in d.clients)
              if (_selection.contains(l.client.id)) l.client,
          ]),
          style: ElevatedButton.styleFrom(
            backgroundColor: AgriColors.errorRed,
            foregroundColor: Colors.white,
          ),
          child: const Text(
            'Supprimer la sélection',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _liste({
    required String cle,
    required String valeur,
    required String toutes,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) => SizedBox(
    width: 200,
    child: DropdownButtonFormField<String>(
      key: Key(cle),
      initialValue: valeur,
      isExpanded: true,
      isDense: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        color: AgriColors.onSurface,
      ),
      items: [
        DropdownMenuItem(value: '', child: Text(toutes)),
        for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    ),
  );

  /// « Actif » / « Créance en retard », et « En attente » tant que le serveur n'a pas
  /// acquitté la fiche.
  Widget _statutClient(LigneClient l) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      _pastille(
        l.statut,
        l.statut == 'Actif' ? AgriColors.brandEmerald : AgriColors.errorDeep,
      ),
      if (l.enAttente)
        Container(
          key: Key('client-en-attente-${l.client.id}'),
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: AgriColors.accentYellow.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'En attente',
            style: TextStyle(
              fontSize: 10,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
        ),
    ],
  );

  Widget _actionsClient(Customer c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: Key('modifier-client-${c.id}'),
        tooltip: 'Modifier',
        onPressed: () => _ouvrirFiche(c),
        icon: const Icon(SymbolesAgri.edit, size: 16),
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
        color: AgriColors.infoBlue,
      ),
      IconButton(
        key: Key('archiver-client-${c.id}'),
        tooltip: 'Archiver',
        onPressed: () => _archiver([c]),
        icon: const Icon(SymbolesAgri.archive, size: 16),
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
        color: AgriColors.outline,
      ),
    ],
  );

  // ── Onglet 2 : Suivi des Dettes ───────────────────────────────────────────

  Widget _ongletDettes(DonneesClients d, bool large) {
    final jour = HeureBenin.maintenant();
    final terme = _recherche.trim().toLowerCase();

    final lignes = d.creances.where((l) {
      if (terme.isEmpty) return true;
      return l.nomClient.toLowerCase().contains(terme);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          'Suivi des Dettes Clients',
          SymbolesAgri.request_quote,
          'Encours, échéances et recouvrement.',
          large,
        ),
        const SizedBox(height: AgriSpacing.md),
        _grilleKpis(large, [
          CarteKpi(
            libelle: 'Encours Global',
            valeur: _montant(d.encoursGlobal),
            unite: 'FCFA',
            couleurLisere: AgriColors.errorRed,
            icone: SymbolesAgri.account_balance_wallet,
            couleurIcone: AgriColors.errorRed,
          ),
          CarteKpi(
            libelle: 'Échus > 30 jours',
            valeur: _montant(
              d.echusAuDela(jour, ClientsCreancesRepository.seuilEchu),
            ),
            unite: 'FCFA',
            couleurLisere: AgriColors.accentYellow,
            icone: SymbolesAgri.schedule,
            couleurIcone: AgriColors.brandForest,
          ),
          // ⚠️⚠️ LE TAUX DE RECOUVREMENT SUPPOSE CE QUI A ÉTÉ SOLDÉ. Le serveur
          // ne descend que les créances ENCORE DUES : le poste ne voit pas le
          // dénominateur. Un taux calculé sur les seules créances ouvertes
          // vaudrait toujours 0 % ou presque, et se lirait comme un
          // recouvrement en échec.
          const CarteKpi(
            libelle: 'Taux de Recouvrement',
            valeur: '—',
            legende: 'Créances soldées non synchronisées',
            couleurLisere: AgriColors.infoBlue,
            icone: SymbolesAgri.trending_up,
            couleurIcone: AgriColors.infoBlue,
          ),
          CarteKpi(
            libelle: 'Acomptes Reçus',
            valeur: _montant(d.avancesEnCours),
            unite: 'FCFA',
            couleurLisere: AgriColors.brandEmerald,
            icone: SymbolesAgri.savings,
          ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        _champRecherche('Rechercher un débiteur...'),
        const SizedBox(height: AgriSpacing.md),
        _tableau(
          largeur: 980,
          colonnes: const [
            ('Débiteur', 4),
            ('Facture Associée', 3),
            ('Échéance', 3),
            ('Total Facturé', 3),
            ('Solde Restant', 3),
            ('Actions', 2),
          ],
          vide: '— Aucune créance en cours —',
          lignes: [
            for (var i = 0; i < lignes.length; i++)
              _ligne(i, [
                (
                  Text(
                    lignes[i].nomClient,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                    ),
                  ),
                  4,
                ),
                // ⚠️ AUCUN NUMÉRO DE FACTURE N'EXISTE — ni au poste, ni dans
                // `sales` côté serveur, ni dans le POS (ticket 14.71).
                (const Text('—', style: _cellule), 3),
                (_echeance(lignes[i], jour), 3),
                (Text(_montant(lignes[i].creance.amount), style: _cellule), 3),
                (
                  Text(
                    _montant(lignes[i].resteDu),
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.errorDeep,
                    ),
                  ),
                  3,
                ),
                (_actionInerte(), 2),
              ]),
          ],
        ),
      ],
    );
  }

  /// Échéance, colorée par son retard.
  ///
  /// ⚠️ **LE RETARD SE COMPTE DEPUIS L'ÉCHÉANCE**, jamais depuis l'émission :
  /// une facture émise il y a 90 jours mais payable à 120 n'est pas en retard.
  Widget _echeance(LigneCreance l, DateTime jour) {
    final retard = l.retard(jour);

    if (retard == null) {
      return const Text('—', style: _cellule);
    }

    final enRetard = retard > 0;

    return Text(
      enRetard
          ? '${_date(l.creance.dueDate)} (+$retard j)'
          : _date(l.creance.dueDate),
      style: TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: enRetard ? AgriTypography.gras : AgriTypography.normal,
        color: enRetard ? AgriColors.errorDeep : AgriColors.onSurface,
      ),
    );
  }

  // ── Onglet 3 : Relances Clients ───────────────────────────────────────────

  /// ⚠️⚠️ **CORRECTION D'UNE ERREUR DE VÉRIFICATION.** Cet onglet a d'abord été
  /// livré comme « module non embarqué », au motif qu'« aucune table de relance
  /// n'existe, ni au poste ni sur le serveur ». C'était faux : la table
  /// s'appelle `customer_reminders` — pas `payment_reminders`, le seul nom
  /// cherché — elle porte 8 lignes réelles et l'écran web `RelancesClients`
  /// l'alimente à chaque envoi. Chercher UN nom et conclure à l'absence est
  /// exactement le raccourci que la doctrine interdit ; la table descend depuis
  /// le ticket 14.76.
  ///
  /// ⚠️ **LES TROIS BOUTONS D'ENVOI DE LA MAQUETTE SONT ABSENTS**
  /// (`relances-clients.html` l.146-148 : « Relancer WhatsApp », « Relancer par
  /// Mail », « Exporter Courrier »). Envoyer suppose le réseau ET le canal mail
  /// du serveur (`CustomerReminderMail`) ; surtout, `customer_reminders` est un
  /// référentiel en LECTURE SEULE — une relance partie du poste ne serait
  /// enregistrée nulle part, et le client serait rappelé une seconde fois
  /// depuis le web le lendemain. Le motif est affiché à l'écran, pas seulement
  /// ici.
  Widget _ongletRelances(DonneesClients d, bool large) {
    final jour = HeureBenin.maintenant();
    final file = d.fileDeRelance(jour);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          'Relances & Recouvrement',
          SymbolesAgri.campaign,
          'Moteur de relance multi-canal intelligent des créances clients.',
          large,
        ),
        const SizedBox(height: AgriSpacing.md),
        _grilleKpis(large, [
          // ⚠️ ÉCART DOCUMENTÉ — DEUX RÈGLES POUR UN MÊME LIBELLÉ. La maquette
          // légende cet indicateur « Retards de plus de 30 jours »
          // (`relances-clients.html` l.115) ; le web, lui, somme TOUTE la file
          // échue, sans seuil (`RelancesClients.php` l.110 + l.117-125). Le
          // poste suit la légende qu'il affiche — et reste ainsi cohérent avec
          // son propre onglet « Suivi des Dettes », qui porte le même seuil.
          // ARBITRAGE CLIENT : quel est le bon seuil, 0 ou 30 jours ?
          CarteKpi(
            libelle: 'Créances Échues',
            valeur: _montant(
              d.echusAuDela(jour, ClientsCreancesRepository.seuilEchu),
            ),
            unite: 'FCFA',
            legende: 'Retards de plus de 30 jours',
            couleurLisere: AgriColors.errorRed,
            icone: SymbolesAgri.event_busy,
            couleurIcone: AgriColors.errorRed,
          ),
          CarteKpi(
            libelle: 'Relances Effectuées',
            valeur: '${d.relancesDuMois(jour)}',
            unite: 'env.',
            legende: 'WhatsApp, SMS & Mail',
            couleurLisere: AgriColors.infoBlue,
            icone: SymbolesAgri.campaign,
            couleurIcone: AgriColors.infoBlue,
          ),
          // ⚠️⚠️ LE TAUX DE RÉPONSE SE MESURE SUR CE QUI A ÉTÉ PAYÉ. Le web le
          // calcule sur les créances ayant reçu au moins une relance, réglées
          // ou non (`RelancesClients.php` l.104-113) ; le serveur ne descend
          // au poste que ce qui RESTE DÛ, donc jamais une créance soldée. Le
          // dénominateur serait tronqué et le taux se lirait comme un échec du
          // recouvrement.
          const CarteKpi(
            libelle: 'Taux de Réponse',
            valeur: '—',
            legende: 'Créances soldées non synchronisées',
            couleurLisere: AgriColors.brandEmerald,
            icone: SymbolesAgri.check_circle,
          ),
          // ⚠️⚠️ MÊME CAUSE : le montant recouvré somme les règlements des
          // créances relancées. Celles qui ont été soldées ont quitté le
          // tirage — le poste n'en compterait qu'une part, présentée comme un
          // total.
          const CarteKpi(
            libelle: 'Montant Recouvré',
            valeur: '—',
            legende: 'Règlements soldés non synchronisés',
            couleurLisere: AgriColors.brandForest,
            icone: SymbolesAgri.trending_up,
            couleurIcone: AgriColors.brandForest,
          ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        // Maquette : `grid grid-cols-1 lg:grid-cols-[65%_35%] gap-md` (l.132).
        if (large)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 65, child: _fileDeRelance(file, jour)),
                const SizedBox(width: AgriSpacing.md),
                Expanded(flex: 35, child: _modeleDeMessage()),
              ],
            ),
          )
        else ...[
          _fileDeRelance(file, jour),
          const SizedBox(height: AgriSpacing.md),
          _modeleDeMessage(),
        ],
      ],
    );
  }

  /// Panneau gauche — `relances-clients.html` l.133-137.
  Widget _fileDeRelance(List<LigneCreance> file, DateTime jour) => Container(
    key: const Key('file-de-relance'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'FILE DE RELANCE ACTIVE',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: AgriTypography.gras,
            color: AgriColors.brandForest,
          ),
        ),
        const SizedBox(height: AgriSpacing.sm),
        if (file.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AgriSpacing.md),
            child: Text(
              '— Aucune créance échue à relancer —',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontStyle: FontStyle.italic,
                color: AgriColors.outline,
              ),
            ),
          )
        else
          for (final l in file) ...[
            _carteDebiteur(l, jour),
            const SizedBox(height: AgriSpacing.sm),
          ],
        _mentionPoste(
          'Les envois — WhatsApp, mail, courrier — partent de la surface web : '
          "ils demandent le réseau, et une relance faite d'ici ne serait "
          'inscrite nulle part. Le client serait rappelé deux fois.',
        ),
      ],
    ),
  );

  /// Une ligne de la file — `relances-clients.html` l.138-144.
  Widget _carteDebiteur(LigneCreance l, DateTime jour) => Container(
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AgriColors.brandEmerald,
            shape: BoxShape.circle,
          ),
          child: Text(
            _initiales(l.nomClient),
            style: const TextStyle(
              fontSize: AgriTypography.sm,
              fontWeight: AgriTypography.gras,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.nomClient,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AgriTypography.sm,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandForest,
                ),
              ),
              Row(
                children: [
                  Text(
                    '${_montant(l.resteDu)} FCFA',
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.errorDeep,
                    ),
                  ),
                  Text(
                    ' — ${l.retard(jour)} jours de retard',
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// Panneau droit — `relances-clients.html` l.157-181.
  ///
  /// ⚠️ **LES TROIS TEXTES SONT CEUX DE LA MAQUETTE, AU CARACTÈRE PRÈS**
  /// (`relances-clients.html` l.331-335) — le web les reprend à l'identique.
  /// Ils servent au téléphone comme au courrier : l'opérateur lit le texte
  /// exact, hors ligne.
  ///
  /// ⚠️ **NI LES PASTILLES D'INSERTION NI « SAUVEGARDER MODÈLE » NE SONT
  /// PORTÉES** (l.169-179). Aucune table de modèles n'existe — le web le dit
  /// aussi (`RelancesClients.php` l.55-57) : le bouton n'y persiste rien. Un
  /// bouton qui affiche « sauvegardé » sans rien enregistrer est un mensonge
  /// d'interface ; les balises, elles, n'ont pas de champ où s'insérer
  /// puisqu'il n'y a rien à envoyer depuis le poste.
  Widget _modeleDeMessage() => Container(
    key: const Key('modele-de-message'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'NIVEAU DE RELANCE',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: AgriTypography.gras,
            color: AgriColors.brandForest,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        DropdownButtonFormField<String>(
          key: const Key('niveau-relance'),
          initialValue: _niveauRelance,
          isDense: true,
          // ⚠️ `w-full` dans la maquette (l.161) : sans `isExpanded`, l'option
          // sélectionnée garde sa largeur naturelle et déborde de 28 px.
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(
            fontSize: AgriTypography.sm,
            color: AgriColors.onSurface,
          ),
          items: [
            for (final n in niveauxRelance)
              DropdownMenuItem(value: n.$1, child: Text(n.$2)),
          ],
          onChanged: (v) =>
              setState(() => _niveauRelance = v ?? _niveauRelance),
        ),
        const SizedBox(height: AgriSpacing.md),
        const Text(
          'MODÈLE DE MESSAGE',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: AgriTypography.gras,
            color: AgriColors.brandForest,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.md,
            vertical: AgriSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Text(
            modelesRelance[_niveauRelance] ?? '',
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              height: AgriTypography.xsInterligne / AgriTypography.xs,
              color: AgriColors.onSurface,
            ),
          ),
        ),
      ],
    ),
  );

  /// Initiales du débiteur — la pastille de la maquette (l.139).
  static String _initiales(String nom) {
    final mots = nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty);
    if (mots.isEmpty) return '?';
    return mots.take(2).map((m) => m[0].toUpperCase()).join();
  }

  // ── Onglet 4 : Historique Avances ─────────────────────────────────────────

  Widget _ongletAvances(DonneesClients d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entete(
        'Historique des Avances',
        SymbolesAgri.savings,
        'Acomptes versés par les clients.',
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: AgriSpacing.xs,
          runSpacing: AgriSpacing.xs,
          children: [
            OutlinedButton.icon(
              key: const Key('exporter-avances'),
              onPressed: () => _exporterAvances(d),
              icon: const Icon(SymbolesAgri.picture_as_pdf, size: 18),
              label: const Text(
                'Exporter',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AgriColors.brandForest,
                side: const BorderSide(color: AgriColors.outlineVariant),
                shape: const StadiumBorder(),
              ),
            ),
            ElevatedButton.icon(
              key: const Key('nouvelle-avance'),
              onPressed: () => _nouvelAcompte(d),
              icon: const Icon(SymbolesAgri.add_circle, size: 18),
              label: const Text(
                'Nouvelle Avance',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AgriSpacing.md),
      _grilleKpis(large, [
        CarteKpi(
          libelle: 'Avances en cours',
          valeur: _montant(d.avancesEnCours),
          unite: 'FCFA',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.savings,
        ),
        CarteKpi(
          libelle: 'Clients concernés',
          valeur: '${d.clientsAvecAvance}',
          couleurLisere: AgriColors.infoBlue,
          icone: SymbolesAgri.groups,
          couleurIcone: AgriColors.infoBlue,
        ),
        // ⚠️ Le serveur ne sert que les avances ACTIVES : une avance
        // soldée disparaît du tirage. Compter « 0 soldée ce mois-ci »
        // affirmerait qu'aucune ne l'a été.
        const CarteKpi(
          libelle: 'Avances soldées (mois)',
          valeur: '—',
          legende: 'Avances closes non synchronisées',
          couleurLisere: AgriColors.accentYellow,
          icone: SymbolesAgri.done_all,
          couleurIcone: AgriColors.brandForest,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1000,
        colonnes: const [
          ('Client', 4),
          ('Montant Avance', 3),
          ('Solde Restant', 3),
          ('Date', 3),
          ('Statut', 4),
          ('Actions', 2),
        ],
        vide: '— Aucune avance en cours —',
        lignes: [
          for (var i = 0; i < d.avances.length; i++)
            _ligne(i, [
              (
                Text(
                  d.avances[i].nomClient,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                4,
              ),
              (Text(_montant(d.avances[i].avance.amount), style: _cellule), 3),
              (_soldeAvance(d.avances[i]), 3),
              (
                Text(_date(d.avances[i].avance.advanceDate), style: _cellule),
                3,
              ),
              (_statutAvance(d.avances[i]), 4),
              (_actionsAvance(d, d.avances[i]), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      _mentionPoste(
        'Les soldes sont NETS des imputations saisies sur ce poste et pas encore '
        'envoyées : le poste ne modifie jamais le solde d\'une avance ni d\'une '
        'créance, le serveur les applique à la synchronisation. Une avance '
        '« En attente » n\'est pas encore reçue par la ferme : ni la trésorerie ni '
        'la comptabilité n\'ont bougé.',
      ),
    ],
  );

  /// Solde restant NET, et ce qui le sépare du solde servi quand une imputation attend.
  Widget _soldeAvance(LigneAvance l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _montant(l.soldeRestant),
        key: Key('avance-solde-${l.avance.id}'),
        style: _cellule,
      ),
      if (l.imputationEnAttente)
        Text(
          'dont ${_montant(l.imputeEnAttente)} imputé(s) en attente',
          key: Key('avance-solde-net-${l.avance.id}'),
          style: const TextStyle(fontSize: 10, color: AgriColors.outline),
        ),
    ],
  );

  /// « En cours » / « Soldée », puis « En attente » tant que le serveur n'a pas acquitté
  /// l'avance, « Imputation en attente » tant qu'une imputation n'est pas acquittée, et
  /// « Refusée » avec le motif du serveur si l'avance a été rejetée.
  Widget _statutAvance(LigneAvance l) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      _pastille(
        l.soldee ? 'Soldée' : 'En cours',
        l.soldee ? AgriColors.outline : AgriColors.brandEmerald,
      ),
      if (l.enAttente)
        Container(
          key: Key('avance-en-attente-${l.avance.id}'),
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: AgriColors.accentYellow.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'En attente',
            style: TextStyle(
              fontSize: 10,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      if (l.imputationEnAttente)
        Container(
          key: Key('avance-imputation-attente-${l.avance.id}'),
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: AgriColors.accentYellow.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'Imputation en attente',
            style: TextStyle(
              fontSize: 10,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      if (l.refusee)
        Column(
          key: Key('avance-refusee-${l.avance.id}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pastille('Refusée par le serveur', AgriColors.errorDeep),
            Text(
              l.motifRefus ?? 'Refus sans motif communiqué.',
              style: const TextStyle(fontSize: 10, color: AgriColors.errorDeep),
            ),
          ],
        ),
    ],
  );

  /// ⚠️ **PAS DE « MODIFIER » NI D'« ARCHIVER »** (D4, D5) : le montant d'une avance
  /// entamée ou comptabilisée est figé, et une avance qui a un reste ne s'archive pas.
  /// L'œil de la maquette reste inerte ; « Imputer » ouvre « Imputer un Acompte ».
  Widget _actionsAvance(DonneesClients d, LigneAvance l) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Opacity(
        opacity: 0.4,
        child: Icon(SymbolesAgri.visibility, size: 16, color: AgriColors.outline),
      ),
      if (!l.soldee && !l.refusee)
        IconButton(
          key: Key('imputer-avance-${l.avance.id}'),
          tooltip: 'Imputer',
          onPressed: () => _imputer(d, l),
          icon: const Icon(SymbolesAgri.sync, size: 16),
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
          color: AgriColors.brandForest,
        ),
    ],
  );

  Future<void> _nouvelAcompte(DonneesClients d) async {
    final saisi = await ouvrirNouvelAcompte(
      context: context,
      depot: widget.depot,
      donnees: d,
    );
    if (saisi == null) return;
    await _charger();

    // ⚠️ Le reçu n'est émis QU'APRÈS l'écriture locale : un reçu pour une saisie perdue
    // serait un faux. Une panne de l'éditeur n'annule pas l'avance, déjà écrite.
    final editeur = widget.imprimer;
    if (editeur == null) {
      _annoncer(
        'Acompte enregistré pour ${saisi.nomClient} — il partira à la prochaine '
        'synchronisation.',
      );
      return;
    }
    try {
      await editeur(
        DocumentsAvances.recu(
          client: saisi.nomClient,
          motif: saisi.motif,
          montant: saisi.avance.amount,
          mode: saisi.mode,
          date: saisi.avance.advanceDate ?? widget.maintenant(),
        ),
        widget.maintenant(),
      );
      _annoncer(
        'Acompte enregistré pour ${saisi.nomClient} — reçu généré. Il partira à '
        'la prochaine synchronisation.',
      );
    } catch (_) {
      _annoncer(
        'Acompte enregistré pour ${saisi.nomClient}, mais le reçu n\'a pas pu '
        'être édité.',
      );
    }
  }

  Future<void> _imputer(DonneesClients d, LigneAvance depart) async {
    final ecrit = await ouvrirImputation(
      context: context,
      depot: widget.depot,
      donnees: d,
      depart: depart,
    );
    if (!ecrit) return;
    await _charger();
    _annoncer(
      'Imputation enregistrée — elle sera appliquée à la prochaine '
      'synchronisation.',
    );
  }

  /// « Exporter » — `exportAvancesPDF()` : toute la liste (la maquette n'exporte que les
  /// lignes filtrées, mais le poste n'a pas ces filtres). Une liste vide n'est pas
  /// éditée : un document réduit à son en-tête ressemblerait à « rien à signaler ».
  Future<void> _exporterAvances(DonneesClients d) async {
    if (d.avances.isEmpty) {
      _annoncer('Aucune avance à exporter.');
      return;
    }
    final editeur = widget.imprimer;
    if (editeur == null) return;
    final message = await editeur(
      DocumentsAvances.liste(d.avances),
      widget.maintenant(),
    );
    _annoncer(message ?? 'Document envoyé à l\'impression.');
  }

  void _annoncer(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: AgriTypography.xs),
        ),
        backgroundColor: AgriColors.brandEmerald,
      ),
    );
  }

  // ── Briques communes ──────────────────────────────────────────────────────

  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  Widget _entete(String titre, IconData icone, String sousTitre, bool large) =>
      Container(
        padding: const EdgeInsets.only(bottom: AgriSpacing.md),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, size: 26, color: AgriColors.brandEmerald),
                const SizedBox(width: AgriSpacing.xs),
                Text(
                  titre,
                  style: TextStyle(
                    fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.xs),
            Text(
              sousTitre,
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
          ],
        ),
      );

  Widget _grilleKpis(bool large, List<Widget> cartes) => GrilleKpi(colonnes: large ? cartes.length : 2, children: cartes,
  );

  Widget _champRecherche(String invite) => SizedBox(
    width: 320,
    child: TextField(
      key: const Key('clients-recherche'),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(SymbolesAgri.search, size: 18),
        hintText: invite,
        hintStyle: const TextStyle(fontSize: AgriTypography.xs),
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: AgriTypography.xs),
      onChanged: (v) => setState(() => _recherche = v),
    ),
  );

  Widget _tableau({
    required double largeur,
    required List<(String, int)> colonnes,
    required List<Widget> lignes,
    required String vide,
    Widget? teteSelection,
  }) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: largeur,
        child: Column(
          children: [
            Container(
              color: AgriColors.surfaceZebra,
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
              child: Row(
                children: [
                  if (teteSelection != null)
                    SizedBox(width: 32, child: teteSelection),
                  for (final (libelle, flex) in colonnes)
                    Expanded(
                      flex: flex,
                      child: Text(libelle.toUpperCase(), style: _enteteColonne),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  vide,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            ...lignes,
          ],
        ),
      ),
    ),
  );

  Widget _ligne(
    int index,
    List<(Widget, int)> cellules, {
    Widget? teteSelection,
  }) => Container(
    key: Key('ligne-$index'),
    color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(
      children: [
        if (teteSelection != null) SizedBox(width: 32, child: teteSelection),
        for (final (contenu, flex) in cellules)
          Expanded(flex: flex, child: contenu),
      ],
    ),
  );

  Widget _pastille(String libelle, Color couleur) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        border: Border.all(color: couleur.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
      child: Text(
        libelle,
        style: TextStyle(
          fontSize: 11,
          fontWeight: AgriTypography.gras,
          color: couleur,
        ),
      ),
    ),
  );

  /// ⚠️ Les actions de la maquette — fiche client, relance, encaissement —
  /// modifient des référentiels du serveur. La colonne reste, l'action est
  /// inerte.
  Widget _actionInerte() => const Opacity(
    opacity: 0.4,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Icon(SymbolesAgri.visibility, size: 16, color: AgriColors.outline),
    ),
  );

  Widget _mentionPoste(String texte) => Container(
    key: const Key('mention-poste'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.accentYellow.withValues(alpha: 0.10),
      border: Border.all(
        color: AgriColors.accentYellow.withValues(alpha: 0.30),
      ),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(SymbolesAgri.info, size: 18, color: AgriColors.brandForest),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Text(
            texte,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
    ),
  );

  static String _montant(double valeur) {
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  static String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
