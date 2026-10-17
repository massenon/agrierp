<?php

namespace App\Console\Commands;

use App\Models\Purchase;
use Illuminate\Console\Command;

/**
 * Ticket 15.21 — DÉTECTION (lecture seule) des achats sans écriture comptable.
 *
 * Avant ce ticket, la réception d'un bon de commande créait l'achat, le stock et une dette (401) sans passer
 * d'écriture ; les achats d'avant le ticket 14.24 sont dans le même cas. Ce rapport les liste. Il NE RÉGULARISE
 * RIEN : passer une écriture de reprise (à quelle date ? dans quel exercice, peut-être clos ?) est une décision du
 * cabinet FAGUEZ et du client, jamais un effet de bord d'un correctif. Conséquence connue : un tel achat ne peut pas
 * être retourné (ticket 15.20 : « n'a pas d'écriture comptable »).
 *
 * Code de sortie : 0 s'il n'y en a aucun, 1 sinon (utilisable dans une vérification planifiée).
 */
class AchatsSansEcriture extends Command
{
    protected $signature = 'comptabilite:achats-sans-ecriture';

    protected $description = 'Liste les achats sans écriture comptable (lecture seule, ne régularise rien)';

    public function handle(): int
    {
        $achats = Purchase::query()
            ->whereNull('accounting_entry_id')
            ->orderBy('purchase_date')
            ->orderBy('created_at')
            ->get();   // toutes les colonnes : la commande doit tourner même sur une base pas encore migrée (returned_at, 15.20)

        if ($achats->isEmpty()) {
            $this->info('Aucun achat sans écriture comptable.');

            return self::SUCCESS;
        }

        foreach ($achats as $a) {
            $this->line(sprintf(
                '%s  %s  %s FCFA%s%s',
                $a->id,
                $a->purchase_date?->format('Y-m-d'),
                number_format((float) $a->total, 2, '.', ''),
                $a->purchase_order_id ? '  [réception de bon de commande]' : '',
                $a->returned_at ? '  [déjà retourné]' : '',
            ));
        }

        $this->newLine();
        $this->warn($achats->count().' achat(s) sans écriture comptable, pour '.number_format((float) $achats->sum('total'), 2, '.', '').' FCFA. Aucun achat n\'a été modifié.');
        $this->line('Les régulariser est une décision du cabinet et du client : voir le ticket 15.21.');

        return self::FAILURE;
    }
}
