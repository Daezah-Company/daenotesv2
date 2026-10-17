<?php

namespace App\Models;

use App\Models\Concerns\OwnedByUser;
use Database\Factories\NoteFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Note extends Model
{
    /** @use HasFactory<NoteFactory> */
    use HasFactory, OwnedByUser, SoftDeletes;

    const CREATED_AT = null;

    protected $fillable = [
        'user_id',
        'uuid',
        'title',
        'body',
        'color',
        'pinned',
        'archived_at',
        'synced_at',
    ];

    protected function casts(): array
    {
        return [
            'pinned' => 'boolean',
            'archived_at' => 'datetime',
            'deleted_at' => 'datetime',
            'synced_at' => 'datetime',
            'updated_at' => 'datetime',
        ];
    }

    public function user(): \Illuminate\Database\Eloquent\Relations\BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
