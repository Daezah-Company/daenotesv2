<?php

namespace App\Models;

use App\Models\Concerns\OwnedByUser;
use Database\Factories\TodoFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Todo extends Model
{
    /** @use HasFactory<TodoFactory> */
    use HasFactory, OwnedByUser, SoftDeletes;

    const CREATED_AT = null;

    protected $fillable = [
        'user_id',
        'uuid',
        'title',
        'group_name',
        'notes',
        'done',
        'done_at',
        'priority',
        'due_at',
        'remind_at',
        'archived_at',
        'synced_at',
    ];

    protected function casts(): array
    {
        return [
            'done' => 'boolean',
            'done_at' => 'datetime',
            'due_at' => 'datetime',
            'remind_at' => 'datetime',
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
