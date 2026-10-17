import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/export/document_officiel.dart';
import 'administration_repository.dart';

/// Documents officiels (PDF) des trois pages du hub Administration — ticket F0.82.
///
/// ⚠️⚠️ **TITRES, SOUS-TITRES, COLONNES ET ORDRE SONT CEUX DES FONCTIONS DE LA MAQUETTE**
/// (`exportCourriersPDF`, `exportDocumentsPDF`, `exportDocAdminPDF`) : un test les relit dans
/// le HTML. Le web n'a pas d'export ; le poste suit la maquette.
///
/// ⚠️ **LES LIGNES EXPORTÉES SONT CELLES AFFICHÉES**, dans l'ordre de l'écran, MOINS ce que
/// l'écran ne montre que pour être corrigé : les enregistrements retirés et les retraits
/// refusés (`isActive = false`) ne sont jamais exportés. Une donnée absente est « — », jamais 0.
/// La maquette n'a pas de colonne « état d'envoi » : aucune n'est ajoutée ; une mention en pied
/// de page dit combien de lignes ne sont pas encore reçues par la ferme.
class DocumentsAdministration {
  const DocumentsAdministration._();

  /// Tiret affiché pour toute information que le poste ne détient pas.
  static const inconnu = '—';

  static String jour(DateTime? d) => d == null
      ? inconnu
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _texte(String? v) =>
      (v == null || v.trim().isEmpty) ? inconnu : v;

  /// Mention de pied : lignes saisies ici, pas encore acquittées par le serveur.
  static List<String> _mentions(
    Iterable<SyncStatus> statuts, {
    String? supplement,
  }) {
    final n = statuts.where((s) => s != SyncStatus.synced).length;
    return [
      ?supplement,
      if (n > 0)
        '$n ligne(s) saisie(s) sur ce poste, pas encore reçue(s) par la ferme '
            '(en attente de synchronisation).',
    ];
  }

  static String? _pied(List<String> mentions) =>
      mentions.isEmpty ? null : mentions.join(' ');

  /// `exportCourriersPDF()`. La référence est attribuée par le serveur : « — » tant que le
  /// courrier n'est pas acquitté.
  static DocumentOfficiel courriers(List<Mail> courriers) {
    final actifs = courriers.where((c) => c.isActive).toList();
    final sansReference = actifs.where((c) => c.reference == null).length;

    return DocumentOfficiel(
      titre: 'Registre des Courriers',
      sousTitre: 'Courriers entrants et sortants',
      entetes: const ['Référence', 'Type', 'Objet', 'Partie', 'Date'],
      lignes: [
        for (final c in actifs)
          DonneesDocument([
            _texte(c.reference),
            c.type == 'entrant' ? 'Entrant' : 'Sortant',
            c.subject,
            _texte(c.party),
            jour(c.mailDate),
          ]),
      ],
      noteDePied: _pied(
        _mentions(
          actifs.map((c) => c.syncStatus),
          supplement: sansReference > 0
              ? "« — » en Référence : le serveur l'attribue à la synchronisation."
              : null,
        ),
      ),
    );
  }

  /// `exportDocumentsPDF()`. Le statut se déduit de l'échéance, à la date [maintenant]
  /// (règle du serveur, `AdministrationRepository.statutArchive`).
  static DocumentOfficiel archives(
    List<ArchivedDocument> archives,
    DateTime maintenant,
  ) {
    final actifs = archives.where((a) => a.isActive).toList();
    final aujourdhui = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
    );

    return DocumentOfficiel(
      titre: 'Archivage des Documents',
      sousTitre: 'Documents administratifs, juridiques et fiscaux archivés',
      entetes: const [
        'Document',
        'Catégorie',
        'Date Archivage',
        'Expiration',
        'Statut',
      ],
      lignes: [
        for (final a in actifs)
          DonneesDocument([
            a.title,
            _texte(a.category),
            jour(a.archivedDate),
            jour(a.expiryDate),
            AdministrationRepository.statutArchive(
              a.expiryDate,
              aujourdhui,
            ).libelle,
          ]),
      ],
      noteDePied: _pied(_mentions(actifs.map((a) => a.syncStatus))),
    );
  }

  /// `exportDocAdminPDF()`. ⚠️ Aucun fichier n'est produit : c'est la liste du registre.
  static DocumentOfficiel documents(List<AdministrativeDocument> documents) {
    final actifs = documents.where((d) => d.isActive).toList();

    return DocumentOfficiel(
      titre: 'Documents Administratifs Générés',
      sousTitre: 'Attestations, certificats et correspondances',
      entetes: const ['Document', 'Type', 'Bénéficiaire', 'Date', 'Statut'],
      lignes: [
        for (final d in actifs)
          DonneesDocument([
            d.title,
            _texte(d.type),
            _texte(d.beneficiary),
            jour(d.docDate),
            switch (d.status) {
              AdministrationRepository.statutSigne => 'Signé',
              AdministrationRepository.statutEnAttente => 'En attente',
              _ => inconnu,
            },
          ]),
      ],
      noteDePied: _pied(_mentions(actifs.map((d) => d.syncStatus))),
    );
  }
}
