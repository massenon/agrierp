<?php

namespace App\Services;

use Barryvdh\DomPDF\Facade\Pdf;
use Barryvdh\DomPDF\PDF as PdfDocument;

/**
 * Point d'entrée UNIQUE pour tout export PDF (rapports tabulaires ET
 * documents officiels comme les bons de commande, Document 06 §5.2) —
 * jamais un service ou une vue d'en-tête dupliquée par export
 * (AVOID_INSTRUCTIONS.md § Difficult Debugging : un seul point de vérité
 * par donnée/mécanisme partagé). Premier usage réel : ticket 5.5
 * (`BonsCommande`) — orientation portrait par défaut à Sprint 0
 * (paysage), désormais paramétrable (`$orientation`) sans changer le
 * comportement des appels existants.
 *
 * Valeurs d'en-tête exactes vérifiées par extraction directe du document
 * officiel — DIRECTIVE_PDF_HEADER_OFFICIEL_ENTETE_EXACT.md fait foi en cas
 * de divergence avec toute autre description (Document 04 §4.9, Document 06
 * §5.2 restent des descriptions génériques dépassées par cette directive).
 *
 * `resources/views/exports/layout.blade.php` porte l'en-tête institutionnel
 * fixe ; chaque vue de rapport injecte uniquement son contenu via
 * `@yield('content')` ou la section 'content' — jamais de re-déclaration
 * de l'en-tête dans une vue de rapport individuelle.
 */
class PdfExportService
{
    public function render(string $view, array $data, string $title, string $period, string $orientation = 'landscape'): PdfDocument
    {
        return Pdf::loadView('exports.layout', array_merge($data, [
            'reportView' => $view,
            'reportTitle' => $title,
            'period' => $period,
            'author' => auth()->user()?->name ?? 'Système',
            'companyLogo' => public_path('assets/images/logo.png'),
            'companyName' => 'LA FERME ÉCOLE OLOUWACHEGOUN',
            'companyActivities' => "Production Animale | Production Végétale | Transformation Alimentaire | "
                ."Fabrication de Cages Galvanisées | Formation Agricole | Suivi-Appui et Conseil Agricoles",
            'companyAddress' => "Attan-Ewé, Arrondissement d'Ikpinlè, Commune d'Adja-Ouèrè, Bénin",
            'companyPhone' => '+229 01 97 84 02 85/97 84 02 85',
            'companyRccm' => 'RB/PNO/22 A 33870',
            'companyEmail' => 'olomagloire1@gmail.com / contact@fermeolouwachegoun.com',
            'companyWebsite' => 'www.fermeolouwachegoun.com',
        ]))->setPaper('a4', $orientation);
    }
}
