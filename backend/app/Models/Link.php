<?php

namespace App\Models;

use App\Models\Concerns\OwnedByUser;
use App\Support\ItemResolver;
use Database\Factories\LinkFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * An edge between two items, both sides identified by client uuid.
 *
 * The bigint ids of notes/todos are deliberately never stored here: an
 * offline-first client links items it created locally, so only uuids exist at
 * that moment.
 */
class Link extends Model
{
    /** @use HasFactory<LinkFactory> */
    use HasFactory, OwnedByUser, SoftDeletes;

    protected $fillable = [
        'user_id',
        'uuid',
        'source_type',
        'source_uuid',
        'target_type',
        'target_uuid',
        'label',
        'synced_at',
    ];

    protected function casts(): array
    {
        return [
            'deleted_at' => 'datetime',
            'synced_at' => 'datetime',
            'created_at' => 'datetime',
            'updated_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function source(): ?Model
    {
        return ItemResolver::find($this->source_type, $this->source_uuid);
    }

    public function target(): ?Model
    {
        return ItemResolver::find($this->target_type, $this->target_uuid);
    }

    /** The pair this edge connects, in the shape the unique index enforces. */
    public function pairAttributes(): array
    {
        return [
            'source_type' => $this->source_type,
            'source_uuid' => $this->source_uuid,
            'target_type' => $this->target_type,
            'target_uuid' => $this->target_uuid,
        ];
    }
}
