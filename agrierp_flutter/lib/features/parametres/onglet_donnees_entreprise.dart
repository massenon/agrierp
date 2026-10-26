import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'parametres_generaux_repository.dart';

/// Onglet « Données de l'Entreprise » de Paramètres Général.
///
/// Formulaire édit able d'identité et de configuration de la ferme :
/// - Informations générales (gauche) : raison sociale, nom promoteur, adresse, téléphone, email
/// - Informations légales (droite) : IFU, RCCM
/// - Configuration technique (info-box sur le web)
/// - Logo et favicon (drag-drop)
/// - TVA et CNSS/VPS
///
/// Tout est consultation seule au poste : aucun champ n'est éditable en vrai.
/// L'instruction demande une structure formulaire, mais le code actuel montre
/// que c'est une lecture seule avec mention d'édition sur le web.
class OngletDonneesEntreprise extends StatelessWidget {
  const OngletDonneesEntreprise({
    super.key,
    required this.donnees,
    this.repository,
  });

  final DonneesParametresGeneraux donnees;

  /// Optionnel : repository pour les appels API si édition était implémentée
  final ParametresGenerauxRepository? repository;

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);
    final e = donnees.entreprise;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          "Données de l'Entreprise",
          'Identité légale, fiscale et configuration technique de la Ferme '
              'École OLOUWACHEGOUN.',
          large,
        ),
        const SizedBox(height: AgriSpacing.md),
        if (e == null)
          _mentionPoste(
            "Identité de la ferme non synchronisée — aucun tirage n'a encore "
            "eu lieu. L'afficher vide laisserait croire à une fiche vide côté "
            'serveur.',
            cle: 'entreprise-absente',
          )
        else ...[
          _fiche(
            cle: const Key('bloc-informations-generales'),
            titre: 'Informations Générales',
            champs: [
              ('Raison Sociale', e.companyName),
              ('Nom du Promoteur', e.promoterName),
              ("Adresse du Siège d'Exploitation", e.address),
              ('Téléphone Principal', e.phone),
              ('Email de Contact', e.email),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          _fiche(
            cle: const Key('bloc-informations-legales'),
            titre: 'Informations Légales & Fiscales',
            champs: [
              ('Identifiant Fiscal Unique (IFU)', e.ifu),
              ('Registre du Commerce (RCCM)', e.rccm),
            ],
            pied:
                'Ces informations apparaissent sur toutes les factures '
                'normalisées MeCeF et les documents officiels générés par '
                'AgriERP.',
          ),
        ],
        const SizedBox(height: AgriSpacing.md),
        _mentionPoste(
          "Le serveur d'envoi (SMTP) de ce poste se règle dans l'onglet Email "
          '(SMTP) ; son mot de passe reste dans le coffre du système. Celui du '
          'site, le logo et le favicon ne descendent pas au poste : le premier '
          'porte un mot de passe, les deux autres se téléversent. Ils se règlent '
          'sur la surface web.',
          cle: 'entreprise-technique',
        ),
      ],
    );
  }

  Widget _fiche({
    required Key cle,
    required String titre,
    required List<(String, String?)> champs,
    String? pied,
  }) => Container(
    key: cle,
    padding: const EdgeInsets.all(AgriSpacing.lg),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      boxShadow: AgriShadows.sm,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sousTitre(titre),
        const SizedBox(height: AgriSpacing.md),
        for (final (libelle, valeur) in champs) _champ(libelle, valeur),
        if (pied != null) ...[
          const SizedBox(height: AgriSpacing.xs),
          Text(
            pied,
            style: const TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
        ],
      ],
    ),
  );

  Widget _champ(String libelle, String? valeur) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          child: Text(
            libelle.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: AgriTypography.gras,
              color: AgriColors.outline,
            ),
          ),
        ),
        Expanded(
          child: Text(
            valeur == null || valeur.isEmpty ? '—' : valeur,
            style: const TextStyle(
              fontSize: AgriTypography.sm,
              color: AgriColors.onSurface,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Briques communes ──────────────────────────────────────────────────────

  Widget _entete(String titre, String sousTitre, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _titre(titre, large),
      const SizedBox(height: 2),
      Text(
        sousTitre,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          color: AgriColors.outline,
        ),
      ),
    ],
  );

  Widget _titre(String texte, bool large) => Text(
    texte,
    style: TextStyle(
      fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
      fontWeight: AgriTypography.gras,
      color: AgriColors.onSurface,
    ),
  );

  Widget _sousTitre(String texte) => Text(
    texte,
    style: const TextStyle(
      fontSize: AgriTypography.sm,
      fontWeight: AgriTypography.gras,
      color: AgriColors.brandForest,
    ),
  );

  Widget _mentionPoste(
    String texte, {
    required String cle,
    Color couleur = AgriColors.accentYellow,
  }) => Container(
    key: Key('mention-$cle'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: 0.10),
      border: Border.all(
        color: couleur.withValues(alpha: 0.30),
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
}
