import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import 'clients_creances_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// Ouvre « Nouveau Client » (`existant == null`) ou « Modifier le Client ».
///
/// ⚠️⚠️ **L'ENREGISTREMENT EST LOCAL, PUIS SYNCHRONISÉ** (ticket F0.72), comme les produits
/// et les fournisseurs : la fiche est écrite tout de suite, `pending`, et le serveur — qui
/// reste maître de la règle — la valide à la synchronisation. Rien n'exige le réseau.
///
/// ⚠️ **Seul le nom est obligatoire** (règle du web, `CustomerCatalogService`) ; la
/// maquette marque aussi « Téléphone * », le poste suit Laravel et ne le dit pas.
///
/// Retourne `true` si une fiche a été écrite.
Future<bool> ouvrirFicheClient({
  required BuildContext context,
  required ClientsCreancesRepository depot,
  Customer? existant,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) => _ModaleFicheClient(depot: depot, existant: existant),
  );
  return ok == true;
}

/// « Confirmer l'archivage » d'une fiche ([noms] à un nom) ou de plusieurs (le nombre).
/// Retourne `true` si l'archivage a eu lieu.
///
/// ⚠️ **ARCHIVER N'EFFACE RIEN** : la maquette dit « Détruire » et demande un mot de passe
/// administrateur ; le web archive (`is_active = false`) sans mot de passe. Le poste suit
/// le web — il ne supprime jamais, et n'invente pas un contrôle que le serveur n'a pas.
Future<bool> confirmerArchivageClients({
  required BuildContext context,
  required ClientsCreancesRepository depot,
  required List<Customer> clients,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    confirmation: true,
    constructeur: (_) =>
        _ModaleArchivageClients(depot: depot, clients: clients),
  );
  return ok == true;
}

class _ModaleFicheClient extends StatefulWidget {
  const _ModaleFicheClient({required this.depot, required this.existant});

  final ClientsCreancesRepository depot;
  final Customer? existant;

  @override
  State<_ModaleFicheClient> createState() => _ModaleFicheClientState();
}

class _ModaleFicheClientState extends State<_ModaleFicheClient> {
  late final TextEditingController _nom = TextEditingController(
    text: widget.existant?.name ?? '',
  );
  late final TextEditingController _telephone = TextEditingController(
    text: widget.existant?.phone ?? '',
  );
  late final TextEditingController _ville = TextEditingController(
    text: widget.existant?.city ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.existant?.email ?? '',
  );
  Map<String, String> _erreurs = const {};

  bool get _creation => widget.existant == null;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    _ville.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final saisie = FormulaireClient(
      nom: _nom.text,
      telephone: _telephone.text,
      ville: _ville.text,
      email: _email.text,
    );

    final erreurs = ClientsCreancesRepository.validerFiche(saisie);
    if (erreurs.isNotEmpty) {
      setState(() => _erreurs = erreurs);
      return;
    }

    if (_creation) {
      await widget.depot.creerClient(saisie);
    } else {
      await widget.depot.modifierClient(widget.existant!.id, saisie);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _champ(
    String libelle,
    String cle,
    TextEditingController c, {
    String? indice,
    TextInputType? clavier,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          libelle,
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        TextField(
          key: Key('client-$cle'),
          controller: c,
          keyboardType: clavier,
          style: const TextStyle(fontSize: AgriTypography.xs),
          decoration: InputDecoration(
            hintText: indice,
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: _erreurs[cle],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ModaleAgri(
      titre: _creation ? 'Nouveau Client' : 'Modifier le Client',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _champ('Nom complet *', 'nom', _nom, indice: 'ex : AMOUSSOU Régis'),
          _champ(
            'Téléphone',
            'telephone',
            _telephone,
            indice: '+229 ..',
            clavier: TextInputType.phone,
          ),
          _champ('Ville', 'ville', _ville, indice: 'ex : Adja-Ouèrè'),
          _champ(
            'Adresse email',
            'email',
            _email,
            clavier: TextInputType.emailAddress,
          ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BoutonModalePrimaire(
          key: const Key('client-enregistrer'),
          libelle: 'Enregistrer',
          onPressed: _valider,
        ),
      ],
    );
  }
}

class _ModaleArchivageClients extends StatelessWidget {
  const _ModaleArchivageClients({required this.depot, required this.clients});

  final ClientsCreancesRepository depot;
  final List<Customer> clients;

  @override
  Widget build(BuildContext context) {
    // Même texte que le composant du web : une fiche est nommée, plusieurs sont comptées.
    final sujet = clients.length == 1
        ? clients.single.name
        : '${clients.length} client(s) sélectionné(s)';

    return ModaleConfirmation(
      titre: "Confirmer l'archivage",
      message:
          '$sujet sera marqué(e) comme archivé(e) (statut inactif). '
          "Aucune suppression définitive n'est effectuée.",
      icone: SymbolesAgri.archive,
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BoutonModalePrimaire(
          key: const Key('archivage-clients-confirmer'),
          libelle: 'Archiver',
          onPressed: () async {
            await depot.archiverClients([for (final c in clients) c.id]);
            if (context.mounted) Navigator.of(context).pop(true);
          },
        ),
      ],
    );
  }
}
