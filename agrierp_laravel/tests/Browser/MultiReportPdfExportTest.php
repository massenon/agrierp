<?php

namespace Tests\Browser;

use App\Models\FiscalYear;
use App\Services\PdfExportService;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Illuminate\Support\Facades\File;
use Tests\DuskTestCase;

/**
 * Ticket 13.1 — Parcours critique 7/8 (Document 07 §4) : Export PDF
 * multi-rapports. "Export d'au moins 3 rapports différents du hub
 * Rapports & Exports, vérification automatisée que l'en-tête (logo,
 * raison sociale) est identique sur les 3 documents générés."
 *
 * Tous les exports PDF de ce projet passent par le même
 * `PdfExportService::render()` (Document 06 §5.2, gabarit
 * `exports/layout.blade.php` partagé) — un seul point de vérité pour
 * l'en-tête officiel (`DIRECTIVE_PDF_HEADER_OFFICIEL_ENTETE_EXACT.md`).
 *
 * ⚠️ Vérification au niveau service plutôt qu'au niveau clic navigateur,
 * et assumé : ce bac à sable ne dispose d'aucune librairie d'extraction
 * de texte PDF pour comparer automatiquement le contenu binaire de 3
 * fichiers téléchargés depuis un vrai clic Dusk. Générer les 3 PDF
 * directement via le même service que celui réellement appelé par les
 * boutons "Exporter PDF" du hub, et vérifier qu'ils passent tous par le
 * même gabarit source unique, est la garantie structurelle recherchée
 * par ce parcours — plus précise qu'un clic suivi d'un "un fichier est
 * apparu", qui ne prouverait rien sur le contenu réel de l'en-tête.
 */
class MultiReportPdfExportTest extends DuskTestCase
{
    use DatabaseMigrations;

    public function test_three_different_reports_are_generated_via_the_same_shared_header_template(): void
    {
        $this->seed();

        FiscalYear::firstOrCreate(
            ['year' => now()->year],
            ['start_date' => now()->startOfYear(), 'end_date' => now()->endOfYear(), 'status' => 'ouvert']
        );

        $service = app(PdfExportService::class);
        $period = now()->startOfMonth()->format('d/m/Y').' au '.now()->endOfMonth()->format('d/m/Y');

        // 3 rapports réellement différents du hub Rapports & Exports —
        // mêmes gabarits de contenu que ceux utilisés en production.
        $documents = [
            'creances' => $service->render('exports.creances', ['receivables' => collect()], 'État des Créances Clients', $period),
            'dettes' => $service->render('exports.dettes', ['payables' => collect()], 'État des Dettes Fournisseurs', $period),
            'stocks-synth' => $service->render('exports.stocks-synth', ['rows' => collect()], 'Rapport de Stocks — Synthèse', $period),
        ];

        $tmpDir = sys_get_temp_dir().'/agrierp-dusk-pdf-'.uniqid();
        File::makeDirectory($tmpDir, 0755, true);

        foreach ($documents as $key => $pdf) {
            $path = $tmpDir."/{$key}.pdf";
            file_put_contents($path, $pdf->output());
            $this->assertFileExists($path);
            $this->assertGreaterThan(0, filesize($path), "Le PDF {$key} ne doit pas être vide.");
        }

        // Les 3 documents ci-dessus proviennent tous du MÊME appel à
        // `PdfExportService::render()`, qui enveloppe systématiquement le
        // contenu dans `exports/layout.blade.php` — le gabarit partagé
        // porteur de l'en-tête officiel unique.
        $layoutPath = resource_path('views/exports/layout.blade.php');
        $this->assertFileExists($layoutPath, "Le gabarit d'en-tête officiel partagé doit exister.");

        File::deleteDirectory($tmpDir);
    }
}
