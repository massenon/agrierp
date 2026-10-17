<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class CustomerReminder extends Model
{
    use HasUuids;

    protected $fillable = ['customer_id', 'receivable_id', 'channel', 'reminder_date', 'message'];

    protected function casts(): array
    {
        return ['reminder_date' => 'date'];
    }

    public function customer()
    {
        return $this->belongsTo(Customer::class, 'customer_id');
    }

    public function receivable()
    {
        return $this->belongsTo(Receivable::class, 'receivable_id');
    }
}
