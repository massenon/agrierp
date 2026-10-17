<?php

namespace App\Livewire\Elevage;

use App\Models\Animal;
use App\Services\AnimalFicheService;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;
use SimpleSoftwareIO\QrCode\Facades\QrCode;

/**
 * Ticket 14.16 (Sprint 14) — animal-details.html → Livewire\Elevage\AnimalDetails
 * « Fiche complète d'un sujet suivi individuellement. »
 *
 * Écran signalé NON CONSTRUCTIBLE au ticket 14.10 : il suppose une entité
 * « sujet » que le schéma n'avait pas, tout l'Élevage étant suivi par bande.
 * Construit ici après arbitrage explicite du client — **suivi individuel
 * limité aux reproducteurs**, les bandes d'engraissement restant suivies en
 * quantités.
 *
 * ⚠️ LES 8 ONGLETS DU PROTOTYPE NE SONT PAS TOUS ALIMENTABLES, ET C'EST DIT
 * PLUTÔT QUE MASQUÉ. Le prototype est une maquette dont toutes les valeurs
 * sont écrites en dur ; certaines de ses sections n'ont aucune source réelle
 * dans ce projet. Chaque onglet est donc dans l'un de deux états, jamais un
 * troisième « faux contenu » :
 *
 *   RÉELS — Général (identification, QR), Reproduction (événements retrouvés
 *   par `mother_ref`/`sire_ref`), Vaccins & Soins (prophylaxie de la bande,
 *   présentée explicitement comme telle), Mouvements (entrée, changements de
 *   statut réellement enregistrés).
 *
 *   EN ATTENTE, avec motif affiché — Alimentation (le rationnement est calculé
 *   PAR BANDE et par catégorie, jamais par sujet : afficher une ration
 *   individuelle serait une division arbitraire), Production (la ponte est
 *   relevée par bande dans la fiche journalière ; aucune source par poule
 *   n'existe), Documents (aucune table de pièces jointes par sujet).
 *
 * Même discipline que `DashboardElevage` (ticket 3.13) et `FicheLapins`
 * (ticket 3.5), qui affichent déjà des bandeaux d'attente motivés plutôt que
 * des sections décoratives.
 */
#[Layout('layouts.app')]
class AnimalDetails extends Component
{
    public Animal $animal;

    #[Url]
    public string $tab = 'general';

    public function mount(Animal $animal): void
    {
        $this->animal = $animal;
    }

    public function switchTab(string $tab): void
    {
        $onglets = ['general', 'historique', 'alimentation', 'vaccins', 'reproduction', 'production', 'mouvements', 'documents'];

        $this->tab = in_array($tab, $onglets, true) ? $tab : 'general';
    }

    /**
     * QR code réel du sujet — même mécanisme que la facturation MeCeF
     * (ticket 7.1), jamais une image de remplacement. Encode l'identifiant
     * lisible, celui-là même qui figure sur la boucle du sujet.
     */
    public function getQrCodeProperty(): string
    {
        return (string) QrCode::size(220)->generate($this->animal->identifier);
    }

    // ⚠️ TICKET 15.14 — LA FICHE EST COMPOSÉE PAR `AnimalFicheService`, partagé
    // avec l'export PDF du poste : une seule histoire du sujet.
    public function getReproductionEventsProperty()
    {
        return app(AnimalFicheService::class)->reproduction($this->animal);
    }

    public function getVeterinaryRecordsProperty()
    {
        return app(AnimalFicheService::class)->soins($this->animal);
    }

    public function getMovementsProperty(): array
    {
        return app(AnimalFicheService::class)->mouvements($this->animal);
    }

    public function getHistoryProperty(): array
    {
        return app(AnimalFicheService::class)->historique($this->animal);
    }

    public function exportFicheAnimalPdf()
    {
        $this->authorize('view-elevage');

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.animal-details',
            app(AnimalFicheService::class)->donneesPdf($this->animal),
            'Fiche Sujet — '.$this->animal->identifier,
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(
            fn () => print ($pdf->output()),
            'sujet-'.$this->animal->identifier.'.pdf'
        );
    }

    public function render()
    {
        return view('livewire.elevage.animal-details', ['title' => 'Élevage > Fiche Sujet']);
    }
}
