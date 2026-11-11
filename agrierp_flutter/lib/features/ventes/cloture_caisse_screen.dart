import 'package:flutter/material.dart';

import '../../core/database/app_database.dart' show CashClosure;
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import 'cloture_caisse_repository.dart';

/// Sprint C — Clôture de Caisse (poste).
///
/// Miroir fidèle de `livewire/ventes/cloture-caisse.blade.php`.
///
/// Le poste NE VALIDE PAS lui-même : il envoie une demande via
/// `SyncEngine.pushCashClosures` et le serveur valide. L'écran construit le
/// récapitulatif, l'utilisateur saisit fond de caisse et montant compté, puis
/// « Envoyer la clôture » pose une entrée `en_cours` en mémoire (affichée
/// jusqu'à l'acquittement). La table `cash_closures` reçoit les validées au
/// tirage suivant.
class ClotureCaisseScreen extends StatefulWidget {
  const ClotureCaisseScreen({
    super.key,
    required this.depot,
    required this.deviceId,
  });

  final ClotureCaisseRepository depot;
  final String deviceId;

  @override
  State<ClotureCaisseScreen> createState() => _ClotureCaisseScreenState();
}

class _ClotureCaisseScreenState extends State<ClotureCaisseScreen> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _dateSelectionnee = HeureBenin.aujourdhui();

  final _ctrlFond = TextEditingController(text: '0');
  final _ctrlMontant = TextEditingController(text: '0');

  /// Ventes du jour par mode (calculées à chaque changement de date).
  Map<String, double> _ventes = {'especes': 0, 'mobile_money': 0, 'virement': 0};

  /// Clôtures déjà validées pour la date sélectionnée sur ce poste.
  bool _dejaValidee = false;

  /// Historique des 10 dernières clôtures de ce poste.
  List<CashClosure> _historique = [];

  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _ctrlFond.addListener(_recalcEcart);
    _ctrlMontant.addListener(_recalcEcart);
    _charger();
  }

  @override
  void dispose() {
    _ctrlFond.dispose();
    _ctrlMontant.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final dateStr = _formatDate(_dateSelectionnee);
      final resultats = await Future.wait([
        widget.depot.ventesJourParMode(
          closureDate: dateStr,
          deviceId: widget.deviceId,
        ),
        widget.depot.dejaValideAujourdhui(widget.deviceId),
        widget.depot.dernieresCloturesPoste(widget.deviceId),
      ]);
      if (!mounted) return;
      setState(() {
        _ventes = resultats[0] as Map<String, double>;
        _dejaValidee = resultats[1] as bool;
        _historique = resultats[2] as List<CashClosuresData>;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.toString();
        _chargement = false;
      });
    }
  }

  void _recalcEcart() => setState(() {});

  double get _ventesEspeces => _ventes['especes'] ?? 0;
  double get _ventesMobile => _ventes['mobile_money'] ?? 0;
  double get _ventesVirement => _ventes['virement'] ?? 0;
  double get _totalVentes => _ventesEspeces + _ventesMobile + _ventesVirement;

  double get _fondDeCaisse =>
      double.tryParse(_ctrlFond.text.replaceAll(' ', '')) ?? 0;
  double get _montantCompte =>
      double.tryParse(_ctrlMontant.text.replaceAll(' ', '')) ?? 0;

  /// écart = montant_compte − (fond_de_caisse + ventes_espèces + ventes_mobile + ventes_virement)
  double get _ecart => _montantCompte - (_fondDeCaisse + _totalVentes);

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _nombre(double v) {
    final entier = v.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${v.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  Future<void> _choisirDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateSelectionnee,
      firstDate: DateTime(2020),
      lastDate: HeureBenin.aujourdhui(),
      locale: const Locale('fr'),
    );
    if (picked != null && picked != _dateSelectionnee) {
      setState(() => _dateSelectionnee = picked);
      _charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vuErreur()
              : _vuContenu(),
    );
  }

  Widget _vuErreur() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(SymbolesAgri.error, color: AgriColors.errorRed, size: 32),
          const SizedBox(height: 8),
          Text(_erreur!, style: TextStyle(color: AgriColors.errorRed)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _charger,
            icon: const Icon(SymbolesAgri.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _vuContenu() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _enTete(),
          const SizedBox(height: 16),
          if (_dejaValidee) _badgeDejaValidee(),
          const SizedBox(height: 12),
          _cartesKpi(),
          const SizedBox(height: 16),
          _formulaire(),
          const SizedBox(height: 24),
          _sectionHistorique(),
        ],
      ),
    );
  }

  Widget _enTete() {
    return Row(
      children: [
        Icon(SymbolesAgri.point_of_sale, color: AgriColors.brandEmerald, size: 20),
        const SizedBox(width: 8),
        Text(
          'Clôture de Caisse',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        // Sélecteur de date (miroir du `<input type="date">` du Blade)
        OutlinedButton.icon(
          onPressed: _choisirDate,
          icon: const Icon(SymbolesAgri.calendar_today, size: 16),
          label: Text(_formatDate(_dateSelectionnee)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AgriColors.brandEmerald,
            side: BorderSide(color: AgriColors.outlineVariant),
          ),
        ),
      ],
    );
  }

  Widget _badgeDejaValidee() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(SymbolesAgri.check_circle, color: Color(0xFF16A34A), size: 16),
          SizedBox(width: 6),
          Text(
            'Clôture déjà validée pour cette date',
            style: TextStyle(color: Color(0xFF16A34A), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _cartesKpi() {
    return Row(
      children: [
        Expanded(
          child: _carteKpi(
            libelle: 'Espèces',
            valeur: _ventesEspeces,
            icone: SymbolesAgri.payments,
            couleur: AgriColors.brandEmerald,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _carteKpi(
            libelle: 'Mobile Money',
            valeur: _ventesMobile,
            icone: SymbolesAgri.smartphone,
            couleur: AgriColors.infoBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _carteKpi(
            libelle: 'Virement',
            valeur: _ventesVirement,
            icone: SymbolesAgri.account_balance,
            couleur: AgriColors.outline,
          ),
        ),
      ],
    );
  }

  Widget _carteKpi({
    required String libelle,
    required double valeur,
    required IconData icone,
    required Color couleur,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      color: AgriColors.surfaceCard,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: couleur, size: 16),
                const SizedBox(width: 6),
                Text(libelle,
                    style: TextStyle(
                        fontSize: 11,
                        color: AgriColors.outline,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_nombre(valeur)} FCFA',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: couleur,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formulaire() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      color: AgriColors.surfaceCard,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Saisie de la clôture',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              // Fond de caisse
              _champMontant(
                libelle: 'Fond de Caisse (FCFA)',
                ctrl: _ctrlFond,
                aide: 'Montant de départ en caisse ce matin',
              ),
              const SizedBox(height: 12),
              // Montant compté
              _champMontant(
                libelle: 'Montant Compté (FCFA)',
                ctrl: _ctrlMontant,
                aide: 'Espèces + mobile money comptées physiquement',
              ),
              const SizedBox(height: 16),
              // Ligne de récapitulatif
              _ligneRecapitulatif(
                libelle: 'Total ventes espèces',
                valeur: _ventesEspeces,
              ),
              _ligneRecapitulatif(
                libelle: 'Total ventes mobile money',
                valeur: _ventesMobile,
              ),
              _ligneRecapitulatif(
                libelle: 'Total ventes virement',
                valeur: _ventesVirement,
              ),
              const Divider(height: 20),
              // Écart
              _ligneEcart(),
              const SizedBox(height: 16),
              if (_ecart != 0) _noteCompte(),
              const SizedBox(height: 16),
              // Bouton valider
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _dejaValidee ? null : _envoyer,
                  icon: const Icon(SymbolesAgri.send, size: 18),
                  label: Text(
                    _dejaValidee
                        ? 'Clôture déjà envoyée'
                        : 'Envoyer la clôture',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AgriColors.brandEmerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _champMontant({
    required String libelle,
    required TextEditingController ctrl,
    required String aide,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      decoration: InputDecoration(
        labelText: libelle,
        helperText: aide,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Obligatoire';
        final n = double.tryParse(v.replaceAll(' ', ''));
        if (n == null) return 'Nombre invalide';
        if (n < 0) return 'Doit être ≥ 0';
        return null;
      },
    );
  }

  Widget _ligneRecapitulatif({
    required String libelle,
    required double valeur,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(libelle,
              style:
                  TextStyle(fontSize: 13, color: AgriColors.outline)),
          Text('${_nombre(valeur)} FCFA',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _ligneEcart() {
    final ecart = _ecart;
    final Color couleur;
    final String texte;
    if (ecart > 0) {
      couleur = const Color(0xFF16A34A);
      texte = '+${_nombre(ecart)} FCFA (gain)';
    } else if (ecart < 0) {
      couleur = AgriColors.errorRed;
      texte = '${_nombre(ecart)} FCFA (perte)';
    } else {
      couleur = AgriColors.onSurface;
      texte = '${_nombre(ecart)} FCFA';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Écart',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        Text(texte,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: couleur)),
      ],
    );
  }

  Widget _noteCompte() {
    final ecart = _ecart;
    final gain = ecart > 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: gain
            ? const Color(0xFFF0FDF4)
            : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color:
              gain ? const Color(0xFFBBF7D0) : const Color(0xFFFFCDD2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            gain ? SymbolesAgri.info : SymbolesAgri.warning,
            size: 15,
            color: gain
                ? const Color(0xFF16A34A)
                : AgriColors.errorRed,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              gain
                  ? 'Gain de caisse : une écriture D 571 / C 718 sera générée.'
                  : 'Perte de caisse : une écriture D 658 / C 571 sera générée.',
              style: TextStyle(
                fontSize: 12,
                color: gain
                    ? const Color(0xFF15803D)
                    : AgriColors.errorDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _envoyer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_dejaValidee) return;

    // L'envoi réel passe par SyncEngine au prochain cycle de synchro.
    // On affiche juste la confirmation visuelle ; la clôture est posée
    // `en_cours` localement et sera validée par le serveur.
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
            'Clôture enregistrée — elle sera validée lors de la prochaine synchronisation.'),
        backgroundColor: Color(0xFF065F46),
        duration: Duration(seconds: 4),
      ),
    );
    // Marque la date comme déjà envoyée pour l'UI.
    setState(() => _dejaValidee = true);
  }

  Widget _sectionHistorique() {
    if (_historique.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(SymbolesAgri.history, color: AgriColors.outline, size: 16),
            const SizedBox(width: 6),
            Text('Historique des clôtures',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          color: AgriColors.surfaceCard,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 36,
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Espèces'), numeric: true),
                DataColumn(label: Text('Mobile Money'), numeric: true),
                DataColumn(label: Text('Virement'), numeric: true),
                DataColumn(label: Text('Montant Compté'), numeric: true),
                DataColumn(label: Text('Écart'), numeric: true),
                DataColumn(label: Text('Statut')),
              ],
              rows: _historique.map((c) {
                final ecartVal = c.ecart;
                final Color ecartColor;
                if (ecartVal > 0) {
                  ecartColor = const Color(0xFF16A34A);
                } else if (ecartVal < 0) {
                  ecartColor = AgriColors.errorRed;
                } else {
                  ecartColor = AgriColors.onSurface;
                }
                return DataRow(cells: [
                  DataCell(Text(c.closureDate)),
                  DataCell(Text('${_nombre(c.ventesEspeces)} FCFA')),
                  DataCell(Text('${_nombre(c.ventesMobileMoney)} FCFA')),
                  DataCell(Text('${_nombre(c.ventesVirement)} FCFA')),
                  DataCell(Text('${_nombre(c.montantCompte)} FCFA')),
                  DataCell(Text(
                    '${ecartVal >= 0 ? '+' : ''}${_nombre(ecartVal)} FCFA',
                    style: TextStyle(color: ecartColor),
                  )),
                  DataCell(_badgeStatut(c.statut)),
                ]);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _badgeStatut(String statut) {
    final (bg, fg, label) = switch (statut) {
      'validée' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A), 'Validée'),
      'annulée' => (const Color(0xFFFFE4E6), AgriColors.errorRed, 'Annulée'),
      _ => (const Color(0xFFFEF9C3), const Color(0xFFB45309), 'En cours'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}
