<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ItemShare extends Model
{
    protected $fillable = [
        'item_type',
        'item_id',
        'owner_user_id',
        'shared_with_user_id',
        'permission',
        'revoked_at',
    ];

    protected function casts(): array
    {
        return ['revoked_at' => 'datetime'];
    }

    public function sharedWith(): \Illuminate\Database\Eloquent\Relations\BelongsTo
    {
        return $this->belongsTo(User::class, 'shared_with_user_id');
    }
}
