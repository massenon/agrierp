<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class AttestationTemplate extends Model
{
    use HasUuids;

    protected $fillable = [
        'type', 'body_text', 'format', 'show_watermark', 'show_header', 'show_signature', 'show_stamp',
        'numero_sequence',
        'sig1_titre', 'sig1_nom', 'sig2_titre', 'sig2_nom', 'sig3_titre', 'sig3_nom',
    ];

    protected function casts(): array
    {
        return [
            'show_watermark' => 'boolean',
            'show_header' => 'boolean',
            'show_signature' => 'boolean',
            'show_stamp' => 'boolean',
        ];
    }

    public static function forType(string $type): self
    {
        $defaults = [
            'employe' => "Nous soussigné, Ferme École OLOUWACHEGOUN, attestons que [NOM], est employé(e) au sein de notre structure en qualité de [POSTE] sous contrat [CONTRAT] du [DATE_DEBUT] au [DATE_FIN].",
            'stagiaire' => "Je soussigné OLOUKOUNLE O. Hassimiyou, Directeur Général de la FERME ECOLE OLOUWACHEGOUN, atteste que le nommé(e) [NOM], né(e) le [DATE_NAISSANCE] à [LIEU_NAISSANCE], a suivi une formation pratique sur ladite ferme, du [DATE_DEBUT] au [DATE_FIN] dans les domaines ci-après :",
        ];

        return static::firstOrCreate(['type' => $type], ['body_text' => $defaults[$type] ?? '']);
    }
}
