<?php

namespace App\Models;

use App\Models\Concerns\OwnedByUser;
use App\Support\ItemResolver;
use Database\Factories\ReminderFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * A scheduled ping attached to an item by uuid, never by internal id.
 */
class Reminder extends Model
{
    /** @use HasFactory<ReminderFactory> */
    use HasFactory, OwnedByUser, SoftDeletes;

    const CREATED_AT = null;

    protected $fillable = [
        'user_id',
        'uuid',
        'item_type',
        'item_uuid',
        'title',
        'scheduled_at',
        'fired_at',
        'synced_at',
    ];

    protected function casts(): array
    {
        return [
            'scheduled_at' => 'datetime',
            'fired_at' => 'datetime',
            'deleted_at' => 'datetime',
            'synced_at' => 'datetime',
            'updated_at' => 'datetime',
        ];
    }

    public function item(): ?Model
    {
        return ItemResolver::find($this->item_type, $this->item_uuid);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
