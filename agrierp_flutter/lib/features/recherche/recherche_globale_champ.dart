import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/theme/agri_tokens.dart';
import 'recherche_globale_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// Ticket H1b — CHAMP DE RECHERCHE GLOBALE de la barre supérieure, transposé de
/// `resources/views/livewire/shared/global-search.blade.php` (le maître) :
/// - champ `w-64` (256 px) `bg-surface-zebra border border-outline-variant rounded-full px-md py-xs`, anneau
///   `ring-brand-emerald` au focus, icône `search` 16 px, placeholder « Recherche globale ERP… (Ctrl+K) » ;
/// - Ctrl+K donne le focus ; recherche après 150 ms dès 2 caractères ; ↑ ↓ Entrée pour choisir, Échap pour fermer ;
///   bouton d'effacement `close` ;
/// - panneau `w-96` (384 px) `max-h-[70vh]` groupé par domaine (étiquette 10 px en capitales, icône 14 px, « (n) »),
///   « Aucun résultat pour « … ». » quand rien ne correspond.
class RechercheGlobaleChamp extends StatefulWidget {
  const RechercheGlobaleChamp({
    super.key,
    required this.depot,
    required this.role,
    required this.onNaviguer,
  });

  final RechercheGlobaleRepository depot;
  final String role;
  final void Function(EcranPoste) onNaviguer;

  @override
  State<RechercheGlobaleChamp> createState() => _RechercheGlobaleChampState();
}

class _RechercheGlobaleChampState extends State<RechercheGlobaleChamp> {
  final _saisie = TextEditingController();
  final _focus = FocusNode();
  final _lien = LayerLink();
  final _panneau = OverlayPortalController();
  Timer? _attente;
  List<DomaineRecherche> _domaines = const [];
  int _actif = -1;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_raccourci);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_raccourci);
    _attente?.cancel();
    _saisie.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Ctrl+K (Cmd+K) : focus et sélection du texte, comme `x-on:keydown.window.ctrl.k`.
  bool _raccourci(KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.keyK &&
        (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed)) {
      _focus.requestFocus();
      _saisie.selection = TextSelection(baseOffset: 0, extentOffset: _saisie.text.length);
      return true;
    }
    return false;
  }

  List<ResultatRecherche> get _aplatis => [for (final d in _domaines) ...d.resultats];

  void _modifie(String texte) {
    setState(() {});
    _attente?.cancel();
    if (texte.trim().length < 2) {
      _fermer();
      return;
    }
    _attente = Timer(const Duration(milliseconds: 150), () async {
      final domaines = await widget.depot.rechercher(texte, widget.role);
      if (!mounted || _saisie.text != texte) return;
      setState(() {
        _domaines = domaines;
        _actif = -1;
      });
      _panneau.show();
    });
  }

  void _fermer() {
    _panneau.hide();
    setState(() {
      _domaines = const [];
      _actif = -1;
    });
  }

  void _choisir(ResultatRecherche r) {
    _fermer();
    _focus.unfocus();
    widget.onNaviguer(r.cible);
  }

  KeyEventResult _clavier(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final n = _aplatis.length;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown && n > 0) {
      setState(() => _actif = (_actif + 1).clamp(0, n - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp && n > 0) {
      setState(() => _actif = (_actif - 1).clamp(0, n - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && _actif >= 0 && _actif < n) {
      _choisir(_aplatis[_actif]);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _fermer();
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static Color _couleur(String c) => switch (c) {
    'emerald' => AgriColors.brandEmerald,
    'blue' => AgriColors.infoBlue,
    // `brand-maize-ink` du web : le jaune lisible sur fond blanc.
    _ => AgriColors.brandForest,
  };

  static IconData _icone(String nom) => switch (nom) {
    'pets' => SymbolesAgri.pets,
    'medication' => SymbolesAgri.medication,
    'point_of_sale' => SymbolesAgri.point_of_sale,
    'person' => SymbolesAgri.person,
    'inventory_2' => SymbolesAgri.inventory_2,
    'local_shipping' => SymbolesAgri.local_shipping,
    'menu_book' => SymbolesAgri.menu_book,
    'account_balance' => SymbolesAgri.account_balance,
    'badge' => SymbolesAgri.badge,
    _ => SymbolesAgri.search,
  };

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _lien,
      child: OverlayPortal(
        controller: _panneau,
        overlayChildBuilder: (_) => _resultats(context),
        child: Focus(
          onKeyEvent: _clavier,
          child: SizedBox(
            key: const Key('recherche-globale'),
            width: 256,
            height: 32,
            child: TextField(
              key: const Key('recherche-globale-saisie'),
              controller: _saisie,
              focusNode: _focus,
              onChanged: _modifie,
              style: const TextStyle(fontSize: AgriTypography.xs),
              decoration: InputDecoration(
                hintText: 'Recherche globale ERP… (Ctrl+K)',
                hintStyle: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
                prefixIcon: const Icon(SymbolesAgri.search, size: 16, color: AgriColors.outline),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
                suffixIcon: _saisie.text.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('recherche-globale-effacer'),
                        iconSize: 14,
                        color: AgriColors.outline,
                        icon: const Icon(SymbolesAgri.close),
                        onPressed: () {
                          _saisie.clear();
                          _fermer();
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor: AgriColors.surfaceZebra,
                contentPadding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AgriRadius.full),
                  borderSide: const BorderSide(color: AgriColors.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AgriRadius.full),
                  borderSide: const BorderSide(color: AgriColors.brandEmerald, width: 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultats(BuildContext context) {
    var index = 0;
    return CompositedTransformFollower(
      link: _lien,
      targetAnchor: Alignment.bottomLeft,
      offset: const Offset(0, AgriSpacing.xs),
      child: Align(
        alignment: Alignment.topLeft,
        child: TapRegion(
          onTapOutside: (_) => _fermer(),
          child: Material(
            key: const Key('recherche-globale-panneau'),
            color: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AgriRadius.lg),
              side: const BorderSide(color: AgriColors.outlineVariant),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 384, minWidth: 384, maxHeight: MediaQuery.sizeOf(context).height * 0.7),
              child: _domaines.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AgriSpacing.md),
                      child: Text(
                        'Aucun résultat pour « ${_saisie.text} ».',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: AgriSpacing.xs),
                      children: [
                        for (final d in _domaines)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.xs),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(_icone(d.icone), size: 14, color: _couleur(d.couleur)),
                                    const SizedBox(width: AgriSpacing.xs),
                                    Text(
                                      '${d.libelle.toUpperCase()} (${d.resultats.length})',
                                      key: Key('recherche-domaine-${d.cle}'),
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _couleur(d.couleur)),
                                    ),
                                  ],
                                ),
                                for (final r in d.resultats) _ligne(r, index++),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ligne(ResultatRecherche r, int i) {
    return InkWell(
      key: Key('recherche-resultat-$i'),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      onTap: () => _choisir(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: AgriSpacing.xs),
        decoration: BoxDecoration(
          color: i == _actif ? AgriColors.surfaceZebra : null,
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Row(
          children: [
            Icon(_icone(r.icone), size: 16, color: r.critique ? AgriColors.errorRed : AgriColors.outline),
            const SizedBox(width: AgriSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.libelle, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.w600)),
                  Text(
                    r.sousLibelle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: r.critique ? AgriColors.errorRed : AgriColors.outline,
                      fontWeight: r.critique ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(SymbolesAgri.chevron_right, size: 14, color: AgriColors.outline),
          ],
        ),
      ),
    );
  }
}
