<?php

namespace App\Services;

use App\Models\ChartOfAccount;
use App\Models\Expense;
use App\Models\ExpenseLine;
use App\Models\TreasuryAccount;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Ticket DEP1 — transforme chaque ancienne dépense (libellé + catégorie texte + montant) en 1 en-tête + 1 ligne.
 *
 * ⚠️ NE TOUCHE JAMAIS À LA COMPTABILITÉ : ni écriture créée, ni écriture modifiée, ni `accounting_entry_id`. Une pièce
 * déjà passée reste exactement ce qu'elle est (EF11). L'en-tête garde son montant (le total) et son libellé (le résumé).
 *
 * Correspondance catégorie → compte : celle de la comptabilisation d'origine (`RecordExpenseAccountingEntryAction`) —
 * le code SYSCOHADA en tête de la catégorie (« 605 - Énergie » → 605), compte de classe 6. Aucune correspondance : le
 * compte « charges diverses » du plan, 628 « Autres charges », et une ligne de journal (`Log::warning`).
 */
class ConversionDepensesEnLignes
{
    /** Compte « charges diverses » du plan (dernière catégorie de l'ancienne liste). */
    public const COMPTE_DIVERS = '628';

    /** « 605 - Énergie » → le compte de classe 6 de code 605 ; `null` si la catégorie est illisible ou le compte absent. */
    public static function compteDeLaCategorie(?string $categorie): ?ChartOfAccount
    {
        if (! $categorie || ! preg_match('/^\s*(\d{2,4})/', $categorie, $trouve)) {
            return null;
        }

        return ChartOfAccount::where('code', $trouve[1])->where('class', 6)->first();
    }

    /**
     * @return array{converties: int, divers: int, ignorees: int}
     */
    public static function convertir(): array
    {
        $bilan = ['converties' => 0, 'divers' => 0, 'ignorees' => 0];

        Expense::query()->whereDoesntHave('lines')->orderBy('id')->chunkById(200, function ($depenses) use (&$bilan) {
            foreach ($depenses as $depense) {
                $compte = self::compteDeLaCategorie($depense->category);
                $divers = false;

                if ($compte === null) {
                    $compte = ChartOfAccount::where('code', self::COMPTE_DIVERS)->where('class', 6)->first();
                    $divers = true;
                }

                if ($compte === null) {
                    // Plan comptable sans 628 : rien ne peut être déduit, la dépense reste lisible SANS ligne (l'en-tête
                    // porte toujours son montant) et le défaut est dit — jamais une dépense perdue ni un compte inventé.
                    Log::warning('Conversion des dépenses : aucune ligne créée, ni le compte de la catégorie ni le compte '.self::COMPTE_DIVERS.' n\'existent.', [
                        'expense_id' => $depense->id, 'category' => $depense->category,
                    ]);
                    $bilan['ignorees']++;

                    continue;
                }

                if ($divers) {
                    Log::warning('Conversion des dépenses : aucune correspondance pour la catégorie, compte '.self::COMPTE_DIVERS.' retenu.', [
                        'expense_id' => $depense->id, 'category' => $depense->category,
                    ]);
                    $bilan['divers']++;
                }

                DB::transaction(function () use ($depense, $compte) {
                    $ligne = new ExpenseLine();
                    $ligne->id = ExpenseLine::idDeConversion($depense->id);
                    $ligne->fill([
                        'expense_id' => $depense->id,
                        'position' => 0,
                        'label' => $depense->label,
                        'charge_account_id' => $compte->id,
                        'amount' => $depense->amount,
                    ]);
                    $ligne->save();

                    // Le mode de paiement se déduit du type du compte de trésorerie (le web n'en avait pas d'autre).
                    // `updateQuietly` : ni `updated_at` ni évènement ne bougent (la ligne arrive au poste par son propre
                    // tirage ; le curseur de tirage sera relevé par la requête ci-dessous).
                    $type = TreasuryAccount::whereKey($depense->treasury_account_id)->value('type');
                    if ($type !== null && $depense->payment_mode === null) {
                        DB::table('expenses')->where('id', $depense->id)->update(['payment_mode' => $type]);
                    }
                });

                $bilan['converties']++;
            }
        });

        // Les postes tirent par `updated_at` : toutes les dépenses converties redescendent AVEC leurs lignes.
        if ($bilan['converties'] > 0) {
            DB::table('expenses')->whereIn('id', DB::table('expense_lines')->select('expense_id'))->update(['updated_at' => now()]);
        }

        return $bilan;
    }
}
