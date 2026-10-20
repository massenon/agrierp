<?php

namespace App\Services;

use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Ticket S-T6 — CONTRÔLE DE COHÉRENCE POSTE ↔ SERVEUR (méthode TATACORA : nombre et total par table et par jour).
 *
 * `GET /api/sync/coherence?depuis=AAAA-MM-JJ` rend, pour chaque table de [AGREGATS] et pour chaque jour depuis
 * `depuis`, le NOMBRE de lignes et le TOTAL du montant pertinent. Le poste fait le même calcul sur sa base locale et
 * compare (écran Synchronisation, « Contrôle de cohérence ») : un écart dit qu'une ligne s'est perdue dans un sens ou
 * dans l'autre, ou qu'un montant a divergé, sans attendre qu'un rapport tombe faux.
 *
 * ⚠️⚠️ [AGREGATS] EST LA TABLE DE CORRESPONDANCE UNIQUE, ET LE POSTE LA LIT. `agrierp_flutter/lib/core/sync/
 * agregats_coherence.dart` porte la même ; `test/coherence_synchronisation_test.dart` lit CE fichier et exige l'égalité
 * entrée par entrée. Une ligne par table, sous cette forme exacte : le test la lit au texte.
 *
 *  - `jour` : colonne(s) qui datent la ligne, la première non nulle (`sold_at ?? created_at` des ventes, la date
 *    effective du web). Au poste, `sales.sold_at` porte déjà la date effective : le tirage la sert sous ce nom.
 *  - `montant` : colonne sommée ; `filtre` : condition `[colonne, opérateur, valeur]` ou `null`.
 *
 * ⚠️ SEULES LES TABLES DONT LE POSTE TIENT UN MIROIR COMPLET y figurent : envoyées ET tirées en entier (ventes, achats,
 * fiches, soins, avances, transferts, dépenses), ou tirées en lecture seule (le grand livre des stocks, qui porte les
 * ajustements d'inventaire rejoués des postes). Pour elles, poste et serveur doivent avoir les mêmes lignes.
 * Ticket U13 — **les dépenses y entrent** : elles descendent désormais au poste (web et autres postes, archivage
 * compris) ; seules les ACTIVES sont comptées (une dépense archivée n'est plus une dépense).
 */
class CoherenceSynchronisationService
{
    /**
     * @var array<string, array{libelle: string, jour: array<int, string>, montant: string, filtre: ?array{0: string, 1: string, 2: string|int}}>
     */
    public const AGREGATS = [
        'sales' => ['libelle' => 'Ventes', 'jour' => ['sold_at', 'created_at'], 'montant' => 'total', 'filtre' => ['status', '<>', 'annulee']],
        'purchases' => ['libelle' => 'Achats', 'jour' => ['purchase_date'], 'montant' => 'total', 'filtre' => null],
        'livestock_daily_entries' => ['libelle' => 'Fiches journalières (morts)', 'jour' => ['entry_date'], 'montant' => 'mort', 'filtre' => null],
        'veterinary_records' => ['libelle' => 'Soins (coût)', 'jour' => ['record_date'], 'montant' => 'cost', 'filtre' => ['is_active', '=', 1]],
        'customer_advances' => ['libelle' => 'Avances clients', 'jour' => ['advance_date'], 'montant' => 'amount', 'filtre' => ['is_active', '=', 1]],
        'livestock_transfers' => ['libelle' => 'Transferts entre bandes (sujets)', 'jour' => ['transfer_date'], 'montant' => 'quantity', 'filtre' => ['is_active', '=', 1]],
        'stock_movements' => ['libelle' => 'Mouvements de stock, ajustements compris (quantités)', 'jour' => ['movement_date'], 'montant' => 'quantity', 'filtre' => null],
        'expenses' => ['libelle' => 'Dépenses', 'jour' => ['expense_date'], 'montant' => 'amount', 'filtre' => ['is_active', '=', 1]],
    ];

    /** Fenêtre maximale d'un contrôle : au-delà, la réponse grossit sans servir (un contrôle regarde le récent). */
    public const JOURS_MAXIMUM = 366;

    /**
     * @return array<string, array{libelle: string, jours: array<string, array{nombre: int, total: float}>}>
     */
    public function calculer(Carbon $depuis): array
    {
        $resultat = [];

        foreach (self::AGREGATS as $table => $definition) {
            $jour = count($definition['jour']) > 1
                ? 'COALESCE('.implode(', ', $definition['jour']).')'
                : $definition['jour'][0];

            $requete = DB::table($table)
                ->selectRaw("{$jour} AS jour, {$definition['montant']} AS montant")
                // ⚠️ Borne en 'AAAA-MM-JJ', jamais en 'AAAA-MM-JJ 00:00:00' : sur SQLite une colonne `date` est un
                // texte, et '2026-10-01' < '2026-10-01 00:00:00' en ordre lexical — le premier jour serait perdu.
                ->whereRaw("{$jour} >= ?", [$depuis->toDateString()]);

            if ($definition['filtre'] !== null) {
                [$colonne, $operateur, $valeur] = $definition['filtre'];
                $requete->where($colonne, $operateur, $valeur);
            }

            $jours = [];
            foreach ($requete->cursor() as $ligne) {
                if ($ligne->jour === null) {
                    continue;
                }
                // Le jour est lu dans la valeur stockée (heure murale du serveur, `APP_TIMEZONE`), jamais converti :
                // c'est le jour que les écrans du web affichent.
                $cle = substr((string) $ligne->jour, 0, 10);
                $jours[$cle] ??= ['nombre' => 0, 'total' => 0.0];
                $jours[$cle]['nombre']++;
                $jours[$cle]['total'] += (float) ($ligne->montant ?? 0);
            }

            ksort($jours);
            foreach ($jours as $cle => $valeurs) {
                $jours[$cle]['total'] = round($valeurs['total'], 2);
            }

            $resultat[$table] = ['libelle' => $definition['libelle'], 'jours' => $jours];
        }

        return $resultat;
    }
}
