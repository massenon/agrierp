import 'package:flutter/material.dart';

import '../../core/database/app_database.dart' show Customer;
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import 'clients_creances_repository.dart';
import 'fiche_client_modales.dart';
import 'recouvrement_modale.dart';

/// Ticket VC-3 — `Livewire\Ventes\ProfileClient` (`profile-client.blade.php`) au poste : « Profil Client ».
///
/// Fiche gauche (initiales, nom, téléphone, « Solde Global Dû », barre de crédit, trois boutons) et quatre onglets
/// à droite : Ventes · Créances · Avances & Acomptes · Relances. Le poste écrit le FAIT (règlement, relance) ;
/// les soldes affichés sont NETS de ce qu'il a saisi et que le serveur n'a pas encore appliqué.
class ProfilClientPage extends StatefulWidget {
  const ProfilClientPage({super.key, required this.depot, required this.clientId, required this.onRetour});

  final ClientsCreancesRepository depot;
  final String clientId;

  /// « Retour » vers la liste ; reçoit `true` si quelque chose a été écrit (la liste se recharge).
  final void Function(bool modifie) onRetour;

  @override
  State<ProfilClientPage> createState() => _ProfilClientPageState();
}

class _ProfilClientPageState extends State<ProfilClientPage> {
  static const _onglets = ['Ventes', 'Créances', 'Avances & Acomptes', 'Relances'];

  ProfilClient? _profil;
  String _onglet = 'Ventes';
  bool _modifie = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final p = await widget.depot.profil(widget.clientId);
    if (!mounted) return;
    setState(() => _profil = p);
  }

  Future<DonneesClients> _donnees() => widget.depot.charger();

  void _annoncer(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: AgriTypography.xs)),
        backgroundColor: AgriColors.brandEmerald,
      ),
    );
  }

  Future<void> _modifierFiche(Customer c) async {
    final ecrit = await ouvrirFicheClient(context: context, depot: widget.depot, existant: c);
    if (!ecrit) return;
    _modifie = true;
    await _charger();
  }

  /// `openGlobalRegularisation` : règlement du solde GLOBAL, imputé aux plus anciennes créances d'abord.
  Future<void> _reglementGlobal(ProfilClient p) async {
    final donnees = await _donnees();
    if (!mounted) return;
    final ecrit = await ouvrirRecouvrement(
      context: context,
      depot: widget.depot,
      donnees: donnees,
      titre: 'Enregistrer un Règlement',
      libelleReference: 'Référence',
      clientGlobal: p.client.id,
      soldeGlobal: p.soldeGlobal,
    );
    if (!ecrit) return;
    _modifie = true;
    await _charger();
    _annoncer('Règlement enregistré — il sera appliqué à la prochaine synchronisation.');
  }

  /// `openReceivableRegularisation` : règlement d'UNE créance.
  Future<void> _reglerCreance(LigneCreance l) async {
    final donnees = await _donnees();
    if (!mounted) return;
    final ecrit = await ouvrirRecouvrement(
      context: context,
      depot: widget.depot,
      donnees: donnees,
      depart: l,
      titre: 'Enregistrer un Règlement',
      libelleReference: 'Référence',
    );
    if (!ecrit) return;
    _modifie = true;
    await _charger();
    _annoncer('Règlement enregistré — il sera appliqué à la prochaine synchronisation.');
  }

  /// `sendQuickReminder` : relance WhatsApp pré-remplie, sans créance visée.
  Future<void> _relanceRapide(ProfilClient p) async {
    try {
      await widget.depot.relancer(
        clientId: p.client.id,
        canal: 'whatsapp',
        message: 'Relance rapide — solde dû ${DocumentsAvances.formaterMontant(p.soldeGlobal)} FCFA.',
      );
    } on SaisieRefusee catch (e) {
      _annoncer(e.motif);
      return;
    }
    _modifie = true;
    await _charger();
    _annoncer('Relance enregistrée — elle partira à la prochaine synchronisation.');
  }

  static String _f(double v) => DocumentsAvances.formaterMontant(v);

  static String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final p = _profil;
    if (p == null) return const Center(child: CircularProgressIndicator());

    final large = AgriBreakpoints.large(context);
    final gauche = _fiche(p);
    final droite = _panneau(p);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('profil-retour'),
            onPressed: () => widget.onRetour(_modifie),
            icon: const Icon(SymbolesAgri.arrow_back, size: 16),
            label: const Text('Retour', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
          ),
        ),
        const Text(
          'Profil Client',
          style: TextStyle(fontSize: AgriTypography.xl, fontWeight: FontWeight.bold, color: AgriColors.onSurface),
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Fiche complète, historique et créances du tiers.',
          style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.lg),
        if (large)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 35, child: gauche),
              const SizedBox(width: AgriSpacing.md),
              Expanded(flex: 65, child: droite),
            ],
          )
        else ...[
          gauche,
          const SizedBox(height: AgriSpacing.md),
          droite,
        ],
      ],
    );
  }

  Widget _carte({required Widget enfant, EdgeInsets? marge}) => Container(
    padding: marge ?? const EdgeInsets.all(AgriSpacing.lg),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: enfant,
  );

  Widget _fiche(ProfilClient p) {
    final c = p.client;
    final initiales = c.name
        .split(' ')
        .where((m) => m.isNotEmpty)
        .take(2)
        .map((m) => m.substring(0, 1))
        .join()
        .toUpperCase();
    final pct = p.pourcentageCredit;

    return _carte(
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: CircleAvatar(
              radius: 32,
              backgroundColor: AgriColors.brandEmerald,
              child: Text(
                initiales,
                key: const Key('profil-initiales'),
                style: const TextStyle(color: Colors.white, fontSize: AgriTypography.xl, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          Text(
            c.name,
            key: const Key('profil-nom'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, color: AgriColors.brandForest),
          ),
          Text(
            c.phone ?? '—',
            key: const Key('profil-telephone'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
          ),
          const SizedBox(height: AgriSpacing.md),
          Container(
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(color: AgriColors.surfaceZebra, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                const Text(
                  'SOLDE GLOBAL DÛ',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgriColors.outline),
                ),
                Text(
                  '${_f(p.soldeGlobal)} FCFA',
                  key: const Key('profil-solde'),
                  style: const TextStyle(fontSize: AgriTypography.xl, fontWeight: FontWeight.w800, color: AgriColors.errorRed),
                ),
              ],
            ),
          ),
          if (pct != null) ...[
            const SizedBox(height: AgriSpacing.md),
            Container(
              padding: const EdgeInsets.all(AgriSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: AgriColors.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LIMITE DE CRÉDIT',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgriColors.outline),
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      key: const Key('profil-barre-credit'),
                      value: pct / 100,
                      minHeight: 8,
                      backgroundColor: AgriColors.surfaceZebra,
                      color: AgriColors.brandEmerald,
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  Text(
                    '${_f(p.soldeGlobal)} FCFA utilisés sur ${_f(c.creditLimit)} FCFA autorisés ($pct%)',
                    key: const Key('profil-credit'),
                    style: const TextStyle(fontSize: 10, color: AgriColors.outline),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AgriSpacing.md),
          OutlinedButton(
            key: const Key('profil-modifier'),
            onPressed: () => _modifierFiche(c),
            child: const Text('Modifier la fiche', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: AgriSpacing.xs),
          ElevatedButton(
            key: const Key('profil-reglement'),
            onPressed: () => _reglementGlobal(p),
            style: ElevatedButton.styleFrom(backgroundColor: AgriColors.brandEmerald, foregroundColor: Colors.white),
            child: const Text('Enregistrer un règlement', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: AgriSpacing.xs),
          OutlinedButton(
            key: const Key('profil-relance-rapide'),
            onPressed: () => _relanceRapide(p),
            style: OutlinedButton.styleFrom(foregroundColor: AgriColors.brandEmerald),
            child: const Text('Envoyer une relance rapide', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _panneau(ProfilClient p) => _carte(
    marge: const EdgeInsets.all(AgriSpacing.md),
    enfant: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AgriColors.outlineVariant))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final o in _onglets)
                  InkWell(
                    key: Key('profil-onglet-$o'),
                    onTap: () => setState(() => _onglet = o),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 2,
                            color: _onglet == o ? AgriColors.brandEmerald : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Text(
                        o,
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          fontWeight: FontWeight.bold,
                          color: _onglet == o ? AgriColors.brandEmerald : AgriColors.outline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        switch (_onglet) {
          'Créances' => _creances(p),
          'Avances & Acomptes' => _avances(p),
          'Relances' => _relances(p),
          _ => _ventes(p),
        },
      ],
    ),
  );

  static const _petit = TextStyle(fontSize: AgriTypography.xs);
  static const _entete = TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline);

  Widget _vide(String texte, Key cle) => Padding(
    padding: const EdgeInsets.all(AgriSpacing.md),
    child: Center(child: Text(texte, key: cle, style: _entete)),
  );

  Widget _ligneTable(int i, List<(Widget, int)> cellules) => Container(
    color: i.isOdd ? AgriColors.surfaceZebra : null,
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Row(children: [for (final (w, flex) in cellules) Expanded(flex: flex, child: w)]),
  );

  Widget _teteTable(List<(String, int)> titres) => Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AgriColors.outlineVariant))),
    child: Row(children: [for (final (t, flex) in titres) Expanded(flex: flex, child: Text(t, style: _entete))]),
  );

  String _facture(String? venteId, String repli) => (venteId ?? repli).substring(0, 8).toUpperCase();

  Widget _ventes(ProfilClient p) {
    if (p.ventes.isEmpty) return _vide('Aucune vente pour ce client.', const Key('profil-ventes-vide'));
    return Column(
      children: [
        _teteTable(const [('Facture', 2), ('Date', 2), ('Articles', 4), ('Montant', 2), ('Statut', 2)]),
        for (final (i, v) in p.ventes.indexed)
          _ligneTable(i, [
            (Text(_facture(v.vente.id, v.vente.id), key: Key('profil-vente-$i'), style: _petit), 2),
            (Text(_date(v.vente.soldAt), style: _petit), 2),
            (Text(v.articles, style: _petit), 4),
            (Text(_f(v.vente.total), style: _petit, textAlign: TextAlign.right), 2),
            (
              v.vente.paymentMode == 'credit'
                  ? const Text('Crédit', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: AgriColors.errorRed))
                  : const Text('Payée', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: AgriColors.brandEmerald)),
              2,
            ),
          ]),
      ],
    );
  }

  Widget _creances(ProfilClient p) {
    if (p.creances.isEmpty) return _vide('Aucune créance en cours.', const Key('profil-creances-vide'));
    final jour = DateTime.now();
    return Column(
      children: [
        _teteTable(const [('Facture', 2), ('Échéance', 2), ('Ancienneté', 2), ('Solde Dû', 2), ('Actions', 2)]),
        for (final (i, l) in p.creances.indexed)
          _ligneTable(i, [
            (Text(_facture(l.creance.saleId, l.creance.id), style: _petit), 2),
            (Text(l.creance.dueDate == null ? '—' : _date(l.creance.dueDate!), style: _petit), 2),
            (
              Text(
                l.retard(jour) == null ? '—' : '${l.retard(jour)!.abs()} jours',
                style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: AgriColors.errorRed),
              ),
              2,
            ),
            (
              Text(
                _f(l.resteDu),
                key: Key('profil-creance-solde-$i'),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: AgriColors.errorRed),
              ),
              2,
            ),
            (
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  key: Key('profil-regler-$i'),
                  onTap: () => _reglerCreance(l),
                  child: const Text(
                    'Régler',
                    style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold, color: AgriColors.brandEmerald),
                  ),
                ),
              ),
              2,
            ),
          ]),
      ],
    );
  }

  Widget _avances(ProfilClient p) {
    if (p.avances.isEmpty) return _vide('Aucun acompte en cours pour ce client.', const Key('profil-avances-vide'));
    return Column(
      children: [
        for (final (i, a) in p.avances.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AgriColors.outlineVariant))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${_date(a.avance.advanceDate)} — ${_f(a.avance.amount)} FCFA',
                    key: Key('profil-avance-$i'),
                    style: _petit,
                  ),
                ),
                Text('Restant : ${_f(a.soldeRestant)} FCFA', style: _entete),
              ],
            ),
          ),
      ],
    );
  }

  Widget _relances(ProfilClient p) {
    if (p.relances.isEmpty) return _vide('Aucune relance envoyée à ce client.', const Key('profil-relances-vide'));
    return Column(
      children: [
        _teteTable(const [('Canal', 2), ('Date', 2), ('Message', 6)]),
        for (final (i, r) in p.relances.indexed)
          _ligneTable(i, [
            (
              Text(
                switch (r.channel) {
                  'whatsapp' => 'WhatsApp',
                  'email' => 'Email',
                  _ => 'SMS',
                },
                key: Key('profil-relance-canal-$i'),
                style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold),
              ),
              2,
            ),
            (Text(_date(r.reminderDate), style: _petit), 2),
            (Text(r.message ?? '', style: _petit), 6),
          ]),
      ],
    );
  }
}
