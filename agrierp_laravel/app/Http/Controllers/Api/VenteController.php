<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Sale;
use App\Services\PdfExportService;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * Ticket AV2 — « Télécharger PDF » DU DÉTAIL D'UNE VENTE, DEPUIS UN POSTE.
 *
 * Même document que `Livewire\Ventes\HistoriqueVentes::exportSaleTicketPdf()` (le ticket de caisse d'une vente) : même
 * gabarit (`exports.sale-ticket`), même titre, même droit (`export-ventes`). Le PDF est produit ici : l'en-tête
 * officiel de la ferme n'a pas à être recopié sur chaque machine, et la génération reste une action du serveur
 * (comme la fiche d'un sujet, ticket 15.14). Exige donc le réseau, ce que l'écran du poste dit.
 */
class VenteController extends Controller
{
    public function pdf(Request $request, string $id, PdfExportService $pdfs): Response
    {
        abort_unless($request->user()->can('export-ventes'), 403, "Votre rôle ne permet pas d'exporter le ticket d'une vente.");

        $sale = Sale::with(['customer', 'lines.product'])->findOrFail($id);
        $reference = strtoupper(substr($sale->id, 0, 8));

        $pdf = $pdfs->render('exports.sale-ticket', ['sale' => $sale], 'Ticket de Vente', $reference);

        return response($pdf->output(), 200, [
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'attachment; filename="vente-'.$reference.'.pdf"',
        ]);
    }
}
