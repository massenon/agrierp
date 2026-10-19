import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/export/document_officiel.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../rapports/rapports_exports_screen.dart' show Editeur;
import 'administration_repository.dart';
import 'archive_modales.dart';
import 'courrier_modales.dart';
import 'document_modales.dart';
import 'documents_administration.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/administration.html` → Administration & Document.
///
/// ⚠️⚠️ **HUB À TROIS ONGLETS**, dans l'ordre du hub : Gestion des Courriers ·
/// Archivage des Documents · Documents Administratifs — chargés en `<iframe>`
/// par la maquette.
///
/// ⚠️⚠️ **LES TROIS ONGLETS S'ÉCRIVENT AU POSTE** : courriers (F0.78), documents archivés
/// (F0.79) et documents administratifs (F0.80) — local d'abord, `pending`, validé par le
/// serveur (qui numérote les courriers). ⚠️ « Générer un Document » n'écrit qu'une LIGNE DE
/// REGISTRE : l'en-tête officielle, la signature et le fichier, le poste ne les a pas.
class AdministrationScreen extends StatefulWidget {
  const AdministrationScreen({
    super.key,
    required this.depot,
    this.imprimer,
    this.maintenant,
  });

  final AdministrationRepository depot;
  final Editeur? imprimer;
  final DateTime Function()? maintenant;

  @override
  State<AdministrationScreen> createState() => _AdministrationScreenState();
}

class _AdministrationScreenState extends State<AdministrationScreen> {
  /// Les trois onglets du hub, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Gestion des Courriers', SymbolesAgri.mail),
    ('Archivage des Documents', SymbolesAgri.inventory),
    ('Documents Administratifs', SymbolesAgri.description),
  ];

  String _onglet = onglets.first.$1;
  DonneesAdministration? _donnees;

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
                        'Archivage des Documents' => _ongletArchives(d, large),
                        'Documents Administratifs' => _ongletDocuments(
                          d,
                          large,
                        ),
                        _ => _ongletCourriers(d, large),
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
              key: Key('onglet-administration-$titre'),
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
                    const SizedBox(width: AgriSpacing.xs),
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

  // ── Onglet 1 : Gestion des Courriers ──────────────────────────────────────

  Widget _ongletCourriers(DonneesAdministration d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Gestion des Courriers', large),
      const SizedBox(height: AgriSpacing.md),
      Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: AgriSpacing.xs,
          runSpacing: AgriSpacing.xs,
          children: [
            _boutonExport(
              'exporter-pdf-courriers',
              () => _exporter(
                DocumentsAdministration.courriers(d.courriers),
                'Aucun courrier à exporter.',
              ),
            ),
            ElevatedButton.icon(
              key: const Key('nouveau-courrier'),
              onPressed: () => _ouvrirCourrier(null),
              icon: const Icon(SymbolesAgri.add_circle, size: 18),
              label: const Text(
                'Nouveau Courrier',
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
      // ⚠️ LES TROIS CARTES DE LA MAQUETTE, avec ses libellés (ticket F0.78). L'ancienne
      // carte « Courriers (mois) » n'existait pas dans `gestion-courriers.html`.
      _grilleKpis(large, [
        CarteKpi(
          libelle: 'Reçus (mois)',
          valeur: '${d.recus}',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.mark_email_read,
        ),
        CarteKpi(
          libelle: 'Envoyés (mois)',
          valeur: '${d.envoyes}',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.send,
        ),
        // ⚠️ UN TIRET, JAMAIS 0 : aucun statut de courrier n'existe en base. « 0 » dirait
        // qu'aucun courrier n'attend de réponse ; le poste ne le sait simplement pas.
        CarteKpi(
          libelle: 'En attente',
          valeur: d.enAttente == null ? '—' : '${d.enAttente}',
          legende: 'Aucun statut de courrier en base',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.pending,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1000,
        colonnes: const [
          ('Référence', 3),
          ('Type', 2),
          ('Objet', 5),
          ('Partie', 3),
          ('Date', 3),
          ('Actions', 2),
        ],
        videWidget: _videCourriers(),
        lignes: [
          for (var i = 0; i < d.courriers.length; i++)
            _ligne(i, [
              (_celluleReference(d, d.courriers[i]), 3),
              (_typeCourrier(d.courriers[i].type), 2),
              (
                Text(
                  d.courriers[i].subject,
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                5,
              ),
              (
                Text(
                  d.courriers[i].party ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              (Text(_date(d.courriers[i].mailDate), style: _cellule), 3),
              (_actionsCourrier(d.courriers[i]), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      _mentionPoste(
        "La référence d'un courrier est attribuée par le serveur : elle "
        "s'affiche après la synchronisation, jamais avant.",
      ),
    ],
  );

  /// Référence du serveur, ou « — » tant que le courrier n'est pas acquitté. Un courrier
  /// écrit ici et pas encore envoyé le dit ; un courrier refusé montre le motif du serveur,
  /// mot pour mot.
  Widget _celluleReference(DonneesAdministration d, Mail c) {
    final refus = d.refusCourriers[c.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.reference ?? '—',
          key: Key('courrier-reference-${c.id}'),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: AgriTypography.gras,
            color: AgriColors.brandEmerald,
          ),
        ),
        if (c.syncStatus == SyncStatus.pending)
          KeyedSubtree(
            key: Key('courrier-a-envoyer-${c.id}'),
            child: _pastille('À envoyer', couleur: AgriColors.accentYellow),
          ),
        if (c.syncStatus == SyncStatus.conflict) ...[
          KeyedSubtree(
            key: Key('courrier-refuse-${c.id}'),
            child: _pastille(
              c.isActive ? 'Refusé' : 'Archivage refusé',
              couleur: AgriColors.errorRed,
            ),
          ),
          if (refus != null)
            Text(
              refus,
              key: Key('courrier-motif-${c.id}'),
              style: const TextStyle(fontSize: 10, color: AgriColors.errorDeep),
            ),
        ],
      ],
    );
  }

  /// Modifier / Archiver — ⚠️ AUCUNE VISIBILITÉ PAR RÔLE n'est décidée ici : le RBAC n'est
  /// pas tranché (seul `admin` atteint cet écran) et le serveur refuse sans le droit
  /// `manage-administration`.
  Widget _actionsCourrier(Mail c) => c.isActive
      ? _boutonsCourrier(c)
      // Archivage refusé : ni modifier ni ré-archiver (la ligne est déjà archivée au poste) ;
      // la remise en file se fait depuis l'écran Synchronisation, une fois la cause corrigée.
      : const SizedBox.shrink();

  Widget _boutonsCourrier(Mail c) => Row(
    children: [
      IconButton(
        key: Key('modifier-courrier-${c.id}'),
        tooltip: 'Modifier',
        visualDensity: VisualDensity.compact,
        onPressed: () => _ouvrirCourrier(c),
        icon: const Icon(SymbolesAgri.edit, size: 18, color: AgriColors.infoBlue),
      ),
      IconButton(
        key: Key('archiver-courrier-${c.id}'),
        tooltip: 'Archiver',
        visualDensity: VisualDensity.compact,
        onPressed: () => _archiverCourrier(c),
        icon: const Icon(SymbolesAgri.archive, size: 18, color: AgriColors.errorDeep),
      ),
    ],
  );

  /// État vide de la maquette (`empty-gestion-courriers`) et son « + Nouveau Courrier ».
  Widget _videCourriers() => Padding(
    key: const Key('courriers-vide'),
    padding: const EdgeInsets.all(AgriSpacing.xl),
    child: Column(
      children: [
        const Icon(SymbolesAgri.inbox, size: 44, color: AgriColors.outlineVariant),
        const SizedBox(height: AgriSpacing.sm),
        const Text(
          'Aucun résultat trouvé',
          style: TextStyle(
            fontSize: AgriTypography.sm,
            fontWeight: AgriTypography.gras,
            color: AgriColors.onSurface,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Essayez un autre terme ou un autre filtre.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        TextButton(
          key: const Key('nouveau-courrier-vide'),
          onPressed: () => _ouvrirCourrier(null),
          child: const Text(
            '+ Nouveau Courrier',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandEmerald,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _ouvrirCourrier(Mail? existant) async {
    final ecrit = await ouvrirFicheCourrier(
      context: context,
      depot: widget.depot,
      existant: existant,
    );
    if (ecrit) await _charger();
  }

  Future<void> _archiverCourrier(Mail c) async {
    final fait = await confirmerArchivageCourrier(
      context: context,
      depot: widget.depot,
      courrier: c,
    );
    if (fait) await _charger();
  }

  Widget _typeCourrier(String type) {
    final entrant = type == 'entrant';

    return _pastille(
      entrant ? 'Entrant' : 'Sortant',
      couleur: entrant ? AgriColors.infoBlue : AgriColors.brandForest,
    );
  }

  // ── Onglet 2 : Archivage des Documents ────────────────────────────────────

  /// Le jour LOCAL du poste, sans heure : la règle de statut du serveur compte en jours
  /// calendaires (F0.79).
  DateTime get _maintenant => widget.maintenant?.call() ?? DateTime.now();

  DateTime _aujourdhui() {
    final n = _maintenant;
    return DateTime(n.year, n.month, n.day);
  }

  /// « Exporter PDF » (ticket F0.82) : édite les lignes AFFICHÉES. ⚠️ Une liste vide n'est pas
  /// éditée : un document réduit à son en-tête ressemble à un rapport « rien à signaler »
  /// alors que le poste n'a simplement rien (même choix que Liste d'Achats, F0.75).
  Future<void> _exporter(DocumentOfficiel document, String vide) async {
    if (document.lignes.isEmpty) {
      _annoncer(vide);
      return;
    }
    final editeur = widget.imprimer;
    if (editeur == null) return;

    // ⚠️ Polices introuvables, imprimante absente, construction du PDF : l'éditeur peut lever.
    // Sans cette capture, l'erreur resterait asynchrone et non gérée, et l'utilisateur
    // n'aurait aucun retour.
    try {
      final message = await editeur(document, _maintenant);
      _annoncer(message ?? 'Document envoyé à l’impression.');
    } catch (_) {
      _annoncer(
        'L’édition du document a échoué. Réessayez ou vérifiez l’imprimante.',
      );
    }
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

  /// Le bouton blanc « Exporter PDF » de l'en-tête des trois onglets (maquette).
  Widget _boutonExport(String cle, VoidCallback onPressed) =>
      OutlinedButton.icon(
        key: Key(cle),
        onPressed: onPressed,
        icon: const Icon(SymbolesAgri.picture_as_pdf, size: 18),
        style: OutlinedButton.styleFrom(
          foregroundColor: AgriColors.brandForest,
          side: const BorderSide(color: AgriColors.outlineVariant),
          shape: const StadiumBorder(),
        ),
        label: const Text(
          'Exporter PDF',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _ongletArchives(DonneesAdministration d, bool large) {
    final jour = _aujourdhui();
    final actives = d.archivesActives;
    final expirees = d.expirees(jour);
    final bientot = d.bientotExpirees(jour);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titre('Archivage des Documents', large),
        const SizedBox(height: AgriSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: AgriSpacing.xs,
            runSpacing: AgriSpacing.xs,
            children: [
              _boutonExport(
                'exporter-pdf-archives',
                () => _exporter(
                  DocumentsAdministration.archives(d.archives, _maintenant),
                  'Aucun document archivé à exporter.',
                ),
              ),
              ElevatedButton.icon(
                key: const Key('nouveau-archive'),
                onPressed: () => _ouvrirArchive(null),
                icon: const Icon(SymbolesAgri.add_circle, size: 18),
                label: const Text(
                  'Archiver un Document',
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
        // ⚠️ LES DEUX CARTES DE LA MAQUETTE (libellés compris, vérifiés par un test qui lit
        // `archivage-documents.html`), PLUS « Expirés » : un agrément DÉJÀ périmé expose la
        // ferme aujourd'hui, la maquette l'ignore, et le confondre avec « Expirant sous 30j »
        // le ferait passer pour un simple rappel (écart assumé, `cartes_attendues.dart`).
        _grilleKpis(large, [
          CarteKpi(
            libelle: 'Documents archivés',
            valeur: '${actives.length}',
            couleurLisere: AgriColors.brandEmerald,
            icone: SymbolesAgri.folder,
          ),
          CarteKpi(
            libelle: 'Expirant sous 30j',
            valeur: '${bientot.length}',
            legende: 'Bientôt expiré : 1 à 30 jours',
            couleurLisere: AgriColors.accentYellow,
            icone: SymbolesAgri.event_busy,
            couleurIcone: AgriColors.brandForest,
          ),
          // ⚠️⚠️ UNE ARCHIVE EXPIRÉE EST UN AGRÉMENT PÉRIMÉ, pas une ligne de tableau : un
          // bail ou un agrément vétérinaire dont l'échéance est atteinte ou passée expose
          // la ferme. C'est l'alerte de cet écran.
          CarteKpi(
            libelle: 'Expirés',
            valeur: '${expirees.length}',
            legende: 'Échéance atteinte ou dépassée',
            couleurLisere: AgriColors.errorRed,
            icone: SymbolesAgri.event_busy,
            couleurIcone: AgriColors.errorRed,
          ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        _tableau(
          largeur: 1000,
          colonnes: const [
            ('Document', 5),
            ('Catégorie', 3),
            ('Date Archivage', 3),
            ('Expiration', 3),
            ('Statut', 3),
            ('Actions', 2),
          ],
          videWidget: _videArchives(),
          lignes: [
            for (var i = 0; i < d.archives.length; i++)
              _ligne(i, [
                (_celluleArchive(d, d.archives[i]), 5),
                (
                  Text(
                    d.archives[i].category ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: _cellule,
                  ),
                  3,
                ),
                (Text(_date(d.archives[i].archivedDate), style: _cellule), 3),
                (_expiration(d.archives[i], jour), 3),
                (_statutArchive(d.archives[i], jour), 3),
                (_actionsArchive(d.archives[i]), 2),
              ]),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _mentionPoste(
          "Le statut d'un document se calcule sur le poste d'après sa date "
          "d'expiration : « Bientôt expiré » de 1 à 30 jours, « Expiré » dès le "
          "jour de l'échéance. Aucun fichier n'est joint : ni la maquette ni le "
          "serveur n'en portent.",
        ),
      ],
    );
  }

  /// Nom du document, avec ce qu'il faut savoir de son envoi : « À envoyer » tant que le
  /// serveur ne l'a pas acquitté, « Refusé » (ou « Archivage refusé » pour un retrait) avec
  /// le motif du serveur MOT POUR MOT.
  Widget _celluleArchive(DonneesAdministration d, ArchivedDocument a) {
    final refus = d.refusArchives[a.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          a.title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: AgriTypography.gras,
          ),
        ),
        if (a.syncStatus == SyncStatus.pending)
          KeyedSubtree(
            key: Key('archive-a-envoyer-${a.id}'),
            child: _pastille('À envoyer', couleur: AgriColors.accentYellow),
          ),
        if (a.syncStatus == SyncStatus.conflict) ...[
          KeyedSubtree(
            key: Key('archive-refuse-${a.id}'),
            child: _pastille(
              a.isActive ? 'Refusé' : 'Archivage refusé',
              couleur: AgriColors.errorRed,
            ),
          ),
          if (refus != null)
            Text(
              refus,
              key: Key('archive-motif-${a.id}'),
              style: const TextStyle(fontSize: 10, color: AgriColors.errorDeep),
            ),
        ],
      ],
    );
  }

  /// Modifier / Archiver — ⚠️ AUCUNE VISIBILITÉ PAR RÔLE n'est décidée ici (RBAC non
  /// tranché ; le serveur refuse sans le droit `manage-administration`).
  Widget _actionsArchive(ArchivedDocument a) => a.isActive
      ? Row(
          children: [
            IconButton(
              key: Key('modifier-archive-${a.id}'),
              tooltip: 'Modifier',
              visualDensity: VisualDensity.compact,
              onPressed: () => _ouvrirArchive(a),
              icon: const Icon(
                SymbolesAgri.edit,
                size: 18,
                color: AgriColors.infoBlue,
              ),
            ),
            IconButton(
              key: Key('archiver-archive-${a.id}'),
              tooltip: 'Archiver',
              visualDensity: VisualDensity.compact,
              onPressed: () => _retirerArchive(a),
              icon: const Icon(
                SymbolesAgri.archive,
                size: 18,
                color: AgriColors.errorDeep,
              ),
            ),
          ],
        )
      // Retrait refusé : déjà retiré au poste ; la remise en file se fait depuis l'écran
      // Synchronisation, une fois la cause corrigée.
      : const SizedBox.shrink();

  /// État vide de la maquette (`empty-archivage-documents`) et son « + Archiver un Document ».
  Widget _videArchives() => Padding(
    key: const Key('archives-vide'),
    padding: const EdgeInsets.all(AgriSpacing.xl),
    child: Column(
      children: [
        const Icon(SymbolesAgri.inbox, size: 44, color: AgriColors.outlineVariant),
        const SizedBox(height: AgriSpacing.sm),
        const Text(
          'Aucun résultat trouvé',
          style: TextStyle(
            fontSize: AgriTypography.sm,
            fontWeight: AgriTypography.gras,
            color: AgriColors.onSurface,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Essayez un autre terme ou un autre filtre.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        TextButton(
          key: const Key('nouveau-archive-vide'),
          onPressed: () => _ouvrirArchive(null),
          child: const Text(
            '+ Archiver un Document',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandEmerald,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _ouvrirArchive(ArchivedDocument? existant) async {
    final ecrit = await ouvrirFicheArchive(
      context: context,
      depot: widget.depot,
      existant: existant,
    );
    if (ecrit) await _charger();
  }

  Future<void> _retirerArchive(ArchivedDocument a) async {
    final fait = await confirmerRetraitArchive(
      context: context,
      depot: widget.depot,
      document: a,
    );
    if (fait) await _charger();
  }

  Widget _expiration(ArchivedDocument a, DateTime jour) {
    if (a.expiryDate == null) return const Text('—', style: _cellule);

    final expire =
        a.isActive &&
        AdministrationRepository.statutArchive(a.expiryDate, jour) ==
            StatutArchive.expire;

    return Text(
      _date(a.expiryDate),
      style: TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: expire ? AgriTypography.gras : AgriTypography.normal,
        color: expire ? AgriColors.errorDeep : AgriColors.onSurface,
      ),
    );
  }

  /// Statut déduit de l'échéance (jamais stocké). Un retrait refusé n'a plus de statut :
  /// « — ».
  Widget _statutArchive(ArchivedDocument a, DateTime jour) {
    if (!a.isActive) return const Text('—', style: _cellule);

    final statut = AdministrationRepository.statutArchive(a.expiryDate, jour);

    return _pastille(
      statut.libelle,
      couleur: switch (statut) {
        StatutArchive.valide => AgriColors.brandEmerald,
        StatutArchive.bientotExpire => AgriColors.accentYellow,
        StatutArchive.expire => AgriColors.errorRed,
      },
    );
  }

  // ── Onglet 3 : Documents Administratifs ───────────────────────────────────

  Widget _ongletDocuments(DonneesAdministration d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titre('Documents Administratifs', large),
      const SizedBox(height: AgriSpacing.md),
      Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: AgriSpacing.xs,
          runSpacing: AgriSpacing.xs,
          children: [
            _boutonExport(
              'exporter-pdf-documents',
              () => _exporter(
                DocumentsAdministration.documents(d.documents),
                'Aucun document à exporter.',
              ),
            ),
            ElevatedButton.icon(
              key: const Key('nouveau-document'),
              onPressed: () => _ouvrirDocument(null),
              icon: const Icon(SymbolesAgri.add_circle, size: 18),
              label: const Text(
                'Générer un Document',
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
      // ⚠️ LES DEUX CARTES DE LA MAQUETTE, avec ses libellés (vérifiés par un test qui lit
      // `documents-administratifs.html`), PLUS « En attente » (signature) : écart assumé,
      // `cartes_attendues.dart`. Les anciennes cartes « Documents » et « Signés » (absentes de
      // la maquette) sont retirées.
      _grilleKpis(large, [
        // ⚠️ UN TIRET, JAMAIS 0 : le poste n'a aucun catalogue de modèles (ni le serveur).
        // « 0 » dirait que la ferme n'en possède aucun ; elle n'a simplement pas de source.
        const CarteKpi(
          libelle: 'Modèles disponibles',
          valeur: '—',
          legende: 'Aucun catalogue de modèles',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.description,
        ),
        CarteKpi(
          libelle: 'Générés (mois)',
          valeur: '${d.generesDuMois}',
          legende: 'Documents enregistrés ce mois',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.edit_note,
        ),
        CarteKpi(
          libelle: 'En attente',
          valeur: '${d.documentsEnAttente}',
          legende: 'Signature du DG',
          couleurLisere: AgriColors.accentYellow,
          icone: SymbolesAgri.pending,
          couleurIcone: AgriColors.brandForest,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1000,
        colonnes: const [
          ('Document', 5),
          ('Type', 3),
          ('Bénéficiaire', 3),
          ('Date', 3),
          ('Statut', 3),
          ('Actions', 2),
        ],
        videWidget: _videDocuments(),
        lignes: [
          for (var i = 0; i < d.documents.length; i++)
            _ligne(i, [
              (_celluleDocument(d, d.documents[i]), 5),
              (
                Text(
                  d.documents[i].type ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              (
                Text(
                  d.documents[i].beneficiary ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              (Text(_date(d.documents[i].docDate), style: _cellule), 3),
              (_statutDocument(d.documents[i]), 3),
              (_actionsDocument(d.documents[i]), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ RISQUE DE PROMESSE TROMPEUSE : le libellé de la maquette dit « Générer », le poste
      // n'écrit qu'une ligne de registre. La mention le dit en toutes lettres.
      _mentionPoste(
        '« Générer un Document » enregistre une ligne au registre (titre, type, '
        'bénéficiaire, date, statut) : le poste ne produit aucun fichier — ni '
        'en-tête officielle, ni signature du DG, ni cachet.',
      ),
    ],
  );

  /// Titre du document, avec ce qu'il faut savoir de son envoi : « À envoyer » tant que le
  /// serveur ne l'a pas acquitté, « Refusé » (ou « Archivage refusé » pour un retrait) avec
  /// le motif du serveur MOT POUR MOT.
  Widget _celluleDocument(DonneesAdministration d, AdministrativeDocument doc) {
    final refus = d.refusDocuments[doc.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          doc.title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: AgriTypography.gras,
          ),
        ),
        if (doc.syncStatus == SyncStatus.pending)
          KeyedSubtree(
            key: Key('document-a-envoyer-${doc.id}'),
            child: _pastille('À envoyer', couleur: AgriColors.accentYellow),
          ),
        if (doc.syncStatus == SyncStatus.conflict) ...[
          KeyedSubtree(
            key: Key('document-refuse-${doc.id}'),
            child: _pastille(
              doc.isActive ? 'Refusé' : 'Archivage refusé',
              couleur: AgriColors.errorRed,
            ),
          ),
          if (refus != null)
            Text(
              refus,
              key: Key('document-motif-${doc.id}'),
              style: const TextStyle(fontSize: 10, color: AgriColors.errorDeep),
            ),
        ],
      ],
    );
  }

  /// Statut de signature. Un retrait refusé n'a plus de statut : « — ».
  Widget _statutDocument(AdministrativeDocument doc) {
    if (!doc.isActive) return const Text('—', style: _cellule);

    return switch (doc.status) {
      AdministrationRepository.statutSigne => _pastille(
        'Signé',
        couleur: AgriColors.brandEmerald,
      ),
      AdministrationRepository.statutEnAttente => _pastille(
        'En attente',
        couleur: AgriColors.accentYellow,
      ),
      _ => const Text('—', style: _cellule),
    };
  }

  /// Modifier / Archiver — ⚠️ AUCUNE VISIBILITÉ PAR RÔLE n'est décidée ici (RBAC non
  /// tranché ; le serveur refuse sans le droit `manage-administration`).
  Widget _actionsDocument(AdministrativeDocument doc) => doc.isActive
      ? Row(
          children: [
            IconButton(
              key: Key('modifier-document-${doc.id}'),
              tooltip: 'Modifier',
              visualDensity: VisualDensity.compact,
              onPressed: () => _ouvrirDocument(doc),
              icon: const Icon(
                SymbolesAgri.edit,
                size: 18,
                color: AgriColors.infoBlue,
              ),
            ),
            IconButton(
              key: Key('archiver-document-${doc.id}'),
              tooltip: 'Archiver',
              visualDensity: VisualDensity.compact,
              onPressed: () => _retirerDocument(doc),
              icon: const Icon(
                SymbolesAgri.archive,
                size: 18,
                color: AgriColors.errorDeep,
              ),
            ),
          ],
        )
      // Retrait refusé : déjà retiré au poste ; la remise en file se fait depuis l'écran
      // Synchronisation, une fois la cause corrigée.
      : const SizedBox.shrink();

  /// État vide de la maquette (`empty-documents-administratifs`) et son
  /// « + Générer un Document ».
  Widget _videDocuments() => Padding(
    key: const Key('documents-vide'),
    padding: const EdgeInsets.all(AgriSpacing.xl),
    child: Column(
      children: [
        const Icon(SymbolesAgri.inbox, size: 44, color: AgriColors.outlineVariant),
        const SizedBox(height: AgriSpacing.sm),
        const Text(
          'Aucun résultat trouvé',
          style: TextStyle(
            fontSize: AgriTypography.sm,
            fontWeight: AgriTypography.gras,
            color: AgriColors.onSurface,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Essayez un autre terme ou un autre filtre.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        TextButton(
          key: const Key('nouveau-document-vide'),
          onPressed: () => _ouvrirDocument(null),
          child: const Text(
            '+ Générer un Document',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandEmerald,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _ouvrirDocument(AdministrativeDocument? existant) async {
    final ecrit = await ouvrirFicheDocument(
      context: context,
      depot: widget.depot,
      existant: existant,
    );
    if (ecrit) await _charger();
  }

  Future<void> _retirerDocument(AdministrativeDocument doc) async {
    final fait = await confirmerRetraitDocument(
      context: context,
      depot: widget.depot,
      document: doc,
    );
    if (fait) await _charger();
  }

  // ── Briques communes ──────────────────────────────────────────────────────

  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.outline,
  );

  Widget _titre(String texte, bool large) => Text(
    texte,
    style: TextStyle(
      fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
      fontWeight: AgriTypography.gras,
      color: AgriColors.onSurface,
    ),
  );

  Widget _pastille(String libelle, {Color couleur = AgriColors.brandEmerald}) =>
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            libelle,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: AgriTypography.gras,
              color: couleur == AgriColors.accentYellow
                  ? AgriColors.brandForest
                  : couleur,
            ),
          ),
        ),
      );

  Widget _grilleKpis(bool large, List<Widget> cartes) => GridView.count(
    crossAxisCount: large ? cartes.length : 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AgriSpacing.md,
    crossAxisSpacing: AgriSpacing.md,
    childAspectRatio: large ? 2.4 : 1.6,
    children: cartes,
  );

  Widget _tableau({
    required double largeur,
    required List<(String, int)> colonnes,
    required List<Widget> lignes,
    required Widget videWidget,
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
                  for (final (libelle, flex) in colonnes)
                    Expanded(
                      flex: flex,
                      child: Text(libelle.toUpperCase(), style: _enteteColonne),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty) videWidget,
            ...lignes,
          ],
        ),
      ),
    ),
  );

  Widget _ligne(int index, List<(Widget, int)> cellules) => Container(
    key: Key('ligne-$index'),
    color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(
      children: [
        for (final (contenu, flex) in cellules)
          Expanded(flex: flex, child: contenu),
      ],
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

  static String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
