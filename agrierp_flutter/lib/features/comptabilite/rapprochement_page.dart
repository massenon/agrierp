import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/database/app_database.dart' show ChartOfAccount;
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/champs_date_agri.dart';
import 'documents_comptabilite.dart';
import 'rapprochement_repository.dart';

/// Un relevé choisi : son nom, son texte et sa taille.
typedef ReleveChoisi = ({String nom, String contenu, int octets});

/// Sélecteur de fichier par défaut : un CSV ou un texte, lu en UTF-8 (injecté en test).
Future<ReleveChoisi?> choisirReleveCsv() async {
  final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt'], dialogTitle: 'Importer un relevé (CSV)');
  if (r == null || r.files.isEmpty || r.files.first.path == null) return null;
  final octets = await File(r.files.first.path!).readAsBytes();
  return (nom: r.files.first.name, contenu: utf8.decode(octets, allowMalformed: true), octets: octets.length);
}

/// Ticket CP-5 — `Livewire\Comptabilite\RapprochementBancaire` (carte « Rapprochement Bancaire » du hub). Même structure que le
/// Blade : import du relevé, compte et période, quatre cartes, bandeau d'équilibre, deux tableaux (livre / relevé), note du
/// lettrage automatique. Le calcul est celui du serveur (parité exécutée) ; l'import est une DEMANDE.
class RapprochementPage extends StatefulWidget {
  const RapprochementPage({super.key, required this.depot, required this.maintenant, this.choisirReleve = choisirReleveCsv});

  final RapprochementRepository depot;
  final DateTime Function() maintenant;
  final Future<ReleveChoisi?> Function() choisirReleve;

  @override
  State<RapprochementPage> createState() => _RapprochementPageState();
}

class _RapprochementPageState extends State<RapprochementPage> {
  List<ChartOfAccount>? _comptes;
  String _compte = '';
  late DateTime _debut = DateTime(widget.maintenant().year, widget.maintenant().month, 1);
  late DateTime _fin = DateTime(widget.maintenant().year, widget.maintenant().month, widget.maintenant().day);
  Rapprochement? _resultat;
  ReleveChoisi? _fichier;
  String? _message;
  Map<String, String> _erreurs = const {};
  List<({dynamic demande, String? motif})> _imports = const [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final comptes = await widget.depot.comptes();
    if (_compte.isEmpty && comptes.isNotEmpty) _compte = comptes.first.id;
    final imports = await widget.depot.importsEnAttente();
    final r = _compte.isEmpty ? null : await widget.depot.rapprocher(_compte, _debut, _fin);
    if (!mounted) return;
    setState(() {
      _comptes = comptes;
      _resultat = r;
      _imports = imports;
    });
  }

  static String _m(double v) => DocumentsComptabilite.montant(v);

  Future<void> _lancer() async {
    final f = _fichier;
    try {
      await widget.depot.importerReleve(compteId: _compte, contenu: f?.contenu ?? '', octets: f?.octets ?? 0, nomFichier: f?.nom);
      _fichier = null;
      _erreurs = const {};
      _message = 'Relevé envoyé au serveur : ses lignes apparaîtront à la prochaine synchronisation.';
    } on RapprochementRefuse catch (e) {
      _erreurs = e.erreurs;
    }
    await _charger();
  }

  @override
  Widget build(BuildContext context) {
    final comptes = _comptes;
    if (comptes == null) return const Padding(padding: EdgeInsets.all(AgriSpacing.lg), child: Center(child: CircularProgressIndicator()));
    final r = _resultat;
    final large = AgriBreakpoints.large(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Icon(SymbolesAgri.sync_alt, size: 26, color: AgriColors.brandEmerald),
          const SizedBox(width: AgriSpacing.xs),
          Expanded(child: Text('Rapprochement Bancaire', style: TextStyle(fontSize: large ? AgriTypography.xxl : AgriTypography.xl, fontWeight: AgriTypography.gras, color: AgriColors.onSurface))),
          ElevatedButton.icon(
            key: const Key('rapprochement-importer'),
            onPressed: () async {
              final f = await widget.choisirReleve();
              if (f != null) setState(() => _fichier = f);
            },
            icon: const Icon(SymbolesAgri.upload_file, size: 18),
            style: ElevatedButton.styleFrom(backgroundColor: AgriColors.brandEmerald, foregroundColor: Colors.white, shape: const StadiumBorder()),
            label: const Text('Importer un Relevé (CSV)', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        if (_fichier != null)
          Container(
            key: const Key('rapprochement-fichier'),
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(AgriRadius.lg)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Fichier prêt : ${_fichier!.nom} — format attendu date;libellé;montant, montant signé.', style: const TextStyle(fontSize: AgriTypography.xs)),
              if (_erreurs['releve'] != null) Text(_erreurs['releve']!, key: const Key('rapprochement-erreur-releve'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
              const SizedBox(height: AgriSpacing.xs),
              Row(children: [
                ElevatedButton(key: const Key('rapprochement-lancer'), onPressed: _lancer, child: const Text("Lancer l'import")),
                const SizedBox(width: AgriSpacing.sm),
                TextButton(key: const Key('rapprochement-annuler'), onPressed: () => setState(() => _fichier = null), child: const Text('Annuler')),
              ]),
            ]),
          ),
        if (_message != null) Text(_message!, key: const Key('rapprochement-message'), style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
        for (final i in _imports)
          Padding(
            padding: const EdgeInsets.only(top: AgriSpacing.xs),
            child: Text(
              i.motif == null ? 'Import en attente de synchronisation : ${i.demande.fileName ?? 'relevé'}.' : 'Import refusé par le serveur (${i.demande.fileName ?? 'relevé'}) : ${i.motif}',
              key: Key('rapprochement-import-${i.demande.id}'),
              style: TextStyle(fontSize: 11, color: i.motif == null ? AgriColors.outline : AgriColors.errorDeep),
            ),
          ),
        const SizedBox(height: AgriSpacing.md),
        Wrap(
          spacing: AgriSpacing.md,
          runSpacing: AgriSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 320,
              child: comptes.isEmpty
                  ? const Text('Aucun compte de trésorerie au plan comptable', key: Key('rapprochement-aucun-compte'), style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline))
                  : DropdownButtonFormField<String>(
                      key: const Key('rapprochement-compte'),
                      initialValue: _compte,
                      isDense: true,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Compte :'),
                      items: [for (final c in comptes) DropdownMenuItem(value: c.id, child: Text('${c.code} — ${c.label}', overflow: TextOverflow.ellipsis))],
                      onChanged: (v) async {
                        _compte = v ?? '';
                        await _charger();
                      },
                    ),
            ),
            SizedBox(
              width: 180,
              child: ChampDateFormulaire(
                cle: const Key('rapprochement-debut'),
                etiquette: 'Du',
                valeur: _debut,
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _debut, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) {
                    _debut = d;
                    await _charger();
                  }
                },
              ),
            ),
            SizedBox(
              width: 180,
              child: ChampDateFormulaire(
                cle: const Key('rapprochement-fin'),
                etiquette: 'au',
                valeur: _fin,
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _fin, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) {
                    _fin = d;
                    await _charger();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        if (r != null) ...[
          GrilleKpi(colonnes: large ? 4 : 2, children: [
            CarteKpi(key: const Key('kpi-rapprochement-livre'), libelle: 'Solde Livre (Grand Livre)', valeur: '${_m(r.soldeLivre)} F', couleurLisere: AgriColors.brandEmerald),
            CarteKpi(key: const Key('kpi-rapprochement-releve'), libelle: 'Solde Relevé Bancaire', valeur: '${_m(r.soldeReleve)} F', couleurLisere: AgriColors.infoBlue),
            CarteKpi(key: const Key('kpi-rapprochement-instance'), libelle: 'Opérations en Instance', valeur: '${_m(r.enInstance.abs())} F', couleurLisere: AgriColors.accentYellow),
            CarteKpi(
              key: const Key('kpi-rapprochement-ecart'),
              libelle: 'Écart (doit être 0)',
              valeur: '${_m(r.ecart)} F',
              couleurLisere: r.equilibre ? AgriColors.brandEmerald : AgriColors.errorRed,
              couleurValeur: r.equilibre ? AgriColors.brandEmerald : AgriColors.errorDeep,
            ),
          ]),
          const SizedBox(height: AgriSpacing.sm),
          Text(
            r.equilibre
                ? 'Rapprochement équilibré — Solde Livre corrigé des opérations en instance et des lignes non saisies = Solde Relevé.'
                : 'Rapprochement déséquilibré — écart de ${_m(r.ecart)} F à justifier avant toute clôture.',
            key: const Key('rapprochement-bandeau'),
            style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: r.equilibre ? AgriColors.brandEmerald : AgriColors.errorDeep),
          ),
          const SizedBox(height: AgriSpacing.md),
          _tableau('Grand Livre', r.livre, 'En Instance', 'Aucune écriture sur ce compte pour la période.', 'livre'),
          const SizedBox(height: AgriSpacing.md),
          _tableau('Relevé Bancaire Importé', r.releve, 'Nouveau — À Saisir', 'Aucun relevé importé pour ce compte sur la période.', 'releve'),
        ],
        const SizedBox(height: AgriSpacing.md),
        Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(color: AgriColors.surfaceZebra, border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(AgriRadius.lg)),
          child: const Text(
            "Lettrage automatique : une écriture et une ligne de relevé sont appariées lorsqu'elles portent le même montant à moins de ${RapprochementRepository.toleranceJours} jours d'écart — le délai normal de traitement bancaire. Chaque ligne n'est appariée qu'une seule fois, afin qu'un doublon réel ne puisse jamais être masqué par un double lettrage.",
            style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
          ),
        ),
      ],
    );
  }

  Widget _tableau(String titre, List<LigneRapprochement> lignes, String libelleNonPointe, String vide, String cle) => Container(
    decoration: BoxDecoration(color: AgriColors.surfaceCard, border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(AgriRadius.lg)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(color: AgriColors.surfaceZebra, padding: const EdgeInsets.all(AgriSpacing.sm), child: Text(titre, style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: AgriTypography.gras, color: AgriColors.brandForest))),
      Container(
        color: AgriColors.surfaceZebra,
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.xs),
        child: Row(children: [
          for (final (l, f, a) in const [('Date', 2, TextAlign.left), ('Libellé', 5, TextAlign.left), ('Montant', 3, TextAlign.right), ('Statut', 3, TextAlign.center)])
            Expanded(flex: f, child: Text(l.toUpperCase(), textAlign: a, style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.outline))),
        ]),
      ),
      if (lignes.isEmpty) Padding(padding: const EdgeInsets.all(AgriSpacing.lg), child: Text(vide, key: Key('rapprochement-vide-$cle'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline))),
      for (var i = 0; i < lignes.length; i++)
        Container(
          key: Key('rapprochement-$cle-$i'),
          color: i.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
          child: Row(children: [
            Expanded(flex: 2, child: Text(DocumentsComptabilite.jour(lignes[i].date), style: const TextStyle(fontSize: AgriTypography.xs))),
            Expanded(flex: 5, child: Text(lignes[i].libelle, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AgriTypography.xs))),
            Expanded(flex: 3, child: Text(_m(lignes[i].montant), textAlign: TextAlign.right, style: const TextStyle(fontSize: AgriTypography.xs))),
            Expanded(flex: 3, child: Text(lignes[i].pointee ? 'Pointé' : libelleNonPointe, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: lignes[i].pointee ? AgriColors.brandEmerald : AgriColors.errorDeep))),
          ]),
        ),
    ]),
  );
}
