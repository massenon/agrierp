<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class VeterinaryCalendarEvent extends Model
{
    use HasUuids;

    protected $fillable = ['lot_id', 'task_type', 'scheduled_date', 'status'];

    protected function casts(): array
    {
        return ['scheduled_date' => 'date'];
    }

    public function lot()
    {
        return $this->belongsTo(LivestockLot::class, 'lot_id');
    }

    /**
     * Statut d'affichage réel : un événement "planned" dont la date est
     * dépassée s'affiche "late" sans que la valeur stockée soit modifiée
     * silencieusement (l'action "Confirmer Administration" reste le seul
     * moyen de passer à "done").
     */
    public function getDisplayStatusAttribute(): string
    {
        if ($this->status === 'planned' && $this->scheduled_date->isPast()) {
            return 'late';
        }

        return $this->status;
    }
}
