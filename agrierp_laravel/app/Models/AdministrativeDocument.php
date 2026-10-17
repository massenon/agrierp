<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class AdministrativeDocument extends Model
{
    use HasUuids;

    protected $fillable = ['title', 'type', 'beneficiary', 'doc_date', 'status', 'is_active'];

    protected function casts(): array
    {
        return [
            'doc_date' => 'date',
            'is_active' => 'boolean',
        ];
    }
}
