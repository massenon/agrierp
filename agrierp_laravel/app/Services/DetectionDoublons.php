<?php

namespace App\Services;

use App\Support\CleUnicite;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket UNI — DÉTECTION (lecture seule) des codes de bande et des libellés de catégorie en double.
 *
 * Ne modifie, ne renomme et ne supprime RIEN : le client renomme lui-même. La clé de comparaison est celle de la
 * règle de saisie (`CleUnicite` : casse, accents et espaces ignorés).
 */
class DetectionDoublons
{
    /**
     * @return list<array{cle: string, lignes: list<array{id: string, valeur: string, actif: bool, liees: array<string, int>}>}>
     */
    public function bandes(): array
    {
        $lignes = DB::table('livestock_lots')->orderBy('created_date')->orderBy('id')->get(['id', 'code', 'is_active']);

        return $this->grouper($lignes->map(fn ($l) => [
            'id' => (string) $l->id, 'valeur' => (string) $l->code, 'actif' => (bool) $l->is_active,
            'liees' => $this->liéesDeLaBande((string) $l->id),
        ])->all());
    }

    /**
     * @return list<array{cle: string, lignes: list<array{id: string, valeur: string, actif: bool, liees: array<string, int>}>}>
     */
    public function categories(): array
    {
        $lignes = DB::table('product_categories')->orderBy('created_at')->orderBy('id')->get(['id', 'label', 'is_active']);

        return $this->grouper($lignes->map(fn ($l) => [
            'id' => (string) $l->id, 'valeur' => (string) $l->label, 'actif' => (bool) $l->is_active,
            'liees' => ['produit(s)' => DB::table('products')->where('category_id', $l->id)->count()],
        ])->all());
    }

    /** Nombre de codes de bande partagés par plusieurs bandes (bandeau de l'écran « Bandes & Sujets »). */
    public function nombreDeCodesDeBandeEnDouble(): int
    {
        return collect(DB::table('livestock_lots')->pluck('code'))
            ->map(fn ($code) => CleUnicite::cle((string) $code))
            ->filter(fn ($cle) => $cle !== '')
            ->countBy()
            ->filter(fn ($n) => $n > 1)
            ->count();
    }

    /** Nombre de groupes en double (bandes + catégories). */
    public function total(): int
    {
        return count($this->bandes()) + count($this->categories());
    }

    /** @return array<string, int> lignes qui s'appuient sur la bande, par nature */
    private function liéesDeLaBande(string $id): array
    {
        $compte = fn (string $table, string ...$colonnes) => Schema::hasTable($table)
            ? DB::table($table)->where(function ($q) use ($colonnes, $id) {
                foreach ($colonnes as $c) {
                    $q->orWhere($c, $id);
                }
            })->count()
            : 0;

        return [
            'fiche(s)' => $compte('livestock_daily_entries', 'lot_id'),
            'ligne(s) de vente' => $compte('sale_lines', 'lot_id'),
            'transfert(s)' => $compte('livestock_transfers', 'source_lot_id', 'target_lot_id'),
            'sujet(s) nominatif(s)' => $compte('animals', 'lot_id'),
        ];
    }

    /**
     * @param  list<array{id: string, valeur: string, actif: bool, liees: array<string, int>}>  $lignes
     * @return list<array{cle: string, lignes: list<array{id: string, valeur: string, actif: bool, liees: array<string, int>}>}>
     */
    private function grouper(array $lignes): array
    {
        $groupes = [];
        foreach ($lignes as $ligne) {
            $cle = CleUnicite::cle($ligne['valeur']);
            if ($cle !== '') {
                $groupes[$cle][] = $ligne;
            }
        }
        ksort($groupes);

        $doublons = [];
        foreach ($groupes as $cle => $membres) {
            if (count($membres) > 1) {
                $doublons[] = ['cle' => (string) $cle, 'lignes' => $membres];
            }
        }

        return $doublons;
    }
}
