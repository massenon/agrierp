import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/fichiers_entreprise.dart';
import '../theme/symboles_agri.dart';

/// Ticket CONF-1 — LE LOGO CHOISI DE L'ENTREPRISE dans l'interface du poste (barre latérale, écran de connexion), comme le
/// composant Blade `<x-logo-entreprise>` du web : le logo de Paramètres > Données de l'Entreprise (gardé par `FichiersEntreprise`,
/// posé au poste ou tiré du serveur), sinon l'icône d'installation.
///
/// Se redessine quand le fichier change (`FichiersEntreprise.version`). Jamais bloquant : une lecture impossible (dossier
/// absent, plugin indisponible en test) laisse l'icône. ⚠️ Le favicon n'a pas d'équivalent ici : le poste n'a pas d'onglet,
/// son icône de fenêtre est celle de l'installateur (`outils/generer_icone.py`).
class LogoEntreprise extends StatefulWidget {
  const LogoEntreprise({super.key, required this.taille, required this.couleurRepli});

  final double taille;
  final Color couleurRepli;

  @override
  State<LogoEntreprise> createState() => _LogoEntrepriseState();
}

class _LogoEntrepriseState extends State<LogoEntreprise> {
  Uint8List? _octets;

  @override
  void initState() {
    super.initState();
    FichiersEntreprise.version.addListener(_charger);
    _charger();
  }

  @override
  void dispose() {
    FichiersEntreprise.version.removeListener(_charger);
    super.dispose();
  }

  Future<void> _charger() async {
    Uint8List? octets;
    try {
      octets = await FichiersEntreprise.courant.lire('logo');
    } catch (_) {
      octets = null;
    }
    if (mounted) setState(() => _octets = octets);
  }

  @override
  Widget build(BuildContext context) {
    final octets = _octets;
    final repli = Icon(SymbolesAgri.agriculture, color: widget.couleurRepli, size: widget.taille);
    if (octets == null) return repli;
    return Image.memory(
      octets,
      key: const Key('logo-entreprise'),
      width: widget.taille,
      height: widget.taille,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => repli,
    );
  }
}
