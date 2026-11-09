import 'package:flutter/material.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/theme/agri_tokens.dart';
import 'aide_a_propos_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/aide-a-propos.html` → Aide & À Propos.
///
/// ⚠️ **PAGE DE DOCUMENTATION : AUCUNE DONNÉE, AUCUN TIRAGE.** Le contenu vient
/// d'[AideAProposRepository]. Elle fonctionne donc identiquement hors ligne.
///
/// ⚠️ **LES QUESTIONS S'OUVRENT INDÉPENDAMMENT**, comme `toggleFaq` du
/// prototype : ouvrir la troisième ne referme pas la première. La surface web
/// (Alpine, `openIndex`) fait, elle, un accordéon à une seule question ouverte ;
/// le prototype l'emporte sur le visuel et le comportement.
///
/// ⚠️ **UNE CARTE DE MODULE QUE LE RÔLE NE PEUT PAS OUVRIR EST ATTÉNUÉE ET
/// INERTE**, comme les entrées de la barre latérale. Le prototype montre les
/// douze à tous et laisse le refus à l'arrivée ; ici on évite d'envoyer le
/// caissier sur un « accès refusé » plein écran.
///
/// ⚠️ **LE LIEN « CONTACTEZ L'ÉDITEUR » N'EST RENDU QUE SI SON ÉCRAN EXISTE**
/// (`onContact` fourni) : un lien mort serait pire qu'un lien absent.
class AideAProposScreen extends StatefulWidget {
  const AideAProposScreen({
    super.key,
    required this.onOuvrir,
    required this.peutOuvrir,
    this.onContact,
  });

  /// Ouvre l'écran d'un module.
  final void Function(EcranPoste) onOuvrir;

  /// Le rôle courant peut-il ouvrir cet écran ?
  final bool Function(EcranPoste) peutOuvrir;

  /// Ouvre « Contactez l'Éditeur ». `null` : l'écran n'existe pas encore.
  final VoidCallback? onContact;

  @override
  State<AideAProposScreen> createState() => _AideAProposScreenState();
}

class _AideAProposScreenState extends State<AideAProposScreen> {
  static const _icones = <EcranPoste, IconData>{
    EcranPoste.tableauDeBord: SymbolesAgri.dashboard,
    EcranPoste.gestionElevage: SymbolesAgri.pets,
    EcranPoste.soinsEtVaccins: SymbolesAgri.vaccines,
    EcranPoste.ventesEtDevis: SymbolesAgri.point_of_sale,
    EcranPoste.clientsEtCreances: SymbolesAgri.payments,
    EcranPoste.achatsEtCommandes: SymbolesAgri.local_shipping,
    EcranPoste.gestionStocks: SymbolesAgri.inventory_2,
    EcranPoste.facturation: SymbolesAgri.receipt_long,
    EcranPoste.personnelEtStages: SymbolesAgri.badge,
    EcranPoste.comptabilite: SymbolesAgri.account_balance,
    EcranPoste.administrationEtDocument: SymbolesAgri.folder_shared,
    EcranPoste.rapportsEtExports: SymbolesAgri.picture_as_pdf,
  };

  final _recherche = TextEditingController();

  /// Indices (dans la liste COMPLÈTE) des questions ouvertes.
  final _ouvertes = <int>{};

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);
    final colonnes = large
        ? 3
        : AgriBreakpoints.petit(context)
        ? 2
        : 1;
    final retenues = AideAProposRepository.rechercher(_recherche.text);

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _entete(large),
            const SizedBox(height: AgriSpacing.lg),
            _cartePresentation(AgriBreakpoints.moyen(context)),
            const SizedBox(height: AgriSpacing.lg),
            _titreSection('Modules du Logiciel'),
            const SizedBox(height: AgriSpacing.md),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: AideAProposRepository.modules.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: colonnes,
                mainAxisSpacing: AgriSpacing.md,
                crossAxisSpacing: AgriSpacing.md,
                // ⚠️ 168 px : la plus longue description (Gestion Élevage) tient
                // sur quatre lignes à 3 colonnes. À 132 px elle était TRONQUÉE par
                // des points de suspension — vu à la capture, pas au test.
                mainAxisExtent: 168,
              ),
              itemBuilder: (_, i) => _carteModule(i),
            ),
            const SizedBox(height: AgriSpacing.xl),
            _titreSection('Foire Aux Questions'),
            const SizedBox(height: AgriSpacing.md),
            _champRecherche(),
            const SizedBox(height: AgriSpacing.md),
            _listeQuestions(retenues),
            if (widget.onContact != null) ...[
              const SizedBox(height: AgriSpacing.xl),
              Center(
                child: InkWell(
                  key: const Key('aide-contact'),
                  onTap: widget.onContact,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        SymbolesAgri.support_agent,
                        size: 18,
                        color: AgriColors.brandEmerald,
                      ),
                      SizedBox(width: AgriSpacing.xs),
                      Text(
                        "Vous ne trouvez pas de réponse ? Contactez l'éditeur",
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          fontWeight: AgriTypography.gras,
                          color: AgriColors.brandEmerald,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _entete(bool large) => Container(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(SymbolesAgri.help, size: 26, color: AgriColors.brandEmerald),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              'Aide & À Propos',
              style: TextStyle(
                fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
                fontWeight: AgriTypography.gras,
                color: AgriColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Documentation complète, guide des modules et foire aux questions.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    ),
  );

  BoxDecoration get _carte => BoxDecoration(
    color: AgriColors.surfaceCard,
    border: Border.all(color: AgriColors.outlineVariant),
    borderRadius: BorderRadius.circular(AgriRadius.lg),
  );

  Widget _cartePresentation(bool ligne) {
    final texte = Column(
      crossAxisAlignment: ligne
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text.rich(
          const TextSpan(
            children: [
              TextSpan(
                text: 'LogiAgriERP ',
                style: TextStyle(
                  fontSize: AgriTypography.lg,
                  fontWeight: FontWeight.w900,
                  color: AgriColors.brandForest,
                ),
              ),
              TextSpan(
                text: 'v${AideAProposRepository.version}',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ],
          ),
          key: const Key('aide-version'),
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          AideAProposRepository.descriptionLogiciel,
          key: Key('aide-description'),
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          AideAProposRepository.couvertureLogiciel,
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    );

    const icone = Icon(
      SymbolesAgri.agriculture,
      size: 64,
      color: AgriColors.brandEmerald,
    );

    return Container(
      key: const Key('aide-presentation'),
      padding: const EdgeInsets.all(AgriSpacing.lg),
      decoration: _carte,
      child: ligne
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                icone,
                const SizedBox(width: AgriSpacing.lg),
                Expanded(child: texte),
              ],
            )
          : Column(
              children: [
                icone,
                const SizedBox(height: AgriSpacing.lg),
                texte,
              ],
            ),
    );
  }

  Widget _titreSection(String texte) => Text(
    texte.toUpperCase(),
    style: const TextStyle(
      fontSize: AgriTypography.sm,
      fontWeight: AgriTypography.gras,
      color: AgriColors.brandForest,
    ),
  );

  Widget _carteModule(int i) {
    final m = AideAProposRepository.modules[i];
    final ouvrable = widget.peutOuvrir(m.ecran);

    return Opacity(
      opacity: ouvrable ? 1 : 0.45,
      child: InkWell(
        key: Key('aide-module-$i'),
        onTap: ouvrable ? () => widget.onOuvrir(m.ecran) : null,
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: _carte,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icones[m.ecran], size: 26, color: AgriColors.brandEmerald),
              const SizedBox(height: AgriSpacing.xs),
              Text(
                m.titre,
                style: const TextStyle(
                  fontSize: AgriTypography.sm,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandForest,
                ),
              ),
              const SizedBox(height: AgriSpacing.xs),
              Expanded(
                child: Text(
                  m.description,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 5,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _champRecherche() => Container(
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: _carte,
    child: TextField(
      key: const Key('faq-recherche'),
      controller: _recherche,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: AgriTypography.sm),
      decoration: InputDecoration(
        hintText: "Rechercher dans l'aide (ex : facture, stock, paie...)",
        hintStyle: const TextStyle(fontSize: AgriTypography.sm),
        prefixIcon: const Icon(SymbolesAgri.search, size: 18),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          borderSide: const BorderSide(color: AgriColors.outlineVariant),
        ),
      ),
    ),
  );

  Widget _listeQuestions(List<QuestionAide> retenues) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
    decoration: _carte,
    child: Column(
      children: [
        for (final q in retenues)
          _question(AideAProposRepository.questions.indexOf(q), q),
        if (retenues.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AgriSpacing.lg),
            child: Text(
              'Aucun résultat pour cette recherche.',
              key: Key('faq-vide'),
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _question(int i, QuestionAide q) {
    final ouverte = _ouvertes.contains(i);

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: Key('faq-$i'),
            onTap: () => setState(
              () => ouverte ? _ouvertes.remove(i) : _ouvertes.add(i),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AgriSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      q.question,
                      style: const TextStyle(
                        fontSize: AgriTypography.sm,
                        fontWeight: FontWeight.w600,
                        color: AgriColors.brandForest,
                      ),
                    ),
                  ),
                  Icon(
                    ouverte ? SymbolesAgri.expand_less : SymbolesAgri.expand_more,
                    color: AgriColors.outline,
                  ),
                ],
              ),
            ),
          ),
          if (ouverte)
            Padding(
              padding: const EdgeInsets.only(bottom: AgriSpacing.md),
              child: Text(
                q.reponse,
                key: Key('faq-reponse-$i'),
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
