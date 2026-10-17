<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Animal;
use App\Services\AnimalFicheService;
use App\Services\PdfExportService;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * Ticket 15.14 — EXPORT PDF DE LA FICHE D'UN SUJET, DEPUIS UN POSTE.
 *
 * Même document que `AnimalDetails::exportFicheAnimalPdf` : mêmes données
 * (`AnimalFicheService`), même gabarit (`exports.animal-details`), mêmes droits
 * (`view-elevage`). Le PDF est produit ici : l'en-tête officiel de la ferme n'a pas
 * à être recopié sur chaque machine.
 */
class AnimalController extends Controller
{
    public function pdf(Request $request, string $id, AnimalFicheService $fiche, PdfExportService $pdfs): Response
    {
        abort_unless($request->user()->can('view-elevage'), 403, "Votre rôle ne permet pas d'exporter une fiche sujet.");

        $animal = Animal::findOrFail($id);

        $pdf = $pdfs->render(
            'exports.animal-details',
            $fiche->donneesPdf($animal),
            'Fiche Sujet — '.$animal->identifier,
            'État au '.now()->format('d/m/Y'),
        );

        return response($pdf->output(), 200, [
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'attachment; filename="sujet-'.$animal->identifier.'.pdf"',
        ]);
    }
}
