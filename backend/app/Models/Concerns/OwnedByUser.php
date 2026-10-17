<?php

namespace App\Models\Concerns;

use App\Models\Scopes\OwnedByUserScope;
use Illuminate\Database\Eloquent\Builder;

/**
 * Shared row-isolation for every user-owned item table.
 *
 * A global scope pins every query to the authenticated user, so controllers
 * never repeat "where user_id = ..." and a foreign uuid simply is not found
 * (404), which avoids leaking existence across accounts.
 */
trait OwnedByUser
{
    public static function bootOwnedByUser(): void
    {
        static::addGlobalScope(new OwnedByUserScope());
    }

    public function scopeForUser(Builder $query, int $userId): Builder
    {
        return $query->withoutGlobalScope(OwnedByUserScope::class)
            ->where($this->getTable().'.user_id', $userId);
    }

    /**
     * Find by client uuid inside the current user's rows, trashed included.
     * Returns null when the row belongs to someone else or does not exist.
     */
    public static function findByUuid(string $uuid, bool $withTrashed = false): ?static
    {
        $query = static::query();

        if ($withTrashed) {
            $query->withTrashed();
        }

        return $query->where('uuid', $uuid)->first();
    }
}
