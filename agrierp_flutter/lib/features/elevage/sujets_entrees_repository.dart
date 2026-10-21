import 'package:drift/drift.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../stocks/pmp_service.dart';
import 'fiche_journaliere_repository.dart';

/// Saisie d'une entrée de sujets refusée AVANT toute écriture : un message par champ, ceux du web. Clés = les
/// propriétés du composant : `species_id`, `lot_id`, `origine`, `quantite`, `entry_date`, et `entry` (l'entrée n'existe plus).
class SujetRefuse implements Exception {
  const SujetRefuse(this.erreurs);

  final Map<String, String> erreurs;

  @override
  String toString() => erreurs.values.join(' ');
}

/// Ce que l'exploitant a saisi dans « Nouveau Sujet » / « Modifier le Sujet ».
class FormulaireSujet {
  const FormulaireSujet({
    this.speciesId = '',
    this.lotId = '',
    this.origine = '',
    this.quantite = '1',
    this.date,
  });

  final String speciesId;
  final String lotId;
  final String origine;

  /// Texte du champ « Quantité * » (`public int $quantite = 1`) : vide = 0.
  final String quantite;
  final DateTime? date;
}

/// Une ligne du journal : UNE ORIGINE d'une fiche du jour.
class LigneSujet {
  const LigneSujet({
    required this.fiche,
    required this.origine,
    required this.quantite,
    required this.codeBande,
    required this.especeLibelle,
    this.motifRefus,
  });

  final LivestockDailyEntry fiche;
  final String origine;
  final int quantite;
  final String? codeBande;
  final String? especeLibelle;

  /// Motif du serveur, mot pour mot, quand la dernière envoi de cette fiche a été refusé (`conflict`).
  final String? motifRefus;
}

class IndicateursSujets {
  const IndicateursSujets({required this.naissancesMois, required this.acquisitionsMois, required this.effectifTotal});

  final int naissancesMois;
  final int acquisitionsMois;
  final int effectifTotal;
}

/// Ticket BS2 — « Enregistrer des Sujets » du poste : miroir de `App\Livewire\Elevage\EnregistrerSujets` et de
/// `App\Actions\SaisieSujetAction`.
///
/// Une ligne du journal est UNE ORIGINE d'une fiche du jour (Naissance → `ne`, Achat → `achat`, Don → `don`). Ajouter
/// AJOUTE la quantité à la colonne de la fiche (bande, jour) ; modifier la change (quantité, origine, jour) ; archiver
/// la RETIRE (colonne remise à 0, la ligne quitte le journal, la fiche est gardée).
///
/// ⚠️ **UN SEUL ÉCRIVAIN DES FICHES** : tout passe par [FicheJournaliereRepository.ecrireEntrees] — refus d'exercice
/// clos, remise en file (`pending`), cascade unique des effectifs. Le serveur reçoit la fiche (`livestock_daily_entries`,
/// dernier écrivain gagne) et refait sa propre cascade : aucune table nouvelle, aucune règle recopiée.
///
/// ⚠️ Un effectif qui deviendrait NÉGATIF un jour suivant refuse le geste, tout est annulé (la formule le ramènerait à 0
/// en silence).
class SujetsEntreesRepository {
  SujetsEntreesRepository({required AppDatabase database, required FicheJournaliereRepository fiches, DateTime Function()? horloge})
    : _db = database,
      // ignore: prefer_initializing_formals
      _fiches = fiches,
      _horloge = horloge ?? HeureBenin.maintenant;

  final AppDatabase _db;
  final FicheJournaliereRepository _fiches;
  final DateTime Function() _horloge;

  /// Origine → colonne de la fiche (`SaisieSujetAction::ORIGINES`).
  static const origines = {'Naissance': 'ne', 'Achat': 'achat', 'Don': 'don'};

  /// `SaisieSujetAction::MESSAGE_INTROUVABLE`, mot pour mot.
  static const messageIntrouvable = "Cette entrée n'existe plus : elle a déjà été modifiée ou archivée.";

  /// Toasts de `EnregistrerSujets`, mot pour mot.
  static const toastEnregistree = 'Enregistrement effectué avec succès.';
  static const toastModifiee = 'Modification enregistrée avec succès.';
  static const toastArchivee = 'Entrée archivée avec succès.';

  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

  static int _de(LivestockDailyEntry f, String origine) => switch (origine) {
    'Naissance' => f.ne,
    'Achat' => f.achat,
    _ => f.don,
  };

  // ── Lecture ──────────────────────────────────────────────────────────────────────────────────────────────────────

  Future<IndicateursSujets> indicateurs() async {
    final maintenant = _horloge();
    final debut = DateTime(maintenant.year, maintenant.month);
    final fin = DateTime(maintenant.year, maintenant.month + 1);
    final duMois = await (_db.select(_db.livestockDailyEntries)
          ..where((t) => t.entryDate.isBiggerOrEqualValue(debut) & t.entryDate.isSmallerThanValue(fin)))
        .get();
    final vivantes = await (_db.select(_db.livestockLots)
          ..where((t) => t.status.equals('actif') & t.isActive.equals(true)))
        .get();
    return IndicateursSujets(
      naissancesMois: duMois.fold<int>(0, (s, f) => s + f.ne),
      acquisitionsMois: duMois.fold<int>(0, (s, f) => s + f.achat),
      effectifTotal: vivantes.fold<int>(0, (s, b) => s + b.currentQuantity),
    );
  }

  /// `getSpeciesOptionsProperty()` : espèces dont le module est actif, par libellé.
  Future<List<EspeceElevage>> especes() async {
    final actifs = {
      for (final m in await _db.select(_db.modulesConfig).get())
        if (m.isEnabled) m.speciesCode,
    };
    return [
      for (final e in await _db.select(_db.livestockSpecies).get())
        if (actifs.contains(e.code)) e,
    ]..sort((a, b) => cleCommeLeServeur(a.label).compareTo(cleCommeLeServeur(b.label)));
  }

  /// `getLotOptionsProperty()` : bandes de l'espèce, `status = actif` ET non archivées, par code.
  Future<List<LivestockLot>> bandes(String speciesId) async {
    if (speciesId.isEmpty) return const [];
    return (_db.select(_db.livestockLots)
          ..where((t) => t.speciesId.equals(speciesId) & t.status.equals('actif') & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.code)]))
        .get();
  }

  /// `getEntriesProperty()` : les 50 fiches les plus récentes portant un achat, une naissance ou un don, UNE LIGNE PAR
  /// ORIGINE > 0. [statut] : `Naissance` ou `Achat` (vide : toutes).
  Future<List<LigneSujet>> entrees({String recherche = '', String statut = ''}) async {
    final bandes = {for (final b in await _db.select(_db.livestockLots).get()) b.id: b};
    final especes = {for (final e in await _db.select(_db.livestockSpecies).get()) e.id: e};
    final refus = {
      for (final c in await (_db.select(_db.syncConflicts)..where((t) => t.sourceTable.equals('livestock_daily_entries'))).get())
        c.recordId: c.reason,
    };
    final filtre = cleCommeLeServeur(recherche);

    final fiches = [
      for (final f in await _db.select(_db.livestockDailyEntries).get())
        if ((f.achat > 0 || f.ne > 0 || f.don > 0) &&
            (recherche.isEmpty || cleCommeLeServeur(bandes[f.lotId]?.code ?? '').contains(filtre)) &&
            (statut != 'Naissance' || f.ne > 0) &&
            (statut != 'Achat' || f.achat > 0))
          f,
    ]..sort((a, b) {
        final c = b.entryDate.compareTo(a.entryDate);
        return c != 0 ? c : a.id.compareTo(b.id);
      });

    return [
      for (final f in fiches.take(50))
        for (final origine in origines.keys)
          if (_de(f, origine) > 0 && (statut.isEmpty || statut == origine))
            LigneSujet(
              fiche: f,
              origine: origine,
              quantite: _de(f, origine),
              codeBande: bandes[f.lotId]?.code,
              especeLibelle: especes[bandes[f.lotId]?.speciesId]?.label,
              motifRefus: f.syncStatus == SyncStatus.conflict ? refus[f.id] : null,
            ),
    ];
  }

  // ── Écriture ─────────────────────────────────────────────────────────────────────────────────────────────────────

  static int? _quantite(String texte) {
    final t = texte.trim();
    return t.isEmpty ? 0 : int.tryParse(t);
  }

  /// Les trois règles communes de `saveEntry()` / `updateEntry()` : `origine` `required|in:Naissance,Achat,Don`,
  /// `quantite` `required|integer|min:1`, `entry_date` `required|date`. Messages de `lang/fr/validation.php`.
  static Map<String, String> _validerSaisie(FormulaireSujet f) {
    final e = <String, String>{};
    if (f.origine.isEmpty) {
      e['origine'] = 'Le champ origine est obligatoire.';
    } else if (!origines.containsKey(f.origine)) {
      e['origine'] = "La valeur sélectionnée pour le champ origine n'est pas valide.";
    }
    final q = _quantite(f.quantite);
    if (q == null) {
      e['quantite'] = 'Le champ quantité doit être un nombre entier.';
    } else if (q < 1) {
      e['quantite'] = 'Le champ quantité doit être au moins égal à 1.';
    }
    if (f.date == null) e['entry_date'] = "Le champ date d'entrée est obligatoire.";
    return e;
  }

  /// Les règles de `saveEntry()` (espèce et bande en plus). Vide si tout est valable.
  static Map<String, String> valider(FormulaireSujet f, {bool especeConnue = true, bool bandeConnue = true}) {
    final e = <String, String>{};
    if (f.speciesId.isEmpty) {
      e['species_id'] = 'Le champ espèce est obligatoire.';
    } else if (!especeConnue) {
      e['species_id'] = "La valeur sélectionnée pour le champ espèce n'existe pas.";
    }
    if (f.lotId.isEmpty) {
      e['lot_id'] = 'Le champ bande est obligatoire.';
    } else if (!bandeConnue) {
      e['lot_id'] = "La valeur sélectionnée pour le champ bande n'existe pas.";
    }
    return {...e, ..._validerSaisie(f)};
  }

  /// `saveEntry()` : AJOUTE la quantité à la colonne de l'origine de la fiche (bande, jour).
  Future<LivestockDailyEntry> ajouter(FormulaireSujet f) async {
    final erreurs = valider(
      f,
      especeConnue: f.speciesId.isEmpty || await (_db.select(_db.livestockSpecies)..where((t) => t.id.equals(f.speciesId))).getSingleOrNull() != null,
      bandeConnue: f.lotId.isEmpty || await (_db.select(_db.livestockLots)..where((t) => t.id.equals(f.lotId))).getSingleOrNull() != null,
    );
    if (erreurs.isNotEmpty) throw SujetRefuse(erreurs);

    final jour = _jour(f.date!);
    await ExerciceDeSaisie(_db, maintenant: _horloge).refuser(jour, regle: RegleExercice.closSeulement);

    return _db.transaction(() async {
      final fiche = await _ajouterSurLaFiche(f.lotId, f.origine, _quantite(f.quantite)!, jour);
      await _refuserSiEffectifNegatif(f.lotId, jour);
      return fiche;
    });
  }

  /// `updateEntry()` : change la quantité, l'origine et/ou le jour de la ligne [origineAncienne] de la fiche [ficheId].
  Future<LivestockDailyEntry> modifier(String ficheId, String origineAncienne, FormulaireSujet f) async {
    final erreurs = _validerSaisie(f);
    if (erreurs.isNotEmpty) throw SujetRefuse(erreurs);

    final ancienne = await _ficheAvecEntree(ficheId, origineAncienne);
    final jourAncien = _jour(ancienne.entryDate);
    final jour = _jour(f.date!);
    final exercice = ExerciceDeSaisie(_db, maintenant: _horloge);
    await exercice.refuser(jourAncien, regle: RegleExercice.closSeulement);
    await exercice.refuser(jour, regle: RegleExercice.closSeulement);

    final quantite = _quantite(f.quantite)!;
    return _db.transaction(() async {
      LivestockDailyEntry fiche;
      if (jourAncien == jour && origineAncienne == f.origine) {
        // Même cellule : la quantité REMPLACE l'ancienne (ajouter la doublerait).
        fiche = await _ecrire(ancienne.lotId, jour, {f.origine: quantite});
      } else {
        await _ecrire(ancienne.lotId, jourAncien, {origineAncienne: 0});
        fiche = await _ajouterSurLaFiche(ancienne.lotId, f.origine, quantite, jour);
      }
      await _refuserSiEffectifNegatif(ancienne.lotId, jourAncien.isBefore(jour) ? jourAncien : jour);
      return fiche;
    });
  }

  /// `archiveEntry()` : RETIRE l'entrée (colonne remise à 0) ; la fiche est gardée avec ses autres colonnes.
  Future<void> archiver(String ficheId, String origine) async {
    final fiche = await _ficheAvecEntree(ficheId, origine);
    final jour = _jour(fiche.entryDate);
    await ExerciceDeSaisie(_db, maintenant: _horloge).refuser(jour, regle: RegleExercice.closSeulement);

    await _db.transaction(() async {
      await _ecrire(fiche.lotId, jour, {origine: 0});
      await _refuserSiEffectifNegatif(fiche.lotId, jour);
    });
  }

  /// La fiche [ficheId] dont l'[origine] porte une quantité > 0, sinon « entrée introuvable ».
  Future<LivestockDailyEntry> _ficheAvecEntree(String ficheId, String origine) async {
    final fiche = origines.containsKey(origine)
        ? await (_db.select(_db.livestockDailyEntries)..where((t) => t.id.equals(ficheId))).getSingleOrNull()
        : null;
    if (fiche == null || _de(fiche, origine) <= 0) throw const SujetRefuse({'entry': messageIntrouvable});
    return fiche;
  }

  /// La quantité ajoutée à la colonne de l'origine (le code historique de `saveEntry`).
  Future<LivestockDailyEntry> _ajouterSurLaFiche(String lotId, String origine, int quantite, DateTime jour) async {
    final existante = await _fiches.chargerJour(lotId, jour);
    final actuelle = existante == null ? 0 : _de(existante, origine);
    return _ecrire(lotId, jour, {origine: actuelle + quantite});
  }

  /// Écrit la ou les colonnes d'entrée données ; les autres gardent leur valeur.
  Future<LivestockDailyEntry> _ecrire(String lotId, DateTime jour, Map<String, int> valeurs) async {
    final existante = await _fiches.chargerJour(lotId, jour);
    int pris(String origine) => valeurs[origine] ?? (existante == null ? 0 : _de(existante, origine));
    return _fiches.ecrireEntrees(
      lotId: lotId,
      jour: jour,
      achat: pris('Achat'),
      ne: pris('Naissance'),
      don: pris('Don'),
    );
  }

  /// Refuse tout effectif négatif à partir de [depuis] (calcul SANS la borne à 0 de la formule). Dans la transaction du
  /// geste : le refus annule tout.
  Future<void> _refuserSiEffectifNegatif(String lotId, DateTime depuis) async {
    final bande = await (_db.select(_db.livestockLots)..where((t) => t.id.equals(lotId))).getSingle();
    var courant = await _fiches.effectifPrecedent(lotId, depuis);
    final fiches = await (_db.select(_db.livestockDailyEntries)
          ..where((t) => t.lotId.equals(lotId) & t.entryDate.isBiggerOrEqualValue(depuis))
          ..orderBy([(t) => OrderingTerm(expression: t.entryDate)]))
        .get();
    for (final f in fiches) {
      courant += f.achat + f.ne + f.transfertEntree - (f.mort + f.vente + f.don + f.transfertSortie);
      if (courant < 0) {
        final d = f.entryDate;
        throw SujetRefuse({
          'quantite':
              "Saisie refusée : l'effectif de la bande ${bande.code} deviendrait négatif le "
              '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ($courant).',
        });
      }
    }
  }
}
