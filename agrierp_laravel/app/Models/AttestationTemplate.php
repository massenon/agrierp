<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class AttestationTemplate extends Model
{
    use HasUuids;

    protected $fillable = [
        'type', 'body_text', 'format', 'show_watermark', 'show_header', 'show_signature', 'show_stamp',
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
            'stagiaire' => "Nous soussigné, Ferme École OLOUWACHEGOUN, attestons que [NOM] a suivi avec assiduité et succès une formation pratique dans la spécialité [SPECIALITE] du [DATE_DEBUT] au [DATE_FIN].",
        ];

        return static::firstOrCreate(['type' => $type], ['body_text' => $defaults[$type] ?? '']);
    }
}
