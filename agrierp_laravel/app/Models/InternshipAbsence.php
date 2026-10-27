<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class InternshipAbsence extends Model
{
    use HasUuids;

    // ⚠️ TICKET 14.55 — voir `FeedRationStandard` : sans `is_active` ici,
    // l'archivage serait ignoré en silence.
    protected $fillable = ['internship_id', 'absence_date', 'reason', 'is_active'];

    protected function casts(): array
    {
        return ['absence_date' => 'date', 'is_active' => 'boolean'];
    }

    public function internship()
    {
        return $this->belongsTo(Internship::class, 'internship_id');
    }
}
