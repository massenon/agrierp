<?php

namespace App\Actions;

use App\Models\LivestockLot;
use App\Models\VeterinaryRecord;
use App\Services\ProtocoleDuJourService;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Ticket 15.35 — VALIDER LES TRAITEMENTS DU PROTOCOLE DU JOUR (fiches Lapins, Porcs).
 *
 * ⚠️⚠️ CE N'EST PAS UNE CASE À COCHER DÉCORATIVE. Chaque traitement validé écrit
 * un soin au registre vétérinaire ET, s'il porte un délai d'attente, la période
 * de rémanence qui bloque la vente de la bande — par le point de passage unique
 * `RecordVeterinaryCareAction`, jamais recopié ici. La rémanence naît AU CLIC de
 * validation : afficher le protocole n'écrit rien (un traitement prévu n'est pas
 * un traitement administré).
 *
 * ⚠️ IDEMPOTENT : valider deux fois = un seul soin. Le rapprochement se fait sur
 * le protocole RECALCULÉ à l'instant de l'écriture (jamais sur ce que l'écran
 * croyait), sous verrou de la bande : deux onglets ou un double clic ne peuvent
 * pas créer deux soins — ni deux périodes de rémanence — pour le même traitement.
 *
 * ⚠️ SEULS LES TRAITEMENTS DU BARÈME SE VALIDENT : un identifiant forgé ou inconnu
 * est ignoré. Depuis le ticket #45, une bande indéterminée (reproduction sans
 * saillie) expose aussi ses traitements — le cycle est inconnu mais l'administration
 * reste possible ; les identifiants doivent tout de même exister dans le barème.
 */
class ValidateProphylaxisTreatmentsAction
{
    public function __construct(
        private readonly ProtocoleDuJourService $protocole,
        private readonly RecordVeterinaryCareAction $soin,
    ) {}

    /**
     * @param  array<int, string>  $idsBareme  identifiants `prophylaxis_schedule_standards` cochés
     * @return Collection<int, VeterinaryRecord> les soins réellement créés (vide si rien à écrire)
     */
    public function execute(LivestockLot $bande, CarbonInterface $jour, array $idsBareme, ?string $observations = null): Collection
    {
        return DB::transaction(function () use ($bande, $jour, $idsBareme, $observations) {
            // Verrou de la bande : sérialise deux validations concurrentes (MySQL ;
            // sans effet sous SQLite de test, où les écritures sont déjà séquentielles).
            LivestockLot::whereKey($bande->id)->lockForUpdate()->first();

            $etat = $this->protocole->pourBande($bande->load('species'), $jour);

            $crees = collect();

            foreach ($etat->traitements as $ligne) {
                $standard = $ligne['standard'];

                if ($ligne['deja_administre'] || ! in_array($standard->id, $idsBareme, true)) {
                    continue;
                }

                $crees->push($this->soin->execute([
                    'lot_id' => $bande->id,
                    'action_type' => $standard->treatment,
                    'product_used' => $standard->product_recommended,
                    'dose' => $standard->dosage,
                    'symptomes' => $observations !== null && trim($observations) !== '' ? trim($observations) : null,
                    'record_date' => $jour->toDateString(),
                ], (int) $standard->withdrawal_days));
            }

            return $crees;
        });
    }
}
